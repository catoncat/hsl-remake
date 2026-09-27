"""Execute the original complete combat stamina helper on bounded synthetic actors.

This is static-derived x86 execution, not gameplay observation. It executes real
effect predicates, permits no stubbed callees or RNG, and checks actor writes.

Registry task stamina (family probe, hsltools.probes._base.ProbeTask): check validates the
tracked packet against the independent model; generate executes the original instructions
(needs the documented hsl01.exe and unicorn). Bodies moved verbatim from the former hsl_native_stamina_probe.py.
"""
from __future__ import annotations
import hashlib
import json
from pathlib import Path
import struct

from hsltools.native.image import EXE_SHA, image
from hsltools.paths import ROOT
from hsltools.probes._base import ProbeTask

PACKET = ROOT / 'docs/evidence_packets/static_reverse/original_stamina.json'

ANCHORS = {
    0x40E590: (253, 'Complete combat stamina gain; returns at 0x40e68c'),
    0x40E240: (46, 'Predicate reads effective actor flags at +0x18c'),
    0x40E2E0: (16, 'Double gain predicate requests mask0x40'),
    0x44246C: (47, 'Physical exchange tests positive result, then passes prepared damage to stamina'),
    0x447E82: (33, 'ITEM st_x2 maps to effect mask0x40'),
    0x448183: (34, 'ITEM no_addst maps to effect mask0x400'),
    0x448709: (18, 'Equipment application ORs item flags into actor effective flags'),
    0x44B678: (26, 'Next-level threshold uses actor level field+0x9c'),
}


def fixtures() -> list[dict]:
    result = []
    for max_hp in (9, 10, 11, 100):
        for damage in sorted({0, max(max_hp, 10)//2-1, max(max_hp, 10)//2, max_hp, max_hp+17}):
            for after in (0, 1):
                for delta in (-4, 3, 4):
                    result.append(dict(max_hp=max_hp, damage=damage, hp_after=after,
                                       attacker_level=10+delta, defender_level=10,
                                       attacker_st=0, defender_st=0, attacker_flags=0, defender_flags=0))
    for attacker_flags in (0, 0x40, 0x400, 0x440):
        for defender_flags in (0, 0x40, 0x400, 0x440):
            for stamina in (0, 57, 60):
                result.append(dict(max_hp=100, damage=50, hp_after=0,
                                   attacker_level=14, defender_level=10,
                                   attacker_st=stamina, defender_st=stamina,
                                   attacker_flags=attacker_flags, defender_flags=defender_flags))
    return result


def expected(case: dict) -> dict:
    effective_hp = max(10, case['max_hp'])
    base = 4 if min(case['damage'], effective_hp) >= effective_hp//2 else 3
    base += int(case['hp_after'] <= 0)
    base -= int(case['attacker_level'] - case['defender_level'] > 3)
    values = {}
    for role, multiplier in [('attacker', 1), ('defender', 2)]:
        before, flags = case[role+'_st'], case[role+'_flags']
        gain = base * multiplier * (2 if flags & 0x40 else 1)
        values[role] = before if flags & 0x400 else min(60, before+gain)
    return values


def execute(base: int, mapped: bytearray, case: dict) -> dict:
    from unicorn import Uc, UC_ARCH_X86, UC_MODE_32, UC_HOOK_CODE, UC_HOOK_MEM_WRITE
    from unicorn.x86_const import UC_X86_REG_ESP, UC_X86_REG_EIP
    machine = Uc(UC_ARCH_X86, UC_MODE_32)
    machine.mem_map(base, len(mapped))
    machine.mem_write(base, bytes(mapped))
    machine.mem_map(0x10000000, 0x10000)
    actor_base, objects, stack, sentinel = 0x10001000, 0x10002000, 0x1000FF00, 0x10000000

    def put(at, value): machine.mem_write(at, struct.pack('<I', value & 0xFFFFFFFF))
    def get(at): return struct.unpack('<I', machine.mem_read(at, 4))[0]

    put(0x4C1BC8, actor_base)
    for index, role in enumerate(['attacker', 'defender']):
        record = actor_base + 0x1FC*index
        put(objects + index*0x200 + 0xA4, index)
        put(record + 0x9C, case[role+'_level'])
        put(record + 0xE8, case[role+'_st'])
        put(record + 0x18C, case[role+'_flags'])
    put(actor_base + 0x1FC + 0xD8, case['hp_after'])
    put(actor_base + 0x1FC + 0xDC, case['max_hp'])
    machine.mem_write(stack, struct.pack('<IIII', sentinel, objects, objects+0x200, case['damage']))
    machine.reg_write(UC_X86_REG_ESP, stack)
    original = bytes(machine.mem_read(actor_base, 0x3F8))
    expected_bytes = bytearray(original)
    output = expected(case)
    for index, role in enumerate(['attacker', 'defender']):
        struct.pack_into('<I', expected_bytes, index*0x1FC+0xE8, output[role])
    steps = 0
    writes = []

    def code(_machine, address, _size, _data):
        nonlocal steps
        steps += 1
        if not any(lo <= address < hi for lo, hi in [(0x40E590,0x40E68D),(0x40E240,0x40E26E),(0x40E2E0,0x40E2F0)]):
            raise ValueError(f'Unmodelled callee {address:#x}; no substitutes or RNG allowed')

    def write(_machine, _access, address, size, value, _data):
        if 0x1000F000 <= address < 0x10010000: return
        if address not in [actor_base+0xE8, actor_base+0x1FC+0xE8] or size != 4:
            raise ValueError(f'Unexpected original write {address:#x}/{size}')
        writes.append({'role': 'attacker' if address == actor_base+0xE8 else 'defender', 'value': value})

    machine.hook_add(UC_HOOK_CODE, code)
    machine.hook_add(UC_HOOK_MEM_WRITE, write)
    machine.emu_start(0x40E590, sentinel, count=512)
    if machine.reg_read(UC_X86_REG_EIP) != sentinel or bytes(machine.mem_read(actor_base, 0x3F8)) != expected_bytes:
        raise ValueError('Original stamina helper did not return with exactly the expected actor writes')
    native = {role: get(actor_base+index*0x1FC+0xE8) for index, role in enumerate(['attacker','defender'])}
    return {'input': case, 'native': native, 'normal_return': True, 'steps': steps, 'writes': writes,
            'rng_calls': 0, 'other_actor_bytes_unchanged': True}


def check(packet: dict):
    if packet['schema'] != 'hsl_native_stamina.v1' or packet['exe_sha256'] != EXE_SHA:
        raise ValueError('Unknown stamina evidence')
    if [row['input'] for row in packet['cases']] != fixtures(): raise ValueError('Missing stamina cases')
    for row in packet['cases']:
        case = row['input']
        native = expected(case)
        writes = [{'role': role, 'value': native[role]} for role in ['attacker','defender'] if not case[role+'_flags'] & 0x400]
        if row['native'] != native or row['writes'] != writes or row['rng_calls'] != 0 or not row['normal_return'] or not row['other_actor_bytes_unchanged']:
            raise ValueError('Stamina result, mutation or return boundary differs')
    if set(packet['anchors']) != {hex(a) for a in ANCHORS}: raise ValueError('Missing stamina anchor')
    for address, (size, _) in ANCHORS.items():
        anchor = packet['anchors'][hex(address)]
        raw = bytes.fromhex(anchor['hex'])
        if len(raw) != size or hashlib.sha256(raw).hexdigest() != anchor['sha256']: raise ValueError('Invalid stamina anchor')


def execute_packet(exe: Path) -> dict:
    """Run the bounded original instructions on the documented EXE and assemble the packet."""
    base, mapped = image(exe.read_bytes())
    packet = {'schema': 'hsl_native_stamina.v1', 'evidence_tier': 'static-derived', 'exe_sha256': EXE_SHA,
              'cases': [execute(base, mapped, case) for case in fixtures()],
              'anchors': {hex(a): {'description': desc, 'hex': bytes(mapped[a-base:a-base+n]).hex(),
                          'sha256': hashlib.sha256(mapped[a-base:a-base+n]).hexdigest()}
                          for a,(n,desc) in ANCHORS.items()}}
    return packet


def summary_line(packet: dict, executed_now: bool) -> str:
    return f'STAMINA_NATIVE_PASS normal={len(packet["cases"])} execution={executed_now}'


TASK = ProbeTask('stamina', PACKET, check, execute_packet, summary_line)


def tasks() -> list[ProbeTask]:
    return [TASK]
