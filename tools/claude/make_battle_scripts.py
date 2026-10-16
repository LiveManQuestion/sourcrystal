"""Assemble the event scripts battle.py injects, using the project's macros.
usage (from the repo root): python3 tools/claude/make_battle_scripts.py"""
import json, os, subprocess, tempfile

here = os.path.dirname(os.path.abspath(__file__))
TRAINERS = [("BUGSY", 2), ("JASMINE", 2), ("KOGA", 1), ("KOGA", 2), ("BROCK", 2),
            ("MISTY", 2), ("SABRINA", 1), ("FALKNER", 2), ("RIVAL2", 1),
            ("WHITNEY", 2)]
out = {}
with tempfile.TemporaryDirectory() as tmp:
    for cls, i in TRAINERS:
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
json.dump(out, open(os.path.join(here, 'battle_scripts.json'), 'w'))
print('wrote', len(out), 'scripts')
