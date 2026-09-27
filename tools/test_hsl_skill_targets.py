import copy
import json
from pathlib import Path
import sys
import unittest

sys.path.insert(0,str(Path(__file__).resolve().parent))
from hsltools.probes.skill_target import ANCHORS, PACKET, check_mapped, check_packet
from hsltools.data.skill_targeting import OUT, build, function_bits, function_mask, range_pattern


class SkillTargetTests(unittest.TestCase):
    def test_source_range_masks_are_not_invented_radii(self):
        self.assertEqual(json.loads(OUT.read_text()),build())
        cross=range_pattern('range2Cell')['data']
        self.assertEqual(cross[1][1],0)
        self.assertGreater(cross[2][0],0)
        self.assertGreater(range_pattern('range3CellCircle')['data'][2][1],0)

    def test_function_symbols_fail_closed(self):
        bits=function_bits()
        self.assertEqual(function_mask('magicFun_Attack, magicFun_Poison',bits),9)
        for expression in ['', 'magicFun_Missing','1','magicFun_Attack,']:
            with self.assertRaisesRegex(ValueError,'Unknown or missing'):
                function_mask(expression,bits)

    def test_original_coverage_and_mode_boundaries(self):
        packet=json.loads(PACKET.read_text())
        check_packet(packet)
        self.assertEqual(packet['source_function_modes']['magicFun_HealMP'],{'magic':2,'special':3})
        self.assertEqual(packet['source_function_modes']['magicFun_ActiveAgain'],{'magic':2,'special':3})
        for field,value in [('coverage',9),('normal_returns',1),('next_target',1),('actor_and_map_unchanged',False)]:
            changed=copy.deepcopy(packet)
            changed['cases'][0][field]=value
            with self.assertRaisesRegex(ValueError,'Target result/return'):
                check_packet(changed)

    def test_altered_function_mask_or_target_append_rejected(self):
        base=0x400000
        mapped=bytearray(0x80000)
        for address,encoded,_ in ANCHORS:
            data=bytes.fromhex(encoded)
            mapped[address-base:address-base+len(data)]=data
        check_mapped(base,mapped)
        for address in [0x444E9F,0x44504B,0x410585]:
            changed=mapped.copy()
            changed[address-base]^=1
            with self.assertRaisesRegex(ValueError,'instruction differs'):
                check_mapped(base,changed)


if __name__=='__main__': unittest.main()
