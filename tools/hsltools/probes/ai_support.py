"""Original ally scanners to full return and two aid-priority blocks; no stubs.

Scans repeat through their genuine saved cursor. The priority suffix ends before
the remaining categories/dispatcher. Input objects, roster and seed are synthetic.

Registry task ai_support (family probe, hsltools.probes._base.ProbeTask): check validates the
tracked packet against the independent model; generate executes the original instructions
(needs the documented hsl01.exe and unicorn). Bodies moved verbatim from the former hsl_native_ai_support_probe.py.
"""
from __future__ import annotations
import copy
import json
from pathlib import Path
import struct

from hsltools.native.image import EXE_SHA, image
from hsltools.paths import ROOT
from hsltools.probes._base import ProbeTask

PACKET = ROOT / 'docs/evidence_packets/static_reverse/original_ai_support.json'

LIMIT = 24000
ANCHORS = [
    (0x44C949, 39, 'Source loader binds ai_help_otherhp to actor strategy offset +0x1dc.'),
    (0x44C970, 39, 'Source loader binds ai_help_status to actor strategy offset +0x1e0.'),
    (0x440E3D, 120, 'ai_help_otherhp (bit4/mode3) then ai_help_status (bit8/mode4), carrying the current roll.'),
    (0x440767, 27, 'Eight-cell healing-ally scan; continuation resumes after the previous target.'),
    (0x4407F8, 20, 'After all supported action-category attempts, resume the next healing target.'),
    (0x43FB93, 42, 'Status assistance calls the eight-cell ally scanner with a status-mask output.'),
    (0x440789, 22, 'Healing assistance uses the shared action-category selector before item/magic/special attempts.'),
    (0x4407D0, 40, 'Item category selects the first HP medicine and asks the movement helper for range-one access to this ally.'),
    (0x440959, 35, 'Status assistance also uses the shared action selector.'),
]


def fixtures() -> list[dict]:
    units = [
        dict(coord=[10, 10], side=0x20000, hp=100, max_hp=100, status_flags=0),
        dict(coord=[11, 10], side=0x10000, hp=1, max_hp=100, status_flags=1),
        dict(coord=[11, 11], side=0x20000, hp=30, max_hp=100, status_flags=2),
        None,
        dict(coord=[18, 18], side=0x20000, hp=1, max_hp=100, status_flags=1),
        dict(coord=[12, 10], side=0x20000, hp=4, max_hp=100, status_flags=16),
        dict(coord=[13, 10], side=0x20000, hp=0, max_hp=100, status_flags=9),
        dict(coord=[11, 10], side=0x60000, hp=1, max_hp=100, status_flags=1),
        dict(coord=[19, 10], side=0x20000, hp=1, max_hp=100, status_flags=1),
    ]
    result = [dict(kind=kind, units=copy.deepcopy(units), owner=0, radius=radius, seed=seed)
              for kind in ['heal', 'status'] for radius in [0, 1, 7, 8, 9] for seed in [1, 19]]
    for hp, maximum in [(1, 10), (1, 20), (11, 20), (29, 100), (170, 1000), (175, 10000)]:
        result.append(dict(kind='heal', units=[copy.deepcopy(units[0]), dict(units[2], hp=hp, max_hp=maximum)], owner=0, radius=8, seed=7))
    for rates in [(0, 0), (100, 100), (20, 90), (90, 20)]:
        for attempted in [0, 4, 8, 12]:
            for roll in [1, 30, 99]:
                result.append(dict(kind='priority', rates=list(rates), attempted=attempted, roll=roll, seed=7))
    return result


def expected(case: dict, draws: list[dict]) -> dict:
    position = 0
    def draw(bound):
        nonlocal position
        if position >= len(draws) or draws[position]['bound'] != bound or not 0 <= draws[position]['value'] < bound:
            raise ValueError('Support RNG order differs')
        value = draws[position]['value']; position += 1
        return value
    if case['kind'] == 'priority':
        attempted, roll, mode = case['attempted'], case['roll'], 0
        for index, flag in enumerate([4, 8]):
            if attempted & flag: continue
            attempted |= flag
            if roll <= case['rates'][index]: mode = index + 3; break
            roll = draw(99) + 1
        result = dict(mode=mode, attempted=attempted, next_roll=roll)
    else:
        owner = case['units'][case['owner']]
        found, masks = [], []
        for index, unit in enumerate(case['units']):
            if unit is None or index == case['owner'] or (unit['side'] & 0x870000) != (owner['side'] & 0x870000): continue
            if any(abs(unit['coord'][axis] - owner['coord'][axis]) > case['radius'] for axis in [0, 1]): continue
            mask = unit['status_flags'] & 15
            if case['kind'] == 'heal':
                threshold = unit['max_hp'] * (12 + draw(18)) // 100
                if threshold < 10: threshold = 10 + threshold % 10
                elif threshold > 160: threshold = 160 + threshold % 16
                selected = unit['max_hp'] - unit['hp'] >= 10 and unit['hp'] <= threshold
            else: selected = mask != 0
            if selected:
                found.append(index + 1)
                if case['kind'] == 'status': masks.append(mask)
        result = dict(indices=found + [0], masks=masks, exhausted_cursor=200)
    if position != len(draws): raise ValueError('Unconsumed support RNG draws')
    return result


def execute(base: int, mapped: bytearray, case: dict) -> dict:
    from unicorn import Uc, UC_ARCH_X86, UC_MODE_32, UC_HOOK_CODE
    from unicorn.x86_const import UC_X86_REG_EAX, UC_X86_REG_EBX, UC_X86_REG_EBP, UC_X86_REG_EDI, UC_X86_REG_ESI, UC_X86_REG_EIP, UC_X86_REG_ESP
    m = Uc(UC_ARCH_X86, UC_MODE_32)
    m.mem_map(base, len(mapped)); m.mem_write(base, bytes(mapped))
    m.mem_map(0x10000000, 0x80000)
    objects, actors, output, stack, stop = 0x10010000, 0x10040000, 0x10070000, 0x1007fe00, 0x10000000
    def put(at, value): m.mem_write(at, struct.pack('<I', value & 0xffffffff))
    def get(at): return struct.unpack('<I', m.mem_read(at, 4))[0]
    put(0x4c1bc8, actors); put(0x4c1e8c, 1)
    put(0x4795d4, case['seed']); put(0x4795d8, 0x87654321)
    m.mem_write(0x4c34c0, bytes(800))
    priority = case['kind'] == 'priority'
    owner_index = case.get('owner', 0); owner = objects + owner_index * 0x200
    if priority:
        put(objects + 0x98, case['attempted'])
        put(actors + 0x1dc, case['rates'][0]); put(actors + 0x1e0, case['rates'][1])
        m.reg_write(UC_X86_REG_EBP, objects); m.reg_write(UC_X86_REG_EBX, actors)
        m.reg_write(UC_X86_REG_ESI, case['roll']); m.reg_write(UC_X86_REG_EDI, 0)
        entry = 0x440e3d
    else:
        for index, unit in enumerate(case['units']):
            if unit is None: continue
            obj, actor = objects + index * 0x200, actors + index * 0x1fc
            put(0x4c34c0 + index * 4, obj)
            put(obj + 4, unit['coord'][0] * 32); put(obj + 8, unit['coord'][1] * 32)
            put(obj + 0x64, 3); put(obj + 0xa4, index)
            for offset, key in [(0x28, 'side'), (0xd8, 'hp'), (0xdc, 'max_hp'), (0x24, 'status_flags')]: put(actor + offset, unit[key])
        entry = 0x40c2f0 if case['kind'] == 'heal' else 0x40c3a0
    before = bytes(m.mem_read(objects, 0x60000))
    draws, pending, steps = [], [], 0
    def guard(_m, address, _size, _data):
        nonlocal steps
        if priority and address in [0x441035, 0x440eb5]: m.emu_stop(); return
        steps += 1
        if not any(lo <= address < hi for lo, hi in [(0x40c2f0, 0x40c480), (0x40c110, 0x40c1cf), (0x40ba20, 0x40ba72), (0x458c10, 0x458cb3), (0x440e3d, 0x440eb5)]):
            raise ValueError(f'Unreviewed support callee {address:#x}')
        if pending and pending[-1][0] == address:
            _, bound = pending.pop(); draws.append(dict(bound=bound, value=m.reg_read(UC_X86_REG_EAX)))
        if address == 0x458c80:
            sp = m.reg_read(UC_X86_REG_ESP); pending.append((get(sp), get(sp + 4)))
    m.hook_add(UC_HOOK_CODE, guard)
    indices, masks, continuations = [], [], []
    for invocation in range(1 if priority else len(case['units']) + 1):
        args = [] if priority else [owner, case['radius'], int(invocation > 0), output]
        put(output, 0xabcdef)
        m.mem_write(stack, struct.pack('<' + 'I' * (len(args) + 1), stop, *args)); m.reg_write(UC_X86_REG_ESP, stack)
        m.emu_start(entry, stop, count=LIMIT)
        end = m.reg_read(UC_X86_REG_EIP)
        if pending or (end not in [0x441035, 0x440eb5] if priority else end != stop or m.reg_read(UC_X86_REG_ESP) != stack + 4):
            raise ValueError('Support function did not reach declared boundary')
        if priority: break
        value = m.reg_read(UC_X86_REG_EAX); indices.append(value)
        cursor_address = 0x4c1a0c if case['kind'] == 'heal' else 0x4c1a18
        continuations.append(get(cursor_address))
        if case['kind'] == 'status' and value: masks.append(get(output))
        if not value:
            if get(output) != 0xabcdef: raise ValueError('Exhausted scanner changed output')
            break
    if priority:
        result = dict(mode=m.reg_read(UC_X86_REG_EDI), attempted=get(objects + 0x98), next_roll=m.reg_read(UC_X86_REG_ESI))
        after_expected = bytearray(before); struct.pack_into('<I', after_expected, 0x98, result['attempted'])
    else:
        result = dict(indices=indices, masks=masks, exhausted_cursor=continuations[-1])
        after_expected = before
        if continuations != [value - 1 if value else 200 for value in indices]: raise ValueError('Saved native cursor differs')
    if result != expected(case, draws) or bytes(m.mem_read(objects, 0x60000)) != bytes(after_expected):
        raise ValueError(f'Support result or unrelated memory changed: {case} {result}')
    return dict(input=case, result=result, draws=draws, normal_return=not priority,
                instructions=steps, calls=1 if priority else len(indices), stop_address=hex(end))


def check(packet: dict) -> None:
    if packet.get('schema') != 'hsl_ai_support_native.v1' or packet.get('exe_sha256') != EXE_SHA or packet.get('native_execution') is not True: raise ValueError('Invalid support identity')
    if [row['input'] for row in packet['cases']] != fixtures(): raise ValueError('Support coverage differs')
    for row in packet['cases']:
        normal = row['input']['kind'] != 'priority'
        if row['normal_return'] is not normal or not 0 < row['instructions'] < LIMIT * row['calls'] or row['result'] != expected(row['input'], row['draws']): raise ValueError('Support result/boundary differs')
        if row['stop_address'] not in (['0x10000000'] if normal else ['0x441035', '0x440eb5']): raise ValueError('Unexpected support stop')
    if [(int(row['address'], 16), len(bytes.fromhex(row['bytes'])), row['meaning']) for row in packet['anchors']] != ANCHORS: raise ValueError('Support caller anchors differ')


def execute_packet(exe: Path) -> dict:
    """Run the bounded original instructions on the documented EXE and assemble the packet."""
    base, mapped = image(exe.read_bytes())
    packet = dict(schema='hsl_ai_support_native.v1', evidence_tier='static-derived', exe_sha256=EXE_SHA, native_execution=True,
                  cases=[execute(base, mapped, case) for case in fixtures()],
                  anchors=[dict(address=hex(at), bytes=bytes(mapped[at-base:at-base+size]).hex(), meaning=meaning) for at, size, meaning in ANCHORS],
                  limits=['Ally scanners and original random/health/side helpers return normally across consecutive calls.',
                          'Priority suffix stops before other aid/attack checks and dispatcher. No native movement planner, cast, or whole AI turn is executed.',
                          'Original scans do not independently exclude HP0 or unsupported cures; the live living/owned-effect adapter must do so explicitly.'])
    return packet


def summary_line(packet: dict, executed_now: bool) -> str:
    return f'AI_SUPPORT_NATIVE_PASS scans={sum(c["normal_return"] for c in packet["cases"])} suffixes={sum(not c["normal_return"] for c in packet["cases"])} executed_now={executed_now}'


TASK = ProbeTask('ai_support', PACKET, check, execute_packet, summary_line)


def tasks() -> list[ProbeTask]:
    return [TASK]
