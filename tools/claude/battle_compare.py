"""Compare two battle_matrix.sh result files per trainer.
usage: battle_compare.py OLD.jsonl NEW.jsonl
Prints AI wins, timeouts and crashes per trainer and in total. With 6 seeds a
swing of one or two wins is noise (the game's RNG depends on CPU timing, which
any code change shifts); rerun the trainers in question with SEEDS=36."""
import collections, json, sys

def load(path):
    by = collections.defaultdict(list)
    for line in open(path):
        r = json.loads(line)
        by[r["trainer"]].append(r)
    return by

old, new = load(sys.argv[1]), load(sys.argv[2])
wins = lambda rs: sum(r["won"] == 1 and r["ended"] for r in rs)
tos = lambda rs: sum(not r["ended"] for r in rs)
crashes = lambda rs: sum(bool(r["crashed_at"]) for r in rs)
print(f"{'trainer':10} {'AI wins':>15} {'timeouts':>10} {'crashes':>9}")
for t in sorted(set(old) | set(new)):
    o, n = old.get(t, []), new.get(t, [])
    print(f"{t:10} {wins(o):>4}/{len(o):<2} -> {wins(n):>2}/{len(n):<2} {tos(o):>4} -> {tos(n):<2} {crashes(o):>3} -> {crashes(n)}")
ao, an = [r for rs in old.values() for r in rs], [r for rs in new.values() for r in rs]
print(f"{'total':10} {wins(ao):>4}/{len(ao):<2} -> {wins(an):>2}/{len(an):<2} {tos(ao):>4} -> {tos(an):<2} {crashes(ao):>3} -> {crashes(an)}")
