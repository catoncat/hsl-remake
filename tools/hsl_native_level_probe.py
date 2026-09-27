#!/usr/bin/env python3
"""Bounded native NPC level-selection probe; does not execute stat growth or Wine."""
import argparse
import json
import struct
from pathlib import Path
from hsltools.data.first_skill import TABLES, blocks, digest
from hsltools.paths import ORIGINAL_EXE


def probe(exe):
    from unicorn import Uc, UC_ARCH_X86, UC_MODE_32, UC_HOOK_CODE
    from unicorn.x86_const import UC_X86_REG_ESP, UC_X86_REG_EIP, UC_X86_REG_EAX, UC_X86_REG_EDI
    raw = exe.read_bytes()
    if digest(raw) != 'f0b5f835d7d0d311b3ed75049c9fc2adc2b470b2bb30700e593abedf8c0a70f7':
        raise ValueError('Unsupported original EXE hash')
    pe = struct.unpack_from('<I', raw, 60)[0]
    count = struct.unpack_from('<H', raw, pe + 6)[0]
    optional = struct.unpack_from('<H', raw, pe + 20)[0]
    base = struct.unpack_from('<I', raw, pe + 52)[0]
    size = struct.unpack_from('<I', raw, pe + 80)[0]
    players = {b['code']: b for b in blocks((TABLES / 'PLAYERS.TXT').read_bytes(), 'character')}
    result = {'schema': 'hsl_native_level_selection.v1', 'evidence_tier': 'static-derived',
              'exe_sha256': digest(raw), 'players_sha256': digest((TABLES / 'PLAYERS.TXT').read_bytes()),
              'entry': '0x40e870', 'samples': [],
              'limits': ['Synthetic object classes and a single registered player; not original scenario initialization.',
                         'Controlled RNG endpoints, not a measured distribution or original RNG sequence.',
                         'Stops before growth/stat refresh; no resulting HP, attack or defense claims.']}
    for code in ['21', '23', '24', '26']:
        row = players[code]
        for party_level in [1, 2, 5]:
            for object_class in [2, 3]:
                for endpoint in ['zero', 'maximum']:
                    uc = Uc(UC_ARCH_X86, UC_MODE_32)
                    uc.mem_map(base, (size + 4095) & ~4095)
                    for section in range(count):
                        _, rva, length, pointer = struct.unpack_from('<IIII', raw, pe + 24 + optional + 40 * section + 8)
                        if length:
                            uc.mem_write(base + rva, raw[pointer:pointer + length])
                    uc.mem_map(0x10000000, 0x10000)
                    uc.mem_map(0x20000000, 0x10000)
                    def put(address, value): uc.mem_write(address, struct.pack('<I', value))
                    def get(address): return struct.unpack('<I', uc.mem_read(address, 4))[0]
                    actor, obj, player_obj = 0x20000000, 0x20001000, 0x20002000
                    put(0x4c1bc8, actor)
                    put(obj + 0xa4, 0)
                    put(obj + 0x64, object_class)
                    for field, offset in [('str', 0x64), ('dex', 0x68), ('mind', 0x6c), ('con', 0x70)]:
                        put(actor + offset, int(row[field]))
                    put(player_obj + 0xa4, 1)
                    put(actor + 0x1fc + 0x9c, party_level)
                    put(0x4c34c0, player_obj)
                    stack = 0x1000ff00
                    put(stack, 0x10000000)
                    put(stack + 4, obj)
                    put(stack + 8, int(row['level_adjust_range']))
                    put(stack + 12, int(row['level_adjust_disp_range']))
                    uc.reg_write(UC_X86_REG_ESP, stack)
                    observed = {'actor': code.zfill(3), 'party_level': party_level, 'object_class': object_class,
                                'rng_endpoint': endpoint, 'range': int(row['level_adjust_range']),
                                'dispersion': int(row['level_adjust_disp_range']), 'rng_bounds': []}
                    def guard(machine, address, instruction_size, user):
                        if address in [0x40e94a, 0x40eb18]:
                            observed['base_level'] = get(actor + 0x9c)
                            observed['selected_level'] = machine.reg_read(UC_X86_REG_EDI) if address == 0x40e94a else observed['base_level']
                            observed['stop'] = hex(address)
                            machine.emu_stop()
                        elif address == 0x458c80:
                            sp = machine.reg_read(UC_X86_REG_ESP)
                            bound = get(sp + 4)
                            if not 0 < bound < 1000: raise ValueError('Unexpected RNG bound')
                            observed['rng_bounds'].append(bound)
                            machine.reg_write(UC_X86_REG_EAX, 0 if endpoint == 'zero' else bound - 1)
                            machine.reg_write(UC_X86_REG_EIP, get(sp))
                            machine.reg_write(UC_X86_REG_ESP, sp + 4)
                        elif not 0x40e7a0 <= address < 0x40e94a:
                            raise ValueError('Unexpected execution address ' + hex(address))
                    uc.hook_add(UC_HOOK_CODE, guard)
                    uc.emu_start(0x40e870, 0x10000000, count=10000)
                    if 'stop' not in observed: raise RuntimeError('Native probe did not reach bounded stop')
                    result['samples'].append(observed)
    return result


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--exe', type=Path, default=ORIGINAL_EXE)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    data = probe(args.exe)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(data, ensure_ascii=False, indent=2) + '\n')
    print('NATIVE_LEVEL_SELECTION_PASS samples=' + str(len(data['samples'])))
