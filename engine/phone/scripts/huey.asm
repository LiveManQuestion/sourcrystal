HueyPhoneCalleeScript: ; You call
	gettrainername STRING_BUFFER_3, SAILOR, HUEY1
	checkflag ENGINE_HUEY_READY_FOR_REMATCH
	iftrue HueyBattleReminder
	farscall PhoneScript_AnswerPhone_Male
	readvar VAR_WEEKDAY
	ifnotequal WEDNESDAY, .NotWednesday
	checktime NITE
	iftrue HueyWantsBattle

.NotWednesday:
	farsjump HueyHangUpScript

HueyBattleReminder:
	getlandmarkname STRING_BUFFER_5, LANDMARK_LIGHTHOUSE
	farsjump HueyReminderScript

HueyPhoneCallerScript: ; Calls you
	gettrainername STRING_BUFFER_3, SAILOR, HUEY1
	checkflag ENGINE_HUEY_READY_FOR_REMATCH
	iftrue HueyBattleReminder
	farscall PhoneScript_GreetPhone_Male
	farscall PhoneScript_Random2
	; 50% chance for a rematch
	ifequal 0, HueyWantsBattle
	farsjump Phone_GenericCall_Male

HueyWantsBattle:
	getlandmarkname STRING_BUFFER_5, LANDMARK_LIGHTHOUSE
	setflag ENGINE_HUEY_READY_FOR_REMATCH
	farsjump PhoneScript_WantsToBattle_Male
