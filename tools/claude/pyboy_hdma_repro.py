"""Repro for the PyBoy HBlank DMA bug in docs/pyboy_hdma_issue.md: builds a
tiny CGB ROM (hdma.gbc in the current directory) and prints HDMA5 after 8
scanlines of a 33-block HBlank DMA. Expected 0x18 at both speeds.
usage: ~/.local/share/uv/tools/pyboy/bin/python pyboy_hdma_repro.py"""
from pyboy import PyBoy

def run(double_speed):
    code = bytes.fromhex(
        "f3"                                    # di
        + ("3e01e04d10" if double_speed else "")   # ld a,1 / ldh [KEY1],a / stop
        + "3ec0e051afe052e053e054"              # HDMA source $C000, dest $8000
        + "f044fe0a20fa"                       # wait for LY == 10
        + "3ea0e055"                            # HDMA5 = $A0: HBlank DMA, 33 blocks
        + "0e08"                                # c = 8
        + "f04447f044b828fb0d20f5"              # wait for LY to change c times
        + "f055ea00c1"                          # [$C100] = HDMA5
        + "3e01ea01c118fe")                     # [$C101] = 1, loop forever
    rom = bytearray(0x8000)
    rom[0x100:0x104] = bytes.fromhex("00c35001")  # nop / jp $0150
    rom[0x143] = 0xC0                             # CGB only
    rom[0x150:0x150 + len(code)] = code
    rom[0x14D] = -sum(rom[0x134:0x14D]) - 25 & 0xFF  # header checksum
    open("hdma.gbc", "wb").write(rom)
    p = PyBoy("hdma.gbc", window="null", cgb=True)
    while p.memory[0xC101] != 1:
        p.tick()
    print("double speed" if double_speed else "normal speed", hex(p.memory[0xC100]))
    p.stop(save=False)

run(False)  # 0x18: 8 blocks copied in 8 lines
run(True)   # 0x10: 16 blocks copied in 8 lines; hardware copies 8 (0x18)
