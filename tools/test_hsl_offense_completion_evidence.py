import json
from pathlib import Path
import struct
import sys
import unittest

sys.path.insert(0,str(Path(__file__).resolve().parent))
from hsltools.evidence.offense_completion import ANCHORS, STATES, PACKET, check_mapped, expected_packet


class OffenseCompletionEvidenceTests(unittest.TestCase):
    def test_saved_policy_and_unexecuted_boundary(self):
        packet=json.loads(PACKET.read_text())
        self.assertEqual(packet,expected_packet())
        self.assertFalse(packet['native_execution'])
        self.assertTrue(packet['original_byte_validation_performed'])
        self.assertFalse(packet['completed_action']['requires_prior_movement'])
        self.assertTrue(packet['completed_action']['ordinary_miss'])

    def test_synthetic_byte_and_table_validation(self):
        base=0x400000
        mapped=bytearray(0x60000)
        for address,encoded,_ in ANCHORS:
            data=bytes.fromhex(encoded)
            mapped[address-base:address-base+len(data)]=data
        for slot,(state,entry) in enumerate(STATES.items()):
            mapped[0x445758-base+state]=slot
            struct.pack_into('<I',mapped,0x445694-base+4*slot,entry)
        check_mapped(base,mapped)
        for address in [0x444770,0x44481e,0x44548b]:
            changed=mapped.copy()
            changed[address-base] ^= 1
            with self.assertRaisesRegex(ValueError,'instruction differs'):
                check_mapped(base,changed)
        changed=mapped.copy()
        changed[0x445758-base+84]=2
        with self.assertRaisesRegex(ValueError,'dispatcher differs'):
            check_mapped(base,changed)
