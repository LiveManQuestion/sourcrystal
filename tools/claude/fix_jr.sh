#!/bin/bash
# After `peephole.py apply`: assemble every object in every build variant, then
# link, reverting each jr that RGBDS reports out of range, until all ROMs build.
cd "$(dirname "$(readlink -f "$0")")/../.."
here=tools/claude
objs="audio home main ram data/text/common data/maps/map_data data/pokemon/dex_entries data/pokemon/egg_moves data/pokemon/evos_attacks engine/movie/credits engine/overworld/events gfx/icons gfx/misc gfx/pics gfx/sprites gfx/tilesets lib/mobile/main lib/mobile/mail"
log=$(mktemp -d)
locs_from() { grep -A1 "JR\` target" "$@" | grep -o "at [^ ]*\.asm([0-9]*)" | sed 's/^at //;s/(/:/;s/)//' | sort -u; }
for it in $(seq 1 15); do
	rm -f $log/*.log
	for v in "-D _CRYSTAL11" "-D _CRYSTAL11 -D _GBTOWER" "-D _CRYSTAL11 -D _DEBUG" "-D _CRYSTAL11 -D _CRYSTAL11_VC"; do
		for o in $objs; do
			echo "rgbasm -Q8 -P includes.asm -Weverything -Wtruncation=1 -Wno-obsolete $v -X 100000 -o /dev/null $o.asm > $log/$(echo "$o$v" | tr ' /' '__').log 2>&1"
		done
	done | xargs -P 16 -I{} bash -c "{}"
	locs=$(locs_from $log/*.log)
	[ -z "$locs" ] && break
	echo "assembly pass $it: reverting $(echo "$locs" | wc -l) jr"
	python3 $here/peephole.py revert $locs | tail -1
done
for it in $(seq 1 20); do
	make -j16 -k main.o home.o main_GBTower.o home_GBTower.o main_debug.o home_debug.o main_vc.o home_vc.o >/dev/null 2>&1
	make -k -j1 all > $log/build.log 2>&1 && { echo "all ROMs build"; exit 0; }
	locs=$(locs_from $log/build.log)
	[ -z "$locs" ] && { echo "build failed for another reason, see $log/build.log"; exit 1; }
	echo "link pass $it: reverting $(echo "$locs" | wc -l) jr"
	python3 $here/peephole.py revert $locs | tail -1
done
