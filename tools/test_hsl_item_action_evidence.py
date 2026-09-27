import copy
import json
import struct
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from hsltools.evidence.item_action import (
    ANCHORS,
    OBJECTS,
    PACKET,
    ROUTES,
    PARENT_RETURNS,
    check_mapped,
    check_objects,
    expected_packet)


class ItemActionEvidenceTests(unittest.TestCase):
    def test_saved_packet_and_command_routes(self):
        packet = json.loads(PACKET.read_text())
        self.assertEqual(packet, expected_packet())
        self.assertFalse(packet['native_execution'])
        self.assertEqual(packet['command_routes']['equip']['state'], 7)
        self.assertEqual(packet['command_routes']['drop']['state'], 8)
        self.assertEqual(packet['window_close']['parent_returns']['window_closed']['state'], 77)

    def test_menu_order_cannot_replace_object_data8(self):
        source = json.loads(OBJECTS.read_text())
        source['commands'] = dict(reversed(list(source['commands'].items())))
        check_objects(source)  # JSON/menu order does not change the command states.
        bad = copy.deepcopy(source)
        bad['commands']['equip']['command_id'] = 8
        with self.assertRaisesRegex(ValueError, 'Data8/state mismatch: equip'):
            check_objects(bad)

    def test_native_dispatch_and_important_guard_tampering(self):
        base = 0x400000
        mapped = bytearray(0x80000)
        for address, encoded, _ in ANCHORS:
            value = bytes.fromhex(encoded)
            mapped[address-base:address-base+len(value)] = value
        for index, route in enumerate({**ROUTES, **PARENT_RETURNS}.values()):
            mapped[0x445758-base+route['state']] = index
            struct.pack_into('<I', mapped, 0x445694-base+4*index, int(route['entry'], 16))
        check_mapped(base, mapped)
        redirected = mapped.copy()
        redirected[0x445758-base+7] = 3  # Route Equip to the Drop entry.
        with self.assertRaisesRegex(ValueError, 'dispatch differs: equip'):
            check_mapped(base, redirected)
        altered = mapped.copy()
        altered[0x40E6AF-base] ^= 1  # Change the important-item mask in the predicate.
        with self.assertRaisesRegex(ValueError, 'bytes differ'):
            check_mapped(base, altered)
        changed_parent = mapped.copy()
        changed_parent[0x445758-base+77] = 3
        with self.assertRaisesRegex(ValueError, 'dispatch differs: window_closed'):
            check_mapped(base, changed_parent)
        changed_full_bag = mapped.copy()
        changed_full_bag[0x438873-base] ^= 1
        with self.assertRaisesRegex(ValueError, 'bytes differ at 0x438868'):
            check_mapped(base, changed_full_bag)


if __name__ == '__main__':
    unittest.main()
