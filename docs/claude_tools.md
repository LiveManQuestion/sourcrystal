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
`sourcrystal.sav`; its first 32 KB is the cartridge RAM. Make it with
`save_ram.py [SAVE] OUT` (`python3 tools/claude/save_ram.py SCRATCH/user.ram`),
not `head -c 32768`: it also clears `sRTCStatusFlags`. A set flag (the
emulator's clock was reset, as in the user's save of 2026-10-16) makes
Continue ask to reset the clock, a prompt the harnesses' boot button presses
don't expect, so battles never start (`"started": false`). Never write over
the user's save files.
- `ai_check.sh [ROM] [BASE_REV]` (defaults: `sourcrystal.gbc`, `HEAD`):
  everything to check a Smogon AI change, in one report: both test suites,
  `PLAYER=smart` battles on Koga 2, Misty 2, Whitney 2 and Jasmine 2
  compared with `battle_compare.py`, and `engine_judge.py --patterns` over
  traced battles, compared with the base. Options (environment): `SEEDS=144`
  battles and `TRACE_SEEDS=36` traced battles per trainer, `ITERS=600000`
  judge iterations per decision (`JOBS=11` at a time; `ITERS=0` uses the
  old `MS=400` timed search), `TRAINERS=...`, `SAVE=...`, `NO_JUDGE=1`.
  Each ROM's results are cached in `.aicheck/` (git-ignored) by its
  contents, the save, `smart_player.py` and the options (judge files by
  their search settings), so the base runs once per commit; about 25
  minutes per uncached ROM (traces 2, battles 6, judge up to 19; the tests
  run alongside). The traced battles are the battles' first seeds, so
  those come from the traces, and every judged position is kept in
  `.aicheck/judge-cache-i<ITERS>.jsonl` (shared by all ROMs: the engine only
  sees the position), so positions an earlier run reached aren't searched
  again. Run it in the background and read the report; tee it to a file
  to keep it.
- `ai_scenarios.py ROM SYM RAM [-k TEXT]`: exact-state checks of AI_Smogon's
  scores, the heal-move multiplier the engine picks, the switch-in choice by
  type (`switch_cases`) and the power AIGetEnemyMove loads (`hp_cases`).
  Restarts itself if the test battle ends, resuming each phase where it
  stopped; last line `RESULT: ALL OK`. About 3.5 minutes; `-k heal` runs only
  the cases whose name contains "heal" (seconds). Add cases there.
  `AI_Smogon` is far-called: match the stack pointer, not just the address,
  when hooking a return.
- `damage_diff.py VANILLA.gbc VANILLA.sym ROM.gbc ROM.sym [N]`: runs the damage
  code on the same random inputs in both ROMs. Expect 0 mismatches.
- `smoke.py ROM RAM OUTDIR`: boot, title, Continue, overworld and menus, with
  a screenshot hash per step; diff two ROMs' output (the clock changes some).
  PyBoy draws Bill's PC as a white screen; test it through RAM.
- `battle_harness.py`: the battle setup shared by `battle.py`, `ai_trace.py`
  and `ai_profile.py` (`Battle(...)`, `.on(label, fn)`, `.start()`,
  `.run(frames)`, `.log_switches()` for `battle.py`'s switch log and
  routine counts). `.on()` lets several callbacks share a label: PyBoy
  allows one hook per address and raises "Hook already registered"
  otherwise.
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
    the best replacement after a faint. It sees the enemy's moves. It plays
    the save team's status moves by simple rules (`status_move`): Sleep Talk
    while asleep, Rest when low, Explosion when about to faint, Roar on a
    boosted foe, Sleep Powder (Sleep Clause), Spikes, Curse/Growth while the
    foe needs 4+ hits and can't phaze or Haze, Toxic on walls; each counted
    in `player_actions`. `SMART_PLAYER=basic` (environment, also for
    `battle_matrix.sh` and `ai_check.sh`) plays only attacks and Spikes, like
    the player before 2026-10-17, and its results keep the old cache keys. It drives the menus by writing their cursor variables from
    hooks; a watchdog gets it out of unexpected menus. `player_actions` in the
    JSON counts its attacks, switches, replacements, watchdog triggers and
    hook errors (should be 0; PyBoy swallows exceptions in hooks).
- `battle_matrix.sh OUTDIR RAM ROM1 [ROM2]` (`SEEDS=6`, `TRAINERS=...`,
  `PLAYER=smart` for `--smart`, `FIRST_SEED=145 SEEDS=432` to add seeds
  145-432 to an earlier run; combine the `.jsonl` files): 9 trainers × 6 seeds, ~15 min per ROM; give
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
  decision (its branch labels, scores (None when the decision didn't compute
  them, like a Pokemon its boosts keep in: the WRAM then holds an older
  matchup's), the move picked and every move's score
  after all AI layers (`move_scores`), both sides' state, the stalemate flag),
  every switch-in candidate's score with its attack lists, healing blocks and
  setup credit,
  and every enemy switch-in, as one JSON line. `ai_trace.py report
  TRACES...`: switches, replacements, each candidate's average score against
  each player Pokemon, and stay-ins that an independent damage race
  (`smart_player.race`) calls clearly wrong.
- `engine_judge.py TRACE.jsonl... [--ms 500] [--threads 4] [--json OUT]`
  (or `--iterations N [--jobs 11] [--cache FILE]`: N iterations on one
  thread per decision, decisions in parallel; poke-engine's threads scale
  badly, 11 give only 3.3x one, so this is twice as fast at the same depth;
  the cache, keyed by the engine's `State.to_string()`, searches each
  position once): a
  second opinion on every `SwitchSmogon` decision in `ai_trace.py` traces
  from poke-engine, the Gen 2 search engine behind the Foul Play bot
  (`bots/foul-play-main`). It rebuilds each position (both parties, items,
  stat changes, volatiles, screens, Spikes, weather), runs MCTS with the AI as
  side one and prints the agreement rate, regret (the engine's value of its
  own action minus its value of the AI's, as win chances 0 to 1), the biggest
  disagreements and the stay/switch disagreements by matchup. `--report OUT`
  prints saved results again; `--patterns OUT [BASE]` ranks the
  disagreements of saved results by total regret, grouped by action,
  matchup and both (a pattern worth fixing has many clear disagreements over
  several battles), and with BASE prints each top pattern before and after;
  neither needs poke-engine; `--check` confirms that every move, species and
  item maps to an engine id (unknown ids silently become NONE). Moves are
  all the same "stay" while the AI's Pokemon is asleep or frozen, except
  Sleep Talk and Snore. After the player switches, the AI's move was already
  picked (`AIChooseMove` runs at the start of the turn, `SwitchSmogon` after
  the player's switch), so only staying in with that move and the switches
  are compared. With 500 ms per decision the engine picks the same
  action in about 97% of reruns.
  - Setup: run it with `bots/pe-venv/bin/python`, a uv venv (Python 3.13)
    with `poke-engine==0.0.48` built from source for Gen 2 (needs cargo):
    `uv venv -p 3.13 bots/pe-venv && VIRTUAL_ENV=bots/pe-venv uv pip install
    -p bots/pe-venv/bin/python poke-engine==0.0.48 --no-binary poke-engine
    --config-settings="build-args=--features poke-engine/gen2
    --no-default-features"`. The PyPI wheel is Gen 4.
  - Caveats: the engine sees the player's whole party, so some disagreements
    are ones the AI couldn't have avoided. It simulates Showdown's Gen 2: its
    damage matched the cartridge formula's max roll on 103 of 106 real
    matchups (the rest were 1-point rounding), but Fly (90), Petal Dance
    (120) and Tackle (40) keep their later power; Hidden Power counts as 70
    power and sleep turns start from 0. Items it doesn't know, like the
    Sitrus Berry, do nothing (`--check` lists the ones it knows; Sour
    Crystal's renamed items, like the Lum Berry, are mapped back to Gen 2's).
  - Comparing two ROMs: compare the pattern a change targets (the
    decisions of one matchup or move), not the overall totals. Any code
    change reshuffles the battles' RNG, so different positions come up:
    a weather fix that never touched Koga 2's team moved his clear
    disagreements from 9 to 34, half of them from one battle.
  - Oak and Safari (also in `bots/`) only simulate Gen 1.
- `ai_profile.py ROM SYM RAM TRAINER SEED [SPAN...]`: time AI code in
  scanlines (154 per frame): by default the switch decision, the switch-in
  search and the parts of a matchup score; `START:END1|END2=name` for others.
  A switch decision should stay within about 8 frames.
- `storage_test.py ROM SYM RAM [SEED] [STEPS]`: model-based test of the PC
  boxes (moves, saves, resets, interrupted saves). Last line `RESULT: OK`.
  `game_call.py` calls ROM functions from Python: `Game(rom, sym, ram)`,
  `.boot()`, `.call(name, A=..., HL=..., poke={...})`. The overworld rewrites
  some WRAM every frame (`wTimeOfDay` and `hHours`, from the clock), so set
  those with `poke`, written just before the call starts.
- `smogon_calls_test.py ROM SYM RAM`: calls Smogon AI helpers on hand-made
  battle states: `AISmogon_PickedMoveKOsFirst` (its answer, and that it
  keeps `wEnemyMoveStruct`, `wCurDamage` and `wCriticalHit`),
  `AISmogon_PenalizeAsleepActive`, `AISmogon_EnemyHasUsefulBoosts`,
  `AISmogon_GetSetupBoost`, `AISmogon_SetupPower`, the stalemate flag of
  `AISmogon_ScoreActive`, `AI_Smogon_Explosion`, `AI_Smogon_Toxic`,
  `AISmogon_SpikesFirst` and `AI_Smogon_Heal` (on positions built from
  traces, against the save's party). Last line `RESULT: ALL OK`. Put tests of logic that
  depends on the matchup here, not in `ai_scenarios.py`: its test battle's
  enemy and its 999-Defense player change from run to run. Add cases
  there for helpers `ai_scenarios.py` can't reach (it only reads move
  scores).

`stadium2/` runs Pokémon Stadium 2 in mupen64plus (`docs/stadium2.md`).

`peephole.py` applies the pret wiki's "Optimizing assembly code" peepholes
(skipping timing-sensitive, RAM-copied, link and printer code); then run
`fix_jr.sh` until all four ROMs build. Already applied in 342bbfb61.
