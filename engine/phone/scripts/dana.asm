DanaPhoneCalleeScript: ; You call
	gettrainername STRING_BUFFER_3, LASS, DANA1
	checkflag ENGINE_DANA_HAS_THUNDERSTONE
	iftrue DanaThunderstoneReminder
	checkflag ENGINE_DANA_READY_FOR_REMATCH
	iftrue DanaBattleReminder
	farscall PhoneScript_AnswerPhone_Female
	readvar VAR_WEEKDAY
	ifnotequal THURSDAY, .NotThursday
	checktime NITE
	iftrue DanaWantsBattle

.NotThursday:
	checkflag ENGINE_DANA_GAVE_THUNDERSTONE
	iftrue .skipThunderStone
	; 9% chance when you call them
	farscall PhoneScript_Random11
	ifequal 0, DanaHasThunderstone
	setflag ENGINE_DANA_GAVE_THUNDERSTONE
.skipThunderStone:
	farsjump DanaHangUpScript

DanaBattleReminder:
	getlandmarkname STRING_BUFFER_5, LANDMARK_ROUTE_38
	farsjump DanaReminderScript

DanaThunderstoneReminder:
	getlandmarkname STRING_BUFFER_5, LANDMARK_ROUTE_38
	farsjump DanaComePickUpScript

DanaPhoneCallerScript: ; Calls you
	gettrainername STRING_BUFFER_3, LASS, DANA1
	checkflag ENGINE_DANA_HAS_THUNDERSTONE
	iftrue DanaThunderstoneReminder
	checkflag ENGINE_DANA_READY_FOR_REMATCH
	iftrue DanaBattleReminder
	farscall PhoneScript_GreetPhone_Female
	; 33% chance when they call you
	farscall PhoneScript_Random3
	ifequal 0, DanaHasThunderstone
	setflag ENGINE_DANA_GAVE_THUNDERSTONE
	farscall PhoneScript_Random2
	; 50% chance for a rematch
	ifequal 0, DanaWantsBattle
	farscall PhoneScript_Random3
	ifequal 0, DanaFoundRare
	farsjump Phone_GenericCall_Female

DanaWantsBattle:
	getlandmarkname STRING_BUFFER_5, LANDMARK_ROUTE_38
	setflag ENGINE_DANA_READY_FOR_REMATCH
	farsjump PhoneScript_WantsToBattle_Female

DanaFoundRare:
	farsjump Phone_CheckIfUnseenRare_Female

DanaHasThunderstone:
	setflag ENGINE_DANA_HAS_THUNDERSTONE
	getlandmarkname STRING_BUFFER_5, LANDMARK_ROUTE_38
	farsjump PhoneScript_FoundItem_Female
