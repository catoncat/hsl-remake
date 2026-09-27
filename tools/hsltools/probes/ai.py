"""Execute original target/action selectors in bounded synthetic x86 memory.

All callees execute their original bytes. The original RNG is initialized in
memory, never replaced. No Wine, OS calls, natural gameplay or pathfinding claim.

Registry task ai (family probe, hsltools.probes._base.ProbeTask): check validates the
tracked packet against the independent model; generate executes the original instructions
(needs the documented hsl01.exe and unicorn). Bodies moved verbatim from the former hsl_native_ai_probe.py.
"""
from __future__ import annotations
import copy
import json
from pathlib import Path
import struct

from hsltools.native.image import EXE_SHA, image
from hsltools.paths import ROOT
from hsltools.probes._base import ProbeTask

PACKET = ROOT / 'docs/evidence_packets/static_reverse/original_ai_decisions.json'

JOB_GROUPS = {1: [85, 87, 90, 91, 97, 98, 99, 100], 2: [83, 84],
              3: [80, 81, 82], 4: [88, 89], 5: [92, 93], 6: [94, 95, 96]}


def fixtures() -> list[dict]:
    rows = []
    for seed in [1, 19]:
        for magic, special in [(0, 0), (95, 0), (0, 100), (50, 50), (20, 90), (100, 100)]:
            for available in [(False, False), (True, False), (False, True), (True, True)]:
                for silence in [False, True]:
                    rows.append({'kind': 'action', 'seed': [seed, 0x87654321], 'magic_rate': magic,
                                 'special_rate': special, 'magic_available': available[0],
                                 'special_available': available[1], 'silenced': silence})
    units = [
        {'coord': [10, 10], 'side': 0x20000, 'hp': 100, 'level': 3, 'job': 90, 'sid': 26, 'removed': False},
        {'coord': [16, 10], 'side': 0x10000, 'hp': 40, 'level': 5, 'job': 80, 'sid': 0, 'removed': False},
        {'coord': [13, 14], 'side': 0x10000, 'hp': 70, 'level': 2, 'job': 90, 'sid': 21, 'removed': False},
        {'coord': [13, 10], 'side': 0x10000, 'hp': 10, 'level': 7, 'job': 83, 'sid': 22, 'removed': False},
        {'coord': [11, 10], 'side': 0x20000, 'hp': 1, 'level': 1, 'job': 90, 'sid': 25, 'removed': False},
        {'coord': [11, 10], 'side': 0x10000, 'hp': 0, 'level': 1, 'job': 90, 'sid': 25, 'removed': True},
        {'coord': [30, 30], 'side': 0x10000, 'hp': 1, 'level': 1, 'job': 94, 'sid': 24, 'removed': False},
        None,
        {'coord': [9, 7], 'side': 0x10000, 'hp': 45, 'level': 3, 'job': 92, 'sid': 23, 'removed': False}]
    base = {'kind': 'target', 'owner': 0, 'units': units, 'range': 8, 'near_range': 5, 'excluded_sid': -1}
    for seed in [1, 19]:
        for mode in range(7):
            for preference in range(7):
                rows.append({**copy.deepcopy(base), 'mode': mode, 'preference': preference, 'seed': [seed, 0x87654321]})
    for radius, near, excluded in [(0, 0, -1), (4, 0, -1), (8, 0, 0), (8, 5, 21), (8, 5, 22)]:
        rows.append({**copy.deepcopy(base), 'range': radius, 'near_range': near, 'excluded_sid': excluded,
                     'mode': 3, 'preference': 1, 'seed': [7, 0x87654321]})
    # Slot zero is a real target but is also the preference sentinel in the original.
    swapped = copy.deepcopy(base)
    swapped['units'][0], swapped['units'][2] = swapped['units'][2], swapped['units'][0]
    rows.append({**swapped, 'owner': 2, 'mode': 3, 'preference': 1, 'seed': [7, 0x87654321]})
    return rows


def expected(case: dict, draws: list[dict]) -> int:
    cursor = 0

    def take(bound):
        nonlocal cursor
        if cursor >= len(draws) or draws[cursor]['bound'] != bound or not 0 <= draws[cursor]['value'] < bound:
            raise ValueError('AI native RNG sequence or bounds differ')
        value = draws[cursor]['value']
        cursor += 1
        return value

    if case['kind'] == 'action':
        roll = take(99) + 1
        order = [2, 1] if roll & 1 else [1, 2]
        result = 0
        for index, channel in enumerate(order):
            valid = case['special_available'] if channel == 2 else case['magic_available'] and not case['silenced']
            if not valid: continue
            if roll <= case['special_rate' if channel == 2 else 'magic_rate']:
                result = channel
                break
            if index == 0: roll = take(99) + 1
    else:
        owner = case['units'][case['owner']]
        best, previous, preferred, minimum, maximum = -1, -1, 0, 700000, 0
        for index, unit in enumerate(case['units']):
            if not unit or index == case['owner'] or unit['removed'] or owner['side'] & unit['side'] & 0x870000:
                continue
            dx, dy = unit['coord'][0] - owner['coord'][0], unit['coord'][1] - owner['coord'][1]
            if dx * dx + dy * dy > case['range'] ** 2: continue
            mode = case['mode']
            score = unit['hp'] if mode in [1, 2] else unit['level'] if mode in [5, 6] else 32 * (abs(dx) + abs(dy))
            improved = mode == 0 or (score < minimum if mode in [1, 3, 5] else score > maximum)
            if improved:
                if mode in [1, 3, 5]: minimum = score
                if mode in [2, 4, 6]: maximum = score
                if best != -1 and take(2): continue
                previous, best = best, index
            elif case['preference'] == 0:
                continue
            if case['excluded_sid'] != -1 and case['excluded_sid'] == unit['sid']:
                best = previous
                continue
            if dx * dx + dy * dy > case['near_range'] ** 2 or unit['job'] not in JOB_GROUPS.get(case['preference'], []):
                continue
            if preferred not in [0, -1] and take(2): continue
            preferred = index
        result = (preferred if preferred != 0 else best) + 1
    if cursor != len(draws): raise ValueError('AI independent replay did not consume all original draws')
    return result


def execute(base: int, mapped: bytearray, case: dict) -> dict:
    from unicorn import Uc, UC_ARCH_X86, UC_MODE_32, UC_HOOK_CODE
    from unicorn.x86_const import UC_X86_REG_EAX, UC_X86_REG_EIP, UC_X86_REG_ESP
    machine = Uc(UC_ARCH_X86, UC_MODE_32)
    machine.mem_map(base, len(mapped))
    machine.mem_write(base, bytes(mapped))
    machine.mem_map(0x10000000, 0x80000)
    objects, actors, stack, sentinel = 0x10010000, 0x10040000, 0x1007ff00, 0x10000000

    def put(address, value): machine.mem_write(address, struct.pack('<I', value & 0xffffffff))
    def get(address): return struct.unpack('<I', machine.mem_read(address, 4))[0]

    put(0x4c1bc8, actors)
    put(0x4c1e8c, 1)
    put(0x4795d4, case['seed'][0])
    put(0x4795d8, case['seed'][1])
    target_case = case['kind'] == 'target'
    if target_case:
        machine.mem_write(0x4c34c0, bytes(200 * 4))
        for index, unit in enumerate(case['units']):
            if unit is None: continue
            obj, actor = objects + index * 0x200, actors + index * 0x1fc
            put(0x4c34c0 + index * 4, obj)
            put(obj + 4, unit['coord'][0] * 32)
            put(obj + 8, unit['coord'][1] * 32)
            put(obj + 0x80, 0x8000000 if unit['removed'] else 0)
            put(obj + 0x64, 3)
            put(obj + 0xa4, index)
            for offset, key in [(0x28, 'side'), (0xd8, 'hp'), (0x9c, 'level'), (0x18, 'job'), (0x84, 'sid')]:
                put(actor + offset, unit[key])
        owner = objects + case['owner'] * 0x200
        actor = actors + case['owner'] * 0x1fc
        put(actor + 0x12c, case['near_range'])
        put(actor + 0x1bc, case['excluded_sid'])
        entry, arguments = 0x40bb80, [owner, case['mode'], case['preference'], case['range']]
    else:
        put(objects + 0xa4, 0)
        put(actors + 0x24, 2 if case['silenced'] else 0)
        put(actors + 0x1ec, case['special_rate'])
        put(actors + 0x1f0, case['magic_rate'])
        entry, arguments = 0x40c570, [objects, int(case['magic_available']), int(case['special_available'])]
    before = bytes(machine.mem_read(objects, 0x40000))
    draws, returning, steps = [], [], 0
    allowed = [(0x40bb80, 0x40be9e), (0x40ba20, 0x40ba72), (0x44fa80, 0x44fac5),
               (0x45ec32, 0x45ec63), (0x40c570, 0x40c61d), (0x458c10, 0x458cb3)]

    def guard(_machine, address, _size, _data):
        nonlocal steps
        steps += 1
        if not any(low <= address < high for low, high in allowed):
            raise ValueError(f'Unreviewed AI callee: {address:#x}')
        if returning and returning[-1][0] == address:
            _, bound = returning.pop()
            raw = machine.reg_read(UC_X86_REG_EAX)
            draws.append({'bound': bound, 'value': raw & 1 if bound == 2 else raw})
        if address == (0x458c10 if target_case else 0x458c80):
            sp = machine.reg_read(UC_X86_REG_ESP)
            returning.append((get(sp), 2 if target_case else get(sp + 4)))

    machine.hook_add(UC_HOOK_CODE, guard)
    machine.mem_write(stack, struct.pack('<' + 'I' * (len(arguments) + 1), sentinel, *arguments))
    machine.reg_write(UC_X86_REG_ESP, stack)
    machine.emu_start(entry, sentinel, count=16384)
    if machine.reg_read(UC_X86_REG_EIP) != sentinel or returning:
        raise ValueError('Original AI function did not normally return within 16384 instructions')
    result = machine.reg_read(UC_X86_REG_EAX)
    if result != expected(case, draws):
        raise ValueError(f'Original AI differs from independent replay: {case} {draws} result={result}')
    if before != bytes(machine.mem_read(objects, 0x40000)):
        raise ValueError('AI selector changed an input unit')
    return {'input': case, 'draws': draws, 'native': result, 'normal_return': True, 'instructions': steps}


def check_packet(packet: dict) -> None:
    if packet.get('exe_sha256') != EXE_SHA or packet.get('native_execution') is not True:
        raise ValueError('AI packet lacks native executable identity')
    if [row['input'] for row in packet['cases']] != fixtures(): raise ValueError('AI fixture coverage changed')
    for row in packet['cases']:
        if row['normal_return'] is not True or not 0 < row['instructions'] < 16384 or row['native'] != expected(row['input'], row['draws']):
            raise ValueError('Saved AI result or normal-return boundary differs')


def execute_packet(exe: Path) -> dict:
    """Run the bounded original instructions on the documented EXE and assemble the packet."""
    base, mapped = image(exe.read_bytes())
    packet = {'schema': 'hsl_ai_decisions_native.v1', 'evidence_tier': 'static-derived',
              'exe_sha256': EXE_SHA, 'native_execution': True, 'entries': ['0x40bb80', '0x40c570'],
              'rng': '0x458c10/0x458c80 state 0x4795d4/0x4795d8; NOT 0x42c780 state',
              'cases': [execute(base, mapped, case) for case in fixtures()],
              'limits': ['Synthetic unit table; original input functions and RNG execute unchanged to normal return.',
                         'No pathfinding, ability-list generation, full actor state machine, support action or gameplay execution.',
                         'Excluded-ID restore follows original previous-candidate state; undefined stack cases are not inferred.']}
    return packet


def summary_line(packet: dict, executed_now: bool) -> str:
    return f'AI_NATIVE_DECISIONS_PASS cases={len(packet["cases"])} executed_now={executed_now}'


TASK = ProbeTask('ai', PACKET, check_packet, execute_packet, summary_line)


def tasks() -> list[ProbeTask]:
    return [TASK]
