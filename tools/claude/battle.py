"""Headless Challenge Mode battle test against Smogon-AI trainers (PyBoy).
usage: battle.py [--smart] ROM SYM SAVE TRAINER(e.g. "BUGSY 2") SEED [max_frames] [end_screenshot.png]

Plays one battle with battle_harness.py (see there for the setup and the two
players: an unkillable Typhlosion pressing random buttons, or with --smart
the save's own party played by smart_player.py, so win rates mean
something). Prints one JSON line with the harness's result, how often each
hooked AI routine ran, and every enemy switch-in ("switches"; summarize with
switch_report.py). Needs battle_scripts.json from make_battle_scripts.py."""
import json
import sys

from battle_harness import Battle

SMART = '--smart' in sys.argv
argv = [a for a in sys.argv if a != '--smart']
rom, symf, save, trainer, seed = argv[1:6]
max_frames = int(argv[6]) if len(argv) > 6 else 60 * 60 * 12

battle = Battle(rom, symf, save, trainer, seed, smart=SMART)
add_log = battle.log_switches()
battle.start()
result = battle.run(max_frames)
result = add_log(result)
print(json.dumps(result))
if len(argv) > 7:
    battle.screenshot(argv[7])
battle.stop()
