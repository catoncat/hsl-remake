import copy
import json
import sys
import unittest
import hashlib
import struct
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from hsltools.data.gol_road import OUT, build
from hsltools.probes.player_install import PACKET, check


class GolRoadTests(unittest.TestCase):
    def test_formal_roster_and_event_have_separate_ownership(self):
        scene = build()
        self.assertEqual(json.loads(OUT.read_text()), scene)
        self.assertEqual([a['actor_id'] for a in scene['playable_units']], ['003','001','028','028','028','028','028'])
        self.assertNotIn('tina', [a['id'] for a in scene['playable_units']])
        self.assertEqual(scene['script_actor_templates']['obj_Story_Player2']['actor']['weapon_code'],82)
        self.assertEqual(scene['scenario_rules']['script_fallback']['escape_zone'], [])

    def test_actual_source_event_and_second_phase(self):
        scene = build()
        events = scene['scenario_rules']['status_timelines']['event_0']['events']
        self.assertEqual(sum(e['script_action_name']=='actInsertObject' for e in events),4)
        self.assertEqual(sum(e['script_action_name']=='actInsertStoryObject' and e['args'][0]=='obj_Story_Player2' for e in events),1)
        messages = [e['message_id'] for e in events if e['kind']=='dialogue_message_id']
        self.assertIn('768',messages)
        win = scene['scenario_rules']['status_timelines']['win_0']['events']
        self.assertTrue(any(e['script_action_name']=='actSetNextPlayLevelEvent' and e['args']==['2','55'] for e in win))

    def test_install_packet_has_actual_boundaries(self):
        packet = json.loads(PACKET.read_text())
        check(packet)
        self.assertTrue(packet['dispatch'])
        self.assertTrue(all(not r['normal_return'] for r in packet['dispatch']))
        self.assertTrue(all(r['normal_return'] for r in packet['enable']))
        for key in ['native_execution','exe_sha256','anchors_sha256']:
            bad=copy.deepcopy(packet);bad[key]=False
            with self.assertRaises(ValueError):check(bad)

    def test_conditional_slot_does_not_grant_a_missing_member(self):
        packet=json.loads(PACKET.read_text())
        for row in packet['dispatch']:
            case=row['input']
            if case['conditional'] and (case['before']==0 or case['before'] & 0x80000000):
                self.assertFalse(row['native']['constructs'])
                self.assertEqual(row['native']['after'],case['before'])

    def test_curated_play_receipts_and_frames_are_self_contained(self):
        root = Path(__file__).resolve().parents[1]
        folder = root / 'docs/evidence_packets/runtime_observations/gol_road'
        capture = json.loads((folder/'receipt.json').read_text())
        self.assertFalse(capture['native_execution'])
        self.assertEqual([r['mode'] for r in capture['routes']], ['natural','arrival','defeat_tina','campaign'])
        self.assertTrue(all(p['exit_code']==0 for p in capture['processes']))
        natural = capture['routes'][0]
        self.assertTrue(natural['initial_actor_ids'])
        self.assertTrue(natural['final_actors'])
        self.assertTrue(natural['script_transactions'][0]['created_ids'])
        campaign = capture['routes'][3]
        self.assertEqual(campaign['campaign_stages'],['res://content/battles/story_055.json','res://content/battles/story_056.json','res://content/world/world_map_scene.json'])
        self.assertEqual(set(campaign['carry']['units']),{'leonard','hu','tina'})
        self.assertEqual(campaign['initialization_rng_after'],natural['initialization_rng_after'])
        for frame in capture['frames']:
            data=(folder/frame['file']).read_bytes()
            self.assertEqual(hashlib.sha256(data).hexdigest(),frame['sha256'])
            self.assertEqual(struct.unpack('>II',data[16:24]),(640,480))


if __name__=='__main__':unittest.main()
