import copy
import json
import sys
import unittest
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parent))
import hsltools.probes.permanent_items as probe
from hsltools.data.consumables import build
from hsltools.data.permanent_items import training

class PermanentItemTests(unittest.TestCase):
    def test_native_prefixes_and_full_refreshes(self):
        packet=json.loads(probe.PACKET.read_text());probe.check(packet)
        for part in ['sample','source','phase','bytes']:
            bad=copy.deepcopy(packet)
            if part=='sample':bad['cases'][0]['applications'][0]['draws'][0]['bound']+=1
            elif part=='source':bad['cases'][0]['applications'][0]['after']['attack_power']+=1
            elif part=='phase':bad['cases'][0]['refreshes'][1]['kind']='repeat_refresh'
            else:bad['anchors'][0]['bytes']='00'+bad['anchors'][0]['bytes'][2:]
            with self.assertRaises(ValueError):probe.check(bad)

    def test_source_fields_and_unchanged_initial_kits(self):
        result=build();items=result['items']
        for key,(code,field,_,_) in probe.FIELDS.items():
            self.assertEqual(items[str(code)]['permanent'],{key:[1,1] if code>=257 else [1,5]})
            self.assertEqual(items[str(code)]['local_attack'],[])
        self.assertEqual(result['initial_inventory']['001'],[int(probe.sources()[0]['001']['item'+str(i)]) for i in range(1,9)])
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
