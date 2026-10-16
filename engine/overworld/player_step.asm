_HandlePlayerStep::
	ld a, [wPlayerStepFlags]
	and a
	ret z
	bit PLAYERSTEP_START_F, a
	jr nz, .update_overworld_map
	bit PLAYERSTEP_STOP_F, a
	jr nz, .update_player_coords
	bit PLAYERSTEP_CONTINUE_F, a
	jr nz, .finish
	ret

.update_overworld_map
	ld a, 4
	ld [wHandlePlayerStep], a
	call UpdateOverworldMap
	jr .finish

.update_player_coords
	call UpdatePlayerCoords
	jr .finish

.finish
	call HandlePlayerStep
	ld a, [wPlayerStepVectorX]
	ld d, a
	ld a, [wPlayerStepVectorY]
	ld e, a
	ld a, [wPlayerBGMapOffsetX]
	sub d
	ld [wPlayerBGMapOffsetX], a
	ld a, [wPlayerBGMapOffsetY]
	sub e
	ld [wPlayerBGMapOffsetY], a
	ret

ScrollScreen::
	ld a, [wPlayerStepVectorX]
	ld d, a
	ld a, [wPlayerStepVectorY]
	ld e, a
	ldh a, [hSCX]
	add d
	ldh [hSCX], a
	ldh a, [hSCY]
	add e
	ldh [hSCY], a
	ret

HandlePlayerStep:
	ld hl, wHandlePlayerStep
	ld a, [hl]
	and a
	ret z
	dec [hl]
	ld a, [hl]
	ld hl, .Jumptable
	rst JumpTable
	ret

.Jumptable:
	dw GetMovementPermissions
	dw BufferScreen
	dw .mobile
	dw .fail2
; The rest are never used.  Ever.
	dw .fail1
	dw .fail1
	dw .fail1
	dw .fail1
	dw .fail1
	dw .fail1
	dw .fail1

.fail1
	ret

.mobile
	farcall StubbedTrainerRankings_StepCount
	ret

.fail2
	ret

UpdatePlayerCoords:
	ld a, [wPlayerStepDirection]
	and a
	jr nz, .check_step_down
	ld hl, wYCoord
	inc [hl]
	ret

.check_step_down
	cp UP
	jr nz, .check_step_left
	ld hl, wYCoord
	dec [hl]
	ret

.check_step_left
	cp LEFT
	jr nz, .check_step_right
	ld hl, wXCoord
	dec [hl]
	ret

.check_step_right
	cp RIGHT
	ret nz
	ld hl, wXCoord
	inc [hl]
	ret

UpdateOverworldMap:
	ld a, [wPlayerStepDirection]
	and a
	jr z, .step_down
	cp UP
	jr z, .step_up
	cp LEFT
	jr z, .step_left
	cp RIGHT
	jr z, .step_right
	ret

.step_down
	call .ScrollOverworldMapDown
	call LoadOverworldTilemap
	call ScrollMapDown
	ret

.step_up
	call .ScrollOverworldMapUp
	call LoadOverworldTilemap
	call ScrollMapUp
	ret

.step_left
	call .ScrollOverworldMapLeft
	call LoadOverworldTilemap
	call ScrollMapLeft
	ret

.step_right
	call .ScrollOverworldMapRight
	call LoadOverworldTilemap
	call ScrollMapRight
	ret

.ScrollOverworldMapDown:
	ld a, [wBGMapAnchor]
	add 2 * BG_MAP_WIDTH
	ld [wBGMapAnchor], a
	jr nc, .not_overflowed
	ld a, [wBGMapAnchor + 1]
	inc a
	and %11
	or HIGH(vBGMap0)
	ld [wBGMapAnchor + 1], a
.not_overflowed
	ld hl, wPlayerMetatileY
	inc [hl]
	ld a, [hl]
	cp 2 ; was 1
	jr nz, .done_down
	ld [hl], 0
	call .ScrollMapDataDown
.done_down
	ret

.ScrollMapDataDown:
	ld hl, wOverworldMapAnchor
	ld a, [wMapWidth]
	add 3 * 2 ; surrounding tiles
	add [hl]
	ld [hli], a
	ret nc
	inc [hl]
	ret

.ScrollOverworldMapUp:
	ld a, [wBGMapAnchor]
	sub 2 * BG_MAP_WIDTH
	ld [wBGMapAnchor], a
	jr nc, .not_underflowed
	ld a, [wBGMapAnchor + 1]
	dec a
	and %11
	or HIGH(vBGMap0)
	ld [wBGMapAnchor + 1], a
.not_underflowed
	ld hl, wPlayerMetatileY
	dec [hl]
	ld a, [hl]
	cp -1 ; was 0
	jr nz, .done_up
	ld [hl], $1
	call .ScrollMapDataUp
.done_up
	ret

.ScrollMapDataUp:
	ld hl, wOverworldMapAnchor
	ld a, [wMapWidth]
	add 3 * 2 ; surrounding tiles
	ld b, a
	ld a, [hl]
	sub b
	ld [hli], a
	ret nc
	dec [hl]
	ret

.ScrollOverworldMapLeft:
	ld a, [wBGMapAnchor]
	ld e, a
	and $e0
	ld d, a
	ld a, e
	sub $2
	and $1f
	or d
	ld [wBGMapAnchor], a
	ld hl, wPlayerMetatileX
	dec [hl]
	ld a, [hl]
	cp -1
	jr nz, .done_left
	ld [hl], 1
	call .ScrollMapDataLeft
.done_left
	ret

.ScrollMapDataLeft:
	ld hl, wOverworldMapAnchor
	ld a, [hl]
	sub 1
	ld [hli], a
	ret nc
	dec [hl]
	ret

.ScrollOverworldMapRight:
	ld a, [wBGMapAnchor]
	ld e, a
	and $e0
	ld d, a
	ld a, e
	add $2
	and $1f
	or d
	ld [wBGMapAnchor], a
	ld hl, wPlayerMetatileX
	inc [hl]
	ld a, [hl]
	cp 2
	jr nz, .done_right
	ld [hl], 0
	call .ScrollMapDataRight
.done_right
	ret

.ScrollMapDataRight:
	ld hl, wOverworldMapAnchor
	ld a, [hl]
	add 1
	ld [hli], a
	ret nc
	inc [hl]
	ret

ScrollMapUp:
	hlcoord 0, 0
	ld de, wBGMapBuffer
	call BackupBGMapRow
	ld c, 2 * SCREEN_WIDTH
	call ScrollBGMapPalettes
	ld a, [wBGMapAnchor]
	ld e, a
	ld a, [wBGMapAnchor + 1]
	ld d, a
	call UpdateBGMapRow
	ld a, $1
	ldh [hBGMapUpdate], a
	ret

ScrollMapDown:
	hlcoord 0, SCREEN_HEIGHT - 2
	ld de, wBGMapBuffer
	call BackupBGMapRow
	ld c, 2 * SCREEN_WIDTH
	call ScrollBGMapPalettes
	ld a, [wBGMapAnchor]
	ld l, a
	ld a, [wBGMapAnchor + 1]
	ld h, a
	ld bc, BG_MAP_WIDTH tiles
	add hl, bc
; cap d at HIGH(vBGMap0)
	ld a, h
	and %00000011
	or HIGH(vBGMap0)
	ld e, l
	ld d, a
	call UpdateBGMapRow
	ld a, $1
	ldh [hBGMapUpdate], a
	ret

ScrollMapLeft:
	hlcoord 0, 0
	ld de, wBGMapBuffer
	call BackupBGMapColumn
	ld c, 2 * SCREEN_HEIGHT
	call ScrollBGMapPalettes
	ld a, [wBGMapAnchor]
	ld e, a
	ld a, [wBGMapAnchor + 1]
	ld d, a
	call UpdateBGMapColumn
	ld a, $1
	ldh [hBGMapUpdate], a
	ret

ScrollMapRight:
	hlcoord SCREEN_WIDTH - 2, 0
	ld de, wBGMapBuffer
	call BackupBGMapColumn
	ld c, 2 * SCREEN_HEIGHT
	call ScrollBGMapPalettes
	ld a, [wBGMapAnchor]
	ld e, a
	and %11100000
	ld b, a
	ld a, e
	add SCREEN_HEIGHT
	and %00011111
	or b
	ld e, a
	ld a, [wBGMapAnchor + 1]
	ld d, a
	call UpdateBGMapColumn
	ld a, $1
	ldh [hBGMapUpdate], a
	ret

BackupBGMapRow:
	ld c, 2 * SCREEN_WIDTH
.loop
	ld a, [hli]
	ld [de], a
	inc de
	dec c
	jr nz, .loop
	ret

BackupBGMapColumn:
	ld c, SCREEN_HEIGHT
.loop
	ld a, [hli]
	ld [de], a
	inc de
	ld a, [hl]
	ld [de], a
	inc de
	ld a, SCREEN_WIDTH - 1
	add l
	ld l, a
	jr nc, .skip
	inc h

.skip
	dec c
	jr nz, .loop
	ret

UpdateBGMapRow:
	ld hl, wBGMapBufferPointers
	push de
	call .iteration
	pop de
	ld a, BG_MAP_WIDTH
	add e
	ld e, a

.iteration
	ld c, 10
.loop
	ld a, e
	ld [hli], a
	ld a, d
	ld [hli], a
	ld a, e
	inc a
	inc a
	and $1f
	ld b, a
	ld a, e
	and $e0
	or b
	ld e, a
	dec c
	jr nz, .loop
	ld a, SCREEN_WIDTH
	ldh [hBGMapTileCount], a
	ret

UpdateBGMapColumn:
	ld hl, wBGMapBufferPointers
	ld c, SCREEN_HEIGHT
.loop
	ld a, e
	ld [hli], a
	ld a, d
	ld [hli], a
	ld a, BG_MAP_WIDTH
	add e
	ld e, a
	jr nc, .skip
	inc d
; cap d at HIGH(vBGMap0)
	ld a, d
	and %11
	or HIGH(vBGMap0)
	ld d, a

.skip
	dec c
	jr nz, .loop
	ld a, SCREEN_HEIGHT
	ldh [hBGMapTileCount], a
	ret
