"""Bounded full original level inference, automatic allocation and entry adjustment.

Source records and object inputs are explicit. Original callees execute normally;
no RNG, refresh, allocation or VM call is replaced. This is not a full game boot.

Registry task auto_growth (family probe, hsltools.probes._base.ProbeTask): check validates the
tracked packet against the independent model; generate executes the original instructions
(needs the documented hsl01.exe and unicorn). Bodies moved verbatim from the former hsl_native_auto_growth_probe.py.
"""
from __future__ import annotations
import copy
import hashlib
import json
from pathlib import Path
import struct

from hsltools.data.equipment import build as equipment_data
from hsltools.model.jobs import ATTRIBUTES, CAPS, SLOTS, source_profile, calculate
from hsltools.native.image import EXE_SHA, image
from hsltools.native.sources import sources
from hsltools.paths import ROOT
from hsltools.probes._base import ProbeTask
from hsltools.probes.departure import setup_world
from hsltools.sources.tables import TABLES, digest

PACKET = ROOT / 'docs/evidence_packets/static_reverse/original_auto_growth.json'

ANCHORS = [
    (0x40e800, 106, 'Infer level from base attribute total: one plus positive excess over52 rounded up by five.'),
    (0x40e7a0, 92, 'Average non-null objects in the20 registered player slots; empty or zero average becomes one.'),
    (0x439f80, 440, 'Allocate at most five requested points per level, subtract threshold, refresh, assign class quotas, refresh on exit.'),
    (0x43a128, 21, 'Automatic quota dispatch bytes for job80 through100; these are not derived-stat formulas.'),
    (0x40e894, 190, 'Object kind3 and zero adjustment arguments skip random scaling; otherwise clamp registered-party average and sample the target level.'),
    (0x40e94a, 500, 'Above-base adjustment changes kill EXP, gold and source offsets before automatic allocation; final refresh fills current HP/MP.'),
    (0x450ba4, 65, 'Opcode56 packs range in the high word and dispersion in the low word of the previous nonzero roster index; it does not immediately scale.'),
    (0x44ca64, 81, 'PLAYERS level_adjust_range and level_adjust_disp_range populate the same packed source field.'),
    (0x43ef0f, 28, 'An actor-initialization caller passes the two source words to the full adjustment helper.'),
    (0x442729, 22, 'The reward caller distinguishes object kind3 before entering manual versus automatic growth phases.'),
    (0x4429af, 70, 'The non-kind3 reward suffix checks available capacity and invokes automatic allocation, not player stat controls.'),
]
ANCHOR_SHA = '92d93113effdd074fef66c1c76b2368083fa8bebd3116ede63c487cfcf14100b'
SOURCE_KEYS = ('attack_power','magic_attack_power','defense','speed','hit_point','magic_point')
SOURCE_OFFSETS = {'attack_power':0x1a4,'magic_attack_power':0x1a8,'defense':0x1ac,'speed':0x1b0}
STATS = {'max_hp':0xdc,'max_mp':0xe4,'current_hp':0xd8,'current_mp':0xe0,'attack':0xc0,
         'defense':0xb4,'speed':0xb8,'hit_rate':0xbc,'magic_attack':0xd0,'move_point':0x12c,'exp_threshold':0x8c}


def base_case(code: str) -> dict:
    players, _, defines = sources(); row = players[code]
    return dict(actor=code, attributes={k:int(row[k]) for k in ATTRIBUTES}, level=int(row.get('level',1)),
                equipment=[int(row.get(k,0)) for k in SLOTS], hp=7, mp=3, exp=500,
                stamina=0, mode=defines[row['mode']], base_move=int(row.get('move_point', 0)),
                object_kind=2, range=0, dispersion=0, party=[1,7,12], seed=[19,0x87654321], points=5)


def fixtures() -> list[dict]:
    rows = []
    for code in ['001','002','004','006','021','025','026','028','036','039']:
        base=base_case(code)
        rows.append(dict(base, kind='infer'))
        for spread,variation,party,kind in [(0,0,[1],2),(20,3,[10,12],2),(30,0,[30,30],2),(20,9,[99,1],2),(20,3,[99],3),(0,3,[],2)]:
            rows.append(dict(base,kind='adjust',range=spread,dispersion=variation,party=party,object_kind=kind))
    players,_,defines=sources()
    for code in ['001','002','004','006','026','039']:
        base=base_case(code);caps=dict(zip(ATTRIBUTES,CAPS[defines[players[code]['job']]]))
        for count in [0,1,5,7,15]:rows.append(dict(base,kind='allocate',points=count))
        for label,attrs in [('near_cap',{k:caps[k]-1 for k in ATTRIBUTES}),
                            ('one_at_cap',dict(base['attributes'],str=caps['str'])),('all_capped',caps)]:
            rows.append(dict(base,kind='allocate',name=label,attributes=attrs,points=10))
    for party in [[],[0],[1],[2,7],[99,1,7],[0,0,0],[12]*20]:
        rows.append(dict(base_case('026'),kind='average',party=party))
    for seed in [1,7,99]:
        rows.append(dict(base_case('026'),kind='adjust',range=30,dispersion=3,party=[20,23],seed=[seed,0x87654321],stamina=40))
    return rows


def inferred(attrs: dict) -> int:
    return 1 + max(0,(sum(attrs.values()) - 52 + 4)//5)


def allocate(attrs: dict, level: int, exp: int, job: int, points: int, first_threshold: int | None = None) -> tuple[dict,int,int]:
    values=attrs.copy();caps=dict(zip(ATTRIBUTES,CAPS[job]))
    remaining=max(0,min(points,sum(caps[k]-values[k] for k in ATTRIBUTES)))
    quotas=[1,1,1,2] if job in [85,86,87,90,91,92,93,96,97] else [1,2,1,1] if job in [83,84] else [2,1,1,1]
    while remaining:
        budget=min(5,remaining);remaining-=budget
        exp=max(0,exp-(min(2000,(level+1)*50) if first_threshold is None else first_threshold));level+=1
        first_threshold=None
        for key,quota in zip(ATTRIBUTES,quotas):
            amount=max(0,min(quota,budget,caps[key]-values[key]));values[key]+=amount;budget-=amount
        if budget > 0:
            # The actual fallback loop has no remaining-budget exit inside it.
            # Preserve this measured behavior; do not invent a balanced allocator.
            for key in ATTRIBUTES:
                amount=max(0,caps[key]-values[key]);values[key]+=amount;budget-=amount
    return values,level,exp


def expected(c: dict, draws: list[dict]) -> dict:
    players,_,defines=sources(); row=players[c['actor']];profile=source_profile(row,defines)
    profile['source']['mode']=c['mode'];attrs=c['attributes'].copy();level=c['level'];exp=c['exp'];stamina=c['stamina']
    kill=int(row.get('kill_exp',0));gold=int(row.get('gold',0));cursor=0
    def take(bound):
        nonlocal cursor
        if cursor >= len(draws) or draws[cursor]['bound']!=bound:raise ValueError('Adjustment random-call order differs')
        value=draws[cursor]['value'];cursor+=1
        if not 0<=value<bound:raise ValueError('Adjustment sample outside source bound')
        return value
    average=max(1,sum(c['party'])//len(c['party'])) if c['party'] else 1
    if c['kind']=='average':
        if draws:raise ValueError('Average must not draw random numbers')
        return dict(average=average)
    if c['kind'] in ['infer','adjust']:level=inferred(attrs)
    if c['kind']=='allocate':attrs,level,exp=allocate(attrs,level,exp,profile['job_code'],c['points'])
    elif c['kind']=='adjust' and c['object_kind']!=3 and (c['range'] or c['dispersion']):
        low=max(1,level-c['range']);high=max(low+1,level+c['range']);center=max(low,min(high,average))
        low=max(1,center-min(c['dispersion'],4));high=max(low+1,center+c['dispersion']);width=high-low+1
        target=low+take((width+1)//2+1)+take(width//2)
        if target>level:
            delta=target-level
            kill+=kill*max(15,min(150,(take(4)+7)*delta))//100
            gold+=gold*max(10,min(80,(take(4)+7)*delta))//100
            gold=(gold+9)//10*10
            for key,bound,offset in [('hit_point',100,250),('magic_point',150,150),('speed',20,20),('attack_power',60,50),('magic_attack_power',10,10)]:
                profile['source'][key]+=(take(bound)+offset)*delta//100
                # Both source words are halfwords (+0x1b6 / +0x1b4); the refresh 0x448840 reads
                # hit_point sign-extended (Enemy066/067 declare -10000 and refresh to max HP 1).
                if key=='magic_point':profile['source'][key]&=0xffff
                if key=='hit_point':profile['source'][key]=((profile['source'][key]+0x8000)&0xffff)-0x8000
            if stamina==0:stamina=take(11)
            attrs,level,exp=allocate(attrs,level,exp,profile['job_code'],delta*5,min(2000,(c['level']+1)*50))
    if cursor!=len(draws):raise ValueError('Unused original random draws')
    # Level-inference alone does not call refresh; the probe refreshes once before
    # invoking every helper to make its declared input and comparisons precise.
    stat_level=c['level'] if c['kind']=='infer' else level
    hp,mp=(1000000,1000000) if c['kind']=='adjust' else (c['hp'],c['mp'])
    result=calculate(profile,attrs,stat_level,c['equipment'],equipment_data()['items'],hp,mp,c['base_move'])
    return dict(attributes=attrs,level=level,exp=exp,stamina=stamina,kill_exp=kill,gold=gold,
                source={k:profile['source'][k] for k in SOURCE_KEYS},stats=result)


def execute(base: int,mapped: bytearray,c: dict) -> dict:
    from unicorn import Uc,UC_ARCH_X86,UC_MODE_32,UC_HOOK_CODE
    from unicorn.x86_const import UC_X86_REG_EAX,UC_X86_REG_EIP,UC_X86_REG_ESP
    players,items,defines=sources();row=players[c['actor']];profile=source_profile(row,defines)
    m=Uc(UC_ARCH_X86,UC_MODE_32);m.mem_map(base,len(mapped));m.mem_write(base,bytes(mapped))
    for at,size in [(0x10000000,0x20000),(0x20000000,0x10000),(0x21000000,0x20000)]:m.mem_map(at,size)
    obj,actor,stack,stop=0x10001000,0x20000000,0x1001ff00,0x10000000
    def put(at,value):m.mem_write(at,struct.pack('<I',value&0xffffffff))
    def get(at):return struct.unpack('<i',m.mem_read(at,4))[0]
    put(0x4c1bc8,actor);put(obj+0xa4,0);put(obj+0x64,c['object_kind'])
    for i,key in enumerate(ATTRIBUTES):put(actor+0x64+i*4,c['attributes'][key])
    for key,off in SOURCE_OFFSETS.items():put(actor+off,profile['source'][key])
    for key,off in [('avoid_hit_ratio',0x198),('attack_back',0x19c),('attack_damagex2',0x1a0)]:put(actor+off,profile['source'][key])
    for off,value in [(0x18,profile['job_code']),(0x28,c['mode']),(0x9c,c['level']),(0xd8,c['hp']),(0xe0,c['mp']),
                      (0x130,c['base_move']),(0x88,c['exp']),(0xe8,c['stamina']),(0x90,int(row.get('kill_exp',0))),(0x98,int(row.get('gold',0)))]:put(actor+off,value)
    put(actor+0x1b4,(profile['source']['hit_point']<<16)|profile['source']['magic_point'])
    for i in range(5):put(actor+0x118+i*4,profile['source']['base_resist_by_type'][str(i)])
    if profile['source']['has_magic']:put(actor+0x174,1)
    put(0x4c1b40,0x21000000)
    for i,code in enumerate(c['equipment']):
        put(actor+0xec+i*4,code)
        if not code:continue
        item=items[code];at=0x21000000+176*code
        put(at+8,defines[item['type']]);put(at+0x10,-1);put(at+0x8c,-1)
        if 'add_resist' in item:
            kind,amount=[s.strip() for s in item['add_resist'].split(',')];put(at+0x10,defines[kind]);put(at+0x14,int(amount))
        for key,off in [('attack_damage',0x88),('hit_ratio',0x98),('add_weapon_hit',0x18),('add_attack_power',0x20),('add_magic_power',0x24),('add_mp',0x28),('add_hp',0x2c),('add_move',0x34),('add_speed',0x38),('add_defense',0x3c),('add_miss_hit',0x44),('add_attack_back',0x48),('add_weapon_dmgx2',0x4c)]:put(at+off,int(item.get(key,0)))
    for i,level in enumerate(c['party']):
        p=obj+0x200*(i+1);put(p+0xa4,i+1);put(actor+(i+1)*0x1fc+0x9c,level);put(0x4c34c0+i*4,p)
    put(0x4c1e8c,1);put(0x4c3044,c['seed'][0]);put(0x4c3040,c['seed'][1])
    steps=0;draws=[];pending=[];collect=False
    allowed=[(0x40e7a0,0x40eb3e),(0x439f20,0x43a119),(0x448370,0x44b820),(0x458bb0,0x458cb3)]
    def guard(_m,at,_size,_data):
        nonlocal steps
        steps+=1
        if not any(lo<=at<hi for lo,hi in allowed):raise ValueError(f'Unreviewed auto-growth callee {at:#x}')
        if collect and pending and pending[-1][0]==at:
            _,bound=pending.pop();draws.append(dict(bound=bound,value=m.reg_read(UC_X86_REG_EAX)))
        if collect and at==0x458c80:
            esp=m.reg_read(UC_X86_REG_ESP);pending.append((get(esp),get(esp+4)))
    m.hook_add(UC_HOOK_CODE,guard)
    def call(entry,args,budget):
        m.mem_write(stack,struct.pack('<'+'I'*(len(args)+1),stop,*args));m.reg_write(UC_X86_REG_ESP,stack)
        m.emu_start(entry,stop,count=budget)
        if m.reg_read(UC_X86_REG_EIP)!=stop or m.reg_read(UC_X86_REG_ESP)!=stack+4:raise ValueError('Automatic growth did not return normally within budget')
    call(0x448840,[actor],12000);initial_stats=steps;collect=True
    parties_before=bytes(m.mem_read(actor+0x1fc,len(c['party'])*0x1fc))
    entry={'infer':0x40e800,'average':0x40e7a0,'allocate':0x439f80,'adjust':0x40e870}[c['kind']]
    args=[] if c['kind']=='average' else [obj,c['points']] if c['kind']=='allocate' else [obj,c['range'],c['dispersion']] if c['kind']=='adjust' else [obj]
    call(entry,args,200000)
    if pending or parties_before!=bytes(m.mem_read(actor+0x1fc,len(c['party'])*0x1fc)):raise ValueError('Random return or unrelated-party mutation')
    if c['kind']=='average':actual=dict(average=m.reg_read(UC_X86_REG_EAX))
    else:
        stats={k:get(actor+off) for k,off in STATS.items()}
        stats['resist_by_type']={str(i):get(actor+0x104+i*4) for i in range(5)}
        for key,off in [('avoid_hit_ratio',0x19a),('attack_back',0x19e),('attack_damagex2',0x1a2)]:stats[key]=struct.unpack('<H',m.mem_read(actor+off,2))[0]
        source={k:get(actor+off) for k,off in SOURCE_OFFSETS.items()}
        source.update(magic_point=struct.unpack('<H',m.mem_read(actor+0x1b4,2))[0],hit_point=struct.unpack('<h',m.mem_read(actor+0x1b6,2))[0])
        actual=dict(attributes={k:get(actor+0x64+i*4) for i,k in enumerate(ATTRIBUTES)},level=get(actor+0x9c),exp=get(actor+0x88),stamina=get(actor+0xe8),kill_exp=get(actor+0x90),gold=get(actor+0x98),source=source,stats=stats)
    wanted=expected(c,draws)
    if actual!=wanted:raise ValueError(f'Native auto-growth differs {c}: {actual} != {wanted}; draws={draws}')
    return dict(input=c,native=actual,draws=draws,normal_return=True,entry=hex(entry),instructions=steps-initial_stats,unrelated_party_unchanged=True)


def vm_cases():
    return [dict(previous=index,range=a,dispersion=b) for index in [-1,0,1,2] for a,b in [(0,0),(20,3),(65535,65535),(65536,-1)]]


def vm_expected(c):
    values=[0x70003]*3
    if c['previous']>0:values[c['previous']]=((c['range']<<16)+(c['dispersion']&0xffff))&0xffffffff
    return dict(packed=values,cursor_words=6,other_actor_bytes_unchanged=True)


def vm_execute(base,mapped,c):
    from unicorn import UC_HOOK_CODE
    m,put,get,call,pointers,record,_,_=setup_world(base,mapped,{})
    records=record-0x1fc;vm=0x10017000;program=0x10018000
    for i in range(3):put(records+i*0x1fc+0x1f8,0x70003)
    put(0x4c1d38,0 if c['previous']<0 else pointers[c['previous']]);put(vm+0x90,program);put(vm+0x8c,0)
    # Setter56 continues within the VM. A missing-object wait88 is the next real
    # instruction and supplies a normal, non-mutating yield without any stub.
    for i,value in enumerate([56,c['range'],c['dispersion'],88,999,1]):put(program+i*4,value)
    before=bytearray(m.mem_read(records,3*0x1fc));steps=0
    def guard(_m,at,_n,_d):
        nonlocal steps
        steps+=1
        if not any(lo<=at<hi for lo,hi in [(0x450840,0x4508a8),(0x450ba4,0x450be5),(0x4511e9,0x4511fe),(0x4513b4,0x45141b),(0x4527c3,0x4527d5),(0x44fa80,0x44fb8a)]):raise ValueError(f'Unreviewed adjustment VM callee {at:#x}')
    m.hook_add(UC_HOOK_CODE,guard);result=call(0x450840,[vm],4096)
    wanted=vm_expected(c)
    for i,value in enumerate(wanted['packed']):struct.pack_into('<I',before,i*0x1fc+0x1f8,value)
    actual=dict(packed=[get(records+i*0x1fc+0x1f8) for i in range(3)],cursor_words=(get(vm+0x90)-program)//4,other_actor_bytes_unchanged=before==bytes(m.mem_read(records,len(before))))
    if result!=0 or actual!=wanted:raise ValueError(f'Adjustment VM mismatch {c}: {actual}')
    return dict(input=c,native=actual,normal_return=True,instructions=steps)


def check(packet):
    if packet.get('schema')!='hsl_auto_growth_native.v1' or packet.get('exe_sha256')!=EXE_SHA or packet.get('native_execution') is not True:raise ValueError('Automatic growth identity differs')
    if packet['sources']!={n:digest((TABLES/n).read_bytes()) for n in ['PLAYERS.TXT','ITEM.TXT','TYPE.H','ACTION.H']}:raise ValueError('Automatic growth table identity differs')
    players,_,defines=sources()
    if packet.get('profiles')!={c:source_profile(players[c],defines) for c in sorted({r['actor'] for r in fixtures()})}:raise ValueError('Automatic growth role source differs')
    if [r['input'] for r in packet['cases']]!=fixtures() or [r['input'] for r in packet['vm']]!=vm_cases():raise ValueError('Automatic growth fixture coverage differs')
    for row in packet['cases']:
        if row['native']!=expected(row['input'],row['draws']) or not row['normal_return'] or not row['unrelated_party_unchanged'] or not 0<row['instructions']<200000:raise ValueError('Automatic growth result or return differs')
    for row in packet['vm']:
        if row['native']!=vm_expected(row['input']) or row['normal_return'] is not True or not 0<row['instructions']<4096:raise ValueError('Adjustment VM return differs')
    if [(int(r['address'],16),len(bytes.fromhex(r['bytes'])),r['meaning']) for r in packet['anchors']]!=ANCHORS:raise ValueError('Automatic growth anchors differ')
    fingerprint=hashlib.sha256(bytes.fromhex(''.join(r['bytes'] for r in packet['anchors']))).hexdigest()
    if ANCHOR_SHA and fingerprint!=ANCHOR_SHA:raise ValueError('Automatic growth original instructions differ')


def execute_packet(exe: Path) -> dict:
    """Run the bounded original instructions on the documented EXE and assemble the packet."""
    base,mapped=image(exe.read_bytes())
    players,_,defines=sources()
    packet=dict(schema='hsl_auto_growth_native.v1',exe_sha256=EXE_SHA,evidence_tier='static-derived',native_execution=True,
                sources={n:digest((TABLES/n).read_bytes()) for n in ['PLAYERS.TXT','ITEM.TXT','TYPE.H','ACTION.H']},
                profiles={c:source_profile(players[c],defines) for c in sorted({r['actor'] for r in fixtures()})},
                cases=[execute(base,mapped,c) for c in fixtures()],vm=[vm_execute(base,mapped,c) for c in vm_cases()],
                anchors=[dict(address=hex(at),bytes=bytes(mapped[at-base:at-base+size]).hex(),meaning=meaning) for at,size,meaning in ANCHORS],
                limits=['Each numeric helper returns normally. Setter56 continues in the real VM until the next real missing-object wait88 yields; actor construction/global phase dispatch are not executed.',
                        'Object kind3 is an explicit native gate, separate from player control and source mode flags; live insertion eligibility requires a separately declared adapter.',
                        'Automatic allocation near caps has a native fallback that fills remaining attributes to caps; it is not silently replaced with balanced five-point allocation.',
                        'Original random draws are executed and recorded; the live saved generator is not claimed to be the native global random stream.'])
    return packet


def summary_line(packet: dict, executed_now: bool) -> str:
    return f'AUTO_GROWTH_NATIVE_PASS cases={len(packet["cases"])} vm={len(packet["vm"])} executed_now={executed_now} anchors_sha='+hashlib.sha256(bytes.fromhex(''.join(r['bytes'] for r in packet['anchors']))).hexdigest()


TASK = ProbeTask('auto_growth', PACKET, check, execute_packet, summary_line)


def tasks() -> list[ProbeTask]:
    return [TASK]
