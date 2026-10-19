# PyBoy HBlank DMA issue

Notes for an issue reported to PyBoy (github.com/Baekalfen/PyBoy), so a later
session can answer the maintainers. Written 2026-10-19, against PyBoy 2.8.1
(the newest release on PyPI then). Add the issue's link here once it's posted.

## The bug

In CGB double speed mode, PyBoy's HBlank DMA (HDMA5 bit 7 set) copies two
16-byte blocks per HBlank. Normal speed copies one, which is right; Pan Docs
says HBlank DMA copies $10 bytes per HBlank at either speed.

Measured with `tools/claude/pyboy_hdma_repro.py`: a 33-block HBlank DMA, HDMA5
read after N scanlines (blocks left minus one):

| Scanlines | Normal speed | Double speed | Hardware |
|-----------|--------------|--------------|----------|
| 4         | `$1C`        | `$18`        | `$1C`    |
| 8         | `$18`        | `$10`        | `$18`    |
| 16        | `$10`        | `$00`        | `$10`    |

The "hardware" column comes from Pan Docs, not a measurement: there's no
flash cart or hardware log behind it. Other emulators draw Sour Crystal's
textbox correctly, which agrees with it.

## Why it matters for Sour Crystal

pokecrystal's `_continue_HDMATransfer` (`engine/gfx/dma_transfer.asm`)
starts an HBlank DMA one block longer than needed, counts scanlines, then
stops the last block with `res 7, [rHDMA5]`. Sour Crystal runs in double
speed (`DoubleSpeed`, `home/double_speed.asm`) and vanilla doesn't. In PyBoy
the transfer has already finished by then (HDMA5 reads `$ff`; checked by
hooking that instruction while a textbox opened), so the write (`$7f`, bit 7
clear) starts a 128-block general DMA of leftover `wScratchTilemap` data.
Later font loads overwrite most of it but not the textbox frame tiles
`$ba`-`$bf` (Sour loads only `a`-`z` after the frame), so PyBoy draws the
textbox border as the letters k-p. See also `docs/claude_tools.md`.

## Where the fix probably is (not checked)

`Motherboard.tick` in `pyboy/core/mb.py` runs `hdma.tick()` while the LCD is
in mode 0 and a transfer is active, and `HDMA.tick` returns 206 cycles per
block. In double speed those 206 cycles are probably half an HBlank, so a
second block fits in the same HBlank. Only a guess from reading the source.

## The issue as posted

Title: `HBlank HDMA copies two blocks per HBlank in CGB double speed mode`

Body: the text in the next section, with `tools/claude/pyboy_hdma_repro.py`
(without its docstring) as the code block.

> In CGB double speed mode, HBlank DMA (HDMA5 bit 7 set) copies two 16-byte
> blocks per HBlank instead of one. In normal speed it's correct. Per Pan
> Docs, HBlank DMA copies $10 bytes per HBlank at either speed.
>
> This script builds a tiny CGB ROM. It starts a 33-block HBlank DMA, waits
> 8 scanlines, then reads HDMA5 (the blocks left minus one): [script]
>
> On PyBoy 2.8.1 this prints `0x18` and then `0x10`. Both should be `0x18`.
>
> This breaks a common pattern (pokecrystal's `_continue_HDMATransfer`):
> start an HBlank DMA one block longer than needed, count scanlines, then
> stop it with `res 7, [rHDMA5]`. In double speed the transfer has already
> finished, so that write starts a 128-block general DMA instead, and 2 KB
> of VRAM gets overwritten.

## If the maintainers ask

- **For a ROM file:** run the repro script; it writes `hdma.gbc` to the
  current directory (32 KB, CGB only, no Nintendo logo).
- **"Is this from real hardware?"** No, from Pan Docs, and other emulators
  agree. Say so plainly rather than claiming a hardware test.
- **For the game:** the pattern is in pret/pokecrystal (public). Vanilla
  Crystal doesn't run in double speed, so it isn't affected; the ROM hack
  is. Don't share ROMs.
- **After a fix:** rerun the repro (expect `0x18` twice) and a textbox
  screenshot through `tools/claude/game_call.py`. The textbox border should
  draw correctly. Then delete the PyBoy note from `CLAUDE.md` and the
  paragraph in `docs/claude_tools.md`.
