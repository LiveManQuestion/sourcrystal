#!/bin/bash
# usage: snap.sh OUTDIR NAME [KEY[:ms]|wait:ms ...]
# Sends keys to the emulator on :77, then saves the screen to OUTDIR/shots/NAME.png.
dir=$(dirname "$0")
[ $# -gt 2 ] && DISPLAY=:77 python3 "$dir/xkey.py" "${@:3}"
DISPLAY=:77 import -window root "$1/shots/$2.png"
