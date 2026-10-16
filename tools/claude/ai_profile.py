"""Time AI code in headless battles, in scanlines (154 per frame).

usage: ai_profile.py ROM SYM SAVE TRAINER SEED [--random] [--frames N] [SPAN...]
  SPAN: START:END[|END2...][=name], labels from the .sym file. The span
  starts when the CPU reaches START and ends at the first END reached.

Without SPANs it times the Smogon AI's switch decision (SwitchSmogon to
DontSwitch or SwitchSmogon.switch), the switch-in search
(AISmogon_FindBestSwitchIn to .done) and the parts of a matchup score. The
time is frame * 154 + LY, so it counts every cycle the game spends,
interrupts included; a frame is 154 scanlines (16.7 ms), and the overworld
step code has no spare frame time at all. Plays one battle with
battle_harness.py (the smart player unless --random)."""
import collections
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

DEFAULT_SPANS = [
    'SwitchSmogon:DontSwitch|SwitchSmogon.switch=switch decision',
    'AISmogon_FindBestSwitchIn:AISmogon_FindBestSwitchIn.done=switch-in search',
    'AISmogon_ScoreMatchup:AISmogon_ScoreMatchup.player_moves_done=score: player attacks',
    'AISmogon_ScoreMatchup.player_can_attack:AISmogon_ScoreMatchup.our_moves_done=score: our attacks',
    'AISmogon_ScoreMatchup.our_moves_done:AISmogon_ScoreMatchup.got_turns=score: healing and turns',
    'AISmogon_AttackDamage:AISmogon_AttackDamage.done=one attack',
]


def main(argv):
    from battle_harness import Battle
    rom, symf, save, trainer, seed = argv[:5]
    rest = argv[5:]
    smart = '--random' not in rest
    frames = 216000
    if '--frames' in rest:
        frames = int(rest[rest.index('--frames') + 1])
        rest = [a for i, a in enumerate(rest) if a != '--frames' and (i == 0 or rest[i - 1] != '--frames')]
    specs = [a for a in rest if ':' in a] or DEFAULT_SPANS
    battle = Battle(rom, symf, save, trainer, seed, smart=smart)
    now = lambda: battle.pb.frame_count * 154 + battle.mem[0xff44]
    started, times = {}, collections.defaultdict(list)
    for spec in specs:
        spec, _, name = spec.partition('=')
        start, ends = spec.split(':')
        name = name or spec
        missing = [label for label in [start] + ends.split('|') if label not in battle.sym]
        if missing:
            print('missing labels:', ', '.join(missing), '- skipping', name)
            continue

        def on_start(ctx, name=name):
            started[name] = now()

        def on_end(ctx, name=name):
            if name in started:
                times[name].append(now() - started.pop(name))
        battle.on(start, on_start)
        for end in ends.split('|'):
            battle.on(end, on_end)
    battle.start()
    result = battle.run(frames)
    battle.stop()
    print(f'{trainer} seed {seed}: ended {result["ended"]}, AI won {result["won"] == 1}, '
          f'{result["frames"]} frames')
    print(f'{"span":32} {"calls":>6} {"mean":>8} {"max":>8}   scanlines (154 = 1 frame)')
    for spec in specs:
        name = spec.partition('=')[2] or spec.partition('=')[0]
        t = times.get(name)
        if t:
            print(f'{name[:32]:32} {len(t):6} {sum(t) / len(t):8.1f} {max(t):8}   '
                  f'max {max(t) / 154:.1f} frames')


if __name__ == '__main__':
    if len(sys.argv) < 6:
        print(__doc__)
    else:
        main(sys.argv[1:])
