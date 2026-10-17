"""Scenario tests for the new AI_Smogon handlers and the reverted heal engine.
usage: ai_scenarios.py ROM SYM SAVE.ram [FIRST_CASE]   (prints PASS/FAIL per case)
The last line is "RESULT: ALL OK" or "RESULT: NOT OK". When the test battle
ends before every case has run, the script restarts itself from the next case
(skipping phases that already finished) until everything has run.
Starts a Challenge Mode battle like tools/claude/battle.py, then each time
AI_Smogon runs, sets up the next scenario (moves, weather, statuses...), resets
the scores to 20 and reads them when AI_Smogon returns. A last phase gives the
enemy only heal moves and checks the multiplier index BattleCommand_
TimeBasedHealContinue picks at .Heal. Alongside, a switch-in phase gives
AISmogon_FindBestSwitchIn two candidates with equal stats against a player
type and checks which one it picks (types and moves decide); the party is
restored and no switch happens. A move power phase sets the enemy's DVs and
happiness and checks the power and type AIGetEnemyMove loads for Hidden Power,
Return, Frustration and Magnitude."""
import io, json, os, re, sys, random
from pyboy import PyBoy

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..')
rom, symf, save = sys.argv[1:4]
first = int(sys.argv[4]) if len(sys.argv) > 4 else 0
# set when the script restarts itself (see the end)
FAILED_BEFORE = int(os.environ.get('AI_SCENARIOS_FAILED', '0'))
SKIP_SWITCH = os.environ.get('AI_SCENARIOS_SKIP_SWITCH') == '1'
SKIP_POWER = os.environ.get('AI_SCENARIOS_SKIP_POWER') == '1'
HEAL_FIRST = int(os.environ.get('AI_SCENARIOS_HEAL_FIRST', '0'))

# --- constants -------------------------------------------------------------
C = {}
def parse(path):
    val, step = 0, 1
    for line in open(os.path.join(ROOT, path)):
        line = line.split(';')[0].strip()
        m = re.match(r'const_def\s*(\S+)?\s*(?:,\s*(\S+))?', line)
        if m and line.startswith('const_def'):
            val = int(m.group(1).replace('$', '0x'), 0) if m.group(1) else 0
            step = int(m.group(2)) if m.group(2) else 1
            continue
        m = re.match(r'const_next\s+(\S+)', line)
        if m:
            val = int(m.group(1).replace('$', '0x'), 0); continue
        m = re.match(r'const_skip\s*(\d+)?', line)
        if m and line.startswith('const_skip'):
            val += step * int(m.group(1) or 1); continue
        m = re.match(r'shift_const\s+(\w+)', line)
        if m:
            C[m.group(1) + '_F'] = val; C[m.group(1)] = 1 << val; val += 1; continue
        m = re.match(r'const\s+(\w+)', line)
        if m:
            C[m.group(1)] = val; val += step
for f in ('constants/move_constants.asm', 'constants/battle_constants.asm', 'constants/type_constants.asm',
          'constants/pokemon_constants.asm'):
    parse(f)
C.update(MORN_F=0, DAY_F=1, NITE_F=2, EVE_F=3)  # constants/ram_constants.asm wTimeOfDay
assert C['THUNDER'] == 0x57 and C['MOONLIGHT'] == 0xec, (C['THUNDER'], C['MOONLIGHT'])

sym = {}
for line in open(symf):
    if line.startswith(';') or ' ' not in line:
        continue
    loc, name = line.split()[:2]
    if ':' not in loc:
        continue
    b, a = loc.split(':')
    sym[name] = (int(b, 16), int(a, 16))
W = lambda n: sym[n][1]

pb = PyBoy(rom, window='null', ram_file=io.BytesIO(open(save, 'rb').read()), sound_emulated=False, log_level='ERROR')
mem = pb.memory
def word(addr, v):
    mem[addr] = v >> 8; mem[addr + 1] = v & 0xff

# --- scenarios ---------------------------------------------------------------
# Each: (name, moves, setup dict, expected scores). Setup keys are applied over
# a neutral baseline. Scores are relative to 20 (AI_Smogon's delta only).
M = lambda *names: [C[n] for n in names]
S = lambda *bits: sum(1 << C[b] for b in bits)
base = dict(weather=0, ptypes=(C['FIRE'], C['FIRE']), etypes=(C['NORMAL'], C['NORMAL']),
            espd=200, pspd=100, sub1=0, sub2=0, sub4=0, sub5=0, psub3=0, psub5=0,
            estatus=0, toxic=0, wrap=0, perish=0, hp=(40, 100), tod=C['DAY_F'], hours=12,
            pspecies=C['MAGIKARP'], php=(100, 100), pstatus=0, patk=7, psub4=0, pused=(), plast=0, crit=0,
            patkstat=None)
F, D = C['FIRE'], C['GROUND']
scen = [
    ('thunder rain neutral', M('THUNDER'), dict(weather=C['WEATHER_RAIN']), [18]),
    ('thunder no rain', M('THUNDER'), dict(), [20]),
    ('thunder rain vs ground', M('THUNDER'), dict(weather=C['WEATHER_RAIN'], ptypes=(D, D)), [20]),
    ('rollout curled', M('ROLLOUT'), dict(sub2=S('SUBSTATUS_CURLED')), [18]),
    ('rollout not curled', M('ROLLOUT'), dict(), [20]),
    ('rollout curled vs ground', M('ROLLOUT'), dict(sub2=S('SUBSTATUS_CURLED'), ptypes=(D, D)), [20]),
    ('fly faster', M('TACKLE', 'GUST', 'EARTHQUAKE', 'HARDEN'), dict(psub3=S('SUBSTATUS_FLYING')), [30, 20, 30, 20]),
    ('fly thunder/twister/own fly', M('THUNDER', 'TWISTER', 'FLY', 'SWIFT'), dict(psub3=S('SUBSTATUS_FLYING')), [20, 20, 20, 30]),
    ('dig faster', M('TACKLE', 'GUST', 'EARTHQUAKE', 'MAGNITUDE'), dict(psub3=S('SUBSTATUS_UNDERGROUND')), [30, 30, 20, 20]),
    ('fly slower', M('TACKLE', 'GUST', 'EARTHQUAKE', 'HARDEN'), dict(psub3=S('SUBSTATUS_FLYING'), espd=50), [20, 20, 20, 20]),
    ('fly lock-on', M('TACKLE', 'GUST', 'EARTHQUAKE', 'HARDEN'), dict(psub3=S('SUBSTATUS_FLYING'), psub5=S('SUBSTATUS_LOCK_ON')), [20, 20, 30, 20]),
    ('dig lock-on', M('TACKLE', 'GUST', 'EARTHQUAKE', 'HARDEN'), dict(psub3=S('SUBSTATUS_UNDERGROUND'), psub5=S('SUBSTATUS_LOCK_ON')), [20, 20, 20, 20]),
    ('endure plain', M('ENDURE'), dict(hp=(10, 100)), [20]),
    ('endure sand', M('ENDURE'), dict(weather=C['WEATHER_SANDSTORM']), [30]),
    ('endure sand rock', M('ENDURE'), dict(weather=C['WEATHER_SANDSTORM'], etypes=(C['ROCK'], C['NORMAL'])), [20]),
    ('endure psn dies', M('ENDURE'), dict(estatus=1 << C['PSN'], hp=(12, 100)), [30]),
    ('endure psn lives', M('ENDURE'), dict(estatus=1 << C['PSN'], hp=(13, 100)), [20]),
    ('endure toxic3 dies', M('ENDURE'), dict(estatus=1 << C['PSN'], sub5=S('SUBSTATUS_TOXIC'), toxic=3, hp=(24, 100)), [30]),
    ('endure toxic3 lives', M('ENDURE'), dict(estatus=1 << C['PSN'], sub5=S('SUBSTATUS_TOXIC'), toxic=3, hp=(25, 100)), [20]),
    ('endure seed+curse', M('ENDURE'), dict(sub4=S('SUBSTATUS_LEECH_SEED'), sub1=S('SUBSTATUS_CURSE'), hp=(37, 100)), [30]),
    ('endure seed+curse lives', M('ENDURE'), dict(sub4=S('SUBSTATUS_LEECH_SEED'), sub1=S('SUBSTATUS_CURSE'), hp=(38, 100)), [20]),
    ('endure wrap', M('ENDURE'), dict(wrap=3), [30]),
    ('endure wrap ends', M('ENDURE'), dict(wrap=1), [20]),
    ('endure wrap sub', M('ENDURE'), dict(wrap=3, sub4=S('SUBSTATUS_SUBSTITUTE')), [20]),
    ('endure perish 1', M('ENDURE'), dict(sub1=S('SUBSTATUS_PERISH'), perish=1), [30]),
    ('endure perish 2', M('ENDURE'), dict(sub1=S('SUBSTATUS_PERISH'), perish=2), [20]),
    ('heal morn match', M('MORNING_SUN', 'SYNTHESIS', 'MOONLIGHT', 'RECOVER'), dict(patkstat=400, tod=C['MORN_F'], hours=6), [18, 20, 20, 18]),
    ('heal nite rain', M('MORNING_SUN', 'SYNTHESIS', 'MOONLIGHT', 'RECOVER'), dict(patkstat=400, tod=C['NITE_F'], hours=23, weather=C['WEATHER_RAIN']), [30, 30, 20, 18]),
    ('heal day sun', M('MORNING_SUN', 'SYNTHESIS', 'MOONLIGHT', 'RECOVER'), dict(patkstat=400, tod=C['DAY_F'], weather=C['WEATHER_SUN']), [18, 18, 18, 18]),
    ('heal eve 17h', M('MORNING_SUN', 'SYNTHESIS', 'MOONLIGHT', 'RECOVER'), dict(patkstat=400, tod=C['EVE_F'], hours=17), [20, 18, 20, 18]),
    ('heal eve 19h', M('MORNING_SUN', 'SYNTHESIS', 'MOONLIGHT', 'RECOVER'), dict(patkstat=400, tod=C['EVE_F'], hours=19), [20, 20, 18, 18]),
    ('heal above half', M('MORNING_SUN', 'SYNTHESIS', 'MOONLIGHT', 'RECOVER'), dict(tod=C['MORN_F'], hours=6, hp=(60, 100)), [20, 20, 20, 20]),
    # AISmogon_HealCanWait: the player has revealed four moves, so only those count.
    ('heal can wait vs splash', M('RECOVER', 'REST'), dict(pused=M('SPLASH', 'SPLASH', 'SPLASH', 'SPLASH')), [21, 21]),
    ('heal can wait, but poisoned', M('RECOVER', 'REST'),
     dict(pused=M('SPLASH', 'SPLASH', 'SPLASH', 'SPLASH'), estatus=1 << C['PSN']), [18, 18]),
    ('heal can wait, but seeded', M('RECOVER'),
     dict(pused=M('SPLASH', 'SPLASH', 'SPLASH', 'SPLASH'), sub4=S('SUBSTATUS_LEECH_SEED')), [18]),
    ('heal vs hyper beam', M('RECOVER'), dict(pused=M('HYPER_BEAM', 'SPLASH', 'SPLASH', 'SPLASH'), patkstat=400), [18]),
    ('destiny bond doomed faster', M('DESTINY_BOND'), dict(hp=(20, 100)), [17]),
    ('destiny bond doomed slower', M('DESTINY_BOND'), dict(hp=(20, 100), espd=50), [20]),
    ('destiny bond healthy', M('DESTINY_BOND'), dict(hp=(60, 100)), [20]),
    ('protect vs worn exploder', M('PROTECT'), dict(pspecies=C['CLOYSTER'], php=(40, 100)), [17]),
    ('protect vs healthy exploder', M('PROTECT'), dict(pspecies=C['CLOYSTER'], php=(90, 100)), [20]),
    ('protect vs worn exploder, ghost', M('PROTECT'), dict(pspecies=C['CLOYSTER'], php=(40, 100),
                                                           etypes=(C['GHOST'], C['POISON'])), [20]),
    ('protect vs worn non-exploder', M('PROTECT'), dict(pspecies=C['LAPRAS'], php=(40, 100)), [20]),
    ('growl/charm vs cursed physical', M('GROWL', 'CHARM'), dict(pused=M('BODY_SLAM'), patk=8), [17, 17]),
    ('charm vs unboosted physical', M('CHARM'), dict(pused=M('BODY_SLAM')), [20]),
    ('charm vs belly drum', M('CHARM'), dict(pused=M('BODY_SLAM'), patk=13), [22]),
    ('charm vs boosted special', M('CHARM'), dict(pused=M('THUNDER'), patk=8), [22]),
    ('charm vs substitute', M('CHARM'), dict(pused=M('BODY_SLAM'), patk=8, psub4=S('SUBSTATUS_SUBSTITUTE')), [30]),
    ('mean look vs phazer', M('MEAN_LOOK'), dict(pused=M('ROAR')), [22]),
    ('mean look vs non-phazer', M('MEAN_LOOK'), dict(pused=M('SURF')), [20]),
    ('sub vs sleeping', M('SUBSTITUTE'), dict(hp=(60, 100), pstatus=2), [18]),
    ('sub vs sleeping sleep talker', M('SUBSTITUTE'), dict(hp=(60, 100), pstatus=2, pused=M('SLEEP_TALK')), [20]),
    ('sub vs frozen', M('SUBSTITUTE'), dict(hp=(60, 100), pstatus=1 << C['FRZ']), [18]),
    ('roar vs non-phazer', M('ROAR'), dict(pused=M('SURF')), [20]),
    ('roar vs slower phazer', M('ROAR'), dict(pused=M('ROAR')), [22]),
    ('roar vs faster phazer', M('ROAR'), dict(pused=M('WHIRLWIND'), espd=50), [20]),
    ('encore after encore', M('ENCORE'), dict(plast=C['ENCORE']), [30]),
    ('encore after mirror move', M('ENCORE'), dict(plast=C['MIRROR_MOVE']), [30]),
    ('encore after swords dance', M('ENCORE'), dict(plast=C['SWORDS_DANCE']), [17]),
    # Speeds from the enemy party: the player is just faster than the slowest
    # teammate (paralysis would flip it), or slower than all of them.
    ('t-wave for slow teammate', M('THUNDER_WAVE'), dict(espd=999, pspd=lambda: min(ot_speeds()) + 1), [19]),
    ('t-wave, teammates faster', M('THUNDER_WAVE'), dict(espd=999, pspd=lambda: min(ot_speeds()) - 1), [20]),
    ('t-wave, teammates too slow', M('THUNDER_WAVE'), dict(espd=999, pspd=lambda: max(ot_speeds()) * 4 + 4), [20]),
    # AI_Smogon_Weather: +3 when the weather helps the player's attacks too.
    ('rain vs zapdos', M('RAIN_DANCE'), dict(pspecies=C['ZAPDOS'], ptypes=(C['ELECTRIC'], C['FLYING'])), [23]),
    ('rain vs zapdos that used thunder', M('RAIN_DANCE'),
     dict(pspecies=C['ZAPDOS'], ptypes=(C['ELECTRIC'], C['FLYING']), pused=M('THUNDER')), [23]),
    ('rain vs zapdos, four other moves', M('RAIN_DANCE'),
     dict(pspecies=C['ZAPDOS'], ptypes=(C['ELECTRIC'], C['FLYING']), pused=M('SPLASH', 'SPLASH', 'SPLASH', 'SPLASH')), [20]),
    ('rain vs exeggutor', M('RAIN_DANCE'), dict(pspecies=C['EXEGGUTOR'], ptypes=(C['GRASS'], C['PSYCHIC_TYPE'])), [20]),
    ('sun vs charizard', M('SUNNY_DAY'), dict(pspecies=C['CHARIZARD'], ptypes=(C['FIRE'], C['FLYING'])), [23]),
    ('sun vs exeggutor', M('SUNNY_DAY'), dict(pspecies=C['EXEGGUTOR'], ptypes=(C['GRASS'], C['PSYCHIC_TYPE'])), [20]),
    ('rain vs unlisted electric type', M('RAIN_DANCE'), dict(ptypes=(C['ELECTRIC'], C['ELECTRIC'])), [23]),
    ('rain vs unlisted normal type', M('RAIN_DANCE'), dict(ptypes=(C['NORMAL'], C['NORMAL'])), [20]),
    # AI_Smogon_SureKO: the player has 1 HP, so any hit KOs.
    ('sure KO: most accurate', M('FIRE_BLAST', 'ICE_BEAM', 'THUNDER', 'HARDEN'),
     dict(php=(1, 100), ptypes=(C['NORMAL'], C['NORMAL'])), [22, 17, 22, 20]),
    ('sure KO: thunder in rain', M('THUNDER', 'THUNDERBOLT'),
     dict(php=(1, 100), ptypes=(C['NORMAL'], C['NORMAL']), weather=C['WEATHER_RAIN']), [15, 17]),
    ('sure KO: priority when slower', M('QUICK_ATTACK', 'BODY_SLAM'),
     dict(php=(1, 100), ptypes=(C['NORMAL'], C['NORMAL']), espd=50), [17, 22]),
    ('sure KO: no priority when faster', M('QUICK_ATTACK', 'BODY_SLAM'),
     dict(php=(1, 100), ptypes=(C['NORMAL'], C['NORMAL'])), [17, 17]),
    ('sure KO: not hyper beam', M('HYPER_BEAM', 'BODY_SLAM'),
     dict(php=(1, 100), ptypes=(C['NORMAL'], C['NORMAL'])), [20, 17]),
    ('sure KO: substitute', M('FIRE_BLAST', 'ICE_BEAM'),
     dict(php=(1, 100), ptypes=(C['NORMAL'], C['NORMAL']), psub4=S('SUBSTATUS_SUBSTITUTE')), [20, 20]),
    ('sure KO: none', M('FIRE_BLAST', 'ICE_BEAM'),
     dict(php=(999, 999), ptypes=(C['NORMAL'], C['NORMAL'])), [20, 20]),
    # 1.3x Ice Beam's highest regular roll: a KO only if the damage doubled
    ('sure KO: not from a stale critical hit', M('ICE_BEAM'),
     dict(php=lambda: (int(ice_beam_damage() * 1.3), 999), ptypes=(C['NORMAL'], C['NORMAL']), crit=1), [20]),
    ('sure KO: just in range', M('ICE_BEAM'),
     dict(php=lambda: (int(ice_beam_damage() * 0.8), 999), ptypes=(C['NORMAL'], C['NORMAL'])), [17]),
    ('sure KO: asleep', M('SLEEP_TALK', 'ICE_BEAM'),
     dict(php=(1, 100), ptypes=(C['NORMAL'], C['NORMAL']), estatus=2), [20, 20]),
    ('sure KO: immune', M('BODY_SLAM', 'ICE_BEAM'),
     dict(php=(1, 100), ptypes=(C['GHOST'], C['GHOST'])), [20, 17]),
]

def ot_speeds():
    # Speeds of the enemy's healthy Pokemon other than the active one.
    size = W('wOTPartyMon2') - W('wOTPartyMon1')
    out = []
    for i in range(mem[W('wOTPartyCount')]):
        if i == mem[W('wCurOTMon')]:
            continue
        hp_, spd = W('wOTPartyMon1HP') + i * size, W('wOTPartyMon1Speed') + i * size
        if mem[hp_] | mem[hp_ + 1]:
            out.append(mem[spd] << 8 | mem[spd + 1])
    return out
scen = scen[first:]
# Engine phase: (name, move, tod, hours, weather, expected .Multipliers index)
heal_cases = [
    ('morn sun morning', 'MORNING_SUN', C['MORN_F'], 6, 0, 2),
    ('morn sun night', 'MORNING_SUN', C['NITE_F'], 23, 0, 1),
    ('synthesis eve 17h', 'SYNTHESIS', C['EVE_F'], 17, 0, 2),
    ('synthesis eve 19h', 'SYNTHESIS', C['EVE_F'], 19, 0, 1),
    ('moonlight eve 19h', 'MOONLIGHT', C['EVE_F'], 19, 0, 2),
    ('moonlight night sun', 'MOONLIGHT', C['NITE_F'], 23, C['WEATHER_SUN'], 3),
    ('moonlight day rain', 'MOONLIGHT', C['DAY_F'], 12, C['WEATHER_RAIN'], 0),
    ('synthesis day sand', 'SYNTHESIS', C['DAY_F'], 12, C['WEATHER_SANDSTORM'], 1),
]

# Switch-in phase: (name, player types, [(species, moves)...], expected index
# [, extra]). The player's Pokemon is a Magikarp (no expected attacks in
# SmogonExpectedAttacks, so its types decide) unless extra sets 'species'.
# Other extra keys: 'used' (revealed moves), 'php' (HP out of 100), 'chp'
# (the candidates' HP out of 200), 'escreens'.
switch_cases = [
    ('switch vs fire: water over 4x weak', (C['FIRE'], C['FIRE']),
     [(C['FORRETRESS'], M('TACKLE')), (C['STARMIE'], M('SURF'))], 1),
    ('switch vs water: grass over fire', (C['WATER'], C['WATER']),
     [(C['VENUSAUR'], M('RAZOR_LEAF')), (C['CHARIZARD'], M('FLAMETHROWER'))], 0),
    ('switch vs electric: ground immunity', (C['ELECTRIC'], C['ELECTRIC']),
     [(C['GYARADOS'], M('SURF')), (C['GOLEM'], M('EARTHQUAKE'))], 1),
    ('switch vs ground: flying immunity', (C['GROUND'], C['GROUND']),
     [(C['SKARMORY'], M('DRILL_PECK')), (C['GOLEM'], M('EARTHQUAKE'))], 0),
    ('switch vs dark: fighting over psychic', (C['DARK'], C['DARK']),
     [(C['ALAKAZAM'], M('PSYCHIC_M')), (C['HERACROSS'], M('MEGAHORN'))], 1),
    # Golem's usual attack is Earthquake, which can't touch Charizard.
    ('switch vs golem: expects earthquake, not rock', (C['ROCK'], C['GROUND']),
     [(C['CHARIZARD'], M('FLAMETHROWER')), (C['SNORLAX'], M('BODY_SLAM'))], 0, dict(species=C['GOLEM'])),
    ('switch vs golem with rock slide revealed', (C['ROCK'], C['GROUND']),
     [(C['CHARIZARD'], M('FLAMETHROWER')), (C['SNORLAX'], M('BODY_SLAM'))], 1,
     dict(species=C['GOLEM'], used=M('ROCK_SLIDE', 'REST', 'ROAR', 'CURSE'))),
    ('switch vs rock/ground with no data: both stabs', (C['ROCK'], C['GROUND']),
     [(C['CHARIZARD'], M('FLAMETHROWER')), (C['SNORLAX'], M('BODY_SLAM'))], 1),
    # Equal matchups: the Ghost takes a worn-down Cloyster's Explosion.
    ('switch vs worn cloyster: ghost absorbs explosion', (C['WATER'], C['ICE']),
     [(C['SNORLAX'], M('THUNDERBOLT')), (C['MISDREAVUS'], M('THUNDERBOLT'))], 1,
     dict(species=C['CLOYSTER'], php=40)),
    ('switch vs cloyster after spikes: ghost absorbs explosion', (C['WATER'], C['ICE']),
     [(C['SNORLAX'], M('THUNDERBOLT')), (C['MISDREAVUS'], M('THUNDERBOLT'))], 1,
     dict(species=C['CLOYSTER'], escreens=1 << C['SCREENS_SPIKES'])),
    ('switch vs healthy cloyster: no explosion expected', (C['WATER'], C['ICE']),
     [(C['SNORLAX'], M('THUNDERBOLT')), (C['MISDREAVUS'], M('THUNDERBOLT'))], 0,
     dict(species=C['CLOYSTER'])),
    # Jynx usually has Lovely Kiss: a Sleep Talk user takes it.
    ('switch vs jynx: sleep talk absorbs sleep', (C['ICE'], C['PSYCHIC_TYPE']),
     [(C['SNORLAX'], M('THUNDERBOLT')), (C['SNORLAX'], M('THUNDERBOLT', 'SLEEP_TALK'))], 1,
     dict(species=C['JYNX'])),
    ('switch vs lapras: no sleep expected', (C['WATER'], C['ICE']),
     [(C['SNORLAX'], M('THUNDERBOLT')), (C['SNORLAX'], M('THUNDERBOLT', 'SLEEP_TALK'))], 0,
     dict(species=C['LAPRAS'])),
    # Equal matchups: Spikes on the AI's side hurt the non-Flying switch-in.
    # (at 120 of 200 HP, Spikes' 25 HP leave it one hit from fainting)
    ('switch vs water, no spikes: tie keeps the first', (C['WATER'], C['WATER']),
     [(C['RATICATE'], M('BODY_SLAM')), (C['PIDGEOT'], M('BODY_SLAM'))], 0, dict(chp=120)),
    ('switch vs water with spikes: flying avoids them', (C['WATER'], C['WATER']),
     [(C['RATICATE'], M('BODY_SLAM')), (C['PIDGEOT'], M('BODY_SLAM'))], 1,
     dict(chp=120, escreens=1 << C['SCREENS_SPIKES'])),
]

# Hidden Power phase: (Atk/Def DVs, Spd/Spc DVs) -> vanilla power and type
HP_TYPES = ['FIGHTING', 'FLYING', 'POISON', 'GROUND', 'ROCK', 'BUG', 'GHOST', 'STEEL',
            'FIRE', 'WATER', 'GRASS', 'ELECTRIC', 'PSYCHIC_TYPE', 'ICE', 'DRAGON', 'DARK']
def hidden_power(ad, ss):
    top = (ad >> 7 & 1) << 3 | (ad >> 3 & 1) << 2 | (ss >> 7 & 1) << 1 | (ss >> 3 & 1)
    return (top * 5 + (ss & 3)) // 2 + 31, C[HP_TYPES[(ad >> 4 & 3) << 2 | (ad & 3)]]
assert hidden_power(0xcf, 0xff) == (70, C['GROUND'])
# (name, move, (Atk/Def DVs, Spd/Spc DVs), happiness, expected (power, type))
hp_cases = [('hidden power DVs %02x%02x' % dvs, 'HIDDEN_POWER', dvs, 70, hidden_power(*dvs))
            for dvs in ((0xcf, 0xff), (0xee, 0xee), (0x00, 0x00), (0xfa, 0x7d))]
hp_cases += [
    ('return max happiness', 'RETURN', (0, 0), 255, (102, C['NORMAL'])),
    ('return happiness 70', 'RETURN', (0, 0), 70, (70 * 10 // 25, C['NORMAL'])),
    ('frustration no happiness', 'FRUSTRATION', (0, 0), 0, (102, C['NORMAL'])),
    ('frustration happiness 30', 'FRUSTRATION', (0, 0), 30, ((255 - 30) * 10 // 25, C['NORMAL'])),
    ('magnitude average', 'MAGNITUDE', (0, 0), 70, (71, C['GROUND'])),
]

if SKIP_SWITCH:
    switch_cases = []
if SKIP_POWER:
    hp_cases = []
heal_cases = heal_cases[HEAL_FIRST:]

results, state = [], {'i': 0, 'cur': None, 'ret': None, 'heal_i': 0, 'heal_cur': None}

def ice_beam_damage():
    """The enemy's highest regular Ice Beam roll on a neutral, unboosted player."""
    rd = lambda n: mem[W(n)] << 8 | mem[W(n) + 1]
    level = mem[W('wEnemyMonLevel')]
    return (2 * level // 5 + 2) * 95 * rd('wEnemyMonSpclAtk') // max(1, rd('wBattleMonSpclDef')) // 50 + 2

def apply(setup, moves):
    st = dict(base); st.update(setup)
    st = {k: v() if callable(v) else v for k, v in st.items()}
    for i in range(4):
        mem[W('wEnemyMonMoves') + i] = moves[i] if i < len(moves) else 0
        mem[W('wEnemyMonPP') + i] = 10 if i < len(moves) else 0
        mem[W('wEnemyAIMoveScores') + i] = 20 if i < len(moves) else 80
    mem[W('wBattleWeather')] = st['weather']
    mem[W('wWeatherCount')] = 3 if st['weather'] else 0
    mem[W('wBattleMonType1')], mem[W('wBattleMonType2')] = st['ptypes']
    mem[W('wEnemyMonType1')], mem[W('wEnemyMonType2')] = st['etypes']
    word(W('wEnemyMonSpeed'), st['espd']); word(W('wBattleMonSpeed'), st['pspd'])
    for k, n in (('sub1', 'wEnemySubStatus1'), ('sub2', 'wEnemySubStatus2'), ('sub4', 'wEnemySubStatus4'),
                 ('sub5', 'wEnemySubStatus5'), ('psub3', 'wPlayerSubStatus3'), ('psub5', 'wPlayerSubStatus5')):
        mem[W(n)] = st[k]
    mem[W('wPlayerSubStatus1')] = 0
    mem[W('wEnemyMonStatus')] = st['estatus']
    mem[W('wEnemyToxicCount')] = st['toxic']
    mem[W('wEnemyWrapCount')] = st['wrap']
    mem[W('wEnemyPerishCount')] = st['perish']
    mem[W('wEnemyProtectCount')] = 0
    word(W('wEnemyMonHP'), st['hp'][0]); word(W('wEnemyMonMaxHP'), st['hp'][1])
    mem[W('wTimeOfDay')] = st['tod']
    mem[W('hHours')] = st['hours']
    mem[W('wEnemyScreens')] = 0; mem[W('wPlayerScreens')] = 0
    if state.get('player') is None:
        state['player'] = [mem[W('wBattleMonSpecies')]] + [mem[W('wBattleMonHP') + k] for k in range(4)] + \
                          [mem[W('wPlayerUsedMoves') + k] for k in range(4)] + \
                          [mem[W(n)] for n in ('wBattleMonStatus', 'wPlayerAtkLevel', 'wPlayerSubStatus4', 'wLastPlayerMove')]
    mem[W('wBattleMonSpecies')] = st['pspecies']
    word(W('wBattleMonHP'), st['php'][0]); word(W('wBattleMonMaxHP'), st['php'][1])
    for k in range(4):
        mem[W('wPlayerUsedMoves') + k] = st['pused'][k] if k < len(st['pused']) else 0
    mem[W('wBattleMonStatus')] = st['pstatus']
    mem[W('wPlayerAtkLevel')] = st['patk']
    mem[W('wPlayerSubStatus4')] = st['psub4']
    mem[W('wLastPlayerMove')] = st['plast']
    mem[W('wCriticalHit')] = st['crit']
    # the test battle's player hits very weakly: give it real attacking stats
    if st['patkstat'] is not None:
        state['patk_saved'] = [mem[W('wBattleMonAttack') + k] for k in range(10)]
        word(W('wBattleMonAttack'), st['patkstat']); word(W('wBattleMonSpclAtk'), st['patkstat'])

def on_ret(ctx):
    # the return address is the shared far call stub: only count our own return
    if state['cur'] is None or pb.register_file.SP != state['sp'] + 2:
        return
    name, moves, exp = state['cur']
    got = [mem[W('wEnemyAIMoveScores') + i] for i in range(len(moves))]
    results.append((name, got, exp, got == exp))
    state['cur'] = None
    # undo the scenario so the enemy survives and the battle keeps going
    if state.get('player') is not None:
        p = state['player']
        mem[W('wBattleMonSpecies')] = p[0]
        for k in range(4):
            mem[W('wBattleMonHP') + k] = p[1 + k]
            mem[W('wPlayerUsedMoves') + k] = p[5 + k]
        for k, n in enumerate(('wBattleMonStatus', 'wPlayerAtkLevel', 'wPlayerSubStatus4', 'wLastPlayerMove')):
            mem[W(n)] = p[9 + k]
        state['player'] = None
    if state.get('patk_saved') is not None:
        for k, v in enumerate(state.pop('patk_saved')):
            mem[W('wBattleMonAttack') + k] = v
    word(W('wEnemyMonHP'), 100); word(W('wEnemyMonMaxHP'), 100)
    for n in ('wEnemyMonStatus', 'wEnemyWrapCount', 'wEnemyPerishCount', 'wEnemyToxicCount', 'wEnemySubStatus1',
              'wEnemySubStatus2', 'wEnemySubStatus4', 'wEnemySubStatus5', 'wPlayerSubStatus3', 'wPlayerSubStatus5'):
        mem[W(n)] = 0

hp = {'i': 0, 'cur': None, 'saved': None}
def on_get_move(ctx):
    if hp['cur'] is None or mem[W('wEnemyMoveStruct')] != C[hp['cur'][1]]:
        return
    name, move, dvs, happiness, exp = hp['cur']
    got = [mem[W('wEnemyMoveStruct') + 2], mem[W('wEnemyMoveStruct') + 3]]  # MOVE_POWER, MOVE_TYPE
    results.append((name, got, list(exp), got == list(exp)))
    hp['cur'] = None
    mem[W('wEnemyMonDVs')], mem[W('wEnemyMonDVs') + 1], mem[W('wEnemyMonHappiness')] = hp['saved']
pb.hook_register(*sym['AIGetEnemyMove.done'], on_get_move, None)

def on_entry(ctx):
    sp = pb.register_file.SP
    ret = mem[sp] | mem[sp + 1] << 8
    state['sp'] = sp
    if state['ret'] is None:
        state['ret'] = ret
        pb.hook_register(sym['AI_Smogon'][0] if ret >= 0x4000 else 0, ret, on_ret, None)
    if hp['i'] < len(hp_cases):
        case = hp_cases[hp['i']]
        name, move, dvs, happiness, exp = case
        hp['saved'] = (mem[W('wEnemyMonDVs')], mem[W('wEnemyMonDVs') + 1], mem[W('wEnemyMonHappiness')])
        apply(dict(), M(move))
        mem[W('wEnemyMonDVs')], mem[W('wEnemyMonDVs') + 1] = dvs
        mem[W('wEnemyMonHappiness')] = happiness
        hp['cur'] = case
        hp['i'] += 1
        return
    i = state['i']
    if i < len(scen):
        name, moves, setup, exp = scen[i]
        apply(setup, moves)
        state['cur'] = (name, moves, exp)
        state['i'] += 1
    elif state['heal_i'] < len(heal_cases):
        # engine phase: only the next heal move, low HP, so the enemy uses it
        name, mv, tod, hours, weather, exp = heal_cases[state['heal_i']]
        apply(dict(weather=weather, tod=tod, hours=hours, hp=(30, 200)), M(mv))
pb.hook_register(*sym['AI_Smogon'], on_entry, None)

def on_heal_entry(ctx):
    if state['heal_i'] >= len(heal_cases) or mem[W('hBattleTurn')] != 1:
        return
    name, mv, tod, hours, weather, exp = heal_cases[state['heal_i']]
    mem[W('wTimeOfDay')] = tod; mem[W('hHours')] = hours; mem[W('wBattleWeather')] = weather
    state['heal_cur'] = (name, exp)
def on_heal(ctx):
    if state['heal_cur'] is None:
        return
    name, exp = state['heal_cur']
    got = pb.register_file.C
    results.append(('ENGINE ' + name, [got], [exp], got == exp))
    state['heal_cur'] = None
    state['heal_i'] += 1
pb.hook_register(*sym['BattleCommand_TimeBasedHealContinue'], on_heal_entry, None)
pb.hook_register(*sym['BattleCommand_TimeBasedHealContinue.Heal'], on_heal, None)

# --- switch-in phase ---------------------------------------------------------
PARTY_LEN = W('wOTPartyMon2') - W('wOTPartyMon1')
PLAYER_SAVE = [('wBattleMonType1', 2), ('wBattleMonAttack', 10), ('wBattleMonStatus', 1), ('wPlayerUsedMoves', 4),
               ('wBattleMonSpecies', 1), ('wBattleMonHP', 4), ('wEnemyScreens', 1)]
sw = {'i': 0, 'saved': None}
def on_switch_entry(ctx):
    if sw['i'] >= len(switch_cases) or sw['saved'] is not None:
        return
    name, ptypes, cands, exp, *extra = switch_cases[sw['i']]
    extra = extra[0] if extra else {}
    active = mem[W('wCurOTMon')]
    others = [i for i in range(mem[W('wOTPartyCount')]) if i != active]
    if len(others) < len(cands):
        return
    party = W('wOTPartyMon1')
    sw['saved'] = ([mem[party + k] for k in range(PARTY_LEN * 6)],
                   [[mem[W(n) + k] for k in range(l)] for n, l in PLAYER_SAVE])
    mem[W('wBattleMonType1')], mem[W('wBattleMonType2')] = ptypes
    for k in range(5):
        word(W('wBattleMonAttack') + 2 * k, 200)
    mem[W('wBattleMonStatus')] = 0
    used = extra.get('used', [])
    for k in range(4):
        mem[W('wPlayerUsedMoves') + k] = used[k] if k < len(used) else 0
    mem[W('wBattleMonSpecies')] = extra.get('species', C['MAGIKARP'])
    word(W('wBattleMonHP'), extra.get('php', 100)); word(W('wBattleMonMaxHP'), 100)
    mem[W('wEnemyScreens')] = extra.get('escreens', 0)
    slots = []
    for j, i in enumerate(others):
        b = i * PARTY_LEN
        if j < len(cands):
            species, moves = cands[j]
            mem[W('wOTPartyMon1Species') + b] = species
            for k in range(4):
                mem[W('wOTPartyMon1Moves') + b + k] = moves[k] if k < len(moves) else 0
            mem[W('wOTPartyMon1Status') + b] = 0
            word(W('wOTPartyMon1HP') + b, extra.get('chp', 200)); word(W('wOTPartyMon1MaxHP') + b, 200)
            for k in range(5):
                word(W('wOTPartyMon1Attack') + b + 2 * k, 200)
            slots.append(i)
        else:
            word(W('wOTPartyMon1HP') + b, 0)
    sw['slots'] = slots
    sw['cur'] = (name, exp)

def on_switch_done(ctx):
    if sw['saved'] is None:
        return
    name, exp = sw['cur']
    best = mem[W('wSmogonAIBestMon')]
    got = sw['slots'].index(best) if best in sw['slots'] else -1
    results.append((name, [got], [exp], got == exp))
    party_bytes, player_bytes = sw['saved']
    for k, v in enumerate(party_bytes):
        mem[W('wOTPartyMon1') + k] = v
    for (n, l), vals in zip(PLAYER_SAVE, player_bytes):
        for k, v in enumerate(vals):
            mem[W(n) + k] = v
    # report no switch-in, so the battle goes on as if nothing happened
    mem[W('wSmogonAIBestMon')] = 0xff
    sw['saved'] = None
    sw['i'] += 1
pb.hook_register(*sym['AISmogon_FindBestSwitchIn'], on_switch_entry, None)
pb.hook_register(*sym['AISmogon_FindBestSwitchIn.done'], on_switch_done, None)

crashed = []
pb.hook_register(0, 0x38, lambda ctx: crashed.append(pb.register_file.SP), None)

frame = 0
def run(n):
    global frame
    for _ in range(n):
        pb.tick(1, False); frame += 1
def press(btn, hold=4, after=12):
    pb.button_press(btn); run(hold); pb.button_release(btn); run(after)

script = json.load(open(os.path.join(ROOT, 'tools/claude/battle_scripts.json')))['BUGSY 2']
TACKLE, SWORDS_DANCE, ROAR, TOXIC, HAZE, REFLECT, CYNDAQUIL, TYPHLOSION = script[:8]
SCRIPT = bytes(script[8:])
run(600); press('start', after=200); press('start', after=120); press('a', after=120); press('a', after=300)
mem[W('wChallengeMode')] |= 1
mon = 'wPartyMon1'
mem[W('wPartySpecies')] = TYPHLOSION; mem[W(mon + 'Species')] = TYPHLOSION
for i, mv in enumerate((TACKLE, SWORDS_DANCE, ROAR, TOXIC)):
    mem[W(mon + 'Moves') + i] = mv; mem[W(mon + 'PP') + i] = 30
mem[W(mon + 'Level')] = 100; mem[W(mon + 'Status')] = 0
word(W(mon + 'HP'), 999); word(W(mon + 'MaxHP'), 999)
for st, v in (('Attack', 5), ('Defense', 999), ('Speed', 100), ('SpclAtk', 5), ('SpclDef', 999)):
    word(W(mon + st), v)
for i, b in enumerate(SCRIPT):
    mem[0xcfe2 + i] = b
mem[W('wMapReentryScriptQueueFlag')] = 1
mem[W('wMapReentryScriptBank')] = 1
mem[W('wMapReentryScriptAddress')] = 0xe2; mem[W('wMapReentryScriptAddress') + 1] = 0xcf

rng = random.Random(1)
while frame < 60 * 60 * 120 and not crashed and (state['heal_i'] < len(heal_cases) or sw['i'] < len(switch_cases)):
    if mem[W('wBattleMode')] == 2:
        # Keep the player alive, but not while a case is running: the AI
        # can take several frames, and this would overwrite the case's HP.
        if state['cur'] is None and hp['cur'] is None and sw['saved'] is None:
            word(W('wBattleMonHP'), 999)
        press('a' if rng.random() < 0.8 else 'b', after=rng.randint(8, 30))
    else:
        run(30)

failed = FAILED_BEFORE + sum(not r[3] for r in results)
for r in results:
    print(('PASS' if r[3] else 'FAIL'), r[0], 'got', r[1], 'expected', r[2])
print('run from case', first, ': scenarios', state['i'], '/', len(scen), 'engine', state['heal_i'], '/', len(heal_cases),
      'switch', sw['i'], '/', len(switch_cases), 'move power', hp['i'], '/', len(hp_cases), 'crashed', crashed, 'frames', frame)
complete = (state['i'] == len(scen) and state['heal_i'] == len(heal_cases)
            and sw['i'] == len(switch_cases) and hp['i'] == len(hp_cases))
progress = state['i'] or state['heal_i'] or sw['i'] or hp['i']
if not complete and progress and not crashed:
    # the test battle ended early: start over from the next case
    sys.stdout.flush()
    env = dict(os.environ, AI_SCENARIOS_FAILED=str(failed),
               AI_SCENARIOS_SKIP_SWITCH='1' if SKIP_SWITCH or sw['i'] == len(switch_cases) else '0',
               AI_SCENARIOS_SKIP_POWER='1' if SKIP_POWER or hp['i'] == len(hp_cases) else '0',
               AI_SCENARIOS_HEAL_FIRST=str(HEAL_FIRST + state['heal_i']))
    script = os.path.abspath(__file__)
    os.execve(sys.executable, [sys.executable, script, rom, symf, save, str(first + state['i'])], env)
print('RESULT:', 'ALL OK' if complete and not failed else f'NOT OK ({failed} failed{", incomplete" if not complete else ""})')
