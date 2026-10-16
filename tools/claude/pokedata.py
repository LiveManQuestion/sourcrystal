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
for _name, _n in SPECIES.items():
    _path = os.path.join(ROOT, 'data/pokemon/base_stats', _name.lower() + '.asm')
    if os.path.exists(_path):
        for _line in open(_path):
            _m = re.match(r'\s*db (\w+),\s*(\w+)\s*; type', _line)
            if _m:
                BASE_TYPES[_n] = (TYPES[_m.group(1)], TYPES[_m.group(2)])

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
