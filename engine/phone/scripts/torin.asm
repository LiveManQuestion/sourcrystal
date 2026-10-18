TorinPhoneCalleeScript: ; You call
	gettrainername STRING_BUFFER_3, SCHOOLBOY, TORIN1
	checkflag ENGINE_TORIN_READY_FOR_REMATCH
	iftrue TorinBattleReminder
	farscall PhoneScript_AnswerPhone_Male
	checkcode VAR_WEEKDAY
	ifnotequal WEDNESDAY, .NotWednesday
	checktime NITE
	iftrue TorinWantsBattle

.NotWednesday:
	farjump TorinSchoolScript

TorinBattleReminder:
	getlandmarkname STRING_BUFFER_5, LANDMARK_ROUTE_14
	farjump TorinReminderScript

TorinPhoneCallerScript: ; Calls you
	gettrainername STRING_BUFFER_3, SCHOOLBOY, TORIN1
	checkflag ENGINE_TORIN_READY_FOR_REMATCH
	iftrue TorinBattleReminder
	farscall PhoneScript_GreetPhone_Male
	farscall PhoneScript_Random2
	; 50% chance for a rematch
	ifequal 0, TorinWantsBattle
	farjump Phone_GenericCall_Male

TorinWantsBattle:
	getlandmarkname STRING_BUFFER_5, LANDMARK_ROUTE_14
	setflag ENGINE_TORIN_READY_FOR_REMATCH
	farjump PhoneScript_WantsToBattle_Male
