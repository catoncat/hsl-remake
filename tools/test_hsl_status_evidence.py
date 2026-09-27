import json
from pathlib import Path
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parent))
from hsltools.evidence.status import TABLES, PACKET, expected_packet, source_join


class StatusEvidenceTests(unittest.TestCase):
    def test_source_join_and_explicit_execution_boundary(self):
        packet = json.loads(PACKET.read_text())
        self.assertEqual(packet, expected_packet())
        self.assertFalse(packet['verification']['native_execution'])
        self.assertFalse(packet['verification']['new_exe_byte_check'])
        self.assertEqual(packet['states']['paralysis']['actor_flag'], 4)

    def test_changed_function_polarity_is_rejected(self):
        sources = {name: (TABLES / name).read_bytes() for name in ['TYPE.H', 'ITEM.TXT', 'PLAYERS.TXT']}
        sources['TYPE.H'] = sources['TYPE.H'].replace(b'magicFun_NoMagic        0x00000010', b'magicFun_NoMagic        0x00000002')
        with self.assertRaisesRegex(ValueError, 'definition differs'):
            source_join(sources)

    def test_missing_initial_status_is_not_assumed_healthy(self):
        sources = {name: (TABLES / name).read_bytes() for name in ['TYPE.H', 'ITEM.TXT', 'PLAYERS.TXT']}
        import re
        sources['PLAYERS.TXT'] = re.sub(rb'(?m)^status\s*=\s*0', b'status = 2', sources['PLAYERS.TXT'], count=1)
        with self.assertRaisesRegex(ValueError, 'needs counter evidence'):
            source_join(sources)


if __name__ == '__main__':
    unittest.main()
