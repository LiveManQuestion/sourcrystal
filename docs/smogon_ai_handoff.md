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
Tentacruel vs Rest Vaporeon, 2026-10-17).

The headless smart player now uses its status moves (Curse, Rest, Sleep
Talk, Sleep Powder, Roar, Toxic, Explosion); `SMART_PLAYER=basic` is the old
attack-only player. It beats the AI far more often, so win rates from
before it aren't comparable.

Last measured (4 trainers x 144 seeds, the user's party, new player), after
the healer setup fix: AI wins 229 of 576. Koga 2 125/144, Whitney 2 52,
Misty 2 36, Jasmine 2 16 (the 144-seed numbers swing by ~10 from RNG
timing alone). Engine judge (600k iterations per decision) over 144 traced
battles: 4530 decisions, total regret 59.53. The cache for this ROM
(`HEAD` at `e79f45c49`) is `.aicheck/a30884bdc99f33a1`, judge in
`judge-i600000.jsonl` (`judge.jsonl` is the older timed judge's).

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

## Candidate patterns (600k-iteration judge, after the healer setup fix)

Clear disagreements (regret > 0.1) by matchup, AI action and engine action:

```
clear decisions battles regret
  14   25   2   2.49  KINGDRA    vs VAPOREON  sleeptalk -> switch (tentacruel)
   6    6   3   1.64  TENTACRUEL vs CLOYSTER  sludgebomb -> substitute
   3   15   2   0.96  TENTACRUEL vs VAPOREON  sludgebomb -> gigadrain
   7    9   1   0.89  QWILFISH   vs ZAPDOS    sludgebomb -> switch
   2   14   2   0.84  TENTACRUEL vs ZAPDOS    surf -> switch
```

Misty's sleeping Kingdra Sleep Talking into Vaporeon where the engine
switches to Tentacruel: the old timed judge (11 threads, 400 ms) missed
most of it; 4 s and 6M-iteration searches agree with the new judge on
Misty seed 5 decision 21. Only 2 battles, so check that it holds across
seeds. Then Misty's Tentacruel vs Cloyster (Substitute where the AI
attacks: check what the engine knows first, Cloyster's moves, Explosion?).
Koga's Tentacruel vs Vaporeon at low HP is the KO-range kind. One Swords
Dance miss is left (Misty seed 35: +2 Tentacruel vs a 207/327 Vaporeon
that just switched in, nothing revealed). Venusaur vs Snorlax in KO range
is left: the gap disappears with the player's bench removed.

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
