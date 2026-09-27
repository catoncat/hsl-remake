import json
from pathlib import Path
import struct
import sys
import unittest

sys.path.insert(0,str(Path(__file__).resolve().parent))
from hsltools.evidence.action_state import (
    COMMANDS,
    PHASES,
    SUBSTATES,
    MOVE_SUBSTATES,
    FINISH_SUBSTATES,
    ANCHORS,
    PACKET,
    check_mapped,
    check_objects,
    expected_packet)


class ActionStateEvidenceTests(unittest.TestCase):
    def test_packet_preserves_verification_boundary(self):
        packet = json.loads(PACKET.read_text())
        self.assertEqual(packet,expected_packet())
        self.assertFalse(packet['verification']['native_execution'])
        self.assertTrue(packet['verification']['trace_instruction_bytes_checked'])
        self.assertEqual(packet['commands']['wait']['destination'],'0x4454a5')
        self.assertEqual(packet['outer_phases']['21'],'0x4440d1')

    def test_dispatch_confusion_is_rejected(self):
        base = 0x400000
        mapped = bytearray(0x60000)
        for address, encoded, _ in ANCHORS:
            data = bytes.fromhex(encoded)
            mapped[address-base:address-base+len(data)] = data
        states = {**{s:e for _,s,e in COMMANDS.values()},**SUBSTATES}
        for i,(state,entry) in enumerate(states.items()):
            mapped[0x445758-base+state] = i
            struct.pack_into('<I',mapped,0x445694-base+4*i,entry)
        for i,(phase,entry) in enumerate(PHASES.items()):
            mapped[0x44567c-base+phase] = i
            struct.pack_into('<I',mapped,0x445668-base+4*i,entry)
        struct.pack_into('<12I',mapped,0x445820-base,*MOVE_SUBSTATES)
        struct.pack_into('<9I',mapped,0x4457FC-base,*FINISH_SUBSTATES)
        check_mapped(base,mapped)
        for address in [0x445758+4,0x44567c+21,0x445820+9*4]:
            wrong = mapped.copy()
            wrong[address-base] ^= 1
            with self.assertRaisesRegex(ValueError,'dispatch differs'):
                check_mapped(base,wrong)
        for address in [0x4442D6,0x443C1A,0x443C38]:
            wrong = mapped.copy()
            wrong[address-base] ^= 1
            with self.assertRaisesRegex(ValueError,'instruction differs'):
                check_mapped(base,wrong)

    def test_wait_is_data8_four_not_object_code(self):
        rows = {code:{'obj_Process_Code':'defProcBattleCommandString','obj_Data8':state}
                for code,state,_ in COMMANDS.values()}
        check_objects(rows)
        rows[113]['obj_Data8'] = 113
        with self.assertRaisesRegex(ValueError,'Data8 differs: wait'):
            check_objects(rows)
