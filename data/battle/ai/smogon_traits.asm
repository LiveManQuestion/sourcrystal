; Per-species tendencies of GSC OU sets, used by AI_Smogon as a prior when the
; player hasn't revealed the relevant move yet. Generated from 41k Smogtours
; GSC OU replays (Siatam's GSC OU Stats Master, data up to 2 October 2026).
;   SMOGON_SLEEP_TALK: Sleep Talk on >= 20% of revealed sets
;   SMOGON_REST:       Rest on >= 30% of revealed sets
;   SMOGON_PHAZER:     Roar or Whirlwind on >= 25% of revealed sets
;   SMOGON_SETUP:      a boosting move (Curse, Growth, Swords Dance, ...) on >= 35%
;   SMOGON_THREAT:     common (>= 3% usage) win condition or wall that is a good
;                      Explosion target (not Rock, Steel or Ghost)

SmogonTraits:
	table_width 1
	db 0                                                             ; BULBASAUR
	db 0                                                             ; IVYSAUR
	db 0                                                             ; VENUSAUR (0.5% usage)
	db 0                                                             ; CHARMANDER
	db 0                                                             ; CHARMELEON
	db SMOGON_SETUP                                                  ; CHARIZARD (1.9% usage)
	db 0                                                             ; SQUIRTLE
	db 0                                                             ; WARTORTLE
	db 0                                                             ; BLASTOISE
	db 0                                                             ; CATERPIE
	db 0                                                             ; METAPOD
	db 0                                                             ; BUTTERFREE
	db 0                                                             ; WEEDLE
	db 0                                                             ; KAKUNA
	db 0                                                             ; BEEDRILL
	db 0                                                             ; PIDGEY
	db 0                                                             ; PIDGEOTTO
	db 0                                                             ; PIDGEOT
	db 0                                                             ; RATTATA
	db 0                                                             ; RATICATE
	db 0                                                             ; SPEAROW
	db 0                                                             ; FEAROW
	db 0                                                             ; EKANS
	db 0                                                             ; ARBOK
	db 0                                                             ; PIKACHU (0.2% usage)
	db 0                                                             ; RAICHU
	db 0                                                             ; SANDSHREW
	db SMOGON_SETUP                                                  ; SANDSLASH (0.1% usage)
	db 0                                                             ; NIDORAN_F
	db 0                                                             ; NIDORINA
	db 0                                                             ; NIDOQUEEN
	db 0                                                             ; NIDORAN_M
	db 0                                                             ; NIDORINO
	db 0                                                             ; NIDOKING (15.7% usage)
	db 0                                                             ; CLEFAIRY
	db SMOGON_SETUP                                                  ; CLEFABLE (0.5% usage)
	db 0                                                             ; VULPIX
	db 0                                                             ; NINETALES
	db 0                                                             ; JIGGLYPUFF
	db 0                                                             ; WIGGLYTUFF
	db 0                                                             ; ZUBAT
	db 0                                                             ; GOLBAT
	db 0                                                             ; ODDISH
	db 0                                                             ; GLOOM
	db 0                                                             ; VILEPLUME
	db 0                                                             ; PARAS
	db 0                                                             ; PARASECT
	db 0                                                             ; VENONAT
	db 0                                                             ; VENOMOTH
	db 0                                                             ; DIGLETT
	db 0                                                             ; DUGTRIO
	db 0                                                             ; MEOWTH
	db 0                                                             ; PERSIAN
	db 0                                                             ; PSYDUCK
	db 0                                                             ; GOLDUCK
	db 0                                                             ; MANKEY
	db 0                                                             ; PRIMEAPE
	db 0                                                             ; GROWLITHE
	db 0                                                             ; ARCANINE
	db 0                                                             ; POLIWAG
	db 0                                                             ; POLIWHIRL
	db 0                                                             ; POLIWRATH
	db 0                                                             ; ABRA
	db 0                                                             ; KADABRA
	db 0                                                             ; ALAKAZAM (2.9% usage)
	db 0                                                             ; MACHOP
	db 0                                                             ; MACHOKE
	db SMOGON_SETUP | SMOGON_THREAT                                  ; MACHAMP (16.0% usage)
	db 0                                                             ; BELLSPROUT
	db 0                                                             ; WEEPINBELL
	db 0                                                             ; VICTREEBEL
	db 0                                                             ; TENTACOOL
	db SMOGON_SETUP                                                  ; TENTACRUEL (2.7% usage)
	db 0                                                             ; GEODUDE
	db 0                                                             ; GRAVELER
	db SMOGON_PHAZER                                                 ; GOLEM (16.9% usage)
	db 0                                                             ; PONYTA
	db 0                                                             ; RAPIDASH
	db 0                                                             ; SLOWPOKE
	db 0                                                             ; SLOWBRO
	db 0                                                             ; MAGNEMITE
	db 0                                                             ; MAGNETON
	db 0                                                             ; FARFETCH_D
	db 0                                                             ; DODUO
	db 0                                                             ; DODRIO
	db 0                                                             ; SEEL
	db 0                                                             ; DEWGONG
	db 0                                                             ; GRIMER
	db SMOGON_SETUP                                                  ; MUK (0.6% usage)
	db 0                                                             ; SHELLDER
	db SMOGON_THREAT                                                 ; CLOYSTER (69.8% usage)
	db 0                                                             ; GASTLY
	db 0                                                             ; HAUNTER
	db 0                                                             ; GENGAR (30.3% usage)
	db 0                                                             ; ONIX
	db 0                                                             ; DROWZEE
	db 0                                                             ; HYPNO
	db 0                                                             ; KRABBY
	db 0                                                             ; KINGLER
	db 0                                                             ; VOLTORB
	db 0                                                             ; ELECTRODE
	db 0                                                             ; EXEGGCUTE
	db SMOGON_THREAT                                                 ; EXEGGUTOR (29.8% usage)
	db 0                                                             ; CUBONE
	db SMOGON_SETUP | SMOGON_THREAT                                  ; MAROWAK (8.5% usage)
	db 0                                                             ; HITMONLEE
	db 0                                                             ; HITMONCHAN
	db 0                                                             ; LICKITUNG
	db 0                                                             ; KOFFING
	db 0                                                             ; WEEZING
	db 0                                                             ; RHYHORN
	db SMOGON_PHAZER | SMOGON_SETUP                                  ; RHYDON (5.4% usage)
	db 0                                                             ; CHANSEY
	db 0                                                             ; TANGELA
	db SMOGON_PHAZER | SMOGON_SETUP                                  ; KANGASKHAN (0.6% usage)
	db 0                                                             ; HORSEA
	db 0                                                             ; SEADRA
	db 0                                                             ; GOLDEEN
	db 0                                                             ; SEAKING
	db 0                                                             ; STARYU
	db 0                                                             ; STARMIE (15.4% usage)
	db 0                                                             ; MR__MIME
	db 0                                                             ; SCYTHER
	db 0                                                             ; JYNX (9.2% usage)
	db 0                                                             ; ELECTABUZZ (0.1% usage)
	db 0                                                             ; MAGMAR
	db 0                                                             ; PINSIR
	db 0                                                             ; TAUROS (0.2% usage)
	db 0                                                             ; MAGIKARP
	db 0                                                             ; GYARADOS
	db 0                                                             ; LAPRAS (0.2% usage)
	db 0                                                             ; DITTO
	db 0                                                             ; EEVEE
	db SMOGON_SLEEP_TALK | SMOGON_REST | SMOGON_SETUP | SMOGON_THREAT; VAPOREON (10.4% usage)
	db SMOGON_SETUP | SMOGON_THREAT                                  ; JOLTEON (3.3% usage)
	db 0                                                             ; FLAREON
	db 0                                                             ; PORYGON
	db 0                                                             ; OMANYTE
	db 0                                                             ; OMASTAR (0.1% usage)
	db 0                                                             ; KABUTO
	db 0                                                             ; KABUTOPS
	db SMOGON_PHAZER                                                 ; AERODACTYL (0.3% usage)
	db SMOGON_SLEEP_TALK | SMOGON_REST | SMOGON_SETUP | SMOGON_THREAT; SNORLAX (96.8% usage)
	db SMOGON_SLEEP_TALK | SMOGON_REST                               ; ARTICUNO (0.3% usage)
	db SMOGON_SLEEP_TALK | SMOGON_REST | SMOGON_THREAT               ; ZAPDOS (66.9% usage)
	db SMOGON_SLEEP_TALK                                             ; MOLTRES (1.4% usage)
	db 0                                                             ; DRATINI
	db 0                                                             ; DRAGONAIR
	db 0                                                             ; DRAGONITE (1.8% usage)
	db 0                                                             ; MEWTWO
	db 0                                                             ; MEW
	db 0                                                             ; CHIKORITA
	db 0                                                             ; BAYLEEF
	db 0                                                             ; MEGANIUM (1.3% usage)
	db 0                                                             ; CYNDAQUIL
	db 0                                                             ; QUILAVA
	db 0                                                             ; TYPHLOSION
	db 0                                                             ; TOTODILE
	db 0                                                             ; CROCONAW
	db 0                                                             ; FERALIGATR
	db 0                                                             ; SENTRET
	db 0                                                             ; FURRET
	db 0                                                             ; HOOTHOOT
	db 0                                                             ; NOCTOWL
	db 0                                                             ; LEDYBA
	db 0                                                             ; LEDIAN
	db 0                                                             ; SPINARAK
	db 0                                                             ; ARIADOS
	db 0                                                             ; CROBAT
	db 0                                                             ; CHINCHOU
	db 0                                                             ; LANTURN
	db 0                                                             ; PICHU
	db 0                                                             ; CLEFFA
	db 0                                                             ; IGGLYBUFF
	db 0                                                             ; TOGEPI
	db 0                                                             ; TOGETIC
	db 0                                                             ; NATU
	db 0                                                             ; XATU
	db 0                                                             ; MAREEP
	db 0                                                             ; FLAAFFY
	db 0                                                             ; AMPHAROS (0.1% usage)
	db 0                                                             ; BELLOSSOM
	db 0                                                             ; MARILL
	db 0                                                             ; AZUMARILL
	db 0                                                             ; SUDOWOODO
	db 0                                                             ; POLITOED
	db 0                                                             ; HOPPIP
	db 0                                                             ; SKIPLOOM
	db 0                                                             ; JUMPLUFF (0.1% usage)
	db 0                                                             ; AIPOM
	db 0                                                             ; SUNKERN
	db 0                                                             ; SUNFLORA
	db 0                                                             ; YANMA
	db 0                                                             ; WOOPER
	db SMOGON_REST | SMOGON_SETUP                                    ; QUAGSIRE (1.9% usage)
	db SMOGON_SETUP                                                  ; ESPEON (2.9% usage)
	db SMOGON_SLEEP_TALK | SMOGON_REST | SMOGON_THREAT               ; UMBREON (6.5% usage)
	db 0                                                             ; MURKROW
	db 0                                                             ; SLOWKING
	db 0                                                             ; MISDREAVUS (5.5% usage)
	db 0                                                             ; UNOWN
	db 0                                                             ; WOBBUFFET
	db 0                                                             ; GIRAFARIG
	db 0                                                             ; PINECO
	db 0                                                             ; FORRETRESS (19.3% usage)
	db 0                                                             ; DUNSPARCE
	db 0                                                             ; GLIGAR (0.2% usage)
	db SMOGON_PHAZER | SMOGON_SETUP                                  ; STEELIX (23.7% usage)
	db 0                                                             ; SNUBBULL
	db 0                                                             ; GRANBULL
	db 0                                                             ; QWILFISH (0.2% usage)
	db SMOGON_SETUP                                                  ; SCIZOR (0.8% usage)
	db SMOGON_REST                                                   ; SHUCKLE (0.2% usage)
	db SMOGON_SLEEP_TALK | SMOGON_REST | SMOGON_SETUP | SMOGON_THREAT; HERACROSS (6.0% usage)
	db 0                                                             ; SNEASEL
	db 0                                                             ; TEDDIURSA
	db SMOGON_SLEEP_TALK | SMOGON_SETUP                              ; URSARING (0.1% usage)
	db 0                                                             ; SLUGMA
	db 0                                                             ; MAGCARGO
	db 0                                                             ; SWINUB
	db SMOGON_SLEEP_TALK | SMOGON_REST                               ; PILOSWINE (0.5% usage)
	db 0                                                             ; CORSOLA
	db 0                                                             ; REMORAID
	db 0                                                             ; OCTILLERY
	db 0                                                             ; DELIBIRD
	db 0                                                             ; MANTINE
	db SMOGON_REST | SMOGON_PHAZER | SMOGON_SETUP                    ; SKARMORY (22.3% usage)
	db 0                                                             ; HOUNDOUR
	db 0                                                             ; HOUNDOOM (1.5% usage)
	db SMOGON_SLEEP_TALK | SMOGON_REST                               ; KINGDRA (0.4% usage)
	db 0                                                             ; PHANPY
	db SMOGON_SLEEP_TALK                                             ; DONPHAN (0.4% usage)
	db SMOGON_SETUP                                                  ; PORYGON2 (1.2% usage)
	db 0                                                             ; STANTLER
	db SMOGON_SETUP                                                  ; SMEARGLE (2.3% usage)
	db 0                                                             ; TYROGUE
	db 0                                                             ; HITMONTOP
	db 0                                                             ; SMOOCHUM
	db 0                                                             ; ELEKID
	db 0                                                             ; MAGBY
	db 0                                                             ; MILTANK (4.9% usage)
	db 0                                                             ; BLISSEY (3.1% usage)
	db SMOGON_SLEEP_TALK | SMOGON_REST | SMOGON_PHAZER | SMOGON_THREAT; RAIKOU (34.1% usage)
	db 0                                                             ; ENTEI (0.3% usage)
	db SMOGON_SLEEP_TALK | SMOGON_REST | SMOGON_THREAT               ; SUICUNE (4.8% usage)
	db 0                                                             ; LARVITAR
	db 0                                                             ; PUPITAR
	db SMOGON_PHAZER                                                 ; TYRANITAR (30.4% usage)
	db 0                                                             ; LUGIA
	db 0                                                             ; HO_OH
	db 0                                                             ; CELEBI
	assert_table_length NUM_POKEMON
