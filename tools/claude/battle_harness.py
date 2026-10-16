"""Headless Challenge Mode battles against Smogon-AI trainers (PyBoy), shared
by battle.py, ai_trace.py and ai_profile.py.

    battle = Battle(rom, sym, save, 'WHITNEY 2', seed, smart=True)
    battle.on('SwitchSmogon', lambda ctx: ...)   # any number per label
    battle.start()                               # boot, Continue, queue the battle
    result = battle.run(max_frames)              # play it out
    battle.stop()

start() boots SAVE (32 KB cartridge RAM), continues, turns on Challenge Mode
and queues a battle script (from battle_scripts.json, made by
make_battle_scripts.py) in free WRAM0 ($cfe2) via the map reentry script
queue. The player is either:
- smart=False: the first party slot becomes a bulky level 100 Typhlosion
  (Tackle/Swords Dance/Roar/Toxic) that presses random buttons and gets
  healed now and then. Good for crashes and stalls, not for win rates.
- smart=True: the save's own party, healed once, played by smart_player.py.

run() returns: started, ended, won (wBattleResult: 0 win, 1 loss, 2 draw),
frames, crashed_at (a jump to the rst $38 crash vector, with the stack),
player_left / enemy_left (Pokemon with HP left at the end), enemy_moves
({"species,move": count} of the moves the AI picked) and, when smart, the
player's actions."""
import collections
import io
import json
import os
import random
import sys

from pyboy import PyBoy

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from pokedata import load_sym  # noqa: E402


class Battle:
    def __init__(self, rom, symf, save, trainer, seed, smart=False):
        self.trainer, self.seed, self.smart = trainer, seed, smart
        self.rng = random.Random(int(seed))
        script = json.load(open(os.path.join(HERE, 'battle_scripts.json')))[trainer]
        self.move_ids = script[:8]
        self.script = bytes(script[8:])
        self.sym = load_sym(symf)
        self.pb = PyBoy(rom, window='null', ram_file=io.BytesIO(open(save, 'rb').read()),
                        sound_emulated=False, log_level='ERROR')
        self.mem = self.pb.memory
        self.frame = 0
        self.crashed = []
        self.player = None
        self._hooks = {}
        self.on_address(0, 0x38, self._on_crash)

    def W(self, name):
        return self.sym[name][1]

    def word(self, addr):
        return self.mem[addr] << 8 | self.mem[addr + 1]

    def set_word(self, addr, value):
        self.mem[addr] = value >> 8
        self.mem[addr + 1] = value & 0xff

    def on(self, label, fn):
        """Call fn(ctx) whenever the CPU reaches label. Several callbacks can
        share a label (PyBoy allows one hook per address). PyBoy swallows
        exceptions in hooks, so keep callbacks simple or count errors."""
        self.on_address(*self.sym[label], fn)

    def on_address(self, bank, addr, fn):
        key = (bank, addr)
        if key not in self._hooks:
            self._hooks[key] = []
            fns = self._hooks[key]
            self.pb.hook_register(bank, addr, lambda ctx: [f(ctx) for f in fns], None)
        self._hooks[key].append(fn)

    def _on_crash(self, ctx):
        rf = self.pb.register_file
        sp = rf.SP
        stack = [self.mem[sp + i] | self.mem[sp + i + 1] << 8 for i in range(0, 16, 2)]
        self.crashed.append(self.frame)
        self.crashed.append({'sp': hex(sp), 'stack': [hex(x) for x in stack],
                             'rombank': self.mem[0xff9d], 'a': rf.A, 'hl': hex(rf.HL)})

    def tick(self, n):
        for _ in range(n):
            self.pb.tick(1, False)
            self.frame += 1

    def press(self, button, hold=4, after=12):
        self.pb.button_press(button)
        self.tick(hold)
        self.pb.button_release(button)
        self.tick(after)

    def start(self):
        mem, W = self.mem, self.W
        # boot and continue the save
        self.tick(600)
        self.press('start', after=200)
        self.press('start', after=120)
        self.press('a', after=120)
        self.press('a', after=300)
        mem[W('wChallengeMode')] |= 1
        if self.smart:
            from smart_player import SmartPlayer, heal_party
            self.player = SmartPlayer(self.pb, self.sym, hook=self.on)
            heal_party(mem, W)
        else:
            tackle, swords_dance, roar, toxic, _, _, _, typhlosion = self.move_ids
            mon = 'wPartyMon1'
            mem[W('wPartySpecies')] = typhlosion
            mem[W(mon + 'Species')] = typhlosion
            for i, move in enumerate((tackle, swords_dance, roar, toxic)):
                mem[W(mon + 'Moves') + i] = move
                mem[W(mon + 'PP') + i] = 30
            mem[W(mon + 'Level')] = 100
            mem[W(mon + 'Status')] = 0
            self.set_word(W(mon + 'HP'), 999)
            self.set_word(W(mon + 'MaxHP'), 999)
            speed = self.rng.choice((150, 300, 450))
            for stat, v in (('Attack', 120), ('Defense', 700), ('Speed', speed),
                            ('SpclAtk', 120), ('SpclDef', 700)):
                self.set_word(W(mon + stat), v)
        # queue the battle script in free WRAM0
        base = 0xcfe2
        for i, b in enumerate(self.script):
            mem[base + i] = b
        mem[W('wMapReentryScriptQueueFlag')] = 1
        mem[W('wMapReentryScriptBank')] = 1
        mem[W('wMapReentryScriptAddress')] = base & 0xff
        mem[W('wMapReentryScriptAddress') + 1] = base >> 8

    def alive(self, first, count):
        length = self.W(first[:-1] + '2') - self.W(first)
        return sum(1 for i in range(self.mem[self.W(count)])
                   if self.word(self.W(first + 'HP') + i * length))

    def in_battle(self):
        return (self.mem[self.W('wBattleMode')] == 2
                and self.mem[self.W('wOtherTrainerClass')] == self.script[6])

    def run(self, max_frames):
        mem, W, rng = self.mem, self.W, self.rng
        started = False
        # Pokemon left during the battle (a lost battle heals the party after)
        left = (None, None)
        enemy_moves = collections.Counter()
        last_turn = None
        out_frames = 0
        while self.frame < max_frames and not self.crashed:
            if self.in_battle():
                started = True
                out_frames = 0
                left = (self.alive('wPartyMon1', 'wPartyCount'), self.alive('wOTPartyMon1', 'wOTPartyCount'))
                if self.player:
                    self.press(self.player.button(), after=rng.randint(8, 30))
                else:
                    # keep the player's Pokemon alive so the battle runs long
                    if rng.random() < 0.02:
                        self.set_word(W('wBattleMonHP'), 999)
                    r = rng.random()
                    button = 'a' if r < 0.70 else 'down' if r < 0.82 else 'up' if r < 0.90 else 'b'
                    self.press(button, after=rng.randint(8, 30))
                move = mem[W('wCurEnemyMove')]
                turn = mem[W('wEnemyTurnsTaken')], mem[W('wEnemyMonSpecies')], move
                if turn != last_turn and move:
                    enemy_moves[(mem[W('wEnemyMonSpecies')], move)] += 1
                    last_turn = turn
            else:
                self.tick(30)
                if started:
                    out_frames += 30
                    if out_frames > 900:
                        break
        result = {'trainer': self.trainer, 'seed': self.seed, 'frames': self.frame, 'started': started,
                  'ended': started and mem[W('wBattleMode')] == 0, 'won': mem[W('wBattleResult')] & 0xf,
                  'crashed_at': self.crashed[:2],
                  'enemy_moves': {f'{sp},{mv}': n for (sp, mv), n in enemy_moves.items()}}
        result['player_left'], result['enemy_left'] = left
        if result['won'] == 1:
            # lost: the last faint can come after the last snapshot
            result['player_left'] = 0
        if self.player:
            result['player_actions'] = self.player.actions
        return result

    def screenshot(self, path):
        import struct
        import zlib
        arr = self.pb.screen.ndarray[:, :, :3].copy()
        h, w, _ = arr.shape
        raw = b''.join(b'\0' + arr[y].tobytes() for y in range(h))
        chunk = lambda t, d: struct.pack('>I', len(d)) + t + d + struct.pack('>I', zlib.crc32(t + d) & 0xffffffff)
        open(path, 'wb').write(b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', w, h, 8, 2, 0, 0, 0))
                               + chunk(b'IDAT', zlib.compress(raw)) + chunk(b'IEND', b''))

    def stop(self):
        self.pb.stop(save=False)
