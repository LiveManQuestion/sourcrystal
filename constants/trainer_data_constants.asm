; TrainerClassAttributes struct members (see data/trainers/attributes.asm)
rsreset
DEF TRNATTR_ITEM1           rb ; 0
DEF TRNATTR_ITEM2           rb ; 1
DEF TRNATTR_BASEMONEY       rb ; 2
DEF TRNATTR_AI_MOVE_WEIGHTS rw ; 3
DEF TRNATTR_AI_ITEM_SWITCH  rw ; 5
DEF NUM_TRAINER_ATTRIBUTES EQU _RS

; TRNATTR_AI_MOVE_WEIGHTS bit flags (wEnemyTrainerAIFlags)
; AIScoringPointers indexes (see engine/battle/ai/move.asm)
	const_def
	shift_const AI_BASIC
	shift_const AI_SETUP
	shift_const AI_TYPES
	shift_const AI_OFFENSIVE
	shift_const AI_SMART
	shift_const AI_OPPORTUNIST
	shift_const AI_AGGRESSIVE
	shift_const AI_CAUTIOUS
	shift_const AI_STATUS
	shift_const AI_RISKY
	shift_const AI_IMMUNITIES
	shift_const AI_SMOGON
DEF NO_AI EQU 0

; SmogonTraits bit flags (see data/battle/ai/smogon_traits.asm)
	const_def
	shift_const SMOGON_SLEEP_TALK
	shift_const SMOGON_REST
	shift_const SMOGON_PHAZER
	shift_const SMOGON_SETUP
	shift_const SMOGON_THREAT

; Smogon AI matchup scores (see engine/battle/ai/smogon_switch.asm)
DEF SMOGON_MATCHUP_EVEN      EQU 128 ; neither side hits harder
DEF SMOGON_MATCHUP_GOOD      EQU SMOGON_MATCHUP_EVEN + 16
DEF SMOGON_FASTER_BONUS      EQU 6   ; outspeeds the player's Pokemon
DEF SMOGON_REVENGE_BONUS     EQU 6   ; ...and that Pokemon is below half HP
DEF SMOGON_STAB_POWER        EQU 80  ; assumed power of unrevealed STAB attacks
DEF SMOGON_WEAK_POWER        EQU 60  ; attacks below this lose a quarter
DEF SMOGON_STRONG_POWER      EQU 100 ; attacks from this on gain a quarter

; Smogon AI rough damage points (see AISmogon_AttackPoints)
DEF SMOGON_POINTS_RESISTED   EQU 4
DEF SMOGON_POINTS_NEUTRAL    EQU 10
DEF SMOGON_POINTS_SUPER      EQU 20
DEF SMOGON_POINTS_4X         EQU 32

; Smogon AI switch-in penalties (see AISmogon_SwitchInPenalty)
DEF SMOGON_PENALTY_HALF_HP    EQU 8
DEF SMOGON_PENALTY_QUARTER_HP EQU 24
DEF SMOGON_PENALTY_ASLEEP     EQU 20
DEF SMOGON_PENALTY_SLEEP_TALK EQU 4 ; asleep, but can still attack
DEF SMOGON_PENALTY_FROZEN     EQU 30
DEF SMOGON_PENALTY_PARALYZED  EQU 4
DEF SMOGON_PENALTY_POISON_BRN EQU 2

; Smogon AI switching thresholds (see SwitchSmogon)
DEF SMOGON_SWITCH_MARGIN     EQU 20 ; matchup gain needed to switch
DEF SMOGON_SPIKES_MARGIN     EQU 10 ; extra gain needed with Spikes down
DEF SMOGON_JUST_IN_MARGIN    EQU 10 ; extra gain needed right after switching in
DEF SMOGON_SURE_SWITCH       EQU 12 ; gain past the margin that always switches
DEF SMOGON_ESCAPE_TOLERANCE  EQU 16 ; how much worse an escape switch-in may be

; AISmogon_StatEdges flags
	const_def
	const SMOGON_PHYSICAL_EDGE_F ; 0
	const SMOGON_SPECIAL_EDGE_F  ; 1

; TRNATTR_AI_ITEM_SWITCH bit flags
	const_def
	shift_const SWITCH_OFTEN     ; 0
	shift_const SWITCH_RARELY    ; 1
	shift_const SWITCH_SOMETIMES ; 2
	shift_const SWITCH_SMOGON    ; 3
	shift_const ALWAYS_USE       ; 4
	shift_const UNKNOWN_USE      ; 5
	shift_const CONTEXT_USE      ; 6

; TrainerTypes bits (see engine/battle/read_trainer_party.asm)
	const_def
	const TRAINERTYPE_MOVES_F     ; 0
	const TRAINERTYPE_ITEM_F      ; 1
	const TRAINERTYPE_VARIABLE_F  ; 3
	const TRAINERTYPE_DVS_F       ; 4
	const TRAINERTYPE_HAPPINESS_F ; 5

; Trainer party types (see data/trainers/parties.asm)
DEF TRAINERTYPE_NORMAL     EQU 0
DEF TRAINERTYPE_MOVES      EQU 1 << TRAINERTYPE_MOVES_F
DEF TRAINERTYPE_ITEM       EQU 1 << TRAINERTYPE_ITEM_F
DEF TRAINERTYPE_ITEM_MOVES EQU TRAINERTYPE_MOVES | TRAINERTYPE_ITEM
DEF TRAINERTYPE_VARIABLE   EQU 1 << TRAINERTYPE_VARIABLE_F
DEF TRAINERTYPE_DVS        EQU 1 << TRAINERTYPE_DVS_F
DEF TRAINERTYPE_HAPPINESS  EQU 1 << TRAINERTYPE_HAPPINESS_F

DEF PERFECT_DV EQU $11 ; treated as $FF in enemy party data
DEF MAX_HAPPINESS EQU $42 ; treated as $FF in enemy party data

