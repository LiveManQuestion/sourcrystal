# Pokémon Stadium 2 compatibility

Found by running Stadium 2 (US) in mupen64plus with Transfer Pak emulation and
tracing what it reads and writes on the Game Boy cartridge (2026-10-15).

## What Stadium 2 checks

- **The cartridge**: Stadium 2 has a table of Game Boy titles (US ROM
  `0x23a5700`). For Crystal it matches `PM_CRYSTAL` plus the "base" block
  that `tools/stadium` writes at the end of the ROM. Stadium 2 contains a copy
  of Crystal's banks for the GB Tower: the "base" bits say which banks of the
  cartridge match it, and the `N64PS3` half-bank checksums cover the rest.
  The build runs `tools/stadium` on every ROM, so any build is recognized.
- **The save**: the main save checksum, and the player name and ID.
- **The Lab** (PC, boxes, items, mail) only accepts a save made on one of these
  maps (US ROM `0x97f1c`, group.number): every vanilla Pokémon Center 1F,
  `POKECENTER_2F` (20.1), `POKECOM_CENTER_ADMIN_OFFICE_MOBILE` (11.21) and
  `PLAYERS_HOUSE_2F` (24.7). The `UNUSED_*_MAP` placeholders keep those IDs;
  Sour Crystal's new Pokémon Centers (Mt. Moon, Safari Zone Gate) can't be on
  the list.

## What it reads and writes

- Game Pak check: SRAM bank 1 `$A000-$AD1F` (options, game data, checksums,
  the start of `sBox`) and a little of bank 0.
- Lab: banks 2 and 3 (boxes 1-14) and the mail in bank 0.
- Box changes are written to `sBox1 - sBox14` directly, as vanilla saves them
  (vanilla copies `sBox` there when saving and back when loading). Stadium 2
  leaves `sBox` alone. Box names are written to `wBoxNames` in both save copies,
  with both checksums updated.
- Moving Pokémon between the Game Pak and Stadium's own boxes needs 150
  Pokémon caught in the Game Pak's Pokédex. "Re-order BOXes" works without
  that. Tested: re-ordering boxes, and moving the current box to an N64 box
  (with the Pokédex flags set in a test save); the game loads both correctly.

## GB Tower

Stadium's Game Boy emulator doesn't handle GDMA (`SafeHDMATransfer`, which
waits for HBlank on `rSTAT`): with GDMA the intro is blank, party icons are
garbled and NPCs turn into other sprites (in ares too, so it's Stadium, not
the emulator). `_Start` detects the GB Tower from the registers it starts
games with (b = $11, l = $00; a Game Boy Color has b = $00, l = $0D, a GBA
b = $01) and sets `hGBTower`, which turns off GDMA (`CheckGDMA`,
`BillsPC_Get2bpp`) and the battle start delay that GDMA needed. So every ROM
works in the GB Tower, and handhelds keep GDMA. `sourcrystal_GBTower.gbc`
(`-D _GBTOWER`) forces `hGBTower` on. Found by storing the boot registers in
SRAM (bank 0 `$BF20`) and reading Stadium's SRAM copy from a mupen64plus
savestate (N64 `0x1B74A0` = bank 0). Tested in mupen64plus: intro, title,
party menu with `sourcrystal.gbc`; PyBoy (CGB) leaves `hGBTower` off.

ares (148) runs the GB Tower at full speed. It reads the Game Boy save from
`<ROM name>.ram` and the clock from `<ROM name>.rtc` next to the ROM (not
`.sav`): `head -c 32768 sourcrystal.sav > sourcrystal_GBTower.ram`.

In mupen64plus, emulators need two mupen64plus-core fixes and an LLE RSP:

- Without the Transfer Pak fix (the system mupen64plus 2.6.0 lacks it),
  Stadium reads the whole ROM and then says "The Transfer Pak is not set
  properly". Upstream mupen64plus-core and RMG 0.8.2+ have it.
- Without RMG's RSP/RDP timing patch (Rosalie241/RMG `e8d4d6341b`, not
  upstream), it reads ROM banks 1-4, $27 and $7F and then hangs on a white
  screen. HLE RSP hangs too.
- Vanilla Crystal behaves the same, so these are emulator problems.

`tools/claude/stadium2/build_core.sh` builds upstream mupen64plus-core plus
that patch into `.stadium2/` (git-ignored; the dynarec needs `nasm`, without
it the core falls back to the much slower cached interpreter).
`play.sh [STADIUM2.n64 GBROM GBSAV]` (default: the US ROM, `sourcrystal.gbc`,
`sourcrystal.sav`) plays with it: RMG's cxd4 RSP and GLideN64 (`GFX=parallel`
for RMG's parallel-RDP), the first gamepad as controller 1 with the Transfer
Pak, and a backup of GBSAV first. For headless runs, pass
the same `--corelib`, `--rsp` and cxd4 settings to `run.sh`.

The "Out of bound read from GB RAM 8000" warning is Stadium reading SRAM
bank 4 during the Game Pak check (a real MBC3 mirrors bank 0 there); it's
harmless with `gb_ram_mirroring.diff`, which `build_core.sh` applies: banks
past the end of the cartridge's ROM or RAM mirror the start, like on
hardware (upstream returns nothing for them). Stadium writes a 32-byte
pattern to bank 0 `$A000` before that read, probably to check the mirroring.

mupen64plus-core used to truncate the Game Boy save to the 32 KB of SRAM the
first time it wrote it, dropping the 48-byte clock footer of a 32816-byte
`.sav`, so the game then asked to reset the clock. Fixed upstream in
`902bc60f` (`docs/mupen64plus_pr.md`), which `build_core.sh` builds; RMG's
own core still truncates until an RMG release picks it up.

Upstream's MBC3 clock starts with `last_time` = 0 (`poweron_mbc3_rtc`), so
when the GB Tower latches and reads it, the core adds every second since
1970: past 511 days, which sets the day carry bit that `_FixDays` treats as
a reset. Gold/Silver/Crystal then say "The clock's time may be wrong"
(Continue shows TIME ???) and save that flag (`sRTCStatusFlags` = `$80`).
`gb_rtc_start_time.diff` (in `build_core.sh`) starts it at power on. The
clock still starts at day 0 each session: it doesn't load the `.sav`
footer's clock.

## Testing

Needs `mupen64plus` and `xorg-server-xvfb`, and a Stadium 2 (US) ROM in `.z64`
byte order (`37 80 40 12` at the start is `.v64`: swap every byte pair). Use
copies of saves: mupen64plus writes the Game Boy save back on exit.

    Xvfb :77 -screen 0 800x600x24 &
    python3 tools/claude/stadium2/setmap.py sourcrystal.sym in.sav out.sav 8 1
    tools/claude/stadium2/lab.sh OUTDIR ps2.z64 sourcrystal.gbc out.sav run

`setmap.py` moves a save into the Azalea Pokémon Center (8.1) so the Lab
accepts it. `lab.sh` goes to the Lab's PC and saves screenshots; `snap.sh`
sends more keys and takes screenshots; `tpak.py OUTDIR/run.log sourcrystal.sym`
lists what Stadium read and wrote. Close the emulator with Escape (`xkey.py
Escape`) so it writes the save.

`tools/claude/storage_test.py` tests the box code itself in PyBoy, including
changes made to the saved boxes outside the game.
