"""Execute original per-target EXP conversion and isolated final-award suffixes.

Only 0x40a5d0 returns normally. The award and kill-state slices stop before UI,
status-tick or queue callbacks; no callee is replaced or skipped by a stub.

Registry task experience (family probe, hsltools.probes._base.ProbeTask): check validates the
tracked packet against the independent model; generate executes the original instructions
(needs the documented hsl01.exe and unicorn). Bodies moved verbatim from the former hsl_native_experience_probe.py.
"""
from __future__ import annotations
import hashlib
import json
from pathlib import Path
import struct

from hsltools.native.image import EXE_SHA, image
from hsltools.native.machine import machine_for
from hsltools.paths import ROOT
from hsltools.probes._base import ProbeTask
from hsltools.probes.status_lifecycle import application_fixtures, execute as status_prefix, expected_application

PACKET = ROOT / 'docs/evidence_packets/static_reverse/original_experience.json'

ANCHOR_DIGEST = '891b5955ce7cb71c3733386cb130f56a1535ce837e616ddc586356e6e3fc6de8'
ANCHORS = [
    (0x40A61D, 27, 'Dead target adds kill_exp and reads prior low-word chain, capped at eight.'),
    (0x40B853, 53, 'Applicator converts this target contribution before returning EXP.'),
    (0x442B7B, 24, 'A new magic action clears its accumulated EXP and reward totals.'),
    (0x443100, 14, 'Local magic adds each target return to the same action EXP accumulator.'),
    (0x444776, 18, 'Zero remaining growth capacity discards EXP, not gold or loot.'),
    (0x4427A9, 62, 'Final award applies equipment EXP doubling then adds to actor EXP.'),
    (0x442936, 40, 'After payout, threshold and growth capacity govern the level-up phase.'),
    (0x4431DA, 57, 'Magic marks a kill and increments the chain only on the first kill in the cast.'),
    (0x443C09, 47, 'Own action finish keeps the low word only when a kill mark is present.'),
    (0x444637, 14, 'A surviving counter target clears the counterattacker chain.'),
    (0x447E40, 33, 'ITEM exp_x2 maps to the exact final-award flag 0x10.'),
    (0x40AD75, 40, 'Poison contributes ten per newly added duration unit, after cap nine.'),
    (0x40AEAE, 22, 'Silence contributes five per newly added duration unit, after cap nine.'),
]


def fixtures() -> list[dict]:
    common = dict(seed=[7, 0x87654321], contribution=36, attacker_level=3,
                  target_level=3, target_hp=40, kill_exp=16, kill_word=0)
    rows = []
    for contribution in [0, 1, 2, 5, 20, 36, 100]:
        for attacker, target in [(1, 1), (1, 2), (1, 10), (2, 1), (7, 2), (80, 1)]:
            rows.append(dict(common, contribution=contribution, attacker_level=attacker, target_level=target))
    for chain in [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 0x10002]:
        for attacker, target in [(2, 1), (1, 2)]:
            rows.append(dict(common, attacker_level=attacker, target_level=target, target_hp=0, kill_word=chain))
    for seed in [1, 19, 101]:
        for contribution in [1, 20, 250]:
            rows.append(dict(common, seed=[seed, 0x87654321], contribution=contribution, target_hp=0, kill_word=2))
    return rows


def status_cases() -> list[dict]:
    # New observation of contribution only; existing packet remains unchanged.
    return [case for case in application_fixtures() if case['seed'][0] == 1]


def status_expected(case: dict, draws: list[dict]) -> dict:
    result = expected_application(case, draws)
    key = case['status']
    added = (result['status_counters'][key] & 0xffff) - (case['words'][key] & 0xffff)
    return dict(result, contribution=added * (10 if key == 'poison' else 5))


def expected(case: dict, draws: list[dict]) -> int:
    cursor = 0
    def take(bound: int) -> int:
        nonlocal cursor
        if cursor >= len(draws) or draws[cursor]['bound'] != bound:
            raise ValueError('EXP random-call order differs')
        value = draws[cursor]['value']; cursor += 1
        if not (value == 0 if bound == 0 else 0 <= value < bound):
            raise ValueError('EXP random value outside native bound')
        return value
    contribution = case['contribution']
    result = 0
    if contribution:
        reward = case['kill_exp'] if case['target_hp'] == 0 else 0
        delta = case['attacker_level'] - case['target_level']
        if delta >= 0:
            noise = take(contribution // 2)
            result = (contribution * 40 // 100 + reward + noise) * 100 // (max(1, min(5, delta)) * 80)
        else:
            result = min(5, -delta) * contribution + reward
        result = max(1, result - take(result * 30 // 100))
        chain = min(8, case['kill_word'] & 0xffff) if case['target_hp'] == 0 else 0
        if chain: result = result * (100 + chain * 50) // 100
    if cursor != len(draws): raise ValueError('EXP has unconsumed native draws')
    return result


def execute(base: int, mapped: bytearray, case: dict) -> dict:
    from unicorn import UC_HOOK_CODE
    from unicorn.x86_const import UC_X86_REG_EAX, UC_X86_REG_EIP, UC_X86_REG_ESP
    m = machine_for(base, mapped)
    obj, target_obj, actor, target = 0x10001000, 0x10002000, 0x10004000, 0x100041fc
    stack, stop = 0x1001ff00, 0x10000000
    def put(at, value): m.mem_write(at, struct.pack('<I', value & 0xffffffff))
    def get(at): return struct.unpack('<I', m.mem_read(at, 4))[0]
    put(0x4c1bc8, actor); put(obj + 0xa4, 0); put(target_obj + 0xa4, 1)
    put(actor + 0x9c, case['attacker_level']); put(target + 0x9c, case['target_level'])
    put(target + 0xd8, case['target_hp']); put(target + 0x90, case['kill_exp'])
    put(actor + 0xa8, case['kill_word']); put(0x4c13fc, case['contribution'])
    put(0x4c1e8c, 1); put(0x4c3044, case['seed'][0]); put(0x4c3040, case['seed'][1])
    before = bytes(m.mem_read(obj, 0x4000))
    steps, draws, returning = 0, [], []
    def guard(_m, address, _size, _data):
        nonlocal steps
        steps += 1
        if not any(lo <= address < hi for lo, hi in [(0x40a5d0, 0x40a78d), (0x42c780, 0x42c7d9), (0x458bb0, 0x458cb3)]):
            raise ValueError(f'Unreviewed EXP callee {address:#x}')
        if returning and returning[-1][0] == address:
            _, bound = returning.pop(); draws.append(dict(bound=bound, value=m.reg_read(UC_X86_REG_EAX)))
        if address == 0x42c780:
            esp = m.reg_read(UC_X86_REG_ESP); returning.append((get(esp), get(esp + 4)))
    m.hook_add(UC_HOOK_CODE, guard)
    m.mem_write(stack, struct.pack('<3I', stop, obj, target_obj)); m.reg_write(UC_X86_REG_ESP, stack)
    m.emu_start(0x40a5d0, stop, count=4096)
    actual = m.reg_read(UC_X86_REG_EAX)
    if m.reg_read(UC_X86_REG_EIP) != stop or returning or m.reg_read(UC_X86_REG_ESP) != stack + 4:
        raise ValueError('EXP helper did not return normally within budget')
    if actual != expected(case, draws) or before != bytes(m.mem_read(obj, 0x4000)):
        raise ValueError(f'EXP native mismatch or actor mutation: {case} {draws} {actual}')
    return dict(input=case, native=actual, draws=draws, normal_return=True, instructions=steps, actors_unchanged=True)


def suffix_fixtures() -> list[dict]:
    return ([dict(kind='award', exp=exp, amount=amount, effects=effects)
             for exp in [0, 99, 1800] for amount in [1, 36, 220] for effects in [0, 0x10]] +
            [dict(kind='finish', word=word) for word in [0, 1, 8, 0x10000, 0x10001, 0x10008]] +
            [dict(kind='magic_kill', word=word, previous_kills=kills)
             for word in [0, 3, 0x10003] for kills in [0, 1]])


def execute_suffix(base: int, mapped: bytearray, case: dict) -> dict:
    from unicorn import UC_HOOK_CODE
    from unicorn.x86_const import UC_X86_REG_EAX, UC_X86_REG_EBX, UC_X86_REG_EBP, UC_X86_REG_EDI, UC_X86_REG_ESI, UC_X86_REG_EIP, UC_X86_REG_ESP
    m = machine_for(base, mapped)
    obj, actor, stack = 0x10001000, 0x10004000, 0x1001ff00
    def put(at, value): m.mem_write(at, struct.pack('<I', value & 0xffffffff))
    def get(at): return struct.unpack('<I', m.mem_read(at, 4))[0]
    put(0x4c1bc8, actor); put(obj + 0xa4, 0)
    m.reg_write(UC_X86_REG_ESP, stack)
    if case['kind'] == 'award':
        put(actor + 0x88, case['exp']); put(actor + 0x18c, case['effects'])
        m.reg_write(UC_X86_REG_EBX, obj); m.reg_write(UC_X86_REG_EBP, case['amount'])
        entry, stops = 0x4427a9, [0x4427e7]
        allowed = [(entry, stops[0]), (0x40e2c0, 0x40e2d0), (0x40e240, 0x40e26e)]
    elif case['kind'] == 'finish':
        put(actor + 0xa8, case['word'])
        m.reg_write(UC_X86_REG_EDI, actor); m.reg_write(UC_X86_REG_ESI, obj)
        m.reg_write(UC_X86_REG_EBX, 0x10000)
        entry, stops = 0x443c01, [0x443c1a, 0x443c38]
        allowed = [(entry, 0x443c39)]
    else:
        put(actor + 0xa8, case['word']); put(0x4c2974, case['previous_kills'])
        m.reg_write(UC_X86_REG_ESI, actor)
        entry, stops = 0x4431da, [0x44320d, 0x443213]
        allowed = [(entry, 0x443214)]
    steps = 0
    def guard(_m, address, _size, _data):
        nonlocal steps
        if address in stops: m.emu_stop(); return
        steps += 1
        if not any(lo <= address < hi for lo, hi in allowed): raise ValueError(f'Unexpected EXP suffix call {address:#x}')
    m.hook_add(UC_HOOK_CODE, guard); m.emu_start(entry, 0x10000000, count=256)
    stop = m.reg_read(UC_X86_REG_EIP)
    if stop not in stops: raise ValueError('EXP suffix did not reach declared stop')
    if case['kind'] == 'award':
        result = dict(exp=get(actor + 0x88), awarded=m.reg_read(UC_X86_REG_EBP))
        amount = case['amount'] * (2 if case['effects'] & 0x10 else 1)
        wanted = dict(exp=case['exp'] + amount, awarded=amount)
    else:
        result = dict(word=get(actor + 0xa8))
        wanted = dict(word=((case['word'] & 0xffff) if case['word'] & 0x10000 else 0) if case['kind'] == 'finish'
                      else (case['word'] | 0x10000) + (case['previous_kills'] == 0))
    if result != wanted: raise ValueError(f'EXP suffix mismatch {case}: {result} != {wanted}')
    return dict(input=case, native=result, normal_return=False, entry=hex(entry), stop_address=hex(stop), instructions=steps)


def check(packet: dict) -> None:
    if packet.get('schema') != 'hsl_native_experience.v1' or packet.get('exe_sha256') != EXE_SHA or packet.get('native_execution') is not True:
        raise ValueError('Missing EXP original identity')
    if [row['input'] for row in packet['cases']] != fixtures() or [row['input'] for row in packet['suffixes']] != suffix_fixtures():
        raise ValueError('EXP coverage differs')
    for row in packet['cases']:
        if row['native'] != expected(row['input'], row['draws']) or row['normal_return'] is not True or row['actors_unchanged'] is not True or not 0 < row['instructions'] < 4096:
            raise ValueError('EXP result or normal-return boundary differs')
    for row in packet['suffixes']:
        case = row['input']; kind = case['kind']
        if kind == 'award':
            amount = case['amount'] * (2 if case['effects'] & 0x10 else 1)
            wanted = dict(exp=case['exp'] + amount, awarded=amount); stops = ['0x4427e7']
        else:
            wanted = dict(word=(case['word'] & 0xffff if case['word'] & 0x10000 else 0) if kind == 'finish' else (case['word'] | 0x10000) + (case['previous_kills'] == 0))
            stops = ['0x443c1a', '0x443c38'] if kind == 'finish' else ['0x44320d', '0x443213']
        if row['native'] != wanted or row['normal_return'] is not False or row['stop_address'] not in stops or not 0 < row['instructions'] < 256:
            raise ValueError('EXP suffix result or boundary differs')
    if [(int(row['address'], 16), len(bytes.fromhex(row['bytes'])), row['meaning']) for row in packet['anchors']] != ANCHORS:
        raise ValueError('EXP caller anchors differ')
    if hashlib.sha256(b''.join(bytes.fromhex(row['bytes']) for row in packet['anchors'])).hexdigest() != ANCHOR_DIGEST:
        raise ValueError('EXP caller bytes differ')
    if [row['input'] for row in packet['status_contributions']] != status_cases(): raise ValueError('Status contribution fixtures differ')
    for row in packet['status_contributions']:
        if row['native'] != status_expected(row['input'], row['draws']) or row['normal_return'] is not False or row['stop_address'] != '0x40b831':
            raise ValueError('Status contribution or prefix boundary differs')


def execute_packet(exe: Path) -> dict:
    """Run the bounded original instructions on the documented EXE and assemble the packet."""
    base, mapped = image(exe.read_bytes())
    packet = dict(schema='hsl_native_experience.v1', exe_sha256=EXE_SHA, evidence_tier='static-derived', native_execution=True,
                  cases=[execute(base, mapped, case) for case in fixtures()],
                  suffixes=[execute_suffix(base, mapped, case) for case in suffix_fixtures()],
                  status_contributions=[status_prefix(base, mapped, case, include_contribution=True) for case in status_cases()],
                  anchors=[dict(address=hex(at), bytes=bytes(mapped[at-base:at-base+length]).hex(), meaning=meaning) for at, length, meaning in ANCHORS],
                  limits=['Contribution conversion returns normally; final award and kill-state are bounded suffixes before presentation/queue calls.',
                          'One spell accumulates per-target EXP and awards once, not a campaign or victory reward pool.',
                          'Input actor levels, kill state, contributions and equipment flags are synthetic; source initialization is separate.'])
    return packet


def summary_line(packet: dict, executed_now: bool) -> str:
    return f'EXPERIENCE_NATIVE_PASS cases={len(packet["cases"])} suffixes={len(packet["suffixes"])} status_contributions={len(packet["status_contributions"])} executed_now={executed_now}'


TASK = ProbeTask('experience', PACKET, check, execute_packet, summary_line)


def tasks() -> list[ProbeTask]:
    return [TASK]
