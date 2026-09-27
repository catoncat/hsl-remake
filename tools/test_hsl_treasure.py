import copy
import hashlib
import json
import struct
from pathlib import Path
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parent))
from hsltools.probes.treasure import PACKET, check
from hsltools.data.treasures import OUTPUT, build


class TreasureTests(unittest.TestCase):
    def test_actual_instance_contents_not_drop_probabilities(self):
        data = build()
        self.assertEqual(json.loads(OUTPUT.read_text()), data)
        # hidden: runtime-measured shape word 0xffff at round 1 (original_treasure.md §隐藏宝物).
        self.assertEqual([(r['record_index'], r['coord'], r['items'], r['hidden'])
                          for level in data['levels'].values() for r in level['chests']],
                         [(79, [20, 17], [202, 241, 246], True),
                          (23, [5, 14], [244, 244, 254], True),
                          (24, [15, 14], [2, 241], True)])
        self.assertEqual(set(data['levels']), {'1', '2'})

    def test_original_execution_boundaries_are_not_full_game_claims(self):
        packet = json.loads(PACKET.read_text())
        check(packet)
        self.assertTrue(all(r['proof']['normal_return'] for r in packet['copies'] + packet['initialization']))
        self.assertEqual(sum(not r['proof']['normal_return'] for r in packet['grants']), 7)
        self.assertTrue(all(r['repeated']['normal_return'] for r in packet['grants']))
        self.assertTrue(all(not r['proof']['normal_return'] for r in packet['contacts']))
        # The original copy compacts holes but does not itself clear leftover
        # template words: don't turn this source detail into a fake zero fill.
        sparse = next(r for r in packet['copies'] if r['tail'] == 777 and r['words'] == [0, 241, 0, 244, 0, 2, 0, 246])
        self.assertEqual(sparse['result'], [241, 244, 2, 246, 777, 777, 777, 777])

    def test_duplicate_items_aggregate_in_original_pending_queue(self):
        packet = json.loads(PACKET.read_text())
        duplicate = next(r for r in packet['grants'] if not r['opened'] and r['words'] == [241] * 8)
        self.assertEqual(duplicate['queue'], [[241, 10], [2, 1]])
        self.assertEqual(duplicate['proof']['item_calls'], [[241, 1]] * 8)
        self.assertEqual(duplicate['repeated']['item_calls'], [])
        self.assertTrue(duplicate['actor_unchanged'])

    def test_claim_forgery_and_source_drift_fail_closed(self):
        original = json.loads(PACKET.read_text())
        mutations = [
            lambda p: p.update(native_execution=False),
            lambda p: p.update(exe_sha256='0' * 64),
            lambda p: p.update(anchors_sha256='0' * 64),
            lambda p: p['sources']['levels'][0]['chests'][0]['words'].__setitem__(0, 281),
            lambda p: p['grants'][0]['proof'].update(normal_return=True),
            lambda p: p['grants'][0]['proof'].update(rng_unchanged=False),
            lambda p: p['grants'][0]['repeated'].update(item_calls=[[202, 1]]),
            lambda p: p['initialization'][0]['values'].__setitem__(6, 64),
            lambda p: p['contacts'][0]['proof'].update(stop='0x4156d0'),
        ]
        for mutation in mutations:
            packet = copy.deepcopy(original)
            mutation(packet)
            with self.assertRaises(ValueError): check(packet)

    def test_same_tile_flag_and_contact_are_independent_native_gates(self):
        rows = json.loads(PACKET.read_text())['contacts']
        self.assertEqual([r['proof']['stop'] for r in rows],
                         ['0x44556f', '0x4156d0', '0x4477b0', '0x411b90', '0x411b90', '0x4156d0', '0x411b90'])
        self.assertTrue(all(r['chest_unchanged'] for r in rows))

    def test_curated_controls_and_true_cross_process_recovery(self):
        folder = Path(__file__).resolve().parents[1] / 'docs/evidence_packets/runtime_observations/treasure'
        review = json.loads((folder / 'receipt.json').read_text())
        self.assertFalse(review['native_execution'])
        routes = {r['mode']: r for r in review['routes']}
        self.assertEqual(set(routes), {'natural_pickup', 'full', 'duplicates', 'attack',
                                     'defeat', 'victory', 'campaign', 'resume_pool'})
        self.assertTrue(review['processes'])
        self.assertTrue(all(p['exit_code'] == 0 and p['unchanged_during_verification']
                            for p in review['processes']))
        self.assertEqual(routes['natural_pickup']['final']['battle_outcome'], '')
        self.assertEqual(routes['natural_pickup']['final']['treasures']['opened_ids'], ['2:24'])
        self.assertTrue(routes['victory']['final']['battle_outcome'].startswith('victory'))
        self.assertTrue(routes['defeat']['final']['battle_outcome'].startswith('defeat'))
        self.assertTrue(routes['defeat']['restarted'])
        campaign = routes['campaign']
        self.assertTrue(campaign['fresh_process'])
        self.assertNotEqual(campaign['producer']['pid'], campaign['consumer_pid'])
        producer = next(p for p in review['processes'] if 'victory' in p['accepted_routes'])
        self.assertEqual(producer['pid'], campaign['producer']['pid'])
        self.assertEqual(campaign['final'], routes['victory']['final'])
        self.assertEqual(campaign['stages'], ['res://content/battles/story_055.json',
                                            'res://content/battles/story_056.json',
                                            'res://content/world/world_map_scene.json'])
        self.assertTrue(campaign['carry']['pending_rewards']['items'])
        resumed = routes['resume_pool']
        self.assertEqual(len(resumed['final']['settlement']['pending']),
                         len(resumed['initial']['settlement']['pending']) - 1)
        self.assertEqual(resumed['final']['treasures']['opened_ids'], [])
        prior = json.loads((folder / 'preceding_party.json').read_text())
        self.assertEqual(prior['carry']['units']['leonard']['level'], 2)
        self.assertEqual(prior['carry']['units']['hu']['level'], 4)
        self.assertTrue(review['frames'])
        for frame in review['frames']:
            data = (folder / frame['file']).read_bytes()
            self.assertEqual(hashlib.sha256(data).hexdigest(), frame['sha256'])
            self.assertEqual(struct.unpack('>II', data[16:24]), (640, 480))


if __name__ == '__main__': unittest.main()
