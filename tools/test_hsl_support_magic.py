import copy
import json
from pathlib import Path
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parent))
from hsltools.probes.support import PACKET, check
from hsltools.data.skill_book import build as skill_book
from hsltools.data.skill_targeting import build as targets
from hsltools.data.support_magic import check as check_assets


class SupportMagicTests(unittest.TestCase):
    def test_original_returns_and_bounded_applications(self):
        data=json.loads(PACKET.read_text())
        check(data)
        self.assertEqual((len(data['rolls']), len(data['applications'])), (18,24))
        for first, second in zip(data['rolls'][::2], data['rolls'][1::2]):
            self.assertEqual(first['native'],second['native'])
            self.assertEqual(first['draws'],second['draws'])
        for kind in ['hp', 'no_magic', 'poison', 'status_flags', 'contribution']:
            changed=copy.deepcopy(data)
            changed['applications'][-1]['native'][kind]+=1
            with self.subTest(kind=kind), self.assertRaises(ValueError): check(changed)

    def test_missing_coverage_unbounded_claims_and_invented_rng_are_rejected(self):
        data=json.loads(PACKET.read_text())
        for field,value in [('normal_return',True),('stop_address','0x40b832'),('instructions',4096),('draws',[{'bound':100,'value':0}])]:
            changed=copy.deepcopy(data)
            changed['applications'][-1][field]=value
            with self.subTest(field=field), self.assertRaises(ValueError): check(changed)
        changed=copy.deepcopy(data)
        changed['rolls'].pop()
        with self.assertRaises(ValueError): check(changed)
        changed=copy.deepcopy(data)
        changed['rolls'][0]['draws'][0]['value']=100
        with self.assertRaises(ValueError): check(changed)
        changed=copy.deepcopy(data)
        changed['native_execution']=False
        with self.assertRaises(ValueError): check(changed)

    def test_registered_sources_have_complete_ranges_and_original_media(self):
        book=skill_book()
        ranges=targets()['ranges']
        for entry in book['skills'].values():
            for key in ['range','effect_range']: self.assertIn(entry['fields'][key],ranges)
        self.assertFalse(any('magicWATER' in skill for skill in book['actors']['001']['supported_initial_ids']))
        self.assertIn('magic:magicWATER:magicCode06',book['actors']['027']['supported_initial_ids'])
        check_assets()


if __name__=='__main__': unittest.main()
