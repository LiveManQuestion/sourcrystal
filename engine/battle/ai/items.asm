AI_SwitchOrTryItem:
	and a

	ld a, [wBattleMode]
	dec a
	ret z

	ld a, [wLinkMode]
	and a
	ret nz

	farcall CheckEnemyLockedIn
	ret nz

	ld a, [wPlayerSubStatus5]
	bit SUBSTATUS_CANT_RUN, a
	jr nz, DontSwitch

	ld a, [wEnemyWrapCount]
	and a
	jr nz, DontSwitch

	; always load the first trainer class in wTrainerClass for Battle Tower trainers
	ld hl, TrainerClassAttributes + TRNATTR_AI_ITEM_SWITCH
	ld a, [wInBattleTowerBattle]
	and a
	jr nz, .ok

	ld a, [wTrainerClass]
	dec a
	ld bc, NUM_TRAINER_ATTRIBUTES
	call AddNTimes

.ok
	bit SWITCH_SMOGON_F, [hl]
	jr z, .not_smogon
; Smogon switching is only for Challenge Mode; otherwise switch sometimes.
	ld a, [wChallengeMode]
	bit GAME_CHALLENGE_MODE_F, a
	jp nz, SwitchSmogon
	jp SwitchSometimes

.not_smogon
	bit SWITCH_OFTEN_F, [hl]
	jr nz, SwitchOften
	bit SWITCH_RARELY_F, [hl]
	jr nz, SwitchRarely
	bit SWITCH_SOMETIMES_F, [hl]
	jr nz, SwitchSometimes
	; fallthrough

DontSwitch:
	call AI_TryItem
	ret

SwitchOften:
	call CheckAbleToSwitch
	ld a, [wEnemySwitchMonParam]
	and $f0
	jr z, DontSwitch

	cp $10
	jr nz, .not_10
	call Random
	cp 50 percent + 1
	jr c, .switch
	jr DontSwitch
.not_10

	cp $20
	jr nz, .not_20
	call Random
	cp 79 percent - 1
	jr c, .switch
	jr DontSwitch
.not_20

	; $30
	call Random
	cp 4 percent
	jr c, DontSwitch

.switch
	ld a, [wEnemySwitchMonParam]
	and $f
	inc a
	; In register 'a' is the number (1-6) of the mon to switch to
	ld [wEnemySwitchMonIndex], a
	jp AI_TrySwitch

SwitchRarely:
	call CheckAbleToSwitch
	ld a, [wEnemySwitchMonParam]
	and $f0
	jr z, DontSwitch

	cp $10
	jr nz, .not_10
	call Random
	cp 8 percent
	jr c, .switch
	jr DontSwitch
.not_10

	cp $20
	jr nz, .not_20
	call Random
	cp 12 percent
	jr c, .switch
	jr DontSwitch
.not_20

	; $30
	call Random
	cp 79 percent - 1
	jr c, DontSwitch

.switch
	ld a, [wEnemySwitchMonParam]
	and $f
	inc a
	ld [wEnemySwitchMonIndex], a
	jp AI_TrySwitch

SwitchSometimes:
	call CheckAbleToSwitch
	ld a, [wEnemySwitchMonParam]
	and $f0
	jp z, DontSwitch

	cp $10
	jr nz, .not_10
	call Random
	cp 20 percent - 1
	jr c, .switch
	jp DontSwitch
.not_10

	cp $20
	jr nz, .not_20
	call Random
	cp 50 percent + 1
	jr c, .switch
	jp DontSwitch
.not_20

	; $30
	call Random
	cp 20 percent - 1
	jp c, DontSwitch

.switch
	ld a, [wEnemySwitchMonParam]
	and $f
	inc a
	ld [wEnemySwitchMonIndex], a
	jp AI_TrySwitch

SwitchSmogon:
; Switch like a GSC OU player: compare the active Pokemon's matchup against
; the player's Pokemon with the best matchup a healthy teammate would have
; (see engine/battle/ai/smogon_switch.asm), and only switch when the gain is
; worth the hit the switch-in takes. Matchups come from what the player's
; Pokemon visibly is and does, so this works against any team.
	farcall FindAliveEnemyMons
	jp c, DontSwitch

; With a Perish count of 1, escape no matter what.
	ld a, [wEnemySubStatus1]
	bit SUBSTATUS_PERISH, a
	jr z, .no_perish
	ld a, [wEnemyPerishCount]
	cp 1
	jr nz, .no_perish
	call AISmogon_FindBestSwitchIn
	jp c, DontSwitch
	jp .switch
.no_perish

; Reasons to stay in:
; Knocking the player out first beats any switch.
	call AISmogon_PickedMoveKOsFirst
	jp c, DontSwitch
; So does putting it to sleep or laying Spikes before it can hit back.
	call AISmogon_PickedLeadMoveFirst
	jp c, DontSwitch
; Switching out throws away stat boosts that help and a Substitute.
	call AISmogon_EnemyHasUsefulBoosts
	jp c, DontSwitch
	ld a, [wEnemySubStatus4]
	bit SUBSTATUS_SUBSTITUTE, a
	jp nz, DontSwitch

; A Pokemon in KO range is worth more as a sacrifice: staying in gives
; a healthy teammate a free switch-in when it faints.
	call AICheckEnemyQuarterHP
	jp nc, DontSwitch

; A Ghost or Psychic fleeing a Pursuit user takes double damage.
	call AISmogon_PlayerHasPursuit
	jr nc, .no_pursuit
	ld a, [wEnemyMonType1]
	call AISmogon_GhostOrPsychic
	jp z, DontSwitch
	ld a, [wEnemyMonType2]
	call AISmogon_GhostOrPsychic
	jp z, DontSwitch
.no_pursuit

; A Rest user below half HP should Rest instead of switching.
	ld a, [wEnemyMonStatus]
	and SLP_MASK
	jr nz, .no_rest
	call AICheckEnemyHalfHP
	jr c, .no_rest
	ld hl, .RestMove
	call AIHasMoveInArray
	jp c, DontSwitch
.no_rest

	call AISmogon_ScoreActive
	call AISmogon_PenalizeAsleepActive

; So should one below half HP about to use a recovery move that heals more
; than the player's strongest attack takes off (Whitney's Miltank switched
; out instead of using Milk Drink against Snorlax and Steelix).
	call AISmogon_PickedHealOutpaces
	jp c, DontSwitch

; A Pokemon that can phaze, Haze or Explode deals with a boosted player
; itself, unless neither side can KO the other: then it would just Haze
; forever (Crobat against a Curse Steelix).
	ld a, [wCurOTMon]
	ld [wSmogonAIMon], a
	call AISmogon_CanStopSetup
	jr nc, .find_switch_in
	ld a, [wSmogonAIActiveStalled]
	and a
	jp z, DontSwitch
.find_switch_in
	call AISmogon_FindBestSwitchIn
	jp c, DontSwitch

; Reasons to switch out even without a bad matchup:
; Switching turns Toxic back into regular poison.
	ld a, [wEnemySubStatus5]
	bit SUBSTATUS_TOXIC, a
	jr z, .not_toxic
	ld a, [wEnemyToxicCount]
	cp 3
	jr nc, .escape
.not_toxic

; Switching removes Leech Seed, a Ghost's Curse and Encore.
	ld a, [wEnemySubStatus4]
	bit SUBSTATUS_LEECH_SEED, a
	jr nz, .escape
	ld a, [wEnemySubStatus1]
	bit SUBSTATUS_CURSE, a
	jr nz, .escape
	call AISmogon_EncoredIntoStatusMove
	jr c, .escape

; A Pokemon with no useful move left (every move scored worse than neutral),
; like a Smeargle that has used Spore and Spikes, makes room for a teammate.
	ld a, [wEnemyAIMovesSpent]
	and a
	jr nz, .spent

; Neither side can KO the other (Crobat against a Steelix it can't wear
; down through Leftovers): any better matchup is progress.
	ld a, [wSmogonAIActiveStalled]
	and a
	jr nz, .spent

; Let a Sleep Talk user take the player's sleep move instead of losing the
; active Pokemon to sleep.
	call AISmogon_ShouldAbsorbSleep
	jr nc, .matchup

.spent
; ...but only for a better matchup, or two spent Pokemon swap back and forth.
	ld a, [wEnemyAISwitchScore]
	ld b, a
	ld a, [wSmogonAIBestScore]
	cp b
	jr z, .stay
	jr nc, .switch
.stay
	jp DontSwitch

.escape
; Escape unless the best switch-in matches up much worse.
	ld a, [wEnemyAISwitchScore]
	sub SMOGON_ESCAPE_TOLERANCE
	jr c, .switch
	ld b, a
	ld a, [wSmogonAIBestScore]
	cp b
	jr nc, .switch
	jp DontSwitch

.matchup
; Only switch for a clearly better matchup (the switch-in's score already
; counts the hit and Spikes it takes coming in), and not right after coming
; in, which just goes back and forth.
	ld c, SMOGON_SWITCH_MARGIN
	ld a, [wEnemyTurnsTaken]
	and a
	jr nz, .settled_in
	ld a, c
	add SMOGON_JUST_IN_MARGIN
	ld c, a
.settled_in
	ld a, [wEnemyAISwitchScore]
	add c
	jp c, DontSwitch
	ld c, a
	ld a, [wSmogonAIBestScore]
	sub c
	jp c, DontSwitch

; A small improvement isn't always worth it.
	cp SMOGON_SURE_SWITCH
	jr nc, .switch
	call Random
	cp 70 percent
	jp nc, DontSwitch

.switch
	ld a, [wSmogonAIBestMon]
	inc a
	; In register 'a' is the number (1-6) of the mon to switch to
	ld [wEnemySwitchMonIndex], a
	jp AI_TrySwitch

.RestMove:
	db REST
	db -1 ; end

AISmogon_PickedHealOutpaces:
; Return carry if the enemy is below half HP, the move it picked
; (wCurEnemyMove: AISmogon_ScoreActive reuses wEnemyMoveStruct) heals half
; its max HP, and the player's strongest attack (AISmogon_ScoreActive's
; estimate) does less than that.
	call AICheckEnemyHalfHP
	jr c, .no
	ld a, [wCurEnemyMove]
	ld hl, .HalfHealMoves
	ld de, 1
	call IsInArray
	jr nc, .no
; carry if the strongest attack < max HP / 2
	ld a, [wEnemyMonMaxHP]
	ld d, a
	ld a, [wEnemyMonMaxHP + 1]
	ld e, a
	srl d
	rr e
	ld a, [wSmogonAIThreat + ATTACKS_BEST + 1]
	sub e
	ld a, [wSmogonAIThreat + ATTACKS_BEST]
	sbc d
	ret

.no
	and a
	ret

.HalfHealMoves:
	db RECOVER
	db SOFTBOILED
	db MILK_DRINK
	db -1 ; end

AI_TryItem:
	; items are not allowed in the Battle Tower
	ld a, [wInBattleTowerBattle]
	and a
	ret nz

	ld a, [wEnemyTrainerItem1]
	ld b, a
	ld a, [wEnemyTrainerItem2]
	or b
	ret z

	ld a, [wOTPartyCount]
	cp 2
	jr c, .only_one_mon

	ld d, a
	ld e, 0
	ld b, 1 << (PARTY_LENGTH - 1)
	ld c, 0
	ld hl, wOTPartyMon1HP

.loop_alive
	ld a, [wCurOTMon]
	cp e
	jr z, .next_alive

	push bc
	ld b, [hl]
	inc hl
	ld a, [hld]
	or b
	pop bc
	jr z, .next_alive

	ld a, c
	or b
	ld c, a

.next_alive
	srl b
	push bc
	ld bc, PARTYMON_STRUCT_LENGTH
	add hl, bc
	pop bc
	inc e
	dec d
	jr nz, .loop_alive

	ld a, c
	and a
	jr z, .only_one_mon

	call .IsHighestLevel
	ret nc

.only_one_mon
	ld a, [wTrainerClass]
	dec a
	ld hl, TrainerClassAttributes + TRNATTR_AI_ITEM_SWITCH
	ld bc, NUM_TRAINER_ATTRIBUTES
	call AddNTimes
	ld b, h
	ld c, l
	ld hl, AI_Items
.loop
	ld de, wEnemyTrainerItem1
	ld a, [hl]
	and a
	inc a
	ret z

	ld a, [de]
	cp [hl]
	jr z, .has_item
	inc de
	ld a, [de]
	cp [hl]
	jr z, .has_item

	dec de
	inc hl
	inc hl
	inc hl
	jr .loop

.has_item
	inc hl

	push hl
	push de
	ld de, .callback
	push de
	ld a, [hli]
	ld h, [hl]
	ld l, a
	jp hl
.callback
	pop de
	pop hl

	inc hl
	inc hl
	jr c, .loop

; used item
	xor a
	ld [de], a
	inc a
	ld [wEnemyGoesFirst], a

	ld hl, wEnemySubStatus3
	res SUBSTATUS_BIDE, [hl]

	xor a
	ld [wEnemyFuryCutterCount], a
	ld [wEnemyProtectCount], a
	ld [wEnemyRageCounter], a

	ld hl, wEnemySubStatus4
	res SUBSTATUS_RAGE, [hl]

	xor a
	ld [wLastEnemyCounterMove], a

	scf
	ret

.IsHighestLevel:
	ld a, [wEnemySubStatus1]
	bit SUBSTATUS_PERISH, a
	jr nz, .no

	ld a, [wOTPartyCount]
	ld d, a
	ld e, 0
	ld hl, wOTPartyMon1Level
	ld bc, PARTYMON_STRUCT_LENGTH
.next
	ld a, [hl]
	cp e
	jr c, .ok
	ld e, a
.ok
	add hl, bc
	dec d
	jr nz, .next

	ld a, [wCurOTMon]
	ld hl, wOTPartyMon1Level
	call AddNTimes
	ld a, [hl]
	cp e
	jr nc, .yes

.no
	and a
	ret

.yes
	scf
	ret

AI_Items:
	dbw FULL_RESTORE, .FullRestore
	dbw MAX_POTION,   .MaxPotion
	dbw HYPER_POTION, .HyperPotion
	dbw SUPER_POTION, .SuperPotion
	dbw POTION,       .Potion
	dbw X_ACCURACY,   .XAccuracy
	dbw FULL_HEAL,    .FullHeal
	dbw GUARD_SPEC,   .GuardSpec
	dbw DIRE_HIT,     .DireHit
	dbw X_ATTACK,     .XAttack
	dbw X_DEFEND,     .XDefend
	dbw X_SPEED,      .XSpeed
	dbw X_SPECIAL,    .XSpecial
	db -1 ; end

.FullHeal:
	call .Status
	jp c, .DontUse
	call EnemyUsedFullHeal
	jp .Use

.Status:
	ld a, [wEnemyMonStatus]
	and a
	jp z, .DontUse

	ld a, [bc]
	bit CONTEXT_USE_F, a
	jr nz, .StatusCheckContext
	ld a, [bc]
	bit ALWAYS_USE_F, a
	jp nz, .Use
	call Random
	cp 20 percent - 1
	jp c, .Use
	jp .DontUse

.StatusCheckContext:
	ld a, [wEnemySubStatus5]
	bit SUBSTATUS_TOXIC, a
	jr z, .FailToxicCheck
	ld a, [wEnemyToxicCount]
	cp 4
	jr c, .FailToxicCheck
	call Random
	cp 50 percent + 1
	jp c, .Use
.FailToxicCheck:
	ld a, [wEnemyMonStatus]
	and 1 << FRZ | SLP_MASK
	jp z, .DontUse
	jp .Use

.FullRestore:
	call .HealItem
	jr nc, .UseFullRestore
	ld a, [bc]
	bit CONTEXT_USE_F, a
	jp z, .DontUse
	call .Status
	jp c, .DontUse

.UseFullRestore:
	call EnemyUsedFullRestore
	jp .Use

.MaxPotion:
	call .HealItem
	jp c, .DontUse
	call EnemyUsedMaxPotion
	jp .Use

.HealItem:
	ld a, [bc]
	bit CONTEXT_USE_F, a
	jr nz, .CheckHalfOrQuarterHP
	callfar AICheckEnemyHalfHP
	jp c, .DontUse
	ld a, [bc]
	bit UNKNOWN_USE_F, a
	jr nz, .CheckQuarterHP
	callfar AICheckEnemyQuarterHP
	jr nc, .UseHealItem
	call Random
	cp 50 percent + 1
	jr c, .UseHealItem
	jp .DontUse

.CheckQuarterHP:
	callfar AICheckEnemyQuarterHP
	jp c, .DontUse
	call Random
	cp 20 percent - 1
	jp c, .DontUse
	jr .UseHealItem

.CheckHalfOrQuarterHP:
	callfar AICheckEnemyHalfHP
	jp c, .DontUse
	callfar AICheckEnemyQuarterHP
	jr nc, .UseHealItem
	call Random
	cp 20 percent - 1
	jp nc, .DontUse

.UseHealItem:
	jp .Use

.HyperPotion:
	call .HealItem
	jp c, .DontUse
	ld b, 200
	call EnemyUsedHyperPotion
	jp .Use

.SuperPotion:
	call .HealItem
	jp c, .DontUse
	ld b, 50
	call EnemyUsedSuperPotion
	jp .Use

.Potion:
	call .HealItem
	jp c, .DontUse
	ld b, 20
	call EnemyUsedPotion
	jp .Use

; Everything up to "End unused" is unused

.UnusedHealItem: ; unreferenced
; This has similar conditions to .HealItem
	callfar AICheckEnemyMaxHP
	jr c, .dont_use
	push bc
	ld de, wEnemyMonMaxHP + 1
	ld hl, wEnemyMonHP + 1
	ld a, [de]
	sub [hl]
	jr z, .check_40_percent
	dec hl
	dec de
	ld c, a
	sbc [hl]
	and a
	jr nz, .check_40_percent
	ld a, c
	cp b
	jr c, .check_50_percent
	callfar AICheckEnemyQuarterHP
	jr c, .check_40_percent

.check_50_percent
	pop bc
	ld a, [bc]
	bit UNKNOWN_USE_F, a
	jp z, .Use
	call Random
	cp 50 percent + 1
	jp c, .Use

.dont_use
	jp .DontUse

.check_40_percent
	pop bc
	ld a, [bc]
	bit UNKNOWN_USE_F, a
	jr z, .DontUse
	call Random
	cp 39 percent + 1
	jr c, .Use
	jr .DontUse

; End unused

.XAccuracy:
	call .XItem
	jr c, .DontUse
	call EnemyUsedXAccuracy
	jr .Use

.GuardSpec:
	call .XItem
	jr c, .DontUse
	call EnemyUsedGuardSpec
	jr .Use

.DireHit:
	call .XItem
	jr c, .DontUse
	call EnemyUsedDireHit
	jr .Use

.XAttack:
	call .XItem
	jr c, .DontUse
	call EnemyUsedXAttack
	jr .Use

.XDefend:
	call .XItem
	jr c, .DontUse
	call EnemyUsedXDefend
	jr .Use

.XSpeed:
	call .XItem
	jr c, .DontUse
	call EnemyUsedXSpeed
	jr .Use

.XSpecial:
	call .XItem
	jr c, .DontUse
	call EnemyUsedXSpecial
	jr .Use

.XItem:
	ld a, [wEnemyTurnsTaken]
	and a
	jr nz, .notfirstturnout
	ld a, [bc]
	bit ALWAYS_USE_F, a
	jr nz, .Use
	call Random
	cp 50 percent + 1
	jr c, .DontUse
	ld a, [bc]
	bit CONTEXT_USE_F, a
	jr nz, .Use
	call Random
	cp 50 percent + 1
	jr c, .DontUse
	jr .Use
.notfirstturnout
	ld a, [bc]
	bit ALWAYS_USE_F, a
	jr z, .DontUse
	call Random
	cp 20 percent - 1
	jr nc, .DontUse
	jr .Use

.DontUse:
	scf
	ret

.Use:
	and a
	ret

AIUpdateHUD:
	call UpdateEnemyMonInParty
	farcall UpdateEnemyHUD
	ld a, $1
	ldh [hBGMapMode], a
	ld hl, wEnemyItemState
	dec [hl]
	scf
	ret

AIUsedItemSound:
	push de
	ld de, SFX_FULL_HEAL
	call PlaySFX
	pop de
	ret

EnemyUsedFullHeal:
	call AIUsedItemSound
	call AI_HealStatus
	ld a, FULL_HEAL
	jp PrintText_UsedItemOn_AND_AIUpdateHUD

EnemyUsedMaxPotion:
	ld a, MAX_POTION
	ld [wCurEnemyItem], a
	jr FullRestoreContinue

EnemyUsedFullRestore:
	call AI_HealStatus
	ld a, FULL_RESTORE
	ld [wCurEnemyItem], a
	; fallthrough

FullRestoreContinue:
	ld de, wCurHPAnimOldHP
	ld hl, wEnemyMonHP + 1
	ld a, [hld]
	ld [de], a
	inc de
	ld a, [hl]
	ld [de], a
	inc de
	ld hl, wEnemyMonMaxHP + 1
	ld a, [hld]
	ld [de], a
	inc de
	ld [wCurHPAnimMaxHP], a
	ld [wEnemyMonHP + 1], a
	ld a, [hl]
	ld [de], a
	ld [wCurHPAnimMaxHP + 1], a
	ld [wEnemyMonHP], a
	jr EnemyPotionFinish

EnemyUsedPotion:
	ld a, POTION
	ld b, 20
	jr EnemyPotionContinue

EnemyUsedSuperPotion:
	ld a, SUPER_POTION
	ld b, 50
	jr EnemyPotionContinue

EnemyUsedHyperPotion:
	ld a, HYPER_POTION
	ld b, 200

EnemyPotionContinue:
	ld [wCurEnemyItem], a
	ld hl, wEnemyMonHP + 1
	ld a, [hl]
	ld [wCurHPAnimOldHP], a
	add b
	ld [hld], a
	ld [wCurHPAnimNewHP], a
	ld a, [hl]
	ld [wCurHPAnimOldHP + 1], a
	ld [wCurHPAnimNewHP + 1], a
	jr nc, .ok
	inc a
	ld [hl], a
	ld [wCurHPAnimNewHP + 1], a
.ok
	inc hl
	ld a, [hld]
	ld b, a
	ld de, wEnemyMonMaxHP + 1
	ld a, [de]
	dec de
	ld [wCurHPAnimMaxHP], a
	sub b
	ld a, [hli]
	ld b, a
	ld a, [de]
	ld [wCurHPAnimMaxHP + 1], a
	sbc b
	jr nc, EnemyPotionFinish
	inc de
	ld a, [de]
	dec de
	ld [hld], a
	ld [wCurHPAnimNewHP], a
	ld a, [de]
	ld [hl], a
	ld [wCurHPAnimNewHP + 1], a

EnemyPotionFinish:
	call PrintText_UsedItemOn
	hlcoord 2, 2
	xor a
	ld [wWhichHPBar], a
	call AIUsedItemSound
	predef AnimateHPBar
	jp AIUpdateHUD

AI_TrySwitch:
; Determine whether the AI can switch based on how many Pokemon are still alive.
; If it can switch, it will.
	ld a, [wOTPartyCount]
	ld c, a
	ld hl, wOTPartyMon1HP
	ld d, 0
.SwitchLoop:
	ld a, [hli]
	ld b, a
	ld a, [hld]
	or b
	jr z, .fainted
	inc d
.fainted
	push bc
	ld bc, PARTYMON_STRUCT_LENGTH
	add hl, bc
	pop bc
	dec c
	jr nz, .SwitchLoop

	ld a, d
	cp 2
	jr nc, AI_Switch
	and a
	ret

AI_Switch:
	ld a, $1
	ld [wEnemyIsSwitching], a
	ld [wEnemyGoesFirst], a
	ld hl, wEnemySubStatus4
	res SUBSTATUS_RAGE, [hl]
	xor a
	ldh [hBattleTurn], a
	callfar PursuitSwitch

	push af
	ld a, [wCurOTMon]
	ld hl, wOTPartyMon1Status
	ld bc, PARTYMON_STRUCT_LENGTH
	call AddNTimes
	ld d, h
	ld e, l
	ld hl, wEnemyMonStatus
	ld bc, MON_MAXHP - MON_STATUS
	call CopyBytes
	pop af

	jr c, .skiptext
	ld hl, EnemyWithdrewText
	call PrintText

.skiptext
	ld a, 1
	ld [wBattleHasJustStarted], a
	callfar NewEnemyMonStatus
	callfar ResetEnemyStatLevels
	ld hl, wPlayerSubStatus1
	res SUBSTATUS_IN_LOVE, [hl]
	farcall EnemySwitch
	farcall ResetBattleParticipants
	xor a
	ld [wBattleHasJustStarted], a
	ld a, [wLinkMode]
	and a
	ret nz
	scf
	ret

EnemyWithdrewText:
	text_far _EnemyWithdrewText
	text_end

AI_HealStatus:
	ld a, [wCurOTMon]
	ld hl, wOTPartyMon1Status
	ld bc, PARTYMON_STRUCT_LENGTH
	call AddNTimes
	xor a
	ld [hl], a
	ld [wEnemyMonStatus], a
	ld [wEnemyConfuseCount], a
	ld hl, wEnemySubStatus3
	res SUBSTATUS_CONFUSED, [hl]
	ld hl, wEnemySubStatus1
	res SUBSTATUS_NIGHTMARE, [hl]
	ld hl, wEnemySubStatus5
	res SUBSTATUS_TOXIC, [hl]
	farcall CalcEnemyStats
	ret

EnemyUsedXAccuracy:
	call AIUsedItemSound
	ld hl, wEnemySubStatus4
	set SUBSTATUS_X_ACCURACY, [hl]
	ld a, X_ACCURACY
	jr PrintText_UsedItemOn_AND_AIUpdateHUD

EnemyUsedGuardSpec:
	call AIUsedItemSound
	ld hl, wEnemySubStatus4
	set SUBSTATUS_MIST, [hl]
	ld a, GUARD_SPEC
	jr PrintText_UsedItemOn_AND_AIUpdateHUD

EnemyUsedDireHit:
	call AIUsedItemSound
	ld hl, wEnemySubStatus4
	set SUBSTATUS_FOCUS_ENERGY, [hl]
	ld a, DIRE_HIT
	jr PrintText_UsedItemOn_AND_AIUpdateHUD

EnemyUsedXAttack:
	ld b, ATTACK
	ld a, X_ATTACK
	jr EnemyUsedXItem

EnemyUsedXDefend:
	ld b, DEFENSE
	ld a, X_DEFEND
	jr EnemyUsedXItem

EnemyUsedXSpeed:
	ld b, SPEED
	ld a, X_SPEED
	jr EnemyUsedXItem

EnemyUsedXSpecial:
	ld b, SP_ATTACK
	ld a, X_SPECIAL

; Parameter
; a = ITEM_CONSTANT
; b = BATTLE_CONSTANT (ATTACK, DEFENSE, SPEED, SP_ATTACK, SP_DEFENSE, ACCURACY, EVASION)
EnemyUsedXItem:
	ld [wCurEnemyItem], a
	push bc
	call PrintText_UsedItemOn
	pop bc
	farcall RaiseStat
	jp AIUpdateHUD

; Parameter
; a = ITEM_CONSTANT
PrintText_UsedItemOn_AND_AIUpdateHUD:
	ld [wCurEnemyItem], a
	call PrintText_UsedItemOn
	jp AIUpdateHUD

PrintText_UsedItemOn:
	ld a, [wCurEnemyItem]
	ld [wNamedObjectIndex], a
	call GetItemName
	ld hl, wStringBuffer1
	ld de, wMonOrItemNameBuffer
	ld bc, ITEM_NAME_LENGTH
	call CopyBytes
	ld hl, EnemyUsedOnText
	jp PrintText

EnemyUsedOnText:
	text_far _EnemyUsedOnText
	text_end
