"""Replay original distance helpers and bounded AI retention/wait/center suffixes.

The AI dispatcher, UI callbacks and map flood are not stubbed or claimed to
return. Each suffix stops at its declared next decision boundary.

Registry task ai_navigation (family probe, hsltools.probes._base.ProbeTask): check validates the
tracked packet against the independent model; generate executes the original instructions
(needs the documented hsl01.exe and unicorn). Bodies moved verbatim from the former hsl_native_ai_navigation_probe.py.
"""
from __future__ import annotations
import json
from pathlib import Path
import struct

from hsltools.native.image import EXE_SHA, image
from hsltools.native.machine import machine_for
from hsltools.paths import ROOT
from hsltools.probes._base import ProbeTask

PACKET = ROOT / 'docs/evidence_packets/static_reverse/original_ai_navigation.json'

ANCHORS = [(0x44c7e0, 39, 'wait_round loader initializes zero then writes live+1b8'),
           (0x44c8d5, 35, 'ai_fixed writes live+1d0, used as a home radius'),
           (0x44c9e8, 35, 'ai_lock writes live+1e8, compared with a 1..99 sample'),
           (0x40ca20, 25, 'Center search visits every positive casting-mask cell'),
           (0x40cfeA, 106, 'Moving casts retain maximum coverage, up to 250 native candidates'),
           (0x40d08c, 54, 'Per-update budget resumes the cursor; it is not a total search limit'),
           (0x40d5bd, 38, 'Large-footprint approach begins with northwest target offset'),
           (0x40d7b9, 35, 'Normal one-cell target uses its actual center'),
           (0x40cc28, 49, 'One covered primary prefers its own center when that cell is castable'),
           (0x448987, 12, 'Stat refresh copies source move_point+130 into current movement+12c before equipment')]


def fixtures():
    rows = []
    for delta in [[0,0],[1,0],[0,1],[-1,0],[0,-1],[1,1],[-1,1],[1,-1],[-1,-1],[3,4],[4,4],[5,0],[6,0]]:
        for radius in [1,5]:
            for kind in ['circle','diamond']:
                rows.append(dict(kind=kind,delta=delta,radius=radius))
    for wait in [0,1,3]:
        for hp, flags in [(100,0),(99,0),(100,1),(100,2)]: rows.append(dict(kind='wait',wait=wait,hp=hp,flags=flags))
    for rate in [0,30,60,100]:
        for roll in [1,30,31,60,61,99]: rows.append(dict(kind='lock',rate=rate,roll=roll))
    for delta in [[2,0],[3,4],[4,4],[8,0],[9,0]]:
        for fixed in [0,4,8]:
            for removed in [False,True]: rows.append(dict(kind='retain',delta=delta,fixed=fixed,removed=removed))
    return rows


def expected(c):
    kind=c['kind']
    if kind in ['circle','diamond']:
        x,y=c['delta']; r=c['radius']
        return dict(value=int(x*x+y*y<=r*r if kind=='circle' else abs(x)+abs(y)<=r))
    if kind=='wait':
        wake=c['hp']!=100 or c['flags']!=0
        return dict(wait=0 if wake else max(0,c['wait']-1),next='normal' if not c['wait'] or wake else 'nearby')
    if kind=='lock': return dict(next='retain' if c['roll']<=c['rate'] else 'search')
    distance=sum(map(abs,c['delta']))
    return dict(next='retain' if not c['removed'] and distance<=8 and (not c['fixed'] or distance<=c['fixed']) else 'search')


def execute(base,mapped,c):
    from unicorn import UC_HOOK_CODE
    from unicorn.x86_const import UC_X86_REG_EAX,UC_X86_REG_EBP,UC_X86_REG_EBX,UC_X86_REG_ESI,UC_X86_REG_ESP,UC_X86_REG_EIP
    m=machine_for(base,mapped); stack=0x1001fe00; owner=0x10001000; target=0x10002000; actor=0x10004000; sentinel=0x10000000
    def put(at,v):m.mem_write(at,struct.pack('<I',v&0xffffffff))
    def get(at):return struct.unpack('<I',m.mem_read(at,4))[0]
    m.reg_write(UC_X86_REG_ESP,stack); put(stack,sentinel)
    kind=c['kind']; returns=kind in ['circle','diamond']
    if returns:
        entry=0x45ec32 if kind=='circle' else 0x45ec63
        for i,v in enumerate([160,160,160+c['delta'][0]*32,160+c['delta'][1]*32,c['radius']*32]):put(stack+4+i*4,v)
        stops={sentinel:'return'}; allowed=[(0x45ec32,0x45ec93)]
    elif kind=='wait':
        entry=0x43f603; stops={0x43f62b:'nearby',0x43f67f:'normal'}; allowed=[(entry,0x43f67f)]
        m.reg_write(UC_X86_REG_EBX,actor)
        for offset,value in [(0x1b8,c['wait']),(0x24,c['flags']),(0xd8,c['hp']),(0xdc,100)]:put(actor+offset,value)
    elif kind=='lock':
        entry=0x441002; stops={0x44100c:'search',0x441035:'retain'};allowed=[(entry,0x44100c)]
        m.reg_write(UC_X86_REG_EBX,actor);m.reg_write(UC_X86_REG_ESI,c['roll']);put(actor+0x1e8,c['rate'])
    else:
        entry=0x43f55f;stops={0x43f603:'search',0x43f74e:'retain'}
        allowed=[(entry,0x43f603),(0x40bb50,0x40bb79),(0x45ec63,0x45ec93)]
        m.reg_write(UC_X86_REG_EBP,owner);m.reg_write(UC_X86_REG_ESI,0);put(stack+0x2c,actor)
        put(owner+0x88,1);put(0x4c34c0,target);put(target+0x80,0x8000000 if c['removed'] else 0)
        put(owner+4,176);put(owner+8,176);put(owner+0x44,(176<<16)|176)
        put(target+4,176+c['delta'][0]*32);put(target+8,176+c['delta'][1]*32)
        put(actor+0x1c8,8);put(actor+0x1d0,c['fixed']);put(actor+0x1cc,0)
    steps=0
    def guard(_m,addr,_size,_data):
        nonlocal steps
        if addr in stops:m.emu_stop();return
        steps+=1
        if not any(lo<=addr<hi for lo,hi in allowed):raise ValueError(f'Unreviewed navigation instruction {addr:#x}')
    m.hook_add(UC_HOOK_CODE,guard);m.emu_start(entry,sentinel if returns else 0x10000100,count=2048)
    stop=m.reg_read(UC_X86_REG_EIP)
    if stop not in stops:raise ValueError('Navigation probe exceeded declared boundary')
    actual=dict(value=m.reg_read(UC_X86_REG_EAX)) if returns else dict(next=stops[stop])
    if kind=='wait':actual['wait']=get(actor+0x1b8)
    if actual!=expected(c):raise ValueError(f'Navigation mismatch {c}: {actual}')
    return dict(input=c,native=actual,normal_return=returns,entry=hex(entry),stop_address=hex(stop),instructions=steps)


def check(p):
    if p.get('schema')!='hsl_native_ai_navigation.v1' or p.get('exe_sha256')!=EXE_SHA or p.get('native_execution') is not True:raise ValueError('Navigation identity missing')
    if [r['input'] for r in p['cases']]!=fixtures():raise ValueError('Navigation coverage differs')
    for row in p['cases']:
        if row['native']!=expected(row['input']) or row['normal_return']!=(row['input']['kind'] in ['circle','diamond']) or not 0<row['instructions']<2048:raise ValueError('Navigation result differs')
        kind=row['input']['kind']
        entry={'circle':'0x45ec32','diamond':'0x45ec63','wait':'0x43f603','lock':'0x441002','retain':'0x43f55f'}[kind]
        stops=['0x10000000'] if row['normal_return'] else {'wait':['0x43f62b','0x43f67f'],'lock':['0x44100c','0x441035'],'retain':['0x43f603','0x43f74e']}[kind]
        if row['entry']!=entry or row['stop_address'] not in stops:raise ValueError('Navigation execution boundary differs')
    if [(int(r['address'],16),len(bytes.fromhex(r['bytes'])),r['meaning']) for r in p['anchors']]!=ANCHORS:raise ValueError('Navigation anchors differ')


def execute_packet(exe: Path) -> dict:
    """Run the bounded original instructions on the documented EXE and assemble the packet."""
    base,mapped=image(exe.read_bytes())
    p=dict(schema='hsl_native_ai_navigation.v1',exe_sha256=EXE_SHA,native_execution=True,evidence_tier='static-derived',
           cases=[execute(base,mapped,c) for c in fixtures()],
           anchors=[dict(address=hex(at),bytes=bytes(mapped[at-base:at-base+n]).hex(),meaning=label) for at,n,label in ANCHORS],
           limits=['Distance functions return normally; retention/wait/probability are suffixes ending before the next decision.',
                   'Map candidate traversal and source center tie comparisons are static anchors, not a complete native flood execution.',
                   'Eight-direction offsets in 0x40d530 concern large target footprints, not proof of diagonal ordinary movement.'])
    return p


def summary_line(p: dict, executed_now: bool) -> str:
    return f'AI_NAVIGATION_NATIVE_PASS cases={len(p["cases"])} executed_now={executed_now}'


TASK = ProbeTask('ai_navigation', PACKET, check, execute_packet, summary_line)


def tasks() -> list[ProbeTask]:
    return [TASK]
