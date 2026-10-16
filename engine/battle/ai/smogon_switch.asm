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
	push hl
	ld a, e
	ld hl, wSmogonAITypes
	call .PlayerAttack
	pop hl
	jr .expected_loop

.assume_stab
; ...or else strong STAB attacks of both its types.
	pop hl
	ld c, TRUE
	ld d, SMOGON_STAB_POWER
	ld a, [wBattleMonType1]
	ld e, a
	call .PlayerAttack
	ld a, [wBattleMonType2]
	cp e
	call nz, .PlayerAttack
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
	call AISmogon_PlayerCantAttack
	jr z, .player_can_attack
	ld hl, wSmogonAIThreat
; One that usually has Sleep Talk may still have it: count 3/4 of its
; threat (Sleep Talk calls an attack most of the time) instead of half.
	ld a, [wBattleMonStatus]
	and SLP_MASK
	jr z, .halve_threat
	ld a, [wPlayerUsedMoves + NUM_MOVES - 1]
	and a
	jr nz, .halve_threat
	call AISmogon_GetPlayerTraits
	bit SMOGON_SLEEP_TALK_F, a
	jr z, .halve_threat
	ld a, [hl]
	srl a
	srl a
	cpl
	inc a
	add [hl]
	ld [hl], a
	jr .player_can_attack

.halve_threat
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

; Outspeeding wins trades... The active Pokemon's Speed includes its stat
; changes and paralysis; paralysis quarters the Speed of one in the back.
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
	jp z, .done
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
; The stat matchup adds or removes a quarter, or half when it's lopsided.
	ld a, e
	cp SPECIAL
	ld a, b
	jr c, .physical
	assert SMOGON_SPECIAL_EDGE_SHIFT == 2
	rrca
	rrca
.physical
	and %11
	ld c, a
	assert SMOGON_EDGE_MUCH_WORSE == 0
	jr z, .lopsided
	cp SMOGON_EDGE_MUCH_BETTER
	jr nz, .got_edge
.lopsided
	sla l
.got_edge
	ld a, h
	assert SMOGON_EDGE_BETTER == %10 && SMOGON_EDGE_MUCH_BETTER == %11
	bit 1, c
	jr nz, .edge
	sub l
	jr nc, .done
	xor a
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
; defending side's screens. Return in b how the attacker's stats compare to
; the defender's (SMOGON_EDGE_* levels): Attack vs Defense in bits 0-1 and
; Sp.Atk vs Sp.Def in bits 2-3. Reflect and Light Screen make it one level
; worse. The defender's stats count its bulk: they're scaled by its max HP
; against the usual HP at its level, so Blissey's and Snorlax's huge HP matter.
	push de
	push hl
	push af
	call AISmogon_GetBulk
	pop af
	ld c, a
	inc hl
	inc hl
	call AISmogon_CompareBulk
	bit SCREENS_REFLECT, c
	call nz, .Screen
	ld b, a
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
	call AISmogon_CompareBulk
	bit SCREENS_LIGHT_SCREEN, c
	call nz, .Screen
	assert SMOGON_SPECIAL_EDGE_SHIFT == 2
	add a
	add a
	or b
	ld b, a
	pop hl
	pop de
	ret

.Screen:
; A screen halves the damage.
	and a
	ret z
	dec a
	ret

AISmogon_GetBulk:
; hl = the defender's Attack in a party or battle struct, where its max HP
; and level come 2 and 7 bytes before. Store its max HP / 4 in
; wSmogonAIBulkHP, and the usual HP at its level (about 3.25 * level + 10)
; / 4 in wSmogonAIBulkRef.
	push de
	push hl
	dec hl
	ld e, [hl]
	dec hl
	ld d, [hl]
	srl d
	rr e
	srl d
	rr e
	ld a, d
	and a
	ld a, e
	jr z, .got_hp
	ld a, $ff
.got_hp
	ld [wSmogonAIBulkHP], a
	ld de, -(MON_ATK - MON_LEVEL - 2)
	add hl, de
	assert MON_ATK - MON_LEVEL == wBattleMonAttack - wBattleMonLevel
	assert MON_ATK - MON_MAXHP == wBattleMonAttack - wBattleMonMaxHP
; 13 * level / 16 + 3
	ld e, [hl]
	ld d, 0
	ld h, d
	ld l, e
	add hl, hl
	add hl, de
	add hl, hl
	add hl, hl
	add hl, de
	ld a, l
	srl h
	rra
	srl h
	rra
	srl h
	rra
	srl h
	rra
	add 3
	ld [wSmogonAIBulkRef], a
	pop hl
	pop de
	ret

AISmogon_CompareBulk:
; Return in a how the attacker's stat word at de times wSmogonAIBulkRef
; compares to the defender's stat word at hl times wSmogonAIBulkHP, from
; SMOGON_EDGE_MUCH_WORSE (below half) to SMOGON_EDGE_MUCH_BETTER (at least
; double). Both products fit in 18 bits, so doubling one can't overflow.
	push bc
	push de
	push hl
	xor a
	ldh [hMultiplicand], a
	ld a, [de]
	ldh [hMultiplicand + 1], a
	inc de
	ld a, [de]
	ldh [hMultiplicand + 2], a
	ld a, [wSmogonAIBulkRef]
	ldh [hMultiplier], a
	call Multiply
	ldh a, [hProduct + 1]
	push af
	ldh a, [hProduct + 2]
	ld b, a
	ldh a, [hProduct + 3]
	ld c, a
	xor a
	ldh [hMultiplicand], a
	ld a, [hli]
	ldh [hMultiplicand + 1], a
	ld a, [hl]
	ldh [hMultiplicand + 2], a
	ld a, [wSmogonAIBulkHP]
	ldh [hMultiplier], a
	call Multiply
; d:b:c = the attacker's product, hProduct + 1 = the defender's
	pop de
	call .Compare
	jr c, .worse
	ld hl, hProduct + 3
	sla [hl]
	dec hl
	rl [hl]
	dec hl
	rl [hl]
	call .Compare
	ld a, SMOGON_EDGE_BETTER
	jr c, .done
	inc a
	jr .done

.worse
	sla c
	rl b
	rl d
	call .Compare
	ld a, SMOGON_EDGE_MUCH_WORSE
	jr c, .done
	inc a
.done
	pop hl
	pop de
	pop bc
	ret

.Compare:
; Return carry if d:b:c is less than the 3 bytes at hProduct + 1.
	ld hl, hProduct + 3
	ld a, c
	sub [hl]
	dec hl
	ld a, b
	sbc [hl]
	dec hl
	ld a, d
	sbc [hl]
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
