#!/bin/bash
# usage: run.sh OUTDIR STADIUM2.z64 GBROM GBRAM [mupen64plus args...]
# Runs Pokemon Stadium 2 (US, .z64 byte order) on DISPLAY=:77 (start Xvfb :77
# first) with GBROM/GBRAM in controller 1's Transfer Pak. mupen64plus writes
# GBRAM back on exit, so pass a copy. Keys (X keysyms, see xkey.py):
# x=A z=B Return=Start i/k/j/l=D-pad u/m/v/n=stick q/s=L/R a=Z t/g/f/h=C.
out=$1 n64=$2 rom=$(realpath "$3") ram=$(realpath "$4")
shift 4
mkdir -p "$out/cfg" "$out/shots"
# The console frontend only reads the Transfer Pak files from the config file.
printf '[Transferpak]\nGB-rom-1 = "%s"\nGB-ram-1 = "%s"\n' "$rom" "$ram" > "$out/cfg/mupen64plus.cfg"
export DISPLAY=:77 SDL_AUDIODRIVER=dummy SDL_VIDEODRIVER=x11
unset WAYLAND_DISPLAY
K='Input-SDL-Control1'
exec mupen64plus --configdir "$out/cfg" --datadir /usr/share/mupen64plus --nosaveoptions \
  --noosd --windowed --resolution 640x480 --sshotdir "$out/shots" \
  --gfx mupen64plus-video-rice \
  --set "$K[plugged]=True" --set "$K[plugin]=4" --set "$K[mode]=0" --set "$K[device]=-1" \
  --set "$K[A Button]=key(120)" --set "$K[B Button]=key(122)" --set "$K[Start]=key(13)" \
  --set "$K[DPad U]=key(105)" --set "$K[DPad D]=key(107)" --set "$K[DPad L]=key(106)" --set "$K[DPad R]=key(108)" \
  --set "$K[Z Trig]=key(97)" --set "$K[R Trig]=key(115)" --set "$K[L Trig]=key(113)" \
  --set "$K[C Button U]=key(116)" --set "$K[C Button D]=key(103)" --set "$K[C Button L]=key(102)" --set "$K[C Button R]=key(104)" \
  --set "$K[X Axis]=key(118,110)" --set "$K[Y Axis]=key(117,109)" \
  "$@" "$n64"
