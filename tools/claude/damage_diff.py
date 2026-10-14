"""Differential damage test against vanilla Crystal (PyBoy, headless).
usage: damage_diff.py VANILLA.gbc VANILLA.sym ROM.gbc ROM.sym [CASES]
Build vanilla first (copy pokecrystal-master/ somewhere and run make there).
Runs BattleCommand_DamageStats, _DamageCalc and _Stab from a small driver in
WRAM on random battlers, moves, items, weather, screens, stat levels, crits,
badges and link mode in both ROMs, and compares wCurDamage and wTypeModifier
(damage variation is random, so it's skipped)."""
import io, os, sys, random, re
from pyboy import PyBoy
os.chdir(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
vrom, vsym, rom, sym = sys.argv[1:5]
N = int(sys.argv[5]) if len(sys.argv) > 5 else 2000

def consts(path, start=0):
    C, v = {}, start
    for l in open(path):
        l = l.split(";")[0].strip()
        m = re.match(r"const_def\s*(\d+)?", l)
        if l.startswith("const_def"): v = int(m.group(1) or 0); continue
        if l.startswith("const_skip"): v += 1; continue
        m = re.match(r"const\s+(\w+)", l)
        if m: C[m.group(1)] = v; v += 1
    return C
ITEM = consts("pokecrystal-master/constants/item_constants.asm")
MON = consts("pokecrystal-master/constants/pokemon_constants.asm")
TYPE = consts("pokecrystal-master/constants/type_constants.asm")
types = [TYPE[t] for t in ("NORMAL","FIGHTING","FLYING","POISON","GROUND","ROCK","BUG","GHOST","STEEL",
                           "FIRE","WATER","GRASS","ELECTRIC","PSYCHIC_TYPE","ICE","DRAGON","DARK")]
items = [0]*6 + [ITEM[i] for i in ("LIGHT_BALL","THICK_CLUB","METAL_POWDER","LEFTOVERS","CHARCOAL","MYSTIC_WATER",
    "MIRACLE_SEED","MAGNET","TWISTEDSPOON","NEVERMELTICE","BLACKBELT_I","SOFT_SAND","SHARP_BEAK","POISON_BARB",
    "SILVERPOWDER","HARD_STONE","SPELL_TAG","DRAGON_FANG","DRAGON_SCALE","BLACKGLASSES","METAL_COAT","PINK_BOW","POLKADOT_BOW")]
species_bias = [MON[m] for m in ("PIKACHU","CUBONE","MAROWAK","DITTO")]

def syms(p):
    d = {}
    for l in open(p):
        l = l.split(";")[0].strip()
        if ":" in l and " " in l:
            a, n = l.split()[:2]; b, o = a.split(":"); d[n] = (int(b, 16), int(o, 16))
    return d

class Rom:
    def __init__(self, rom, sym):
        self.s = syms(sym)
        self.pb = PyBoy(rom, window="null", sound_emulated=False, log_level="ERROR")
        self.pb.tick(400, False)
        self.state = io.BytesIO(); self.pb.save_state(self.state)
        b, _ = self.s["BattleCommand_DamageStats"]
        assert self.s["BattleCommand_DamageCalc"][0] == b and self.s["BattleCommand_Stab"][0] == b
        self.bank = b
        rb = self.s["Moves"]; off = rb[0] * 0x4000 + rb[1] - 0x4000
        self.moves = open(rom, "rb").read()[off:off + 7 * 251]
    def W(self, n): return self.s[n][1]
    def run(self, case):
        pb, m, W = self.pb, self.pb.memory, self.W
        self.state.seek(0); pb.load_state(self.state)
        m[0xffff] = 0  # no interrupts
        def word(a, v): m[a] = v >> 8; m[a + 1] = v & 0xff
        for side, mon, stats, stlv, scr, sub in (("player", "wBattleMon", "wPlayerAttack", "wPlayerStatLevels", "wPlayerScreens", "wPlayerSubStatus"),
                                                 ("enemy", "wEnemyMon", "wEnemyAttack", "wEnemyStatLevels", "wEnemyScreens", "wEnemySubStatus")):
            c = case[side]
            m[W(mon + "Species")] = c["species"]; m[W(mon + "Item")] = c["item"]; m[W(mon + "Level")] = c["level"]
            m[W(mon + "Type1")], m[W(mon + "Type2")] = c["types"]
            for k in range(5):
                word(W(mon + "Attack") + 2 * k, c["stats"][k]); word(W(stats) + 2 * k, c["raw"][k])
            for k in range(7): m[W(stlv) + k] = c["levels"][k]
            m[W(scr)] = c["screens"]
            for k in range(1, 6): m[W(sub + str(k))] = 0
        mv = case["move"]
        for st in ("wPlayerMoveStruct", "wEnemyMoveStruct"):
            for k in range(7): m[W(st) + k] = self.moves[7 * (mv - 1) + k]
        m[W("wBattleWeather")] = case["weather"]; m[W("wCriticalHit")] = case["crit"]
        m[W("hBattleTurn")] = case["turn"]; m[W("wJohtoBadges")] = case["badges"]
        m[W("wLinkMode")] = case["link"]; m[W("wBattleMode")] = 2; m[W("wInBattleTowerBattle")] = 0
        if "wChallengeMode" in self.s: m[W("wChallengeMode")] = 0
        word(W("wCurDamage"), 0); m[W("wTypeModifier")] = 0
        # driver: call DamageStats, DamageCalc, Stab; then loop forever
        code = []
        for n in ("BattleCommand_DamageStats", "BattleCommand_DamageCalc", "BattleCommand_Stab"):
            a = self.s[n][1]; code += [0xcd, a & 0xff, a >> 8]
        code += [0x18, 0xfe]
        base = 0xc000
        for k, v in enumerate(code): m[base + k] = v
        m[0x2000] = self.bank; m[W("hROMBank")] = self.bank
        rf = pb.register_file
        rf.SP = 0xdff0
        rf.PC = base
        pb.tick(3, False)
        return (m[W("wCurDamage")] << 8 | m[W("wCurDamage") + 1], m[W("wTypeModifier")], rf.PC)

rng = random.Random(1)
def side():
    sp = rng.choice(species_bias) if rng.random() < 0.15 else rng.randint(1, 251)
    return dict(species=sp, item=rng.choice(items), level=rng.randint(2, 100),
                types=(rng.choice(types), rng.choice(types)),
                stats=[rng.randint(5, 999) for _ in range(5)], raw=[rng.randint(5, 999) for _ in range(5)],
                levels=[rng.choice([7, 7, 1, 4, 9, 13]) for _ in range(7)], screens=rng.choice([0, 0, 1 << 3, 1 << 4, 1 << 3 | 1 << 4]))
V = Rom(vrom, vsym)
H = Rom(rom, sym)
damaging = [i + 1 for i in range(251) if V.moves[7 * i + 2] > 1]
assert V.moves == H.moves
bad = 0; nonzero = 0
for t in range(N):
    case = dict(player=side(), enemy=side(), move=rng.choice(damaging), weather=rng.randint(0, 3),
                crit=rng.random() < 0.2, turn=rng.randint(0, 1), badges=rng.randint(0, 255), link=rng.choice([0, 0, 0, 3]))
    a = V.run(case); b = H.run(case)
    nonzero += a[0] > 0
    if a[:2] != b[:2] or a[2] != 0xc000 + 9 or b[2] != 0xc000 + 9:
        bad += 1
        if bad <= 10: print("MISMATCH", a, b, case)
print(f"{N} cases, {nonzero} with nonzero damage, {bad} mismatches")
