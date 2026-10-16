; Matchup evaluation for the Smogon AI (SWITCH_SMOGON and AI_SMOGON).
;
; Instead of relying on GSC OU usage data, which says nothing about Pokemon
; outside the OU metagame, these routines judge a matchup the way a player
; does from the battle screen, so they work against any team:
; - how hard the player's Pokemon can hit ours: the attacks its species
;   usually has (or STAB attacks of its types) and the attacks it has
;   revealed since it came in,
; - how hard our Pokemon can hit back with its attacks,
; - each side's best attack is estimated with the damage formula (level,
;   power, the stats involved, STAB, type, Hidden Power's real type,
;   Reflect and Light Screen, and rain or sun), and turned into how many
;   turns it takes to KO the other side from its current HP,
; - whether the player's Pokemon is asleep or frozen,
; - who is faster (it hits first), and the hit a switch-in takes on the way in.
; A matchup scores SMOGON_MATCHUP_EVEN + 16 * log2(the player's turns to KO
; ours / ours to KO the player's), so 16 points is a race twice as good.
; Higher is better for the AI.
;
; Everything here only runs for Smogon-AI trainers in Challenge Mode, and
; never in link battles.

AISmogon_UsesSmogonSwitching:
; Return nz if the enemy trainer switches with SWITCH_SMOGON in Challenge Mode.
	ld a, [wLinkMode]
	and a
	jr nz, .no
	ld a, [wChallengeMode]
	bit GAME_CHALLENGE_MODE_F, a
	ret z

	ld a, [wInBattleTowerBattle]
	and a
	; always use the first trainer class for Battle Tower trainers
	ld a, 1
	jr nz, .got_class
	ld a, [wTrainerClass]
.got_class
	ld hl, TrainerClassAttributes + TRNATTR_AI_ITEM_SWITCH - NUM_TRAINER_ATTRIBUTES
	ld bc, NUM_TRAINER_ATTRIBUTES
	call AddNTimes
	ld a, BANK(TrainerClassAttributes)
	call GetFarByte
	and SWITCH_SMOGON
	ret

.no
	xor a
	ret

AISmogon_ChooseReplacement:
; After a faint, return carry and b = the party index of the Pokemon with the
; best matchup against the player's, if the trainer uses Smogon switching.
	call AISmogon_UsesSmogonSwitching
; z: return no carry
	ret z
	call AISmogon_FindBestSwitchIn
	ccf
	ret

AISmogon_ScoreActive:
; Score the active Pokemon's matchup in wEnemyAISwitchScore.
	push bc
	ld a, [wCurOTMon]
	ld b, a
	call AISmogon_ScoreMatchup
	ld [wEnemyAISwitchScore], a
	pop bc
	ret

AISmogon_FindBestSwitchIn:
; Find the healthy, non-active Pokemon with the best matchup, discounting
; low HP and status, and favoring answers to a boosted player, Sleep Talk
; users against a sleep move, and Rock, Steel and Ghost types against a
; likely Explosion. Return its party index in b and wSmogonAIBestMon, and its
; score in wSmogonAIBestScore.
; Return carry if there is none.
	ld a, -1
	ld [wSmogonAIBestMon], a
	xor a
	ld [wSmogonAIBestScore], a
	ld b, a
.loop
	ld a, [wOTPartyCount]
	cp b
	jr z, .done
	ld a, [wCurOTMon]
	cp b
	jr z, .next

	ld a, b
	ld [wSmogonAIMon], a
	ld a, MON_HP
	call AISmogon_OTPartyAttr
	ld a, [hli]
	or [hl]
	jr z, .next

	call AISmogon_ScoreMatchup
	ld c, a
	call AISmogon_SwitchInPenalty
	ld d, a
	ld a, c
	sub d
	; keep scores of at least 1, so any healthy Pokemon beats none
	jr z, .floor
	jr nc, .compare
.floor
	ld a, 1
.compare
	ld c, a
	call AISmogon_SwitchInBonus
	add c
	jr nc, .got_bonus
	ld a, $ff
.got_bonus
	ld c, a
	ld a, [wSmogonAIBestScore]
	cp c
	jr nc, .next
	ld a, c
	ld [wSmogonAIBestScore], a
	ld a, b
	ld [wSmogonAIBestMon], a

.next
	inc b
	jr .loop

.done
	ld a, [wSmogonAIBestMon]
	ld b, a
	inc a
	jr z, .none
	and a
	ret

.none
	scf
	ret

AISmogon_SwitchInBonus:
; Return in a how much better wOTPartyMon [wSmogonAIMon] is as a switch-in
; for what it can do beyond its matchup.
	push bc
	ld c, 0
	call AISmogon_CanStopSetup
	jr nc, .sleep
	ld c, SMOGON_ANTI_SETUP_BONUS
.sleep
; A Sleep Talk user takes the player's sleep move and keeps attacking.
	call AISmogon_PlayerThreatensSleep
	jr nc, .boom
	ld a, SLEEP_TALK
	call AISmogon_OTMonHasMove
	jr nc, .boom
	ld a, c
	add SMOGON_SLEEP_ABSORB_BONUS
	ld c, a
.boom
; A Rock, Steel or Ghost type takes a likely Explosion. wSmogonAITypes still
; holds this Pokemon's types from AISmogon_ScoreMatchup.
	call AISmogon_PlayerMayExplode
	jr nc, .done
	ld a, [wSmogonAITypes]
	call AISmogon_ResistsExplosion
	jr z, .boom_absorber
	ld a, [wSmogonAITypes + 1]
	call AISmogon_ResistsExplosion
	jr nz, .done
.boom_absorber
	ld a, c
	add SMOGON_BOOM_ABSORB_BONUS
	ld c, a
.done
	ld a, c
	pop bc
	ret

AISmogon_ResistsExplosion:
; Return z if type a resists Normal or is immune to it.
	cp ROCK
	ret z
	cp STEEL
	ret z
	cp GHOST
	ret

AISmogon_PlayerMayExplode:
; Return carry if the player's Pokemon is likely to explode now: it usually
; has Explosion or Selfdestruct (or has revealed it among its four moves), it
; can move, and it has done its job (Spikes are down on the AI's side) or is
; below half HP.
	ld a, [wBattleMonStatus]
	and SLP_MASK | 1 << FRZ
	ret nz
	ld a, [wPlayerUsedMoves + NUM_MOVES - 1]
	and a
	jr z, .traits
	ld a, EXPLOSION
	call AISmogon_PlayerRevealedMove
	jr c, .worn_down
	ld a, SELFDESTRUCT
	call AISmogon_PlayerRevealedMove
	ret nc
	jr .worn_down

.traits
	call AISmogon_GetPlayerTraits
	and SMOGON_EXPLODER
	ret z
.worn_down
	ld a, [wEnemyScreens]
	bit SCREENS_SPIKES, a
	scf
	ret nz
	push bc
	call AICheckPlayerHalfHP
	pop bc
	ccf
	ret

AISmogon_PlayerThreatensSleep:
; Return carry if the player's Pokemon can use a sleep move on the AI's side
; (it isn't asleep or frozen, and no Safeguard is up) and has revealed one,
; or usually has one and hasn't revealed four other moves.
	ld a, [wBattleMonStatus]
	and SLP_MASK | 1 << FRZ
	ret nz
	ld a, [wEnemyScreens]
	and 1 << SCREENS_SAFEGUARD
	ret nz
	push hl
	ld hl, .SleepMoves
.loop
	ld a, [hli]
	cp -1
	jr z, .traits
	call AISmogon_PlayerRevealedMove
	jr nc, .loop
	pop hl
	ret

.traits
	pop hl
	ld a, [wPlayerUsedMoves + NUM_MOVES - 1]
	and a
	ret nz
	call AISmogon_GetPlayerTraits
	and SMOGON_SLEEPER
	ret z
	scf
	ret

.SleepMoves:
	db SPORE
	db SLEEP_POWDER
	db LOVELY_KISS
	db HYPNOSIS
	db SING
	db -1 ; end

AISmogon_ShouldAbsorbSleep:
; Return carry if the player threatens to put the active Pokemon to sleep,
; and the best switch-in (from AISmogon_FindBestSwitchIn) can take the sleep
; with Sleep Talk while the active Pokemon can't.
	ld a, [wEnemyMonStatus]
	and SLP_MASK
	ret nz
	call AISmogon_PlayerThreatensSleep
	ret nc
	ld a, [wCurOTMon]
	ld [wSmogonAIMon], a
	ld a, SLEEP_TALK
	call AISmogon_OTMonHasMove
	ccf
	ret nc
	ld a, [wSmogonAIBestMon]
	ld [wSmogonAIMon], a
	ld a, SLEEP_TALK
	jp AISmogon_OTMonHasMove

AISmogon_CanStopSetup:
; Return carry if the player's Pokemon has boosted and wOTPartyMon
; [wSmogonAIMon] can undo it with phazing or Haze, or Explode on it.
	push bc
	push hl
	call AISmogon_PlayerBoosted
	jr nc, .done
	ld hl, .Moves
.loop
	ld a, [hli]
	cp -1
; z: done with no carry
	jr z, .done
	call AISmogon_OTMonHasMove
	jr nc, .loop
.done
	pop hl
	pop bc
	ret

.Moves:
	db ROAR
	db WHIRLWIND
	db HAZE
	db EXPLOSION
	db SELFDESTRUCT
	db -1 ; end

AISmogon_SwitchInPenalty:
; Return in a how much worse a switch-in is because of its status: a
; sleeping or frozen one would just sit there. (Its HP is part of its
; matchup score.)
	push bc
	push de
	push hl
	ld c, 0
	ld a, MON_STATUS
	call AISmogon_OTPartyAttr
	ld b, [hl]
	ld a, b
	and SLP_MASK
	jr z, .not_asleep
	ld a, SLEEP_TALK
	call AISmogon_OTMonHasMove
	ld a, SMOGON_PENALTY_SLEEP_TALK
	jr c, .add
	ld a, SMOGON_PENALTY_ASLEEP
	jr .add

.not_asleep
	bit FRZ, b
	ld a, SMOGON_PENALTY_FROZEN
	jr nz, .add
	bit PAR, b
	ld a, SMOGON_PENALTY_PARALYZED
	jr nz, .add
	ld a, b
	and 1 << PSN | 1 << BRN
	jr z, .done
	ld a, SMOGON_PENALTY_POISON_BRN
.add
	add c
	ld c, a
.done
	ld a, c
	pop hl
	pop de
	pop bc
	ret

AISmogon_OTMonHasMove:
; Return carry if wOTPartyMon [wSmogonAIMon] knows move a.
	push bc
	push hl
	ld c, a
	ld a, MON_MOVES
	call AISmogon_OTPartyAttr
	ld b, NUM_MOVES
.loop
	ld a, [hli]
	cp c
	jr z, .yes
	dec b
	jr nz, .loop
	and a
	jr .done

.yes
	scf
.done
	pop hl
	pop bc
	ret

AISmogon_ScoreMatchup:
; Return in a the matchup score of wOTPartyMon b against the player's active
; Pokemon: SMOGON_MATCHUP_EVEN + 16 * log2(the player's turns to KO it /
; its turns to KO the player). Higher is better for the AI.
	push bc
	push de
	push hl
	ld a, b
	ld [wSmogonAIMon], a

; Read the types from the base data, so this works for Pokemon in the back.
	ld a, MON_SPECIES
	call AISmogon_OTPartyAttr
	ld a, [hl]
	ld hl, BaseData + BASE_TYPES - BASE_DATA_SIZE
	ld bc, BASE_DATA_SIZE
	call AddNTimes
	ld de, wSmogonAITypes
	ld bc, wSmogonAIThreat - wSmogonAITypes
	ld a, BANK(BaseData)
	call FarCopyBytes

; How hard can the player hit this Pokemon?
	ld a, MON_ATK
	call AISmogon_OTPartyAttr
	ld de, wBattleMonAttack
	ld a, [wEnemyScreens]
	call AISmogon_SetupDamage
	ld hl, wSmogonAITypes
	call AISmogon_FillTypeMatchups

; Until the player's Pokemon has revealed all four moves, expect the attacks
; its species usually has in GSC OU...
	ld a, [wPlayerUsedMoves + NUM_MOVES - 1]
	and a
	jr nz, .revealed_moves
	push hl
	call AISmogon_FindExpectedAttacks
	jr nc, .assume_stab
.expected_loop
	ld a, [hli]
	cp -1
	jr z, .expected_done
	ld e, a
	ld d, [hl]
	inc hl
	ld c, FALSE
	ld a, [wBattleMonType1]
	cp e
	jr z, .expected_stab
	ld a, [wBattleMonType2]
	cp e
	jr nz, .expected_no_stab
.expected_stab
	inc c
.expected_no_stab
	ld a, e
	call AISmogon_AttackDamage
	jr .expected_loop

.assume_stab
; ...or else strong STAB attacks of both its types.
	pop hl
	ld c, TRUE
	ld d, SMOGON_STAB_POWER
	ld a, [wBattleMonType1]
	ld e, a
	call AISmogon_AttackDamage
	ld a, [wBattleMonType2]
	cp e
	call nz, AISmogon_AttackDamage
	jr .revealed_moves

.expected_done
	pop hl
.revealed_moves
; Also consider the attacks it has revealed since it came in.
	ld e, 0
.player_moves
	push de
	push hl
	ld hl, wPlayerUsedMoves
	ld a, e
	add l
	ld l, a
	adc h
	sub l
	ld h, a
	ld a, [hl]
	and a
	jr z, .player_moves_end
	ld hl, wBattleMonDVs
	call AISmogon_GetAttack
	pop hl
	ld a, d
	and a
	jr z, .next_player_move
	ld c, FALSE
	ld a, [wBattleMonType1]
	cp e
	jr z, .player_stab
	ld a, [wBattleMonType2]
	cp e
	jr nz, .player_no_stab
.player_stab
	inc c
.player_no_stab
	ld a, e
	call AISmogon_AttackDamage
.next_player_move
	pop de
	inc e
	ld a, e
	cp NUM_MOVES
	jr c, .player_moves
	jr .player_moves_done

.player_moves_end
	pop hl
	pop de
.player_moves_done
	ld a, [wSmogonAIBestDamage]
	ld h, a
	ld a, [wSmogonAIBestDamage + 1]
	ld l, a

; A sleeping or frozen Pokemon can't attack, unless it uses Sleep Talk.
	call AISmogon_PlayerCantAttack
	jr z, .player_can_attack
	ld d, h
	ld e, l
	srl d
	rr e
; One that usually has Sleep Talk may still have it: count 3/4 of its
; damage (Sleep Talk calls an attack most of the time) instead of half.
	ld a, [wBattleMonStatus]
	and SLP_MASK
	jr z, .halve_threat
	ld a, [wPlayerUsedMoves + NUM_MOVES - 1]
	and a
	jr nz, .halve_threat
	call AISmogon_GetPlayerTraits
	bit SMOGON_SLEEP_TALK_F, a
	jr z, .halve_threat
	srl d
	rr e
	ld a, l
	sub e
	ld l, a
	ld a, h
	sbc d
	ld h, a
	jr .player_can_attack

.halve_threat
	ld h, d
	ld l, e
.player_can_attack
	ld a, h
	ld [wSmogonAIThreat], a
	ld a, l
	ld [wSmogonAIThreat + 1], a

; How hard can this Pokemon hit the player?
	ld a, MON_ATK
	call AISmogon_OTPartyAttr
	ld d, h
	ld e, l
	ld hl, wBattleMonAttack
	ld a, [wPlayerScreens]
	call AISmogon_SetupDamage
	ld hl, wBattleMonType
	call AISmogon_FillTypeMatchups

	ld e, 0
.our_moves
	push de
	ld a, MON_MOVES
	call AISmogon_OTPartyAttr
	ld a, e
	add l
	ld l, a
	adc h
	sub l
	ld h, a
	ld a, [hl]
	and a
	jr z, .our_moves_end
	push af
	ld a, MON_DVS
	call AISmogon_OTPartyAttr
	pop af
	call AISmogon_GetAttack
	ld a, d
	and a
	jr z, .next_our_move
	ld c, FALSE
	ld a, [wSmogonAITypes]
	cp e
	jr z, .our_stab
	ld a, [wSmogonAITypes + 1]
	cp e
	jr nz, .our_no_stab
.our_stab
	inc c
.our_no_stab
	ld a, e
	call AISmogon_AttackDamage
.next_our_move
	pop de
	inc e
	ld a, e
	cp NUM_MOVES
	jr c, .our_moves
	jr .our_moves_done

.our_moves_end
	pop de
.our_moves_done
	ld a, [wSmogonAIBestDamage]
	ld [wSmogonAIPower], a
	ld a, [wSmogonAIBestDamage + 1]
	ld [wSmogonAIPower + 1], a

; Turns for this Pokemon to KO the player's...
	ld hl, wBattleMonHP
	ld a, [hli]
	ld d, a
	ld e, [hl]
	ld hl, wSmogonAIPower
	call AISmogon_TurnsToKO
	add a
	push af

; ...and for the player's to KO it, counted in half turns.
	ld a, [wCurOTMon]
	ld c, a
	ld a, [wSmogonAIMon]
	cp c
	ld hl, wEnemyMonHP
	jr z, .got_hp
	ld a, MON_HP
	call AISmogon_OTPartyAttr
.got_hp
	ld a, [hli]
	ld d, a
	ld e, [hl]
	ld hl, wSmogonAIThreat
	call AISmogon_TurnsToKO
	add a
	ld b, a

; A switch-in takes a hit on the way in, unless it replaces a fainted
; Pokemon.
	ld a, [wCurOTMon]
	ld c, a
	ld a, [wSmogonAIMon]
	cp c
	jr z, .no_entry_hit
	ld hl, wEnemyMonHP
	ld a, [hli]
	or [hl]
	jr z, .no_entry_hit
	dec b
	dec b
.no_entry_hit

; The faster Pokemon gets its hit in first: half a turn more. The active
; Pokemon's Speed includes its stat changes and paralysis; paralysis quarters
; the Speed of one in the back.
	ld a, [wCurOTMon]
	ld c, a
	ld a, [wSmogonAIMon]
	cp c
	jr nz, .party_speed
	ld a, [wEnemyMonSpeed]
	ld d, a
	ld a, [wEnemyMonSpeed + 1]
	ld e, a
	jr .compare_speed

.party_speed
	ld a, MON_STATUS
	call AISmogon_OTPartyAttr
	ld c, [hl]
	ld a, MON_SPD
	call AISmogon_OTPartyAttr
	ld a, [hli]
	ld d, a
	ld e, [hl]
	bit PAR, c
	jr z, .compare_speed
	srl d
	rr e
	srl d
	rr e
.compare_speed
	; carry if de < the player's Speed
	ld a, [wBattleMonSpeed + 1]
	ld c, a
	ld a, e
	sub c
	ld a, [wBattleMonSpeed]
	ld c, a
	ld a, d
	sbc c
	jr c, .slower
	inc b
.slower
	; a switch-in KOed on the way in counts as half a turn
	ld a, b
	dec a
	cp $80
	jr c, .got_turns
	ld b, 1
.got_turns

; Even + 16 * log2(the player's half turns / ours)
	ld a, b
	call AISmogon_Log2
	ld d, a
	pop af
	call AISmogon_Log2
	ld b, a
	ld a, SMOGON_MATCHUP_EVEN
	add d
	sub b
	pop hl
	pop de
	pop bc
	ret

AISmogon_TurnsToKO:
; Return in a how many hits of the damage word at hl it takes to KO a
; Pokemon with de HP, from 1 to SMOGON_MAX_TURNS.
	ld a, [hli]
	ld b, a
	ld c, [hl]
	or c
	ld a, SMOGON_MAX_TURNS
	ret z
; ceil(HP / damage)
	ld h, d
	ld l, e
	dec bc
	add hl, bc
	inc bc
	xor a
	ldh [hMathBuffer + 1], a
	ld a, h
	ldh [hMathBuffer + 2], a
	ld a, l
	ldh [hMathBuffer + 3], a
	ld d, b
	ld e, c
	call AISmogon_Divide24
	ld a, h
	and a
	jr nz, .max
	ld a, l
	and a
	jr z, .min
	cp SMOGON_MAX_TURNS + 1
	ret c
.max
	ld a, SMOGON_MAX_TURNS
	ret

.min
	inc a
	ret

AISmogon_Divide24:
; Divide the 24-bit big-endian number at hMathBuffer + 1 by de (1 to $7fff).
; Leave the quotient there and return its low 16 bits in hl.
; Much faster than Divide for this.
	ld hl, 0
	ld b, 24
.loop
; Shift the dividend's top bit into the remainder in hl...
	ldh a, [hMathBuffer + 3]
	add a
	ldh [hMathBuffer + 3], a
	ldh a, [hMathBuffer + 2]
	rla
	ldh [hMathBuffer + 2], a
	ldh a, [hMathBuffer + 1]
	rla
	ldh [hMathBuffer + 1], a
	rl l
	rl h
; ...and subtract the divisor when it fits, for a 1 in the quotient.
	ld a, l
	sub e
	ld c, a
	ld a, h
	sbc d
	jr c, .next
	ld h, a
	ld l, c
	ldh a, [hMathBuffer + 3]
	inc a
	ldh [hMathBuffer + 3], a
.next
	dec b
	jr nz, .loop
	ldh a, [hMathBuffer + 2]
	ld h, a
	ldh a, [hMathBuffer + 3]
	ld l, a
	ret

AISmogon_Log2:
; Return in a about 16 * log2(a), for a from 1 to 255. Clobbers b and c.
	ld c, 7 * 16
.normalize
	bit 7, a
	jr nz, .got_exponent
	add a
	ld b, a
	ld a, c
	sub 16
	ld c, a
	ld a, b
	jr .normalize

.got_exponent
; the four bits after the top one approximate the fraction
	rrca
	rrca
	rrca
	and $f
	add c
	ret

AISmogon_SetupDamage:
; de = the attacker's Attack, hl = the defender's Attack, each followed by
; Defense, Speed, Sp.Atk and Sp.Def as big-endian words, with the level 7
; bytes before (as in party and battle structs), and a = the defending
; side's screens. Store what AISmogon_AttackDamage needs, and reset
; wSmogonAIBestDamage.
	assert MON_ATK - MON_LEVEL == wBattleMonAttack - wBattleMonLevel
	assert wBattleMonSpclDef - wBattleMonAttack == MON_SDF - MON_ATK
	assert wBattleMonSpclAtk - wBattleMonAttack == MON_SAT - MON_ATK
	push bc
	push de
	push hl
	ld [wSmogonAIScreens], a

; 2 * level / 5 + 2
	ld h, d
	ld l, e
	ld bc, -(MON_ATK - MON_LEVEL)
	add hl, bc
	ld a, [hl]
	ld [wSmogonAILevel], a
	add a
	ld b, -1
.div5
	inc b
	sub 5
	jr nc, .div5
	ld a, b
	add 2
	ld [wSmogonAILevelFactor], a

; Attack vs Defense (Reflect doubles Defense)
	pop hl
	push hl
	ld a, [de]
	ld b, a
	inc de
	ld a, [de]
	ld c, a
	inc hl
	inc hl
	ld a, [hli]
	ld d, a
	ld e, [hl]
	ld a, [wSmogonAIScreens]
	bit SCREENS_REFLECT, a
	call nz, .Double
	call .Scale
	call .Factor
	ld a, h
	ld [wSmogonAIPhysFactor], a
	ld a, l
	ld [wSmogonAIPhysFactor + 1], a

; Sp.Atk vs Sp.Def (Light Screen doubles Sp.Def)
	pop hl
	pop de
	push de
	push hl
	ld a, e
	add MON_SAT - MON_ATK
	ld e, a
	adc d
	sub e
	ld d, a
	ld a, [de]
	ld b, a
	inc de
	ld a, [de]
	ld c, a
	ld a, l
	add MON_SDF - MON_ATK
	ld l, a
	adc h
	sub l
	ld h, a
	ld a, [hli]
	ld d, a
	ld e, [hl]
	ld a, [wSmogonAIScreens]
	bit SCREENS_LIGHT_SCREEN, a
	call nz, .Double
	call .Scale
	call .Factor
	ld a, h
	ld [wSmogonAISpclFactor], a
	ld a, l
	ld [wSmogonAISpclFactor + 1], a

	xor a
	ld [wSmogonAIBestDamage], a
	ld [wSmogonAIBestDamage + 1], a
	pop hl
	pop de
	pop bc
	ret

.Double:
	sla e
	rl d
	ret

.Factor:
; Return in hl (2 * level / 5 + 2) * c * 256 / e / 50: the damage formula
; without the power, which AISmogon_AttackDamage multiplies by and divides
; by 256. At most 42 * 255 * 256 / 50, so it fits in 16 bits.
	xor a
	ldh [hMultiplicand], a
	ldh [hMultiplicand + 1], a
	ld a, [wSmogonAILevelFactor]
	ldh [hMultiplicand + 2], a
	ld a, c
	ldh [hMultiplier], a
	call Multiply
	; * 256
	ldh a, [hProduct + 2]
	ldh [hMathBuffer + 1], a
	ldh a, [hProduct + 3]
	ldh [hMathBuffer + 2], a
	xor a
	ldh [hMathBuffer + 3], a
	; de = defense * 50
	ld l, e
	ld h, 0
	ld d, h
	add hl, hl
	add hl, hl
	add hl, de
	add hl, hl
	ld d, h
	ld e, l
	add hl, hl
	add hl, hl
	add hl, de
	ld d, h
	ld e, l
	jp AISmogon_Divide24

.Scale:
; Halve bc and de together until both fit in a byte. The defending stat in
; e is at least 1.
	ld a, b
	or d
	jr z, .scaled
	srl b
	rr c
	srl d
	rr e
	jr .Scale

.scaled
	ld a, e
	and a
	ret nz
	inc e
	ret

AISmogon_FillTypeMatchups:
; Fill wSmogonAITypeEffectiveness with each attack type's effectiveness
; against the types at hl, as CheckTypeMatchup would compute it (ignoring
; Foresight), so AISmogon_AttackDamage doesn't scan the type chart per move.
	push bc
	push de
	push hl
	ld b, [hl]
	inc hl
	ld c, [hl]
	ld hl, wSmogonAITypeEffectiveness
	ld e, TYPES_END
	ld a, EFFECTIVE
.init
	ld [hli], a
	dec e
	jr nz, .init

	ld hl, AISmogon_TypeMatchups
.loop
	ld a, [hli]
	cp -1
	jr z, .done
	cp -2
	jr z, .loop
	ld e, a
	ld a, [hli]
	cp b
	jr z, .match
	cp c
	jr z, .match
	inc hl
	jr .loop

.match
	ld a, [hli]
	push hl
	ld d, a
	ld hl, wSmogonAITypeEffectiveness
	ld a, e
	add l
	ld l, a
	adc h
	sub l
	ld h, a
	ld a, d
	cp SUPER_EFFECTIVE
	jr z, .super
	cp NOT_VERY_EFFECTIVE
	jr z, .not_very
	xor a
	jr .store

.super
	ld a, [hl]
	add a
	jr .store

.not_very
	ld a, [hl]
	srl a
.store
	ld [hl], a
	pop hl
	jr .loop

.done
	pop hl
	pop de
	pop bc
	ret

AISmogon_AttackDamage:
; Estimate the damage of an attack of type a and power d, with STAB if c is
; nonzero, using AISmogon_SetupDamage and AISmogon_FillTypeMatchups, and
; keep the highest in wSmogonAIBestDamage.
; Fixed-damage moves like Seismic Toss (power 1) do the attacker's level.
; The random factor, critical hits and accuracy are left out.
	push bc
	push de
	push hl
	ld e, a
	ld hl, wSmogonAITypeEffectiveness
	add l
	ld l, a
	adc h
	sub l
	ld h, a
	ld a, [hl]
	and a
	jp z, .done
	ld b, a

	ld a, d
	cp 2
	jr nc, .formula
	ld a, [wSmogonAILevel]
	ld l, a
	ld h, 0
	jp .keep

.formula
	ld hl, wSmogonAIPhysFactor
	ld a, e
	cp SPECIAL
	jr c, .got_factor
	ld hl, wSmogonAISpclFactor
.got_factor
; power * factor / 256 + 2 (see AISmogon_SetupDamage.Factor), at most
; $7ff so the multipliers below (up to 9 times) stay below $8000
	xor a
	ldh [hMultiplicand], a
	ld a, [hli]
	ldh [hMultiplicand + 1], a
	ld a, [hl]
	ldh [hMultiplicand + 2], a
	ld a, d
	ldh [hMultiplier], a
	call Multiply
	ldh a, [hProduct + 1]
	ld h, a
	ldh a, [hProduct + 2]
	ld l, a
	inc hl
	inc hl
	ld a, h
	cp HIGH($800)
	jr c, .capped
	ld hl, $7ff
.capped

	ld a, c
	and a
	call nz, .AddHalf

; Rain boosts Water and weakens Fire; sun does the opposite.
	ld a, [wBattleWeather]
	cp WEATHER_RAIN
	jr z, .rain
	cp WEATHER_SUN
	jr nz, .type
	ld a, e
	cp FIRE
	jr z, .weather_boost
	cp WATER
	jr z, .weather_drop
	jr .type

.rain
	ld a, e
	cp WATER
	jr z, .weather_boost
	cp FIRE
	jr nz, .type
.weather_drop
	srl h
	rr l
	jr .type

.weather_boost
	call .AddHalf

.type
; Effectiveness: 2 or 4 times, or a half or a quarter.
	ld a, b
	cp EFFECTIVE
	jr z, .keep
	jr c, .resisted
	add hl, hl
	cp EFFECTIVE * 4
	jr c, .keep
	add hl, hl
	jr .keep

.resisted
	srl h
	rr l
	cp NOT_VERY_EFFECTIVE
	jr nc, .keep
	srl h
	rr l

.keep
	ld a, [wSmogonAIBestDamage]
	cp h
	jr c, .store
	jr nz, .done
	ld a, [wSmogonAIBestDamage + 1]
	cp l
	jr nc, .done
.store
	ld a, h
	ld [wSmogonAIBestDamage], a
	ld a, l
	ld [wSmogonAIBestDamage + 1], a
.done
	pop hl
	pop de
	pop bc
	ret

.AddHalf:
	push de
	ld d, h
	ld e, l
	srl d
	rr e
	add hl, de
	pop de
	ret

AISmogon_Compare16:
; Return carry if the big-endian word at de is less than the one at hl.
	push bc
	ld a, [de]
	ld b, a
	inc de
	ld a, [de]
	dec de
	inc hl
	sub [hl]
	dec hl
	ld a, b
	sbc [hl]
	pop bc
	ret

AISmogon_GetAttack:
; Return the power of move a in d and its type in e.
; Hidden Power's power and type come from the DVs at hl.
	cp HIDDEN_POWER
	push af
	call AISmogon_GetMovePowerAndType
	pop af
	ret nz
	push hl
	push bc
	; power = (5 * (the top bit of each DV) + (Special DV & 3)) / 2 + 31,
	; with the top bits in Attack, Defense, Speed, Special order
	ld a, [hli]
	ld c, [hl]
	ld b, a
	and %1000 << 4
	swap a
	ld d, a
	ld a, b
	and %1000
	rrca
	or d
	ld d, a
	ld a, c
	and %1000 << 4
	swap a
	rrca
	rrca
	or d
	ld d, a
	ld a, c
	and %1000
	rrca
	rrca
	rrca
	or d
	ld d, a
	add a
	add a
	add d
	ld d, a
	ld a, c
	and %0011
	add d
	srl a
	add 31
	ld d, a
	pop bc
	pop hl
	push hl
	; type index = (Attack DV & 3) << 2 | (Defense DV & 3)
	ld a, [hl]
	and %0011
	ld e, a
	ld a, [hl]
	and %0011 << 4
	swap a
	add a
	add a
	or e
	add LOW(HiddenPowerDamage.VanillaTypeRemapping)
	ld l, a
	adc HIGH(HiddenPowerDamage.VanillaTypeRemapping)
	sub l
	ld h, a
	ld a, BANK(HiddenPowerDamage)
	call GetFarByte
	ld e, a
	pop hl
	ret

AISmogon_GetMovePowerAndType:
; Return the power of move a in d and its type in e.
; Return and Frustration count as 102, their power at max (min) happiness,
; which OU sets always have, and Magnitude as its average power, 71.
	push bc
	push hl
	push af
	ld hl, Moves + MOVE_POWER - MOVE_LENGTH
	ld bc, MOVE_LENGTH
	call AddNTimes
	ld a, BANK(Moves)
	call GetFarByte
	ld d, a
	assert MOVE_TYPE == MOVE_POWER + 1
	inc hl
	ld a, BANK(Moves)
	call GetFarByte
	ld e, a
	pop af
	cp RETURN
	jr z, .max_happiness
	cp FRUSTRATION
	jr z, .max_happiness
	cp MAGNITUDE
	jr nz, .done
	ld d, 71
	jr .done

.max_happiness
	ld d, 102
.done
	pop hl
	pop bc
	ret

AISmogon_FindExpectedAttacks:
; If the player's Pokemon is in SmogonExpectedAttacks, return carry and hl =
; its attacks (type and power pairs, ending with -1). Keeps b and de.
	ld a, [wBattleMonSpecies]
	ld c, a
	ld hl, SmogonExpectedAttacks
.loop
	ld a, [hli]
	and a
	ret z
	cp c
	jr z, .found
.skip
	ld a, [hli]
	cp -1
	jr z, .loop
	inc hl
	jr .skip

.found
	scf
	ret

AISmogon_OTPartyAttr:
; Return in hl the address of field a of wOTPartyMon [wSmogonAIMon].
	add LOW(wOTPartyMon1)
	ld l, a
	adc HIGH(wOTPartyMon1)
	sub l
	ld h, a
	push bc
	ld a, [wSmogonAIMon]
	ld bc, PARTYMON_STRUCT_LENGTH
	call AddNTimes
	pop bc
	ret

AISmogon_EncoredIntoStatusMove:
; Return carry if the enemy is locked by Encore into a move that does no damage.
	ld a, [wEnemySubStatus5]
	bit SUBSTATUS_ENCORED, a
	ret z
	ld a, [wLastEnemyMove]
	and a
	ret z
	push de
	call AISmogon_GetMovePowerAndType
	ld a, d
	pop de
	and a
	ret nz
	scf
	ret
