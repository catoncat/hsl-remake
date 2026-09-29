"""The original bitmap fonts as glyph atlases the remake draws every interface text with.

hsl01.exe draws all of its text with two bitmap font pairs (static-derived, hsl01.exe):

  0x42f230  loads DATA\\FONT.15 + ASCFONT.15 through the loader 0x460ace with full glyphs 16x15,
            half glyphs 8x15 and a half-glyph drop of 2 px (the loader's eighth argument, kept at
            font +0x14); 0x42f308 loads DATA\\FONT.24 + ASCFONT.24 with full 24x24, half 12x24,
            drop 0.
  0x4608e4  the draw loop: a byte >= 0xa1 starts a two-byte Big5 code drawn from the full font at
            the pen, which then moves by the full width (+0x0c); any other byte is one half glyph
            from the ASC font drawn `drop` px lower, the pen moving by the half width (+0x10); a
            space is not drawn but still advances. The per-call extra gap ([ebp+0x24]) is 0 at
            every one of the 66 call sites whose pushes resolve (four pass a register).
  callers   draw every string twice: once at (+1, +1) in the shadow colour, then in the text
            colour (e.g. the message renderer 0x411e11 / 0x411e58).

This task decodes the four members of hsl.pak into two atlases and one glyph table, keeping only
the characters the remake can show (`used_chars`: every string of the runtime content —
content/imported, content/battles, content/authored and content/generated JSON, the Big5 tables
of content/imported, the string literals of game/**/*.gd and *.tscn — in its display-seam form):

  FONT24.png / FONT15.png   white ink on transparent: the used full glyphs in `chars` order on a
                            FULL_COLUMNS-wide grid, then half glyphs 0x00-0x7f on one row below.
  original_fonts.json       per font the cell sizes, drop and atlas sha256; `chars` (atlas order)
                            with `slots` (the original full-glyph slot each was read from): the
                            Big5 slot of the character (cp950), overridden by the display seam's
                            slot (resource-derived: 体 is drawn at the 體 slot, 职 at the 翻 slot
                            because the original swapped 職／翻) or a remake alias
                            (remake-invented: a character without a Big5 code drawn with a
                            look-alike glyph; `half_aliases` point at a half glyph). Bytes
                            0x20-0x7e use the half glyphs.

game/text/OriginalBitmapFont.gd builds the Godot font from these. check (no original install
needed) proves the atlases have their recorded size and sha256 and every recorded slot is still
what the review and char tables give; it counts (does not fail on) characters of the current
content the atlas lacks — those fall back to the system font until the next generate.

Registry task original_bitmap_font (family assets); generate reads the original PAK.
"""
from __future__ import annotations

import io
import json
import re
from pathlib import Path

from hsltools.data.simplified_chars import OUT as CHAR_TABLE, REVIEW
from hsltools.registry import Context, ScriptCheckTask, original_archive
from hsltools.sources.original_font import BIG5_GLYPH_RANGES, FONTS, glyph_index, read_font
from hsltools.sources.shp import png_sha256

OUT_DIR = Path('content/generated/hsl/fonts')
TABLE = OUT_DIR / 'original_fonts.json'
FULL_COLUMNS = 64
# name -> (full member, half member, half-glyph drop): hsl01.exe 0x42f230 / 0x42f308.
FACES = {
    'FONT24': ('FONT.24', 'ASCFONT.24', 0),
    'FONT15': ('FONT.15', 'ASCFONT.15', 2),
}
# Characters of the remake's own copy with no Big5 code, drawn with a look-alike glyph
# (remake-invented): the katakana middle dot of joined titles as the centred Big5 A145 dot,
# the minus sign of a stat change as the ASCII hyphen, the selection pointer as the arrow, the
# sub-page mark of 重製選項 › as the ASCII greater-than.
ALIASES = {'・': '‧', '−': '-', '▶': '→', '›': '>'}
# Half glyphs below 0x20 the original draws (resource-derived, ASCFONT.24／ASCFONT.15 atlas row):
# 0x10 ► and 0x11 ◄ frame the 回憶錄 empty-slot text (RESOURCE.TXT item 314, bytes 10 20 B5 4C B0 4F BF FD 20 11, drawn by hsl01.exe 0x424f00).
CONTROL_HALF = {'\u25ba': '\x10', '\u25c4': '\x11'}
HALF_FIRST, HALF_END = 0x20, 0x7F
HALF_ROW = 128  # half glyphs 0x00-0x7f kept on the atlas row (the draw loop takes bytes < 0xa1; text uses 0x20-0x7e)
# Scanned for used characters: runtime content, minus the tables that list every character.
SCAN_JSON = ('content/imported', 'content/battles', 'content/authored', 'content/generated')
SCAN_SKIP = (OUT_DIR.as_posix() + '/', CHAR_TABLE.as_posix())
SCAN_TABLES = ('*.TXT', '*.H', '*.txt', '*.h')
LITERAL = re.compile(r'"((?:[^"\\\n]|\\.)*)"')


def big5_code(ordinal: int) -> int:
    """Inverse of hsl01.exe 0x45f798."""
    lead, rest = divmod(ordinal, 157)
    return (lead + 0x81) << 8 | (rest + 0x40 if rest < 0x3F else rest + 0x62)


def slot_chars() -> dict[int, str]:
    """Full-glyph slot -> the Unicode character of its Big5 code (cp950), first slot of a duplicate kept."""
    slots: dict[int, str] = {}
    seen: set[str] = set()
    for first, end, glyph in BIG5_GLYPH_RANGES:
        for ordinal in range(first, end):
            code = big5_code(ordinal)
            try:
                char = bytes((code >> 8, code & 0xFF)).decode('cp950')
            except UnicodeDecodeError:
                continue
            if len(char) == 1 and char not in seen:
                seen.add(char)
                slots[ordinal - first + glyph] = char
    return slots


def display_slots(root: Path) -> dict[str, int]:
    """The slot drawing each display-seam character the traditional text is shown as.

    A character the seam shows for a traditional one (simplified_chars `chars`) takes the slot
    of a traditional source whose original glyph glyph_review reads as that form; the review's
    slot swap (職 drawn at 翻 and 翻 at 職) takes the other slot of the pair; an unresolved
    reading keeps its own slot (provisional, glyph_review `unresolved`)."""
    review = json.loads((root / REVIEW).read_text(encoding='utf-8'))
    table = json.loads((root / CHAR_TABLE).read_text(encoding='utf-8'))
    drawn: dict[str, str] = {char: table['chars'][char] for char in review['drawn_as_opencc_first']}
    drawn.update(review['drawn_as_other_candidate'])
    result: dict[str, int] = {}
    for source, shown in sorted(drawn.items()):
        slot = glyph_index(source)
        if slot is None:
            raise ValueError(f'{source} (shown {shown}) has no Big5 glyph slot')
        result.setdefault(shown, slot)
    for source, entry in review['slot_swapped'].items():
        result[table['chars'][source]] = glyph_index(entry['drawn'])
        result[entry['drawn']] = glyph_index(source)
    for source in review['unresolved']:
        result.setdefault(table['chars'][source], glyph_index(source))
    return dict(sorted(result.items()))


def glyph_map(root: Path) -> dict[str, int]:
    """Every drawable wide character -> the full-glyph slot drawn for it (Big5, display seam, full aliases)."""
    mapped = {char: slot for slot, char in slot_chars().items()}
    mapped.update(display_slots(root))
    for alias, target in ALIASES.items():
        if ord(target) >= 0x80:
            mapped[alias] = mapped[target]
    return mapped


def _strings(value, found: set[str]) -> None:
    if isinstance(value, str):
        found.update(value)
    elif isinstance(value, dict):
        for key, item in value.items():
            found.update(key)
            _strings(item, found)
    elif isinstance(value, list):
        for item in value:
            _strings(item, found)


def used_chars(root: Path) -> set[str]:
    """Wide characters (>= 0x80) the remake can show, in their display-seam form."""
    found: set[str] = set()
    for base in SCAN_JSON:
        for path in sorted((root / base).rglob('*.json')):
            if path.relative_to(root).as_posix().startswith(SCAN_SKIP):
                continue
            try:
                _strings(json.loads(path.read_text(encoding='utf-8')), found)
            except (UnicodeDecodeError, json.JSONDecodeError):
                continue
    for pattern in SCAN_TABLES:
        for path in sorted((root / 'content/imported').rglob(pattern)):
            found.update(path.read_bytes().decode('cp950', errors='ignore'))
    for pattern in ('*.gd', '*.tscn'):
        for path in sorted((root / 'game').rglob(pattern)):
            for match in LITERAL.finditer(path.read_text(encoding='utf-8')):
                found.update(match.group(1))
    table = json.loads((root / CHAR_TABLE).read_text(encoding='utf-8'))['chars']
    return {table.get(char, char) for char in found if ord(char) >= 0x80}


def atlas_chars(root: Path) -> tuple[list[str], list[str]]:
    """(the used characters the fonts draw, sorted; the used characters they cannot draw)."""
    mapped = glyph_map(root)
    used = used_chars(root) - {alias for alias, target in ALIASES.items() if ord(target) < 0x80} - CONTROL_HALF.keys()
    return sorted(used & mapped.keys()), sorted(used - mapped.keys())


def face_record(name: str, atlas: bytes, count: int) -> dict:
    full, half, drop = FACES[name]
    full_w, full_h, _ = FONTS[full]
    half_w, half_h, _ = FONTS[half]
    rows = -(-count // FULL_COLUMNS)
    return {
        'atlas': (OUT_DIR / f'{name}.png').as_posix(),
        'atlas_sha256': png_sha256(atlas) if atlas else '',
        'atlas_size': [FULL_COLUMNS * full_w, rows * full_h + half_h],
        'members': [f'@:\\data\\{full}', f'@:\\data\\{half}'],
        'full_cell': [full_w, full_h],
        'full_columns': FULL_COLUMNS,
        'half_cell': [half_w, half_h],
        'half_row_top': rows * full_h,
        'half_drop': drop,
    }


def table_payload(root: Path, chars: list[str], atlases: dict[str, bytes]) -> dict:
    mapped = glyph_map(root)
    return {
        'schema': 'hsl_original_fonts.v2',
        'evidence_tier': 'resource-derived',
        'claim': 'The original DATA\\FONT.24／FONT.15 full glyphs and ASCFONT.24／ASCFONT.15 half glyphs, indexed as hsl01.exe '
                 'indexes them; a full glyph advances its width, a half glyph its width and is drawn half_drop px lower '
                 '(static-derived 0x42f230, 0x42f308, 0x4608e4). Only the characters the remake content can show are kept.',
        'sources': ['tools/hsltools/assets/original_bitmap_font.py', 'tools/hsltools/sources/original_font.py',
                    REVIEW.as_posix(), CHAR_TABLE.as_posix()],
        'loader': 'game/text/OriginalBitmapFont.gd',
        'faces': {name: face_record(name, atlases.get(name, b''), len(chars)) for name in FACES},
        'half_range': [HALF_FIRST, HALF_END],
        'half_aliases': {**{alias: target for alias, target in ALIASES.items() if ord(target) < 0x80}, **CONTROL_HALF},
        'aliases_tier': 'remake-invented',
        'chars': ''.join(chars),
        'slots': [mapped[char] for char in chars],
    }


def render_atlas(name: str, pak: Path, slots: list[int]) -> bytes:
    from PIL import Image

    full, half, _ = FACES[name]
    record = face_record(name, b'', len(slots))
    image = Image.new('LA', tuple(record['atlas_size']), (255, 0))
    pixels = image.load()
    for member, glyphs, origin in ((full, list(enumerate(slots)), None),
                                   (half, [(index, index) for index in range(HALF_ROW)], record['half_row_top'])):
        data = read_font(member, pak)
        width, height, stride = FONTS[member]
        size = height * stride
        for cell, index in glyphs:
            if origin is None:
                left, top = cell % FULL_COLUMNS * width, cell // FULL_COLUMNS * height
            else:
                left, top = cell * width, origin
            glyph = data[index * size:(index + 1) * size]
            for row in range(height):
                bits = int.from_bytes(glyph[row * stride:(row + 1) * stride], 'big')
                for column in range(width):
                    if bits >> (stride * 8 - 1 - column) & 1:
                        pixels[left + column, top + row] = (255, 255)
    buffer = io.BytesIO()
    image.save(buffer, format='PNG', optimize=True)
    return buffer.getvalue()


def build(pak: Path, root: Path) -> None:
    chars, undrawable = atlas_chars(root)
    mapped = glyph_map(root)
    atlases = {name: render_atlas(name, pak, [mapped[char] for char in chars]) for name in FACES}
    (root / OUT_DIR).mkdir(parents=True, exist_ok=True)
    for name, data in atlases.items():
        target = root / OUT_DIR / f'{name}.png'
        if not target.is_file() or target.read_bytes() != data:
            target.write_bytes(data)
    (root / TABLE).write_text(json.dumps(table_payload(root, chars, atlases), ensure_ascii=False, indent=1) + '\n', encoding='utf-8')
    print(f'original_bitmap_font: chars={len(chars)} undrawable={len(undrawable)} {"".join(undrawable)}')


def verify(root: Path) -> None:
    from PIL import Image

    tracked = json.loads((root / TABLE).read_text(encoding='utf-8'))
    chars = list(tracked['chars'])
    atlases = {name: (root / OUT_DIR / f'{name}.png').read_bytes() for name in FACES}
    expected = table_payload(root, chars, atlases)
    for name in FACES:
        recorded = tracked['faces'][name]['atlas_sha256']
        assert recorded == expected['faces'][name]['atlas_sha256'], f'{name}.png sha256 differs from {TABLE} (python3 tools/hsl.py generate original_bitmap_font)'
        with Image.open(root / OUT_DIR / f'{name}.png') as image:
            assert list(image.size) == expected['faces'][name]['atlas_size'] and image.mode == 'LA', f'{name}.png is {image.size} {image.mode}'
    assert tracked == expected, f'{TABLE} differs from the generator (python3 tools/hsl.py generate original_bitmap_font)'
    current, undrawable = atlas_chars(root)
    fallback = sorted(set(current) - set(chars)) + undrawable
    print(f'ORIGINAL_BITMAP_FONT_PASS faces={len(FACES)} chars={len(chars)} half={HALF_END - HALF_FIRST} '
          f'fallback={len(fallback)} {"".join(fallback)[:40]}')


class OriginalBitmapFontTask(ScriptCheckTask):
    name = 'original_bitmap_font'
    family = 'assets'
    inputs = (REVIEW.as_posix(), CHAR_TABLE.as_posix())
    outputs = (TABLE.as_posix(), (OUT_DIR / 'FONT24.png').as_posix(), (OUT_DIR / 'FONT15.png').as_posix())
    scripts = ('tools/hsltools/assets/original_bitmap_font.py', 'tools/hsltools/sources/original_font.py',
               'tools/hsltools/data/simplified_chars.py')

    def verify(self, ctx: Context) -> None:
        verify(ctx.root)

    def build(self, ctx: Context) -> None:
        build(original_archive(ctx), ctx.root)


def tasks() -> list[OriginalBitmapFontTask]:
    return [OriginalBitmapFontTask()]
