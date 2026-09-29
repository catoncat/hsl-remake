"""Original move／attack／skill range-cell art: the I_rect border frames and the EXE colour ramps.

Registry task range_cells (family assets): output content/imported/hsl/shared/range_cells/.
The three range drawers 0x411200 (move), 0x411480 (attack) and 0x4116a0 (skill footprint,
palette 0 = magic, 1 = special) each paint every marked 32 px cell twice per tick: ICONBOX.SHP
(a solid 32×32 block) through blit mode 6 — ``dst = ((dst & 0xf7de) + (colour & 0xf7de)) >> 1``,
a 50／50 RGB565 average — with a colour taken from a nine-entry ramp by a per-tick triangle
counter (0..8, −8..−1: 17 ticks a cycle), then the opaque border frame ``I_rect<palette><1..8>``,
advancing one frame every 8 ticks. The ramps and the two 8s live in .data next to each other.
manifest.json is published EXE-derived data (hsltools.original_content.PUBLISHED_EXE_DATA); the
border sheets are PAK art, so without hsl01.exe generate rebuilds only the sheets (build_sheets).
Evidence packet: docs/evidence_packets/static_reverse/original_range_cells.md.
"""
from __future__ import annotations

import hashlib
import json
import struct
from pathlib import Path

from hsltools.native.image import EXE_SHA, image
from hsltools.registry import Context, NotGeneratable, ScriptCheckTask, original_archive
from hsltools.sources.pak import find_decoded_paks_packages, find_paks_record_by_name, read_paks_record_bytes
from hsltools.sources.shp import parse_shp, png_sha256, rgb565_to_rgb, shp_pixel_values

ROOT = Path(__file__).resolve().parents[3]
OUT = ROOT / 'content/imported/hsl/shared/range_cells'
SCHEMA = 'hsl_range_cells.v1'
CELL = 32
FRAME_COUNT = 8

# palette: (drawer, colour ramp address, frame-timer address, I_rect decade)
PALETTES = {
    'move': {'drawer': '0x411200', 'ramp': 0x476be4, 'timer': 0x476bf8, 'decade': 1},
    'attack': {'drawer': '0x411480', 'ramp': 0x476c00, 'timer': 0x476c14, 'decade': 2},
    'magic': {'drawer': '0x4116a0 palette 0', 'ramp': 0x476c1c, 'timer': 0x476c44, 'decade': 3},
    'special': {'drawer': '0x4116a0 palette 1', 'ramp': 0x476c30, 'timer': 0x476c44, 'decade': 4},
}
# The cell cursor 0x430230 (every pick state and the AI lead-in): no fill, the opaque frame
# [0x4c1b34] + frame, i.e. I_rect01..08 (0x42f4ec loads the bank from I_RECT01), own timer words.
CURSOR = {'drawer': '0x430230', 'timer': 0x4784f4, 'decade': 0}


def _sheet_path(palette: str) -> Path:
    return OUT / f'range_border_{palette}.png'


def _read_ramp(base: int, mapped: bytearray, address: int) -> list[int]:
    values: list[int] = []
    offset = address - base
    while True:
        value = struct.unpack_from('<H', mapped, offset)[0]
        if value == 0:
            return values
        values.append(value)
        offset += 2


def _reader(pak: Path):
    packages = find_decoded_paks_packages(pak)

    def read(member: str) -> bytes:
        matches = [(p, r) for p in packages if (r := find_paks_record_by_name(p['records'], member))]
        if len(matches) != 1:
            raise ValueError('missing or ambiguous resource: ' + member)
        package, record = matches[0]
        return read_paks_record_bytes(package['path'], record, data_end_offset=int(package['paks']['candidate_index_offset']))
    return read


def _border_sheet(read, name: str, decade: int) -> list[dict]:
    """Writes range_border_<name>.png from the PAK's I_rect<decade>1..8 frames (only when its pixels
    differ); returns the frames' source rows."""
    from PIL import Image

    sheet = Image.new('RGBA', (CELL * FRAME_COUNT, CELL))
    frames = []
    for index in range(FRAME_COUNT):
        member = f'@:\\shape\\I_rect{decade}{index + 1}.shp'
        payload = read(member)
        shp = parse_shp(payload)
        if (int(shp['width']), int(shp['height'])) != (CELL, CELL):
            raise ValueError(member + ' is not a 32×32 frame')
        tile = Image.new('RGBA', (CELL, CELL))
        tile.putdata([(*rgb565_to_rgb(value), 255) if value is not None else (0, 0, 0, 0) for value in shp_pixel_values(payload, shp)])
        sheet.paste(tile, (CELL * index, 0))
        frames.append({'source_member': member, 'source_sha256': hashlib.sha256(payload).hexdigest()})
    path = _sheet_path(name)
    if not (path.is_file() and Image.open(path).convert('RGBA').tobytes() == sheet.tobytes()):
        sheet.save(path)
    return frames


def build_sheets(pak: Path) -> None:
    """Without hsl01.exe: the border sheets from the PAK, against the tracked manifest.json (the EXE
    ramps and frame timers are published data; the sheets are PAK art the player imports)."""
    manifest = json.loads((OUT / 'manifest.json').read_text())
    if manifest.get('schema') != SCHEMA or manifest.get('exe_sha256') != EXE_SHA:
        raise ValueError(f'{OUT / "manifest.json"}: not the {SCHEMA} manifest of the documented EXE')
    read = _reader(pak)
    for name, spec, row in [*((name, PALETTES[name], manifest['palettes'][name]) for name in PALETTES), ('cursor', CURSOR, manifest['cursor'])]:
        if _border_sheet(read, name, spec['decade']) != row['border_frames']:
            raise ValueError(f'{name}: the PAK border frames are not the ones manifest.json records')
        if png_sha256(_sheet_path(name)) != row['border_sheet_sha256']:
            raise ValueError(f'{name}: border sheet pixels differ from manifest.json')
    print('RANGE_CELLS_SHEETS_IMPORTED', len(PALETTES) + 1)


def build(pak: Path, exe: Path) -> None:
    raw_exe = exe.read_bytes()
    base, mapped = image(raw_exe)
    read = _reader(pak)
    OUT.mkdir(parents=True, exist_ok=True)
    fill = read('@:\\shape\\ICONBOX.SHP')
    fill_shp = parse_shp(fill)
    fill_values = set(shp_pixel_values(fill, fill_shp))
    if (int(fill_shp['width']), int(fill_shp['height'])) != (CELL, CELL) or fill_values != {0xffff}:
        raise ValueError('ICONBOX.SHP is not the solid 32×32 block the drawers blend')
    def frames_of(name: str, spec: dict) -> dict:
        delay, reload, frame, count = struct.unpack_from('<HHHH', mapped, spec['timer'] - base)
        frames = _border_sheet(read, name, spec['decade'])
        path = _sheet_path(name)
        return {
            'drawer': spec['drawer'],
            'frame_timer_address': hex(spec['timer']),
            'frame_ticks': reload,
            'frame_count': count,
            'initial_delay': delay,
            'initial_frame': frame,
            'border_sheet': 'res://' + path.relative_to(ROOT).as_posix(),
            'border_sheet_sha256': png_sha256(path),
            'border_frames': frames,
        }

    palettes = {}
    for name, spec in PALETTES.items():
        ramp = _read_ramp(base, mapped, spec['ramp'])
        palettes[name] = {
            'drawer': spec['drawer'],
            'ramp_address': hex(spec['ramp']),
            'ramp_rgb565': [f'0x{value:04x}' for value in ramp],
            'ramp_rgb': [list(rgb565_to_rgb(value)) for value in ramp],
            **frames_of(name, spec),
        }
    cursor = frames_of('cursor', CURSOR)
    manifest = {
        'schema': SCHEMA,
        'evidence_tier': 'static-derived; resource-derived; runtime-measured',
        'exe_sha256': EXE_SHA,
        'cell_px': CELL,
        'fill': {
            'source_member': '@:\\shape\\ICONBOX.SHP',
            'source_sha256': hashlib.sha256(fill).hexdigest(),
            'blit_mode': 6,
            'blend': 'dst = ((dst & 0xf7de) + (colour & 0xf7de)) >> 1 (RGB565 50/50 average, span case 6 at 0x4684b6; draw flag 0x40000000)',
            'godot_equivalent': 'ramp colour at alpha 0.5 over the whole cell',
        },
        'pulse': {
            'counter_addresses': {'move': '0x4c1a7c', 'attack': '0x4c1a80', 'skill': '0x4c1a84'},
            'sequence': 'after each drawn tick: index += 1, and when index >= 0 and ramp[index] == 0 (past the ninth entry) index = 1 - index; the drawn entry is ramp[abs(index)], so the darkest entry shows on two consecutive ticks (0x411442-0x41145e)',
            'period_ticks': 17,
            'indices': [0, 1, 2, 3, 4, 5, 6, 7, 8, -8, -7, -6, -5, -4, -3, -2, -1],
        },
        'border': {
            'draw_offset_px': [0, 0],
            'frame_order': 'I_rect<palette>1 … I_rect<palette>8 left to right',
            'frame_ticks_note': 'the delay word reloads from the next word (8) and the frame wraps at the count word (8): 64 ticks a lap',
        },
        'tick_evidence': 'docs/evidence_packets/runtime_observations/original_tick_rate/README.md',
        'runtime_check': 'docs/evidence_packets/static_reverse/original_range_cells.md#runtime-measured',
        'palettes': palettes,
        'cursor': cursor,
    }
    (OUT / 'manifest.json').write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + '\n')
    print('RANGE_CELLS_IMPORTED', len(palettes))


def check() -> None:
    from PIL import Image

    manifest = json.loads((OUT / 'manifest.json').read_text())
    assert manifest['schema'] == SCHEMA
    assert manifest['exe_sha256'] == EXE_SHA
    assert manifest['cell_px'] == CELL
    assert manifest['pulse']['period_ticks'] == len(manifest['pulse']['indices']) == 17
    assert set(manifest['palettes']) == set(PALETTES)
    cursor = manifest['cursor']
    assert cursor['drawer'] == CURSOR['drawer'] and cursor['frame_ticks'] == 8 and cursor['frame_count'] == FRAME_COUNT
    assert png_sha256(ROOT / cursor['border_sheet'].removeprefix('res://')) == cursor['border_sheet_sha256']
    for name, palette in manifest['palettes'].items():
        assert len(palette['ramp_rgb565']) == 9, name
        assert palette['ramp_rgb'] == [list(rgb565_to_rgb(int(value, 16))) for value in palette['ramp_rgb565']], name
        assert palette['frame_ticks'] == 8 and palette['frame_count'] == FRAME_COUNT, name
        assert len(palette['border_frames']) == FRAME_COUNT, name
        path = ROOT / palette['border_sheet'].removeprefix('res://')
        assert png_sha256(path) == palette['border_sheet_sha256'], name
        with Image.open(path) as sheet:
            assert sheet.size == (CELL * FRAME_COUNT, CELL), name
            pixels = sheet.convert('RGBA').load()
            # every frame is a hollow border: transparent centre, opaque ring inset by one pixel
            for index in range(FRAME_COUNT):
                assert pixels[CELL * index + 16, 16][3] == 0, name
                assert pixels[CELL * index + 1, 1][3] == 255, name
                assert pixels[CELL * index, 0][3] == 0, name
    print('RANGE_CELLS_CHECK_PASS')


class RangeCellsTask(ScriptCheckTask):
    name = 'range_cells'
    family = 'assets'
    inputs = ()
    outputs = ('content/imported/hsl/shared/range_cells/',)
    scripts = ('tools/hsltools/assets/range_cells.py',)

    def verify(self, ctx: Context) -> None:
        check()

    def build(self, ctx: Context) -> None:
        if ctx.original_exe.is_file():
            build(original_archive(ctx), ctx.original_exe)
        elif (OUT / 'manifest.json').is_file():
            build_sheets(original_archive(ctx))
        else:
            raise NotGeneratable(f'{self.name}: original EXE not found at {ctx.original_exe} (the colour ramps are read from hsl01.exe)')


def tasks() -> list[RangeCellsTask]:
    return [RangeCellsTask()]
