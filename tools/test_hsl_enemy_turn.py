"""enemy_turn oracle: the tracked packet validates offline and every tampering is rejected;
with unicorn and the documented hsl01.exe present, the sample turn re-runs identically."""
import copy
import importlib.util
import json
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import hsltools.probes.enemy_turn as et  # noqa: E402
from hsltools.paths import ORIGINAL_EXE  # noqa: E402


def packet() -> dict:
    return json.loads(et.PACKET.read_text(encoding='utf-8'))


def sample_action(data: dict, actor: str) -> dict:
    return next(a for a in data['turns'][0]['actions'] if a['actor'] == actor)


class EnemyTurnPacketTests(unittest.TestCase):
    def test_tracked_packet_validates(self):
        data = packet()
        et.validate(data)
        sample = data['turns'][0]
        self.assertEqual(sample['meta']['stop'], 'player_control')
        self.assertEqual(sample['meta']['next_actor'], 'leonard')
        attack = sample_action(data, 'actor021_2')
        self.assertEqual((attack['action'], attack['target']), ('attack', 'actor023_2'))
        self.assertTrue(any(d['stream'] == 'damage' for d in attack['draws']))
        self.assertTrue(all(t['meta']['stop'] == 'player_control' for t in data['turns']))
        self.assertIn('ENEMY_TURN_ORACLE_PASS turns=5', et.summary_line(data, False))

    def test_tampering_is_rejected(self):
        def regression(d): sample_action(d, 'actor026_1')['to'] = [12, 7]
        def attack_target(d): sample_action(d, 'actor021_2')['target'] = None
        def attack_damage(d):
            action = sample_action(d, 'actor021_4')
            action['draws'] = [x for x in action['draws'] if x['stream'] != 'damage']
        def stalled(d): d['turns'][2]['meta']['stop'] = 'frame_limit'
        def modulus(d):
            draw = next(x for x in sample_action(d, 'actor026_2')['draws'] if x['n'])
            draw['value'] = draw['n']
        def wait_target(d): sample_action(d, 'actor021_3')['target'] = 'actor023_1'
        def draw_stream(d): sample_action(d, 'actor024_1')['draws'][0]['stream'] = 'ai'
        def queue_tie(d):
            order = d['queue_sort'][0]['order']
            i = [e[0] for e in order].index('leonard')
            order[i], order[i + 1] = order[i + 1], order[i]
        def ablation(d): d['ablations'][0]['stop'] = 'player_control'
        def spike_wait(d): d['ablations'][-1]['transition_pending'] = 0
        def seed(d): d['turns'][1]['rng']['global'] = [9, 9]
        def growth_stream(d): d['growth']['damage_wrappers'] = ['0x42c780']
        def growth_sites(d): d['growth']['rand_sites'][:2] = ['0x42c7af', '0x42c7af']
        def order(d):
            actions = d['turns'][0]['actions']
            actions[0], actions[1] = actions[1], actions[0]
        for tamper in (regression, attack_target, attack_damage, stalled, modulus, wait_target, draw_stream,
                       queue_tie, ablation, spike_wait, seed, order, growth_stream, growth_sites):
            bad = copy.deepcopy(packet())
            tamper(bad)
            with self.subTest(tamper.__name__), self.assertRaises(ValueError):
                et.validate(bad)

    def test_player_turn_end_sequence_is_required(self):
        """The player's own turn-end sequence (+0x8c = 0x10000) ran to the handoff in every turn."""
        for turn in packet()['turns']:
            self.assertEqual(turn['meta']['handoff']['actor'], 'leonard')
            self.assertIsNotNone(turn['meta']['handoff']['frames'][1])
        def missing(d): d['turns'][0]['meta'].pop('handoff')
        def unfinished(d): d['turns'][3]['meta']['handoff']['frames'][1] = None
        for tamper in (missing, unfinished):
            bad = copy.deepcopy(packet())
            tamper(bad)
            with self.subTest(tamper.__name__), self.assertRaises(ValueError):
                et.validate(bad)

    def test_round_lines_match_the_remake_exporter_shape(self):
        lines = et.round_lines(packet()['turns'][0])
        self.assertEqual([line['turn'] for line in lines], [1, 2])
        self.assertEqual([len(line['actions']) for line in lines], [6, 5])
        self.assertEqual(lines[0]['rng'], packet()['turns'][0]['rng'])
        self.assertEqual(lines[1]['rng'], {})
        self.assertTrue(all(a['draws'] == [] for line in lines for a in line['actions']))
        self.assertEqual(list(lines[0]), ['format', 'battle', 'turn', 'rng', 'actions'])


@unittest.skipUnless(importlib.util.find_spec('unicorn') and ORIGINAL_EXE.is_file(),
                     'needs unicorn (uv run --with unicorn==2.1.4) and the documented hsl01.exe')
class EnemyTurnExecutionTests(unittest.TestCase):
    def test_sample_turn_reruns_identically(self):
        turn = et.run_turn(ORIGINAL_EXE, et.SAVE.read_bytes())
        tracked = packet()['turns'][0]
        self.assertEqual({k: v for k, v in turn.items() if k != 'meta'}, {k: v for k, v in tracked.items() if k != 'meta'})
        self.assertEqual(turn['meta']['hp_end'], tracked['meta']['hp_end'])


if __name__ == '__main__':
    unittest.main()
