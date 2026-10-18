KylerPhoneCalleeScript: ; You call
	gettrainername STRING_BUFFER_3, FISHER, KYLER1
	checkflag ENGINE_KYLER_READY_FOR_REMATCH
	iftrue KylerBattleReminder
	farscall PhoneScript_AnswerPhone_Male
	checkcode VAR_WEEKDAY
	ifnotequal THURSDAY, .NotWednesday
	checktime DAY
	iftrue KylerWantsBattle
	checktime EVE
	iftrue KylerWantsBattle

.NotWednesday:
	farjump KylerFishingTipsScript

KylerBattleReminder:
	getlandmarkname STRING_BUFFER_5, LANDMARK_ROUTE_12
	farjump KylerReminderScript

KylerPhoneCallerScript: ; Calls you
	gettrainername STRING_BUFFER_3, FISHER, KYLER1
	checkflag ENGINE_KYLER_READY_FOR_REMATCH
	iftrue KylerBattleReminder
	farscall PhoneScript_GreetPhone_Male
	farscall PhoneScript_Random2
	; 50% chance for a rematch
	ifequal 0, KylerWantsBattle
	farjump Phone_GenericCall_Male

KylerWantsBattle:
	getlandmarkname STRING_BUFFER_5, LANDMARK_ROUTE_12
	setflag ENGINE_KYLER_READY_FOR_REMATCH
	farjump PhoneScript_WantsToBattle_Male