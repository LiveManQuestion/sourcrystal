"""Headless Challenge Mode battle test against Smogon-AI trainers (PyBoy).
usage: battle.py [--smart] ROM SYM SAVE TRAINER(e.g. "BUGSY 2") SEED [max_frames] [end_screenshot.png]

Plays one battle with battle_harness.py (see there for the setup and the two
players: an unkillable Typhlosion pressing random buttons, or with --smart
the save's own party played by smart_player.py, so win rates mean
something). Prints one JSON line with the harness's result, how often each
hooked AI routine ran, and every enemy switch-in ("switches"; summarize with
switch_report.py). Needs battle_scripts.json from make_battle_scripts.py."""
import collections
import json
import sys

from battle_harness import Battle

SMART = '--smart' in sys.argv
argv = [a for a in sys.argv if a != '--smart']
rom, symf, save, trainer, seed = argv[1:6]
max_frames = int(argv[6]) if len(argv) > 6 else 60 * 60 * 12

battle = Battle(rom, symf, save, trainer, seed, smart=SMART)
mem, W, sym = battle.mem, battle.W, battle.sym

counts = collections.Counter()


def count(name):
    def cb(ctx):
        counts[name] += 1
    return cb


# Log every enemy switch-in: 'mid' when the AI chose to switch (with the
# active and best switch-in matchup scores), 'forced' after a faint or Roar.
switch_log = []
pending = {'mid': False}


def on_try_switch(ctx):
    counts['AI_TrySwitch'] += 1
    pending['mid'] = True
    pending['scores'] = (mem[W('wEnemyAISwitchScore')], mem[W('wSmogonAIBestScore')])


def on_load_switch(ctx):
    b = battle.pb.register_file.B
    length = W('wOTPartyMon2') - W('wOTPartyMon1')
    switch_log.append({'kind': 'mid' if pending['mid'] else 'forced', 'from': mem[W('wEnemyMonSpecies')],
                       'from_hp': battle.word(W('wEnemyMonHP')),
                       'to': mem[W('wOTPartyMon1Species') + b * length], 'vs': mem[W('wBattleMonSpecies')],
                       'scores': pending.get('scores') if pending['mid'] else None})
    pending['mid'] = False


battle.on('AI_TrySwitch', on_try_switch)
battle.on('LoadEnemyMonToSwitchTo', on_load_switch)
for n in ['AI_Smogon', 'SwitchSmogon', 'AISmogon_ChooseReplacement', 'AISmogon_CanStopSetup',
          'AI_Smogon_Screens', 'AI_Smogon_BatonPass', 'AI_Smogon_Encore', 'AI_Smogon_HealBell', 'AI_Smogon_Explosion',
          'AI_Smogon_Phaze', 'AI_Smogon_Haze', 'AI_Smogon_Setup', 'AI_Smogon_Spikes', 'AI_Smogon_Toxic', 'AI_Smogon_Sleep',
          'AI_Smogon_RapidSpin', 'AI_Smogon_Heal', 'AISmogon_PlayerIsPhysical', 'AISmogon_PlayerCanPhaze',
          'AISmogon_FindBestSwitchIn']:
    if n in sym:
        battle.on(n, count(n))
    else:
        print('missing symbol', n)

battle.start()
result = battle.run(max_frames)
result = {'switches': switch_log, **result, 'hooks': dict(counts)}
print(json.dumps(result))
if len(argv) > 7:
    battle.screenshot(argv[7])
battle.stop()
