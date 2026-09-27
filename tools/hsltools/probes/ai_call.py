"""Bounded original call broadcast and target-adoption prefix; no Wine or stubs.

Registry task ai_call (family probe, hsltools.probes._base.ProbeTask): check validates the
tracked packet against the independent model; generate executes the original instructions
(needs the documented hsl01.exe and unicorn). Bodies moved verbatim from the former hsl_native_ai_call_probe.py.
"""
from __future__ import annotations
import copy
import json
from pathlib import Path
import struct

from hsltools.native.image import EXE_SHA, image
from hsltools.paths import ROOT
from hsltools.probes._base import ProbeTask

PACKET = ROOT / 'docs/evidence_packets/static_reverse/original_ai_calls.json'

SIDE_MASK = 0x870000
LIMIT = 8192


def fixtures() -> list[dict]:
    units = [
        {'coord': [10, 10], 'side': 0x20000, 'removed': False, 'object_code': 26, 'tag': 7},
        {'coord': [13, 14], 'side': 0x20000, 'removed': False, 'object_code': 21, 'tag': 8},
        {'coord': [14, 14], 'side': 0x20000, 'removed': False, 'object_code': 21, 'tag': 9},
        {'coord': [11, 10], 'side': 0x60000, 'removed': False, 'object_code': 24, 'tag': 10},
        {'coord': [10, 10], 'side': 0x10000, 'removed': False, 'object_code': 0, 'tag': 11},
        {'coord': [11, 10], 'side': 0x20000, 'removed': True, 'object_code': 21, 'tag': 12},
        None,
        {'coord': [10, 10], 'side': 0x20000, 'removed': False, 'object_code': 26, 'tag': 13},
    ]
    rows = []
    for radius in [0, 1, 4, 5, 6, 512]:
        for tag in [0, 5, 200, 65535]:
            rows.append({'kind': 'broadcast', 'owner': 0, 'units': copy.deepcopy(units),
                         'radius': radius, 'tag': tag})
    # Side helper masks flags before exact equality. Removed objects are NOT filtered.
    for side in [0, 0x10000, 0x20000 | 0x100, 0x60000]:
        changed = copy.deepcopy(units)
        changed[0]['side'] = side
        rows.append({'kind': 'broadcast', 'owner': 0, 'units': changed, 'radius': 5, 'tag': 5})
    for ordinary in [0, 5]:
        for pending, excluded in [(0, -1), (5, -1), (6, -1), (7, -1), (2, 21), (2, 0)]:
            changed = copy.deepcopy(units)
            changed[0]['tag'] = pending
            rows.append({'kind': 'adopt', 'owner': 0, 'units': changed, 'radius': 5,
                         'ordinary': ordinary, 'excluded_word': excluded & 0xffff})
    return rows


def expected(case: dict) -> dict:
    tags = [None if unit is None else unit['tag'] for unit in case['units']]
    owner = case['units'][case['owner']]
    recipients = []

    def broadcast(tag):
        for index, unit in enumerate(case['units']):
            if unit is None or index == case['owner']:
                continue
            dx, dy = unit['coord'][0] - owner['coord'][0], unit['coord'][1] - owner['coord'][1]
            if unit['side'] & SIDE_MASK == owner['side'] & SIDE_MASK and dx * dx + dy * dy <= case['radius'] ** 2:
                tags[index] = tag
                recipients.append(index)

    if case['kind'] == 'broadcast':
        broadcast(case['tag'])
        return {'tags': tags, 'recipients': recipients, 'stop': 'normal_return'}
    target, pending = case['ordinary'], owner['tag']
    stop = '0x43f74e'
    if target:
        if case['radius']:
            broadcast(target)
    elif pending:
        target = pending
        tags[case['owner']] = 0
        candidate = case['units'][pending - 1]
        if candidate is None or candidate['removed'] or (case['excluded_word'] != 0 and candidate['object_code'] == case['excluded_word']):
            target = 0
            stop = '0x43f73e'
    return {'tags': tags, 'recipients': recipients, 'target': target, 'stop': stop}


def execute(base: int, mapped: bytearray, case: dict) -> dict:
    from unicorn import Uc, UC_ARCH_X86, UC_MODE_32, UC_HOOK_CODE
    from unicorn.x86_const import UC_X86_REG_EAX, UC_X86_REG_EBP, UC_X86_REG_EBX, UC_X86_REG_EDI, UC_X86_REG_EIP, UC_X86_REG_ESP
    machine = Uc(UC_ARCH_X86, UC_MODE_32)
    machine.mem_map(base, len(mapped))
    machine.mem_write(base, bytes(mapped))
    machine.mem_map(0x10000000, 0x80000)
    objects, actors, stack, sentinel = 0x10010000, 0x10040000, 0x1007ff00, 0x10000000

    def put(address, value): machine.mem_write(address, struct.pack('<I', value & 0xffffffff))
    def word(address, value): machine.mem_write(address, struct.pack('<H', value & 0xffff))
    def get_word(address): return struct.unpack('<H', machine.mem_read(address, 2))[0]

    put(0x4c1bc8, actors)
    machine.mem_write(0x4c34c0, bytes(200 * 4))
    for index, unit in enumerate(case['units']):
        if unit is None:
            continue
        obj, actor = objects + index * 0x200, actors + index * 0x1fc
        put(0x4c34c0 + index * 4, obj)
        put(obj + 4, unit['coord'][0] * 32)
        put(obj + 8, unit['coord'][1] * 32)
        put(obj + 0xa4, index)
        put(obj + 0x80, 0x8000000 if unit['removed'] else 0)
        word(obj + 0xa2, unit['object_code'])
        word(obj + 0x8a, unit['tag'])
        put(actor + 0x28, unit['side'])
    owner, actor = objects + case['owner'] * 0x200, actors + case['owner'] * 0x1fc
    before = bytes(machine.mem_read(objects, 0x40000))
    normal = case['kind'] == 'broadcast'
    if normal:
        entry = 0x40bee0
        machine.mem_write(stack, struct.pack('<IIII', sentinel, owner, case['radius'], case['tag']))
    else:
        entry = 0x43f6c2
        put(actor + 0x1cc, case['radius'])
        word(actor + 0x1bc, case['excluded_word'])
        before = bytes(machine.mem_read(objects, 0x40000))
        machine.reg_write(UC_X86_REG_EBP, owner)
        machine.reg_write(UC_X86_REG_EBX, actor)
        machine.reg_write(UC_X86_REG_EDI, 0x8000000)
        machine.reg_write(UC_X86_REG_EAX, case['ordinary'])
    machine.reg_write(UC_X86_REG_ESP, stack)
    steps = 0
    allowed = [(0x40bee0, 0x40bf67), (0x40ba20, 0x40ba72), (0x45ec32, 0x45ec63)]
    if not normal:
        allowed.append((0x43f6c2, 0x43f74e))

    def guard(_machine, address, _size, _data):
        nonlocal steps
        if not normal and address in [0x43f73e, 0x43f74e]:
            machine.emu_stop()
            return
        if not any(low <= address < high for low, high in allowed):
            raise ValueError(f'Unreviewed call-lifecycle callee: {address:#x}')
        steps += 1

    machine.hook_add(UC_HOOK_CODE, guard)
    machine.emu_start(entry, sentinel, count=LIMIT)
    stop = machine.reg_read(UC_X86_REG_EIP)
    if normal and stop != sentinel or not normal and stop not in [0x43f73e, 0x43f74e]:
        raise ValueError('Call lifecycle did not reach the declared boundary')
    result = expected(case)
    actual_tags = [None if unit is None else get_word(objects + index * 0x200 + 0x8a)
                   for index, unit in enumerate(case['units'])]
    if actual_tags != result['tags']:
        raise ValueError('Original broadcast/adoption differs from independent model')
    if not normal and (get_word(owner + 0x88) != result['target'] or hex(stop) != result['stop']):
        raise ValueError('Original adopted target or prefix boundary differs')
    expected_memory = bytearray(before)
    for index, tag in enumerate(result['tags']):
        if tag is not None:
            struct.pack_into('<H', expected_memory, index * 0x200 + 0x8a, tag)
    if not normal:
        struct.pack_into('<H', expected_memory, case['owner'] * 0x200 + 0x88, result['target'])
    if bytes(machine.mem_read(objects, 0x40000)) != bytes(expected_memory):
        raise ValueError('Original call lifecycle changed unrelated actor memory')
    return {'input': case, 'result': result, 'normal_return': normal, 'instructions': steps}


def check_packet(packet: dict) -> None:
    if packet.get('schema') != 'hsl_ai_calls_native.v1' or packet.get('exe_sha256') != EXE_SHA or packet.get('native_execution') is not True:
        raise ValueError('Call packet lacks executable identity')
    if [row['input'] for row in packet['cases']] != fixtures():
        raise ValueError('Call fixture coverage changed')
    for row in packet['cases']:
        if row['normal_return'] != (row['input']['kind'] == 'broadcast') or not 0 < row['instructions'] < LIMIT or row['result'] != expected(row['input']):
            raise ValueError('Call result or execution boundary differs')


def execute_packet(exe: Path) -> dict:
    """Run the bounded original instructions on the documented EXE and assemble the packet."""
    base, mapped = image(exe.read_bytes())
    packet = {'schema': 'hsl_ai_calls_native.v1', 'evidence_tier': 'static-derived',
              'exe_sha256': EXE_SHA, 'native_execution': True,
              'cases': [execute(base, mapped, case) for case in fixtures()],
              'limits': ['Broadcast executes original callees to normal return; no removed-object filter exists in that helper.',
                         'Adoption starts with the original search result supplied in EAX. It is a prefix, not a full AI normal return.',
                         'Stops before 0x40c110 support handling or 0x40c620 ability preparation; neither is stubbed.',
                         'No original target-lock, wait-round, death cleanup, healing, path or full-turn equivalence claim.']}
    return packet


def summary_line(packet: dict, executed_now: bool) -> str:
    normal = sum(row['normal_return'] for row in packet['cases'])
    return f'AI_CALL_NATIVE_PASS normal_returns={normal} prefixes={len(packet["cases"]) - normal} executed_now={executed_now}'


TASK = ProbeTask('ai_call', PACKET, check_packet, execute_packet, summary_line)


def tasks() -> list[ProbeTask]:
    return [TASK]
