"""Bounded original low-HP, healing-item and priority-prefix evidence; no stubs.

Registry task ai_priority (family probe, hsltools.probes._base.ProbeTask): check validates the
tracked packet against the independent model; generate executes the original instructions
(needs the documented hsl01.exe and unicorn). Bodies moved verbatim from the former hsl_native_ai_priority_probe.py.
"""
from __future__ import annotations
import copy
import json
from pathlib import Path
import struct

from hsltools.native.image import EXE_SHA, image
from hsltools.paths import ROOT
from hsltools.probes._base import ProbeTask

PACKET = ROOT / 'docs/evidence_packets/static_reverse/original_ai_priority.json'

LIMIT = 16384


def fixtures() -> list[dict]:
    units = [
        {'coord': [10, 10], 'side': 0x20000, 'hp': 100, 'max_hp': 100, 'sid': 26, 'removed': False},
        {'coord': [11, 10], 'side': 0x10000, 'hp': 31, 'max_hp': 100, 'sid': 0, 'removed': False},
        {'coord': [15, 15], 'side': 0x10000, 'hp': 9, 'max_hp': 100, 'sid': 21, 'removed': False},
        {'coord': [11, 10], 'side': 0x60000, 'hp': 1, 'max_hp': 100, 'sid': 24, 'removed': False},
        {'coord': [12, 10], 'side': 0x10000, 'hp': 0, 'max_hp': 100, 'sid': 22, 'removed': True},
        None,
        {'coord': [16, 10], 'side': 0x10000, 'hp': 1, 'max_hp': 100, 'sid': 23, 'removed': False},
    ]
    cases = []
    for seed in [1, 19]:
        for radius in [0, 1, 5, 6]:
            for cursor in [0, 2, 4, 7, 200]:
                cases.append({'kind': 'dying', 'owner': 0, 'units': copy.deepcopy(units),
                              'radius': radius, 'cursor': cursor, 'excluded': -1, 'seed': seed})
        for excluded in [0, 21, 22]:
            cases.append({'kind': 'dying', 'owner': 0, 'units': copy.deepcopy(units),
                          'radius': 5, 'cursor': 0, 'excluded': excluded, 'seed': seed})
        cases.append({'kind': 'dying', 'owner': 0, 'units': copy.deepcopy(units),
                      'radius': 5, 'cursor': 4, 'excluded': 22, 'seed': seed})
        for hp, maximum in [(10, 20), (11, 20), (12, 100), (29, 100), (80, 10000), (81, 10000)]:
            sample = copy.deepcopy(units[:2])
            sample[1].update(hp=hp, max_hp=maximum)
            cases.append({'kind': 'dying', 'owner': 0, 'units': sample,
                          'radius': 5, 'cursor': 0, 'excluded': -1, 'seed': seed})
    for seed in [1, 7, 19]:
        for hp, maximum in [(1, 10), (1, 20), (10, 20), (11, 20), (12, 100), (29, 100),
                            (150, 1000), (170, 1000), (175, 10000), (176, 10000), (100, 100)]:
            cases.append({'kind': 'self_hp', 'hp': hp, 'max_hp': maximum, 'seed': seed})
        for own, dying in [(0, 0), (100, 100), (20, 90), (90, 20)]:
            for attempted in [0, 1, 2, 3]:
                cases.append({'kind': 'priority', 'self_rate': own, 'dying_rate': dying,
                              'attempted': attempted, 'seed': seed})
    for slots in [[0] * 8, [1, 2, 3, 4, 0, 0, 0, 0], [4, 3, 2, 1, 0, 0, 0, 0],
                  [1, 1, 0, 0, 0, 0, 0, 4], [0, 0, 0, 0, 0, 0, 0, 4]]:
        cases.append({'kind': 'heal_item', 'slots': slots,
                      'items': {'1': {'type': 1, 'heal_hp': 0}, '2': {'type': 2, 'heal_hp': 50},
                                '3': {'type': 1, 'heal_hp': 30}, '4': {'type': 1, 'heal_hp': 60}}, 'seed': 1})
    return cases


def expected(case: dict, draws: list[dict]) -> dict:
    position = 0

    def draw(bound):
        nonlocal position
        if position >= len(draws) or draws[position]['bound'] != bound or not 0 <= draws[position]['value'] < bound:
            raise ValueError('Priority RNG sequence differs')
        value = draws[position]['value']
        position += 1
        return value

    kind = case['kind']
    if kind == 'priority':
        attempted, selected, roll = case['attempted'], 0, draw(99) + 1
        for bit, rate in [(2, case['self_rate']), (1, case['dying_rate'])]:
            if attempted & bit:
                continue
            attempted |= bit
            if roll <= rate:
                selected = bit
                break
            roll = draw(99) + 1
        result = {'kind': selected, 'attempted': attempted, 'next_roll': roll,
                  'stop': '0x441035' if selected else '0x440e3d'}
    elif kind == 'self_hp':
        threshold = case['max_hp'] * (12 + draw(18)) // 100
        if threshold < 10:
            threshold = 10 + threshold % 10
        elif threshold > 160:
            threshold = 160 + threshold % 16
        result = {'native': int(case['max_hp'] - case['hp'] >= 10 and case['hp'] <= threshold), 'threshold': threshold}
    elif kind == 'heal_item':
        index = next((index for index, code in enumerate(case['slots']) if code and
                      case['items'][str(code)]['type'] == 1 and case['items'][str(code)]['heal_hp'] != 0), -1)
        result = {'native': index + 1}
    else:
        owner, found, evaluated = case['units'][case['owner']], -1, []
        for index in range(case['cursor'], len(case['units'])):
            unit = case['units'][index]
            if unit is None or index == case['owner'] or unit['side'] & owner['side'] & 0x870000:
                continue
            if max(abs(unit['coord'][axis] - owner['coord'][axis]) for axis in [0, 1]) > case['radius']:
                continue
            threshold = min(80, max(10, unit['max_hp'] * (12 + draw(18)) // 100))
            evaluated.append({'index': index, 'threshold': threshold})
            native_sid = -1 if unit['removed'] else unit['sid']
            if unit['hp'] <= threshold and (case['excluded'] == -1 or native_sid != case['excluded']):
                found = index
                break
        result = {'native': found + 1, 'evaluated': evaluated}
    if position != len(draws):
        raise ValueError('Unused original priority RNG values')
    return result


def execute(base: int, mapped: bytearray, case: dict) -> dict:
    from unicorn import Uc, UC_ARCH_X86, UC_MODE_32, UC_HOOK_CODE
    from unicorn.x86_const import UC_X86_REG_EAX, UC_X86_REG_EBP, UC_X86_REG_EDI, UC_X86_REG_ESI, UC_X86_REG_EIP, UC_X86_REG_ESP
    machine = Uc(UC_ARCH_X86, UC_MODE_32)
    machine.mem_map(base, len(mapped))
    machine.mem_write(base, bytes(mapped))
    machine.mem_map(0x10000000, 0x80000)
    objects, actors, items, stack, sentinel = 0x10010000, 0x10040000, 0x10060000, 0x1007fe00, 0x10000000

    def put(address, value): machine.mem_write(address, struct.pack('<I', value & 0xffffffff))
    def get(address): return struct.unpack('<I', machine.mem_read(address, 4))[0]

    put(0x4c1bc8, actors)
    put(0x4c1b40, items)
    put(0x4c1e8c, 1)
    put(0x4795d4, case['seed'])
    put(0x4795d8, 0x87654321)
    machine.mem_write(0x4c34c0, bytes(200 * 4))
    kind, owner_index = case['kind'], case.get('owner', 0)
    owner, actor = objects + owner_index * 0x200, actors + owner_index * 0x1fc
    put(owner + 0xa4, owner_index)
    if kind == 'dying':
        for index, unit in enumerate(case['units']):
            if unit is None: continue
            obj, live = objects + index * 0x200, actors + index * 0x1fc
            put(0x4c34c0 + index * 4, obj)
            put(obj + 4, unit['coord'][0] * 32)
            put(obj + 8, unit['coord'][1] * 32)
            put(obj + 0x64, 3)
            put(obj + 0xa4, index)
            put(obj + 0x80, 0x8000000 if unit['removed'] else 0)
            for offset, key in [(0x28, 'side'), (0xd8, 'hp'), (0xdc, 'max_hp'), (0x84, 'sid')]:
                put(live + offset, unit[key])
        put(actor + 0x1bc, case['excluded'] & 0xffff)
        entry, arguments = 0x40bf70, [owner, case['radius'], case['cursor']]
    elif kind == 'self_hp':
        put(actor + 0xd8, case['hp'])
        put(actor + 0xdc, case['max_hp'])
        entry, arguments = 0x40c110, [owner]
    elif kind == 'heal_item':
        for index, code in enumerate(case['slots']): put(actor + 0x138 + 4 * index, code)
        for code, item in case['items'].items():
            put(items + int(code) * 0xb0 + 8, item['type'])
            put(items + int(code) * 0xb0 + 0x2c, item['heal_hp'])
        entry, arguments = 0x40c1d0, [owner]
    else:
        entry, arguments = 0x440db1, []
        put(actor + 0x1d8, case['self_rate'])
        put(actor + 0x1d4, case['dying_rate'])
        put(owner + 0x98, case['attempted'])
        put(stack + 0x2c, actor)
        machine.reg_write(UC_X86_REG_EBP, owner)
    before = bytes(machine.mem_read(objects, 0x60000))
    draws, pending, steps = [], [], 0
    allowed = [(0x40bf70, 0x40c102), (0x40c110, 0x40c1a2), (0x40c1d0, 0x40c22f),
               (0x440db1, 0x440e3d), (0x40ba20, 0x40ba72), (0x44fa80, 0x44fac5), (0x458c10, 0x458cb3)]

    def guard(_machine, address, _size, _data):
        nonlocal steps
        if kind == 'priority' and address in [0x441035, 0x440e3d]:
            machine.emu_stop()
            return
        if not any(low <= address < high for low, high in allowed):
            raise ValueError(f'Unreviewed priority instruction: {address:#x}')
        steps += 1
        if pending and pending[-1][0] == address:
            _, bound = pending.pop()
            draws.append({'bound': bound, 'value': machine.reg_read(UC_X86_REG_EAX)})
        if address == 0x458c80:
            sp = machine.reg_read(UC_X86_REG_ESP)
            pending.append((get(sp), get(sp + 4)))

    machine.hook_add(UC_HOOK_CODE, guard)
    machine.mem_write(stack, struct.pack('<' + 'I' * (1 + len(arguments)), sentinel, *arguments))
    machine.reg_write(UC_X86_REG_ESP, stack)
    machine.emu_start(entry, sentinel, count=LIMIT)
    stop = machine.reg_read(UC_X86_REG_EIP)
    model = expected(case, draws)
    normal = kind != 'priority'
    if pending or normal and stop != sentinel or not normal and hex(stop) != model['stop']:
        raise ValueError('Priority function did not reach the declared boundary')
    if normal:
        if machine.reg_read(UC_X86_REG_EAX) != model['native']:
            raise ValueError(f'Native {kind} output differs from independent model: {case} {draws}')
        after_expected = before
    else:
        actual = {'kind': machine.reg_read(UC_X86_REG_EDI), 'attempted': get(owner + 0x98),
                  'next_roll': machine.reg_read(UC_X86_REG_ESI), 'stop': hex(stop)}
        if actual != model: raise ValueError('Native priority prefix differs from independent model')
        after_expected = bytearray(before)
        struct.pack_into('<I', after_expected, owner - objects + 0x98, model['attempted'])
    if bytes(machine.mem_read(objects, 0x60000)) != bytes(after_expected):
        raise ValueError('Priority evidence changed unrelated object, actor or inventory memory')
    return {'input': case, 'draws': draws, 'result': model, 'normal_return': normal, 'instructions': steps}


def check_packet(packet: dict) -> None:
    if packet.get('schema') != 'hsl_ai_priority_native.v1' or packet.get('exe_sha256') != EXE_SHA or packet.get('native_execution') is not True:
        raise ValueError('Missing original priority executable identity')
    if [row['input'] for row in packet['cases']] != fixtures(): raise ValueError('Priority coverage differs')
    for row in packet['cases']:
        if row['normal_return'] != (row['input']['kind'] != 'priority') or not 0 < row['instructions'] < LIMIT or row['result'] != expected(row['input'], row['draws']):
            raise ValueError('Saved original priority result/boundary differs')


def execute_packet(exe: Path) -> dict:
    """Run the bounded original instructions on the documented EXE and assemble the packet."""
    base, mapped = image(exe.read_bytes())
    packet = {'schema': 'hsl_ai_priority_native.v1', 'evidence_tier': 'static-derived',
              'exe_sha256': EXE_SHA, 'native_execution': True,
              'cases': [execute(base, mapped, case) for case in fixtures()],
              'limits': ['Synthetic original instructions and RNG; no callee stubs, Wine, host input or natural gameplay.',
                         'Priority prefix stops before support checks or state dispatch; it is not a full AI normal return.',
                         'No native item effects, healing magic, targeting/path scoring or whole-turn RNG equivalence.']}
    return packet


def summary_line(packet: dict, executed_now: bool) -> str:
    normal = sum(row['normal_return'] for row in packet['cases'])
    return f'AI_PRIORITY_NATIVE_PASS normal_returns={normal} prefixes={len(packet["cases"]) - normal} executed_now={executed_now}'


TASK = ProbeTask('ai_priority', PACKET, check_packet, execute_packet, summary_line)


def tasks() -> list[ProbeTask]:
    return [TASK]
