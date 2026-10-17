# Claude session change log

Notable changes made in Claude Code sessions, oldest first, with how each was
checked. `CLAUDE.md` summarizes what's still true; add new entries here.

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
- **2026-10-14**: `AIGetEnemyMove` loads the power moves really have in
  battle, so every AI layer sees it: Hidden Power's power and type from the
  enemy's DVs (via `AISmogon_GetAttack`; before, AI_Immunities dismissed it
  against Ghosts as a Normal move), Return and Frustration from the enemy's
  happiness (BattleCommand_HappinessPower's formula), and Magnitude's average
  of 71. Before, AI_Aggressive saw all of them as 1 power. The Smogon
  matchup scoring also counts Magnitude as 71. `ai_scenarios.py` checks these
  (`hp_cases`). Audited for other contract changes from the vanilla revert
  (only `CheckTypeMatchup` mattered) and status immunities (AI_Status already
  covers Toxic, Leech Seed and Thunder Wave/Glare immunities). Note: any code change shifts the
  game's RNG timing, so compare battle win rates with many seeds (Koga 1
  varied 15/36 vs 10/36 between builds with no Hidden Power on his team).
- **2026-10-14**: Final vanilla check. Two leftovers fixed: Sky Attack was
  in `data/moves/critical_hit_moves.asm`, and Bide (+1) and Teleport (-1)
  had priorities in `data/moves/effects_priorities.asm`. All battle data
  tables now match vanilla byte for byte (except pointers and the "SP.ATK"
  stat names), and `damage_diff.py` found 0 mismatches in 2000 cases (98/500
  against the pre-revert build).
- **2026-10-14**: Tooling to make sessions cheaper. Fixed the RGBDS 1.0
  deprecation warnings at the cause (`STRSUB`/`STRIN`/`CHARSUB` and
  strings used as numbers → `STRSLICE`/`STRFIND`/`STRCHAR` and character
  literals, as in vanilla); all four ROMs and the VC patch are byte-identical,
  and an incremental build prints ~5 lines. Moved this log out of
  `CLAUDE.md`. New tools in `tools/claude/`: `build_vanilla.sh`,
  `cmp_data.py`, `vanilla_diff.py`, `replace_region.py`, `switch_report.py`,
  `battle_compare.py`; `battle.py` logs switches; `battle_matrix.sh` takes
  `SEEDS` and `TRAINERS`; `ai_scenarios.py` restarts itself until every case
  has run and ends with `RESULT: ALL OK`.
- **2026-10-15**: Pokémon Stadium 2 compatibility, tested in mupen64plus with
  Transfer Pak emulation (copies of saves only). The cartridge is recognized
  (`tools/stadium` checksums) and party/bag/money/Pokédex are at vanilla
  offsets. Stadium reads SRAM bank 1 `$A000-$AD1F` at the Game Pak check and
  banks 2-3 (vanilla's 14 boxes) plus bank 0 mail in the Lab; its Lab needs a
  save made on its list of map IDs (US ROM `0x97f1c`: the vanilla Pokémon
  Centers, `POKECENTER_2F`, `PLAYERS_HOUSE_2F`, the PokéCom admin office).
  Added `UNUSED_BLACKTHORN_MAP` and `UNUSED_CERULEAN_MAP_1`/`_2` (sharing
  `maps/UnusedMap.asm`) so Blackthorn's and Route 10's Pokémon Centers have
  vanilla IDs again, with save migration 03 shifting saved map IDs. Checked:
  migration in PyBoy (both save copies, checksums, version 3) and Stadium's Lab
  PC opening for a Blackthorn Pokémon Center save. Mount Moon and Safari Zone
  Gate Pokémon Centers can't be added to Stadium's list. Also moved inline
  comments in `smogon.asm` and `smogon_switch.asm` above their code (STYLE.md).
- **2026-10-15**: PC boxes back in vanilla's save layout (14 boxes instead of
  the 16-box PokeDB) so Stadium 2 reads and changes them; the box UI is
  unchanged. Slot maps keep mons in any slot. Reset protection: changed boxes
  stay in 3 WRAM bank 2 buffers until saving; the UI's "save to continue"
  prompt covers a 4th box. Saving stages them in spare SRAM (not `sScratch`:
  booting changes its first bytes), so `WriteBackupSave` finishes an
  interrupted save. The saved copy is `sBox1 - sBox14` like vanilla (Stadium
  writes those, not `sBox`); `sBox` mirrors the current box. Box names in
  `wBoxNames`, themes in saved WRAM padding, `wPlayerCaught` moved to vanilla's
  unused bytes after `wCurBox`. Migration 03 empties old saves' boxes (not
  converted, as agreed). Checked: `storage_test.py` (4 seeds × 400 random
  operations, resets, interrupted saves, outside changes, new game), the PC UI
  driven through RAM (save prompt, moves), and Stadium 2 showing the boxes and
  re-ordering them, then loading that save (no duplicates).
- **2026-10-15**: Movepools back to vanilla: `evos_attacks.asm` learnsets
  (evolution methods kept, including the item alternatives to trade
  evolutions; Golbat and Chansey no longer share Crobat's and Blissey's
  learnsets), `egg_moves.asm`, and every `tmhm` list. The 26 Sour-only
  TM/tutor moves follow pret/pokered's Gen 1 TM compatibility of the species
  or an earlier evolution (Low Kick: vanilla Low Kick learners). Base stats
  were already vanilla. Checked: learnsets, egg moves and the vanilla part of
  every `tmhm` list equal vanilla's source; all four ROMs build;
  `cmp_data.py`, `ai_scenarios.py` and `smoke.py` pass. Also fixed Dunsparce's
  Frustration on Whitney's rematch team (happiness 0).
- **2026-10-15**: Trainer movesets made legal. Checked every
  `TRAINERTYPE_MOVES` party in `data/trainers/parties.asm` against
  RBY/Yellow/GS/Crystal learnsets (level-up through pre-evolutions, TM/HM,
  Crystal tutors, egg moves, Gen 1 trade-backs, Odd Egg, Extremespeed Dratini,
  Surf/Fly Pikachu; Smeargle can Sketch anything). Replaced 314 impossible
  moves (e.g. Gyarados Earthquake/Crunch, Golbat Crunch, Aerodactyl Rock
  Slide, Skarmory Spikes) with legal moves filling the same role, and fixed
  3 impossible combinations of a Gen 1-only move with a Gen 2 egg move
  (Lt. Surge's Raichu, Bird Keeper Fearow). 51 level-up moves above the
  Pokémon's level remain; Gen 2 breeding can pass those down. Also checked
  against the GSC illegal-combination lists in `illegalmovecombos/` (4092
  rules, 178 species): only Chuck's Granbull (Crunch + Metronome) hit, now
  Ice Punch. All four ROMs build; `ai_scenarios.py` ALL OK.
- **2026-10-15**: Stadium 2 GB Tower in mupen64plus. Traced why it fails
  (the Transfer Pak check without upstream's fix, then a hang without RMG's
  RSP/RDP patch; vanilla Crystal too) and added
  `tools/claude/stadium2/build_core.sh` and `play.sh` (see
  `docs/stadium2.md`). Tested headlessly: Sour Crystal boots in the GB Tower,
  loads the save and reaches the overworld.
- **2026-10-16**: GB Tower graphics glitches (blank intro, garbled party
  icon, NPCs changing sprites, also in ares) come from GDMA, which Stadium's
  Game Boy emulator doesn't handle; `sourcrystal_GBTower.gbc` already skips
  it. Bill's PC called `SafeHDMATransfer` directly; `BillsPC_Get2bpp` now
  skips GDMA under `_GBTOWER` too. Only the GBTower ROM changed. Checked
  in mupen64plus's GB Tower: intro, title and party icons correct.
- **2026-10-16**: GB Tower detection at runtime. Stadium 2's GB Tower starts
  games with b = $11 and l = $00 (read from its SRAM copy in a mupen64plus
  savestate with a test ROM); `_Start` sets `hGBTower` (a spare HRAM byte, so
  no other HRAM address moved), which replaces the `_GBTOWER` checks in
  `CheckGDMA`, `BillsPC_Get2bpp` and the battle start delay. `sourcrystal.gbc`
  now works in the GB Tower: intro and party icons correct in mupen64plus;
  PyBoy keeps `hGBTower` off; `cmp_data.py` ALL IDENTICAL.
- **2026-10-16**: Free space in the full banks (link, serial and printer code
  untouched). Room in the pinned sections: Home 87 -> 539 bytes, Effect Commands
  298 -> 1111, Battle Core 287 -> 1721; Enemy Trainers 6074 -> 5321.
  - Exp gain/exp bar (`GiveExperiencePoints`, `AnimateExpBar`,
    `FillInExpBar`...) moved to `engine/battle/exp.asm` ("Battle Exp").
  - `engine/battle/ai/switch.asm` moved from Effect Commands to the AI bank,
    except `FindAliveEnemyMons`.
  - Home: `ScrollMap*`/`BackupBGMap*`/`UpdateBGMap*` moved to
    `player_step.asm`; `SaveScreen`, `LoadConnectionBlockData` and
    `FadeToMapMusic` (map setup commands, far-called) to `map_setup.asm`.
  - Deleted unreferenced functions in banks 0, $0e and $0f.
  - Checked: all four ROMs build, `cmp_data.py` ALL IDENTICAL, `damage_diff.py`
    0 mismatches, `ai_scenarios.py` ALL OK, smoke and a 5100-frame walk with
    every screen identical to the old ROM, 12 battles with exp and a level-up
    (same exp as the old ROM, no crashes).
- **2026-10-16**: Smogon AI from new sources: the Smogon GSC dex analyses
  (OU/UUBL/UU/Uber sets, saved as `smogonairesources/smogon_dex_gs.json`)
  and the per-species move counts in the replay spreadsheet.
  `tools/claude/smogon_data.py` now generates `smogon_traits.asm` (old flags
  reproduced exactly, `SMOGON_THREAT` kept) and the new `smogon_attacks.asm`.
  - `SmogonExpectedAttacks`: the attack types (and power) on >= 20% of a
    species' sets, e.g. Zapdos Thunder + Hidden Power Ice/Water, Golem only
    Earthquake, Gengar Ice Punch/Thunderbolt/Dynamic Punch, Smeargle none.
    `AISmogon_ScoreMatchup` assumes these instead of two 80-power STABs for
    the 90 listed species, and drops all assumptions once four moves are
    revealed.
  - New traits `SMOGON_EXPLODER`, `SMOGON_PURSUIT`, `SMOGON_SLEEPER`:
    a worn-down (below half HP, or Spikes already down) likely exploder
    makes Rock/Steel/Ghost switch-ins worth `SMOGON_BOOM_ABSORB_BONUS` and
    Protect greatly encouraged (unless the enemy resists Normal); a usual
    Pursuit user keeps Ghosts/Psychics in; a usual sleeper counts as a sleep
    threat for Sleep Talk switch-ins.
  - Speed in matchups: the active Pokemon uses its battle Speed (boosts,
    paralysis); paralysis quarters a benched Pokemon's Speed.
  - `AI_Smogon_DestinyBond`: greatly encouraged at <= 1/4 HP when faster;
    discouraged against a sleeping/frozen Pokemon.
  - Checked: all four ROMs build (Enemy Trainers +861 bytes);
    `cmp_data.py` ALL IDENTICAL; `ai_scenarios.py` ALL OK with 7 new move
    and 8 new switch cases (6 of them fail on the old ROM); battle matrix
    9 trainers × 12 seeds: AI wins 13 -> 24 of 108, timeouts 81 -> 65,
    no crashes.
- **2026-10-16**: Smogon AI from "GSC - A Naughty Guide"
  (`smogonairesources/`, a Smogon-community GSC OU guide).
  - `AISmogon_PlayerCantAttack`: a sleeping Pokemon that has revealed Sleep
    Talk counts as able to attack (no free setup, Substitute, phazing
    restraint or Destiny Bond/Protect/Counter shortcuts against it); frozen
    still can't. Used by all of AI_Smogon's sleep/freeze checks.
  - Matchups: a sleeping Pokemon that usually has Sleep Talk (trait) and
    hasn't revealed four moves keeps 3/4 of its threat instead of half.
  - `AI_Smogon_AttackDown` (Growl, Charm): greatly encouraged against a
    physical attacker with raised (not maxed) Attack, discouraged against
    special attackers, a maxed Belly Drum, or a Substitute.
  - `AI_Smogon_MeanLook`: discouraged against a phazer.
  - `AI_Smogon_Paralyze`: also encouraged when paralysis would let a slower
    healthy teammate outspeed the player (`AISmogon_ParalysisHelpsTeammate`).
  - Checked: all four ROMs build; `cmp_data.py` ALL IDENTICAL;
    `ai_scenarios.py` ALL OK with 13 new cases (7 fail on the previous
    build; the Fly/Dig cases now use Harden as their filler, since Growl now
    has a handler). Battle matrix 9 x 12 vs. the previous build: AI wins
    24 -> 26, timeouts 65 -> 57, no crashes. Per trainer it's noisy (Bugsy
    5 -> 1, Rival 5 -> 10), but Bugsy's and Sabrina's teams use none of the
    affected moves, so those swings are RNG timing.
- **2026-10-16**: Smogon GSC move pages (descriptions and learners, saved
  as `smogonairesources/smogon_moves_gs.json`) checked against the AI's
  move handlers and the engine. Where Showdown's descriptions differ from
  the cartridge (Encore also failing on Sleep Talk etc., Morning Sun
  ignoring the time of day), the AI follows the engine.
  - `AI_Smogon_Phaze`: Roar and Whirlwind fail if the user moves first
    (`BattleCommand_ForceSwitch` checks `wEnemyGoesFirst`), so they're
    discouraged against a slower Pokemon that phazes (revealed, or
    `SMOGON_PHAZER` with fewer than four moves revealed), unless it has
    boosted. New `AISmogon_PlayerPhazes`.
  - `AI_Smogon_Encore`: discouraged when the player's last move was Encore
    or Mirror Move, where `BattleCommand_Encore` fails.
  - Checked: all four ROMs build; `cmp_data.py` ALL IDENTICAL;
    `ai_scenarios.py` ALL OK with 6 new cases (3 fail on the previous
    build). Battle matrix 9 x 12: AI wins 26 -> 26, no crashes; the only
    trainers that phaze (Brock 0 -> 2, Jasmine 2 -> 4) improved. Rival 10 -> 5
    is RNG timing: its team has none of the affected moves.
- **2026-10-16**: Whitney's Challenge Mode rematch was too easy: an all-Normal
  team with no phazing, no Rapid Spin and little damage (Rollout Miltank,
  Present/Flamethrower Smeargle, passive Chansey and Blissey). New OU-style
  team: Smeargle (Spore/Spikes/Rapid Spin/Roar), Tauros (Return/EQ/Thunderbolt/
  Fire Blast), Porygon2, Curse Snorlax, Blissey (Heal Bell, Ice Beam,
  Flamethrower) and Curse/EQ Miltank. Every move was checked against the
  learnsets. With the player's real save party and random inputs (no healing),
  over 32 seeds she went from 3 wins to 24, with no crashes.
  `make_battle_scripts.py` now includes WHITNEY 2. `battle.py` prints the
  enemy's moves by species, and `battle_matrix.sh` writes one file per run,
  because parallel appends of long JSON lines interleaved.
- **2026-10-16**: Spent Pokemon switch out. Whitney's Smeargle used Rapid
  Spin with nothing to spin once Spore and Spikes were done: Rapid Spin was
  its only attack, and it stayed at a neutral score. `AI_Smogon_RapidSpin` now
  mildly discourages it with no Spikes, Leech Seed or Bind to clear.
  `AIChooseMove` sets `wEnemyAIMovesSpent` (a battle-only padding byte, so
  nothing moved) when every move scores worse than 20, and `SwitchSmogon`
  escapes on it like on Leech Seed. Over 32 battles with the player's save
  party: Smeargle's useless Rapid Spins went from 29 to 0, and it switched out
  8 times instead of 1. Whitney's win rate didn't change (24 vs 23 of 32), no
  crashes. `ai_scenarios.py` ALL OK, `cmp_data.py` ALL IDENTICAL.
- **2026-10-16**: Bulk in the Smogon matchup scoring. `AISmogon_ScoreMatchup`
  ignored HP, so Blissey's special bulk counted for nothing: against Zapdos
  all six of Whitney's Pokemon scored 120-127, and ties went to party order
  (Snorlax 43x, Blissey 5x after a faint). `AISmogon_StatEdges` now scales
  the defender's stat by its max HP against the usual HP at its level
  (`AISmogon_GetBulk`: 13 * level / 16 + 3, both / 4; the two temporaries
  use the unused padding bytes after the Reflect counters, so no WRAM
  moved), and each stat comparison is a level (`SMOGON_EDGE_*`: below half,
  worse, better, at least double) that moves the points by a quarter or a
  half. A screen makes it one level worse. A spent Pokemon only switches to a
  strictly better matchup (two spent Pokemon swapped back and forth).
  Results: Blissey sent into Zapdos 41 of 41 times. `ai_scenarios.py` ALL OK,
  `cmp_data.py` ALL IDENTICAL, 9-trainer battle test (6 seeds) no crashes,
  AI wins 0 -> 2 of 54, timeouts 5 -> 3. Still open: the score subtracts
  per-hit points instead of comparing turns to KO, so a fast attacker with a
  super-effective move (Tauros's Thunderbolt into Vaporeon) beats a wall
  that takes far less damage.
- **2026-10-16**: Smogon matchups as a KO race. `AISmogon_ScoreMatchup`
  subtracted per-hit damage points, so a fast attacker with a
  super-effective move beat a wall that takes far less damage (Whitney's
  Blissey switched to Tauros against Vaporeon). Each side's best attack is
  now estimated with the damage formula (`AISmogon_SetupDamage`,
  `AISmogon_AttackDamage`), turned into hits to KO from current HP
  (`AISmogon_TurnsToKO`), and scored EVEN + 16 * log2(the player's half
  turns / ours): the faster side gets half a turn, and a switch-in takes a
  hit on the way in unless it replaces a fainted Pokemon. This replaces the
  speed/revenge bonuses, the stat edges and the low-HP switch-in penalties.
  For speed: the formula without the power is precomputed per pair,
  `AISmogon_Divide24` replaces home `Divide`, and
  `AISmogon_FillTypeMatchups` reads a copy of the type chart in the AI bank
  (`data/types/type_matchups_table.asm`, included by both). A switch
  decision takes at most 7 frames, the same as before (first draft: 18).
  Against the user's save party (48 battles, random inputs): Whitney won 42
  (33 before), clearly losing stay-ins fell from 154 to 18, Blissey ->
  Tauros against Vaporeon is gone (Blissey -> Snorlax instead), and 95 of
  112 replacements after a faint match an independent damage-race estimate.
  `ai_scenarios.py` ALL OK, `cmp_data.py` ALL IDENTICAL, 9-trainer battle
  test no crashes (AI wins 2 -> 0 of 54, timeouts 3 -> 3, both noise).
  Healing (Softboiled, Recover, Leftovers) isn't part of the race yet.
- **2026-10-16**: Healing in the Smogon KO race (`AISmogon_ApplyHealing`,
  `AISmogon_HealOutlasts`, `AISmogon_HealDelay`). Leftovers comes off the
  damage each side takes (the player's Pokemon is assumed to hold it). A
  recovery move (Recover, Softboiled, Milk Drink, Moonlight, Morning Sun,
  Synthesis: half max HP per turn; Rest: a quarter) that outheals the damage
  taken makes that side impossible to KO, and its own KO takes turns *
  healing / (healing - damage taken). The player's side counts revealed
  recovery moves, or Rest from `SmogonTraits`. Whitney's Blissey now scores
  183 against Zapdos (Snorlax 128) and 191 against Cloyster, but still 17
  against Snorlax's Double-Edge. Against the user's save party (48 battles):
  Whitney won 43, no crashes; switch decisions still take at most 7 frames.
  `ai_scenarios.py` ALL OK, `cmp_data.py` ALL IDENTICAL, 9-trainer battle
  test no crashes (AI wins 0 -> 3 of 54, timeouts 3 -> 6, within noise).
  PP isn't modeled, so two Pokemon that both outheal each other come out
  even.
- **2026-10-16**: Recovery PP in the Smogon KO race. A side that outheals
  the damage it takes now lasts until its recovery PP runs out
  (`AISmogon_SideTurns`: HP plus PP * healing per use), and the turns it
  loses to healing are at most its PP (`AISmogon_HealDelay`). Each side's
  healing, PP and HP are in a healing block (`HEAL_*`, `wSmogonAIOurHeal`,
  `wSmogonAIPlayerHeal`). The AI reads its own Pokemon's current PP (from
  `wEnemyMonPP` for the active one); the player's recovery moves count their
  base PP. Two healers no longer come out even: Miltank against a Rest
  Snorlax scores 124 instead of 128, and Blissey against Zapdos 166 instead
  of 183. Against the user's save party (48 battles): Whitney won 43, no
  crashes; switch decisions still take at most 7 frames. `ai_scenarios.py`
  ALL OK, `cmp_data.py` ALL IDENTICAL, 9-trainer battle test no crashes (AI
  wins 3 -> 1 of 54, timeouts 6 -> 2). Attack PP isn't modeled.
- **2026-10-16**: Attack PP in the Smogon KO race. Each side now keeps a
  list of its attacks' damage and PP (`ATTACKS_*` in `wSmogonAIThreat` and
  `wSmogonAIPower`, filled by `AISmogon_AddAttack`; an attack expected and
  revealed is kept once). `AISmogon_TurnsWithPP` uses the strongest attack
  until its PP runs out, then the next; if all of them together can't get
  through the target's HP and heals, it can't KO. Leftovers and the
  sleeping-player discount apply to every attack in the list. The AI's own
  moves count their current PP, the player's revealed moves their base PP,
  and its expected attacks `SMOGON_UNKNOWN_PP` (10). Example: Blissey
  against Vaporeon is now a stalemate (128): neither side can get through
  with its PP. Against the user's save party (48 battles): Whitney won 44,
  no crashes; switch decisions take at most 8 frames (7 before).
  `ai_scenarios.py` ALL OK, `cmp_data.py` ALL IDENTICAL, 9-trainer battle
  test no crashes (AI wins 1 -> 3 of 54, timeouts 2 -> 5).
- **2026-10-16**: PP Ups in the Smogon AI's estimate of the player's PP.
  The player's revealed attacks, recovery moves and unrevealed expected
  attacks (base 10) now assume `SMOGON_PLAYER_PP_UPS` (3) PP Ups
  (`AISmogon_PlayerMaxPP`: each adds a fifth of the base PP, at most 7), since
  a human opponent can't see them and competitive sets max them. The user's
  own save party has none, so lower the constant if that's typical. Example:
  a revealed Surf counts 24 PP, so Vaporeon now gets through Blissey's
  Softboiled (104) instead of a stalemate. `ai_scenarios.py` ALL OK,
  `cmp_data.py` ALL IDENTICAL.
- **2026-10-16**: The player's PP Ups are estimated from their party instead
  of the fixed `SMOGON_PLAYER_PP_UPS` (removed). `AISmogon_CountPlayerPPUps`
  averages the PP Ups per move across the player's whole party (rounded),
  once per matchup: the AI can tell how much the player uses PP Ups, not on
  which Pokemon. Unrevealed attacks get `SMOGON_UNKNOWN_BASE_PP` (10) with
  those PP Ups (`wSmogonAIUnknownPP`). Checked by giving the party none (0,
  10 PP), all (3, 16 PP), and two of six Pokemon maxed (1, 12 PP). The
  user's party has none, so Whitney is back to 43 wins of 48 against it (38
  when assuming 3). `ai_scenarios.py` ALL OK, `cmp_data.py` ALL IDENTICAL,
  9-trainer battle test no crashes.
- **2026-10-16**: `battle.py --smart` (`tools/claude/smart_player.py`): the
  save's own party, healed once and never again, played by a greedy policy
  instead of an unkillable Typhlosion pressing random buttons, so win rates
  mean something. It attacks with the strongest move by the damage formula
  (no Explosion or Counter; two-turn moves count half), switches when a
  healthy teammate wins the KO race at least twice as well after taking a hit
  (not two turns in a row, not while trapped), and picks the best
  replacement after a faint. It writes the menus' cursor variables from hooks
  (`BattleMenu`, `MoveSelectionScreen`, `BattleMenuPKMN_Loop`,
  `PickPartyMonInBattle`, where the party menu has already read
  `wPartyMenuCursor`, so it sets `wMenuCursorY`), backs out of the party menu
  when a switch fails, and a watchdog (down/A/B/A after 40 presses with no
  hook) handles unexpected menus. Hook exceptions are counted (PyBoy swallows
  them). `battle_matrix.sh` takes `PLAYER=smart`. Whitney 2 against the
  user's party: 32 battles, all ended, Whitney won 24, no crashes or hook
  errors, 4 watchdog triggers.
- **2026-10-16**: Smart-player comparison of the ROM before today's AI work
  (279343fec) and after (3c7742bdc), 10 trainers x 12 seeds: AI wins 18 ->
  19 of 120. Six trainers never beat the user's level 76-78 party, so they
  give no signal; Koga 2 went 4 -> 10, Misty 2 5 -> 3, Whitney 2 6 -> 6,
  Jasmine 2 3 -> 0. Jasmine rerun with 24 seeds: 4 -> 3 wins, the player's
  Pokemon left 3.54 -> 3.33, so no regression (noise). Her behavior did
  change: Forretress Explodes and Curses more, and the new replacement
  choice sends Skarmory into the player's Steelix, where every attack is
  resisted and Whirlwind (encouraged with Spikes down) wins. `battle.py` now
  reports `player_left` and `enemy_left`.
- **2026-10-16**: Spikes in the Smogon switch-in race. A switch-in (also
  after a faint) now loses 1/8 of its max HP to Spikes on the AI's side
  unless it's a Flying type (`AISmogon_ApplyHealing`), replacing the flat
  `SMOGON_SPIKES_MARGIN` in `SwitchSmogon`, which ignored Flying types and
  replacements after a faint. New `ai_scenarios.py` cases (and a `chp`
  option for the candidates' HP): with equal matchups, Spikes make Pidgeot
  beat Raticate. The smart player now lays Spikes when it can (so the AI's
  side gets them at all); against it, 4 trainers x 72 seeds: AI wins 130 ->
  126 of 288, the player's Pokemon left 2.20 -> 2.21: neutral within noise
  (Koga 2 51 -> 40 with near-identical switch patterns, Misty 22 -> 26).
  A first run where the bot never laid Spikes, so the new code never ran,
  moved 45 -> 42 of 96 from RNG timing alone.
- **2026-10-16**: Tooling for future AI sessions. `build_rev.sh REV OUT`
  builds any commit (cached in `.revbuild/`). `pokedata.py` parses the game's
  constants and data for every Python tool (following `const_skip`,
  `const_next` and `shift_const`; `smart_player.py` uses it).
  `battle_harness.py` holds the battle setup and loop from `battle.py`
  (unchanged results, checked on 4 battles in both player modes) with
  `Battle.on()` so several callbacks can share a hook. `ai_trace.py` records
  and reports the Smogon AI's switch decisions and candidate scores;
  `ai_profile.py` times AI code in scanlines. `battle_compare.py` prints z
  (standard deviations of the change) for win rates and Pokemon left.
- **2026-10-16**: `engine_judge.py`: poke-engine (Foul Play's search engine,
  built for Gen 2 in `bots/pe-venv`) judges the Smogon AI's traced decisions.
  `ai_trace.py` now logs the full battle state for it (player's party, items,
  stats before stat changes, substatuses, screens, weather) and marks turns
  the AI used an item or the player had switched (`player_switched`: the
  AI's move was picked before the switch); its report no longer applies the
  player's stat changes twice (`wBattleMon`'s stats already include them).
  Checked: every move and species maps to an engine id, engine damage
  matches the cartridge formula on 103 of 106 real matchups, and two runs
  agree on 352 of 363 decisions. Against the user's OU team (48 battles,
  1336 decisions): mean regret 0.015, 42 clear disagreements (regret > 0.1).
  The patterns: a less accurate attack for a KO, switching out with a KO
  available (Tauros), Blissey healing instead of finishing a weakened
  Cloyster, and Rest users staying in asleep without Sleep Talk.
- **2026-10-16**: `AI_Smogon_SureKO`: of the attacks whose lowest roll KOs
  the player, the most accurate is greatly encouraged and the others
  discouraged (a priority attack first when the player is faster), from the
  engine judge's finding that the AI used Fire Blast on a 2 HP Steelix and
  Thunder over Earthquake for a KO (AI_Aggressive keeps the highest roll and
  ignores accuracy). The first version read the stale `wCriticalHit` flag
  through `AIDamageCalc` (double damage after any critical hit) and cost
  wins: Jasmine 2 10/48 -> 3/48 (z -2.1). With it cleared, 11
  `ai_scenarios.py` cases pass (one fails without the fix), the rule changes
  the AI's pick in 21 of 48 battles, and over 576 smart-player battles AI
  wins went 258 -> 253 (z -0.3, noise). About 2 frames per turn
  (`ai_profile.py`).
- **2026-10-16**: `SwitchSmogon` stays in when the move the AI picked KOs the
  player first (`AISmogon_PickedMoveKOsFirst`: a sure KO while faster, or
  with priority; only Perish Song at 1 overrides it), from the engine
  judge's Tauros that switched to Blissey with a KO on a 27 HP Cloyster.
  The sure-KO ranking moved into `AISmogon_RankLoadedMove`, which now also
  keeps `wCurDamage` (Counter reads it) and skips an asleep or frozen
  enemy: `AI_Smogon_SureKO` had been able to push a KO move over Sleep
  Talk. Checked: `sure_ko_test.py` (7 direct cases), `ai_scenarios.py`
  ALL OK (new asleep case), 4 trainers x 144 seeds: AI wins 253 -> 255 of
  576 (z +0.1), mid-battle switches 2.78 -> 2.74 per battle;
  `engine_judge.py`: switch-outs the engine calls clearly wrong 5 -> 2,
  both against a healthy Vaporeon.
- **2026-10-16**: Heal moves below half HP wait while the player can barely
  scratch the AI (`AISmogon_HealCanWait`): with no status, Leech Seed or
  Curse on it, if `SMOGON_HEAL_SAFE_HITS` (3) of the player's strongest
  attack (`AISmogon_ScoreMatchup`'s honest estimate) don't KO, the heal gets
  +1 instead of being encouraged. From the engine judge's Blissey using
  Softboiled at ~40% instead of finishing a weakened Cloyster (Surf: 41 HP).
  `ai_scenarios.py` gets `patkstat` (the test battle's player hits for
  almost nothing) and 4 heal cases, ALL OK. 4 trainers x 144 seeds: AI wins
  255 -> 251 of 576 (z -0.2, noise; rarely fires against the user's team);
  engine_judge: Blissey-heals-vs-Cloyster disagreements 3 -> 0, AI heals
  148 -> 134. 1-3 frames on turns it runs.
- **2026-10-16**: Sleeping Pokemon switch out more readily. In
  `SwitchSmogon`, the active Pokemon's matchup score takes the same sleep
  or freeze penalty as a switch-in (`AISmogon_PenalizeAsleepActive`), unless
  it wakes up this turn (waking up costs the turn, so a sleep counter of N
  loses N turns). And only boosts that help keep it in
  (`AISmogon_EnemyHasUsefulBoosts`): offensive ones, accuracy, evasion, and
  the defense the player's attacks hit, so Misty's Vaporeon asleep after
  Acid Armor no longer stays in against a Surf user. From the engine
  judge's sleeping Rest users that it would switch out. Also fixed
  `ai_scenarios.py` (sure-KO cases failed at random: the main loop's
  `wBattleMonHP = 999` landed mid-AI now that move choice takes several
  frames) and renamed `sure_ko_test.py` to `smogon_calls_test.py` (18 new
  cases). Checked: both suites ALL OK (scenarios 3 runs in a row), 4
  trainers x 144 seeds: AI wins 251 -> 245 of 576 (z -0.4, noise),
  mid-battle switches 2.64 -> 2.76 per battle; engine_judge: regret on
  asleep decisions 6.33 -> 2.37, clear should-have-switched 12 -> 3, clear
  disagreements overall 36 -> 25.
- **2026-10-16**: Setup credit in the KO race (`AISmogon_GetSetupBoost`,
  `AISmogon_SetupPower`): a Pokemon with Swords Dance (x2), or Curse,
  Sharpen, Meditate or Growth (x1.5), counts its attacks of that category
  boosted, a turn later, when the player can't phaze or Haze and
  `SMOGON_SETUP_SAFE_HITS` (4) of the player's strongest attack don't KO
  it. The last sleep case from the engine judge (Misty's Vaporeon asleep
  vs a Surf/Rest Vaporeon) wasn't about sleep: rerunning the engine
  without Tentacruel's Swords Dance made switching to it worth exactly as
  much as staying (0.23 each), with it 0.95. `ai_trace.py` logs each
  candidate's credit (`setup`). Checked: `smogon_calls_test.py` (15 new
  cases) and `ai_scenarios.py` ALL OK; 4 trainers x 144 seeds: AI wins
  245 -> 249 of 576 (z +0.2, noise); engine_judge: asleep regret 2.37 ->
  0.78, clear should-have-switched 3 -> 0, clear disagreements overall
  25 -> 19 (mean regret 0.011). Credit went mostly to Steelix and
  Forretress (Curse) vs Exeggutor and Snorlax, Venusaur (Growth) vs
  Vaporeon and Tentacruel (Swords Dance) vs Vaporeon.
- **2026-10-16**: `AI_Smogon_Weather`: Rain Dance and Sunny Day get +3
  when the weather powers up the player's attacks too: its revealed
  `RainDanceMoves` / `SunnyDayMoves`, or (until four moves are revealed)
  its `SmogonExpectedAttacks`: Water or 120-power Electric (Thunder) for
  rain, Fire or 120-power Grass (SolarBeam) for sun; a species without a
  list counts its types. The vanilla layer only checked the player's types,
  so Jasmine's Magneton kept giving the user's Zapdos a sure Thunder. 8 new
  `ai_scenarios.py` cases, ALL OK. 4 trainers x 144 seeds: Jasmine 2 AI
  wins 15 -> 31 of 144 (z +2.6, the first significant change in this
  series), total 249 -> 265 of 576 (z +0.9); Rain Dance used 1011 -> 221;
  engine_judge: Magneton vs Zapdos regret 0.97 -> 0.35. The judge's overall
  totals over 48 battles moved the other way (19 -> 49 clear
  disagreements), almost all in Koga 2, whose team has no weather move:
  the RNG reshuffle changes which positions come up (17 of Koga's 34 from
  one battle, Crobat using Wing Attack into a Steelix). Compare per
  pattern, not overall totals.
- **2026-10-17**: Stalemates. `AISmogon_ScoreMatchup` sets `wSmogonAIStalled`
  when neither side can KO the other (both `AISmogon_SideTurns` reach
  `SMOGON_MAX_TURNS`), and `AISmogon_ScoreActive` keeps it for the active
  Pokemon (`wSmogonAIActiveStalled`). In a stalemate, `SwitchSmogon` takes
  any better matchup (like `wEnemyAIMovesSpent`), and Haze or phazing is no
  longer a reason to stay against a boosted player. From the engine
  judge's Koga 2 battle where Crobat (Wing Attack) and the user's Steelix
  (Earthquake, Curse; the AI assumes Leftovers) couldn't hurt each other:
  Crobat stayed at an even 128 against Qwilfish's 136, then Hazed every
  Curse. `ai_trace.py` logs the flag in each decision's scores. Checked:
  `smogon_calls_test.py` builds that position from the trace (and two
  controls) and gets the flag right, ALL OK; `ai_scenarios.py` ALL OK; 4
  trainers x 144 seeds: AI wins 265 -> 271 of 576 (z +0.4); Koga 2, Crobat's
  trainer, went 103 -> 93 (z -1.3) there, but over 432 seeds 301 -> 302
  (z +0.1; seeds 145-432 alone +1.0), with Crobat switching out 206 -> 226
  times. `battle_matrix.sh` got `FIRST_SEED` to add seeds to a run. The Crobat battle didn't come up again in 48 traced battles;
  the flag fired in 41 decisions there (mostly Blissey vs the user's
  Vaporeon), regret 0.98 in all.
- **2026-10-17**: `AI_Smogon_Asleep`: fast asleep (sleep counter 2+, so it
  won't wake up this turn) with a usable Sleep Talk or Snore, every other
  move gets `AIDiscourageMove`; awake, Sleep Talk and Snore do (they fail,
  and AI_Smart encourages Sleep Talk unless the counter is 1). Found by
  ranking engine_judge disagreements over 144 battles: Misty's Kingdra and
  Lanturn picked Rest, Surf, Ice Beam or Thunder while asleep. Checked:
  over the same 144 battle seeds, asleep-with-Sleep-Talk decisions that
  picked another move 25 -> 0 (2 left had Sleep Talk at 0 PP); 5 new
  `ai_scenarios.py` cases (one older sure-KO case now expects Ice Beam
  discouraged while asleep), both suites ALL OK; 4 trainers x 144 seeds: AI
  wins 271 -> 262 of 576 (z -0.5), Sleep Talk used 595 -> 1155. Jasmine 2
  went 33 -> 15 there (z -2.8) although her team has no Sleep Talk or
  Snore (no score changes, only the RNG timing): over 432 seeds 82 -> 69
  (z -1.2; seeds 145-432 alone 49 -> 54, z +0.5).
- **2026-10-17**: `AI_Smogon_Explosion` no longer trades a Pokemon that wins
  its matchup by attacking (score above `SMOGON_MATCHUP_EVEN`) for a threat
  or a boosted player; the doomed-and-outsped trade and the trade for
  something no teammate beats are unchanged. The engine judge's most
  consistent disagreement (16 clear in 63 of 144 battles): Koga's Gengar
  exploding at full HP into Zapdos, which it outspeeds and hits with Ice
  Punch (Gengar's score 132). Checked: `smogon_calls_test.py` builds
  Gengar vs Zapdos and Cloyster vs Zapdos from traces (the old code
  explodes with both, the new one only with Cloyster and a doomed Gengar),
  both suites ALL OK; over the same 144 battle seeds, Explosions 71 -> 59,
  their regret 3.42 -> 1.52, clear 16 -> 3; 4 trainers x 144 seeds: AI wins
  262 -> 279 of 576 (z +1.0), Gengar's Explosions 339 -> 218. The 3 left:
  Gengar (124, slightly losing) into a full-HP Vaporeon, which Explosion
  doesn't surely KO (lowest roll 292 of 327).
- **2026-10-17**: Three engine-judge patterns at once (they share
  `smogon.asm`):
  - A trade Explosion (for a threat, a boosted player, or something no
    teammate beats) needs a sure KO (`AISmogon_LoadedMoveKOs`, split out of
    `AISmogon_RankLoadedMove`), unless the exploder is losing by more than
    `SMOGON_BOOM_KO_MARGIN` (8): Gengar (124) no longer explodes into a
    full-HP Vaporeon it can't surely KO, Misty's Cloyster (104) still trades
    with Zapdos. Requiring the KO for Cloyster too cost Misty 2 20 wins of
    144 (z -2.5).
  - Toxic is only encouraged against something our attacks need
    `SMOGON_TOXIC_MIN_TURNS` (4) or more to KO (`wSmogonAIOurTurns`, from
    `AISmogon_ScoreMatchup`), else +1: Tentacruel used Toxic on Exeggutor
    instead of Sludge Bomb.
  - No setup move while our Spikes aren't down and the player has Pokemon
    left to switch in (`AISmogon_SpikesFirst`): Forretress used Curse in
    front of Snorlax.
  - `AIHasMoveEffect` overwrites `wEnemyMoveStruct` (it loads every move),
    which broke the move being scored: Whitney's Snorlax used Curse 2.5x as
    often (her AI wins 94 -> 67, z -3.2) and the Explosion KO check measured
    the last move. `AISmogon_EnemyHasMoveEffect` reads the effects from
    `Moves` instead; the Spikes checks in `AISmogon_SpikesFirst` and
    `AI_Smogon_Explosion` use it.
  - `ai_trace.py` records every move's final score (`move_scores`). Matchup-
    dependent tests moved from `ai_scenarios.py` (its test battle's enemy
    changes between runs) to `smogon_calls_test.py`, which builds positions
    from traces; it now also checks that the move being scored is kept, and
    fails on the buggy builds.
  - Checked: both suites ALL OK; 4 trainers x 144 seeds: AI wins 279 -> 293
    of 576 (z +0.8; Koga 2 107 -> 123, z +2.4; the others within 2 wins);
    engine regret over the same 144 battle seeds: Explosion 1.46 -> 0.84,
    Toxic 2.00 -> 0.15, Forretress's Curse 1.74 -> 0.50.
- **2026-10-17**: Healing can also wait when we KO first.
  `AISmogon_HealCanWait` now also returns carry when one of the enemy's
  attacks with PP left surely KOs the player in two hits
  (`AISmogon_KOsInTwoHits`: `AISmogon_RankLoadedMove` against half the
  player's HP, at current battle stats, keeping `wEnemyMoveStruct`) and the
  player's strongest attack doesn't KO us first (one hit if we're faster,
  two if not). Quarter heals (Synthesis at night, etc.), which were left to
  AI_Smart, also get +1 when healing can wait. The engine judge's most
  consistent pattern (7 clear in 6 battles): Koga's Venusaur at +2 Sp.Atk
  and a third of its HP using Synthesis on a full-HP Vaporeon instead of
  Razor Leaf, which now 2HKOs. Not the Ice Beam fear I first guessed: the
  AI's estimate of Vaporeon's best hit on it is Surf (48).
  - Tried first: counting the active Pokemon's battle stats (stat stages,
    burn, paralysis) in `AISmogon_ScoreMatchup`. It fixed Venusaur but cost
    Whitney 2 95 -> 69 wins of 144 (z -3.1): boosted Curse Miltank stopped
    using Milk Drink. Counting only our boosted Attack/Sp.Atk still lost
    (66, z -3.4), so the matchup scoring stays on party stats.
  - Also found: the Blissey-switches-out-of-Steelix pattern (4 clear) is
    the player's Steelix having used all its Earthquake PP, which the
    engine knows and the AI doesn't.
  - Checked: both suites ALL OK (`ai_scenarios.py`'s "heal above half" now
    expects +1 for the two quarter heals); 4 trainers x 144 seeds: AI wins
    293 -> 293 of 576 (no trainer more than 4 apart); engine regret over the
    same 144 battle seeds: Venusaur vs Vaporeon 1.32 -> 0.31 (clear 7 -> 0),
    all heal moves 5.56 -> 4.53 (clear 13 -> 6), total 44.9 -> 40.7.
- **2026-10-17**: Tools for AI work. `ai_check.sh [ROM] [BASE_REV]` runs
  what each Smogon AI fix this session needed by hand (test suites, 576
  `PLAYER=smart` battles, 144 traced battles and the engine judge, for the
  new ROM and the base) and prints one report, caching each ROM's results
  in `.aicheck/`. `engine_judge.py --patterns OUT [BASE]` (the scratch
  `patterns.py`, plus a before/after view) ranks disagreements by action and
  matchup, and with `--report` no longer needs poke-engine. `save_ram.py`
  makes the harnesses' cartridge RAM from the save: the user's latest save
  had the clock-reset flag set (`sRTCStatusFlags` $80), so Continue asked to
  reset the clock and no headless battle started. CLAUDE.md points at
  `pokecrystal_wiki/`.
- **2026-10-17**: Three test tool fixes. `ai_trace.py` records the
  active and best switch-in scores as None when a decision didn't compute
  them (hooks on `AISmogon_ScoreActive` and `AISmogon_FindBestSwitchIn`):
  a Pokemon its boosts kept in used to show the previous matchup's score,
  which misled the Venusaur investigation. `game_call.py`'s `call` takes
  `poke={...}`, memory written just before the call, for what the overworld
  rewrites every frame (the time of day): `smogon_calls_test.py` now tests
  Synthesis at night and by day. `ai_scenarios.py -k TEXT` runs only the
  matching cases (seconds instead of 3.5 minutes); its restarts now resume
  the switch-in and move power phases instead of rerunning them, and "heal
  above half" gives the player only Splash so it no longer depends on the
  test battle's Pokemon (the committed version failed it in one run).
- **2026-10-17**: Smogon AI: attacks compared by average damage. The
  engine judge's top matchup was Koga's Qwilfish vs the save's Cloyster, and
  its most concentrated pattern Hydro Pump where the engine used Sludge Bomb
  (8 clear in 14 decisions, Koga's Qwilfish and Misty's Tentacruel). The
  pick came from `AI_Aggressive`, which keeps the attack with the highest
  damage roll: Hydro Pump's 70 beat Sludge Bomb's 60 on Cloyster by one
  score point, but at 80% accuracy it averages 56 (Misty's +2 Tentacruel:
  Sludge Bomb ~84 vs 72). In Challenge Mode `AI_Aggressive` now scales the
  damage by the accuracy (`AISmogon_ExpectedDamage`), with Lock-On and
  Thunder in rain counting as sure hits (`AISmogon_LoadedMoveAccuracy`,
  shared with `AISmogon_RankLoadedMove`); Normal Mode is unchanged.
  - Checked: both suites ALL OK (new `smogon_calls_test.py` "aggressive"
    cases fail on the old build); 4 trainers x 144 seeds: AI wins 293 ->
    290 of 576 (Koga 119 -> 129 z +1.7, Misty 57 -> 52 z -0.6, Whitney 95 ->
    87 z -1.0, Jasmine 22 -> 22); Hydro Pump -> Sludge Bomb 1.79 -> 0.22
    regret (clear 8 -> 1), Hydro Pump overall clear 9 -> 2. Total regret
    went 40.95 -> 50.47, mostly a new Crobat vs Steelix position (18 clear,
    all in one battle, KOGA_2_13: reshuffled RNG, as Crobat's only attack
    is the 100%-accurate Wing Attack).
- **2026-10-17**: Smogon AI: Acid Armor only against physical attackers.
  Engine judge pattern: Misty's Vaporeon using Acid Armor on the save's
  Cloyster where the engine Surfs (4 clear, 4 battles), then Surfing anyway.
  `AI_Smogon_Setup` treated it like any boost; it now discourages Acid Armor
  and Barrier against a special attacker and Amnesia against a physical
  one. `AISmogon_PlayerIsPhysical` (also used by screens, Counter/Mirror
  Coat, Growl/Charm and staying in on boosts) now counts the species'
  `SmogonExpectedAttacks` when nothing is revealed, before the stats:
  Cloyster's Attack is above its Sp.Atk, but it attacks with Surf (3 of
  the 4 battles had nothing revealed). Of the save's party only Cloyster
  changes.
  - Checked: both suites ALL OK (new `smogon_calls_test.py` "physical" and
    "setup" cases; the old stat-fallback cases now use Ditto, which has no
    expected attacks); 4 trainers x 144 seeds: AI wins 290 -> 283 of 576
    (Jasmine 22 -> 28 z +0.9, Koga 129 -> 120 z -1.5, Misty 52 -> 54,
    Whitney 87 -> 81 z -0.7); Acid Armor -> Surf clear 4 -> 0, Vaporeon vs
    Cloyster regret 1.49 -> 0.06; total regret 50.5 -> 47.5.
- **2026-10-17**: Claude tools: the smart player uses its status moves. The
  headless `smart_player.py` only attacked, used Spikes and switched, so the
  AI was judged against a player who never used Curse, Rest, Sleep Talk,
  Sleep Powder, Roar, Toxic or Explosion (the save's team is built on them).
  It now picks them by simple rules (Sleep Talk while asleep, Rest when low
  or about to be KO'd, Explosion when about to be KO'd anyway, Roar on a
  boosted foe, one sleeper at a time, Curse/Growth when it outlasts the foe
  and can't be phazed, Toxic on long fights). `SMART_PLAYER=basic` keeps the
  old player; `ai_check.sh`'s cache key includes `smart_player.py` (except
  in basic mode), so the old caches stay valid for it.
  - Same ROM (`d9162c4d0`), old player -> new: AI wins 283 -> 221 of 576
    (Jasmine 28 -> 9 z -3.3, Misty 54 -> 34 z -2.6, Whitney 81 -> 65 z
    -1.9, Koga 120 -> 113 z -1.0); watchdog trips 79 -> 82, no hook errors.
    Judge with the new player: 4496 decisions, total regret 51.91, with new
    patterns the old player never set up (Forretress exploding into a +2
    Defense Snorlax, Tentacruel vs Vaporeon/Cloyster). Win rates from before
    this aren't comparable with later ones.
- **2026-10-17**: Smogon AI: no Explosion into raised Defense unless it
  KOs. First pattern with the new smart player: Jasmine's Forretress
  exploding on the save's Snorlax after two Curses, where the engine Curses
  back (3 clear, 3 battles). +2 Defense cancels Explosion's Defense halving,
  but `AI_Smogon_Explosion`'s "clearly losing" exception (made for Misty's
  Cloyster vs Zapdos) skipped the sure-KO requirement. With the player's
  Defense raised the trade now needs a sure KO.
  - Checked: both suites ALL OK (new `smogon_calls_test.py` Forretress vs
    +2 Snorlax cases fail on the old build); 4 trainers x 144 seeds: AI
    wins 221 -> 229 of 576 (Jasmine 9 -> 20 z +2.2, Koga 113 -> 111, Misty
    34 -> 33, Whitney 65 -> 65); Explosion -> Curse clear 3 -> 0, Forretress
    vs Snorlax regret 1.21 -> 0.77; total regret 51.9 -> 49.5.
- **2026-10-17**: Smogon AI: Hidden Power's bonus only for the strongest
  attack. Engine judge's top matchup: Koga's +1/+2 Venusaur vs the save's
  Snorlax, Hidden Power Fire where the engine uses Razor Leaf (43
  decisions, 1.34 regret). Vanilla `AI_Smart_HiddenPower` encourages any
  neutral Hidden Power of base power 70, which cancelled `AI_Aggressive`'s
  discouragement of the weaker attack: a coin flip against the STAB Razor
  Leaf. In Challenge Mode the bonus now needs Hidden Power to be the
  strongest attack (`AIStrongestMove`, AI_Aggressive's search as a
  routine); just dropping it made Venusaur tie Hidden Power with Growth and
  Synthesis on Zapdos (regret 0.25 -> 5.35). Normal Mode is unchanged. The
  Snorlax-in-KO-range cases (both KO; the engine prefers Razor Leaf for a
  Vaporeon switch-in it can see) stay.
  - Checked: both suites ALL OK (new `smogon_calls_test.py` "hidden power"
    cases: Snorlax fails on the old build, Zapdos keeps the bonus); 4
    trainers x 144 seeds: AI wins 229 -> 206 of 576 (Misty 33 -> 20 z -2.0,
    Jasmine 20 -> 13, Whitney 65 -> 56, which has no Hidden Power user,
    Koga 111 -> 117); 288 more seeds on Misty and Jasmine: Misty 58 -> 54
    (z -0.4), Jasmine 34 -> 47 (z +1.6), so over 432: Misty z -1.5, Jasmine
    +0.6. Hidden Power -> Razor Leaf on Snorlax clear 3 -> 0, Venusaur vs
    Snorlax regret 2.89 -> 1.08; Quagsire 2.35 -> 1.59, Magneton 2.09 ->
    1.65; total regret 49.5 -> 54.9 (spread over unrelated matchups). Move
    layers at most 14.0 frames (was 12.4) for Hidden Power users.
- **2026-10-17**: Smogon AI: keep boosting through a healer. Misty's +2
  Tentacruel vs the save's Rest/Sleep Talk Vaporeon used Sludge Bomb where
  the engine Swords Dances again (3 clear, 3 battles; Tentacruel vs Vaporeon
  10 clear in 24 decisions). +2 Sludge Bomb (153-180) doesn't 2HKO a 327 HP
  Vaporeon, so Rest outlasts it. The matchup score (which ignores boosts)
  is below even only because Vaporeon out-heals our unboosted attacks, and
  `AI_Smogon_Setup` read that as "don't set up". Now Swords Dance and
  Growth get `AISmogon_GreatlyEncourage` (enough to beat `AI_Setup`'s +2
  after the first turn), skipping the matchup check and
  `SMOGON_SETUP_GOAL`, when the player out-heals us
  (`wSmogonAIOurTurns` = `SMOGON_MAX_TURNS`), three of its best hits don't
  KO us, and our strongest boosted attack (`AIStrongestMove`) x 7/4 is
  below its max HP. Curse is left out (Curse changes cost Whitney before).
  - Checked: both suites ALL OK (new `smogon_calls_test.py` "heal setup"
    cases at +2 fail on the old build; +4 and below half HP unchanged);
    4 trainers x 144 seeds: AI wins 206 -> 229 of 576 (Misty 20 -> 36 z
    +2.4, Koga 117 -> 125, Jasmine 13 -> 16, Whitney 56 -> 52 z -0.5).
    Sludge Bomb -> Swords Dance on Vaporeon clear 3 -> 1, Tentacruel vs
    Vaporeon 10 -> 6 clear; total regret 54.9 -> 58.5 over 4530 decisions
    (more Misty battles reach Tentacruel vs Cloyster: Sludge Bomb ->
    Substitute 2 -> 6 clear, an older pattern). Move layers at most 8.8
    frames on Misty seed 35.
