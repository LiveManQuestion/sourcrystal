"""Show how each AI scoring layer changes the move scores, turn by turn.

usage: ai_layers.py ROM SYM SAVE TRAINER SEED [--species NAME] [--frames N]

Plays one battle like ai_trace.py (the smart player; PLAYER_LEVEL works the
same) and hooks AIChooseMove.CheckLayer, which runs after each layer: every
AIChooseMove call prints the enemy's Pokemon and the player's, then each
layer that changed a score with the scores after it (lower is better; 80
is a move out of PP or disabled). --species only prints the turns of that
enemy species."""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from battle_harness import Battle  # noqa: E402
from pokedata import move_name, species_name  # noqa: E402

LAYERS = ['AI_Basic', 'AI_Setup', 'AI_Types', 'AI_Offensive', 'AI_Smart', 'AI_Opportunist', 'AI_Aggressive',
          'AI_Cautious', 'AI_Status', 'AI_Risky', 'AI_Immunities', 'AI_Smogon', 'AI_Legendary']


def main(argv):
    def opt(name, default=None):
        if name in argv:
            i = argv.index(name)
            value = argv[i + 1]
            del argv[i:i + 2]
            return value
        return default
    species = opt('--species')
    frames = int(opt('--frames', 216000))
    rom, symf, save, trainer, seed = argv[:5]
    battle = Battle(rom, symf, save, trainer, seed, smart=True)
    mem, W = battle.mem, battle.W
    state = {'scores': None}

    def scores():
        return [mem[W('wEnemyAIMoveScores') + k] for k in range(4)]

    def on_choose(ctx):
        state['scores'] = scores()
        state['show'] = species is None or species_name(mem[W('wEnemyMonSpecies')]) == species
        if state['show']:
            moves = [move_name(mem[W('wEnemyMonMoves') + k]) for k in range(4)]
            print(f"turn {mem[W('wEnemyTurnsTaken')]}: {species_name(mem[W('wEnemyMonSpecies')])} "
                  f"{battle.word(W('wEnemyMonHP'))}/{battle.word(W('wEnemyMonMaxHP'))} vs "
                  f"{species_name(mem[W('wBattleMonSpecies')])} "
                  f"{battle.word(W('wBattleMonHP'))}/{battle.word(W('wBattleMonMaxHP'))}, "
                  f"weather {mem[W('wBattleWeather')]}: {moves}")

    def on_layer(ctx):
        # the stack holds hl, then bc: c is the next layer's index
        sp = battle.pb.register_file.SP
        layer = mem[sp + 2] - 1
        now = scores()
        if state['scores'] is not None and now != state['scores'] and state.get('show') and layer >= 0:
            name = LAYERS[layer] if layer < len(LAYERS) else str(layer)
            print(f'  {name:15} {now}')
        state['scores'] = now

    def on_spent(ctx):
        if state.get('show'):
            print(f'  final           {scores()}')

    battle.on('AIChooseMove.ApplyLayers', on_choose)
    battle.on('AIChooseMove.CheckLayer', on_layer)
    battle.on('AIChooseMove.CheckSpent', on_spent)
    battle.start()
    result = battle.run(frames)
    battle.stop()
    print({k: result[k] for k in ('won', 'player_left', 'enemy_left')})


if __name__ == '__main__':
    main(sys.argv[1:])
