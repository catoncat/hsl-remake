"""Bounded original x86 AI skill selection and position-ranking observations.

Unicorn executes unchanged EXE instructions against synthetic tables, never the
original game process. Unknown callees fail. Position cases enter an explicitly
named instruction suffix; they are not normal returns from the whole planner.

Registry task ai_skill (family probe, hsltools.probes._base.ProbeTask): check validates the
tracked packet against the independent model; generate executes the original instructions
(needs the documented hsl01.exe and unicorn). Bodies moved verbatim from the former hsl_native_ai_skill_probe.py.
"""
from __future__ import annotations
import hashlib
import json
from pathlib import Path
import struct

from hsltools.native.image import EXE_SHA, image
from hsltools.paths import ROOT
from hsltools.probes._base import ProbeTask

PACKET = ROOT / 'docs/evidence_packets/static_reverse/original_ai_skills.json'

ANCHORS = {
    0x407010: (461, 'function buckets and prepend order; zero/nonzero effect range'),
    0x40C620: (332, 'owned type/code traversal, resource checks and list construction'),
    0x40C770: (523, 'random32 start, circular traversal, random100+1 vs use_ratio'),
    0x40D4E0: (79, 'ai_magic_multi_first order roll'),
    0x40CB42: (142, 'prefer coverage containing requested target; maximum coverage'),
    0x40CFEA: (106, 'retain maximum-coverage movement candidates'),
    0x40D200: (176, 'maximum Manhattan distance and native low-bit tie choice'),
    0x44DB40: (29, 'MAGIC use_ratio parser stores descriptor+0x28; not an ai_percent source key'),
}


def fixtures() -> list[dict]:
    cases = []
    for mask in (1, 8, 17, 2, 0x160, 0x2E00, 0):
        for area in (False, True):
            cases.append(dict(kind='buckets', mask=mask, area=area, seed=0))
    for flag in (0, 1):
        for seed in range(32):
            cases.append(dict(kind='order', flag=flag, seed=seed))
    for bucket in (3, 4):
        for rates in ([], [0], [100], [0, 100], [90, 90], [86, 90, 0], [0]*40):
            for seed in (0, 1, 2, 7, 19, 31):
                cases.append(dict(kind='select', bucket=bucket, rates=rates, seed=seed))
    for positions in ([[3, 4]], [[3, 4], [6, 4], [4, 4]],
                      [[2, 4], [6, 4], [4, 6], [4, 2]],
                      [[4, 4], [4, 4], [4, 4]], [[1, 1], [7, 7], [0, 4]]):
        for seed in range(8):
            cases.append(dict(kind='position_suffix', positions=positions, threat=[4, 4], seed=seed))
    return cases


def expected(case: dict, draws: list[dict]):
    cursor = 0

    def draw(bound: int) -> int:
        nonlocal cursor
        if cursor >= len(draws):
            raise ValueError('Missing native draw')
        item = draws[cursor]
        cursor += 1
        if item['bound'] != bound or not 0 <= item['value'] < bound:
            raise ValueError('Unexpected native random bound/value')
        return item['value']

    kind = case['kind']
    if kind == 'buckets':
        mask, area = case['mask'], case['area']
        result = []
        if mask & 0x501D: result.append(3 if area else 4)
        if mask & 2: result.append(1 if area else 2)
        if mask & 0x160: result.append(5)
        if mask & 0x501C: result.append(6)
        if mask & 0x2E00: result.append(7)
        result.sort()
    elif kind == 'order':
        roll = draw(100) + 1
        result = int(roll > 30 if case['flag'] else roll <= 30)
    elif kind == 'select':
        result = -1
        rates = case['rates']
        if rates:
            start = draw(32) % len(rates)
            for offset in range(len(rates)):
                index = (start + offset) % len(rates)
                if draw(100) + 1 <= rates[index]:
                    result = index
                    break
    else:
        best, result = 0, 0
        tx, ty = case['threat']
        for index, (x, y) in enumerate(case['positions']):
            distance = (abs(x-tx) + abs(y-ty)) * 32
            if distance > best:
                best, result = distance, index
            elif distance == best and draw(2):
                result = index
    if cursor != len(draws):
        raise ValueError('Unexpected extra native draws')
    return result


def execute(base: int, mapped: bytearray, case: dict) -> dict:
    from unicorn import Uc, UC_ARCH_X86, UC_MODE_32, UC_HOOK_CODE
    from unicorn.x86_const import UC_X86_REG_ESP, UC_X86_REG_EIP, UC_X86_REG_EAX, UC_X86_REG_EDI

    machine = Uc(UC_ARCH_X86, UC_MODE_32)
    machine.mem_map(base, len(mapped))
    machine.mem_write(base, bytes(mapped))
    machine.mem_map(0x10000000, 0x80000)
    sentinel, buckets, nodes, table, rows = 0x10000000, 0x10001000, 0x10002000, 0x10010000, 0x10014000
    actor, obj, stack = 0x10020000, 0x10021000, 0x1007FF00

    def put(address: int, value: int):
        machine.mem_write(address, struct.pack('<I', value & 0xFFFFFFFF))

    def get(address: int):
        return struct.unpack('<I', machine.mem_read(address, 4))[0]

    put(0x4C1B78, buckets)
    put(0x4C1BC8, actor)
    put(0x4C1E8C, 1)
    put(0x4795D4, case['seed'])
    put(0x4795D8, 0x87654321)
    kind = case['kind']
    stop = sentinel
    if kind == 'buckets':
        entry, args = 0x407010, [case['mask'], 0, int(case['area']), 0, 0, nodes]
    elif kind == 'order':
        entry, args = 0x40D4E0, [obj]
        put(actor + 0x1F4, case['flag'])
    elif kind == 'select':
        entry, args = 0x40C770, [case['bucket'], 0]
        rates = case['rates']
        put(buckets + (case['bucket']-1)*8, nodes if rates else 0)
        put(buckets + (case['bucket']-1)*8 + 4, len(rates))
        put(0x4C2CA0, table)
        for index, rate in enumerate(rates):
            put(nodes + index*8, index)
            put(nodes + index*8 + 4, nodes + (index+1)*8 if index+1 < len(rates) else 0)
            put(table + index*4, rows + index*0x100)
            put(rows + index*0x100 + 0x24, 1)
            put(rows + index*0x100 + 0x28, rate)
    else:
        entry, args, stop = 0x40D200, [], 0x40D2B0
        put(obj + 4, case['threat'][0]*32 + 16)
        put(obj + 8, case['threat'][1]*32 + 16)
        put(0x4C1A60, len(case['positions']))
        for index, (x, y) in enumerate(case['positions']):
            machine.mem_write(0x4C6560 + index*8, struct.pack('<hhhh', y*32+16, x*32+16, 0, 0))
        machine.reg_write(UC_X86_REG_EAX, obj)
    put(stack, sentinel)
    for index, arg in enumerate(args): put(stack + 4 + index*4, arg)
    machine.reg_write(UC_X86_REG_ESP, stack)
    immutable = bytes(machine.mem_read(actor, 0x2200))
    draws, pending = [], []
    steps = 0
    allowed = [(0x407010, 0x4071DD), (0x40C770, 0x40C97B), (0x409850, 0x40986C),
               (0x40D4E0, 0x40D52F), (0x40D200, 0x40D2B0), (0x458C10, 0x458CB3)]

    def guard(_machine, address, _size, _data):
        nonlocal steps
        steps += 1
        if pending and address == pending[-1]['return']:
            call = pending.pop()
            value = machine.reg_read(UC_X86_REG_EAX)
            draws.append({'bound': call['bound'], 'value': value & 1 if call['bound'] == 2 else value})
        if address == stop:
            machine.emu_stop()
            return
        if not any(lo <= address < hi for lo, hi in allowed):
            raise RuntimeError(f'Unmodelled native callee {address:#x}; no stubs permitted')
        sp = machine.reg_read(UC_X86_REG_ESP)
        if address == 0x458C80:
            pending.append({'return': get(sp), 'bound': get(sp+4)})
        elif address == 0x458C10 and kind == 'position_suffix':
            pending.append({'return': get(sp), 'bound': 2})

    machine.hook_add(UC_HOOK_CODE, guard)
    machine.emu_start(entry, sentinel, count=16384)
    if machine.reg_read(UC_X86_REG_EIP) != stop or pending:
        raise ValueError('Native execution did not reach the declared boundary')
    if immutable != bytes(machine.mem_read(actor, 0x2200)):
        raise ValueError('Selection mutated synthetic actor/target state')
    if kind == 'buckets': result = [index+1 for index in range(7) if get(buckets + index*8 + 4)]
    elif kind == 'select': result = get(0x4C2C40) if machine.reg_read(UC_X86_REG_EAX) else -1
    elif kind == 'position_suffix': result = machine.reg_read(UC_X86_REG_EDI)
    else: result = machine.reg_read(UC_X86_REG_EAX)
    if result != expected(case, draws):
        raise ValueError(f'Native/model mismatch {case}: native={result}, draws={draws}')
    return {'input': case, 'native': result, 'draws': draws, 'steps': steps,
            'normal_return': kind != 'position_suffix', 'entry': hex(entry), 'stop': hex(stop),
            'actor_unchanged': True}


def check(packet: dict):
    if packet['schema'] != 'hsl_native_ai_skills.v1' or packet['exe_sha256'] != EXE_SHA:
        raise ValueError('Unknown AI skill evidence')
    if [row['input'] for row in packet['cases']] != fixtures():
        raise ValueError('AI skill case coverage differs')
    for row in packet['cases']:
        if row['native'] != expected(row['input'], row['draws']):
            raise ValueError('AI skill oracle differs')
        if row['normal_return'] != (row['input']['kind'] != 'position_suffix') or not row['actor_unchanged']:
            raise ValueError('Invalid execution evidence boundary')
    if set(packet['anchors']) != {hex(address) for address in ANCHORS}:
        raise ValueError('Missing instruction anchors')
    for address, (size, _) in ANCHORS.items():
        item = packet['anchors'][hex(address)]
        raw = bytes.fromhex(item['hex'])
        if len(raw) != size or hashlib.sha256(raw).hexdigest() != item['sha256']:
            raise ValueError('Invalid instruction anchor')


def execute_packet(exe: Path) -> dict:
    """Run the bounded original instructions on the documented EXE and assemble the packet."""
    base, mapped = image(exe.read_bytes())
    packet = {'schema': 'hsl_native_ai_skills.v1', 'evidence_tier': 'static-derived',
              'exe_sha256': EXE_SHA, 'cases': [execute(base, mapped, c) for c in fixtures()],
              'anchors': {hex(a): {'description': desc, 'hex': bytes(mapped[a-base:a-base+n]).hex(),
                          'sha256': hashlib.sha256(mapped[a-base:a-base+n]).hexdigest()}
                          for a, (n, desc) in ANCHORS.items()}}
    return packet


def summary_line(packet: dict, executed_now: bool) -> str:
    normal = sum(row['normal_return'] for row in packet['cases'])
    return f'AI_SKILL_NATIVE_PASS normal={normal} position_suffix={len(packet["cases"])-normal} execution={executed_now}'


TASK = ProbeTask('ai_skill', PACKET, check, execute_packet, summary_line)


def tasks() -> list[ProbeTask]:
    return [TASK]
