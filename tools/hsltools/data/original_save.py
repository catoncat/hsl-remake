"""Original save files (戰場記錄 SAVES\\HSLBAT.SAV, 回憶錄 SAVES\\HSLnn.SAV): parse, re-serialise
byte for byte, and generate loadable 回憶錄 files that put the original at a chosen state.

Layout (static-derived from the writer 0x42e070 / reader 0x42e640, see
docs/evidence_packets/static_reverse/original_save_format.md; every compressed block is
`u32 length` + LZW of _original_save_codec):

  LZW(header 0x68)                       0x42e070 field list, version 100
  raw 0x54  registered slot codes        0x4c4360[21]  (0 empty / 800+slot / |0x80000000 disabled)
  raw 200   player-mode bytes            0x4c6d80[200] (per live actor index)
  LZW(0x18edc) live actor records        *0x4c1bc8, 201 x 0x1fc (index = registered slot + 1)
  u32 cap, u32 count, LZW(cap*8)  x2     *0x4c1d10 / *0x4c1d1c 8-byte item lists (0x44f720)
  LZW(200)  encounter ratios             0x4c27e0 u16[100] per big-map point (0x4545c0)
  LZW(0x6720) town menu trees            *0x4c1d74, 100 x 0x108 (original_world_town.md)
  LZW(4000) big-map points               0x4c4a20, the bigmap.dat point table with live mode/flags/event
  LZW(0x640) big-map tracks              0x4c43c0, the bigmap.dat line table with live mode/flags
  [battle saves only] 0x4079f0 queue + 0x44e970 flag tables + per-object records (kept opaque)
  u32 checksum                           0x42e040 over everything before it

The 回憶錄 generator starts from the tracked HSLBAT sample (a level-51 first-control battle
save: the fresh new-game tables), applies the state spec through the same table helpers the
original VM uses (0x426xxx big-map, 0x4547xx town tree) and synthesises every party member's
live record from the runtime PLAYERS template dump (original_save_members: template copy,
0x4348f0 job-up exchange, 0x448840 refresh). A party entry uses the carry vocabulary:
  {'actor_id': '002', 'level': 40, 'attributes': {...}, 'inventory': [284], 'job_up_history': ['011']}

Registry tasks (family original_save): `original_save:sample` round-trips the tracked sample,
`original_save:members` proves the template dump, `original_save:native_second_tier` proves the
generator against the 回憶錄 the original wrote after running both second-tier job-ups from the
`before_second_tier_at_temple` preset (every table but the standing-position header words is
byte-equal to the `after_second_tier_at_temple` preset), `original_save:<preset>` regenerates
the tracked preset files. CLI:
  python3 -m hsltools.data.original_save --state before_second_tier_at_temple --out DIR
"""
from __future__ import annotations

import argparse
import json
import struct
from pathlib import Path

from hsltools.data import json_bytes
from hsltools.data._original_save_codec import checksum, lzw_decode, lzw_encode
from hsltools.data.original_save_members import (RECORD_COUNT, RECORD_SIZE, REC, TEMPLATES_BIN, TemplateTable, actor_code,
                                                 i32, job_up_ready, put32, synthesize, u32)
from hsltools.paths import ROOT
from hsltools.registry import CheckFailed, Context, GeneratedFilesTask, NotGeneratable, ScriptCheckTask

SCHEMA = 'hsl_original_save_state.v1'
PACKET_DIR = ROOT / 'docs/evidence_packets/static_reverse/original_save_format'
SAMPLE = PACKET_DIR / 'HSLBAT_first_control.SAV'
SAMPLE_SUMMARY = PACKET_DIR / 'HSLBAT_first_control.json'
NATIVE_SECOND_TIER = PACKET_DIR / 'HSL_second_tier_native.SAV'
NATIVE_SECOND_TIER_SUMMARY = PACKET_DIR / 'HSL_second_tier_native.json'
NATIVE_SECOND_TIER_PRESET = 'after_second_tier_at_temple'
# Header words of a 回憶錄 that depend on where the walker stood when the scroll was opened; the
# native save was taken after re-entering the temple from the map (walker parked, no track shown).
STANDING_HEADER_WORDS = ('camera_y', 'show_track_point', 'walk_to_point', 'play_seconds')
UNTOUCHED_NATIVE_SLOTS = (2, 3, 4)   # 琥 / 漢克斯 / 雪拉: loaded from the before-preset, never rewritten by the run
OUT = ROOT / 'content/generated/hsl/development/original_saves'
BIG_MAP_FLOW = ROOT / 'content/generated/hsl/static/hsl01/big_map_flow.json'
TOWNDEF = ROOT / 'content/imported/hsl/global/world_map/towndef.json'
WORLD_MAP = ROOT / 'content/imported/hsl/global/world_map/world_map.json'

VERSION = 100
HEADER_SIZE = 0x68
HEADER_LIMIT = 0x9C
PLAYERS_SIZE = RECORD_SIZE * RECORD_COUNT      # 0x18edc
PLAYERS_LIMIT = 0x2564A
SLOT_TABLE_SIZE = 0x54
MODE_TABLE_SIZE = 200
RATIO_SIZE = 200
TOWN_RECORD = 0x108
TOWN_SIZE = TOWN_RECORD * 100                 # 0x6720
POINT_RECORD = 40
POINTS_SIZE = POINT_RECORD * 100
TRACK_RECORD = 16
TRACKS_SIZE = TRACK_RECORD * 100
BIG_MAP_LEVEL = 49

# (offset, struct format, name, original global) — 0x42e070 store order is irrelevant, offsets are.
HEADER_FIELDS = (
    (0x00, 'I', 'version', None),
    (0x04, 'i', 'camera_x', '0x4c091c'),
    (0x08, 'i', 'camera_y', '0x4c0920'),
    (0x0C, 'i', 'current_point', '0x4c1ba4'),
    (0x10, 'i', 'next_level', '0x4c1ba8'),
    (0x14, 'i', 'walk_from_point', '0x477c18'),
    (0x18, 'i', 'level_files', '0x4c1bac'),
    (0x1C, 'i', 'current_level', '0x4c1bb8'),
    (0x20, 'I', 'round_counter', '0x4c1bbc'),
    (0x24, 'h', 'show_track_point', '0x4c1bb0'),
    (0x26, 'h', 'walk_to_point', '0x4c1bb4'),
    (0x28, 'i', 'gold', '0x4c1bcc'),
    (0x2C, 'i', 'level_flag', '0x4c1ba0'),
    (0x30, 'i', 'leonard_level', 'record(slot 0)+0x9c'),
    (0x34, 'i', 'play_seconds', '0x4c1bc0'),
    (0x38, 'I', 'rng_hi', '0x4c3044'),
    (0x3C, 'I', 'rng_lo', '0x4c3040'),
    (0x40, 'H', 'secret_man_index', '0x4c1bd4'),
    (0x42, 'H', 'secret_man_word', '0x4c1bd0'),
    (0x44, 'i', 'secret_man_event', '0x4c1d70'),
    (0x48, 'I', 'serial_state', '0x4c1ad4'),
    (0x4C, 'I', 'over_flag', '0x4c1bd8'),
    (0x50, 'i', 'over_score_1', '0x4c1bdc'),
    (0x54, 'i', 'over_score_2', '0x4c1be0'),
    (0x58, 'i', 'over_score_3', '0x4c1be4'),
    (0x5C, 'h', 'sys_arrive_y', '0x4c296c'),
    (0x5E, 'h', 'sys_arrive_x', '0x4c2968'),
    (0x60, 'i', 'reserved_60', None),
    (0x64, 'i', 'reserved_64', None),
)

# bigmap.dat flag bits (TYPE.H) and the point / track record words.
BMPM = {'bmpmBattle': 0x80000000, 'bmpmGeneral': 0x40000000, 'bmpmTown': 0x20000000,
        'bmpmVisit': 0x10000000, 'bmpmHidden': 0x08000000}
BM_MODES = {'gameBMShowHidden': 0, 'gameBMShowSlow': 1, 'gameBMShow': 2}
POINT_MODE, POINT_FLAGS, POINT_EVENT = 0, 1, 2
TRACK_MODE, TRACK_FLAGS = 0, 1



class OriginalSave:
    """One parsed save; `battle_tail` keeps the battle-only sections verbatim (None for 回憶錄)."""

    def __init__(self) -> None:
        self.header: dict[str, int] = {}
        self.slot_codes = bytearray(SLOT_TABLE_SIZE)
        self.mode_bytes = bytearray(MODE_TABLE_SIZE)
        self.players = bytearray(PLAYERS_SIZE)
        self.lists: list[tuple[int, int, bytes]] = [(0, 0, b''), (0, 0, b'')]
        self.ratios = bytearray(RATIO_SIZE)
        self.towns = bytearray(TOWN_SIZE)
        self.points = bytearray(POINTS_SIZE)
        self.tracks = bytearray(TRACKS_SIZE)
        self.battle_tail: bytes | None = None

    # --- header ---------------------------------------------------------------------------
    @staticmethod
    def unpack_header(raw: bytes) -> dict[str, int]:
        if len(raw) != HEADER_SIZE:
            raise ValueError(f'header is {len(raw)} bytes, expected {HEADER_SIZE}')
        return {name: struct.unpack_from('<' + fmt, raw, offset)[0] for offset, fmt, name, _ in HEADER_FIELDS}

    @staticmethod
    def pack_header(fields: dict[str, int]) -> bytes:
        raw = bytearray(HEADER_SIZE)
        for offset, fmt, name, _ in HEADER_FIELDS:
            struct.pack_into('<' + fmt, raw, offset, fields[name])
        return bytes(raw)

    # --- records --------------------------------------------------------------------------
    def record(self, slot: int) -> memoryview:
        """The live record of registered slot `slot` (index slot + 1)."""
        start = (slot + 1) * RECORD_SIZE
        return memoryview(self.players)[start:start + RECORD_SIZE]

    def slot_code(self, slot: int) -> int:
        return i32(self.slot_codes, slot * 4)

    def set_slot_code(self, slot: int, code: int) -> None:
        struct.pack_into('<i', self.slot_codes, slot * 4, code)

    # --- serialisation --------------------------------------------------------------------
    @classmethod
    def parse(cls, data: bytes) -> 'OriginalSave':
        if len(data) < 8 or checksum(data[:-4]) != u32(data, len(data) - 4):
            raise ValueError('checksum mismatch (0x42e040 sliding XOR)')
        save = cls()
        pos = 0

        def read_u32() -> int:
            nonlocal pos
            value = u32(data, pos)
            pos += 4
            return value

        def read_block(size: int) -> bytes:
            nonlocal pos
            length = read_u32()
            block = lzw_decode(data[pos:pos + length], size)
            if len(block) != size:
                raise ValueError(f'block at {pos - 4} decodes to {len(block)} bytes, expected {size}')
            pos += length
            return block

        save.header = cls.unpack_header(read_block(HEADER_SIZE))
        if save.header['version'] != VERSION:
            raise ValueError(f'save version {save.header["version"]}, expected {VERSION}')
        save.slot_codes = bytearray(data[pos:pos + SLOT_TABLE_SIZE]); pos += SLOT_TABLE_SIZE
        save.mode_bytes = bytearray(data[pos:pos + MODE_TABLE_SIZE]); pos += MODE_TABLE_SIZE
        save.players = bytearray(read_block(PLAYERS_SIZE))
        lists = []
        for _ in range(2):
            capacity = read_u32()
            count = read_u32()
            lists.append((capacity, count, read_block(capacity * 8)))
        save.lists = lists
        save.ratios = bytearray(read_block(RATIO_SIZE))
        save.towns = bytearray(read_block(TOWN_SIZE))
        save.points = bytearray(read_block(POINTS_SIZE))
        save.tracks = bytearray(read_block(TRACKS_SIZE))
        tail = data[pos:len(data) - 4]
        save.battle_tail = bytes(tail) if tail else None
        return save

    def serialize(self) -> bytes:
        out = bytearray()

        def write_block(block: bytes, limit: int = -1) -> None:
            packed = lzw_encode(block, limit)
            out.extend(struct.pack('<I', len(packed)))
            out.extend(packed)

        write_block(self.pack_header(self.header), HEADER_LIMIT)
        out.extend(self.slot_codes)
        out.extend(self.mode_bytes)
        write_block(bytes(self.players), PLAYERS_LIMIT)
        for capacity, count, block in self.lists:
            out.extend(struct.pack('<II', capacity, count))
            write_block(block)
        write_block(bytes(self.ratios))
        write_block(bytes(self.towns))
        write_block(bytes(self.points))
        write_block(bytes(self.tracks))
        if self.battle_tail:
            out.extend(self.battle_tail)
        out.extend(struct.pack('<I', checksum(bytes(out))))
        return bytes(out)

    # --- big-map table helpers (0x426xxx) ----------------------------------------------------
    def point_word(self, point: int, word: int) -> int:
        return u32(self.points, point * POINT_RECORD + word * 4)

    def set_point_word(self, point: int, word: int, value: int) -> None:
        put32(self.points, point * POINT_RECORD + word * 4, value)

    def track_word(self, track: int, word: int) -> int:
        return u32(self.tracks, track * TRACK_RECORD + word * 4)

    def set_track_word(self, track: int, word: int, value: int) -> None:
        put32(self.tracks, track * TRACK_RECORD + word * 4, value)

    def point_set_flag(self, point: int, bits: int) -> None:      # 0x426d60
        self.set_point_word(point, POINT_FLAGS, self.point_word(point, POINT_FLAGS) | bits)

    def point_clear_flag(self, point: int, bits: int) -> None:    # 0x426db0
        self.set_point_word(point, POINT_FLAGS, self.point_word(point, POINT_FLAGS) & ~bits)

    def track_set_flag(self, track: int, bits: int) -> None:      # 0x426d80
        self.set_track_word(track, TRACK_FLAGS, self.track_word(track, TRACK_FLAGS) | bits)

    def track_clear_flag(self, track: int, bits: int) -> None:    # 0x426dd0
        self.set_track_word(track, TRACK_FLAGS, self.track_word(track, TRACK_FLAGS) & ~bits)

    def point_set_event(self, point: int, event: int, mode_bits: int) -> None:   # 0x426c70
        if mode_bits:
            self.point_clear_flag(point, BMPM['bmpmVisit'])
            if mode_bits & 0xE0000000:
                self.point_clear_flag(point, BMPM['bmpmTown'] | BMPM['bmpmGeneral'] | BMPM['bmpmBattle'])
            self.point_set_flag(point, mode_bits)
        if event != -1:
            self.set_point_word(point, POINT_EVENT, event)

    def point_set_mode(self, point: int, mode: int) -> None:      # 0x426b70
        if not self.point_word(point, POINT_FLAGS) & BMPM['bmpmHidden'] and self.point_word(point, POINT_MODE) != 2:
            self.set_point_word(point, POINT_MODE, mode)

    def track_set_mode(self, track: int, mode: int) -> None:      # 0x426bb0
        if not self.track_word(track, TRACK_FLAGS) & BMPM['bmpmHidden'] and self.track_word(track, TRACK_MODE) != 2:
            self.set_track_word(track, TRACK_MODE, mode)

    def set_encounter_ratio(self, point: int, ratio: int) -> None:   # 0x4545c0
        struct.pack_into('<H', self.ratios, point * 2, ratio)

    # --- town tree helpers (0x4546xx .. 0x4549xx) -------------------------------------------
    def _town(self, town: int) -> int:
        return town * TOWN_RECORD

    def town_find(self, town: int, node: int) -> int:             # 0x454690
        for entry in range(8):
            if i32(self.towns, self._town(town) + entry * 0x20) == node:
                return entry
        return -1

    def town_exec_event(self, town: int) -> int:                  # 0x454720
        return struct.unpack_from('<H', self.towns, self._town(town) + 0x100)[0]

    def town_set_exec_event(self, town: int, event: int) -> None:   # 0x454740
        struct.pack_into('<H', self.towns, self._town(town) + 0x100, event & 0xFFFF)

    def town_set_exit_exec_event(self, town: int, event: int) -> None:   # 0x454780 (getter 0x454760)
        struct.pack_into('<H', self.towns, self._town(town) + 0x102, event & 0xFFFF)

    def town_add_root(self, town: int, node: int) -> None:        # 0x4547a0
        if self.town_find(town, node) != -1:
            return
        for entry in range(8):
            offset = self._town(town) + entry * 0x20
            if i32(self.towns, offset) == 0:
                struct.pack_into('<i', self.towns, offset, node)
                return

    def town_add_child(self, town: int, node: int, child: int) -> None:   # 0x454870 -> 0x4547f0
        if self.town_find(town, node) == -1:
            self.town_add_root(town, node)
        entry = self.town_find(town, node)
        if entry == -1:
            return
        base = self._town(town) + entry * 0x20
        words = [i32(self.towns, base + i * 4) for i in range(8)]
        if any(word != 0 and word == child for word in words):
            return
        for i in range(8):
            if words[i] == 0:
                struct.pack_into('<i', self.towns, base + i * 4, child)
                return

    def town_delete_node(self, town: int, node: int) -> None:     # 0x4548b0
        entry = self.town_find(town, node)
        if entry == -1:
            return
        exec_event = self.town_exec_event(town)
        self.town_set_exec_event(town, 0)
        base = self._town(town)
        for target in range(entry, 7):
            src = base + (target + 1) * 0x20
            self.towns[base + target * 0x20:base + target * 0x20 + 0x20] = self.towns[src:src + 0x20]
        self.towns[base + 0xE0:base + 0x100] = bytes(0x20)
        self.town_set_exec_event(town, exec_event)

    def town_delete_child(self, town: int, node: int, child: int) -> None:   # 0x454950 + 0x4549e0
        entry = self.town_find(town, node)
        if entry == -1:
            return
        base = self._town(town) + entry * 0x20
        words = [i32(self.towns, base + i * 4) for i in range(8)]
        if child not in words:
            return
        index = words.index(child)
        words = words[:index] + words[index + 1:] + [0]
        for i, word in enumerate(words):
            struct.pack_into('<i', self.towns, base + i * 4, word)
        if words[1] == 0:
            self.town_delete_node(town, node)

    def town_tree(self, town: int) -> dict[str, list[int]]:
        """{"0": roots, "<root>": children} as the remake's hsl_world_state.v1 towns[].tree."""
        tree: dict[str, list[int]] = {'0': []}
        for entry in range(8):
            base = self._town(town) + entry * 0x20
            words = [i32(self.towns, base + i * 4) for i in range(8)]
            if words[0] == 0:
                continue
            tree['0'].append(words[0])
            children = [word for word in words[1:] if word]
            if children:
                tree[str(words[0])] = children
        return tree


# --- script write tokens (te* of the town VM 0x454e20 / act* of the battle VM 0x450840) -----

def _symbols() -> dict[str, int]:
    towndef = json.loads(TOWNDEF.read_text())
    symbols = {key: int(str(value), 0) for key, value in towndef['symbols'].items() if value is not None}
    symbols.update(BMPM)
    symbols.update(BM_MODES)
    return symbols


def resolve(symbols: dict[str, int], value: str | int) -> int:
    if isinstance(value, int):
        return value
    text = value.strip()
    if text in symbols:
        return symbols[text]
    return int(text, 0)


WRITE_KINDS = frozenset(('AddSelfTE', 'DeleteSelfTE', 'AddTE', 'DeleteTE', 'SetExecEvent', 'SetTownExecEvent', 'SetTownExitExecEvent',
                         'BMSetPointFlag', 'BMClearPointFlag', 'BMSetTrackFlag', 'BMClearTrackFlag', 'BMSetPointEvent',
                         'BMSetPointEventNotVisit', 'BMSetPointMode', 'BMSetTrackMode', 'BMSetPointEncounterRatio',
                         'BMSetShowTrackPoint', 'SetBMWalkToPoint'))


def apply_write(save: OriginalSave, name: str, args: list, symbols: dict[str, int], self_town: int | None = None) -> bool:
    """Apply one flow write token to the tables; False when the token writes nothing saved."""
    kind = name[2:] if name.startswith('te') else name[3:] if name.startswith('act') else name
    if kind not in WRITE_KINDS:
        return False
    vals = [resolve(symbols, a) for a in args]
    if kind in ('AddSelfTE', 'DeleteSelfTE'):
        if self_town is None:
            raise ValueError(f'{name} needs the current town')
        vals = [self_town] + vals
        kind = kind.replace('Self', '')
    if kind == 'AddTE':
        town, node, num, children = vals[0], vals[1], vals[2], vals[3:]
        if num == 0:
            save.town_add_root(town, node)
        else:
            for child in children[:num]:
                save.town_add_child(town, node, child)
        return True
    if kind == 'DeleteTE':
        town, node, num, children = vals[0], vals[1], vals[2], vals[3:]
        if num == 0:
            save.town_delete_node(town, node)
        else:
            for child in children[:num]:
                save.town_delete_child(town, node, child)
        return True
    if kind in ('SetExecEvent', 'SetTownExecEvent'):
        save.town_set_exec_event(vals[0], vals[1]); return True
    if kind == 'SetTownExitExecEvent':
        save.town_set_exit_exec_event(vals[0], vals[1]); return True
    if kind == 'BMSetPointFlag':
        save.point_set_flag(vals[0], vals[1]); return True
    if kind == 'BMClearPointFlag':
        save.point_clear_flag(vals[0], vals[1]); return True
    if kind == 'BMSetTrackFlag':
        save.track_set_flag(vals[0], vals[1]); return True
    if kind == 'BMClearTrackFlag':
        save.track_clear_flag(vals[0], vals[1]); return True
    if kind == 'BMSetPointEvent':
        save.point_set_event(vals[0], vals[1], vals[2] if len(vals) > 2 else 0); return True
    if kind == 'BMSetPointEventNotVisit':
        if not save.point_word(vals[0], POINT_FLAGS) & BMPM['bmpmVisit']:
            save.point_set_event(vals[0], vals[1], vals[2] if len(vals) > 2 else 0)
        return True
    if kind == 'BMSetPointMode':
        save.point_set_mode(vals[0], vals[1]); return True
    if kind == 'BMSetTrackMode':
        save.track_set_mode(vals[0], vals[1]); return True
    if kind == 'BMSetPointEncounterRatio':
        save.set_encounter_ratio(vals[0], vals[1]); return True
    if kind == 'BMSetShowTrackPoint':
        save.header['show_track_point'] = vals[0]; return True
    if kind == 'SetBMWalkToPoint':
        save.header['walk_from_point'] = vals[0]
        save.header['walk_to_point'] = vals[1]
        return True
    return False


def flow_commands(kind: str, level: int, section: str | None = None) -> list[dict]:
    flow = json.loads(BIG_MAP_FLOW.read_text())
    for script in flow['scripts']:
        if script['kind'] == kind and int(script['level']) == level:
            return [cmd for cmd in script['commands'] if section is None or cmd['section'] == section]
    raise KeyError(f'no {kind} {level} in big_map_flow.json')


def towndef_event(code: int) -> dict:
    for event in json.loads(TOWNDEF.read_text())['town_events']:
        if int(event['code']) == code:
            return event
    raise KeyError(f'no TOWNDEF event {code}')


def world_map_point_xy(point: int) -> tuple[int, int]:
    for entry in json.loads(WORLD_MAP.read_text())['points']:
        if int(entry['id']) == point:
            return int(entry['x']), int(entry['y'])
    raise KeyError(f'no big-map point {point} in world_map.json')


def route_tracks(points: list[int]) -> list[int]:
    """The bigmap.dat tracks whose both endpoints are travelled points (the lines a walked route shows)."""
    visited = set(points)
    return [int(track['id']) for track in json.loads(WORLD_MAP.read_text())['tracks']
            if int(track['from_point']) in visited and int(track['to_point']) in visited]


def register_slot(save: OriginalSave, slot: int) -> None:
    """0x42cb30: an empty registered slot gets object code 800 + slot; a disabled one is re-enabled."""
    code = save.slot_code(slot)
    save.set_slot_code(slot, 800 + slot if code == 0 else code & 0xFFFF)
    save.mode_bytes[slot] = 1   # the sample sets byte 0 for 雷歐納德 (0x450710 pmPlayer write); indexing by slot mirrors it


# --- state specs -----------------------------------------------------------------------------

def world_map_header(save: OriginalSave, point: int, point_xy: tuple[int, int]) -> None:
    """Header fields of a 回憶錄 taken on the big map standing at `point` (main loop 0x42f7a4:
    current_point = walk_from or the previous level; the big-map point ids double as level ids)."""
    save.header.update({
        'camera_x': max(0, min(1280 - 640, point_xy[0] - 320)),
        'camera_y': max(0, min(960 - 480, point_xy[1] - 240)),
        'current_point': point, 'next_level': point, 'current_level': point,
        'level_files': BIG_MAP_LEVEL, 'walk_from_point': -1, 'walk_to_point': point, 'show_track_point': -1,
        'sys_arrive_x': 0, 'sys_arrive_y': 0,
    })


def level_entry_header(save: OriginalSave, level: int) -> None:
    """Header fields of a 回憶錄 that loads straight into story / battle level `level` instead of
    the big map: the words `actSetNextPlayLevelEvent level,level` leaves behind (`0x42cc10`:
    `0x4c1ba8` next level = `0x4c1bac` level files = level). After the load the main loop
    `0x42f7a4` runs `0x42da60(next_level)`, which sets `current_level` and loads the LEVEL /
    STORY / WINFAIL files of `level_files` (`0x42ce10`) — the same call the native chain makes
    after the previous level's win section. `current_point` is read by the 讀取回憶錄 list row
    (point name); the tracked level-51 HSLBAT sample carries 1 there and the Wine load of the
    level-53 preset kept it at 1 through level 58 (runtime-measured 2026-09-22)."""
    save.header.update({
        'camera_x': 0, 'camera_y': 0,
        'current_point': 1, 'next_level': level, 'current_level': level, 'level_files': level,
        'walk_from_point': -1, 'walk_to_point': 0, 'show_track_point': 0,
        'sys_arrive_x': 0, 'sys_arrive_y': 0,
    })


def apply_spec(base: OriginalSave, spec: dict) -> tuple[OriginalSave, dict]:
    """Build a 回憶錄 from the base (sample) tables and a state spec; returns (save, receipt)."""
    save = OriginalSave.parse(base.serialize())   # deep copy through the codec
    save.battle_tail = None
    symbols = _symbols()
    receipt: dict = {'schema': SCHEMA, 'name': spec['name'], 'applied_flow': [], 'skipped_tokens': [], 'party': []}
    # 1. the level-51 battle leaves 雷歐納德's registration, its enemy / NPC actor instances (live
    #    indexes >= 21) and two mode bytes behind; the party below is rebuilt from the spec alone.
    save.mode_bytes = bytearray(MODE_TABLE_SIZE)
    save.slot_codes = bytearray(SLOT_TABLE_SIZE)
    save.players = bytearray(PLAYERS_SIZE)
    # 2. script flow writes in story order
    for step in spec['flow']:
        kind = step['kind']
        if kind == 'winfail':
            commands = flow_commands(kind, int(step['level']), step.get('section'))
            for cmd in commands:
                if not apply_write(save, cmd['name'], cmd['args'], symbols):
                    receipt['skipped_tokens'].append(f'{kind}{step["level"]}:{cmd["name"]}')
            receipt['applied_flow'].append(f'{kind}{step["level"]}' + (f':{step["section"]}' if step.get('section') else ''))
        elif kind == 'towndef':
            event = towndef_event(int(step['event']))
            town = int(step['town'])
            for token in event['events']:
                if not apply_write(save, token['token'], token['args'], symbols, self_town=town):
                    pass   # messages, delays, menus: nothing saved
            receipt['applied_flow'].append(f'towndef{step["event"]}@town{town}')
        elif kind == 'writes':
            for name, args in town_job_up_writes(step['file']):
                if not apply_write(save, name, args, symbols):
                    receipt['skipped_tokens'].append(f'writes:{name}')
            receipt['applied_flow'].append(step.get('label', 'writes'))
        else:
            raise ValueError(f'unknown flow step kind {kind}')
    # 3. travelled points / tracks are shown (mode 2, as the reveal 0x4280d0 leaves them)
    shown_points = [int(point) for point in spec.get('shown_points', [])
                    if not save.point_word(int(point), POINT_FLAGS) & BMPM['bmpmHidden']]
    receipt['shown_points'] = shown_points
    receipt['still_hidden_points'] = [int(point) for point in spec.get('shown_points', []) if int(point) not in shown_points]
    for point in shown_points:
        save.set_point_word(point, POINT_MODE, 2)
        save.point_set_flag(point, BMPM['bmpmVisit'])
    for track in route_tracks(shown_points):
        save.set_track_word(track, TRACK_MODE, 2)
    # 4. party: every member's live record is synthesised from its runtime PLAYERS template
    #    (original_save_members); registered slot n holds PLAYERS row n + 1 (0x42cb30 / 0x407eff).
    templates = TemplateTable.load()
    registered: set[int] = set()
    for member in spec['party']:
        code = actor_code(member['actor_id'])
        slot = code - 1
        if not 0 <= slot < 9:
            raise ValueError(f'{spec["name"]}: {member["actor_id"]} is not a party row (001..009)')
        record, entry = synthesize(templates, member)
        save.record(slot)[:] = bytes(record)
        register_slot(save, slot)
        for exchange in entry.get('job_up', []):
            save.set_slot_code(slot, exchange['slot_code'])   # 0x42c700 inside 0x4348f0: the slot takes the up object code
        registered.add(slot)
        entry.update(slot=slot, registered_code=save.slot_code(slot), job_up_ready=job_up_ready(record))
        receipt['party'].append(entry)
    if 0 not in registered:
        raise ValueError(f'{spec["name"]}: 雷歐納德 (001, slot 0) must be in the party (the list row reads his level)')
    # 5. header: standing on the big map at `point`, or entering a level that is not a big-map
    #    point (`entry_level`: the 51 → 52 → 58 → 60 → 53 prologue chain runs through
    #    actSetNextPlayLevelEvent only).
    # 0x427ab3 arrival: a General point runs its event (the level) only while bmpmVisit is clear;
    # a visited one just rolls its encounter ratio, and a load parks the walker without arriving
    # (runtime-measured 2026-09-21: standing on a visited / unvisited 17, clicking it did nothing).
    # So a level preset stands one track away and leaves the level's point shown but unvisited.
    for unvisited in spec.get('unvisited_points', []):
        save.point_clear_flag(int(unvisited), BMPM['bmpmVisit'])
    if 'entry_level' in spec:
        if 'point' in spec:
            raise ValueError(f'{spec["name"]}: entry_level and point are exclusive')
        level_entry_header(save, int(spec['entry_level']))
        point = save.header['current_point']
    else:
        point = int(spec['point'])
        world_map_header(save, point, world_map_point_xy(point))
    save.header['gold'] = int(spec.get('gold', save.header['gold']))
    save.header['leonard_level'] = i32(save.record(0), REC['level'])
    save.header['round_counter'] = 0
    save.header['play_seconds'] = int(spec.get('play_seconds', save.header['play_seconds']))
    for key in ('show_track_point', 'walk_to_point', 'walk_from_point'):
        if key in spec:
            save.header[key] = int(spec[key])
    receipt['header'] = dict(save.header)
    receipt['towns'] = {str(town): {'tree': save.town_tree(town), 'exec_event': save.town_exec_event(town)}
                        for town in spec.get('report_towns', [])}
    receipt['point'] = {'id': point, 'mode': save.point_word(point, POINT_MODE), 'flags': hex(save.point_word(point, POINT_FLAGS)),
                        'event': save.point_word(point, POINT_EVENT)}
    if 'entry_level' in spec:
        receipt['entry_level'] = int(spec['entry_level'])
    receipt['registered_slots'] = {str(slot): hex(save.slot_code(slot) & 0xFFFFFFFF) for slot in range(21) if save.slot_code(slot)}
    return save, receipt


# Main-path story order through chapter 1 into chapter 2 (campaign_overview.md), as flow steps.
CHAPTER1_FLOW = [
    {'kind': 'winfail', 'level': 1, 'section': 'win'},
    {'kind': 'winfail', 'level': 2, 'section': 'win'},
    {'kind': 'winfail', 'level': 3, 'section': 'win'},
    {'kind': 'winfail', 'level': 5, 'section': 'win'},
    {'kind': 'winfail', 'level': 6, 'section': 'win'},
    {'kind': 'towndef', 'event': 23, 'town': 6},
    {'kind': 'towndef', 'event': 30, 'town': 6},
    {'kind': 'winfail', 'level': 7, 'section': 'win'},
    {'kind': 'winfail', 'level': 10, 'section': 'win'},
    {'kind': 'winfail', 'level': 901, 'section': 'win'},
    {'kind': 'towndef', 'event': 43, 'town': 11},
    {'kind': 'towndef', 'event': 138, 'town': 11},
    {'kind': 'winfail', 'level': 12, 'section': 'win'},
    {'kind': 'winfail', 'level': 13, 'section': 'win'},
]

# 0x434680: the town writes the second teCheckJobUp2 success applies. The list lives in the data file
# TownEventRules replays (content/world/town_job_up_writes.json, `hsl check town_job_up_writes`); a
# `writes` flow step reads that file at apply time, so original_save:native_second_tier pins the data
# the remake uses to the native save.
TOWN_JOB_UP_WRITES = ROOT / 'content/world/town_job_up_writes.json'
SECOND_TIER_WRITES_STEP = {'kind': 'writes', 'file': TOWN_JOB_UP_WRITES,
                           'label': '0x434680 second-tier town writes (content/world/town_job_up_writes.json)'}


def town_job_up_writes(path: Path) -> list[tuple[str, list[str]]]:
    """(token, [args...]) of the second_tier block of a hsl_town_job_up_writes.v1 file, in file order."""
    data = json.loads(path.read_text(encoding='utf-8'))
    return [(write['token'], [str(arg) for arg in write['args']]) for write in data['second_tier']['writes']]


# 命運神殿 (town 16) up to the crystal: 薛維斯港 first entry builds the temple tree (TOWNDEF 32), the
# captain reveals point 16 (51), the first entry clears the exec event (53), 老神官二 opens 神殿中樞
# 76 -> {77 祈求, 78} once the party shows 聖水晶 285 (59 -> 60).
TEMPLE_FLOW = [
    {'kind': 'towndef', 'event': 32, 'town': 11},
    {'kind': 'towndef', 'event': 51, 'town': 11},
    {'kind': 'towndef', 'event': 53, 'town': 16},
    {'kind': 'towndef', 'event': 60, 'town': 16},
]

# 0x434770 admits a tier when every base attribute is at least the current job's cap - 50; these
# are exactly the margins for 010 jobSwordMaster (caps 130/112/100/110) and 011 jobPriestMaster
# (96/102/142/112) — the "just enough" second-tier fixture, not a recorded playthrough.
LEONARD_SECOND_TIER_READY = {'str': 80, 'dex': 62, 'mind': 50, 'con': 60}
TINA_SECOND_TIER_READY = {'str': 46, 'dex': 52, 'mind': 92, 'con': 62}
STORY_ITEMS = {'劍之魂': 283, '福音之書': 284}

# Main path through level 36 in campaign order (content/battles/campaign.json): the winfail win
# sections write the point / track / town tables; the town events of chapters 2–3 are not replayed.
MAIN_PATH_TO_37 = CHAPTER1_FLOW + [{'kind': 'winfail', 'level': level, 'section': 'win'}
                                    for level in (15, 17, 18, 19, 21, 22, 24, 26, 28, 29, 30, 31, 32, 33, 34, 36)]

# PLAYERS rows as-is (template levels 1/2/4/7/6, attributes, equipment, items): the same units the
# remake's autoplay sweep starts a registered battle with, so the original's opening rounds can
# be set against the remake's AI trace on equal stats (lane R14; see
# docs/evidence_packets/runtime_observations/original_level17_escort/README.md).
FRESH_PARTY_THROUGH_15 = [{'actor_id': actor_id} for actor_id in ('001', '002', '003', '004', '005')]

PRESETS: dict[str, dict] = {
    'level53_pre_battle': {
        'name': 'level53_pre_battle',
        'claim': '雷歐納德 (001) is registered as his PLAYERS template row after the prologue battles 51 / 52 (WINFAIL051 / 052 '
                 'write no saved table: their win sections are actSetNextPlayLevelEvent only), every other live record is '
                 'zero, and the header holds the words WINFAIL052\'s win leaves behind (actSetNextPlayLevelEvent 58,58: '
                 'next level = level files = 58). The load runs STORY058 -> STORY060 -> level 53 逃出克萊恩城, whose '
                 'obj_Story_Player2 installs 緉娜 from her never-initialised live record, i.e. the PLAYERS 002 row '
                 '(0x407ec0 copies the template while +0x4c..+0x58 are zero). Level 53 is not a big-map point. '
                 '雷歐納德\'s post-52 exp / level is not replayed (template row; he is absent from 53).',
        'entry_level': 58, 'gold': 1000, 'play_seconds': 900,
        'flow': [{'kind': 'winfail', 'level': 51, 'section': 'win'}, {'kind': 'winfail', 'level': 52, 'section': 'win'}],
        'shown_points': [],
        'party': [{'actor_id': '001'}],
        'report_towns': [],
    },
    'level05_pre_battle': {
        'name': 'level05_pre_battle',
        'claim': 'The four members 雷歐納德 / 緹娜 / 琥 / 漢克斯 (001–004) are registered with the levels, exp, base attributes, '
                 'equipment and items the remake chapter autoplay carried into level 5 呼嘯平原 (seed 1 hand-off record, '
                 'lane M1: 001 L7 46/16/8/12, 002 L4 16/11/25/15, 003 L6 24/26/7/20, 004 L7 22/24/12/24), the WINFAIL001 / '
                 '002 / 003 win writes are replayed, the party stands in 自由都市 米蘭多 (point 4) and 呼嘯平原 (point 5, '
                 'bmpmBattle) is shown but unvisited, so walking there runs level 5 natively: STORY005 opens and the '
                 'level installs its enemies. (An entry_level 5 header loads STORY005 with the party but leaves every '
                 'enemy record uninstalled, code 0 L1 1/1, and the first 待機 fires the win section — runtime-measured '
                 '2026-09-23, lane M1.) The party is a fixture copied from the remake run, not a recorded original '
                 'playthrough; 緹娜\'s learned-spell bits stay the PLAYERS 002 template (the remake learned 水剎 at L4).',
        'point': 4, 'unvisited_points': [5], 'gold': 2550, 'play_seconds': 3 * 3600,
        'flow': CHAPTER1_FLOW[:3],
        'shown_points': [1, 2, 3, 4, 5],
        'party': [
            {'actor_id': '001', 'level': 7, 'exp': 222, 'attributes': {'str': 46, 'dex': 16, 'mind': 8, 'con': 12},
             'equipment': [3, 154, 125, 182, 0, 0], 'inventory': [246, 241, 241]},
            {'actor_id': '002', 'level': 4, 'exp': 122, 'attributes': {'str': 16, 'dex': 11, 'mind': 25, 'con': 15},
             'equipment': [83, 152, 122, 181, 201, 0], 'inventory': [241, 244, 241]},
            {'actor_id': '003', 'level': 6, 'exp': 106, 'attributes': {'str': 24, 'dex': 26, 'mind': 7, 'con': 20},
             'equipment': [62, 153, 124, 181, 0, 0], 'inventory': [241, 246, 246, 2, 241, 246]},
            {'actor_id': '004', 'level': 7, 'exp': 103, 'attributes': {'str': 22, 'dex': 24, 'mind': 12, 'con': 24},
             'equipment': [103, 152, 124, 181, 201, 0], 'inventory': [241, 241]},
        ],
        'report_towns': [],
    },
    'level06_pre_battle': {
        'name': 'level06_pre_battle',
        'claim': 'The four members 雷歐納德 / 緹娜 / 琥 / 漢克斯 (001–004) are registered with the levels, exp, base attributes, '
                 'equipment, items and learned skills the remake handed into level 6 席達鎮 (playtest kit memoir_05, the '
                 'user\'s level-6 entry: 001 L8, 002 L5, 003 L7, 004 L8; 緹娜 水剎, 漢克斯 逆刃), the WINFAIL001 / 002 / 003 / '
                 '005 win writes are replayed (WINFAIL005 arms 席達鎮 exec event 19), and the party stands in 席達鎮 '
                 '(point 6, the town menu opens on load) with the tavern still holding 沃斯菲塔士兵 (TOWNDEF 23, '
                 'teSetNextPlayLevelEvent 6,6), so 酒館 -> 沃斯菲塔士兵 runs STORY006 and level 6 natively. The remake '
                 'carried 5 unspent points for 雷歐納德 and 緹娜; the original record has no unspent-point word and the '
                 'install infers the level from the base attributes (0x40e800), so the five points are spent the way the '
                 'remake autoplay spends them (main attribute: 雷歐納德 str, 緹娜 mind) to keep L8 / L5. The party is a '
                 'fixture copied from the remake, not a recorded original playthrough.',
        'point': 6, 'gold': 70, 'play_seconds': 4 * 3600,
        'flow': CHAPTER1_FLOW[:4],
        'shown_points': [1, 2, 3, 4, 5, 6],
        'party': [
            {'actor_id': '001', 'level': 8, 'exp': 11, 'attributes': {'str': 51, 'dex': 16, 'mind': 8, 'con': 12},
             'equipment': [4, 155, 125, 182, 0, 0], 'inventory': [241]},
            {'actor_id': '002', 'level': 5, 'exp': 58, 'attributes': {'str': 16, 'dex': 11, 'mind': 30, 'con': 15},
             'equipment': [83, 152, 122, 181, 201, 0], 'inventory': [241, 241],
             'learned_skills': ['magic:magicWATER:magicCode01']},
            {'actor_id': '003', 'level': 7, 'exp': 335, 'attributes': {'str': 24, 'dex': 31, 'mind': 7, 'con': 20},
             'equipment': [63, 155, 124, 181, 0, 0], 'inventory': [244, 246, 246, 2, 241]},
            {'actor_id': '004', 'level': 8, 'exp': 41, 'attributes': {'str': 27, 'dex': 24, 'mind': 12, 'con': 24},
             'equipment': [103, 152, 124, 181, 201, 0], 'inventory': [241],
             'learned_skills': ['special:magicOTHER:magicCode11']},
        ],
        'report_towns': [6],
    },
    'level02_pre_battle': {
        'name': 'level02_pre_battle',
        'claim': '雷歐納德 (001) and 琥 (003) are registered as their PLAYERS template rows (緹娜 joins inside the level through '
                 'obj_Story_Player2), WINFAIL001 win wrote 歐姆村\'s exec event 9, the party stands in 歐姆村 (point 1) and '
                 '戈爾山道 (point 2) is shown but unvisited, so walking to it runs its event and starts level 2 with '
                 'its EVEF party. '
                 'Levels and gear are the PLAYERS rows, not a recorded playthrough.',
        'point': 1, 'unvisited_points': [2], 'gold': 200, 'play_seconds': 600,
        'flow': CHAPTER1_FLOW[:1],
        'shown_points': [1, 2],
        'party': [{'actor_id': '001'}, {'actor_id': '003'}],
        'report_towns': [1],
    },
    'level17_pre_battle': {
        'name': 'level17_pre_battle',
        'claim': 'The five chapter-1 members 001–005 are registered as their PLAYERS template rows (the remake sweep\'s '
                 'level-17 party), the main-path WINFAIL win writes through 15 are replayed, the party stands in 席達鎮 '
                 '(point 6, the town on 艾瓦台地\'s only travelled track) and 艾瓦台地 (point 17) is shown but unvisited, '
                 'so walking to it runs its event and starts level 17 (escort of 克里夫 064 / the three 062 refugees). '
                 'Levels and gear are the PLAYERS rows, not a recorded '
                 'playthrough.',
        'point': 6, 'unvisited_points': [17], 'gold': 3000, 'play_seconds': 2 * 3600,
        'flow': CHAPTER1_FLOW + [{'kind': 'winfail', 'level': 15, 'section': 'win'}],
        'shown_points': [1, 2, 3, 4, 5, 6, 7, 8, 10, 11, 12, 13, 15, 17],
        'party': FRESH_PARTY_THROUGH_15,
        'report_towns': [],
    },
    'second_tier_at_amphibian_gate': {
        'name': 'second_tier_at_amphibian_gate',
        'claim': '雷歐納德 (001 -> 010 -> 019) and 緹娜 (002 -> 011 -> 020) hold their second titles through the 0x4348f0 '
                 'exchange and stand on the big map at 兩棲族部落 (point 14) after the 0x434680 town writes, which are '
                 'pre-applied by the generator (the native trigger is the before_second_tier_at_temple preset). Levels and '
                 'attributes are a fixture at the second-tier margin, not a recorded playthrough.',
        'point': 14, 'gold': 5000, 'play_seconds': 3600,
        'flow': CHAPTER1_FLOW + TEMPLE_FLOW + [
            # the table writes of the first native success; the second success (80) reaches
            # teCheckTEExist 76/81 with 81 already present and branches to 87 before its writes
            {'kind': 'towndef', 'event': 79, 'town': 16},
            {'kind': 'towndef', 'event': 141, 'town': 14},
            {'kind': 'towndef', 'event': 151, 'town': 14},
            SECOND_TIER_WRITES_STEP,
        ],
        'shown_points': [1, 2, 3, 4, 5, 6, 7, 8, 10, 11, 12, 13, 14, 16],
        'party': [
            {'actor_id': '001', 'level': 41, 'attributes': LEONARD_SECOND_TIER_READY, 'inventory': [241, 241, 246], 'job_up_history': ['010', '019']},
            {'actor_id': '002', 'level': 40, 'attributes': TINA_SECOND_TIER_READY, 'inventory': [241, 244], 'job_up_history': ['011', '020']},
        ],
        'report_towns': [14, 16],
    },
    'before_second_tier_at_temple': {
        'name': 'before_second_tier_at_temple',
        'claim': '雷歐納德 (010 劍豪) and 緹娜 (011 神官) hold their first titles, every base attribute sits exactly at the '
                 '0x434770 margin (cap - 50) of the second tier, 雷歐納德 carries 劍之魂 283 and 緹娜 福音之書 284, 神殿中樞 76 '
                 'is open after the crystal event 60, and the party stands on the big map at 命運神殿 (point 16): entering '
                 '神殿中樞 -> 祈求 -> a member runs TOWNDEF 69/70 -> 79/80 -> teCheckJobUp2 natively; the second success runs '
                 '0x434680. 琥 / 漢克斯 / 雪拉 ride along with their first titles; levels are a fixture.',
        'point': 16, 'gold': 8000, 'play_seconds': 4 * 3600,
        'flow': CHAPTER1_FLOW + TEMPLE_FLOW,
        'shown_points': [1, 2, 3, 4, 5, 6, 7, 8, 10, 11, 12, 13, 14, 16],
        'party': [
            {'actor_id': '001', 'level': 41, 'attributes': LEONARD_SECOND_TIER_READY, 'inventory': [STORY_ITEMS['劍之魂'], 241, 241, 246], 'job_up_history': ['010']},
            {'actor_id': '002', 'level': 40, 'attributes': TINA_SECOND_TIER_READY, 'inventory': [STORY_ITEMS['福音之書'], 241, 244], 'job_up_history': ['011']},
            {'actor_id': '003', 'level': 35, 'job_up_history': ['012']},
            {'actor_id': '004', 'level': 35, 'job_up_history': ['013']},
            {'actor_id': '005', 'level': 33, 'job_up_history': ['014']},
        ],
        'report_towns': [14, 16],
    },
    'after_second_tier_at_temple': {
        'name': 'after_second_tier_at_temple',
        'claim': 'The state the original wrote (HSL_second_tier_native.SAV) after before_second_tier_at_temple ran 神殿中樞 -> '
                 '祈求 -> 雷歐納德 (69 -> 79, teCheckJobUp2 劍豪 -> 終焉劍使) and 緹娜 (70 -> 80, 神官 -> 聖主) natively: both '
                 'records went through the 0x4348f0 second-tier exchange, the story items 283 / 284 are consumed, the '
                 'registered slots hold the up object codes 818 / 819, event 79 rewrote 命運神殿 (76 -> {77, 81}, 55 -> '
                 '{85, 57, 86}) and 0x434680 rewrote 兩棲族部落. The party stands on the big map at point 16.',
        'point': 16, 'gold': 8000, 'play_seconds': 15275,
        'flow': CHAPTER1_FLOW + TEMPLE_FLOW + [
            # 80's table writes never run: its teCheckTEExist 76/81 finds 81 (written by 79) and branches to 87
            {'kind': 'towndef', 'event': 79, 'town': 16},
            SECOND_TIER_WRITES_STEP,
        ],
        'shown_points': [1, 2, 3, 4, 5, 6, 7, 8, 10, 11, 12, 13, 14, 16],
        'party': [
            {'actor_id': '001', 'level': 41, 'attributes': LEONARD_SECOND_TIER_READY, 'inventory': [241, 241, 246], 'job_up_history': ['010', '019']},
            {'actor_id': '002', 'level': 40, 'attributes': TINA_SECOND_TIER_READY, 'inventory': [241, 244], 'job_up_history': ['011', '020']},
            {'actor_id': '003', 'level': 35, 'job_up_history': ['012']},
            {'actor_id': '004', 'level': 35, 'job_up_history': ['013']},
            {'actor_id': '005', 'level': 33, 'job_up_history': ['014']},
        ],
        'report_towns': [14, 16],
    },
    'level37_pre_jobup': {
        'name': 'level37_pre_jobup',
        'claim': 'The nine party rows 001–009 are registered (咕嚕 008 among them, still his base row so WINFAIL037 can run '
                 'actPlayerJobUpProcess natively), 001–007 hold their first titles, and the party stands on 古代神殿遺跡 '
                 '(point 37) with walk_to_point 37 so the load arrives at the point and its event 37 starts the level. '
                 'Only the winfail table writes of the main path through 36 are replayed; chapter 2–3 town events, member '
                 'levels and attributes are a fixture (provisional).',
        'point': 37, 'gold': 12000, 'play_seconds': 8 * 3600,
        'flow': MAIN_PATH_TO_37,
        'shown_points': list(range(1, 38)),
        'party': [
            {'actor_id': '001', 'level': 36, 'attributes': LEONARD_SECOND_TIER_READY, 'inventory': [241, 241, 246], 'job_up_history': ['010']},
            {'actor_id': '002', 'level': 35, 'attributes': TINA_SECOND_TIER_READY, 'inventory': [241, 244], 'job_up_history': ['011']},
            {'actor_id': '003', 'level': 34, 'job_up_history': ['012']},
            {'actor_id': '004', 'level': 34, 'job_up_history': ['013']},
            {'actor_id': '005', 'level': 33, 'job_up_history': ['014']},
            {'actor_id': '006', 'level': 33, 'job_up_history': ['015']},
            {'actor_id': '007', 'level': 33, 'job_up_history': ['016']},
            {'actor_id': '008', 'level': 32},
            {'actor_id': '009', 'level': 32},
        ],
        'report_towns': [],
    },
}


def load_sample() -> OriginalSave:
    if not SAMPLE.exists():
        raise NotGeneratable(f'sample save missing: {SAMPLE}')
    return OriginalSave.parse(SAMPLE.read_bytes())


def sample_summary(save: OriginalSave, raw: bytes) -> dict:
    return {
        'schema': 'hsl_original_save_sample.v1',
        'evidence_tier': 'resource-derived',
        'file': SAMPLE.name, 'bytes': len(raw), 'sha256': __import__('hashlib').sha256(raw).hexdigest(),
        'origin': 'HSLBAT.SAV written by the original (v1.06, Wine) from the battle scroll 儲存戰場記錄 at 雷歐納德\'s first action menu of level 51 (2026-09-21)',
        'header': {name: value for name, value in save.header.items()},
        'registered_slots': {str(slot): save.slot_code(slot) for slot in range(21) if save.slot_code(slot)},
        'mode_bytes_set': [index for index, value in enumerate(save.mode_bytes) if value],
        'live_records_nonzero': [index for index in range(RECORD_COUNT) if any(save.players[index * RECORD_SIZE:(index + 1) * RECORD_SIZE])],
        'lists': [{'capacity': capacity, 'count': count} for capacity, count, _ in save.lists],
        'encounter_ratios_all': sorted({struct.unpack_from('<H', save.ratios, i * 2)[0] for i in range(100)}),
        'towns_nonempty': {str(town): save.town_tree(town) for town in range(100) if save.town_tree(town)['0']},
        'points_hidden_by_new_game': [p for p in range(100) if save.point_word(p, POINT_FLAGS) & BMPM['bmpmHidden']],
        'tracks_hidden': [t for t in range(100) if save.track_word(t, TRACK_FLAGS) & BMPM['bmpmHidden']],
        'battle_tail_bytes': len(save.battle_tail or b''),
    }


def roundtrip_sample() -> str:
    raw = SAMPLE.read_bytes()
    save = OriginalSave.parse(raw)
    again = save.serialize()
    if again != raw:
        first = next((i for i, (a, b) in enumerate(zip(raw, again)) if a != b), min(len(raw), len(again)))
        raise ValueError(f'sample round trip differs at byte {first} (lengths {len(raw)} vs {len(again)})')
    summary = sample_summary(save, raw)
    tracked = json.loads(SAMPLE_SUMMARY.read_text()) if SAMPLE_SUMMARY.exists() else None
    if tracked != summary:
        raise ValueError('sample summary JSON is stale; regenerate with hsl generate original_save:sample')
    return f'ORIGINAL_SAVE_CHECK_PASS bytes={len(raw)} blocks=10 battle_tail={len(save.battle_tail or b"")} version={save.header["version"]}'


class SampleTask(ScriptCheckTask):
    name = 'original_save:sample'
    family = 'original_save'
    inputs = (SAMPLE.relative_to(ROOT).as_posix(),)
    outputs = (SAMPLE_SUMMARY.relative_to(ROOT).as_posix(),)
    scripts = ('tools/hsltools/data/original_save.py', 'tools/hsltools/data/_original_save_codec.py')

    def verify(self, ctx: Context) -> None:
        print(roundtrip_sample())

    def build(self, ctx: Context) -> None:
        raw = SAMPLE.read_bytes()
        SAMPLE_SUMMARY.write_bytes(json_bytes(sample_summary(OriginalSave.parse(raw), raw)))


def native_second_tier_summary(save: OriginalSave, raw: bytes) -> dict:
    summary = sample_summary(save, raw)
    summary.update({
        'schema': 'hsl_original_save_native_second_tier.v1', 'evidence_tier': 'runtime-measured', 'file': NATIVE_SECOND_TIER.name,
        'origin': '儲存回憶錄 written by the original (v1.06, Wine, 2026-09-21) on the big map at 命運神殿 after the generated '
                  'before_second_tier_at_temple 回憶錄 was loaded and 神殿中樞 -> 祈求 ran teCheckJobUp2 for 雷歐納德 and 緹娜',
        'generator_preset': NATIVE_SECOND_TIER_PRESET, 'header_words_not_compared': list(STANDING_HEADER_WORDS),
        'slots_not_compared': {'slots': list(UNTOUCHED_NATIVE_SLOTS),
                               'reason': 'slot codes and records are untouched before-preset input as generated on 2026-09-21 '
                                         '(800 + slot codes, dword-summed +0x194); the generator now follows 0x4348f0 / 0x42c700 for them'},
        'party': [{'slot': slot, 'registered_code': save.slot_code(slot), 'job': i32(save.record(slot), REC['job']),
                   'job_up_code': i32(save.record(slot), REC['job_up_code']), 'job_up_flags': hex(u32(save.record(slot), REC['job_up_flags'])),
                   'level': i32(save.record(slot), REC['level']), 'max_hp': i32(save.record(slot), REC['max_hp']),
                   'items': [i32(save.record(slot), REC['items'] + 4 * i) for i in range(8) if i32(save.record(slot), REC['items'] + 4 * i)]}
                  for slot in range(5)],
    })
    return summary


def compare_native_second_tier() -> str:
    """The native 回憶錄 against the generated after-preset: same header but the standing words,
    then every table byte for byte (slot codes, mode bytes, all 201 records, lists, ratios, towns,
    points, tracks)."""
    raw = NATIVE_SECOND_TIER.read_bytes()
    native = OriginalSave.parse(raw)
    if native.serialize() != raw:
        raise ValueError('native second-tier save does not round-trip')
    generated, _ = apply_spec(load_sample(), PRESETS[NATIVE_SECOND_TIER_PRESET])
    for key, value in native.header.items():
        if key not in STANDING_HEADER_WORDS and generated.header.get(key) != value:
            raise ValueError(f'header {key}: generated {generated.header.get(key)} != native {value}')
    # The run rewrote slots 0 / 1 only: 0x4348f0 + 0x448840 rebuilt their records and 0x42c700
    # moved their slot codes 800 / 801 -> 818 / 819. Slots 2-4 still hold what the before-preset
    # was generated with at the time (800 + slot codes, dword-summed +0x194); the generator has
    # since adopted 0x4348f0's static reading for them, so those bytes are preset input in the
    # native file, not evidence, and are skipped.
    for slot in (0, 1):
        if native.slot_code(slot) != generated.slot_code(slot):
            raise ValueError(f'slot {slot} code: generated {generated.slot_code(slot)} != native {native.slot_code(slot)}')
        if bytes(native.record(slot)) != bytes(generated.record(slot)):
            first = next(i for i in range(RECORD_SIZE) if native.record(slot)[i] != generated.record(slot)[i])
            raise ValueError(f'slot {slot} record differs from the native save at offset {first:#x}')
    for slot in UNTOUCHED_NATIVE_SLOTS:
        if native.slot_code(slot) != 800 + slot:
            raise ValueError(f'slot {slot} code in the native save is {native.slot_code(slot)}, expected the before-preset input {800 + slot}')
    for index in range(RECORD_COUNT):
        if index - 1 in (0, 1) or index - 1 in UNTOUCHED_NATIVE_SLOTS:
            continue
        if native.players[index * RECORD_SIZE:(index + 1) * RECORD_SIZE] != generated.players[index * RECORD_SIZE:(index + 1) * RECORD_SIZE]:
            raise ValueError(f'record index {index} differs from the native save')
    for table in ('mode_bytes', 'ratios', 'towns', 'points', 'tracks'):
        ours, theirs = bytes(getattr(generated, table)), bytes(getattr(native, table))
        if ours != theirs:
            first = next(i for i in range(min(len(ours), len(theirs))) if ours[i] != theirs[i])
            detail = f' (record {first // RECORD_SIZE} offset {first % RECORD_SIZE:#x})' if table == 'players' else ''
            raise ValueError(f'{table} differs from the native save at byte {first}{detail}')
    if generated.lists != native.lists:
        raise ValueError('item lists differ from the native save')
    summary = native_second_tier_summary(native, raw)
    tracked = json.loads(NATIVE_SECOND_TIER_SUMMARY.read_text()) if NATIVE_SECOND_TIER_SUMMARY.exists() else None
    if tracked != summary:
        raise ValueError('native second-tier summary JSON is stale; regenerate with hsl generate original_save:native_second_tier')
    return (f'ORIGINAL_SAVE_NATIVE_SECOND_TIER_PASS bytes={len(raw)} preset={NATIVE_SECOND_TIER_PRESET} '
            f'slots={native.slot_code(0)},{native.slot_code(1)} tables=5')


class NativeSecondTierTask(ScriptCheckTask):
    name = 'original_save:native_second_tier'
    family = 'original_save'
    inputs = (NATIVE_SECOND_TIER.relative_to(ROOT).as_posix(), SAMPLE.relative_to(ROOT).as_posix(),
              TEMPLATES_BIN.relative_to(ROOT).as_posix(), BIG_MAP_FLOW.relative_to(ROOT).as_posix(),
              TOWNDEF.relative_to(ROOT).as_posix(), TOWN_JOB_UP_WRITES.relative_to(ROOT).as_posix(),
              'content/imported/hsl/global/tables/')
    outputs = (NATIVE_SECOND_TIER_SUMMARY.relative_to(ROOT).as_posix(),)
    scripts = ('tools/hsltools/data/original_save.py', 'tools/hsltools/data/original_save_members.py',
               'tools/hsltools/data/_original_save_codec.py')

    def verify(self, ctx: Context) -> None:
        print(compare_native_second_tier())

    def build(self, ctx: Context) -> None:
        raw = NATIVE_SECOND_TIER.read_bytes()
        NATIVE_SECOND_TIER_SUMMARY.write_bytes(json_bytes(native_second_tier_summary(OriginalSave.parse(raw), raw)))


class PresetTask(GeneratedFilesTask):
    family = 'original_save'
    inputs = (SAMPLE.relative_to(ROOT).as_posix(), BIG_MAP_FLOW.relative_to(ROOT).as_posix(), TOWNDEF.relative_to(ROOT).as_posix(),
              TOWN_JOB_UP_WRITES.relative_to(ROOT).as_posix(), 'content/imported/hsl/global/tables/')
    scripts = ('tools/hsltools/data/original_save.py', 'tools/hsltools/data/_original_save_codec.py')

    def __init__(self, preset: str) -> None:
        self.preset = preset
        self.name = f'original_save:{preset}'
        self.outputs = ((OUT / f'{preset}.SAV').relative_to(ROOT).as_posix(), (OUT / f'{preset}.json').relative_to(ROOT).as_posix())

    def render(self, ctx: Context) -> dict[str, bytes]:
        save, receipt = apply_spec(load_sample(), PRESETS[self.preset])
        raw = save.serialize()
        check = OriginalSave.parse(raw)   # the generated file must read back through the same codec
        if check.serialize() != raw:
            raise CheckFailed(f'{self.name}: generated save does not round-trip')
        receipt['bytes'] = len(raw)
        receipt['sha256'] = __import__('hashlib').sha256(raw).hexdigest()
        receipt['claim'] = PRESETS[self.preset]['claim']
        receipt['evidence_tier'] = 'provisional'
        receipt['install'] = 'copy to <hsl>/SAVES/HSL00.SAV (the first 回憶錄 slot); load in-game via 讀取回憶錄 from any battle or the big map'
        return {self.outputs[0]: raw, self.outputs[1]: json_bytes(receipt)}

    def summary(self, rendered: dict[str, bytes], mode: str) -> str:
        receipt = json.loads(rendered[self.outputs[1]])
        where = f'entry_level={receipt["entry_level"]}' if 'entry_level' in receipt else f'point={receipt["point"]["id"]}'
        return (f'ORIGINAL_SAVE_PRESET_PASS name={self.preset} bytes={receipt["bytes"]} {where} '
                f'slots={",".join(receipt["registered_slots"])} flow={len(receipt["applied_flow"])}')


def tasks() -> list:
    return [SampleTask(), NativeSecondTierTask()] + [PresetTask(name) for name in PRESETS]


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--state', choices=sorted(PRESETS), help='preset to generate')
    parser.add_argument('--out', type=Path, help='directory for HSL00.SAV (+ receipt JSON); default prints the receipt only')
    parser.add_argument('--slot', type=int, default=0, help='回憶錄 slot number for the file name HSLnn.SAV')
    parser.add_argument('--dump', type=Path, help='parse this .SAV and print its summary')
    args = parser.parse_args()
    if args.dump:
        raw = args.dump.read_bytes()
        save = OriginalSave.parse(raw)
        print(json.dumps(sample_summary(save, raw), ensure_ascii=False, indent=2))
        return 0
    if not args.state:
        print(roundtrip_sample())
        return 0
    save, receipt = apply_spec(load_sample(), PRESETS[args.state])
    raw = save.serialize()
    if args.out:
        args.out.mkdir(parents=True, exist_ok=True)
        target = args.out / f'HSL{args.slot:02d}.SAV'
        target.write_bytes(raw)
        (args.out / f'{args.state}.json').write_bytes(json_bytes(receipt))
        print(f'wrote {target} ({len(raw)} bytes)')
    else:
        print(json.dumps(receipt, ensure_ascii=False, indent=2))
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
