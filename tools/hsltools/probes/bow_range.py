"""Original signed shooting masks through the full native coverage builder.

Flat empty grids isolate RANGE signed cells and edge clipping. Obstacle/height
propagation and original object scheduling are not inferred from these cases.

Registry task bow_range (family probe, hsltools.probes._base.ProbeTask): check validates the
tracked packet against the independent model; generate executes the original instructions
(needs the documented hsl01.exe and unicorn). Bodies moved verbatim from the former hsl_native_bow_range_probe.py.
"""
from __future__ import annotations
import json
from pathlib import Path
import re
import struct

from hsltools.native.image import EXE_SHA, image
from hsltools.paths import ROOT
from hsltools.probes._base import ProbeTask
from hsltools.sources.tables import TABLES, digest

PACKET = ROOT / 'docs/evidence_packets/static_reverse/original_bow_range.json'

def pattern(code):
    block=next(b for b in (TABLES/'RANGE.TXT').read_bytes().decode('cp950').split('[range]')[1:] if re.search(r'^code\s*=\s*'+code+r'\s*$',b,re.M))
    size=int(re.search(r'^size\s*=\s*(\d+)',block,re.M)[1])
    rows=[[int(v) for v in text.split(',')] for text in re.findall(r'^data\s*=\s*([^\r\n;]+)',block,re.M)]
    if len(rows)!=size or any(len(r)!=size for r in rows):raise ValueError('Source range dimensions differ')
    return dict(size=size,data=rows)

def cases():
    return [dict(code=code,origin=origin,mode=mode) for code in ['range0Cell','range3CellShoot','range4CellShoot','range3CellThrust']
            for origin in [[4,4],[0,0]] for mode in [2,3]] + [
                dict(code=code,origin=origin,mode=mode,grid_size=13)
                for code in ['range5CellShoot','range6CellShoot'] for origin in [[6,6],[0,0]] for mode in [2,3]]

def expected(c):
    p=pattern(c['code']);half=p['size']//2;cells=[]
    for y,row in enumerate(p['data']):
        for x,value in enumerate(row):
            tx,ty=c['origin'][0]+x-half,c['origin'][1]+y-half
            if value>0 and 0<=tx<c.get('grid_size',9) and 0<=ty<c.get('grid_size',9):cells.append([tx,ty])
    return cells

def execute(base,mapped,c):
    from unicorn import Uc,UC_ARCH_X86,UC_MODE_32,UC_HOOK_CODE
    from unicorn.x86_const import UC_X86_REG_EIP,UC_X86_REG_ESP
    m=Uc(UC_ARCH_X86,UC_MODE_32);m.mem_map(base,len(mapped));m.mem_write(base,bytes(mapped));m.mem_map(0x10000000,0x20000)
    obj,actor,grid,coverage,table,shape,stack,stop=0x10001000,0x10002000,0x10003000,0x10004000,0x10005000,0x10006000,0x1001ff00,0x10000000
    width=c.get('grid_size',9)
    def put(at,v):m.mem_write(at,struct.pack('<I',v&0xffffffff))
    for at,value in [(0x4c0934,width),(0x4c0938,width),(0x4c0928,grid),(0x476b3c,width),(0x476b40,width),(0x4c1b4c,coverage),(0x4c1b58,table),(table,shape),(0x4c1bc8,actor)]:put(at,value)
    m.mem_write(0x4c34c0,bytes(200*4))
    p=pattern(c['code']);m.mem_write(shape,bytes([p['size']]+[v&255 for row in p['data'] for v in row]))
    x,y=[v*32+16 for v in c['origin']];put(obj+4,x);put(obj+8,y);put(obj+0xa4,0);put(actor+0xd8,30)
    before=bytes(m.mem_read(actor,0x1fc));grid_before=bytes(m.mem_read(grid,width*width*4));steps=0
    def guard(_m,at,_n,_d):
        nonlocal steps
        steps+=1
        if not any(lo<=at<hi for lo,hi in [(0x4100e0,0x410498),(0x40fdc0,0x4100e0),(0x40fc90,0x40fdb3),
                                         (0x407800,0x40793c),(0x446b30,0x446b59),(0x40eb40,0x40ecb0)]):raise ValueError(f'Unreviewed bow coverage instruction {at:#x}')
    m.hook_add(UC_HOOK_CODE,guard);m.mem_write(stack,struct.pack('<6I',stop,obj,x,y,0,c['mode']));m.reg_write(UC_X86_REG_ESP,stack)
    budget=500000 if width>9 else 100000
    m.emu_start(0x4100e0,stop,count=budget)
    if m.reg_read(UC_X86_REG_EIP)!=stop or m.reg_read(UC_X86_REG_ESP)!=stack+4:raise ValueError(f'Bow coverage did not return within bound: {c}, instructions={steps}, eip={m.reg_read(UC_X86_REG_EIP):#x}')
    # The builder returns a local pattern-sized mask, not a map-sized bitmap.
    # It updates476b3c/40 to that local width/height before writing coverage.
    raw=list(m.mem_read(coverage,p['size']**2));half=p['size']//2
    cells=[[c['origin'][0]+x-half,c['origin'][1]+y-half] for y in range(p['size']) for x in range(p['size']) if raw[y*p['size']+x]]
    if cells!=expected(c):raise ValueError(f'Original signed range differs {c}: {cells} expected {expected(c)}')
    if before!=bytes(m.mem_read(actor,0x1fc)) or grid_before!=bytes(m.mem_read(grid,width*width*4)):raise ValueError('Bow query changed actor/map')
    return dict(input=c,normal_return=True,entry='0x4100e0',instructions=steps,cells=cells,coverage=raw,actor_and_map_unchanged=True)

def check(packet):
    if packet.get('schema')!='hsl_bow_range_native.v1' or packet.get('exe_sha256')!=EXE_SHA or packet.get('native_execution') is not True:raise ValueError('Bow range original identity differs')
    if packet['sources']!={name:digest((TABLES/name).read_bytes()) for name in ['RANGE.H','RANGE.TXT']}:raise ValueError('Bow source masks changed')
    if [r['input'] for r in packet['cases']]!=cases():raise ValueError('Bow range coverage changed')
    for r in packet['cases']:
        if not r['normal_return'] or r['cells']!=expected(r['input']) or not r['actor_and_map_unchanged'] or not 0<r['instructions']<(500000 if r['input'].get('grid_size',9)>9 else 100000):raise ValueError('Bow range native result differs')
        p=pattern(r['input']['code']);half=p['size']//2
        if len(r['coverage'])!=p['size']**2:raise ValueError('Bow native coverage dimensions differ')
        actual=[[r['input']['origin'][0]+x-half,r['input']['origin'][1]+y-half] for y in range(p['size']) for x in range(p['size']) if r['coverage'][y*p['size']+x]]
        if actual!=r['cells']:raise ValueError('Bow native coverage bytes disagree with cells')


def execute_packet(exe: Path) -> dict:
    """Run the bounded original instructions on the documented EXE and assemble the packet."""
    base,mapped=image(exe.read_bytes())
    packet=dict(schema='hsl_bow_range_native.v1',exe_sha256=EXE_SHA,native_execution=True,evidence_tier='static-derived',
                sources={name:digest((TABLES/name).read_bytes()) for name in ['RANGE.H','RANGE.TXT']},cases=[execute(base,mapped,c) for c in cases()],
                limits=['Full original builder returns on empty flat9x9 or13x13 grids with exact signed source RANGE cells.',
                        'Positive cells accepted; negative close shooting cells excluded. Edges clip; self-target exclusion is the separate action gate.',
                        'No claim of original height/obstacle propagation or whole action dispatch.'])
    return packet


def summary_line(packet: dict, executed_now: bool) -> str:
    return f'BOW_RANGE_NATIVE_PASS returns={len(packet["cases"])} executed_now={executed_now}'


TASK = ProbeTask('bow_range', PACKET, check, execute_packet, summary_line)


def tasks() -> list[ProbeTask]:
    return [TASK]
