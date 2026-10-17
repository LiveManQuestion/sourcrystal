"""Make the cartridge RAM the headless tests boot from out of a save file,
without touching the save: its first 32 KB, with sRTCStatusFlags cleared.
A set flag (the emulator's clock was reset) makes Continue ask to reset the
clock, an extra prompt the harnesses' boot button presses don't expect, so
battles never start.

usage: save_ram.py [SAVE] OUT    (SAVE defaults to sourcrystal.sav)"""
import os
import sys

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..')


def rtc_flags_offset():
    for line in open(os.path.join(ROOT, 'sourcrystal.sym')):
        parts = line.split()
        if len(parts) == 2 and parts[1] == 'sRTCStatusFlags':
            bank, addr = (int(x, 16) for x in parts[0].split(':'))
            return bank * 0x2000 + addr - 0xa000
    sys.exit('sRTCStatusFlags not in sourcrystal.sym: build the ROM first')


def main(argv):
    if len(argv) not in (1, 2):
        sys.exit(__doc__)
    save = argv[0] if len(argv) == 2 else os.path.join(ROOT, 'sourcrystal.sav')
    out = argv[-1]
    if os.path.abspath(out) == os.path.abspath(save):
        sys.exit('refusing to write over the save')
    ram = bytearray(open(save, 'rb').read()[:0x8000])
    off = rtc_flags_offset()
    if ram[off]:
        print(f'cleared sRTCStatusFlags (was ${ram[off]:02x})', file=sys.stderr)
        ram[off] = 0
    with open(out, 'wb') as f:
        f.write(ram)


if __name__ == '__main__':
    main(sys.argv[1:])
