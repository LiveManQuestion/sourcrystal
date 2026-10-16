"""A strong greedy player for battle.py --smart.

Plays the save's own party, with no healing:
- attacks with the move that does the most expected damage (Gen 2 damage
  formula with the real stats and stat changes, STAB, type, accuracy, Hidden
  Power's real type; two-turn moves count half, Explosion and Counter are
  left out),
- switches when a healthy party member wins the KO race against the enemy's
  active Pokemon at least twice as well as the active one, after taking a
  hit on the way in (and not two turns in a row),
- after a faint, sends in the party member with the best KO race.
It sees the enemy's actual moves, so it's a strong benchmark, stronger than a
human who only knows the revealed moves.

It drives the menus through hooks: at the start of BattleMenu,
MoveSelectionScreen, BattleMenuPKMN_Loop and PickPartyMonInBattle it writes
the cursor variable the menu is about to read, then presses A. It backs out
of the party menu with B when it didn't mean to be there or a switch failed,
and a watchdog cycles down/A/B/A when no hook has fired for a while, so an
unexpected menu can't stall a battle (counted in actions['watchdog'])."""
import math, os, re

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..')


def consts(path):
    d = {}
    i = 0
    for line in open(os.path.join(ROOT, path)):
        m = re.match(r'\s*const_def\s*(-?\d*)', line)
        if m:
            i = int(m.group(1) or 0)
            continue
        m = re.match(r'\s*const_next\s*(\d+)', line)
        if m:
            i = int(m.group(1))
            continue
        if re.match(r'\s*const_skip', line):
            i += 1
            continue
        m = re.match(r'\s*const (\w+)', line)
        if m:
            d[m.group(1)] = i
            i += 1
    return d


TYPES = consts('constants/type_constants.asm')
SPECIES = consts('constants/pokemon_constants.asm')
SPECIAL = TYPES['FIRE']
MOVES = {}
for line in open(os.path.join(ROOT, 'data/moves/moves.asm')):
    m = re.match(r'\s*move (\w+),\s*(\w+),\s*(\d+),\s*(\w+),\s*(\d+),\s*(\d+)', line)
    if m:
        MOVES[len(MOVES) + 1] = dict(name=m.group(1), effect=m.group(2), power=int(m.group(3)),
                                     type=TYPES[m.group(4)], acc=int(m.group(5)) / 100,
                                     pp=int(m.group(6)))
CHART = {}
for line in open(os.path.join(ROOT, 'data/types/type_matchups_table.asm')):
    m = re.match(r'\s*db (\w+),\s*(\w+),\s*(\w+)', line)
    if m and m.group(1) in TYPES:
        CHART[TYPES[m.group(1)], TYPES[m.group(2)]] = {
            'SUPER_EFFECTIVE': 2, 'NOT_VERY_EFFECTIVE': .5, 'NO_EFFECT': 0}[m.group(3)]
BASE_TYPES = {}
for name, n in SPECIES.items():
    path = os.path.join(ROOT, 'data/pokemon/base_stats', name.lower() + '.asm')
    if os.path.exists(path):
        for line in open(path):
            m = re.match(r'\s*db (\w+),\s*(\w+)\s*; type', line)
            if m:
                BASE_TYPES[n] = (TYPES[m.group(1)], TYPES[m.group(2)])
HP_TYPES = ['FIGHTING', 'FLYING', 'POISON', 'GROUND', 'ROCK', 'BUG', 'GHOST', 'STEEL',
            'FIRE', 'WATER', 'GRASS', 'ELECTRIC', 'PSYCHIC_TYPE', 'ICE', 'DRAGON', 'DARK']
SKIP = {'EFFECT_SELFDESTRUCT', 'EFFECT_COUNTER', 'EFFECT_MIRROR_COAT'}
CANT_RUN = consts('constants/battle_constants.asm')['SUBSTATUS_CANT_RUN']
TWO_TURN = {'EFFECT_RAZOR_WIND', 'EFFECT_SKY_ATTACK', 'EFFECT_SKULL_BASH', 'EFFECT_SOLARBEAM',
            'EFFECT_HYPER_BEAM'}


def stage(s):
    return (2 + max(0, s - 7)) / (2 + max(0, 7 - s))


def damage(att, dfn, move, dvs):
    """Expected damage of move (id) from att on dfn: dicts with level, types,
    stats [atk, def, spd, sat, sdf] (with stat changes applied)."""
    mv = MOVES.get(move)
    if not mv or mv['effect'] in SKIP:
        return 0
    power, typ = mv['power'], mv['type']
    if mv['name'] == 'HIDDEN_POWER':
        ad, ss = dvs
        top = (ad >> 7 & 1) << 3 | (ad >> 3 & 1) << 2 | (ss >> 7 & 1) << 1 | (ss >> 3 & 1)
        power = (top * 5 + (ss & 3)) // 2 + 31
        typ = TYPES[HP_TYPES[(ad >> 4 & 3) << 2 | (ad & 3)]]
    elif mv['name'] in ('RETURN', 'FRUSTRATION'):
        power = 102
    elif mv['name'] == 'MAGNITUDE':
        power = 71
    if power == 0:
        return 0
    eff = 1
    for t in set(dfn['types']):
        eff *= CHART.get((typ, t), 1)
    if eff == 0:
        return 0
    if power == 1:
        return att['level'] * mv['acc']
    a, d = (att['stats'][3], dfn['stats'][4]) if typ >= SPECIAL else (att['stats'][0], dfn['stats'][1])
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
    def __init__(self, pb, sym):
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
                        'errors': 0}
        for name, cb in (('BattleMenu', self.on_menu), ('MoveSelectionScreen', self.on_moves),
                         ('BattleMenuPKMN_Loop', self.on_pkmn), ('PickPartyMonInBattle', self.on_pick)):
            pb.hook_register(*sym[name], self.guarded(cb), None)

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
            if slot is None:
                # no damaging move left: any move with PP (with none, it
                # Struggles)
                slot = next((i for i, mv in enumerate(moves) if mv and us['pp'][i] & 0x3f), 0)
            self.plan = ('fight', slot)
            m[W('wBattleMenuCursorPosition')] = 1
            self.switched_last = False
            self.actions['attacks'] += 1

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
