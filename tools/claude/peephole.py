#!/usr/bin/env python3
"""Conservative peephole optimizer for the sourcrystal sources.

Passes (from the pret wiki "Optimizing assembly code"):
  tail   `call X` + `ret`      -> `jp X`   (only if X never pops a value it didn't push)
  cp0    `cp 0`                -> `and a`
  xora   `ld a, 0`             -> `xor a`  (only if the flags are overwritten before being read)
  jr     `jp [cc,] X`          -> `jr [cc,] X` (X in the same file and section; out-of-range
                                   ones are reverted using the linker's errors, see fixup())

Usage: peephole.py apply   -> rewrite files, record the jr conversions in $PEEPHOLE_STATE
       peephole.py revert FILE:LINE...   -> turn those jr back into jp
Run fix_jr.sh after `apply` to revert the jr that end up out of range.
Already applied to the whole project in commit 342bbfb61; rerunning it mostly
matters for newly written code.
"""
import os, re, sys, glob, json

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..'))
STATE = os.environ.get('PEEPHOLE_STATE', '/tmp/peephole_jr_sites.json')

# Timing-sensitive, link/time capsule, RAM-copied or fixed-layout code is left alone.
EXCLUDE_PREFIXES = (
    'engine/link/', 'mobile/', 'lib/', 'audio/', 'engine/debug/',
    'home/serial.asm', 'home/vblank.asm', 'home/lcd.asm', 'home/header.asm',
    'home/farcall.asm', 'home/init.asm', 'home/video.asm', 'home/audio.asm',
    'engine/gfx/copy_tilemap_at_once.asm', 'engine/gfx/load_push_oam.asm',
    'engine/phone/phonering_copytilemapatonce.asm',
    'engine/menus/savemenu_copytilemapatonce.asm',
    'engine/tilesets/tileset_anims.asm', 'engine/games/slot_machine.asm',
    'engine/battle_anims/bg_effects.asm', 'engine/gfx/dma_transfer.asm',
    'engine/printer/', 'engine/movie/trade_animation.asm',
)
# Calls through these reach unknown code, so they never become tail jumps.
DISPATCHERS = {'_hl_', '_de_', 'JumpTable', 'FarCall_hl', 'FarCall_de', 'CallPointerAt',
               'FarPointerCall', 'RunCallback', 'StackJumpTable'}

GLOBAL_RE = re.compile(r'^([A-Za-z_][\w#@]*)(?:\.(\w+))?(::?)')
LOCAL_RE = re.compile(r'^\.(\w+):{0,2}(?=\s|;|$)')
INSTR_RE = re.compile(r'^\s+(\S.*)$')


def code(line):
    return re.sub(r';.*', '', line).rstrip()


def all_files():
    files = []
    for d in ('engine', 'home', 'data', 'maps', 'audio', 'mobile', 'lib', 'gfx', 'ram', 'macros', 'constants'):
        files += glob.glob(os.path.join(ROOT, d, '**', '*.asm'), recursive=True)
    files += glob.glob(os.path.join(ROOT, '*.asm'))
    return sorted(os.path.relpath(f, ROOT) for f in files)


def eligible(f):
    return f.startswith(('engine/', 'home/')) and not f.startswith(EXCLUDE_PREFIXES)


class Parsed:
    """Per-file line info: global scope, segment id, whether in a macro/rept/load."""
    def __init__(self, f):
        self.f = f
        self.lines = open(os.path.join(ROOT, f), encoding='utf-8').read().split('\n')
        n = len(self.lines)
        self.scope = [None] * n
        self.seg = [0] * n
        self.skip = [False] * n
        self.labels = {}  # name -> line index (globals as 'Name', locals as 'Scope.local')
        scope = None
        seg = 0
        depth = 0  # macro/rept/load nesting
        for i, raw in enumerate(self.lines):
            c = code(raw)
            s = c.strip()
            u = s.split()[0].upper() if s else ''
            if re.match(r'^(SECTION|ENDSECTION|LOAD|ENDL|PUSHS|POPS)\b', s, re.I) and not raw.startswith(('.',)) :
                seg += 1
            if u in ('MACRO', 'REPT', 'FOR', 'LOAD') or re.match(r'^\w+:\s*MACRO\b', s, re.I):
                depth += 1
            m = GLOBAL_RE.match(c)
            if m and not c[:1].isspace():
                name = m.group(1)
                if m.group(2):
                    self.labels[name + '.' + m.group(2)] = i
                else:
                    if not re.match(r'^\w+\s*:?\s*(MACRO|EQU|EQUS|=|SET|RB|RW|RL)\b', s, re.I) \
                            and not re.match(r'^(DEF|IF|ELIF|ELSE|ENDC|INCLUDE|SECTION|ENDSECTION|ASSERT|STATIC_ASSERT|REDEF|MACRO|ENDM|REPT|ENDR|FOR|PURGE|EXPORT|OPT|PUSHO|POPO|CHARMAP|NEWCHARMAP|SETCHARMAP|PRINTLN|PRINT|WARN|FAIL|SHIFT|LOAD|ENDL|UNION|NEXTU|ENDU|INCBIN)\b', s, re.I):
                        scope = name
                        self.labels[name] = i
            m = LOCAL_RE.match(c)
            if m and scope:
                self.labels[scope + '.' + m.group(1)] = i
            self.scope[i] = scope
            self.seg[i] = seg
            self.skip[i] = depth > 0
            if u in ('ENDM', 'ENDR', 'ENDL'):
                depth = max(0, depth - 1)

    def instr(self, i):
        """The instruction on line i (lowercased, whitespace-normalized), or None."""
        c = code(self.lines[i])
        m = INSTR_RE.match(c)
        if not m:
            return None
        return re.sub(r'\s+', ' ', m.group(1).strip()).replace(' ,', ',').replace(', ', ',')

    def is_label_line(self, i):
        c = code(self.lines[i])
        return bool(c) and not c[:1].isspace()

    def resolve(self, i, target):
        if target.startswith('.'):
            key = (self.scope[i] or '') + target
        else:
            key = target
        return self.labels.get(key)


def next_code_line(p, i):
    j = i + 1
    while j < len(p.lines) and code(p.lines[j]).strip() == '':
        j += 1
    return j if j < len(p.lines) else None


def prev_code_line(p, i):
    j = i - 1
    while j >= 0 and code(p.lines[j]).strip() == '':
        j -= 1
    return j if j >= 0 else None


# ---------- callee stack-safety analysis ----------

class Index:
    def __init__(self):
        self.parsed = {}
        self.where = {}  # global label -> file
        for f in all_files():
            try:
                p = Parsed(f)
            except UnicodeDecodeError:
                continue
            self.parsed[f] = p
            for k in p.labels:
                if '.' not in k:
                    self.where.setdefault(k, []).append(f)
        self.memo = {}

    def safe(self, f, start):
        """Is the code starting at line `start` of f free of pops of values it didn't push?"""
        key = (f, start)
        if key in self.memo:
            return self.memo[key]
        self.memo[key] = True  # assume safe on recursion
        ok = self._safe(f, start)
        self.memo[key] = ok
        return ok

    def _safe(self, f, start):
        p = self.parsed[f]
        depth = 0
        i = start
        first = True
        while i < len(p.lines):
            c = code(p.lines[i])
            if not first and c and not c[:1].isspace() and GLOBAL_RE.match(c) and not c.startswith('.'):
                # fell through into the next function
                return self.safe(f, i) if depth == 0 else False
            first = False
            ins = p.instr(i)
            if ins is None:
                i += 1
                continue
            op = ins.split(' ')[0]
            if re.search(r'\bsp\b', ins) or op in ('reti',) or ins == 'jp hl' or op in ('jp', 'jr') and 'hl' == ins.split(',')[-1]:
                return False
            if op == 'push':
                depth += 1
            elif op == 'pop':
                if depth == 0:
                    return False
                depth -= 1
            elif op in ('jp', 'jr'):
                tgt = ins.split(' ', 1)[1].split(',')[-1]
                if not tgt.startswith('.') and re.match(r'^\w+$', tgt):
                    # tail jump to another function
                    if depth != 0:
                        return False
                    fs = self.where.get(tgt)
                    if not fs or len(fs) != 1:
                        return False
                    if not self.safe(fs[0], self.parsed[fs[0]].labels[tgt]):
                        return False
                elif not re.match(r'^\.?\w+$', tgt):
                    return False
                if ',' not in ins and tgt.startswith('.'):
                    # unconditional local jump: keep scanning textually (conservative)
                    pass
            elif op == 'rst':
                if 'jumptable' in ins.lower():
                    return False
            elif op == 'ret' and depth != 0:
                # returning through a pushed address
                return False
            i += 1
        return depth == 0


def callee_safe(idx, p, i, target):
    if target in DISPATCHERS:
        return False
    if target.startswith('.'):
        li = p.resolve(i, target)
        if li is None:
            return False
        return idx.safe(p.f, li)
    fs = idx.where.get(target)
    if not fs or len(fs) != 1:
        return False
    return idx.safe(fs[0], idx.parsed[fs[0]].labels[target])


# ---------- passes ----------

FLAG_KILLERS = re.compile(r'^(and|or|xor|cp|sub) |^add a,|^pop af$')
FLAG_NEUTRAL = re.compile(r'^(ld|ldh|ldi|ld[id]) |^push |^pop (bc|de|hl)$|^nop$')


def flags_dead_after(p, i):
    j = i
    while True:
        j = next_code_line(p, j)
        if j is None or p.is_label_line(j) or p.skip[j]:
            return False
        ins = p.instr(j)
        if ins is None:
            return False
        if FLAG_KILLERS.match(ins):
            return True
        if FLAG_NEUTRAL.match(ins) and not re.match(r'^ld hl,sp', ins):
            # `ld [hli], a` etc. leave flags alone
            continue
        return False


def set_instr(line, new):
    m = re.match(r'^(\s+)(\S[^;]*?)(\s*;.*)?$', line)
    return m.group(1) + new + (m.group(3) or '')


def apply():
    idx = Index()
    stats = {'tail': 0, 'cp0': 0, 'xora': 0, 'jr': 0}
    jr_sites = []
    for f, p in idx.parsed.items():
        if not eligible(f):
            continue
        lines = p.lines
        delete = set()
        # tail calls
        for i in range(len(lines)):
            if p.skip[i]:
                continue
            ins = p.instr(i)
            if not ins:
                continue
            m = re.match(r'^call ([.\w]+)$', ins)
            if m:
                j = next_code_line(p, i)
                if j is not None and not p.is_label_line(j) and p.instr(j) == 'ret' and not p.skip[j]:
                    if callee_safe(idx, p, i, m.group(1)):
                        lines[i] = set_instr(lines[i], 'jp ' + m.group(1))
                        delete.add(j)
                        stats['tail'] += 1
                continue
            if ins == 'cp 0':
                window = ' '.join(p.instr(k) or '' for k in range(i + 1, min(i + 4, len(lines))))
                if 'daa' not in window:
                    lines[i] = set_instr(lines[i], 'and a')
                    stats['cp0'] += 1
                continue
            if ins in ('ld a,0', 'ld a,$0', 'ld a,$00', 'ld a,false', 'ld a,FALSE'.lower()):
                if flags_dead_after(p, i):
                    lines[i] = set_instr(lines[i], 'xor a')
                    stats['xora'] += 1
        for j in sorted(delete, reverse=True):
            del lines[j]
        # reparse after deletions, then jp -> jr
        open(os.path.join(ROOT, f), 'w', encoding='utf-8').write('\n'.join(lines))
        p = Parsed(f)
        lines = p.lines
        for i in range(len(lines)):
            if p.skip[i]:
                continue
            ins = p.instr(i)
            if not ins:
                continue
            m = re.match(r'^jp ((?:n?z|n?c),)?([.\w]+)$', ins)
            if not m or m.group(2) == 'hl':
                continue
            cond = m.group(1)
            if not cond:
                # jump tables: unconditional jp next to another one
                k = next_code_line(p, i)
                if k is not None and re.match(r'^jp [.\w]+$', p.instr(k) or ''):
                    continue
                k = prev_code_line(p, i)
                if k is not None and re.match(r'^jp [.\w]+$', p.instr(k) or ''):
                    continue
            t = p.resolve(i, m.group(2))
            if t is None or p.seg[t] != p.seg[i] or p.skip[t]:
                continue
            new = 'jr ' + (cond.replace(',', ', ') if cond else '') + m.group(2)
            orig = re.match(r'^\s+(\S[^;]*?)\s*(;.*)?$', lines[i]).group(1)
            lines[i] = set_instr(lines[i], new)
            jr_sites.append([f, i + 1, orig])
            stats['jr'] += 1
        open(os.path.join(ROOT, f), 'w', encoding='utf-8').write('\n'.join(lines))
    json.dump(jr_sites, open(STATE, 'w'))
    print(stats)


def revert(locs):
    sites = {(f, l): o for f, l, o in json.load(open(STATE))}
    byfile = {}
    for loc in locs:
        f, l = loc.rsplit(':', 1)
        if (f, int(l)) not in sites:
            print('not a converted site:', loc)
            continue
        byfile.setdefault(f, []).append(int(l))
    n = 0
    for f, ls in byfile.items():
        path = os.path.join(ROOT, f)
        lines = open(path, encoding='utf-8').read().split('\n')
        for l in ls:
            lines[l - 1] = set_instr(lines[l - 1], sites[(f, l)])
            n += 1
        open(path, 'w', encoding='utf-8').write('\n'.join(lines))
    print('reverted', n)


if __name__ == '__main__':
    if sys.argv[1] == 'apply':
        apply()
    elif sys.argv[1] == 'revert':
        revert(sys.argv[2:])
