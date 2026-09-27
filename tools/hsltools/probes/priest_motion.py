"""Run original speed commands and the isolated movement tail, excluding drawing.

Registry task priest_motion (family probe, hsltools.probes._base.ProbeTask): check validates the
tracked packet against the independent model; generate executes the original instructions
(needs the documented hsl01.exe and unicorn). Bodies moved verbatim from the former hsl_native_priest_motion_probe.py.
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

PACKET = ROOT / 'docs/evidence_packets/static_reverse/original_priest_motion.json'

PROGRAM = [4,192,0x100000,0x10000,0,1,18,3,64,0,0x10000,0x100000,1,15,5,0]


def expected_states():
    # Each speed command yields; each delay setup plus its N waiting calls yields.
    # Integration uses current speed before the clamp/step, including setup.
    rows=[];y=0;speed=0x100000
    for i in range(20):
        y-=speed//65536;speed=max(0,speed-65536)
        rows.append(dict(y=y,speed=speed,flags=0x2000))
    speed=0
    for i in range(17):
        y+=speed//65536;speed=min(0x100000,speed+65536)
        rows.append(dict(y=y,speed=speed,flags=0x4000))
    rows.extend([dict(y=y,speed=speed,flags=0),dict(y=y,speed=speed,flags=0)])
    return rows


def execute(base,mapped):
    from unicorn import UC_HOOK_CODE
    from unicorn.x86_const import UC_X86_REG_ESI,UC_X86_REG_EAX,UC_X86_REG_ESP,UC_X86_REG_EIP
    m=machine_for(base,mapped);obj,program,stack=0x10001000,0x10004000,0x1001f800
    def put(at,v):m.mem_write(at,struct.pack('<I',v&0xffffffff))
    def get(off):return struct.unpack('<i',m.mem_read(obj+off,4))[0]
    put(obj+0xa4,program)
    for i,v in enumerate(PROGRAM):put(program+i*4,v)
    mode='dispatch';steps=0
    def guard(_m,at,_size,_data):
        nonlocal steps
        steps+=1
        if at==(STOP if mode=='dispatch' else 0x4035eb):m.emu_stop();return
        allowed=[(ENTRY,STOP),(0x446be0,0x446c0d)] if mode=='dispatch' else [(0x40351e,0x4035eb),(0x45eb75,0x45ec0e)]
        if not any(lo<=at<hi for lo,hi in allowed):raise ValueError(f'Unreviewed priest motion callee {at:#x}')
    m.hook_add(UC_HOOK_CODE,guard);rows=[]
    for _ in range(64):
        mode='dispatch';m.mem_write(stack,struct.pack('<3I',0x10000000,obj,0));m.reg_write(UC_X86_REG_ESP,stack)
        m.emu_start(ENTRY,0x10000000,count=1024)
        if m.reg_read(UC_X86_REG_EIP)!=STOP:raise ValueError('Speed setter exceeded boundary')
        mode='motion';m.reg_write(UC_X86_REG_ESI,obj);m.reg_write(UC_X86_REG_EAX,get(0x80));m.reg_write(UC_X86_REG_ESP,stack)
        m.emu_start(0x40351e,0x10000000,count=1024)
        if m.reg_read(UC_X86_REG_EIP)!=0x4035eb:raise ValueError('Movement tail exceeded boundary')
        rows.append(dict(y=get(8),speed=get(0x9c),flags=get(0x80)&0x6000))
        if get(0x8c)>>16==101:break
    if rows!=expected_states():raise ValueError(f'Native speed timing differs: {rows}')
    return dict(states=rows,instructions=steps,normal_return=False,dispatcher_stop=hex(STOP),motion_stop='0x4035eb')


def check(packet):
    if packet.get('schema')!='hsl_priest_motion_native.v1' or packet.get('exe_sha256')!=EXE_SHA or packet.get('native_execution') is not True:raise ValueError('Motion identity missing')
    if packet['program']!=PROGRAM or packet['native']['states']!=expected_states() or packet['native']['normal_return'] is not False or packet['native']['motion_stop']!='0x4035eb' or packet['native']['dispatcher_stop']!=hex(STOP):raise ValueError('Motion boundary/result differs')
    if packet['directions']!={'64':[0,65536],'192':[0,-65536]}:raise ValueError('Source directions differ')
    for key,path in [('programs','content/imported/hsl/chapter01/combat_animation/ANIMAL.TXT'),('header','content/imported/hsl/global/tables/ANIMAL.H')]:
        if packet['sources'][key]!=digest(Path(path).read_bytes()):raise ValueError('Motion source changed')


def execute_packet(exe: Path) -> dict:
    """Run the bounded original instructions on the documented EXE and assemble the packet."""
    base,mapped=image(exe.read_bytes())
    packet=dict(schema='hsl_priest_motion_native.v1',exe_sha256=EXE_SHA,native_execution=True,evidence_tier='static-derived',program=PROGRAM,
                sources={key:digest(Path(path).read_bytes()) for key,path in [('programs','content/imported/hsl/chapter01/combat_animation/ANIMAL.TXT'),('header','content/imported/hsl/global/tables/ANIMAL.H')]},
                directions={str(angle):[struct.unpack_from('<i',mapped,table-base+angle*4)[0] for table in [0x4a35fc,0x4a39fc]] for angle in [64,192]},
                native=execute(base,mapped),
                limits=['Synthetic excerpt of priest speed/stop/delays plus explicit aniOver; not original parser padding or full attack execution.',
                        'Each update executes dispatcher to common drawing tail, then an independent bounded movement prefix with original callees; no rendering stubs.',
                        'Only authored vertical angles64/192 and integer fixed-point speeds are enabled; general trig/fractional movement remains separate.',
                        'Source shape/flash order uses the existing ordinary-program proof; current renderer shot/impact/clock remain remake presentation choices.'])
    return packet


def summary_line(packet: dict, executed_now: bool) -> str:
    return 'PRIEST_MOTION_NATIVE_PASS updates='+str(len(packet['native']['states']))+' executed_now='+str(executed_now)


TASK = ProbeTask('priest_motion', PACKET, check, execute_packet, summary_line)


def tasks() -> list[ProbeTask]:
    return [TASK]
