#!/bin/bash
# Run battle.py for every trainer x seed on one or two ROMs, 16 at a time.
# usage: tools/claude/battle_matrix.sh OUTDIR SAVE.ram ROM1.gbc [ROM2.gbc]
#   (each ROM needs its .sym next to it; results go to OUTDIR/<rom name>.jsonl,
#   so give the two ROMs different file names)
# Options (environment): SEEDS=6 (seeds 1..N), FIRST_SEED=1 (seeds FIRST_SEED..N,
# to add seeds to an earlier run), TRAINERS="KOGA 1|KOGA 2",
# PLAYER=smart (battle.py --smart: the save's party played by a strong greedy
# policy, so win rates mean something; without it, an unkillable Typhlosion).
# ~15 min per ROM with the defaults. Summarize with battle_summary.py,
# compare two ROMs per trainer with battle_compare.py, and look at the AI's
# switches with switch_report.py. Any code change shifts the game's RNG
# timing, so judge win-rate changes over many seeds (e.g. SEEDS=36).
here=$(dirname "$(readlink -f "$0")")
P=${PYBOY_PYTHON:-$HOME/.local/share/uv/tools/pyboy/bin/python}
out=$1; save=$2; shift 2
seeds=${SEEDS:-6}
first=${FIRST_SEED:-1}
smart=""
[ "${PLAYER:-}" = smart ] && smart="--smart"
trainers=${TRAINERS:-"BUGSY 2|JASMINE 2|KOGA 1|KOGA 2|BROCK 2|MISTY 2|SABRINA 1|FALKNER 2|RIVAL2 1"}
if [ $# -eq 2 ] && [ "$(basename "$1")" = "$(basename "$2")" ]; then
	echo "both ROMs are named $(basename "$1"): copy one to another name first" >&2
	exit 1
fi
mkdir -p "$out/runs"
rm -f "$out"/runs/*.json
IFS='|' read -ra tlist <<< "$trainers"
for rom in "$@"; do
	for t in "${tlist[@]}"; do
		for s in $(seq "$first" "$seeds"); do echo "$rom|$t|$s"; done
	done
done | xargs -P 16 -I{} bash -c '
	IFS="|" read rom t s <<< "{}"
	n=$(basename "${rom%.gbc}")
	'"$P"' '"$here"'/battle.py '"$smart"' "$rom" "${rom%.gbc}.sym" '"$save"' "$t" $s 216000 2>/dev/null \
		| grep "^{" > "'"$out"'/runs/$n.${t// /_}.$s.json"'
# One file per run: parallel appends of lines over 4 KB to one file interleave.
for rom in "$@"; do
	n=$(basename "${rom%.gbc}")
	cat "$out"/runs/"$n".*.json > "$out/$n.jsonl"
done
