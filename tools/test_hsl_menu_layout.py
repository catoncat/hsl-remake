import json
import tempfile
import unittest
from pathlib import Path

from hsltools.assets.menu_layout import ROOT, EXE_SHA, points, source_tables
from hsltools.assets.command_frames import definitions


class NativeMenuDataTests(unittest.TestCase):
    def test_supported_counts_are_bounded_and_native_axes_are_not_a_circle(self):
        data = json.loads((ROOT / 'native_layout.json').read_text())
        self.assertEqual(data['exe_sha256'], EXE_SHA)
        self.assertEqual(points(data, 4), [[0, -72], [-66, 0], [0, 72], [66, 0]])
        self.assertEqual(points(data, 2), [[0, -72], [0, 72]])
        self.assertEqual(len(points(data, 7)), 7)
        for invalid in (0, 11, -1):
            with self.assertRaises(ValueError):
                points(data, invalid)

    def test_wrong_executable_is_rejected_before_address_reads(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'wrong.exe'
            path.write_bytes(b'not the supported game')
            with self.assertRaisesRegex(ValueError, 'Unsupported'):
                source_tables(path)

    def test_resource_flags_keep_loop_and_pingpong_distinct(self):
        data = definitions()
        self.assertFalse(data['move']['looped'])
        self.assertTrue(data['status']['looped'])
        self.assertEqual(data['status']['frame_count'], 5)
        self.assertTrue({'use', 'give', 'equip', 'drop'} <= data.keys())


if __name__ == '__main__':
    unittest.main()
