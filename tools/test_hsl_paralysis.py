import copy
import json
from pathlib import Path
import sys
import unittest

sys.path.insert(0,str(Path(__file__).resolve().parent))
import hsltools.probes.paralysis as probe
from hsltools.data.skill_book import build as skill_book
from hsltools.data.equipment import build as equipment
from hsltools.data.consumables import build as consumables
from hsltools.assets.paralysis_assets import definitions, OUT
from hsltools.data.support_magic import check as assets_check


class ParalysisEvidenceTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.packet = json.loads(probe.PACKET.read_text())

    def test_original_boundaries_and_tamper_rejection(self):
        probe.check(self.packet)
        for kind in ['entry', 'application', 'return', 'bytes', 'draw']:
            broken = copy.deepcopy(self.packet)
            if kind == 'entry': broken['entries'][0]['native']['phase'] += 1
            elif kind == 'application': broken['applications'][0]['native']['contribution'] += 1
            elif kind == 'return': broken['applications'][0]['normal_return'] = True
            elif kind == 'bytes': broken['anchors'][0]['bytes'] = '00' + broken['anchors'][0]['bytes'][2:]
            else: next(r for r in broken['applications'] if r['draws'])['draws'][0]['bound'] = 1
            with self.assertRaises(ValueError): probe.check(broken)

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
        self.assertFalse(items['71']['supported'])
        medicine = consumables()
        self.assertEqual(medicine['items']['248']['cure_paralysis'], 1)
        self.assertEqual(medicine['items']['248']['heal_hp'], 0)
        self.assertNotIn(248, medicine['initial_inventory']['001'])
        # R27: 251 聖潔香水 registers once every cure bit it carries has a contract (cure_weaken);
        # registering it grants no initial inventory.
        self.assertEqual(medicine['items']['251']['cure_weaken'], 1)
        self.assertFalse(any(251 in slots for slots in medicine['initial_inventory'].values()))

    def test_original_local_effect_resources(self):
        assets_check(definitions(), OUT)
        manifest = json.loads((OUT/'manifest.json').read_text())
        self.assertEqual(len(manifest['images']),8)
        self.assertEqual(set(manifest['sounds']), {'WAV\\UPGROUND01.WAV','WAV\\BOMB0006.WAV'})
