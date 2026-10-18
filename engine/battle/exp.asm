; Experience gain and the exp bar (single-player only), moved out of the full
; Battle Core bank. Battle Core functions are reached with newfarcall.

ApplyExperienceAfterEnemyCaught:
	newfarcall IsAnyMonHoldingExpShare
	ld a, d
	ld [wGivingExperienceToExpShareHolders], a
	; fallthrough
GiveExperiencePoints:
; Give experience.
; Don't give experience if linked or in the Battle Tower.
	ld a, [wLinkMode]
	and a
	ret nz

	ld a, [wInBattleTowerBattle]
	bit IN_BATTLE_TOWER_BATTLE_F, a
	ret nz

	xor a
	ld [wCurPartyMon], a

.loop
	ld a, MON_HP
	call GetPartyParamLocation
	ld a, [hli]
	or [hl]
	; Skip fainted Pokemon
	jp z, .next_mon

; Skip Pokemon that neither fought nor hold an Exp. Share.
	ld hl, wGivingExperienceToExpShareHolders
	call .CheckParticipation
	jr nz, .participating
	ld hl, wBattleParticipantsNotFainted
	call .CheckParticipation
	jp z, .next_mon

	xor a
	ldh [hMultiplicand], a
	ldh [hMultiplicand + 1], a

.participating
	; give stat exp
	ld a, MON_STAT_EXP + 1
	call GetPartyParamLocation
	ld d, h
	ld e, l
	ld hl, wEnemyMonBaseStats
	ld c, NUM_EXP_STATS
.stat_exp_loop
	ld a, [hli]
	ldh [hMultiplicand + 2], a
	push hl
	push de
	push bc
	call .GetExpDistribution
	ld a, MON_POKERUS
	call GetPartyParamLocation
	ld a, [hl]
	and a
	pop bc
	pop de
	pop hl
	call nz, .GiveStatExp
	call .GiveStatExp
	inc de
	inc de
	dec c
	jr nz, .stat_exp_loop

	xor a
	ldh [hMultiplicand + 0], a
	ldh [hMultiplicand + 1], a
	ld a, [wEnemyMonBaseExp]
	ldh [hMultiplicand + 2], a

	ld a, [wEnemyMonLevel]
	ldh [hMultiplier], a
	call Multiply
	ld a, 7
	ldh [hDivisor], a
	ld b, 4
	call Divide

	; Boost Experience for traded Pokemon
	ld a, MON_OT_ID
	call GetPartyParamLocation
	ld a, [wPlayerID]
	cp [hl]
	jr nz, .boosted
	inc hl
	ld a, [wPlayerID + 1]
	cp [hl]
	ld a, 0
	jr z, .no_boost

.boosted
	call .BoostExp
	ld a, 1

.no_boost
	; Boost experience for a Trainer Battle
	ld [wStringBuffer2 + 3], a
	ld a, [wBattleMode]
	dec a
	call nz, .BoostExp

	xor a
	call GetPartyParamLocation
	ld b, h
	ld c, l

	; Boost experience for Lucky Egg
	push bc
	ld a, MON_ITEM
	call GetPartyParamLocation
	ld a, [hl]
	cp LUCKY_EGG
	call z, .BoostExp

	; Scale exp
	push de
	call .GetExpDistribution

	; Make sure to give at least 1 exp.
	ld hl, hQuotient + 1
	push hl
	ld a, [hli]
	or [hl]
	inc hl
	or [hl]
	jr nz, .exp_ok
	inc [hl]

.exp_ok
	; Copy from hQuotient+1 -> wStringBuffer2
	pop hl
	ld de, wStringBuffer2
	push de
	push hl
	ld bc, 3
	push bc
	call CopyBytes

	ld a, [wCurPartyMon]
	ld hl, wPartyMonNicknames
	call GetNickname
	ld hl, Text_MonGainedExpPoint
	call BattleTextbox

	; Copy from wStringBuffer2 -> hQuotient+1
	pop bc
	pop de
	pop hl
	call CopyBytes
	pop de
	pop bc
	call AnimateExpBar
	push bc
	call LoadTilemapToTempTilemap
	pop bc
	ld hl, MON_EXP + 2
	add hl, bc
	ldh a, [hQuotient + 3]
	add [hl]
	ld [hld], a
	ldh a, [hQuotient + 2]
	adc [hl]
	ld [hld], a
	ldh a, [hQuotient + 1]
	adc [hl]
	ld [hl], a
	jr nc, .no_exp_overflow
	ld a, $ff
	ld [hli], a
	ld [hli], a
	ld [hl], a

.no_exp_overflow
	ld a, [wCurPartyMon]
	ld e, a
	ld d, 0
	ld hl, wPartySpecies
	add hl, de
	ld a, [hl]
	ld [wCurSpecies], a
	call GetBaseData
	push bc
	ld d, MAX_LEVEL
	callfar CalcExpAtLevel
	pop bc
	ld hl, MON_EXP + 2
	add hl, bc
	push bc
	ldh a, [hQuotient + 1]
	ld b, a
	ldh a, [hQuotient + 2]
	ld c, a
	ldh a, [hQuotient + 3]
	ld d, a
	ld a, [hld]
	sub d
	ld a, [hld]
	sbc c
	ld a, [hl]
	sbc b
	jr c, .not_max_exp
	ld a, b
	ld [hli], a
	ld a, c
	ld [hli], a
	ld a, d
	ld [hld], a

.not_max_exp
; Check if the mon leveled up
	xor a ; PARTYMON
	ld [wMonType], a
	predef CopyMonToTempMon
	callfar CalcLevel
	pop bc
	ld hl, MON_LEVEL
	add hl, bc
	ld a, [hl]
	cp MAX_LEVEL
	jp nc, .next_mon
	cp d
	jp z, .next_mon
; <NICKNAME> grew to level ##!
	ld [wTempLevel], a
	ld a, [wCurPartyLevel]
	push af
	ld a, d
	ld [wCurPartyLevel], a
	ld [hl], a
	ld hl, MON_SPECIES
	add hl, bc
	ld a, [hl]
	ld [wCurSpecies], a
	ld [wTempSpecies], a ; unused?
	call GetBaseData
	ld hl, MON_MAXHP + 1
	add hl, bc
	ld a, [hld]
	ld e, a
	ld d, [hl]
	push de
	ld hl, MON_MAXHP
	add hl, bc
	ld d, h
	ld e, l
	ld hl, MON_STAT_EXP - 1
	add hl, bc
	push bc
	ld b, TRUE
	predef CalcMonStats
	pop bc
	pop de
	ld hl, MON_MAXHP + 1
	add hl, bc
	ld a, [hld]
	sub e
	ld e, a
	ld a, [hl]
	sbc d
	ld d, a
	dec hl
	ld a, [hl]
	add e
	ld [hld], a
	ld a, [hl]
	adc d
	ld [hl], a
	ld a, [wCurBattleMon]
	ld d, a
	ld a, [wCurPartyMon]
	cp d
	jr nz, .skip_active_mon_update
	ld de, wBattleMonHP
	ld a, [hli]
	ld [de], a
	inc de
	ld a, [hli]
	ld [de], a
	ld de, wBattleMonMaxHP
	push bc
	ld bc, PARTYMON_STRUCT_LENGTH - MON_MAXHP
	call CopyBytes
	pop bc
	ld hl, MON_LEVEL
	add hl, bc
	ld a, [hl]
	ld [wBattleMonLevel], a
	ld a, [wPlayerSubStatus5]
	bit SUBSTATUS_TRANSFORMED, a
	jr nz, .transformed
	ld hl, MON_ATK
	add hl, bc
	ld de, wPlayerStats
	ld bc, PARTYMON_STRUCT_LENGTH - MON_ATK
	call CopyBytes

.transformed
	xor a ; FALSE
	ld [wApplyStatLevelMultipliersToEnemy], a
	newfarcall ApplyStatLevelMultiplierOnAllStats
	callfar ApplyStatusEffectOnPlayerStats
	callfar BadgeStatBoosts
	callfar UpdatePlayerHUD
	newfarcall EmptyBattleTextbox
	call LoadTilemapToTempTilemap
	ld a, $1
	ldh [hBGMapMode], a

.skip_active_mon_update
	farcall LevelUpHappinessMod
	ld a, [wCurBattleMon]
	ld b, a
	ld a, [wCurPartyMon]
	cp b
	jr z, .skip_exp_bar_animation
	ld de, SFX_HIT_END_OF_EXP_BAR
	call PlaySFX
	call WaitSFX
	ld hl, BattleText_StringBuffer1GrewToLevel
	call StdBattleTextbox
	call LoadTilemapToTempTilemap

.skip_exp_bar_animation
	xor a ; PARTYMON
	ld [wMonType], a
	predef CopyMonToTempMon
	hlcoord 9, 0
	ld b, 10
	ld c, 9
	call Textbox
	hlcoord 11, 1
	ld bc, 4
	predef PrintTempMonStats
	ld c, 30
	call DelayFrames
	call WaitPressAorB_BlinkCursor
	call SafeLoadTempTilemapToTilemap
	xor a ; PARTYMON
	ld [wMonType], a
	ld a, [wCurSpecies]
	ld [wTempSpecies], a ; unused?
	ld a, [wCurPartyLevel]
	push af
	ld c, a
	ld a, [wTempLevel]
	ld b, a

.level_loop
	inc b
	ld a, b
	ld [wCurPartyLevel], a
	push bc
	predef LearnLevelMoves
	pop bc
	ld a, b
	cp c
	jr nz, .level_loop
	pop af
	ld [wCurPartyLevel], a
	ld hl, wEvolvableFlags
	ld a, [wCurPartyMon]
	ld c, a
	ld b, SET_FLAG
	predef SmallFarFlagAction
	pop af
	ld [wCurPartyLevel], a

.next_mon
	ld a, [wPartyCount]
	ld b, a
	ld a, [wCurPartyMon]
	inc a
	cp b
	jr z, .done
	ld [wCurPartyMon], a
	jp .loop

.done
	newfarjp ResetBattleParticipants

.CheckParticipation:
	ld a, [wCurPartyMon]
	ld c, a
	ld b, CHECK_FLAG
	ld d, 0
	predef SmallFarFlagAction
	ld a, c
	and a
	ret

.GetExpDistribution:
; Split the exp between the p Pokemon that fought and the e Exp. Share
; holders. If either count is zero, each of the others gets 1/p (or 1/e).
; Otherwise fighting earns 1/(2p) and holding an Exp. Share 1/(2e), and a
; Pokemon that did both gets both: exp * (P + E) / (2ep), where P is e if
; it fought (or 0) and E is p if it holds an Exp. Share (or 0).
	ld a, [wGivingExperienceToExpShareHolders]
	ld d, a
	ld a, [wBattleParticipantsNotFainted]
	ld e, a
	and a
	ld a, d
	jr z, .single_factor
	and a
	ld a, e
	jr z, .single_factor

	; We are dealing with both participants and exp share holders.
	; First, verify that we are a participant.
	push de
	ld b, 0
	ld hl, wGivingExperienceToExpShareHolders
	push bc
	call .CheckParticipation
	pop bc
	pop de
	push af
	ld a, d
	newfarcall CountBits
	ld d, a
	pop af
	jr z, .done_exp_share_pe
	inc b

.done_exp_share_pe
	push de
	push bc
	ld hl, wBattleParticipantsNotFainted
	call .CheckParticipation
	pop bc
	pop de
	push af
	ld a, e
	newfarcall CountBits
	ld e, a
	pop af
	jr z, .done_participants_pe
	set 1, b

.done_participants_pe
	push de
	xor a
	bit 0, b
	jr z, .not_a_participant
	add e
.not_a_participant
	bit 1, b
	jr z, .not_a_holder
	add d
.not_a_holder
	ldh [hMultiplier], a
	call Multiply
	pop de
	ld a, d
	ld c, e
	call SimpleMultiply
	add a
	ldh [hDivisor], a
	ld b, 4
	jp Divide

.single_factor
	newfarcall CountBits
	ldh [hDivisor], a
	ld b, 4
	jp Divide

.GiveStatExp:
	ldh a, [hProduct + 3]
	ld b, a
	ld a, [de]
	add b
	ld [de], a
	ret nc
	dec de

	; Overflowing the lowest byte if stat exp is capped is fine, because
	; we still exceed 63504 (any stat experience beyond that is pointless).
	ld a, [de]
	inc a
	jr nz, .no_overflow
	dec a
.no_overflow
	ld [de], a
	inc de
	ret

.BoostExp:
; Multiply experience by 1.5.
	lb de, 3, 2
	; fallthrough
.ScaleMod:
	ld a, d
	ldh [hMultiplier], a
	call Multiply
	ld a, e
	ldh [hDivisor], a
	ld b, 4
	jmp Divide

.GetSqrt:
	push bc
	cp 225
	ld c, 15
	jr nc, .got_result
	ld b, a
	ld c, 0
.squareloop
	inc c
	ld a, c
	call SimpleMultiply
	cp b
	jr c, .squareloop
	jr z, .got_result
	dec c
.got_result
	ld a, c
	pop bc
	ret

Text_MonGainedExpPoint:
	text_far Text_Gained
	text_asm
	ld hl, ExpPointsText
	ld a, [wStringBuffer2 + 3] ; IsTradedMon
	and a
	ret z

	ld hl, BoostedExpPointsText
	ret

BoostedExpPointsText:
	text_far _BoostedExpPointsText
	text_end

ExpPointsText:
	text_far _ExpPointsText
	text_end

AnimateExpBar:
	push bc

	ld hl, wCurPartyMon
	ld a, [wCurBattleMon]
	cp [hl]
	jp nz, .finish

	ld a, [wBattleMonLevel]
	cp MAX_LEVEL
	jp nc, .finish

	ldh a, [hProduct + 3]
	ld [wExperienceGained + 2], a
	push af
	ldh a, [hProduct + 2]
	ld [wExperienceGained + 1], a
	push af
	ldh a, [hProduct + 1]
	ld [wExperienceGained], a
	push af
	xor a ; PARTYMON
	ld [wMonType], a
	predef CopyMonToTempMon
	ld a, [wTempMonLevel]
	ld b, a
	ld e, a
	push de
	ld de, wTempMonExp + 2
	call CalcExpBar
	push bc
	ld hl, wTempMonExp + 2
	ld a, [wExperienceGained + 2]
	add [hl]
	ld [hld], a
	ld a, [wExperienceGained + 1]
	adc [hl]
	ld [hld], a
	ld a, [wExperienceGained]
	adc [hl]
	ld [hl], a
	jr nc, .NoOverflow
	ld a, $ff
	ld [hli], a
	ld [hli], a
	ld [hl], a

.NoOverflow:
	ld d, MAX_LEVEL
	callfar CalcExpAtLevel
	ldh a, [hProduct + 1]
	ld b, a
	ldh a, [hProduct + 2]
	ld c, a
	ldh a, [hProduct + 3]
	ld d, a
	ld hl, wTempMonExp + 2
	ld a, [hld]
	sub d
	ld a, [hld]
	sbc c
	ld a, [hl]
	sbc b
	jr c, .AlreadyAtMaxExp
	ld a, b
	ld [hli], a
	ld a, c
	ld [hli], a
	ld a, d
	ld [hld], a

.AlreadyAtMaxExp:
	callfar CalcLevel
	ld a, d
	pop bc
	pop de
	ld d, a
	cp e
	jr nc, .LoopLevels
	ld a, e
	ld d, a

.LoopLevels:
	ld a, e
	cp MAX_LEVEL
	jr nc, .FinishExpBar
	cp d
	jr z, .FinishExpBar
	inc a
	ld [wTempMonLevel], a
	ld [wCurPartyLevel], a
	ld [wBattleMonLevel], a
	push de
	call .PlayExpBarSound
	ld c, $40
	call .LoopBarAnimation
	newfarcall PrintPlayerHUD
	ld hl, wBattleMonNickname
	ld de, wStringBuffer1
	ld bc, MON_NAME_LENGTH
	call CopyBytes
	call TerminateExpBarSound
	ld de, SFX_HIT_END_OF_EXP_BAR
	call PlaySFX
	farcall AnimateEndOfExpBar
	call WaitSFX
	ld hl, BattleText_StringBuffer1GrewToLevel
	call StdBattleTextbox
	pop de
	inc e
	ld b, $0
	jr .LoopLevels

.FinishExpBar:
	push bc
	ld b, d
	ld de, wTempMonExp + 2
	call CalcExpBar
	ld a, b
	pop bc
	ld c, a
	call .PlayExpBarSound
	call .LoopBarAnimation
	call TerminateExpBarSound
	pop af
	ldh [hProduct + 1], a
	pop af
	ldh [hProduct + 2], a
	pop af
	ldh [hProduct + 3], a

.finish
	pop bc
	ret

.PlayExpBarSound:
	push bc
	call WaitSFX
	ld de, SFX_EXP_BAR
	call PlaySFX
	ld c, 10
	call DelayFrames
	pop bc
	ret

.LoopBarAnimation:
	ld d, 3
	dec b
.anim_loop
	inc b
	push bc
	push de
	hlcoord 17, 11
	call PlaceExpBar
	pop de
	ld a, $1
	ldh [hBGMapMode], a
	ld c, d
	call DelayFrames
	xor a
	ldh [hBGMapMode], a
	pop bc
	ld a, c
	cp b
	jr z, .end_animation
	inc b
	push bc
	push de
	hlcoord 17, 11
	call PlaceExpBar
	pop de
	ld a, $1
	ldh [hBGMapMode], a
	ld c, d
	call DelayFrames
	xor a
	ldh [hBGMapMode], a
	dec d
	jr nz, .min_number_of_frames
	ld d, 1
.min_number_of_frames
	pop bc
	ld a, c
	cp b
	jr nz, .anim_loop
.end_animation
	ld a, $1
	ldh [hBGMapMode], a
	ret

FillInExpBar:
	push hl
	call CalcExpBar
	pop hl
	ld de, 7
	add hl, de
	jp PlaceExpBar

CalcExpBar:
; Calculate the percent exp between this level and the next
; Level in b
	push de
	ld d, b
	push de
	callfar CalcExpAtLevel
	pop de
; exp at current level gets pushed to the stack
	ld hl, hMultiplicand
	ld a, [hli]
	push af
	ld a, [hli]
	push af
	ld a, [hl]
	push af
; next level
	inc d
	callfar CalcExpAtLevel
; back up the next level exp, and subtract the two levels
	ld hl, hMultiplicand + 2
	ld a, [hl]
	ldh [hMathBuffer + 2], a
	pop bc
	sub b
	ld [hld], a
	ld a, [hl]
	ldh [hMathBuffer + 1], a
	pop bc
	sbc b
	ld [hld], a
	ld a, [hl]
	ldh [hMathBuffer], a
	pop bc
	sbc b
	ld [hl], a
	pop de

	ld hl, hMultiplicand + 1
	ld a, [hli]
	push af
	ld a, [hl]
	push af

; get the amount of exp remaining to the next level
	ld a, [de]
	dec de
	ld c, a
	ldh a, [hMathBuffer + 2]
	sub c
	ld [hld], a
	ld a, [de]
	dec de
	ld b, a
	ldh a, [hMathBuffer + 1]
	sbc b
	ld [hld], a
	ld a, [de]
	ld c, a
	ldh a, [hMathBuffer]
	sbc c
	ld [hld], a
	xor a
	ld [hl], a
	ld a, 64
	ldh [hMultiplier], a
	call Multiply
	pop af
	ld c, a
	pop af
	ld b, a
.loop
	ld a, b
	and a
	jr z, .done
	srl b
	rr c
	ld hl, hProduct
	srl [hl]
	inc hl
	rr [hl]
	inc hl
	rr [hl]
	inc hl
	rr [hl]
	jr .loop

.done
	ld a, c
	ldh [hDivisor], a
	ld b, 4
	call Divide
	ldh a, [hQuotient + 3]
	ld b, a
	ld a, $40
	sub b
	ld b, a
	ret

PlaceExpBar:
; Draw b pixels of exp bar (8 tiles of 8 pixels), from right to left at hl.
	ld c, $8
.loop1
	ld a, b
	sub $8
	jr c, .next
	ld b, a
	; full tile
	ld a, $6a
	ld [hld], a
	dec c
	ret z
	jr .loop1

.next
	add $8
	jr z, .loop2
	; partly full tile: $54 + pixels
	add $54
	jr .skip

.loop2
	; empty tile
	ld a, $62

.skip
	ld [hld], a
	ld a, $62
	dec c
	jr nz, .loop2
	ret
