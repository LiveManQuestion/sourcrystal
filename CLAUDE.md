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
- `tools/claude/ai_scenarios.py ROM SYM RAM`: sets up exact states (moves,
  weather, statuses, speed, time of day) each time `AI_Smogon` runs and checks
  its scores, plus the heal-move multiplier the engine picks, and which of
  two equal-stat candidates `AISmogon_FindBestSwitchIn` picks against a
  player type (`switch_cases`; no real switch happens). Add cases there.
  The battle can end mid-run; rerun from the case it stopped at (4th arg).
  `AI_Smogon` is far-called, so its return address is the shared far-call
  stub that every nested `callfar` also returns through: match the stack
  pointer, not just the address, when hooking a return.
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
- **2026-10-13**: Sleep absorbing. When the player's Pokemon has revealed a
  sleep move (and isn't asleep or frozen, with no enemy Safeguard), Sleep Talk
  users get `SMOGON_SLEEP_ABSORB_BONUS` as switch-ins (`AISmogon_SwitchInBonus`),
  and `SwitchSmogon` treats it as an escape reason when the active Pokemon is
  awake without Sleep Talk and the best switch-in has it
  (`AISmogon_ShouldAbsorbSleep`). Checked headlessly by giving the player
  Spore (`$93`; the constants' comments are hex).
- **2026-10-14**: Protect stalling (`AI_Smogon_Protect`). Protect/Detect is
  encouraged when the player takes more residual damage per turn than the
  enemy (`smogon_residual_points` macro: Toxic, Leech Seed, Curse 2 points,
  3/16+ Toxic 3; poison, burn, Sandstorm, trapping 1; enemy Leftovers +1).
  Net 2 encourages, 4 greatly encourages; a Perish Song count that runs out
  before ours always greatly encourages. Never right after Protect or against
  a sleeping/frozen Pokemon. Checked with 12 headless battles (enemy given
  Protect, player kept badly poisoned vs. not): no crashes, Protect used
  alternately with attacks.
- **2026-10-14**: Counter/Mirror Coat (`AI_Smogon_Counter`, both effects).
  Encourages the one matching `AISmogon_PlayerIsCounterable` (revealed
  attacks, else Attack vs. Sp.Atk; like `AISmogon_PlayerIsPhysical` but
  Hidden Power counts as physical, since Counter goes by its Normal type in
  the move data, and fixed-damage attacks count) while the enemy has half HP
  or more; discourages the other one and both against a sleeping/frozen
  Pokemon; never used into a type immunity (Ghost/Dark). Checked with 36
  headless battles (enemy given both moves; player physical, special, or
  high Sp.Atk with Dark Hidden Power or Seismic Toss): no crashes; Counter
  dominated against physical attackers and once HP/Seismic Toss was revealed,
  Mirror Coat otherwise.
- **2026-10-14**: Battle mechanics back to vanilla Crystal (the user wants the
  battle system to match unmodified Crystal; don't reintroduce these):
  - Body Slam is `EFFECT_PARALYZE_HIT` again (Sour Crystal had given it Stomp's
    double damage against Minimize). `EFFECT_BODY_SLAM` and
    `BattleCommand_CheckHit.AntiMinimize` (Body Slam/Stomp never missing a
    Minimized target, which also checked the wrong side) are gone.
  - Morning Sun/Synthesis/Moonlight heal by time of day again: 1/2 at their
    time, 1/4 otherwise, doubled in sun, halved in rain or Sandstorm, no time
    bonus in link battles. Sour Crystal's Evening (17:00-19:59) counts as day
    before `VANILLA_NITE_HOUR` (18) and night after, like the original game.
    `GetTwoThirdsMaxHP` was only used by Sour Crystal's version and is removed.

  New Smogon AI move handling:
  - Thunder is encouraged in rain, where it never misses (`AI_Smogon_Thunder`).
  - Rollout is encouraged after Defense Curl (`AI_Smogon_Rollout`).
  - When the enemy moves first against a player in the air (Fly) or
    underground (Dig), attacks that can't reach it are discouraged, with
    Lock-On taken into account (`AISmogon_MissesHiddenPlayer`). Swift misses
    too: `.FlyDigMoves` runs before the sure-hit check.
  - Endure is discouraged when residual damage knocks the enemy out anyway
    (`AI_Smogon_Endure`). Poison/burn/Leech Seed/Curse hit right after the
    user's own move (before the player's attack, since Endure goes first), so
    they only matter when they're at least the current HP. Sandstorm, trapping
    moves and Perish Song come at the end of the turn and always do.
  - Heal moves: 1/8 is discouraged, 1/4 is left to AI_Smart, 1/2 or more
    heals at half HP (`AISmogon_TimeBasedHealAmount`).

  Checked with `tools/claude/ai_scenarios.py` (32 AI scenarios plus 8 engine heal cases).
- **2026-10-14**: Battles play exactly like vanilla Crystal / GSC on Smogon,
  bugs included: anything that can matter in a link battle is vanilla (the user
  wants this; don't reintroduce Sour Crystal's battle mechanics or battle bug
  fixes). Single-player-only fixes and features stay. `pokecrystal-master/`
  (untracked) is the vanilla reference.
  - Data is byte-identical to vanilla: moves, effect scripts and commands, type
    order (Ghost physical, Dark/Dragon special), base stats (Gen 2; learnsets
    unchanged), type-boost items 10% (Dragon Scale boosts, Dragon Fang
    doesn't). Held Sitrus Berry heals 30 HP in battle (1/4 from the bag).
  - `effect_commands.asm` and `move_effects/` are vanilla, except: no 25% AI
    status-move failure, Thief's wild-battle changes and stolen-item backup,
    and cosmetics (freeze/paralysis anims, colored Hidden Power, anim params,
    Future Sight anim, shorter delays).
  - `core.asm` battle mechanics are vanilla (Spikes, trap 1/16, Sandstorm
    1/8, Perish/Spikes 0 HP, Berserk Gene count, PRZ/BRN on switch-in,
    Struggle with PP Ups, no Teleport switching).
  - Kept single-player code: exp (Exp. Share split, catch exp), catching and
    ball fixes, wild held items and flee list, Magikarp length, items stolen
    by foes returned (`wPartyBackupItems`, `ConsumeUserItem`), Pursuit faint
    status fix, Glacier Badge fix, max HP < 4 freeze fix, Safari, overworld
    weather starting battle weather, Challenge Mode, trainer DVs/happiness.
  - Smogon AI: Growth is `EFFECT_SP_ATK_UP`; Hidden Power's power comes from
    the DVs (`AISmogon_GetAttack`).
  - Smogon AI: Return and Frustration count as 102 power, max/min happiness
    (`AISmogon_GetMovePowerAndType`). Flail, Reversal, Magnitude and Present
    still count as power 1 (ignored by the matchup scoring).
- **2026-10-14**: Trainer Pokemon with Return get max happiness (255) and
  ones with Frustration get 0, both 102 power (`ReadTrainerParty`), unless
  the party uses `TRAINERTYPE_HAPPINESS`, whose value wins (e.g. the
  Frustration Koffing set to $1e = 90 power). Checked headlessly on Bugsy 2's
  Pinsir (and a ROM copy patched to Frustration).
- **2026-10-14**: `CheckTypeMatchup` takes the attack's type in `a` again
  (`BattleCheckTypeMatchup` loads the current move's type first, so battles
  are unchanged). Vanilla ignores `a`, which broke every type-effectiveness
  judgment in `AISmogon_AttackPoints` and `ai/switch.asm` after the vanilla
  revert. Don't restore the vanilla version. Checked with switch traces against
  Typhlosion: switches into a better Fire resistance went from 8/37 to 26/56.
