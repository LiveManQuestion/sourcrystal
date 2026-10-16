# Claude tools (`tools/claude/`)

Scripts for checking changes without an emulator UI (see also `CLAUDE.md`).

Vanilla comparison (no emulator):
- `build_vanilla.sh`: prints the vanilla ROM and .sym paths:
  `pokecrystal-master/pokecrystal.gbc` (built there with `make crystal`), or a
  build into `.vanilla/` (git-ignored) if that's missing.
- `cmp_data.py [ROM SYM]`: every battle data table vs. vanilla, byte for byte.
  Expect `ALL IDENTICAL`.
- `vanilla_diff.py [-s] FILE...`: diff vs. `pokecrystal-master/` minus noise
  (renames, jr/jp, quotes, tail calls), grouped by function.
- `replace_region.py FILE SOURCE START END`: replace a block of top-level
  labels with the same block from another file or `REV:path`.

Headless tests (PyBoy, installed as a uv tool:
`~/.local/share/uv/tools/pyboy/bin/python`). The user's real save is
`sourcrystal.sav`; its first 32 KB is the cartridge RAM
(`head -c 32768 sourcrystal.sav > SCRATCH/user.ram`). Never write over the
user's save files.
- `ai_scenarios.py ROM SYM RAM`: exact-state checks of AI_Smogon's scores, the
  heal-move multiplier the engine picks, the switch-in choice by type
  (`switch_cases`) and the power AIGetEnemyMove loads (`hp_cases`). Restarts
  itself if the test battle ends; last line `RESULT: ALL OK`. Add cases there.
  `AI_Smogon` is far-called: match the stack pointer, not just the address,
  when hooking a return.
- `damage_diff.py VANILLA.gbc VANILLA.sym ROM.gbc ROM.sym [N]`: runs the damage
  code on the same random inputs in both ROMs. Expect 0 mismatches.
- `smoke.py ROM RAM OUTDIR`: boot, title, Continue, overworld and menus, with
  a screenshot hash per step; diff two ROMs' output (the clock changes some).
  PyBoy draws Bill's PC as a white screen; test it through RAM.
- `battle.py [--smart] ROM SYM RAM "BUGSY 2" SEED [frames]`: one Challenge
  Mode battle against a Smogon-AI trainer. JSON line with crashes, AI routine
  counts, the enemy's moves and every enemy switch-in. Run
  `make_battle_scripts.py` first. An injected battle needs `winlosstext`.
  - Default player: an unkillable Typhlosion (Tackle, Swords Dance, Roar,
    Toxic) pressing random buttons. Good for crashes and stalls, not for win
    rates.
  - `--smart` (`smart_player.py`): the save's own party, healed at the start
    and never again, played by a greedy policy: the strongest attack by the
    damage formula, a switch when a teammate wins the KO race clearly better,
    the best replacement after a faint. It sees the enemy's moves but uses no
    status moves. It drives the menus by writing their cursor variables from
    hooks; a watchdog gets it out of unexpected menus. `player_actions` in the
    JSON counts its attacks, switches, replacements, watchdog triggers and
    hook errors (should be 0; PyBoy swallows exceptions in hooks).
- `battle_matrix.sh OUTDIR RAM ROM1 [ROM2]` (`SEEDS=6`, `TRAINERS=...`,
  `PLAYER=smart` for `--smart`): 9
  trainers × 6 seeds, ~15 min per ROM; give the two ROMs different file
  names. Summaries: `battle_summary.py`, `battle_compare.py OLD NEW` (per
  trainer), `switch_report.py` (switch quality vs. Fire). Timeouts on
  Jasmine/Koga are normal (stall battles; the harness heals the player and
  Roars). Crashes are not. Any code change shifts the RNG timing, so judge
  win rates over many seeds.
- `storage_test.py ROM SYM RAM [SEED] [STEPS]`: model-based test of the PC
  boxes (moves, saves, resets, interrupted saves). Last line `RESULT: OK`.
  `game_call.py` calls ROM functions from Python.

`stadium2/` runs Pokémon Stadium 2 in mupen64plus (`docs/stadium2.md`).

`peephole.py` applies the pret wiki's "Optimizing assembly code" peepholes
(skipping timing-sensitive, RAM-copied, link and printer code); then run
`fix_jr.sh` until all four ROMs build. Already applied in 342bbfb61.
