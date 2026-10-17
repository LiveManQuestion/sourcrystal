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
Snorlax, 2026-10-17).

The headless smart player now uses its status moves (Curse, Rest, Sleep
Talk, Sleep Powder, Roar, Toxic, Explosion); `SMART_PLAYER=basic` is the old
attack-only player. It beats the AI far more often, so win rates from
before it aren't comparable.

Last measured (4 trainers x 144 seeds, the user's party, new player), after
the Explosion fix: AI wins 229 of 576. Koga 2 111/144, Whitney 2 65, Misty
2 33, Jasmine 2 20. Engine judge over 144 traced battles: 4560 decisions,
total regret 49.45. The cache for this ROM is `.aicheck/a5d583a574897d25`.

## The loop

1. Find a pattern: `tools/claude/ai_check.sh` (no arguments: the working
   tree's `sourcrystal.gbc` against `HEAD`). It runs the tests, 576 battles
   and the judge, and prints `engine_judge.py --patterns`. Its cache
   (`.aicheck/`) starts empty, so the first run takes about an hour per ROM:
   start it in the background. On a clean tree both sides are the same ROM,
   so this is one run, and the report's pattern tables are what to pick from.
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

## Candidate patterns (latest judge, new player, after the Explosion fix)

Clear disagreements (regret > 0.1) by matchup, AI action and engine action:

```
clear decisions regret
   3   43  1.34  VENUSAUR vs SNORLAX   hiddenpowerfire -> razorleaf
   3   23  0.98  PORYGON2 vs STEELIX   recover -> icebeam
   3    3  0.85  QUAGSIRE vs VAPOREON  earthquake -> switch
   2    2  0.91  GENGAR   vs ZAPDOS    dynamicpunch -> explosion
   2   10  0.67  KINGDRA  vs VAPOREON  sleeptalk -> switch
```

Venusaur vs Snorlax is the top matchup (98 decisions, 2.89 regret; also
Razor Leaf -> Synthesis, 20 decisions); check first whether the engine is
using the player's whole party, which the AI can't know. The Tentacruel
patterns from the new player's first run (Sludge Bomb where the engine uses
Swords Dance vs Vaporeon or Substitute vs Cloyster, 3 and 4 clear) vanished
after the Explosion fix's RNG reshuffle: see whether they come back with
more seeds before fixing them.

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
- `ai_scenarios.py`'s test battle varies between runs: put matchup-dependent
  tests in `smogon_calls_test.py`. `ai_scenarios.py -k TEXT` runs one case.
- Make the test RAM with `tools/claude/save_ram.py`, never by writing to the
  user's saves. The user's save has the clock-reset flag set, which stops
  headless battles from starting unless cleared.
- Trace `scores` are None when the decision didn't compute them.
- Win-rate z below 2 is noise; a borderline result needs more seeds (the
  user asks "run more seeds").
- The user's test party (`sourcrystal.sav`): Zapdos, Snorlax, Cloyster,
  Exeggutor, Steelix, Vaporeon, levels 76-78. Only Koga 2, Misty 2, Whitney 2
  and Jasmine 2 ever beat it, so only they give a signal.
