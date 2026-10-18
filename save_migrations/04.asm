; version 02 or 03 -> 04: vanilla's SRAM addresses, for save editors (PKHeX).

; The link battle records, Hall of Fame, Crystal data (player gender, GS Ball
; flags) and Battle Tower data were $30 bytes before vanilla's addresses, and
; wSpecialPhoneCallID - wDailyPhoneItemFlags (Blue Card points...) a byte
; before. PKHeX reads and writes some of them at vanilla's addresses. Version
; 02 has the same layout there, so it gets the 02 -> 03 changes (03.asm) and
; these.

DEF OLD_LINK_BATTLE_STATS EQU $b230
DEF OLD_BOX_STAGING_3_PART_2 EQU $be40
DEF SRAM_DATA_SHIFT EQU $30

MigrateSaveFile:
	ld a, [sGameVersion]
	push af
	ld hl, sGameData
	call MigrateDailyData
	pop af
	cp 3
	call nz, MigrateSaveFile03
	call MoveCrystalSRAMData
	jp ApplySaveVersion

MigrateBackupSaveFile:
	ld a, [sBackupGameVersion]
	push af
	ld hl, sBackupGameData
	call MigrateDailyData
	pop af
	cp 3
	call nz, MigrateBackupSaveFile03
	call MoveCrystalSRAMData
	jp ApplyBackupSaveVersion

MigrateDailyData:
; hl = the saved copy of wGameData, with its SRAM bank open
; Move wSpecialPhoneCallID - wDailyPhoneItemFlags up a byte, last byte first.
	ld de, wDailyPhoneItemFlags + 4 - wGameData
	add hl, de
	ld d, h
	ld e, l
	dec hl
	ld c, wDailyPhoneItemFlags + 4 - wSpecialPhoneCallID
.loop
	dec hl
	dec de
	ld a, [hl]
	ld [de], a
	dec c
	jr nz, .loop
	; hl = the new padding byte before wSpecialPhoneCallID
	xor a
	ld [hl], a
	ret

	assert wSpecialPhoneCallID == wLuckyNumberDayTimer + 2 + 1
	assert wKenjiBreakTimer == wDailyPhoneItemFlags + 4 + 3

MoveCrystalSRAMData:
; Move sLinkBattleStats - sBattleTowerDataEnd up SRAM_DATA_SHIFT bytes, over
; the start of the old sBoxStaging3Part2. Those bytes are now the end of
; sBoxStaging3Part1, so a box buffer staged by an interrupted save is kept.
; wGameData isn't loaded yet, so it holds them meanwhile.
	ld a, BANK(sLinkBattleStats)
	call OpenSRAM
	ld hl, OLD_BOX_STAGING_3_PART_2
	ld de, wGameData
	ld bc, SRAM_DATA_SHIFT
	call CopyBytes
	; The ranges overlap, so copy the last byte first.
	ld hl, sBattleTowerDataEnd - SRAM_DATA_SHIFT
	ld de, sBattleTowerDataEnd
	ld bc, sBattleTowerDataEnd - sLinkBattleStats
.loop
	dec hl
	dec de
	ld a, [hl]
	ld [de], a
	dec bc
	ld a, b
	or c
	jr nz, .loop
	ld hl, wGameData
	ld de, OLD_LINK_BATTLE_STATS
	ld bc, SRAM_DATA_SHIFT
	call CopyBytes
	jp CloseSRAM

	assert sLinkBattleStats == OLD_LINK_BATTLE_STATS + SRAM_DATA_SHIFT
	assert sBoxStaging3Part1End == sLinkBattleStats
	assert sBoxStaging3Part2 == OLD_BOX_STAGING_3_PART_2 + SRAM_DATA_SHIFT
	assert sBattleTowerDataEnd - SRAM_DATA_SHIFT <= OLD_BOX_STAGING_3_PART_2
	assert sBattleTowerDataEnd <= sBoxStaging3Part2
	assert BANK(sBoxStaging3Part1) == BANK(sLinkBattleStats)
	assert BANK(sBattleTowerDataEnd) == BANK(sLinkBattleStats)
	assert BANK(sBoxStaging3Part2) == BANK(sLinkBattleStats)
