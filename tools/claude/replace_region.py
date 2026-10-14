"""Replace a block of labels in a file with the same block from another version.
usage: replace_region.py FILE SOURCE START END [SOURCE_START SOURCE_END]
Replaces FILE's lines from label START up to (not including) label END with
SOURCE's lines from SOURCE_START (default START) up to SOURCE_END (default END).
SOURCE is a path, or REV:path for a git revision (e.g. HEAD~1:engine/battle/core.asm).
Labels are top-level (`Name:` or `Name::` at the start of a line), and each must
appear exactly once. pret names that Sour Crystal doesn't use yet are renamed
in the copied text (wBattleAfterAnim, rWBK, PAD_*...), like vanilla_diff.py.
Search by label, never by the first match of a bare name: a call to the end
label earlier in the file would make the block wrap around."""
import os, re, subprocess, sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from vanilla_diff import RENAMES  # noqa: E402

def read(source):
    if ":" in source and not os.path.exists(source):
        return subprocess.run(["git", "show", source], capture_output=True, text=True, check=True).stdout
    return open(source, encoding="utf-8").read()

def find(lines, name):
    idx = [i for i, l in enumerate(lines) if re.match(re.escape(name) + r"::?(\s|;|$)", l)]
    if len(idx) != 1:
        sys.exit(f"label {name} found {len(idx)} times")
    return idx[0]

path, source, start, end = sys.argv[1:5]
src_start, src_end = sys.argv[5:7] if len(sys.argv) > 6 else (start, end)
lines = open(path, encoding="utf-8").read().split("\n")
src = read(source).split("\n")
a, b = find(lines, start), find(lines, end)
c, d = find(src, src_start), find(src, src_end)
if not (a < b and c < d):
    sys.exit("start label must come before end label")
block = "\n".join(src[c:d])
for pat, rep in RENAMES:
    block = re.sub(pat, rep, block)
lines[a:b] = block.split("\n")
open(path, "w", encoding="utf-8").write("\n".join(lines))
print(f"replaced {b - a} lines with {d - c}")
