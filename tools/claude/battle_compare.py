"""Compare two battle_matrix.sh result files per trainer.
usage: battle_compare.py OLD.jsonl NEW.jsonl

Prints AI wins, timeouts and crashes per trainer and in total, with z: how
many standard deviations the change in the AI's win rate is (a two-sample
test). Any code change shifts the game's RNG timing, so results always move
a little: |z| below 2 is noise; 2-3 is worth a closer look (with several
trainers, one of them reaching 2 by chance is likely); a real effect stays
or grows when you rerun with more seeds. With smart-player results
(PLAYER=smart), it also prints the average Pokemon left on each side and
the z of the change, a finer measure than win/loss. Trainers that never win
against the player's party give no signal either way."""
import collections
import json
import math
import sys


def load(path):
    by = collections.defaultdict(list)
    for line in open(path):
        r = json.loads(line)
        by[r["trainer"]].append(r)
    return by


def wins(rs):
    return sum(r["won"] == 1 and r["ended"] for r in rs)


def timeouts(rs):
    return sum(not r["ended"] for r in rs)


def crashes(rs):
    return sum(bool(r["crashed_at"]) for r in rs)


def z_rate(k1, n1, k2, n2):
    """z of the change from k1/n1 to k2/n2 (pooled two-proportion test)."""
    if not n1 or not n2:
        return 0.0
    p = (k1 + k2) / (n1 + n2)
    se = math.sqrt(p * (1 - p) * (1 / n1 + 1 / n2))
    return (k2 / n2 - k1 / n1) / se if se else 0.0


def z_mean(a, b):
    """z of the change in the mean from a to b (Welch)."""
    if len(a) < 2 or len(b) < 2:
        return 0.0
    ma, mb = sum(a) / len(a), sum(b) / len(b)
    va = sum((x - ma) ** 2 for x in a) / (len(a) - 1)
    vb = sum((x - mb) ** 2 for x in b) / (len(b) - 1)
    se = math.sqrt(va / len(a) + vb / len(b))
    return (mb - ma) / se if se else 0.0


def mark(z, n):
    # with fewer than 10 battles a side, the spread itself is too uncertain
    return f"{z:+5.1f}{'*' if abs(z) >= 2 and n >= 10 else ' '}"


old, new = load(sys.argv[1]), load(sys.argv[2])
has_left = all("enemy_left" in r for rs in list(old.values()) + list(new.values()) for r in rs)
header = f"{'trainer':10} {'AI wins':>15} {'z':>6} {'timeouts':>10} {'crashes':>9}"
if has_left:
    header += f"   {'player left':>15} {'z':>6} {'AI left':>14} {'z':>6}"
print(header)


def row(name, o, n):
    few = min(len(o), len(n))
    line = (f"{name:10} {wins(o):>4}/{len(o):<2} -> {wins(n):>2}/{len(n):<2} "
            f"{mark(z_rate(wins(o), len(o), wins(n), len(n)), few)} "
            f"{timeouts(o):>4} -> {timeouts(n):<2} {crashes(o):>3} -> {crashes(n)}")
    if has_left and o and n:
        pl_o = [r["player_left"] for r in o]
        pl_n = [r["player_left"] for r in n]
        el_o = [r["enemy_left"] for r in o]
        el_n = [r["enemy_left"] for r in n]
        avg = lambda xs: sum(xs) / len(xs)
        line += (f"   {avg(pl_o):5.2f} -> {avg(pl_n):5.2f} {mark(z_mean(pl_o, pl_n), few)}"
                 f" {avg(el_o):5.2f} -> {avg(el_n):5.2f} {mark(z_mean(el_o, el_n), few)}")
    print(line)


for t in sorted(set(old) | set(new)):
    row(t, old.get(t, []), new.get(t, []))
row("total", [r for rs in old.values() for r in rs], [r for rs in new.values() for r in rs])
print("z: standard deviations of the change; * marks |z| >= 2 (with 10+ battles a side). "
      "Below 2 is noise.")
