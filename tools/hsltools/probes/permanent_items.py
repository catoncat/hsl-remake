"""Original permanent item prefixes, followed by full level/equipment refreshes.

Registry task permanent_items (family probe, hsltools.probes._base.ProbeTask): check validates the
tracked packet against the independent model; generate executes the original instructions
(needs the documented hsl01.exe and unicorn). Bodies moved verbatim from the former hsl_native_permanent_items_probe.py.
"""
from __future__ import annotations
import copy
from functools import lru_cache
import hashlib
import json
from pathlib import Path
import struct

from hsltools.data.equipment import original_build as build
from hsltools.model.jobs import SLOTS, ATTRIBUTES, source_profile, calculate
from hsltools.native.image import EXE_SHA, image
from hsltools.native.sources import original_sources as sources
from hsltools.paths import ROOT
from hsltools.probes._base import ProbeTask
from hsltools.probes.stat_magic import machine, put_actor, WORDS, flags
from hsltools.sources.tables import TABLES, digest

PACKET = ROOT / 'docs/evidence_packets/static_reverse/original_permanent_items.json'

sources=lru_cache(maxsize=1)(sources)
build=lru_cache(maxsize=1)(build)
ANCHOR_SHA='8dd9978cf546f5764dfca5f47621b391dfccecc21e7517d4a4dba7bc36a62ed1'
FIELDS={
    'attack_power':(253,'global_add_weapon_power',0x50,0x1a4),
    'magic_attack_power':(255,'global_add_magic_power',0x54,0x1a8),
    'defense':(254,'global_add_defense',0x58,0x1ac),
    'speed':(256,'global_add_speed',0x5c,0x1b0),
    'resist_0':(257,'global_add_resist_earth',0x60,0x118),
    'resist_1':(259,'global_add_resist_water',0x64,0x11c),
    'resist_2':(260,'global_add_resist_air',0x68,0x120),
    'resist_3':(258,'global_add_resist_fire',0x6c,0x124),
    'resist_4':(261,'global_add_resist_mind',0x70,0x128),
}
DERIVED={'attack':0xc0,'defense':0xb4,'magic_attack':0xd0,'speed':0xb8,
         'max_hp':0xdc,'max_mp':0xe4,'move_point':0x12c,
         **{'resist_'+str(i):0x104+4*i for i in range(5)}}
ANCHORS=[(0x447b60,263,'ITEM loader maps nine permanent interval fields separately from temporary boosts.'),
         (0x409f32,126,'Magic/defense/speed add sampled values to distinct persistent source fields.'),
         (0x409fb0,365,'Each intrinsic resistance is clamped0..80 before the later job/equipment refresh.'),
         (0x44b69e,44,'Stat refresh clips current HP/MP to maxima rather than refilling them.')]

def fixtures():
    rows=[]
    for actor in ['001','002','026','024']:
        original=source_profile(sources()[0][actor],sources()[2])['source']
        for code in range(253,262):
            for prior in [False,True]:
                field=next(key for key,row in FIELDS.items() if row[0]==code)
                rows.append(dict(actor=actor,code=code,level=20 if prior else 1,
                                 old_raw=(75 if code>=257 else original[field]+7) if prior else None,
                                 enhanced=prior,equipped=True,seed=19 if prior else 7))
    for code in range(257,262):
        for raw in [79,80]:
            rows.append(dict(actor='002',code=code,level=80,old_raw=raw,enhanced=True,equipped=True,seed=1))
    return rows

def initial_raw(c):
    row=sources()[0][c['actor']];src=source_profile(row,sources()[2])['source']
    values={key:src['base_resist_by_type'][key[-1]] if key.startswith('resist_') else src[key] for key in FIELDS}
    if c['old_raw'] is not None:
        key=next(key for key,row in FIELDS.items() if row[0]==c['code'])
        values[key]=c['old_raw']
    return values

def after_item(raw,c,draws):
    key=next(key for key,row in FIELDS.items() if row[0]==c['code'])
    row=sources()[1][c['code']];lo,hi=sorted(map(int,row[FIELDS[key][1]].split(',')))
    if len(draws)!=1 or draws[0]['bound']!=hi-lo+1 or not 0<=draws[0]['value']<=hi-lo:raise ValueError('Permanent item random draw differs')
    result=dict(raw);result[key]=max(0,raw[key]+lo+draws[0]['value'])
    if key.startswith('resist_'):result[key]=min(80,result[key])
    return result

def derived(c,raw,level,gear):
    row=sources()[0][c['actor']];profile=source_profile(row,sources()[2]);src=profile['source']
    for key,value in raw.items():
        if key.startswith('resist_'):src['base_resist_by_type'][key[-1]]=value
        else:src[key]=value
    result=calculate(profile,{k:int(row[k]) for k in ATTRIBUTES},level,gear,build()['items'],1,0,int(row['move_point']))
    result['attack']+=6 if c['enhanced'] else 0;result['defense']+=30 if c['enhanced'] else 0
    return {key:result['resist_by_type'][key[-1]] if key.startswith('resist_') else result[key] for key in DERIVED}

def execute(base,mapped,c):
    from unicorn import UC_HOOK_CODE
    from unicorn.x86_const import UC_X86_REG_EAX,UC_X86_REG_EIP,UC_X86_REG_ESP
    m=machine(base,mapped);obj,actor,stack,stop=0x10001000,0x10004000,0x1001ff00,0x10000000
    def put(at,v):m.mem_write(at,struct.pack('<I',v&0xffffffff))
    def get(at):return struct.unpack('<I',m.mem_read(at,4))[0]
    row=sources()[0][c['actor']];gear=[int(row.get(k,0)) for k in SLOTS] if c['equipped'] else [0]*6
    words=dict(poison=0x70003,no_magic=3,paralysis=2,attack_up=0x60004 if c['enhanced'] else 0,defense_up=0x1e0004 if c['enhanced'] else 0)
    put_actor(m,actor,c['actor'],c['level'],1,0,gear,words)
    put(0x4c1bc8,actor);put(obj+0xa4,0);put(obj+4,240);put(obj+8,240)
    initial=initial_raw(c)
    for key,value in initial.items():put(actor+FIELDS[key][3],value)
    key=next(key for key,row in FIELDS.items() if row[0]==c['code'])
    lo,hi=map(int,sources()[1][c['code']][FIELDS[key][1]].split(','))
    record=0x20000000+176*c['code'];put(record+8,1);put(record+FIELDS[key][2],(hi&65535)<<16|(lo&65535))
    phase='refresh';steps=0;pending=[];draws=[];refresh_calls=0
    def guard(_m,pc,_n,_d):
        nonlocal steps,refresh_calls
        steps+=1
        permitted=[(0x448370,0x44b820)] if phase=='refresh' else [(0x409e40,0x40a343),(0x409e10,0x409e35),(0x446ad0,0x446af9),(0x448370,0x44b820),(0x42c780,0x42c7d9),(0x458bb0,0x458cb3)]
        if not any(lo<=pc<hi for lo,hi in permitted):raise ValueError(f'Unreviewed permanent-item callee {pc:#x}')
        if pc==0x448840:refresh_calls+=1
        if pending and pending[-1][0]==pc:
            _,bound=pending.pop();draws.append(dict(bound=bound,value=m.reg_read(UC_X86_REG_EAX)))
        if pc==0x42c780:
            sp=m.reg_read(UC_X86_REG_ESP);pending.append((get(sp),get(sp+4)))
    m.hook_add(UC_HOOK_CODE,guard)
    def snapshot():return {k:get(actor+off) for k,off in DERIVED.items()}
    def raw_snapshot():return {k:get(actor+row[3]) for k,row in FIELDS.items()}
    def preserved():return [bytes(m.mem_read(actor+at,n)) for at,n in [(0x24,4),(0x30,28),(0x64,16),(0x88,4),(0xec,24),(0x138,32),(0x1b4,4),(0xd8,4),(0xe0,4),(0xe8,4)]]
    def refresh():
        prior=steps;m.mem_write(stack,struct.pack('<2I',stop,actor));m.reg_write(UC_X86_REG_ESP,stack);m.emu_start(0x448840,stop,count=14000)
        if m.reg_read(UC_X86_REG_EIP)!=stop or m.reg_read(UC_X86_REG_ESP)!=stack+4:raise ValueError('Permanent-item source refresh missed full return')
        return steps-prior
    initial_steps=refresh();before=snapshot();stable=preserved()
    if before!=derived(c,initial,c['level'],gear):raise ValueError('Initial source values differ')
    put(0x4c1e8c,1);put(0x4c3044,c['seed']);put(0x4c3040,0x87654321)
    application=[];raw=initial
    for iteration in range(2):
        phase='item';prior=steps;previous_calls=refresh_calls;draws=[]
        m.mem_write(stack,struct.pack('<5I',stop,obj,c['code'],0,0));m.reg_write(UC_X86_REG_ESP,stack);m.emu_start(0x409e40,0x40a343,count=30000)
        if m.reg_read(UC_X86_REG_EIP)!=0x40a343 or pending:raise ValueError('Permanent item prefix did not stop before audio')
        actual=raw_snapshot();wanted=after_item(raw,c,draws)
        if actual!=wanted or snapshot()!=derived(c,wanted,c['level'],gear) or stable!=preserved():raise ValueError(f'Permanent item mutation/derived mismatch {c}: {actual} expected{wanted}')
        application.append(dict(before=raw,after=actual,values=snapshot(),draws=copy.deepcopy(draws),instructions=steps-prior,refresh_calls=refresh_calls-previous_calls,normal_return=False,stop_address='0x40a343'))
        raw=wanted
    phase='refresh';returns=[]
    for name,level,slots in [('repeat_refresh',c['level'],gear),('level_refresh',c['level']+1,gear),('remove_equipment',c['level']+1,[0]*6)]:
        put(actor+0x9c,level)
        for i,code in enumerate(slots):put(actor+0xec+4*i,code)
        for off in DERIVED.values():put(actor+off,9999)
        count=refresh();actual=snapshot();wanted=derived(c,raw,level,slots)
        if actual!=wanted or raw_snapshot()!=raw:raise ValueError(f'Permanent value lost/doubled after {name}: {c} {actual} expected{wanted}')
        returns.append(dict(kind=name,level=level,equipment=slots,values=actual,raw=raw_snapshot(),normal_return=True,instructions=count))
    return dict(input=c,initial=initial,initial_values=before,initial_refresh_return=True,initial_instructions=initial_steps,applications=application,refreshes=returns,unrelated_state_preserved=True)

def check(packet):
    if packet.get('schema')!='hsl_permanent_items_native.v1' or packet.get('exe_sha256')!=EXE_SHA or packet.get('native_execution') is not True:raise ValueError('Permanent evidence identity differs')
    if packet['sources']!={n:digest((TABLES/n).read_bytes()) for n in ['ITEM.TXT','PLAYERS.TXT','TYPE.H']}:raise ValueError('Permanent item sources changed')
    if [r['input'] for r in packet['cases']]!=fixtures():raise ValueError('Permanent item coverage differs')
    for row in packet['cases']:
        c=row['input'];raw=initial_raw(c);src=sources()[0][c['actor']];gear=[int(src.get(k,0)) for k in SLOTS] if c['equipped'] else [0]*6
        if row['initial']!=raw or row['initial_values']!=derived(c,raw,c['level'],gear) or not row['initial_refresh_return'] or not row['unrelated_state_preserved']:raise ValueError('Permanent item initial source differs')
        if len(row['applications'])!=2 or len(row['refreshes'])!=3:raise ValueError('Missing repeated permanent-item application/refresh')
        for part in row['applications']:
            wanted=after_item(raw,c,part['draws'])
            if part['before']!=raw or part['after']!=wanted or part['values']!=derived(c,wanted,c['level'],gear) or part['normal_return'] is not False or part['stop_address']!='0x40a343' or not 0<part['instructions']<30000:raise ValueError('Permanent item prefix outcome/boundary differs')
            raw=wanted
        expected_refreshes=[('repeat_refresh',c['level'],gear),('level_refresh',c['level']+1,gear),('remove_equipment',c['level']+1,[0]*6)]
        if [(part['kind'],part['level'],part['equipment']) for part in row['refreshes']]!=expected_refreshes:raise ValueError('Permanent refresh stages differ')
        for part in row['refreshes']:
            if part['raw']!=raw or part['values']!=derived(c,raw,part['level'],part['equipment']) or part['normal_return'] is not True or not 0<part['instructions']<14000:raise ValueError('Permanent refresh failed identity')
    if [(int(a['address'],16),len(bytes.fromhex(a['bytes'])),a['meaning']) for a in packet['anchors']]!=ANCHORS:raise ValueError('Permanent source anchor differs')
    if hashlib.sha256(bytes.fromhex(''.join(x['bytes'] for x in packet['anchors']))).hexdigest()!=ANCHOR_SHA:raise ValueError('Permanent instruction bytes differ')


def execute_packet(exe: Path) -> dict:
    """Run the bounded original instructions on the documented EXE and assemble the packet."""
    base,mapped=image(exe.read_bytes());anchors=[dict(address=hex(at),bytes=bytes(mapped[at-base:at-base+n]).hex(),meaning=label) for at,n,label in ANCHORS]
    result=dict(schema='hsl_permanent_items_native.v1',exe_sha256=EXE_SHA,native_execution=True,evidence_tier='static-derived',
                sources={n:digest((TABLES/n).read_bytes()) for n in ['ITEM.TXT','PLAYERS.TXT','TYPE.H']},
                cases=[execute(base,mapped,c) for c in fixtures()],anchors=anchors,
                limits=['Item handler stops before audio and caller inventory/turn completion; initial and subsequent stat refreshes return normally.',
                        'Positive source items253..261 on four source jobs, explicit levels/raw offsets/current equipment/status; not natural grants or full loader.',
                        'Resistance cap applies to persistent intrinsic value separately from displayed resistance; original global RNG is not reproduced.'])
    return result


def summary_line(result: dict, executed_now: bool) -> str:
    return 'PERMANENT_ITEMS_NATIVE_PASS cases='+str(len(result['cases']))+' applications='+str(2*len(result['cases']))+' refresh_returns='+str(4*len(result['cases']))+' executed_now='+str(executed_now)+' anchors_sha='+hashlib.sha256(bytes.fromhex(''.join(x['bytes'] for x in result['anchors']))).hexdigest()


TASK = ProbeTask('permanent_items', PACKET, check, execute_packet, summary_line)


def tasks() -> list[ProbeTask]:
    return [TASK]
