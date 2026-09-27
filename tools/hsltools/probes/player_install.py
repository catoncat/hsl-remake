"""Bounded original unconditional/conditional player installation branches.

The slot enable helper returns fully. The callback stops before constructing or
destroying an engine object, or before the first visual initializer; none of those
callees is replaced. Saved receipts do not claim a complete game installation.

Registry task player_install (family probe, hsltools.probes._base.ProbeTask): check validates the
tracked packet against the independent model; generate executes the original instructions
(needs the documented hsl01.exe and unicorn). Bodies moved verbatim from the former hsl_native_player_install_probe.py.
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
from hsltools.probes.map_binding import Native, TABLE as PARSED_TABLE, OBJ as TEMPLATE, STACK as FRAME
from hsltools.sources.tables import blocks
from hsltools.data.world_map import PakReader
PACKET = ROOT / 'docs/evidence_packets/static_reverse/original_player_install.json'

OBJ, STACK, STOP = 0x10001000, 0x1001F000, 0x10000000
REGISTRY = 0x4C4360
ANCHOR_SHA = 'ed42ab72d0dc88bc5fd1afe4df27cecaa0ed2d77efab58def79994439ec3dc1b'
SOURCE_SHA = {2: 'b5cb33ef5f7183652b4f81e7bceef646dc5b9a38bbf52bfc8d0a4089e5a6432c',
              12: '5aa09ad73581c837209ab891beb6ec4fe3fa079f65cc70aa267c5b1c4b113df6'}
ANCHORS = [(0x4080B0, 189, 'PlayerInstall reads Data9 slot, conditionally enables it when Data8 is zero, then requests actor construction.'),
           (0x42CAA0, 21, 'The registered slot getter suppresses bit80000000 entries.'),
           (0x42CB30, 45, 'Enable initializes an empty slot as800+slot or preserves its low16bit object code.'),
           (0x42C700, 21, 'Store one zero-based registered player slot.'),
           (0x45DD2D, 16, 'Before loading object fields, the actual OBS loader clears its176-byte record.'),
           (0x45E0D7, 68, 'OBS Data8 and Data9 numeric fields feed object+a8 and+ac.')]


def sha(raw: bytes) -> str:
    return hashlib.sha256(raw).hexdigest()


def fixtures() -> list[dict]:
    return [dict(slot=slot, before=before, conditional=conditional, position=[33, -1], phase=0)
            for slot in [0, 1, 7, 8, 19]
            for before in [0, 800 + slot, 0x80000000 | (800 + slot)]
            for conditional in [0, 1]]


def initial_fixtures() -> list[dict]:
    return [dict(fixtures()[0], phase=0x20000000, position=xy)
            for xy in [[0,672], [640,544], [-1,-33], [33,47]]]


def default_case(base, mapped, junk):
    from unicorn.x86_const import UC_X86_REG_EBX
    n = Native(base, mapped)
    n.m.mem_write(TEMPLATE, bytes([junk])*176)
    n.put(0x4a19d4, TEMPLATE)
    n.m.reg_write(UC_X86_REG_EBX, TEMPLATE)
    cleared = n.call(0x45dd2d, [], [(0x45dd2d,0x45dd3d),(0x46ee10,0x46ee68)], (0x45dd3d,), True)
    if bytes(n.m.mem_read(TEMPLATE,176)) != bytes(176): raise ValueError('Original OBS zero fill differs')
    n.put(0x4c24b4, PARSED_TABLE); n.put(0x4c25c8,32); n.put(PARSED_TABLE+11,0)
    n.put(FRAME-8,0); n.put(FRAME+16,0)
    before = bytes(n.m.mem_read(TEMPLATE,176))
    parsed = n.call(0x45e0d7, [], [(0x45e0d7,0x45e11b),(0x45dbf1,0x45dc5c),(0x46dd50,0x46debe)], (0x45e11b,), True)
    if bytes(n.m.mem_read(TEMPLATE,176)) != before: raise ValueError('Absent OBS Data8/Data9 overwrote zero defaults')
    return dict(junk=junk, clear_prefix=cleared, missing_fields_prefix=parsed,
                data8=n.get(TEMPLATE+0xa8), data9=n.get(TEMPLATE+0xac),
                boundary='Two separate native loader segments: clear record, then read absent numeric fields on an empty parsed section; intervening fields and full OBS parsing are not executed.')


def expected(case: dict) -> dict:
    code = case['before']
    enabled = code if not code & 0x80000000 else 0
    if enabled == 0 and case['conditional'] == 0:
        code = (800 + case['slot']) if code == 0 else code & 0xFFFF
        enabled = code
    return dict(after=code, constructs=enabled != 0,
                constructor_args=[*case['position'], enabled] if enabled else [],
                stop_address='0x407ec0' if enabled else '0x45e3ed')


def execute(base: int, mapped: bytearray, case: dict, helper_only: bool = False) -> dict:
    from unicorn import UC_HOOK_CODE
    from unicorn.x86_const import UC_X86_REG_EIP, UC_X86_REG_ESP
    m = machine_for(base, mapped)
    def put(at, value): m.mem_write(at, struct.pack('<I', value & 0xFFFFFFFF))
    def get(at): return struct.unpack('<I', m.mem_read(at, 4))[0]
    def signed(at): return struct.unpack('<i', m.mem_read(at, 4))[0]
    for index in range(20): put(REGISTRY + 4*index, 0xABCD0000 + index)
    put(REGISTRY + 4*case['slot'], case['before'])
    for offset, value in [(4, case['position'][0]), (8, case['position'][1]),
                          (0xA8, case['conditional']), (0xAC, case['slot']),
                          (0x80, 0x20000037), (0x30, 0x12340002)]: put(OBJ + offset, value)
    put(0x4C3040, 0x12345678); put(0x4C3044, 0x87654321)
    registry_before = bytes(m.mem_read(REGISTRY, 80))
    object_before = bytes(m.mem_read(OBJ, 0x100))
    steps = 0
    calls = []
    stops = (0x407EC0, 0x45E3ED, 0x43BF30)
    def guard(_m, address, _size, _data):
        nonlocal steps
        if address in stops:
            m.emu_stop()
            return
        if not any(lo <= address < hi for lo, hi in [(0x4080B0, 0x40816D), (0x42CAA0, 0x42CAB5),
                                                     (0x42CB30, 0x42CB5D), (0x42C700, 0x42C715)]):
            raise ValueError(f'Unreviewed install instruction {address:#x}')
        steps += 1
        if address in [0x42CAA0, 0x42CB30, 0x42C700]: calls.append(hex(address))
    m.hook_add(UC_HOOK_CODE, guard)
    args = [case['slot']] if helper_only else [OBJ, case['phase']]
    m.mem_write(STACK, struct.pack('<'+'I'*(len(args)+1), STOP, *args))
    m.reg_write(UC_X86_REG_ESP, STACK)
    entry = 0x42CB30 if helper_only else 0x4080B0
    m.emu_start(entry, STOP, count=2048)
    end = m.reg_read(UC_X86_REG_EIP)
    if end not in (*stops, STOP): raise ValueError('Install probe exceeded its bound')
    normal = end == STOP
    if normal != helper_only: raise ValueError('Unexpected full-return/prefix boundary')
    if normal and m.reg_read(UC_X86_REG_ESP) != STACK + 4: raise ValueError('Helper stack did not return')
    registry_after = bytearray(m.mem_read(REGISTRY, 80))
    registry_after[4*case['slot']:4*case['slot']+4] = registry_before[4*case['slot']:4*case['slot']+4]
    if bytes(registry_after) != registry_before: raise ValueError('Other player slots changed')
    if [get(0x4C3040), get(0x4C3044)] != [0x12345678, 0x87654321]: raise ValueError('Unexpected RNG draw')
    pointer = m.reg_read(UC_X86_REG_ESP)
    actual = dict(after=get(REGISTRY + 4*case['slot']), constructs=end == 0x407EC0,
                  constructor_args=[signed(pointer+4), signed(pointer+8), get(pointer+12)] if end == 0x407EC0 else [],
                  stop_address=hex(end))
    if helper_only:
        wanted = (800 + case['slot']) if case['before'] == 0 else case['before'] & 0xFFFF
        if actual['after'] != wanted or bytes(m.mem_read(OBJ, 0x100)) != object_before:
            raise ValueError('Slot enable helper changed its source object or returned wrong slot')
    elif case['phase'] == 0:
        if actual != expected(case) or bytes(m.mem_read(OBJ, 0x100)) != object_before:
            raise ValueError('Original player installation dispatch differs from its checked branch')
    else:
        if end != 0x43BF30 or [signed(OBJ+4), signed(OBJ+8)] != [((v & ~31) + 16) for v in case['position']]:
            raise ValueError('Initial position prefix differs')
        if get(OBJ+0x80) != 0x37 or get(OBJ+0x30) != 0x1234FFFF:
            raise ValueError('Initializer flags/shape-word prefix differs')
        actual['position'] = [signed(OBJ+4), signed(OBJ+8)]
        actual['object_mode'] = get(OBJ+0x80)
        actual['shape_word'] = get(OBJ+0x30)
    return dict(input=case, entry=hex(entry), native=actual, instructions=steps,
                normal_return=normal, calls=calls, rng_unchanged=True, other_slots_unchanged=True)


def source_records(root: Path) -> list[dict]:
    reader = PakReader(root)
    result = []
    for level in [2, 12]:
        member = f'@:\\data\\obj-{level:03d}.obs'
        raw = reader.read(member)
        records = [r for r in blocks(raw, 'Object') if r.get('obj_Process_Code') == 'defProcPlayerInstall']
        result.append(dict(level=level, member=member, sha256=sha(raw), objects=records))
    return result


def check(packet: dict) -> None:
    if packet.get('schema') != 'hsl_player_install_native.v1' or packet.get('exe_sha256') != EXE_SHA or packet.get('native_execution') is not True:
        raise ValueError('Missing original player install identity')
    if [r['input'] for r in packet['dispatch']] != fixtures(): raise ValueError('Install fixture coverage differs')
    if [r['input'] for r in packet['enable']] != fixtures()[::2] or [r['input'] for r in packet['initialization']] != initial_fixtures(): raise ValueError('Enable/initialization coverage differs')
    if [r['junk'] for r in packet['defaults']] != [0,0xa5]: raise ValueError('OBS default coverage differs')
    for row in packet['defaults']:
        if row['data8'] != 0 or row['data9'] != 0: raise ValueError('Missing source fields do not retain zero')
        for key,stop in [('clear_prefix','0x45dd3d'),('missing_fields_prefix','0x45e11b')]:
            if row[key]['normal_return'] or row[key]['stop_address'] != stop or not row[key]['rng_unchanged'] or not 0 < row[key]['instructions'] < 4096: raise ValueError('Invalid default prefix boundary')
    for row in packet['dispatch']:
        if row['normal_return'] is not False or row['native'] != expected(row['input']) or not 0 < row['instructions'] < 2048 or not row['rng_unchanged'] or not row['other_slots_unchanged']:
            raise ValueError('Invalid install prefix')
    for row in packet['enable']:
        case = row['input']
        wanted = 800 + case['slot'] if case['before'] == 0 else case['before'] & 0xFFFF
        if row['normal_return'] is not True or row['native']['after'] != wanted or row['native']['stop_address'] != hex(STOP): raise ValueError('Invalid full enable return')
    for row in packet['initialization']:
        if row['normal_return'] is not False or row['native']['stop_address'] != '0x43bf30' or row['native']['position'] != [(v & ~31)+16 for v in row['input']['position']]: raise ValueError('Invalid initialization prefix')
    for source in packet['sources']:
        seed = json.loads((ROOT / f'content/generated/hsl/chapter01/battle{source["level"]:03d}_seed.json').read_text())
        if seed['sources']['objects']['sha256'] != source['sha256'] or source['sha256'] != SOURCE_SHA[source['level']]: raise ValueError('Source OBS identity changed')
        if not source['objects'] or any(r['obj_Process_Code'] != 'defProcPlayerInstall' for r in source['objects']): raise ValueError('Source object join is invalid')
    if [(int(r['address'],16),len(bytes.fromhex(r['bytes'])),r['meaning']) for r in packet['anchors']] != ANCHORS: raise ValueError('Anchor scope changed')
    if sha(bytes.fromhex(''.join(r['bytes'] for r in packet['anchors']))) != ANCHOR_SHA or packet['anchors_sha256'] != ANCHOR_SHA: raise ValueError('Anchor bytes changed')


def execute_packet(exe: Path) -> dict:
    """Run the bounded original instructions on the documented EXE and assemble the packet."""
    base, mapped = image(exe.read_bytes())
    cases = fixtures()
    anchors = [dict(address=hex(at), bytes=bytes(mapped[at-base:at-base+length]).hex(), meaning=meaning) for at,length,meaning in ANCHORS]
    packet = dict(schema='hsl_player_install_native.v1', native_execution=True, exe_sha256=EXE_SHA,
                  evidence_tier='static-derived', sources=source_records(exe.parent),
                  dispatch=[execute(base,mapped,c) for c in cases],
                  enable=[execute(base,mapped,c,True) for c in cases[::2]],
                  initialization=[execute(base,mapped,c) for c in initial_fixtures()],
                  defaults=[default_case(base,mapped,junk) for junk in [0,0xa5]],
                  anchors=anchors, anchors_sha256=sha(bytes.fromhex(''.join(r['bytes'] for r in anchors))),
                  limits=['The slot helper returns normally; callback paths stop before constructor407ec0, object disposal45e3ed or visual init43bf30. No callee is stubbed.',
                          'Synthetic slot values and phase0 isolate the original conditional/unconditional dispatch; no full object installation or scheduler equivalence.',
                          'Data8=0 enables a missing/disabled slot; Data8!=0 requires an already-enabled slot. This does not imply an arbitrary absent party member should be granted.',
                          'Job refresh, player-index template copy, growth, resources and source learning have separate existing proof. Remake atomic event order and persistence remain explicit policies.'])
    return packet


def summary_line(packet: dict, executed_now: bool) -> str:
    return f'PLAYER_INSTALL_NATIVE_PASS dispatch={len(packet["dispatch"])} enable_returns={len(packet["enable"])} init_prefixes={len(packet["initialization"])} executed_now={executed_now}'


TASK = ProbeTask('player_install', PACKET, check, execute_packet, summary_line)


def tasks() -> list[ProbeTask]:
    return [TASK]
