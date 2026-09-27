"""Bounded original paralysis: action-entry dispatch, duration, cure and AI scan.

Entry/application/cure are declared prefixes. Duration, inventory scanning and
equipment refresh return normally. No original callee or renderer is stubbed.

Registry task paralysis (family probe, hsltools.probes._base.ProbeTask): check validates the
tracked packet against the independent model; generate executes the original instructions
(needs the documented hsl01.exe and unicorn). Bodies moved verbatim from the former hsl_native_paralysis_probe.py.
"""
from __future__ import annotations
import hashlib
import json
from pathlib import Path
import struct

from hsltools.native.image import image, EXE_SHA
from hsltools.native.machine import machine_for
from hsltools.paths import ROOT
from hsltools.probes._base import ProbeTask
from hsltools.probes.status_roll import independent
from hsltools.sources.tables import TABLES, blocks, digest

PACKET = ROOT / 'docs/evidence_packets/static_reverse/original_paralysis.json'

SOURCE_NAMES = ['MAGIC.TXT','ITEM.TXT','PLAYERS.TXT','TYPE.H','RANGE.TXT']
ANCHORS = [(0x443996,30,'Active player with paralysis and fresh phase0 branches directly to final tail.'),
           (0x443ac2,15,'Skipped player writes phase10003 and bypasses the extra-action query.'),
           (0x43f47b,30,'Active AI uses the same fresh-phase paralysis gate.'),
           (0x441f37,10,'Skipped AI writes phase640001 before the shared tail.'),
           (0x40ac97,104,'Successful paralysis adds capped turns and ten contribution per actual added turn.'),
           (0x40b94b,26,'Paralysis duration expires its whole word and flag4.'),
           (0x40a30c,19,'Item cure mask20000000 clears only paralysis flag and counter.'),
           (0x40c230,154,'Eight-slot native status-cure lookup returns first matching one-based slot.'),
           (0x448142,34,'ITEM avoid_paralysis maps to main effect4000000.'),
           (0x447fac,35,'ITEM cure_paralysis maps to cure effect20000000.'),
           (0x44c37c,48,'PLAYERS no_paralyze maps to innate capability800.'),
           (0x44876f,15,'Nonempty gear maps innate capability800 to effect4000000.')]
ANCHOR_SHA = 'd3d97a5a4d50a9cf9e6e27ac7d75e66c7ceea2e3b5d2a0260f64bae82ecb9796'

def machine(base,mapped):
    from unicorn.x86_const import UC_X86_REG_ESP
    m=machine_for(base,mapped)
    def put(at,v):m.mem_write(at,struct.pack('<I',v&0xffffffff))
    def get(at):return struct.unpack('<I',m.mem_read(at,4))[0]
    obj,actor,stack,stop=0x10001000,0x10004000,0x1001ff00,0x10000000
    put(0x4c1bc8,actor);put(obj+0xa4,0)
    m.reg_write(UC_X86_REG_ESP,stack)
    return m,put,get,obj,actor,stack,stop

def entry(base,mapped,c):
    from unicorn import UC_HOOK_CODE
    from unicorn.x86_const import UC_X86_REG_ESI,UC_X86_REG_EDI,UC_X86_REG_EBP,UC_X86_REG_EDX,UC_X86_REG_EIP,UC_X86_REG_ESP
    m,put,get,obj,actor,stack,stop=machine(base,mapped)
    put(actor+0x24,c['flags']);put(obj+0x8c,c['phase']);put(0x4c1ba0,c['active'])
    put(actor+0x3c,3);put(actor+0x18c,8);put(0x4c1cf0,c['latch']);put(actor+0xd8,25)
    put(actor+0xe0,12);put(actor+0xe8,20);put(actor+0xa8,0x10002)
    put(0x4c6e48,2);put(0x4c1bbc,9)
    before=bytes(m.mem_read(actor,0x1fc))
    player=c['role']=='player'
    m.reg_write(UC_X86_REG_ESI,obj if player else actor)
    m.reg_write(UC_X86_REG_EDI,actor);m.reg_write(UC_X86_REG_EBP,obj);m.reg_write(UC_X86_REG_EDX,0)
    start=0x443996 if player else 0x43f47b
    stops=[0x4439b4,0x4447a7] if player else [0x43f4c7,0x441f41]
    allowed=[(start,0x4439b4 if player else 0x43f499),(0x443ac2,0x443ad1),(0x441f37,0x441f41)]
    steps=0
    def guard(_m,at,_n,_d):
        nonlocal steps
        if at in stops:m.emu_stop();return
        steps+=1
        if not any(a<=at<b for a,b in allowed):raise ValueError(f'Unexpected entry instruction {at:#x}')
    m.hook_add(UC_HOOK_CODE,guard);m.emu_start(start,stop,count=128)
    skipped=bool(c['active']) and bool(c['flags']&4) and c['phase']==0
    desired=(0x10003 if player else 0x640001) if skipped else c['phase']
    end=m.reg_read(UC_X86_REG_EIP)
    assert end==stops[int(skipped)] and get(obj+0x8c)==desired
    assert before==bytes(m.mem_read(actor,0x1fc)) and get(0x4c1cf0)==c['latch'] and get(0x4c6e48)==2 and get(0x4c1bbc)==9 and m.reg_read(UC_X86_REG_ESP)==stack
    return dict(input=c,native=dict(skipped=skipped,phase=desired,latch=c['latch']),normal_return=False,stop_address=hex(end),instructions=steps,actor_queue_unchanged=True)

def application(base,mapped,c):
    from unicorn import UC_HOOK_CODE
    from unicorn.x86_const import UC_X86_REG_EAX,UC_X86_REG_ESP,UC_X86_REG_EIP
    m,put,get,obj,caster,stack,sentinel=machine(base,mapped)
    target_obj,target,record,table=0x10002000,caster+0x1fc,0x10008000,0x10009000
    put(target_obj+0xa4,1)
    for off,v in [(0x24,3|(4 if c['turns'] else 0)),(0x30,0x70003),(0x34,2),(0x3c,c['turns']),(0xd8,c['hp']),(0xdc,100),(0x18c,c['effects']),(0xa0,2 if c['no_attack'] else 0),(0x104,c['resistance'])]:put(target+off,v)
    for off,key in [(0x9c,'level'),(0x54,'mind'),(0xd0,'magic_attack'),(0xd4,'magic_hit_bonus'),(0xb0,'hit_bonus')]:put(caster+off,c[key])
    for off,v in [(4,0),(0x14,12),(0x18,36),(0x1c,40),(0x20,40),(0x24,4)]:put(record+off,v)
    put(0x4c2ca0,table);put(table,record)
    put(0x4c1e8c,1);put(0x4c3044,c['seed']);put(0x4c3040,0x87654321)
    draws=[];returning=[];steps=0
    allowed=[(0x40aa80,0x40b831),(0x409850,0x40986c),(0x40e240,0x40e26e),(0x40e2f0,0x40e305),(0x40a7b0,0x40aa6b),(0x406fe0,0x407010),(0x42c780,0x42c7d9),(0x458bb0,0x458cb3)]
    def guard(_m,at,_n,_d):
        nonlocal steps
        steps+=1
        if not any(a<=at<b for a,b in allowed):raise ValueError(f'Unexpected paralysis application {at:#x}')
        if returning and returning[-1][0]==at:
            _,bound=returning.pop();draws.append(dict(bound=bound,value=m.reg_read(UC_X86_REG_EAX)))
        if at==0x42c780:
            sp=m.reg_read(UC_X86_REG_ESP);returning.append((get(sp),get(sp+4)))
    m.hook_add(UC_HOOK_CODE,guard)
    m.mem_write(stack,struct.pack('<6I',sentinel,obj,target_obj,0,0,0))
    m.emu_start(0x40aa80,0x40b831,count=4096)
    assert m.reg_read(UC_X86_REG_EIP)==0x40b831 and not returning
    turn=c['turns'];added=0
    if c['hp']>0 and not c['effects']&(0x80|0x4000000):
        hit = c['no_attack'] or draws[0]['value']+1<=40
        roll=independent(dict(c,proc=6,low=12,high=36,hit_ratio=40,status_hit_ratio=40),draws[:3 if hit else 1])
        if roll['value']:
            assert len(draws)==4 and draws[-1]['bound']==2
            added=min(9-turn,2+draws[-1]['value']);turn+=added
        else:assert len(draws)==(3 if hit else 1)
    else:assert not draws
    actual=dict(turns=get(target+0x3c),flags=get(target+0x24),contribution=get(0x4c13fc),hp=get(target+0xd8))
    assert actual==dict(turns=turn,flags=3|(4 if turn else 0),contribution=added*10,hp=c['hp']),(c,draws,actual,added)
    assert get(target+0x30)==0x70003 and get(target+0x34)==2
    return dict(input=c,native=actual,draws=draws,normal_return=False,stop_address='0x40b831',instructions=steps)

def duration(base,mapped,c):
    from unicorn import UC_HOOK_CODE
    from unicorn.x86_const import UC_X86_REG_EIP,UC_X86_REG_ESP
    m,put,get,obj,actor,stack,stop=machine(base,mapped)
    flags=0
    for off,key,bit in [(0x30,'poison',1),(0x3c,'paralysis',4),(0x34,'no_magic',2)]:
        put(actor+off,c[key]);flags|=bit if c[key] else 0
    put(actor+0x24,flags);steps=0
    def guard(_m,at,_n,_d):
        nonlocal steps
        steps+=1
        if not 0x40b910<=at<0x40ba12:raise ValueError('Tick left bounded normal-return helper')
    m.hook_add(UC_HOOK_CODE,guard);m.mem_write(stack,struct.pack('<2I',stop,obj));m.emu_start(0x40b910,stop,count=256)
    expected={key:((value&0xffff0000)|((value&0xffff)-1)) if (value&0xffff)>1 else 0 for key,value in c.items()}
    actual={key:get(actor+off) for off,key in [(0x30,'poison'),(0x3c,'paralysis'),(0x34,'no_magic')]}
    assert actual==expected and m.reg_read(UC_X86_REG_EIP)==stop and m.reg_read(UC_X86_REG_ESP)==stack+4
    assert get(actor+0x24)==sum(bit for key,bit in [('poison',1),('no_magic',2),('paralysis',4)] if expected[key])
    return dict(input=c,native=actual,normal_return=True,instructions=steps)

def cure(base,mapped,c):
    from unicorn import UC_HOOK_CODE
    from unicorn.x86_const import UC_X86_REG_EAX,UC_X86_REG_ECX,UC_X86_REG_ESI,UC_X86_REG_EIP
    m,put,get,obj,actor,stack,stop=machine(base,mapped)
    put(actor+0x24,3|(4 if c['turns'] else 0));put(actor+0x3c,c['turns']);put(actor+0x30,0x70003);put(actor+0x34,2)
    put(actor+0xd8,15);put(actor+0xe0,7);put(actor+0x88,99)
    before=bytearray(m.mem_read(actor,0x1fc));steps=0
    m.reg_write(UC_X86_REG_ESI,actor);m.reg_write(UC_X86_REG_EAX,c['effects']);m.reg_write(UC_X86_REG_ECX,0)
    def guard(_m,at,_n,_d):
        nonlocal steps
        steps+=1
        if not 0x40a30c<=at<0x40a31f:raise ValueError('Cure left declared suffix')
    m.hook_add(UC_HOOK_CODE,guard);m.emu_start(0x40a30c,0x40a31f,count=128)
    value=0 if c['effects']&0x20000000 else c['turns']
    struct.pack_into('<I',before,0x3c,value);struct.pack_into('<I',before,0x24,3|(4 if value else 0))
    assert bytes(m.mem_read(actor,0x1fc))==before and m.reg_read(UC_X86_REG_EIP)==0x40a31f
    return dict(input=c,native=dict(turns=value,flags=get(actor+0x24)),normal_return=False,stop_address='0x40a31f',instructions=steps)

def gear(base,mapped,c):
    from unicorn import Uc,UC_ARCH_X86,UC_MODE_32,UC_HOOK_CODE
    from unicorn.x86_const import UC_X86_REG_EIP,UC_X86_REG_ESP
    from hsltools.probes.job_stats import sources
    _,items,defines=sources()
    m=Uc(UC_ARCH_X86,UC_MODE_32);m.mem_map(base,len(mapped));m.mem_write(base,bytes(mapped))
    for at,size in [(0x10000000,0x10000),(0x20000000,0x10000),(0x21000000,0x20000)]:m.mem_map(at,size)
    actor,stack,stop=0x20000000,0x1000ff00,0x10000000
    def put(at,value):m.mem_write(at,struct.pack('<I',value&0xffffffff))
    def get(at):return struct.unpack('<I',m.mem_read(at,4))[0]
    for off,v in [(0x18,c['job']),(0x28,0x10000),(0x9c,3),(0xd8,1),(0xe0,0),(0xe8,20),(0x88,99),(0x130,4),(0x174,1),(0xa0,c['capability']),
                  (0x24,7),(0x3c,3),(0x30,0x70002),(0x34,2)]:put(actor+off,v)
    for off in [0x64,0x68,0x6c,0x70]:put(actor+off,20)
    put(0x4c1b40,0x21000000);accessory=4
    for code in c['codes']:
        row=items[code];at=0x21000000+176*code;kind=defines[row['type']]
        slot=0 if kind==2 else accessory
        if kind!=2:accessory+=1
        put(actor+0xec+slot*4,code)
        for off,v in [(8,kind),(0x10,-1),(0x8c,-1),(0x88,int(row.get('attack_damage',0))),(0x3c,int(row.get('add_defense',0))),(0x98,int(row.get('hit_ratio',0))),
                      (0xa0,0x4000000 if int(row.get('avoid_paralysis',0)) else 0)]:put(at+off,v)
    steps=0;results=[]
    def guard(_m,at,_n,_d):
        nonlocal steps
        steps+=1
        if not 0x448370<=at<0x44b820:raise ValueError(f'Unreviewed paralysis gear callee {at:#x}')
    m.hook_add(UC_HOOK_CODE,guard)
    expected_flag=0x4000000 if c['codes'] and (c['capability']&0x800 or any(int(items[code].get('avoid_paralysis',0)) for code in c['codes'])) else 0
    for _repeat in range(2):
        put(actor+0x18c,0x7fffffff);oldsteps=steps
        m.mem_write(stack,struct.pack('<2I',stop,actor));m.reg_write(UC_X86_REG_ESP,stack)
        m.emu_start(0x448840,stop,count=12000)
        actual={k:get(actor+off) for k,off in [('effects',0x18c),('flags',0x24),('paralysis',0x3c),('poison',0x30),('no_magic',0x34),('hp',0xd8),('mp',0xe0),('stamina',0xe8),('exp',0x88)]}
        assert actual==dict(effects=expected_flag,flags=7,paralysis=3,poison=0x70002,no_magic=2,hp=1,mp=0,stamina=20,exp=99), (c,actual)
        assert m.reg_read(UC_X86_REG_EIP)==stop and m.reg_read(UC_X86_REG_ESP)==stack+4
        results.append(dict(values=actual,normal_return=True,instructions=steps-oldsteps))
    return dict(input=c,native=results)

def scan(base,mapped,c):
    from unicorn import UC_HOOK_CODE
    from unicorn.x86_const import UC_X86_REG_EAX,UC_X86_REG_EIP,UC_X86_REG_ESP
    m,put,get,obj,actor,stack,stop=machine(base,mapped)
    table=0x10008000;put(0x4c1b40,table)
    definitions={241:(1,0),246:(1,0x80000000),248:(1,0x20000000),251:(1,0xf0000000),31:(2,0x4000000)}
    for code,(kind,effect) in definitions.items():
        put(table+176*code+8,kind);put(table+176*code+0xa0,effect)
    for i,code in enumerate(c['slots']):put(actor+0x138+4*i,code)
    before=bytes(m.mem_read(actor,0x1fc));steps=0
    def guard(_m,at,_n,_d):
        nonlocal steps
        steps+=1
        if not 0x40c230<=at<0x40c2d0:raise ValueError(f'Unexpected scan instruction {at:#x}')
    m.hook_add(UC_HOOK_CODE,guard);m.mem_write(stack,struct.pack('<3I',stop,obj,c['mask']));m.emu_start(0x40c230,stop,count=1024)
    wanted=0
    for i,code in enumerate(c['slots']):
        if not code:continue
        kind,eff=definitions[code]
        if kind==1 and any(c['mask']&flag and eff&itemflag for flag,itemflag in [(1,0x80000000),(2,0x40000000),(4,0x20000000),(8,0x10000000)]):wanted=i+1;break
    actual=m.reg_read(UC_X86_REG_EAX)
    assert actual==wanted and m.reg_read(UC_X86_REG_EIP)==stop and m.reg_read(UC_X86_REG_ESP)==stack+4 and before==bytes(m.mem_read(actor,0x1fc))
    return dict(input=c,native=actual,normal_return=True,instructions=steps)

def fixtures():
    common=dict(level=3,mind=20,magic_attack=50,hit_bonus=7,magic_hit_bonus=10,resistance=0,no_attack=False,hp=100)
    return dict(
        entries=[dict(role=role,active=active,flags=flags,phase=phase,latch=latch) for role in ['player','ai'] for active in [0,1] for flags in [0,3,4,7] for phase in [0,1,0x150000] for latch in [0,1]],
        applications=[dict(common,turns=t,effects=e,seed=s,no_attack=n) for t in [0,2,8,9] for e in [0,0x80,0x4000000] for s in [1,7,101] for n in [False,True]],
        ticks=[dict(poison=p,paralysis=q,no_magic=s) for p in [0,0x70001,0x70003] for q in [0,1,2,9] for s in [0,1,3]],
        cures=[dict(turns=t,effects=e) for t in [0,1,3,9] for e in [0,0x80000000,0x20000000]],
        scans=[dict(slots=slots,mask=mask) for slots in [[0]*8,[241,31,246,248,0,0,0,0],[248,246,0,0,0,0,0,0],[0,0,0,0,0,0,0,248],[251,248,246,0,0,0,0,0]] for mask in [0,1,2,4,7,8]],
        gear=[dict(job=j,capability=cap,codes=codes) for j in [80,94] for cap in [0,0x800] for codes in [[],[2],[211],[31],[31,211],[211,211]]])

def expected_application(c,draws):
    turn=c['turns'];added=0
    if c['hp']>0 and not c['effects']&(0x80|0x4000000):
        if not draws or draws[0]['bound']!=100:raise ValueError('Missing original status hit sample')
        hit=c['no_attack'] or draws[0]['value']+1<=40
        count=3 if hit else 1
        roll=independent(dict(c,proc=6,low=12,high=36,hit_ratio=40,status_hit_ratio=40),draws[:count])
        if roll['value']:
            if len(draws)!=4 or draws[-1]['bound']!=2 or not 0<=draws[-1]['value']<2:raise ValueError('Paralysis duration sample differs')
            added=min(9-turn,2+draws[-1]['value']);turn+=added
        elif len(draws)!=count:raise ValueError('Miss consumed extra status samples')
    elif draws:raise ValueError('Immune/dead target consumed status samples')
    return dict(turns=turn,flags=3|(4 if turn else 0),contribution=added*10,hp=c['hp'])

def check(p):
    if p.get('schema')!='hsl_paralysis_native.v1' or p.get('exe_sha256')!=EXE_SHA or p.get('native_execution') is not True:raise ValueError('Paralysis evidence identity differs')
    if p['sources']!={n:digest((TABLES/n).read_bytes()) for n in SOURCE_NAMES}:raise ValueError('Paralysis source changed')
    for kind,cases in fixtures().items():
        if [r['input'] for r in p[kind]]!=cases:raise ValueError('Paralysis coverage differs: '+kind)
        for row in p[kind]:
            c=row['input']
            if kind=='gear':
                flag=0x4000000 if c['codes'] and (c['capability'] & 0x800 or any(code in [31,211] for code in c['codes'])) else 0
                wanted=dict(effects=flag,flags=7,paralysis=3,poison=0x70002,no_magic=2,hp=1,mp=0,stamina=20,exp=99)
                if len(row['native'])!=2 or any(r['values']!=wanted or r['normal_return'] is not True or not 0<r['instructions']<12000 for r in row['native']):raise ValueError('Paralysis gear refresh differs')
                continue
            normal=kind in ['ticks','scans'];limit=4096 if kind=='applications' else 1024
            if row['normal_return']!=normal or not 0<row['instructions']<limit:raise ValueError('Paralysis execution boundary differs')
            if kind=='entries':
                skip=bool(c['active']) and bool(c['flags']&4) and c['phase']==0
                wanted=dict(skipped=skip,phase=(0x10003 if c['role']=='player' else 0x640001) if skip else c['phase'],latch=c['latch'])
                stop=('0x4447a7' if skip else '0x4439b4') if c['role']=='player' else ('0x441f41' if skip else '0x43f4c7')
                if row.get('stop_address')!=stop or row['actor_queue_unchanged'] is not True:raise ValueError('Paralysis dispatch boundary differs')
            elif kind=='applications':
                wanted=expected_application(c,row['draws'])
                if row.get('stop_address')!='0x40b831':raise ValueError('Paralysis application crossed display boundary')
            elif kind=='ticks':wanted={k:((v&0xffff0000)|((v&0xffff)-1)) if (v&0xffff)>1 else 0 for k,v in c.items()}
            elif kind=='cures':
                t=0 if c['effects']&0x20000000 else c['turns'];wanted=dict(turns=t,flags=3|(4 if t else 0))
                if row.get('stop_address')!='0x40a31f':raise ValueError('Paralysis cure crossed boundary')
            else:
                definitions={241:(1,0),246:(1,0x80000000),248:(1,0x20000000),251:(1,0xf0000000),31:(2,0x4000000)}
                wanted=0
                for i,code in enumerate(c['slots']):
                    if code==0:continue
                    typ,eff=definitions[code]
                    if typ==1 and any(c['mask']&a and eff&b for a,b in [(1,0x80000000),(2,0x40000000),(4,0x20000000),(8,0x10000000)]):wanted=i+1;break
            if row['native']!=wanted:raise ValueError('Paralysis native value differs: '+kind)
    if [(int(a['address'],16),len(bytes.fromhex(a['bytes'])),a['meaning']) for a in p['anchors']]!=ANCHORS:raise ValueError('Paralysis anchors differ')
    actual=hashlib.sha256(bytes.fromhex(''.join(a['bytes'] for a in p['anchors']))).hexdigest()
    if actual!=ANCHOR_SHA:raise ValueError('Paralysis source instruction bytes differ')


def execute_packet(exe: Path) -> dict:
    """Run the bounded original instructions on the documented EXE and assemble the packet."""
    base,mapped=image(exe.read_bytes())
    handlers=dict(entries=entry,applications=application,ticks=duration,cures=cure,scans=scan,gear=gear)
    p=dict(schema='hsl_paralysis_native.v1',evidence_tier='static-derived',native_execution=True,exe_sha256=EXE_SHA,
           sources={n:digest((TABLES/n).read_bytes()) for n in SOURCE_NAMES},
           **{k:[handlers[k](base,mapped,c) for c in cases] for k,cases in fixtures().items()},
           anchors=[dict(address=hex(at),bytes=bytes(mapped[at-base:at-base+size]).hex(),meaning=meaning) for at,size,meaning in ANCHORS],
           limits=['Synthetic actor/queue memory; original engine-enable global and fresh phase are explicit entry conditions.',
                   'Entry only changes object phase; it leaves latch, actor and queue intact before the existing final tail. Not full dispatch execution.',
                   'Spell and item stop before display/audio; duration, cure-slot selection and gear refresh return normally. No stubs.',
                   'Gear execution proves refresh effects, not item/job eligibility. Multi-cure251 appears only in native scan fixtures, not newly supported product equipment.'])
    return p


def summary_line(p: dict, executed_now: bool) -> str:
    return ' '.join(str(part) for part in ('PARALYSIS_NATIVE_PASS', {k:len(p[k])*(2 if k=='gear' else 1) for k in fixtures()}, 'executed_now=', executed_now, 'anchors_sha=', hashlib.sha256(bytes.fromhex(''.join(a['bytes'] for a in p['anchors']))).hexdigest()))


TASK = ProbeTask('paralysis', PACKET, check, execute_packet, summary_line)


def tasks() -> list[ProbeTask]:
    return [TASK]
