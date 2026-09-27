"""Bounded original status hit/magnitude and equipment-immunity helpers.

Executes only reviewed, pure x86 helpers in an isolated Unicorn memory image.
No Wine, OS calls, process attachment, function stubs or original-file writes.
This does not execute the status applicator or the original whole spell/UI.

Registry task status_roll (family probe, hsltools.probes._base.ProbeTask): check validates the
tracked packet against the independent model; generate executes the original instructions
(needs the documented hsl01.exe and unicorn). Bodies moved verbatim from the former hsl_native_status_roll_probe.py.
"""
from __future__ import annotations
import json
from pathlib import Path
import struct

from hsltools.native.image import EXE_SHA, image
from hsltools.paths import ROOT
from hsltools.probes._base import ProbeTask

PACKET = ROOT / 'docs/evidence_packets/static_reverse/original_status_rolls.json'

def fixtures() -> list[dict]:
    result = []
    for seed in [1, 7, 19, 101]:
        for proc in [0, 6]:
            for resistance in [0, 80]:
                result.append({'seed': [seed, 0x87654321], 'proc': proc, 'channel': 0,
                               'low': 16, 'high': 32, 'hit_ratio': 80, 'status_hit_ratio': 65,
                               'level': 3, 'mind': 10, 'magic_attack': 24,
                               'hit_bonus': 0, 'magic_hit_bonus': 0, 'no_attack': False,
                               'element': 2, 'resistance': resistance})
    for hit, no_attack in [(0, False), (0, True), (100, False)]:
        result.append({**result[0], 'proc': 6, 'status_hit_ratio': hit, 'no_attack': no_attack})
    for level, mind, power, bonus in [(80, 36, 80, 0), (100, 50, 110, 8), (1, 1, 0, 0)]:
        result.append({**result[0], 'level': level, 'mind': mind, 'magic_attack': power,
                       'hit_ratio': 100, 'magic_hit_bonus': bonus})
    return result


def independent(case: dict, draws: list[dict]) -> dict:
    cursor = 0

    def take(bound):
        nonlocal cursor
        if cursor >= len(draws) or draws[cursor]['bound'] != bound:
            raise ValueError('Unexpected native random-call sequence')
        value = draws[cursor]['value']
        if not 0 <= value < bound:
            raise ValueError('Native range draw outside its requested bound')
        cursor += 1
        return value

    hit = case['status_hit_ratio'] if case['proc'] & 4 else case['hit_ratio'] + case['hit_bonus'] + case['magic_hit_bonus']
    roll = take(100) + 1
    bonus = case['hit_bonus']
    if not case['no_attack'] and roll > hit:
        value = 0
        if not case['proc'] & 4:
            bonus += roll // 10
    else:
        if not case['proc'] & 4:
            bonus = 0
        half = (case['high'] - case['low']) // 2
        sampled = case['low'] + half - take(half + 1) + take(half + 1)
        if case['proc'] & 2:
            value = sampled
        else:
            mind = case['mind'] // 2 if case['mind'] < 36 else (case['mind'] - 36) // 4 + 18
            value = (min(80, max(1, case['level'])) + mind + sampled) * case['magic_attack'] // 100
        if value < 3:
            value += 3 * ((5 - value) // 3)
        if not case['proc'] & 1:
            value = value * (100 - min(80, case['resistance'])) // 100
    if cursor != len(draws):
        raise ValueError('Native helper consumed additional random values')
    return {'value': value, 'hit_bonus_after': bonus}


def run_case(base: int, mapped: bytearray, case: dict) -> dict:
    from unicorn import Uc, UC_ARCH_X86, UC_MODE_32, UC_HOOK_CODE
    from unicorn.x86_const import UC_X86_REG_EAX, UC_X86_REG_EIP, UC_X86_REG_ESP
    machine = Uc(UC_ARCH_X86, UC_MODE_32)
    machine.mem_map(base, len(mapped))
    machine.mem_write(base, bytes(mapped))
    machine.mem_map(0x10000000, 0x20000)
    caster, target, record, bonus = 0x10001000, 0x10002000, 0x10003000, 0x10004000
    stack, sentinel = 0x1001FF00, 0x10000000

    def put(address, value): machine.mem_write(address, struct.pack('<I', value & 0xffffffff))
    def get(address): return struct.unpack('<I', machine.mem_read(address, 4))[0]

    for offset, key in [(0x9c, 'level'), (0x54, 'mind'), (0xd0, 'magic_attack'), (0xd4, 'magic_hit_bonus')]:
        put(caster + offset, case[key])
    put(target + 0xa0, 2 if case['no_attack'] else 0)
    put(target + 0x104 + 4 * case['element'], case['resistance'])
    for offset, key in [(4, 'element'), (0x14, 'low'), (0x18, 'high'), (0x1c, 'hit_ratio'), (0x20, 'status_hit_ratio')]:
        put(record + offset, case[key])
    put(bonus, case['hit_bonus'])
    put(0x4c1e8c, 1)  # Prevent the RNG's OS-clock initialization path.
    put(0x4c3044, case['seed'][0])
    put(0x4c3040, case['seed'][1])
    initial = bytes(machine.mem_read(caster, 0x3000))
    draws, returning = [], []
    allowed = [(0x40a7b0, 0x40aa6b), (0x406fe0, 0x407010),
               (0x42c780, 0x42c7d9), (0x458bb0, 0x458cb3)]
    steps = 0

    def guard(_machine, address, _size, _data):
        nonlocal steps
        steps += 1
        if not any(lo <= address < hi for lo, hi in allowed):
            raise ValueError(f'Unreviewed native callee: {address:#x}')
        if returning and returning[-1][0] == address:
            _, bound = returning.pop()
            draws.append({'bound': bound, 'value': machine.reg_read(UC_X86_REG_EAX)})
        if address == 0x42c780:
            esp = machine.reg_read(UC_X86_REG_ESP)
            returning.append((get(esp), get(esp + 4)))

    machine.hook_add(UC_HOOK_CODE, guard)
    machine.mem_write(stack, struct.pack('<7I', sentinel, caster, target, record, bonus, case['proc'], case['channel']))
    machine.reg_write(UC_X86_REG_ESP, stack)
    machine.emu_start(0x40a7b0, sentinel, count=4096)
    if machine.reg_read(UC_X86_REG_EIP) != sentinel or returning:
        raise ValueError('Status roll helper did not return within the instruction bound')
    actual = {'value': machine.reg_read(UC_X86_REG_EAX), 'hit_bonus_after': get(bonus)}
    if actual != independent(case, draws):
        raise ValueError(f'Native status roll differs from model: {case} {draws} {actual}')
    if bytes(machine.mem_read(caster, 0x3000)) != initial:
        raise ValueError('Native roll helper changed actor or skill input')
    return {'input': case, 'draws': draws, 'native': actual, 'normal_return': True, 'instructions': steps}


def run_immunity(base: int, mapped: bytearray) -> list[dict]:
    from unicorn import Uc, UC_ARCH_X86, UC_MODE_32, UC_HOOK_CODE
    from unicorn.x86_const import UC_X86_REG_EAX, UC_X86_REG_EIP, UC_X86_REG_ESP
    results = []
    for mask in [0x800000, 0x1000000]:
        for effects in [0, 0x80, 0x800000, 0x1000000, 0x1800080]:
            machine = Uc(UC_ARCH_X86, UC_MODE_32)
            machine.mem_map(base, len(mapped))
            machine.mem_write(base, bytes(mapped))
            machine.mem_map(0x10000000, 0x10000)
            obj, actor, stack, sentinel = 0x10001000, 0x10002000, 0x1000FF00, 0x10000000
            machine.mem_write(0x4c1bc8, struct.pack('<I', actor))
            machine.mem_write(actor + 0x18c, struct.pack('<I', effects))
            before = bytes(machine.mem_read(obj, 0x2000))

            def guard(_m, address, _s, _d):
                if not (0x40e2f0 <= address < 0x40e305 or 0x40e240 <= address < 0x40e26e):
                    raise ValueError(f'Unexpected immunity callee: {address:#x}')

            machine.hook_add(UC_HOOK_CODE, guard)
            machine.mem_write(stack, struct.pack('<3I', sentinel, obj, mask))
            machine.reg_write(UC_X86_REG_ESP, stack)
            machine.emu_start(0x40e2f0, sentinel, count=128)
            result = machine.reg_read(UC_X86_REG_EAX)
            if machine.reg_read(UC_X86_REG_EIP) != sentinel or result != int(bool(effects & (mask | 0x80))):
                raise ValueError('Native immunity helper mismatch or bound exceeded')
            if bytes(machine.mem_read(obj, 0x2000)) != before:
                raise ValueError('Immunity check changed actor memory')
            results.append({'mask': mask, 'effects': effects, 'native': result, 'normal_return': True})
    return results


def check_packet(packet: dict) -> None:
    if packet.get('exe_sha256') != EXE_SHA or packet.get('native_execution') is not True:
        raise ValueError('Missing native identity or execution receipt')
    if [r['input'] for r in packet['cases']] != fixtures() or len(packet['immunity_cases']) != 10:
        raise ValueError('Status native fixtures incomplete')
    for row in packet['cases']:
        if not row['normal_return'] or row['native'] != independent(row['input'], row['draws']):
            raise ValueError('Saved native status result conflicts with independent replay')
    for row in packet['immunity_cases']:
        if not row['normal_return'] or row['native'] != int(bool(row['effects'] & (row['mask'] | 0x80))):
            raise ValueError('Saved immunity result conflicts')


def execute_packet(exe: Path) -> dict:
    """Run the bounded original instructions on the documented EXE and assemble the packet."""
    base, mapped = image(exe.read_bytes())
    result = {'schema': 'hsl_status_rolls_native.v1', 'evidence_tier': 'static-derived',
              'exe_sha256': EXE_SHA, 'native_execution': True,
              'entries': ['0x40a7b0', '0x40e2f0'],
              'limits': ['Only isolated magnitude/status-hit and equipment-immunity helpers return normally.',
                         'No complete applicator, UI, effect animation or status tick was executed here.',
                         'Native seed fixtures validate supplied numeric inputs, not original battle initialization.'],
              'cases': [run_case(base, mapped, case) for case in fixtures()],
              'immunity_cases': run_immunity(base, mapped)}
    return result


def summary_line(result: dict, executed_now: bool) -> str:
    return f'STATUS_ROLL_PROBE_PASS cases={len(result["cases"])} immunity={len(result["immunity_cases"])} executed_now={executed_now}'


TASK = ProbeTask('status_roll', PACKET, check_packet, execute_packet, summary_line)


def tasks() -> list[ProbeTask]:
    return [TASK]
