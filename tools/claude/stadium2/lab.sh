#!/bin/bash
# usage: lab.sh OUTDIR STADIUM2.z64 GBROM GBRAM PREFIX
# Boots Stadium 2 in the background and goes to the Lab's PC, saving
# OUTDIR/shots/PREFIX_1.png - PREFIX_6.png (Game Pak check, hub, Lab, PC menu).
# The Lab needs a save made in a Pokemon Center (see setmap.py). From the PC
# menu, `snap.sh OUTDIR NAME k:300 wait:800 k:300 wait:1500 x:300 wait:12000`
# opens BOXES.
dir=$(dirname "$0")
"$dir/run.sh" "$1" "$2" "$3" "$4" --verbose > "$1/$5.log" 2>&1 &
S="$dir/snap.sh"
$S "$1" $5_1 wait:35000 Return:300 wait:10000
$S "$1" $5_2 x:300 wait:15000
$S "$1" $5_3 x:300 wait:8000 j:300 wait:2000
$S "$1" $5_4 x:300 wait:15000
$S "$1" $5_5 x:300 wait:8000
$S "$1" $5_6 x:300 wait:10000
