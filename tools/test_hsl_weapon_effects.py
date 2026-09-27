import copy
import json
from pathlib import Path
import sys
import unittest

sys.path.insert(0,str(Path(__file__).resolve().parent))
import hsltools.probes.weapon_effect as probe
from hsltools.data.equipment import build
from hsltools.assets.interface_audio import weapon_hits


class WeaponEffectsTests(unittest.TestCase):
    def test_native_helpers_and_caller_boundaries(self):
        packet=json.loads(probe.PACKET.read_text())
        probe.check(packet)
        self.assertTrue(any(r['native']['cancelled_index']>=0 for r in packet['effects']))
        self.assertTrue(any(r['native']['poison']!=r['input']['poison'] for r in packet['effects']))
        for row in packet['caller']:
            case=row['input']
            self.assertEqual(row['native']['effect_called'],bool(case['contribution'] and (not case['remaining'] or not case['hp'])))

    def test_native_evidence_rejects_tampering(self):
        original=json.loads(probe.PACKET.read_text())
        for field in ['queue','poison','gear_hp','bytes','boundary','rng']:
            packet=copy.deepcopy(original)
            if field=='queue':packet['queue'][0]['native']['cancelled_index']=100
            elif field=='poison':packet['effects'][0]['native']['poison']=123
            elif field=='gear_hp':packet['gear'][0]['native'][0]['values']['hp']=2
            elif field=='bytes':packet['anchors'][0]['bytes']='00'+packet['anchors'][0]['bytes'][2:]
            elif field=='boundary':packet['caller'][0]['stop_address']='0x442487'
            else:packet['effects'][1]['draws'][0]['bound']=99
            with self.subTest(field=field),self.assertRaises(ValueError):probe.check(packet)

    def test_source_effects_and_real_job_eligibility(self):
        items=build()['items']
        for code,flags in [('29',probe.CANCEL),('35',probe.POISON),('37',probe.POISON)]:
            self.assertTrue(items[code]['supported'])
            self.assertEqual(items[code]['weapon_effect_flags'],flags)
            self.assertTrue(items[code]['job_mask']&(1<<(94-80)))
            self.assertFalse(items[code]['job_mask']&1)
        self.assertEqual(items['144']['job_mask'],7)
        for code in ['144','229']:
            self.assertTrue(items[code]['supported'])
            self.assertEqual(items[code]['status_effect_flags']&0x80,0x80)
        self.assertTrue(items['108']['supported'])  # Independently proved mana-strike follow-up.
        self.assertEqual(items['108']['weapon_effect_flags'],0x400000)
        # R27: 209 詛咒戒指's random_status_error now has the 0x409310 contract (weapon_effect_flags 0x40000).
        self.assertTrue(items['209']['supported'])
        self.assertEqual(items['209']['weapon_effect_flags'],0x40000)
        self.assertEqual(items['51']['weapon_effect_flags'],0x20000)
        self.assertEqual(items['66']['weapon_effect_flags'],0x80000)
        self.assertFalse(items['302']['supported'],'unproven adjacent effects stay rejected')

    def test_empty_sting_is_real_not_fallback_art_or_sound(self):
        manifest=json.loads(Path('content/imported/hsl/shared/panels/manifest.json').read_text())
        sting=manifest['assets']['itemIconSting']
        self.assertTrue(sting['empty'])
        self.assertEqual(sting['source_bytes'],manifest['assets']['itemIconClaw']['source_bytes'])
        self.assertEqual(sting['res_path'],'')
        self.assertEqual([weapon_hits()[code] for code in ['35','37']],['',''])
