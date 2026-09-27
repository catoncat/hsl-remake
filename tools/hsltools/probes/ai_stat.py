"""Bounded original buff priority, full ally scan and usefulness helpers; no stubs.

Registry task ai_stat (family probe, hsltools.probes._base.ProbeTask): check validates the
tracked packet against the independent model; generate executes the original instructions
(needs the documented hsl01.exe and unicorn). Bodies moved verbatim from the former hsl_native_ai_stat_probe.py.
"""
from __future__ import annotations
import hashlib
import json
from pathlib import Path
import struct

from hsltools.native.image import EXE_SHA, image
from hsltools.paths import ROOT
from hsltools.probes._base import ProbeTask

PACKET = ROOT / 'docs/evidence_packets/static_reverse/original_ai_stat.json'

ANCHOR_SHA = 'f159ac035694812c8531aaccd636f7cbcd43d74cceed8691a20a5ee92cbe512b'
LIMIT = 20000
ANCHORS = [(0x440e3d, 180, 'Healing, status, then attack aid priority; bit10/mode6 uses ai_help_attack.'),
           (0x40c480, 230, 'Complete same-side square-radius positive-state scan with persistent cursor, excluding owner.'),
           (0x40c2d0, 31, 'Complete positive-state getter returns flags & 0x70.'),
           (0x40dcf0, 108, 'Complete magic buff list predicate tests mapped buff flags against present positive states.')]

def fixtures():
    rows = [dict(kind='priority', rates=rates, attempted=attempted, roll=roll, seed=7)
            for rates in [[0,0,0],[100,100,100],[0,0,100],[10,30,50]]
            for attempted in [0,4,8,12,16,20,24,28] for roll in [1,30,99]]
    for masks in [[],[0x20],[0x40],[0x20,0x40],[0x100],[0x60]]:
        for flags in [0,7,0x10,0x20,0x30,0x40,0x70,0x77]:
            rows.append(dict(kind='useful', masks=masks, flags=flags, seed=1))
    units = [dict(coord=[10,10],side=0x20000,flags=0),
             dict(coord=[11,10],side=0x10000,flags=0),
             dict(coord=[11,11],side=0x20000,flags=0x10), None,
             dict(coord=[18,18],side=0x20000,flags=7),
             dict(coord=[12,10],side=0x20000,flags=0x20),
             dict(coord=[13,10],side=0x20000,flags=0x30),
             dict(coord=[11,10],side=0x60000,flags=0),
             dict(coord=[19,10],side=0x20000,flags=0)]
    rows += [dict(kind='scan',masks=masks,units=units,radius=radius,seed=1)
             for masks in [[],[0x20],[0x40],[0x20,0x40]] for radius in [0,1,8,9]]
    return rows

def useful(masks, flags):
    mapped = [((0x10 if m & 0x40 else 0) | (0x20 if m & 0x20 else 0) | (0x40 if m & 0x100 else 0)) for m in masks]
    return int(any(m and not (m & flags) for m in mapped))

def expected(case, draws):
    if case['kind'] == 'priority':
        attempted, roll, mode, cursor = case['attempted'],case['roll'],0,0
        for bit,rate,next_mode in zip([4,8,16],case['rates'],[3,4,6]):
            if attempted & bit: continue
            attempted |= bit
            if roll <= rate: mode = next_mode; break
            d = draws[cursor]; cursor += 1
            if d['bound'] != 99 or not 0 <= d['value'] < 99: raise ValueError('Aid RNG mismatch')
            roll = d['value'] + 1
        if cursor != len(draws): raise ValueError('Extra aid RNG')
        return dict(attempted=attempted, next_roll=roll, mode=mode)
    if draws: raise ValueError('Pure buff scanner unexpectedly sampled RNG')
    if case['kind'] == 'useful': return useful(case['masks'],case['flags'])
    owner = case['units'][0]; found=[]; flags=[]
    for i,u in enumerate(case['units']):
        if i == 0 or u is None or (u['side'] & 0x870000) != (owner['side'] & 0x870000): continue
        if any(abs(a-b) > case['radius'] for a,b in zip(owner['coord'],u['coord'])): continue
        if useful(case['masks'],u['flags'] & 0x70): found.append(i+1); flags.append(u['flags'] & 0x70)
    return dict(indices=found+[0], masks=flags, cursor=200)

def execute(base,mapped,c):
    from unicorn import Uc,UC_ARCH_X86,UC_MODE_32,UC_HOOK_CODE
    from unicorn.x86_const import UC_X86_REG_EAX,UC_X86_REG_EBX,UC_X86_REG_EBP,UC_X86_REG_EDI,UC_X86_REG_ESI,UC_X86_REG_ESP,UC_X86_REG_EIP
    m=Uc(UC_ARCH_X86,UC_MODE_32);m.mem_map(base,len(mapped));m.mem_write(base,bytes(mapped));m.mem_map(0x10000000,0x80000)
    stop,obj,actors,buckets,nodes,table,records,out,stack=0x10000000,0x10001000,0x10010000,0x10020000,0x10021000,0x10022000,0x10023000,0x10030000,0x1007fe00
    def put(at,v): m.mem_write(at,struct.pack('<I',v & 0xffffffff))
    def get(at): return struct.unpack('<I',m.mem_read(at,4))[0]
    put(0x4c1bc8,actors);put(0x4c1b78,buckets);put(0x4c1e8c,1)
    put(0x4795d4,c['seed']);put(0x4795d8,0x87654321)
    priority=c['kind']=='priority'
    if priority:
        put(obj+0x98,c['attempted'])
        for off,rate in zip([0x1dc,0x1e0,0x1e4],c['rates']):put(actors+off,rate)
        for reg,value in [(UC_X86_REG_EBP,obj),(UC_X86_REG_EBX,actors),(UC_X86_REG_EDI,0),(UC_X86_REG_ESI,c['roll'])]:m.reg_write(reg,value)
        entry=0x440e3d
    else:
        masks=c['masks'];put(buckets+0x20,nodes if masks else 0);put(buckets+0x24,len(masks));put(0x4c2ca0,table)
        for i,mask in enumerate(masks):
            put(nodes+i*8,i);put(nodes+i*8+4,nodes+(i+1)*8 if i+1<len(masks) else 0)
            put(table+i*4,records+i*0x40);put(records+i*0x40+0x24,mask)
        entry=0x40dcf0 if c['kind']=='useful' else 0x40c480
        if c['kind']=='scan':
            m.mem_write(0x4c34c0,bytes(800))
            for i,u in enumerate(c['units']):
                if u is None:continue
                o=obj+i*0x200;a=actors+i*0x1fc;put(0x4c34c0+i*4,o);put(o+0xa4,i);put(o+0x64,3)
                put(o+4,u['coord'][0]*32);put(o+8,u['coord'][1]*32);put(a+0x28,u['side']);put(a+0x24,u['flags'])
    steps=0;draws=[];pending=[]
    before=bytes(m.mem_read(obj,0x1f000))
    def hook(_m,pc,_size,_data):
        nonlocal steps
        if priority and pc in [0x441035,0x440ef1]:m.emu_stop();return
        steps+=1
        if not any(a<=pc<b for a,b in [(0x440e3d,0x440ef1),(0x40c480,0x40c566),(0x40c2d0,0x40c2ef),(0x40dcf0,0x40dd5c),(0x40e180,0x40e1ec),(0x40ba20,0x40ba72),(0x409850,0x40986c),(0x458c10,0x458cb3)]):raise ValueError(f'Unreviewed AI stat callee {pc:#x}')
        if pending and pending[-1][0]==pc:
            _,bound=pending.pop();draws.append(dict(bound=bound,value=m.reg_read(UC_X86_REG_EAX)))
        if pc==0x458c80:
            sp=m.reg_read(UC_X86_REG_ESP);pending.append((get(sp),get(sp+4)))
    m.hook_add(UC_HOOK_CODE,hook);indices=[];flags=[]
    for call in range(len(c['units'])+1 if c['kind']=='scan' else 1):
        args=[] if priority else [c['flags']] if c['kind']=='useful' else [obj,c['radius'],int(call>0),out]
        put(out,0xabcdef);m.mem_write(stack,struct.pack('<'+'I'*(1+len(args)),stop,*args));m.reg_write(UC_X86_REG_ESP,stack)
        m.emu_start(entry,stop,count=LIMIT);end=m.reg_read(UC_X86_REG_EIP)
        if pending or (end not in [0x441035,0x440ef1] if priority else end!=stop or m.reg_read(UC_X86_REG_ESP)!=stack+4):raise ValueError('AI stat boundary not reached')
        if c['kind']!='scan':break
        value=m.reg_read(UC_X86_REG_EAX);indices.append(value)
        if get(0x4c1a30)!=(value-1 if value else 200):raise ValueError('AI buff cursor differs')
        if not value:
            if get(out)!=0xabcdef:raise ValueError('Exhausted buff scan overwrote mask')
            break
        flags.append(get(out))
    if priority:result=dict(attempted=get(obj+0x98),next_roll=m.reg_read(UC_X86_REG_ESI),mode=m.reg_read(UC_X86_REG_EDI))
    elif c['kind']=='useful':result=m.reg_read(UC_X86_REG_EAX)
    else:result=dict(indices=indices,masks=flags,cursor=get(0x4c1a30))
    after=bytearray(before)
    if priority:struct.pack_into('<I',after,0x98,result['attempted'])
    if bytes(m.mem_read(obj,0x1f000))!=bytes(after) or result!=expected(c,draws):raise ValueError(f'AI stat result differs: {c}, {result}')
    return dict(input=c,result=result,draws=draws,normal_return=not priority,stop_address=hex(end),instructions=steps,calls=call+1)

def check(packet):
    if packet.get('schema')!='hsl_ai_stat_native.v1' or packet.get('exe_sha256')!=EXE_SHA or packet.get('native_execution') is not True:raise ValueError('AI stat identity differs')
    if [r['input'] for r in packet['cases']]!=fixtures():raise ValueError('AI stat coverage differs')
    for r in packet['cases']:
        normal=r['input']['kind']!='priority'
        if r['result']!=expected(r['input'],r['draws']) or r['normal_return'] is not normal or not 0<r['instructions']<LIMIT*r['calls']:raise ValueError('AI stat evidence differs')
        if r['stop_address'] not in (['0x10000000'] if normal else ['0x441035','0x440ef1']):raise ValueError('AI stat exit differs')
    if [(int(r['address'],16),len(bytes.fromhex(r['bytes'])),r['meaning']) for r in packet['anchors']]!=ANCHORS:raise ValueError('AI stat anchors differ')
    if hashlib.sha256(bytes.fromhex(''.join(r['bytes'] for r in packet['anchors']))).hexdigest()!=ANCHOR_SHA:raise ValueError('AI stat original instruction bytes differ')


def execute_packet(exe: Path) -> dict:
    """Run the bounded original instructions on the documented EXE and assemble the packet."""
    base,mapped=image(exe.read_bytes())
    packet=dict(schema='hsl_ai_stat_native.v1',exe_sha256=EXE_SHA,native_execution=True,evidence_tier='static-derived',
                cases=[execute(base,mapped,c) for c in fixtures()],
                anchors=[dict(address=hex(at),bytes=bytes(mapped[at-base:at-base+n]).hex(),meaning=meaning) for at,n,meaning in ANCHORS],
                limits=['Full buff scans/usefulness helpers; priority ends before whole dispatcher. No callee stubs.',
                        'Synthetic legal roster/bucket inputs; no claim of whole original AI navigation or learning.'])
    return packet


def summary_line(packet: dict, executed_now: bool) -> str:
    return ' '.join(str(part) for part in ('AI_STAT_NATIVE_PASS cases=', len(packet['cases']), 'executed_now=', executed_now))


TASK = ProbeTask('ai_stat', PACKET, check, execute_packet, summary_line)


def tasks() -> list[ProbeTask]:
    return [TASK]
