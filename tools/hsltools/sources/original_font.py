"""The original 24／15 px bitmap fonts DATA\\FONT.24 and DATA\\FONT.15 and how hsl01.exe indexes them.

The original text resources are Big5 (cp950, traditional); hsl01.exe never converts text to
GB. What the player sees as simplified comes from the glyph bitmaps: both fonts carry 13867
glyphs indexed by Big5 code, and the glyph at most traditional codes is drawn as the
simplified form (docs/evidence_packets/static_reverse/original_font_script/README.md).

static-derived (hsl01.exe):
  0x42f230-0x42f31b  load DATA\\FONT.15+ASCFONT.15 (16x15) and DATA\\FONT.24+ASCFONT.24 (24x24)
  0x460ace           font loader; with no map argument it builds the Big5-ordinal -> glyph
                     table at 0x460c32-0x460d1b (the four ranges of BIG5_GLYPH_RANGES)
  0x45f798           Big5 ordinal = (lead-0x81)*157 + (trail<=0x7e ? trail-0x40 : trail-0x62)
  0x4608e4           draw loop: a byte >= 0xa1 starts a two-byte code; glyph = table[ordinal],
                     glyph 0 is skipped (`mov ax, word ptr [edi + 2*eax]`)

Command line (needs the original install; prints a glyph as text, no image):

    PYTHONPATH=tools python3 -m hsltools.sources.original_font show 體說後
"""
from __future__ import annotations

import sys
from pathlib import Path

from hsltools.paths import ORIGINAL_PAK
from hsltools.sources.pak import find_decoded_paks_packages, find_paks_record_by_name, read_paks_record_bytes

# (first ordinal, end ordinal, first glyph): 0x460c32-0x460d1b; every other ordinal maps to 0.
BIG5_GLYPH_RANGES = (
    (0x13A0, 0x1538, 0x3326),  # A140-A3BF symbols
    (0x1577, 0x2A90, 0x0000),  # A440-C67E frequent hanzi
    (0x2A90, 0x2BFD, 0x34BE),  # C6A1-C8FE (ETEN extension row)
    (0x2C28, 0x4A35, 0x1519),  # C940-F9D5 less frequent hanzi
)
GLYPH_COUNT = 13867
FONTS = {  # member -> (width, height, bytes per row)
    'FONT.24': (24, 24, 3),
    'FONT.15': (16, 15, 2),
    'ASCFONT.24': (12, 24, 2),  # half-width, 256 glyphs indexed by byte (bytes < 0xa1 in the draw loop)
    'ASCFONT.15': (8, 15, 1),
}
ASCII_GLYPH_COUNT = 256


def big5_ordinal(code: int) -> int:
    lead, trail = code >> 8, code & 0xFF
    return (lead - 0x81) * 157 + (trail - 0x40 if trail <= 0x7E else trail - 0x62)


def glyph_index(char: str) -> int | None:
    """The glyph slot hsl01.exe draws for one character, or None (not Big5 / no glyph)."""
    try:
        raw = char.encode('cp950')
    except UnicodeEncodeError:
        return None
    if len(raw) != 2 or raw[0] < 0xA1:
        return None
    ordinal = big5_ordinal(raw[0] << 8 | raw[1])
    for first, end, glyph in BIG5_GLYPH_RANGES:
        if first <= ordinal < end:
            return ordinal - first + glyph
    return None


def read_font(member: str, pak: Path = ORIGINAL_PAK) -> bytes:
    package = find_decoded_paks_packages(pak)[0]
    record = find_paks_record_by_name(package['records'], '@:\\data\\' + member)
    if record is None:
        raise ValueError(f'{member} not in {pak}')
    data = read_paks_record_bytes(package['path'], record, data_end_offset=int(package['paks']['candidate_index_offset']))
    width, height, stride = FONTS[member]
    count = ASCII_GLYPH_COUNT if member.startswith('ASC') else GLYPH_COUNT
    if len(data) != count * height * stride:
        raise ValueError(f'{member}: {len(data)} bytes, expected {count} glyphs of {height}x{stride}')
    return data


def glyph_rows(font: bytes, member: str, char: str) -> list[str]:
    """One glyph as text rows ('#' ink, '.' blank); ASCFONT members take one ASCII character."""
    index = ord(char) if member.startswith('ASC') else glyph_index(char)
    if index is None:
        raise ValueError(f'{char!r} has no Big5 glyph slot')
    width, height, stride = FONTS[member]
    size = height * stride
    cell = font[index * size:(index + 1) * size]
    rows = []
    for row in range(height):
        bits = int.from_bytes(cell[row * stride:(row + 1) * stride], 'big')
        rows.append(''.join('#' if bits >> (stride * 8 - 1 - column) & 1 else '.' for column in range(width)))
    return rows


def main(argv: list[str]) -> int:
    if len(argv) < 2 or argv[0] != 'show':
        print('usage: python3 -m hsltools.sources.original_font show CHARS [FONT.24|FONT.15]', file=sys.stderr)
        return 2
    member = argv[2] if len(argv) > 2 else 'FONT.24'
    font = read_font(member)
    glyphs = [(char, glyph_rows(font, member, char)) for char in argv[1]]
    print('   '.join(f'{char} slot {glyph_index(char)}'.ljust(FONTS[member][0]) for char, _ in glyphs))
    for row in range(FONTS[member][1]):
        print('   '.join(rows[row] for _, rows in glyphs))
    return 0


if __name__ == '__main__':
    raise SystemExit(main(sys.argv[1:]))
