"""Shared game data for the Claude tools, parsed from the source.

Use this instead of writing another parser: it follows the const macros
(macros/const.asm) exactly, including const_def's start and increment,
const_skip, const_next and shift_const, which ad hoc parsers got wrong.

    from pokedata import CONST, SPECIES, MOVES, TYPES, CHART, BASE_TYPES
    SPECIES['SNORLAX'] -> 143       species_name(143) -> 'SNORLAX'
    MOVES[move_id] -> {name, effect, power, type, acc, pp}
    effectiveness(TYPES['FIRE'], (TYPES['STEEL'], TYPES['GROUND'])) -> 2
    load_sym('sourcrystal.sym')['wEnemyMonHP'] -> (bank, address)
"""
import math
import os
import re

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..'))


def _number(text, known):
    """Evaluate a const macro argument: a number, a known constant or a
    simple expression of them."""
    text = text.split(';')[0].strip()
    text = re.sub(r'\$([0-9a-fA-F]+)', r'0x\1', text)
    text = re.sub(r'%([01]+)', r'0b\1', text)
    return int(eval(text, {}, dict(known)))


def consts(path):
    """Return {name: value} for every const and shift_const in path (relative
    to the repo root). shift_const NAME gives NAME (the mask) and NAME_F."""
    values = {}
    value, inc = 0, 1
    for line in open(os.path.join(ROOT, path)):
        line = line.split(';')[0]
        m = re.match(r'\s*const_def\b(.*)', line)
        if m:
            args = [a for a in m.group(1).split(',') if a.strip()]
            value = _number(args[0], values) if args else 0
            inc = _number(args[1], values) if len(args) > 1 else 1
            continue
        m = re.match(r'\s*const_skip\b(.*)', line)
        if m:
            value += inc * (_number(m.group(1), values) if m.group(1).strip() else 1)
            continue
        m = re.match(r'\s*const_next\s+(.+)', line)
        if m:
            value = _number(m.group(1), values)
            continue
        m = re.match(r'\s*shift_const\s+(\w+)', line)
        if m:
            values[m.group(1)] = 1 << value
            values[m.group(1) + '_F'] = value
            value += inc
            continue
        m = re.match(r'\s*const\s+(\w+)', line)
        if m:
            values[m.group(1)] = value
            value += inc
            continue
        m = re.match(r'\s*DEF\s+(\w+)\s+EQU\s+(.+)', line)
        if m:
            try:
                values[m.group(1)] = _number(m.group(2), values)
            except Exception:
                pass
    return values


def _reverse(d):
    out = {}
    for name, value in d.items():
        out.setdefault(value, name)
    return out


TYPES = consts('constants/type_constants.asm')
SPECIES = consts('constants/pokemon_constants.asm')
MOVE_IDS = consts('constants/move_constants.asm')
CONST = {}
for _path in ('constants/battle_constants.asm', 'constants/trainer_data_constants.asm',
              'constants/item_constants.asm', 'constants/move_effect_constants.asm'):
    CONST.update(consts(_path))
SPECIES_NAMES = _reverse({k: v for k, v in SPECIES.items() if not k.startswith(('NUM_', 'EGG'))})
MOVE_NAMES = _reverse({k: v for k, v in MOVE_IDS.items() if not k.startswith('NUM_')})
ITEM_NAMES = _reverse(consts('constants/item_constants.asm'))
SPECIAL = TYPES['FIRE']  # types from here on are special


def species_name(n):
    return SPECIES_NAMES.get(n, str(n))


def move_name(n):
    return MOVE_NAMES.get(n, str(n))


MOVES = {}
for _line in open(os.path.join(ROOT, 'data/moves/moves.asm')):
    _m = re.match(r'\s*move (\w+),\s*(\w+),\s*(\d+),\s*(\w+),\s*(\d+),\s*(\d+)', _line)
    if _m:
        MOVES[len(MOVES) + 1] = dict(name=_m.group(1), effect=_m.group(2), power=int(_m.group(3)),
                                     type=TYPES[_m.group(4)], acc=int(_m.group(5)) / 100,
                                     pp=int(_m.group(6)))

CHART = {}
for _line in open(os.path.join(ROOT, 'data/types/type_matchups_table.asm')):
    _m = re.match(r'\s*db (\w+),\s*(\w+),\s*(\w+)', _line)
    if _m and _m.group(1) in TYPES:
        CHART[TYPES[_m.group(1)], TYPES[_m.group(2)]] = {
            'SUPER_EFFECTIVE': 2, 'NOT_VERY_EFFECTIVE': .5, 'NO_EFFECT': 0}[_m.group(3)]


def effectiveness(attack_type, defender_types):
    """Type multiplier (ignoring Foresight), as the game computes it."""
    mult = 1
    for t in set(defender_types):
        mult *= CHART.get((attack_type, t), 1)
    return mult


BASE_TYPES = {}
# [hp, atk, def, spd, sat, sdf] and the GROWTH_* name, by species id
BASE_STATS = {}
GROWTH = {}
for _name, _n in SPECIES.items():
    _path = os.path.join(ROOT, 'data/pokemon/base_stats', _name.lower() + '.asm')
    if os.path.exists(_path):
        for _line in open(_path):
            _m = re.match(r'\s*db (\w+),\s*(\w+)\s*; type', _line)
            if _m:
                BASE_TYPES[_n] = (TYPES[_m.group(1)], TYPES[_m.group(2)])
            _m = re.match(r'\s*db\s+(\d+),\s*(\d+),\s*(\d+),\s*(\d+),\s*(\d+),\s*(\d+)\s*$', _line)
            if _m and _n not in BASE_STATS:
                BASE_STATS[_n] = [int(x) for x in _m.groups()]
            _m = re.match(r'\s*db (GROWTH_\w+)', _line)
            if _m:
                GROWTH[_n] = _m.group(1)


def exp_at_level(species, level):
    """The least exp a Pokemon of species has at level (Gen 2 growth rates)."""
    n = level
    return max(0, int({
        'GROWTH_MEDIUM_FAST': n ** 3,
        'GROWTH_SLIGHTLY_FAST': 3 * n ** 3 / 4 + 10 * n * n - 30,
        'GROWTH_SLIGHTLY_SLOW': 3 * n ** 3 / 4 + 20 * n * n - 70,
        'GROWTH_MEDIUM_SLOW': 6 * n ** 3 / 5 - 15 * n * n + 100 * n - 140,
        'GROWTH_FAST': 4 * n ** 3 / 5,
        'GROWTH_SLOW': 5 * n ** 3 / 4}[GROWTH[species]]))


def calc_stats(species, level, dvs, stat_exp):
    """Gen 2 [max hp, atk, def, spd, sat, sdf] from the two DV bytes and the
    five stat exp words (hp, atk, def, spd, spc), like CalcMonStats."""
    atk, dfn, spd, spc = dvs[0] >> 4, dvs[0] & 15, dvs[1] >> 4, dvs[1] & 15
    hp_dv = (atk & 1) << 3 | (dfn & 1) << 2 | (spd & 1) << 1 | spc & 1
    out = []
    for k, (dv, exp) in enumerate(zip((hp_dv, atk, dfn, spd, spc, spc),
                                      (*stat_exp[:4], stat_exp[4], stat_exp[4]))):
        root = min(255, math.ceil(math.sqrt(exp)))
        stat = ((BASE_STATS[species][k] + dv) * 2 + root // 4) * level // 100
        out.append(stat + (level + 10 if k == 0 else 5))
    return out

HIDDEN_POWER_TYPES = ['FIGHTING', 'FLYING', 'POISON', 'GROUND', 'ROCK', 'BUG', 'GHOST', 'STEEL',
                      'FIRE', 'WATER', 'GRASS', 'ELECTRIC', 'PSYCHIC_TYPE', 'ICE', 'DRAGON', 'DARK']


def hidden_power(atk_def_dv, spd_spc_dv):
    """Vanilla Hidden Power (power, type) from the two DV bytes."""
    ad, ss = atk_def_dv, spd_spc_dv
    top = (ad >> 7 & 1) << 3 | (ad >> 3 & 1) << 2 | (ss >> 7 & 1) << 1 | (ss >> 3 & 1)
    return (top * 5 + (ss & 3)) // 2 + 31, TYPES[HIDDEN_POWER_TYPES[(ad >> 4 & 3) << 2 | (ad & 3)]]


def load_sym(path):
    """{label: (bank, address)} from a .sym file."""
    sym = {}
    for line in open(path):
        if line.startswith(';') or ' ' not in line:
            continue
        loc, name = line.split()[:2]
        if ':' in loc:
            bank, addr = loc.split(':')
            sym[name] = (int(bank, 16), int(addr, 16))
    return sym


def label_at(sym, bank, addr):
    """The label at or before bank:addr, as 'Label+0x12', for addresses
    sampled from the CPU (bank is ignored below $4000)."""
    best = None
    for name, (b, a) in sym.items():
        if (b == bank or addr < 0x4000 and b == 0) and a <= addr and (best is None or a > best[1]):
            best = (name, a)
    return f'{best[0]}+{addr - best[1]:#x}' if best else hex(addr)
