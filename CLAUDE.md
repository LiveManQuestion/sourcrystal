# Sour Crystal: notes for Claude

A Pokémon Crystal ROM hack built on the pret/pokecrystal disassembly (see
README.md for features). The Game Boy Z80-like assembly is built with RGBDS.
STYLE.md is the code style guide: tabs, comments above the code they describe,
PascalCase ROM labels, `.local` labels.

## Hard constraints

- **Stay link compatible with unmodified Pokémon Crystal and the Time Capsule
  (Gen 1).** Don't change move, item or species IDs, party/box struct layouts,
  link data, mail, or anything under `engine/link/`, `home/serial.asm`, or
  `engine/printer/`. The battle AI must never run in link battles (check
  `wLinkMode`).
- **Don't break existing saves.** Don't move or resize saved WRAM/SRAM
  (`wPlayerData`, `wPokemonData`, boxes...). Save layout changes need
  `save_compat.asm` / `save_migrations/`. Battle-only WRAM is safe to use.
- Don't commit or push unless the user asks.

## Build

- `make -j16 sour` builds `sourcrystal.gbc`. `make -j16 all` also builds the
  GBTower, debug and VC (`.patch`) variants. Build all four before committing:
  code under `IF DEF(_DEBUG)` etc. differs between them.
- RGBDS 1.0.4. The `STRSUB is deprecated` warnings are pre-existing and harmless.
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

## Battle AI layout

- `engine/battle/ai/move.asm`: `AIChooseMove` runs the scoring layers
  enabled in each trainer class's `TRNATTR_AI_MOVE_WEIGHTS`
  (`data/trainers/attributes.asm`). Lower score = better; `AIDiscourageMove`
  adds 10. Layer order: `AIScoringPointers`. `AI_Smogon` runs last.
- `engine/battle/ai/scoring.asm`: the vanilla-style layers (AI_Basic, AI_Smart,
  ...). AI_Smart's per-effect handlers still apply under AI_Smogon. AI_Smogon
  adds to or cancels their scores.
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
  The Enemy Trainers bank has ~7 KB of room (its floating neighbor sections
  move out as it grows).
- Strategy sources: `smogonairesources/` (untracked; Smogon GSC articles, the
  OU threatlist, sample teams, and a usage-stats spreadsheet).

## Testing (PyBoy, headless)

PyBoy is installed as a uv tool: `~/.local/share/uv/tools/pyboy/bin/python`.
It has no Pillow, so the scripts write PNGs themselves. The user's real save is
`sourcrystal.sav`, and its first 32 KB is the cartridge RAM
(`head -c 32768 sourcrystal.sav > /tmp/user.ram`). `sourcrystal.gbc.ram` is an
empty save. Never write over the user's save files.

- `tools/claude/smoke.py ROM RAM OUTDIR`: boot, title, Continue, overworld and
  menus, with a screenshot hash per step. Diff two ROMs' output to catch
  regressions.
- `tools/claude/battle.py ROM SYM RAM "BUGSY 2" SEED [frames]`: one Challenge
  Mode battle against a Smogon-AI trainer. Reports crashes (jumps to the rst
  $38 crash vector, with the stack), timeouts, and how often each AI routine
  ran. First run `python3 tools/claude/make_battle_scripts.py`.
- `tools/claude/battle_matrix.sh OUTDIR RAM rom1.gbc [rom2.gbc]` runs
  9 trainers × 6 seeds (~15 min per ROM). Summarize with
  `tools/claude/battle_summary.py`. Compare against a build of the previous
  commit: a few timeouts on Jasmine/Koga/Brock are normal (stall battles,
  since the harness keeps healing the player). Crashes are not.
- An injected trainer battle needs `winlosstext`, or a win prints a stale
  pointer and crashes. This was a harness bug, not a game bug.

## Optimization tooling

`tools/claude/peephole.py` applies the pret wiki's "Optimizing assembly code"
peepholes: `call`+`ret` → `jp` only for callees that never pop their own
return address, `jp` → `jr`, `cp 0` → `and a`, and `ld a, 0` → `xor a` when
the flags are dead. It skips timing-sensitive, RAM-copied, link and printer
code (see `EXCLUDE_PREFIXES`). After `apply`, run `tools/claude/fix_jr.sh`,
which reverts every `jr` RGBDS reports out of range until all four ROMs build.
It was applied to the whole project in commit 342bbfb61.

## Change log (Claude sessions)

Add an entry here when making notable changes.

- **2026-10-13**: `342bbfb61` peephole optimization pass over `engine/` and
  `home/` (~1 KB saved, including room in the full Battle Core, Effect Commands
  and ROM0 banks). `138621d66` Smogon AI upgrade:
  - Moved the switching code and SmogonTraits into the AI bank.
  - New move behavior:
    - Reflect/Light Screen matched to the player's attack category
    - Baton Pass, Encore, Heal Bell
    - Explosion avoids Reflect, and a doomed, outsped Pokémon explodes
    - Toxic is favored with Spikes down
    - No phazing out a sleeping, unboosted Pokémon
  - Switching favors a phazer, Haze user or exploder against a boosted
    player.
  - Verified with 108 headless battles (no crashes; same timeout rate as before).
  - Ideas not done yet:
    - Protect to stall out the player's residual damage
    - choose Counter/Mirror Coat by the player's stats
- **2026-10-13**: Sleep absorbing. When the player's Pokemon has revealed a
  sleep move (and isn't asleep or frozen, with no enemy Safeguard), Sleep Talk
  users get `SMOGON_SLEEP_ABSORB_BONUS` as switch-ins (`AISmogon_SwitchInBonus`),
  and `SwitchSmogon` treats it as an escape reason when the active Pokemon is
  awake without Sleep Talk and the best switch-in has it
  (`AISmogon_ShouldAbsorbSleep`). Checked headlessly by giving the player
  Spore (`$93`; the constants' comments are hex).
