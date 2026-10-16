#!/usr/bin/env python3
"""Generate the Smogon AI's per-species data from GSC OU sources.

Writes data/battle/ai/smogon_traits.asm (SmogonTraits) and
data/battle/ai/smogon_attacks.asm (SmogonExpectedAttacks).

Sources (in smogonairesources/, untracked):
- "GSC OU Stats Master.xlsx": Siatam's spreadsheet of Smogtours GSC OU
  replays, with the moves each Pokemon revealed.
- smogon_dex_gs.json: the Smogon GSC dex analyses (OU, UUBL, UU and Uber
  sets), fetched from https://www.smogon.com/dex/gs/pokemon/<name>/ (the
  dump-pokemon "strategies" of each page's dexSettings JSON). Used for
  Hidden Power types and for Pokemon with too few replays.

SMOGON_THREAT is a judgment call, so it's kept from the existing traits file.

Usage: uv run --with openpyxl python3 tools/claude/smogon_data.py
"""

import collections
import json
import re
import sys
from pathlib import Path

import openpyxl

ROOT = Path(__file__).resolve().parents[2]
XLSX = ROOT / 'smogonairesources' / 'GSC OU Stats Master.xlsx'
DEX = ROOT / 'smogonairesources' / 'smogon_dex_gs.json'
TRAITS = ROOT / 'data' / 'battle' / 'ai' / 'smogon_traits.asm'
ATTACKS = ROOT / 'data' / 'battle' / 'ai' / 'smogon_attacks.asm'

SLEEP_TALK_MIN = 0.20
REST_MIN = 0.30
PHAZER_MIN = 0.25
SETUP_MIN = 0.35
EXPLODE_MIN = 0.25
PURSUIT_MIN = 0.25
SLEEP_MIN = 0.30
ATTACK_MIN = 0.20     # an attack type expected on this share of sets
ATTACK_MIN_POWER = 50 # weaker attacks only count if there's nothing else
MAX_ATTACKS = 4
MIN_REPLAY_SETS = 100 # fewer revealed sets than this: use the dex instead
MIN_TRAIT_SETS = 50   # revealed sets needed for the replay-based traits
HIDDEN_POWER_POWER = 70

SETUP_MOVES = {'Curse', 'Growth', 'Swords Dance', 'Belly Drum', 'Agility',
               'Acid Armor', 'Barrier', 'Amnesia', 'Meditate', 'Sharpen'}
SLEEP_MOVES = {'Spore', 'Sleep Powder', 'Lovely Kiss', 'Hypnosis', 'Sing'}
SKIP_ATTACKS = {'Explosion', 'Self-Destruct', 'Selfdestruct', 'Thief',
                'Rapid Spin', 'Flail', 'Reversal', 'Present', 'Dream Eater',
                'Super Fang', 'Psywave', 'Counter', 'Mirror Coat', 'Bide'}
POWER_OVERRIDES = {'Return': 102, 'Frustration': 102, 'Magnitude': 71}


def const_name(name):
    name = {'Nidoran-F': 'NIDORAN_F', 'Nidoran-M': 'NIDORAN_M',
            'Mr. Mime': 'MR__MIME', "Farfetch'd": 'FARFETCH_D',
            'Ho-Oh': 'HO_OH', 'Self-Destruct': 'SELFDESTRUCT',
            'Double-Edge': 'DOUBLE_EDGE', 'Soft-Boiled': 'SOFTBOILED'}.get(name, name)
    return re.sub(r'[^A-Z0-9_]', '', name.upper().replace(' ', '_').replace('-', '_'))


def read_species():
    species = []
    for line in open(ROOT / 'constants' / 'pokemon_constants.asm'):
        m = re.match(r'\s*const (\w+)\s*; ([0-9a-f]{2})$', line)
        if m and int(m.group(2), 16) == len(species) + 1:
            species.append(m.group(1))
        if len(species) == 251:
            break
    return species


def read_moves():
    moves = {}
    for line in open(ROOT / 'data' / 'moves' / 'moves.asm'):
        m = re.match(r'\s*move (\w+),\s*(\w+),\s*(\d+),\s*(\w+),', line)
        if m:
            moves[m.group(1)] = (m.group(2), int(m.group(3)), m.group(4))
    return moves


def move_const(name, moves):
    c = const_name(name)
    for cand in (c, c.replace('_', ''), {'PSYCHIC': 'PSYCHIC_M'}.get(c, c)):
        if cand in moves:
            return cand
    if c == 'DYNAMIC_PUNCH':
        return 'DYNAMICPUNCH'
    for k in moves:
        if k.replace('_', '') == c.replace('_', ''):
            return k
    raise KeyError(name)


def type_const(name):
    return {'Psychic': 'PSYCHIC_TYPE'}.get(name, name.upper())


def replay_stats():
    wb = openpyxl.load_workbook(XLSX, read_only=True)
    rows = wb['Raw (Hidden)'].iter_rows(values_only=True)
    header = next(rows)
    moveset_cols = [i for i, h in enumerate(header) if h and str(h).startswith('Moveset')]
    mon_cols = [i for i, h in enumerate(header) if h and re.fullmatch(r'Mon \d', str(h))]
    teams = 0
    appear = collections.Counter()
    revealed = collections.Counter()
    moves = collections.defaultdict(collections.Counter)
    for r in rows:
        if not r[0]:
            continue
        teams += 1
        for i in mon_cols:
            if r[i]:
                appear[r[i]] += 1
        for i in moveset_cols:
            if not r[i] or ';' not in r[i]:
                continue
            mon, ms = r[i].split(';', 1)
            ms = {m.strip() for m in ms.split(',') if m.strip()}
            if ms:
                revealed[mon] += 1
                for m in ms:
                    moves[mon][m] += 1
    return {mon: {'usage': appear[mon] / teams, 'sets': revealed[mon],
                  'moves': {m: c / revealed[mon] for m, c in moves[mon].items()}}
            for mon in appear}


def dex_stats(dex):
    """Per Pokemon: move shares over its sets in its main format, and the
    Hidden Power types its sets list."""
    out = {}
    for mon, v in dex.items():
        strategies = {s['format']: s for s in v['strategies']}
        for fmt in ('OU', 'UUBL', 'UU', 'Uber'):
            if fmt in strategies and strategies[fmt]['movesets']:
                break
        else:
            continue
        sets = strategies[fmt]['movesets']
        shares = collections.Counter()
        hp_types = collections.Counter()
        for ms in sets:
            seen = collections.Counter()
            for slot in ms['moveslots']:
                for x in slot:
                    seen[x['move']] += 1 / len(slot)
                    if x['move'] == 'Hidden Power' and x.get('type'):
                        hp_types[x['type']] += 1 / len(slot)
            for m, w in seen.items():
                shares[m] += min(w, 1) / len(sets)
        out[mon] = {'format': fmt, 'moves': dict(shares), 'hp_types': hp_types}
    return out


def expected_attacks(move_shares, hp_types, moves):
    """Return [(type, power)] of the attacks expected on this Pokemon."""
    by_type = {}
    fallback = None
    for name, share in sorted(move_shares.items(), key=lambda x: -x[1]):
        if name in SKIP_ATTACKS:
            continue
        try:
            effect, power, mtype = moves[move_const(name, moves)]
        except KeyError:
            continue
        power = POWER_OVERRIDES.get(name, power)
        if power == 0:
            continue
        if name == 'Hidden Power':
            total = sum(hp_types.values())
            if not total:
                continue
            for t, w in hp_types.items():
                entry = by_type.setdefault(type_const(t), [0, HIDDEN_POWER_POWER])
                # Each listed type could be the one, so count the whole share.
                entry[0] += share
            continue
        if fallback is None and share >= ATTACK_MIN:
            fallback = (mtype, power)
        if 1 < power < ATTACK_MIN_POWER:
            continue
        entry = by_type.setdefault(mtype, [0, power])
        entry[0] += share
    picked = sorted(((s, t, p) for t, (s, p) in by_type.items() if s >= ATTACK_MIN),
                    key=lambda x: -x[0])[:MAX_ATTACKS]
    if not picked and fallback:
        return [fallback]
    return [(t, p) for s, t, p in picked]


def main():
    species = read_species()
    moves = read_moves()
    stats = replay_stats()
    dex = dex_stats(json.load(open(DEX)))

    old_threat = set()
    for line in open(TRAITS):
        m = re.match(r'\s*db (.*?);\s*(\w+)', line)
        if m and 'SMOGON_THREAT' in m.group(1):
            old_threat.add(m.group(2))

    traits_lines = []
    attack_lines = []
    for const in species:
        name = next((n for n in list(stats) + list(dex) if const_name(n) == const), None)
        st = stats.get(name)
        dx = dex.get(name)
        if st and st['sets'] >= MIN_REPLAY_SETS:
            shares, source = st['moves'], 'replays'
        elif dx:
            shares, source = dx['moves'], 'dex ' + dx['format']
        else:
            shares, source = None, None

        flags = []
        if st and st['sets'] >= MIN_TRAIT_SETS:
            s = st['moves'].get
            if s('Sleep Talk', 0) >= SLEEP_TALK_MIN: flags.append('SMOGON_SLEEP_TALK')
            if s('Rest', 0) >= REST_MIN: flags.append('SMOGON_REST')
            if s('Roar', 0) + s('Whirlwind', 0) >= PHAZER_MIN: flags.append('SMOGON_PHAZER')
            if sum(s(m, 0) for m in SETUP_MOVES) >= SETUP_MIN: flags.append('SMOGON_SETUP')
        if const in old_threat:
            flags.append('SMOGON_THREAT')
        if shares:
            s = shares.get
            if s('Explosion', 0) + s('Self-Destruct', 0) + s('Selfdestruct', 0) >= EXPLODE_MIN:
                flags.append('SMOGON_EXPLODER')
            if s('Pursuit', 0) >= PURSUIT_MIN: flags.append('SMOGON_PURSUIT')
            if sum(s(m, 0) for m in SLEEP_MOVES) >= SLEEP_MIN: flags.append('SMOGON_SLEEPER')

        comment = const
        if st:
            comment += f' ({st["usage"] * 100:.1f}% usage)'
        traits_lines.append(f'\tdb {" | ".join(flags) or "0":<66} ; {comment}\n')

        if shares:
            hp = dx['hp_types'] if dx else {}
            attacks = expected_attacks(shares, hp, moves)
            body = ''.join(f'{t}, {p}, ' for t, p in attacks)
            attack_lines.append(f'\tdb {const}\n\tdb {body}-1 ; {source}\n')

    with open(TRAITS, 'w') as f:
        f.write(f'''\
; Per-species tendencies of GSC OU sets, used by AI_Smogon as a prior when the
; player hasn't revealed the relevant move yet. Generated by
; tools/claude/smogon_data.py from 41k Smogtours GSC OU replays (Siatam's GSC
; OU Stats Master, data up to 2 October 2026) and the Smogon GSC dex.
;   SMOGON_SLEEP_TALK: Sleep Talk on >= {SLEEP_TALK_MIN:.0%} of revealed sets
;   SMOGON_REST:       Rest on >= {REST_MIN:.0%} of revealed sets
;   SMOGON_PHAZER:     Roar or Whirlwind on >= {PHAZER_MIN:.0%} of revealed sets
;   SMOGON_SETUP:      a boosting move (Curse, Growth, Swords Dance, ...) on >= {SETUP_MIN:.0%}
;   SMOGON_THREAT:     common (>= 3% usage) win condition or wall that is a good
;                      Explosion target (not Rock, Steel or Ghost)
;   SMOGON_EXPLODER:   Explosion or Selfdestruct on >= {EXPLODE_MIN:.0%} of sets
;   SMOGON_PURSUIT:    Pursuit on >= {PURSUIT_MIN:.0%} of sets
;   SMOGON_SLEEPER:    a sleep move on >= {SLEEP_MIN:.0%} of sets
; The first four need {MIN_TRAIT_SETS} revealed sets in the replays; the last three
; use the dex sets for Pokemon with fewer than {MIN_REPLAY_SETS}.

SmogonTraits:
	table_width 1
''')
        f.writelines(traits_lines)
        f.write('\tassert_table_length NUM_POKEMON\n')

    with open(ATTACKS, 'w') as f:
        f.write(f'''\
; The attacks a GSC OU player expects each Pokemon to have, used by the Smogon
; AI's matchups (AISmogon_ScoreMatchup) for moves the player hasn't revealed.
; Pokemon not listed are assumed to have strong attacks of both their types;
; Pokemon listed without attacks rarely have a strong one.
; Generated by tools/claude/smogon_data.py: attack types on >= {ATTACK_MIN:.0%} of the
; revealed sets in 41k Smogtours GSC OU replays (or of the Smogon GSC dex sets
; for Pokemon with fewer than {MIN_REPLAY_SETS} sets), at most {MAX_ATTACKS}, with the power
; of the most common one. Hidden Power counts as {HIDDEN_POWER_POWER} power of each type the dex
; sets give it.
; Entries: species, then type and power pairs, then -1.

SmogonExpectedAttacks:
''')
        f.writelines(attack_lines)
        f.write('\tdb 0 ; end\n')


if __name__ == '__main__':
    sys.exit(main())
