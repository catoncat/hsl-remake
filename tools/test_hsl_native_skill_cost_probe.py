import copy
import json
from pathlib import Path
import sys
import unittest

sys.path.insert(0,str(Path(__file__).resolve().parent))
from hsltools.probes.skill_cost import ANCHORS, PACKET, canonical_table, check_mapped, check_packet, expected


class SkillResourceEvidenceTests(unittest.TestCase):
    def test_source_normalization_does_not_hide_field_changes(self):
        self.assertEqual(canonical_table(b'expend=1\r\n\r\n'),canonical_table(b'expend=1\n'))
        self.assertNotEqual(canonical_table(b'expend=1\r\n'),canonical_table(b'expend=2\n'))
        self.assertNotEqual(canonical_table(b'expend=1\n\nname=3\n'),canonical_table(b'expend=1\nname=3\n'))

    def test_original_cases_and_small_cost_discrepancy(self):
        packet=json.loads(PACKET.read_text())
        check_packet(packet)
        case=next(c for c in packet['cases'] if c['channel']=='magic' and c['half_mp'] and c['expend']==1 and c['available']==0)
        self.assertEqual(case['affordable'],1)
        self.assertEqual(case['debit_block']['remaining_mp'],-1)
        self.assertEqual(expected(case)['required'],0)

    def test_wrong_scale_charge_or_execution_claim_rejected(self):
        source=json.loads(PACKET.read_text())
        for key,value in [('base_cost',999),('normal_helper_returns',1)]:
            changed=copy.deepcopy(source)
            changed['cases'][0][key]=value
            with self.assertRaises(ValueError): check_packet(changed)
        changed=copy.deepcopy(source)
        changed['cases'][0]['debit_block']['full_spell_function_return']=True
        with self.assertRaisesRegex(ValueError,'block boundary'): check_packet(changed)

    def test_modified_original_instruction_rejected(self):
        base=0x400000
        mapped=bytearray(0x80000)
        for addr,encoded,_ in ANCHORS:
            data=bytes.fromhex(encoded)
            mapped[addr-base:addr-base+len(data)]=data
        check_mapped(base,mapped)
        mapped[0x4099A0-base]^=1
        with self.assertRaisesRegex(ValueError,'anchor differs'): check_mapped(base,mapped)


if __name__=='__main__':
    unittest.main()
