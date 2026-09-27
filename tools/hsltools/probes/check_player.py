"""Bounded original execution of actCheckPlayer/actCheckEnemy target counting and the winfail fail scan.

Three questions from PLAYABILITY §5 D5 (lane R8-probe), answered on the documented hsl01.exe with unicorn:

1. 0x44fad0 lookup_registered_actor_by_code_and_serial: what an absent / dead-marked / HP-0 /
   defAnyPlayer / defNoOne code returns.
2. 0x450840 case 0x26 (actCheckPlayer, shared with actCheckEnemy 0x23): a code that 0x44fad0 cannot
   find is not counted, and count == 0 makes the condition hold (return 1, pc past the arguments).
   An absent player therefore counts as fallen; HP is never read, only the object table and the
   0x8000000 dead mark that the damage routines set.
3. 0x44ecb0 fail-status scan: with no armed fail status nothing is called even when the object
   table holds no player; an armed `actCheckPlayer 1 <id>` reaches the status runner 0x453ac0 with
   kind 2 only through the script condition. No player-count check exists outside the script opcodes
   (anchors list every reader of the player counter 0x4c1b90).

Registry task check_player (family probe, hsltools.probes._base.ProbeTask, replaces nothing): check
validates the tracked packet against the independent model; generate re-executes the original
instructions (needs the documented hsl01.exe and unicorn).
"""
from __future__ import annotations

import hashlib
from pathlib import Path
import struct

from hsltools.native.image import EXE_SHA, image
from hsltools.paths import ROOT
from hsltools.probes._base import ProbeTask

PACKET = ROOT / 'docs/evidence_packets/static_reverse/original_check_player_native.json'
SCHEMA = 'hsl_check_player_native.v1'

INTERP, INTERP_END = 0x450840, 0x453708        # story/winfail opcode interpreter (switch tables follow the body)
LOOKUP, LOOKUP_END = 0x44fad0, 0x44fb90        # lookup_registered_actor_by_code_and_serial
CODE_OF = 0x44fa80                             # actor_slot_is_live: kind 3/5, no 0x8000000 mark -> record code
FAIL_SCAN, FAIL_SCAN_END = 0x44ecb0, 0x44ed70  # winfail fail-status scan (called second by 0x44ee20)
STATUS_RUNNER, FAIL_PROCESS = 0x453ac0, 0x453a80
OBJECT_TABLE, RECORDS_PTR, ROUND, GAME_FLAGS = 0x4c34c0, 0x4c1bc8, 0x4c1bbc, 0x4c1b00
FAIL_TABLE_PTR, SCRIPT_BASE = 0x4c1d08, 0x4c1b50
DEAD_MARK, STORY_PHASE = 0x8000000, 0x4000000
OPCODE_CHECK_PLAYER = 0x26

# (slot, record_index, code, kind, flags, hp) object placements; kind 3 = player object, 5 = enemy object.
def placed(slot, record_index, code, kind=3, flags=0, hp=50):
    return dict(slot=slot, record_index=record_index, code=code, kind=kind, flags=flags, hp=hp)

LEONARD = placed(0, 1, 0)
LOOKUP_CASES = [
    dict(name='absent_code', code=0, serial=1, placements=[]),
    dict(name='present', code=0, serial=1, placements=[LEONARD]),
    dict(name='present_dead_marked', code=0, serial=1, placements=[placed(0, 1, 0, flags=DEAD_MARK)]),
    dict(name='present_hp_zero_unmarked', code=0, serial=1, placements=[placed(0, 1, 0, hp=0)]),
    dict(name='present_non_actor_kind', code=0, serial=1, placements=[placed(0, 1, 0, kind=1)]),
    dict(name='enemy_kind_in_enemy_slot', code=21, serial=1, placements=[placed(25, 9, 21, kind=5)]),
    dict(name='serial_beyond_instances_returns_last_match', code=0, serial=2, placements=[LEONARD]),
    dict(name='any_player_none', code=-1, serial=1, placements=[]),
    dict(name='any_player_slot3', code=-1, serial=1, placements=[placed(3, 1, 2)]),
    dict(name='any_enemy_slot25', code=-2, serial=1, placements=[placed(25, 9, 21, kind=5)]),
    dict(name='no_one', code=-3, serial=1, placements=[]),
]
CONDITION_CASES = [
    dict(name='absent_player_holds', ids=[0], placements=[], flags=0),
    dict(name='present_player_does_not_hold', ids=[0], placements=[LEONARD], flags=0),
    dict(name='hp_zero_unmarked_still_present', ids=[0], placements=[placed(0, 1, 0, hp=0)], flags=0),
    dict(name='dead_marked_holds', ids=[0], placements=[placed(0, 1, 0, flags=DEAD_MARK)], flags=0),
    dict(name='two_ids_one_present_does_not_hold', ids=[0, 1], placements=[placed(1, 2, 1)], flags=0),
    dict(name='two_ids_none_holds', ids=[0, 1], placements=[], flags=0),
    dict(name='absent_under_story_phase_rewinds', ids=[0], placements=[], flags=STORY_PHASE),
]
EMPTY = dict(code=None, ids=[])
FAIL_SCAN_CASES = [
    dict(name='no_armed_status_no_players', statuses=[EMPTY] * 10, placements=[]),
    dict(name='armed_leader_present', statuses=[dict(code=0, ids=[0])] + [EMPTY] * 9, placements=[LEONARD]),
    dict(name='armed_leader_alive_others_dead_marked', statuses=[dict(code=0, ids=[0])] + [EMPTY] * 9,
         placements=[LEONARD, placed(1, 2, 1, flags=DEAD_MARK), placed(2, 3, 2, flags=DEAD_MARK)]),
    dict(name='armed_leader_absent', statuses=[dict(code=0, ids=[0])] + [EMPTY] * 9, placements=[]),
    dict(name='armed_leader_absent_others_alive', statuses=[dict(code=0, ids=[0])] + [EMPTY] * 9,
         placements=[placed(1, 2, 1), placed(2, 3, 2)]),
    dict(name='armed_second_entry_all_dead_marked', statuses=[EMPTY, dict(code=1, ids=[0])] + [EMPTY] * 8,
         placements=[placed(0, 1, 0, flags=DEAD_MARK), placed(1, 2, 1, flags=DEAD_MARK)]),
]
ANCHORS = [
    (0x44fa8b, 10, 'actor_slot_is_live rejects an object carrying the 0x8000000 dead mark before reading its code.'),
    (0x4415d4, 18, 'Damage routine: target HP <= 0 sets the 0x8000000 mark on the object and zeroes its action word.'),
    (0x441da5, 18, 'Second damage path sets the same 0x8000000 mark on HP <= 0.'),
    (0x44448d, 18, 'Third (special) damage path sets the same 0x8000000 mark.'),
    (0x407720, 37, 'Object unregistration clears its 0x4c34c0 slot and queue record; the player/enemy counters decrement below.'),
    (0x4077e3, 14, 'Unregistration decrements 0x4c1b94 (enemy) or 0x4c1b90 (player) by the object side flag.'),
    (0x44ee20, 15, 'Per-evaluation order: win scan 0x44ebf0, fail scan 0x44ecb0, event scan 0x44ed70.'),
    (0x44ed30, 60, 'Fail scan on hold: entry code := -1, status runner 0x453ac0(pc, 2, 0); a zero return enters fail process 0x453a80(2).'),
    (0x453a99, 5, 'Fail process kind 2 jumps to 0x42cbd0 (flags |= 0x88000000, next level/event 999, transition 2).'),
    (0x4524de, 19, 'actCheckPlayerTotalNumber (case 0x27) compares its argument with the player counter 0x4c1b90.'),
    (0x43a9ec, 7, 'Cursor cycling reads 0x4c1b90 only to decide whether another player exists.'),
    (0x43aa17, 7, 'Second cursor cycling reader of 0x4c1b90.'),
    (0x4076fe, 6, 'Registration increments 0x4c1b90 for a player-side object.'),
    (0x4079b6, 6, 'Second registration path increments 0x4c1b90.'),
    (0x407299, 12, 'Level reset zeroes both counters.'),
    (0x4080b0, 14, 'PlayerInstall: 0x42caa0(registration[slot]) nonzero -> constructor; registered slots are fielded regardless of the previous level.'),
    (0x42caf0, 29, 'actDeletePlayerCode (opcode 71) is the only script path that clears a registration slot.'),
    (0x42c700, 20, 'Registration writer 0x42c700 (callers: init 0x42c869, enable 0x42cb47, job-up 0x43493d); no caller sets the 0x80000000 disable bit.'),
    (0x4145b4, 31, 'Message box: face word := record[speaker object +0xa4].picture (+0x5c); speaker object comes from 0x4072b0 +0xa8.'),
    (0x4072b0, 16, 'Message box constructor stores the object-table entry of the 0x44fad0 slot as speaker (+0xa8).'),
]
ANCHOR_SHA = '285e218607eff563c74657296a6b07df3edd0332888470863082f6ba93630299'


def lookup_expected(code: int, serial: int, placements: list[dict]) -> int:
    slots = {p['slot']: p for p in placements}
    if code == -3:
        return -4
    if code == -1:
        return next((s for s in range(0, 20) if s in slots), -1)
    if code == -2:
        return next((s for s in range(20, 200) if s in slots), -1)
    last = -1
    for slot in range(200):
        p = slots.get(slot)
        if p is None or p['kind'] not in (3, 5) or p['flags'] & DEAD_MARK or p['code'] != code:
            continue
        serial -= 1
        last = slot
        if serial < 1:
            return slot
    return last


def condition_expected(ids: list[int], placements: list[dict], flags: int) -> dict:
    present = sum(1 for code in ids if lookup_expected(code, 1, placements) != -1)
    if present or flags & STORY_PHASE:
        return dict(result=0, pc_delta=0, present=present)
    return dict(result=1, pc_delta=2 + len(ids), present=0)


def fail_scan_expected(statuses: list[dict], placements: list[dict]) -> dict:
    codes, pcs = [], []
    stop = None
    for index, status in enumerate(statuses):
        if status['code'] is None:
            codes.append(-1); pcs.append(None); continue
        if stop is not None:
            codes.append(status['code']); pcs.append(0); continue
        verdict = condition_expected(status['ids'], placements, 0)
        if verdict['result']:
            codes.append(-1); pcs.append(verdict['pc_delta'])
            stop = dict(address=hex(STATUS_RUNNER), kind=2, entry=index, pc_delta=verdict['pc_delta'])
        else:
            codes.append(status['code']); pcs.append(0)
    return dict(codes=codes, pc_delta=pcs, stop=stop, normal_return=stop is None)


class Machine:
    """Original image plus a scratch window; object table, actor records and VM objects are fixtures."""

    def __init__(self, base: int, mapped: bytearray):
        from unicorn import Uc, UC_ARCH_X86, UC_MODE_32, UC_HOOK_CODE
        from unicorn.x86_const import UC_X86_REG_ESP
        self.m = m = Uc(UC_ARCH_X86, UC_MODE_32)
        m.mem_map(base, len(mapped)); m.mem_write(base, bytes(mapped))
        m.mem_map(0x10000000, 0x40000)
        self.stack, self.stop = 0x1003ff00, 0x10000000
        self.records, self.vm, self.streams, self.objects, self.table = 0x10004000, 0x10001000, 0x10002000, 0x10010000, 0x10008000
        self.put(RECORDS_PTR, self.records); self.put(ROUND, 7); self.put(GAME_FLAGS, 0); self.put(SCRIPT_BASE, 0)
        m.mem_write(OBJECT_TABLE, bytes(200 * 4))
        self.steps, self.allowed, self.stops, self.stopped = 0, [], [], None

        def guard(_m, at, _size, _data):
            if at in self.stops:
                esp = m.reg_read(UC_X86_REG_ESP)
                self.stopped = dict(address=hex(at), args=[self.get(esp + 4 * i) for i in range(1, 4)])
                m.emu_stop(); return
            self.steps += 1
            if not any(lo <= at < hi for lo, hi in self.allowed):
                raise ValueError(f'Unreviewed check-player callee {at:#x}')
        m.hook_add(UC_HOOK_CODE, guard)

    def put(self, at: int, value: int) -> None:
        self.m.mem_write(at, struct.pack('<I', value & 0xffffffff))

    def get(self, at: int) -> int:
        return struct.unpack('<I', self.m.mem_read(at, 4))[0]

    def geti(self, at: int) -> int:
        return struct.unpack('<i', self.m.mem_read(at, 4))[0]

    def place(self, p: dict) -> None:
        obj = self.objects + p['slot'] * 0x100
        self.put(obj + 0x64, p['kind']); self.put(obj + 0x80, p['flags']); self.put(obj + 0xa4, p['record_index'])
        self.put(OBJECT_TABLE + p['slot'] * 4, obj)
        record = self.records + p['record_index'] * 0x1fc
        self.put(record + 0x84, p['code']); self.put(record + 0xd8, p['hp'])

    def stream(self, index: int, ids: list[int]) -> int:
        at = self.streams + index * 0x100
        words = [OPCODE_CHECK_PLAYER, len(ids), *ids, 0x999]
        self.m.mem_write(at, struct.pack('<%di' % len(words), *words))
        return at

    def call(self, entry: int, args: list[int], budget: int = 100000) -> tuple[int, int]:
        from unicorn.x86_const import UC_X86_REG_ESP, UC_X86_REG_EIP, UC_X86_REG_EAX
        self.m.mem_write(self.stack, struct.pack('<' + 'I' * (len(args) + 1), self.stop, *[a & 0xffffffff for a in args]))
        self.m.reg_write(UC_X86_REG_ESP, self.stack)
        self.m.emu_start(entry, self.stop, count=budget)
        eip = self.m.reg_read(UC_X86_REG_EIP)
        if eip != self.stop and eip not in self.stops:
            raise ValueError('Check-player instruction budget exceeded')
        if eip == self.stop and self.m.reg_read(UC_X86_REG_ESP) != self.stack + 4:
            raise ValueError('Check-player stack did not return normally')
        return eip, struct.unpack('<i', struct.pack('<I', self.m.reg_read(UC_X86_REG_EAX)))[0]


def lookup_execute(base, mapped, case: dict) -> dict:
    n = Machine(base, mapped); n.allowed = [(LOOKUP, LOOKUP_END), (CODE_OF, LOOKUP)]
    for p in case['placements']: n.place(p)
    _, result = n.call(LOOKUP, [case['code'], case['serial']])
    expected = lookup_expected(case['code'], case['serial'], case['placements'])
    if result != expected:
        raise ValueError(f'Original lookup diverged: {case["name"]} native={result} expected={expected}')
    return dict(case, native=dict(result=result), normal_return=True, instructions=n.steps)


def condition_execute(base, mapped, case: dict) -> dict:
    n = Machine(base, mapped); n.allowed = [(INTERP, INTERP_END), (LOOKUP, LOOKUP_END), (CODE_OF, LOOKUP)]
    n.put(GAME_FLAGS, case['flags'])
    for p in case['placements']: n.place(p)
    stream = n.stream(0, case['ids'])
    n.put(n.vm + 0x8c, 0); n.put(n.vm + 0x90, stream)
    _, result = n.call(INTERP, [n.vm])
    native = dict(result=result, pc_delta=(n.get(n.vm + 0x90) - stream) // 4, phase=n.get(n.vm + 0x8c), round=n.get(ROUND))
    expected = condition_expected(case['ids'], case['placements'], case['flags'])
    if (native['result'], native['pc_delta'], native['phase'], native['round']) != (expected['result'], expected['pc_delta'], 0, 7):
        raise ValueError(f'Original actCheckPlayer diverged: {case["name"]} native={native} expected={expected}')
    return dict(case, native=native, present=expected['present'], normal_return=True, instructions=n.steps)


def fail_scan_execute(base, mapped, case: dict) -> dict:
    n = Machine(base, mapped)
    n.allowed = [(FAIL_SCAN, FAIL_SCAN_END), (INTERP, INTERP_END), (LOOKUP, LOOKUP_END), (CODE_OF, LOOKUP)]
    n.stops = [STATUS_RUNNER, FAIL_PROCESS]
    n.put(FAIL_TABLE_PTR, n.table)
    n.m.mem_write(n.table, b'\xff' * (10 * 0xb4))
    for p in case['placements']: n.place(p)
    streams = {}
    for index, status in enumerate(case['statuses']):
        entry = n.table + index * 0xb4
        n.m.mem_write(entry, bytes(0xb4))
        if status['code'] is None:
            n.put(entry, 0xffffffff); continue
        streams[index] = n.stream(index, status['ids'])
        n.put(entry, status['code']); n.put(entry + 4 + 0x8c, 0); n.put(entry + 4 + 0x90, streams[index])
    eip, _ = n.call(FAIL_SCAN, [])
    codes = [n.geti(n.table + i * 0xb4) for i in range(10)]
    pcs = [(n.get(n.table + i * 0xb4 + 0x94) - streams[i]) // 4 if i in streams else None for i in range(10)]
    stop = None
    if n.stopped:
        entry = next(i for i in streams if streams[i] <= n.stopped['args'][0] < streams[i] + 0x100)
        stop = dict(address=n.stopped['address'], kind=n.stopped['args'][1], entry=entry, pc_delta=(n.stopped['args'][0] - streams[entry]) // 4)
        if n.stopped['args'][2] != 0:
            raise ValueError(f'Status runner third argument differs: {case["name"]}')
    native = dict(codes=codes, pc_delta=pcs, stop=stop, normal_return=eip == n.stop)
    expected = fail_scan_expected(case['statuses'], case['placements'])
    if native != expected:
        raise ValueError(f'Original fail scan diverged: {case["name"]} native={native} expected={expected}')
    return dict(case, native=native, instructions=n.steps)


def check(packet: dict) -> None:
    if packet.get('schema') != SCHEMA or packet.get('exe_sha256') != EXE_SHA or packet.get('native_execution') is not True:
        raise ValueError('Check-player identity or execution boundary differs')
    for key, fixtures, expected in (('lookups', LOOKUP_CASES, lambda c: dict(result=lookup_expected(c['code'], c['serial'], c['placements']))),
                                    ('conditions', CONDITION_CASES, None), ('fail_scans', FAIL_SCAN_CASES, None)):
        rows = packet.get(key, [])
        if len(rows) != len(fixtures):
            raise ValueError(f'Check-player {key} coverage differs')
        for fixture, row in zip(fixtures, rows):
            if any(row.get(k) != v for k, v in fixture.items()):
                raise ValueError(f'Check-player {key} fixture differs: {fixture["name"]}')
            if not 0 < row.get('instructions', 0) <= 100000:
                raise ValueError(f'Check-player {key} instruction count differs: {fixture["name"]}')
            if key == 'lookups':
                want = expected(fixture); ok = row.get('native') == want and row.get('normal_return') is True
            elif key == 'conditions':
                want = condition_expected(fixture['ids'], fixture['placements'], fixture['flags'])
                native = row.get('native', {})
                ok = (native.get('result'), native.get('pc_delta'), native.get('phase'), native.get('round')) == (want['result'], want['pc_delta'], 0, 7) \
                    and row.get('present') == want['present'] and row.get('normal_return') is True
            else:
                want = fail_scan_expected(fixture['statuses'], fixture['placements']); ok = row.get('native') == want
            if not ok:
                raise ValueError(f'Check-player {key} native result differs: {fixture["name"]}')
    anchors = packet.get('anchors', [])
    if [(int(r['address'], 16), len(bytes.fromhex(r['bytes'])), r['meaning']) for r in anchors] != ANCHORS:
        raise ValueError('Check-player anchors differ')
    if anchor_sha(packet) != ANCHOR_SHA:
        raise ValueError('Check-player anchor instruction bytes differ')


def anchor_sha(packet: dict) -> str:
    return hashlib.sha256(bytes.fromhex(''.join(r['bytes'] for r in packet['anchors']))).hexdigest()


def execute_packet(exe: Path) -> dict:
    """Run the bounded original instructions on the documented EXE and assemble the packet."""
    base, mapped = image(exe.read_bytes())
    return dict(
        schema=SCHEMA, exe_sha256=EXE_SHA, evidence_tier='static-derived', native_execution=True,
        execution='Unicorn x86-32, original bytes, synthetic object table / actor records / VM objects, no stubs',
        entries=dict(lookup=hex(LOOKUP), condition=hex(INTERP), fail_scan=hex(FAIL_SCAN)),
        lookups=[lookup_execute(base, mapped, c) for c in LOOKUP_CASES],
        conditions=[condition_execute(base, mapped, c) for c in CONDITION_CASES],
        fail_scans=[fail_scan_execute(base, mapped, c) for c in FAIL_SCAN_CASES],
        anchors=[dict(address=hex(at), bytes=bytes(mapped[at - base:at - base + length]).hex(), meaning=meaning) for at, length, meaning in ANCHORS],
        limits=[
            'actCheckPlayer reads only the object table 0x4c34c0 through 0x44fad0/0x44fa80: HP is never consulted; the 0x8000000 mark (set by the damage routines on HP <= 0) or unregistration makes an id absent.',
            'A code with no live object (never fielded, deleted, or dead-marked) is not counted; count 0 holds the condition and consumes 2 + num arguments. Under the story phase flag 0x4000000 the interpreter rewinds instead.',
            'The fail scan reaches the status runner 0x453ac0 (kind 2) only through an armed status whose condition holds; execution stops at that call, so the runner, 0x453a80(2) and 0x42cbd0 are static anchors, not executed.',
            'No executed or anchored path derives defeat from the player counter 0x4c1b90 or from an empty player side; its readers are the script opcode actCheckPlayerTotalNumber, cursor cycling and the register/unregister counters.',
            'Whether a registered slot is fielded belongs to PlayerInstall 0x4080b0 (anchor, see original_player_install.md): registration is cleared only by actDeletePlayerCode; STORY/WINFAIL 030-034 never call it.',
        ])


def summary_line(packet: dict, executed_now: bool) -> str:
    return (f'CHECK_PLAYER_NATIVE_PASS lookups={len(packet["lookups"])} conditions={len(packet["conditions"])} '
            f'fail_scans={len(packet["fail_scans"])} anchors={len(packet["anchors"])} executed_now={executed_now}')


TASK = ProbeTask('check_player', PACKET, check, execute_packet, summary_line, replaces=())


def tasks() -> list[ProbeTask]:
    return [TASK]
