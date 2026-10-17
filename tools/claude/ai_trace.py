"""Trace the Smogon AI's switching decisions in headless battles.

usage:
  ai_trace.py run ROM SYM SAVE TRAINER SEED [--random] [--frames N] > trace.jsonl
  ai_trace.py report TRACE.jsonl...

run plays one battle with battle_harness.py (the smart player by default, or
the random Typhlosion with --random) and prints one JSON line:
- decisions: every SwitchSmogon call, with the branch labels it went
  through (SwitchSmogon.escape, .matchup, .switch, DontSwitch...), the
  active and best switch-in scores, the move the AI had picked, its spent
  flag, Spikes on each side, both sides' Pokemon (species, level, HP,
  stats, types, moves, PP, DVs, status, item), item_used when the AI used an
  item instead, player_switched when the player switched this turn (the
  AI's move was picked before, against the previous Pokemon), and in 'state' the rest engine_judge.py needs (the player's
  party, stats before stat changes, substatuses, screens, weather),
- candidates: every switch-in the AI scored (AISmogon_FindBestSwitchIn), with
  its raw matchup score and penalty, the attack lists (ATTACKS_*: best damage
  and each attack's damage and PP), healing blocks (HEAL_*) and setup credit
  (SMOGON_SETUP_*) the score came from,
- switch_ins: every enemy switch-in (mid-battle or forced),
- the battle result (see battle_harness.py).

report summarizes traces: mid-battle switches by (from, to, against), the
replacements after a faint, the average raw matchup score of each candidate
against each player Pokemon, and how often the AI stayed in a matchup it
loses badly while a healthy teammate wins it, judged by smart_player.race (an
independent damage race in Python, not the AI's assembly)."""
import collections
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from pokedata import BASE_TYPES, CONST, species_name  # noqa: E402

BRANCHES = ['SwitchSmogon.no_perish', 'SwitchSmogon.no_pursuit', 'SwitchSmogon.no_rest',
            'SwitchSmogon.not_toxic', 'SwitchSmogon.escape', 'SwitchSmogon.spent',
            'SwitchSmogon.matchup', 'SwitchSmogon.settled_in', 'SwitchSmogon.switch', 'DontSwitch']


def run(argv):
    from battle_harness import Battle
    rom, symf, save, trainer, seed = argv[:5]
    smart = '--random' not in argv
    frames = int(argv[argv.index('--frames') + 1]) if '--frames' in argv else 216000
    battle = Battle(rom, symf, save, trainer, seed, smart=smart)
    mem, W, word = battle.mem, battle.W, battle.word
    length = W('wOTPartyMon2') - W('wOTPartyMon1')

    def mon(prefix, i=None):
        if i is None:
            at = lambda n: W(prefix + n)
            species = mem[at('Species')]
            types = [mem[at('Type1')], mem[at('Type1') + 1]]
        else:
            party_length = W(prefix + '2') - W(prefix + '1')
            at = lambda n: W(prefix + '1' + n) + i * party_length
            species = mem[at('Species')]
            types = list(BASE_TYPES.get(species, (0, 0)))
        return {'species': species, 'level': mem[at('Level')], 'hp': word(at('HP')),
                'max_hp': word(at('MaxHP')), 'stats': [word(at('Attack') + 2 * k) for k in range(5)],
                'types': types, 'moves': [mem[at('Moves') + k] for k in range(4)],
                'pp': [mem[at('PP') + k] for k in range(4)],
                'dvs': [mem[at('DVs')], mem[at('DVs') + 1]], 'status': mem[at('Status')],
                'item': mem[at('Item')]}

    def block(label, size):
        return [mem[W(label) + k] for k in range(size)]

    decisions, candidates, switch_ins = [], [], []
    current = {}

    def on_decide(ctx):
        party = [mon('wOTPartyMon', i) for i in range(mem[W('wOTPartyCount')])]
        active = party[mem[W('wCurOTMon')]]
        active['hp'] = word(W('wEnemyMonHP'))
        d = {'turn': mem[W('wEnemyTurnsTaken')], 'active': mem[W('wCurOTMon')], 'party': party,
             'player': mon('wBattleMon'), 'player_stages': block('wPlayerStatLevels', 7),
             'enemy_stages': block('wEnemyStatLevels', 7), 'move': mem[W('wCurEnemyMove')],
             'spent': mem[W('wEnemyAIMovesSpent')] if 'wEnemyAIMovesSpent' in battle.sym else None,
             'spikes_ai': bool(mem[W('wEnemyScreens')] & 1 << CONST['SCREENS_SPIKES']),
             'spikes_player': bool(mem[W('wPlayerScreens')] & 1 << CONST['SCREENS_SPIKES']),
             'revealed': block('wPlayerUsedMoves', 4), 'path': []}
        # The rest of the battle state, for engine_judge.py: the actives' own
        # moves, PP, item and status (the party copies can be stale), their
        # stats before stat changes, the player's party, volatile statuses,
        # screens and weather.
        enemy = mon('wEnemyMon')
        for key in ('moves', 'pp', 'status', 'item', 'types'):
            active[key] = enemy[key]
        d['state'] = {
            'player_party': [mon('wPartyMon', i) for i in range(mem[W('wPartyCount')])],
            'player_active': mem[W('wCurBattleMon')],
            'unboosted': {side: [word(W(f'w{side}Stats') + 2 * k) for k in range(5)]
                          for side in ('Player', 'Enemy')},
            'substatus': {side: block(f'w{side}SubStatus1', 5) for side in ('Player', 'Enemy')},
            'counts': {side: dict(zip(('rollout', 'confuse', 'toxic', 'disable', 'encore', 'perish'),
                                      block(f'w{side}RolloutCount', 6))) for side in ('Player', 'Enemy')},
            'substitute_hp': {side: mem[W(f'w{side}SubstituteHP')] for side in ('Player', 'Enemy')},
            'screens': {side: mem[W(f'w{side}Screens')] for side in ('Player', 'Enemy')},
            'screen_counts': {side: dict(zip(('safeguard', 'light_screen', 'reflect'),
                                             block(f'w{side}SafeguardCount', 3))) for side in ('Player', 'Enemy')},
            'disabled': {'Player': mem[W('wDisabledMove')], 'Enemy': mem[W('wEnemyDisabledMove')]},
            'weather': mem[W('wBattleWeather')], 'weather_count': mem[W('wWeatherCount')]}
        # AIChooseMove picks the move at the start of the turn, but
        # SwitchSmogon runs after the player's switch: then the move is
        # locked in, picked against the previous Pokemon.
        d['player_switched'] = current.get('chose_vs') not in (None, mem[W('wCurBattleMon')])
        decisions.append(d)
        current['d'] = d

    def on_choose(ctx):
        current['chose_vs'] = mem[W('wCurBattleMon')]

    def on_branch(label):
        def cb(ctx):
            d = current.get('d')
            if d is None:
                return
            d['path'].append(label.split('.')[-1])
            if label in ('DontSwitch', 'SwitchSmogon.switch'):
                d['scores'] = {'active': mem[W('wEnemyAISwitchScore')], 'best': mem[W('wSmogonAIBestScore')],
                               'best_mon': mem[W('wSmogonAIBestMon')]}
                d['switched'] = label == 'SwitchSmogon.switch'
                current['d'] = None
        return cb

    def on_candidate(ctx):
        rf = battle.pb.register_file
        c = {'decision': len(decisions) - 1, 'mon': mem[W('wSmogonAIMon')],
             'species': mem[W('wOTPartyMon1Species') + mem[W('wSmogonAIMon')] * length],
             'player': mem[W('wBattleMonSpecies')], 'raw': rf.C, 'penalty': rf.D, 'final': rf.A,
             'after_faint': word(W('wEnemyMonHP')) == 0}
        if 'wSmogonAISetupBoost' in battle.sym:
            c['setup'] = mem[W('wSmogonAISetupBoost')]
        for label in ('wSmogonAIThreat', 'wSmogonAIPower'):
            if label in battle.sym:
                raw = block(label, 3 + 3 * CONST.get('SMOGON_MAX_ATTACKS', 0))
                c[label] = {'best': raw[0] << 8 | raw[1],
                            'attacks': [[raw[3 + 3 * i] << 8 | raw[4 + 3 * i], raw[5 + 3 * i]] for i in range(raw[2])]
                            if 'SMOGON_MAX_ATTACKS' in CONST else []}
        for label in ('wSmogonAIOurHeal', 'wSmogonAIPlayerHeal'):
            if label in battle.sym:
                raw = block(label, 5)
                c[label] = {'heal': raw[0] << 8 | raw[1], 'pp': raw[2], 'hp': raw[3] << 8 | raw[4]}
        candidates.append(c)

    def on_switch_in(ctx):
        b = battle.pb.register_file.B
        switch_ins.append({'decision': len(decisions) - 1, 'from': mem[W('wEnemyMonSpecies')],
                           'from_hp': word(W('wEnemyMonHP')), 'to': mem[W('wOTPartyMon1Species') + b * length],
                           'vs': mem[W('wBattleMonSpecies')],
                           'kind': 'mid' if decisions and decisions[-1].get('switched')
                           and not decisions[-1].get('loaded') else 'forced'})
        if decisions and decisions[-1].get('switched'):
            decisions[-1]['loaded'] = True

    def on_item(ctx):
        if decisions:
            decisions[-1]['item_used'] = True

    battle.on('AIChooseMove', on_choose)
    battle.on('SwitchSmogon', on_decide)
    battle.on('AIUsedItemSound', on_item)
    for label in BRANCHES:
        if label in battle.sym:
            battle.on(label, on_branch(label))
    battle.on('AISmogon_FindBestSwitchIn.compare', on_candidate)
    battle.on('LoadEnemyMonToSwitchTo', on_switch_in)
    battle.start()
    result = battle.run(frames)
    battle.stop()
    for d in decisions:
        d.pop('loaded', None)
    result.update(decisions=decisions, candidates=candidates, switch_ins=switch_ins)
    print(json.dumps(result))


def report(paths):
    from smart_player import race
    rows = [json.loads(line) for p in paths for line in open(p) if line.startswith('{')]
    name = species_name
    print(f'{len(rows)} battles: AI wins {sum(r["won"] == 1 for r in rows)}, '
          f'crashes {sum(bool(r["crashed_at"]) for r in rows)}, not ended {sum(not r["ended"] for r in rows)}')

    def as_mon(m, stages=None):
        m = dict(m)
        if stages:
            mult = lambda s: (2 + max(0, s - 7)) / (2 + max(0, 7 - s))
            m['stats'] = [int(v * mult(stages[k])) for k, v in enumerate(m['stats'])]
        return m

    mid = collections.Counter((name(s['from']), name(s['to']), name(s['vs']))
                              for r in rows for s in r['switch_ins'] if s['kind'] == 'mid')
    print(f'\nmid-battle switches: {sum(mid.values())}')
    for (a, b, v), n in mid.most_common(15):
        print(f'  {n:4}x {a:11} -> {b:11} vs {v}')

    forced = collections.Counter((name(s['to']), name(s['vs']))
                                 for r in rows for s in r['switch_ins'] if s['kind'] == 'forced' and s['vs'])
    print(f'\nreplacements after a faint: {sum(forced.values())}')
    for (b, v), n in forced.most_common(12):
        print(f'  {n:4}x {b:11} vs {v}')

    scores = collections.defaultdict(list)
    for r in rows:
        for c in r['candidates']:
            scores[(name(c['player']), name(c['species']))].append(c['raw'])
    players = sorted({p for p, _ in scores})
    mons = sorted({m for _, m in scores})
    print('\naverage raw matchup score (128 = even; +16 = a race twice as good) of each candidate')
    print('  vs ' + ' '.join(f'{m[:9]:>9}' for m in mons))
    for p in players:
        cells = [f'{sum(scores[(p, m)]) / len(scores[(p, m)]):9.0f}' if scores.get((p, m)) else f'{"":>9}'
                 for m in mons]
        print(f'  {p[:9]:9} ' + ' '.join(cells))

    stuck = collections.Counter()
    total = 0
    for r in rows:
        for d in r['decisions']:
            if d.get('switched') is not False:
                continue
            total += 1
            party = d['party']
            # (wBattleMon's stats already include the stat changes)
            player = d['player']
            here = race(as_mon(party[d['active']], d['enemy_stages']), player, False)
            alts = [race(m, player, True) for i, m in enumerate(party) if i != d['active'] and m['hp']]
            if here < -1 and alts and max(alts) > 0:
                stuck[(name(party[d['active']]['species']), name(player['species']),
                       d['path'][-2] if len(d['path']) > 1 else d['path'][-1])] += 1
    print(f'\nstayed in: {total} decisions; losing the race badly (log2 < -1) while a healthy '
          f'teammate wins it after taking a hit: {sum(stuck.values())}')
    for (a, v, why), n in stuck.most_common(12):
        print(f'  {n:4}x {a:11} vs {v:11} (last branch {why})')


if __name__ == '__main__':
    if len(sys.argv) > 1 and sys.argv[1] == 'run':
        run(sys.argv[2:])
    elif len(sys.argv) > 1 and sys.argv[1] == 'report':
        report(sys.argv[2:])
    else:
        print(__doc__)
