"""Bounded original scripted departure: request, fade, spatial/queue cleanup.

Registry task departure (family probe, hsltools.probes._base.ProbeTask): check validates the
tracked packet against the independent model; generate executes the original instructions
(needs the documented hsl01.exe and unicorn). Bodies moved verbatim from the former hsl_native_departure_probe.py.
"""
from __future__ import annotations
import hashlib
import json
from pathlib import Path
import struct

from hsltools.native.image import EXE_SHA, image
from hsltools.paths import ROOT
from hsltools.probes._base import ProbeTask
from hsltools.probes.large_actor import setup, body

PACKET = ROOT / 'docs/evidence_packets/static_reverse/original_script_departure.json'

ANCHOR_SHA='6f65d754b7266536c1546b032221a5bb8cc7d98a7de00161b5230d909d306efc'
ANCHORS=[(0x450410,55,'Delete request selects a registered object and schedules state35 with parent continuation.'),
         (0x450450,118,'Walk/delete request requires idle target, writes destination and schedules state36/99.'),
         (0x454286,49,'Walking departure enters a16-tick fade only after its walking stages.'),
         (0x4542a7,112,'Fade completion advances script parent, removes map/queue/template, then unlinks the object; no reward or HP path.'),
         (0x407720,223,'Departure clears registry and queue slot; current removal seeks another enabled slot.'),
         (0x44cb90,29,'Template removal clears record header except slot0; does not zero vitals or inventory.'),
         (0x45e3ed,152,'Object unlink removes active flag, linked-list and bucket membership; a repeated inactive call is a no-op.')]

def cases():
    return [dict(phase=p,sub=s,ticks=t,current=current,large=large,parent=parent)
            for p,s in [(53,0),(53,1),(54,7),(54,8),(54,99)]
            for t in ([1,3] if s in [1,8] else [0])
            for current in [False,True] for large in [0,1] for parent in [False,True]]

def setup_world(base,mapped,c):
    m,put,get,call,obj,records,grid,_=setup(base,mapped,dict(size=[12,12],origin=[5,5],large=c.get('large',0)))
    pointers=[obj,obj+0x200,obj+0x400];target=pointers[1];record=records+0x1fc;parent=obj+0x800
    m.mem_write(0x4c3940,bytes(2400));put(0x4c6e48,1 if c.get('current') else 0)
    put(0x4c1b90,2);put(0x4c1b94,1)
    put(0x4a35ec,0x10010000);put(0x10010000,0x10011000)
    put(0x4a19d8,pointers[2]);put(0x4a35f0,0x10011010);put(0x4a19dc,3)
    for i,p in enumerate(pointers):
        for off,v in [(0x80,0x80000000),(0xa0,i),(0xa4,i),(0x64,3),(0x5c,pointers[i-1] if i else 0),
                      (0x60,pointers[i+1] if i<2 else 0),(0x58,0),(4,(2+i*3)*32+16),(8,(2+i*3)*32+16)]:put(p+off,v)
        put(0x4c34c0+4*i,p)
        put(0x4c3940+12*i,p);put(0x4c3944+12*i,100-i);put(0x4c3948+12*i,1)
        put(0x10011000+8*i,p);put(0x10011004+8*i,0x10011000+8*(i+1) if i<2 else 0)
        for off,v in [(0,1),(0x28,0x20000 if i==1 else 0x10000),(0x84,26 if i<2 else 23),(0xd8,73),(0xe0,19),(0xe8,20),(0x88,37),(0x24,7),(0x30,0x140003),(0x34,3),(0x3c,2)]:put(records+i*0x1fc+off,v)
    put(record+0x2c,c.get('large',0));put(parent+0x8c,0x220003)
    for x,y in body([5,5],c.get('large',0)):put(grid+4*(y*12+x),0x1020000)
    put(target+0x8c,(c.get('phase',53)<<16)|c.get('sub',0));put(target+0x28,c.get('ticks',0))
    put(target+0x50,parent if c.get('parent') else 0)
    return m,put,get,call,pointers,record,grid,parent

ALLOWED=[(0x453b90,0x45432a),(0x407940,0x407987),(0x40ba20,0x40ba72),
         (0x411900,0x4119d0),(0x411ae0,0x411c40),(0x407720,0x4077ff),(0x407540,0x407550),
         (0x4074a0,0x407510),(0x44cb90,0x44cbad),(0x45e3ed,0x45e485)]
CALLS=[0x407940,0x40ba20,0x411b90,0x407540,0x407720,0x4074a0,0x44cb90,0x45e3ed]

def execute(base,mapped,c):
    from unicorn import UC_HOOK_CODE
    from unicorn.x86_const import UC_X86_REG_ESP,UC_X86_REG_EIP
    m,put,get,call,pointers,record,grid,parent=setup_world(base,mapped,c)
    target=pointers[1];stack=0x1001ff00;stop=0x10000000;steps=0;calls=[]
    before=bytes(m.mem_read(record+4,0x1f8))
    def guard(_m,at,_n,_d):
        nonlocal steps
        if at==0x4542ff:m.emu_stop();return # current-actor renderer/reset callback is separate
        steps+=1
        if at in CALLS:calls.append(hex(at))
        if not any(a<=at<b for a,b in ALLOWED):raise ValueError(f'Unreviewed departure callee {at:#x}')
    m.hook_add(UC_HOOK_CODE,guard)
    m.mem_write(stack,struct.pack('<2I',stop,target));m.reg_write(UC_X86_REG_ESP,stack)
    m.emu_start(0x453b90,stop,count=16384)
    end=m.reg_read(UC_X86_REG_EIP)
    if end not in [stop,0x4542ff] or (end==stop and m.reg_read(UC_X86_REG_ESP)!=stack+4):raise ValueError('Departure did not return/reach declared boundary')
    cleanup=c['sub'] in [1,8] and c['ticks']==1
    sub=c['sub'];ticks=c['ticks']
    if sub==0 and c['phase']==53:sub=1;ticks=16
    elif sub==7:sub=8;ticks=16
    elif sub==99:sub=0
    elif sub in [1,8]:ticks-=1
    expected_phase=(c['phase']<<16)|sub
    actual=dict(phase=get(target+0x8c),ticks=get(target+0x28),registered=get(0x4c34c4)!=0,
                queue_present=get(0x4c394c)!=0,index=get(0x4c6e48),record_header=get(record),
                active=bool(get(target+0x80)&0x80000000),parent_phase=get(parent+0x8c),
                map_flags=[get(grid+4*(y*12+x)) for x,y in body([5,5],c['large'])],
                vitals_unchanged=before==bytes(m.mem_read(record+4,0x1f8)),objects=get(0x4a19dc))
    wanted=dict(phase=expected_phase,ticks=ticks,registered=not cleanup,queue_present=not cleanup,
                index=2 if cleanup and c['current'] else int(c['current']),record_header=0 if cleanup else 1,
                active=not(cleanup and not c['current']),parent_phase=0x220003+int(cleanup and c['parent']),
                map_flags=[0x1000000 if cleanup else 0x1020000]*len(body([5,5],c['large'])),
                vitals_unchanged=True,objects=2 if cleanup and not c['current'] else 3)
    if actual!=wanted:raise ValueError((c,actual,wanted))
    required=['0x411b90','0x407720','0x44cb90'] if cleanup else []
    if any(k not in calls for k in required) or (not cleanup and calls):raise ValueError('Departure cleanup order differs')
    return dict(input=c,native=actual,calls=calls,normal_return=end==stop,stop_address=hex(end),instructions=steps)

def requests(base,mapped):
    from unicorn import UC_HOOK_CODE
    from unicorn.x86_const import UC_X86_REG_ESP,UC_X86_REG_EIP,UC_X86_REG_EAX
    result=[]
    for code in [26,23,999]:
        for ordinal in [0,1,2,9]:
            m,put,get,call,pointers,record,grid,parent=setup_world(base,mapped,{})
            steps=0
            def guard(_m,at,_n,_d):
                nonlocal steps
                steps+=1
                if not any(a<=at<b for a,b in [(0x450410,0x450447),(0x44fad0,0x44fb8a),(0x44fa80,0x44fac5)]):raise ValueError(f'Unreviewed request {at:#x}')
            m.hook_add(UC_HOOK_CODE,guard)
            value=call(0x450410,[code,ordinal,parent],4096)
            index= min(1,max(0,ordinal-1)) if code==26 else 2 if code==23 else -1
            # Native ordinal0/1 both choose first; an oversize ordinal returns the last matching actor.
            expected=pointers[index] if index>=0 else 0
            if value!=expected:raise ValueError((code,ordinal,hex(value),hex(expected)))
            phases=[get(p+0x8c) for p in pointers]
            if index>=0 and (phases[index]!=0x350000 or get(value+0x50)!=parent):raise ValueError('Delete request did not bind phase/parent')
            result.append(dict(code=code,ordinal=ordinal,native_index=index,phases=phases,normal_return=True,instructions=steps))
    return result

def walk_cases():
    return [dict(code=code,ordinal=ordinal,idle=idle,x=x,y=y,speed=speed)
            for code,ordinal in [(26,0),(26,2),(23,1),(999,1)]
            for idle in [False,True] for x,y,speed in [(192,224,2),(201,231,6)]]

def relookup(base,mapped):
    from unicorn import UC_HOOK_CODE
    rows=[]
    for ordinal in [0,1,2,9]:
        m,put,get,call,pointers,record,grid,parent=setup_world(base,mapped,dict(phase=53,sub=1,ticks=1,current=False,large=0,parent=True))
        steps=0
        def guard(_m,at,_n,_d):
            nonlocal steps
            steps+=1
            if not any(a<=at<b for a,b in ALLOWED+[(0x450410,0x450447),(0x44fad0,0x44fb8a),(0x44fa80,0x44fac5)]):
                raise ValueError(f'Unreviewed post-departure lookup {at:#x}')
        m.hook_add(UC_HOOK_CODE,guard)
        call(0x453b90,[pointers[1]],16384)
        result=call(0x450410,[26,ordinal,parent],4096)
        actual=dict(index=pointers.index(result),retired_registered=get(0x4c34c4)!=0,
                    retired_active=bool(get(pointers[1]+0x80)&0x80000000),selected_phase=get(result+0x8c))
        if actual!=dict(index=0,retired_registered=False,retired_active=False,selected_phase=0x350000):
            raise ValueError(('post-departure lookup',ordinal,actual))
        rows.append(dict(ordinal=ordinal,native=actual,normal_return=True,instructions=steps))
    return rows

def walk_requests(base,mapped):
    from unicorn import UC_HOOK_CODE
    from unicorn.x86_const import UC_X86_REG_ESP,UC_X86_REG_EIP
    rows=[]
    for case in walk_cases():
        m,put,get,call,pointers,record,grid,parent=setup_world(base,mapped,{})
        for pointer in pointers:put(pointer+0x8c,0 if case['idle'] else 0x10000)
        before=bytes(m.mem_read(record,0x1fc));steps=0
        def guard(_m,at,_n,_d):
            nonlocal steps
            steps+=1
            # Open destination only. A blocked destination's relocation search
            # is independently covered by navigation evidence, not this request.
            if not any(a<=at<b for a,b in [(0x450450,0x4504c7),(0x44fad0,0x44fb8a),(0x44fa80,0x44fac5),
                                          (0x44fbd0,0x44fc29),(0x44fce5,0x44fceb),(0x411c40,0x411c7e)]):
                raise ValueError(f'Unreviewed walk departure request {at:#x}')
        m.hook_add(UC_HOOK_CODE,guard)
        result=call(0x450450,[case['code'],case['ordinal'],case['x'],case['y'],case['speed'],parent],4096)
        accepted=case['idle'] and case['code']!=999
        index=(0 if case['ordinal']<2 else 1) if case['code']==26 else 2
        actual=dict(accepted=bool(result),actor_data_unchanged=before==bytes(m.mem_read(record,0x1fc)))
        if result:
            if result!=pointers[index]:raise ValueError('Walk request selects wrong registered actor')
            actual.update(phase=get(result+0x8c),parent=get(result+0x50)==parent,
                          x=struct.unpack('<H',m.mem_read(result+0x4a,2))[0],
                          y=struct.unpack('<H',m.mem_read(result+0x48,2))[0],
                          speed=struct.unpack('<H',m.mem_read(result+0x98,2))[0])
        expected=dict(accepted=accepted,actor_data_unchanged=True)
        if accepted:expected.update(phase=0x360063,parent=True,x=case['x'],y=case['y'],speed=case['speed'])
        if actual!=expected:raise ValueError((case,actual,expected))
        if m.reg_read(UC_X86_REG_EIP)!=0x10000000 or m.reg_read(UC_X86_REG_ESP)!=0x1001ff04:
            raise ValueError('Walk request did not return normally')
        rows.append(dict(input=case,native=actual,normal_return=True,instructions=steps))
    return rows

def check(packet):
    if packet.get('schema')!='hsl_script_departure_native.v1' or packet.get('exe_sha256')!=EXE_SHA or packet.get('native_execution') is not True:
        raise ValueError('Departure source identity differs')
    if [r['input'] for r in packet['phases']]!=cases():raise ValueError('Departure phase coverage differs')
    for row in packet['phases']:
        c=row['input'];cleanup=c['sub'] in [1,8] and c['ticks']==1
        sub=c['sub'];ticks=c['ticks']
        if sub==0 and c['phase']==53:sub=1;ticks=16
        elif sub==7:sub=8;ticks=16
        elif sub==99:sub=0
        elif sub in [1,8]:ticks-=1
        expected=dict(phase=(c['phase']<<16)|sub,ticks=ticks,registered=not cleanup,queue_present=not cleanup,
                      index=2 if cleanup and c['current'] else int(c['current']),record_header=0 if cleanup else 1,
                      active=not(cleanup and not c['current']),parent_phase=0x220003+int(cleanup and c['parent']),
                      map_flags=[0x1000000 if cleanup else 0x1020000]*(9 if c['large'] else 1),
                      vitals_unchanged=True,objects=2 if cleanup and not c['current'] else 3)
        normal=not(cleanup and c['current'])
        if row['native']!=expected or row['normal_return']!=normal or row['stop_address']!=('0x10000000' if normal else '0x4542ff') or not 0<row['instructions']<16384:
            raise ValueError('Departure native values or stop boundary differ')
        calls=row['calls']
        if cleanup:
            required=['0x411b90','0x407720','0x44cb90']+(['0x45e3ed'] if normal else [])
            if [c for c in calls if c in required]!=required:raise ValueError('Departure cleanup order differs')
        elif calls:raise ValueError('Premature departure cleanup')
    coverage=[(code,ordinal) for code in [26,23,999] for ordinal in [0,1,2,9]]
    if [(r['code'],r['ordinal']) for r in packet['requests']]!=coverage:raise ValueError('Departure request coverage differs')
    for row in packet['requests']:
        index=min(1,max(0,row['ordinal']-1)) if row['code']==26 else 2 if row['code']==23 else -1
        phases=[0,0x350000,0]
        if index>=0:phases[index]=0x350000
        if row['native_index']!=index or row['phases']!=phases or row['normal_return'] is not True or not 0<row['instructions']<4096:
            raise ValueError('Departure request identity/order differs')
    if [r['input'] for r in packet.get('walk_requests',[])]!=walk_cases():raise ValueError('Walk request coverage differs')
    for row in packet['walk_requests']:
        case=row['input'];accepted=case['idle'] and case['code']!=999
        expected=dict(accepted=accepted,actor_data_unchanged=True)
        if accepted:expected.update(phase=0x360063,parent=True,x=case['x'],y=case['y'],speed=case['speed'])
        if row['native']!=expected or row['normal_return'] is not True or not 0<row['instructions']<4096:
            raise ValueError('Walk request result/boundary differs')
    if [r['ordinal'] for r in packet.get('relookup',[])]!=[0,1,2,9]:raise ValueError('Post-departure lookup coverage differs')
    for row in packet['relookup']:
        if row['native']!=dict(index=0,retired_registered=False,retired_active=False,selected_phase=0x350000) or row['normal_return'] is not True or not 0<row['instructions']<20480:
            raise ValueError('Post-departure lookup differs')
    if [(int(a['address'],16),len(bytes.fromhex(a['bytes'])),a['meaning']) for a in packet['anchors']]!=ANCHORS:
        raise ValueError('Departure anchors differ')
    if hashlib.sha256(bytes.fromhex(''.join(a['bytes'] for a in packet['anchors']))).hexdigest()!=ANCHOR_SHA:
        raise ValueError('Departure instruction bytes differ')


def execute_packet(exe: Path) -> dict:
    """Run the bounded original instructions on the documented EXE and assemble the packet."""
    base,mapped=image(exe.read_bytes())
    packet=dict(schema='hsl_script_departure_native.v1',exe_sha256=EXE_SHA,native_execution=True,evidence_tier='static-derived',
                phases=[execute(base,mapped,c) for c in cases()],requests=requests(base,mapped),walk_requests=walk_requests(base,mapped),relookup=relookup(base,mapped),
                anchors=[dict(address=hex(at),bytes=bytes(mapped[at-base:at-base+n]).hex(),meaning=meaning) for at,n,meaning in ANCHORS])
    return packet


def summary_line(packet: dict, executed_now: bool) -> str:
    return f'SCRIPT_DEPARTURE_NATIVE_PASS phases={len(packet["phases"])} requests={len(packet["requests"])} walk_requests={len(packet["walk_requests"])} relookup={len(packet["relookup"])} executed_now={executed_now}'


TASK = ProbeTask('departure', PACKET, check, execute_packet, summary_line)


def tasks() -> list[ProbeTask]:
    return [TASK]
