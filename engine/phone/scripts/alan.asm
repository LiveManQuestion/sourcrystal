AlanPhoneCalleeScript: ; You call
	gettrainername STRING_BUFFER_3, SCHOOLBOY, ALAN1
	checkflag ENGINE_ALAN_HAS_FIRE_STONE
	iftrue AlanFireStoneReminder
	checkflag ENGINE_ALAN_READY_FOR_REMATCH
	iftrue AlanBattleReminder
	farscall PhoneScript_AnswerPhone_Male
	readvar VAR_WEEKDAY
	ifnotequal WEDNESDAY, .NotWednesday
	checktime DAY
	iftrue AlanWantsBattle
	checktime EVE
	iftrue AlanWantsBattle

.NotWednesday:
	checkflag ENGINE_ALAN_GAVE_FIRE_STONE
	iftrue .skipFireStone
	; 9% chance when you call them
	farscall PhoneScript_Random11
	ifequal 0, AlanHasFireStone
.skipFireStone
	farsjump AlanHangUpScript

AlanBattleReminder:
	getlandmarkname STRING_BUFFER_5, LANDMARK_ROUTE_36
	farsjump AlanReminderScript

AlanFireStoneReminder:
	getlandmarkname STRING_BUFFER_5, LANDMARK_ROUTE_36
	farsjump AlanComePickUpScript

AlanPhoneCallerScript: ; Calls you
	gettrainername STRING_BUFFER_3, SCHOOLBOY, ALAN1
	checkflag ENGINE_ALAN_HAS_FIRE_STONE
	iftrue AlanFireStoneReminder
	checkflag ENGINE_ALAN_READY_FOR_REMATCH
	iftrue AlanBattleReminder
	farscall PhoneScript_GreetPhone_Male
	; 33% chance when they call you
	farscall PhoneScript_Random3
	ifequal 0, AlanHasFireStone
	setflag ENGINE_ALAN_GAVE_FIRE_STONE
	farscall PhoneScript_Random2
	; 50% chance for a rematch
	ifequal 0, AlanWantsBattle
	farsjump Phone_GenericCall_Male

AlanWantsBattle:
	getlandmarkname STRING_BUFFER_5, LANDMARK_ROUTE_36
	setflag ENGINE_ALAN_READY_FOR_REMATCH
	farsjump PhoneScript_WantsToBattle_Male

AlanHasFireStone:
	setflag ENGINE_ALAN_HAS_FIRE_STONE
	getlandmarkname STRING_BUFFER_5, LANDMARK_ROUTE_36
	farsjump PhoneScript_FoundItem_Male
