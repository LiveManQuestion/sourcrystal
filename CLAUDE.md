# Sour Crystal: notes for Claude

A Pokémon Crystal ROM hack built on the pret/pokecrystal disassembly (see
README.md for features). The Game Boy Z80-like assembly is built with RGBDS.
STYLE.md is the code style guide: tabs, comments above the code they describe,
PascalCase ROM labels, `.local` labels. `pokecrystal-master/` (untracked) is a
copy of vanilla pret/pokecrystal for reference. Session history:
`docs/claude_changelog.md` (add an entry there for notable changes).

## Keeping this file current

This file describes how things are now; history goes in
`docs/claude_changelog.md`. When a change makes something here wrong (a
renamed label or file, a moved function, a changed mechanic or tool), fix or
delete that line in the same commit. Keep this file under about 10 KB: past
that, move detail into `docs/` and leave a one-line pointer here.

## Hard constraints

- **Stay link compatible with unmodified Pokémon Crystal and the Time Capsule
  (Gen 1).** Don't change move, item or species IDs, party/box struct layouts,
  link data, mail, or anything under `engine/link/`, `home/serial.asm`, or
  `engine/printer/`. The battle AI must never run in link battles (check
  `wLinkMode`). Syntax-only edits there (like the RGBDS 1.0 character
  literals) are fine if all four ROMs, `.sym` and `.map` files stay identical.
- **Don't break existing saves.** Don't move or resize saved WRAM/SRAM
  (`wPlayerData`, `wPokemonData`, boxes...). Save layout changes need
  `save_compat.asm` / `save_migrations/`. Battle-only WRAM is safe to use.
- **Battles play exactly like vanilla Crystal (GSC on Smogon), bugs
  included.** Anything that can matter in a link battle stays vanilla; don't
  reintroduce Sour Crystal's old battle mechanics or battle bug fixes.
  Single-player-only fixes and features are kept (see Current state).
- **Pokémon Stadium 2 compatible** (see `docs/stadium2.md`): keep vanilla's
  box layout and the Pokémon Center map IDs on its list (the `UNUSED_*_MAP`
  placeholders hold some).
- Don't commit or push unless the user asks.

## Build

- `make -j16 sour` builds `sourcrystal.gbc`. `make -j16 all` also builds the
  GBTower, debug and VC (`.patch`) variants. Build all four before committing:
  code under `IF DEF(_DEBUG)` etc. differs between them.
- RGBDS 1.0.4. The build prints no assembler warnings, so any warning is new.
  Use character literals (`cp '@'`, `'<BOLD_V>'`) for characters as numbers,
  and `STRSLICE`/`STRFIND`/`STRCHAR`, not the deprecated forms.
- Incremental builds can hide errors in files that weren't rebuilt: after
  editing macros, `make clean` first.
- `layout.link` pins some sections to banks. Unpinned (floating) sections get
  placed wherever they fit, so a "full" bank in the `.map` file is often just
  filled with floating text that can move elsewhere.
- Free space: `grep -E "^ROMX? bank|TOTAL EMPTY" sourcrystal.map`. To see what
  a change cost per section, run `python3 tools/claude/space.py old.map new.map`.
- `rgblink` reports out-of-range `jr` at link time for forward references,
  with `file(line)` locations. Fix by using `jp`.

## Shell gotcha

The Bash tool's shell doesn't word-split unquoted variables (zsh-like), so
`for x in $list` and `cmd $args` get ONE argument. Put loops that need
splitting in a `bash script.sh` or in Python.

## Current state

- **Battle engine**: `effect_commands.asm`, `move_effects/` and all battle data
  (moves, effects, type order: Ghost physical, Dark/Dragon special, Gen 2 base
  stats, held items, crit moves, priorities) match vanilla. Check with
  `cmp_data.py` and `damage_diff.py`. Remaining differences are cosmetic
  (animations, delays), single-player, or AI-only:
  - Kept single-player code: exp (Exp. Share split, catch exp), catching and
    ball fixes, wild held items and flee list, Magikarp length, items stolen
    by foes returned (`wPartyBackupItems`, `ConsumeUserItem`), Pursuit faint
    status, Glacier Badge and max HP < 4 fixes, Safari battles, overworld
    weather starting battle weather, Challenge Mode (no badge boosts), trainer
    DVs/happiness from party data. Sitrus Berry heals 30 HP held, 1/4 from
    the bag.
  - No 25% AI status-move failure (never ran in link battles anyway).
  - `CheckTypeMatchup` takes the attack's type in `a`; `BattleCheckTypeMatchup`
    loads the current move's type first. The AI calls `CheckTypeMatchup`
    directly, so never restore vanilla's version (it ignores `a`).
- **Movepools** are vanilla's; Sour's Gen 1 TM tutors follow pokered's TM
  lists through the evolution line (GSC trade-backs).
- **Trainers**: Return users get max happiness and Frustration users none
  (`ReadTrainerParty`), unless the party sets `TRAINERTYPE_HAPPINESS`.
- **AI move power**: moves stored as power 1 get their real power for the AI:
  `AIGetEnemyMove` (all layers) loads Hidden Power from the DVs, Return and
  Frustration from happiness, Magnitude as 71; the Smogon matchup scoring
  (`AISmogon_GetMovePowerAndType`) counts Return/Frustration as 102. Flail,
  Reversal and Present still count as 1.

## PC boxes

`engine/pc/bills_pc.asm` (`docs/newbox_format.md`): vanilla's 14-box SRAM
layout plus slot maps. Up to 3 changed boxes stay in WRAM until saving (then
the UI asks to save); they're staged in spare SRAM so `WriteBackupSave` can
finish an interrupted save.

## Battle AI layout

- `engine/battle/ai/move.asm`: `AIChooseMove` runs the scoring layers enabled
  in each trainer class's `TRNATTR_AI_MOVE_WEIGHTS`
  (`data/trainers/attributes.asm`). Lower score = better; `AIDiscourageMove`
  adds 10. Layer order: `AIScoringPointers`. `AI_Smogon` runs last.
- `engine/battle/ai/scoring.asm`: the vanilla-style layers (AI_Basic, AI_Smart,
  AI_Status, ...). AI_Smart's per-effect handlers still apply under AI_Smogon,
  which adds to or cancels their scores. AI_Status covers status immunities.
- `engine/battle/ai/smogon.asm` (`AI_Smogon`): the GSC OU strategy layer,
  only active in Challenge Mode (`wChallengeMode` bit `GAME_CHALLENGE_MODE_F`).
  - Per-effect handlers are in `AI_Smogon_EffectHandlers`. A handler gets
    `hl` = the move's score and may clobber everything else.
    `AISmogon_Encourage` / `AISmogon_GreatlyEncourage` / `AISmogon_EncourageNear`
    lower the score.
  - It only uses what a human player could know: the player's active mon,
    the moves it has revealed (`wPlayerUsedMoves`), and per-species OU
    tendencies (`SmogonTraits` in `data/battle/ai/smogon_traits.asm`, flags
    `SMOGON_*` in `constants/trainer_data_constants.asm`).
- `engine/battle/ai/smogon_switch.asm`: matchup scoring (rough damage points
  from types, stats, power, STAB, weather, screens, speed), plus
  `AISmogon_FindBestSwitchIn` and the post-faint replacement choice. Tuning
  constants (`SMOGON_*`) are in `constants/trainer_data_constants.asm`.
- `engine/battle/ai/items.asm`: `AI_SwitchOrTryItem`. `SwitchSmogon` is the
  mid-battle switch decision for `SWITCH_SMOGON` trainer classes.
- Banks: `items.asm`, `scoring.asm`, `smogon.asm`, `smogon_switch.asm` and
  `smogon_traits.asm` are all in the "Enemy Trainers" section (bank $0e), so
  they call each other with plain `call`. Battle Core (bank $0f) and Effect
  Commands (bank $0d) are nearly full and are reached with `farcall`/`callfar`.
- Strategy sources: `smogonairesources/` (untracked; Smogon GSC articles, the
  OU threatlist, sample teams, and a usage-stats spreadsheet).

## Tools (`tools/claude/`)

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
- `battle.py ROM SYM RAM "BUGSY 2" SEED [frames]`: one Challenge Mode battle
  against a Smogon-AI trainer (player: Typhlosion with Tackle, Swords Dance,
  Roar, Toxic). JSON line with crashes, AI routine counts and every enemy
  switch-in. Run `make_battle_scripts.py` first. An injected battle needs
  `winlosstext`.
- `battle_matrix.sh OUTDIR RAM ROM1 [ROM2]` (`SEEDS=6`, `TRAINERS=...`): 9
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
