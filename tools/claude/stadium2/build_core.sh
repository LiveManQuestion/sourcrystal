#!/bin/bash
# usage: build_core.sh
# Builds a mupen64plus core that can run Stadium 2's GB Tower into .stadium2/
# (git-ignored): upstream mupen64plus-core (which has RMG's Transfer Pak fix)
# plus RMG's RSP/RDP timing patch (Rosalie241/RMG e8d4d6341b). Without that
# patch the GB Tower loads the cartridge and then hangs on a white screen.
# Upstream has the Game Boy cartridge fixes (save footer kept, ROM/RAM banks
# mirrored past the end of the chips, MBC3 clock started at power on:
# PRs #1194-#1196). The frontend and plugins come from upstream too, installed
# to ~/.local (see docs/stadium2.md).
set -e
cd "$(dirname "$0")/../../.."
mkdir -p .stadium2
cd .stadium2
if [ ! -d core ]; then
	git clone -q https://github.com/mupen64plus/mupen64plus-core.git core
	git -C core checkout -q a9ca8ec0
	curl -sfL -H 'Accept: application/vnd.github.v3.diff' \
		https://api.github.com/repos/Rosalie241/RMG/commits/e8d4d6341b -o rsp_fixes.diff
	git -C core apply -p4 ../rsp_fixes.diff
fi
# Without nasm, build without the dynarec (play.sh then uses the slower
# cached interpreter).
asm=; command -v nasm > /dev/null || asm=NO_ASM=1
make -C core/projects/unix clean > /dev/null
make -C core/projects/unix all $asm VULKAN=0 -j"$(nproc)" > build.log 2>&1 ||
	{ tail -20 build.log; exit 1; }
echo "$PWD/core/projects/unix/libmupen64plus.so.2"
