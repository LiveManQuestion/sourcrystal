# Smogon AI: engine judge handoff

Notes for the next Claude session working on the Smogon AI (Challenge Mode
trainer AI) with the engine judge. Written 2026-10-17 at `bebd07720`, branch
`smogon-ai`. Read CLAUDE.md, `docs/battle_ai.md` and `docs/claude_tools.md`
first; `docs/claude_changelog.md` has the reasoning behind every fix below.

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
2026-10-17).

The headless smart player now uses its status moves (Curse, Rest, Sleep
Talk, Sleep Powder, Roar, Toxic, Explosion); `SMART_PLAYER=basic` is the old
attack-only player. It beats the AI far more often, so win rates from
before it aren't comparable.

Last measured (4 trainers x 144 seeds, the user's party, new player), after
the Swords Dance credit fix: AI wins 241 of 576. Koga 2 119/144, Whitney 2
57, Misty 2 38, Jasmine 2 27 (the 144-seed numbers swing by ~10 from RNG
timing alone; Jasmine swung 20 of 432 on a build that didn't change her
decisions). Engine judge (600k iterations per decision) over 144 traced
battles: 4784 decisions, total regret 62.79. The cache for this ROM is
`.aicheck/8c1d8c1c6fbcbbb7`, judge in `judge-i600000.jsonl`.

## The loop

1. Find a pattern: `tools/claude/ai_check.sh` (no arguments: the working
   tree's `sourcrystal.gbc` against `HEAD`). It runs the tests, 576 battles
   and the judge, and prints `engine_judge.py --patterns`. Its cache
   (`.aicheck/`, git-ignored) persists between sessions: on a clean tree
   both sides are `HEAD`'s ROM, already cached, so the report is instant
   and its pattern tables are what to pick from. An uncached ROM takes
   about 30 minutes: start it in the background. The cache misses (and the
   base reruns) when `smart_player.py`, the save (`sourcrystal.sav`: playing
   and saving changes it) or the options change, or if `.aicheck/` is
   deleted (`git clean -x`).
2. Pick a concentrated pattern: many clear disagreements over several
   battles in one matchup and action ("matchup and AI action -> engine
   action" table). Big totals spread thin over many decisions are noise.
3. Understand it before fixing it. Read the decisions
   (`.aicheck/<key>/judge.jsonl`, `--report`, the traces in
   `.aicheck/<key>/traces/`: `move_scores`, `path`, `scores`) and rebuild the
   position in `tools/claude/smogon_calls_test.py` (`set_ot`, `set_player`,
   `g.call(..., poke=...)`) to read what the AI computed. My first guess
   was wrong more than once (Venusaur: not an Ice Beam fear, a tie with an
   unboosted KO race).
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

## Candidate patterns (600k-iteration judge, after the Swords Dance fix)

Clear disagreements (regret > 0.1) by matchup, AI action and engine action:

```
clear decisions regret
   4    5   1.40  QWILFISH   vs CLOYSTER  curse -> sludgebomb
   4   31   1.72  VENUSAUR   vs ZAPDOS    hiddenpowerfire70 -> synthesis
   4    4   1.08  STEELIX    vs ZAPDOS    rockslide -> curse
   4   18   1.00  BLISSEY    vs SNORLAX   switch -> switch (another)
   4    7   0.96  TENTACRUEL vs STEELIX   surf -> gigadrain
```

Nothing is concentrated now. Koga's Qwilfish Cursing in front of Cloyster
has shown up in three runs (4 clear in 2 of 72 extra Koga battles too):
the likeliest next one. Venusaur's Growth got slightly worse with the
wider `.BreaksHealing` (regret 0.25 -> 0.68, 2 clear): watch it. Steelix
vs Zapdos is new in a run where Steelix's logic didn't change. Venusaur vs
Snorlax in KO range is left: the gap disappears with the player's bench
removed.

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
- Trace `scores` are None when the decision didn't compute them.
- The judge's values depend on its search mode (single-thread values run
  ~0.05 lower than 11-thread ones): compare regret only between results of
  the same settings, which `ai_check.sh` does by naming the files.
- Win-rate z below 2 is noise; a borderline result needs more seeds (the
  user asks "run more seeds").
- The user's test party (`sourcrystal.sav`): Zapdos, Snorlax, Cloyster,
  Exeggutor, Steelix, Vaporeon, levels 76-78. Only Koga 2, Misty 2, Whitney 2
  and Jasmine 2 ever beat it, so only they give a signal.
