"""Original wind/fire rolls and HP-application prefixes before display callbacks.

Registry task magic_damage (family probe, hsltools.probes._base.ProbeTask): check validates the
tracked packet against the independent model; generate executes the original instructions
(needs the documented hsl01.exe and unicorn). Bodies moved verbatim from the former hsl_native_magic_damage_probe.py.
"""
from __future__ import annotations
import json
from pathlib import Path
import struct

from hsltools.native.machine import machine_for
from hsltools.paths import ROOT
from hsltools.probes._base import ProbeTask
from hsltools.probes.status_roll import EXE_SHA, image, independent, run_case
from hsltools.sources.tables import digest, TABLES
from hsltools.data.mage_magic import definitions
PACKET = ROOT / 'docs/evidence_packets/static_reverse/original_magic_damage.json'

def fixtures() -> list[dict]:
    rows = []
    for key, spell in definitions()['spells'].items():
        fields = spell['fields']; low, high = map(int, fields['damage'].split(','))
        base = dict(spell=key, proc=0, channel=0, low=low, high=high,
                    hit_ratio=int(fields['hit_ratio']), status_hit_ratio=0, hit_bonus=0,
                    magic_hit_bonus=0, no_attack=False, element=3 if key == 'fire' else 2)
        for seed in [1, 7, 19]:
            for level, mind, power in [(1, 15, 24), (3, 35, 50), (80, 36, 100), (100, 50, 110), (1, 1, 0)]:
                for resistance in [0, 80]:
                    rows.append(dict(base, seed=[seed, 0x87654321], level=level, mind=mind,
                                     magic_attack=power, resistance=resistance))
        for rate, bonus, equipment, no_attack in [(0, 0, 0, False), (0, 0, 0, True), (0, 7, 95, False), (50, 0, 0, False)]:
            rows.append(dict(rows[-1], hit_ratio=rate, hit_bonus=bonus, magic_hit_bonus=equipment, no_attack=no_attack))
    return rows


def applications() -> list[dict]:
    rows = fixtures()
    return [dict(rows[i], hp=hp) for i in [0, 1, 8, 30, 34, 35, 42, 64] for hp in [1, 5, 100]]


def expected(case: dict, draws: list[dict]) -> dict:
    roll = independent(case, draws)
    damage = min(case['hp'], roll['value'])
    return dict(hp=case['hp'] - damage, actual_damage=damage,
                contribution=damage, hit_bonus_local=roll['hit_bonus_after'])


def execute(base: int, mapped: bytearray, case: dict) -> dict:
    from unicorn import UC_HOOK_CODE
    from unicorn.x86_const import UC_X86_REG_EAX, UC_X86_REG_EIP, UC_X86_REG_ESP
    m = machine_for(base, mapped)
    obj, target_obj, caster, record, table = 0x10001000, 0x10002000, 0x10004000, 0x10008000, 0x10009000
    target, stack = caster + 0x1fc, 0x1001ff00
    def put(at, value): m.mem_write(at, struct.pack('<I', value & 0xffffffff))
    def get(at): return struct.unpack('<I', m.mem_read(at, 4))[0]
    put(0x4c1bc8, caster); put(obj + 0xa4, 0); put(target_obj + 0xa4, 1)
    for offset, key in [(0x9c, 'level'), (0x54, 'mind'), (0xd0, 'magic_attack'), (0xd4, 'magic_hit_bonus'), (0xb0, 'hit_bonus')]: put(caster + offset, case[key])
    put(target + 0xd8, case['hp']); put(target + 0xa0, 2 if case['no_attack'] else 0)
    put(target + 0x104 + case['element'] * 4, case['resistance'])
    for offset, key in [(4, 'element'), (0x14, 'low'), (0x18, 'high'), (0x1c, 'hit_ratio'), (0x20, 'status_hit_ratio')]: put(record + offset, case[key])
    put(record + 0x24, 1); put(0x4c2ca0 + case['element'] * 4, table); put(table, record)
    put(0x4c1e8c, 1); put(0x4c3044, case['seed'][0]); put(0x4c3040, case['seed'][1])
    steps, draws, returning = 0, [], []
    def guard(_m, address, _size, _data):
        nonlocal steps
        if address in [0x40ab87, 0x40abb0]: m.emu_stop(); return
        steps += 1
        if not any(lo <= address < hi for lo, hi in [(0x40aa80, 0x40ab87), (0x409850, 0x40986c), (0x40a7b0, 0x40aa6b), (0x406fe0, 0x407010), (0x42c780, 0x42c7d9), (0x458bb0, 0x458cb3)]):
            raise ValueError(f'Unreviewed magic damage callee {address:#x}')
        if returning and returning[-1][0] == address:
            _, bound = returning.pop(); draws.append(dict(bound=bound, value=m.reg_read(UC_X86_REG_EAX)))
        if address == 0x42c780:
            esp = m.reg_read(UC_X86_REG_ESP); returning.append((get(esp), get(esp + 4)))
    m.hook_add(UC_HOOK_CODE, guard)
    m.mem_write(stack, struct.pack('<6I', 0x10000000, obj, target_obj, case['element'], 0, 0))
    m.reg_write(UC_X86_REG_ESP, stack); m.emu_start(0x40aa80, 0x10000000, count=4096)
    stop = m.reg_read(UC_X86_REG_EIP)
    if stop not in [0x40ab87, 0x40abb0] or returning: raise ValueError('Magic damage prefix exceeded its stop')
    result = dict(hp=get(target + 0xd8), actual_damage=get(0x4c13fc), contribution=get(0x4c13fc), hit_bonus_local=get(stack - 28))
    if result != expected(case, draws): raise ValueError(f'Original magic HP application differs {case}: {result}')
    return dict(input=case, native=result, draws=draws, instructions=steps, normal_return=False, stop_address=hex(stop))


def check(packet: dict) -> None:
    if packet.get('schema') != 'hsl_native_magic_damage.v1' or packet.get('exe_sha256') != EXE_SHA or packet.get('native_execution') is not True:
        raise ValueError('Missing native magic damage identity')
    if packet['source_magic_sha256'] != digest((TABLES / 'MAGIC.TXT').read_bytes()): raise ValueError('Magic source table changed')
    if [r['input'] for r in packet['rolls']] != fixtures() or [r['input'] for r in packet['applications']] != applications():
        raise ValueError('Native damage fixture coverage differs')
    for row in packet['rolls']:
        if row['native'] != independent(row['input'], row['draws']) or row['normal_return'] is not True or not 0 < row['instructions'] < 4096:
            raise ValueError('Native damage return differs')
    for row in packet['applications']:
        if row['native'] != expected(row['input'], row['draws']) or row['normal_return'] is not False or row['stop_address'] not in ['0x40ab87', '0x40abb0'] or not 0 < row['instructions'] < 4096:
            raise ValueError('Native damage application or boundary differs')


def execute_packet(exe: Path) -> dict:
    """Run the bounded original instructions on the documented EXE and assemble the packet."""
    base, mapped = image(exe.read_bytes())
    packet = dict(schema='hsl_native_magic_damage.v1', exe_sha256=EXE_SHA, native_execution=True,
                  evidence_tier='static-derived', source_magic_sha256=digest((TABLES / 'MAGIC.TXT').read_bytes()),
                  rolls=[run_case(base, mapped, c) for c in fixtures()],
                  applications=[execute(base, mapped, c) for c in applications()],
                  limits=['Numeric helper returns normally; HP application stops before display callback and XP conversion.',
                          'Wind and fire source definitions are single-target; area tests of the shared resolver are explicit synthetic geometry.',
                          'Source actor initialization, native global RNG identity and display timing are separate.'])
    return packet


def summary_line(packet: dict, executed_now: bool) -> str:
    return f'MAGIC_DAMAGE_NATIVE_PASS rolls={len(packet["rolls"])} applications={len(packet["applications"])} executed_now={executed_now}'


TASK = ProbeTask('magic_damage', PACKET, check, execute_packet, summary_line)


def tasks() -> list[ProbeTask]:
    return [TASK]
