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

usage: smogon_calls_test.py ROM SYM SAVE.ram    (last line RESULT: ALL OK)"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from game_call import Game
from pokedata import MOVE_IDS, TYPES, SPECIES, CONST
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
    g.call('AISmogon_EnemyHasUsefulBoosts')
    carry = bool(g.result['F'] & 0x10)
    good = carry == exp
    ok &= good
    print('PASS' if good else 'FAIL', name, 'carry', carry, 'expected', exp)

setup_cases = [
    # (name, candidate moves, its types, threat, player's revealed moves, expected SMOGON_SETUP_*)
    ('swords dance, surf-only player', ['SLUDGE_BOMB', 'SWORDS_DANCE', 'HYDRO_PUMP', 'SUBSTITUTE'],
     ('WATER', 'POISON'), 43, ['SURF', 'GROWTH', 'SLEEP_TALK', 'REST'], 'SMOGON_SETUP_DOUBLE'),
    ('swords dance, player hits hard', ['SLUDGE_BOMB', 'SWORDS_DANCE', 'HYDRO_PUMP', 'SUBSTITUTE'],
     ('WATER', 'POISON'), 70, ['SURF', 'GROWTH', 'SLEEP_TALK', 'REST'], 'SMOGON_SETUP_NONE'),
    ('swords dance, player roars', ['SLUDGE_BOMB', 'SWORDS_DANCE', 'HYDRO_PUMP', 'SUBSTITUTE'],
     ('WATER', 'POISON'), 43, ['SURF', 'ROAR', 'SLEEP_TALK', 'REST'], 'SMOGON_SETUP_NONE'),
    ('swords dance, player hazes', ['SLUDGE_BOMB', 'SWORDS_DANCE', 'HYDRO_PUMP', 'SUBSTITUTE'],
     ('WATER', 'POISON'), 43, ['SURF', 'HAZE', 'SLEEP_TALK', 'REST'], 'SMOGON_SETUP_NONE'),
    ('growth', ['SURF', 'GROWTH', 'REST', 'SLEEP_TALK'], ('WATER', 'WATER'), 43,
     ['SURF', 'GROWTH', 'SLEEP_TALK', 'REST'], 'SMOGON_SETUP_SPECIAL'),
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
def set_ot(mon):
    base = A('wOTPartyMon1Species')
    off = {f: A('wOTPartyMon1' + f) - base for f in OT_FIELDS}
    m[base] = mon['species']; m[base + off['Item']] = mon['item']; m[base + off['Level']] = mon['level']
    m[base + off['Status']] = 0
    for i in range(4):
        m[base + off['Moves'] + i] = mon['moves'][i]; m[base + off['PP'] + i] = mon['pp'][i]
    m[base + off['DVs']], m[base + off['DVs'] + 1] = mon['dvs']
    for f, v in (('HP', mon['hp']), ('MaxHP', mon['max_hp'])):
        m[base + off[f]] = v >> 8; m[base + off[f] + 1] = v & 0xff
    for k, v in enumerate(mon['stats']):
        m[base + off['Attack'] + 2 * k] = v >> 8; m[base + off['Attack'] + 2 * k + 1] = v & 0xff
    w('wOTPartyCount', 1); w('wOTPartySpecies', mon['species']); w('wOTPartySpecies', 0xff, 1)
    w('wCurOTMon', 0); w('wEnemyMonSpecies', mon['species']); w('wEnemyMonStatus', 0)
    word('wEnemyMonHP', mon['hp']); word('wEnemyMonMaxHP', mon['max_hp']); word('wEnemyMonSpeed', mon['stats'][2])
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
print('RESULT:', 'ALL OK' if ok else 'NOT OK')
