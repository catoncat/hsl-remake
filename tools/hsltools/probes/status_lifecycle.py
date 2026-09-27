"""Execute reviewed poison/silence branches and the complete counter-tick helper.

Application stops at 0x40b831, before presentation/experience callbacks. This is
an executed prefix, NOT a normal return or a complete original spell. Tick runs
0x40b910 to its real return with other counters zero. No stubs, Wine or OS calls.

Registry task status_lifecycle (family probe, hsltools.probes._base.ProbeTask): check validates the
tracked packet against the independent model; generate executes the original instructions
(needs the documented hsl01.exe and unicorn). Bodies moved verbatim from the former hsl_native_status_lifecycle_probe.py.
"""
from __future__ import annotations
import json
from pathlib import Path
import struct

from hsltools.paths import ROOT
from hsltools.probes._base import ProbeTask
from hsltools.probes.status_roll import EXE_SHA, image, fixtures, independent

PACKET = ROOT / 'docs/evidence_packets/static_reverse/original_status_application.json'

def application_fixtures() -> list[dict]:
    rows = []
    for status, element in [('poison', 2), ('no_magic', 4)]:
        for seed in [1, 7, 19]:
            for turns, power in [(0, 0), (2, 5), (8, 50), (9, 50)]:
                words = {'poison': 0, 'no_magic': 0}
                words[status] = ((power if status == 'poison' else 0) << 16) | turns
                rows.append({**fixtures()[0], 'seed': [seed, 0x87654321], 'status': status,
                             'element': element, 'hp': 100, 'words': words,
                             'effects': 0, 'hit_bonus': 7})
        for effects in [0x80, 0x800000 if status == 'poison' else 0x1000000]:
            rows.append({**rows[-1], 'effects': effects})
        rows.append({**rows[-1], 'hp': 0, 'effects': 0})
    return rows


def tick_fixtures() -> list[dict]:
    return [{'poison': (7 << 16) | p if p else 0, 'no_magic': s}
            for p in [0, 1, 2, 9] for s in [0, 1, 3]]


def flags(words: dict) -> int:
    return (1 if words['poison'] else 0) | (2 if words['no_magic'] else 0)


def expected_application(case: dict, draws: list[dict]) -> dict:
    cursor, bonus = 0, case['hit_bonus']
    words = dict(case['words'])

    def take(bound):
        nonlocal cursor
        if cursor >= len(draws) or draws[cursor]['bound'] != bound or not 0 <= draws[cursor]['value'] < bound:
            raise ValueError('Status application random sequence differs')
        value = draws[cursor]['value']
        cursor += 1
        return value

    def roll(proc):
        nonlocal cursor, bonus
        if cursor >= len(draws):
            raise ValueError('Status roll draws missing')
        rate = case['status_hit_ratio'] if proc & 4 else case['hit_ratio'] + bonus + case['magic_hit_bonus']
        count = 3 if case['no_attack'] or draws[cursor]['value'] + 1 <= rate else 1
        result = independent({**case, 'proc': proc, 'hit_bonus': bonus}, draws[cursor:cursor + count])
        cursor += count
        bonus = result['hit_bonus_after']
        return result['value']

    key = case['status']
    immunity = 0x800000 if key == 'poison' else 0x1000000
    if case['hp'] > 0 and not case['effects'] & (immunity | 0x80) and roll(6):
        duration = 2 + take(2)
        power = 0
        if key == 'poison':
            power = roll(0)
            if power > 50: power -= 10 * ((power - 41) // 10)
            if power < 5: power += 5 * ((9 - power) // 5)
        previous = words[key]
        old_power = previous >> 16
        power = power if old_power == 0 else max(old_power, (old_power + power) // 2)
        words[key] = (power << 16) | min(9, (previous & 0xffff) + duration)
    if cursor != len(draws):
        raise ValueError('Unconsumed application random draws')
    return {'hp': case['hp'], 'status_flags': flags(words), 'status_counters': words, 'hit_bonus_after': bonus}


def expected_tick(words: dict) -> dict:
    result = {key: ((word & 0xffff0000) | ((word & 0xffff) - 1)) if (word & 0xffff) > 1 else 0
              for key, word in words.items()}
    return {'status_flags': flags(result), 'status_counters': result}


def execute(base: int, mapped: bytearray, case: dict, tick: bool = False, include_contribution: bool = False) -> dict:
    from unicorn import Uc, UC_ARCH_X86, UC_MODE_32, UC_HOOK_CODE
    from unicorn.x86_const import UC_X86_REG_EAX, UC_X86_REG_EIP, UC_X86_REG_ESP
    machine = Uc(UC_ARCH_X86, UC_MODE_32)
    machine.mem_map(base, len(mapped))
    machine.mem_write(base, bytes(mapped))
    machine.mem_map(0x10000000, 0x20000)
    obj, target_obj, caster, record, table = 0x10001000, 0x10002000, 0x10004000, 0x10008000, 0x10009000
    target = caster + 0x1fc
    stack, sentinel = 0x1001ff00, 0x10000000

    def put(address, value): machine.mem_write(address, struct.pack('<I', value & 0xffffffff))
    def get(address): return struct.unpack('<I', machine.mem_read(address, 4))[0]

    put(0x4c1bc8, caster)
    put(obj + 0xa4, 0)
    put(target_obj + 0xa4, 1)
    words = case if tick else case['words']
    for offset, key in [(0x30, 'poison'), (0x34, 'no_magic')]: put(target + offset, words[key])
    put(target + 0x24, flags(words))
    if not tick:
        for offset, key in [(0x9c, 'level'), (0x54, 'mind'), (0xd0, 'magic_attack'), (0xd4, 'magic_hit_bonus'), (0xb0, 'hit_bonus')]:
            put(caster + offset, case[key])
        put(target + 0xd8, case['hp'])
        put(target + 0xdc, case['hp'])
        put(target + 0xa0, 2 if case['no_attack'] else 0)
        put(target + 0x18c, case['effects'])
        put(target + 0x104 + case['element'] * 4, case['resistance'])
        for offset, key in [(4, 'element'), (0x14, 'low'), (0x18, 'high'), (0x1c, 'hit_ratio'), (0x20, 'status_hit_ratio')]:
            put(record + offset, case[key])
        put(record + 0x24, 8 if case['status'] == 'poison' else 16)
        put(0x4c2ca0 + case['element'] * 4, table)
        put(table, record)
        put(0x4c1e8c, 1)
        put(0x4c3044, case['seed'][0])
        put(0x4c3040, case['seed'][1])
    allowed = [(0x40b910, 0x40ba12)] if tick else [
        (0x40aa80, 0x40b831), (0x409850, 0x40986c), (0x40e240, 0x40e26e), (0x40e2f0, 0x40e305),
        (0x40a7b0, 0x40aa6b), (0x406fe0, 0x407010), (0x42c780, 0x42c7d9), (0x458bb0, 0x458cb3)]
    steps, draws, returning = 0, [], []

    def guard(_machine, address, _size, _data):
        nonlocal steps
        steps += 1
        if not any(lo <= address < hi for lo, hi in allowed):
            raise ValueError(f'Unreviewed status lifecycle callee: {address:#x}')
        if returning and returning[-1][0] == address:
            _, bound = returning.pop()
            draws.append({'bound': bound, 'value': machine.reg_read(UC_X86_REG_EAX)})
        if address == 0x42c780:
            esp = machine.reg_read(UC_X86_REG_ESP)
            returning.append((get(esp), get(esp + 4)))

    machine.hook_add(UC_HOOK_CODE, guard)
    arguments = [target_obj] if tick else [obj, target_obj, case['element'], 0, 0]
    machine.mem_write(stack, struct.pack('<' + 'I' * (len(arguments) + 1), sentinel, *arguments))
    machine.reg_write(UC_X86_REG_ESP, stack)
    stop = sentinel if tick else 0x40b831
    machine.emu_start(0x40b910 if tick else 0x40aa80, stop, count=4096)
    if machine.reg_read(UC_X86_REG_EIP) != stop or returning:
        raise ValueError('Status lifecycle did not reach its declared stop within 4096 instructions')
    result = {'status_flags': get(target + 0x24), 'status_counters': {'poison': get(target + 0x30), 'no_magic': get(target + 0x34)}}
    if not tick: result.update(hp=get(target + 0xd8), hit_bonus_after=get(caster + 0xb0))
    if result != (expected_tick(case) if tick else expected_application(case, draws)):
        raise ValueError(f'Status native result differs: {case} {draws} {result}')
    if include_contribution:
        if tick: raise ValueError('Counter expiry has no spell contribution')
        result['contribution'] = get(0x4c13fc)
    return {'input': case, 'native': result, 'draws': draws, 'instructions': steps,
            'stop_address': hex(stop), 'normal_return': tick}


def check_packet(packet: dict) -> None:
    if packet.get('exe_sha256') != EXE_SHA or packet.get('native_execution') is not True:
        raise ValueError('Missing status lifecycle native identity')
    for key, fixtures_list, tick in [('application_cases', application_fixtures(), False), ('tick_cases', tick_fixtures(), True)]:
        rows = packet.get(key, [])
        if [row['input'] for row in rows] != fixtures_list:
            raise ValueError('Status lifecycle fixture set differs')
        for row in rows:
            expected = expected_tick(row['input']) if tick else expected_application(row['input'], row['draws'])
            if row['native'] != expected or row['normal_return'] is not tick or row['stop_address'] != ('0x10000000' if tick else '0x40b831') or not 0 < row['instructions'] < 4096:
                raise ValueError('Status lifecycle output or execution boundary differs')


def execute_packet(exe: Path) -> dict:
    """Run the bounded original instructions on the documented EXE and assemble the packet."""
    base, mapped = image(exe.read_bytes())
    packet = {'schema': 'hsl_status_application_native.v1', 'evidence_tier': 'static-derived',
              'native_execution': True, 'exe_sha256': EXE_SHA,
              'application_cases': [execute(base, mapped, case) for case in application_fixtures()],
              'tick_cases': [execute(base, mapped, case, True) for case in tick_fixtures()],
              'limits': ['Application executes only poison or no-magic without primary HP damage, and stops at 0x40b831 before callbacks.',
                         'Only the duration helper returns normally; post-action poison HP loss belongs to its separate callers.',
                         'No animation, experience, whole-spell invocation, death/terminal cleanup or original AI selection was executed.']}
    return packet


def summary_line(packet: dict, executed_now: bool) -> str:
    return f'STATUS_LIFECYCLE_NATIVE_PASS application_prefixes={len(packet["application_cases"])} tick_returns={len(packet["tick_cases"])} executed_now={executed_now}'


TASK = ProbeTask('status_lifecycle', PACKET, check_packet, execute_packet, summary_line)


def tasks() -> list[ProbeTask]:
    return [TASK]
