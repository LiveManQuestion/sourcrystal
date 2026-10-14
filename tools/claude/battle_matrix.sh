#!/bin/bash
# Run battle.py for every trainer x seeds on one or two ROMs, 16 at a time.
# usage: tools/claude/battle_matrix.sh OUTDIR SAVE.ram ROM1.gbc [ROM2.gbc]
#   (each ROM needs its .sym next to it; results go to OUTDIR/<rom name>.jsonl)
# Takes ~30 min for 2 ROMs. Summarize with tools/claude/battle_summary.py.
here=$(dirname "$(readlink -f "$0")")
P=${PYBOY_PYTHON:-$HOME/.local/share/uv/tools/pyboy/bin/python}
out=$1; save=$2; shift 2
mkdir -p "$out"
for rom in "$@"; do
	for t in "BUGSY 2" "JASMINE 2" "KOGA 1" "KOGA 2" "BROCK 2" "MISTY 2" "SABRINA 1" "FALKNER 2" "RIVAL2 1"; do
		for s in 1 2 3 4 5 6; do echo "$rom|$t|$s"; done
	done
done | xargs -P 16 -I{} bash -c '
	IFS="|" read rom t s <<< "{}"
	'"$P"' '"$here"'/battle.py "$rom" "${rom%.gbc}.sym" '"$save"' "$t" $s 216000 2>/dev/null \
		| grep "^{" >> '"$out"'/$(basename "${rom%.gbc}").jsonl'
