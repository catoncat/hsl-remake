"""Live actor records (0x1fc bytes, `*0x4c1bc8`) for party members of a generated 回憶錄.

The original builds every live record by copying the parsed PLAYERS.TXT template of the same
code (`0x44cb10(index, 1)` from the template table `*0x4c1afc`) and then refreshing the derived
layer (`0x448840`). The template table was dumped once from the running original
(`hsl_win32_memread.exe --read-bytes`, see original_save_format.md) and is tracked as
`PLAYERS_templates_runtime.bin`: 66 records, one per PLAYERS.TXT row, in code order.

Synthesis mirrors that order: template copy → player-only install words → level / attributes /
exp / inventory / equipment from the spec (carry vocabulary: actor_id, level, exp, attributes,
inventory, equipment, job_up_history) → the `0x4348f0` job-up exchange per history entry →
`0x448840` refresh through the proven job model (hsltools.model.jobs.calculate).

Registry task `original_save:members` proves the tracked template dump against PLAYERS.TXT, the
job model (every template's derived layer re-derives byte for byte) and the resource-handle
rule, and that `synthesize('001')` equals 雷歐納德's live record in the tracked HSLBAT sample.
"""
from __future__ import annotations

import hashlib
import json
import os
import struct
from pathlib import Path

from hsltools.data import json_bytes
from hsltools.data.equipment import build as equipment_data
from hsltools.model.jobs import ATTRIBUTES, CAPS, calculate
from hsltools.paths import ROOT
from hsltools.registry import CheckFailed, Context, NotGeneratable, ScriptCheckTask, original_archive
from hsltools.sources.tables import TABLES, blocks

PACKET_DIR = ROOT / 'docs/evidence_packets/static_reverse/original_save_format'
TEMPLATES_BIN = PACKET_DIR / 'PLAYERS_templates_runtime.bin'
TEMPLATES_SUMMARY = PACKET_DIR / 'PLAYERS_templates_runtime.json'
OBJ_ALL_H = TABLES / 'OBJ-ALL.H'
TYPE_H = TABLES / 'TYPE.H'
RESOURCE_H = TABLES / 'resource.h'
DUMP_ENV = 'HSL_ORIGINAL_MEMORY_DUMP'   # hsl_win32_memread JSON with a `templates` --read-bytes read

RECORD_SIZE = 0x1FC
RECORD_COUNT = 201

# Live actor record fields (byte offsets; original_save_format.md field table).
REC = {
    'code': 0x00, 'name_id': 0x04, 'sound_walk_dead': 0x08, 'sound_miss_attack': 0x0C, 'sound_hit_walkwater': 0x10,
    'dead_message': 0x14, 'job': 0x18, 'job_show_name': 0x1C, 'class_shoothit': 0x20, 'mode': 0x28,
    'size_carry': 0x2C, 'str': 0x4C, 'dex': 0x50, 'mind': 0x54, 'con': 0x58, 'face': 0x5C, 'job_up_code': 0x60,
    'base_str': 0x64, 'base_dex': 0x68, 'base_mind': 0x6C, 'base_con': 0x70,
    'cap_str': 0x74, 'cap_dex': 0x78, 'cap_mind': 0x7C, 'cap_con': 0x80, 'install_code': 0x84, 'exp': 0x88,
    'exp_threshold': 0x8C, 'kill_exp': 0x90, 'gold': 0x98, 'level': 0x9C, 'capability_flags': 0xA0,
    'defense': 0xB4, 'speed': 0xB8, 'hit_ratio': 0xBC, 'attack': 0xC0, 'weapon_magic_type': 0xC4, 'magic_attack': 0xD0,
    'hp': 0xD8, 'max_hp': 0xDC, 'mp': 0xE0, 'max_mp': 0xE4, 'stamina': 0xE8,
    'weapon': 0xEC, 'head': 0xF0, 'armor': 0xF4, 'foot': 0xF8, 'other1': 0xFC, 'other2': 0x100,
    'resist_work': 0x104, 'resist_base': 0x118, 'move_work': 0x12C, 'move': 0x130, 'job_up_flags': 0x134,
    'items': 0x138, 'special_words': 0x158, 'magic_words': 0x174, 'effect_flags': 0x18C,
    'add_steal': 0x194, 'add_avoid': 0x198, 'add_attack_back': 0x19C, 'add_damagex2': 0x1A0, 'add_attack': 0x1A4,
    'add_magic': 0x1A8, 'add_defense': 0x1AC, 'add_speed': 0x1B0, 'add_mp_hp': 0x1B4,
}
EQUIPMENT_SLOTS = ('weapon', 'head', 'armor', 'foot', 'other1', 'other2')
ITEM_SLOTS = 8
JOB_UP_FIRST_TIER = 0x80000000
JOB_UP_SECOND_TIER = 0x40000000
RESIST_CAP = 80
MOVE_CAP = 12
STEAL_WORK_DEFAULT = 12   # 0x448840: +0x196 = +0x194 word, 12 when that word is 0
NO_MAGIC_FLAG = 0x4000    # 0x448840: +0x18c |= 0x4000 when the six magic words are 0 (then MP = 0)
# 0x448420(record, item != 0): +0x18c |= item flag word, then the record's +0xa0 capability bits
# map onto +0x18c. The item flag word is rebuilt from the ITEM.TXT booleans equipment.py already
# names plus the three bits the 66 runtime templates pin (action_twice 0x8, double_attack 0x8000,
# mp_auto_restore 0x200); an equipped item with any other boolean set has no proven bit and fails.
CAPABILITY_TO_EFFECT = {0x40: 0x800000, 0x200: 0x8000, 0x400: 0x1000, 0x800: 0x4000000,
                        0x1000: 0x1000000, 0x2000: 0x2000000, 0x4000: 0x40}
ITEM_FLAG_BOOLEANS = {'action_twice': 0x8, 'double_attack': 0x8000, 'mp_auto_restore': 0x200}
ITEM_UNPROVEN_BOOLEANS = ('mp_use_half', 'hp_auto_restore', 'hp_transfer_mp', 'experience_double',
                          'gold_double', 'move_magic_use', 'add_attack_range')
# 0x407ec0 writes the install-time dead-message word of a player member; the tracked HSLBAT
# sample shows 304 << 16 (RESOURCE 304, the generic dying line) on 雷歐納德. Other members are
# not observed (provisional): the constructor rewrites the word at the next install anyway.
PLAYER_DEAD_MESSAGE_WORD = 304 << 16
PM_PLAYER = 0x10000

# Resource-handle words of a record: (field, half, PLAYERS.TXT column, pool). The handle of a
# WAV is 1 + its index in the case-insensitive sort of the PAK's `@:\wav\` names (0 = none);
# the handle of a picture is its index in the case-insensitive sort of every `*.shp` PAK name.
HANDLE_WORDS = (
    ('sound_walk_dead', 'lo', 'sound_walk', 'wav'), ('sound_walk_dead', 'hi', 'sound_dead', 'wav'),
    ('sound_miss_attack', 'lo', 'sound_miss', 'wav'), ('sound_miss_attack', 'hi', 'sound_attack', 'wav'),
    ('sound_hit_walkwater', 'lo', 'sound_hit', 'wav'), ('sound_hit_walkwater', 'hi', 'sound_walkwater', 'wav'),
    ('class_shoothit', 'hi', 'sound_shoothit', 'wav'), ('face', 'u32', 'picture', 'shp'),
)


def u32(data, offset: int) -> int:
    return struct.unpack_from('<I', data, offset)[0]


def i32(data, offset: int) -> int:
    return struct.unpack_from('<i', data, offset)[0]


def u16(data, offset: int) -> int:
    return struct.unpack_from('<H', data, offset)[0]


def i16(data, offset: int) -> int:
    return struct.unpack_from('<h', data, offset)[0]


def put32(data, offset: int, value: int) -> None:
    struct.pack_into('<I', data, offset, value & 0xFFFFFFFF)


def put16(data, offset: int, value: int) -> None:
    struct.pack_into('<H', data, offset, value & 0xFFFF)


def _defines(path: Path) -> dict[str, int]:
    out: dict[str, int] = {}
    for line in path.read_bytes().decode('cp950', errors='replace').splitlines():
        parts = line.split()
        if len(parts) >= 3 and parts[0] == '#define':
            try:
                out[parts[1]] = int(parts[2], 0)
            except ValueError:
                pass
    return out


def players_rows() -> dict[int, dict[str, str]]:
    return {int(row['code']): row for row in blocks((TABLES / 'PLAYERS.TXT').read_bytes(), 'character')}


def actor_code(actor_id: str | int) -> int:
    """Carry vocabulary actor_id ('001') or a PLAYERS code (1) -> the PLAYERS code."""
    return int(str(actor_id), 10)


# --- the template table ------------------------------------------------------------------------

class TemplateTable:
    """The parsed PLAYERS.TXT templates as the original holds them (`*0x4c1afc`), by code."""

    def __init__(self, records: dict[int, bytes]) -> None:
        self.records = records

    @classmethod
    def load(cls) -> 'TemplateTable':
        if not TEMPLATES_BIN.exists() or not TEMPLATES_SUMMARY.exists():
            raise NotGeneratable(f'template dump missing: {TEMPLATES_BIN}')
        summary = json.loads(TEMPLATES_SUMMARY.read_text())
        raw = TEMPLATES_BIN.read_bytes()
        codes = summary['codes']
        if len(raw) != len(codes) * RECORD_SIZE:
            raise ValueError(f'{TEMPLATES_BIN.name} is {len(raw)} bytes, expected {len(codes)} x {RECORD_SIZE}')
        return cls({code: raw[i * RECORD_SIZE:(i + 1) * RECORD_SIZE] for i, code in enumerate(codes)})

    @classmethod
    def from_dump(cls, dump: dict) -> 'TemplateTable':
        read = next(r for r in dump['reads'] if r['name'] == 'templates')
        if read['status'] != 'ok' or read['size'] != RECORD_SIZE * RECORD_COUNT:
            raise ValueError('dump read `templates` is not a complete 201 x 0x1fc table')
        table = bytes.fromhex(read['hex'])
        records = {}
        for index in range(RECORD_COUNT):
            record = table[index * RECORD_SIZE:(index + 1) * RECORD_SIZE]
            if any(record):
                if u32(record, REC['code']) != index:
                    raise ValueError(f'template index {index} carries code {u32(record, 0)}')
                records[index] = record
        return cls(records)

    def record(self, code: int) -> bytearray:
        if code not in self.records:
            raise KeyError(f'no PLAYERS template for code {code}')
        return bytearray(self.records[code])

    def serialize(self) -> bytes:
        return b''.join(self.records[code] for code in sorted(self.records))


# --- 0x448840 refresh through the proven job model -----------------------------------------------

def record_profile(record) -> dict:
    """The refresh inputs 0x448840 reads from the record itself (job, mode, the additive layer)."""
    return {
        'model': 'native_job_stats_v1', 'job_code': i32(record, REC['job']),
        'source': {
            'attack_power': i32(record, REC['add_attack']), 'magic_attack_power': i32(record, REC['add_magic']),
            'defense': i32(record, REC['add_defense']), 'speed': i32(record, REC['add_speed']),
            # the +0x1b4 pair is signed (PLAYERS 066 declares hit_point -10000)
            'hit_point': i16(record, REC['add_mp_hp'] + 2), 'magic_point': i16(record, REC['add_mp_hp']),
            'avoid_hit_ratio': u16(record, REC['add_avoid']), 'attack_back': u16(record, REC['add_attack_back']),
            'attack_damagex2': u16(record, REC['add_damagex2']), 'mode': u32(record, REC['mode']),
            'has_magic': any(u32(record, REC['magic_words'] + 4 * i) for i in range(6)),
            'base_resist_by_type': {str(i): i32(record, REC['resist_base'] + 4 * i) for i in range(5)},
        },
    }


def item_flag_word(item: dict, code: int) -> int:
    """The ITEM row's flag word that 0x448420 ORs into +0x18c of the wearer."""
    unproven = [key for key in ITEM_UNPROVEN_BOOLEANS if item[key]] + (['magic_hit_bonus'] if item['magic_hit_bonus'] else [])
    if unproven:
        raise ValueError(f'item {code} sets {unproven}: its +0x18c bit is not proven, the record cannot be synthesised')
    return (item['weapon_effect_flags'] | item['status_effect_flags'] | item['stamina_effect_flags']
            | sum(bit for key, bit in ITEM_FLAG_BOOLEANS.items() if item[key]))


def effect_flags(record, gear: list[int], items: dict) -> int:
    """+0x18c as 0x448840 rebuilds it: per equipped item 0x448420 ORs the item flag word and the
    +0xa0 capability map; the no-magic bit closes the refresh."""
    flags = 0
    capability = u32(record, REC['capability_flags'])
    for code in gear:
        if code:
            flags |= item_flag_word(items[str(code)], code)
            flags |= sum(bit for mask, bit in CAPABILITY_TO_EFFECT.items() if capability & mask)
    if not any(u32(record, REC['magic_words'] + 4 * i) for i in range(6)):
        flags |= NO_MAGIC_FLAG
    return flags


def refresh_record(record) -> dict:
    """0x448840(record): caps from the job row, the derived layer, clamped current HP / MP."""
    profile = record_profile(record)
    attrs = {key: i32(record, REC['base_' + key]) for key in ATTRIBUTES}
    gear = [i32(record, REC[slot]) for slot in EQUIPMENT_SLOTS]
    items = equipment_data()['items']
    result = calculate(profile, attrs, i32(record, REC['level']), gear, items,
                       i32(record, REC['hp']), i32(record, REC['mp']), i32(record, REC['move']))
    put32(record, REC['effect_flags'], effect_flags(record, gear, items))
    put16(record, REC['add_steal'] + 2, u16(record, REC['add_steal']) or STEAL_WORK_DEFAULT)
    for index, cap in enumerate(CAPS[profile['job_code']]):
        put32(record, REC['cap_str'] + 4 * index, cap)
    for field, key in (('max_hp', 'max_hp'), ('max_mp', 'max_mp'), ('hp', 'current_hp'), ('mp', 'current_mp'),
                       ('attack', 'attack'), ('defense', 'defense'), ('speed', 'speed'), ('hit_ratio', 'hit_rate'),
                       ('magic_attack', 'magic_attack'), ('move_work', 'move_point'), ('exp_threshold', 'exp_threshold')):
        put32(record, REC[field], result[key])
    for index in range(5):
        put32(record, REC['resist_work'] + 4 * index, result['resist_by_type'][str(index)])
    for field, key in (('add_avoid', 'avoid_hit_ratio'), ('add_attack_back', 'attack_back'), ('add_damagex2', 'attack_damagex2')):
        put16(record, REC[field] + 2, result[key])
    return result


# --- 0x4348f0 job-up exchange ------------------------------------------------------------------

def job_up_exchange(record, target: bytes, flag: int) -> dict:
    """0x4348f0(code, flag) with the PLAYERS template of the resolved job-up code as `target`
    (original_town_job_up.md field table), followed by the 0x448840 refresh. The returned
    `slot_code` is the up object code 0x42c700 writes into the member's registered slot."""
    from_code = i32(record, REC['code'])
    slot_code = i32(record, REC['job_up_code'])
    for field in ('sound_walk_dead', 'sound_miss_attack', 'sound_hit_walkwater', 'dead_message'):
        if u32(target, REC[field]):
            put32(record, REC[field], u32(target, REC[field]))
    for field in ('job', 'job_show_name'):
        put32(record, REC[field], u32(target, REC[field]))
    for half in (0, 2):
        if u16(target, REC['class_shoothit'] + half):
            put16(record, REC['class_shoothit'] + half, u16(target, REC['class_shoothit'] + half))
    for field in ('size_carry', 'face', 'job_up_code'):
        put32(record, REC[field], u32(target, REC[field]))
    if u32(target, REC['weapon']):
        put32(record, REC['weapon'], u32(target, REC['weapon']))
    for index in range(5):
        offset = REC['resist_base'] + 4 * index
        put32(record, offset, min(RESIST_CAP, i32(record, offset) + i32(target, offset)))
    put32(record, REC['move'], min(MOVE_CAP, i32(record, REC['move']) + i32(target, REC['move'])))
    # +0x194..+0x1a0 add only their low words (the high words are 0x448840 work values);
    # +0x1a4..+0x1b4 add whole dwords.
    for field in ('add_steal', 'add_avoid', 'add_attack_back', 'add_damagex2'):
        put16(record, REC[field], (u16(record, REC[field]) + u16(target, REC[field])) & 0xFFFF)
    for offset in range(REC['add_attack'], REC['add_mp_hp'] + 4, 4):
        put32(record, offset, (u32(record, offset) + u32(target, offset)) & 0xFFFFFFFF)
    put32(record, REC['job_up_flags'], u32(record, REC['job_up_flags']) | flag)
    put32(record, REC['capability_flags'], u32(target, REC['capability_flags']))
    refresh_record(record)
    return {'from_code': from_code, 'to_code': i32(target, REC['code']), 'job': i32(record, REC['job']),
            'job_up_code': i32(record, REC['job_up_code']), 'slot_code': slot_code, 'flag': hex(flag)}


# --- member synthesis --------------------------------------------------------------------------

def synthesize(templates: TemplateTable, member: dict) -> tuple[bytearray, dict]:
    """A party member's live record from its PLAYERS template and a carry-vocabulary spec:
    actor_id, level, exp, attributes {str,dex,mind,con}, inventory [item codes], equipment
    [6 codes], job_up_history [target actor ids, first = first tier, second = second tier],
    learned_skills [remake skill ids learned after the template, OR-ed into the learner bit words]."""
    code = actor_code(member['actor_id'])
    record = templates.record(code)
    if u32(record, REC['mode']) != PM_PLAYER:
        raise ValueError(f'PLAYERS row {code:03d} is not a pmPlayer template (mode {u32(record, REC["mode"]):#x})')
    put32(record, REC['dead_message'], PLAYER_DEAD_MESSAGE_WORD)
    receipt: dict = {'actor_id': f'{code:03d}', 'template': 'PLAYERS_templates_runtime.bin'}
    if 'level' in member:
        put32(record, REC['level'], int(member['level']))
    if 'exp' in member:
        put32(record, REC['exp'], int(member['exp']))
    for key, value in member.get('attributes', {}).items():
        if key not in ATTRIBUTES:
            raise ValueError(f'unknown attribute {key}')
        put32(record, REC['base_' + key], int(value))
        put32(record, REC[key], int(value))
    if 'inventory' in member:
        items = [int(item) for item in member['inventory']]
        if len(items) > ITEM_SLOTS:
            raise ValueError(f'{code:03d}: inventory holds {len(items)} items, the record has {ITEM_SLOTS} slots')
        for index in range(ITEM_SLOTS):
            put32(record, REC['items'] + 4 * index, items[index] if index < len(items) else 0)
    if 'equipment' in member:
        gear = [int(item) for item in member['equipment']]
        if len(gear) != len(EQUIPMENT_SLOTS):
            raise ValueError(f'{code:03d}: equipment needs {len(EQUIPMENT_SLOTS)} codes')
        for slot, item in zip(EQUIPMENT_SLOTS, gear):
            put32(record, REC[slot], item)
    for skill_id in member.get('learned_skills', []):
        word, bit = learned_skill_bit(skill_id)
        put32(record, word, u32(record, word) | bit)
    put32(record, REC['hp'], 9999)
    put32(record, REC['mp'], 9999)
    refresh_record(record)
    history = list(member.get('job_up_history', []))
    if len(history) > 2:
        raise ValueError(f'{code:03d}: at most two job-up tiers exist')
    objects = _defines(OBJ_ALL_H) if history else {}
    for tier, target_id in enumerate(history):
        # 0x434770 opens a tier only while record.job_up_code names the next up object
        # (obj_Player<N>Up1 / Up2 of OBJ-ALL.H); the spec names the PLAYERS row that object installs.
        expected = objects.get(f'obj_Player{code}Up{tier + 1}')
        if expected is None or i32(record, REC['job_up_code']) != expected:
            raise ValueError(f'{code:03d}: job-up tier {tier + 1} is not open (job_up_code {i32(record, REC["job_up_code"])})')
        target = templates.record(actor_code(target_id))
        receipt.setdefault('job_up', []).append(
            job_up_exchange(record, bytes(target), JOB_UP_FIRST_TIER if tier == 0 else JOB_UP_SECOND_TIER))
    receipt.update(level=i32(record, REC['level']), job=i32(record, REC['job']), face_handle=hex(u32(record, REC['face'])),
                   attributes={key: i32(record, REC['base_' + key]) for key in ATTRIBUTES},
                   caps=[i32(record, REC['cap_str'] + 4 * i) for i in range(4)],
                   max_hp=i32(record, REC['max_hp']), max_mp=i32(record, REC['max_mp']),
                   items=[i32(record, REC['items'] + 4 * i) for i in range(ITEM_SLOTS) if i32(record, REC['items'] + 4 * i)])
    return record, receipt


# The learners 0x4373f0 (magic, +0x174 six words) and 0x437a40 (special, +0x158 seven words) set
# word[type] |= 1 << code with type in mag-spc.h section order and code = magicCodeNN - 1
# (docs/evidence_packets/static_reverse/original_growth_lifecycle.json: job 85 [4, 1, 0] = 水剎
# magic:magicWATER:magicCode01; job 88 special row type 5 code 10 = 逆刃 special:magicOTHER:magicCode11).
SKILL_ELEMENTS = ('magicEARTH', 'magicWATER', 'magicAIR', 'magicFIRE', 'magicMIND', 'magicOTHER')


def learned_skill_bit(skill_id: str) -> tuple[int, int]:
    """(record offset, bit) of a remake skill id `magic|special:<element>:magicCodeNN`."""
    parts = skill_id.split(':')
    if len(parts) != 3 or parts[0] not in ('magic', 'special') or parts[1] not in SKILL_ELEMENTS or not parts[2].startswith('magicCode'):
        raise ValueError(f'unsupported learned skill id {skill_id}')
    code = int(parts[2][len('magicCode'):])
    if not 1 <= code <= 32:
        raise ValueError(f'unsupported learned skill code {skill_id}')
    base = REC['magic_words'] if parts[0] == 'magic' else REC['special_words']
    return base + 4 * SKILL_ELEMENTS.index(parts[1]), 1 << (code - 1)


def job_up_ready(record) -> bool:
    """0x434770 without the slot test: job_up_code != 0 and every base attribute >= cap - 50."""
    if i32(record, REC['job_up_code']) == 0:
        return False
    return all(i32(record, REC['base_' + key]) >= i32(record, REC['cap_str'] + 4 * index) - 50
               for index, key in enumerate(ATTRIBUTES))


# --- the tracked dump: build from a memory dump, verify against sources -------------------------

def pak_handles(pak: Path) -> dict[str, int]:
    """PLAYERS.TXT resource name (lower case) -> runtime handle, from the PAK directory order rule."""
    from hsltools.sources.pak import find_decoded_paks_packages
    names = [record['name'] for record in find_decoded_paks_packages(pak)[0]['records']]
    wav = sorted((name for name in names if name.lower().startswith('@:\\wav\\')), key=str.lower)
    shp = sorted((name for name in names if name.lower().endswith('.shp')), key=str.lower)
    handles = {name.lower().split('\\', 1)[1]: index + 1 for index, name in enumerate(wav)}
    handles.update({name.lower().split('\\', 1)[1]: index for index, name in enumerate(shp)})
    used = {row[column].lower() for row in players_rows().values() for _, _, column, _ in HANDLE_WORDS if row.get(column)}
    missing = sorted(used - set(handles))
    if missing:
        raise ValueError(f'PLAYERS.TXT names not in the PAK: {missing}')
    return {name: handles[name] for name in sorted(used)}


def handle_word(record, field: str, half: str) -> int:
    offset = REC[field]
    if half == 'u32':
        return u32(record, offset)
    return u16(record, offset + (2 if half == 'hi' else 0))


def verify_templates(templates: TemplateTable, summary: dict, sample_record: bytes) -> dict:
    """Every template against its PLAYERS.TXT row, the job model and the handle map; the
    synthesised 雷歐納德 against the live record the original wrote. Returns the counts."""
    rows = players_rows()
    defines = {**_defines(TYPE_H), **_defines(OBJ_ALL_H), **_defines(RESOURCE_H)}
    if sorted(templates.records) != sorted(rows):
        raise ValueError(f'template codes {sorted(templates.records)} differ from PLAYERS.TXT rows {sorted(rows)}')
    handles = summary['resource_handles']
    checked_fields = 0
    for code, row in rows.items():
        record = templates.records[code]

        def expect(name: str, offset: int, value: int, width: str = 'i32') -> None:
            nonlocal checked_fields
            got = i32(record, offset) if width == 'i32' else u16(record, offset)
            if got != value:
                raise ValueError(f'template {code:03d} {name} at {offset:#x} is {got}, PLAYERS.TXT gives {value}')
            checked_fields += 1

        expect('code', REC['code'], code)
        expect('name', REC['name_id'], int(row['name']) if row['name'].isdigit() else defines[row['name']])
        expect('job', REC['job'], defines[row['job']])
        expect('job_show_name', REC['job_show_name'], int(row.get('job_show_name', 0) or 0))
        expect('class', REC['class_shoothit'], (defines[row['class']] if row['class'] in defines else int(row['class'])) & 0xFFFF, 'u16')
        expect('mode', REC['mode'], defines[row['mode']])
        expect('size_type', REC['size_carry'], int(row.get('size_type', 0) or 0), 'u16')
        expect('carry_item', REC['size_carry'] + 2, int(row.get('carry_item', 0) or 0), 'u16')
        job_up = row.get('job_up_code', '0')
        expect('job_up_code', REC['job_up_code'], defines[job_up] if job_up in defines else int(job_up))
        for key in ATTRIBUTES:
            expect(key, REC[key], int(row[key]))
            expect('base_' + key, REC['base_' + key], int(row[key]))
        expect('install_code', REC['install_code'], 0)
        expect('exp', REC['exp'], int(row.get('exp', 0) or 0))
        expect('kill_exp', REC['kill_exp'], int(row.get('kill_exp', 0) or 0))
        expect('gold', REC['gold'], int(row.get('gold', 0) or 0))
        expect('level', REC['level'], int(row.get('level', 0) or 0))
        expect('stamina', REC['stamina'], int(row.get('stamina', 0) or 0))
        for slot, key in zip(EQUIPMENT_SLOTS, ('weapon_equip', 'head_equip', 'armor_equip', 'foot_equip', 'other1_equip', 'other2_equip')):
            expect(key, REC[slot], int(row.get(key, 0) or 0))
        for index, key in enumerate(('earth', 'water', 'air', 'fire', 'mind')):
            expect('resist_' + key, REC['resist_base'] + 4 * index, int(row.get('resist_' + key, 0) or 0))
        expect('move_point', REC['move'], int(row.get('move_point', 0) or 0))
        expect('job_up_flags', REC['job_up_flags'], 0)
        for index in range(ITEM_SLOTS):
            expect(f'item{index + 1}', REC['items'] + 4 * index, int(row.get(f'item{index + 1}', 0) or 0))
        for field, half, column, _ in HANDLE_WORDS:
            value = handles[row[column].lower()] if row.get(column) else 0
            got = handle_word(record, field, half)
            if got != value:
                raise ValueError(f'template {code:03d} handle {column} is {got}, the PAK order rule gives {value}')
            checked_fields += 1
        refreshed = bytearray(record)
        refresh_record(refreshed)
        if bytes(refreshed) != record:
            first = next(i for i in range(RECORD_SIZE) if refreshed[i] != record[i])
            raise ValueError(f'template {code:03d}: the job model re-derives a different byte at {first:#x}')
    synthesized, _ = synthesize(templates, {'actor_id': '001'})
    if bytes(synthesized) != sample_record:
        first = next(i for i in range(RECORD_SIZE) if synthesized[i] != sample_record[i])
        raise ValueError(f'synthesize(001) differs from the HSLBAT sample live record at byte {first:#x}')
    return {'templates': len(rows), 'fields': checked_fields}


def build_summary(templates: TemplateTable, handles: dict[str, int], dump_meta: dict) -> dict:
    raw = templates.serialize()
    rows = players_rows()
    return {
        'schema': 'hsl_original_players_templates.v1',
        'evidence_tier': 'runtime-measured',
        'file': TEMPLATES_BIN.name, 'bytes': len(raw), 'sha256': hashlib.sha256(raw).hexdigest(),
        'record_size': RECORD_SIZE, 'codes': sorted(templates.records),
        'origin': dump_meta,
        'layout': 'one 0x1fc record per PLAYERS.TXT row in code order; the runtime table *0x4c1afc holds them at '
                  'index = code (201 slots, the other 135 were zero in the dump)',
        'handle_rule': {
            'wav': '1 + index of the name in the case-insensitive sort of the PAK\'s @:\\wav\\ names (220 names); 0 = none',
            'shp': 'index of the name in the case-insensitive sort of every *.shp PAK name (4519 names)',
            'words': [{'field': field, 'half': half, 'column': column, 'pool': pool} for field, half, column, pool in HANDLE_WORDS],
        },
        'resource_handles': handles,
        'pm_player_rows': [f'{code:03d}' for code, row in sorted(rows.items()) if row['mode'] == 'pmPlayer'],
    }


class MembersTask(ScriptCheckTask):
    name = 'original_save:members'
    family = 'original_save'
    inputs = ('content/imported/hsl/global/tables/', TEMPLATES_BIN.relative_to(ROOT).as_posix(),
              'docs/evidence_packets/static_reverse/original_save_format/HSLBAT_first_control.SAV')
    outputs = (TEMPLATES_SUMMARY.relative_to(ROOT).as_posix(),)
    scripts = ('tools/hsltools/data/original_save_members.py', 'tools/hsltools/model/jobs.py')

    def verify(self, ctx: Context) -> None:
        from hsltools.data.original_save import load_sample
        templates = TemplateTable.load()
        summary = json.loads(TEMPLATES_SUMMARY.read_text())
        if summary['sha256'] != hashlib.sha256(TEMPLATES_BIN.read_bytes()).hexdigest():
            raise ValueError(f'{TEMPLATES_BIN.name} does not match its summary sha256')
        counts = verify_templates(templates, summary, bytes(load_sample().record(0)))
        print(f'ORIGINAL_SAVE_MEMBERS_PASS templates={counts["templates"]} fields={counts["fields"]} '
              f'handles={len(summary["resource_handles"])} synthesized_001=sample')

    def build(self, ctx: Context) -> None:
        dump_path = os.environ.get(DUMP_ENV)
        if not dump_path:
            raise NotGeneratable(f'{self.name}: set {DUMP_ENV} to a hsl_win32_memread JSON holding a `templates` '
                                 f'--read-bytes read of *0x4c1afc ({RECORD_SIZE * RECORD_COUNT:#x} bytes)')
        dump = json.loads(Path(dump_path).read_text())
        templates = TemplateTable.from_dump(dump)
        handles = pak_handles(original_archive(ctx))
        meta = {'tool': dump.get('tool'), 'templates_ptr': next(r['value_u32_hex'] for r in dump['reads'] if r['name'] == 'templates_ptr'),
                'note': 'ReadProcessMemory of the running original (Wine) at the big map; the table is filled by the '
                        'PLAYERS.TXT parser at start-up and does not depend on the game state'}
        TEMPLATES_BIN.write_bytes(templates.serialize())
        TEMPLATES_SUMMARY.write_bytes(json_bytes(build_summary(templates, handles, meta)))


def tasks() -> list:
    return [MembersTask()]
