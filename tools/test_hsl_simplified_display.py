"""Ablations of content:simplified_display (the repository itself is checked by that gate): a
removed table entry or an unreviewed character in player text must fail check_strings, a baked-text
image with neither redraw nor kept reason must fail check_images, and the credits redraw
(workteam_simplified) must fail its cell check when 伋 is stamped with its FONT.24 glyph or a
redrawn cell still shows the traditional lettering."""
import hashlib
import json
import shutil
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from hsltools.assets.workteam_simplified import COLOURS, OUTPUT as WORKTEAM_OUTPUT, SOURCE as WORKTEAM_SOURCE, cell_plan, check_cells, redrawn_char
from hsltools.checks.simplified_display import IMAGE_INVENTORY, check_images, check_strings, displayed
from hsltools.data.simplified_chars import OPENCC_TS, OUT as TABLE, opencc_candidates, traditional_only
from hsltools.paths import ROOT


def table() -> dict:
    return json.loads((ROOT / TABLE).read_text(encoding='utf-8'))


# FONT.24 at 伋's Big5 code, rows 6-20 of the 24x24 cell (`PYTHONPATH=tools python3 -m
# hsltools.sources.original_font show 伋`): the 亻 is drawn as a 1-like stroke, which the credits
# showed as garbage in R6-L9b's redraw. Kept here so the ablation needs no original install.
FONT24_JI_ROWS = (
    '.....###...#......##....', '..#####...##########....', '######....#.##....##....',
    '######......##...##.....', '...###......##...#......', '...###......##..#####...',
    '...###......###..####...', '...###.....##.##...##...', '...###.....##..##..##...',
    '...###.....##...####....', '...###....##.....####...', '...###...##....########.',
    '...###.#########..######', '...##.###..........#####', '...##...............###.',
)
FONT24_JI_FIRST_ROW = 6


class SimplifiedDisplayTests(unittest.TestCase):
    def setUp(self) -> None:
        self.trad = traditional_only(opencc_candidates(ROOT))
        self.temp = Path(tempfile.mkdtemp())
        (self.temp / OPENCC_TS).parent.mkdir(parents=True)
        shutil.copy(ROOT / OPENCC_TS, self.temp / OPENCC_TS)
        (self.temp / 'game').mkdir()

    def tearDown(self) -> None:
        shutil.rmtree(self.temp)

    def player_text(self, text: str) -> None:
        (self.temp / 'game' / 'Probe.gd').write_text(f'var shown := "{text}"\n', encoding='utf-8')

    def test_display_matches_the_original_font(self) -> None:
        chars = table()['chars']
        self.assertEqual(displayed('開始新故事', chars), '开始新故事')
        self.assertEqual(displayed('戰亂開始後', chars), '战乱开始後')  # 後 is drawn traditional by FONT.24
        self.assertEqual(displayed('殘餘點數', chars), '残馀点数')  # 餘 is drawn 馀, like the baked WINDOW41

    def test_removed_table_entry_fails(self) -> None:
        ablated = table()
        del ablated['chars']['體']
        issues, _ = check_strings(ROOT, ablated, self.trad)
        self.assertTrue(any(issue.startswith('體 ') for issue in issues), issues[:3])

    def test_unreviewed_traditional_character_fails(self) -> None:
        self.assertNotIn('鬱', table()['chars'])
        self.player_text('鬱金')
        issues, _ = check_strings(self.temp, table(), self.trad)
        self.assertEqual(len(issues), 1)
        self.assertTrue(issues[0].startswith('鬱 '), issues)
        self.player_text('體力')
        self.assertEqual(check_strings(self.temp, table(), self.trad)[0], [])

    def image_root(self, edit) -> Path:
        inventory = json.loads((ROOT / IMAGE_INVENTORY).read_text(encoding='utf-8'))
        for entry in inventory['images']:
            for path in [entry['path']] + ([entry['simplified_replacement']['path']] if 'simplified_replacement' in entry else []):
                (self.temp / path).parent.mkdir(parents=True, exist_ok=True)
                shutil.copy(ROOT / path, self.temp / path)
            edit(entry)
        (self.temp / TABLE).parent.mkdir(parents=True, exist_ok=True)
        shutil.copy(ROOT / TABLE, self.temp / TABLE)
        (self.temp / IMAGE_INVENTORY).parent.mkdir(parents=True, exist_ok=True)
        (self.temp / IMAGE_INVENTORY).write_text(json.dumps(inventory, ensure_ascii=False), encoding='utf-8')
        return self.temp

    def test_traditional_image_without_redraw_fails(self) -> None:
        def drop(entry: dict) -> None:
            entry.pop('simplified_replacement', None)
        issues, _ = check_images(self.image_root(drop))
        self.assertEqual(len(issues), 1)
        self.assertIn('workteam.SHP.png', issues[0])


class WorkteamCellTests(unittest.TestCase):
    """workteam_simplified.check_cells on a copy of the credits redraw with one cell ablated."""

    def setUp(self) -> None:
        self.temp = Path(tempfile.mkdtemp())
        for path in (WORKTEAM_SOURCE, WORKTEAM_OUTPUT, TABLE, OPENCC_TS):
            (self.temp / path).parent.mkdir(parents=True, exist_ok=True)
            shutil.copy(ROOT / path, self.temp / path)
        self.cells = cell_plan(ROOT)

    def tearDown(self) -> None:
        shutil.rmtree(self.temp)

    def cell(self, char: str):
        return next(cell for cell in self.cells if cell.char == char)

    def edit_output(self, edit) -> None:
        from PIL import Image

        with Image.open(self.temp / WORKTEAM_OUTPUT) as image:
            drawn = image.convert('RGBA')
        edit(drawn)
        drawn.save(self.temp / WORKTEAM_OUTPUT)

    def clear(self, image, box) -> None:
        from PIL import Image

        image.paste(Image.new('RGBA', (box[2] - box[0], box[3] - box[1]), (0, 0, 0, 0)), box[:2])

    def stamp_font24_ji(self, image) -> None:
        cell = self.cell('伋')
        self.clear(image, cell.box)
        for gy, row in enumerate(FONT24_JI_ROWS):
            for gx, bit in enumerate(row):
                if bit == '#':
                    image.putpixel((cell.origin[0] + gx, cell.origin[1] + FONT24_JI_FIRST_ROW + gy), COLOURS[cell.colour])

    def issues_starting(self, char: str) -> list[str]:
        cell = self.cell(char)
        return [issue for issue in check_cells(self.temp) if issue.startswith(f'{char} at {cell.box[:2]}')]

    def test_repository_redraw_passes(self) -> None:
        self.assertEqual(check_cells(self.temp), [])
        self.assertEqual({cell.char for cell in self.cells if cell.char in '伋昶漢劉' and cell.redrawn}, {'漢', '劉'})

    def test_ji_with_its_font24_glyph_fails(self) -> None:
        self.edit_output(self.stamp_font24_ji)
        self.assertEqual([issue.split(': ', 1)[1] for issue in self.issues_starting('伋')], ['kept cell differs from the shape\'s lettering'])

    def test_redrawn_cell_with_shape_lettering_fails(self) -> None:
        from PIL import Image

        box = self.cell('漢').box
        with Image.open(ROOT / WORKTEAM_SOURCE) as source:
            lettering = source.convert('RGBA').crop(box)
        self.edit_output(lambda image: image.paste(lettering, box[:2]))
        self.assertEqual([issue.split(': ', 1)[1] for issue in self.issues_starting('漢')],
                         ['redrawn cell still shows the shape\'s traditional lettering'])

    def test_unreadable_traditional_character_fails_the_plan(self) -> None:
        trad = traditional_only(opencc_candidates(ROOT))
        chars = table()
        self.assertTrue(redrawn_char('劉', chars, trad))
        self.assertFalse(redrawn_char('伋', chars, trad))  # both scripts share it: the shape's lettering stays
        self.assertFalse(redrawn_char('後', chars, trad))  # FONT.24 draws it traditional
        with self.assertRaisesRegex(ValueError, 'remake'):
            redrawn_char('職', chars, trad)  # FONT.24 draws 翻 at 職's code
        del chars['chars']['劉']
        with self.assertRaisesRegex(ValueError, 'no FONT.24 reading'):
            redrawn_char('劉', chars, trad)

    def test_check_images_runs_the_cell_check(self) -> None:
        self.edit_output(self.stamp_font24_ji)
        digest = hashlib.sha256((self.temp / WORKTEAM_OUTPUT).read_bytes()).hexdigest()
        inventory = json.loads((ROOT / IMAGE_INVENTORY).read_text(encoding='utf-8'))
        for entry in inventory['images']:
            (self.temp / entry['path']).parent.mkdir(parents=True, exist_ok=True)
            if entry['path'] != WORKTEAM_SOURCE.as_posix():
                shutil.copy(ROOT / entry['path'], self.temp / entry['path'])
            if 'simplified_replacement' in entry:
                entry['simplified_replacement']['sha256'] = digest
        (self.temp / IMAGE_INVENTORY).parent.mkdir(parents=True, exist_ok=True)
        (self.temp / IMAGE_INVENTORY).write_text(json.dumps(inventory, ensure_ascii=False), encoding='utf-8')
        issues, _ = check_images(self.temp)
        self.assertTrue(issues and issues[0].startswith('伋 at (304, 146): kept cell differs'), issues)


if __name__ == '__main__':
    unittest.main()
