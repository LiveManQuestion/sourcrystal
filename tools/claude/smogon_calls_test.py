"""Direct checks of Smogon AI helpers, called from the overworld with
game_call.py on hand-made battle states:
- AISmogon_PickedMoveKOsFirst (smogon.asm), the reason SwitchSmogon stays
  in to KO the player first: the carry, and that wEnemyMoveStruct,
  wCurDamage and wCriticalHit come back unchanged.
- AISmogon_PenalizeAsleepActive (smogon_switch.asm): the sleep or freeze
  penalty taken off the active Pokemon's score.
- AISmogon_EnemyHasUsefulBoosts (smogon.asm): which boosts keep the active
  Pokemon in.

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
print('RESULT:', 'ALL OK' if ok else 'NOT OK')
