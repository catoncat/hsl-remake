"""hsltools.data tables pinned by native probes (original EXE results): each segment checks one generated
rule table against its probe (Gol road, growth lifecycle, large actor, moon dance, paralysis, permanent
items, position equipment, priest, role resources, stat magic, tactical items, traversal, treasure, water
strike, mobile jobs, departure, native stats, turn select); one segment per former file."""
from __future__ import annotations

# ---- from test_hsl_gol_road.py ----

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


# ---- from test_hsl_growth_lifecycle.py ----

import copy
import json
import sys
import unittest
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent))
from hsltools.probes.growth_lifecycle import PACKET as PACKET_growth_lifecycle, check as check_growth_lifecycle
from hsltools.data.growth_lifecycle import build as build_growth_lifecycle, OUT as OUT_growth_lifecycle
from hsltools.data.growth_lifecycle_trial import build as trial, OUT as TRIAL


class GrowthLifecycleTests(unittest.TestCase):
    def test_native_returns_and_call_boundaries(self):
        packet = json.loads(PACKET_growth_lifecycle.read_text())
        check_growth_lifecycle(packet)
        self.assertTrue(packet['rewards'])
        self.assertTrue(packet['learning'])
        self.assertTrue(all(not row['draws'] for row in packet['rewards'] + packet['learning']))
        self.assertTrue(any(not row['normal_return'] for row in packet['rewards']))
        for kind in ['reward', 'learning', 'source_bytes', 'table', 'vm']:
            with self.subTest(kind=kind):
                bad = copy.deepcopy(packet)
                if kind == 'reward': bad['rewards'][0]['native']['level'] += 1
                elif kind == 'learning': bad['learning'][0]['native']['rng_unchanged'] = False
                elif kind == 'source_bytes': bad['anchors'][0]['bytes'] = '00' + bad['anchors'][0]['bytes'][2:]
                elif kind == 'table': bad['special_tables']['80']['rows'][0]['attributes']['str'] -= 1
                else: bad['vm'][1]['latch'] = 1
                with self.assertRaises(ValueError): check_growth_lifecycle(bad)

    def test_source_masks_and_independent_thresholds(self):
        data = build_growth_lifecycle()
        self.assertEqual(json.loads(OUT_growth_lifecycle.read_text()), data)
        self.assertEqual(data['actors']['002']['magic:magicWATER'] & (1 << 4), 0)
        self.assertTrue(data['actors']['002']['magic:magicWATER'] & (1 << 5))
        cure = next(row for row in data['jobs']['85']['magic'] if row['id'] == 'magic:magicWATER:magicCode05')
        self.assertEqual(cure['level'], 6)
        self.assertEqual(cure['name'], '驅毒')
        self.assertEqual(data['jobs']['80']['magic'], [])
        self.assertEqual(data['jobs']['90']['special'], [])
        first = data['jobs']['80']['special'][0]
        self.assertEqual(first['attributes'], {'str':26, 'dex':20, 'mind':20, 'con':24})
        self.assertEqual(first['id'], 'special:magicAIR:magicCode01')

    def test_campaign_policy_keeps_learned_skills(self):
        data = json.loads(Path('content/battles/campaign.json').read_text())
        self.assertIn('learned_skills', data['carry_policy']['unit_keys'])
        self.assertIn('permanent_gains', data['carry_policy']['unit_keys'])

    def test_public_trial_uses_real_learning_identities(self):
        scene = trial()[TRIAL]
        actors = {row['id']: row for row in scene['playable_units']}
        self.assertEqual(actors['companion']['actor_id'], '001')
        self.assertEqual(actors['companion']['growth_profile']['allocation'], 'manual')
        self.assertEqual(actors['companion']['status_counters']['poison'], (16 << 16) | 3)
        self.assertEqual(actors['tina']['actor_id'], '002')
        self.assertNotIn('learned_skills', actors['tina'])
        self.assertEqual(actors['tina']['coord'], [10, 16])
        self.assertEqual(actors['companion']['coord'], [10, 15])
        self.assertTrue(all(row['coord'] == row['grid_coord'] for row in actors.values()))


# ---- from test_hsl_large_actor.py ----

import copy
import json
from pathlib import Path
import sys
import unittest

sys.path.insert(0,str(Path(__file__).resolve().parent))
import hsltools.probes.large_actor as probe
from hsltools.data.large_actor import build as build_large_actor
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
        actor,trial=build_large_actor()
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


# ---- from test_hsl_moon_dance.py ----

import copy
import json
import sys
import unittest
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parent))
from hsltools.probes.moon_dance import PACKET as PACKET_moon_dance, check as check_moon_dance
from hsltools.data.moon_dance import definition, check_assets, trial as trial_moon_dance, ID
from hsltools.data.skill_book import build as build_moon_dance


class MoonDanceTests(unittest.TestCase):
    def test_actual_original_callbacks_and_mutation_guards(self):
        packet=json.loads(PACKET_moon_dance.read_text());check_moon_dance(packet)
        for key in ['hp','draw','normal','cost','bytes']:
            bad=copy.deepcopy(packet)
            if key=='hp':bad['cases'][0]['results'][1]['native']['hp']+=1
            elif key=='draw':bad['cases'][1]['results'][0]['draws'][0]['bound']+=1
            elif key=='normal':bad['cases'][1]['results'][0]['normal_return']=True
            elif key=='cost':bad['suffixes'][0]['native']['stamina']+=20
            else:bad['anchors'][0]['bytes']='00'+bad['anchors'][0]['bytes'][2:]
            with self.assertRaises(ValueError):check_moon_dance(bad)

    def test_complete_source_program_assets_and_ownership(self):
        value=definition();check_assets(value)
        self.assertEqual(value['source_hit_delays'],[80,90,100,110,120])
        self.assertEqual(len([p for p in value['program'] if p['op']=='aniProcessHitMiss']),5)
        self.assertEqual(value['source_fields']['range'],'range0Cell')
        book=build_moon_dance()
        self.assertIn(ID,book['actors']['002']['supported_initial_ids'])
        self.assertNotIn(ID,book['actors']['001']['supported_initial_ids'])
        self.assertEqual(book['actors']['029']['supported_initial_ids'],[])

    def test_development_stamina_and_roster_are_explicit(self):
        value=trial_moon_dance()
        self.assertEqual(value['skill_rules']['initial_stamina'],40)
        self.assertTrue(value['playable_units'])
        self.assertIn('not a formal',value['development_note'])
        self.assertEqual(json.loads(Path('content/battles/first_battle.json').read_text())['skill_rules']['initial_stamina'],0)
        self.assertEqual(json.loads(Path('content/battles/priest_trial.json').read_text())['skill_rules']['initial_stamina'],0)


# ---- from test_hsl_paralysis.py ----

import copy
import json
from pathlib import Path
import sys
import unittest

sys.path.insert(0,str(Path(__file__).resolve().parent))
import hsltools.probes.paralysis as probe_paralysis
from hsltools.data.skill_book import build as skill_book
from hsltools.data.equipment import build as equipment
from hsltools.data.consumables import build as consumables
from hsltools.assets.paralysis_assets import definitions, OUT as OUT_paralysis
from hsltools.data.support_magic import check as assets_check


class ParalysisEvidenceTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.packet = json.loads(probe_paralysis.PACKET.read_text())

    def test_original_boundaries_and_tamper_rejection(self):
        probe_paralysis.check(self.packet)
        for kind in ['entry', 'application', 'return', 'bytes', 'draw']:
            broken = copy.deepcopy(self.packet)
            if kind == 'entry': broken['entries'][0]['native']['phase'] += 1
            elif kind == 'application': broken['applications'][0]['native']['contribution'] += 1
            elif kind == 'return': broken['applications'][0]['normal_return'] = True
            elif kind == 'bytes': broken['anchors'][0]['bytes'] = '00' + broken['anchors'][0]['bytes'][2:]
            else: next(r for r in broken['applications'] if r['draws'])['draws'][0]['bound'] = 1
            with self.assertRaises(ValueError): probe_paralysis.check(broken)

    def test_expiry_and_skip_preserve_the_original_independent_boundaries(self):
        skipped = [r for r in self.packet['entries'] if r['native']['skipped']]
        self.assertTrue(skipped)
        self.assertTrue(all(r['actor_queue_unchanged'] and not r['normal_return'] for r in skipped))
        self.assertEqual({r['input']['latch'] for r in skipped}, {0,1})
        capped = [r for r in self.packet['applications'] if r['input']['turns'] == 9]
        self.assertTrue(all(r['native']['contribution'] == 0 and r['native']['turns'] == 9 for r in capped))
        immune = [r for r in self.packet['applications'] if r['input']['effects']]
        self.assertTrue(all(not r['draws'] for r in immune))

        plain = [r for r in self.packet['gear'] if r['input']['codes'] == [2]]
        self.assertTrue(plain)
        for row in plain:
            self.assertEqual(row['native'][0]['values']['effects'],0x4000000 if row['input']['capability'] else 0)

    def test_source_ownership_cure_and_equipment_are_not_new_default_grants(self):
        book = skill_book(); sid = 'magic:magicEARTH:magicCode05'
        self.assertEqual([code for code,actor in book['actors'].items() if sid in actor['supported_initial_ids']], ['052','056','060'])
        self.assertEqual(book['skills'][sid]['fields']['function'], 'magicFun_Paralysis')
        self.assertEqual(book['skills'][sid]['fields']['status_hit_ratio'], '40')
        items = equipment()['items']
        for code in ['31','211']:
            self.assertTrue(items[code]['supported'])
            self.assertEqual(items[code]['status_effect_flags'] & 0x4000000, 0x4000000)
        self.assertTrue(items['71']['supported'])  # range6CellShoot: 0x409090 -> ITEM+0x84, 0x40f8b0 generic flood.
        medicine = consumables()
        self.assertEqual(medicine['items']['248']['cure_paralysis'], 1)
        self.assertEqual(medicine['items']['248']['heal_hp'], 0)
        self.assertNotIn(248, medicine['initial_inventory']['001'])
        # R27: 251 聖潔香水 registers once every cure bit it carries has a contract (cure_weaken);
        # registering it grants no initial inventory.
        self.assertEqual(medicine['items']['251']['cure_weaken'], 1)
        self.assertFalse(any(251 in slots for slots in medicine['initial_inventory'].values()))

    def test_original_local_effect_resources(self):
        assets_check(definitions(), OUT_paralysis)
        manifest = json.loads((OUT_paralysis/'manifest.json').read_text())
        self.assertEqual(len(manifest['images']),8)
        self.assertEqual(set(manifest['sounds']), {'WAV\\UPGROUND01.WAV','WAV\\BOMB0006.WAV'})


# ---- from test_hsl_permanent_items.py ----

import copy
import json
import sys
import unittest
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parent))
import hsltools.probes.permanent_items as probe_permanent_items
from hsltools.data.consumables import build as build_permanent_items
from hsltools.data.permanent_items import training

class PermanentItemTests(unittest.TestCase):
    def test_native_prefixes_and_full_refreshes(self):
        packet=json.loads(probe_permanent_items.PACKET.read_text());probe_permanent_items.check(packet)
        for part in ['sample','source','phase','bytes']:
            bad=copy.deepcopy(packet)
            if part=='sample':bad['cases'][0]['applications'][0]['draws'][0]['bound']+=1
            elif part=='source':bad['cases'][0]['applications'][0]['after']['attack_power']+=1
            elif part=='phase':bad['cases'][0]['refreshes'][1]['kind']='repeat_refresh'
            else:bad['anchors'][0]['bytes']='00'+bad['anchors'][0]['bytes'][2:]
            with self.assertRaises(ValueError):probe_permanent_items.check(bad)

    def test_source_fields_and_unchanged_initial_kits(self):
        result=build_permanent_items();items=result['items']
        for key,(code,field,_,_) in probe_permanent_items.FIELDS.items():
            self.assertEqual(items[str(code)]['permanent'],{key:[1,1] if code>=257 else [1,5]})
            self.assertEqual(items[str(code)]['local_attack'],[])
        self.assertEqual(result['initial_inventory']['001'],[int(probe_permanent_items.sources()[0]['001']['item'+str(i)]) for i in range(1,9)])
        self.assertFalse(set(range(253,262)) & set(result['initial_inventory']['002']))
        # 252 世界樹之葉 is registered on purpose for WINFAIL032 actUseItem (66841668); 251 聖潔香水 joined in R27
        # once cure_weaken had a contract — neither grants initial inventory.
        self.assertIn('251',items);self.assertIn('252',items)
        self.assertFalse(any(251 in slots for slots in result['initial_inventory'].values()))

    def test_public_trial_declares_inventory_not_free_gains(self):
        scene,inventory=training()
        self.assertEqual(scene['id'],'permanent_item_training')
        self.assertFalse(any('permanent_gains' in actor for actor in scene['playable_units']))
        self.assertEqual({code for slots in inventory['initial_inventory'].values() for code in slots if 253<=code<=261},set(range(253,262)))
        controlled=[actor['actor_id'] for actor in scene['playable_units'] if actor.get('player_commandable')]
        self.assertEqual({code for actor in controlled for code in inventory['initial_inventory'].get(actor,[]) if 253<=code<=261},set(range(253,262)))


# ---- from test_hsl_position_equipment.py ----

import copy
import json
import unittest
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent))
import hsltools.probes.position_equipment as probe_position_equipment
from hsltools.data.equipment import build as build_position_equipment
from hsltools.data.skill_book import build as book
from hsltools.data.attack_ranges import SOURCE, compile_ranges, weapon_ranges, ITEM_SOURCE


class PositionEquipmentTests(unittest.TestCase):
    def test_original_returns_and_boundaries(self):
        packet=json.loads(probe_position_equipment.PACKET.read_text())
        probe_position_equipment.check(packet)
        for mutate in ['value','boundary','bytes']:
            broken=copy.deepcopy(packet)
            if mutate=='value':broken['cases'][0]['native']['value']+=1
            elif mutate=='boundary':broken['cases'][0]['normal_return']=False
            else:broken['anchors'][0]['bytes']='00'+broken['anchors'][0]['bytes'][2:]
            with self.assertRaises(ValueError):probe_position_equipment.check(broken)

    def test_source_abilities_and_separate_equipment(self):
        items=build_position_equipment()['items'];actors=book()['actors']
        self.assertEqual([k for k,v in actors.items() if v['move_magic_use']],['020','059'])
        for code,move,extra in [('232',True,False),('233',False,True),('236',True,True)]:
            self.assertTrue(items[code]['supported'])
            self.assertEqual((items[code]['move_magic_use'],items[code]['add_attack_range']),(move,extra))
        self.assertTrue(items['69']['supported'])
        self.assertTrue(items['69']['double_attack'])
        self.assertEqual(items['69']['attack_range'], 'range5CellShoot')

    def test_source_range_indices_not_synthetic_dilation(self):
        patterns=compile_ranges(SOURCE.read_bytes().decode('cp950'))
        self.assertEqual([patterns[k]['index'] for k in ['range1Cell','range2Cell','range3Cell']],[1,2,3])
        self.assertEqual(len(patterns['range3Cell']['offsets']),12)
        self.assertNotIn([1,1],patterns['range3Cell']['offsets'])
        weapons = weapon_ranges(ITEM_SOURCE.read_bytes().decode('cp950'))
        self.assertEqual(weapons['0'], 'range0Cell')
        self.assertEqual(weapons['61'], 'range3CellShoot')
        self.assertEqual(weapons['69'], 'range5CellShoot')
        self.assertTrue(set(weapons.values()) <= {'range0Cell','range1Cell','range2Cell','range3CellShoot','range4CellShoot','range5CellShoot','range6CellShoot','range3CellCircle','range3CellThrust','range5CellCircle'})


# ---- from test_hsl_priest.py ----

import copy
import json
from pathlib import Path
import sys
import unittest

sys.path.insert(0,str(Path(__file__).resolve().parent))
import hsltools.probes.priest as priest
import hsltools.probes.priest_motion as motion
import hsltools.probes.mana_item as mana
from hsltools.assets.combat_animation import compile_action, PROGRAMS
from hsltools.data.priest import build as build_priest
from hsltools.probes.job_stats import sources


class PriestIntegrationTests(unittest.TestCase):
    def test_original_mapping_refresh_and_corruption(self):
        packet=json.loads(priest.PACKET.read_text());priest.check(packet)
        actual=next(r for r in packet['bindings'] if r['input']['slot']==1)
        self.assertEqual(actual['template_index'],2)
        self.assertNotEqual(actual['template_index'],actual['input']['previous_template'])
        for kind in ['template','stat','boundary','bytes']:
            bad=copy.deepcopy(packet)
            if kind=='template':bad['bindings'][1]['template_index']=29
            elif kind=='stat':bad['stats'][0]['native'][0]['values']['max_mp']+=1
            elif kind=='boundary':bad['bindings'][0]['prefix_stop']='0x407f15'
            else:bad['anchors'][0]['bytes']='00'+bad['anchors'][0]['bytes'][2:]
            with self.assertRaises(ValueError):priest.check(bad)

    def test_motion_proof_and_complete_source_program(self):
        packet=json.loads(motion.PACKET.read_text());motion.check(packet)
        source=next(r for r in json.loads(PROGRAMS.read_text())['records'] if r['code']=='SID_PLAYER1')
        dispatch=compile_action(source['programs']['action'],6)
        self.assertEqual(dispatch['motion_offsets'][0],[0,0])
        self.assertEqual(dispatch['motion_offsets'][-1],[0,0])
        self.assertEqual(min(p[1] for p in dispatch['motion_offsets']),-136)
        self.assertLess(next(e['update'] for e in dispatch['events'] if e['op']=='aniSetStopSpeed'),dispatch['release_update'])
        bad=copy.deepcopy(packet);bad['native']['states'][5]['y']+=1
        with self.assertRaises(ValueError):motion.check(bad)

    def test_mana_source_prefix_and_zero_draws(self):
        packet=json.loads(mana.PACKET.read_text());mana.check(packet)
        self.assertTrue(all(r['rng_calls']==0 for r in packet['cases']))
        self.assertTrue(any(r['native']['restored_mp']==0 for r in packet['cases']))
        bad=copy.deepcopy(packet);bad['cases'][0]['native']['flags']=9
        with self.assertRaises(ValueError):mana.check(bad)

    def test_trial_is_explicit_and_source_healing_is_not_granted_to_leonard(self):
        actor,scenario,rules,items=build_priest()
        self.assertEqual((actor['actor']['actor_id'],actor['actor']['growth_profile']['job_code']),('002',85))
        self.assertEqual(scenario['player_unit_id'],'tina')
        self.assertEqual(scenario['rule_adapter'],'development_battle')
        self.assertEqual(items['items']['244']['heal_mp'],30)
        self.assertEqual(rules['schema'],'hsl_development_objectives.v1')
        book=json.loads(Path('content/generated/hsl/skills/initial_book.json').read_text())
        self.assertEqual(book['actors']['002']['supported_initial_ids'],['special:magicOTHER:magicCode06','magic:magicWATER:magicCode06'])
        self.assertNotIn('magic:magicWATER:magicCode06',book['actors']['001']['supported_initial_ids'])
        players,_,_=sources()
        story=players['029']
        self.assertTrue(all(int(story.get(key,0))==0 for key in ['weapon_equip','head_equip','armor_equip','foot_equip','other1_equip','other2_equip']))
        self.assertEqual(book['actors']['029']['supported_initial_ids'],[])
        self.assertNotIn('029',json.loads(Path('content/generated/hsl/roles/profiles.json').read_text())['actors'])


# ---- from test_hsl_role_resources.py ----

import copy
import json
import sys
import unittest

from hsltools.sources.tables import authored_characters
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import hsltools.probes.job_stats as jobs
import hsltools.probes.recovery as recovery
from hsltools.data.role_profiles import build as build_role_resources, OUTPUT
from hsltools.data.equipment import build as equipment


class RoleResourceTests(unittest.TestCase):
    def test_native_packets_and_generated_roles(self):
        jobs.check(json.loads(jobs.PACKET.read_text()))
        recovery.check(json.loads(recovery.PACKET.read_text()))
        self.assertEqual(build_role_resources(), json.loads(OUTPUT.read_text()))

    def test_mutated_native_results_and_anchors_are_refused(self):
        for module, field in [(jobs, 'cases'), (recovery, 'prefixes')]:
            original = json.loads(module.PACKET.read_text())
            for kind in ('anchor', 'normal_return', 'missing'):
                broken = copy.deepcopy(original)
                if kind == 'anchor':
                    anchor = broken['anchors'][0]
                    anchor['bytes'] = '00' + anchor['bytes'][2:]
                elif kind == 'missing':
                    broken[field].pop()
                elif module is jobs:
                    broken[field][0]['native'][0]['normal_return'] = False
                else:
                    broken[field][0]['normal_return'] = True
                with self.assertRaises(ValueError):
                    module.check(broken)

    def test_recovery_native_draws_cover_all_six_values(self):
        packet = json.loads(recovery.PACKET.read_text())
        self.assertEqual({d['value'] for r in packet['prefixes'] for d in r['draws']}, set(range(6)))
        # Low amounts add, rather than clamp to, their small-resource bonus.
        self.assertEqual(recovery.amount('hp', 39, 1, 0), 4)
        self.assertEqual(recovery.amount('mp', 60, 0, 0), 3)

    def test_live_scope_is_not_all_classes_or_all_equipment(self):
        roles = build_role_resources()['actors']
        authored = {row['code'].zfill(3) for row in authored_characters()}
        original = {code: r for code, r in roles.items() if code not in authored}
        # Every proved 0x448840 branch: the base jobs plus the town job-up titles 81/82/84/86/87/89/97 (PLAYERS 010-020).
        self.assertEqual({r['profile']['job_code'] for r in original.values()}, {80,81,82,83,84,85,86,87,88,89,90,91,92,93,94,95,96,97,98,99})
        self.assertTrue(all(r['profile']['allocation'] == ('manual' if 1 <= int(code) <= 9 else 'fixed_template') for code, r in original.items()))
        # Authored rows declare their allocation and carry no evidence packet.
        self.assertTrue(all(r['profile']['allocation'] in ('manual', 'fixed_template') and 'evidence' not in r['profile'] for code, r in roles.items() if code in authored))
        items = equipment()['items']
        for code in ('218', '223', '224'):
            self.assertTrue(items[code]['supported'])
        self.assertTrue(items['145']['supported'])  # Independent casting-equipment follow-up.
        self.assertTrue(items['145']['hp_transfer_mp'])
        self.assertTrue(items['194']['supported'])  # add_defnese: no such string in the EXE, the ITEM loader never reads it.


# ---- from test_hsl_stat_magic.py ----

import copy
import json
import sys
import unittest
from pathlib import Path

sys.path.insert(0,str(Path(__file__).resolve().parent))
import hsltools.probes.stat_magic as native
import hsltools.probes.ai_stat as ai
import hsltools.data.stat_magic as data
from hsltools.data.skill_book import build as build_stat_magic


class StatMagicTests(unittest.TestCase):
    def test_bounded_native_application_refresh_and_expiry(self):
        packet=json.loads(native.PACKET.read_text())
        native.check(packet)
        for field in ['application','expiry','boundary','bytes']:
            bad=copy.deepcopy(packet)
            if field=='application':bad['applications'][0]['derived']['attack']+=1
            elif field=='expiry':bad['ticks'][-1]['derived']['defense']+=1
            elif field=='boundary':bad['applications'][0]['normal_return']=True
            else:bad['anchors'][0]['bytes']='00'+bad['anchors'][0]['bytes'][2:]
            with self.assertRaises(ValueError):native.check(bad)

    def test_original_ai_priority_and_nonredundant_scan(self):
        packet=json.loads(ai.PACKET.read_text())
        ai.check(packet)
        bad=copy.deepcopy(packet);bad['cases'][0]['result']['attempted']^=16
        with self.assertRaises(ValueError):ai.check(bad)
        self.assertEqual(ai.useful([0x20,0x40],0x30),0)
        self.assertEqual(ai.useful([0x20,0x40],0x10),1)
        self.assertEqual(ai.useful([0x20],0x20),0)

    def test_source_grants_and_explicit_training_remain_distinct(self):
        book=build_stat_magic();defs=data.definitions()
        self.assertEqual({k:v['fields']['expend'] for k,v in defs.items()},{'attack_up':'19','defense_up':'12','dispel':'18'})
        self.assertFalse(any(s['skill_id'] in book['actors']['002']['supported_initial_ids'] for s in defs.values()))
        self.assertTrue(all(defs[k]['skill_id'] in book['actors']['045']['supported_initial_ids'] for k in ['attack_up','defense_up']))
        self.assertIn(defs['dispel']['skill_id'],book['actors']['027']['supported_initial_ids'])
        self.assertEqual(book['actors']['029']['supported_initial_ids'],[])
        trial,inventory=data.training()
        self.assertEqual(json.loads(data.TRIAL.read_text()),trial)
        self.assertEqual(json.loads(data.INVENTORY.read_text()),inventory)
        self.assertEqual(set(trial['training_skill_grants']['002']),{s['skill_id'] for s in defs.values()})
        self.assertNotIn('training_skill_grants',json.loads(Path('content/battles/first_battle.json').read_text()))

    def test_source_effect_frames_and_audio_are_intact(self):
        data.check(data.definitions(),data.OUT,data.FRAME_MEMBERS)
        frames=data.FRAME_MEMBERS['MAGIC\\MIN12_01.SHP']
        self.assertEqual(len(frames),12)
        self.assertEqual(frames[3],'MAGIC\\MIN12_11.SHP')


# ---- from test_hsl_tactical_items.py ----

import copy
import json
import sys
import unittest
from pathlib import Path

sys.path.insert(0,str(Path(__file__).resolve().parent))
import hsltools.probes.tactical_items as native_tactical_items
import hsltools.probes.item_cure_route as route
import hsltools.probes.item_magic as mixed
import hsltools.data.consumables as consumables_tactical_items
import hsltools.data.tactical_items as data_tactical_items


class TacticalItemsTests(unittest.TestCase):
    def test_native_application_random_scan_and_boundaries(self):
        packet=json.loads(native_tactical_items.PACKET.read_text());native_tactical_items.check(packet)
        for mutation in ['boundary','derived','draw','bytes']:
            bad=copy.deepcopy(packet)
            if mutation=='boundary':bad['applications'][0]['normal_return']=True
            elif mutation=='derived':bad['applications'][0]['derived']['attack']+=1
            elif mutation=='draw':next(r for r in bad['applications'] if r['draws'])['draws'][0]['bound']+=1
            else:bad['anchors'][0]['bytes']='00'+bad['anchors'][0]['bytes'][2:]
            with self.assertRaises(ValueError):native_tactical_items.check(bad)

    def test_cure_category_and_mixed_strength_execution(self):
        packet=json.loads(route.PACKET.read_text());route.check(packet)
        bad=copy.deepcopy(packet);bad['cases'][0]['stop_address']='0x4408b8'
        with self.assertRaises(ValueError):route.check(bad)
        packet=json.loads(mixed.PACKET.read_text());mixed.check(packet)
        bad=copy.deepcopy(packet);bad['ticks'][0]['derived']['defense']+=1
        with self.assertRaises(ValueError):mixed.check(bad)

    def test_source_items_keep_source_initial_kits(self):
        compiled=consumables_tactical_items.build()
        self.assertEqual(json.loads(consumables_tactical_items.OUTPUT.read_text()),compiled)
        self.assertEqual(compiled['schema'],'hsl_first_battle_consumables.v4')
        source=native_tactical_items.sources()[0]
        for code in ['001','002']:
            self.assertEqual(compiled['initial_inventory'][code],[int(source[code][f'item{i}']) for i in range(1,9)])
        items=compiled['items']
        self.assertEqual(items['247']['cure_no_magic'],1)
        self.assertEqual(items['250']['restore_stamina'],20)
        self.assertEqual(items['262']['local_attack'],[5,10])
        self.assertEqual(items['263']['local_defense'],[5,10])
        self.assertEqual(items['262']['permanent'],{})
        self.assertEqual(items['263']['permanent'],{})

    def test_explicit_trial_uses_same_effect_catalog(self):
        trial,inventory=data_tactical_items.training()
        self.assertEqual(json.loads(data_tactical_items.TRIAL.read_text()),trial)
        self.assertEqual(json.loads(data_tactical_items.INVENTORY.read_text()),inventory)
        self.assertEqual(inventory['items'],consumables_tactical_items.build()['items'])
        self.assertEqual(trial['skill_rules']['initial_stamina'],0)
        self.assertEqual(inventory['initial_inventory']['002'],[247,250,262,263,227,232,244,241])
        self.assertNotIn('training_skill_grants',json.loads(Path('content/battles/first_battle.json').read_text()))


# ---- from test_hsl_traversal.py ----

import copy
import json
from pathlib import Path
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parent))
import hsltools.data.skill_book as book_traversal
import hsltools.probes.traversal as native_traversal
import hsltools.data.terrain_heights as heights


class TraversalTests(unittest.TestCase):
    def test_saved_normal_returns_and_landing_prefixes(self):
        packet = json.loads(native_traversal.PACKET.read_text())
        native_traversal.check(packet)
        self.assertTrue(all(packet[key] for key in ['helper', 'flood', 'landing']))

    def test_ground_start_on_cliff_crosses_only_near_cliff_heights(self):
        # 0x40f200 passes the start cell's own height to 0x40ed50: from 0xff a ground mode
        # enters only 0xff／253／254 neighbours (never steps down); flight ignores height.
        packet = json.loads(native_traversal.PACKET.read_text())
        rows = [row for row in packet['flood'] if [3, 3, 0xff000000] in row['input']['cells']]
        self.assertTrue(rows)
        for row in rows:
            flags = native_traversal.flags_for(row['input'])
            budget = row['input']['budget']
            reached = [(x - budget + 3, y - budget + 3) for y, line in enumerate(row['native']) for x, value in enumerate(line) if value > 0 and (x, y) != (budget, budget)]
            if row['input']['mode'] == 6:
                self.assertEqual(len(reached), 36)
            else:
                self.assertTrue(all(flags[cell] >> 24 >= 253 for cell in reached), row['input'])

    def test_source_traits_are_retained_without_granting_a_default_flyer(self):
        actors = book_traversal.build()['actors']
        for name in ['001', '021', '023', '024', '025', '026']:
            self.assertEqual(actors[name]['traversal'], {'flying': False, 'no_block': False, 'size_type': 0})
        self.assertTrue(actors['006']['traversal']['flying'])
        self.assertTrue(actors['101']['traversal']['no_block'])
        self.assertEqual(actors['017']['traversal']['size_type'], 1)

    def test_changed_native_output_boundary_or_bytes_is_not_accepted(self):
        packet = json.loads(native_traversal.PACKET.read_text())
        for kind in ['result', 'stop', 'return', 'bytes']:
            changed = copy.deepcopy(packet)
            if kind == 'result': changed['flood'][0]['native'][2][2] += 1
            elif kind == 'stop': changed['landing'][0]['native']['stop_address'] = '0x443d9d'
            elif kind == 'return': changed['landing'][0]['normal_return'] = True
            else: changed['anchors'][0]['bytes'] = '00' + changed['anchors'][0]['bytes'][2:]
            with self.subTest(kind=kind), self.assertRaises(ValueError): native_traversal.check(changed)

    def test_retained_heights_reconstruct_both_original_wrd_files(self):
        for level in heights.LEVELS:
            packet = json.loads(heights.paths_for_level(level)['terrain'].read_text())
            heights.validate(packet)
            changed = copy.deepcopy(packet)
            cell = changed['grid'][0][0]
            cell['h'] = (cell['h'] + 1) % 255
            cell['b'] = 0
            with self.subTest(level=level), self.assertRaisesRegex(ValueError, 'original WRD hash'): heights.validate(changed)


# ---- from test_hsl_treasure.py ----

import copy
import hashlib
import json
import struct
from pathlib import Path
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parent))
from hsltools.probes.treasure import PACKET as PACKET_treasure, check as check_treasure
from hsltools.data.treasures import OUTPUT as OUTPUT_treasure, build as build_treasure


class TreasureTests(unittest.TestCase):
    def test_actual_instance_contents_not_drop_probabilities(self):
        data = build_treasure()
        self.assertEqual(json.loads(OUTPUT_treasure.read_text()), data)
        # hidden: runtime-measured shape word 0xffff at round 1 (original_treasure.md §隐藏宝物).
        self.assertEqual([(r['record_index'], r['coord'], r['items'], r['hidden'])
                          for level in data['levels'].values() for r in level['chests']],
                         [(79, [20, 17], [202, 241, 246], True),
                          (23, [5, 14], [244, 244, 254], True),
                          (24, [15, 14], [2, 241], True)])
        self.assertEqual(set(data['levels']), {'1', '2'})

    def test_original_execution_boundaries_are_not_full_game_claims(self):
        packet = json.loads(PACKET_treasure.read_text())
        check_treasure(packet)
        self.assertTrue(all(r['proof']['normal_return'] for r in packet['copies'] + packet['initialization']))
        self.assertEqual(sum(not r['proof']['normal_return'] for r in packet['grants']), 7)
        self.assertTrue(all(r['repeated']['normal_return'] for r in packet['grants']))
        self.assertTrue(all(not r['proof']['normal_return'] for r in packet['contacts']))
        # The original copy compacts holes but does not itself clear leftover
        # template words: don't turn this source detail into a fake zero fill.
        sparse = next(r for r in packet['copies'] if r['tail'] == 777 and r['words'] == [0, 241, 0, 244, 0, 2, 0, 246])
        self.assertEqual(sparse['result'], [241, 244, 2, 246, 777, 777, 777, 777])

    def test_duplicate_items_aggregate_in_original_pending_queue(self):
        packet = json.loads(PACKET_treasure.read_text())
        duplicate = next(r for r in packet['grants'] if not r['opened'] and r['words'] == [241] * 8)
        self.assertEqual(duplicate['queue'], [[241, 10], [2, 1]])
        self.assertEqual(duplicate['proof']['item_calls'], [[241, 1]] * 8)
        self.assertEqual(duplicate['repeated']['item_calls'], [])
        self.assertTrue(duplicate['actor_unchanged'])

    def test_claim_forgery_and_source_drift_fail_closed(self):
        original = json.loads(PACKET_treasure.read_text())
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
            with self.assertRaises(ValueError): check_treasure(packet)

    def test_same_tile_flag_and_contact_are_independent_native_gates(self):
        rows = json.loads(PACKET_treasure.read_text())['contacts']
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


# ---- from test_hsl_water_strike.py ----

import copy
import json
import sys
import unittest
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent))
from hsltools.data.skill_book import build as build_water_strike
from hsltools.probes.water_strike import PACKET as PACKET_water_strike, check as check_water_strike
from hsltools.data.water_strike import OUT as OUT_water_strike, SKILL_ID, definitions as definitions_water_strike
from hsltools.data.water_strike_trial import build as trial_water_strike, OUT as TRIAL_water_strike


class WaterStrikeTests(unittest.TestCase):
    def test_exact_source_and_ownership(self):
        book=build_water_strike();spell=book['skills'][SKILL_ID]
        self.assertEqual(spell['fields'],definitions_water_strike()['water']['fields'])
        self.assertEqual(spell['element'],'1')
        self.assertIn(SKILL_ID,book['actors']['025']['supported_initial_ids'])
        self.assertNotIn(SKILL_ID,book['actors']['002']['supported_initial_ids'])
        self.assertNotIn(SKILL_ID,book['actors']['026']['supported_initial_ids'])

    def test_native_coverage_and_rejection(self):
        data=json.loads(PACKET_water_strike.read_text());check_water_strike(data)
        self.assertTrue(data['rolls'])
        self.assertTrue(data['applications'])
        bad=copy.deepcopy(data);bad['applications'][0]['normal_return']=True
        with self.assertRaises(ValueError):check_water_strike(bad)

    def test_original_assets_not_wind_reskins(self):
        data=json.loads((OUT_water_strike/'manifest.json').read_text())
        self.assertEqual(len(data['images']),11)
        self.assertEqual(set(data['sounds']),{'WAV\\WATER005.WAV'})
        self.assertTrue(all(name.startswith('MAGIC\\WAT') for name in data['images']))
        self.assertEqual(data['bindings']['water']['actions'][2],'effWait,80')

    def test_public_trial_has_real_learning_and_cross(self):
        data=trial_water_strike()[TRIAL_water_strike];actors={a['id']:a for a in data['playable_units']}
        self.assertEqual(actors['tina']['actor_id'],'002')
        self.assertNotIn('learned_skills',actors['tina'])
        self.assertEqual(sum(actors['tina']['combat_profile'][k] for k in ['str','dex','mind','con']),62)
        self.assertEqual(actors['enemy021_1']['coord'],[12,16])
        self.assertEqual(actors['enemy021_2']['coord'],[11,15])
        self.assertNotIn([11,16],[a['coord'] for a in actors.values()])


# ---- from test_hsl_mobile_jobs.py ----

import copy
import json
from pathlib import Path
import sys
import unittest

sys.path.insert(0,str(Path(__file__).resolve().parent))
import hsltools.probes.mobile_jobs as jobs_mobile_jobs
import hsltools.probes.mana_strike as mana_mobile_jobs
import hsltools.probes.mobile_motion as motion_mobile_jobs
import hsltools.probes.mobile_source as optional
from hsltools.data.mobile_jobs import build as build_mobile_jobs
from hsltools.assets.combat_animation import PROGRAMS, compile_action
from hsltools.data.equipment import build as equipment
from hsltools.data.combat_aftermath import build as aftermath

class MobileJobsTests(unittest.TestCase):
    def test_full_native_refresh_identity_and_boundaries(self):
        packet=json.loads(jobs_mobile_jobs.PACKET.read_text());jobs_mobile_jobs.check(packet)
        for kind in ['value','boundary','bytes']:
            bad=copy.deepcopy(packet)
            if kind=='value':bad['cases'][0]['native'][0]['values']['attack']+=1
            elif kind=='boundary':bad['cases'][0]['native'][0]['normal_return']=False
            else:bad['anchors'][0]['bytes']='00'+bad['anchors'][0]['bytes'][2:]
            with self.assertRaises(ValueError):jobs_mobile_jobs.check(bad)

    def test_mana_uses_capped_last_damage_and_keeps_source(self):
        packet=json.loads(mana_mobile_jobs.PACKET.read_text());mana_mobile_jobs.check(packet)
        lethal=next(r for r in packet['impact'] if r['input']==dict(hp=1,damage=300,mp=77,effects=mana_mobile_jobs.MP_FLAG))
        self.assertEqual(lethal['native'],dict(hp=0,contribution=1,mp=77,attacker_mp=51))
        bad=copy.deepcopy(packet);bad['impact'][0]['native']['mp']+=1
        with self.assertRaises(ValueError):mana_mobile_jobs.check(bad)
        self.assertTrue(any(r['native']['effect_called'] and r['input']['hp']==0 and r['input']['remaining']>0 for r in packet['caller']))
        self.assertTrue(all(not r['native']['effect_called'] for r in packet['caller'] if r['input']['remaining'] and r['input']['hp']))

    def test_exact_defaults_flight_and_hidden_skills(self):
        data=build_mobile_jobs();actors={c:data[Path(f'content/generated/hsl/actors/{c}.json')]['actor'] for c in jobs_mobile_jobs.ACTORS}
        for code,job,weapon in [('004',88,102),('006',92,43),('028',88,21),('036',92,33)]:
            self.assertEqual((actors[code]['growth_profile']['job_code'],actors[code]['weapon_code']),(job,weapon))
        book=json.loads(Path('content/generated/hsl/skills/initial_book.json').read_text())['actors']
        self.assertTrue(book['006']['traversal']['flying']);self.assertFalse(book['036']['traversal']['flying'])
        self.assertEqual(book['004']['supported_initial_ids'],['special:magicOTHER:magicCode10'])  # 銀之手: PLAYERS special_other initial (lane A)
        self.assertEqual(book['006']['supported_initial_ids'],['magic:magicAIR:magicCode01','special:magicOTHER:magicCode16'])
        item=equipment()['items']['108']
        self.assertTrue(item['supported']);self.assertEqual(item['weapon_effect_flags'],mana_mobile_jobs.MP_FLAG)
        self.assertTrue(item['job_mask']&(1<<8));self.assertFalse(item['job_mask']&(1<<12))

    def test_source_motion_and_optional_zero(self):
        motion_mobile_jobs.check(json.loads(motion_mobile_jobs.PACKET.read_text()));optional.check(json.loads(optional.PACKET.read_text()))
        programs={r['code']:r for r in json.loads(PROGRAMS.read_text())['records']}
        for token in ['SID_PLAYER3','SID_PLAYER5']:
            dispatch=compile_action(programs[token]['programs']['action'],12)
            self.assertLess(dispatch['release_update'],dispatch['complete_updates'])
            self.assertTrue(dispatch['presentation_transform_states'])
            self.assertEqual(dispatch['presentation_transform_states'][0],dict(offset=[0,0],zoom=65536))
        bad=json.loads(motion_mobile_jobs.PACKET.read_text());bad['xy'][0]['position'][0]+=1
        with self.assertRaises(ValueError):motion_mobile_jobs.check(bad)

    def test_authored_inventory_uses_actual_role_ids(self):
        data=build_mobile_jobs();trial=data[Path('content/battles/mobile_jobs_trial.json')]
        bag=data[Path('content/generated/hsl/development/mobile_jobs_inventory.json')]
        self.assertEqual(trial['player_unit_id'],'thief')
        self.assertEqual([a['actor_id'] for a in trial['playable_units'] if a['player_commandable']],['004','006','002'])
        self.assertIn(108,bag['initial_inventory']['004']);self.assertIn(232,bag['initial_inventory']['006'])
        first=json.loads(Path('content/battles/first_battle.json').read_text())
        self.assertNotIn('004',[a['actor_id'] for a in first['playable_units']])

    def test_new_roles_have_source_death_records_even_without_a_line(self):
        records=aftermath()['actors']
        for code in jobs_mobile_jobs.ACTORS:
            self.assertIn(code,records)
            self.assertIsInstance(records[code]['messages'],list)
            self.assertTrue(all(row['id'] and row['text'] for row in records[code]['messages']))


# ---- from test_hsl_departure.py ----

import copy,json,sys,unittest
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parent))
import hsltools.probes.departure as probe_departure

class DepartureEvidenceTests(unittest.TestCase):
    def test_native_phase_and_request_boundaries(self):
        packet=json.loads(probe_departure.PACKET.read_text());probe_departure.check(packet)
        self.assertTrue(packet['phases'])
        self.assertTrue(packet['requests'])
        self.assertTrue(packet['walk_requests'])
        self.assertTrue(packet['relookup'])
        self.assertTrue(all(r['normal_return'] for r in packet['walk_requests']))
        self.assertTrue(any(not r['normal_return'] for r in packet['phases']))
        self.assertTrue(any(r['normal_return'] and not r['native']['active'] for r in packet['phases']))
    def test_reject_modified_source_result_and_order(self):
        original=json.loads(probe_departure.PACKET.read_text())
        for mutate in ['bytes','vitals','current','order','boundary','request']:
            packet=copy.deepcopy(original)
            cleanup=next(r for r in packet['phases'] if '0x44cb90' in r['calls'])
            if mutate=='bytes':packet['anchors'][0]['bytes']='00'+packet['anchors'][0]['bytes'][2:]
            elif mutate=='vitals':cleanup['native']['vitals_unchanged']=False
            elif mutate=='current':cleanup['native']['index']=99
            elif mutate=='order':cleanup['calls'].reverse()
            elif mutate=='boundary':cleanup['stop_address']='0x0'
            else:packet['requests'][0]['native_index']=2
            with self.assertRaises(ValueError,msg=mutate):probe_departure.check(packet)


# ---- from test_hsl_native_stats_probe.py ----

import json
import unittest
from pathlib import Path

from tools.hsl_native_stats_probe import DEFAULT_ACTORS


class NativeStatsProbeTests(unittest.TestCase):
    def test_default_actor_set_remains_first_battle_compatible(self):
        self.assertEqual(DEFAULT_ACTORS, ('1', '21', '23', '24', '26'))

    def test_second_battle_packet_extends_without_changing_first_battle_results(self):
        first = json.loads(Path('docs/evidence_packets/static_reverse/first_battle_template_stats.json').read_text())
        second = json.loads(Path('docs/evidence_packets/static_reverse/second_battle_template_stats.json').read_text())
        self.assertEqual(first['exe_sha256'], second['exe_sha256'])
        self.assertEqual(first['inputs_sha256'], second['inputs_sha256'])
        for actor_id in ('001', '021', '023', '024', '026'):
            self.assertEqual(first['actors'][actor_id], second['actors'][actor_id])
        self.assertEqual(second['actors']['025']['equipped']['max_hp'], 91)
        self.assertEqual(second['actors']['025']['equipped']['attack'], 58)
        self.assertEqual(second['actors']['025']['equipped']['defense'], 46)
        self.assertEqual(second['actors']['025']['equipped']['speed'], 16)
        self.assertEqual(second['actors']['025']['equipped']['hit_rate'], 92)
        self.assertEqual(second['actors']['069']['base']['mode'], 'pmPlayer')


# ---- from test_hsl_native_turn_select_probe.py ----

import copy
import json
from pathlib import Path
import sys
import unittest
sys.path.insert(0, str(Path(__file__).resolve().parent))
from hsltools.probes.turn_select import PACKET as PACKET_native_turn_select_probe, check_packet


class TurnSelectorEvidenceTests(unittest.TestCase):
    def test_saved_original_returns(self):
        check_packet(json.loads(PACKET_native_turn_select_probe.read_text()))

    def test_wrong_successor_or_round_is_rejected(self):
        source = json.loads(PACKET_native_turn_select_probe.read_text())
        for field, value in [('index', 199), ('round', 8)]:
            changed = copy.deepcopy(source)
            changed['cases'][1]['native'][field] = value
            with self.assertRaisesRegex(ValueError, 'fixture/output'):
                check_packet(changed)

    def test_budget_overrun_or_missing_return_cannot_be_evidence(self):
        source = json.loads(PACKET_native_turn_select_probe.read_text())
        for field, value in [('instructions', 4097), ('normal_return', False)]:
            changed = copy.deepcopy(source)
            changed['cases'][0][field] = value
            with self.assertRaisesRegex(ValueError, 'normal return'):
                check_packet(changed)


if __name__ == "__main__":
    import unittest
    unittest.main()
