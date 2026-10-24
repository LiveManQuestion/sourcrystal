"""Second opinion on the Smogon AI's decisions from poke-engine, the Gen 2
search engine behind the Foul Play bot.

usage (with the poke-engine venv's Python, see docs/claude_tools.md):
  engine_judge.py TRACE.jsonl... [--ms 500] [--threads 4] [--top 15] [--json OUT]
  engine_judge.py TRACE.jsonl... --iterations N [--jobs 11] [--cache FILE] [--top 15] [--json OUT]
  engine_judge.py --report OUT   # report saved results again, without searching
  engine_judge.py --patterns OUT [BASE]  # rank patterns; with BASE, compare them
  engine_judge.py --check        # every move, species and item maps to the engine

For each SwitchSmogon decision in ai_trace.py traces (the turns the AI used
an item or had no PP left are left out), it rebuilds the position, runs poke-engine's MCTS for
--ms milliseconds with the AI as side one (or, with --iterations, exactly N
iterations on one thread, --jobs decisions at a time: the engine's threads
scale badly, so this searches as deep in less time, and how deep doesn't
depend on the machine's load; --cache FILE keeps every position's search,
so a position an earlier run reached with the same settings, or another
decision reached, isn't searched again), and compares the AI's action (the
switch-in, or the move it picked) with the engine's: the action the search
visited most. A decision's regret is the engine's value of its own action
minus its value of the AI's (values are side one's chances, 0 to 1). It
prints how often the two agree, the decisions with the biggest regret and
the regret grouped by kind (stay vs. switch, move vs. move).

--patterns ranks the disagreements of saved results by total regret,
grouped by action, matchup, and both: a pattern is worth fixing when its
regret is concentrated (many clear disagreements, over several battles).
With BASE (the same traces' seeds on an older ROM), it prints each top
pattern's regret before and after. Compare patterns, not totals: any code
change reshuffles the battles' RNG, so totals swing by chance.

Read the results with care:
- The engine knows the player's whole party, moves and items, which the AI
  doesn't. Disagreements the AI couldn't have avoided show up too.
- poke-engine simulates Pokemon Showdown's Gen 2, not the cartridge. Close,
  but not exact (damage_diff.py stays the reference for damage). Hidden
  Power counts as 70 power, sleep turns start from 0, and items the engine
  doesn't know (--check lists the ones it does) do nothing.
- After the player switches, the engine still lets the player act this turn
  (the position comes from after the switch), so it overrates the player a
  little there. Those decisions only compare staying in with switching.
- MCTS is noisy: a value from few visits means little, so regret is only
  counted when the AI's action got --min-visits visits. Rerun with a larger
  --ms or --iterations to see whether a disagreement holds up."""
import collections
import hashlib
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from pokedata import (CONST, ITEM_NAMES, MOVE_NAMES, MOVES, SPECIES_NAMES, TYPES,  # noqa: E402
                      hidden_power, move_name, species_name)

try:
    import poke_engine as pe  # noqa: E402
except ImportError:  # --report and --patterns don't need it
    pe = None

GEN2_TYPES = ['NORMAL', 'FIGHTING', 'FLYING', 'POISON', 'GROUND', 'ROCK', 'BUG', 'GHOST', 'STEEL', 'FIRE',
              'WATER', 'GRASS', 'ELECTRIC', 'PSYCHIC_TYPE', 'ICE', 'DRAGON', 'DARK']
# (not from TYPES itself: other constants share some values, like STEEL's)
TYPE_NAMES = {TYPES[name]: name for name in GEN2_TYPES}
# (poke-engine's Gen 2 gives Frustration, Flail and Magnitude no power:
# Frustration is 102 at a trainer's 0 happiness, Flail works like Reversal,
# and Stomping Tantrum is a 75-power Ground attack, near Magnitude's 71)
MOVE_RENAMES = {'PSYCHIC_M': 'psychic', 'FAINT_ATTACK': 'feintattack', 'VICEGRIP': 'visegrip',
                'HI_JUMP_KICK': 'highjumpkick', 'RETURN': 'return102', 'FRUSTRATION': 'return102',
                'FLAIL': 'reversal', 'MAGNITUDE': 'stompingtantrum'}
# Sour Crystal's item names that differ from Gen 2's (the IDs are vanilla's)
ITEM_RENAMES = {'NO_ITEM': 'none', 'PECHA_BERRY': 'psncureberry', 'CHERI_BERRY': 'przcureberry',
                'ASPEAR_BERRY': 'burntberry', 'RAWST_BERRY': 'iceberry', 'PERSIM_BERRY': 'bitterberry',
                'CHESTO_BERRY': 'mintberry', 'SILK_SCARF': 'pinkbow', 'LUM_BERRY': 'miracleberry',
                'LEPPA_BERRY': 'mysteryberry', 'ORAN_BERRY': 'berry', 'SITRUS_BERRY': 'goldberry',
                'BLACKBELT_I': 'blackbelt'}
WEATHER = {CONST['WEATHER_RAIN']: 'rain', CONST['WEATHER_SUN']: 'sun', CONST['WEATHER_SANDSTORM']: 'sand'}
# (substatus byte, flag) -> engine volatile status
VOLATILES = {(0, 'SUBSTATUS_NIGHTMARE'): 'nightmare', (0, 'SUBSTATUS_CURSE'): 'curse',
             (0, 'SUBSTATUS_IDENTIFIED'): 'foresight', (0, 'SUBSTATUS_IN_LOVE'): 'attract',
             (1, 'SUBSTATUS_CURLED'): 'defensecurl', (2, 'SUBSTATUS_RAMPAGE'): 'lockedmove',
             (2, 'SUBSTATUS_UNDERGROUND'): 'dig', (2, 'SUBSTATUS_FLYING'): 'fly',
             (2, 'SUBSTATUS_CONFUSED'): 'confusion', (3, 'SUBSTATUS_FOCUS_ENERGY'): 'focusenergy',
             (3, 'SUBSTATUS_SUBSTITUTE'): 'substitute', (3, 'SUBSTATUS_RECHARGE'): 'mustrecharge',
             (3, 'SUBSTATUS_LEECH_SEED'): 'leechseed', (4, 'SUBSTATUS_ENCORED'): 'encore',
             (4, 'SUBSTATUS_DESTINY_BOND'): 'destinybond'}


def engine_id(name):
    return name.lower().replace('_', '')


def type_id(t):
    name = TYPE_NAMES.get(t)
    return 'psychic' if name == 'PSYCHIC_TYPE' else engine_id(name) if name else 'typeless'


def item_id(item):
    name = ITEM_NAMES.get(item, 'NO_ITEM')
    return ITEM_RENAMES.get(name, engine_id(name))


def move_id(move, dvs):
    name = MOVE_NAMES.get(move, 'none')
    if name == 'HIDDEN_POWER':
        return f'hiddenpower{type_id(hidden_power(*dvs)[1])}70'
    return MOVE_RENAMES.get(name, engine_id(name))


def status_of(byte, toxic):
    if byte & CONST['SLP_MASK']:
        return 'sleep'
    for flag, name in (('PSN', 'toxic' if toxic else 'poison'), ('BRN', 'burn'), ('FRZ', 'freeze'),
                       ('PAR', 'paralyze')):
        if byte & 1 << CONST[flag]:
            return name
    return 'none'


def pokemon(m, stats=None, toxic=False, disabled=0):
    types = [type_id(t) for t in m['types']]
    if types[1] == types[0]:
        types[1] = 'typeless'
    stats = stats or m['stats']
    moves = [pe.Move(id=move_id(mv, m['dvs']), pp=pp & 0x3f, disabled=mv == disabled)
             for mv, pp in zip(m['moves'], m['pp']) if mv]
    return pe.Pokemon(id=engine_id(species_name(m['species'])), level=m['level'], types=tuple(types),
                      base_types=tuple(types), hp=m['hp'], maxhp=m['max_hp'],
                      item=item_id(m.get('item', 0)),
                      attack=stats[0], defense=stats[1], speed=stats[2], special_attack=stats[3],
                      special_defense=stats[4], status=status_of(m['status'], toxic), moves=moves)


def side(party, active, stages, st, who):
    sub, counts = st['substatus'][who], st['counts'][who]
    toxic = bool(sub[4] & 1 << CONST['SUBSTATUS_TOXIC'])
    mons = [pokemon(m, st['unboosted'][who] if i == active else None, toxic and i == active,
                    st['disabled'][who] if i == active else 0) for i, m in enumerate(party)]
    vol = {name for (byte, flag), name in VOLATILES.items() if sub[byte] & 1 << CONST[flag]}
    # The engine panics on an Encore without the encored move (traces from
    # before ai_trace.py logged it, or a move the Pokemon doesn't have).
    last_used = 'move:none'
    if 'encore' in vol:
        last = st.get('last_move', {}).get(who)
        moves = party[active]['moves']
        if last and last in moves:
            last_used = f'move:{moves.index(last)}'
        else:
            vol.discard('encore')
    if sub[0] & 1 << CONST['SUBSTATUS_PERISH'] and 1 <= counts['perish'] <= 4:
        vol.add(f'perish{counts["perish"]}')
    screens, sc = st['screens'][who], st['screen_counts'][who]
    conditions = pe.SideConditions(
        spikes=int(bool(screens & 1 << CONST['SCREENS_SPIKES'])),
        reflect=sc['reflect'] if screens & 1 << CONST['SCREENS_REFLECT'] else 0,
        light_screen=sc['light_screen'] if screens & 1 << CONST['SCREENS_LIGHT_SCREEN'] else 0,
        safeguard=sc['safeguard'] if screens & 1 << CONST['SCREENS_SAFEGUARD'] else 0,
        toxic_count=counts['toxic'] if toxic else 0)
    durations = pe.VolatileStatusDurations(confusion=counts['confuse'], encore=counts['encore'])
    s = [x - 7 for x in stages]
    return pe.Side(pokemon=mons, active_index=pe.PokemonIndex(str(active)), volatile_statuses=vol,
                   volatile_status_durations=durations, side_conditions=conditions, last_used_move=last_used,
                   substitute_health=st['substitute_hp'][who], attack_boost=s[0], defense_boost=s[1],
                   speed_boost=s[2], special_attack_boost=s[3], special_defense_boost=s[4],
                   accuracy_boost=s[5], evasion_boost=s[6])


def position(d):
    """The poke-engine State of a decision, the AI as side one."""
    st = d['state']
    player_party = [dict(m) for m in st['player_party']]
    player_party[st['player_active']] = dict(d['player'])
    return pe.State(side_one=side(d['party'], d['active'], d['enemy_stages'], st, 'Enemy'),
                    side_two=side(player_party, st['player_active'], d['player_stages'], st, 'Player'),
                    weather=WEATHER.get(st['weather'], 'none'),
                    weather_turns_remaining=st['weather_count'] if st['weather'] in WEATHER else 0)


def ai_action(d):
    if d.get('switched'):
        return 'switch ' + engine_id(species_name(d['party'][d['scores']['best_mon']]['species']))
    return move_id(d['move'], d['party'][d['active']]['dvs'])


def search(state, ms, threads, iterations=0):
    """The engine's search of a position (State.to_string()): its iterations
    and the (value, visits) of each of side one's options."""
    result = pe.monte_carlo_tree_search(pe.State.from_string(state), duration_ms=ms, iterations=iterations,
                                        threads=1 if iterations else threads)
    return {'visits': result.total_visits,
            'options': {o.move_choice: (o.total_score / o.visits if o.visits else 0, o.visits)
                        for o in result.side_one}}


SEARCH_TIMEOUT = 300


def search_safe(args):
    """search(*args) in a forked child, or {'error': ...} when the engine
    fails. A Rust panic is a BaseException, and a few positions make the
    engine loop until it overflows its stack (a segfault, minutes later):
    either would kill a multiprocessing worker and hang the pool, so the
    child is killed after SEARCH_TIMEOUT seconds (a search usually takes
    one or two)."""
    import select
    import signal
    import time
    r, w = os.pipe()
    pid = os.fork()
    if pid == 0:
        os.close(r)
        try:
            found = search(*args)
        except BaseException as e:  # noqa: B036
            found = {'error': f'{type(e).__name__}: {e}'}
        with os.fdopen(w, 'w') as f:
            f.write(json.dumps(found))
        os._exit(0)
    os.close(w)
    chunks, end = [], time.monotonic() + SEARCH_TIMEOUT
    with os.fdopen(r) as f:
        while True:
            left = end - time.monotonic()
            if left <= 0 or not select.select([f], [], [], left)[0]:
                os.kill(pid, signal.SIGKILL)
                os.waitpid(pid, 0)
                return {'error': f'no result after {SEARCH_TIMEOUT} s'}
            chunk = f.read()
            if not chunk:
                break
            chunks.append(chunk)
    os.waitpid(pid, 0)
    if not chunks:
        return {'error': 'engine crashed'}
    return json.loads(''.join(chunks))


def judge(d, found):
    """A decision's record from the search of its position."""
    status = d['party'][d['active']]['status']
    return {'ai_raw': ai_action(d), 'visits': found['visits'],
            'asleep': bool(status & (CONST['SLP_MASK'] | 1 << CONST['FRZ'])),
            'locked': move_id(d['move'], d['party'][d['active']]['dvs']) if d.get('player_switched') else None,
            'options': found['options']}


def score(j, min_visits):
    """Add the AI's and the engine's actions and the regret. While the AI's
    Pokemon is asleep or frozen, every move but Sleep Talk and Snore does
    nothing, so they count as one action, staying in: the most visited one.
    After the player switched, the AI's move was already picked, so its only
    options are that move and the switches."""
    options = j['options']
    if j.get('locked'):
        options = {k: v for k, v in options.items() if kind(k) == 'switch' or k == j['locked']}
    ai, best = j['ai_raw'], max(options, key=lambda k: options[k][1])
    if j['asleep']:
        idle = [k for k in options if kind(k) == 'move' and k not in ('sleeptalk', 'snore')]
        if idle:
            stay = max(idle, key=lambda k: options[k][1])
            ai, best = (stay if a in idle else a for a in (ai, best))
    value, visits = options.get(ai, (None, 0))
    j.update(ai=ai, engine=best, ai_value=value, ai_visits=visits, engine_value=options[best][0],
             regret=options[best][0] - value if visits >= min_visits else None)


def check():
    """Every move, species and item the game has must map to an engine id
    (the engine silently turns unknown ids into NONE)."""
    bad = []
    for move in MOVES:
        mid = move_id(move, (0xff, 0xff))
        mons = [pe.Pokemon(id='mew', moves=[pe.Move(id=mid)])]
        text = pe.State(side_one=pe.Side(pokemon=mons), side_two=pe.Side(pokemon=mons)).to_string()
        if text.split(',')[22].split(';')[0] == 'NONE':
            bad.append(('move', move_name(move), mid))
    for n, name in SPECIES_NAMES.items():
        if n == 0 or n > 251:
            continue
        mons = [pe.Pokemon(id=engine_id(name))]
        if pe.State(side_one=pe.Side(pokemon=mons), side_two=pe.Side(pokemon=mons)).to_string().startswith('NONE'):
            bad.append(('species', name, engine_id(name)))
    for name in bad:
        print(*name)
    known = []
    for n, name in sorted(ITEM_NAMES.items()):
        mons = [pe.Pokemon(item=item_id(n))]
        if pe.State(side_one=pe.Side(pokemon=mons), side_two=pe.Side(pokemon=mons)).to_string().split(',')[10] not in (
                'NONE', 'UNKNOWNITEM'):
            known.append(name)
    print(f'{len(bad)} unmapped moves/species; items the engine knows: {" ".join(known)}')


def main(argv):
    if not argv:
        return print(__doc__)
    if pe is None and '--report' not in argv and '--patterns' not in argv:
        sys.exit('poke_engine is missing: run this with the poke-engine venv, from the repo root:\n'
                 '  bots/pe-venv/bin/python tools/claude/engine_judge.py TRACE.jsonl...\n'
                 '(setup: docs/claude_tools.md)')
    if '--check' in argv:
        return check()
    opts = {'--ms': 500, '--threads': 4, '--iterations': 0, '--jobs': 11, '--top': 15, '--min-visits': 50,
            '--json': None, '--report': None, '--cache': None}
    paths = []
    it = iter(argv)
    for a in it:
        if a in opts:
            opts[a] = next(it) if a in ('--json', '--report', '--cache') else int(next(it))
        else:
            paths.append(a)
    if '--patterns' in paths:
        paths.remove('--patterns')
        return patterns(*paths[:2], top=opts['--top'], min_visits=opts['--min-visits'])
    if opts['--report']:
        rows = [json.loads(line) for line in open(opts['--report'])]
        for j in rows:
            score(j, opts['--min-visits'])
        return report(rows, opts['--top'])
    todo = []
    for p in paths:
        for b, line in enumerate(open(p)):
            if not line.startswith('{'):
                continue
            r = json.loads(line)
            for i, d in enumerate(r['decisions']):
                # (out of PP, the engine has no Struggle to compare with)
                if 'state' not in d or 'switched' not in d or d.get('item_used') or \
                        not any(pp & 0x3f for pp in d['party'][d['active']]['pp']):
                    continue
                todo.append((p, b, i, d))
    settings = (opts['--ms'], opts['--threads'], opts['--iterations'])
    states = [position(d).to_string() for _, _, _, d in todo]
    keys = [hashlib.sha1(s.encode()).hexdigest() for s in states]
    # Each position is searched once: in earlier runs (--cache, the same
    # settings), or once for all the decisions that reach it.
    cache = {}
    if opts['--cache']:
        if not opts['--iterations']:
            sys.exit('--cache needs --iterations: a timed search depends on the machine\'s load')
        if os.path.exists(opts['--cache']):
            for line in open(opts['--cache']):
                c = json.loads(line)
                cache[c['key']] = c
    new = {}
    for k, s in zip(keys, states):
        if k not in cache:
            new.setdefault(k, s)
    tasks = [(s, *settings) for s in new.values()]
    out = open(opts['--cache'], 'a') if opts['--cache'] else None
    failed = {}
    if opts['--iterations'] and opts['--jobs'] > 1:
        import multiprocessing
        pool = multiprocessing.Pool(opts['--jobs'])
        found = pool.imap(search_safe, tasks, chunksize=1)
    else:
        pool, found = None, map(search_safe, tasks)
    # (written as each search ends, so an interrupted run keeps its work)
    for n, (k, f) in enumerate(zip(new, found)):
        if 'error' in f:
            failed[k] = f['error']
            continue
        cache[k] = dict(key=k, **f)
        if out:
            out.write(json.dumps(cache[k]) + '\n')
            out.flush()
        if n % 500 == 499:
            print(f'{n + 1}/{len(new)} positions searched', file=sys.stderr)
    if pool:
        pool.close()
    print(f'{len(todo)} decisions, {len(new)} positions searched, {len(todo) - len(new)} reused', file=sys.stderr)
    for e, n in collections.Counter(failed.values()).items():
        print(f'{n} positions the engine failed on: {e}', file=sys.stderr)
    rows = []
    for (p, b, i, d), k in zip(todo, keys):
        if k in failed:
            continue
        j = judge(d, cache[k])
        j.update(trace=os.path.basename(p), battle=b, decision=i, turn=d['turn'],
                 ai_mon=species_name(d['party'][d['active']]['species']),
                 player_mon=species_name(d['player']['species']), path=d['path'][-2:],
                 ai_hp=f'{d["party"][d["active"]]["hp"]}/{d["party"][d["active"]]["max_hp"]}',
                 player_hp=f'{d["player"]["hp"]}/{d["player"]["max_hp"]}')
        score(j, opts['--min-visits'])
        rows.append(j)
    if opts['--json']:
        with open(opts['--json'], 'w') as f:
            for j in rows:
                f.write(json.dumps(j) + '\n')
    report(rows, opts['--top'])


def kind(action):
    return 'switch' if action.startswith('switch') else 'move'


def action(a):
    return 'switch' if a.startswith('switch') else a


PATTERN_KEYS = [
    ('AI action -> engine action', lambda j: (action(j['ai']), action(j['engine']))),
    ('AI action (any engine action)', lambda j: action(j['ai'])),
    ('matchup', lambda j: (j['ai_mon'], j['player_mon'])),
    ('matchup and AI action -> engine action',
     lambda j: (j['ai_mon'], j['player_mon'], action(j['ai']), action(j['engine']))),
]


def load_scored(path, min_visits):
    rows = [json.loads(line) for line in open(path)]
    for j in rows:
        score(j, min_visits)
    return [j for j in rows if j['regret'] is not None]


def group(rows, key):
    """key -> [total regret, decisions, clear (> 0.1), battles] over disagreements."""
    g = {}
    for j in rows:
        if j['ai'] == j['engine']:
            continue
        e = g.setdefault(key(j), [0.0, 0, 0, set()])
        e[0] += j['regret']; e[1] += 1; e[2] += j['regret'] > 0.1; e[3].add(j['trace'])
    return {k: (r, n, c, len(b)) for k, (r, n, c, b) in g.items()}


def patterns(path, base=None, top=15, min_visits=50):
    new = load_scored(path, min_visits)
    old = load_scored(base, min_visits) if base else None
    def total(rows):
        return f'{len(rows)} decisions, total regret {sum(j["regret"] for j in rows):.2f}'
    print(total(new) + (f' (base: {total(old)})' if old else ''))
    for title, key in PATTERN_KEYS:
        g = group(new, key)
        if old is None:
            print(f'\n{title}  (total regret, decisions, clear > 0.1, battles)')
            for k, (r, n, c, b) in sorted(g.items(), key=lambda kv: -kv[1][0])[:top]:
                print(f'  {r:6.2f} {n:4} {c:4} {b:3}  {k}')
            continue
        # The top patterns of either run, so fixed ones show up too.
        h = group(old, key)
        keys = sorted(set(sorted(g, key=lambda k: -g[k][0])[:top]) | set(sorted(h, key=lambda k: -h[k][0])[:top]),
                      key=lambda k: -max(g.get(k, (0,))[0], h.get(k, (0,))[0]))
        print(f'\n{title}  (base -> new: total regret, decisions, clear > 0.1)')
        for k in keys:
            (r0, n0, c0, _), (r1, n1, c1, _) = h.get(k, (0, 0, 0, 0)), g.get(k, (0, 0, 0, 0))
            print(f'  {r0:6.2f} {n0:4} {c0:3}  -> {r1:6.2f} {n1:4} {c1:3}  {k}')


def report(rows, top):
    if not rows:
        print('no decisions (traces from before ai_trace.py logged the state?)')
        return
    agree = sum(j['ai'] == j['engine'] for j in rows)
    counted = [j for j in rows if j['regret'] is not None]
    print(f'{len(rows)} decisions, ~{sum(j["visits"] for j in rows) // len(rows)} iterations each; '
          f'engine agrees {agree} ({100 * agree / len(rows):.0f}%)')
    print(f'mean regret {sum(j["regret"] for j in counted) / max(1, len(counted)):.3f} over {len(counted)} '
          f'decisions where the AI\'s action got enough visits; {len(rows) - len(counted)} AI actions the '
          f'engine barely tried (it thinks they are bad)')
    clear = [j for j in counted if j['regret'] > 0.1]
    print(f'clear disagreements (regret > 0.1): {len(clear)}, '
          f'{sum(kind(j["ai"]) != kind(j["engine"]) for j in clear)} of them stay vs. switch')

    groups = collections.defaultdict(list)
    for j in rows:
        groups[(kind(j['ai']), kind(j['engine']))].append(j)
    print('\nAI -> engine     n  barely tried  mean regret')
    for (a, e), js in sorted(groups.items()):
        rs = [j['regret'] for j in js if j['regret'] is not None]
        print(f'  {a:6} -> {e:6} {len(js):4} {sum(j["regret"] is None for j in js):12}  '
              f'{sum(rs) / len(rs) if rs else 0:11.3f}')

    def key(j):
        return 1.0 if j['regret'] is None else j['regret']
    print(f'\nbiggest disagreements (regret; "-" = the engine barely tried the AI\'s action)')
    for j in sorted((j for j in rows if j['ai'] != j['engine']), key=key, reverse=True)[:top]:
        r = '-' if j['regret'] is None else f'{j["regret"]:.2f}'
        print(f'  {r:>5}  {j["trace"]}#{j["battle"]}.{j["decision"]} turn {j["turn"]:2}: '
              f'{j["ai_mon"]} ({j["ai_hp"]}{", asleep" if j["asleep"] else ""}) vs {j["player_mon"]} ({j["player_hp"]}): '
              f'AI {j["ai"]}, engine {j["engine"]} ({j["engine_value"]:.2f}) [{" ".join(j["path"])}]')

    pairs = collections.Counter((j['ai_mon'], j['player_mon'], kind(j['ai']), kind(j['engine']))
                                for j in rows if kind(j['ai']) != kind(j['engine']))
    print('\nstay/switch disagreements by matchup')
    for (a, p, k1, k2), n in pairs.most_common(top):
        print(f'  {n:4}x {a:11} vs {p:11} AI {k1}, engine {k2}')


if __name__ == '__main__':
    main(sys.argv[1:])
