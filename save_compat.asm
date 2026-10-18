; This file contains save file migration actions.
; The migration should only update saves from the last released version,
; so as to avoid getting bogged down with too much code.
; (e.g. version 1 -> 2, not version 1 -> 3.) Versions that were never
; released can share a migration with the one before them.

; Loading a newer save file should either error out or be unstable,
; since we don't know what that newer version contains.

; 00 = v6.1
; 01 = v6.2
;      * Add the save file version.
; 02 = vX.Y
;      * wPhoneList is now a bit flag array.
; 03 = vX.Y
;      * Placeholder maps restore vanilla's map IDs (for Pokemon Stadium 2).
;      * Vanilla's PC box layout (for Pokemon Stadium 2). Boxes are emptied.
; 04 = vX.Y
;      * Vanilla's addresses for the link battle records, Hall of Fame,
;        Crystal data, Battle Tower data and Blue Card points (for PKHeX).
;        Version 02 saves migrate too (03 was never released).

; When making a breaking change to the save format, the following
; should be updated:
DEF GAME_VERSION EQU 4
; The oldest version the migration can update.
DEF OLDEST_MIGRATABLE_VERSION EQU 2
INCLUDE "save_migrations/03.asm"
INCLUDE "save_migrations/04.asm"

;------------------------------------------------------------------------------

ApplySaveVersion:
	ld a, BANK(sGameVersion)
	call OpenSRAM
	ld hl, sGameVersion
	ld [hl], GAME_VERSION
	jp SaveChecksum

ApplyBackupSaveVersion:
	ld a, BANK(sBackupGameVersion)
	call OpenSRAM
	ld hl, sBackupGameVersion
	ld [hl], GAME_VERSION
	call CloseSRAM
	call SaveBackupChecksum
	and a ; clear carry
	ret

	const_def
	const MIGRATION_NO_CHANGE_NEEDED
	const MIGRATION_SHOULD_MIGRATE
	const MIGRATION_CANNOT_MIGRATE
	const MIGRATION_UNKNOWN
SaveCanBeMigrated::
; a = the save file's version
; returns:
;    a = MIGRATION_*
;    f = may be affected

; Saves from before version 01 never wrote a version, so that byte may hold
; anything. If it holds a random value, a player who knows the save is that
; old can force a migration like so:
	push af
		; press RIGHT while selecting "CONTINUE"
		ldh a, [hJoypadDown]
		and D_RIGHT
		cp D_RIGHT
		jr z, .force_migration
	pop af

; On some emulators, an unwritten version byte is $ff, so treat $ff as an old
; save:
	assert GAME_VERSION < $ff
	cp -1
	jr z, .yes

; Otherwise, the check can proceed as normal.
	sub a, GAME_VERSION
	jr z, .no
	jr nc, .unknown
	cp LOW(OLDEST_MIGRATABLE_VERSION - GAME_VERSION)
	jr nc, .yes
	; older than OLDEST_MIGRATABLE_VERSION
	ld a, MIGRATION_CANNOT_MIGRATE
	ret
.yes
	ld a, MIGRATION_SHOULD_MIGRATE
	ret
.no
	ld a, MIGRATION_NO_CHANGE_NEEDED
	ret
; the save is from a newer version: don't know what to do
.unknown
	ld a, MIGRATION_UNKNOWN
	ret
.force_migration
	pop af
	jr .yes

InitiateBackupMigration:
	ld a, BANK(sBackupGameVersion)
	call OpenSRAM
	ld a, [sBackupGameVersion]
	call SaveCanBeMigrated
	cp MIGRATION_NO_CHANGE_NEEDED
	jr z, .done
	cp MIGRATION_CANNOT_MIGRATE
	jr z, MigrationCannotMigrate
	cp MIGRATION_SHOULD_MIGRATE
	jp z, MigrateBackupSaveFile
	jr MigrationUnknown
.done
	call CloseSRAM
	ret

InitiateMigration:
	ld a, BANK(sGameVersion)
	call OpenSRAM
	ld a, [sGameVersion]
	call SaveCanBeMigrated
	cp MIGRATION_NO_CHANGE_NEEDED
	jr z, .done
	cp MIGRATION_CANNOT_MIGRATE
	jr z, MigrationCannotMigrate
	cp MIGRATION_SHOULD_MIGRATE
	jp z, MigrateSaveFile
	jr MigrationUnknown
.done
	call CloseSRAM
	ret

MigrationUnknown:
	call CloseSRAM
	ld a, [wOptions]
	push af
	set NO_TEXT_SCROLL, a
	ld [wOptions], a
	ld hl, UnknownVersionText
	call PrintText
	pop af
	ld [wOptions], a
	scf
	ret

MigrationCannotMigrate:
	call CloseSRAM
	ld a, [wOptions]
	push af
	set NO_TEXT_SCROLL, a
	ld [wOptions], a
	ld hl, CannotMigrateText
	call PrintText
	pop af
	ld [wOptions], a
	scf
	ret

UnknownVersionText:
	text "This save file"
	line "appears to be from"
	para "a newer version of"
	line "the game."
	para "Please use it with"
	line "the newer version"
	cont "instead."
	prompt

CannotMigrateText:
	text "This save file"
	line "appears to be from"
	para "an older version"
	line "of the game."
	para "Consult the docs"
	line "for details on"
	para "how to update the"
	line "save file."
	prompt
