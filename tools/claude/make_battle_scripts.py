"""Assemble the event scripts battle.py injects, using the project's macros:
one for every party of every SWITCH_SMOGON trainer class.
usage (from the repo root): python3 tools/claude/make_battle_scripts.py"""
import json, os, re, subprocess, tempfile

here = os.path.dirname(os.path.abspath(__file__))


def smogon_parties():
    """(class, party number, top level) of every party of the SWITCH_SMOGON
    classes, from data/trainers/attributes.asm and parties.asm (the level is
    the Challenge Mode party's, when the party has one)."""
    key = lambda name: name.replace(' ', '').replace('_', '').lower()
    smogon, cls = set(), None
    for line in open('data/trainers/attributes.asm'):
        m = re.match(r'^; (.+)$', line)
        if m:
            cls = key(m.group(1))
        elif 'SWITCH_SMOGON' in line:
            smogon.add(cls)
    out, group, levels = [], None, None
    for line in open('data/trainers/parties.asm'):
        m = re.match(r'^(\w+)Group:', line)
        if m:
            group = key(m.group(1))
        m = re.match(r'\s*; (\w+) \((\d+)\)', line)
        if m and group in smogon:
            levels = {'normal': [], 'challenge': []}
            mode = 'normal'
            out.append((m.group(1), int(m.group(2)), levels))
        elif m:
            levels = None
        if levels is not None:
            if 'Challenge Mode' in line:
                mode = 'challenge'
            m = re.match(r'\s*db\s+(\d+),\s*[A-Z]', line)
            if m:
                levels[mode].append(int(m.group(1)))
    return [(cls, i, max(lv['challenge'] or lv['normal'])) for cls, i, lv in out]


TRAINERS = smogon_parties()
out, top_levels = {}, {}
with tempfile.TemporaryDirectory() as tmp:
    for cls, i, level in TRAINERS:
        # 8 constant bytes battle.py needs, then the script at $cfe2.
        # winlosstext is required: without it, winning prints a stale pointer and crashes.
        open(f'{tmp}/t.asm', 'w').write(f'''SECTION "t", ROM0[0]
	db TACKLE, SWORDS_DANCE, ROAR, TOXIC, HAZE, REFLECT, CYNDAQUIL, TYPHLOSION
LOAD "s", WRAM0[$cfe2]
Script:
	winlosstext .Text, .Text
	loadtrainer {cls}, {i}
	startbattle
	reloadmapafterbattle
	end
.Text:
	text "OK"
	done
ENDL
''')
        subprocess.run(['rgbasm', '-Q8', '-P', 'includes.asm', '-Wno-obsolete', '-o', f'{tmp}/t.o', f'{tmp}/t.asm'], check=True)
        subprocess.run(['rgblink', '-x', '-o', f'{tmp}/t.bin', f'{tmp}/t.o'], check=True)
        out[f'{cls} {i}'] = list(open(f'{tmp}/t.bin', 'rb').read()[:8 + 30])
        top_levels[f'{cls} {i}'] = level
json.dump(out, open(os.path.join(here, 'battle_scripts.json'), 'w'))
# for PLAYER_LEVEL=match (battle_harness.py)
json.dump(top_levels, open(os.path.join(here, 'battle_levels.json'), 'w'))
print('wrote', len(out), 'scripts')
