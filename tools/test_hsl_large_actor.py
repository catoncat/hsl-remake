import copy
import json
from pathlib import Path
import sys
import unittest

sys.path.insert(0,str(Path(__file__).resolve().parent))
import hsltools.probes.large_actor as probe
from hsltools.data.large_actor import build
from hsltools.data.ai_profiles import build as ai_profiles
from hsltools.data.skill_book import build as skill_book
from hsltools.evidence.actor_walk_manifest import check_actor_walk_manifest
from hsltools.assets.interface_audio import weapon_hits


class LargeActorEvidenceTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.packet=json.loads(probe.PACKET.read_text())

    def test_bounded_native_receipts_and_tamper_rejection(self):
        probe.check(self.packet)
        for kind in ('lookup','marking','flood','enumeration','stats','loader','boundary','bytes'):
            p=copy.deepcopy(self.packet)
            if kind=='lookup':p['lookup'][0]['native']=123
            elif kind=='marking':p['marking'][0]['native']['cleared'][0]^=1
            elif kind=='flood':p['flood'][0]['native'][0][0]^=1
            elif kind=='enumeration':p['enumeration'][0]['native'].append(0)
            elif kind=='stats':p['stats'][0]['native'][0]['values']['attack']+=1
            elif kind=='loader':p['ai_defaults'][0]['native']=1
            elif kind=='boundary':p['ai_defaults'][0]['normal_return']=True
            else:p['ai_defaults'][0]['bytes']='00'+p['ai_defaults'][0]['bytes'][2:]
            with self.assertRaises(ValueError):probe.check(p)

    def test_original_flight_transit_and_single_identity(self):
        self.assertEqual(len(probe.body([4,4],1)),9)
        flying=[r for r in self.packet['flood'] if r['input']['mode']==6]
        self.assertTrue(any(v&0x80 for r in flying for line in r['native'] for v in line))
        for row in self.packet['enumeration']:
            self.assertEqual(len(row['native']),len(set(row['native'])))
        self.assertTrue(all(r['only_own_ring_removed'] and r['actor_unchanged'] for r in self.packet['flood']))

    def test_source039_and_development_grants_stay_separate(self):
        actor,trial=build()
        self.assertEqual(actor['actor_id'],'039')
        self.assertEqual(actor['growth_profile']['job_code'],94)
        self.assertEqual(actor['weapon_code'],40)
        self.assertTrue(trial['development_only'])
        self.assertEqual([u['actor_id'] for u in trial['playable_units']].count('039'),1)
        source=skill_book()['actors']['039']
        self.assertEqual(source['traversal']['size_type'],1)
        self.assertEqual(source['supported_initial_ids'],[])
        self.assertFalse(source['move_magic_use'])
        for name in ('first_battle','battle_052'):
            current=json.loads(Path('content/battles/'+name+'.json').read_text())
            self.assertNotIn('039',[u['actor_id'] for u in current['playable_units']])

    def test_ai_zeros_come_from_the_executed_missing_key_path(self):
        row=ai_profiles()['actors']['039']
        self.assertIn(row['profile']['find_type'],ai_profiles()['find_types'].values())
        self.assertEqual(row['missing_required'],[])
        self.assertEqual(row['defaulted_fields'],{key:0 for key in probe.AI_LOADER})
        self.assertEqual(row['profile']['find_range'],80)
        self.assertEqual(row['profile']['ai_lock'],80)
        self.assertTrue(all(r['parser_executed'] and not r['normal_return'] for r in self.packet['ai_defaults']))

    def test_all_source_body_art_groups_are_bound(self):
        path=Path('content/imported/hsl/chapter01/actor_walk_frames/actor_walk_manifest.json')
        check_actor_walk_manifest(path,['001','021','023','024','025','026','039'])
        actor=json.loads(path.read_text())['actors']['039']
        self.assertEqual(actor['frame_count'],30)
        self.assertEqual(actor['missing_source_members'],[])
        self.assertEqual(set(actor['animations']['walk']),{'up','down','left','right'})
        combat=json.loads(Path('content/imported/hsl/chapter01/combat_animation/manifest.json').read_text())['actors']['039']
        self.assertEqual(len(combat['frames']),5)
        self.assertEqual(combat['dispatch']['release_update'],33)
        self.assertEqual(combat['special_frames'],[])  # declared: no s_shape strip imported
        panels=json.loads(Path('content/imported/hsl/shared/panels/manifest.json').read_text())
        self.assertEqual(panels['actors']['039']['race'],'獸族')
        self.assertEqual(panels['actors']['039']['title'],'海輝魔')
        self.assertTrue(panels['assets']['itemIconClaw']['empty'])
        self.assertEqual(panels['assets']['itemIconClaw']['res_path'],'')
        self.assertEqual(weapon_hits()['40'],'')
