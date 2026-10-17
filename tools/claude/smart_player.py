"""A strong greedy player for battle.py --smart.

Plays the save's own party, with no healing:
- attacks with the move that does the most expected damage (Gen 2 damage
  formula with the real stats and stat changes, STAB, type, accuracy, Hidden
  Power's real type; two-turn moves count half, Explosion and Counter are
  left out),
- switches when a healthy party member wins the KO race against the enemy's
  active Pokemon at least twice as well as the active one, after taking a
  hit on the way in (and not two turns in a row),
- after a faint, sends in the party member with the best KO race,
- plays its status moves the way the save's OU team does (status_move):
  Sleep Talk while asleep, Rest when low, Explosion when about to faint,
  Roar on a boosted foe, Sleep Powder (Sleep Clause), Spikes, Curse and
  Growth when the foe can't punish them, and Toxic on walls.
SMART_PLAYER=basic (environment) turns the status moves off but Spikes,
like the player before 2026-10-17, which only attacked.
It sees the enemy's actual moves, so it's a strong benchmark, stronger than a
human who only knows the revealed moves.

It drives the menus through hooks: at the start of BattleMenu,
MoveSelectionScreen, BattleMenuPKMN_Loop and PickPartyMonInBattle it writes
the cursor variable the menu is about to read, then presses A. It backs out
of the party menu with B when it didn't mean to be there or a switch failed,
and a watchdog cycles down/A/B/A when no hook has fired for a while, so an
unexpected menu can't stall a battle (counted in actions['watchdog'])."""
import math
import os

from pokedata import BASE_TYPES, CONST, MOVES, SPECIAL, TYPES, effectiveness, hidden_power

SKIP = {'EFFECT_SELFDESTRUCT', 'EFFECT_COUNTER', 'EFFECT_MIRROR_COAT'}
CANT_RUN = CONST['SUBSTATUS_CANT_RUN']
SCREENS_SPIKES = CONST['SCREENS_SPIKES']
SUBSTITUTE = 1 << CONST['SUBSTATUS_SUBSTITUTE']
TOXIC = 1 << CONST['SUBSTATUS_TOXIC']
SLP = CONST['SLP_MASK']
PHAZE_HAZE = {'ROAR', 'WHIRLWIND', 'HAZE'}
# stat levels (7 = unchanged) the setup moves stop at
SETUP_CAP = {'CURSE': 10, 'GROWTH': 9}
TWO_TURN = {'EFFECT_RAZOR_WIND', 'EFFECT_SKY_ATTACK', 'EFFECT_SKULL_BASH', 'EFFECT_SOLARBEAM',
            'EFFECT_HYPER_BEAM'}


def stage(s):
    return (2 + max(0, s - 7)) / (2 + max(0, 7 - s))


def damage(att, dfn, move, dvs, boom=False):
    """Expected damage of move (id) from att on dfn: dicts with level, types,
    stats [atk, def, spd, sat, sdf] (with stat changes applied). Explosion
    counts only with boom (it halves Defense)."""
    mv = MOVES.get(move)
    if not mv or mv['effect'] in SKIP and not (boom and mv['effect'] == 'EFFECT_SELFDESTRUCT'):
        return 0
    power, typ = mv['power'], mv['type']
    if mv['name'] == 'HIDDEN_POWER':
        power, typ = hidden_power(*dvs)
    elif mv['name'] in ('RETURN', 'FRUSTRATION'):
        power = 102
    elif mv['name'] == 'MAGNITUDE':
        power = 71
    if power == 0:
        return 0
    eff = effectiveness(typ, dfn['types'])
    if eff == 0:
        return 0
    if power == 1:
        return att['level'] * mv['acc']
    a, d = (att['stats'][3], dfn['stats'][4]) if typ >= SPECIAL else (att['stats'][0], dfn['stats'][1])
    if boom:
        d //= 2
    dmg = ((2 * att['level'] // 5 + 2) * power * a / max(1, d)) / 50 + 2
    if typ in att['types']:
        dmg *= 1.5
    dmg *= eff * 0.925 * mv['acc']
    if mv['effect'] in TWO_TURN:
        dmg /= 2
    return dmg


def best_move(att, dfn, moves, pps, dvs):
    best, slot = 0, None
    for i, mv in enumerate(moves):
        if mv and pps[i] & 0x3f:
            d = damage(att, dfn, mv, dvs)
            if d > best:
                best, slot = d, i
    return best, slot


def race(us, them, entry_hit):
    """log2 of (their turns to KO us / our turns to KO them), in half turns
    (the faster side gets half a turn). Higher is better for us."""
    ours, _ = best_move(us, them, us['moves'], us['pp'], us['dvs'])
    theirs, _ = best_move(them, us, them['moves'], them['pp'], them['dvs'])
    our_turns = max(1, min(63, math.ceil(them['hp'] / ours))) if ours else 63
    hp = us['hp'] - (theirs if entry_hit else 0)
    if hp <= 0:
        return -7
    their_turns = min(63, math.ceil(hp / theirs)) if theirs else 63
    half = 2 * their_turns + (1 if us['stats'][2] > them['stats'][2] else 0)
    return math.log2(half / (2 * our_turns))


def heal_party(mem, W):
    """Restore the party's HP, status and PP (with its PP Ups)."""
    length = W('wPartyMon2') - W('wPartyMon1')
    for i in range(mem[W('wPartyCount')]):
        b = i * length
        mem[W('wPartyMon1HP') + b] = mem[W('wPartyMon1MaxHP') + b]
        mem[W('wPartyMon1HP') + b + 1] = mem[W('wPartyMon1MaxHP') + b + 1]
        mem[W('wPartyMon1Status') + b] = 0
        for k in range(4):
            move = mem[W('wPartyMon1Moves') + b + k]
            if move in MOVES:
                ups = mem[W('wPartyMon1PP') + b + k] >> 6
                base = MOVES[move]['pp']
                mem[W('wPartyMon1PP') + b + k] = ups << 6 | base + ups * min(base // 5, 7)


class SmartPlayer:
    def __init__(self, pb, sym, hook=None):
        # hook(label, fn): battle_harness.Battle.on, or a plain PyBoy hook
        hook = hook or (lambda label, fn: pb.hook_register(*sym[label], fn, None))
        self.pb, self.m = pb, pb.memory
        self.sym = sym
        self.W = lambda n: sym[n][1]
        self.plan = None
        self.switched_last = False
        self.no_switch = False
        self.back_out = False
        self.pkmn_visits = 0
        self.idle = 0
        self.watchdog = 0
        self.actions = {'attacks': 0, 'switches': 0, 'replacements': 0, 'watchdog': 0,
                        'errors': 0, 'spikes': 0}
        self.status_moves = os.environ.get('SMART_PLAYER') != 'basic'
        for name, cb in (('BattleMenu', self.on_menu), ('MoveSelectionScreen', self.on_moves),
                         ('BattleMenuPKMN_Loop', self.on_pkmn), ('PickPartyMonInBattle', self.on_pick)):
            hook(name, self.guarded(cb))

    def guarded(self, cb):
        # PyBoy swallows exceptions in hooks: count them instead
        def run(ctx):
            try:
                cb(ctx)
            except Exception as e:
                self.actions['errors'] += 1
                self.last_error = repr(e)
        return run

    def word(self, a):
        return self.m[a] << 8 | self.m[a + 1]

    def battle_mon(self, prefix, stages):
        m, W, w = self.m, self.W, self.word
        species = m[W(prefix + 'Species')]
        return dict(species=species, level=m[W(prefix + 'Level')], hp=w(W(prefix + 'HP')),
                    types=(m[W(prefix + 'Type1')], m[W(prefix + 'Type1') + 1]),
                    stats=[w(W(prefix + 'Attack') + 2 * k) for k in range(5)],
                    moves=[m[W(prefix + 'Moves') + k] for k in range(4)],
                    pp=[m[W(prefix + 'PP') + k] for k in range(4)],
                    dvs=(m[W(prefix + 'DVs')], m[W(prefix + 'DVs') + 1]))

    def party_mon(self, i):
        m, W, w = self.m, self.W, self.word
        base = W('wPartyMon1') + i * (W('wPartyMon2') - W('wPartyMon1'))
        off = lambda n: base + W('wPartyMon1' + n) - W('wPartyMon1')
        species = m[off('Species')]
        return dict(species=species, level=m[off('Level')], hp=w(off('HP')),
                    types=BASE_TYPES.get(species, (0, 0)),
                    stats=[w(off('Attack') + 2 * k) for k in range(5)],
                    moves=[m[off('Moves') + k] for k in range(4)],
                    pp=[m[off('PP') + k] for k in range(4)],
                    dvs=(m[off('DVs')], m[off('DVs') + 1]), status=m[off('Status')])

    def enemy(self):
        return self.battle_mon('wEnemyMon', None)

    def candidates(self, entry_hit):
        enemy = self.enemy()
        cur = self.m[self.W('wCurBattleMon')]
        out = []
        for i in range(self.m[self.W('wPartyCount')]):
            mon = self.party_mon(i)
            if mon['hp'] == 0 or (entry_hit and i == cur):
                continue
            # asleep or frozen ones would just sit there
            if mon['status'] & 7 or mon['status'] & 0x20:
                continue
            out.append((race(mon, enemy, entry_hit), i))
        return sorted(out, reverse=True)

    def enemy_bench(self):
        """How many of the enemy's other Pokemon can still battle."""
        m, W = self.m, self.W
        length = W('wOTPartyMon2') - W('wOTPartyMon1')
        cur = m[W('wCurOTMon')]
        return sum(1 for i in range(m[W('wOTPartyCount')]) if i != cur and
                   self.word(W('wOTPartyMon1HP') + i * length))

    def trapped(self):
        m, W = self.m, self.W
        return m[W('wPlayerSubStatus5')] & 1 << CANT_RUN or m[W('wPlayerWrapCount')]

    def on_menu(self, ctx):
        m, W = self.m, self.W
        self.idle = 0
        self.back_out = False
        self.pkmn_visits = 0
        us, enemy = self.battle_mon('wBattleMon', None), self.enemy()
        here = race(us, enemy, False)
        alts = self.candidates(True)
        if (not self.switched_last and not self.no_switch and not self.trapped() and alts
                and here < 0 and alts[0][0] >= here + 1):
            self.plan = ('switch', alts[0][1])
            m[W('wBattleMenuCursorPosition')] = 2
            self.switched_last = True
            self.actions['switches'] += 1
        else:
            # leave out a Disabled move
            disabled = m[W('wDisabledMove')]
            moves = [0 if mv == disabled else mv for mv in us['moves']]
            _, slot = best_move(us, enemy, moves, us['pp'], us['dvs'])
            status = self.status_move(us, enemy, moves)
            if status is not None:
                slot = status
                name = MOVES[moves[slot]]['name'].lower()
                self.actions[name] = self.actions.get(name, 0) + 1
            if slot is None:
                # no damaging move left: any move with PP (with none, it
                # Struggles)
                slot = next((i for i, mv in enumerate(moves) if mv and us['pp'][i] & 0x3f), 0)
            self.plan = ('fight', slot)
            m[W('wBattleMenuCursorPosition')] = 1
            self.switched_last = False
            self.actions['attacks'] += 1

    def status_move(self, us, enemy, moves):
        """The slot of the status move (or Explosion) to use this turn, or
        None to attack."""
        m, W, w = self.m, self.W, self.word
        slots = {MOVES[mv]['name']: i for i, mv in enumerate(moves)
                 if mv in MOVES and us['pp'][i] & 0x3f}
        bench = self.enemy_bench()
        spikes_down = m[W('wEnemyScreens')] & 1 << SCREENS_SPIKES
        if not self.status_moves:
            if 'SPIKES' in slots and not spikes_down and bench:
                return slots['SPIKES']
            return None
        max_hp = w(W('wBattleMonMaxHP'))
        sleep = m[W('wBattleMonStatus')] & SLP
        enemy_status = m[W('wEnemyMonStatus')]
        enemy_max = w(W('wEnemyMonMaxHP'))
        enemy_sub = m[W('wEnemySubStatus4')] & SUBSTITUTE
        enemy_moves = {MOVES[mv]['name'] for mv in enemy['moves'] if mv in MOVES}
        enemy_asleep = enemy_status & SLP or enemy_status & 1 << CONST['FRZ']
        ours, _ = best_move(us, enemy, moves, us['pp'], us['dvs'])
        theirs, _ = best_move(enemy, us, enemy['moves'], enemy['pp'], enemy['dvs'])
        if enemy_asleep and 'SLEEP_TALK' not in enemy_moves:
            theirs = 0
        our_turns = math.ceil(enemy['hp'] / ours) if ours else 63
        faster = us['stats'][2] > enemy['stats'][2]

        # Asleep: Sleep Talk until the turn it wakes up.
        if sleep:
            return slots.get('SLEEP_TALK') if sleep > 1 else None
        # Low: Rest, if the matchup is good at full HP.
        if 'REST' in slots and (us['hp'] * 5 < max_hp * 2 or theirs >= us['hp']) and \
                us['hp'] < max_hp and race(dict(us, hp=max_hp), enemy, False) >= 0:
            return slots['REST']
        # About to faint: Explosion, if it takes most of the foe's HP.
        if 'EXPLOSION' in slots and theirs >= us['hp'] and not (our_turns == 1 and faster):
            if damage(us, enemy, moves[slots['EXPLOSION']], us['dvs'], boom=True) * 4 >= enemy['hp'] * 3:
                return slots['EXPLOSION']
        # Boosted foe: Roar it out.
        stages = [m[W('wEnemyStatLevels') + k] for k in range(7)]
        if 'ROAR' in slots and bench and sum(max(0, v - 7) for v in stages) >= 2:
            return slots['ROAR']
        # Put a healthy foe to sleep, one at a time (Sleep Clause).
        if 'SLEEP_POWDER' in slots and not enemy_status and not enemy_sub and \
                'SLEEP_TALK' not in enemy_moves and enemy['hp'] * 2 >= enemy_max and \
                not self.enemy_party_asleep():
            return slots['SLEEP_POWDER']
        if 'SPIKES' in slots and not spikes_down and bench:
            return slots['SPIKES']
        # Set up while the foe needs 4+ hits and can't phaze or Haze, until
        # one attack would KO.
        if our_turns > 1 and theirs * 4 < us['hp'] and not enemy_moves & PHAZE_HAZE and \
                not m[W('wPlayerSubStatus5')] & TOXIC:
            levels = [m[W('wPlayerStatLevels') + k] for k in range(7)]
            if 'CURSE' in slots and levels[0] < SETUP_CAP['CURSE'] and TYPES['GHOST'] not in us['types']:
                return slots['CURSE']
            if 'GROWTH' in slots and levels[3] < SETUP_CAP['GROWTH']:
                return slots['GROWTH']
        # Toxic a wall: a healthy foe our attacks take 3+ hits to KO.
        if 'TOXIC' in slots and not enemy_status and not enemy_sub and our_turns >= 3 and \
                not {TYPES['POISON'], TYPES['STEEL']} & set(enemy['types']):
            return slots['TOXIC']
        return None

    def enemy_party_asleep(self):
        m, W = self.m, self.W
        length = W('wOTPartyMon2') - W('wOTPartyMon1')
        return any(m[W('wOTPartyMon1Status') + i * length] & SLP and
                   self.word(W('wOTPartyMon1HP') + i * length)
                   for i in range(m[W('wOTPartyCount')]))

    def on_moves(self, ctx):
        self.idle = 0
        self.back_out = False
        self.no_switch = False
        if self.plan and self.plan[0] == 'fight':
            self.m[self.W('wCurMoveNum')] = self.plan[1]

    def on_pkmn(self, ctx):
        self.idle = 0
        self.pkmn_visits += 1
        if self.plan and self.plan[0] == 'switch' and self.pkmn_visits == 1:
            self.m[self.W('wPartyMenuCursor')] = self.plan[1] + 1
        else:
            # not meant to be here, or the switch failed: cancel, and fight
            # this turn
            self.back_out = True
            self.no_switch = True
            self.switched_last = False

    def on_pick(self, ctx):
        # after a faint (or a shift offer when the enemy's fainted)
        self.idle = 0
        self.back_out = False
        alts = self.candidates(False)
        cur = self.m[self.W('wCurBattleMon')]
        alts = [a for a in alts if a[1] != cur]
        if not alts:
            # only sleeping or frozen ones left: any that can still fight
            alts = [(0, i) for i in range(self.m[self.W('wPartyCount')])
                    if i != cur and self.party_mon(i)['hp']]
        if alts:
            # the party menu has already read wPartyMenuCursor: move its cursor
            self.m[self.W('wPartyMenuCursor')] = alts[0][1] + 1
            self.m[self.W('wMenuCursorY')] = alts[0][1] + 1
            self.actions['replacements'] += 1
        self.switched_last = False

    def button(self):
        self.idle += 1
        if self.idle > 40:
            if self.idle == 41:
                self.actions['watchdog'] += 1
            self.watchdog += 1
            return ('down', 'a', 'b', 'a')[self.watchdog % 4]
        return 'b' if self.back_out else 'a'
