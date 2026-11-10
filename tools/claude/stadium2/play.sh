#!/bin/bash
# usage: play.sh [STADIUM2.n64|.z64 GBROM GBSAV [mupen64plus args...]]
# Plays Pokemon Stadium 2 with GBROM/GBSAV in controller 1's Transfer Pak,
# GB Tower included (run build_core.sh first). Defaults: the US ROM in
# pokestadiumgs-master/baseroms/us/, sourcrystal.gbc and sourcrystal.sav.
# Uses RMG's cxd4 RSP (LLE, needed by the GB Tower) and GLideN64, or with
# GFX=parallel RMG's parallel-RDP (Vulkan; slower, but draws everything like
# the hardware). Controller 1 is the first SDL gamepad, auto-configured.
# mupen64plus writes GBSAV back on exit: a copy is kept in GBSAV.bak-DATE
# first. Escape quits, F5/F7 save/load state. CORE=path/libmupen64plus.so.2
# uses another core (default: the one build_core.sh makes).
dir=$(cd "$(dirname "$0")" && pwd)
top=$(cd "$dir/../../.." && pwd)
core=${CORE:-$top/.stadium2/core/projects/unix/libmupen64plus.so.2}
plugins=/usr/lib/RMG/Plugin
[ -f "$core" ] || { echo "run $dir/build_core.sh first" >&2; exit 1; }
if [ $# -ge 3 ]; then
	n64=$1 rom=$2 sav=$3
	shift 3
else
	n64="$top/pokestadiumgs-master/baseroms/us/Pokemon Stadium 2 (USA).n64"
	rom=$top/sourcrystal.gbc sav=$top/sourcrystal.sav
fi
rom=$(realpath "$rom") sav=$(realpath "$sav")
# .n64 (little-endian) and .v64 (byte-swapped) dumps -> .z64
case $(head -c 4 "$n64" | od -An -tx1 | tr -d ' ') in
80371240) z64=$n64 ;;
40123780) z64=$top/.stadium2/stadium2.z64
	[ -f "$z64" ] || python3 -c 'import sys,array; a=array.array("I",open(sys.argv[1],"rb").read()); a.byteswap(); open(sys.argv[2],"wb").write(a.tobytes())' "$n64" "$z64" ;;
37804012) z64=$top/.stadium2/stadium2.z64
	[ -f "$z64" ] || python3 -c 'import sys,array; a=array.array("H",open(sys.argv[1],"rb").read()); a.byteswap(); open(sys.argv[2],"wb").write(a.tobytes())' "$n64" "$z64" ;;
*) echo "$n64: not an N64 ROM" >&2; exit 1 ;;
esac
cp -p "$sav" "$sav.bak-$(date +%Y%m%d-%H%M%S)"
cfg=$top/.stadium2/cfg
mkdir -p "$cfg"
# The console frontend only reads the Transfer Pak files from the config file.
printf '[Transferpak]\nGB-rom-1 = "%s"\nGB-ram-1 = "%s"\n' "$rom" "$sav" > "$cfg/mupen64plus.cfg"
if [ "$GFX" = parallel ]; then
	gfx=(--gfx "$plugins/GFX/mupen64plus-video-parallel.so" --set 'rsp-cxd4[DisplayListToGraphicsPlugin]=False')
else
	gfx=(--gfx "$plugins/GFX/mupen64plus-video-GLideN64.so" --set 'rsp-cxd4[DisplayListToGraphicsPlugin]=True')
fi
K='Input-SDL-Control1'
exec mupen64plus --configdir "$cfg" --datadir "$HOME/.local/share/mupen64plus" --nosaveoptions \
	--corelib "$core" --rsp "$plugins/RSP/mupen64plus-rsp-cxd4.so" "${gfx[@]}" \
	--set "$K[plugged]=True" --set "$K[mode]=2" --set "$K[plugin]=4" \
	--windowed --resolution 960x720 "$@" "$z64"
