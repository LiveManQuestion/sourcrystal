; Matchup evaluation for the Smogon AI (SWITCH_SMOGON and AI_SMOGON).
;
; Instead of relying on GSC OU usage data, which says nothing about Pokemon
; outside the OU metagame, these routines judge a matchup the way a player
; does from the battle screen, so they work against any team:
; - how hard the player's Pokemon can hit ours: its own types (assuming STAB
;   attacks of both) and the attacks it has revealed since it came in,
; - how hard our Pokemon can hit back with its attacks,
; - who has the edge between the attacking and defending stats involved
;   (physical or special, by type), the moves' power and STAB, Hidden Power's
;   real type, Reflect and Light Screen, and rain or sun,
; - whether the player's Pokemon is asleep or frozen,
; - who is faster, and whether that allows a revenge kill.
; Each side's best attack is reduced to rough damage points, and a matchup
; scores SMOGON_MATCHUP_EVEN + (our points) - (the player's points), plus
; bonuses for speed. Higher is better for the AI.
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
	ret z ; no carry
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
; low HP and status, and favoring answers to a boosted player and Sleep Talk
; users against a sleep move. Return its
; party index in b and wSmogonAIBestMon, and its score in wSmogonAIBestScore.
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
	jr nc, .done
	ld a, SLEEP_TALK
	call AISmogon_OTMonHasMove
	jr nc, .done
	ld a, c
	add SMOGON_SLEEP_ABSORB_BONUS
	ld c, a
.done
	ld a, c
	pop bc
	ret

AISmogon_PlayerThreatensSleep:
; Return carry if the player's Pokemon has revealed a sleep move it can use
; on the AI's side: it isn't asleep or frozen, and no Safeguard is up.
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
	jr z, .done ; no carry
	call AISmogon_PlayerRevealedMove
	jr nc, .loop
.done
	pop hl
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
	jr z, .done ; no carry
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
; Return in a how much worse a switch-in is because of its HP and status.
; A Pokemon in KO range can't afford to take a hit on the way in, and a
; sleeping or frozen one would just sit there.
	push bc
	push de
	push hl
	ld c, 0
	ld a, MON_HP
	call AISmogon_OTPartyAttr
	call AISmogon_HPBelowHalf
	jr nc, .status
	ld c, SMOGON_PENALTY_HALF_HP
	; HP * 4 < max HP?
	sla e
	rl d
	ld a, e
	sub [hl]
	ld a, d
	sbc b
	jr nc, .status
	ld c, SMOGON_PENALTY_QUARTER_HP

.status
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

AISmogon_HPBelowHalf:
; hl = a Pokemon's HP, followed by its max HP (big-endian words).
; Return carry if HP * 2 < max HP, with de = HP * 2, b = the max HP's high
; byte and hl pointing to its low byte.
	ld a, [hli]
	ld d, a
	ld a, [hli]
	ld e, a
	ld a, [hli]
	ld b, a
	sla e
	rl d
	ld a, e
	sub [hl]
	ld a, d
	sbc b
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
; Pokemon. SMOGON_MATCHUP_EVEN is even; higher is better for the AI.
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

	xor a
	ld [wSmogonAIThreat], a
	ld [wSmogonAIPower], a

; How hard can the player hit this Pokemon?
	ld a, MON_ATK
	call AISmogon_OTPartyAttr
	ld de, wBattleMonAttack
	ld a, [wEnemyScreens]
	call AISmogon_StatEdges
	ld hl, wSmogonAITypes

; Assume the player has strong STAB attacks of both its types.
	ld c, TRUE
	ld d, SMOGON_STAB_POWER
	ld a, [wBattleMonType1]
	ld e, a
	call .PlayerAttack
	ld a, [wBattleMonType2]
	cp e
	call nz, .PlayerAttack

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
	call .PlayerAttack
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

; A sleeping or frozen Pokemon can't attack, unless it uses Sleep Talk.
	ld a, [wBattleMonStatus]
	and SLP_MASK | 1 << FRZ
	jr z, .player_can_attack
	ld hl, wPlayerUsedMoves
	ld b, NUM_MOVES
.sleep_talk_loop
	ld a, [hli]
	cp SLEEP_TALK
	jr z, .player_can_attack
	dec b
	jr nz, .sleep_talk_loop
	ld hl, wSmogonAIThreat
	srl [hl]
.player_can_attack

; How hard can this Pokemon hit the player?
	ld a, MON_ATK
	call AISmogon_OTPartyAttr
	ld d, h
	ld e, l
	ld hl, wBattleMonAttack
	ld a, [wPlayerScreens]
	call AISmogon_StatEdges

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
	ld hl, wBattleMonType
	ld a, e
	call AISmogon_AttackPoints
	ld hl, wSmogonAIPower
	cp [hl]
	jr c, .next_our_move
	ld [hl], a
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

; Even + our best attack - the player's best attack
	ld a, [wSmogonAIThreat]
	ld b, a
	ld a, [wSmogonAIPower]
	add SMOGON_MATCHUP_EVEN
	sub b
	ld b, a

; Outspeeding wins trades...
	ld a, MON_SPD
	call AISmogon_OTPartyAttr
	ld d, h
	ld e, l
	ld hl, wBattleMonSpeed
	call AISmogon_Compare16
	ld a, b
	jr c, .done
	add SMOGON_FASTER_BONUS
	ld c, a

; ...and finishes off a weakened Pokemon before it can move.
	ld hl, wBattleMonHP
	call AISmogon_HPBelowHalf
	ld a, c
	jr nc, .done
	add SMOGON_REVENGE_BONUS
.done
	pop hl
	pop de
	pop bc
	ret

.PlayerAttack:
	call AISmogon_AttackPoints
	push hl
	ld hl, wSmogonAIThreat
	cp [hl]
	jr c, .keep_threat
	ld [hl], a
.keep_threat
	pop hl
	ret

AISmogon_AttackPoints:
; Return in a rough damage points for an attack of type a and power d against
; the types at hl. c is nonzero for STAB. b holds the attacker's stat edges
; (see AISmogon_StatEdges).
; Effectiveness gives the base points; STAB, rain or sun add or remove half;
; power and the stat edge add or remove a quarter.
; Fixed-damage moves like Seismic Toss count as neutral hits.
	push bc
	push de
	push hl
	ld e, a
	newfarcall CheckTypeMatchup
	ld a, [wTypeMatchup]
	and a
	jr z, .done
	ld h, SMOGON_POINTS_RESISTED
	cp EFFECTIVE
	jr c, .got_points
	ld h, SMOGON_POINTS_NEUTRAL
	jr z, .got_points
	ld h, SMOGON_POINTS_SUPER
	cp SUPER_EFFECTIVE + 1
	jr c, .got_points
	ld h, SMOGON_POINTS_4X
.got_points

	ld a, d
	cp 2
	ld a, SMOGON_POINTS_NEUTRAL
	jr c, .done

	; l = a quarter of the base points
	ld a, h
	srl a
	srl a
	ld l, a

	ld a, c
	and a
	jr z, .no_stab
	ld a, l
	add a
	add h
	ld h, a
.no_stab

; Rain boosts Water and weakens Fire; sun does the opposite.
	ld a, [wBattleWeather]
	cp WEATHER_RAIN
	jr z, .rain
	cp WEATHER_SUN
	jr nz, .no_weather
	ld a, e
	cp FIRE
	jr z, .weather_boost
	cp WATER
	jr z, .weather_drop
	jr .no_weather

.rain
	ld a, e
	cp WATER
	jr z, .weather_boost
	cp FIRE
	jr nz, .no_weather
.weather_drop
	ld a, h
	sub l
	sub l
	ld h, a
	jr .no_weather

.weather_boost
	ld a, l
	add a
	add h
	ld h, a
.no_weather

	ld a, d
	cp SMOGON_WEAK_POWER
	jr nc, .not_weak
	ld a, h
	sub l
	ld h, a
	jr .stats

.not_weak
	cp SMOGON_STRONG_POWER
	jr c, .stats
	ld a, h
	add l
	ld h, a

.stats
	ld a, e
	cp SPECIAL
	ld a, b
	jr c, .physical
	assert SMOGON_SPECIAL_EDGE_F == SMOGON_PHYSICAL_EDGE_F + 1
	rrca
.physical
	assert SMOGON_PHYSICAL_EDGE_F == 0
	rrca
	ld a, h
	jr c, .edge
	sub l
	jr .done

.edge
	add l
.done
	pop hl
	pop de
	pop bc
	ret

AISmogon_StatEdges:
; de = the attacker's Attack, hl = the defender's Attack, each followed by
; Defense, Speed, Sp.Atk and Sp.Def as big-endian words, and a = the
; defending side's screens. Return in b which of the attacker's stats beat
; the defender's: Attack vs Defense (SMOGON_PHYSICAL_EDGE_F) and Sp.Atk vs
; Sp.Def (SMOGON_SPECIAL_EDGE_F). Reflect and Light Screen take an edge away.
	push de
	push hl
	ld c, a
	ld b, 0
	inc hl
	inc hl
	call AISmogon_Compare16
	jr c, .no_physical_edge
	bit SCREENS_REFLECT, c
	jr nz, .no_physical_edge
	set SMOGON_PHYSICAL_EDGE_F, b
.no_physical_edge
	; Defense -> Sp.Def and Attack -> Sp.Atk
	assert wBattleMonSpclDef - wBattleMonDefense == MON_SDF - MON_DEF
	assert wBattleMonSpclAtk - wBattleMonAttack == MON_SAT - MON_ATK
	ld a, l
	add (MON_SDF - MON_DEF)
	ld l, a
	adc h
	sub l
	ld h, a
	ld a, e
	add (MON_SAT - MON_ATK)
	ld e, a
	adc d
	sub e
	ld d, a
	call AISmogon_Compare16
	jr c, .done
	bit SCREENS_LIGHT_SCREEN, c
	jr nz, .done
	set SMOGON_SPECIAL_EDGE_F, b
.done
	pop hl
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
; which OU sets always have.
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
	jr nz, .done
.max_happiness
	ld d, 102
.done
	pop hl
	pop bc
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
