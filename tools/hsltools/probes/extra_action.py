"""Original action_twice query returns and player/AI completion prefixes.

The completion slices stop at existing dispatcher tails before rendering. They
execute the unmodified effect getter and no queue/status/presentation stubs.

Registry task extra_action (family probe, hsltools.probes._base.ProbeTask): check validates the
tracked packet against the independent model; generate executes the original instructions
(needs the documented hsl01.exe and unicorn). Bodies moved verbatim from the former hsl_native_extra_action_probe.py.
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
from hsltools.sources.tables import TABLES

PACKET = ROOT / 'docs/evidence_packets/static_reverse/original_extra_action.json'

ANCHOR_SHA = 'bf79487e22d827074071847b3a303299b614d0e2aeca1a58ef8da6f784e4a6fa'
ANCHORS = [
    (0x447e1f,33,'ITEM action_twice is effect flag8, independent of double_attack.'),
    (0x40e2b0,16,'Pure action_twice getter asks current actor equipment mask8.'),
    (0x443a86,75,'Player completion repeats immediately once or enters the status tail; a latched repeat does not query equipment again.'),
    (0x441f08,67,'AI completion uses the same once-only gate before its status and queue tail.'),
    (0x443ad1,86,'Player poison HP application is downstream of the final-action gate.'),
    (0x443c09,60,'Final player kill-chain cleanup and status tick precede queue advancement.'),
    (0x442080,58,'Final AI kill-chain cleanup and status tick precede queue advancement.'),
    (0x443a0d,90,'Fresh player menu setup does not reset the extra-action latch.'),
]


def cases():
    return [dict(role=role,effects=effects,latch=latch) for role in ['player','ai']
            for effects in [0,8,0x8000,0x8008,0xffff] for latch in [0,1]]


def expected(c):
    again = c['latch'] == 0 and bool(c['effects'] & 8)
    return dict(again=again,latch=1 if again else 0,
                phase=0 if again else 0x10003 if c['role']=='player' else 0x640001,
                equipment_queries=0 if c['latch'] else 1)


def execute(base,mapped,c):
    from unicorn import UC_HOOK_CODE
    from unicorn.x86_const import UC_X86_REG_EBP,UC_X86_REG_EDX,UC_X86_REG_ESI,UC_X86_REG_EIP,UC_X86_REG_ESP
    m=machine_for(base,mapped)
    obj,actor,stack=0x10001000,0x10004000,0x1001ff00
    def put(at,value):m.mem_write(at,struct.pack('<I',value&0xffffffff))
    def get(at):return struct.unpack('<I',m.mem_read(at,4))[0]
    put(0x4c1bc8,actor);put(obj+0xa4,0);put(obj+0x8c,0)
    put(actor+0x18c,c['effects']);put(actor+0xd8,25);put(actor+0x30,(7<<16)|3)
    put(actor+0x34,2);put(actor+0x24,3);put(actor+0xa8,0x10002)
    put(0x4c1cf0,c['latch']);put(0x4c6e48,2);put(0x4c1bbc,9)
    before=bytes(m.mem_read(actor,0x1fc))
    m.reg_write(UC_X86_REG_ESP,stack);m.reg_write(UC_X86_REG_EDX,0)
    m.reg_write(UC_X86_REG_ESI,obj);m.reg_write(UC_X86_REG_EBP,obj)
    entry,stop=(0x443a86,0x4447a7) if c['role']=='player' else (0x441f08,0x441f41)
    steps=0;queries=0
    def guard(_m,address,_size,_data):
        nonlocal steps,queries
        steps+=1
        if address==0x40e2b0:queries+=1
        if not any(lo<=address<hi for lo,hi in [(0x443a86,0x443ad1),(0x441f08,0x441f41),(0x40e2b0,0x40e2c0),(0x40e240,0x40e26e)]):
            raise ValueError(f'Unreviewed extra-action callee {address:#x}')
    m.hook_add(UC_HOOK_CODE,guard);m.emu_start(entry,stop,count=256)
    actual=dict(again=get(obj+0x8c)==0,latch=get(0x4c1cf0),phase=get(obj+0x8c),equipment_queries=queries)
    if m.reg_read(UC_X86_REG_EIP)!=stop or m.reg_read(UC_X86_REG_ESP)!=stack or actual!=expected(c):
        raise ValueError(f'Extra-action completion differs {c}: {actual}')
    if bytes(m.mem_read(actor,0x1fc))!=before or get(0x4c6e48)!=2 or get(0x4c1bbc)!=9:
        raise ValueError('Completion prefix ticked HP/status/chain or advanced queue')
    return dict(input=c,native=actual,entry=hex(entry),stop_address=hex(stop),normal_return=False,
                actor_and_queue_unchanged=True,instructions=steps)


def query(base,mapped,effects):
    from unicorn import UC_HOOK_CODE
    from unicorn.x86_const import UC_X86_REG_EAX,UC_X86_REG_EIP,UC_X86_REG_ESP
    m=machine_for(base,mapped);obj,actor,stack,stop=0x10001000,0x10004000,0x1001ff00,0x10000000
    for at,value in [(0x4c1bc8,actor),(obj+0xa4,0),(actor+0x18c,effects)]:m.mem_write(at,struct.pack('<I',value))
    before=bytes(m.mem_read(actor,0x1fc));steps=0
    def guard(_m,address,_size,_data):
        nonlocal steps
        steps+=1
        if not (0x40e2b0<=address<0x40e2c0 or 0x40e240<=address<0x40e26e):raise ValueError('Unexpected action getter callee')
    m.hook_add(UC_HOOK_CODE,guard);m.mem_write(stack,struct.pack('<II',stop,obj));m.reg_write(UC_X86_REG_ESP,stack)
    m.emu_start(0x40e2b0,stop,count=128)
    actual=m.reg_read(UC_X86_REG_EAX)
    if m.reg_read(UC_X86_REG_EIP)!=stop or m.reg_read(UC_X86_REG_ESP)!=stack+4 or actual!=int(bool(effects&8)) or bytes(m.mem_read(actor,0x1fc))!=before:
        raise ValueError('Action getter did not return expected result normally')
    return dict(effects=effects,native=actual,normal_return=True,instructions=steps)


def source_sha():return hashlib.sha256((TABLES/'ITEM.TXT').read_bytes()).hexdigest()


def check(p):
    if p.get('schema')!='hsl_extra_action_native.v1' or p.get('exe_sha256')!=EXE_SHA or p.get('source_sha256')!=source_sha() or p.get('native_execution') is not True:
        raise ValueError('Extra action source identity differs')
    if [r['input'] for r in p['prefixes']]!=cases() or [r['effects'] for r in p['queries']]!=[0,8,0x8000,0x8008,0xffff]:
        raise ValueError('Extra action coverage differs')
    for row in p['prefixes']:
        entry,stop=('0x443a86','0x4447a7') if row['input']['role']=='player' else ('0x441f08','0x441f41')
        if row['native']!=expected(row['input']) or row['normal_return'] is not False or row['entry']!=entry or row['stop_address']!=stop or row['actor_and_queue_unchanged'] is not True or not 0<row['instructions']<256:
            raise ValueError('Extra action prefix result/boundary differs')
    for row in p['queries']:
        if row['native']!=int(bool(row['effects']&8)) or row['normal_return'] is not True or not 0<row['instructions']<128:
            raise ValueError('Extra action getter differs')
    if [(int(a['address'],16),len(bytes.fromhex(a['bytes'])),a['meaning']) for a in p['anchors']]!=ANCHORS:
        raise ValueError('Extra action anchors differ')
    if hashlib.sha256(b''.join(bytes.fromhex(a['bytes']) for a in p['anchors'])).hexdigest()!=ANCHOR_SHA:
        raise ValueError('Extra action original bytes differ')


def execute_packet(exe: Path) -> dict:
    """Run the bounded original instructions on the documented EXE and assemble the packet."""
    base,mapped=image(exe.read_bytes())
    p=dict(schema='hsl_extra_action_native.v1',exe_sha256=EXE_SHA,source_sha256=source_sha(),evidence_tier='static-derived',native_execution=True,
           queries=[query(base,mapped,e) for e in [0,8,0x8000,0x8008,0xffff]],
           prefixes=[execute(base,mapped,c) for c in cases()],
           anchors=[dict(address=hex(at),bytes=bytes(mapped[at-base:at-base+size]).hex(),meaning=meaning) for at,size,meaning in ANCHORS],
           limits=['Getter returns normally; completion prefixes stop before shared dispatcher tails, not whole turns.',
                   'Original effect flag is read on first completion; second completion consumes the latch regardless of equipment.',
                   'The downstream HP/status/queue blocks are byte anchors and reuse separately verified status/queue helpers.',
                   'Synthetic live actor and latch; no graphics, whole input dispatcher or complete battle initialization executed.'])
    return p


def summary_line(p: dict, executed_now: bool) -> str:
    return f'EXTRA_ACTION_NATIVE_PASS queries={len(p["queries"])} prefixes={len(p["prefixes"])} executed_now={executed_now}'


TASK = ProbeTask('extra_action', PACKET, check, execute_packet, summary_line)


def tasks() -> list[ProbeTask]:
    return [TASK]
