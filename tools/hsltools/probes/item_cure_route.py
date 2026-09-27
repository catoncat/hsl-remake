"""Original AI cure category: self coordinate or ally-search branch, before motion.

Starts440877, really calls the negative-state getter and eight-slot item scan.
Stops before ally search or the shared destination commit; no original stub.

Registry task item_cure_route (family probe, hsltools.probes._base.ProbeTask): check validates the
tracked packet against the independent model; generate executes the original instructions
(needs the documented hsl01.exe and unicorn). Bodies moved verbatim from the former hsl_native_item_cure_route_probe.py.
"""
from __future__ import annotations
import hashlib
import json
from pathlib import Path
import struct

from hsltools.native.image import EXE_SHA, image
from hsltools.paths import ROOT
from hsltools.probes._base import ProbeTask
from hsltools.probes.stat_magic import machine
from hsltools.probes.tactical_items import scan_model

PACKET = ROOT / 'docs/evidence_packets/static_reverse/original_item_cure_route.json'

BYTES_SHA='9321851267792f56308ec3863a03c9e6094cbf6a712dec8e957cc8aafa522497'

def cases():
    return [dict(inventory=inv,flags=bits,self_target=self_target) for inv in [[0]*8,[247,248,246,0,0,0,0,0],[246,247,248,0,0,0,0,0]] for bits in [0,2,7,0x37] for self_target in [False,True]]

def expected(c):
    found=scan_model(c)>0
    return dict(branch='self_destination' if found and c['self_target'] else 'ally_search' if found else 'unavailable',
                packed_coordinate=0x70008 if found and c['self_target'] else None)

def execute(base,mapped,c):
    from unicorn import UC_HOOK_CODE
    from unicorn.x86_const import UC_X86_REG_EBP,UC_X86_REG_ESP,UC_X86_REG_EIP,UC_X86_REG_EAX
    m=machine(base,mapped);owner,target,actor,stack=0x10001000,0x10002000,0x10004000,0x1001ff00
    def put(at,v):m.mem_write(at,struct.pack('<I',v))
    put(0x4c1bc8,actor);put(owner+0xa4,0);put(target+0xa4,1)
    put(owner+4,7);put(owner+8,8);put(0x4c1cec,owner if c['self_target'] else target)
    put(actor+(0 if c['self_target'] else 0x1fc)+0x24,c['flags']);put(0x4c1b40,0x20000000)
    for i,code in enumerate(c['inventory']):put(actor+0x138+i*4,code)
    for code,mask in [(246,0x80000000),(247,0x40000000),(248,0x20000000)]:
        put(0x20000000+code*176+8,1);put(0x20000000+code*176+0xa0,mask)
    before=bytes(m.mem_read(actor,0x3f8));steps=0
    stops={0x4408ac:'ally_search',0x4408b8:'self_destination',0x4408e2:'unavailable'}
    def guard(_m,at,_n,_d):
        nonlocal steps
        if at in stops:m.emu_stop();return
        steps+=1
        if not any(lo<=at<hi for lo,hi in [(0x440877,0x4408ac),(0x40c1b0,0x40c1cf),(0x40c230,0x40c2d0)]):raise ValueError(f'Unreviewed cure route {at:#x}')
    m.hook_add(UC_HOOK_CODE,guard);m.reg_write(UC_X86_REG_EBP,owner);m.reg_write(UC_X86_REG_ESP,stack)
    m.emu_start(0x440877,0x10000000,count=1024);end=m.reg_read(UC_X86_REG_EIP)
    actual=dict(branch=stops.get(end),packed_coordinate=m.reg_read(UC_X86_REG_EAX) if end==0x4408b8 else None)
    if actual!=expected(c) or m.reg_read(UC_X86_REG_ESP)!=stack or before!=bytes(m.mem_read(actor,0x3f8)):raise ValueError('Cure route/side effects differ')
    return dict(input=c,native=actual,instructions=steps,normal_return=False,stop_address=hex(end),actors_unchanged=True)

def check(p):
    if p.get('schema')!='hsl_item_cure_route.v1' or p.get('exe_sha256')!=EXE_SHA or p.get('native_execution') is not True:raise ValueError('Cure route identity differs')
    if [r['input'] for r in p['cases']]!=cases():raise ValueError('Cure route coverage differs')
    for row in p['cases']:
        stop={'ally_search':'0x4408ac','self_destination':'0x4408b8','unavailable':'0x4408e2'}[expected(row['input'])['branch']]
        if row['native']!=expected(row['input']) or row['normal_return'] or row['stop_address']!=stop or not row['actors_unchanged'] or not 0<row['instructions']<1024:raise ValueError('Cure route boundary differs')
    if hashlib.sha256(bytes.fromhex(p['bytes'])).hexdigest()!=BYTES_SHA or p['bytes_sha256']!=BYTES_SHA:raise ValueError('Cure route instruction digest differs')


def execute_packet(exe: Path) -> dict:
    """Run the bounded original instructions on the documented EXE and assemble the packet."""
    base,mapped=image(exe.read_bytes());raw=bytes(mapped[0x440877-base:0x4408e8-base])
    p=dict(schema='hsl_item_cure_route.v1',exe_sha256=EXE_SHA,native_execution=True,evidence_tier='static-derived',cases=[execute(base,mapped,c) for c in cases()],bytes=raw.hex(),bytes_sha256=hashlib.sha256(raw).hexdigest(),limits=['Category selection priority and actual path search are separate; this prefix only validates self-versus-ally cure setup before moving or consuming inventory.'])
    return p


def summary_line(p: dict, executed_now: bool) -> str:
    return 'ITEM_CURE_ROUTE_PASS cases='+str(len(p['cases']))+' executed_now='+str(executed_now)+' bytes='+p['bytes_sha256']


TASK = ProbeTask('item_cure_route', PACKET, check, execute_packet, summary_line)


def tasks() -> list[ProbeTask]:
    return [TASK]
