#!/bin/bash
# Build the ROM of any commit, to compare it with the working tree.
# usage: tools/claude/build_rev.sh REV OUT [TARGET]
#   REV: a commit, branch or tag; OUT: an output path prefix (writes OUT.gbc,
#   OUT.sym and OUT.map); TARGET: sour (default), gbtower, debug or vc.
# Builds in a temporary git worktree with the prebuilt git-ignored
# tools/superfamiconv linked in, and caches the results by commit hash in
# .revbuild/ (git-ignored), so building the same commit again is instant.
set -e
root=$(cd "$(dirname "$0")/../.." && pwd)
rev=$1; out=$2; target=${3:-sour}
[ -n "$rev" ] && [ -n "$out" ] || { echo "usage: $0 REV OUT [TARGET]" >&2; exit 1; }
sha=$(git -C "$root" rev-parse --verify "$rev^{commit}")
case $target in
	sour) name=sourcrystal ;;
	gbtower) name=sourcrystal_GBTower ;;
	debug) name=sourcrystal_debug ;;
	vc) name=sourcrystal_vc ;;
	*) echo "unknown target $target" >&2; exit 1 ;;
esac
cache=$root/.revbuild/$sha
if [ ! -f "$cache/$name.gbc" ]; then
	tree=$(mktemp -d "${TMPDIR:-/tmp}/revbuild.XXXXXX")
	trap 'git -C "$root" worktree remove --force "$tree" 2>/dev/null; rm -rf "$tree"' EXIT
	git -C "$root" worktree add -f --detach "$tree" "$sha" -q
	ln -sf "$root/tools/superfamiconv" "$tree/tools/superfamiconv"
	make -C "$tree/tools" -j16 > "$tree/tools.log" 2>&1 || { tail -20 "$tree/tools.log" >&2; exit 1; }
	make -C "$tree" -j16 "$target" > "$tree/build.log" 2>&1 || { grep -iE "error" "$tree/build.log" | head -20 >&2; exit 1; }
	mkdir -p "$cache"
	cp "$tree/$name.gbc" "$tree/$name.sym" "$tree/$name.map" "$cache/"
fi
mkdir -p "$(dirname "$out")"
cp "$cache/$name.gbc" "$out.gbc"
cp "$cache/$name.sym" "$out.sym"
cp "$cache/$name.map" "$out.map"
echo "$out.gbc ($sha)"
