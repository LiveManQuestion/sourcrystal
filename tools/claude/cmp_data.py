"""Compare the assembled battle data of this ROM with vanilla Crystal.
usage: cmp_data.py [ROM.gbc ROM.sym]   (defaults to sourcrystal.gbc/.sym)
Builds vanilla with tools/claude/build_vanilla.sh if needed. Prints one line
per table: moves, move effect scripts, type chart, base stats (stats, types,
catch rate, base exp), item held effects, and every table in data/battle and
data/types plus the critical hit and priority lists. Pointer tables differ by
address only; their non-pointer bytes are compared."""
import glob, os, re, subprocess, sys

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..")
os.chdir(ROOT)
rom, sym = sys.argv[1:3] if len(sys.argv) > 2 else ("sourcrystal.gbc", "sourcrystal.sym")
vrom, vsym = subprocess.run(["bash", "tools/claude/build_vanilla.sh"], capture_output=True,
                            text=True, check=True).stdout.split()

def syms(path):
    d = {}
    for line in open(path):
        line = line.split(";")[0].strip()
        if ":" in line and " " in line:
            loc, name = line.split()[:2]
            b, a = loc.split(":")
            d[name] = (int(b, 16), int(a, 16))
    return d

def off(bank, addr):
    return addr if bank == 0 else bank * 0x4000 + addr - 0x4000

V, H = open(vrom, "rb").read(), open(rom, "rb").read()
vs, hs = syms(vsym), syms(sym)
at = lambda data, s, name: off(*s[name])
bad = 0
# Intended differences (not battle mechanics)
EXPECTED = {"StatNames": "Sour Crystal's SP.ATK/SP.DEF wording"}

def report(name, same, detail=""):
    global bad
    if not same and name in EXPECTED:
        print(f"{name:28} differs as expected: {EXPECTED[name]}")
        return
    bad += not same
    print(f"{name:28} {'identical' if same else 'DIFF ' + detail}")

def until(data, start, end_byte=0xff, step=1):
    i = start
    while data[i] != end_byte:
        i += step
    return data[start:i + 1]

# Moves: 7 bytes each
a, b = V[at(V, vs, "Moves"):][:7 * 251], H[at(H, hs, "Moves"):][:7 * 251]
report("Moves", a == b, str(sorted({i // 7 + 1 for i in range(len(a)) if a[i] != b[i]})))

# Move effect scripts, through the pointer table
def scripts(data, s):
    n = (s["MoveEffectsPointersEnd"][1] - s["MoveEffectsPointers"][1]) // 2 if "MoveEffectsPointersEnd" in s else None
    x, bank = at(data, s, "MoveEffectsPointers"), s["MoveEffects"][0]
    out = []
    for i in range(n or 157):  # NUM_MOVE_EFFECTS
        p = data[x + 2 * i] | data[x + 2 * i + 1] << 8
        out.append(until(data, off(bank, p)))
    return out
ev, eh = scripts(V, vs), scripts(H, hs)
report("MoveEffects (scripts)", ev == eh, str([i for i in range(len(ev)) if ev[i] != eh[i]]))

# Type chart, up to its end marker
report("TypeMatchups", until(V, at(V, vs, "TypeMatchups")) == until(H, at(H, hs, "TypeMatchups")))

# Base data: the struct sizes differ (more TM bits), so find each stride
def stride(data, s):
    x = at(data, s, "BaseData")
    for k in range(28, 64):
        if all(data[x + k * i] == i + 1 for i in range(251)):
            return x, k
(xv, kv), (xh, kh) = stride(V, vs), stride(H, hs)
diff = [i + 1 for i in range(251) if V[xv + kv * i:xv + kv * i + 11] != H[xh + kh * i:xh + kh * i + 11]]
report("BaseData (stats/types/...)", not diff, str(diff))

# Item held effects and their parameters
xv, xh = at(V, vs, "ItemAttributes"), at(H, hs, "ItemAttributes")
diff = [i + 1 for i in range(255) if V[xv + 7 * i + 2:xv + 7 * i + 4] != H[xh + 7 * i + 2:xh + 7 * i + 4]]
report("ItemAttributes (held)", not diff, str(diff))

# Every other battle table, up to the next label (or its end marker)
POINTER_TABLES = {"BattleCommandPointers", "TypeNames"}
ENTRY_SIZE = {"HeldStatUpItems": 3}  # effect, then a pointer
files = (glob.glob("pokecrystal-master/data/battle/*.asm") + glob.glob("pokecrystal-master/data/types/*.asm")
         + ["pokecrystal-master/data/moves/critical_hit_moves.asm", "pokecrystal-master/data/moves/effects_priorities.asm"])
for f in sorted(files):
    for line in open(f):
        m = re.match(r"([A-Z]\w*):", line)
        if not m or m.group(1) in POINTER_TABLES or m.group(1) not in vs:
            continue
        name = m.group(1)
        if name not in hs:
            report(name, False, "(missing)")
            continue
        bank, addr = vs[name]
        size = min((o for n, (bb, o) in vs.items() if bb == bank and o > addr), default=addr + 64) - addr
        a, b = V[at(V, vs, name):][:size], H[at(H, hs, name):][:size]
        if 0xff in a and name not in ("WeatherTypeModifiers", "WeatherMoveModifiers"):
            a = a[:a.index(0xff) + 1]
            b = b[:len(a)]
        if name in ENTRY_SIZE:
            k = ENTRY_SIZE[name]
            a, b = a[::k], b[::k]
        report(name, a == b, os.path.relpath(f, "pokecrystal-master"))

print("ALL IDENTICAL" if not bad else f"{bad} DIFFERENT")
