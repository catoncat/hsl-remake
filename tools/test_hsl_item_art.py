import json
from pathlib import Path
import shutil
import tempfile
import unittest
from unittest.mock import patch

from hsltools.assets import item_art


class ItemArtTests(unittest.TestCase):
    def test_original_category_bindings(self):
        self.assertEqual(item_art.bindings(), {'241': 'itemIconUse', '246': 'itemIconUse'})

    def test_current_art(self):
        item_art.check()

    def test_corrupt_asset_is_rejected(self):
        data = json.loads((item_art.ROOT / 'manifest.json').read_text())
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            for key, asset in data['assets'].items():
                target = root / (key + '.png')
                shutil.copyfile(Path(asset['res_path'].removeprefix('res://')), target)
                asset['res_path'] = 'res://' + target.as_posix()
            (root / 'manifest.json').write_text(json.dumps(data))
            (root / 'consumable.png').write_bytes(b'corrupt')
            with patch.object(item_art, 'ROOT', root), self.assertRaises(AssertionError):
                item_art.check()

    def test_wrong_category_is_rejected(self):
        data = json.loads((item_art.ROOT / 'manifest.json').read_text())
        data['item_categories']['241'] = 'itemIconSword'
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / 'manifest.json').write_text(json.dumps(data))
            with patch.object(item_art, 'ROOT', root), self.assertRaises(AssertionError):
                item_art.check()


if __name__ == '__main__':
    unittest.main()
