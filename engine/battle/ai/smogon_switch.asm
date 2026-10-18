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
; Score the active Pokemon's matchup in wEnemyAISwitchScore, and set
; wSmogonAIActiveStalled if neither side can KO the other.
	push bc
	ld a, [wCurOTMon]
	ld b, a
	call AISmogon_ScoreMatchup
	ld [wEnemyAISwitchScore], a
	ld a, [wSmogonAIStalled]
	ld [wSmogonAIActiveStalled], a
	pop bc
	ret

AISmogon_GetSetupBoost:
; Return in a how wSmogonAIMon's attacks count in the KO race if it can
; boost before attacking (SMOGON_SETUP_*, see AISmogon_SetupPower): it
; knows Swords Dance, Growth, Sharpen, Meditate or Curse (not as a Ghost),
; the player can't phaze or Haze, and SMOGON_SETUP_SAFE_HITS of the
; player's strongest attack (wSmogonAIThreat) don't KO it. Like Misty's
; Tentacruel, which can Swords Dance in front of a Surf-only Vaporeon.
	call AISmogon_PlayerCanPhaze
	jr c, .none

; de = its HP
	ld a, [wCurOTMon]
	ld b, a
	ld a, [wSmogonAIMon]
	cp b
	jr nz, .party_hp
	ld a, [wEnemyMonHP]
	ld d, a
	ld a, [wEnemyMonHP + 1]
	ld e, a
	jr .got_hp
.party_hp
	ld a, MON_HP
	call AISmogon_OTPartyAttr
	ld d, [hl]
	inc hl
	ld e, [hl]
.got_hp
	push de
	ld a, [wSmogonAIThreat + ATTACKS_BEST]
	ld d, a
	ld a, [wSmogonAIThreat + ATTACKS_BEST + 1]
	ld e, a
	ld hl, 0
	ld b, SMOGON_SETUP_SAFE_HITS
.add_hit
	add hl, de
	dec b
	jr nz, .add_hit
	pop de
	; no carry if the hits KO
	ld a, l
	sub e
	ld a, h
	sbc d
	jr nc, .none

	ld a, SWORDS_DANCE
	call AISmogon_OTMonHasMove
	ld a, SMOGON_SETUP_DOUBLE
	ret c
	ld a, GROWTH
	call AISmogon_OTMonHasMove
	ld a, SMOGON_SETUP_SPECIAL
	ret c
	ld a, SHARPEN
	call AISmogon_OTMonHasMove
	jr c, .physical
	ld a, MEDITATE
	call AISmogon_OTMonHasMove
	jr c, .physical
	ld a, CURSE
	call AISmogon_OTMonHasMove
	jr nc, .none
	ld a, [wSmogonAITypes]
	cp GHOST
	jr z, .none
	ld a, [wSmogonAITypes + 1]
	cp GHOST
	jr z, .none
.physical
	ld a, SMOGON_SETUP_PHYSICAL
	ret

.none
	xor a ; SMOGON_SETUP_NONE
	ret

AISmogon_SetupPower:
; Raise power d of an attack of type e as wSmogonAISetupBoost says: x2 or
; x1.5, if the boost is for its category, at most 255. Keeps everything
; but a and d.
	ld a, [wSmogonAISetupBoost]
	and a ; SMOGON_SETUP_NONE
	ret z
	cp SMOGON_SETUP_SPECIAL
	ld a, e
	jr z, .special
	cp SPECIAL
	ret nc
	jr .boost
.special
	cp SPECIAL
	ret c
.boost
	ld a, [wSmogonAISetupBoost]
	cp SMOGON_SETUP_DOUBLE
	ld a, d
	jr z, .double
	srl a
	add d
	jr .got_power
.double
	add a
.got_power
	jr nc, .no_cap
	ld a, $ff
.no_cap
	ld d, a
	ret

AISmogon_PenalizeAsleepActive:
; Take the switch-in penalty for sleep or freeze (AISmogon_SwitchInPenalty)
; off the active Pokemon's score too, so a Rest user asleep without Sleep
; Talk makes room for a better matchup. Not when it wakes up this turn: it
; can't move then, but neither can a switch-in. Call after
; AISmogon_ScoreActive.
	ld a, [wEnemyMonStatus]
	ld b, a
	and SLP_MASK
	jr z, .not_asleep
	cp 2
	ret c
	ld a, SLEEP_TALK
	call AISmogon_OTMonHasMove
	ld c, SMOGON_PENALTY_SLEEP_TALK
	jr c, .penalize
	ld c, SMOGON_PENALTY_ASLEEP
	jr .penalize

.not_asleep
	bit FRZ, b
	ret z
	ld c, SMOGON_PENALTY_FROZEN
.penalize
	ld a, [wEnemyAISwitchScore]
	sub c
	jr nc, .got_score
	xor a
.got_score
	ld [wEnemyAISwitchScore], a
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
; Return carry if the player's Pokemon is likely to explode now: it can
; (AISmogon_PlayerCanExplode), and it has done its job (Spikes are down on
; the AI's side) or is below half HP.
	call AISmogon_PlayerCanExplode
	ret nc
	ld a, [wEnemyScreens]
	bit SCREENS_SPIKES, a
	scf
	ret nz
	push bc
	call AICheckPlayerHalfHP
	pop bc
	ccf
	ret

AISmogon_PlayerCanExplode:
; Return carry if the player's Pokemon can move and usually has Explosion or
; Selfdestruct (or has revealed it among its four moves).
	ld a, [wBattleMonStatus]
	and SLP_MASK | 1 << FRZ
	ret nz
	ld a, [wPlayerUsedMoves + NUM_MOVES - 1]
	and a
	jr z, .traits
	ld a, EXPLOSION
	call AISmogon_PlayerRevealedMove
	ret c
	ld a, SELFDESTRUCT
	jp AISmogon_PlayerRevealedMove

.traits
	call AISmogon_GetPlayerTraits
	and SMOGON_EXPLODER
	ret z
	scf
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
	call AISmogon_CountPlayerPPUps

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
	ld hl, wSmogonAIThreat
	call AISmogon_StartAttacks
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
	ld a, [wSmogonAIUnknownPP]
	ld b, a
	ld a, e
	call AISmogon_AttackDamage
	jr .expected_loop

.assume_stab
; ...or else strong STAB attacks of both its types.
	pop hl
	ld c, TRUE
	ld d, SMOGON_STAB_POWER
	ld a, [wSmogonAIUnknownPP]
	ld b, a
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
	push af
	call AISmogon_BasePP
	call AISmogon_PlayerMaxPP
	ld b, a
	pop af
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

; A sleeping or frozen Pokemon can't attack, unless it uses Sleep Talk:
; count half its damage.
	call AISmogon_PlayerCantAttack
	jr z, .player_can_attack
	ld c, FALSE
; One that usually has Sleep Talk may still have it: count 3/4 of its
; damage (Sleep Talk calls an attack most of the time) instead.
	ld a, [wBattleMonStatus]
	and SLP_MASK
	jr z, .scale_threat
	ld a, [wPlayerUsedMoves + NUM_MOVES - 1]
	and a
	jr nz, .scale_threat
	call AISmogon_GetPlayerTraits
	bit SMOGON_SLEEP_TALK_F, a
	jr z, .scale_threat
	inc c
.scale_threat
	ld hl, wSmogonAIThreat
	call AISmogon_ScaleAttacks
.player_can_attack

; A Pokemon that can boost while the player barely scratches it will
; (AI_Smogon_Setup): count its attacks boosted, a turn later.
	call AISmogon_GetSetupBoost
	ld [wSmogonAISetupBoost], a

; How hard can this Pokemon hit the player?
	ld a, MON_ATK
	call AISmogon_OTPartyAttr
	ld d, h
	ld e, l
	ld hl, wBattleMonAttack
	ld a, [wPlayerScreens]
	call AISmogon_SetupDamage
	ld hl, wSmogonAIPower
	call AISmogon_StartAttacks
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
	call AISmogon_OurMovePP
	ld b, a
	pop af
	push af
	ld a, MON_DVS
	call AISmogon_OTPartyAttr
	pop af
	call AISmogon_GetAttack
	ld a, d
	and a
	jr z, .next_our_move
	call AISmogon_SetupPower
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
	call AISmogon_ApplyHealing

; Turns for this Pokemon to KO the player's (longer if the player's
; outheals it), plus the turns it spends healing itself...
	ld hl, wSmogonAIPlayerHeal
	ld de, wSmogonAIPower
	call AISmogon_SideTurns
	ld [wSmogonAIOurTurns], a
	ld hl, wSmogonAIOurHeal
	ld de, wSmogonAIThreat
	call AISmogon_HealDelay
	add a
; ...plus the turn it spends boosting.
	ld c, a
	ld a, [wSmogonAISetupBoost]
	and a
	ld a, c
	jr z, .no_setup_turn
	add 2
.no_setup_turn
	push af

; ...and the same for the player's to KO it, counted in half turns.
	ld hl, wSmogonAIOurHeal
	ld de, wSmogonAIThreat
	call AISmogon_SideTurns
; Neither side can KO the other if both take SMOGON_MAX_TURNS.
	push af
	cp SMOGON_MAX_TURNS
	jr nz, .not_stalled
	ld a, [wSmogonAIOurTurns]
	cp SMOGON_MAX_TURNS
	jr nz, .not_stalled
	ld a, TRUE
	jr .got_stalled
.not_stalled
	xor a ; FALSE
.got_stalled
	ld [wSmogonAIStalled], a
	pop af
	ld hl, wSmogonAIPlayerHeal
	ld de, wSmogonAIPower
	call AISmogon_HealDelay
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

AISmogon_ApplyHealing:
; Fill wSmogonAIOurHeal and wSmogonAIPlayerHeal (see wram.asm) for each side,
; and take Leftovers off the damage it takes per turn. A recovery move heals
; half the max HP per use, Rest a quarter (it costs sleeping turns). The AI
; knows its own Pokemon's moves, item and PP; the player's Pokemon heals
; with the recovery moves it has revealed, or Rest if it usually has it,
; with the PP Ups the player uses (AISmogon_CountPlayerPPUps), and is
; assumed to hold Leftovers like most GSC OU Pokemon.
	ld a, [wBattleMonHP]
	ld [wSmogonAIPlayerHeal + HEAL_HP], a
	ld a, [wBattleMonHP + 1]
	ld [wSmogonAIPlayerHeal + HEAL_HP + 1], a
	ld a, [wCurOTMon]
	ld c, a
	ld a, [wSmogonAIMon]
	cp c
	ld hl, wEnemyMonHP
	jr z, .got_our_hp
	ld a, MON_HP
	call AISmogon_OTPartyAttr
.got_our_hp
	ld a, [hli]
	ld [wSmogonAIOurHeal + HEAL_HP], a
	ld a, [hl]
	ld [wSmogonAIOurHeal + HEAL_HP + 1], a

	ld a, MON_MAXHP
	call AISmogon_OTPartyAttr
	ld a, [hli]
	ld d, a
	ld e, [hl]

; A switch-in (also after a faint) loses 1/8 of its max HP to Spikes on the
; way in, unless it's a Flying type.
	ld a, [wCurOTMon]
	ld c, a
	ld a, [wSmogonAIMon]
	cp c
	jr z, .no_spikes
	ld a, [wEnemyScreens]
	bit SCREENS_SPIKES, a
	jr z, .no_spikes
	ld a, [wSmogonAITypes]
	cp FLYING
	jr z, .no_spikes
	ld a, [wSmogonAITypes + 1]
	cp FLYING
	jr z, .no_spikes
	push de
	srl d
	rr e
	srl d
	rr e
	srl d
	rr e
	ld hl, wSmogonAIOurHeal + HEAL_HP + 1
	ld a, [hl]
	sub e
	ld [hld], a
	ld a, [hl]
	sbc d
	ld [hl], a
	jr nc, .spiked
	xor a
	ld [hli], a
	ld [hl], a
.spiked
	pop de
.no_spikes
	ld hl, AISmogon_RecoveryMoves
.our_recovery
	ld a, [hli]
	inc hl
	cp REST
	jr z, .our_rest
	call AISmogon_OurMovePP
	jr nc, .our_recovery
	call .Half
	jr .got_our_heal

.our_rest
	call AISmogon_OurMovePP
	call .Quarter
.got_our_heal
	ld hl, wSmogonAIOurHeal
	call .Store
	ld a, MON_ITEM
	call AISmogon_OTPartyAttr
	ld a, [hl]
	cp LEFTOVERS
	jr nz, .player
	ld hl, wSmogonAIThreat
	call AISmogon_SubtractSixteenth

.player
	ld a, [wBattleMonMaxHP]
	ld d, a
	ld a, [wBattleMonMaxHP + 1]
	ld e, a
	ld hl, AISmogon_RecoveryMoves
.player_recovery
	ld a, [hli]
	cp REST
	jr z, .player_rest
	call AISmogon_PlayerRevealedMove
	ld a, [hli]
	jr nc, .player_recovery
	call .Half
	jr .got_player_heal

.player_rest
	call AISmogon_PlayerRevealedMove
	jr c, .player_rests
	ld a, [wPlayerUsedMoves + NUM_MOVES - 1]
	and a
	jr nz, .player_rests
	call AISmogon_GetPlayerTraits
	and SMOGON_REST
	jr z, .player_rests
	scf
.player_rests
	ld a, [hl]
	call .Quarter
.got_player_heal
	call AISmogon_PlayerMaxPP
	ld hl, wSmogonAIPlayerHeal
	call .Store
	ld hl, wSmogonAIPower
	jp AISmogon_SubtractSixteenth

.Store:
; Store the healing bc and PP a at hl.
	ld [hl], b
	inc hl
	ld [hl], c
	inc hl
	ld [hl], a
	ret

.Half:
; bc = de / 2, keeping a and carry
	ld b, d
	ld c, e
	srl b
	rr c
	scf
	ret

.Quarter:
; bc = de / 4 if carry, else 0 (with no PP)
	ld bc, 0
	jr c, .quarter
	xor a
	ret

.quarter
	call .Half
	srl b
	rr c
	ret

AISmogon_OurMovePP:
; Return carry and the current PP of move a in a if wOTPartyMon
; [wSmogonAIMon] knows it.
	push bc
	push de
	push hl
	ld c, a
	ld a, MON_MOVES
	call AISmogon_OTPartyAttr
	ld b, 0
.find_move
	ld a, [hli]
	cp c
	jr z, .found_move
	inc b
	ld a, b
	cp NUM_MOVES
	jr c, .find_move
	; no carry
	jr .done_pp

.found_move
	ld a, [wCurOTMon]
	ld e, a
	ld a, [wSmogonAIMon]
	cp e
	ld hl, wEnemyMonPP
	jr z, .got_pp
	ld a, MON_PP
	call AISmogon_OTPartyAttr
.got_pp
	ld a, b
	add l
	ld l, a
	adc h
	sub l
	ld h, a
	ld a, [hl]
	and PP_MASK
	scf
.done_pp
	pop hl
	pop de
	pop bc
	ret

AISmogon_RecoveryMoves:
; move, base PP (Rest last)
	db RECOVER,     20
	db SOFTBOILED,  10
	db MILK_DRINK,  10
	db MOONLIGHT,    5
	db MORNING_SUN,  5
	db SYNTHESIS,    5
	db REST,        10

AISmogon_HealOutlasts:
; Return carry if the healing per turn at hl is more than the damage per
; turn at de (both words), with PP left. Preserves a.
	push bc
	push hl
	ld b, a
	inc hl
	inc hl
	ld a, [hld]
	and a
	dec hl
	jr z, .done
	ld a, [de]
	cp [hl]
	jr nz, .done
	inc de
	inc hl
	ld a, [de]
	cp [hl]
	dec de
.done
	ld a, b
	pop hl
	pop bc
	ret

AISmogon_SideTurns:
; Return in a how many turns it takes to KO one side, from 1 to
; SMOGON_MAX_TURNS: hl = its healing block (healing, PP, HP), de = the
; damage it takes per turn. A side that outheals the damage lasts until
; its recovery PP runs out: its HP counts each heal it has left.
	assert HEAL_AMOUNT == 0 && HEAL_PP == 2 && HEAL_HP == 3
	push hl
	call AISmogon_HealOutlasts
	jr nc, .no_healing
	xor a
	ldh [hMultiplicand], a
	ld a, [hli]
	ldh [hMultiplicand + 1], a
	ld a, [hli]
	ldh [hMultiplicand + 2], a
	ld a, [hli]
	ldh [hMultiplier], a
	call Multiply
	ld a, [hli]
	ld b, a
	ld c, [hl]
	ldh a, [hProduct + 3]
	add c
	ld c, a
	ldh a, [hProduct + 2]
	adc b
	ld b, a
	jr .got_hp

.no_healing
	inc hl
	inc hl
	inc hl
	ld a, [hli]
	ld b, a
	ld c, [hl]
.got_hp
	ld h, d
	ld l, e
	ld d, b
	ld e, c
	call AISmogon_TurnsWithPP
	pop hl
	ret

AISmogon_HealDelay:
; a = turns to KO the other side; hl = this side's healing block, de = the
; damage it takes per turn. If it outheals the damage, it spends some turns
; healing instead of attacking: return the lesser of a * healing /
; (healing - damage) and a + its recovery PP, at most SMOGON_MAX_TURNS.
	call AISmogon_HealOutlasts
	ret nc
	push bc
	push de
	push hl
	push af
	ld c, a
	xor a
	ldh [hMultiplicand], a
	ld a, [hli]
	ldh [hMultiplicand + 1], a
	ld a, [hl]
	ldh [hMultiplicand + 2], a
	ld a, c
	ldh [hMultiplier], a
	call Multiply
	; de = healing - damage
	ld a, [hld]
	ld c, a
	inc de
	ld a, [de]
	ld b, a
	ld a, c
	sub b
	ld c, a
	dec de
	ld a, [de]
	ld b, a
	ld a, [hl]
	sbc b
	ld d, a
	ld e, c
	ldh a, [hProduct + 1]
	ldh [hMathBuffer + 1], a
	ldh a, [hProduct + 2]
	ldh [hMathBuffer + 2], a
	ldh a, [hProduct + 3]
	ldh [hMathBuffer + 3], a
	call AISmogon_Divide24
	ld a, h
	and a
	ld a, $ff
	jr nz, .got_slowed
	ld a, l
.got_slowed
	ld e, a
	pop af
	pop hl
	push hl
	inc hl
	inc hl
	add [hl]
	cp e
	jr c, .got_turns
	ld a, e
.got_turns
	cp SMOGON_MAX_TURNS + 1
	jr c, .done
	ld a, SMOGON_MAX_TURNS
.done
	pop hl
	pop de
	pop bc
	ret

AISmogon_StartAttacks:
; Start a new attack list at hl (ATTACKS_*) for AISmogon_AttackDamage.
	ld a, l
	ld [wSmogonAIAttacks], a
	ld a, h
	ld [wSmogonAIAttacks + 1], a
	assert ATTACKS_BEST == 0 && ATTACKS_COUNT == 2
	xor a
	ld [hli], a
	ld [hli], a
	ld [hl], a
	ret

AISmogon_AddAttack:
; Add damage de with b PP to the current attack list, and keep the best
; damage. An attack doing the same damage as one already there (the same
; move, expected and revealed) only keeps the higher PP.
	ld a, [wSmogonAIAttacks]
	ld l, a
	ld a, [wSmogonAIAttacks + 1]
	ld h, a
	ld a, [hli]
	cp d
	jr c, .new_best
	jr nz, .not_best
	ld a, [hl]
	cp e
	jr nc, .not_best
.new_best
	ld a, e
	ld [hld], a
	ld [hl], d
	inc hl
.not_best
	inc hl
	assert ATTACKS_LIST == ATTACKS_COUNT + 1
	; c = count, hl = the list
	ld c, [hl]
	push hl
	inc hl
	ld a, c
	and a
	jr z, .append
.find
	ld a, [hli]
	cp d
	jr nz, .next
	ld a, [hl]
	cp e
	jr nz, .next
	inc hl
	ld a, [hl]
	cp b
	jr nc, .done
	ld [hl], b
	jr .done

.next
	inc hl
	inc hl
	dec c
	jr nz, .find
.append
; hl points past the list
	pop hl
	push hl
	ld a, [hl]
	cp SMOGON_MAX_ATTACKS
	jr nc, .done
	inc [hl]
	; hl += 1 + 3 * count
	ld c, a
	add a
	add c
	inc a
	add l
	ld l, a
	adc h
	sub l
	ld h, a
	ld [hl], d
	inc hl
	ld [hl], e
	inc hl
	ld [hl], b
.done
	pop hl
	ret

AISmogon_ForEachDamage:
; Call the routine at bc with hl pointing to each damage word of the attack
; list at hl: the best damage, then each attack's. The routine keeps bc.
	push hl
	call .Call
	pop hl
	inc hl
	inc hl
	ld a, [hli]
	and a
	ret z
.loop
	push af
	push hl
	call .Call
	pop hl
	pop af
	inc hl
	inc hl
	inc hl
	dec a
	jr nz, .loop
	ret

.Call:
	push bc
	ret

AISmogon_ScaleAttacks:
; Scale every damage in the attack list at hl to half, or 3/4 if c is TRUE.
	ld a, c
	and a
	ld bc, .Half
	jr z, AISmogon_ForEachDamage
	ld bc, .ThreeQuarters
	jr AISmogon_ForEachDamage

.Half:
	ld a, [hl]
	srl a
	ld [hli], a
	ld a, [hl]
	rra
	ld [hl], a
	ret

.ThreeQuarters:
	ld a, [hli]
	ld d, a
	ld e, [hl]
	srl d
	rr e
	srl d
	rr e
	ld a, [hl]
	sub e
	ld [hld], a
	ld a, [hl]
	sbc d
	ld [hl], a
	ret

AISmogon_SubtractSixteenth:
; Subtract de / 16 (Leftovers) from every damage in the attack list at hl,
; down to 0.
	push de
	srl d
	rr e
	srl d
	rr e
	srl d
	rr e
	srl d
	rr e
	ld a, d
	ld [wSmogonAIMovePP], a
	ld a, e
	ld [wSmogonAIMovePP + 1], a
	ld bc, .Subtract
	call AISmogon_ForEachDamage
	pop de
	ret

.Subtract:
	inc hl
	ld a, [wSmogonAIMovePP + 1]
	ld e, a
	ld a, [hl]
	sub e
	ld [hld], a
	ld a, [wSmogonAIMovePP]
	ld d, a
	ld a, [hl]
	sbc d
	ld [hl], a
	ret nc
	xor a
	ld [hli], a
	ld [hl], a
	ret

AISmogon_BasePP:
; Return the base PP of move a.
	push bc
	push hl
	ld hl, Moves + MOVE_PP - MOVE_LENGTH
	ld bc, MOVE_LENGTH
	call AddNTimes
	ld a, BANK(Moves)
	call GetFarByte
	pop hl
	pop bc
	ret

AISmogon_CountPlayerPPUps:
; Store in wSmogonAIPlayerPPUps the PP Ups per move across the player's
; party, rounded: the AI can tell how much the player uses PP Ups, but not
; on which Pokemon. Also store the PP of the player's unrevealed attacks
; (SMOGON_UNKNOWN_BASE_PP with those PP Ups) in wSmogonAIUnknownPP.
	push bc
	push de
	push hl
	ld hl, wPartyMon1Moves
	ld a, [wPartyCount]
	ld b, a
	; d = moves, e = PP Ups
	ld de, 0
.mon
	ld a, b
	and a
	jr z, .average
	push hl
	ld c, NUM_MOVES
.move
	ld a, [hl]
	and a
	jr z, .next_move
	inc d
	push hl
	ld a, l
	add MON_PP - MON_MOVES
	ld l, a
	adc h
	sub l
	ld h, a
	ld a, [hl]
	rlca
	rlca
	and %11
	add e
	ld e, a
	pop hl
.next_move
	inc hl
	dec c
	jr nz, .move
	pop hl
	push bc
	ld bc, PARTYMON_STRUCT_LENGTH
	add hl, bc
	pop bc
	dec b
	jr .mon

.average
; (PP Ups + moves / 2) / moves
	ld a, d
	and a
	jr z, .got_average
	srl a
	add e
	ld c, -1
.divide
	inc c
	sub d
	jr nc, .divide
	ld a, c
.got_average
	ld [wSmogonAIPlayerPPUps], a
	ld a, SMOGON_UNKNOWN_BASE_PP
	call AISmogon_PlayerMaxPP
	ld [wSmogonAIUnknownPP], a
	pop hl
	pop de
	pop bc
	ret

AISmogon_PlayerMaxPP:
; Return the PP of a move of the player's with base PP a, with
; wSmogonAIPlayerPPUps PP Ups: each adds a fifth of the base PP, at most 7.
; Keeps bc and de.
	push bc
	push de
	ld b, a
	ld c, -1
.divide_by_5
	inc c
	sub 5
	jr nc, .divide_by_5
	ld a, c
	cp 7
	jr c, .got_boost
	ld a, 7
.got_boost
	ld c, a
	ld a, [wSmogonAIPlayerPPUps]
	ld d, a
	ld a, b
	inc d
.add_boost
	dec d
	jr z, .done
	add c
	jr .add_boost

.done
	pop de
	pop bc
	ret

AISmogon_TurnsWithPP:
; Return in a how many turns the attacker with the attack list at hl takes
; to KO a side with de HP, from 1 to SMOGON_MAX_TURNS. It uses its strongest
; attack until its PP runs out, then the next; if all of them together
; can't do it, the side can't be KOed.
	ld a, d
	ld [wSmogonAIRemaining], a
	ld a, e
	ld [wSmogonAIRemaining + 1], a
	xor a
	ld [wSmogonAITurns], a
	inc hl
	inc hl
	ld b, [hl]
	inc hl
	; c = the attacks still unused (a bit each)
	ld c, $ff
.round
; Find the strongest unused attack with PP: its address goes in
; hMathBuffer + 3 (high) and + 4 (low).
	push bc
	push hl
	xor a
	ldh [hMathBuffer + 3], a
	ld d, a
	ld e, a
	inc b
.find
	dec b
	jr z, .found
	srl c
	jr nc, .skip
	inc hl
	inc hl
	ld a, [hld]
	dec hl
	and a
	jr z, .skip
	ld a, [hli]
	cp d
	jr c, .skip_dec
	jr nz, .stronger
	ld a, [hl]
	cp e
	jr c, .skip_dec
	jr z, .skip_dec
.stronger
	ld e, [hl]
	dec hl
	ld d, [hl]
	ld a, l
	ldh [hMathBuffer + 4], a
	ld a, h
	ldh [hMathBuffer + 3], a
	jr .skip

.skip_dec
	dec hl
.skip
	inc hl
	inc hl
	inc hl
	jr .find

.found
	pop hl
	pop bc
	; none left?
	ldh a, [hMathBuffer + 3]
	and a
	jp z, .max
; Mark it used: bit (its address - hl) / 3 of c.
	push hl
	ldh a, [hMathBuffer + 4]
	sub l
	ld l, a
	ld a, 1
.bit
	dec l
	dec l
	dec l
	bit 7, l
	jr nz, .got_bit
	add a
	jr .bit

.got_bit
	cpl
	and c
	ld c, a
	; its PP
	ldh a, [hMathBuffer + 4]
	ld l, a
	ldh a, [hMathBuffer + 3]
	ld h, a
	inc hl
	inc hl
	ld a, [hl]
	pop hl
	push bc
	push hl
	ld b, a
; hits needed = ceil(remaining / damage)
	ld a, [wSmogonAIRemaining]
	ld h, a
	ld a, [wSmogonAIRemaining + 1]
	ld l, a
	dec de
	add hl, de
	inc de
	xor a
	ldh [hMathBuffer + 1], a
	ld a, h
	ldh [hMathBuffer + 2], a
	ld a, l
	ldh [hMathBuffer + 3], a
	push bc
	call AISmogon_Divide24
	pop bc
	ld a, h
	and a
	jr nz, .use_all_pp
	ld a, b
	cp l
	jr nc, .enough
.use_all_pp
; Use all its PP: turns += PP, remaining -= PP * damage.
	ld a, b
	ldh [hMultiplier], a
	xor a
	ldh [hMultiplicand], a
	ld a, d
	ldh [hMultiplicand + 1], a
	ld a, e
	ldh [hMultiplicand + 2], a
	call Multiply
	ldh a, [hProduct + 3]
	ld e, a
	ld a, [wSmogonAIRemaining + 1]
	sub e
	ld [wSmogonAIRemaining + 1], a
	ldh a, [hProduct + 2]
	ld e, a
	ld a, [wSmogonAIRemaining]
	sbc e
	ld [wSmogonAIRemaining], a
	ld a, [wSmogonAITurns]
	add b
	ld [wSmogonAITurns], a
	pop hl
	pop bc
	cp SMOGON_MAX_TURNS
	jr nc, .max
	jp .round

.enough
	ld a, [wSmogonAITurns]
	add l
	pop hl
	pop bc
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
; side's screens. Store what AISmogon_AttackDamage needs.
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
; Estimate the damage of an attack of type a and power d with b PP, with
; STAB if c is nonzero, using AISmogon_SetupDamage and
; AISmogon_FillTypeMatchups, and add it to the attack list from
; AISmogon_StartAttacks.
; Fixed-damage moves like Seismic Toss (power 1) do the attacker's level.
; The random factor, critical hits and accuracy are left out.
	push bc
	push de
	push hl
	ld e, a
	ld a, b
	ld [wSmogonAIMovePP], a
	ld a, e
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
	ld a, h
	or l
	jr z, .done
	ld d, h
	ld e, l
	ld a, [wSmogonAIMovePP]
	ld b, a
	call AISmogon_AddAttack
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
