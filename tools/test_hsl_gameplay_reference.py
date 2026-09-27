"""Catch broken or misleading source-frame references before they reach agents."""
from copy import deepcopy
import hashlib
import json
from pathlib import Path
import tempfile
import unittest
from PIL import Image
from hsltools.evidence.gameplay_reference import PACKET, check, sha256
from hsltools import original_content


class GameplayReferenceTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        Image.new('RGB', (4, 3)).save(self.root / 'frame.png')
        Image.new('RGB', (4, 3)).save(self.root / 'sheet.jpg')
        self.data = {
            'schema': 'hsl_gameplay_reference.v1',
            'source': {'fps': [30, 1], 'frame_count': 30, 'duration_seconds': 1,
                       'sha256': 'a' * 64, 'recording_size': [4, 3], 'limitations': ['fixture']},
            'assets': [
                {'path': 'frame.png', 'kind': 'video_frame', 'size': [4, 3],
                 'sha256': sha256(self.root / 'frame.png'), 'source_frames': [4],
                 'rgb_md5': hashlib.md5(bytes(36)).hexdigest()},
                {'path': 'sheet.jpg', 'kind': 'contact_sheet', 'size': [4, 3],
                 'sha256': sha256(self.root / 'sheet.jpg')},
            ],
            'categories': [{'id': 'case', 'contact_sheet': 'sheet.jpg', 'retained_frames': ['frame.png'],
                            'contact_tiles': [{'source_frames': [4]}]}],
        }

    @unittest.skipUnless(original_content.present(), 'original-derived content absent (hsltools.original_content)')
    def test_current_packet_is_self_contained(self):
        check(PACKET, json.loads((PACKET / 'manifest.json').read_text()))

    def test_rejects_tampered_media_and_unindexed_desktop_frame(self):
        check(self.root, self.data)
        Image.new('RGB', (4, 3), 'white').save(self.root / 'desktop.png')
        with self.assertRaisesRegex(ValueError, 'Unindexed'):
            check(self.root, self.data)
        (self.root / 'desktop.png').unlink()
        Image.new('RGB', (4, 3), 'white').save(self.root / 'frame.png')
        with self.assertRaisesRegex(ValueError, 'hash mismatch'):
            check(self.root, self.data)

    def test_rejects_invalid_time_and_dangling_category(self):
        for indices in [[30], [-1], [1.5], [], [4, 4]]:
            with self.subTest(indices=indices):
                data = deepcopy(self.data)
                data['assets'][0]['source_frames'] = indices
                with self.assertRaises(ValueError):
                    check(self.root, data)
        data = deepcopy(self.data)
        data['categories'][0]['retained_frames'] = ['absent.png']
        with self.assertRaisesRegex(ValueError, 'missing frame'):
            check(self.root, data)

    def test_rejects_external_asset_path(self):
        for path in ['../outside.png', '/tmp/outside.png']:
            with self.subTest(path=path):
                data = deepcopy(self.data)
                data['assets'][0]['path'] = path
                with self.assertRaisesRegex(ValueError, 'Invalid packet path'):
                    check(self.root, data)
