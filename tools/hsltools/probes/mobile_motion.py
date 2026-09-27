"""Bounded horizontal speed tail and relative XY suffix for source004/006 art.

Registry task mobile_motion (family probe, hsltools.probes._base.ProbeTask): check validates the
tracked packet against the independent model; generate executes the original instructions
(needs the documented hsl01.exe and unicorn). Bodies moved verbatim from the former hsl_native_mobile_motion_probe.py.
"""
from __future__ import annotations
import json
from pathlib import Path
import struct

from hsltools.native.animal_dispatcher import ENTRY, STOP
from hsltools.native.image import EXE_SHA, image
from hsltools.native.machine import machine_for
from hsltools.paths import ROOT
from hsltools.probes._base import ProbeTask
from hsltools.sources.tables import digest

PACKET = ROOT / 'docs/evidence_packets/static_reverse/original_mobile_motion.json'

PROGRAM=[4,0,0xa0000,0x10000,0,1,12,4,128,0xa0000,0x8000,0,1,35,5,0]

def expected_motion():
    rows=[];x=0
    for direction,count,step in [(1,14,0x10000),(-1,37,0x8000)]:
        speed=0xa0000
        for _ in range(count):
            x+=(direction*speed)//65536;speed=max(0,speed-step)
            rows.append(dict(x=x,y=0,speed=speed,flags=0x2000))
    rows.extend([dict(x=x,y=0,speed=0,flags=0),dict(x=x,y=0,speed=0,flags=0)])
    return rows

def motion(base,mapped):
    from unicorn import UC_HOOK_CODE
    from unicorn.x86_const import UC_X86_REG_ESI,UC_X86_REG_EAX,UC_X86_REG_ESP,UC_X86_REG_EIP
    m=machine_for(base,mapped);obj,program,stack=0x10001000,0x10004000,0x1001f800
    def put(at,v):m.mem_write(at,struct.pack('<I',v&0xffffffff))
    def get(off):return struct.unpack('<i',m.mem_read(obj+off,4))[0]
    put(obj+0xa4,program)
    for i,value in enumerate(PROGRAM):put(program+i*4,value)
    mode='dispatch';steps=0
    def guard(_m,at,_size,_data):
        nonlocal steps
        if at==(STOP if mode=='dispatch' else 0x4035eb):m.emu_stop();return
        steps+=1
        allowed=[(ENTRY,STOP),(0x446be0,0x446c0d)] if mode=='dispatch' else [(0x40351e,0x4035eb),(0x45eb75,0x45ec0e)]
        if not any(lo<=at<hi for lo,hi in allowed):raise ValueError(f'Unreviewed horizontal motion callee {at:#x}')
    m.hook_add(UC_HOOK_CODE,guard);rows=[]
    for _ in range(90):
        mode='dispatch';m.mem_write(stack,struct.pack('<3I',0x10000000,obj,0));m.reg_write(UC_X86_REG_ESP,stack)
        m.emu_start(ENTRY,0x10000000,count=1024)
        if m.reg_read(UC_X86_REG_EIP)!=STOP:raise ValueError('Horizontal setter failed boundary')
        mode='motion';m.reg_write(UC_X86_REG_ESI,obj);m.reg_write(UC_X86_REG_EAX,get(0x80));m.reg_write(UC_X86_REG_ESP,stack)
        m.emu_start(0x40351e,0x10000000,count=1024)
        if m.reg_read(UC_X86_REG_EIP)!=0x4035eb:raise ValueError('Horizontal integration failed boundary')
        rows.append(dict(x=get(4),y=get(8),speed=get(0x9c),flags=get(0x80)&0x6000))
        if get(0x8c)>>16==101:break
    if rows!=expected_motion():raise ValueError('Horizontal signed fixed-point steps differ: '+str(rows))
    return dict(states=rows,normal_return=False,dispatcher_stop=hex(STOP),motion_stop='0x4035eb',instructions=steps)

def xy_cases():return [dict(offset=pair,mirrored=flag) for pair in [[50,0],[0,-140],[-50,17]] for flag in [False,True]]

def xy(base,mapped,case):
    from unicorn import UC_HOOK_CODE
    from unicorn.x86_const import UC_X86_REG_ESI,UC_X86_REG_EDI,UC_X86_REG_EBX,UC_X86_REG_ESP,UC_X86_REG_EIP
    m=machine_for(base,mapped);obj,parent,actor,program,stack=0x10001000,0x10002000,0x10003000,0x10004000,0x1001f800
    def put(at,v):m.mem_write(at,struct.pack('<I',v&0xffffffff))
    def get(off):return struct.unpack('<i',m.mem_read(obj+off,4))[0]
    for at,value in [(obj+4,320),(obj+8,320),(obj+0xac,parent),(parent+0xa4,0),(0x4c1bc8,actor),(actor+0xa0,8 if case['mirrored'] else 0)]:put(at,value)
    for i,value in enumerate([*case['offset'],0]):put(program+4*i,value)
    for reg,value in [(UC_X86_REG_ESI,obj),(UC_X86_REG_EDI,program),(UC_X86_REG_EBX,0),(UC_X86_REG_ESP,stack)]:m.reg_write(reg,value)
    steps=0
    def guard(_m,at,_size,_data):
        nonlocal steps
        steps+=1
        if not(0x40218f<=at<0x4021df or 0x402278<=at<0x4022aa or 0x401f3b<=at<0x401f60 or 0x446be0<=at<0x446c0d):raise ValueError(f'Unreviewed XY suffix callee {at:#x}')
    m.hook_add(UC_HOOK_CODE,guard);m.emu_start(0x40218f,STOP,count=512)
    wanted=[320+case['offset'][0]*(-1 if case['mirrored'] else 1),320+case['offset'][1]]
    actual=[get(4),get(8)]
    if actual!=wanted or m.reg_read(UC_X86_REG_EIP)!=STOP or get(0x8c)>>16!=101:raise ValueError('Relative XY suffix did not drain next opcode')
    return dict(input=case,position=actual,normal_return=False,entry='0x40218f',stop_address=hex(STOP),instructions=steps,next_over_same_call=True)

def check(packet):
    if packet.get('schema')!='hsl_mobile_motion_native.v1' or packet.get('exe_sha256')!=EXE_SHA or packet.get('native_execution') is not True:raise ValueError('Mobile motion identity differs')
    if packet['program']!=PROGRAM or packet['motion']['states']!=expected_motion() or packet['motion']['motion_stop']!='0x4035eb' or packet['motion']['normal_return']:raise ValueError('Mobile motion states/boundary differ')
    if [r['input'] for r in packet['xy']]!=xy_cases():raise ValueError('Relative XY coverage differs')
    for r in packet['xy']:
        c=r['input']
        if r['position']!=[320+c['offset'][0]*(-1 if c['mirrored'] else 1),320+c['offset'][1]] or not r['next_over_same_call'] or r['normal_return'] or r['entry']!='0x40218f' or r['stop_address']!=hex(STOP):raise ValueError('Relative XY result differs')
    if packet['source_sha256']!=digest(Path('content/imported/hsl/chapter01/combat_animation/ANIMAL.TXT').read_bytes()):raise ValueError('Mobile animation source changed')


def execute_packet(exe: Path) -> dict:
    """Run the bounded original instructions on the documented EXE and assemble the packet."""
    base,mapped=image(exe.read_bytes());packet=dict(schema='hsl_mobile_motion_native.v1',exe_sha256=EXE_SHA,native_execution=True,evidence_tier='static-derived',program=PROGRAM,motion=motion(base,mapped),xy=[xy(base,mapped,c) for c in xy_cases()],source_sha256=digest(Path('content/imported/hsl/chapter01/combat_animation/ANIMAL.TXT').read_bytes()),limits=['XY suffix begins after optional afterimage construction, which is not stubbed or claimed executed. It applies relative coordinates and drains the next opcode in the same invocation.', 'Horizontal motion is an explicit authored-speed excerpt; full drawing/flash/mirroring dispatch remains separate. Signed half-speed rounds down per original fixed-point math.','Source006 consecutive zoom handler already has its own animal_program_execution proof; renderer wall-clock and framing remain remake choices.'])
    return packet


def summary_line(packet: dict, executed_now: bool) -> str:
    return f'MOBILE_MOTION_NATIVE_PASS updates={len(packet["motion"]["states"])} xy={len(packet["xy"])} executed_now={executed_now}'


TASK = ProbeTask('mobile_motion', PACKET, check, execute_packet, summary_line)


def tasks() -> list[ProbeTask]:
    return [TASK]
