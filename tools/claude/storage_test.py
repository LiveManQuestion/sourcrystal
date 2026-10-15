"""Model-based test of the box storage system (engine/pc/bills_pc.asm).
usage: storage_test.py ROM SYM RAM [SEED] [STEPS]

Random puts, removes, box<->box and party<->box swaps and saves, checked
against a Python model after every few steps (every slot, plus the saved
boxes' and buffers' counts, species lists and slot maps). Then: resetting
without saving, a save interrupted when the boxes are being written, the
saved boxes being changed outside the game (as Pokemon Stadium 2 does), and a
new game's first save. Last line: RESULT: OK. Uses a copy of RAM only."""
import os, random, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from game_call import Game

ROM, SYM = sys.argv[1], sys.argv[2]
NUM_BOXES, MONS_PER_BOX, NUM_BUFFERS = 14, 20, 3
save0 = open(sys.argv[3], 'rb').read()[:0x8000]
seed = int(sys.argv[4]) if len(sys.argv) > 4 else 1
steps = int(sys.argv[5]) if len(sys.argv) > 5 else 300
rng = random.Random(seed)
fails = []

def check(cond, msg):
    if not cond:
        fails.append(msg)
        print('FAIL:', msg)

def mon_id(g):
    hi, lo = g.mem('wBufferMonID', 2)
    return hi << 8 | lo

def read_slot(g, b, c):
    r = g.call('GetStorageBoxMon', B=b, C=c)
    return None if r['z'] else mon_id(g)

def read_box(g, b):
    return [read_slot(g, b, c) for c in range(1, MONS_PER_BOX + 1)]

def read_party(g):
    return [read_slot(g, 0, c) for c in range(1, g.mem('wPartyCount')[0] + 1)]

def raw_box_ok(count, species, slotmap, where):
    ok = count <= MONS_PER_BOX and species[count] == 0xff
    pos = [v for v in slotmap if v]
    ok &= pos == list(range(1, count + 1))
    check(ok, f'{where}: count {count} species {species[:count + 1]} map {slotmap}')

def check_raw(g):
    """Saved boxes and buffers must have consistent counts, lists and maps."""
    sym = g.sym
    for b in range(1, NUM_BOXES + 1):
        name = f'sBox{b}'
        count = g.sram(name)[0]
        species = g.sram(name, MONS_PER_BOX + 1, 1)
        maps = 'sBoxSlotMaps1' if b <= 7 else 'sBoxSlotMaps8'
        slotmap = g.sram(maps, MONS_PER_BOX, ((b - 1) % 7) * MONS_PER_BOX)
        raw_box_ok(count, species, slotmap, f'saved box {b}')
    table = g.mem('wBoxBufferBoxes', NUM_BUFFERS)
    for n, b in enumerate(table):
        if not b: continue
        base = f'wBoxBuffer{n + 1}'
        slotmap = g.wram(2, base + 'SlotMap', MONS_PER_BOX)
        count = g.wram(2, base + 'Box')[0]
        species = g.wram(2, base + 'Box', MONS_PER_BOX + 1, 1)
        raw_box_ok(count, species, slotmap, f'buffer {n + 1} (box {b})')
    check(len([b for b in table if b]) == len(set(b for b in table if b)), f'duplicate buffers {table}')

def compare(g, boxes, party, what):
    for b in range(1, NUM_BOXES + 1):
        got = read_box(g, b)
        check(got == boxes[b], f'{what}: box {b} is {got}, expected {boxes[b]}')
    got = read_party(g)
    check(got == party, f'{what}: party is {got}, expected {party}')
    check_raw(g)

def new_mon(g, ident):
    """Puts party mon 1 with a new ID in wBufferMon."""
    g.call('GetStorageBoxMon', B=0, C=1)
    g.pb.memory[g.addr('wBufferMonID')] = ident >> 8
    g.pb.memory[g.addr('wBufferMonID') + 1] = ident & 0xff

g = Game(ROM, SYM, save0)
g.boot()
boxes = {b: read_box(g, b) for b in range(1, NUM_BOXES + 1)}
party = read_party(g)
print('start: party', party, 'stored', sum(x is not None for b in boxes.values() for x in b))
check_raw(g)
dirty = set()
next_id = 0x1000
saved_state = None
counts = {}

def can_change(*bs):
    need = {b for b in bs if b and b not in dirty}
    return len(dirty | need) <= NUM_BUFFERS, need

for step in range(steps):
    op = rng.choice(['put'] * 4 + ['remove'] * 2 + ['swap'] * 3 + ['party'] * 2 + ['save'])
    # Mostly use a few boxes so the buffer limit is hit sometimes.
    pick = lambda: rng.choice([1, 2, 3, 4, 5, rng.randint(1, NUM_BOXES)])
    counts[op] = counts.get(op, 0) + 1
    if op == 'put':
        b, c = pick(), rng.randint(1, MONS_PER_BOX)
        next_id += 1
        new_mon(g, next_id)
        r = g.call('PutStorageBoxMon', B=b, C=c)
        ok, need = can_change(b)
        check(r['z'] == ok, f'step {step} put {b},{c}: z {r["z"]} expected {ok}')
        if ok:
            dirty |= need
            boxes[b][c - 1] = next_id
    elif op == 'remove':
        b, c = pick(), rng.randint(1, MONS_PER_BOX)
        r = g.call('RemoveStorageBoxMon', B=b, C=c)
        ok, need = can_change(b)
        check(r['z'] == ok, f'step {step} remove {b},{c}: z {r["z"]} expected {ok}')
        if ok:
            dirty |= need
            boxes[b][c - 1] = None
    elif op == 'swap':
        b, c, d, e = pick(), rng.randint(1, MONS_PER_BOX), pick(), rng.randint(1, MONS_PER_BOX)
        r = g.call('SwapStorageBoxSlots', B=b, C=c, D=d, E=e)
        ok, need = can_change(b, d)
        if (b, c) == (d, e):
            ok = True; need = set()
        check((r['A'] == 0) == ok and r['A'] in (0, 1), f'step {step} swap {b},{c} {d},{e}: a {r["A"]} expected ok {ok}')
        if ok and r['A'] == 0:
            dirty |= need
            boxes[b][c - 1], boxes[d][e - 1] = boxes[d][e - 1], boxes[b][c - 1]
    elif op == 'party':
        p = rng.randint(1, len(party) + 1)
        b, c = pick(), rng.randint(1, MONS_PER_BOX)
        box_mon = boxes[b][c - 1]
        party_mon = party[p - 1] if p <= len(party) else None
        if party_mon is None and box_mon is None:
            continue
        if party_mon is None and len(party) == 6:
            continue
        r = g.call('SwapStorageBoxSlots', B=0, C=p, D=b, E=c)
        ok, need = can_change(b)
        if r['A'] in (4, 5):
            # last healthy mon or mail: nothing changes
            pass
        else:
            check((r['A'] == 0) == ok and r['A'] in (0, 1), f'step {step} party {p} <-> {b},{c}: a {r["A"]} expected ok {ok}')
            if ok and r['A'] == 0:
                dirty |= need
                boxes[b][c - 1] = party_mon
                if party_mon is not None and box_mon is not None:
                    party[p - 1] = box_mon
                elif party_mon is not None:
                    party.pop(p - 1)
                else:
                    party.append(box_mon)
    elif op == 'save':
        g.call('SaveGameData', frames=600)
        dirty = set()
        saved_state = ({b: list(v) for b, v in boxes.items()}, list(party), g.sram_dump())
    if step % 25 == 24 or op == 'save':
        compare(g, boxes, party, f'step {step} ({op})')
    if len(fails) > 5:
        break

print('ops', counts, 'dirty', sorted(dirty))
compare(g, boxes, party, 'end')

# Reset without saving: the boxes and party must be as last saved.
if saved_state:
    sboxes, sparty, sram = saved_state
    g2 = Game(ROM, SYM, sram)
    g2.boot()
    compare(g2, sboxes, sparty, 'after reset without saving')

# Interrupted save: stop right when the backup save starts storing the boxes,
# then load. The new boxes and party must be there.
interrupted = {}
def on_commit(ctx):
    if 'sram' not in interrupted:
        interrupted['sram'] = g.sram_dump()
bank, addr = g.sym['CommitStorageBoxes']
g.pb.hook_register(bank, addr, on_commit, None)
# make some changes first, using all 3 buffers
g.call('SaveGameData', frames=600)
for b, c in [(1, 3), (6, 7), (14, 20)]:
    next_id += 1
    new_mon(g, next_id)
    r = g.call('PutStorageBoxMon', B=b, C=c)
    if not r['z']:
        g.call('SaveGameData', frames=600)
        new_mon(g, next_id)
        r = g.call('PutStorageBoxMon', B=b, C=c)
    boxes[b][c - 1] = next_id
interrupted.clear()
g.call('SaveGameData', frames=600)
check('sram' in interrupted, 'CommitStorageBoxes hook')
g3 = Game(ROM, SYM, interrupted['sram'])
g3.boot()
compare(g3, boxes, party, 'after an interrupted save')

check(g3.sram('sStagedBoxes')[0] == 0, 'staging cleared after recovery')

# Pokemon Stadium 2 changes the saved boxes (sBox1 - sBox14) like vanilla, and
# leaves sBox alone. Keep only the last mon of the current box, then load.
sram = bytearray(g3.sram_dump())
cur = g3.mem('wCurBox')[0] + 1
bank, addr = g3.sym[f'sBox{cur}']
sb = bank * 0x2000 + addr - 0xa000
count = sram[sb]
if count:
    expected = [x for x in boxes[cur] if x is not None][-1:]
    last = count - 1
    def move(off, size):
        sram[sb + off:sb + off + size] = sram[sb + off + last * size:sb + off + (last + 1) * size]
    sram[sb + 1] = sram[sb + 1 + last]
    sram[sb + 2] = 0xff
    move(22, 32)
    move(22 + 32 * 20, 11)
    move(22 + 43 * 20, 11)
    sram[sb] = 1
    g4 = Game(ROM, SYM, bytes(sram))
    g4.boot()
    boxes[cur] = expected + [None] * (MONS_PER_BOX - 1)
    compare(g4, boxes, party, 'after Stadium changed the current box')
    check(g4.sram('sBox', 1102) == g4.sram(f'sBox{cur}', 1102), 'sBox matches the current box')
else:
    print('current box is empty; skipped the Stadium test')

# A new game's boxes are empty until it's saved, then the old ones are erased.
g.pb.memory[g.addr('wStorageNewGame')] = 1
empty = {b: [None] * MONS_PER_BOX for b in range(1, NUM_BOXES + 1)}
compare(g, empty, party, 'new game before saving')
next_id += 1
new_mon(g, next_id)
check(g.call('PutStorageBoxMon', B=2, C=4)['z'], 'new game put')
empty[2][3] = next_id
g.call('SaveGameData', frames=600)
compare(g, empty, party, 'new game after saving')
g5 = Game(ROM, SYM, g.sram_dump())
g5.boot()
compare(g5, empty, party, 'new game after loading')

print('RESULT:', 'OK' if not fails else f'{len(fails)} FAILURES')
