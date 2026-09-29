"""Bounded original reward growth, initialization gates and player learning.

Numeric/learning functions return normally. Initial-object/phase gates stop at
declared control boundaries. No callee is skipped, patched or replaced by a stub.

Registry task growth_lifecycle (family probe, hsltools.probes._base.ProbeTask): check validates the
tracked packet against the independent model; generate executes the original instructions
(needs the documented hsl01.exe and unicorn). Bodies moved verbatim from the former hsl_native_growth_lifecycle_probe.py.
"""
from __future__ import annotations
import copy
import hashlib
import json
from pathlib import Path
import struct

from hsltools.data.equipment import original_build as equipment_data
from hsltools.model.jobs import ATTRIBUTES, CAPS, SLOTS, source_profile, calculate
from hsltools.native.image import EXE_SHA, image
from hsltools.native.sources import original_sources as sources
from hsltools.paths import ROOT
from hsltools.probes._base import ProbeTask
from hsltools.probes.auto_growth import base_case, allocate, expected as entry_expected, SOURCE_OFFSETS, STATS
from hsltools.probes.departure import setup_world
from hsltools.sources.tables import TABLES, digest

PACKET = ROOT / 'docs/evidence_packets/static_reverse/original_growth_lifecycle.json'

LIVE_JOBS = [80,85,88,90,92,94]
MAGIC_LEVELS = {
    80: [], 88: [], 94: [],
    85: [(1,1,5),(4,1,0),(6,1,4),(9,0,5),(11,1,1),(14,3,4),(18,4,1),(18,1,6),
         (25,4,2),(27,4,5),(30,5,0),(35,5,1),(39,4,6)],
    90: [(1,0,0),(1,3,0),(1,1,0),(1,2,0),(7,4,0),(8,1,5),(10,1,1),
         (12,3,1),(13,2,1),(14,0,1),(23,0,4)],
    92: [(1,2,0),(8,2,4),(12,2,1)],
}
SPECIAL_TABLES = {80:(0x4782b0,1),85:(0x478314,1),88:(0x4783c0,1),
                  90:(0,0),92:(0x4783fc,1),94:(0x478444,1)}
ANCHORS = [
    (0x442729,22,'Reward object kind3 selects the manual branch; other kinds use automatic allocation.'),
    (0x44299c,151,'Reward phase8 repeats capacity-limited five-point allocation while EXP permits; manual branch stops at UI.'),
    (0x43eed1,42,'Fresh-object flag20000000 enters initialization and clears the flag before external resource setup.'),
    (0x43eefb,48,'Fresh AI object passes source packed adjustment words to40e870 after resource setup.'),
    (0x443443,48,'Player-object counterpart passes the same source words; kind3 bypasses random adjustment in40e870.'),
    (0x43f3a5,86,'General actor callback adjusts under global4000000 and actAdjustAllPlayerLevel latch.'),
    (0x4438d4,104,'Player callback uses the same phase/latch gate for all-roster adjustment.'),
    (0x452408,33,'Opcode73 sets a yielding VM phase and the global adjustment latch.'),
    (0x452f1a,24,'Resuming opcode73 resets the phase and global adjustment latch.'),
    (0x4373f0,1328,'Player magic learning dispatches on job and stored level plus one, preserving existing masks.'),
    (0x437970,201,'Special learning checks class tier and four base attributes in source table order; at most one new skill per call.'),
    (0x437a40,401,'Live-job special learning selects its source table and class tier.'),
    (0x4370fc,198,'Magic grant writes its missing bit and generates a message; repeat is a no-op.'),
    (0x437281,304,'Special nonnull message buffer previews without granting; null buffer commits the first eligible missing bit.'),
    (0x437d3e,67,'Magic learner is called by the player level-up message object, separately from automatic NPC allocation.'),
    (0x43805e,135,'Player special preview and later null-buffer commit use the same learning helper.'),
]
ANCHOR_SHA = 'c4f9143bf23da1899a7be6561b9c036526cb46f51f15ff3985d27f0220c4bb1b'
TABLE_SHA = '3208eae8c5fcdd5d5bd04d8daa10d8dc1a8a15cc8f92133e95455e5bb0cd9b10'


class Machine:
    def __init__(self, base: int, mapped: bytearray, case: dict):
        from unicorn import Uc, UC_ARCH_X86, UC_MODE_32, UC_HOOK_CODE
        from unicorn.x86_const import UC_X86_REG_EAX, UC_X86_REG_ESP
        self.m = m = Uc(UC_ARCH_X86, UC_MODE_32)
        m.mem_map(base,len(mapped));m.mem_write(base,bytes(mapped))
        for at,size in [(0x10000000,0x20000),(0x20000000,0x10000),(0x21000000,0x20000),(0x22000000,0x20000)]:m.mem_map(at,size)
        self.obj,self.actor,self.stack,self.stop = 0x10001000,0x20000000,0x1001ff00,0x10000000
        self.steps=0;self.draws=[];self.pending=[];self.calls=[];self.stops=[]
        self.allowed=[(0x40e7a0,0x40eb3e),(0x439f20,0x43a119),(0x448370,0x44b820),(0x458bb0,0x458cb3)]
        players,items,defines=sources();row=players[case['actor']];profile=source_profile(row,defines)
        obj,actor=self.obj,self.actor
        put=self.put
        put(0x4c1bc8,actor);put(obj+0xa4,0);put(obj+0x64,case['object_kind'])
        for i,key in enumerate(ATTRIBUTES):put(actor+0x64+i*4,case['attributes'][key])
        for key,off in SOURCE_OFFSETS.items():put(actor+off,profile['source'][key])
        for key,off in [('avoid_hit_ratio',0x198),('attack_back',0x19c),('attack_damagex2',0x1a0)]:put(actor+off,profile['source'][key])
        for off,value in [(0x18,profile['job_code']),(0x28,case['mode']),(0x9c,case['level']),
                          (0xd8,case['hp']),(0xe0,case['mp']),(0x130,case['base_move']),
                          (0x88,case['exp']),(0xe8,case['stamina']),(0x90,int(row.get('kill_exp',0))),
                          (0x98,int(row.get('gold',0))),(0x1f8,(case['range']<<16)|case['dispersion'])]:put(actor+off,value)
        put(actor+0x1b4,(profile['source']['hit_point']<<16)|profile['source']['magic_point'])
        for i in range(5):put(actor+0x118+i*4,profile['source']['base_resist_by_type'][str(i)])
        if profile['source']['has_magic']:put(actor+0x174,1)
        put(0x4c1b40,0x21000000)
        for i,code in enumerate(case['equipment']):
            put(actor+0xec+i*4,code)
            if not code:continue
            item=items[code];at=0x21000000+176*code
            put(at+8,defines[item['type']]);put(at+0x10,-1);put(at+0x8c,-1)
            if 'add_resist' in item:
                kind,amount=[s.strip() for s in item['add_resist'].split(',')];put(at+0x10,defines[kind]);put(at+0x14,int(amount))
            for key,off in [('attack_damage',0x88),('hit_ratio',0x98),('add_weapon_hit',0x18),('add_attack_power',0x20),('add_magic_power',0x24),('add_mp',0x28),('add_hp',0x2c),('add_move',0x34),('add_speed',0x38),('add_defense',0x3c),('add_miss_hit',0x44),('add_attack_back',0x48),('add_weapon_dmgx2',0x4c)]:put(at+off,int(item.get(key,0)))
        for i,level in enumerate(case['party']):
            p=obj+0x200*(i+1);put(p+0xa4,i+1);put(actor+(i+1)*0x1fc+0x9c,level);put(0x4c34c0+i*4,p)
        put(0x4c1e8c,1);put(0x4c3044,case['seed'][0]);put(0x4c3040,case['seed'][1])
        def guard(_m,at,_n,_d):
            if at in self.stops:m.emu_stop();return
            self.steps+=1
            if not any(lo<=at<hi for lo,hi in self.allowed):raise ValueError(f'Unreviewed lifecycle callee {at:#x}')
            if self.pending and self.pending[-1][0]==at:
                _,bound=self.pending.pop();self.draws.append(dict(bound=bound,value=m.reg_read(UC_X86_REG_EAX)))
            if at==0x458c80:
                esp=m.reg_read(UC_X86_REG_ESP);self.pending.append((self.get(esp),self.get(esp+4)))
            if at in [0x439f80,0x40e870,0x437080]:
                esp=m.reg_read(UC_X86_REG_ESP)
                self.calls.append(dict(address=hex(at),args=[self.get(esp+4*i) for i in range(1,7 if at==0x437080 else 4 if at==0x40e870 else 3)]))
        m.hook_add(UC_HOOK_CODE,guard)
        self.call(0x448840,[actor])
        self.steps=0

    def put(self,at,value):self.m.mem_write(at,struct.pack('<I',int(value)&0xffffffff))
    def get(self,at):return struct.unpack('<I',self.m.mem_read(at,4))[0]

    def call(self,entry,args,budget=200000):
        from unicorn.x86_const import UC_X86_REG_ESP,UC_X86_REG_EIP,UC_X86_REG_EAX
        self.m.mem_write(self.stack,struct.pack('<'+'I'*(len(args)+1),self.stop,*args))
        self.m.reg_write(UC_X86_REG_ESP,self.stack);self.m.emu_start(entry,self.stop,count=budget)
        end=self.m.reg_read(UC_X86_REG_EIP)
        if end!=self.stop and end not in self.stops:raise ValueError('Lifecycle instruction budget exceeded')
        if end==self.stop and self.m.reg_read(UC_X86_REG_ESP)!=self.stack+4:raise ValueError('Lifecycle stack did not return normally')
        if self.pending:raise ValueError('Unreturned random call')
        return end,self.m.reg_read(UC_X86_REG_EAX)

    def learning_names(self):
        # Synthetic nonempty strings and definition pointers are input fixtures;
        # all mask, source dispatch and native string-copy instructions execute.
        self.put(0x4c1b3c,0x22000000)
        self.m.mem_write(0x22008000,b'ability\0')
        for i in range(1024):self.put(0x22000000+i*4,0x22008000)
        for i in range(7):
            table=0x22010000+i*0x100
            self.put(0x4c2ca0+i*4,table)
            self.put(0x4c3920+i*4,table)
            for n in range(32):self.put(table+n*4,0x22018000)
        self.put(0x22018000,0)
        self.allowed.extend([(0x437080,0x4373b1),(0x4373f0,0x43791e),(0x437970,0x437a3e),
                             (0x437a40,0x437bd2),(0x4477b0,0x4477bf),(0x4098b0,0x4098e4),(0x4099b0,0x4099e4)])


def reward_cases():
    rows=[]
    for actor in ['001','002','004','006','026','039']:
        c=base_case(actor)
        for kind in [2,3]:
            for exp in [99,100,249,250,999]:rows.append(dict(c,kind='reward',object_kind=kind,exp=exp,level=1))
        players,_,defs=sources();caps=dict(zip(ATTRIBUTES,CAPS[defs[players[actor]['job']]]))
        for attrs in [caps,{k:v-1 for k,v in caps.items()},dict(c['attributes'],str=caps['str'])]:
            rows.append(dict(c,kind='reward',object_kind=2,exp=9999,level=1,attributes=attrs))
    return rows


def reward_expected(c):
    players,_,defs=sources();profile=source_profile(players[c['actor']],defs);job=profile['job_code']
    attrs=c['attributes'].copy();exp=c['exp'];level=c['level'];count=0
    caps=dict(zip(ATTRIBUTES,CAPS[job]))
    manual=c['object_kind']==3 and exp>=min(2000,(level+1)*50) and sum(caps[k]-attrs[k] for k in ATTRIBUTES)>0
    if c['object_kind']!=3:
        while exp>=min(2000,(level+1)*50) and sum(caps[k]-attrs[k] for k in ATTRIBUTES)>0:
            attrs,level,exp=allocate(attrs,level,exp,job,5);count+=1
    stats=calculate(profile,attrs,level,c['equipment'],equipment_data()['items'],c['hp'],c['mp'],c['base_move'])
    return dict(attributes=attrs,level=level,exp=exp,levels_allocated=count,manual_ui=manual,
                current_hp=stats['current_hp'],current_mp=stats['current_mp'],max_hp=stats['max_hp'],max_mp=stats['max_mp'],
                attack=stats['attack'],defense=stats['defense'],speed=stats['speed'],source_unchanged=True,skills_unchanged=True,rng_unchanged=True)


def reward_execute(base,mapped,c):
    n=Machine(base,mapped,c);a=n.actor
    n.allowed.append((0x442720,0x442a64));n.stops=[0x442a45]
    n.put(0x4c432c,8)
    immutable=bytes(n.m.mem_read(a+0x158,0x94));rng=bytes(n.m.mem_read(0x4c3040,8))
    end,_=n.call(0x442720,[n.obj,0,0,0])
    actual=dict(attributes={k:n.get(a+0x64+i*4) for i,k in enumerate(ATTRIBUTES)},level=n.get(a+0x9c),exp=n.get(a+0x88),
                levels_allocated=len(n.calls),manual_ui=end==0x442a45,
                **{k:n.get(a+off) for k,off in STATS.items() if k in ['current_hp','current_mp','max_hp','max_mp','attack','defense','speed']},
                source_unchanged=immutable[0x4c:]==bytes(n.m.mem_read(a+0x1a4,0x48)),
                skills_unchanged=immutable[:0x34]==bytes(n.m.mem_read(a+0x158,0x34)),rng_unchanged=rng==bytes(n.m.mem_read(0x4c3040,8)))
    if n.draws or actual!=reward_expected(c):raise ValueError(f'Reward lifecycle mismatch: {c}\n{actual}\n{reward_expected(c)}')
    return dict(input=c,native=actual,normal_return=end==n.stop,stop_address=hex(end),instructions=n.steps,draws=n.draws)


def special_tables(base,mapped):
    result={}
    for job,(address,tier) in SPECIAL_TABLES.items():
        rows=[]
        if address:
            for i in range(20):
                at=address-base+i*14
                if struct.unpack_from('<h',mapped,at)[0]==-1:break
                r=struct.unpack_from('<7h',mapped,at)
                rows.append(dict(tier=r[0],attributes=dict(zip(ATTRIBUTES,r[1:5])),type=r[5],code=r[6]))
            else:raise ValueError('Unterminated special learning table')
        length=14*len(rows)+2 if address else 0
        result[str(job)]=dict(address=hex(address),tier=tier,rows=rows,bytes=bytes(mapped[address-base:address-base+length]).hex() if address else '')
    return result


def learning_cases(tables):
    rows=[]
    for job in LIVE_JOBS:
        for level in sorted({0,1,2,3,5,7,8,17,39,40,*[max(0,x-2) for x,_,_ in MAGIC_LEVELS[job]],*[x-1 for x,_,_ in MAGIC_LEVELS[job]]}):
            for existing in [False,True]:rows.append(dict(kind='magic',job=job,level=level,attributes=[30]*4,existing=existing))
        vectors=[[1]*4,[100]*4]
        for r in tables[str(job)]['rows']:
            if r['tier']>tables[str(job)]['tier']:continue
            attrs=list(r['attributes'].values());vectors.append(attrs)
            for i in range(4):
                low=attrs.copy();low[i]-=1;vectors.append(low)
        for attrs in vectors:
            for preview in [True,False]:rows.append(dict(kind='special',job=job,level=1,attributes=attrs,preview=preview,existing=False))
    return rows


def learning_expected(c,tables):
    masks=[0xffffffff if c['existing'] else 0]* (6 if c['kind']=='magic' else 7)
    before=masks.copy();eligible=[]
    if c['kind']=='magic':
        for threshold,kind,code in MAGIC_LEVELS[c['job']]:
            if c['level']+1>=threshold:
                eligible.append([0,kind,code])
                masks[kind]|=1<<code
    else:
        table=tables[str(c['job'])]
        for r in table['rows']:
            if r['tier']<=table['tier'] and all(value>=r['attributes'][key] for key,value in zip(ATTRIBUTES,c['attributes'])):
                eligible.append([1,r['type'],r['code']])
                if not before[r['type']]&(1<<r['code']):
                    if not c['preview']:masks[r['type']]|=1<<r['code']
                    break
    return dict(masks=masks,attempts=eligible,rng_unchanged=True,attributes_unchanged=True)


def learning_execute(base,mapped,c,tables):
    n=Machine(base,mapped,base_case('001'));n.learning_names();a=n.actor
    n.put(a+0x18,c['job']);n.put(a+0x9c,c['level'])
    for i,value in enumerate(c['attributes']):n.put(a+0x64+i*4,value)
    start=0x174 if c['kind']=='magic' else 0x158;count=6 if c['kind']=='magic' else 7
    for i in range(count):n.put(a+start+i*4,0xffffffff if c['existing'] else 0)
    text=0x10010000 if c['kind']=='magic' or c.get('preview') else 0
    attrs=bytes(n.m.mem_read(a+0x64,16));rng=bytes(n.m.mem_read(0x4c3040,8))
    end,_=n.call(0x4373f0 if c['kind']=='magic' else 0x437a40,[a,text])
    actual=dict(masks=[n.get(a+start+i*4) for i in range(count)],attempts=[r['args'][2:5] for r in n.calls],
                rng_unchanged=rng==bytes(n.m.mem_read(0x4c3040,8)),attributes_unchanged=attrs==bytes(n.m.mem_read(a+0x64,16)))
    if n.draws or actual!=learning_expected(c,tables):raise ValueError(f'Learning differs: {c}\n{actual}\n{learning_expected(c,tables)}')
    return dict(input=c,native=actual,normal_return=end==n.stop,instructions=n.steps,draws=n.draws)


def gate_cases():
    return [dict(base_case(actor),kind='adjust',gate=gate,global_phase=phase,latch=latch,
                 object_kind=obj_kind,range=20,dispersion=3,party=[12,14])
            for actor,obj_kind in [('001',3),('026',2)] for gate in ['ai','player']
            for phase in [0,0x4000000] for latch in [0,1]]


def gate_execute(base,mapped,c):
    from unicorn.x86_const import UC_X86_REG_EBP,UC_X86_REG_ESI,UC_X86_REG_ESP,UC_X86_REG_EIP
    n=Machine(base,mapped,c);m=n.m
    ai=c['gate']=='ai';entry,end=(0x43f3a5,0x43f3fb) if ai else (0x4438d4,0x44393c)
    n.allowed.append((entry,end));n.stops=[end]
    m.reg_write(UC_X86_REG_EBP,n.obj if ai else 0);m.reg_write(UC_X86_REG_ESI,n.obj)
    n.put(0x4c1b00,c['global_phase']);n.put(0x4c1d48,c['latch'])
    m.reg_write(UC_X86_REG_ESP,n.stack);m.emu_start(entry,n.stop,count=200000)
    if m.reg_read(UC_X86_REG_EIP)!=end or n.pending:raise ValueError('Initial gate did not reach declared boundary')
    called=bool(c['global_phase']&0x4000000 and c['latch'])
    calls=[r for r in n.calls if r['address']=='0x40e870']
    if len(calls)!=int(called) or (called and calls[0]['args']!=[n.obj,c['range'],c['dispersion']]):raise ValueError('Initial gate/source arguments differ')
    wanted=entry_expected(c,n.draws) if called else None
    if called and (n.get(n.actor+0x9c)!=wanted['level'] or n.get(n.actor+0xd8)!=wanted['stats']['current_hp']):raise ValueError('Initial gate did not execute complete growth helper')
    return dict(input=c,native=dict(adjusted=called,level=n.get(n.actor+0x9c),hp=n.get(n.actor+0xd8)),
                draws=n.draws,normal_return=False,stop_address=hex(end),instructions=n.steps)


def vm_execute(base,mapped):
    from unicorn import UC_HOOK_CODE
    m,put,get,call,_,record,_,_=setup_world(base,mapped,{})
    vm=0x10017000;program=0x10018000;steps=0
    put(vm+0x90,program);put(vm+0x8c,0);put(program,73);put(0x4c1d48,0)
    before=bytes(m.mem_read(record-0x1fc,3*0x1fc))
    def guard(_m,at,_n,_d):
        nonlocal steps
        steps+=1
        if not any(lo<=at<hi for lo,hi in [(0x450840,0x4508a8),(0x452408,0x452429),(0x45280c,0x452817),(0x452f1a,0x452f32)]):raise ValueError(f'Unreviewed all-growth VM callee {at:#x}')
    m.hook_add(UC_HOOK_CODE,guard);rows=[]
    for expected in [1,0]:
        prior=steps;returned=call(0x450840,[vm],4096)
        row=dict(latch=get(0x4c1d48),phase=get(vm+0x8c),cursor_words=(get(vm+0x90)-program)//4,
                 records_unchanged=before==bytes(m.mem_read(record-0x1fc,3*0x1fc)),normal_return=True,instructions=steps-prior)
        if returned!=0 or row['latch']!=expected or row['phase']!=(73<<16 if expected else 0) or row['cursor_words']!=1 or not row['records_unchanged']:raise ValueError(f'All-growth VM differs: {row}')
        rows.append(row)
    return rows


def check(p):
    if p.get('schema')!='hsl_growth_lifecycle_native.v1' or p.get('exe_sha256')!=EXE_SHA or p.get('native_execution') is not True:raise ValueError('Lifecycle identity differs')
    if p['source_hashes']!={n:digest((TABLES/n).read_bytes()) for n in ['PLAYERS.TXT','ITEM.TXT','TYPE.H','ACTION.H']}:raise ValueError('Lifecycle source tables differ')
    if p['magic_levels']!={str(k):[list(r) for r in v] for k,v in MAGIC_LEVELS.items()}:raise ValueError('Magic level model differs')
    if list(p['special_tables']) != [str(job) for job in LIVE_JOBS]:raise ValueError('Special learning jobs differ')
    if hashlib.sha256(bytes.fromhex(''.join(v['bytes'] for v in p['special_tables'].values()))).hexdigest()!=TABLE_SHA:raise ValueError('Special learning source bytes differ')
    for key,table in p['special_tables'].items():
        at,tier=SPECIAL_TABLES[int(key)];raw=bytes.fromhex(table['bytes'])
        if table['address']!=hex(at) or table['tier']!=tier:raise ValueError('Special learning source location differs')
        decoded=[dict(tier=r[0],attributes=dict(zip(ATTRIBUTES,r[1:5])),type=r[5],code=r[6]) for r in struct.iter_unpack('<7h',raw[:-2])] if raw else []
        if table['rows']!=decoded or (raw and raw[-2:]!=b'\xff\xff'):raise ValueError('Special learning table decode differs')
    if [r['input'] for r in p['rewards']]!=reward_cases() or [r['input'] for r in p['learning']]!=learning_cases(p['special_tables']) or [r['input'] for r in p['gates']]!=gate_cases():raise ValueError('Lifecycle coverage differs')
    for row in p['rewards']:
        wanted=reward_expected(row['input'])
        if row['native']!=wanted or row['normal_return']==wanted['manual_ui'] or row['draws'] or not 0<row['instructions']<200000:raise ValueError('Reward lifecycle proof differs')
    for row in p['learning']:
        if row['native']!=learning_expected(row['input'],p['special_tables']) or not row['normal_return'] or row['draws'] or not 0<row['instructions']<200000:raise ValueError('Learning proof differs')
    for row in p['gates']:
        c=row['input'];called=bool(c['global_phase']&0x4000000 and c['latch'])
        want=entry_expected(c,row['draws']) if called else None
        if row['native']!=dict(adjusted=called,level=want['level'] if called else c['level'],hp=want['stats']['current_hp'] if called else c['hp']) or row['normal_return'] or row['stop_address']!=('0x43f3fb' if c['gate']=='ai' else '0x44393c') or not 0<row['instructions']<200000:raise ValueError('Initialization gate proof differs')
    for index,row in enumerate(p['vm']):
        if row['latch']!=1-index or row['phase']!=(73<<16 if index==0 else 0) or row['cursor_words']!=1 or not row['records_unchanged'] or not row['normal_return']:raise ValueError('VM lifecycle proof differs')
    if len(p['vm'])!=2 or [(int(r['address'],16),len(bytes.fromhex(r['bytes'])),r['meaning']) for r in p['anchors']]!=ANCHORS:raise ValueError('Lifecycle anchors differ')
    sha=hashlib.sha256(bytes.fromhex(''.join(r['bytes'] for r in p['anchors']))).hexdigest()
    if ANCHOR_SHA and sha!=ANCHOR_SHA:raise ValueError('Lifecycle instruction bytes differ')


def execute_packet(exe: Path) -> dict:
    """Run the bounded original instructions on the documented EXE and assemble the packet."""
    base,mapped=image(exe.read_bytes());tables=special_tables(base,mapped)
    p=dict(schema='hsl_growth_lifecycle_native.v1',exe_sha256=EXE_SHA,evidence_tier='static-derived',native_execution=True,
           source_hashes={n:digest((TABLES/n).read_bytes()) for n in ['PLAYERS.TXT','ITEM.TXT','TYPE.H','ACTION.H']},
           magic_levels={str(k):[list(r) for r in v] for k,v in MAGIC_LEVELS.items()},special_tables=tables,
           rewards=[reward_execute(base,mapped,c) for c in reward_cases()],learning=[learning_execute(base,mapped,c,tables) for c in learning_cases(tables)],
           gates=[gate_execute(base,mapped,c) for c in gate_cases()],vm=vm_execute(base,mapped),
           anchors=[dict(address=hex(at),bytes=bytes(mapped[at-base:at-base+length]).hex(),meaning=meaning) for at,length,meaning in ANCHORS],
           limits=['Reward phase8 is full return for NPC/no-growth, manual positive-growth stops before UI436490.',
                   'Learning helpers execute normally using synthetic string/name pointers. Whole player UI callback is not emulated.',
                   'Magic uses job and stored level+1; special uses base attributes/tier and one missing bit per call. NPC automatic allocation does not invoke either learner.',
                   'Initial gates stop before subsequent actor actions; full resource creation and renderer timing remain separate.',
                   'The original entry helper uses the global native RNG. The remake saved initialization stream remains explicitly separate from combat/reward streams.'])
    return p


def summary_line(p: dict, executed_now: bool) -> str:
    return ' '.join(str(part) for part in ('GROWTH_LIFECYCLE_NATIVE_PASS', f'rewards={len(p["rewards"])} learning={len(p["learning"])} gates={len(p["gates"])} vm={len(p["vm"])} executed_now={executed_now}', 'anchors_sha='+hashlib.sha256(bytes.fromhex(''.join(r['bytes'] for r in p['anchors']))).hexdigest()))


TASK = ProbeTask('growth_lifecycle', PACKET, check, execute_packet, summary_line)


def tasks() -> list[ProbeTask]:
    return [TASK]
