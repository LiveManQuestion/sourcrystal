#!/bin/bash
# Print the paths of a vanilla Pokémon Crystal ROM and its .sym, for the
# comparison tools (cmp_data.py, damage_diff.py). Uses the build in
# pokecrystal-master/ (make crystal there) if it exists; otherwise builds a copy
# of pokecrystal-master/ into .vanilla/ (git-ignored) once.
set -e
root=$(cd "$(dirname "$0")/../.." && pwd)
if [ -f "$root/pokecrystal-master/pokecrystal.gbc" ] && [ -f "$root/pokecrystal-master/pokecrystal.sym" ]; then
	echo "$root/pokecrystal-master/pokecrystal.gbc $root/pokecrystal-master/pokecrystal.sym"
	exit
fi
out=$root/.vanilla
if [ ! -f "$out/pokecrystal.gbc" ]; then
	rm -rf "$out"
	cp -r "$root/pokecrystal-master" "$out"
	make -C "$out" -j16 crystal > "$out/build.log" 2>&1 || { tail -20 "$out/build.log"; exit 1; }
fi
echo "$out/pokecrystal.gbc $out/pokecrystal.sym"
