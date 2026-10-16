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
