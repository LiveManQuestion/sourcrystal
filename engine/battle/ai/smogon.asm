AI_Smogon:
; Play like a GSC OU (Smogon) player.
; - Follow the GSC OU clauses: Sleep Clause, OHKO Clause, Evasion Clause and
;   SleepTrap Clause (no sleep move together with Mean Look or Spider Web).
; - Follow standard GSC OU strategy: lead with sleep, lay Spikes and phaze
;   into them, spin Spikes away, stop setup sweepers with phazing, Haze,
;   Growl or Charm, set up only when it's safe (a sleeping Pokemon with Sleep
;   Talk can still punish it), paralyze for slow teammates, don't Mean Look a
;   phazer, heal before falling into KO range, trade
;   Explosion for a healthy threat, steal Leftovers with Thief, Toxic walls
;   that can't Rest it off (especially into Spikes), Pursuit fleeing Ghosts
;   and Psychics, put up the screen that blocks the player's attacks, Baton
;   Pass boosts out of trouble, Encore a setup or status move, Heal Bell
;   a team weighed down by status, Protect to stall out the player's
;   residual damage, take a sure KO with the surest attack, don't start
;   rain or sun that powers up the player's attacks too, and use Sleep Talk
;   while asleep.
; - Know the battle mechanics: Thunder never misses in rain, Defense Curl
;   doubles Rollout, attacks miss a Pokemon in the air or underground, Endure
;   doesn't stop residual damage, and Morning Sun, Synthesis and Moonlight
;   heal by time of day and weather.
; Only uses information a human player could have: the player's active
; Pokemon, its types, stats, HP, status and stat changes, the moves it has
; revealed since it came in, and how that species is usually played in GSC OU
; (SmogonTraits) for moves it hasn't revealed yet. Matchups are judged from
; types, stats and moves (see smogon_switch.asm), so they hold up against
; Pokemon that never see OU play too.
; Only active in Challenge Mode.

	ld a, [wChallengeMode]
	bit GAME_CHALLENGE_MODE_F, a
	ret z

	ld hl, wEnemyAIMoveScores
	ld de, wEnemyMonMoves
	ld b, NUM_MOVES + 1
.checkmove
	dec b
	jr z, .done

	ld a, [de]
	inc de
	and a
	jr z, .done

	push de
	push bc
	push hl
	call AIGetEnemyMove

	call AISmogon_MissesHiddenPlayer
	jr nc, .not_hidden
	pop hl
	push hl
	call AIDiscourageMove
	jr .nextmove

.not_hidden
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

.done
	call AI_Smogon_Asleep
	jp AI_Smogon_SureKO

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
	dbw EFFECT_PROTECT,      AI_Smogon_Protect
	dbw EFFECT_SUBSTITUTE,   AI_Smogon_Substitute
	dbw EFFECT_CURSE,        AI_Smogon_Setup
	dbw EFFECT_ATTACK_UP_2,  AI_Smogon_Setup ; Swords Dance
	dbw EFFECT_SP_ATK_UP,     AI_Smogon_Setup ; Growth
	dbw EFFECT_DEFENSE_UP_2, AI_Smogon_Setup ; Acid Armor, Barrier
	dbw EFFECT_SP_DEF_UP_2,  AI_Smogon_Setup ; Amnesia
	dbw EFFECT_SPEED_UP_2,   AI_Smogon_Setup ; Agility
	dbw EFFECT_BELLY_DRUM,   AI_Smogon_Setup
	dbw EFFECT_REFLECT,      AI_Smogon_Screens
	dbw EFFECT_LIGHT_SCREEN, AI_Smogon_Screens
	dbw EFFECT_BATON_PASS,   AI_Smogon_BatonPass
	dbw EFFECT_ENCORE,       AI_Smogon_Encore
	dbw EFFECT_HEAL_BELL,    AI_Smogon_HealBell
	dbw EFFECT_COUNTER,      AI_Smogon_Counter
	dbw EFFECT_MIRROR_COAT,  AI_Smogon_Counter
	dbw EFFECT_THUNDER,      AI_Smogon_Thunder
	dbw EFFECT_RAIN_DANCE,   AI_Smogon_Weather
	dbw EFFECT_SUNNY_DAY,    AI_Smogon_Weather
	dbw EFFECT_ROLLOUT,      AI_Smogon_Rollout
	dbw EFFECT_ENDURE,       AI_Smogon_Endure
	dbw EFFECT_DESTINY_BOND, AI_Smogon_DestinyBond
	dbw EFFECT_ATTACK_DOWN,  AI_Smogon_AttackDown ; Growl
	dbw EFFECT_ATTACK_DOWN_2, AI_Smogon_AttackDown ; Charm
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
; Trapping doesn't stop the player from phazing us out, which ends the trap.
	call AISmogon_PlayerCanPhaze
	ret nc
	inc [hl]
	inc [hl]
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
	jr z, .nothing_to_spin
	push hl
	farcall FindAliveEnemyMons
	pop hl
	ret c
	jr AISmogon_Encourage

.nothing_to_spin
; With no Spikes, Leech Seed or Bind to clear, it's a weak 20 power attack.
	ld a, [wEnemyWrapCount]
	and a
	ret nz
	ld a, [wEnemySubStatus4]
	bit SUBSTATUS_LEECH_SEED, a
	ret nz
	inc [hl]
	ret

AI_Smogon_Phaze:
; Roar and Whirlwind fail against a last Pokemon.
	call AISmogon_ScanPlayerParty
	ld a, c
	and a
	jp z, AIDiscourageMove
; A sleeping (without Sleep Talk) or frozen Pokemon is a sitting duck:
; phazing it out would only bring in something that can fight back. Unless
; it has boosted.
	call AISmogon_PlayerCantAttack
	jr z, .awake
	call AISmogon_PlayerBoosted
	jr c, AISmogon_GreatlyEncourage
	inc [hl]
	ret

.awake
; Roar and Whirlwind go after other moves, and fail if the user moves first.
; Against a phazer we outspeed, ours goes first and fails, and theirs
; succeeds. Unless the player has boosted, and won't phaze away its boosts.
	call AISmogon_PlayerBoosted
	jr c, .no_phazing_war
	call AICompareSpeed
	jr nc, .no_phazing_war
	call AISmogon_PlayerPhazes
	jr nc, .no_phazing_war
	inc [hl]
	inc [hl]
	ret

.no_phazing_war
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
; Morning Sun, Synthesis and Moonlight vary: not worth a turn for 1/8 of max HP,
; and mostly left to AI_Smart (heal below a quarter) for 1/4.
	ld a, [wEnemyMoveStruct + MOVE_EFFECT]
	cp EFFECT_HEAL
	jr z, .heal
	call AISmogon_TimeBasedHealAmount
	and a
	jp z, AIDiscourageMove
	dec a
	jr z, .quarter
.heal
; Heal before falling into KO range, at half HP rather than a quarter...
	call AICheckEnemyHalfHP
	jr c, .above_half
; ...unless the player's attacks barely scratch us, or we KO it first:
; then attacking is worth more, like Blissey finishing a weakened Cloyster.
	call AISmogon_HealCanWait
	jp nc, AISmogon_Encourage
	inc [hl]
	ret

.quarter
; A quarter of max HP is only worth a turn when the player is about to KO
; us (AI_Smart encourages it below a quarter).
	call AISmogon_HealCanWait
	ret nc
	inc [hl]
	ret

.above_half
; Rest also cures status, so use it earlier when statused.
	ld a, [wEnemyMoveStruct + MOVE_ANIM]
	cp REST
	ret nz
	ld a, [wEnemyMonStatus]
	and a
	ret z
	dec [hl]
	ret

AISmogon_HealCanWait:
; Return carry if the enemy can put off healing: SMOGON_HEAL_SAFE_HITS of
; the player's strongest attack (AISmogon_ScoreMatchup's estimate, from
; what the player could have) don't KO it, or it KOs the player first in
; two hits (Venusaur after Growth against a Vaporeon), and nothing hurts it
; every turn (status, Leech Seed or Curse, which the estimate leaves out).
	ld a, [wEnemyMonStatus]
	and a
	ret nz
	ld a, [wEnemySubStatus4]
	bit SUBSTATUS_LEECH_SEED, a
	ret nz
	ld a, [wEnemySubStatus1]
	bit SUBSTATUS_CURSE, a
	ret nz
	push hl
	call AISmogon_ScoreActive
	ld b, SMOGON_HEAL_SAFE_HITS
	call .HitsLeaveHP
	jr c, .done
	call AISmogon_KOsInTwoHits
	jr nc, .done
; The player gets one hit in before our second, or two if it's faster.
	ld b, 1
	call AICompareSpeed
	jr c, .got_hits
	inc b
.got_hits
	call .HitsLeaveHP
.done
	pop hl
	ret

.HitsLeaveHP:
; Return carry if b of the player's strongest attack don't KO the enemy.
	ld a, [wSmogonAIThreat + ATTACKS_BEST]
	ld d, a
	ld a, [wSmogonAIThreat + ATTACKS_BEST + 1]
	ld e, a
	ld hl, 0
.add_hit
	add hl, de
	dec b
	jr nz, .add_hit
; carry if hl < HP
	ld a, [wEnemyMonHP + 1]
	ld e, a
	ld a, [wEnemyMonHP]
	ld d, a
	ld a, l
	sub e
	ld a, h
	sbc d
	ret

AISmogon_KOsInTwoHits:
; Return carry if one of the enemy's attacks with PP left surely KOs the
; player in two hits (AISmogon_RankLoadedMove against half its HP). Keeps
; wEnemyMoveStruct, which holds the move being scored.
	ld hl, wEnemyMoveStruct + MOVE_LENGTH - 1
	ld c, MOVE_LENGTH
.save
	ld a, [hld]
	push af
	dec c
	jr nz, .save
; Halve the player's HP, rounding up.
	ld hl, wBattleMonHP
	ld a, [hli]
	ld d, a
	ld e, [hl]
	push de
	srl d
	rr e
	jr nc, .halved
	inc de
.halved
	ld a, e
	ld [hld], a
	ld [hl], d

	ld b, FALSE
	ld c, NUM_MOVES
	ld hl, wEnemyMonMoves
	ld de, wEnemyMonPP
.loop
	ld a, [de]
	inc de
	and PP_MASK
	ld a, [hli]
	jr z, .next
	and a
	jr z, .next
	push bc
	push de
	push hl
	call AIGetEnemyMove
	call AISmogon_RankLoadedMove
	pop hl
	pop de
	pop bc
	and a
	jr z, .next
	ld b, TRUE
.next
	dec c
	jr nz, .loop

	pop de
	ld hl, wBattleMonHP
	ld a, d
	ld [hli], a
	ld [hl], e
	ld hl, wEnemyMoveStruct
	ld c, MOVE_LENGTH
.restore
	pop af
	ld [hli], a
	dec c
	jr nz, .restore
	ld a, b
	and a
	ret z
	scf
	ret

AISmogon_TimeBasedHealAmount:
; Return in a how much the enemy's Morning Sun, Synthesis or Moonlight (effect
; a) heals, like BattleCommand_TimeBasedHealContinue: 0 for 1/8 of max HP,
; 1 for 1/4, 2 for 1/2 and 3 for all of it.
	ld b, MORN_F
	cp EFFECT_MORNING_SUN
	jr z, .got_move_time
	ld b, DAY_F
	cp EFFECT_SYNTHESIS
	jr z, .got_move_time
	ld b, NITE_F
.got_move_time
	ld c, 2
; Evening isn't in the original game: it was day until 6 PM, then night.
	ld a, [wTimeOfDay]
	cp EVE_F
	jr nz, .got_time_of_day
	ldh a, [hHours]
	cp VANILLA_NITE_HOUR
	ld a, DAY_F
	jr c, .got_time_of_day
	ld a, NITE_F
.got_time_of_day
	cp b
	jr z, .weather
	dec c
.weather
; Doubled in sun, halved in rain or Sandstorm.
	ld a, [wBattleWeather]
	and a
	jr z, .done
	inc c
	cp WEATHER_SUN
	jr z, .done
	dec c
	dec c
.done
	ld a, c
	ret

AI_Smogon_Thunder:
; Thunder never misses in rain.
	ld a, [wBattleWeather]
	cp WEATHER_RAIN
	ret nz
	call AISmogon_IsResisted
	ret c
	jp AISmogon_Encourage

AI_Smogon_Asleep:
; Fast asleep (it won't wake up this turn), only Sleep Talk and Snore do
; anything: with one of them, discourage every other move (Kingdra kept
; picking Rest or Surf). Awake, they fail: discourage them (AI_Smart
; encourages Sleep Talk unless the Pokemon wakes up this turn). On the turn
; it wakes up, nothing works.
	ld a, [wEnemyMonStatus]
	and SLP_MASK
	jr z, .awake
	cp 2
	ret c

	ld c, 0
.find_loop
	call .SleepMove
	jr c, .found
	inc c
	ld a, c
	cp NUM_MOVES
	jr c, .find_loop
	ret

.found
	ld c, 0
.asleep_loop
	call .SleepMove
	call nc, .Discourage
	inc c
	ld a, c
	cp NUM_MOVES
	jr c, .asleep_loop
	ret

.awake
	ld c, 0
.awake_loop
	call .SleepMove
	call c, .Discourage
	inc c
	ld a, c
	cp NUM_MOVES
	jr c, .awake_loop
	ret

.Discourage:
; Discourage move c. Keeps bc.
	ld hl, wEnemyAIMoveScores
	ld b, 0
	add hl, bc
	jp AIDiscourageMove

.SleepMove:
; Return carry if move c is a usable Sleep Talk or Snore. Keeps bc.
	push bc
	ld b, 0
	ld hl, wEnemyAIMoveScores
	add hl, bc
	ld a, [hl]
	cp 80 ; disabled or out of PP
	jr nc, .no
	ld hl, wEnemyMonMoves
	add hl, bc
	ld a, [hl]
	and a
	jr z, .no
	call AIGetEnemyMove
	ld a, [wEnemyMoveStruct + MOVE_EFFECT]
	cp EFFECT_SLEEP_TALK
	jr z, .yes
	cp EFFECT_SNORE
	jr z, .yes
.no
	pop bc
	and a
	ret

.yes
	pop bc
	scf
	ret

AI_Smogon_SureKO:
; Take a sure KO with the surest attack: of the attacks whose lowest damage
; roll KOs the player, encourage the most accurate one (a priority attack
; first when the player is faster) and discourage the rest. The damage
; layers (AI_Aggressive, AI_Risky) only look at the highest roll and ignore
; accuracy, so they used Fire Blast over Ice Beam on a Steelix with 2 HP.
	ld c, 0
.rank_loop
	push bc
	call .Rank
	pop bc
	ld hl, wSmogonAIKORanks
	ld b, 0
	add hl, bc
	ld [hl], a
	inc c
	ld a, c
	cp NUM_MOVES
	jr c, .rank_loop

; b = the best rank
	ld hl, wSmogonAIKORanks
	ld bc, NUM_MOVES
.best_loop
	ld a, [hli]
	cp b
	jr c, .not_better
	ld b, a
.not_better
	dec c
	jr nz, .best_loop
	ld a, b
	and a
	ret z

	ld hl, wEnemyAIMoveScores
	ld de, wSmogonAIKORanks
	ld c, NUM_MOVES
.score_loop
	ld a, [de]
	inc de
	and a
	jr z, .next
	cp b
	jr z, .surest
	inc [hl]
	inc [hl]
	jr .next
.surest
	call AISmogon_GreatlyEncourage
.next
	inc hl
	dec c
	jr nz, .score_loop
	ret

.Rank:
; Return in a the rank of move c (AISmogon_RankLoadedMove).
	ld b, 0
	ld hl, wEnemyAIMoveScores
	add hl, bc
	ld a, [hl]
	cp 80 ; disabled or out of PP
	jr nc, .not_ko
	ld hl, wEnemyMonMoves
	add hl, bc
	ld a, [hl]
	and a
	jr z, .not_ko
	call AIGetEnemyMove
	jp AISmogon_RankLoadedMove

.not_ko
	xor a
	ret

AISmogon_LoadedMoveKOs:
; Return carry if the lowest damage roll of the move in wEnemyMoveStruct
; KOs the player: 27/32 of AIDamageCalc's highest (the lowest is 217/255,
; 85%). wCriticalHit is still set if the last attack was a critical hit,
; and AIDamageCalc would double the damage: count a regular hit. Keeps
; wCurDamage (Counter and Mirror Coat read it) and wCriticalHit.
	ld a, [wCurDamage]
	ld h, a
	ld a, [wCurDamage + 1]
	ld l, a
	push hl
	ld a, [wCriticalHit]
	push af
	xor a
	ld [wCriticalHit], a
	call .KOs
	sbc a
	ld b, a
	pop af
	ld [wCriticalHit], a
	pop hl
	ld a, h
	ld [wCurDamage], a
	ld a, l
	ld [wCurDamage + 1], a
	ld a, b
	add a ; carry if b is $ff
	ret

.KOs:
	call AIDamageCalc
	ld a, [wCurDamage]
	ld h, a
	ld d, a
	ld a, [wCurDamage + 1]
	ld l, a
	ld e, a
rept 3
	srl d
	rr e
endr
	call .Subtract
rept 2
	srl d
	rr e
endr
	call .Subtract
	ld a, [wBattleMonHP + 1]
	ld e, a
	ld a, [wBattleMonHP]
	ld d, a
	ld a, l
	sub e
	ld a, h
	sbc d
	ccf
	ret

.Subtract:
; hl -= de
	ld a, l
	sub e
	ld l, a
	ld a, h
	sbc d
	ld h, a
	ret

AISmogon_PickedMoveKOsFirst:
; Return carry if the move the enemy is about to use (wCurEnemyMove) is a
; sure KO that lands before the player moves: the enemy is faster, or the
; move has priority. Keeps wEnemyMoveStruct, which the battle has loaded.
	ld a, [wCurEnemyMove]
	and a
	ret z
	ld hl, wEnemyMoveStruct + MOVE_LENGTH - 1
	ld c, MOVE_LENGTH
.save
	ld a, [hld]
	push af
	dec c
	jr nz, .save
	ld a, [wCurEnemyMove]
	call AIGetEnemyMove
	call AISmogon_RankLoadedMove
	ld b, a
	ld hl, wEnemyMoveStruct
	ld c, MOVE_LENGTH
.restore
	pop af
	ld [hli], a
	dec c
	jr nz, .restore
	ld a, b
	and a
	ret z
	bit 7, a
	scf
	ret nz
	jp AICompareSpeed

AISmogon_RankLoadedMove:
; Return in a the rank of the move in wEnemyMoveStruct as a sure KO: 0 if
; its lowest damage roll doesn't KO the player (or a Substitute would take
; it, or the enemy is asleep or frozen and can't attack, so Sleep Talk
; keeps its turn), else its accuracy / 4 + 1 (at most 64), plus $80 for a
; priority attack when the player is faster. Keeps wCurDamage and
; wCriticalHit.
	ld a, [wPlayerSubStatus4]
	bit SUBSTATUS_SUBSTITUTE, a
	jr nz, .not_ko
	ld a, [wEnemyMonStatus]
	and SLP_MASK | 1 << FRZ
	jr nz, .not_ko
	ld a, [wEnemyMoveStruct + MOVE_POWER]
	and a
	jr z, .not_ko
	ld a, [wEnemyMoveStruct + MOVE_EFFECT]
	ld hl, .NotSureKOEffects
	ld de, 1
	call IsInArray
	jr c, .not_ko
	call AISmogon_MissesHiddenPlayer
	jr c, .not_ko

	call AISmogon_LoadedMoveKOs
	jr nc, .not_ko

; Lock-On makes the next attack hit, and so does Thunder in rain.
	ld a, [wEnemySubStatus5]
	bit SUBSTATUS_LOCK_ON, a
	ld a, 100 percent
	jr nz, .got_accuracy
	ld a, [wEnemyMoveStruct + MOVE_EFFECT]
	cp EFFECT_THUNDER
	jr nz, .accuracy
	ld a, [wBattleWeather]
	cp WEATHER_RAIN
	ld a, 100 percent
	jr z, .got_accuracy
.accuracy
	ld a, [wEnemyMoveStruct + MOVE_ACC]
.got_accuracy
	srl a
	srl a
	inc a
	ld b, a
	ld a, [wEnemyMoveStruct + MOVE_EFFECT]
	cp EFFECT_PRIORITY_HIT
	jr nz, .no_priority
	call AICompareSpeed
	jr c, .no_priority
	set 7, b
.no_priority
	ld a, b
	ret

.not_ko
	xor a
	ret

.NotSureKOEffects:
; Attacks that need a charging or recharge turn, lock the user in, or
; whose damage is random or depends on the player's state. Explosion is
; AI_Smogon_Explosion's call.
	db EFFECT_SELFDESTRUCT
	db EFFECT_OHKO
	db EFFECT_HYPER_BEAM
	db EFFECT_RAZOR_WIND
	db EFFECT_SKY_ATTACK
	db EFFECT_SKULL_BASH
	db EFFECT_SOLARBEAM
	db EFFECT_FLY
	db EFFECT_RAMPAGE
	db EFFECT_ROLLOUT
	db EFFECT_BIDE
	db EFFECT_DREAM_EATER
	db EFFECT_SNORE
	db EFFECT_FALSE_SWIPE
	db EFFECT_FUTURE_SIGHT
	db EFFECT_PSYWAVE
	db EFFECT_PRESENT
	db EFFECT_MAGNITUDE
	db EFFECT_COUNTER
	db EFFECT_MIRROR_COAT
	db EFFECT_SUPER_FANG
	db -1 ; end

AI_Smogon_Weather:
; Rain makes Thunder hit and powers up Water attacks; sun powers up Fire
; attacks and lets SolarBeam fire at once; for both sides. Don't start
; weather the player's Pokemon would use too (Magneton's Rain Dance gave
; Zapdos a sure Thunder): by the attacks it has revealed (AI_Smart's
; RainDanceMoves and SunnyDayMoves), or, until it has revealed four moves,
; the ones its species usually has (SmogonExpectedAttacks): Water or a
; 120-power Electric attack (Thunder) for rain, Fire or a 120-power Grass
; attack (SolarBeam) for sun. A species without that list counts its types.
	push hl
	ld a, [wEnemyMoveStruct + MOVE_EFFECT]
	cp EFFECT_RAIN_DANCE
	ld hl, RainDanceMoves
	lb bc, WATER, ELECTRIC
	jr z, .got_weather
	ld hl, SunnyDayMoves
	lb bc, FIRE, GRASS
.got_weather
; b = the type it powers up, d = the type whose 120-power attack needs it
	ld d, c
.revealed_loop
	ld a, [hli]
	cp -1
	jr z, .expected
	call AISmogon_PlayerRevealedMove
	jr nc, .revealed_loop
	jr .helps_player

.expected
	ld a, [wPlayerUsedMoves + NUM_MOVES - 1]
	and a
	jr nz, .done
	call AISmogon_FindExpectedAttacks
	jr nc, .player_types
.expected_loop
	ld a, [hli]
	cp -1
	jr z, .done
	ld e, a
	ld a, [hli]
	ld c, a
	ld a, e
	cp b
	jr z, .helps_player
	cp d
	jr nz, .expected_loop
	ld a, c
	cp 120
	jr z, .helps_player
	jr .expected_loop

.player_types
	ld a, [wBattleMonType1]
	cp b
	jr z, .helps_player
	cp d
	jr z, .helps_player
	ld a, [wBattleMonType2]
	cp b
	jr z, .helps_player
	cp d
	jr z, .helps_player
.done
	pop hl
	ret

.helps_player
	pop hl
	jp AIBadWeatherType

AI_Smogon_Rollout:
; Defense Curl doubles Rollout's power.
	ld a, [wEnemySubStatus2]
	bit SUBSTATUS_CURLED, a
	ret z
	call AISmogon_IsResisted
	ret c
	jp AISmogon_Encourage

AI_Smogon_Endure:
; Endure only keeps 1 HP against attacks. It goes first, so our poison, burn,
; Leech Seed and Curse damage comes right after it, before the player attacks;
; Sandstorm, trapping moves and Perish Song come at the end of the turn,
; before Leftovers. Don't Endure if any of them knocks us out anyway.
	ld a, [wBattleWeather]
	cp WEATHER_SANDSTORM
	jr nz, .no_sand
	ld a, [wEnemyMonType1]
	call AISmogon_SandstormImmune
	jr z, .no_sand
	ld a, [wEnemyMonType2]
	call AISmogon_SandstormImmune
	jp nz, AIDiscourageMove
.no_sand
; A trapping move hurts unless it ends this turn or we're behind a Substitute.
	ld a, [wEnemyWrapCount]
	cp 2
	jr c, .not_trapped
	ld a, [wEnemySubStatus4]
	bit SUBSTATUS_SUBSTITUTE, a
	jp z, AIDiscourageMove
.not_trapped
	ld a, [wEnemySubStatus1]
	bit SUBSTATUS_PERISH, a
	jr z, .no_perish
	ld a, [wEnemyPerishCount]
	cp 1
	jp z, AIDiscourageMove
.no_perish

; Add up the damage that comes right after Endure, like ResidualDamage.
	push hl
	ld de, 0
	ld a, [wEnemyMonStatus]
	and 1 << PSN | 1 << BRN
	jr z, .no_psn_brn
	ld a, [wEnemySubStatus5]
	bit SUBSTATUS_TOXIC, a
	jr nz, .toxic
; Poison and burn: 1/8 of max HP.
	ld a, 3
	call .AddMaxHPFraction
	jr .no_psn_brn

.toxic
	ld a, [wEnemyToxicCount]
	inc a
.toxic_loop
	push af
; Toxic: 1/16 of max HP per count.
	ld a, 4
	call .AddMaxHPFraction
	pop af
	dec a
	jr nz, .toxic_loop
.no_psn_brn
	ld a, [wEnemySubStatus4]
; Leech Seed: 1/8 of max HP.
	bit SUBSTATUS_LEECH_SEED, a
	ld a, 3
	call nz, .AddMaxHPFraction
	ld a, [wEnemySubStatus1]
; Curse: 1/4 of max HP.
	bit SUBSTATUS_CURSE, a
	ld a, 2
	call nz, .AddMaxHPFraction

; Discourage Endure if that's at least our HP.
	ld a, [wEnemyMonHP + 1]
	ld c, a
	ld a, e
	sub c
	ld a, [wEnemyMonHP]
	ld c, a
	ld a, d
	sbc c
	pop hl
	ret c
	jp AIDiscourageMove

.AddMaxHPFraction:
; Add max HP >> a (at least 1) to de.
	ld hl, wEnemyMonMaxHP
	ld b, [hl]
	inc hl
	ld c, [hl]
.shift
	srl b
	rr c
	dec a
	jr nz, .shift
	ld a, b
	or c
	jr nz, .add
	inc c
.add
	ld h, d
	ld l, e
	add hl, bc
	ld d, h
	ld e, l
	ret

AISmogon_IsResisted:
; Return carry if the player resists the enemy's move or is immune to it.
	push hl
	ld a, 1
	ldh [hBattleTurn], a
	callfar BattleCheckTypeMatchup
	pop hl
	ld a, [wTypeMatchup]
	cp EFFECTIVE
	ret

AISmogon_MissesHiddenPlayer:
; Return carry if the enemy's move is an attack that misses because the
; player's Pokemon is in the air (Fly) or underground (Dig), and we're faster,
; so we attack before it comes back.
	ld a, [wPlayerSubStatus3]
	and 1 << SUBSTATUS_FLYING | 1 << SUBSTATUS_UNDERGROUND
	ret z
	ld b, a
	call AICompareSpeed
	ret nc
	ld a, [wEnemyMoveStruct + MOVE_POWER]
	and a
	jr z, .hits
; Fly and Dig dodge too.
	ld a, [wEnemyMoveStruct + MOVE_EFFECT]
	cp EFFECT_FLY
	jr z, .hits
	ld hl, .DigMoves
	ld a, [wPlayerSubStatus5]
	bit SUBSTATUS_LOCK_ON, a
	jr z, .no_lock_on
; Locked on: everything hits but Earthquake, Fissure and Magnitude into Fly.
	bit SUBSTATUS_FLYING, b
	jr z, .hits
	ld a, [wEnemyMoveStruct + MOVE_ANIM]
	ld de, 1
	jp IsInArray

.no_lock_on
	bit SUBSTATUS_FLYING, b
	jr z, .got_moves
	ld hl, .FlyMoves
.got_moves
	ld a, [wEnemyMoveStruct + MOVE_ANIM]
	ld de, 1
	call IsInArray
	ccf
	ret

.hits
	and a
	ret

.FlyMoves:
; Whirlwind also hits, but isn't an attack.
	db GUST
	db THUNDER
	db TWISTER
	db -1 ; end

.DigMoves:
	db EARTHQUAKE
	db FISSURE
	db MAGNITUDE
	db -1 ; end

AI_Smogon_Explosion:
; Exploding with the last Pokemon just loses the battle.
	push hl
	farcall FindAliveEnemyMons
	pop hl
	jr c, .bad

; Don't explode into a resisting type or a Substitute.
	call AISmogon_IsResisted
	jr c, .bad
	ld a, [wPlayerSubStatus4]
	bit SUBSTATUS_SUBSTITUTE, a
	jr nz, .bad
; Reflect halves Explosion's damage.
	ld a, [wPlayerScreens]
	bit SCREENS_REFLECT, a
	jr nz, .bad

; Lay Spikes before exploding.
	ld a, [wPlayerScreens]
	bit SCREENS_SPIKES, a
	jr nz, .spikes_done
	ld b, EFFECT_SPIKES
	call AISmogon_EnemyHasMoveEffect
	ret c
.spikes_done

; A Pokemon in KO range that the player outspeeds is about to faint anyway:
; take something down with it, and get a free switch-in.
	call AICheckEnemyQuarterHP
	jr c, .not_doomed
	call AICompareSpeed
	jr nc, .threat
.not_doomed

; Trade this Pokemon for a healthy threat like Snorlax, even at full HP,
; or for anything that has started boosting, unless it wins the matchup by
; attacking (Gengar outspeeds Zapdos and hits it with Ice Punch); or for
; anything that beats this Pokemon and that no teammate matches up well
; against.
	call AICheckPlayerHalfHP
	ret nc
	call AISmogon_GetPlayerTraits
	bit SMOGON_THREAT_F, a
	jr nz, .threat_unless_winning
	call AISmogon_PlayerBoosted
	jr c, .threat_unless_winning
	push hl
	call AISmogon_ScoreActive
	call AISmogon_FindBestSwitchIn
	pop hl
	ret c
	ld a, [wEnemyAISwitchScore]
	cp SMOGON_MATCHUP_EVEN
	ret nc
	ld a, [wSmogonAIBestScore]
	cp SMOGON_MATCHUP_EVEN
	ret nc
	jr .trade

.threat_unless_winning
	push hl
	call AISmogon_ScoreActive
	pop hl
	ld a, [wEnemyAISwitchScore]
	cp SMOGON_MATCHUP_EVEN + 1
	ret nc
.trade
; A trade has to take the player's Pokemon down with it (Gengar's Explosion
; doesn't surely KO a healthy Vaporeon), unless this Pokemon is clearly
; losing anyway: Misty's Cloyster still takes most of Zapdos's HP.
	ld a, [wEnemyAISwitchScore]
	cp SMOGON_MATCHUP_EVEN - SMOGON_BOOM_KO_MARGIN
	jr c, .threat
	push hl
	call AISmogon_LoadedMoveKOs
	pop hl
	ret nc
.threat
	dec [hl]
	jp AISmogon_GreatlyEncourage

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
; Toxic wears down walls, but Rest users just sleep it off, and attacking
; is faster against something our attacks KO within SMOGON_TOXIC_MIN_TURNS
; (Tentacruel's Sludge Bomb on Exeggutor).
	ld a, REST
	call AISmogon_PlayerRevealedMove
	jr c, .rester
	call AISmogon_GetPlayerTraits
	bit SMOGON_REST_F, a
	jr nz, .rester
	push hl
	call AISmogon_ScoreActive
	pop hl
	ld a, [wSmogonAIOurTurns]
	cp SMOGON_TOXIC_MIN_TURNS
	jr c, .rester
	dec [hl]
; Poison and Spikes wear switch-ins down together.
	ld a, [wPlayerScreens]
	bit SCREENS_SPIKES, a
	ret z
	dec [hl]
	ret

.rester
	inc [hl]
	ret

AI_Smogon_Paralyze:
; Paralysis cripples faster Pokemon and setup sweepers, and lets slow,
; strong teammates outspeed the player.
	call AICompareSpeed
	jr nc, .encourage
	call AISmogon_GetPlayerTraits
	bit SMOGON_SETUP_F, a
	jr nz, .encourage
	call AISmogon_ParalysisHelpsTeammate
	ret nc
.encourage
	dec [hl]
	ret

AISmogon_ParalysisHelpsTeammate:
; Return carry if a healthy teammate is slower than the player's Pokemon, but
; would outspeed it once paralysis quarters its Speed.
	push hl
	ld hl, wOTPartyMon1HP
	ld a, [wOTPartyCount]
	ld b, a
	ld c, 0
.loop
	ld a, [wCurOTMon]
	cp c
	jr z, .next
	ld a, [hli]
	or [hl]
	dec hl
	jr z, .next
	push bc
	push hl
	ld de, MON_SPD - MON_HP
	add hl, de
	ld a, [hli]
	ld d, a
	ld e, [hl]
	ld a, [wBattleMonSpeed]
	ld b, a
	ld a, [wBattleMonSpeed + 1]
	ld c, a
	; slower: Speed < the player's
	ld a, e
	sub c
	ld a, d
	sbc b
	jr nc, .no
	; faster once paralyzed: Speed * 4 > the player's
	sla e
	rl d
	sla e
	rl d
	ld a, c
	sub e
	ld a, b
	sbc d
	jr c, .yes
.no
	pop hl
	pop bc
.next
	ld de, PARTYMON_STRUCT_LENGTH
	add hl, de
	inc c
	dec b
	jr nz, .loop
	pop hl
	and a
	ret

.yes
	pop hl
	pop bc
	pop hl
	scf
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

AI_Smogon_DestinyBond:
; Destiny Bond takes down whatever knocks us out before we move again.
; Use it when the player is about to knock us out, and we move first: the
; player's attack then can't come before Destiny Bond is up.
; A sleeping or frozen Pokemon won't attack, so don't waste the turn.
	call AISmogon_PlayerCantAttack
	jr nz, .discourage
	call AICheckEnemyQuarterHP
	ret c
	call AICompareSpeed
	ret nc
	jp AISmogon_GreatlyEncourage

.discourage
	inc [hl]
	inc [hl]
	ret

AISmogon_PlayerHasPursuit:
; Return carry if the player's Pokemon has revealed Pursuit, or usually has
; it and hasn't revealed four other moves.
	ld a, PURSUIT
	call AISmogon_PlayerRevealedMove
	ret c
	ld a, [wPlayerUsedMoves + NUM_MOVES - 1]
	and a
	ret nz
	call AISmogon_GetPlayerTraits
	and SMOGON_PURSUIT
	ret z
	scf
	ret

AISmogon_GhostOrPsychic:
	cp GHOST
	ret z
	cp PSYCHIC_TYPE
	ret

AI_Smogon_AttackDown:
; Growl and Charm wall physical setup sweepers like Curse Snorlax by undoing
; their Attack boosts. They do nothing through a Substitute, little against
; special attackers, and can't keep up with a Belly Drum that maxed out Attack.
	ld a, [wPlayerSubStatus4]
	bit SUBSTATUS_SUBSTITUTE, a
	jp nz, AIDiscourageMove
	call AISmogon_PlayerIsPhysical
	jr nc, .discourage
	ld a, [wPlayerAtkLevel]
	cp MAX_STAT_LEVEL
	jr nc, .discourage
	cp BASE_STAT_LEVEL + 1
	ret c
	jp AISmogon_GreatlyEncourage

.discourage
	inc [hl]
	inc [hl]
	ret

AI_Smogon_PerishSong:
; Perish Song is a sure KO once Mean Look has trapped the player.
	ld a, [wPlayerSubStatus5]
	bit SUBSTATUS_CANT_RUN, a
	ret z
	jp AISmogon_Encourage

MACRO smogon_residual_points
; Add to c how much residual damage the Pokemon with these SubStatus1,
; SubStatus4, SubStatus5, Status, Type1, Type2, WrapCount and ToxicCount
; takes each turn: 2 points for Toxic (3 once it does 3/16), Leech Seed and
; Curse, and 1 for poison, burn, Sandstorm and trapping moves.
	ld a, [\3]
	bit SUBSTATUS_TOXIC, a
	jr z, .no_toxic\@
	inc c
	inc c
	ld a, [\8]
	cp 2
	jr c, .status_done\@
	inc c
	jr .status_done\@

.no_toxic\@
	ld a, [\4]
	and 1 << PSN | 1 << BRN
	jr z, .status_done\@
	inc c
.status_done\@
	ld a, [\2]
	bit SUBSTATUS_LEECH_SEED, a
	jr z, .no_leech_seed\@
	inc c
	inc c
.no_leech_seed\@
	ld a, [\1]
	bit SUBSTATUS_CURSE, a
	jr z, .no_curse\@
	inc c
	inc c
.no_curse\@
	ld a, [\7]
	and a
	jr z, .no_wrap\@
	inc c
.no_wrap\@
	ld a, [wBattleWeather]
	cp WEATHER_SANDSTORM
	jr nz, .no_sand\@
	ld a, [\5]
	call AISmogon_SandstormImmune
	jr z, .no_sand\@
	ld a, [\6]
	call AISmogon_SandstormImmune
	jr z, .no_sand\@
	inc c
.no_sand\@
ENDM

AI_Smogon_Protect:
; Protect (and Detect) stalls a turn while residual damage wears down the
; player: Toxic, Leech Seed, Curse, Perish Song, poison, burn, Sandstorm,
; and trapping moves. AI_Smart already discourages using it twice in a row.
	ld a, [wEnemyProtectCount]
	and a
	ret nz
; A sleeping or frozen Pokemon can't hurt us: attack it instead of stalling.
	call AISmogon_PlayerCantAttack
	ret nz

; Protect against a likely Explosion, unless it would barely hurt.
	push hl
	call AISmogon_PlayerMayExplode
	pop hl
	jr nc, .no_explosion
	ld a, [wEnemyMonType1]
	call AISmogon_ResistsExplosion
	jr z, .no_explosion
	ld a, [wEnemyMonType2]
	call AISmogon_ResistsExplosion
	jp nz, AISmogon_GreatlyEncourage
.no_explosion

; Stall out the player's Perish Song count if ours runs out later.
	ld a, [wPlayerSubStatus1]
	bit SUBSTATUS_PERISH, a
	jr z, .no_perish
	ld a, [wEnemySubStatus1]
	bit SUBSTATUS_PERISH, a
	jp z, AISmogon_GreatlyEncourage
	ld a, [wEnemyPerishCount]
	ld b, a
	ld a, [wPlayerPerishCount]
	cp b
	jp c, AISmogon_GreatlyEncourage
.no_perish

; Stalling only helps if the player takes more residual damage than we do.
	ld c, 0
	smogon_residual_points wEnemySubStatus1, wEnemySubStatus4, wEnemySubStatus5, \
		wEnemyMonStatus, wEnemyMonType1, wEnemyMonType2, wEnemyWrapCount, wEnemyToxicCount
	ld b, c
	ld c, 0
	smogon_residual_points wPlayerSubStatus1, wPlayerSubStatus4, wPlayerSubStatus5, \
		wBattleMonStatus, wBattleMonType1, wBattleMonType2, wPlayerWrapCount, wPlayerToxicCount
; Leftovers recovers while we stall.
	ld a, [wEnemyMonItem]
	cp LEFTOVERS
	jr nz, .no_leftovers
	call AICheckEnemyMaxHP
	jr c, .no_leftovers
	inc c
.no_leftovers
	ld a, c
	sub b
	ret c
	cp 2
	ret c
	cp 4
	jp c, AISmogon_Encourage
	jp AISmogon_GreatlyEncourage

AISmogon_SandstormImmune:
; Return z if type a takes no Sandstorm damage.
	cp ROCK
	ret z
	cp GROUND
	ret z
	cp STEEL
	ret

AI_Smogon_Substitute:
; A sleeping or frozen Pokemon can't break a Substitute.
	call AISmogon_PlayerCantAttack
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

; A move that can't raise any stat further is useless.
	call .GetBoostLevel
	cp MAX_STAT_LEVEL
	jp nc, AIDiscourageMove

; Lay Spikes first (Forretress used Curse in front of Snorlax instead).
	call AISmogon_SpikesFirst
	jr c, .discourage

; Don't set up into phazing or Haze, which would erase the boosts.
	call AISmogon_PlayerCanPhaze
	jr c, .discourage

; Badly poisoned: no time to set up.
	ld a, [wEnemySubStatus5]
	bit SUBSTATUS_TOXIC, a
	jr nz, .discourage

; Set up only while healthy (this also keeps Belly Drum from failing).
	call AICheckEnemyHalfHP
	ret nc

; Don't set up in front of something that hits harder than we do.
	push hl
	call AISmogon_ScoreActive
	pop hl
	ld a, [wEnemyAISwitchScore]
	cp SMOGON_MATCHUP_EVEN
	jr c, .discourage

; Once boosted enough to sweep, attack instead.
	call .GetBoostLevel
	cp SMOGON_SETUP_GOAL
	jr nc, .discourage

; A sleeping or frozen Pokemon can't punish setup, unless it uses Sleep Talk
; (Curse + Sleep Talk Snorlax wins Snorlax wars that way).
	call AISmogon_PlayerCantAttack
	jp nz, AISmogon_Encourage

; Otherwise encourage boosting, especially against something that can
; barely hurt us.
	dec [hl]
	ld a, [wEnemyAISwitchScore]
	cp SMOGON_MATCHUP_GOOD
	ret c
	dec [hl]
	ret

.discourage
	inc [hl]
	inc [hl]
	ret

.GetBoostLevel:
; Return in a the lowest stat level among the stats this move raises.
	ld a, [wEnemyMoveStruct + MOVE_EFFECT]
	lb bc, ATTACK, DEFENSE
	cp EFFECT_CURSE
	jr z, .got_stats
; Growth
	lb bc, SP_ATTACK, SP_ATTACK
	cp EFFECT_SP_ATK_UP
	jr z, .got_stats
	lb bc, ATTACK, ATTACK
	cp EFFECT_BELLY_DRUM
	jr z, .got_stats
	; Swords Dance, Acid Armor, Agility, Amnesia, ...
	assert EFFECT_DEFENSE_UP_2 - EFFECT_ATTACK_UP_2 == DEFENSE
	assert EFFECT_SPEED_UP_2 - EFFECT_ATTACK_UP_2 == SPEED
	assert EFFECT_SP_DEF_UP_2 - EFFECT_ATTACK_UP_2 == SP_DEFENSE
	sub EFFECT_ATTACK_UP_2
	ld b, a
	ld c, a
.got_stats
	push hl
	ld hl, wEnemyStatLevels
	ld a, l
	add b
	ld l, a
	adc h
	sub l
	ld h, a
	ld b, [hl]
	ld hl, wEnemyStatLevels
	ld a, l
	add c
	ld l, a
	adc h
	sub l
	ld h, a
	ld a, [hl]
	pop hl
	cp b
	ret c
	ld a, b
	ret

AISmogon_EnemyHasMoveEffect:
; Return carry if the enemy knows a move with effect b. Unlike
; AIHasMoveEffect, this keeps wEnemyMoveStruct, the move being scored (it
; reads the effects from Moves), and hl.
	push hl
	push de
	ld hl, wEnemyMonMoves
	ld c, NUM_MOVES
.loop
	ld a, [hli]
	and a
	jr z, .no
	push hl
	push bc
	dec a
	ld hl, Moves + MOVE_EFFECT
	ld bc, MOVE_LENGTH
	call AddNTimes
	ld a, BANK(Moves)
	call GetFarByte
	pop bc
	pop hl
	cp b
	jr z, .yes
	dec c
	jr nz, .loop
.no
	pop de
	pop hl
	and a
	ret

.yes
	pop de
	pop hl
	scf
	ret

AISmogon_SpikesFirst:
; Return carry if the enemy has Spikes to lay: it knows them, they aren't
; down on the player's side yet, and the player has Pokemon left to switch
; in. Keeps hl.
	ld a, [wPlayerScreens]
	bit SCREENS_SPIKES, a
	jr nz, .no
	ld b, EFFECT_SPIKES
	call AISmogon_EnemyHasMoveEffect
	jr nc, .no
	push hl
	call AISmogon_ScanPlayerParty
	pop hl
	ld a, c
	and a
	jr z, .no
	scf
	ret

.no
	and a
	ret

AI_Smogon_Screens:
; Put up the screen that blocks the player's attacks: Reflect against a
; physical attacker, Light Screen against a special one.
	call AISmogon_PlayerIsPhysical
	ld a, [wEnemyMoveStruct + MOVE_EFFECT]
	jr nc, .special
	cp EFFECT_REFLECT
	jr .check

.special
	cp EFFECT_LIGHT_SCREEN
.check
	jp z, AISmogon_EncourageNear
	inc [hl]
	inc [hl]
	ret

AI_Smogon_Counter:
; Counter and Mirror Coat hit back for double the damage of a physical or
; special attack. Ghosts are immune to Counter, Dark types to Mirror Coat.
	push hl
	ld a, 1
	ldh [hBattleTurn], a
	callfar BattleCheckTypeMatchup
	pop hl
	ld a, [wTypeMatchup]
	and a
	jp z, AIDiscourageMove
; A sleeping or frozen Pokemon won't attack.
	call AISmogon_PlayerCantAttack
	jr nz, .discourage
; Use the one that matches the player's attacks, going by the attacks it
; has revealed, or else by its Attack and Sp.Atk stats.
	call AISmogon_PlayerIsCounterable
	ld a, [wEnemyMoveStruct + MOVE_EFFECT]
	jr nc, .special
	cp EFFECT_COUNTER
	jr .check

.special
	cp EFFECT_MIRROR_COAT
.check
	jr nz, .discourage
; It moves last, so it has to survive the hit first.
	call AICheckEnemyHalfHP
	ret nc
	jr AISmogon_EncourageNear

.discourage
	inc [hl]
	inc [hl]
	ret

AI_Smogon_BatonPass:
; Baton Pass fails without a teammate to pass to.
	push hl
	farcall FindAliveEnemyMons
	pop hl
	jp c, AIDiscourageMove

; With nothing to pass, it's just a slower switch.
	call AISmogon_EnemyBoosted
	jr c, .something_to_pass
	ld a, [wEnemySubStatus4]
	bit SUBSTATUS_SUBSTITUTE, a
	jr nz, .something_to_pass
	inc [hl]
	inc [hl]
	ret

.something_to_pass
; Pass boosts or a Substitute on before a phazer or Haze erases them, or
; when the player's Pokemon gets the better of this one.
	call AISmogon_PlayerCanPhaze
	jr c, AISmogon_EncourageNear
	push hl
	call AISmogon_ScoreActive
	pop hl
	ld a, [wEnemyAISwitchScore]
	cp SMOGON_MATCHUP_EVEN
	jr c, AISmogon_EncourageNear
; Otherwise keep the boosts here and use them.
	inc [hl]
	ret

AI_Smogon_Encore:
; Encore a move that doesn't hurt, like a setup or status move, to lock the
; player into wasting turns. It works best when we move first.
	ld a, [wPlayerSubStatus5]
	bit SUBSTATUS_ENCORED, a
	ret nz
	ld a, [wLastPlayerMove]
	and a
	ret z
; Encore fails on Encore and Mirror Move (and Struggle, an attack).
	cp ENCORE
	jp z, AIDiscourageMove
	cp MIRROR_MOVE
	jp z, AIDiscourageMove
	call AISmogon_GetMovePowerAndType
	ld a, d
	and a
	ret nz
	dec [hl]
	call AICompareSpeed
	ret nc
	; fallthrough

AISmogon_EncourageNear:
; Same as AISmogon_Encourage, within jr range of the handlers around it.
	dec [hl]
	dec [hl]
	ret

AI_Smogon_HealBell:
; Heal Bell is worth a turn once two or more of the team are statused.
	push hl
	ld c, 0
	ld a, [wEnemyMonStatus]
	and a
	jr z, .active_done
	inc c
.active_done
	ld hl, wOTPartyMon1Status
	ld de, PARTYMON_STRUCT_LENGTH
	ld b, 0
.loop
	ld a, [wOTPartyCount]
	cp b
	jr z, .done
	ld a, [wCurOTMon]
	cp b
	jr z, .next
	push hl
	ld a, [hli]
	assert MON_HP - MON_STATUS == 2
	inc hl
	and a
	jr z, .next_pop
	ld a, [hli]
	or [hl]
	jr z, .next_pop
	inc c
.next_pop
	pop hl
.next
	add hl, de
	inc b
	jr .loop

.done
	pop hl
	ld a, c
	cp 2
	ret c
	jr AISmogon_EncourageNear

AISmogon_PlayerCanPhaze:
; Return carry if the player's Pokemon has revealed Roar, Whirlwind or Haze,
; or is usually played with phazing.
	push de
	ld de, .AntiSetupMoves
.loop
	ld a, [de]
	inc de
	cp -1
	jr z, .traits
	call AISmogon_PlayerRevealedMove
	jr nc, .loop
	pop de
	ret

.traits
	pop de
	call AISmogon_GetPlayerTraits
	and SMOGON_PHAZER
	ret z
	scf
	ret

.AntiSetupMoves:
	db ROAR
	db WHIRLWIND
	db HAZE
	db -1 ; end

AISmogon_PlayerPhazes:
; Return carry if the player's Pokemon has revealed Roar or Whirlwind, or
; usually has one and hasn't revealed four other moves.
	ld a, ROAR
	call AISmogon_PlayerRevealedMove
	ret c
	ld a, WHIRLWIND
	call AISmogon_PlayerRevealedMove
	ret c
	ld a, [wPlayerUsedMoves + NUM_MOVES - 1]
	and a
	ret nz
	call AISmogon_GetPlayerTraits
	and SMOGON_PHAZER
	ret z
	scf
	ret

AISmogon_PlayerIsCounterable:
; Same as AISmogon_PlayerIsPhysical, but the way Counter and Mirror Coat
; see attacks: Hidden Power is physical (Normal in the move data), and
; fixed-damage attacks like Seismic Toss and Night Shade count.
	push bc
	push de
	push hl
	ld hl, 0
	jr AISmogon_PlayerIsPhysical.start

AISmogon_PlayerIsPhysical:
; Return carry if the player's Pokemon attacks mainly physically, going by
; the attacks it has revealed, or else by its Attack and Sp.Atk stats.
	push bc
	push de
	push hl
	ld hl, wBattleMonDVs
.start
; hl = DVs for Hidden Power's type, or 0 for Normal
	push hl
; b = physical attacks, c = special attacks
	ld bc, 0
	ld hl, wPlayerUsedMoves
.loop
	ld a, [hli]
	and a
	jr z, .counted
	pop de
	push de
	push hl
	ld h, d
	ld l, e
	ld e, a
	ld a, h
	or l
	ld a, e
	jr z, .no_dvs
	call AISmogon_GetAttack
	jr .got_attack

.no_dvs
	call AISmogon_GetMovePowerAndType
	ld a, d
	dec a
	jr nz, .got_attack
; Count fixed-damage attacks.
	inc d
.got_attack
	pop hl
	; skip status moves, and fixed-damage moves, which screens don't stop
	ld a, d
	cp 2
	jr c, .next
	ld a, e
	cp SPECIAL
	jr nc, .special
	inc b
	jr .next

.special
	inc c
.next
	assert HIGH(wPlayerUsedMoves) == HIGH(wPlayerUsedMoves + NUM_MOVES)
	ld a, l
	cp LOW(wPlayerUsedMoves + NUM_MOVES)
	jr nz, .loop

.counted
	pop de
	; carry if more physical attacks than special ones
	ld a, c
	cp b
	jr nz, .done
	; carry if Sp.Atk < Attack
	ld de, wBattleMonSpclAtk
	ld hl, wBattleMonAttack
	call AISmogon_Compare16
.done
	pop hl
	pop de
	pop bc
	ret

AISmogon_PlayerCantAttack:
; Return nz if the player's Pokemon can't attack this turn: it's frozen (it
; doesn't move on the turn it thaws either), or asleep and hasn't revealed
; Sleep Talk.
	ld a, [wBattleMonStatus]
	bit FRZ, a
	ret nz
	and SLP_MASK
	ret z
	ld a, SLEEP_TALK
	call AISmogon_PlayerRevealedMove
	; Sleep Talk: a = 0 (z), else a = 1 (nz)
	sbc a
	inc a
	ret

AISmogon_GetPlayerTraits:
; Return the SmogonTraits flags of the player's active Pokemon in a.
	push hl
	ld a, [wBattleMonSpecies]
	add LOW(SmogonTraits - 1)
	ld l, a
	adc HIGH(SmogonTraits - 1)
	sub l
	ld h, a
	ld a, [hl]
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

AISmogon_EnemyHasUsefulBoosts:
; Return carry if the enemy has raised a stat level that helps against the
; player's Pokemon: Attack, Speed, Sp.Atk, accuracy or evasion, or the
; defense its attacks hit (AISmogon_PlayerIsPhysical). Acid Armor doesn't
; stop Surf.
	ld hl, wEnemyAtkLevel
	call .Raised
	ret c
	ld hl, wEnemySpdLevel
	call .Raised
	ret c
	ld hl, wEnemySAtkLevel
	call .Raised
	ret c
	ld hl, wEnemyAccLevel
	call .Raised
	ret c
	ld hl, wEnemyEvaLevel
	call .Raised
	ret c
	call AISmogon_PlayerIsPhysical
	ld hl, wEnemyDefLevel
	jr c, .Raised
	ld hl, wEnemySDefLevel
.Raised:
; carry if [hl] > BASE_STAT_LEVEL
	ld a, BASE_STAT_LEVEL
	cp [hl]
	ret

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
; d = sleep bits, e = party index
	ld de, 0
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
