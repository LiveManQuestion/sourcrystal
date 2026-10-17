# Sour Crystal: notes for Claude

A Pokémon Crystal ROM hack built on the pret/pokecrystal disassembly (see
README.md for features). The Game Boy Z80-like assembly is built with RGBDS.
STYLE.md is the code style guide: tabs, comments above the code they describe,
PascalCase ROM labels, `.local` labels. `pokecrystal-master/` (untracked) is a
copy of vanilla pret/pokecrystal for reference, and `pokecrystal_wiki/`
(untracked) pret's wiki of pokecrystal tutorials (adding moves, items, trainer
classes, AI layers...). Session history:
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
- Exp gain and the exp bar are in their own floating section
  (`engine/battle/exp.asm`), out of Battle Core. `newfarcall` is slow: the
  overworld step code (`ScrollMap*` in `player_step.asm`) is at the frame
  budget, and one `newfarcall` there added a lag frame.
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

## Battle AI

Details: `docs/battle_ai.md`. In short: `AIChooseMove`
(`engine/battle/ai/move.asm`) runs the scoring layers each trainer class
enables (lower score = better); `AI_Smogon` (`smogon.asm`, Challenge Mode
only) runs last and only uses what a human could know. Switching is `SwitchSmogon` (`items.asm`) with matchup
scoring in `smogon_switch.asm`. All of these share bank $0e; Battle Core and
Effect Commands need `farcall` or `newfarcall`.

## Tools (`tools/claude/`)

Details and usage: `docs/claude_tools.md`. The usual checks after a battle or
AI change: `cmp_data.py` (expect `ALL IDENTICAL`), `damage_diff.py` (0
mismatches), `ai_scenarios.py ROM SYM RAM` (`RESULT: ALL OK`) and
`battle_matrix.sh` (no crashes; compare with `battle_compare.py`). For a
Smogon AI change, `ai_check.sh` runs the tests, the battles and the engine
judge against `HEAD` in one report (cached; about an hour per new ROM).
Headless tests use PyBoy (`~/.local/share/uv/tools/pyboy/bin/python`) and the
user's `sourcrystal.sav` as cartridge RAM, made with `save_ram.py` (not `head
-c`: a clock-reset flag in the save stops battles from starting). Never
write over the user's save files.

- Compare against an older commit with `build_rev.sh REV OUT` (cached).
- Read game constants and data in Python with `pokedata.py`; ad hoc parsers
  got `const_skip` and `shift_const` wrong.
- Judge AI strength with `PLAYER=smart battle_matrix.sh` on Koga 2, Misty 2,
  Whitney 2 and Jasmine 2 (the others never beat the user's party), 48+
  seeds; `battle_compare.py` prints z, and below 2 is noise. Explain a
  change with `ai_trace.py` and check its cost with `ai_profile.py`.
  `engine_judge.py` (Foul Play's Gen 2 engine, poke-engine, in
  `bots/pe-venv`) rates each traced decision; `--patterns` finds the
  mistakes worth fixing.
- PyBoy: one hook per address (share them with `battle_harness.Battle.on`),
  and exceptions in hooks are swallowed silently, so count or log them. Some
  menus (party, PC) draw as a white screen; check state through RAM.
