"""Bounded native priest refresh and actual player-slot/template binding.

Slot helpers/template copy return normally; installed-object binding stops before
initialization callbacks. Source029 is the departing story actor, not player1's
live template. No opcode substitution, renderer or unreviewed callee is used.

Registry task priest (family probe, hsltools.probes._base.ProbeTask): check validates the
tracked packet against the independent model; generate executes the original instructions
(needs the documented hsl01.exe and unicorn). Bodies moved verbatim from the former hsl_native_priest_probe.py.
"""
from __future__ import annotations
import hashlib
import json
from pathlib import Path
import struct

from hsltools.data.equipment import original_build as equipment_data
from hsltools.model.jobs import source_profile, calculate, ATTRIBUTES, CAPS, SLOTS
from hsltools.native.image import EXE_SHA, image
from hsltools.native.machine import machine_for
from hsltools.native.sources import original_sources as sources
from hsltools.paths import ROOT
from hsltools.probes._base import ProbeTask
from hsltools.probes.job_stats import execute as refresh
from hsltools.sources.tables import TABLES, digest

PACKET = ROOT / 'docs/evidence_packets/static_reverse/original_priest.json'

ANCHOR_SHA = '9b0f2c3a28672a71a7a7f3feb6d4076dabf75d76d46d61ea057da2099c5f928d'
SOURCE_PATHS = {name:TABLES/name for name in ['PLAYERS.TXT','TYPE.H','ITEM.TXT','SHAPEDEF.H','OBJ-ALL.H']}
SOURCE_PATHS['STORY053.TXT'] = ROOT/'content/imported/hsl/chapter01/battle053/source_texts/STORY053.TXT'
ANCHORS = [(0x42c700,21,'Player object code is stored by zero-based party slot.'),
           (0x42caa0,24,'Player install getter returns the enabled object code of that slot.'),
           (0x42cac0,35,'Reverse lookup returns the matching zero-based party slot.'),
           (0x407eff,21,'Process3 binding sets actor record index to the found party slot plus one.'),
           (0x44cb10,56,'Player initialization copies the same one-based source template into live record.'),
           (0x44946f,48,'Priest85 dispatch loads cap row5 before its resistance and shared priest-family arithmetic.'),
           (0x4786e4,8,'Priest caps are four88 values, distinct from Wise87.'),
           (0x4498c9,426,'Priest-family HP/MP/attack/defense/magic/speed terms are shared after job-specific resistance.'),
           (0x44b820,24,'Stat dispatcher entry5 routes job85 to44946f.')]


def fixtures():
    players,_,defines=sources();row=players['002']
    attrs={k:int(row[k]) for k in ATTRIBUTES};gear=[int(row.get(s,0)) for s in SLOTS]
    base=dict(actor='002',name='initial',attributes=attrs,level=int(row['level']),equipment=gear,
              hp=9999,mp=9999,mode=defines[row['mode']],base_move=int(row['move_point']))
    cases=[base]
    for level in [2,9,10,19,20,21,22,23,44,99]:
        cases.append(dict(base,name='level_'+str(level),level=level,hp=1,mp=0))
    for key in ATTRIBUTES:
        cases.append(dict(base,name=key+'_plus1',level=2,attributes=dict(attrs,**{key:attrs[key]+1}),hp=17,mp=3))
    cases.extend([dict(base,name='caps',level=99,attributes=dict(zip(ATTRIBUTES,CAPS[85]))),
                  dict(base,name='enemy_mode',mode=0x20000,level=12),
                  dict(base,name='empty_equipment',equipment=[0]*6,hp=7,mp=3)])
    for label,new_gear in [('long_staff',[87,152,122,181,201,0]),('recovery',[94,159,145,187,223,224]),
                           ('half_repeat',[82,152,122,181,218,227]),('range_mobility',[87,152,122,187,233,236])]:
        cases.append(dict(base,name=label,level=20,equipment=new_gear,hp=13,mp=2))
    return cases


def binding_cases():
    return [dict(slot=slot,object_code=code,previous_template=29) for slot,code in [(0,800),(1,801),(2,802),(19,819),(1,901)]]


def execute_binding(base,mapped,case):
    from unicorn import UC_HOOK_CODE
    from unicorn.x86_const import UC_X86_REG_ESP,UC_X86_REG_EIP,UC_X86_REG_EAX,UC_X86_REG_ESI,UC_X86_REG_EDI
    m=machine_for(base,mapped);obj,templates,live,stack,sentinel=0x10001000,0x10002000,0x1000d000,0x1001ff00,0x10000000
    def put(at,v):m.mem_write(at,struct.pack('<I',v&0xffffffff))
    def get(at):return struct.unpack('<I',m.mem_read(at,4))[0]
    slot=case['slot'];code=case['object_code'];index=slot+1
    put(0x4c1afc,templates);put(0x4c1bc8,live);put(obj+0xa4,case['previous_template'])
    original=bytes((i*13+index)%256 for i in range(0x1fc))
    m.mem_write(templates+index*0x1fc,original);m.mem_write(live+index*0x1fc,b'\xbb'*0x1fc)
    steps=0;stop_prefix=0x407f14
    def guard(_m,at,_size,_data):
        nonlocal steps
        if at==stop_prefix:m.emu_stop();return
        steps+=1
        if not any(lo<=at<hi for lo,hi in [(0x42c700,0x42c715),(0x42caa0,0x42cae3),(0x407eff,stop_prefix),(0x44cb10,0x44cb52)]):
            raise ValueError(f'Unreviewed priest binding instruction {at:#x}')
    m.hook_add(UC_HOOK_CODE,guard)
    def call(entry,args):
        m.mem_write(stack,struct.pack('<'+'I'*(len(args)+1),sentinel,*args));m.reg_write(UC_X86_REG_ESP,stack)
        m.emu_start(entry,sentinel,count=4096)
        if m.reg_read(UC_X86_REG_EIP)!=sentinel or m.reg_read(UC_X86_REG_ESP)!=stack+4:raise ValueError('Binding helper did not return')
        return m.reg_read(UC_X86_REG_EAX)
    call(0x42c700,[slot,code]);returned=call(0x42caa0,[slot]);reverse=call(0x42cac0,[code])
    m.reg_write(UC_X86_REG_ESI,obj);m.reg_write(UC_X86_REG_EDI,code);m.reg_write(UC_X86_REG_ESP,stack)
    m.emu_start(0x407eff,sentinel,count=512)
    if m.reg_read(UC_X86_REG_EIP)!=stop_prefix:raise ValueError('Player mapping prefix overran stop')
    mapped_index=get(obj+0xa4)
    copied=call(0x44cb10,[mapped_index,1])
    if (returned,reverse,mapped_index,copied)!=(code,slot,index,index) or bytes(m.mem_read(live+index*0x1fc,0x1fc))!=original:
        raise ValueError('Player mapping/copy differs')
    return dict(input=case,object_code=returned,template_index=mapped_index,copy_return=copied,
                template_sha256=digest(original),live_sha256=digest(bytes(m.mem_read(live+index*0x1fc,0x1fc))),
                normal_returns=4,prefix_entry='0x407eff',prefix_stop='0x407f14',instructions=steps)


def check(packet):
    if packet.get('schema')!='hsl_priest_native.v1' or packet.get('exe_sha256')!=EXE_SHA or packet.get('native_execution') is not True:raise ValueError('Priest identity missing')
    if packet['sources']!={k:digest(p.read_bytes()) for k,p in SOURCE_PATHS.items()}:raise ValueError('Priest source changed')
    if [r['input'] for r in packet['stats']]!=fixtures() or [r['input'] for r in packet['bindings']]!=binding_cases():raise ValueError('Priest coverage differs')
    players,_,defines=sources();catalog=equipment_data()['items']
    for row in packet['stats']:
        c=row['input'];profile=source_profile(players['002'],defines);profile['source']['mode']=c['mode']
        wanted=calculate(profile,c['attributes'],c['level'],c['equipment'],catalog,c['hp'],c['mp'],c['base_move'])
        if row['profile']!=profile or len(row['native'])!=2:raise ValueError('Priest profile differs')
        for r in row['native']:
            if r['values']!=wanted or r['normal_return'] is not True or not 0<r['instructions']<12000:raise ValueError('Priest refresh differs')
    for row in packet['bindings']:
        c=row['input'];idx=c['slot']+1
        if row['template_index']!=idx or row['copy_return']!=idx or row['object_code']!=c['object_code'] or row['normal_returns']!=4 or row['prefix_stop']!='0x407f14' or row['prefix_entry']!='0x407eff' or not 0<row['instructions']<4096:raise ValueError('Priest binding boundary differs')
        if row['template_sha256']!=digest(bytes((i*13+idx)%256 for i in range(0x1fc))) or row['live_sha256']!=row['template_sha256']:raise ValueError('Priest template copy differs')
    if [(int(r['address'],16),len(bytes.fromhex(r['bytes'])),r['meaning']) for r in packet['anchors']]!=ANCHORS:raise ValueError('Priest anchors differ')
    if hashlib.sha256(bytes.fromhex(''.join(r['bytes'] for r in packet['anchors']))).hexdigest()!=ANCHOR_SHA:raise ValueError('Priest original bytes differ')


def execute_packet(exe: Path) -> dict:
    """Run the bounded original instructions on the documented EXE and assemble the packet."""
    base,mapped=image(exe.read_bytes())
    packet=dict(schema='hsl_priest_native.v1',exe_sha256=EXE_SHA,evidence_tier='static-derived',native_execution=True,
                sources={k:digest(p.read_bytes()) for k,p in SOURCE_PATHS.items()},
                stats=[refresh(base,mapped,c) for c in fixtures()],bindings=[execute_binding(base,mapped,c) for c in binding_cases()],
                anchors=[dict(address=hex(at),bytes=bytes(mapped[at-base:at-base+n]).hex(),meaning=text) for at,n,text in ANCHORS],
                limits=['Full stat refresh on source002 inputs, not whole gameplay/native template parser.',
                        'Four binding/copy helper returns plus an installed-object prefix before subsequent initialization callbacks.',
                        'STORY053 deletes SID_ENEMY029 before inserting obj_Story_Player2; player slot1 maps to template002, not029.',
                        'Manual five-point allocation follows current remake policy; initial player globals, class changes and whole dispatcher remain separate.'])
    return packet


def summary_line(packet: dict, executed_now: bool) -> str:
    return 'PRIEST_NATIVE_PASS full_refreshes='+str(2*len(packet['stats']))+' binding_returns='+str(4*len(packet['bindings']))+' executed_now='+str(executed_now)+' anchors_sha='+hashlib.sha256(bytes.fromhex(''.join(r['bytes'] for r in packet['anchors']))).hexdigest()


TASK = ProbeTask('priest', PACKET, check, execute_packet, summary_line)


def tasks() -> list[ProbeTask]:
    return [TASK]
