"""Original damage/hit random stream: generator 0x458c10, rand(n) 0x458c80 and the damage-stream
wrappers 0x42c720 / 0x42c780, executed on the documented hsl01.exe.

The original keeps two generator states. The global one (0x4795d4 / 0x4795d8) serves AI
decisions, script random, growth and object installs; the damage stream (0x4c3044 / 0x4c3040)
serves every exchange, cast, item effect, experience and turn-end recovery draw: 0x42c720 /
0x42c780 save the global state, load the damage state, draw, write the damage state back and
restore the global state. New game seeds the damage words once (0x42ca47: only when both are
zero, word0 = t, word1 = ~t with t = 0x457830 timeGetTime - base); the save file keeps them at
offsets 0x38 / 0x3c (writer 0x42e342, reader 0x42e988 restores them unless the `random`
command-line switch set 0x4c1aec).

Registry task damage_random (family evidence): check validates the tracked packet against the
independent model below (the Godot NativeRandom suite replays the same packet value for value);
generate re-executes the original instructions (needs the documented hsl01.exe and unicorn).
"""
from __future__ import annotations

import hashlib
import struct
from pathlib import Path

from hsltools.native.image import EXE_SHA, image
from hsltools.native.machine import machine_for
from hsltools.paths import ROOT
from hsltools.registry import Context, PacketTask

PACKET = ROOT / 'docs/evidence_packets/static_reverse/original_damage_random.json'
SCHEMA = 'hsl_native_damage_random.v1'
DRAWS = 1000
# (word0, word1) start states: a clock-like new-game seed (t, ~t), the zero-shift edge
# (word1 == 1 makes the first rotate count 0), a sign-bit word0 (arithmetic shifts) and an
# arbitrary high-bit pair.
STATES = [(0x0012d687, 0xffed2978), (0x7fffffff, 0x00000001), (0x80000000, 0x80000001), (0xdeadbeef, 0x87654321)]
# rand(n) bounds cycled through each sequence: the game's own bounds (100, 5, 6, 2, 3, 7, 10),
# rand(0) (returns 0 without advancing), the 16-bit / 32-bit split at 0xffff / 0x10000 and
# negative (signed idiv) bounds.
BOUNDS = [100, 5, 6, 0, 2, 1, 3, 7, 10, 0xffff, 0x10000, 0x7fffffff, -1, -7, -0x80000000, 256, 99, 12345, 0x12345, 4]
GLOBAL_SENTINEL = (0x13579bdf, 0x2468ace0)
ANCHORS = [(0x458bb0, 30, 'Set generator state words 0x4795d4 / 0x4795d8 and mark it seeded (0x4c1e8c = 1).'),
           (0x458bd0, 63, 'Read generator state words out (seeding from the clock first when unseeded).'),
           (0x458c10, 109, 'Generator: a1=a+1, b1=b-1, rotate-add a by b1&31 then b by a&31 (sar/shl, counts masked to 5 bits); returns a+b.'),
           (0x458c80, 51, 'rand(n): n==0 returns 0 without drawing; n<=0xffff (signed) (r&0xffff) idiv n; else r mod n unsigned.'),
           (0x42c720, 84, 'Damage-stream raw draw: swap the damage words 0x4c3044 / 0x4c3040 in, draw 0x458c10, write back, restore the global words.'),
           (0x42c780, 89, 'Damage-stream rand(n): same swap around 0x458c80.'),
           (0x42ca47, 35, 'New game: when both damage words are zero, word0 = t and word1 = ~t (t from 0x457830).'),
           (0x42e342, 18, 'Save writer stores damage words at file offsets 0x38 / 0x3c.'),
           (0x42e980, 25, 'Save reader restores damage words from 0x38 / 0x3c unless the `random` switch (0x4c1aec) is set.')]


def advance(a: int, b: int) -> tuple[int, int, int]:
    """Independent model of 0x458c10 on u32 words: returns (a', b', raw)."""
    def sar(value: int, count: int) -> int:
        signed = value - (1 << 32) if value & 0x80000000 else value
        return (signed >> count) & 0xffffffff
    a1, b1 = (a + 1) & 0xffffffff, (b - 1) & 0xffffffff
    k = b1 & 31
    a2 = (sar(a1, (32 - k) & 31) + ((a1 << k) & 0xffffffff)) & 0xffffffff
    k2 = a2 & 31
    b2 = (((b1 << ((32 - k2) & 31)) & 0xffffffff) + sar(b1, k2)) & 0xffffffff
    return a2, b2, (a2 + b2) & 0xffffffff


def rand(a: int, b: int, bound: int) -> tuple[int, int, int]:
    """Independent model of 0x458c80: returns (a', b', result as u32)."""
    if bound == 0:
        return a, b, 0
    a, b, raw = advance(a, b)
    if bound <= 0xffff:
        # cdq; idiv: the dividend r & 0xffff is never negative, so the C remainder is
        # dividend mod |n| for every signed bound (negative ones included).
        return a, b, (raw & 0xffff) % abs(bound)
    return a, b, raw % (bound & 0xffffffff)


def model_sequences(a0: int, b0: int) -> dict:
    a, b, raws = a0, b0, []
    for _ in range(DRAWS):
        a, b, raw = advance(a, b)
        raws.append(raw)
    raw_end = [a, b]
    a, b, results = a0, b0, []
    for index in range(DRAWS):
        a, b, value = rand(a, b, BOUNDS[index % len(BOUNDS)])
        results.append(value)
    return dict(raw=raws, raw_end=raw_end, rand=results, rand_end=[a, b])


def hex_words(values: list[int]) -> str:
    return ''.join(f'{v:08x}' for v in values)


def words_of(text: str) -> list[int]:
    return [int(text[i:i + 8], 16) for i in range(0, len(text), 8)]


def digest(values: list[int]) -> str:
    return hashlib.sha256(struct.pack(f'<{len(values)}I', *values)).hexdigest()


class Native:
    """One unicorn machine; each call runs a single original function to its return."""
    ALLOWED = [(0x458bb0, 0x458cb3), (0x42c720, 0x42c7d9)]
    STACK, STOP = 0x1001ff00, 0x10000000

    def __init__(self, base: int, mapped: bytearray) -> None:
        from unicorn import UC_HOOK_CODE
        self.m = machine_for(base, mapped)
        self.put(0x4c1e8c, 1)
        def guard(_m, address, _size, _data):
            if address != self.STOP and not any(lo <= address < hi for lo, hi in self.ALLOWED):
                raise ValueError(f'damage random probe left its functions at {address:#x}')
        self.m.hook_add(UC_HOOK_CODE, guard)

    def put(self, at: int, value: int) -> None:
        self.m.mem_write(at, struct.pack('<I', value & 0xffffffff))

    def get(self, at: int) -> int:
        return struct.unpack('<I', self.m.mem_read(at, 4))[0]

    def call(self, entry: int, *args: int) -> int:
        from unicorn.x86_const import UC_X86_REG_EAX, UC_X86_REG_EIP, UC_X86_REG_ESP
        self.m.mem_write(self.STACK, struct.pack('<' + 'I' * (len(args) + 1), self.STOP, *[x & 0xffffffff for x in args]))
        self.m.reg_write(UC_X86_REG_ESP, self.STACK)
        self.m.emu_start(entry, self.STOP, count=400)
        if self.m.reg_read(UC_X86_REG_EIP) != self.STOP or self.m.reg_read(UC_X86_REG_ESP) != self.STACK + 4:
            raise ValueError(f'damage random probe did not return from {entry:#x}')
        return self.m.reg_read(UC_X86_REG_EAX)

    def global_state(self) -> list[int]:
        return [self.get(0x4795d4), self.get(0x4795d8)]

    def damage_state(self) -> list[int]:
        return [self.get(0x4c3044), self.get(0x4c3040)]

    def set_global(self, a: int, b: int) -> None:
        self.put(0x4795d4, a); self.put(0x4795d8, b)

    def set_damage(self, a: int, b: int) -> None:
        self.put(0x4c3044, a); self.put(0x4c3040, b)


def execute_state(native: Native, a0: int, b0: int) -> dict:
    native.set_global(a0, b0)
    raws = [native.call(0x458c10) for _ in range(DRAWS)]
    raw_end = native.global_state()
    native.set_global(a0, b0)
    results = [native.call(0x458c80, BOUNDS[i % len(BOUNDS)]) for i in range(DRAWS)]
    rand_end = native.global_state()
    native.set_global(a0, b0)
    zero = native.call(0x458c80, 0)
    zero_unchanged = native.global_state() == [a0, b0]
    native.set_global(*GLOBAL_SENTINEL); native.set_damage(a0, b0)
    damage_rand = [native.call(0x42c780, BOUNDS[i % len(BOUNDS)]) for i in range(DRAWS)]
    damage_rand_end = native.damage_state()
    rand_global_kept = native.global_state() == list(GLOBAL_SENTINEL)
    native.set_damage(a0, b0)
    damage_raw = [native.call(0x42c720) for _ in range(DRAWS)]
    damage_raw_end = native.damage_state()
    raw_global_kept = native.global_state() == list(GLOBAL_SENTINEL)
    return dict(state=[a0, b0], raw_hex=hex_words(raws), raw_end=raw_end, rand_hex=hex_words(results), rand_end=rand_end,
                rand_zero=dict(result=zero, state_unchanged=zero_unchanged),
                damage_wrapper=dict(rand_sha256=digest(damage_rand), rand_end=damage_rand_end, raw_sha256=digest(damage_raw),
                                    raw_end=damage_raw_end, global_state_kept=rand_global_kept and raw_global_kept))


def check(packet: dict) -> None:
    if packet.get('schema') != SCHEMA or packet.get('exe_sha256') != EXE_SHA or packet.get('native_execution') is not True:
        raise ValueError('Invalid original damage random identity')
    if packet.get('draws') != DRAWS or packet.get('bounds') != BOUNDS or packet.get('global_sentinel') != list(GLOBAL_SENTINEL):
        raise ValueError('Damage random fixture coverage differs')
    if [row['state'] for row in packet['states']] != [list(s) for s in STATES]:
        raise ValueError('Damage random start states differ')
    for row in packet['states']:
        model = model_sequences(*row['state'])
        if words_of(row['raw_hex']) != model['raw'] or row['raw_end'] != model['raw_end']:
            raise ValueError(f'0x458c10 differs from the model from state {row["state"]}')
        if words_of(row['rand_hex']) != model['rand'] or row['rand_end'] != model['rand_end']:
            raise ValueError(f'0x458c80 differs from the model from state {row["state"]}')
        if row['rand_zero'] != dict(result=0, state_unchanged=True):
            raise ValueError('rand(0) must return 0 without advancing')
        wrapper = row['damage_wrapper']
        if (wrapper['rand_sha256'] != digest(model['rand']) or wrapper['rand_end'] != model['rand_end']
                or wrapper['raw_sha256'] != digest(model['raw']) or wrapper['raw_end'] != model['raw_end']
                or wrapper['global_state_kept'] is not True):
            raise ValueError('Damage-stream wrappers differ from the generator on the damage words')
    if [(int(r['address'], 16), len(bytes.fromhex(r['bytes'])), r['meaning']) for r in packet['anchors']] != ANCHORS:
        raise ValueError('Damage random anchors differ')


def execute_packet(exe: Path) -> dict:
    base, mapped = image(exe.read_bytes())
    native = Native(base, mapped)
    return dict(schema=SCHEMA, exe_sha256=EXE_SHA, evidence_tier='static-derived', native_execution=True,
                draws=DRAWS, bounds=BOUNDS, global_sentinel=list(GLOBAL_SENTINEL),
                states=[execute_state(native, a, b) for a, b in STATES],
                anchors=[dict(address=hex(at), bytes=bytes(mapped[at - base:at - base + size]).hex(), meaning=meaning) for at, size, meaning in ANCHORS],
                limits=['Each call runs one original function to its return with the seeded flag set; the clock seeding branch (0x457830) is not executed.',
                        'New-game seeding and the save offsets are static anchors (byte-pinned), not executed.',
                        'rand_hex holds 0x458c80 results as u32 words for the cycled bounds; damage wrappers are pinned by digest against the same model.'])


def summary_line(packet: dict, executed_now: bool) -> str:
    return f'DAMAGE_RANDOM_NATIVE_PASS states={len(packet["states"])} draws={packet["draws"]} executed_now={executed_now}'


class DamageRandomTask(PacketTask):
    name = 'damage_random'
    family = 'evidence'
    inputs = ()
    packet = PACKET.relative_to(ROOT).as_posix()
    outputs = (packet,)
    replaces = ()
    scripts = ('tools/hsltools/evidence/damage_random.py',)

    def validate(self, packet: dict) -> None:
        check(packet)

    def execute(self, ctx: Context) -> dict:
        return execute_packet(ctx.original_exe)

    def summary(self, packet: dict, executed_now: bool) -> str:
        return summary_line(packet, executed_now)


def tasks() -> list[DamageRandomTask]:
    return [DamageRandomTask()]
