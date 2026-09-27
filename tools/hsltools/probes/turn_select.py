"""Execute original 0x4074a0 with synthetic ready slots; never stub rebuild.

The selected branches return normally. Queue construction, status ticking,
0x407510's other callees and the actual game loop are outside this probe.

Registry task turn_select (family probe, hsltools.probes._base.ProbeTask): check validates the
tracked packet against the independent model; generate executes the original instructions
(needs the documented hsl01.exe and unicorn). Bodies moved verbatim from the former hsl_native_turn_select_probe.py.
"""
from __future__ import annotations
import json
from pathlib import Path
import struct

from hsltools.native.image import EXE_SHA, image
from hsltools.paths import ROOT
from hsltools.probes._base import ProbeTask

PACKET = ROOT / 'docs/evidence_packets/static_reverse/original_turn_selection_native.json'

ENTRY, END = 0x4074A0, 0x407510
INDEX, RECORDS, ROUND = 0x4C6E48, 0x4C3940, 0x4C1BBC
CASES = [
    {'name': 'null_argument', 'index': 0, 'argument': 0, 'slots': [[1, 101, 1]]},
    {'name': 'immediate_successor', 'index': 0, 'argument': 1, 'slots': [[0, 100, 0], [1, 101, 1], [2, 102, 1]]},
    {'name': 'skip_null_pointer', 'index': 0, 'argument': 1, 'slots': [[1, 0, 1], [2, 102, 1]]},
    {'name': 'skip_spent', 'index': 0, 'argument': 1, 'slots': [[1, 101, 0], [2, 102, 1]]},
    {'name': 'non_boolean_ready', 'index': 0, 'argument': 1, 'slots': [[1, 101, 2], [2, 102, 1]]},
    {'name': 'last_slot', 'index': 198, 'argument': 1, 'slots': [[199, 199, 1]]},
    {'name': 'wrap_to_earlier_ready', 'index': 199, 'argument': 1, 'slots': [[0, 100, 1], [1, 101, 1]]},
    {'name': 'wrap_skips_spent_and_null', 'index': 198, 'argument': 1, 'slots': [[0, 100, 0], [1, 0, 1], [2, 102, 1]]},
]


def expected(case: dict) -> dict:
    rows = {i: [pointer, ready] for i, pointer, ready in case['slots']}
    index = case['index']
    if case['argument']:
        candidates = list(range(index + 1, 200)) + list(range(200))
        index = next(i for i in candidates if rows.get(i, [0, 0])[0] and rows.get(i, [0, 0])[1])
        rows[index][1] = 0
    return {'index': index, 'round': 7,
            'slots': [[i, *rows[i]] for i in sorted(rows)]}


def run_case(base: int, mapped: bytearray, case: dict) -> dict:
    from unicorn import Uc, UC_ARCH_X86, UC_MODE_32, UC_HOOK_CODE
    from unicorn.x86_const import UC_X86_REG_ESP, UC_X86_REG_EIP
    machine = Uc(UC_ARCH_X86, UC_MODE_32)
    machine.mem_map(base, len(mapped))
    machine.mem_write(base, bytes(mapped))
    machine.mem_map(0x10000000, 0x10000)
    stack, sentinel = 0x1000FF00, 0x10000000
    machine.mem_write(RECORDS, bytes(200 * 12))
    machine.mem_write(INDEX, struct.pack('<i', case['index']))
    machine.mem_write(ROUND, struct.pack('<H', 7))
    for slot, pointer, ready in case['slots']:
        machine.mem_write(RECORDS + 12 * slot, struct.pack('<III', pointer, 900 - slot, ready))
    before = bytes(machine.mem_read(RECORDS, 200 * 12))
    machine.mem_write(stack, struct.pack('<II', sentinel, case['argument']))
    machine.reg_write(UC_X86_REG_ESP, stack)
    instructions = 0

    def guard(_machine, address, _size, _data):
        nonlocal instructions
        instructions += 1
        if not ENTRY <= address < END:
            raise RuntimeError(f'Unexecuted rebuild/callee reached: {address:#x}')

    machine.hook_add(UC_HOOK_CODE, guard)
    machine.emu_start(ENTRY, sentinel, count=4096)
    if machine.reg_read(UC_X86_REG_EIP) != sentinel:
        raise RuntimeError('Turn selector did not return within 4096 instructions')
    after = bytes(machine.mem_read(RECORDS, 200 * 12))
    result = {'index': struct.unpack('<i', machine.mem_read(INDEX, 4))[0],
              'round': struct.unpack('<H', machine.mem_read(ROUND, 2))[0],
              'slots': [[i, *struct.unpack('<III', after[12*i:12*i+12])[::2]] for i, _, _ in sorted(case['slots'])]}
    expected_image = bytearray(before)
    if case['argument']:
        struct.pack_into('<I', expected_image, 12*result['index']+8, 0)
    if after != expected_image or result != expected(case):
        raise ValueError(f'Original selector diverged: {case["name"]}')
    return {**case, 'native': result, 'normal_return': True,
            'instructions': instructions, 'only_selected_ready_word_changed': True}


def probe(exe: Path) -> dict:
    base, mapped = image(exe.read_bytes())
    return {'schema': 'hsl_turn_selection_native.v1', 'exe_sha256': EXE_SHA,
            'evidence_tier': 'static-derived', 'native_execution': True,
            'entry': hex(ENTRY), 'execution': 'Unicorn x86-32, original bytes, synthetic memory, no stubs',
            'cases': [run_case(base, mapped, case) for case in CASES],
            'limits': ['Only no-rebuild paths of 0x4074a0 execute; entering 0x407340 is rejected.',
                       'Circular search can choose an earlier still-ready slot without rebuilding or advancing the round.',
                       'Native ready is cleared on selection. Godot action_ready remains completion bookkeeping, not native flag parity.',
                       'No actual gameplay, original roster registration, status ticks or 0x407510 caller execution.']}


def check_packet(packet: dict) -> None:
    if packet.get('exe_sha256') != EXE_SHA or packet.get('native_execution') is not True or packet.get('entry') != hex(ENTRY):
        raise ValueError('Native selector identity or execution boundary differs')
    if len(packet.get('cases', [])) != len(CASES):
        raise ValueError('Missing selector cases')
    for source, saved in zip(CASES, packet['cases']):
        if any(saved.get(key) != value for key, value in source.items()) or saved.get('native') != expected(source):
            raise ValueError('Selector fixture/output differs')
        if not saved.get('normal_return') or not saved.get('only_selected_ready_word_changed') or not 0 < saved.get('instructions', 0) <= 4096:
            raise ValueError('Selector normal return not established')


def execute_packet(exe: Path) -> dict:
    """Run the bounded original selector on the documented EXE and assemble the packet."""
    return probe(exe)


def summary_line(packet: dict, executed_now: bool) -> str:
    return f'TURN_SELECTION_NATIVE_PASS cases={len(CASES)} executed_now={executed_now}'


TASK = ProbeTask('turn_select', PACKET, check_packet, execute_packet, summary_line)


def tasks() -> list[ProbeTask]:
    return [TASK]
