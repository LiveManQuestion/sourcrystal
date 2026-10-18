; version 01 -> 02: convert wPhoneList into bitflags.
; (Kept for reference: save_compat.asm no longer includes it.)

; wPhoneList used to be a list of contact IDs (phone_contacts.asm), holding
; at most CONTACT_LIST_SIZE (10). Making the list longer would have moved
; everything after it in the save, which led to this save migration system.

; Instead, wPhoneList became a bit flag array with a bit for every contact,
; like the Pokedex, so the phone can hold all of them. The phone no longer
; lists contacts in the order they were added.

MigrateSaveFile:
	ld hl, sPlayerData + (wPhoneList - wPlayerData)
; WRAM isn't loaded yet, so wPhoneList can hold a copy of the old contact
; list meanwhile.
	ld de, wPhoneList
	ld c, 0
.continue_memmove
	ld a, [hl]
	ld [hl], 0
	inc hl
	ld [de], a
	inc de
	inc c
	ld a, c
	cp 10 + 1 ; CONTACT_LIST_SIZE + 1
	jr nz, .continue_memmove

; Now let's iterate over the thing we moved to generate the new bitflag array.
	ld hl, wPhoneList
	ld d, 0
	ld b, SET_FLAG
.continue_convert
	ld a, [hl]
; Skip entry if it's invalid PHONE_00.
	and a
	jr z, .skip_this
; Bit flag array has the first contact that's not PHONE_00 start at 0, so adjust.
	dec a
	ld e, a
; c contains the upper limit, we now count down instead.
	push bc
	push hl
		ld hl, sPlayerData + (wPhoneList - wPlayerData)
		call FlagAction
	pop hl
	pop bc
.skip_this
	inc hl
	dec c
	jr nz, .continue_convert

; **HOTFIX**
; The saved random weather maps changed format between 6.2 and 7.0, and the
; migration missed it, so it could rain indoors until the next day.
; old format: group1, group2, mapId1, mapId2
; new format: group1, mapId1, group2, mapId2
; Swapping the middle two bytes fixes it.
	ld hl, sPlayerData + (wWeatherRandomMapJohto+1 - wPlayerData)
	call .do_swap
	ld hl, sPlayerData + (wWeatherRandomMapKanto+1 - wPlayerData)
	call .do_swap

; Finish migration
	jp ApplySaveVersion

.do_swap
	ld a, [hli]
	ld b, a
	ld a, [hl]
	dec hl
	ld [hli], a
	ld [hl], b
	ret

MigrateBackupSaveFile:
; Same as MigrateSaveFile, for the backup save.
	ld hl, sBackupPlayerData + (wPhoneList - wPlayerData)
	ld de, wPhoneList
	ld c, 0
.continue_memmove
	ld a, [hl]
	ld [hl], 0
	inc hl
	ld [de], a
	inc de
	inc c
	ld a, c
	cp 10 + 1 ; CONTACT_LIST_SIZE + 1
	jr nz, .continue_memmove
	ld hl, wPhoneList
	ld d, 0
	ld b, SET_FLAG
.continue_convert
	ld a, [hl]
	and a
	jr z, .skip_this
	dec a
	ld e, a
	push bc
	push hl
		ld hl, sBackupPlayerData + (wPhoneList - wPlayerData)
		call FlagAction
	pop hl
	pop bc
.skip_this
	inc hl
	dec c
	jr nz, .continue_convert
	ld hl, sBackupPlayerData + (wWeatherRandomMapJohto+1 - wPlayerData)
	call MigrateSaveFile.do_swap
	ld hl, sBackupPlayerData + (wWeatherRandomMapKanto+1 - wPlayerData)
	call MigrateSaveFile.do_swap
	jp ApplyBackupSaveVersion
