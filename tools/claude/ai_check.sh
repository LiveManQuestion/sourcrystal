#!/bin/bash
# Check a Smogon AI change end to end against an older commit: the test
# suites, battles against the save's party (battle_matrix.sh, PLAYER=smart)
# and engine_judge.py's patterns over traced battles.
# usage: tools/claude/ai_check.sh [ROM] [BASE_REV]
#   ROM: the new ROM, with its .sym next to it (default: sourcrystal.gbc,
#   built from the working tree); BASE_REV: the commit to compare with
#   (default: HEAD).
# Options (environment): SEEDS=144 (battles per trainer), TRACE_SEEDS=36
# (traced battles per trainer, for the judge), ITERS=600000 (judge search
# iterations per decision, JOBS=11 decisions at a time; ITERS=0 searches
# MS=400 milliseconds on 11 threads instead, as before), TRAINERS="KOGA 2|MISTY 2|WHITNEY 2|JASMINE 2"
# (TRAINERS=all: every party of every Smogon AI trainer class, from
# make_battle_scripts.py; with PLAYER_LEVEL=match the save's party plays at
# each party's top level, see battle_harness.py, and SEEDS=$TRACE_SEEDS
# takes the battles from the traces),
# SMART_PLAYER=basic (the player without status moves, see smart_player.py),
# SAVE=sourcrystal.sav (read through save_ram.py), NO_JUDGE=1 (skip
# the traces and the judge).
# Each ROM's results are cached in .aicheck/ (git-ignored) by the ROM's
# contents, the save, the smart player and these options (the judge's files
# are named by its search settings, so changing them keeps the battles), so
# the base runs only once and rerunning a ROM is instant. About 30 minutes
# per ROM that isn't cached; the tests run alongside the battles.
set -e
root=$(cd "$(dirname "$0")/../.." && pwd)
here=$root/tools/claude
P=${PYBOY_PYTHON:-$HOME/.local/share/uv/tools/pyboy/bin/python}
PE=$root/bots/pe-venv/bin/python
rom=$(readlink -f "${1:-$root/sourcrystal.gbc}")
base_rev=${2:-HEAD}
seeds=${SEEDS:-144}
trace_seeds=${TRACE_SEEDS:-36}
ms=${MS:-400}
iters=${ITERS:-600000}
jobs=${JOBS:-11}
if [ "$iters" -gt 0 ]; then
	jname=judge-i$iters
	search="--iterations $iters --jobs $jobs --cache $root/.aicheck/judge-cache-i$iters.jsonl"
else
	jname=judge
	search="--ms $ms --threads 11"
fi
trainers=${TRAINERS:-"KOGA 2|MISTY 2|WHITNEY 2|JASMINE 2"}
if [ "$trainers" = all ]; then
	trainers=$(python3 -c "import json; print('|'.join(json.load(open('$here/battle_scripts.json'))))")
fi
save=${SAVE:-$root/sourcrystal.sav}
judge=1
[ -n "${NO_JUDGE:-}" ] && judge=""
if [ -n "$judge" ] && [ ! -x "$PE" ]; then
	echo "no poke-engine venv at $PE (see docs/claude_tools.md): judging skipped" >&2
	judge=""
fi
[ -f "$rom" ] && [ -f "${rom%.gbc}.sym" ] || { echo "usage: $0 [ROM] [BASE_REV] (ROM needs its .sym)" >&2; exit 1; }

work=$(mktemp -d "${TMPDIR:-/tmp}/aicheck.XXXXXX")
trap 'rm -rf "$work"' EXIT
# Never write to the user's save: copy the cartridge RAM part.
python3 "$here/save_ram.py" "$save" "$work/save.ram"
"$here/build_rev.sh" "$base_rev" "$work/base" > /dev/null

# run_rom ROM: print the cache directory holding ROM's results, running
# whatever isn't cached yet.
run_rom() {
	local r=$1
	local key
	# (the full smart player's rules are part of the key; SMART_PLAYER=basic
	# plays like the player before them, so it keeps the old keys)
	key=$( (cat "$r" "$work/save.ram"; echo "$seeds|$trace_seeds|$ms|$trainers${PLAYER_LEVEL:+|$PLAYER_LEVEL}"
		[ "${SMART_PLAYER:-}" = basic ] || cat "$here/smart_player.py") | sha256sum | cut -c1-16)
	local dir=$root/.aicheck/$key
	mkdir -p "$dir"
	cp "$r" "$dir/rom.gbc"; cp "${r%.gbc}.sym" "$dir/rom.sym"; cp "$work/save.ram" "$dir/save.ram"
	if [ -n "$judge" ] && [ ! -f "$dir/traces.done" ] && [ ! -f "$dir/judge.done" ]; then
		echo "$(basename "$r"): $trace_seeds traced battles per trainer..." >&2
		rm -rf "$dir/traces"; mkdir -p "$dir/traces"
		IFS='|' read -ra tlist <<< "$trainers"
		for t in "${tlist[@]}"; do
			for s in $(seq 1 "$trace_seeds"); do echo "$t|$s"; done
		done | xargs -P 12 -I{} bash -c '
			IFS="|" read t s <<< "{}"
			'"$P"' '"$here"'/ai_trace.py run '"$dir"'/rom.gbc '"$dir"'/rom.sym '"$dir"'/save.ram "$t" $s 2>/dev/null \
				| grep "^{" > "'"$dir"'/traces/${t// /_}_$s.jsonl"'
		touch "$dir/traces.done"
	fi
	if [ ! -f "$dir/matrix.done" ]; then
		# The traced battles are the battles' first seeds, played the same
		# way (ai_trace.py prints battle.py's line plus its decisions): take
		# those from the traces, unless one is missing or older than that.
		local first=1 traced=$((trace_seeds < seeds ? trace_seeds : seeds))
		if [ -f "$dir/traces.done" ] && python3 - "$dir/traces" "$trainers" "$traced" > "$dir/traced.jsonl" <<'PY'
import json, os, sys
traces, trainers, n = sys.argv[1], sys.argv[2].split('|'), int(sys.argv[3])
for t in trainers:
    for s in range(1, n + 1):
        path = os.path.join(traces, '%s_%d.jsonl' % (t.replace(' ', '_'), s))
        line = open(path).readline() if os.path.exists(path) else ''
        if not line.startswith('{'):
            sys.exit(1)
        r = json.loads(line)
        if 'hooks' not in r:
            sys.exit(1)
        for k in ('decisions', 'candidates', 'switch_ins'):
            r.pop(k)
        print(json.dumps(r))
PY
		then
			first=$((traced + 1))
		else
			: > "$dir/traced.jsonl"
		fi
		echo "$(basename "$r"): $seeds battles per trainer ($((first - 1)) from the traces)..." >&2
		: > "$dir/rom.jsonl"
		if [ "$first" -le "$seeds" ]; then
			PLAYER=smart FIRST_SEED=$first SEEDS=$seeds TRAINERS=$trainers "$here/battle_matrix.sh" "$dir" "$dir/save.ram" "$dir/rom.gbc" > /dev/null 2>&1
		fi
		cat "$dir/traced.jsonl" >> "$dir/rom.jsonl"
		rm -rf "$dir/runs" "$dir/traced.jsonl"
		touch "$dir/matrix.done"
	fi
	if [ -n "$judge" ] && [ ! -f "$dir/$jname.done" ]; then
		echo "$(basename "$r"): the judge ($search)..." >&2
		# (word splitting on $search is wanted)
		(cd "$root" && "$PE" "$here/engine_judge.py" "$dir"/traces/*.jsonl $search --top 30 \
			--json "$dir/$jname.jsonl" > "$dir/$jname.txt" 2>&1)
		touch "$dir/$jname.done"
	fi
	echo "$dir"
}

# The test suites, cached too by the ROM and the save, run while the
# battles do (the judge counts iterations, so sharing the CPU costs it no
# depth).
cp "$rom" "$work/new.gbc"; cp "${rom%.gbc}.sym" "$work/new.sym"
tests=$root/.aicheck/tests-$( (cat "$rom" "$work/save.ram") | sha256sum | cut -c1-16).txt
tests_pid=
if [ ! -f "$tests" ]; then
	echo "$(basename "$rom"): test suites (in the background)..." >&2
	{
		"$P" "$here/smogon_calls_test.py" "$work/new.gbc" "$work/new.sym" "$work/save.ram" 2>&1 | grep -E "^FAIL|^RESULT" || true
		"$P" "$here/ai_scenarios.py" "$work/new.gbc" "$work/new.sym" "$work/save.ram" 2>&1 | grep -E "^FAIL|^RESULT" || true
	} > "$tests.tmp" && mv "$tests.tmp" "$tests" &
	tests_pid=$!
fi
old=$(run_rom "$work/base.gbc")
new=$(run_rom "$work/new.gbc")
[ -z "$tests_pid" ] || wait "$tests_pid"
echo "== tests on $(basename "$rom"): smogon_calls_test.py, then ai_scenarios.py"
cat "$tests"
echo
echo "== battles: $base_rev -> $(basename "$rom") (cached in $old and $new)"
python3 "$here/battle_compare.py" "$old/rom.jsonl" "$new/rom.jsonl"
if [ -n "$judge" ]; then
	echo
	echo "== engine judge patterns: $base_rev -> $(basename "$rom")"
	python3 "$here/engine_judge.py" --patterns "$new/$jname.jsonl" "$old/$jname.jsonl" --top 15
fi
