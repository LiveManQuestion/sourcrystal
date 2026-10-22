; In Challenge Mode, the wild legendaries in LegendaryAIMons pick their
; moves like a Smogon AI trainer's Pokemon (AIChooseMove), with the layers
; in LegendaryAIMoveWeights.

LegendaryAIMons:
	db RAIKOU
	db ENTEI
	db SUICUNE
	db MEWTWO
	db LUGIA
	db HO_OH
	db -1

LegendaryAIMoveWeights:
; read like TrainerClassAttributes' TRNATTR_AI_MOVE_WEIGHTS
	dw AI_BASIC | AI_SETUP | AI_SMART | AI_AGGRESSIVE | AI_CAUTIOUS | AI_STATUS | AI_RISKY | AI_IMMUNITIES | AI_SMOGON | AI_LEGENDARY

	assert BANK(LegendaryAIMoveWeights) == BANK(TrainerClassAttributes), \
		"AIChooseMove reads LegendaryAIMoveWeights from TrainerClassAttributes' bank"

AIUsesLegendaryAI:
; Return carry if the enemy is a wild legendary that picks its moves with
; the trainer AI. Wild battles are never link battles.
	ld a, [wBattleMode]
	dec a ; WILD_BATTLE?
	jr nz, .no
	ld a, [wChallengeMode]
	bit GAME_CHALLENGE_MODE_F, a
	jr z, .no
	ld a, [wEnemyMonSpecies]
	ld hl, LegendaryAIMons
	ld de, 1
	jp IsInArray

.no
	and a
	ret

LegendaryChallengeMoves:
; species, then the four moves it has in place of its level-up moves
	db LUGIA,   CURSE,        AEROBLAST, WHIRLWIND, RECOVER
	db HO_OH,   FLAMETHROWER, TOXIC,     RECOVER,   WHIRLWIND
	db MEWTWO,  PSYCHIC_M,    DYNAMICPUNCH, BARRIER, RECOVER
	db ENTEI,   FIRE_BLAST,   SUNNY_DAY, SOLARBEAM, ROAR
	db SUICUNE, HYDRO_PUMP,   SURF,      ICE_BEAM,  ROAR
	db RAIKOU,  THUNDERBOLT,  ROAR,      RAIN_DANCE, THUNDER
	db -1

AILegendary_SetChallengeMoves:
; LoadEnemyMon: give a wild legendary that uses the legendary AI its
; LegendaryChallengeMoves moveset. They're kept if it's caught.
	call AIUsesLegendaryAI
	ret nc
	ld a, [wEnemyMonSpecies]
	ld hl, LegendaryChallengeMoves
	ld de, 1 + NUM_MOVES
	call IsInArray
	ret nc
	inc hl
	ld de, wEnemyMonMoves
	ld bc, NUM_MOVES
	jp CopyBytes

AILegendary_FillOTParty:
; The AI reads its own Pokemon from the enemy party (wOTPartyMon1 at
; wCurOTMon), which wild battles leave unset: make the wild Pokemon a party
; of one, with its unboosted stats like a trainer's.
	ld a, 1
	ld [wOTPartyCount], a
	ld a, [wEnemyMonSpecies]
	ld [wOTPartySpecies], a
	ld a, -1
	ld [wOTPartySpecies + 1], a
	xor a
	ld [wCurOTMon], a

	ld hl, wEnemyMonSpecies
	ld de, wOTPartyMon1Species
	ld bc, wEnemyMonDVs - wEnemyMonSpecies
	call CopyBytes
	ld hl, wEnemyMonDVs
	ld de, wOTPartyMon1DVs
	ld bc, wEnemyMonLevel - wEnemyMonDVs
	call CopyBytes
	ld hl, wEnemyMonLevel
	ld de, wOTPartyMon1Level
	ld bc, wEnemyMonStats - wEnemyMonLevel
	call CopyBytes
	ld hl, wEnemyStats
	ld de, wOTPartyMon1Stats
	ld bc, wOTPartyMon1StructEnd - wOTPartyMon1Stats
	jp CopyBytes

AI_Legendary:
; A wild legendary fights alone: never end the battle with Roar, Whirlwind
; or Teleport (the player came to catch it), or use Baton Pass, which fails
; without a teammate.
	ld hl, wEnemyAIMoveScores - 1
	ld de, wEnemyMonMoves
	ld b, NUM_MOVES + 1
.checkmove
	dec b
	ret z

	inc hl
	ld a, [de]
	and a
	ret z

	inc de
	call AIGetEnemyMove
	ld a, [wEnemyMoveStruct + MOVE_EFFECT]
	cp EFFECT_FORCE_SWITCH
	jr z, .dismiss
	cp EFFECT_TELEPORT
	jr z, .dismiss
	cp EFFECT_BATON_PASS
	jr nz, .checkmove

; Worse than any usable move, still better than an unusable one (80).
.dismiss
	ld a, [hl]
	cp 79
	jr nc, .checkmove
	ld [hl], 79
	jr .checkmove
