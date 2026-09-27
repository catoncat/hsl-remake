"""Export native BCMD lookup tables (instruction model, not full engine execution).

Registry task menu_layout (family assets): output content/imported/hsl/shared/command_menu/native_layout.json;
generate reads the SHA-locked original EXE. Bodies moved verbatim from the former hsl_menu_layout.py.
"""
import hashlib
import json
import struct
from pathlib import Path

from hsltools.registry import Context, NotGeneratable, ScriptCheckTask

ROOT = Path('content/imported/hsl/shared/command_menu')
EXE_SHA = 'f0b5f835d7d0d311b3ed75049c9fc2adc2b470b2bb30700e593abedf8c0a70f7'


def source_tables(exe):
    raw = exe.read_bytes()
    if hashlib.sha256(raw).hexdigest() != EXE_SHA:
        raise ValueError('Unsupported original executable version')
    pe = struct.unpack_from('<I', raw, 60)[0]
    n = struct.unpack_from('<H', raw, pe + 6)[0]
    optional = struct.unpack_from('<H', raw, pe + 20)[0]
    base = struct.unpack_from('<I', raw, pe + 52)[0]
    def read(va, count):
        rva = va - base
        for i in range(n):
            _, section, length, offset = struct.unpack_from('<IIII', raw, pe + 24 + optional + 40 * i + 8)
            if section <= rva and rva + count <= section + length:
                return raw[offset + rva - section:offset + rva - section + count]
        raise ValueError('Not file backed: ' + hex(va))
    tables = {axis: list(struct.unpack('<256i', read(address, 1024)))
              for axis, address in [('x', 0x4a35fc), ('y', 0x4a39fc)]}
    return {'schema': 'hsl_menu_layout.v1', 'evidence_tier': 'static-derived', 'exe_sha256': EXE_SHA,
            'tables': tables, 'table_sha256': {axis: hashlib.sha256(struct.pack('<256i', *v)).hexdigest() for axis, v in tables.items()},
            'center_y': -28, 'radius_x': 66, 'radius_y': 72, 'initial_angle': 192, 'hover_delay_calls': 7,
            'hover_scale_fixed': 0x15800,
            'limits': ['Model of 0x43ebf3..0x43eda6, not execution of full menu selection/edge/camera dispatch.',
                       'Calls per second remain calibrated, not inferred from video FPS.']}


def points(data, count):
    if not 1 <= count <= 10:
        raise ValueError('Unsupported command count')
    step = 256 // count + (1 if count == 6 else 0)
    mask = 248 if count == 7 else 255
    return [[(data['tables']['x'][((192 - i * step) & 255) & mask] * 66) >> 16,
             (data['tables']['y'][((192 - i * step) & 255) & mask] * 72) >> 16] for i in range(count)]


def check():
    data = json.loads((ROOT / 'native_layout.json').read_text())
    assert data['schema'] == 'hsl_menu_layout.v1' and data['exe_sha256'] == EXE_SHA
    assert (data['center_y'], data['radius_x'], data['radius_y'], data['initial_angle'], data['hover_delay_calls']) == (-28, 66, 72, 192, 7)
    assert data['hover_scale_fixed'] == 0x15800
    for axis, table in data['tables'].items():
        assert len(table) == 256 and all(isinstance(x, int) and abs(x) <= 65536 for x in table)
        assert hashlib.sha256(struct.pack('<256i', *table)).hexdigest() == data['table_sha256'][axis]
    assert points(data, 4) == [[0, -72], [-66, 0], [0, 72], [66, 0]]
    assert points(data, 2) == [[0, -72], [0, 72]]
    print('MENU_LAYOUT_CHECK_PASS')


class MenuLayoutTask(ScriptCheckTask):
    name = 'menu_layout'
    family = 'assets'
    inputs = ()
    outputs = ((ROOT / 'native_layout.json').as_posix(),)
    replaces = ('tools/hsl_menu_layout.py --check',)
    scripts = ('tools/hsltools/assets/menu_layout.py',)

    def verify(self, ctx: Context) -> None:
        check()

    def build(self, ctx: Context) -> None:
        if not ctx.original_exe.exists():
            raise NotGeneratable(f'{self.name}: original EXE not found at {ctx.original_exe}')
        (ROOT / 'native_layout.json').write_text(json.dumps(source_tables(ctx.original_exe), indent=2) + '\n')


def tasks() -> list[MenuLayoutTask]:
    return [MenuLayoutTask()]
