"""Summarize enemy switches from battle.py / battle_matrix.sh output.
usage: switch_report.py RESULTS.jsonl [MORE.jsonl...]
The test player is a Fire-type Typhlosion, so for each AI-chosen ('mid')
switch it compares the Fire weakness of the Pokemon leaving and entering
(from the base stats and type chart), lists the most common switches, and
shows the switches into a worse or equal Fire matchup with the matchup scores
the AI saw (active, best switch-in): near-equal scores mean an escape switch
(Toxic, Leech Seed...), not a matchup switch. 'forced' switch-ins come from
faints and the player's Roar."""
import collections, json, os, re, sys

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..")

def consts(path):
    out, v = {}, 0
    for line in open(os.path.join(ROOT, path)):
        line = line.split(";")[0].strip()
        if line.startswith("const_def"):
            m = re.match(r"const_def\s*(\d+)?", line)
            v = int(m.group(1) or 0)
            continue
        m = re.match(r"const\s+(\w+)", line)
        if m:
            out.setdefault(v, m.group(1))  # later const groups (Unown letters...) reuse numbers
            v += 1
    return out

SPECIES = consts("constants/pokemon_constants.asm")
CHART = {}
for line in open(os.path.join(ROOT, "data/types/type_matchups_table.asm")):
    m = re.match(r"\s*db (\w+),\s*(\w+),\s*(\w+)", line)
    if m and m.group(3) in ("SUPER_EFFECTIVE", "NOT_VERY_EFFECTIVE", "NO_EFFECT"):
        CHART[m.group(1), m.group(2)] = {"SUPER_EFFECTIVE": 2, "NOT_VERY_EFFECTIVE": .5, "NO_EFFECT": 0}[m.group(3)]

def types(species):
    name = SPECIES.get(species, "?").lower()
    path = os.path.join(ROOT, "data/pokemon/base_stats", name + ".asm")
    if os.path.exists(path):
        for line in open(path):
            if "; type" in line:
                return [t.strip() for t in line.split(";")[0].replace("db", "").split(",")]
    return []

def fire(species):
    r = 1
    for t in set(types(species)):
        r *= CHART.get(("FIRE", t), 1)
    return r

name = lambda s: SPECIES.get(s, str(s))
for path in sys.argv[1:]:
    rows = [json.loads(l) for l in open(path)]
    mids = [dict(s, trainer=r["trainer"], seed=r["seed"]) for r in rows for s in r.get("switches", []) if s["kind"] == "mid"]
    better = sum(fire(s["to"]) < fire(s["from"]) for s in mids)
    worse = sum(fire(s["to"]) > fire(s["from"]) for s in mids)
    wins = sum(r["won"] == 1 and r["ended"] for r in rows)
    print(f"== {path}: {len(rows)} battles, AI wins {wins}, crashes {sum(bool(r['crashed_at']) for r in rows)}, "
          f"timeouts {sum(not r['ended'] for r in rows)}")
    print(f"   {len(mids)} AI switches: into better Fire resistance {better}, same {len(mids) - better - worse}, worse {worse}")
    for (a, b), n in collections.Counter((s["from"], s["to"]) for s in mids).most_common(10):
        print(f"   {n:3}x {name(a):11} (Fire x{fire(a)}) -> {name(b)} (Fire x{fire(b)})")
    print("   worse or equal (not resisting Fire better):")
    for s in mids:
        if fire(s["to"]) >= fire(s["from"]) and fire(s["to"]) >= 1:
            print(f"     {s['trainer']:9} seed {s['seed']}: {name(s['from'])} (x{fire(s['from'])}) -> "
                  f"{name(s['to'])} (x{fire(s['to'])}), scores {s['scores']}")
