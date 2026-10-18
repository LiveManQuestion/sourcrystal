# Smogon AI: engine judge handoff

Notes for the next Claude session working on the Smogon AI (Challenge Mode
trainer AI) with the engine judge. Updated 2026-10-18 after the free-setup fix, branch
`smogon-ai`. Read CLAUDE.md, `docs/battle_ai.md` and `docs/claude_tools.md`
first; `docs/claude_changelog.md` has the reasoning behind every fix below.

To pick up where the last session stopped: on a clean tree, run
`tools/claude/ai_check.sh` (HEAD's ROM is cached, so the report comes back
at once), read its "matchup and AI action -> engine action" table next to
the candidates below, and start the loop at step 2.

## Where things stand

Fixed this way so far (each one an engine-judge pattern, newest last; see the
changelog): sure-KO move choice, staying in to KO first, healing only when
threatened, sleeping Pokemon switching out, setup credit, Rain Dance
(Magneton vs Zapdos), stalemates (Crobat vs Steelix), Sleep Talk, Explosion
only when not winning, sure-KO Explosion trades, Toxic only for walls,
Spikes before setup, and not healing when a two-hit KO comes first (Venusaur
vs Vaporeon, `a65dbedd0`), and comparing attacks by damage times accuracy
in Challenge Mode (Qwilfish's Hydro Pump vs Cloyster, `91187591c`), and
Acid Armor only against physical attackers, with unrevealed attackers
judged by their expected attacks (Vaporeon vs Cloyster, `d9162c4d0`), and
no Explosion into raised Defense without a sure KO (Forretress vs Curse
Snorlax, `9362c639c`), and Hidden Power's AI_Smart bonus only when it's the
strongest attack (Venusaur vs Snorlax, `e3e9c0641`), and Swords Dance /
Growth through a player that out-heals our unboosted attacks (Misty's
Tentacruel vs Rest Vaporeon, `e79f45c49`), and Substitute against a likely
Explosion (Misty's Tentacruel vs Cloyster, `7451bb297`), and Swords Dance
setup credit with two safe hits (Tentacruel and Kingdra vs Vaporeon,
`bebf560a6`), and no setup when our attacks already 2HKO (Qwilfish vs
Cloyster, `869aa0388`), and free setup behind a Substitute in front of a
Pokemon that can't attack (Misty's Tentacruel vs a Rest Snorlax).

The headless smart player now uses its status moves (Curse, Rest, Sleep
Talk, Sleep Powder, Roar, Toxic, Explosion); `SMART_PLAYER=basic` is the old
attack-only player. It beats the AI far more often, so win rates from
before it aren't comparable.

Last measured (4 trainers x 144 seeds, the user's party, new player), after
the free-setup fix: AI wins 235 of 576. Koga 2 119/144, Whitney 2 51,
Misty 2 48, Jasmine 2 17 (the 144-seed numbers swing by ~10 from RNG
timing alone; Jasmine swung 20 of 432 on a build that didn't change her
decisions). Engine judge (600k iterations per decision) over 144 traced
battles: 4494 decisions, total regret 50.98. The cache for this ROM is
`.aicheck/fe010ce29ba6223a`, judge in `judge-i600000.jsonl`.

## The loop

1. Find a pattern: `tools/claude/ai_check.sh` (no arguments: the working
   tree's `sourcrystal.gbc` against `HEAD`). It runs the tests, 576 battles
   and the judge, and prints `engine_judge.py --patterns`. Its cache
   (`.aicheck/`, git-ignored) persists between sessions: on a clean tree
   both sides are `HEAD`'s ROM, already cached, so the report is instant
   and its pattern tables are what to pick from. An uncached ROM takes
   about 25 minutes: start it in the background. The cache misses (and the
   base reruns) when `smart_player.py`, the save (`sourcrystal.sav`: playing
   and saving changes it) or the options change, or if `.aicheck/` is
   deleted (`git clean -x`).
2. Pick a concentrated pattern: many clear disagreements over several
   battles in one matchup and action ("matchup and AI action -> engine
   action" table). Big totals spread thin over many decisions are noise.
3. Understand it before fixing it. Read the decisions
   (`.aicheck/<key>/judge-i600000.jsonl`, `--report`, the traces in
   `.aicheck/<key>/traces/`: `move_scores`, `path`, `scores`) and rebuild the
   position in `tools/claude/smogon_calls_test.py` (`set_ot`, `set_player`,
   `g.call(..., poke=...)`) to read what the AI computed. My first guess
   was wrong more than once (Venusaur: not an Ice Beam fear, a tie with an
   unboosted KO race).
   A pattern from one run can be a few unlucky battles: trace and judge
   more seeds on the same ROM before fixing (seeds 37-108 of one trainer:
   `ai_trace.py run ROM SYM RAM "KOGA 2" SEED` per seed into a folder, 12
   at a time, then `engine_judge.py FOLDER/*.jsonl --iterations 600000
   --jobs 11 --cache .aicheck/judge-cache-i600000.jsonl --json OUT`, with
   the ROM, SYM and RAM from the `.aicheck/<key>/` folder; about 10 minutes
   per 72 battles). For a borderline win rate, `battle_matrix.sh` with
   `FIRST_SEED=145 SEEDS=432` on both ROMs, then `battle_compare.py`.
4. Rule out what the AI can't know. The engine sees the player's whole party,
   moves, items and PP. Example: Blissey switching out of Steelix (4 clear)
   was Steelix having used all its Earthquake PP.
5. Fix in `engine/battle/ai/smogon.asm` / `smogon_switch.asm` / `items.asm`,
   add `smogon_calls_test.py` cases that fail on the old build, build all
   four ROMs (`make -j16 all`), then `ai_check.sh` again. Accept only if
   no trainer drops with |z| >= 2 and the targeted pattern's clear count
   falls. Compare per pattern, not totals: any code change reshuffles the
   RNG.
6. Changelog entry, then commit when the user says so (they review each fix
   and say "commit").

## Candidate patterns (600k-iteration judge, after the free-setup fix)

Clear disagreements (regret > 0.1) by matchup, AI action and engine action:

```
clear decisions regret
  10   28   2.35  TENTACRUEL vs ZAPDOS    surf -> switch
   3   13   0.78  TENTACRUEL vs VAPOREON  sludgebomb -> gigadrain
   3   16   0.89  PORYGON2   vs STEELIX   recover -> icebeam
   3    5   0.96  QWILFISH   vs CLOYSTER  curse -> sludgebomb
```

Tentacruel vs Zapdos (Surf where the engine switches) grew 6 -> 10 with
the last fix's reshuffle and is now the most concentrated: trace more Misty
seeds first. Koga's Tentacruel vs Vaporeon (Giga Drain) is
the KO-range kind. Qwilfish's Curse on a full-HP Cloyster appeared only
after an RNG reshuffle (no Substitute involved). Venusaur vs Snorlax in KO
range is left: the gap disappears with the player's bench removed.

## Pitfalls already hit

- `AIHasMoveEffect` (and anything calling `AIGetEnemyMove`) overwrites
  `wEnemyMoveStruct`, the move being scored. Save and restore it
  (`AISmogon_PickedMoveKOsFirst`, `AISmogon_KOsInTwoHits`) or read `Moves`
  directly (`AISmogon_EnemyHasMoveEffect`). Whitney lost 27 of 144 to this.
- `AIDamageCalc` doubles damage if the stale `wCriticalHit` is set; clear
  and restore it.
- Counting the active Pokemon's battle stats (boosts) in
  `AISmogon_ScoreMatchup` cost Whitney ~28 of 144 (Curse Miltank stopped
  healing). Changes to the matchup score ripple everywhere; prefer local
  fixes.
- Requiring a sure KO for every Explosion trade cost Misty 20 of 144.
- A fix can switch off an earlier one: the Swords Dance setup credit made
  the matchup score stop seeing that a Rest Vaporeon outheals us, which
  `.BreaksHealing` relied on. The old fixes' `smogon_calls_test.py` cases
  caught it; run them on every change.
- Before blaming a change for a trainer's drop, compare its traces with
  the base's: if every first difference is a different position or one of
  vanilla's random score points, it's RNG (Jasmine, 62 -> 42 of 432).
- Removing a score bonus can also remove what put a move ahead of the
  status moves at 20 (Hidden Power on Zapdos tied with Growth): make it
  conditional instead.
- `ai_scenarios.py`'s test battle varies between runs: put matchup-dependent
  tests in `smogon_calls_test.py`. `ai_scenarios.py -k TEXT` runs one case.
- Make the test RAM with `tools/claude/save_ram.py`, never by writing to the
  user's saves. The user's save has the clock-reset flag set, which stops
  headless battles from starting unless cleared.
- MCTS gives an option it barely visited the average of its first random
  playouts: in a won endgame the AI's choice can look 0.4 worse after a
  few hundred visits. Check those with `pe.iterative_deepening_expectiminimax`
  (its `matrix` is side one's options x side two's, NaN where pruned).
- Trace `scores` are None when the decision didn't compute them.
- The judge's values depend on its search mode (single-thread values run
  ~0.05 lower than 11-thread ones): compare regret only between results of
  the same settings, which `ai_check.sh` does by naming the files.
- Win-rate z below 2 is noise; a borderline result needs more seeds (the
  user asks "run more seeds").
- The user's test party (`sourcrystal.sav`): Zapdos, Snorlax, Cloyster,
  Exeggutor, Steelix, Vaporeon, levels 76-78. Only Koga 2, Misty 2, Whitney 2
  and Jasmine 2 ever beat it, so only they give a signal.
