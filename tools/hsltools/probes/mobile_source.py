"""Execute the native optional numeric-field reader when the attribute is absent.

Registry task mobile_source (family probe, hsltools.probes._base.ProbeTask): check validates the
tracked packet against the independent model; generate executes the original instructions
(needs the documented hsl01.exe and unicorn). Bodies moved verbatim from the former hsl_native_mobile_source_probe.py.
"""
from __future__ import annotations
import json
from pathlib import Path
import struct

from hsltools.native.image import EXE_SHA, image
from hsltools.native.machine import machine_for
from hsltools.paths import ROOT
from hsltools.probes._base import ProbeTask
from hsltools.probes.priest import execute_binding
from hsltools.sources.tables import digest

PACKET = ROOT / 'docs/evidence_packets/static_reverse/original_optional_source_field.json'

def execute(base,mapped,before):
    from unicorn import UC_HOOK_CODE
    from unicorn.x86_const import UC_X86_REG_ESP,UC_X86_REG_EIP,UC_X86_REG_EAX
    m=machine_for(base,mapped);stack,stop,table,name,output=0x1001ff00,0x10000000,0x10001000,0x10002000,0x10003000
    def put(at,v):m.mem_write(at,struct.pack('<I',v))
    put(0x4c24b4,table);put(0x4c25c8,32);put(table+11,0)
    put(output,before);m.mem_write(name,b'status\0')
    m.mem_write(stack,struct.pack('<5I',stop,name,1,0,output));m.reg_write(UC_X86_REG_ESP,stack)
    steps=0
    def guard(_m,at,_size,_data):
        nonlocal steps
        steps+=1
        if not 0x46dd50<=at<0x46debe:raise ValueError(f'Unreviewed optional-field callee {at:#x}')
    m.hook_add(UC_HOOK_CODE,guard);m.emu_start(0x46de70,stop,count=512)
    value=struct.unpack('<I',m.mem_read(output,4))[0]
    if m.reg_read(UC_X86_REG_EIP)!=stop or m.reg_read(UC_X86_REG_ESP)!=stack+4 or m.reg_read(UC_X86_REG_EAX)!=0 or value!=before:raise ValueError('Absent optional field overwrote caller default')
    return dict(before=before,after=value,result=0,instructions=steps,normal_return=True)

def check(packet):
    if packet.get('schema')!='hsl_optional_source_field.v1' or packet.get('exe_sha256')!=EXE_SHA or packet.get('native_execution') is not True:raise ValueError('Optional source identity differs')
    if [r['before'] for r in packet['cases']]!=[0,77]:raise ValueError('Optional field coverage differs')
    for r in packet['cases']:
        if r['after']!=r['before'] or r['result']!=0 or not r['normal_return'] or not 0<r['instructions']<512:raise ValueError('Optional field return differs')
    if [r['input'] for r in packet['bindings']]!=[dict(slot=s,object_code=800+s,previous_template=29) for s in [3,5]]:raise ValueError('Mobile player binding coverage differs')
    for r in packet['bindings']:
        c=r['input'];index=c['slot']+1
        if (r['template_index'],r['copy_return'],r['object_code'],r['normal_returns'],r['prefix_stop'])!=(index,index,c['object_code'],4,'0x407f14'):raise ValueError('Mobile player binding return differs')
        if r['live_sha256']!=r['template_sha256'] or r['template_sha256']!=digest(bytes((i*13+index)%256 for i in range(0x1fc))):raise ValueError('Mobile player template copy differs')


def execute_packet(exe: Path) -> dict:
    """Run the bounded original instructions on the documented EXE and assemble the packet."""
    base,mapped=image(exe.read_bytes());packet=dict(schema='hsl_optional_source_field.v1',exe_sha256=EXE_SHA,native_execution=True,evidence_tier='static-derived',cases=[execute(base,mapped,v) for v in [0,77]],bindings=[execute_binding(base,mapped,dict(slot=s,object_code=800+s,previous_template=29)) for s in [3,5]],limits=['Empty attribute chain executes46de70 and46dd50 normally; output remains the caller default. Whole PLAYERS parsing is not executed.','Role loader44b980 explicitly initializes the status output to zero before optional lookup; new source006/036 omit that field.','Player slots3/5 execute source binding and complete template copy into records4/6; each case has four normal helper returns and a bounded407eff prefix.'])
    return packet


def summary_line(packet: dict, executed_now: bool) -> str:
    return 'OPTIONAL_SOURCE_FIELD_PASS normal_returns=2 player_bindings=2 binding_helper_returns=8 executed_now='+str(executed_now)


TASK = ProbeTask('mobile_source', PACKET, check, execute_packet, summary_line)


def tasks() -> list[ProbeTask]:
    return [TASK]
