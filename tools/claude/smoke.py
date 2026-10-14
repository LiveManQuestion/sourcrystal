"""Run a ROM headless with a fixed input script; save screenshots at checkpoints.
usage: smoke.py ROM RAMFILE OUTDIR
Prints a hash per checkpoint: run it on two ROMs and diff the output to check
that a change doesn't alter boot, title, Continue, overworld and menus."""
import io, os, sys, hashlib
from pyboy import PyBoy

rom, ramfile, out = sys.argv[1:4]
os.makedirs(out, exist_ok=True)
ram = io.BytesIO(open(ramfile, 'rb').read()) if ramfile != '-' else None
pb = PyBoy(rom, window='null', ram_file=ram, rtc_file=io.BytesIO(b'\0' * 48) if False else None, sound_emulated=False, log_level='ERROR')

frame = 0
def run(n):
    global frame
    for _ in range(n):
        pb.tick(1, True)
        frame += 1

def press(btn, hold=6, after=20):
    pb.button_press(btn)
    run(hold)
    pb.button_release(btn)
    run(after)

import zlib, struct
def write_png(path, arr):
    h, w, _ = arr.shape
    raw = b''.join(b'\0' + arr[y].tobytes() for y in range(h))
    def chunk(t, d):
        return struct.pack('>I', len(d)) + t + d + struct.pack('>I', zlib.crc32(t + d) & 0xffffffff)
    open(path, 'wb').write(b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', w, h, 8, 2, 0, 0, 0)) + chunk(b'IDAT', zlib.compress(raw)) + chunk(b'IEND', b''))

shots = []
def shot(name):
    arr = pb.screen.ndarray[:, :, :3].copy()
    path = os.path.join(out, f'{len(shots):02d}_{name}.png')
    write_png(path, arr)
    shots.append((name, hashlib.sha1(arr.tobytes()).hexdigest()[:10]))

# Intro -> title -> main menu -> Continue
run(600); shot('intro')
press('start', after=200); shot('title')
press('start', after=120); shot('mainmenu')
press('a', after=120); shot('continue_info')
press('a', after=300); shot('overworld')
# walk a little in each direction and open the start menu
for d in ('down', 'left', 'up', 'right'):
    press(d, hold=40, after=30)
shot('walked')
press('start', after=60); shot('startmenu')
press('a', after=120); shot('submenu')
press('b', after=60); press('b', after=60); shot('back')
for name, h in shots:
    print(name, h)
pb.stop(save=False)
