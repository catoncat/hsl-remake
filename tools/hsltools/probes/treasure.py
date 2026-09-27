"""Bounded original EVEF chest copy, initialization, collection and contact paths.

The native item queue has explicit spare capacity. Its lookup/append code runs;
allocation, disposal, discovery sound and the whole actor dispatcher are not
stubbed or claimed. Active collection stops at the disposal call, after grants.

Registry task treasure (family probe, hsltools.probes._base.ProbeTask): check validates the
tracked packet against the independent model; generate executes the original instructions
(needs the documented hsl01.exe and unicorn). Bodies moved verbatim from the former hsl_native_treasure_probe.py.
"""
from __future__ import annotations
import hashlib
import json
from pathlib import Path
import re
import struct

from hsltools.native.image import EXE_SHA, image
from hsltools.paths import ROOT
from hsltools.probes._base import ProbeTask
from hsltools.sources.tables import blocks
from hsltools.data.world_map import PakReader
PACKET = ROOT / 'docs/evidence_packets/static_reverse/original_treasure.json'

OBJ, RECORD, QUEUE, ACTOR, NODES = 0x10001000, 0x10002000, 0x10003000, 0x10004000, 0x10006000
STACK, STOP = 0x1001f000, 0x10000000
ANCHOR_SHA = '2c2f37da51627bf69ec280d48e07daa5f7b52acf76dc96dbd214ec9797a24e25'
SOURCE_SHA = '66ec382406f2499c4a2e318665153c816782a179247d69ef773031bc22d17c24'
ANCHORS = [
    (0x477cd0, 4, 'PROCESS.DEF slot41 points at defProcTreasureBox.'),
    (0x42dae7, 15, 'Level creation passes42bd50 as the EVEF per-instance callback.'),
    (0x46be68, 40, 'The EVEF iterator passes the created object and current208-byte record to its callback.'),
    (0x42bd50, 70, 'Chest branch compacts eight nonzero EVEF words from+10 into object+90; tail is not cleared here.'),
    (0x415730, 131, 'Chest initialization aligns its origin and initializes a32px contact rectangle; shape visibility follows the message bit.'),
    (0x4156d0, 84, 'Collection skips opened bit08000000, queues eight nonzero contents then marks and requests disposal.'),
    (0x44f290, 49, 'Pending item lookup ignores zero-count rows.'),
    (0x44f2d0, 220, 'Item queue appends new codes or adds quantities; the tested queue has explicit spare capacity.'),
    (0x4454a5, 202, 'Player completion queries its tile then contact objects, selecting process41 before collection; not provisional move input.'),
    (0x46cf98, 209, 'Contact enumeration and object getter used by the tested player suffix.'),
]


def sha(raw: bytes) -> str:
    return hashlib.sha256(raw).hexdigest()


def sources(root: Path) -> dict:
    reader = PakReader(root)
    process = reader.read('@:\\data\\PROCESS.DEF')
    index = int(re.search(r'defProcTreasureBox\s*=\s*(\d+)', process.decode('cp950'))[1])
    if index != 41:
        raise ValueError('Original chest process changed')
    levels = []
    for level in [1, 2]:
        member = '@:\\data\\LEVEL%03d.BIN' % level
        data = reader.read(member)
        obs_member = '@:\\data\\OBJ-%03d.OBS' % level
        obs = reader.read(obs_member)
        templates = {int(r['obj_code']): r for r in blocks(obs, 'Object') if r.get('obj_Process_Code') == 'defProcTreasureBox'}
        rows = []
        for i in range(struct.unpack_from('<I', data, 4)[0]):
            at = 16 + i * 208
            code, x, y = struct.unpack_from('<Iii', data, at + 4)
            if code not in templates:
                continue
            words = list(struct.unpack_from('<8I', data, at + 16))
            rows.append(dict(record_index=i, object_code=code, pixel=[x, y], words=words,
                             items=[v for v in words if v], template=templates[code]))
        levels.append(dict(level=level, member=member, sha256=sha(data), obs_member=obs_member,
                           obs_sha256=sha(obs), chests=rows))
    return dict(process_member='@:\\data\\PROCESS.DEF', process_sha256=sha(process), process_index=index, levels=levels)


def item_cases() -> list[list[int]]:
    return [[202, 241, 246, 0, 0, 0, 0, 0], [244, 244, 254, 0, 0, 0, 0, 0],
            [2, 241, 0, 0, 0, 0, 0, 0], [0] * 8, [0, 241, 0, 244, 0, 2, 0, 246],
            [241] * 8, [2, 202, 241, 244, 246, 248, 250, 254]]


class Machine:
    def __init__(self, base: int, mapped: bytes):
        from unicorn import Uc, UC_ARCH_X86, UC_MODE_32
        self.m = Uc(UC_ARCH_X86, UC_MODE_32)
        self.m.mem_map(base, len(mapped)); self.m.mem_write(base, bytes(mapped))
        self.m.mem_map(0x10000000, 0x20000)
        self.put(0x4c3040, 0x12345678); self.put(0x4c3044, 0x87654321)

    def put(self, at: int, value: int) -> None:
        self.m.mem_write(at, struct.pack('<I', value & 0xffffffff))

    def get(self, at: int) -> int:
        return struct.unpack('<I', self.m.mem_read(at, 4))[0]

    def run(self, entry: int, args: list[int], allowed: list[tuple[int, int]], stops=(), registers=None) -> dict:
        from unicorn import UC_HOOK_CODE
        from unicorn.x86_const import UC_X86_REG_EIP, UC_X86_REG_ESP
        self.m.mem_write(STACK, struct.pack('<' + 'I' * (len(args) + 1), STOP, *[v & 0xffffffff for v in args]))
        self.m.reg_write(UC_X86_REG_ESP, STACK)
        for register, value in (registers or {}).items(): self.m.reg_write(register, value)
        steps = 0
        calls = []
        def guard(_m, at, _size, _data):
            nonlocal steps
            if at in stops: self.m.emu_stop(); return
            if not any(low <= at < high for low, high in allowed):
                raise ValueError('Unreviewed treasure instruction ' + hex(at))
            steps += 1
            if at == 0x44f2d0:
                sp = self.m.reg_read(UC_X86_REG_ESP)
                calls.append([self.get(sp + 4), self.get(sp + 8)])
        hook = self.m.hook_add(UC_HOOK_CODE, guard)
        try: self.m.emu_start(entry, STOP, count=10000)
        finally: self.m.hook_del(hook)
        end = self.m.reg_read(UC_X86_REG_EIP)
        if end not in (STOP, *stops): raise ValueError('Treasure instruction budget exhausted')
        normal = end == STOP
        if normal and self.m.reg_read(UC_X86_REG_ESP) != STACK + 4: raise ValueError('Native return stack differs')
        if [self.get(0x4c3040), self.get(0x4c3044)] != [0x12345678, 0x87654321]: raise ValueError('Unexpected treasure RNG draw')
        return dict(entry=hex(entry), stop=hex(end), normal_return=normal, instructions=steps,
                    rng_unchanged=True, item_calls=calls)


def copy_case(base, mapped, words, tail):
    n = Machine(base, mapped)
    for i, value in enumerate(words): n.put(RECORD + 16 + i * 4, value)
    n.put(OBJ + 0x64, 41)
    for i in range(8): n.put(OBJ + 0x90 + i * 4, tail)
    before = bytes(n.m.mem_read(OBJ, 176))
    record_before = bytes(n.m.mem_read(RECORD, 208))
    proof = n.run(0x42bd50, [OBJ, RECORD], [(0x42bd50, 0x42bd96)])
    compact = [v for v in words if v]
    expected = compact + [tail] * (8 - len(compact))
    wanted = bytearray(before)
    for i, value in enumerate(expected): struct.pack_into('<I', wanted, 0x90 + 4 * i, value)
    if bytes(n.m.mem_read(OBJ, 176)) != wanted or bytes(n.m.mem_read(RECORD, 208)) != record_before:
        raise ValueError('Original EVEF chest copy changed unrelated fields')
    return dict(words=words, tail=tail, result=expected, proof=proof, unrelated_unchanged=True)


def grant_expected(words, opened):
    queue = [[241, 2], [2, 1]]
    if not opened:
        for code in words:
            if not code: continue
            row = next((r for r in queue if r[0] == code), None)
            if row is None: queue.append([code, 1])
            else: row[1] += 1
    return queue


def grant_case(base, mapped, words, opened):
    n = Machine(base, mapped)
    n.put(0x4c1d28, QUEUE); n.put(0x4c1d2c, 2); n.put(0x4c1d30, 32)
    for i, (code, count) in enumerate(grant_expected([], True)):
        n.put(QUEUE + 8 * i, code); n.put(QUEUE + 8 * i + 4, count)
    for i, value in enumerate(words): n.put(OBJ + 0x90 + i * 4, value)
    n.put(OBJ + 0x80, 0x08000005 if opened else 5)
    before = bytes(n.m.mem_read(OBJ, 176))
    n.m.mem_write(ACTOR, bytes([0xa5]) * 508)
    allowed = [(0x4156d0, 0x415724), (0x44f290, 0x44f3ac)]
    proof = n.run(0x4156d0, [OBJ], allowed, (0x45e3ed,))
    queue = [[n.get(QUEUE + 8 * i), n.get(QUEUE + 8 * i + 4)] for i in range(n.get(0x4c1d2c))]
    expected = bytearray(before); struct.pack_into('<I', expected, 0x80, 0x08000005)
    if queue != grant_expected(words, opened) or bytes(n.m.mem_read(OBJ, 176)) != expected:
        raise ValueError('Original grant differs from the source item sequence')
    if bytes(n.m.mem_read(ACTOR, 508)) != bytes([0xa5]) * 508: raise ValueError('Grant unexpectedly touches actor state')
    # The second invocation really executes the native opened guard, without
    # pretending that the stopped disposal routine completed.
    repeated = n.run(0x4156d0, [OBJ], allowed, (0x45e3ed,))
    if not repeated['normal_return'] or repeated['item_calls']: raise ValueError('Opened chest granted again')
    after = [[n.get(QUEUE + 8 * i), n.get(QUEUE + 8 * i + 4)] for i in range(n.get(0x4c1d2c))]
    if after != queue: raise ValueError('Repeated grant changed pending items')
    return dict(words=words, opened=opened, capacity=32, initial_queue=[[241, 2], [2, 1]],
                queue=queue, marked_opened=True, proof=proof, repeated=repeated, actor_unchanged=True)


def initialize_case(base, mapped, position, visible):
    n = Machine(base, mapped)
    n.put(OBJ + 4, position[0]); n.put(OBJ + 8, position[1])
    n.put(OBJ + 0x30, 0x12340002); n.put(OBJ + 0x80, 0x20000005)
    proof = n.run(0x415730, [OBJ, 0x20010000 if visible else 0x20000000], [(0x415730, 0x4157e3)])
    actual = [n.get(OBJ + offset) for offset in [4, 8, 0x30, 0x80, 0x68, 0x6c, 0x70, 0x74]]
    wanted = [v & 0xffffffe0 for v in position] + [0x12340002 if visible else 0x1234ffff, 0x100005, 0, 0, 32, 32]
    if actual != wanted: raise ValueError('Native chest initialization differs')
    return dict(position=position, visible=visible, values=actual, proof=proof)


def contact_cases():
    return [dict(tile_flag=flag, process=process, hidden=hidden, x=x)
            for flag, process, hidden, x in [(0, 41, False, 0), (0x80000, 41, False, 0),
                (0x80000, 41, True, 0), (0x80000, 40, False, 0),
                (0x80000, 41, False, 40), (0x80000, 41, False, 8), (0x80000, 41, False, 9)]]


def contact_case(base, mapped, case):
    from unicorn.x86_const import UC_X86_REG_ESI, UC_X86_REG_EBX
    n = Machine(base, mapped)
    # A synthetic 16x16 actor contact rectangle; map flags are separate inputs.
    for off, value in [(4, 0), (8, 0), (0x68, -8), (0x6c, -8), (0x70, 8), (0x74, 8)]: n.put(ACTOR + off, value)
    n.put(OBJ + 0x64, case['process']); n.put(OBJ + 0x30, 0xffff if case['hidden'] else 2)
    n.put(0x4c09e4, 1); n.put(0x4c09e8, NODES)
    for off, value in [(0, case['x']), (4, case['x'] + 32), (8, NODES + 32), (16, 0),
                       (32, 0), (36, 32), (40, OBJ)]: n.put(NODES + off, value)
    before = bytes(n.m.mem_read(OBJ, 176))
    proof = n.run(0x4454f7, [], [(0x4454f7, 0x44556f), (0x46cf98, 0x46d069)],
                  (0x4156d0, 0x4477b0, 0x411b90, 0x44556f),
                  {UC_X86_REG_ESI: ACTOR, UC_X86_REG_EBX: case['tile_flag']})
    expected = '0x44556f' if not case['tile_flag'] else '0x411b90' if case['process'] != 41 or case['x'] > 8 else '0x4477b0' if case['hidden'] else '0x4156d0'
    if proof['stop'] != expected or bytes(n.m.mem_read(OBJ, 176)) != before:
        raise ValueError('Original player contact suffix differs')
    return dict(input=case, proof=proof, chest_unchanged=True)


def check(packet):
    if packet.get('schema') != 'hsl_treasure_native.v1' or packet.get('exe_sha256') != EXE_SHA or packet.get('native_execution') is not True:
        raise ValueError('Invalid native treasure identity')
    if packet['sources']['process_index'] != 41: raise ValueError('Wrong process slot')
    if sha(json.dumps(packet['sources'], ensure_ascii=False, sort_keys=True, separators=(',', ':')).encode()) != SOURCE_SHA:
        raise ValueError('Original treasure instance fields changed')
    for source in packet['sources']['levels']:
        seed = json.loads((ROOT / ('content/generated/hsl/chapter01/battle%03d_seed.json' % source['level'])).read_text())
        if source['sha256'] != seed['sources']['level']['sha256'] or source['obs_sha256'] != seed['sources']['objects']['sha256']:
            raise ValueError('Chest source hashes differ from the original level')
        for row in source['chests']:
            if len(row['words']) != 8 or row['items'] != [v for v in row['words'] if v]: raise ValueError('Invalid source content words')
    if [(r['words'], r['tail']) for r in packet['copies']] != [(w, t) for w in item_cases() for t in [0, 777]]:
        raise ValueError('Native content-copy coverage differs')
    for r in packet['copies']:
        values = [v for v in r['words'] if v]
        if r['result'] != values + [r['tail']] * (8-len(values)) or not r['proof']['normal_return'] or not r['unrelated_unchanged']:
            raise ValueError('Native content-copy return differs')
    if [(r['words'], r['opened']) for r in packet['grants']] != [(w, o) for w in item_cases() for o in [False, True]]:
        raise ValueError('Native collection coverage differs')
    for r in packet['grants']:
        expected_stop = hex(STOP) if r['opened'] else '0x45e3ed'
        if r['queue'] != grant_expected(r['words'], r['opened']) or r['proof']['stop'] != expected_stop or r['proof']['normal_return'] != r['opened']:
            raise ValueError('Native item queue differs')
        if r['proof']['item_calls'] != ([] if r['opened'] else [[v, 1] for v in r['words'] if v]) or not r['repeated']['normal_return'] or r['repeated']['item_calls']:
            raise ValueError('Collection repetition differs')
        if r['capacity'] != 32 or not r['marked_opened'] or not r['actor_unchanged'] or not r['repeated']['rng_unchanged']:
            raise ValueError('Native collection fixture or mutation boundary changed')
    if [(r['position'], r['visible']) for r in packet['initialization']] != [(xy, v) for xy in [[640, 544], [33, 47], [-1, -33]] for v in [False, True]]:
        raise ValueError('Chest initialization coverage differs')
    for r in packet['initialization']:
        wanted = [v & 0xffffffe0 for v in r['position']] + [0x12340002 if r['visible'] else 0x1234ffff, 0x100005, 0, 0, 32, 32]
        if r['values'] != wanted or not r['proof']['normal_return']: raise ValueError('Chest initialization result differs')
    if [r['input'] for r in packet['contacts']] != contact_cases(): raise ValueError('Contact coverage differs')
    for row in packet['contacts']:
        c = row['input']
        expected = '0x44556f' if not c['tile_flag'] else '0x411b90' if c['process'] != 41 or c['x'] > 8 else '0x4477b0' if c['hidden'] else '0x4156d0'
        if row['proof']['stop'] != expected or row['proof']['normal_return'] or not row['chest_unchanged']:
            raise ValueError('Contact prefix boundary differs')
    for family in ['copies', 'grants', 'initialization', 'contacts']:
        for row in packet[family]:
            proof = row['proof']
            if not proof['rng_unchanged'] or not 0 < proof['instructions'] < 10000: raise ValueError('Unbounded native result')
    if [(int(r['address'], 16), len(bytes.fromhex(r['bytes'])), r['meaning']) for r in packet['anchors']] != ANCHORS:
        raise ValueError('Treasure instruction scope differs')
    if sha(bytes.fromhex(''.join(r['bytes'] for r in packet['anchors']))) != ANCHOR_SHA or packet['anchors_sha256'] != ANCHOR_SHA:
        raise ValueError('Treasure instruction fingerprint differs')


def execute_packet(exe: Path) -> dict:
    """Run the bounded original instructions on the documented EXE and assemble the packet."""
    base, mapped = image(exe.read_bytes())
    anchors = [dict(address=hex(at), bytes=bytes(mapped[at-base:at-base+size]).hex(), meaning=meaning) for at, size, meaning in ANCHORS]
    packet = dict(schema='hsl_treasure_native.v1', evidence_tier='static-derived', exe_sha256=EXE_SHA, native_execution=True,
                  sources=sources(exe.parent), copies=[copy_case(base, mapped, w, t) for w in item_cases() for t in [0, 777]],
                  grants=[grant_case(base, mapped, w, o) for w in item_cases() for o in [False, True]],
                  initialization=[initialize_case(base, mapped, xy, visible) for xy in [[640, 544], [33, 47], [-1, -33]] for visible in [False, True]],
                  contacts=[contact_case(base, mapped, c) for c in contact_cases()], anchors=anchors,
                  anchors_sha256=sha(bytes.fromhex(''.join(r['bytes'] for r in anchors))),
                  limits=['Real source EVEF content with synthetic allocated object/queue memory. No whole level or object allocator execution.',
                          'Active collection stops before native disposal; repeated opened-guard calls return fully. Pending items are not yet actor inventory.',
                          'Contact suffix stops before collection, discovery sound, or map-flag clearing. The tested16px rectangle is synthetic, not a complete actor shape contract.',
                          'Player action-tail entry and source collection have zero RNG in the tested boundaries; global scheduler, AI looting and exact timing remain separate.'])
    return packet


def summary_line(packet: dict, executed_now: bool) -> str:
    return ('TREASURE_NATIVE_PASS copies=%d grants=%d initialization=%d contacts=%d executed_now=%s' %
              (len(packet['copies']), len(packet['grants']), len(packet['initialization']), len(packet['contacts']), executed_now))


TASK = ProbeTask('treasure', PACKET, check, execute_packet, summary_line)


def tasks() -> list[ProbeTask]:
    return [TASK]
