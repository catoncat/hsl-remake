import copy
import json
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from hsltools.evidence.inventory_equipment import ANCHORS, PACKET, check_mapped, check_packet


class InventoryEvidenceTests(unittest.TestCase):
    def test_reviewed_packet_and_static_boundary(self):
        packet = json.loads(PACKET.read_text())
        check_packet(packet)
        changed = copy.deepcopy(packet)
        changed['verification_boundary']['new_native_execution'] = True
        with self.assertRaisesRegex(ValueError, 'native execution'):
            check_packet(changed)

    def test_modified_instruction_is_rejected(self):
        base = min(address for address, _, _ in ANCHORS)
        end = max(address + len(bytes.fromhex(encoded)) for address, encoded, _ in ANCHORS)
        mapped = bytearray(end - base)
        for address, encoded, _ in ANCHORS:
            data = bytes.fromhex(encoded)
            mapped[address-base:address-base+len(data)] = data
        check_mapped(base, mapped)
        mapped[0x436E5D - base] ^= 1  # Change the proven eight-slot loop bound.
        with self.assertRaisesRegex(ValueError, 'bytes differ'):
            check_mapped(base, mapped)

    def test_missing_bytes_and_conflicting_layout_are_rejected(self):
        with self.assertRaisesRegex(ValueError, 'outside image'):
            check_mapped(0, b'')
        packet = json.loads(PACKET.read_text())
        packet['layout']['inventory_capacity'] = 9
        with self.assertRaisesRegex(ValueError, 'layout contradicts'):
            check_packet(packet)


if __name__ == '__main__':
    unittest.main()
