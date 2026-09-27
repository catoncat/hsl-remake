"""Bounded original blood-to-MP and equipped casting protection/accuracy.

Effective transfer stops before the first renderer. No renderer is replaced or
skipped; its second-call source ordering is recorded by instruction anchors.

Registry task casting_equipment (family probe, hsltools.probes._base.ProbeTask): check validates the
tracked packet against the independent model; generate executes the original instructions
(needs the documented hsl01.exe and unicorn). Bodies moved verbatim from the former hsl_native_casting_equipment_probe.py.
"""
from __future__ import annotations
import hashlib
import json
from pathlib import Path
import struct

from hsltools.native.image import EXE_SHA, image
from hsltools.native.machine import machine_for
from hsltools.native.sources import sources
from hsltools.paths import ROOT
from hsltools.probes._base import ProbeTask
from hsltools.sources.tables import TABLES, digest

PACKET = ROOT / 'docs/evidence_packets/static_reverse/original_casting_equipment.json'

ANCHOR_SHA = '3e0d690f79f93851b1316d56c92e47729c2cef81376d38dbbb33af96439d5d66'
FLAGS = {'avoid_poison': 0x800000, 'avoid_nomagic': 0x1000000}
ANCHORS = [(0x447983, 36, 'add_magic_hit loader stores the parsed value into item+1c.'),
           (0x4480e5, 64, 'ITEM poison/silence protection independently ORs main effect bits800000/1000000.'),
           (0x4481b8, 86, 'hp_transfer_mp and take_off use the other item effect word.'),
           (0x40e210, 48, 'Other actor effect query reads actor+190, not main+18c.'),
           (0x4094c0, 279, 'Blood transfer samples original triangular HP cost, keeps1HP, caps MP independently and prepares numbers.'),
           (0x406fe0, 48, 'Triangular range uses two bound(halfspan+1) draws; odd upper endpoint is not necessarily reachable.'),
           (0x40e56b, 22, 'After both automatic resources, caller executes blood transfer with accumulated display delay.'),
           (0x4485b6, 48, 'Equipped magic hit is additive into actor+d4.'),
           (0x448709, 122, 'Current equipment effects OR separately; innate capability mapping follows nonempty gear.')]


def transfer_cases():
    rows = []
    for maximum in [1, 2, 9, 30, 99, 400]:
        for hp in sorted({1, max(1, maximum // 2), maximum}):
            for max_mp, mp in [(0, 0), (30, 0), (30, 29), (30, 30)]:
                for seed in [1, 7, 101, 65535]:
                    rows.append(dict(max_hp=maximum, hp=hp, max_mp=max_mp, mp=mp, seed=seed, enabled=True, delay=80))
    for hp in [1, 20, 30]:
        rows.append(dict(max_hp=30, hp=hp, max_mp=30, mp=4, seed=7, enabled=False, delay=0))
    return rows


def transfer_expected(case, draws):
    cost = 0
    if case['enabled']:
        low = max(1, case['max_hp'] * 8 // 100)
        high = max(low + 1, case['max_hp'] * 12 // 100)
        half = (high - low) // 2
        if len(draws) != 2 or any(d['bound'] != half + 1 or not 0 <= d['value'] <= half for d in draws):
            raise ValueError('Transfer RNG bounds/count differ')
        cost = min(case['hp'] - 1, low + half - draws[0]['value'] + draws[1]['value'])
    elif draws:
        raise ValueError('Disabled transfer consumed RNG')
    gain = min(case['max_mp'] - case['mp'], cost)
    return dict(hp=case['hp'] - cost, mp=case['mp'] + gain, hp_loss=cost, mp_gain=gain,
                number_args=[160, 212, cost, 0, 0, case['delay']] if cost else [])


def execute_transfer(base, mapped, case):
    from unicorn import UC_HOOK_CODE
    from unicorn.x86_const import UC_X86_REG_EAX, UC_X86_REG_EIP, UC_X86_REG_ESP
    m = machine_for(base, mapped)
    actor, obj, stack, stop = 0x10004000, 0x10001000, 0x1001ff00, 0x10000000
    def put(at, value): m.mem_write(at, struct.pack('<I', value & 0xffffffff))
    def get(at): return struct.unpack('<I', m.mem_read(at, 4))[0]
    put(0x4c1bc8, actor); put(obj + 0xa4, 0); put(obj + 4, 160); put(obj + 8, 260)
    for off, value in [(0xd8, case['hp']), (0xdc, case['max_hp']), (0xe0, case['mp']), (0xe4, case['max_mp']),
                       (0x190, int(case['enabled'])), (0x18c, 0x108030a), (0xe8, 20), (0x88, 37),
                       (0x24, 3), (0x30, 0x70003), (0x34, 2)]: put(actor + off, value)
    put(0x4c1e8c, 1); put(0x4c3044, case['seed']); put(0x4c3040, 0x87654321)
    before = bytes(m.mem_read(actor, 0x1fc))
    steps, draws, returning = 0, [], []
    def guard(_m, address, _size, _data):
        nonlocal steps
        if address == 0x40959f: m.emu_stop(); return
        steps += 1
        if not any(lo <= address < hi for lo, hi in [(0x4094c0, 0x4095d7), (0x40e210, 0x40e240), (0x406fe0, 0x407010), (0x42c780, 0x42c7d9), (0x458bb0, 0x458cb3)]):
            raise ValueError(f'Unreviewed transfer callee {address:#x}')
        if returning and returning[-1][0] == address:
            _, bound = returning.pop(); draws.append(dict(bound=bound, value=m.reg_read(UC_X86_REG_EAX)))
        if address == 0x42c780:
            sp = m.reg_read(UC_X86_REG_ESP); returning.append((get(sp), get(sp + 4)))
    m.hook_add(UC_HOOK_CODE, guard)
    m.mem_write(stack, struct.pack('<3I', stop, obj, case['delay'])); m.reg_write(UC_X86_REG_ESP, stack)
    m.emu_start(0x4094c0, stop, count=4096)
    end = m.reg_read(UC_X86_REG_EIP)
    if end not in [0x40959f, stop] or returning: raise ValueError('Transfer did not reach declared boundary')
    actual = dict(hp=get(actor + 0xd8), mp=get(actor + 0xe0), hp_loss=case['hp'] - get(actor + 0xd8),
                  mp_gain=get(actor + 0xe0) - case['mp'], number_args=[])
    if end == 0x40959f: actual['number_args'] = list(struct.unpack('<6I', m.mem_read(m.reg_read(UC_X86_REG_ESP), 24)))
    expected = transfer_expected(case, draws)
    image_after = bytearray(before)
    struct.pack_into('<I', image_after, 0xd8, expected['hp']); struct.pack_into('<I', image_after, 0xe0, expected['mp'])
    if actual != expected or bytes(m.mem_read(actor, 0x1fc)) != image_after: raise ValueError(f'Transfer model differs {case}: {actual}')
    if end == stop and (m.reg_read(UC_X86_REG_ESP) != stack + 4 or m.reg_read(UC_X86_REG_EAX) != 0):
        raise ValueError('Zero-cost transfer did not return normally')
    return dict(input=case, native=actual, draws=draws, normal_return=end == stop, stop_address=hex(end), instructions=steps, only_hp_mp_changed=True)


def gear_cases():
    return [dict(job=job, codes=codes, status=status) for job in [80, 90]
            for codes in [[], [145], [128], [217], [219], [215], [226], [215, 226], [128, 217, 219], [145, 217, 219]]
            for status in [0, 3]]


def gear_expected(case):
    _, items, _ = sources()
    flags, other, accuracy = 0, 0, 0
    for code in case['codes']:
        row = items[code]
        flags |= sum(bit for key, bit in FLAGS.items() if int(row.get(key, 0)))
        other |= int(bool(int(row.get('hp_transfer_mp', 0))))
        accuracy += int(row.get('add_magic_hit', 0))
    return dict(effects=flags, other_effects=other, magic_hit=accuracy, status=case['status'],
                poison=0x70003 if case['status'] else 0, no_magic=2 if case['status'] else 0, hp=1, mp=0, stamina=20, exp=37)


def execute_gear(base, mapped, case):
    from unicorn import Uc, UC_ARCH_X86, UC_MODE_32, UC_HOOK_CODE
    from unicorn.x86_const import UC_X86_REG_EIP, UC_X86_REG_ESP
    _, items, defines = sources()
    m = Uc(UC_ARCH_X86, UC_MODE_32); m.mem_map(base, len(mapped)); m.mem_write(base, bytes(mapped))
    for at, size in [(0x10000000, 0x10000), (0x20000000, 0x10000), (0x21000000, 0x20000)]: m.mem_map(at, size)
    actor, stack, stop = 0x20000000, 0x1000ff00, 0x10000000
    def put(at, value): m.mem_write(at, struct.pack('<I', value & 0xffffffff))
    def get(at): return struct.unpack('<I', m.mem_read(at, 4))[0]
    for off, value in [(0x18, case['job']), (0x28, 0x10000), (0x9c, 3), (0xd8, 1), (0xe0, 0),
                      (0x130, 4), (0x174, 1), (0x24, case['status']), (0x30, 0x70003 if case['status'] else 0),
                      (0x34, 2 if case['status'] else 0), (0xe8, 20), (0x88, 37)]: put(actor + off, value)
    for off in [0x64, 0x68, 0x6c, 0x70]: put(actor + off, 20)
    put(0x4c1b40, 0x21000000)
    accessory = 4
    for code in case['codes']:
        row = items[code]; at = 0x21000000 + 176 * code
        index = 2 if defines[row['type']] == 4 else accessory
        if index >= 4: accessory += 1
        put(actor + 0xec + index * 4, code)
        for off, value in [(8, defines[row['type']]), (0x10, -1), (0x8c, -1), (0x88, int(row.get('attack_damage', 0))),
                          (0x1c, int(row.get('add_magic_hit', 0))), (0x24, int(row.get('add_magic_power', 0))),
                          (0xa0, sum(bit for key, bit in FLAGS.items() if int(row.get(key, 0)))),
                          (0xa4, int(bool(int(row.get('hp_transfer_mp', 0)))))]: put(at + off, value)
    steps = 0
    def guard(_m, address, _size, _data):
        nonlocal steps
        steps += 1
        if not 0x448370 <= address < 0x44b820: raise ValueError(f'Unreviewed gear refresh {address:#x}')
    m.hook_add(UC_HOOK_CODE, guard)
    results = []
    for _repeat in range(2):
        for off in [0x18c, 0x190, 0xd4]: put(actor + off, 0x7fffffff)
        prior = steps
        m.mem_write(stack, struct.pack('<2I', stop, actor)); m.reg_write(UC_X86_REG_ESP, stack)
        m.emu_start(0x448840, stop, count=12000)
        if m.reg_read(UC_X86_REG_EIP) != stop or m.reg_read(UC_X86_REG_ESP) != stack + 4: raise ValueError('Gear refresh did not return')
        result = {key: get(actor + off) for key, off in [('effects', 0x18c), ('other_effects', 0x190), ('magic_hit', 0xd4),
                    ('status', 0x24), ('poison', 0x30), ('no_magic', 0x34), ('hp', 0xd8), ('mp', 0xe0), ('stamina', 0xe8), ('exp', 0x88)]}
        if result != gear_expected(case): raise ValueError(f'Gear refresh mismatch {case}: {result}')
        results.append(dict(values=result, normal_return=True, instructions=steps-prior))
    return dict(input=case, native=results)


def check(packet):
    if packet.get('schema') != 'hsl_casting_equipment_native.v1' or packet.get('exe_sha256') != EXE_SHA or packet.get('native_execution') is not True: raise ValueError('Casting evidence identity differs')
    if packet['sources'] != {n: digest((TABLES / n).read_bytes()) for n in ['ITEM.TXT','TYPE.H']}: raise ValueError('Casting source differs')
    if [r['input'] for r in packet['transfers']] != transfer_cases() or [r['input'] for r in packet['gear']] != gear_cases(): raise ValueError('Casting coverage differs')
    for row in packet['transfers']:
        expected = transfer_expected(row['input'], row['draws'])
        returning = expected['hp_loss'] == 0
        if row['native'] != expected or row['normal_return'] != returning or row['stop_address'] != hex(0x10000000 if returning else 0x40959f) or not 0 < row['instructions'] < 4096 or not row['only_hp_mp_changed']: raise ValueError('Transfer evidence differs')
    for row in packet['gear']:
        if len(row['native']) != 2 or any(r['values'] != gear_expected(row['input']) or r['normal_return'] is not True or not 0 < r['instructions'] < 12000 for r in row['native']): raise ValueError('Gear refresh evidence differs')
    if [(int(a['address'], 16), len(bytes.fromhex(a['bytes'])), a['meaning']) for a in packet['anchors']] != ANCHORS: raise ValueError('Casting anchors differ')
    if hashlib.sha256(bytes.fromhex(''.join(a['bytes'] for a in packet['anchors']))).hexdigest() != ANCHOR_SHA: raise ValueError('Casting instruction bytes differ')


def execute_packet(exe: Path) -> dict:
    """Run the bounded original instructions on the documented EXE and assemble the packet."""
    base, mapped = image(exe.read_bytes())
    packet = dict(schema='hsl_casting_equipment_native.v1', evidence_tier='static-derived', exe_sha256=EXE_SHA, native_execution=True,
                  sources={n: digest((TABLES / n).read_bytes()) for n in ['ITEM.TXT','TYPE.H']},
                  transfers=[execute_transfer(base, mapped, c) for c in transfer_cases()],
                  gear=[execute_gear(base, mapped, c) for c in gear_cases()],
                  anchors=[dict(address=hex(at), bytes=bytes(mapped[at-base:at-base+size]).hex(), meaning=meaning) for at,size,meaning in ANCHORS],
                  limits=['Effective transfer stops before number rendering; HP1/disabled branches return fully, and HP1 still samples twice.',
                          'Full gear refresh uses synthetic current-job fields and source item values. This is effect application, not job eligibility. Existing poison/silence remains after protective equip.',
                          'Protection/accuracy effect composition is verified; whole gameplay, exact clocks and global RNG are separate.'])
    return packet


def summary_line(packet: dict, executed_now: bool) -> str:
    return f'CASTING_EQUIPMENT_NATIVE_PASS transfers={len(packet["transfers"])} gear_returns={2*len(packet["gear"])} executed_now={executed_now} anchors_sha='+hashlib.sha256(bytes.fromhex(''.join(a['bytes'] for a in packet['anchors']))).hexdigest()


TASK = ProbeTask('casting_equipment', PACKET, check, execute_packet, summary_line)


def tasks() -> list[ProbeTask]:
    return [TASK]
