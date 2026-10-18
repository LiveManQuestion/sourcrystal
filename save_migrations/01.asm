; version 00 -> 01: simply update the save version
; (Kept for reference: save_compat.asm no longer includes it.)

; Version 01 started tagging saves with their version in sGameVersion, which
; Apply[Backup]SaveVersion writes. Every save migration ends by jumping there.

MigrateSaveFile:
	jp ApplySaveVersion

MigrateBackupSaveFile:
	jp ApplyBackupSaveVersion
