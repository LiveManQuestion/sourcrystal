"""Headless Challenge Mode battle test against Smogon-AI trainers (PyBoy).
usage: battle.py [--smart] ROM SYM SAVE TRAINER(e.g. "BUGSY 2") SEED [max_frames] [end_screenshot.png]

Boots SAVE (32 KB cartridge RAM), continues, turns on Challenge Mode, makes the
player's first Pokemon a bulky level 100 Typhlosion (Tackle/Swords Dance/Roar/
Toxic), queues a battle script in free WRAM0 ($cfe2) via the map reentry
script queue, then plays with random inputs. Prints one JSON line: whether the
battle started and ended, the result, any jump to the rst $38 crash vector
(with the stack), how often each hooked AI routine ran, and every enemy
switch-in ("switches"; summarize with switch_report.py).
Needs battle_scripts.json from make_battle_scripts.py.

With --smart, the player keeps the save's own party, is never healed, and
plays the strong greedy policy in smart_player.py instead of random inputs,
so win rates mean something. The JSON line adds the player's actions."""
import io, json, os, random, sys, collections
from pyboy import PyBoy

SMART = '--smart' in sys.argv
argv = [a for a in sys.argv if a != '--smart']
rom, symf, save, trainer, seed = argv[1:6]
max_frames = int(argv[6]) if len(argv) > 6 else 60 * 60 * 12
rng = random.Random(int(seed))
here = os.path.dirname(os.path.abspath(__file__))
script = json.load(open(os.path.join(here, 'battle_scripts.json')))[trainer]
TACKLE, SWORDS_DANCE, ROAR, TOXIC, HAZE, REFLECT, CYNDAQUIL, TYPHLOSION = script[:8]
SCRIPT = bytes(script[8:])

sym = {}
for line in open(symf):
    if line.startswith(';') or ' ' not in line:
        continue
    loc, name = line.split()[:2]
    if ':' not in loc:
        continue
    b, a = loc.split(':')
    sym[name] = (int(b, 16), int(a, 16))
W = lambda n: sym[n][1]

pb = PyBoy(rom, window='null', ram_file=io.BytesIO(open(save, 'rb').read()), sound_emulated=False, log_level='ERROR')
mem = pb.memory

counts = collections.Counter()
events = []
def hook(name):
    def cb(ctx):
        counts[name] += 1
    b, a = sym[name]
    pb.hook_register(b, a, cb, None)

crashed = []
def on_crash(ctx):
    rf = pb.register_file
    sp = rf.SP
    stack = [mem[sp + i] | mem[sp + i + 1] << 8 for i in range(0, 16, 2)]
    crashed.append(frame)
    crashed.append({'sp': hex(sp), 'stack': [hex(x) for x in stack], 'rombank': mem[0xff9d], 'a': rf.A, 'hl': hex(rf.HL)})
pb.hook_register(0, 0x38, on_crash, None)

# Log every enemy switch-in: 'mid' when the AI chose to switch (with the
# active and best switch-in matchup scores), 'forced' after a faint or Roar.
switch_log = []
pending = {'mid': False}
def on_try_switch(ctx):
    counts['AI_TrySwitch'] += 1
    pending['mid'] = True
    pending['scores'] = (mem[W('wEnemyAISwitchScore')], mem[W('wSmogonAIBestScore')])
pb.hook_register(*sym['AI_TrySwitch'], on_try_switch, None)
def on_load_switch(ctx):
    b = pb.register_file.B
    L = sym['wOTPartyMon2'][1] - sym['wOTPartyMon1'][1]
    hp = mem[W('wEnemyMonHP')] << 8 | mem[W('wEnemyMonHP') + 1]
    switch_log.append({'kind': 'mid' if pending['mid'] else 'forced', 'from': mem[W('wEnemyMonSpecies')],
                       'from_hp': hp, 'to': mem[W('wOTPartyMon1Species') + b * L], 'vs': mem[W('wBattleMonSpecies')],
                       'scores': pending.get('scores') if pending['mid'] else None})
    pending['mid'] = False
pb.hook_register(*sym['LoadEnemyMonToSwitchTo'], on_load_switch, None)

for n in ['AI_Smogon', 'SwitchSmogon', 'AISmogon_ChooseReplacement', 'AISmogon_CanStopSetup',
          'AI_Smogon_Screens', 'AI_Smogon_BatonPass', 'AI_Smogon_Encore', 'AI_Smogon_HealBell', 'AI_Smogon_Explosion',
          'AI_Smogon_Phaze', 'AI_Smogon_Haze', 'AI_Smogon_Setup', 'AI_Smogon_Spikes', 'AI_Smogon_Toxic', 'AI_Smogon_Sleep',
          'AI_Smogon_RapidSpin', 'AI_Smogon_Heal', 'AISmogon_PlayerIsPhysical', 'AISmogon_PlayerCanPhaze',
          'AISmogon_FindBestSwitchIn']:
    if n in sym:
        hook(n)
    else:
        print('missing symbol', n)

frame = 0
def run(n):
    global frame
    for _ in range(n):
        pb.tick(1, False)
        frame += 1

def press(btn, hold=4, after=12):
    pb.button_press(btn); run(hold); pb.button_release(btn); run(after)

# boot and continue the save
run(600); press('start', after=200); press('start', after=120); press('a', after=120); press('a', after=300)

# Challenge Mode on, a bulky level 100 Typhlosion that sets up and phazes
mem[W('wChallengeMode')] |= 1
player = None
if SMART:
    sys.path.insert(0, here)
    from smart_player import SmartPlayer
    from smart_player import heal_party
    player = SmartPlayer(pb, sym)
    heal_party(mem, W)
def word(addr, v):
    mem[addr] = v >> 8; mem[addr + 1] = v & 0xff
if not SMART:
    mon = 'wPartyMon1'
    mem[W('wPartySpecies')] = TYPHLOSION
    mem[W(mon + 'Species')] = TYPHLOSION
    for i, mv in enumerate((TACKLE, SWORDS_DANCE, ROAR, TOXIC)):
        mem[W(mon + 'Moves') + i] = mv
        mem[W(mon + 'PP') + i] = 30
    mem[W(mon + 'Level')] = 100
    mem[W(mon + 'Status')] = 0
    word(W(mon + 'HP'), 999); word(W(mon + 'MaxHP'), 999)
    spd = rng.choice((150, 300, 450))
    for st, v in (('Attack', 120), ('Defense', 700), ('Speed', spd), ('SpclAtk', 120), ('SpclDef', 700)):
        word(W(mon + st), v)

# queue the battle script in free WRAM0
base = 0xcfe2
for i, b in enumerate(SCRIPT):
    mem[base + i] = b
mem[W('wMapReentryScriptQueueFlag')] = 1
mem[W('wMapReentryScriptBank')] = 1
mem[W('wMapReentryScriptAddress')] = base & 0xff
mem[W('wMapReentryScriptAddress') + 1] = base >> 8

started = False
enemy_moves = collections.Counter()
last_turn = None
out_frames = 0
while frame < max_frames and not crashed:
    in_battle = mem[W('wBattleMode')] == 2 and mem[W('wOtherTrainerClass')] == SCRIPT[6]
    if in_battle:
        started = True
        out_frames = 0
        if player:
            press(player.button(), after=rng.randint(8, 30))
        else:
            # keep the player's Pokemon alive so the battle runs long
            if rng.random() < 0.02:
                word(W('wBattleMonHP'), 999)
            r = rng.random()
            btn = 'a' if r < 0.70 else 'down' if r < 0.82 else 'up' if r < 0.90 else 'b'
            press(btn, after=rng.randint(8, 30))
        mv = mem[W('wCurEnemyMove')]
        t = mem[W('wEnemyTurnsTaken')], mem[W('wEnemyMonSpecies')], mv
        if t != last_turn and mv:
            enemy_moves[(mem[W('wEnemyMonSpecies')], mv)] += 1
            last_turn = t
    else:
        run(30)
        if started:
            out_frames += 30
            if out_frames > 900:
                break

result = {'switches': switch_log, 
    'trainer': trainer, 'seed': seed, 'frames': frame, 'started': started,
    'ended': started and mem[W('wBattleMode')] == 0, 'won': mem[W('wBattleResult')] & 0xf, 'crashed_at': crashed[:2],
    'hooks': dict(counts), 'enemy_moves': {f'{sp},{mv}': n for (sp, mv), n in enemy_moves.items()},
}
if player:
    result['player_actions'] = player.actions
print(json.dumps(result))
if len(argv) > 7:
    import zlib, struct
    arr = pb.screen.ndarray[:, :, :3].copy()
    h, w, _ = arr.shape
    raw = b''.join(b'\0' + arr[y].tobytes() for y in range(h))
    ch = lambda t, d: struct.pack('>I', len(d)) + t + d + struct.pack('>I', zlib.crc32(t + d) & 0xffffffff)
    open(argv[7], 'wb').write(b'\x89PNG\r\n\x1a\n' + ch(b'IHDR', struct.pack('>IIBBBBB', w, h, 8, 2, 0, 0, 0)) + ch(b'IDAT', zlib.compress(raw)) + ch(b'IEND', b''))
pb.stop(save=False)
