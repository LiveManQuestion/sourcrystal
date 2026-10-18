; version 02 -> 03: vanilla's map IDs and box layout for Pokemon Stadium 2.
;
; Pokemon Stadium 2 only lets you use a Game Pak in its Lab when the game was
; saved in a Pokemon Center, which it checks against its own list of vanilla
; Crystal map IDs. Removing unused maps had shifted the IDs of the Blackthorn
; and Route 10 Pokemon Centers, so placeholder maps (UNUSED_BLACKTHORN_MAP,
; UNUSED_CERULEAN_MAP_1 and _2) now fill those slots again. Every map ID the
; save holds after a placeholder moves up to match.
;
; Stadium also reads and changes the PC boxes, so they're back in vanilla's
; layout: 14 boxes instead of 16, with box names in wBoxNames. The old box
; format isn't converted, so the boxes are emptied.
;
; Version 03 was never released, so 04.asm runs these for version 02 saves
; before its own changes.

MigrateSaveFile03:
	ld hl, sGameData
	call MigrateMapIDs
	ld hl, sGameData
	call MigrateBoxData
	newfarjp InitializeSavedBoxes

MigrateBackupSaveFile03:
	ld hl, sBackupGameData
	call MigrateMapIDs
	ld hl, sBackupGameData
	call MigrateBoxData
	newfarjp InitializeSavedBoxes

MigrateBoxData:
; hl = the saved copy of wGameData, with its SRAM bank open
	push hl
	ld de, wCurBox - wGameData
	add hl, de
	xor a
	ld [hli], a
	; wPlayerCaught and wPlayerCaught2 were the last 2 bytes of wBoxNames.
	push hl
	ld de, wBoxNames + BOX_NAME_LENGTH * NUM_BOXES - 2 - wPlayerCaught
	add hl, de
	ld a, [hli]
	ld b, a
	ld c, [hl]
	pop hl
	ld a, b
	ld [hli], a
	ld [hl], c
	pop hl
	push hl
	ld de, wBoxNames - wGameData
	add hl, de
	newfarcall SetDefaultBoxNames
	pop hl
	ld de, wBoxThemes - wGameData
	add hl, de
	newfarjp SetDefaultBoxThemes

	assert wPlayerCaught == wCurBox + 1
	assert wPlayerCaught2 == wPlayerCaught + 1
	assert wBoxNames == wPlayerCaught2 + 1

MigrateMapIDs:
; hl = the saved copy of wGameData, with its SRAM bank open
	push hl
	ld de, .GroupFirst
.group_first_loop
	call .GetField
	jr c, .group_first_done
; bc = the field: map group, then map number
	ld a, [bc]
	inc bc
	call .Shift
	jr .group_first_loop

.group_first_done
	pop hl
	ld de, .NumberFirst
.number_first_loop
	call .GetField
	ret c
; bc = the field: map number, then map group
	inc bc
	ld a, [bc]
	dec bc
	call .Shift
	jr .number_first_loop

.GetField:
; Return carry at the end of the table at de.
; Otherwise, return bc = hl + the next offset in the table.
	ld a, [de]
	inc de
	ld c, a
	ld a, [de]
	inc de
	ld b, a
	and c
	inc a
	jr z, .table_end
	push hl
	add hl, bc
	ld b, h
	ld c, l
	pop hl
	and a
	ret

.table_end
	scf
	ret

.Shift:
; a = map group, bc = the map number to update
	cp GROUP_UNUSED_BLACKTHORN_MAP
	jr z, .blackthorn
	cp GROUP_UNUSED_CERULEAN_MAP_1
	ret nz
	ld a, [bc]
	cp MAP_UNUSED_CERULEAN_MAP_1
	ret c
	inc a
	cp MAP_UNUSED_CERULEAN_MAP_2
	jr c, .shifted
	inc a
	jr .shifted

.blackthorn
	ld a, [bc]
	cp MAP_UNUSED_BLACKTHORN_MAP
	ret c
	inc a
.shifted
	ld [bc], a
	ret

	assert sGameDataEnd - sGameData == wGameDataEnd - wGameData
	assert sBackupGameDataEnd - sBackupGameData == wGameDataEnd - wGameData
	assert GROUP_UNUSED_CERULEAN_MAP_2 == GROUP_UNUSED_CERULEAN_MAP_1
	assert MAP_UNUSED_CERULEAN_MAP_2 > MAP_UNUSED_CERULEAN_MAP_1

.GroupFirst:
	assert wMapNumber == wMapGroup + 1
	dw wMapGroup - wGameData
	assert wDigMapNumber == wDigMapGroup + 1
	dw wDigMapGroup - wGameData
	assert wBackupMapNumber == wBackupMapGroup + 1
	dw wBackupMapGroup - wGameData
	assert wLastSpawnMapNumber == wLastSpawnMapGroup + 1
	dw wLastSpawnMapGroup - wGameData
	assert wYanmaMapNumber == wYanmaMapGroup + 1
	dw wYanmaMapGroup - wGameData
	assert wSwarmMapNumber == wSwarmMapGroup + 1
	dw wSwarmMapGroup - wGameData
	assert wRoamMon1MapNumber == wRoamMon1MapGroup + 1
	dw wRoamMon1MapGroup - wGameData
	assert wRoamMon2MapNumber == wRoamMon2MapGroup + 1
	dw wRoamMon2MapGroup - wGameData
	assert wRoamMon3MapNumber == wRoamMon3MapGroup + 1
	dw wRoamMon3MapGroup - wGameData
	; Random weather: rain and sun maps for Johto and Kanto
	assert wWeatherRandomSunKanto == wWeatherRandomMapJohto + NUM_WEATHER_MAPS_PER_DAY * 2 * 3
for n, NUM_WEATHER_MAPS_PER_DAY * 4
	dw wWeatherRandomMapJohto + n * 2 - wGameData
endr
	dw -1

.NumberFirst:
	assert wRoamMons_CurMapGroup == wRoamMons_CurMapNumber + 1
	dw wRoamMons_CurMapNumber - wGameData
	assert wRoamMons_LastMapGroup == wRoamMons_LastMapNumber + 1
	dw wRoamMons_LastMapNumber - wGameData
	dw -1
