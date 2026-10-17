"""Direct checks of AISmogon_PickedMoveKOsFirst (engine/battle/ai/smogon.asm),
the reason SwitchSmogon stays in to KO the player first: calls it from the
overworld with game_call.py on hand-made battle states and checks the carry
and that wEnemyMoveStruct, wCurDamage and wCriticalHit come back unchanged.

usage: sure_ko_test.py ROM SYM SAVE.ram    (last line RESULT: ALL OK)"""
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
print('RESULT:', 'ALL OK' if ok else 'NOT OK')
