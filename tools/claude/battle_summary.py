"""Summarize battle_matrix.sh results. usage: battle_summary.py RESULTS.jsonl..."""
import collections, json, sys

for f in sys.argv[1:]:
    rs = [json.loads(l) for l in open(f)]
    hooks = collections.Counter()
    for r in rs:
        hooks.update(r['hooks'])
    print(f'== {f}: {len(rs)} battles, results {dict(collections.Counter(r["won"] for r in rs))} (0 = player won)')
    for r in rs:
        if r['crashed_at'] or not r['ended'] or not r['started']:
            kind = 'CRASH' if r['crashed_at'] else 'timeout' if r['started'] else 'never started'
            print(f'   {kind}: {r["trainer"]} seed {r["seed"]}, AI turns {r["hooks"].get("AI_Smogon")}, {r["crashed_at"]}')
    for k, v in sorted(hooks.items()):
        print(f'{v:8d} {k}')
