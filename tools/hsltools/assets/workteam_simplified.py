"""Redraw the end-credits shape workteam.SHP so its traditional-only characters show simplified.

workteam.SHP (640x1440, content/imported/hsl/global/title/previews/workteam.SHP.png) is the one
image a player sees whose baked text is traditional (製作小組, 企畫, the staff names, 劇終): it is
not drawn through the font, so the original font's simplified glyphs never reach it. The remake
shows every other text the way the original font draws it
(docs/evidence_packets/static_reverse/original_font_script/), so this task redraws the credits
from their Big5 transcription (LINES, CLOSING) cell by cell on the shape's own line boxes:

  redrawn  a traditional-only character (OpenCC TSCharacters key) whose FONT.24 glyph
           glyph_review.json reads as a simplified form (content/generated/hsl/text/simplified_chars.json
           `chars`): its cell is cleared and the DATA\\FONT.24 glyph at that Big5 code — the glyph
           the original prints for it — is stamped in the line's ink colour, on the line's
           vertical centre and horizontally centred on the shape's letter in that cell (so the
           gaps beside kept cells stay the shape's). The closing 劇終 is
           42 px tall in the shape; it is drawn with the FONT.24 glyph doubled (48 px cell).
  kept     every other cell (the characters both scripts share, the half-width 2D／3D, and the
           characters FONT.24 itself draws traditional) keeps the shape's lettering pixel for
           pixel. FONT.24 is not used there: it would only swap the typeface, and some of its
           glyphs are unusable (昶 is blank; 伋's 亻 is drawn as a 1-like stroke and read as
           garbage in the credits).

A traditional-only character without a FONT.24 reading, one whose FONT.24 glyph is a remake
exception (remake_choices: slot swap, unresolved, …) or one whose glyph is blank fails the build
instead of keeping traditional lettering. check_cells proves the output against this plan without
the original install: kept cells and everything outside the redrawn cells equal the shape, every
redrawn cell has ink in the shape's colours and differs from the shape.

The redrawn cells change the letter shapes to the game font (remake-invented); the layout (lines,
columns, colours) is the shape's. The original PNG stays in place and unchanged; GameClearScreen
shows the replacement through content/generated/hsl/text/simplified_images.json.

Registry task workteam_simplified (family assets): outputs
content/generated/hsl/title/workteam_simplified.png and content/generated/hsl/text/simplified_images.json;
check needs no original install (pixel hash against image_inventory.json: the PNG a player's Pillow writes has
other bytes, hsltools.sources.shp.png_sha256), generate reads the PAK.
"""
from __future__ import annotations

import json
from pathlib import Path
from typing import NamedTuple

from hsltools.data.simplified_chars import OPENCC_TS, opencc_candidates, traditional_only
from hsltools.registry import Context, ScriptCheckTask, original_archive
from hsltools.sources.original_font import FONTS, glyph_rows, read_font
from hsltools.sources.shp import png_sha256

SOURCE = Path('content/imported/hsl/global/title/previews/workteam.SHP.png')
OUTPUT = Path('content/generated/hsl/title/workteam_simplified.png')
IMAGE_TABLE = Path('content/generated/hsl/text/simplified_images.json')
CHAR_TABLE = Path('content/generated/hsl/text/simplified_chars.json')
INVENTORY = Path('docs/evidence_packets/static_reverse/original_font_script/image_inventory.json')
COLOURS = {'g': (123, 255, 65, 255), 'w': (255, 255, 255, 255)}  # the shape's two ink colours
FULL_PITCH = 24
HALF_PITCH = 12
# (ink top, ink bottom, colour, first column x, Big5 text): each line's ink rows and first
# column measured on workteam.SHP; columns are a 24 px grid (full-width spaces keep the gaps).
LINES = (
    (64, 84, 'g', 245, '製作小組'),
    (122, 142, 'g', 64, '企畫'),
    (146, 166, 'w', 136, '鄧彥志　　林汝伋'),
    (194, 214, 'g', 64, '2D美術'),
    (218, 238, 'w', 136, '鄧彥志　　陳彥名'),
    (266, 286, 'g', 64, '3D模型'),
    (290, 310, 'w', 136, '陳彥名　　楊漢昶　　鄧彥志'),
    (338, 358, 'g', 64, '主程式'),
    (362, 382, 'w', 136, '林汝伋'),
    (411, 431, 'g', 64, '工具程式'),
    (434, 454, 'w', 136, '林汝伋'),
    (482, 502, 'g', 64, '遊戲引擎'),
    (506, 526, 'w', 136, '林汝伋　　居則文'),
    (554, 574, 'g', 64, '動畫'),
    (578, 598, 'w', 136, '陳彥名'),
    (626, 646, 'g', 64, '音樂'),
    (650, 670, 'w', 136, '許泰滄'),
    (698, 718, 'g', 64, '音效'),
    (722, 742, 'w', 136, '奧汀科技'),
    (771, 790, 'g', 64, '測試'),
    (794, 815, 'w', 136, '華大衛　　黃博聖　　施懷宇　　吳致松'),
    (818, 839, 'w', 136, '鄭淑芬　　王浩辰　　林逸青　　賴柏州'),
    (842, 863, 'w', 136, '張啟新　　居則文　　王奉平　　劉　信'),
    (866, 887, 'w', 136, '楊漢昶　　江　霖　　廖荷婷'),
)
# 劇終: (glyph, ink centre x, ink centre y) of the two 42 px characters.
CLOSING = (('劇', 271, 1188), ('終', 388, 1188))
CLOSING_SCALE = 2


def _distinct(chars) -> str:
    return ''.join(dict.fromkeys(chars))


class Cell(NamedTuple):
    char: str
    box: tuple[int, int, int, int]  # left, top, right, bottom (exclusive): the pixels the cell owns
    origin: tuple[int, int]  # top-left of the stamped FONT.24 cell
    colour: str
    scale: int
    redrawn: bool


def redrawn_char(char: str, table: dict, traditional: set[str]) -> bool:
    """Whether the credits show `char` through its FONT.24 glyph (see the module docstring)."""
    if char not in traditional or char in table['kept_traditional']:
        return False
    if char in table['remake_choices']:
        raise ValueError(f'{char}: FONT.24 does not draw the form the remake shows ({table["remake_choices"][char]["reason"]})')
    if char not in table['chars']:
        raise ValueError(f'{char}: traditional-only with no FONT.24 reading; add it to glyph_review.json '
                         '(PYTHONPATH=tools python3 -m hsltools.sources.original_font show X) and hsl generate simplified_chars')
    return True


def cell_plan(root: Path) -> list[Cell]:
    table = json.loads((root / CHAR_TABLE).read_text(encoding='utf-8'))
    traditional = traditional_only(opencc_candidates(root))
    cells: list[Cell] = []
    for top, bottom, colour, left, text in LINES:
        cell_top = (top + bottom + 1) // 2 - FONTS['FONT.24'][1] // 2
        x = left
        for char in text:
            pitch = HALF_PITCH if ord(char) < 0x80 else FULL_PITCH
            if char != '\u3000':
                cells.append(Cell(char, (x, top, x + pitch, bottom + 1), (x, cell_top), colour, 1, redrawn_char(char, table, traditional)))
            x += pitch
    size = FONTS['FONT.24'][0] * CLOSING_SCALE
    for char, centre_x, centre_y in CLOSING:
        left, top = centre_x - size // 2, centre_y - size // 2
        cells.append(Cell(char, (left, top, left + size, top + size), (left, top), 'g', CLOSING_SCALE, redrawn_char(char, table, traditional)))
    return cells


def _centring_shift(lettering, rows: list[str], scale: int) -> int:
    """Pixels to move the stamped glyph right so its ink is centred on the shape's lettering in the
    cell (kept inside the cell): FONT.24 inks columns 1-23 of its cell, the shape's letters sit at columns 0-21, so
    stamping at the cell origin leaves a redrawn letter touching its right neighbour and a wide
    gap on its left (華大衛 read as 华大 卫 beside the kept 大)."""
    columns = [column for column in range(len(rows[0])) if any(row[column] == '#' for row in rows)]
    shape_left, _, shape_right, _ = lettering.getbbox()
    shift = (shape_left + shape_right - (columns[0] + columns[-1] + 1) * scale) // 2
    return max(-columns[0] * scale, min(shift, lettering.width - (columns[-1] + 1) * scale))


def render(font24: bytes, root: Path):
    """The shape with every redrawn cell cleared and its FONT.24 glyph stamped; kept cells untouched."""
    from PIL import Image

    with Image.open(root / SOURCE) as source:
        image = source.convert('RGBA')
    pixels = image.load()
    for cell in cell_plan(root):
        if not cell.redrawn:
            continue
        rows = glyph_rows(font24, 'FONT.24', cell.char)
        if '#' not in ''.join(rows):
            raise ValueError(f'{cell.char}: blank FONT.24 glyph for a traditional-only character')
        left, top, right, bottom = cell.box
        shift = _centring_shift(image.crop(cell.box), rows, cell.scale)
        for y in range(top, bottom):
            for x in range(left, right):
                pixels[x, y] = (0, 0, 0, 0)
        for gy, row in enumerate(rows):
            for gx, bit in enumerate(row):
                if bit != '#':
                    continue
                for dy in range(cell.scale):
                    for dx in range(cell.scale):
                        x, y = cell.origin[0] + shift + gx * cell.scale + dx, cell.origin[1] + gy * cell.scale + dy
                        if not (left <= x < right and top <= y < bottom):
                            raise ValueError(f'{cell.char}: FONT.24 ink at ({x}, {y}) falls outside its cell {cell.box}')
                        pixels[x, y] = COLOURS[cell.colour]
    return image


def check_cells(root: Path, output: Path = OUTPUT) -> list[str]:
    """The output against cell_plan: kept cells and all pixels outside redrawn cells equal the
    shape; each redrawn cell has ink only in the shape's colours and differs from the shape."""
    from PIL import Image

    with Image.open(root / output) as image, Image.open(root / SOURCE) as source:
        drawn, shape = image.convert('RGBA'), source.convert('RGBA')
    if drawn.size != shape.size:
        return [f'{output} is {drawn.size}, the shape is {shape.size}']
    issues: list[str] = []
    ink = set(COLOURS.values())
    outside_drawn, outside_shape = drawn.copy(), shape.copy()
    for cell in cell_plan(root):
        ours, theirs = drawn.crop(cell.box), shape.crop(cell.box)
        where = f'{cell.char} at {cell.box[:2]}'
        if not theirs.getbbox():
            issues.append(f'{where}: the shape has no lettering in this cell (LINES grid off?)')
        if not cell.redrawn:
            if ours.tobytes() != theirs.tobytes():
                issues.append(f'{where}: kept cell differs from the shape\'s lettering')
            continue
        colours = {pixel for _, pixel in ours.getcolors(ours.width * ours.height) if pixel[3]}
        if not colours:
            issues.append(f'{where}: redrawn cell is blank')
        elif not colours <= ink:
            issues.append(f'{where}: redrawn cell has colours outside the shape ink {sorted(colours - ink)[:4]}')
        elif ours.tobytes() == theirs.tobytes():
            issues.append(f'{where}: redrawn cell still shows the shape\'s traditional lettering')
        blank = Image.new('RGBA', ours.size, (0, 0, 0, 0))
        outside_drawn.paste(blank, cell.box[:2])
        outside_shape.paste(blank, cell.box[:2])
    if outside_drawn.tobytes() != outside_shape.tobytes():
        issues.append(f'{output}: pixels outside the redrawn cells differ from the shape')
    return issues


def image_table() -> dict:
    return {
        'schema': 'hsl_simplified_images.v1',
        'evidence_tier': 'provisional',
        'claim': 'Images whose baked traditional text the remake shows redrawn with the original font\'s simplified glyphs; '
                 'the display seam loads the replacement instead of the original shape (the original PNG is unchanged).',
        'inventory': INVENTORY.as_posix(),
        'images': {'res://' + SOURCE.as_posix(): 'res://' + OUTPUT.as_posix()},
    }


def build(pak: Path, root: Path) -> None:
    from PIL import Image

    image = render(read_font('FONT.24', pak), root)
    target = root / OUTPUT
    target.parent.mkdir(parents=True, exist_ok=True)
    keep = False
    if target.is_file():
        with Image.open(target) as tracked:
            keep = tracked.size == image.size and tracked.convert('RGBA').tobytes() == image.tobytes()
    if not keep:
        image.save(target)
    table = root / IMAGE_TABLE
    table.parent.mkdir(parents=True, exist_ok=True)
    table.write_text(json.dumps(image_table(), ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    cells = cell_plan(root)
    inventory_path = root / INVENTORY
    inventory = json.loads(inventory_path.read_text(encoding='utf-8'))
    for entry in inventory['images']:
        if entry['path'] == SOURCE.as_posix():
            entry['simplified_replacement'] = {'path': OUTPUT.as_posix(), 'rgba_sha256': png_sha256(target),
                                               'generator': 'tools/hsltools/assets/workteam_simplified.py',
                                               'redrawn_with_font24': _distinct(cell.char for cell in cells if cell.redrawn),
                                               'shape_lettering_kept_for': _distinct(cell.char for cell in cells if not cell.redrawn)}
    inventory_path.write_text(json.dumps(inventory, ensure_ascii=False, indent=1) + '\n', encoding='utf-8')


def verify(root: Path) -> None:
    table = json.loads((root / IMAGE_TABLE).read_text(encoding='utf-8'))
    assert table == image_table(), f'{IMAGE_TABLE} differs from the generator (python3 tools/hsl.py generate workteam_simplified)'
    entry = next(e for e in json.loads((root / INVENTORY).read_text(encoding='utf-8'))['images'] if e['path'] == SOURCE.as_posix())
    replacement = entry.get('simplified_replacement', {})
    assert replacement.get('path') == OUTPUT.as_posix(), f'{INVENTORY} records no simplified_replacement for {SOURCE}'
    assert png_sha256(root / OUTPUT) == replacement['rgba_sha256'], f'{OUTPUT} pixel hash differs from {INVENTORY}'
    issues = check_cells(root)
    assert not issues, f'{len(issues)} credits cell problem(s):\n  ' + '\n  '.join(issues)
    cells = cell_plan(root)
    redrawn = sum(cell.redrawn for cell in cells)
    print(f'WORKTEAM_SIMPLIFIED_PASS lines={len(LINES)} closing={len(CLOSING)} cells={len(cells)} redrawn={redrawn} kept={len(cells) - redrawn}')


class WorkteamSimplifiedTask(ScriptCheckTask):
    name = 'workteam_simplified'
    family = 'assets'
    inputs = (SOURCE.as_posix(), INVENTORY.as_posix(), CHAR_TABLE.as_posix(), OPENCC_TS.as_posix())
    outputs = (OUTPUT.as_posix(), IMAGE_TABLE.as_posix())
    scripts = ('tools/hsltools/assets/workteam_simplified.py', 'tools/hsltools/sources/original_font.py',
               'tools/hsltools/data/simplified_chars.py')

    def verify(self, ctx: Context) -> None:
        verify(ctx.root)

    def build(self, ctx: Context) -> None:
        build(original_archive(ctx), ctx.root)


def tasks() -> list[WorkteamSimplifiedTask]:
    return [WorkteamSimplifiedTask()]
