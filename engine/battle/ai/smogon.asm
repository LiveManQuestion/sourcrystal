AI_Smogon:
; Play like a GSC OU (Smogon) player.
; - Follow the GSC OU clauses: Sleep Clause, OHKO Clause, Evasion Clause and
;   SleepTrap Clause (no sleep move together with Mean Look or Spider Web).
; - Follow standard GSC OU strategy: lead with sleep, lay Spikes and phaze
;   into them, spin Spikes away, stop setup sweepers with phazing or Haze,
;   set up only when it's safe, heal before falling into KO range, trade
;   Explosion for a healthy threat, steal Leftovers with Thief, Toxic walls
;   that can't Rest it off, and Pursuit fleeing Ghosts and Psychics.
; Only uses information a human player could have: the player's active
; Pokemon, its types, HP, status and stat changes, the moves it has revealed
; since it came in, and how that species is usually played in GSC OU
; (SmogonTraits) for moves it hasn't revealed yet.

	ld hl, wEnemyAIMoveScores
	ld de, wEnemyMonMoves
	ld b, NUM_MOVES + 1
.checkmove
	dec b
	ret z

	ld a, [de]
	inc de
	and a
	ret z

	push de
	push bc
	push hl
	call AIGetEnemyMove

	ld a, [wEnemyMoveStruct + MOVE_EFFECT]
	ld hl, AI_Smogon_EffectHandlers
	ld de, 3
	call IsInArray

	inc hl
	jr nc, .nextmove

	ld a, [hli]
	ld e, a
	ld d, [hl]

	pop hl
	push hl

	ld bc, .nextmove
	push bc

	push de
	ret

.nextmove
	pop hl
	pop bc
	pop de
	inc hl
	jr .checkmove

AI_Smogon_EffectHandlers:
	dbw EFFECT_SLEEP,        AI_Smogon_Sleep
	dbw EFFECT_OHKO,         AIDiscourageMove ; OHKO Clause
	dbw EFFECT_EVASION_UP,   AIDiscourageMove ; Evasion Clause
	dbw EFFECT_EVASION_UP_2, AIDiscourageMove ; Evasion Clause
	dbw EFFECT_MEAN_LOOK,    AI_Smogon_MeanLook
	dbw EFFECT_SPIKES,       AI_Smogon_Spikes
	dbw EFFECT_RAPID_SPIN,   AI_Smogon_RapidSpin
	dbw EFFECT_FORCE_SWITCH, AI_Smogon_Phaze
	dbw EFFECT_RESET_STATS,  AI_Smogon_Haze
	dbw EFFECT_HEAL,         AI_Smogon_Heal
	dbw EFFECT_MORNING_SUN,  AI_Smogon_Heal
	dbw EFFECT_SYNTHESIS,    AI_Smogon_Heal
	dbw EFFECT_MOONLIGHT,    AI_Smogon_Heal
	dbw EFFECT_SELFDESTRUCT, AI_Smogon_Explosion
	dbw EFFECT_THIEF,        AI_Smogon_Thief
	dbw EFFECT_TOXIC,        AI_Smogon_Toxic
	dbw EFFECT_PARALYZE,     AI_Smogon_Paralyze
	dbw EFFECT_PURSUIT,      AI_Smogon_Pursuit
	dbw EFFECT_PERISH_SONG,  AI_Smogon_PerishSong
	dbw EFFECT_SUBSTITUTE,   AI_Smogon_Substitute
	dbw EFFECT_CURSE,        AI_Smogon_Setup
	dbw EFFECT_ATTACK_UP_2,  AI_Smogon_Setup ; Swords Dance
	dbw EFFECT_GROWTH,       AI_Smogon_Setup
	dbw EFFECT_DEFENSE_UP_2, AI_Smogon_Setup ; Acid Armor, Barrier
	dbw EFFECT_SP_DEF_UP_2,  AI_Smogon_Setup ; Amnesia
	dbw EFFECT_SPEED_UP_2,   AI_Smogon_Setup ; Agility
	dbw EFFECT_BELLY_DRUM,   AI_Smogon_Setup
	db -1 ; end

AI_Smogon_Sleep:
; Sleep Clause: never put a second Pokemon to sleep.
	call AISmogon_ScanPlayerParty
	ld a, d
	and a
	jp nz, AIDiscourageMove

; SleepTrap Clause: don't put a trapped Pokemon to sleep.
	ld a, [wPlayerSubStatus5]
	bit SUBSTATUS_CANT_RUN, a
	jp nz, AIDiscourageMove

; Sleep is the strongest status in GSC: greatly encourage it, unless the
; target uses Sleep Talk and will just keep attacking while asleep.
; Save sleep for something else then.
	ld a, SLEEP_TALK
	call AISmogon_PlayerRevealedMove
	jr c, .sleep_talker
	call AISmogon_GetPlayerTraits
	bit SMOGON_SLEEP_TALK_F, a
	jr z, AISmogon_GreatlyEncourage
.sleep_talker
	inc [hl]
	inc [hl]
	ret

AI_Smogon_MeanLook:
; SleepTrap Clause: a Pokemon with a sleep move doesn't trap.
	ld b, EFFECT_SLEEP
	call AIHasMoveEffect
	jp c, AIDiscourageMove
	ret

AI_Smogon_Spikes:
; Spikes are the backbone of GSC OU. Lay them early while the player has
; Pokemon left to switch in; they do nothing against a last Pokemon.
	call AISmogon_ScanPlayerParty
	ld a, c
	and a
	jp z, AIDiscourageMove
	dec [hl]
	cp 2
	ret c
	jr AISmogon_Encourage

AI_Smogon_RapidSpin:
; Spin away Spikes if there are Pokemon left to switch in.
	ld a, [wEnemyScreens]
	bit SCREENS_SPIKES, a
	ret z
	push hl
	farcall FindAliveEnemyMons
	pop hl
	ret c
	jr AISmogon_Encourage

AI_Smogon_Phaze:
; Roar and Whirlwind fail against a last Pokemon.
	call AISmogon_ScanPlayerParty
	ld a, c
	and a
	jp z, AIDiscourageMove
; Phaze to make the player take Spikes damage again.
	ld a, [wPlayerScreens]
	bit SCREENS_SPIKES, a
	jr z, AI_Smogon_Haze
	dec [hl]
	; fallthrough

AI_Smogon_Haze:
; Phaze or Haze away the boosts of a setup sweeper.
	call AISmogon_PlayerBoosted
	ret nc
	; fallthrough

AISmogon_GreatlyEncourage:
	dec [hl]
AISmogon_Encourage:
	dec [hl]
	dec [hl]
	ret

AI_Smogon_Heal:
; Heal before falling into KO range, at half HP rather than a quarter.
	call AICheckEnemyHalfHP
	jr nc, AISmogon_Encourage
; Rest also cures status, so use it earlier when statused.
	ld a, [wEnemyMoveStruct + MOVE_ANIM]
	cp REST
	ret nz
	ld a, [wEnemyMonStatus]
	and a
	ret z
	dec [hl]
	ret

AI_Smogon_Explosion:
; Don't explode into a resisting type or a Substitute.
	push hl
	ld a, 1
	ldh [hBattleTurn], a
	callfar BattleCheckTypeMatchup
	pop hl
	ld a, [wTypeMatchup]
	cp EFFECTIVE
	jr c, .bad
	ld a, [wPlayerSubStatus4]
	bit SUBSTATUS_SUBSTITUTE, a
	jr nz, .bad

; Lay Spikes before exploding.
	ld a, [wPlayerScreens]
	bit SCREENS_SPIKES, a
	jr nz, .spikes_done
	ld b, EFFECT_SPIKES
	call AIHasMoveEffect
	ret c
.spikes_done

; Trade this Pokemon for a healthy threat like Snorlax, even at full HP.
	call AICheckPlayerHalfHP
	ret nc
	call AISmogon_GetPlayerTraits
	bit SMOGON_THREAT_F, a
	ret z
	dec [hl]
	jr AISmogon_GreatlyEncourage

.bad
	inc [hl]
	inc [hl]
	inc [hl]
	ret

AI_Smogon_Thief:
; Stealing Leftovers is a core GSC OU tactic, but Thief only steals
; if the user isn't holding an item and there's no Substitute.
	ld a, [wEnemyMonItem]
	and a
	ret nz
	ld a, [wBattleMonItem]
	and a
	ret z
	ld a, [wPlayerSubStatus4]
	bit SUBSTATUS_SUBSTITUTE, a
	ret nz
; Undo AI_Smart's blanket penalty for Thief, and slightly encourage it.
	ld a, [hl]
	sub 30 + 1
	jr c, .no_penalty
	ld [hl], a
	ret

.no_penalty
	dec [hl]
	ret

AI_Smogon_Toxic:
; Toxic wears down walls, but Rest users just sleep it off.
	ld a, REST
	call AISmogon_PlayerRevealedMove
	jr c, .rester
	call AISmogon_GetPlayerTraits
	bit SMOGON_REST_F, a
	jr nz, .rester
	dec [hl]
	ret

.rester
	inc [hl]
	ret

AI_Smogon_Paralyze:
; Paralysis cripples faster Pokemon and setup sweepers.
	call AICompareSpeed
	jr nc, .encourage
	call AISmogon_GetPlayerTraits
	bit SMOGON_SETUP_F, a
	ret z
.encourage
	dec [hl]
	ret

AI_Smogon_Pursuit:
; Ghosts and Psychics flee from Pursuit users; catch them on the way out.
	ld a, [wBattleMonType1]
	call AISmogon_GhostOrPsychic
	jr z, .encourage
	ld a, [wBattleMonType2]
	call AISmogon_GhostOrPsychic
	ret nz
.encourage
	dec [hl]
	ret

AISmogon_GhostOrPsychic:
	cp GHOST
	ret z
	cp PSYCHIC_TYPE
	ret

AI_Smogon_PerishSong:
; Perish Song is a sure KO once Mean Look has trapped the player.
	ld a, [wPlayerSubStatus5]
	bit SUBSTATUS_CANT_RUN, a
	ret z
	jp AISmogon_Encourage

AI_Smogon_Substitute:
; A sleeping or frozen Pokemon can't break a Substitute.
	ld a, [wBattleMonStatus]
	and SLP_MASK | 1 << FRZ
	ret z
	call AICheckEnemyHalfHP
	ret nc
	jp AISmogon_Encourage

AI_Smogon_Setup:
; Curse is only a stat-up move for non-Ghosts.
	ld a, [wEnemyMoveStruct + MOVE_EFFECT]
	cp EFFECT_CURSE
	jr nz, .not_ghost
	ld a, [wEnemyMonType1]
	cp GHOST
	ret z
	ld a, [wEnemyMonType2]
	cp GHOST
	ret z
.not_ghost

; Don't set up into phazing or Haze, which would erase the boosts.
	ld de, .AntiSetupMoves
.anti_setup_loop
	ld a, [de]
	inc de
	cp -1
	jr z, .anti_setup_done
	call AISmogon_PlayerRevealedMove
	jr c, .discourage
	jr .anti_setup_loop

.anti_setup_done
	call AISmogon_GetPlayerTraits
	bit SMOGON_PHAZER_F, a
	jr nz, .discourage

; Badly poisoned: no time to set up.
	ld a, [wEnemySubStatus5]
	bit SUBSTATUS_TOXIC, a
	jr nz, .discourage

; Set up only while healthy (this also keeps Belly Drum from failing).
	call AICheckEnemyHalfHP
	ret nc

; A sleeping or frozen Pokemon can't punish setup.
	ld a, [wBattleMonStatus]
	and SLP_MASK | 1 << FRZ
	jp nz, AISmogon_Encourage

; Otherwise encourage boosting until it's high enough to sweep.
	ld a, [wEnemyAtkLevel]
	cp BASE_STAT_LEVEL + 3
	ret nc
	ld a, [wEnemySAtkLevel]
	cp BASE_STAT_LEVEL + 3
	ret nc
	dec [hl]
	ret

.discourage
	inc [hl]
	inc [hl]
	ret

.AntiSetupMoves:
	db ROAR
	db WHIRLWIND
	db HAZE
	db -1 ; end

AISmogon_GetPlayerTraits:
; Return the SmogonTraits flags of the player's active Pokemon in a.
	push hl
	push de
	ld a, [wBattleMonSpecies]
	dec a
	ld e, a
	ld d, 0
	ld hl, SmogonTraits
	add hl, de
	ld a, BANK(SmogonTraits)
	call GetFarByte
	pop de
	pop hl
	ret

AISmogon_PlayerRevealedMove:
; Return carry if the player's active Pokemon has used move a.
	push hl
	push bc
	ld hl, wPlayerUsedMoves
	ld c, NUM_MOVES
.loop
	cp [hl]
	jr z, .yes
	inc hl
	dec c
	jr nz, .loop
	and a
	jr .done

.yes
	scf
.done
	pop bc
	pop hl
	ret

AISmogon_PlayerBoosted:
; Return carry if any of the player's stat levels are raised.
	push hl
	ld hl, wPlayerStatLevels
	jr AISmogon_StatLevelsRaised

AISmogon_EnemyBoosted:
; Return carry if any of the enemy's stat levels are raised.
	push hl
	ld hl, wEnemyStatLevels
	; fallthrough

AISmogon_StatLevelsRaised:
	ld c, NUM_LEVEL_STATS
.loop
	ld a, [hli]
	cp BASE_STAT_LEVEL + 1
	jr nc, .yes
	dec c
	jr nz, .loop
	pop hl
	and a
	ret

.yes
	pop hl
	scf
	ret

AISmogon_ScanPlayerParty:
; Look at the player's Pokemon other than the active one.
; Return c = how many can still battle,
; and d = their sleep counters OR'd together (nonzero if any are asleep).
	push hl
	ld hl, wPartyMon1HP
	ld a, [wPartyCount]
	ld b, a
	ld c, 0
	ld de, 0 ; d = sleep bits, e = party index
.loop
	ld a, [wCurBattleMon]
	cp e
	jr z, .next

	push hl
	ld hl, wPartySpecies
	ld a, l
	add e
	ld l, a
	adc h
	sub l
	ld h, a
	ld a, [hl]
	pop hl
	cp EGG
	jr z, .next

	ld a, [hli]
	or [hl]
	dec hl
	jr z, .next

	inc c
	dec hl
	dec hl
	assert MON_HP - MON_STATUS == 2
	ld a, [hli]
	inc hl
	and SLP_MASK
	or d
	ld d, a

.next
	ld a, l
	add PARTYMON_STRUCT_LENGTH
	ld l, a
	adc h
	sub l
	ld h, a
	inc e
	dec b
	jr nz, .loop

	pop hl
	ret
