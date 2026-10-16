# Claude tools (`tools/claude/`)

Scripts for checking changes without an emulator UI (see also `CLAUDE.md`).

Building and data:
- `build_rev.sh REV OUT [TARGET]`: build any commit (TARGET `sour`, `gbtower`,
  `debug` or `vc`) into `OUT.gbc`, `OUT.sym` and `OUT.map`, to compare it with
  the working tree. Uses a temporary worktree with the git-ignored prebuilt
  `tools/superfamiconv` linked in; results are cached by commit hash in
  `.revbuild/` (git-ignored), so a second build is instant.
- `pokedata.py`: the game's constants and data parsed from the source, for
  every Python tool: `CONST`, `SPECIES`, `MOVE_IDS`, `MOVES` (name, effect,
  power, type, accuracy, PP), `TYPES`, `CHART`, `BASE_TYPES`,
  `effectiveness()`, `hidden_power()`, `species_name()`, `move_name()`,
  `load_sym()`, `label_at()`. It follows `macros/const.asm` exactly
  (`const_skip`, `const_next`, `shift_const`'s `_F` bits): use it instead of
  another ad hoc parser.

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
- `battle_harness.py`: the battle setup shared by `battle.py`, `ai_trace.py`
  and `ai_profile.py` (`Battle(...)`, `.on(label, fn)`, `.start()`,
  `.run(frames)`). `.on()` lets several callbacks share a label: PyBoy allows
  one hook per address and raises "Hook already registered" otherwise.
- `battle.py [--smart] ROM SYM RAM "BUGSY 2" SEED [frames]`: one Challenge
  Mode battle against a Smogon-AI trainer. JSON line with crashes, AI routine
  counts, the enemy's moves, every enemy switch-in, and `player_left` /
  `enemy_left` (Pokemon with HP left at the end: finer than win/loss). Run
  `make_battle_scripts.py` first (add trainers to its list). An injected
  battle needs `winlosstext`.
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
  `PLAYER=smart` for `--smart`): 9 trainers × 6 seeds, ~15 min per ROM; give
  the two ROMs different file names. Summaries: `battle_summary.py`,
  `battle_compare.py OLD NEW` (per trainer, with z: the change in standard
  deviations; below 2 is noise), `switch_report.py` (switch quality vs. Fire,
  random player only). With the random player, timeouts on Jasmine/Koga are
  normal (stall battles; the harness heals the player and Roars); crashes are
  not. Any code change shifts the RNG timing, so results always move a
  little.
  - To judge AI strength: `PLAYER=smart` on the trainers that can beat the
    user's level 76-78 party (`TRAINERS="KOGA 2|MISTY 2|WHITNEY 2|JASMINE 2"`;
    the others never win, so they give no signal), with 48+ seeds, compared
    against `build_rev.sh` of the last commit.
- `ai_trace.py run ROM SYM RAM TRAINER SEED [--random]`: every `SwitchSmogon`
  decision (its branch labels, scores, the move picked, both sides' state),
  every switch-in candidate's score with its attack lists and healing blocks,
  and every enemy switch-in, as one JSON line. `ai_trace.py report
  TRACES...`: switches, replacements, each candidate's average score against
  each player Pokemon, and stay-ins that an independent damage race
  (`smart_player.race`) calls clearly wrong.
- `ai_profile.py ROM SYM RAM TRAINER SEED [SPAN...]`: time AI code in
  scanlines (154 per frame): by default the switch decision, the switch-in
  search and the parts of a matchup score; `START:END1|END2=name` for others.
  A switch decision should stay within about 8 frames.
- `storage_test.py ROM SYM RAM [SEED] [STEPS]`: model-based test of the PC
  boxes (moves, saves, resets, interrupted saves). Last line `RESULT: OK`.
  `game_call.py` calls ROM functions from Python.

`stadium2/` runs Pokémon Stadium 2 in mupen64plus (`docs/stadium2.md`).

`peephole.py` applies the pret wiki's "Optimizing assembly code" peepholes
(skipping timing-sensitive, RAM-copied, link and printer code); then run
`fix_jr.sh` until all four ROMs build. Already applied in 342bbfb61.
