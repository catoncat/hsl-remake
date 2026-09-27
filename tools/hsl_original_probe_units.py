#!/usr/bin/env python3
"""Read-only dump of the original's live battle units (lane R14 / R16 observation aid).

Reads `*0x4c1bc8` (live actor records, 0x1fc stride; field table in
docs/evidence_packets/static_reverse/original_save_format.md) and the object pointer table
at 0x4c34c0 (200 slots; obj+4/+8 pixel position, obj+0x80 flags, obj+0xa4 actor index —
offsets from tools/hsltools/probes/ai.py) through `ignored/bin/hsl_win32_memread.exe`
(`tools/build_runtime_helpers.sh --win32-rpm`). Nothing is written to the process.

    WINEPREFIX=~/.wine-hsl-original python3 tools/hsl_original_probe_units.py PID [label] [--out-dir DIR]

PID is the Wine task pid (`WINEPREFIX=… wine tasklist`), not the macOS process id. One JSON
`units-<label>.json` per call lands in --out-dir (default ignored/original-probe-units/), plus a
one-line-per-unit summary on stdout: slot, actor index, code/name, side word (player 0x10000,
enemy 0x20000, friendly NPC 0x50000), level, HP, MP, grid cell, non-zero item slots (+0x138),
the identity-strip "known" byte `0x4c6d80[obj+0xa2]` (`known`／`unknown`, lane P4; the 0x434d10
mask predicate indexed by the object's live serial word, docs/evidence_packets/static_reverse/original_identity_bar.md) and
REMOVED when the object carries the 0x8000000 death mark. The JSON also carries the four
working / base attributes, hit ratio, magic attack, stamina, the six equipment words, the
object's pixel position and the raw 0x1fc record hex (lane R33's level-53 field comparison). Used for the level-17 escort
packet (docs/evidence_packets/runtime_observations/original_level17_escort/README.md).

Two globals ride along: the round counter `round_0x4c1bbc` (u16: 0x42c6b9 sets 1 at level start,
0x4074f1 `inc word` per round) and `rng_seeded_0x4c1e8c`, the global RNG's seeded flag (0x458c10
seeds 0x4795d4／0x4795d8 from the clock while it is 0; 1 once anything drew). Receipts written
before 2026-09-25 name that flag `round_counter_0x4c1e8c` — a mislabel (lane ORACLE); their value 1
means "RNG seeded", not "round 1". docs/evidence_packets/static_reverse/original_enemy_turn.md.
"""
from __future__ import annotations

import argparse
import json
import os
import struct
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / 'tools'))
from hsltools.data.original_save_members import REC  # noqa: E402
from hsltools.paths import WINE_PREFIX  # noqa: E402

MEMREAD = ROOT / 'ignored/bin/hsl_win32_memread.exe'
DEFAULT_OUT_DIR = ROOT / 'ignored/original-probe-units'
ACTOR_TABLE_POINTER = 0x4c1bc8
OBJECT_TABLE = 0x4c34c0
OBJECT_SLOTS = 200
ROUND_COUNTER = 0x4c1bbc      # u16 (0x4074f1 inc word)
RNG_SEEDED_FLAG = 0x4c1e8c    # 0x458c10 clock-seeds while 0 — not a round counter
KNOWN_TABLE = 0x4c6d80
KNOWN_SLOTS = 200
RECORD_STRIDE = 0x1fc
OBJECT_BYTES = 0x200
DEATH_MARK = 0x8000000
ITEM_SLOTS = 8
NAMES = {1: '雷歐納德', 2: '緹娜', 3: '琥', 4: '漢克斯', 5: '雪拉', 7: '嚎', 23: 'guard023', 25: 'emperor025', 26: 'mage026',
         29: 'princess029', 35: 'enemy35', 36: 'enemy36', 37: 'enemy37', 38: 'enemy38', 61: 'villager061', 62: 'refugee062', 64: '克里夫064'}
EQUIPMENT = ('weapon', 'head', 'armor', 'foot', 'other1', 'other2')


def memread(pid: int, *reads: str) -> list[dict]:
    if not MEMREAD.exists():
        raise SystemExit(f'{MEMREAD} missing: run tools/build_runtime_helpers.sh --win32-rpm')
    env = dict(os.environ, WINEPREFIX=str(WINE_PREFIX))
    out = subprocess.run(['wine', str(MEMREAD), '--pid', str(pid), *reads], capture_output=True, text=True, timeout=60, env=env).stdout
    lines = [line for line in out.splitlines() if line.startswith('{')]
    if not lines:
        raise SystemExit(f'hsl_win32_memread returned no JSON for pid {pid}: {out.strip()[:200]}')
    return json.loads(lines[-1])['reads']


def u32(data: bytes, offset: int) -> int:
    return struct.unpack_from('<I', data, offset)[0]


def i32(data: bytes, offset: int) -> int:
    return struct.unpack_from('<i', data, offset)[0]


def dump(pid: int, label: str) -> dict:
    reads = memread(pid, '--read-u32', f'actors=0x{ACTOR_TABLE_POINTER:x}', '--read-bytes', f'objects=0x{OBJECT_TABLE:x}:0x{OBJECT_SLOTS * 4:x}',
                    '--read-u32', f'round=0x{ROUND_COUNTER:x}', '--read-bytes', f'known=0x{KNOWN_TABLE:x}:0x{KNOWN_SLOTS:x}',
                    '--read-u32', f'seeded=0x{RNG_SEEDED_FLAG:x}')
    actors = int(reads[0]['value_u32_hex'], 16)
    objects = bytes.fromhex(reads[1]['hex'])
    known = bytes.fromhex(reads[3]['hex'])
    live = [(slot, u32(objects, slot * 4)) for slot in range(OBJECT_SLOTS) if u32(objects, slot * 4)]
    object_reads = memread(pid, *[arg for slot, pointer in live for arg in ('--read-bytes', f'obj{slot}=0x{pointer:x}:0x{OBJECT_BYTES:x}')]) if live else []
    rows = []
    for (slot, pointer), read in zip(live, object_reads):
        obj = bytes.fromhex(read['hex'])
        index = u32(obj, 0xa4)
        rows.append((slot, pointer, index, i32(obj, 4), i32(obj, 8), u32(obj, 0x80), struct.unpack_from('<H', obj, 0xa2)[0]))
    record_reads = memread(pid, *[arg for _, _, index, *_ in rows for arg in ('--read-bytes', f'act{index}=0x{actors + index * RECORD_STRIDE:x}:0x{RECORD_STRIDE:x}')]) if rows else []
    result = {'schema': 'hsl_original_live_units.v1', 'label': label, 'time': time.strftime('%Y-%m-%dT%H:%M:%S'), 'pid': pid,
              'round_0x4c1bbc': int(reads[2]['value_u32_hex'], 16) & 0xffff,
              'rng_seeded_0x4c1e8c': int(reads[4]['value_u32_hex'], 16), 'units': []}
    for (slot, pointer, index, px, py, flags, serial), read in zip(rows, record_reads):
        record = bytes.fromhex(read['hex'])
        code = i32(record, REC['code'])
        result['units'].append({
            'slot': slot, 'object_pointer': f'0x{pointer:x}', 'actor_index': index, 'code': code, 'name': NAMES.get(code),
            'side': i32(record, REC['mode']), 'level': i32(record, REC['level']), 'hp': i32(record, REC['hp']), 'max_hp': i32(record, REC['max_hp']),
            'mp': i32(record, REC['mp']), 'max_mp': i32(record, REC['max_mp']), 'grid': [px // 32, py // 32], 'pixel': [px, py],
            'flags': f'0x{flags:x}', 'removed': bool(flags & DEATH_MARK),
            # 0x434d10 indexes the known table by the object's +0xa2 word (the live serial), not by the record index.
            'known_serial': serial, 'known': bool(known[serial]) if serial < KNOWN_SLOTS else None,
            'attributes': {key: i32(record, REC[key]) for key in ('str', 'dex', 'mind', 'con')},
            'base_attributes': {key: i32(record, REC['base_' + key]) for key in ('str', 'dex', 'mind', 'con')},
            'attack': i32(record, REC['attack']), 'defense': i32(record, REC['defense']), 'speed': i32(record, REC['speed']),
            'hit_ratio': i32(record, REC['hit_ratio']), 'magic_attack': i32(record, REC['magic_attack']), 'stamina': i32(record, REC['stamina']),
            'move': i32(record, REC['move']), 'exp': i32(record, REC['exp']), 'job': i32(record, REC['job']),
            'capability_flags': f"0x{u32(record, REC['capability_flags']):x}", 'effect_flags': f"0x{u32(record, REC['effect_flags']):x}",
            'equipment': {name: i32(record, REC[name]) for name in EQUIPMENT},
            'items': [i32(record, REC['items'] + 4 * slot_index) for slot_index in range(ITEM_SLOTS)],
            'record_hex': record.hex(),
        })
    return result


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('pid', type=int, help='Wine task pid of hsl01.exe (WINEPREFIX=… wine tasklist)')
    parser.add_argument('label', nargs='?', default='probe')
    parser.add_argument('--out-dir', type=Path, default=DEFAULT_OUT_DIR)
    args = parser.parse_args()
    result = dump(args.pid, args.label)
    args.out_dir.mkdir(parents=True, exist_ok=True)
    out = args.out_dir / f'units-{args.label}.json'
    out.write_text(json.dumps(result, ensure_ascii=False, indent=1), encoding='utf-8')
    print(f"{args.label}: {len(result['units'])} units round={result['round_0x4c1bbc']} "
          f"rng_seeded={result['rng_seeded_0x4c1e8c']} -> {out}")
    for unit in result['units']:
        print(f"  slot{unit['slot']:>3} idx{unit['actor_index']:>3} {unit['code']:03d} {str(unit['name']):<10} side0x{unit['side']:x} L{unit['level']:<2} "
              f"hp {unit['hp']:>4}/{unit['max_hp']:<4} mp {unit['mp']:>3} grid {unit['grid']} items {[x for x in unit['items'] if x]} "
              f"{'known' if unit['known'] else 'unknown'} {'REMOVED' if unit['removed'] else ''}")
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
