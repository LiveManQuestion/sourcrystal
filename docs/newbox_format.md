# Newbox data format

The PC boxes use vanilla Crystal's save layout, so Pokémon Stadium 2 and Gen 2
save tools can read them. Sour Crystal adds a slot map per box (so Pokémon can
sit in any slot) and themes. See `engine/pc/bills_pc.asm` for the code.

## Save file address locations

Offsets are in the 32 KB save file (SRAM bank × 0x2000 + address − 0xA000).

* 0x4000-0x5E2F: boxes 1-7 (0x450 bytes each, vanilla format)
* 0x5E30-0x5EBB: slot maps for boxes 1-7 (20 bytes each)
* 0x6000-0x7E2F: boxes 8-14
* 0x7E30-0x7EBB: slot maps for boxes 8-14
* 0x2D10-0x315F: a copy of the current box (vanilla's `sBox`)

Box names (`wBoxNames`, 9 characters each, no terminator) and the current box
(`wCurBox`) are in the main save data at vanilla's locations. Themes
(`wBoxThemes`, 1 byte per box) are in the main save data too.

The saved copy of each box is the one in boxes 1-14, as in vanilla (which
copies `sBox` there when saving and back when loading). The game keeps `sBox`
equal to the current box.

## Box format

The vanilla box format: a count, a species list ending with 0xFF (Egg for
eggs), then 20 Pokémon (the first 32 bytes of the party structure), 20 OT names
and 20 nicknames (11 bytes each). The mons are in slot order.

## Slot map format

20 bytes, one per slot, starting from the top left corner and continuing along
the row (so the slot below the first one is the 5th). Each byte is 0 for an
empty slot, or the Pokémon's position in the box's lists (1-20). The positions
must be 1, 2, … up to the count, in slot order. If they aren't (for example
after Pokémon Stadium 2 changed the box), the game puts the Pokémon in the
first slots when loading.

## Saving

Changes to a box are kept in WRAM (up to 3 boxes) until the game is saved, so
resetting without saving leaves the saved boxes as they were. Before saving, the
changed boxes are also copied to spare SRAM ("staging", `sStagedBoxes`), so a
save interrupted after the main save data is written can still write them when
the game is loaded.

## Box themes

* 0x00: Pokédex
* 0x01: Pokégear ♂
* 0x02: Pokégear ♀
* 0x03: Pack ♂
* 0x04: Pack ♀
* 0x05: Trainer Card ♂
* 0x06: Trainer Card ♀
* 0x07: Normal
* 0x08: Fighting
* 0x09: Flying
* 0x0A: Poison
* 0x0B: Ground
* 0x0C: Rock
* 0x0D: Bug
* 0x0E: Ghost
* 0x0F: Steel
* 0x10: Fire
* 0x11: Water
* 0x12: Grass
* 0x13: Electric
* 0x14: Psychic
* 0x15: Ice
* 0x16: Dragon
* 0x17: Dark
