"""Diff files against vanilla (pokecrystal-master/), grouped by function.
usage: vanilla_diff.py [-s] FILE...   (-s: only count changed lines per function)
Normalizes the noise first, so only real changes show: comments, whitespace,
jr vs. jp, ' vs. " character literals, call+ret vs. jp tail calls, and names
that pret renamed after Sour Crystal forked (wBattleAfterAnim, rWBK, PAD_*...).
Changed lines are listed under the label (in this repo's file) they fall in."""
import difflib, os, re, sys

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..")

RENAMES = [
    (r"\bwBattleAfterAnim\b", "wNumHits"),
    (r"\bANIM_(\w+) - BATTLE_AFTERANIMS\b", r"BATTLEANIM_\1"),
    (r"\brWBK\b", "rSVBK"),
    (r"\bB_PAD_(UP|DOWN|LEFT|RIGHT)\b", r"D_\1_F"),
    (r"\bB_PAD_(A|B)\b", r"\1_BUTTON_F"),
    (r"\bB_PAD_(SELECT|START)\b", r"\1_F"),
    (r"\bPAD_(UP|DOWN|LEFT|RIGHT)\b", r"D_\1"),
    (r"\bPAD_(A|B)\b", r"\1_BUTTON"),
    (r"\bPAD_(SELECT|START)\b", r"\1"),
    (r"\bTILE_SIZE\b", "LEN_2BPP_TILE"),
    (r"\bOBJ_SIZE\b", "SPRITEOAMSTRUCT_LENGTH"),
    (r"\bB_LCDC_WIN_MAP\b", "rLCDC_WINDOW_TILEMAP"),
    (r"\bSCREEN_AREA\b", "SCREEN_WIDTH * SCREEN_HEIGHT"),
    (r"\bTILEMAP_AREA\b", "BG_MAP_WIDTH * BG_MAP_HEIGHT"),
]

def normalize(line):
    line = line.split(";")[0]
    line = re.sub(r"\s+", " ", line).strip()
    if not line:
        return ""
    line = re.sub(r"\bjr\b", "jp", line)
    line = line.replace("'", '"')
    for pat, rep in RENAMES:
        line = re.sub(pat, rep, line)
    return line

def lines_of(path):
    raw = open(path, encoding="utf-8", errors="replace").read().split("\n")
    out = []
    for i, line in enumerate(raw):
        n = normalize(line)
        if n:
            out.append((n, i + 1))
    # "call X" + "ret" is the same as "jp X"
    merged = []
    for j, (n, i) in enumerate(out):
        if n == "ret" and merged and merged[-1][0].startswith("call ") and "," not in merged[-1][0]:
            merged[-1] = ("jp " + merged[-1][0][5:], merged[-1][1])
            continue
        merged.append((n, i))
    return merged

def label_at(raw, lineno):
    for i in range(lineno - 1, -1, -1):
        m = re.match(r"([A-Za-z_]\w*):", raw[i])
        if m:
            return m.group(1)
    return "(top)"

def main():
    os.chdir(ROOT)
    args = sys.argv[1:]
    summary = "-s" in args
    files = [a for a in args if a != "-s"]
    for path in files:
        vpath = os.path.join("pokecrystal-master", path)
        if not os.path.exists(vpath):
            print(f"== {path}: not in vanilla")
            continue
        a, b = lines_of(vpath), lines_of(path)
        raw = open(path, encoding="utf-8", errors="replace").read().split("\n")
        vraw = open(vpath, encoding="utf-8", errors="replace").read().split("\n")
        groups = {}
        sm = difflib.SequenceMatcher(None, [x[0] for x in a], [x[0] for x in b], autojunk=False)
        for tag, i1, i2, j1, j2 in sm.get_opcodes():
            if tag == "equal":
                continue
            where = label_at(raw, b[j1][1]) if j1 < len(b) else label_at(raw, len(raw))
            g = groups.setdefault(where, [])
            g += [f"- {vraw[a[i][1] - 1].strip()}" for i in range(i1, i2)]
            g += [f"+ {raw[b[j][1] - 1].strip()}" for j in range(j1, j2)]
        print(f"== {path}: {sum(len(g) for g in groups.values())} changed lines in {len(groups)} places")
        for where, g in groups.items():
            print(f"  {where}: {len(g)}")
            if not summary:
                for line in g[:40]:
                    print("    " + line)
                if len(g) > 40:
                    print(f"    ... {len(g) - 40} more")

if __name__ == "__main__":
    main()
