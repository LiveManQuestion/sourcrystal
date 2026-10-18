#!/bin/bash
# usage: build_core.sh
# Builds a mupen64plus core that can run Stadium 2's GB Tower into .stadium2/
# (git-ignored): upstream mupen64plus-core (which has RMG's Transfer Pak fix)
# plus RMG's RSP/RDP timing patch (Rosalie241/RMG e8d4d6341b). Without that
# patch the GB Tower loads the cartridge and then hangs on a white screen.
# keep_save_footer.diff stops the core from truncating the Game Boy save to
# the cartridge RAM size, which dropped the emulators' clock footer.
set -e
cd "$(dirname "$0")/../../.."
top=$PWD
mkdir -p .stadium2
cd .stadium2
if [ ! -d core ]; then
	git clone -q https://github.com/mupen64plus/mupen64plus-core.git core
	git -C core checkout -q ba95bab
	curl -sfL -H 'Accept: application/vnd.github.v3.diff' \
		https://api.github.com/repos/Rosalie241/RMG/commits/e8d4d6341b -o rsp_fixes.diff
	git -C core apply -p4 ../rsp_fixes.diff
	git -C core apply "$top/tools/claude/stadium2/keep_save_footer.diff"
fi
# Without nasm, build without the dynarec (play.sh then uses the slower
# cached interpreter).
asm=; command -v nasm > /dev/null || asm=NO_ASM=1
make -C core/projects/unix clean > /dev/null
make -C core/projects/unix all $asm VULKAN=0 -j"$(nproc)" > build.log 2>&1 ||
	{ tail -20 build.log; exit 1; }
echo "$PWD/core/projects/unix/libmupen64plus.so.2"
