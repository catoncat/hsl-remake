"""Execute original wait-setting and object-synchronization VM instructions.

Each VM invocation enters0x450840 and returns normally after one opcode. Nearby
AI wait decisions reuse their separately bounded source suffix, not a stub.

Registry task script_wait (family probe, hsltools.probes._base.ProbeTask): check validates the
tracked packet against the independent model; generate executes the original instructions
(needs the documented hsl01.exe and unicorn). Bodies moved verbatim from the former hsl_native_script_wait_probe.py.
"""
from __future__ import annotations
import hashlib
import json
from pathlib import Path
import struct

from hsltools.native.image import EXE_SHA, image
from hsltools.paths import ROOT
from hsltools.probes._base import ProbeTask
from hsltools.probes.ai_navigation import execute as wait_execute, expected as wait_expected
from hsltools.probes.departure import setup_world
from hsltools.sources.tables import TABLES

PACKET = ROOT / 'docs/evidence_packets/static_reverse/original_script_wait.json'

ANCHORS_SHA='7fa3058ca7b925962c7f105ace3fa3c54881012d9ee6cbf1e377c0d64f42e7bf'
ANCHORS=[(0x452388,48,'Opcode33 replaces the previous insertion actor wait DWORD and advances one argument.'),
         (0x4523b8,80,'Opcode34 resolves the current registered code/serial and replaces wait, advancing three arguments even without a target.'),
         (0x4513b4,103,'Opcode88 rewinds its own cursor while the selected object phase is nonzero; idle or missing advances without changing actor data.'),
         (0x43f603,40,'A fresh AI wait evaluation decrements a nonzero count; any status or missing HP wakes it.'),
         (0x43f644,63,'A valid nearby target clears the remaining wait; a missing or removed target leaves the wait branch.')]

def cases():
    setters=[dict(opcode=opcode,code=code,serial=serial,value=value,old=old,previous=previous)
             for opcode in [33,34] for code,serial in [(26,0),(26,2),(23,1),(999,1)]
             for value,old in [(0,6),(1,0),(2,9),(9999,1),(-1,0)] for previous in [0,2]]
    waits=[dict(opcode=88,code=code,serial=serial,phase=phase,other_phase=other,repeat=repeat)
           for code,serial in [(26,0),(26,2),(23,1),(999,1)]
           for phase,other in [(0,0),(0,0x360063),(0x10000,0),(0x350001,0),(0x360003,0x10000)] for repeat in [False,True]]
    return setters+waits

def index_for(c):
    if c['opcode']==33:return c['previous']
    return -1 if c['code']==999 else (1 if c['code']==26 and c['serial']>=2 else 0) if c['code']==26 else 2

def expected(c):
    index=index_for(c);op=c['opcode']
    if op!=88:
        values=[c['old']]*3
        if index>=0:values[index]=c['value']&0xffffffff
        return dict(wait_values=values,cursor_words=2 if op==33 else 4,returns=1,records_unchanged_except_wait=True)
    blocked=index>=0 and c['phase']!=0
    return dict(cursor_words=3 if not blocked or c['repeat'] else 0,first_cursor_words=0 if blocked else 3,
                returns=2 if blocked and c['repeat'] else 1,records_unchanged=True,queue_unchanged=True)

def execute(base,mapped,c):
    from unicorn import UC_HOOK_CODE
    from unicorn.x86_const import UC_X86_REG_ESP,UC_X86_REG_EIP
    m,put,get,call,pointers,record,grid,parent=setup_world(base,mapped,{})
    records=record-0x1fc; vm=0x10017000; program=0x10018000;op=c['opcode'];index=index_for(c)
    for i,p in enumerate(pointers):
        put(p+0x8c,c.get('phase',0) if i==index else c.get('other_phase',0))
        put(records+i*0x1fc+0x1b8,c.get('old',6))
    put(0x4c1d38,pointers[c.get('previous',0)]);put(vm+0x8c,0);put(vm+0x90,program)
    args=[c['value']] if op==33 else [c['code'],c['serial']]+([c['value']] if op==34 else [])
    for i,value in enumerate([op,*args]):put(program+4*i,value)
    before=bytearray(m.mem_read(records,3*0x1fc));queue=bytes(m.mem_read(0x4c3940,2400));steps=0
    allowed=[(0x450840,0x4508a8),(0x452388,0x452408),(0x4513b4,0x45141b),(0x4527c3,0x4527d5),(0x44fa80,0x44fb8a)]
    def guard(_m,at,_n,_d):
        nonlocal steps
        steps+=1
        if not any(lo<=at<hi for lo,hi in allowed):raise ValueError(f'Unreviewed script-wait callee {at:#x}')
    m.hook_add(UC_HOOK_CODE,guard)
    def invoke():
        result=call(0x450840,[vm],4096)
        if result!=0 or m.reg_read(UC_X86_REG_EIP)!=0x10000000 or m.reg_read(UC_X86_REG_ESP)!=0x1001ff04:
            raise ValueError('Script wait did not return normally')
    invoke();pc=(get(vm+0x90)-program)//4;returns=1
    if op==88:
        first=pc
        if index>=0 and c['phase'] and c['repeat']:
            put(pointers[index]+0x8c,0);invoke();returns+=1;pc=(get(vm+0x90)-program)//4
        actual=dict(cursor_words=pc,first_cursor_words=first,returns=returns,
                    records_unchanged=before==bytes(m.mem_read(records,len(before))),queue_unchanged=queue==bytes(m.mem_read(0x4c3940,2400)))
    else:
        wanted=before[:]
        if index>=0:struct.pack_into('<I',wanted,index*0x1fc+0x1b8,c['value']&0xffffffff)
        actual=dict(wait_values=[get(records+i*0x1fc+0x1b8) for i in range(3)],cursor_words=pc,returns=returns,
                    records_unchanged_except_wait=wanted==bytes(m.mem_read(records,len(before))))
    if actual!=expected(c):raise ValueError((c,actual,expected(c)))
    return dict(input=c,native=actual,normal_return=True,instructions=steps)

def wait_cases():
    return [dict(kind='wait',wait=wait,hp=hp,flags=flags)
            for wait in [0,1,2,9999] for hp,flags in [(100,0),(99,0),(100,1),(100,2),(100,4),(100,0x10),(100,0x20)]]

def check(p):
    if p.get('schema')!='hsl_script_wait_native.v1' or p.get('exe_sha256')!=EXE_SHA or p.get('native_execution') is not True:
        raise ValueError('Script wait identity differs')
    if p['source_action_sha256']!=hashlib.sha256((TABLES/'ACTION.H').read_bytes()).hexdigest():raise ValueError('Script opcode source differs')
    if [r['input'] for r in p['vm']]!=cases() or [r['input'] for r in p['wait']]!=wait_cases():raise ValueError('Script wait coverage differs')
    for row in p['vm']:
        if row['native']!=expected(row['input']) or row['normal_return'] is not True or not 0<row['instructions']<8192:raise ValueError('Script-wait return differs')
    for row in p['wait']:
        if row['native']!=wait_expected(row['input']) or row['normal_return'] is not False or row['entry']!='0x43f603' or row['stop_address'] not in ['0x43f62b','0x43f67f']:raise ValueError('AI wait suffix differs')
    if [(int(r['address'],16),len(bytes.fromhex(r['bytes'])),r['meaning']) for r in p['anchors']]!=ANCHORS:raise ValueError('Script wait caller anchors differ')
    if hashlib.sha256(bytes.fromhex(''.join(r['bytes'] for r in p['anchors']))).hexdigest()!=ANCHORS_SHA:raise ValueError('Script wait instruction bytes differ')


def execute_packet(exe: Path) -> dict:
    """Run the bounded original instructions on the documented EXE and assemble the packet."""
    base,mapped=image(exe.read_bytes())
    p=dict(schema='hsl_script_wait_native.v1',exe_sha256=EXE_SHA,evidence_tier='static-derived',native_execution=True,
           source_action_sha256=hashlib.sha256((TABLES/'ACTION.H').read_bytes()).hexdigest(),
           vm=[execute(base,mapped,c) for c in cases()],wait=[wait_execute(base,mapped,c) for c in wait_cases()],
           anchors=[dict(address=hex(at),bytes=bytes(mapped[at-base:at-base+n]).hex(),meaning=meaning) for at,n,meaning in ANCHORS],
           limits=['VM returns normally after one opcode; busy object replay invokes it again only after that object becomes idle.',
                   'Setter stores a full DWORD without clamping; live nonnegative0..10000 domain excludes unbounded/negative raw values.',
                   'AI waiting suffixes stop before nearby search or normal priority; retained-target and full navigation evidence are separate.',
                   'Object-phase waiting does not tick actor statuses, consume resources or remove the actor from the battle queue.'])
    return p


def summary_line(p: dict, executed_now: bool) -> str:
    return f'SCRIPT_WAIT_NATIVE_PASS vm_cases={len(p["vm"])} normal_returns={sum(r["native"]["returns"] for r in p["vm"])} wait_suffixes={len(p["wait"])} executed_now={executed_now} anchors_sha='+hashlib.sha256(bytes.fromhex(''.join(r['bytes'] for r in p['anchors']))).hexdigest()


TASK = ProbeTask('script_wait', PACKET, check, execute_packet, summary_line)


def tasks() -> list[ProbeTask]:
    return [TASK]
