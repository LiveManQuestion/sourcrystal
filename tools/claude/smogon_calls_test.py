"""Direct checks of Smogon AI helpers, called from the overworld with
game_call.py on hand-made battle states:
- AISmogon_PickedMoveKOsFirst (smogon.asm), the reason SwitchSmogon stays
  in to KO the player first: the carry, and that wEnemyMoveStruct,
  wCurDamage and wCriticalHit come back unchanged.
- AISmogon_PenalizeAsleepActive (smogon_switch.asm): the sleep or freeze
  penalty taken off the active Pokemon's score.
- AISmogon_EnemyHasUsefulBoosts (smogon.asm): which boosts keep the active
  Pokemon in.
- AISmogon_GetSetupBoost and AISmogon_SetupPower (smogon_switch.asm): the
  credit a Pokemon that can boost safely gets in the KO race.
- AISmogon_ScoreActive's stalemate flag (wSmogonAIActiveStalled), on
  positions from Koga 2 against the save's party.
- AI_Smogon_Explosion, AI_Smogon_Toxic, AISmogon_SpikesFirst,
  AI_Smogon_Heal and AI_Smogon_Substitute on positions from Koga 2, Misty 2,
  Whitney 2 and Jasmine 2 against the save's party.
- AISmogon_PickedLeadMoveFirst (smogon.asm): when Spore or Spikes keeps
  the active Pokemon in.

usage: smogon_calls_test.py ROM SYM SAVE.ram    (last line RESULT: ALL OK)"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from game_call import Game
from pokedata import BASE_TYPES, MOVE_IDS, TYPES, SPECIES, CONST
rom, sym, ram = sys.argv[1:4]
g = Game(rom, sym, open(ram, 'rb').read()); g.boot()
m = g.pb.memory
A = g.addr
def w(name, v, off=0): m[A(name) + off] = v
def word(name, v): m[A(name)] = v >> 8; m[A(name) + 1] = v & 0xff
MARK = [0xa1 + i for i in range(7)]
def setup(move='ICE_BEAM', php=1, espd=200, pspd=100, status=0, psub4=0, weather=0):
    w('wCurEnemyMove', MOVE_IDS[move]); w('wEnemyMonMoves', MOVE_IDS[move])
    for i, v in enumerate(MARK): w('wEnemyMoveStruct', v, i)
    word('wCurDamage', 0x1234); w('wCriticalHit', 1)
    w('wEnemyMonSpecies', SPECIES['SNORLAX']); w('wBattleMonSpecies', SPECIES['SNORLAX'])
    w('wEnemyMonLevel', 50); w('wBattleMonLevel', 50)
    for n in ('wEnemyMonAttack', 'wEnemyMonDefense', 'wEnemyMonSpclAtk', 'wEnemyMonSpclDef',
              'wBattleMonAttack', 'wBattleMonDefense', 'wBattleMonSpclAtk', 'wBattleMonSpclDef'):
        word(n, 100)
    word('wEnemyMonSpeed', espd); word('wBattleMonSpeed', pspd)
    word('wBattleMonHP', php); word('wBattleMonMaxHP', max(php, 100))
    for n in ('wEnemyMonType1', 'wEnemyMonType2', 'wBattleMonType1', 'wBattleMonType2'):
        w(n, TYPES['NORMAL'])
    for n in ('wEnemyMonItem', 'wBattleMonItem', 'wPlayerScreens', 'wEnemyScreens', 'wEnemySubStatus5',
              'wPlayerSubStatus3', 'wPlayerSubStatus5', 'wBattleMonStatus'):
        w(n, 0)
    w('wPlayerSubStatus4', psub4); w('wEnemyMonStatus', status); w('wBattleWeather', weather)
    for k in range(7):
        w('wEnemyStatLevels', 7, k); w('wPlayerStatLevels', 7, k)
cases = [
    ('faster sure KO', {}, True),
    ('slower', dict(espd=50), False),
    ('slower, priority', dict(move='QUICK_ATTACK', espd=50), True),
    ('player healthy', dict(php=999), False),
    ('asleep', dict(status=2), False),
    ('player substitute', dict(psub4=1 << CONST['SUBSTATUS_SUBSTITUTE']), False),
    ('hyper beam', dict(move='HYPER_BEAM'), False),
]
ok = True
for name, kw, exp in cases:
    setup(**kw)
    r = g.call('AISmogon_PickedMoveKOsFirst')
    carry = bool(g.result['F'] & 0x10)
    kept = [m[A('wEnemyMoveStruct') + i] for i in range(7)] == MARK and \
        (m[A('wCurDamage')] << 8 | m[A('wCurDamage') + 1]) == 0x1234 and m[A('wCriticalHit')] == 1
    good = carry == exp and kept
    ok &= good
    print('PASS' if good else 'FAIL', name, 'carry', carry, 'expected', exp, 'state kept', kept)

P = CONST
asleep_cases = [
    # (name, status, has Sleep Talk, score before, score after)
    ('asleep 3 turns', 3, False, 128, 128 - P['SMOGON_PENALTY_ASLEEP']),
    ('asleep 2 turns', 2, False, 128, 128 - P['SMOGON_PENALTY_ASLEEP']),
    ('asleep, wakes up this turn', 1, False, 128, 128),
    ('asleep with Sleep Talk', 3, True, 128, 128 - P['SMOGON_PENALTY_SLEEP_TALK']),
    ('frozen', 1 << P['FRZ'], False, 128, 128 - P['SMOGON_PENALTY_FROZEN']),
    ('awake', 0, False, 128, 128),
    ('paralyzed', 1 << P['PAR'], False, 128, 128),
    ('asleep, low score floors at 0', 3, False, 10, 0),
]
for name, status, sleep_talk, before, after in asleep_cases:
    w('wEnemyMonStatus', status)
    w('wEnemyAISwitchScore', before)
    w('wSmogonAIMon', 0)
    moves = ['SURF', 'REST', 'SLEEP_TALK' if sleep_talk else 'ICE_BEAM', 'ACID_ARMOR']
    for i, mv in enumerate(moves):
        w('wOTPartyMon1Moves', MOVE_IDS[mv], i)
    g.call('AISmogon_PenalizeAsleepActive')
    got = m[A('wEnemyAISwitchScore')]
    good = got == after
    ok &= good
    print('PASS' if good else 'FAIL', name, 'score', got, 'expected', after)

LEVELS = ['wEnemyAtkLevel', 'wEnemyDefLevel', 'wEnemySpdLevel', 'wEnemySAtkLevel', 'wEnemySDefLevel',
          'wEnemyAccLevel', 'wEnemyEvaLevel']
boost_cases = [
    # (name, {stat level: value}, player's revealed moves, player Attack, Sp.Atk, expected carry)
    ('acid armor vs surf', {'wEnemyDefLevel': 9}, ['SURF'], 100, 100, False),
    ('acid armor vs body slam', {'wEnemyDefLevel': 9}, ['BODY_SLAM'], 100, 100, True),
    ('amnesia vs surf', {'wEnemySDefLevel': 9}, ['SURF'], 100, 100, True),
    ('amnesia vs body slam', {'wEnemySDefLevel': 9}, ['BODY_SLAM'], 100, 100, False),
    # (Ditto has no SmogonExpectedAttacks entry, so its stats decide)
    ('acid armor, nothing revealed, physical stats', {'wEnemyDefLevel': 9}, [], 200, 100, True),
    ('acid armor, nothing revealed, special stats', {'wEnemyDefLevel': 9}, [], 100, 200, False),
    ('curse attack', {'wEnemyAtkLevel': 8, 'wEnemySpdLevel': 6}, ['SURF'], 100, 100, True),
    ('growth', {'wEnemySAtkLevel': 8}, ['SURF'], 100, 100, True),
    ('only lowered', {'wEnemySpdLevel': 5, 'wEnemyDefLevel': 7}, ['SURF'], 100, 100, False),
    ('none', {}, ['SURF'], 100, 100, False),
]
for name, levels, used, atk, spa, exp in boost_cases:
    for n in LEVELS:
        w(n, levels.get(n, 7))
    for i in range(4):
        w('wPlayerUsedMoves', MOVE_IDS[used[i]] if i < len(used) else 0, i)
    word('wBattleMonAttack', atk); word('wBattleMonSpclAtk', spa)
    w('wBattleMonSpecies', SPECIES['DITTO'])
    g.call('AISmogon_EnemyHasUsefulBoosts')
    carry = bool(g.result['F'] & 0x10)
    good = carry == exp
    ok &= good
    print('PASS' if good else 'FAIL', name, 'carry', carry, 'expected', exp)

setup_cases = [
    # (name, candidate moves, its types, threat, player's revealed moves, expected SMOGON_SETUP_*)
    ('swords dance, surf-only player', ['SLUDGE_BOMB', 'SWORDS_DANCE', 'HYDRO_PUMP', 'SUBSTITUTE'],
     ('WATER', 'POISON'), 43, ['SURF', 'GROWTH', 'SLEEP_TALK', 'REST'], 'SMOGON_SETUP_DOUBLE'),
    # (Swords Dance only needs two hits not to KO: in front of a Vaporeon at
    # +2, three hits KO Tentacruel)
    ('swords dance, +2 growth player', ['SLUDGE_BOMB', 'SWORDS_DANCE', 'HYDRO_PUMP', 'SUBSTITUTE'],
     ('WATER', 'POISON'), 85, ['SURF', 'GROWTH', 'SLEEP_TALK', 'REST'], 'SMOGON_SETUP_DOUBLE'),
    ('swords dance, player hits hard', ['SLUDGE_BOMB', 'SWORDS_DANCE', 'HYDRO_PUMP', 'SUBSTITUTE'],
     ('WATER', 'POISON'), 130, ['SURF', 'GROWTH', 'SLEEP_TALK', 'REST'], 'SMOGON_SETUP_NONE'),
    ('swords dance, player roars', ['SLUDGE_BOMB', 'SWORDS_DANCE', 'HYDRO_PUMP', 'SUBSTITUTE'],
     ('WATER', 'POISON'), 43, ['SURF', 'ROAR', 'SLEEP_TALK', 'REST'], 'SMOGON_SETUP_NONE'),
    ('swords dance, player hazes', ['SLUDGE_BOMB', 'SWORDS_DANCE', 'HYDRO_PUMP', 'SUBSTITUTE'],
     ('WATER', 'POISON'), 43, ['SURF', 'HAZE', 'SLEEP_TALK', 'REST'], 'SMOGON_SETUP_NONE'),
    ('growth', ['SURF', 'GROWTH', 'REST', 'SLEEP_TALK'], ('WATER', 'WATER'), 43,
     ['SURF', 'GROWTH', 'SLEEP_TALK', 'REST'], 'SMOGON_SETUP_SPECIAL'),
    ('growth, player hits harder', ['SURF', 'GROWTH', 'REST', 'SLEEP_TALK'], ('WATER', 'WATER'), 70,
     ['SURF', 'GROWTH', 'SLEEP_TALK', 'REST'], 'SMOGON_SETUP_NONE'),
    ('curse', ['CURSE', 'EARTHQUAKE', 'REST', 'HIDDEN_POWER'], ('WATER', 'GROUND'), 43,
     ['SURF', 'GROWTH', 'SLEEP_TALK', 'REST'], 'SMOGON_SETUP_PHYSICAL'),
    ('curse as a ghost', ['CURSE', 'SHADOW_BALL', 'REST', 'HIDDEN_POWER'], ('GHOST', 'POISON'), 43,
     ['SURF', 'GROWTH', 'SLEEP_TALK', 'REST'], 'SMOGON_SETUP_NONE'),
    ('no boosting move', ['SURF', 'ICE_BEAM', 'REST', 'ACID_ARMOR'], ('WATER', 'WATER'), 43,
     ['SURF', 'GROWTH', 'SLEEP_TALK', 'REST'], 'SMOGON_SETUP_NONE'),
]
length = A('wOTPartyMon2') - A('wOTPartyMon1')
for name, moves, types, threat, used, exp in setup_cases:
    w('wCurOTMon', 0); w('wSmogonAIMon', 1)
    for i, mv in enumerate(moves):
        w('wOTPartyMon1Moves', MOVE_IDS[mv], length + i)
    word('wOTPartyMon1HP', 0); m[A('wOTPartyMon1HP') + length] = 253 >> 8; m[A('wOTPartyMon1HP') + length + 1] = 253 & 0xff
    w('wSmogonAITypes', TYPES[types[0]]); w('wSmogonAITypes', TYPES[types[1]], 1)
    w('wSmogonAIThreat', threat >> 8); w('wSmogonAIThreat', threat & 0xff, 1)
    w('wBattleMonSpecies', SPECIES['VAPOREON'])
    for i in range(4):
        w('wPlayerUsedMoves', MOVE_IDS[used[i]], i)
    g.call('AISmogon_GetSetupBoost')
    got = g.result['A']
    good = got == CONST[exp]
    ok &= good
    print('PASS' if good else 'FAIL', 'setup:', name, 'got', got, 'expected', exp)

power_cases = [
    # (name, boost, power, type, expected power)
    ('double physical', 'SMOGON_SETUP_DOUBLE', 90, 'POISON', 180),
    ('double skips special', 'SMOGON_SETUP_DOUBLE', 120, 'WATER', 120),
    ('special x1.5', 'SMOGON_SETUP_SPECIAL', 120, 'WATER', 180),
    ('special skips physical', 'SMOGON_SETUP_SPECIAL', 100, 'GROUND', 100),
    ('physical x1.5', 'SMOGON_SETUP_PHYSICAL', 100, 'GROUND', 150),
    ('double caps at 255', 'SMOGON_SETUP_DOUBLE', 150, 'NORMAL', 255),
    ('none', 'SMOGON_SETUP_NONE', 100, 'GROUND', 100),
]
for name, boost, power, typ, exp in power_cases:
    w('wSmogonAISetupBoost', CONST[boost])
    g.call('AISmogon_SetupPower', D=power, E=TYPES[typ])
    got = g.result['D']
    good = got == exp
    ok &= good
    print('PASS' if good else 'FAIL', 'setup power:', name, 'got', got, 'expected', exp)

# AISmogon_ScoreActive's stalemate flag, on positions from Koga 2 vs the
# save's party: the enemy's active Pokemon is OT party slot 0, and the
# player's is a copy of a save party member.
OT_FIELDS = ('Species', 'Item', 'Moves', 'DVs', 'PP', 'Level', 'Status', 'HP', 'MaxHP', 'Attack')
def set_ot(mon, slot=0):
    first = A('wOTPartyMon1Species')
    off = {f: A('wOTPartyMon1' + f) - first for f in OT_FIELDS}
    base = first + slot * (A('wOTPartyMon2') - A('wOTPartyMon1'))
    m[base] = mon['species']; m[base + off['Item']] = mon['item']; m[base + off['Level']] = mon['level']
    m[base + off['Status']] = 0
    for i in range(4):
        m[base + off['Moves'] + i] = mon['moves'][i]; m[base + off['PP'] + i] = mon['pp'][i]
    m[base + off['DVs']], m[base + off['DVs'] + 1] = mon['dvs']
    for f, v in (('HP', mon['hp']), ('MaxHP', mon['max_hp'])):
        m[base + off[f]] = v >> 8; m[base + off[f] + 1] = v & 0xff
    for k, v in enumerate(mon['stats']):
        m[base + off['Attack'] + 2 * k] = v >> 8; m[base + off['Attack'] + 2 * k + 1] = v & 0xff
    if slot:
        return
    w('wOTPartyCount', 1); w('wOTPartySpecies', mon['species']); w('wOTPartySpecies', 0xff, 1)
    w('wCurOTMon', 0); w('wEnemyMonSpecies', mon['species']); w('wEnemyMonStatus', 0)
    w('wEnemyMonLevel', mon['level'])
    w('wEnemyMonType1', BASE_TYPES[mon['species']][0]); w('wEnemyMonType2', BASE_TYPES[mon['species']][1])
    word('wEnemyMonHP', mon['hp']); word('wEnemyMonMaxHP', mon['max_hp'])
    for k, v in enumerate(mon['stats']):  # the battle stats AIDamageCalc reads
        m[A('wEnemyMonAttack') + 2 * k] = v >> 8; m[A('wEnemyMonAttack') + 2 * k + 1] = v & 0xff
    for i in range(4):
        w('wEnemyMonMoves', mon['moves'][i], i); w('wEnemyMonPP', mon['pp'][i], i)
def set_player(slot, types, used):
    src = A('wPartyMon%dSpecies' % slot)
    for f in ('Species', 'Item', 'Level', 'Status'):
        m[A('wBattleMon' + f)] = m[A('wPartyMon%d%s' % (slot, f))]
    for f, n in (('Moves', 4), ('DVs', 2), ('PP', 4), ('HP', 2), ('MaxHP', 2), ('Attack', 10)):
        for i in range(n):
            m[A('wBattleMon' + f) + i] = m[A('wPartyMon%d%s' % (slot, f)) + i]
    w('wBattleMonType1', TYPES[types[0]]); w('wBattleMonType2', TYPES[types[1]])
    for i in range(4):
        w('wPlayerUsedMoves', MOVE_IDS[used[i]] if i < len(used) else 0, i)
CROBAT = dict(species=SPECIES['CROBAT'], level=86, hp=161, max_hp=268, stats=[185, 168, 254, 151, 168],
              moves=[MOVE_IDS[x] for x in ('HAZE', 'TOXIC', 'WING_ATTACK', 'REST')], pp=[30, 10, 29, 10],
              dvs=(255, 255), item=0)
QWILFISH = dict(species=SPECIES['QWILFISH'], level=85, hp=231, max_hp=231, stats=[192, 158, 175, 124, 124],
                moves=[MOVE_IDS[x] for x in ('CURSE', 'SLUDGE_BOMB', 'HYDRO_PUMP', 'SPIKES')], pp=[10, 10, 5, 20],
                dvs=(255, 255), item=0)
for n in ('wPlayerScreens', 'wEnemyScreens', 'wBattleWeather', 'wPlayerSubStatus1', 'wPlayerSubStatus3',
          'wPlayerSubStatus4', 'wPlayerSubStatus5', 'wEnemySubStatus1', 'wEnemySubStatus4', 'wEnemySubStatus5'):
    w(n, 0)
for k in range(7):
    w('wPlayerStatLevels', 7, k); w('wEnemyStatLevels', 7, k)
party = [m[A('wPartyMon%dSpecies' % k)] for k in range(1, 7)]
stall_cases = [
    # (name, enemy, player's party slot, its types, revealed moves, expected stalled)
    ('crobat vs earthquake steelix', CROBAT, 'STEELIX', ('STEEL', 'GROUND'), ['EARTHQUAKE'], True),
    ('qwilfish vs earthquake steelix', QWILFISH, 'STEELIX', ('STEEL', 'GROUND'), ['EARTHQUAKE'], False),
    ('crobat vs zapdos', CROBAT, 'ZAPDOS', ('ELECTRIC', 'FLYING'), ['THUNDER'], False),
]
for name, mon, player, types, used, exp in stall_cases:
    if SPECIES[player] not in party:
        print('SKIP', name, '(no', player, 'in the save party)')
        continue
    set_ot(mon)
    set_player(party.index(SPECIES[player]) + 1, types, used)
    g.call('AISmogon_ScoreActive', frames=600)
    got = bool(m[A('wSmogonAIActiveStalled')])
    good = got == exp
    ok &= good
    print('PASS' if good else 'FAIL', 'stalemate:', name, 'stalled', got, 'expected', exp,
          'score', m[A('wEnemyAISwitchScore')])

# AI_Smogon_Explosion on positions from Koga 2 and Misty 2 vs the save's
# Zapdos and Vaporeon: the score (20) it leaves for Explosion (16 when it
# explodes).
GENGAR = dict(species=SPECIES['GENGAR'], level=84, hp=220, max_hp=220, stats=[139, 131, 215, 248, 156],
              moves=[MOVE_IDS[x] for x in ('EXPLOSION', 'ICE_PUNCH', 'THUNDERBOLT', 'DYNAMICPUNCH')],
              pp=[5, 15, 15, 5], dvs=(255, 255), item=0)
CLOYSTER = dict(species=SPECIES['CLOYSTER'], level=80, hp=194, max_hp=194, stats=[168, 317, 141, 165, 101],
                moves=[MOVE_IDS[x] for x in ('SURF', 'SPIKES', 'TOXIC', 'EXPLOSION')],
                pp=[15, 20, 10, 5], dvs=(127, 255), item=0)
boom_cases = [
    # (name, enemy, its HP, its Speed, the player's HP, expected score)
    ('gengar outspeeds and wins vs zapdos', GENGAR, 220, 215, 160, 20),
    # (Cloyster's lowest Explosion roll on Zapdos is 252: no sure KO at 280
    # HP, but it's clearly losing, so it trades anyway)
    ('cloyster loses to zapdos, no sure KO', CLOYSTER, 194, 141, 280, 16),
    ('cloyster loses to zapdos, sure KO', CLOYSTER, 194, 141, 200, 16),
    ('gengar doomed and outsped', GENGAR, 40, 100, 160, 16),
]
# (Spikes are down only for Cloyster, which would lay them first: with them
# not down, the handler looks for a Spikes move, which must keep
# wEnemyMoveStruct, the Explosion it then checks for a KO)
boom_cases = [c + ('ZAPDOS', ('ELECTRIC', 'FLYING'), ['THUNDER']) for c in boom_cases] + [
    # Gengar's lowest Explosion roll on a full-HP Vaporeon is 292 of 327
    ('gengar into a full-hp vaporeon', GENGAR, 220, 215, 327, 20, 'VAPOREON', ('WATER', 'WATER'), ['SURF']),
    # Explosion KOs, but Gengar's last move (Dynamic Punch) wouldn't
    ('weakened gengar into a weakened vaporeon', GENGAR, 120, 215, 250, 16, 'VAPOREON', ('WATER', 'WATER'), ['SURF']),
]
for name, mon, hp, speed, php, exp, player, ptypes, pused in boom_cases:
    if SPECIES[player] not in party:
        print('SKIP', name); continue
    set_ot(dict(mon, hp=hp))
    set_ot(QWILFISH, 1)
    w('wOTPartyCount', 2); w('wOTPartySpecies', QWILFISH['species'], 1); w('wOTPartySpecies', 0xff, 2)
    word('wEnemyMonSpeed', speed)
    set_player(party.index(SPECIES[player]) + 1, ptypes, pused)
    word('wBattleMonHP', php)
    w('wPlayerScreens', 1 << CONST['SCREENS_SPIKES'] if mon is CLOYSTER else 0)
    g.call('AIGetEnemyMove', A=MOVE_IDS['EXPLOSION'])
    w('wEnemyAIMoveScores', 20)
    g.call('AI_Smogon_Explosion', HL=A('wEnemyAIMoveScores'), frames=600)
    got = m[A('wEnemyAIMoveScores')]
    good = got == exp
    ok &= good
    print('PASS' if good else 'FAIL', 'explosion:', name, 'score', got, 'expected', exp,
          'matchup', m[A('wEnemyAISwitchScore')])
w('wPlayerScreens', 0)

# AI_Smogon_Explosion vs raised Defense (Jasmine 2's Forretress vs the
# save's Snorlax after two Curses): no trade without a sure KO.
FORRETRESS = dict(species=SPECIES['FORRETRESS'], level=76, hp=222, max_hp=222, stats=[164, 240, 88, 119, 119],
                  moves=[MOVE_IDS[x] for x in ('PIN_MISSILE', 'SPIKES', 'EXPLOSION', 'CURSE')],
                  pp=[19, 19, 5, 10], dvs=(255, 255), item=0)
curse_boom_cases = [
    # (name, the player's HP, expected score)
    ('forretress vs +2 snorlax', 352, 20),
    # (Explosion's lowest roll is below half its HP, where trades stop, so
    # it never explodes on it; the Cloyster cases above keep the losing
    # trade against unboosted Defense)
    ('forretress vs +2 snorlax, half HP', 177, 20),
]
for name, php, exp in curse_boom_cases:
    if SPECIES['SNORLAX'] not in party:
        print('SKIP', name); continue
    set_ot(FORRETRESS)
    set_ot(QWILFISH, 1)
    w('wOTPartyCount', 2); w('wOTPartySpecies', QWILFISH['species'], 1); w('wOTPartySpecies', 0xff, 2)
    set_player(party.index(SPECIES['SNORLAX']) + 1, ('NORMAL', 'NORMAL'), ['CURSE'])
    word('wBattleMonHP', php)
    # +2 Attack and Defense, -2 Speed: the battle stats hold the stages
    for k, (lvl, n) in enumerate(((9, 'Attack'), (9, 'Defense'), (5, 'Speed'))):
        w('wPlayerStatLevels', lvl, k)
        word('wBattleMon' + n, (m[A('wBattleMon' + n)] << 8 | m[A('wBattleMon' + n) + 1]) * (lvl - 5) // 2
             if lvl > 7 else (m[A('wBattleMon' + n)] << 8 | m[A('wBattleMon' + n) + 1]) // 2)
    w('wPlayerScreens', 1 << CONST['SCREENS_SPIKES'])
    g.call('AIGetEnemyMove', A=MOVE_IDS['EXPLOSION'])
    w('wEnemyAIMoveScores', 20)
    g.call('AI_Smogon_Explosion', HL=A('wEnemyAIMoveScores'), frames=600)
    got = m[A('wEnemyAIMoveScores')]
    good = got == exp
    ok &= good
    print('PASS' if good else 'FAIL', 'explosion:', name, 'score', got, 'expected', exp,
          'matchup', m[A('wEnemyAISwitchScore')])
for k in range(7):
    w('wPlayerStatLevels', 7, k)
w('wPlayerScreens', 0)

# AI_Smogon_Toxic: Toxic is for walls, not what our attacks KO soon.
TENTACRUEL = dict(species=SPECIES['TENTACRUEL'], level=85, hp=256, max_hp=256, stats=[149, 141, 200, 166, 234],
                  moves=[MOVE_IDS[x] for x in ('SURF', 'SLUDGE_BOMB', 'TOXIC', 'GIGA_DRAIN')],
                  pp=[15, 10, 10, 5], dvs=(255, 255), item=0)
TOXIC_ONLY = dict(TENTACRUEL, moves=[MOVE_IDS[x] for x in ('TOXIC', 'SUPERSONIC', 'SPIKES', 'HAZE')])
toxic_cases = [
    # (name, enemy, the player's Pokemon, its types, its revealed moves, expected score)
    # (not Snorlax or Zapdos: their usual sets have Rest, which sleeps Toxic off)
    ('tentacruel vs exeggutor (sludge bomb KOs soon)', TENTACRUEL, 'EXEGGUTOR', ('GRASS', 'PSYCHIC_TYPE'),
     ['PSYCHIC_M'], 21),
    ('no attacks vs exeggutor (a wall to it)', TOXIC_ONLY, 'EXEGGUTOR', ('GRASS', 'PSYCHIC_TYPE'),
     ['PSYCHIC_M'], 19),
]
for name, mon, player, ptypes, pused, exp in toxic_cases:
    if SPECIES[player] not in party:
        print('SKIP', name); continue
    set_ot(mon)
    set_player(party.index(SPECIES[player]) + 1, ptypes, pused)
    w('wEnemyAIMoveScores', 20)
    g.call('AI_Smogon_Toxic', HL=A('wEnemyAIMoveScores'), frames=600)
    got = m[A('wEnemyAIMoveScores')]
    good = got == exp
    ok &= good
    print('PASS' if good else 'FAIL', 'toxic:', name, 'score', got, 'expected', exp,
          'our turns', m[A('wSmogonAIOurTurns')] if 'wSmogonAIOurTurns' in g.sym else '?')

# AISmogon_SpikesFirst: no setup before Spikes are down, while the player
# (the save's party) has Pokemon left to switch in.
spikes_cases = [
    ('spikes not down yet', ('PIN_MISSILE', 'SPIKES', 'EXPLOSION', 'CURSE'), 0, True),
    ('spikes down', ('PIN_MISSILE', 'SPIKES', 'EXPLOSION', 'CURSE'), 1 << CONST['SCREENS_SPIKES'], False),
    ('no spikes move', ('PIN_MISSILE', 'TOXIC', 'EXPLOSION', 'CURSE'), 0, False),
]
for name, moves, screens, exp in spikes_cases if 'AISmogon_SpikesFirst' in g.sym else []:
    for i, mv in enumerate(moves):
        w('wEnemyMonMoves', MOVE_IDS[mv], i)
    w('wPlayerScreens', screens)
    g.call('AIGetEnemyMove', A=MOVE_IDS['CURSE'])  # the move being scored
    g.call('AISmogon_SpikesFirst')
    carry = bool(g.result['F'] & 0x10)
    kept = m[A('wEnemyMoveStruct')] == MOVE_IDS['CURSE']
    good = carry == exp and kept
    ok &= good
    print('PASS' if good else 'FAIL', 'spikes first:', name, 'carry', carry, 'expected', exp,
          'move being scored kept', kept)
w('wPlayerScreens', 0)
# AI_Smogon_Heal: heal only when the player's strongest attack would KO us
# soon, and not when we KO it first in two hits (positions from Koga 2 and
# Whitney 2). Checking our attacks must keep wEnemyMoveStruct, the heal.
VENUSAUR = dict(species=SPECIES['VENUSAUR'], level=88, hp=244, max_hp=244, stats=[173, 172, 172, 207, 207],
                moves=[MOVE_IDS[x] for x in ('GROWTH', 'RAZOR_LEAF', 'SYNTHESIS', 'RECOVER')],
                pp=[40, 25, 5, 5], dvs=(236, 255), item=0)
BLISSEY = dict(species=SPECIES['BLISSEY'], level=76, hp=496, max_hp=496, stats=[30, 43, 111, 141, 233],
               moves=[MOVE_IDS[x] for x in ('SOFTBOILED', 'HEAL_BELL', 'ICE_BEAM', 'FLAMETHROWER')],
               pp=[10, 5, 10, 15], dvs=(255, 255), item=0)
# Synthesis heals a quarter at night (poked when the call starts: the
# overworld rewrites the time from the clock every frame).
NIGHT = {'wTimeOfDay': 2, 'hHours': 23}  # NITE_F, constants/ram_constants.asm
DAY = {'wTimeOfDay': 1, 'hHours': 12}  # DAY_F
heal_cases = [
    # (name, enemy, its HP, Sp.Atk stage, move, the player's Pokemon, its types, revealed moves, expected score,
    # time of day: night if left out)
    # (Surf takes 48 of Venusaur's 84 HP; Razor Leaf needs 3 hits on Vaporeon, 2 after Growth)
    ('venusaur recover vs vaporeon', VENUSAUR, 84, 7, 'RECOVER', 'VAPOREON', ('WATER', 'WATER'),
     ['SURF'], 18),
    ('+2 venusaur recover vs vaporeon (KOs first)', VENUSAUR, 84, 9, 'RECOVER', 'VAPOREON',
     ('WATER', 'WATER'), ['SURF'], 21),
    ('venusaur synthesis at night (1/4) vs vaporeon', VENUSAUR, 84, 7, 'SYNTHESIS', 'VAPOREON', ('WATER', 'WATER'),
     ['SURF'], 20),
    ('+2 venusaur synthesis at night (1/4) vs vaporeon (KOs first)', VENUSAUR, 84, 9, 'SYNTHESIS', 'VAPOREON',
     ('WATER', 'WATER'), ['SURF'], 21),
    ('blissey softboiled vs vaporeon', BLISSEY, 200, 7, 'SOFTBOILED', 'VAPOREON', ('WATER', 'WATER'),
     ['SURF'], 18),
    ('venusaur synthesis by day (1/2) vs vaporeon', VENUSAUR, 84, 7, 'SYNTHESIS', 'VAPOREON', ('WATER', 'WATER'),
     ['SURF'], 18, DAY),
]
for name, mon, hp, stage, move, player, ptypes, pused, exp, *time in heal_cases:
    if SPECIES[player] not in party:
        print('SKIP', name); continue
    set_ot(dict(mon, hp=hp))
    # the battle stat holds the stage, like after Growth
    w('wEnemySAtkLevel', stage); word('wEnemyMonSpclAtk', mon['stats'][3] * (stage - 5) // 2)
    set_player(party.index(SPECIES[player]) + 1, ptypes, pused)
    w('wBattleWeather', 0)
    g.call('AIGetEnemyMove', A=MOVE_IDS[move])
    w('wEnemyAIMoveScores', 20)
    g.call('AI_Smogon_Heal', HL=A('wEnemyAIMoveScores'), frames=600, poke=time[0] if time else NIGHT)
    got = m[A('wEnemyAIMoveScores')]
    kept = m[A('wEnemyMoveStruct')] == MOVE_IDS[move]
    good = got == exp and kept
    ok &= good
    print('PASS' if good else 'FAIL', 'heal:', name, 'score', got, 'expected', exp, 'move being scored kept', kept)
w('wEnemySAtkLevel', 7)

# AI_Aggressive (scoring.asm) in Challenge Mode: the attack that does the
# most damage on average (AISmogon_ExpectedDamage), on positions from Koga 2
# and Misty 2 vs the save's Cloyster. Hydro Pump's highest roll is the
# biggest, but at 80% accuracy Sludge Bomb does more. Normal Mode still
# takes the highest roll.
QWILFISH_KOGA = dict(species=SPECIES['QWILFISH'], level=85, hp=231, max_hp=231, stats=[192, 158, 175, 124, 124],
                     moves=[MOVE_IDS[x] for x in ('CURSE', 'SLUDGE_BOMB', 'HYDRO_PUMP', 'SPIKES')],
                     pp=[10, 10, 5, 20], dvs=(255, 255), item=0)
TENTACRUEL_MISTY = dict(species=SPECIES['TENTACRUEL'], level=84, hp=118, max_hp=253, stats=[134, 139, 198, 164, 231],
                        moves=[MOVE_IDS[x] for x in ('SLUDGE_BOMB', 'SWORDS_DANCE', 'HYDRO_PUMP', 'SUBSTITUTE')],
                        pp=[8, 30, 3, 10], dvs=(127, 255), item=0)
aggressive_cases = [
    # (name, enemy, Attack stage, Challenge Mode, expected scores)
    ('qwilfish vs cloyster', QWILFISH_KOGA, 7, True, [20, 20, 21, 20]),
    ('qwilfish vs cloyster, normal mode', QWILFISH_KOGA, 7, False, [20, 21, 20, 20]),
    ('+2 tentacruel vs cloyster', TENTACRUEL_MISTY, 9, True, [20, 20, 21, 20]),
]
challenge = m[A('wChallengeMode')]
for name, mon, stage, cm, exp in aggressive_cases:
    if SPECIES['CLOYSTER'] not in party:
        print('SKIP', name); continue
    set_ot(mon)
    w('wEnemyAtkLevel', stage); word('wEnemyMonAttack', mon['stats'][0] * (stage - 5) // 2)
    set_player(party.index(SPECIES['CLOYSTER']) + 1, ('WATER', 'ICE'), ['SURF'])
    w('wBattleWeather', 0); w('wCriticalHit', 0)
    w('wChallengeMode', challenge | 1 if cm else challenge & ~1)
    for i in range(4):
        w('wEnemyAIMoveScores', 20, i)
    g.call('AI_Aggressive', frames=600)
    got = [m[A('wEnemyAIMoveScores') + i] for i in range(4)]
    good = got == exp
    ok &= good
    print('PASS' if good else 'FAIL', 'aggressive:', name, 'scores', got, 'expected', exp)
w('wChallengeMode', challenge); w('wEnemyAtkLevel', 7)

# AI_Smart_HiddenPower, then AI_Aggressive: Koga's +1 Venusaur's neutral
# Hidden Power Fire. Vanilla's bonus for base power 70 tied it with the
# stronger Razor Leaf on Snorlax; in Challenge Mode it only goes to the
# strongest attack (on Zapdos, which resists Razor Leaf).
VENUSAUR_KOGA = dict(species=SPECIES['VENUSAUR'], level=88, hp=244, max_hp=244, stats=[173, 172, 172, 207, 207],
                     moves=[MOVE_IDS[x] for x in ('GROWTH', 'RAZOR_LEAF', 'SYNTHESIS', 'HIDDEN_POWER')],
                     pp=[38, 25, 5, 14], dvs=(236, 255), item=0)
hidden_power_cases = [
    # (name, the player's Pokemon, its types, Challenge Mode, expected scores)
    ('venusaur vs snorlax', 'SNORLAX', ('NORMAL', 'NORMAL'), True, [20, 20, 21, 21]),
    ('venusaur vs snorlax, normal mode', 'SNORLAX', ('NORMAL', 'NORMAL'), False, [20, 20, 21, 20]),
    ('venusaur vs zapdos', 'ZAPDOS', ('ELECTRIC', 'FLYING'), True, [20, 21, 21, 19]),
]
for name, player, ptypes, cm, exp in hidden_power_cases:
    if SPECIES[player] not in party:
        print('SKIP', name); continue
    set_ot(VENUSAUR_KOGA)
    w('wEnemyMonDVs', VENUSAUR_KOGA['dvs'][0]); w('wEnemyMonDVs', VENUSAUR_KOGA['dvs'][1], 1)
    w('wEnemySAtkLevel', 8); word('wEnemyMonSpclAtk', 207 * 3 // 2)
    set_player(party.index(SPECIES[player]) + 1, ptypes, [])
    w('wBattleWeather', 0); w('wCriticalHit', 0)
    w('wChallengeMode', challenge | 1 if cm else challenge & ~1)
    for i in range(4):
        w('wEnemyAIMoveScores', 20, i)
    g.call('AI_Smart', frames=1200)
    g.call('AI_Aggressive', frames=600)
    got = [m[A('wEnemyAIMoveScores') + i] for i in range(4)]
    good = got == exp
    ok &= good
    print('PASS' if good else 'FAIL', 'hidden power:', name, 'scores', got, 'expected', exp)
w('wChallengeMode', challenge); w('wEnemySAtkLevel', 7)

# AISmogon_PlayerIsPhysical on the save's party: by the revealed attacks,
# else the expected ones (SmogonExpectedAttacks), else the stats.
physical_cases = [
    # (the player's Pokemon, its types, its revealed moves, expected carry)
    ('CLOYSTER', ('WATER', 'ICE'), [], False),  # Attack > Sp.Atk, but Surf
    ('CLOYSTER', ('WATER', 'ICE'), ['SPIKES'], False),
    ('CLOYSTER', ('WATER', 'ICE'), ['EXPLOSION'], True),
    ('SNORLAX', ('NORMAL', 'NORMAL'), [], True),
    ('STEELIX', ('STEEL', 'GROUND'), [], True),
    ('ZAPDOS', ('ELECTRIC', 'FLYING'), [], False),
    ('VAPOREON', ('WATER', 'WATER'), [], False),
]
for player, ptypes, pused, exp in physical_cases:
    if SPECIES[player] not in party:
        print('SKIP', player); continue
    set_player(party.index(SPECIES[player]) + 1, ptypes, pused)
    g.call('AISmogon_PlayerIsPhysical')
    got = bool(g.result['F'] & 0x10)
    good = got == exp
    ok &= good
    print('PASS' if good else 'FAIL', 'physical:', player, pused, 'carry', got, 'expected', exp)

# AI_Smogon_Setup: Acid Armor only against a physical attacker (Misty 2's
# Vaporeon vs the save's Cloyster, which attacks with Surf unless it has
# shown Explosion).
VAPOREON_MISTY = dict(species=SPECIES['VAPOREON'], level=78, hp=314, max_hp=314, stats=[117, 122, 129, 200, 176],
                      moves=[MOVE_IDS[x] for x in ('SURF', 'ICE_BEAM', 'REST', 'ACID_ARMOR')],
                      pp=[15, 10, 10, 40], dvs=(127, 255), item=0)
setup_cases = [
    # (name, the player's Pokemon, its types, its revealed moves, its Attack (None: its own), expected score)
    ('acid armor vs cloyster', 'CLOYSTER', ('WATER', 'ICE'), [], None, 22),
    ('acid armor vs surf cloyster', 'CLOYSTER', ('WATER', 'ICE'), ['SURF'], None, 22),
    # (a Snorlax too weak to threaten Vaporeon: it's physical, so boost)
    ('acid armor vs weak snorlax', 'SNORLAX', ('NORMAL', 'NORMAL'), ['DOUBLE_EDGE'], 40, 18),
]
for name, player, ptypes, pused, atk, exp in setup_cases:
    if SPECIES[player] not in party:
        print('SKIP', name); continue
    set_ot(VAPOREON_MISTY)
    set_player(party.index(SPECIES[player]) + 1, ptypes, pused)
    if atk:
        word('wBattleMonAttack', atk)
    w('wPlayerScreens', 1 << CONST['SCREENS_SPIKES']); w('wEnemySubStatus5', 0)
    g.call('AIGetEnemyMove', A=MOVE_IDS['ACID_ARMOR'])
    w('wEnemyAIMoveScores', 20)
    g.call('AI_Smogon_Setup', HL=A('wEnemyAIMoveScores'), frames=600)
    got = m[A('wEnemyAIMoveScores')]
    good = got == exp
    ok &= good
    print('PASS' if good else 'FAIL', 'setup:', name, 'score', got, 'expected', exp)
w('wPlayerScreens', 0)

# AI_Smogon_Setup vs a Pokemon that outheals our attacks (Misty's Tentacruel
# vs the save's Rest Vaporeon, which +2 Sludge Bomb doesn't 2HKO from full
# HP): keep boosting while it's safe, until the attack 2HKOs.
heal_setup_cases = [
    # (name, Attack stage, Tentacruel's HP, Vaporeon's revealed moves, expected score)
    ('+2 tentacruel vs vaporeon', 9, 158, [], 17),
    ('+2 tentacruel vs resttalk vaporeon', 9, 158, ['SURF', 'GROWTH', 'SLEEP_TALK', 'REST'], 17),
    ('+4 tentacruel vs vaporeon (2HKOs)', 11, 158, [], 22),
    ('+2 tentacruel below half HP', 9, 100, [], 20),
]
for name, stage, hp, pused, exp in heal_setup_cases:
    if SPECIES['VAPOREON'] not in party:
        print('SKIP', name); continue
    set_ot(dict(TENTACRUEL_MISTY, hp=hp))
    w('wEnemyMonDVs', TENTACRUEL_MISTY['dvs'][0]); w('wEnemyMonDVs', TENTACRUEL_MISTY['dvs'][1], 1)
    w('wEnemyAtkLevel', stage); word('wEnemyMonAttack', TENTACRUEL_MISTY['stats'][0] * (stage - 5) // 2)
    set_player(party.index(SPECIES['VAPOREON']) + 1, ('WATER', 'WATER'), pused)
    w('wBattleWeather', 0); w('wCriticalHit', 0); w('wEnemySubStatus5', 0)
    g.call('AIGetEnemyMove', A=MOVE_IDS['SWORDS_DANCE'])
    w('wEnemyAIMoveScores', 20)
    g.call('AI_Smogon_Setup', HL=A('wEnemyAIMoveScores'), frames=2500)
    got = m[A('wEnemyAIMoveScores')]
    good = got == exp
    ok &= good
    print('PASS' if good else 'FAIL', 'setup:', name, 'score', got, 'expected', exp)
w('wEnemyAtkLevel', 7)

# AI_Smogon_Setup when our attacks already 2HKO (Koga's Qwilfish vs the
# save's Cloyster at half HP, its last Pokemon): Curse can't save a turn.
curse_cases = [
    # (name, Cloyster's HP, expected score)
    ('qwilfish vs half-HP cloyster', 118, 22),
    ('qwilfish vs full-HP cloyster', 206, 19),
]
saved_hp = [(m[A('wPartyMon%dHP' % k)], m[A('wPartyMon%dHP' % k) + 1]) for k in range(1, 7)]
saved_cur = m[A('wCurBattleMon')]
for name, php, exp in curse_cases:
    if SPECIES['CLOYSTER'] not in party:
        print('SKIP', name); continue
    slot = party.index(SPECIES['CLOYSTER']) + 1
    w('wCurBattleMon', slot - 1)
    for k in range(1, 7):
        if k != slot:
            m[A('wPartyMon%dHP' % k)], m[A('wPartyMon%dHP' % k) + 1] = 0, 0
    set_ot(dict(QWILFISH_KOGA, hp=203))
    set_player(party.index(SPECIES['CLOYSTER']) + 1, ('WATER', 'ICE'), [])
    word('wBattleMonHP', php)
    w('wBattleWeather', 0); w('wCriticalHit', 0); w('wEnemySubStatus5', 0)
    g.call('AIGetEnemyMove', A=MOVE_IDS['CURSE'])
    w('wEnemyAIMoveScores', 20)
    g.call('AI_Smogon_Setup', HL=A('wEnemyAIMoveScores'), frames=2500)
    got = m[A('wEnemyAIMoveScores')]
    good = got == exp
    ok &= good
    print('PASS' if good else 'FAIL', 'setup:', name, 'score', got, 'expected', exp)
for k in range(1, 7):
    m[A('wPartyMon%dHP' % k)], m[A('wPartyMon%dHP' % k) + 1] = saved_hp[k - 1]
w('wCurBattleMon', saved_cur)

# AI_Smogon_Setup behind a Substitute (Misty's Tentacruel vs the save's Rest
# Snorlax): a sleeping Pokemon can't punish the boost, even below half HP or
# in a losing matchup.
SUB = 1 << CONST['SUBSTATUS_SUBSTITUTE']
free_setup_cases = [
    # (name, Tentacruel's HP, its Substitute, Attack stage, Snorlax's status, expected score)
    ('tentacruel behind a sub vs sleeping snorlax', 69, SUB, 7, 3, 17),
    ('tentacruel behind a sub vs sleeping snorlax, above half HP', 190, SUB, 7, 3, 17),
    ('tentacruel behind a sub vs awake snorlax', 190, SUB, 7, 0, 22),
    ('tentacruel without a sub vs sleeping snorlax', 190, 0, 7, 3, 22),
    ('tentacruel without a sub below half HP', 69, 0, 7, 3, 20),
    ('+2 tentacruel behind a sub vs sleeping snorlax', 190, SUB, 9, 3, 22),
]
for name, hp, sub, stage, pstatus, exp in free_setup_cases:
    if SPECIES['SNORLAX'] not in party:
        print('SKIP', name); continue
    set_ot(dict(TENTACRUEL_MISTY, hp=hp))
    w('wEnemyMonDVs', TENTACRUEL_MISTY['dvs'][0]); w('wEnemyMonDVs', TENTACRUEL_MISTY['dvs'][1], 1)
    w('wEnemyAtkLevel', stage); word('wEnemyMonAttack', TENTACRUEL_MISTY['stats'][0] * (stage - 5) // 2)
    set_player(party.index(SPECIES['SNORLAX']) + 1, ('NORMAL', 'NORMAL'), ['DOUBLE_EDGE', 'REST'])
    w('wBattleMonStatus', pstatus); w('wEnemySubStatus4', sub)
    w('wBattleWeather', 0); w('wCriticalHit', 0); w('wEnemySubStatus5', 0)
    g.call('AIGetEnemyMove', A=MOVE_IDS['SWORDS_DANCE'])
    w('wEnemyAIMoveScores', 20)
    g.call('AI_Smogon_Setup', HL=A('wEnemyAIMoveScores'), frames=2500)
    got = m[A('wEnemyAIMoveScores')]
    good = got == exp
    ok &= good
    print('PASS' if good else 'FAIL', 'setup:', name, 'score', got, 'expected', exp)
w('wEnemyAtkLevel', 7); w('wBattleMonStatus', 0); w('wEnemySubStatus4', 0)

# AI_Smogon_Substitute vs a likely Explosion (Misty's Tentacruel vs the
# save's Cloyster): a Substitute wastes it, so it's greatly encouraged, unless
# Explosion would barely hurt or the player has shown it doesn't have it.
substitute_cases = [
    # (name, Tentacruel's HP, its types, Cloyster's revealed moves, its status, expected score)
    ('tentacruel vs cloyster', 222, ('WATER', 'POISON'), [], 0, 17),
    ('tentacruel vs cloyster after spikes', 222, ('WATER', 'POISON'), ['SPIKES', 'SURF'], 0, 17),
    ('tentacruel vs cloyster without explosion', 222, ('WATER', 'POISON'),
     ['SPIKES', 'SURF', 'TOXIC', 'ICE_BEAM'], 0, 20),
    ('steel type vs cloyster', 222, ('STEEL', 'STEEL'), [], 0, 20),
    ('tentacruel below half HP', 118, ('WATER', 'POISON'), [], 0, 20),
    ('tentacruel vs sleeping cloyster', 222, ('WATER', 'POISON'), [], 2, 18),
    # (a last Pokemon that explodes loses the battle: here the save's
    # others have fainted)
    ('tentacruel vs a last cloyster', 222, ('WATER', 'POISON'), [], 0, 20),
]
party_hp = [(m[A('wPartyMon%dHP' % k)], m[A('wPartyMon%dHP' % k) + 1]) for k in range(1, 7)]
cur_battle_mon = m[A('wCurBattleMon')]
for name, hp, types, pused, pstatus, exp in substitute_cases:
    if SPECIES['CLOYSTER'] not in party:
        print('SKIP', name); continue
    slot = party.index(SPECIES['CLOYSTER']) + 1
    w('wCurBattleMon', slot - 1)
    for k in range(1, 7):
        last = 'last' in name and k != slot
        m[A('wPartyMon%dHP' % k)], m[A('wPartyMon%dHP' % k) + 1] = (0, 0) if last else party_hp[k - 1]
    set_ot(dict(TENTACRUEL_MISTY, hp=hp))
    w('wEnemyMonType1', TYPES[types[0]]); w('wEnemyMonType2', TYPES[types[1]])
    set_player(party.index(SPECIES['CLOYSTER']) + 1, ('WATER', 'ICE'), pused)
    w('wBattleMonStatus', pstatus)
    w('wEnemyAIMoveScores', 20)
    g.call('AI_Smogon_Substitute', HL=A('wEnemyAIMoveScores'), frames=600)
    got = m[A('wEnemyAIMoveScores')]
    good = got == exp
    ok &= good
    print('PASS' if good else 'FAIL', 'substitute:', name, 'score', got, 'expected', exp)
w('wBattleMonStatus', 0)
for k in range(1, 7):
    m[A('wPartyMon%dHP' % k)], m[A('wPartyMon%dHP' % k) + 1] = party_hp[k - 1]
w('wCurBattleMon', cur_battle_mon)

# AISmogon_PlayerSurelyCantAttack: frozen, or asleep without Sleep Talk
# (revealed, or usual for its species until four other moves are revealed).
FRZ = 1 << CONST['FRZ']
cant_attack_cases = [
    # (name, species, status, revealed moves, expected nz)
    ('frozen zapdos', 'ZAPDOS', FRZ, [], True),
    ('awake zapdos', 'ZAPDOS', 0, [], False),
    ('sleeping zapdos, sleep talk usual', 'ZAPDOS', 3, ['REST'], False),
    ('sleeping zapdos, sleep talk revealed', 'ZAPDOS', 3, ['REST', 'SLEEP_TALK'], False),
    ('sleeping zapdos, four other moves', 'ZAPDOS', 3, ['REST', 'THUNDER', 'HIDDEN_POWER', 'REFLECT'], True),
    ('sleeping exeggutor', 'EXEGGUTOR', 3, [], True),
]
for name, species, status, used, exp in cant_attack_cases:
    w('wBattleMonSpecies', SPECIES[species]); w('wBattleMonStatus', status)
    for i in range(4):
        w('wPlayerUsedMoves', MOVE_IDS[used[i]] if i < len(used) else 0, i)
    g.call('AISmogon_PlayerSurelyCantAttack')
    got = not g.result['F'] & 0x80
    good = got == exp
    ok &= good
    print('PASS' if good else 'FAIL', 'surely can\'t attack:', name, 'got', got, 'expected', exp)
w('wBattleMonStatus', 0)

# A switch-in takes no hit on the way in when the player surely can't
# attack (Koga's Tentacruel, with Gengar in the back, vs the save's last
# Pokemon, a frozen Zapdos): Gengar's score, Tentacruel's is 120.
entry_cases = [
    # (name, Zapdos's status, its revealed moves, expected Gengar score)
    ('gengar vs frozen zapdos', FRZ, [], 140),
    ('gengar vs awake zapdos', 0, [], 120),
    ('gengar vs sleeping zapdos, sleep talk usual', 3, [], 120),
]
for name, pstatus, pused, exp in entry_cases:
    if SPECIES['ZAPDOS'] not in party:
        print('SKIP', name); continue
    slot = party.index(SPECIES['ZAPDOS']) + 1
    w('wCurBattleMon', slot - 1)
    for k in range(1, 7):
        m[A('wPartyMon%dHP' % k)], m[A('wPartyMon%dHP' % k) + 1] = (0, 0) if k != slot else party_hp[k - 1]
    set_ot(GENGAR, 1)
    set_ot(TENTACRUEL)
    w('wOTPartyCount', 2); w('wOTPartySpecies', SPECIES['GENGAR'], 1); w('wOTPartySpecies', 0xff, 2)
    w('wEnemyMonDVs', 255); w('wEnemyMonDVs', 255, 1); w('wEnemyTurnsTaken', 3)
    set_player(slot, ('ELECTRIC', 'FLYING'), pused)
    word('wBattleMonHP', 164); w('wBattleMonStatus', pstatus)
    w('wBattleWeather', 0); w('wCriticalHit', 0)
    g.call('AISmogon_ScoreActive', frames=1500)
    g.call('AISmogon_FindBestSwitchIn', frames=4000)
    got = m[A('wSmogonAIBestScore')]
    good = got == exp and m[A('wSmogonAIBestMon')] == 1
    ok &= good
    print('PASS' if good else 'FAIL', 'entry hit:', name, 'score', got, 'expected', exp,
          'active', m[A('wEnemyAISwitchScore')])
w('wBattleMonStatus', 0)
for k in range(1, 7):
    m[A('wPartyMon%dHP' % k)], m[A('wPartyMon%dHP' % k) + 1] = party_hp[k - 1]
w('wCurBattleMon', cur_battle_mon)

# AISmogon_PickedLeadMoveFirst: Whitney's Spore Smeargle stays in to use
# Spore or Spikes before the player can hit back, instead of switching out
# on its first turn against every lead.
SUB = 1 << CONST['SUBSTATUS_SUBSTITUTE']
lead_cases = [
    # (name, picked move, Smeargle's speed, player's species, speed, status, substatus 4, expected carry)
    ('spore, faster than steelix', 'SPORE', 134, 'STEELIX', 95, 0, 0, True),
    ('spikes, faster than snorlax', 'SPIKES', 134, 'SNORLAX', 74, 0, 0, True),
    ('spikes, slower than zapdos', 'SPIKES', 134, 'ZAPDOS', 214, 0, 0, False),
    ('spore, slower than exeggutor', 'SPORE', 134, 'EXEGGUTOR', 137, 0, 0, False),
    ('spikes, slower than a frozen zapdos', 'SPIKES', 134, 'ZAPDOS', 214, FRZ, 0, True),
    ('spore, faster, player behind a substitute', 'SPORE', 134, 'STEELIX', 95, 0, SUB, False),
    ('rapid spin, faster', 'RAPID_SPIN', 134, 'STEELIX', 95, 0, 0, False),
]
for name, move, espd, species, pspd, pstatus, psub4, exp in lead_cases:
    if 'AISmogon_PickedLeadMoveFirst' not in g.sym:
        ok = False
        print('FAIL lead move first:', name, '(not in this ROM)')
        continue
    g.call('AIGetEnemyMove', A=MOVE_IDS[move])
    word('wEnemyMonSpeed', espd); word('wBattleMonSpeed', pspd)
    w('wBattleMonSpecies', SPECIES[species]); w('wBattleMonStatus', pstatus)
    w('wPlayerSubStatus4', psub4)
    for i in range(4):
        w('wPlayerUsedMoves', 0, i)
    g.call('AISmogon_PickedLeadMoveFirst')
    carry = bool(g.result['F'] & 0x10)
    good = carry == exp
    ok &= good
    print('PASS' if good else 'FAIL', 'lead move first:', name, 'carry', carry, 'expected', exp)
w('wBattleMonStatus', 0); w('wPlayerSubStatus4', 0)
print('RESULT:', 'ALL OK' if ok else 'NOT OK')
