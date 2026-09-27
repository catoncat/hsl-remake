import copy
import json
import sys
import unittest
from pathlib import Path

sys.path.insert(0,str(Path(__file__).resolve().parent))
import hsltools.probes.tactical_items as native
import hsltools.probes.item_cure_route as route
import hsltools.probes.item_magic as mixed
import hsltools.data.consumables as consumables
import hsltools.data.tactical_items as data


class TacticalItemsTests(unittest.TestCase):
    def test_native_application_random_scan_and_boundaries(self):
        packet=json.loads(native.PACKET.read_text());native.check(packet)
        for mutation in ['boundary','derived','draw','bytes']:
            bad=copy.deepcopy(packet)
            if mutation=='boundary':bad['applications'][0]['normal_return']=True
            elif mutation=='derived':bad['applications'][0]['derived']['attack']+=1
            elif mutation=='draw':next(r for r in bad['applications'] if r['draws'])['draws'][0]['bound']+=1
            else:bad['anchors'][0]['bytes']='00'+bad['anchors'][0]['bytes'][2:]
            with self.assertRaises(ValueError):native.check(bad)

    def test_cure_category_and_mixed_strength_execution(self):
        packet=json.loads(route.PACKET.read_text());route.check(packet)
        bad=copy.deepcopy(packet);bad['cases'][0]['stop_address']='0x4408b8'
        with self.assertRaises(ValueError):route.check(bad)
        packet=json.loads(mixed.PACKET.read_text());mixed.check(packet)
        bad=copy.deepcopy(packet);bad['ticks'][0]['derived']['defense']+=1
        with self.assertRaises(ValueError):mixed.check(bad)

    def test_source_items_keep_source_initial_kits(self):
        compiled=consumables.build()
        self.assertEqual(json.loads(consumables.OUTPUT.read_text()),compiled)
        self.assertEqual(compiled['schema'],'hsl_first_battle_consumables.v4')
        source=native.sources()[0]
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
        trial,inventory=data.training()
        self.assertEqual(json.loads(data.TRIAL.read_text()),trial)
        self.assertEqual(json.loads(data.INVENTORY.read_text()),inventory)
        self.assertEqual(inventory['items'],consumables.build()['items'])
        self.assertEqual(trial['skill_rules']['initial_stamina'],0)
        self.assertEqual(inventory['initial_inventory']['002'],[247,250,262,263,227,232,244,241])
        self.assertNotIn('training_skill_grants',json.loads(Path('content/battles/first_battle.json').read_text()))
