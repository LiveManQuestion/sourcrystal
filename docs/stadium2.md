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
  Pokémon caught. "Re-order BOXes" works without that.

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
