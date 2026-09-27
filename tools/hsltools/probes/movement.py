"""Run the original four-neighbor flood and obstacle-adjacency helper to return.

Normal one-cell mode0, flat ground or 0xff cliffs and explicit obstacle flags.
No UI, roster callback, instruction substitution or callee stub is used.

Registry task movement (family probe, hsltools.probes._base.ProbeTask): check validates the
tracked packet against the independent model; generate executes the original instructions
(needs the documented hsl01.exe and unicorn). Bodies moved verbatim from the former hsl_native_movement_probe.py.
"""
from __future__ import annotations
import heapq
import json
from pathlib import Path
import struct

from hsltools.native.image import EXE_SHA, image
from hsltools.native.machine import machine_for
from hsltools.paths import ROOT
from hsltools.probes._base import ProbeTask

PACKET = ROOT / 'docs/evidence_packets/static_reverse/original_movement.json'

DIRECTIONS = [(0,-1),(0,1),(-1,0),(1,0)]
MASK = 0x74000


def fixtures():
    layouts = [[], [(5,4)], [(5,3),(5,4),(5,5)], [(2,y) for y in range(2,7)],
               [(x,4) for x in [1,2,3,5,6,7]], [(5,3),(3,5),(5,5)],
               [(5,y) for y in range(9)]]
    return [dict(size=[9,9], origin=[4,4], budget=budget, cells=[[x,y,flag] for x,y in layout])
            for layout in layouts for flag in [0x4000,0xff000000] for budget in [1,2,4,6]] + [
                dict(size=[9,9], origin=[0,0], budget=4, cells=[[1,1,0x4000]]),
                dict(size=[9,9], origin=[8,8], budget=4, cells=[[7,7,0x4000]])]


def helper_fixtures():
    return [dict(direction=d, cells=[[4+dx,4+dy,flag]], mask=MASK)
            for d in range(4) for dx,dy in DIRECTIONS for flag in [0x4000,0x10000,0x20000,0x40000,0xff000000]]


def helper_expected(c):
    dx,dy = DIRECTIONS[c['direction']]
    previous = (4-dx,4-dy)
    return 2 if any((x,y) != previous and flags & c['mask'] for x,y,flags in c['cells']) else 1


def expected(c):
    width,height = c['size']; ox,oy = c['origin']; budget=c['budget']
    flags = {(x,y):v for x,y,v in c['cells']}
    origin = (ox,oy); cost={origin:0}; queue=[(0,ox,oy)]
    while queue:
        used,x,y=heapq.heappop(queue)
        if used != cost[(x,y)]: continue
        # Native records arrival before charging the clearance for onward steps.
        extra = int((x,y) != origin and any(flags.get((x+dx,y+dy),0)&MASK for dx,dy in DIRECTIONS))
        for dx,dy in DIRECTIONS:
            cell=(x+dx,y+dy); nx,ny=cell
            if not 0<=nx<width or not 0<=ny<height or flags.get(cell,0)&MASK or flags.get(cell,0)>>24==0xff: continue
            candidate=used+1+extra
            if candidate<=budget and candidate<cost.get(cell,10**6):
                cost[cell]=candidate;heapq.heappush(queue,(candidate,nx,ny))
    side=2*budget+1
    return [[budget+1-cost[(ox+x-budget,oy+y-budget)] if (ox+x-budget,oy+y-budget) in cost else 0 for x in range(side)] for y in range(side)]


def execute(base,mapped,c,helper=False):
    from unicorn import UC_HOOK_CODE
    from unicorn.x86_const import UC_X86_REG_EAX,UC_X86_REG_EIP,UC_X86_REG_ESP
    m=machine_for(base,mapped);obj=0x10001000;grid=0x10003000;mask=0x10008000;stack=0x1001ff00;stop=0x10000000
    def put(at,v):m.mem_write(at,struct.pack('<I',v&0xffffffff))
    width,height=[9,9] if helper else c['size']
    origin=[4,4] if helper else c['origin']
    put(obj+4,origin[0]*32+16);put(obj+8,origin[1]*32+16)
    put(0x4c0934,width);put(0x4c0938,height);put(0x4c0928,grid);put(0x4c1b44,mask)
    for x,y,flag in c['cells']:put(grid+4*(y*width+x),flag)
    steps=0
    def guard(_m,at,_size,_data):
        nonlocal steps
        steps+=1
        if not any(lo<=at<hi for lo,hi in [(0x40eb40,0x40ecb0),(0x40ed50,0x40f348),(0x407800,0x407941)]):
            raise ValueError(f'Unreviewed movement callee {at:#x}')
    m.hook_add(UC_HOOK_CODE,guard)
    args=[4,4,c['direction'],c['mask'],6] if helper else [obj,c['budget'],0]
    m.mem_write(stack,struct.pack('<'+'I'*(1+len(args)),stop,*args));m.reg_write(UC_X86_REG_ESP,stack)
    m.emu_start(0x40eb80 if helper else 0x40f200,stop,count=300000)
    if m.reg_read(UC_X86_REG_EIP)!=stop or m.reg_read(UC_X86_REG_ESP)!=stack+4:
        raise ValueError('Movement function exceeded its normal-return boundary')
    if helper: actual=m.reg_read(UC_X86_REG_EAX);wanted=helper_expected(c)
    else:
        side=2*c['budget']+1;data=m.mem_read(mask,side*side)
        actual=[list(data[y*side:(y+1)*side]) for y in range(side)];wanted=expected(c)
    if actual!=wanted:raise ValueError(f'Movement oracle mismatch {c}: {actual} expected {wanted}')
    return dict(input=c,native=actual,normal_return=True,instructions=steps,entry='0x40eb80' if helper else '0x40f200')


def check(p):
    if p.get('schema')!='hsl_native_movement.v1' or p.get('exe_sha256')!=EXE_SHA or p.get('native_execution') is not True:raise ValueError('Movement identity missing')
    for name,cases,oracle,entry in [('flood',fixtures(),expected,'0x40f200'),('adjacency',helper_fixtures(),helper_expected,'0x40eb80')]:
        if [r['input'] for r in p[name]]!=cases:raise ValueError('Movement coverage changed')
        for row in p[name]:
            if row['native']!=oracle(row['input']) or row['normal_return'] is not True or row['entry']!=entry or not 0<row['instructions']<300000:raise ValueError('Movement return differs')


def execute_packet(exe: Path) -> dict:
    """Run the bounded original instructions on the documented EXE and assemble the packet."""
    base,mapped=image(exe.read_bytes())
    p=dict(schema='hsl_native_movement.v1',exe_sha256=EXE_SHA,native_execution=True,evidence_tier='static-derived',
           flood=[execute(base,mapped,c) for c in fixtures()],adjacency=[execute(base,mapped,c,True) for c in helper_fixtures()],
           limits=['Original normal one-cell mode0 flood and neighbor helper return normally with synthetic map inputs.',
                   '0xff cliffs block entry but do not match the low-bit obstacle mask; only explicit obstacle flags incur adjacency cost.',
                   'Current living occupants are conservatively treated as blocking; original pass-through eligibility, altitude variants and large footprints are separate.',
                   'A full-map shortest-path search is a remake composition of the verified cost rule, not the native cache or path tie order.'])
    return p


def summary_line(p: dict, executed_now: bool) -> str:
    return f'MOVEMENT_NATIVE_PASS flood={len(p["flood"])} adjacency={len(p["adjacency"])} executed_now={executed_now}'


TASK = ProbeTask('movement', PACKET, check, execute_packet, summary_line)


def tasks() -> list[ProbeTask]:
    return [TASK]
