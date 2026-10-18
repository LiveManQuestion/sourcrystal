# Save file migrations

This directory contains all of the code for migrating from a prior save version
to a newer one. It's intended as a sort of reference for how and why a
change had to be made, because putting this stuff behind the git log doesn't
seem to be the best course of action.

Only the latest migration is `INCLUDE`'d inside of `save_compat.asm`, plus
the ones it reuses for unreleased versions (04 runs 03 for version 02 saves).

> [!NOTE]
> Save migration routines end with a `jp ApplySaveVersion`/`ApplyBackupSaveVersion`, to ensure the proper save version is tagged.
> It is also *always* called `MigrateSaveFile`/`MigrateBackupSaveFile`.

## Save versions summary

### (save version 04)

* Move the link battle records, Hall of Fame, Crystal data and Battle Tower
  data up $30 bytes, and wSpecialPhoneCallID - wDailyPhoneItemFlags up a
  byte, to vanilla's addresses, so PKHeX edits the player's gender, GS Ball
  flags and Blue Card points correctly. Version 03 was never released, so
  this migration also updates version 02 saves (running 03.asm's changes
  first).

### (save version 03)

* Add placeholder maps so the Blackthorn and Cerulean map groups use vanilla's
  map IDs again. Pokemon Stadium 2 only accepts saves made in a Pokemon Center
  from its list of vanilla map IDs. Saved map IDs after the placeholders move up.
* Go back to vanilla's PC box layout (14 boxes), which Pokemon Stadium 2 reads
  and changes. The old boxes aren't converted: they're emptied, and box names
  and themes are reset. The legendary caught flags (`wPlayerCaught`) move to
  vanilla's unused bytes after `wCurBox`.

### v7.0 (save version 02)

* Change how the Pokegear stores contacts. This results in the phone essentially having
  maximum capacity.

### v6.2 (save version 01)

* Save tagging system introduced.
