"""PyBoy harness: boot a save to the overworld and call ROM functions.
Game(rom, sym, ram).boot() continues the save; call(name, B=..., HL=...) runs
a function at the next DelayFrame (switching the ROM bank directly, so a and
the flags come back) and restores every register afterwards. Used by
storage_test.py."""
import io, re
from pyboy import PyBoy

class Game:
    def __init__(self, rom, sym, ram):
        self.sym = {}
        for l in open(sym):
            m = re.match(r'([0-9a-f]+):([0-9a-f]+) (\S+)', l)
            if m: self.sym[m[3]] = (int(m[1], 16), int(m[2], 16))
        self.ram = io.BytesIO(bytes(ram))
        self.pb = PyBoy(rom, window='null', ram_file=self.ram, sound_emulated=False, log_level='ERROR')
        self.pending = None
        self.result = None
        self.saved = None
        b, a = self.sym['DelayFrame']
        self.pb.hook_register(b, a, self._hook, None)

    def addr(self, name):
        return self.sym[name][1]

    def run(self, n):
        for _ in range(n): self.pb.tick(1, False)

    def press(self, b, hold=6, after=30):
        self.pb.button_press(b); self.run(hold); self.pb.button_release(b); self.run(after)

    def boot(self):
        self.run(600); self.press('start', after=200); self.press('start', after=120)
        self.press('a', after=120); self.press('a', after=600)

    def _hook(self, ctx):
        r = self.pb.register_file
        if self.saved is not None and r.SP == self.saved['SP']:
            # The injected call returned here.
            self.result = dict(A=r.A, F=r.F, B=r.B, C=r.C, D=r.D, E=r.E, HL=r.HL)
            bank = self.saved.pop('bank')
            self.pb.memory[self.addr('hROMBank')] = bank
            self.pb.memory[0x2000] = bank
            for k, v in self.saved.items(): setattr(r, k, v)
            self.saved = None
            return
        if self.pending and self.saved is None:
            name, args = self.pending
            self.pending = None
            self.saved = dict(A=r.A, F=r.F, B=r.B, C=r.C, D=r.D, E=r.E, HL=r.HL, SP=r.SP)
            self.saved['bank'] = self.pb.memory[self.addr('hROMBank')]
            bank, target = self.sym[name]
            sp = r.SP - 2
            ret = self.addr('DelayFrame')
            self.pb.memory[sp] = ret & 0xff
            self.pb.memory[sp + 1] = ret >> 8
            r.SP = sp
            if bank:
                self.pb.memory[self.addr('hROMBank')] = bank
                self.pb.memory[0x2000] = bank
            for k in 'ABCDE':
                if k in args: setattr(r, k, args[k])
            if 'HL' in args: r.HL = args['HL']
            r.PC = target

    def call(self, name, frames=120, **args):
        self.result = None
        self.pending = (name, args)
        for _ in range(frames):
            self.pb.tick(1, False)
            if self.result is not None: break
        assert self.result is not None, 'call did not return: ' + name
        res = self.result
        res['z'] = bool(res['F'] & 0x80)
        res['c'] = bool(res['F'] & 0x10)
        return res

    def mem(self, name, n=1, off=0):
        a = self.addr(name) + off
        return [self.pb.memory[a + i] for i in range(n)]

    def wram(self, bank, name, n=1, off=0):
        a = self.addr(name) + off
        return [self.pb.memory[bank, a + i] for i in range(n)]

    def sram(self, name, n=1, off=0):
        b, a = self.sym[name]
        a += off
        return [self.pb.memory[b, a + i] for i in range(n)]

    def sram_dump(self):
        return bytes(self.pb.memory[bank, 0xa000 + i] for bank in range(4) for i in range(0x2000))
