import json
from pathlib import Path
import struct
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parent))
from hsltools.evidence.give import ANCHORS, ROUTES, PACKET, check_mapped, exchange, expected_packet


class GiveEvidenceTests(unittest.TestCase):
    def test_packet_boundary_and_examples(self):
        packet = json.loads(PACKET.read_text())
        self.assertEqual(packet, expected_packet())
        self.assertFalse(packet['native_execution'])
        for case in packet['examples']:
            from collections import Counter
            before = Counter(x for x in case['sender'] + case['receiver'] if x)
            result = case['expected']
            self.assertEqual(before, Counter(x for x in result['sender'] + result['receiver'] if x))
        same = next(c for c in packet['examples'] if c['name'].startswith('same_code'))
        self.assertFalse(same['expected']['action_used'])
        self.assertNotEqual(same['sender'], same['expected']['sender'])

    def test_corrupted_flags_and_dispatch_rejected(self):
        base = 0x400000
        mapped = bytearray(0x80000)
        for address, encoded, _ in ANCHORS:
            value = bytes.fromhex(encoded)
            mapped[address-base:address-base+len(value)] = value
        for slot, (state, entry) in enumerate(ROUTES.items()):
            mapped[0x445758-base+state] = slot
            struct.pack_into('<I', mapped, 0x445694-base+4*slot, entry)
        check_mapped(base, mapped)
        for address in [0x438C97, 0x444DFD, 0x43BA16]:
            altered = mapped.copy()
            altered[address-base] ^= 1
            with self.assertRaisesRegex(ValueError, 'bytes differ'):
                check_mapped(base, altered)
        altered = mapped.copy()
        altered[0x445758-base+116] = 0
        with self.assertRaisesRegex(ValueError, 'dispatcher differs'):
            check_mapped(base, altered)

    def test_invalid_model_inputs_rejected(self):
        bag = [241,0,0,0,0,0,0,0]
        for index in [-1,8]:
            with self.assertRaises(ValueError):
                exchange(bag,index,bag,0)
        with self.assertRaises(ValueError):
            exchange(bag,0,[0],0)
