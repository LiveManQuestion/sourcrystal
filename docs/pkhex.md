# PKHeX compatibility

PKHeX (and other Gen 2 save editors) read a Sour Crystal save as an English
Crystal save: it has vanilla's main and backup save data, checksums, party,
Pokédex, Day-Care and PC box layout (`docs/newbox_format.md`), and since save
version 04 vanilla's addresses for the link battle records, Hall of Fame,
Crystal data (player gender, GS Ball flags), Battle Tower data and Blue Card
points (`save_migrations/04.asm`). Keep saved data at vanilla's addresses.

Checked (2026-10-18) with PKHeX.Core from `PKHeX-Avalonia/` in a small
console program: loading the user's save, editing money, a nickname, box 1
(the current box) and box 2, gender and Blue Card points, and booting the
result headlessly; the game had every change.

What PKHeX doesn't know about:

- **Slot positions**: PKHeX writes each box in vanilla's packed format. A box
  whose Pokémon count changed loses its slot positions: the game puts its
  Pokémon in the first slots when loading (as after Stadium 2).
- **Legality**: encounters that differ from vanilla's (wild areas, levels)
  show as illegal.
- **Event flags and scene variables**: PKHeX labels them as vanilla's, but
  Sour Crystal added some (and `wBoxThemes` is in its event work range).
- Box themes, the slot maps and the save version aren't shown.

PKHeX's second checksum compares the backup save's checksum with the main
data's. The game writes the backup a few frames after the main copy, so the
play time often differs and PKHeX reports it as invalid; that's harmless, and
PKHeX copies the main data to the backup when it saves.
