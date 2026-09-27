"""Execute original ordinary-series poison/cancellation helpers and queue edits.

The helper chain and equipment refresh return normally. Caller phase4 stops before
the next animation or stamina callback; EXP conversion and effects execute as-is.

Registry task weapon_effect (family probe, hsltools.probes._base.ProbeTask): check validates the
tracked packet against the independent model; generate executes the original instructions
(needs the documented hsl01.exe and unicorn). Bodies moved verbatim from the former hsl_native_weapon_effect_probe.py.
"""
from __future__ import annotations
import hashlib
import json
from pathlib import Path
import struct

from hsltools.data.equipment import build as catalog
from hsltools.model.jobs import ATTRIBUTES, SLOTS, calculate, source_profile
from hsltools.native.image import EXE_SHA, image
from hsltools.native.machine import machine_for
from hsltools.native.sources import sources
from hsltools.paths import ROOT
from hsltools.probes._base import ProbeTask
from hsltools.probes.experience import expected as experience_expected
from hsltools.probes.stat_magic import machine as gear_machine, put_actor
from hsltools.sources.tables import TABLES, digest

PACKET = ROOT / 'docs/evidence_packets/static_reverse/original_weapon_effects.json'

CANCEL, POISON=0x10000,0x200000
FLAGS={'attack_cancel':CANCEL,'attack_poison':POISON,'keep_status_good':0x80}
# 0x409310 status word: attacker +0x18c bits (ITEM loader 0x4477c0), the target immunity each one
# consults through 0x40e2f0 (ORed with universal protection 0x80), and the helper it calls.
WEAKEN,RANDOM,NO_MAGIC,PARALYSIS=0x20000,0x40000,0x80000,0x100000
STATUS_FLAGS={'attack_weaken':WEAKEN,'random_status_error':RANDOM,'attack_nomagic':NO_MAGIC,'attack_paralysis':PARALYSIS}
STATUS_BRANCHES=[('weaken',WEAKEN,0x2000000,0x409240),('no_magic',NO_MAGIC,0x1000000,0x409210),
                 ('paralysis',PARALYSIS,0x4000000,0x409110),('poison',POISON,0x800000,0x4091b0)]
STATUS_WORDS={'poison':0x30,'no_magic':0x34,'weaken':0x38,'paralysis':0x3c}
STATUS_BITS={'poison':1,'no_magic':2,'paralysis':4,'weaken':8}
# ITEM +0xa0 immunity bits 0x448420 ORs into the wearer's +0x18c (equipment.py status_effect_flags).
IMMUNITY_FIELDS={'keep_status_good':0x80,'avoid_poison':0x800000,'avoid_nomagic':0x1000000,'avoid_weaken':0x2000000,'avoid_paralysis':0x4000000}
ANCHORS=[(0x4095e0,37,'Ordinary effect chain calls cancellation, status, then optional MP drain.'),
         (0x4092d0,64,'Cancellation rolls1..100 <=10 before clearing a future enabled slot.'),
         (0x409420,55,'Poison immunity precedes the independent1..100 <=25 chance.'),
         (0x4091b0,88,'Weapon poison adds1..2 turns capped9 and triangular16..32 intensity.'),
         (0x407550,74,'Search begins after current queue index; clear only first matching nonzero flag.'),
         (0x40e2f0,21,'The requested immunity is ORed with universal protection80.'),
         (0x4423e7,36,'Actual per-hit EXP conversion precedes the ordinary effect chain.'),
         (0x442483,40,'Positive EXP reaches effects before the final-series stamina call.'),
         (0x4424be,38,'An alive target with an extra strike remaining reopens animation first.'),
         (0x44800e,29,'The attack_cancel field maps its nonzero parser result to effect10000.'),
         (0x4480a9,29,'The attack_poison field maps its nonzero parser result to effect200000.'),
         (0x447ea5,31,'The keep_status_good field maps its nonzero parser result to effect80.'),
         (0x409345,66,'random_status_error replaces the whole word: rand100+1 <25 weaken, <50 no-magic, <75 paralysis, else poison.'),
         (0x409387,153,'Weaken/no-magic/paralysis each test 0x40e2f0 immunity 2000000/1000000/4000000, then rand100+1 <=25 before the helper.'),
         (0x409240,91,'Weaken helper: flag8, low word +rand2+1 capped9, triangular3..7 merged max(old,(old+new)/2), then full refresh 0x448840.'),
         (0x409210,44,'No-magic helper: flag2, low word +rand2+1 capped9, high word kept.'),
         (0x409110,41,'Paralysis helper: flag4, whole dword +rand2+1 capped9.'),
         (0x448037,19,'The attack_weaken field maps its nonzero parser result to effect20000.'),
         (0x448056,19,'The random_status_error field maps its nonzero parser result to effect40000.'),
         (0x448075,19,'The attack_nomagic field maps its nonzero parser result to effect80000.'),
         (0x448094,19,'The attack_paralysis field maps its nonzero parser result to effect100000.')]
ANCHOR_SHA='a453f68deb9b33eea10c888764847a9ea3d0acea82062728604fb34990d47124'


def cases():
    base=dict(seed=[1,0x87654321],effects=0,immunity=0,poison=0,hp=100,index=0,
              slots=[[0,0],[2,1],[1,1],[3,1]],contribution=20,remaining=0)
    rows=[dict(base,seed=[seed,0x87654321],effects=effect)
          for seed in range(1,33) for effect in [0,CANCEL,POISON,CANCEL|POISON]]
    rows += [dict(base,seed=[seed,0x87654321],effects=CANCEL|POISON,immunity=immunity,poison=word)
             for seed in [1,7,19] for immunity in [0,0x80,0x800000] for word in [0x100003,0x320008,0x140009]]
    rows += [dict(base,effects=CANCEL|POISON,hp=0,seed=[seed,0x87654321]) for seed in [1,7,19]]
    return rows


def queue_cases():
    return [dict(index=index,slots=slots) for index in [-1,0,1,3,199]
            for slots in [[[1,1],[0,0],[1,1],[2,1]],[[0,0],[1,0],[1,1],[1,1]],[[0,0],[2,1],[1,0],[3,1]]]]


def caller_cases():
    base=cases()[0]
    return [dict(base,effects=CANCEL|POISON,seed=[seed,0x87654321],remaining=r,hp=hp,contribution=p)
            for seed in [1,7,19] for r in [0,1] for hp in [0,100] for p in [0,20]]


def cancel_index(case):
    return next((i for i,(actor,ready) in enumerate(case['slots']) if i>case['index'] and actor==1 and ready),-1)


def expected(case,draws,enabled=True):
    cursor=0
    def draw(bound):
        nonlocal cursor
        if cursor>=len(draws) or draws[cursor]['bound']!=bound:raise ValueError('Weapon random-call order differs')
        value=draws[cursor]['value'];cursor+=1
        if not 0<=value<bound:raise ValueError('Weapon RNG exceeds bound')
        return value
    queue=[s[1] for s in case['slots']];changed=-1;poison=case['poison']
    if enabled and case['effects']&CANCEL and draw(100)+1<=10:
        changed=cancel_index(case)
        if changed>=0:queue[changed]=0
    if enabled and case['effects']&POISON and not case['immunity']&0x800080:
        if draw(100)+1<=25:
            duration=min(9,(poison&0xffff)+draw(2)+1)
            power=24-draw(9)+draw(9);old=poison>>16
            if old:power=max(old,(power+old)//2)
            poison=(power<<16)|duration
    if cursor!=len(draws):raise ValueError('Unexpected trailing weapon draw')
    mp=case.get('mp',77)
    if enabled and case['effects']&0x400000:mp=max(0,mp-case['contribution']//3)
    return dict(poison=poison,status=6|int(poison!=0),paralysis=2,no_magic=3,hp=case['hp'],mp=mp,
                queue=queue,cancelled_index=changed)


def execute(base,mapped,case,kind='effects'):
    from unicorn import UC_HOOK_CODE
    from unicorn.x86_const import UC_X86_REG_EAX,UC_X86_REG_EIP,UC_X86_REG_ESP
    m=machine_for(base,mapped);owner,target,roster,stack,stop=0x10001000,0x10002000,0x10004000,0x1001ff00,0x10000000
    def put(at,value):m.mem_write(at,struct.pack('<I',value&0xffffffff))
    def get(at):return struct.unpack('<I',m.mem_read(at,4))[0]
    put(0x4c1bc8,roster);put(owner+0xa4,0);put(target+0xa4,1)
    record=roster+0x1fc
    put(roster+0x18c,case.get('effects',0));put(record+0x18c,case.get('immunity',0))
    for off,value in [(0xd8,case.get('hp',100)),(0xe0,case.get('mp',77)),(0x30,case.get('poison',0)),
                      (0x34,3),(0x3c,2),(0x24,6|int(case.get('poison',0)!=0)),(0x9c,1),(0x90,300)]:put(record+off,value)
    put(roster+0x9c,1);put(0x4c13fc,case.get('contribution',20))
    pointers=[owner,target,0x10003000,0x10003800]
    m.mem_write(0x4c3940,bytes(2400));put(0x4c6e48,case['index'])
    for i,(actor,ready) in enumerate(case['slots']):
        for off,value in [(0,pointers[actor]),(4,actor),(8,ready)]:put(0x4c3940+i*12+off,value)
    put(0x4c1e8c,1);put(0x4c3044,case.get('seed',[1])[0]);put(0x4c3040,0x87654321)
    before_owner=bytes(m.mem_read(roster,0x1fc))
    entry=0x407550 if kind=='queue' else 0x4423c0 if kind=='caller' else 0x4095e0
    args=[target] if kind=='queue' else [owner,target]
    stops=[]
    if kind=='caller':
        put(0x4c432c,4);put(0x4c2c48,case['remaining']);put(0x4c4320,0)
        args += [0x10009000,2]
        stops=[0x4424e4,0x44248e]
    allowed=[(0x407550,0x40759a),(0x4091b0,0x409208),(0x4092d0,0x4094d0),
             (0x4095e0,0x409605),(0x40e240,0x40e26e),(0x40e2f0,0x40e305),(0x406fe0,0x407010),
             (0x42c780,0x42c7d9),(0x458bb0,0x458cb3),(0x4423c0,0x442720),(0x40a5d0,0x40a78d)]
    steps=0;draws=[];returns=[];calls=[];stage='experience' if kind=='caller' else 'effects'
    def guard(_m,at,_size,_data):
        nonlocal steps,stage
        if at in stops:m.emu_stop();return
        steps+=1
        if not any(lo<=at<hi for lo,hi in allowed):raise ValueError(f'Unreviewed weapon callee {at:#x}')
        if returns and returns[-1][0]==at:
            _,bound,part=returns.pop();draws.append(dict(bound=bound,value=m.reg_read(UC_X86_REG_EAX),stage=part))
        if at==0x4095e0:stage='effects';calls.append(hex(at))
        elif at in [0x4092d0,0x409310,0x4091b0,0x407550,0x409460,0x40a5d0]:calls.append(hex(at))
        if at==0x42c780:
            sp=m.reg_read(UC_X86_REG_ESP);returns.append((get(sp),get(sp+4),stage))
    m.hook_add(UC_HOOK_CODE,guard)
    m.mem_write(stack,struct.pack('<'+'I'*(len(args)+1),stop,*args));m.reg_write(UC_X86_REG_ESP,stack)
    m.emu_start(entry,stop,count=8192);end=m.reg_read(UC_X86_REG_EIP)
    if end not in [stop,*stops] or returns or (end==stop and m.reg_read(UC_X86_REG_ESP)!=stack+4):raise ValueError('Weapon execution boundary differs')
    if bytes(m.mem_read(roster,0x1fc))!=before_owner:raise ValueError('Effect helper mutated attacker')
    queue=[get(0x4c3948+i*12) for i in range(len(case['slots']))]
    changed=next((i for i,v in enumerate(queue) if v!=case['slots'][i][1]),-1)
    if kind=='queue':
        expected_index=cancel_index(case)
        wanted=[row[1] if i!=expected_index else 0 for i,row in enumerate(case['slots'])]
        actual=dict(queue=queue,cancelled_index=changed,value=m.reg_read(UC_X86_REG_EAX))
        if queue!=wanted or changed!=expected_index or actual['value']!=int(expected_index>=0):raise ValueError('Native queue cancellation differs')
    else:
        actual=dict(poison=get(record+0x30),status=get(record+0x24),paralysis=get(record+0x3c),
                    no_magic=get(record+0x34),hp=get(record+0xd8),mp=get(record+0xe0),queue=queue,cancelled_index=changed)
        enabled=kind!='caller' or ((case['remaining']==0 or case['hp']==0) and case['contribution']>0)
        effect_draws=[{k:d[k] for k in ['bound','value']} for d in draws if d['stage']=='effects']
        if actual!=expected(case,effect_draws,enabled):raise ValueError(f'Weapon model differs {case}: {actual}')
        if kind=='caller':
            exp_case=dict(contribution=case['contribution'],attacker_level=1,target_level=1,target_hp=case['hp'],kill_exp=300,kill_word=0)
            exp_draws=[{k:d[k] for k in ['bound','value']} for d in draws if d['stage']=='experience']
            if get(0x10009000)!=experience_expected(exp_case,exp_draws):raise ValueError('Caller EXP precedes effect incorrectly')
            if ('0x4095e0' in calls)!=enabled:raise ValueError('Intermediate/miss strike reached effects')
            actual.update(experience=get(0x10009000),effect_called=enabled)
    return dict(input=case,native=actual,draws=draws,calls=calls,instructions=steps,normal_return=end==stop,
                entry=hex(entry),stop_address=hex(end),attacker_unchanged=True)


def status_cases():
    """0x409310 inputs: attacker word, a full PLAYERS target (0x448840 refreshable), accessory
    immunities, pre-existing words and fixed seeds. Seeds 1..32 give first rand100 values
    <=24 at 5/10/13/15/16/22/23; the random-word seeds pin the four segment boundaries."""
    words=dict(weaken=0,no_magic=0,paralysis=0,poison=0);every=WEAKEN|NO_MAGIC|PARALYSIS|POISON
    base=dict(actor='002',level=5,hp=1000,mp=1000,gear=[0]*6,words=words,effects=0,seed=1)
    # seeds 62 / 231: first rand100 value 24 / 25, the last success and first failure of `rand100+1 <= 25`
    rows=[dict(base,effects=effect,seed=seed) for effect in [WEAKEN,NO_MAGIC,PARALYSIS] for seed in [*range(1,33),62,231]]
    rows += [dict(base,effects=every,seed=seed) for seed in [5,7,10,15,19,22]]
    # first rand100 value: 0/0 -> 1 weaken, 23 -> 24 weaken, 24 -> 25 no-magic, 48 -> 49 no-magic,
    # 49 -> 50 paralysis, 73 -> 74 paralysis, 74 -> 75 poison, 99 -> 100 poison
    rows += [dict(base,effects=RANDOM,seed=seed) for seed in [15,53,76,99,62,462,239,77,343,743,55,1655,209,20,387,40]]
    rows += [dict(base,effects=RANDOM|every,seed=seed) for seed in [15,343,209]]
    for codes in [[220],[219],[211],[217],[229],[220,219],[211,217]]:
        rows += [dict(base,effects=every,gear=[0,0,0,0,*codes,*[0]*(2-len(codes))],seed=seed) for seed in [15,10]]
    for existing in [dict(weaken=0x50003),dict(weaken=0x30008),dict(weaken=0x70001),dict(no_magic=8),dict(no_magic=0x10008),
                     dict(paralysis=9),dict(poison=0x140009),dict(weaken=0x50003,no_magic=3,paralysis=2,poison=0x70003)]:
        rows += [dict(base,effects=every,words=dict(words,**existing),seed=seed) for seed in [5,10,15]]
    rows += [dict(base,actor=actor,level=level,effects=every,seed=15) for actor in ['001','002','026','024'] for level in [1,20]]
    rows += [dict(base,effects=every,hp=hp,mp=mp,seed=15) for hp,mp in [(1,0),(0,0),(30,5)]]
    return rows


def immunity_word(gear):
    _,items,_=sources()
    return sum(sum(bit for key,bit in IMMUNITY_FIELDS.items() if int(items[code].get(key,0))) for code in gear if code)


def status_expected(case,draws):
    """Independent model of 0x409310 and its helpers on the recorded native draws: the final words,
    flags, helper order and the 0x448840-derived values after a weaken refresh."""
    cursor=0
    def draw(bound):
        nonlocal cursor
        if cursor>=len(draws) or draws[cursor]['bound']!=bound:raise ValueError('Status random-call order differs')
        value=draws[cursor]['value'];cursor+=1
        if not 0<=value<bound:raise ValueError('Status RNG exceeds bound')
        return value
    words=dict(case['words']);flags=sum(bit for key,bit in STATUS_BITS.items() if words[key]);immunity=immunity_word(case['gear'])
    word=case['effects']&(WEAKEN|NO_MAGIC|PARALYSIS|POISON);selected=None
    if case['effects']&RANDOM:
        roll=draw(100)+1;word=WEAKEN if roll<25 else NO_MAGIC if roll<50 else PARALYSIS if roll<75 else POISON
        selected=dict(roll=roll,bit=hex(word))
    calls=[];refreshed=False
    for key,bit,immune_bit,helper in STATUS_BRANCHES:
        if not word&bit or immunity&(immune_bit|0x80) or draw(100)+1>25:continue
        calls.append(hex(helper));flags|=STATUS_BITS[key];old=words[key]
        if key=='weaken':
            turns=min(9,(old&0xffff)+draw(2)+1);power=5-draw(3)+draw(3);prior=struct.unpack('<h',struct.pack('<H',old>>16))[0]
            if prior:
                merged=int((prior+power)/2);power=merged if merged>=prior else prior
            words[key]=(power&0xffff)<<16|turns;refreshed=True
        elif key=='no_magic':words[key]=(old&0xffff0000)|min(9,(old&0xffff)+draw(2)+1)
        elif key=='paralysis':words[key]=min(9,old+draw(2)+1)
        else:
            duration=min(9,(old&0xffff)+draw(2)+1);power=24-draw(9)+draw(9);prior=old>>16
            if prior:power=max(prior,(power+prior)//2)
            words[key]=(power<<16)|duration
    if cursor!=len(draws):raise ValueError('Unexpected trailing status draw')
    players,_,defines=sources();row=players[case['actor']];attributes={key:int(row[key]) for key in ATTRIBUTES}
    if flags&8:
        power=struct.unpack('<h',struct.pack('<H',words['weaken']>>16))[0]
        attributes={key:max(1,value-power) for key,value in attributes.items()}
    profile=source_profile(row,defines)
    derived=calculate(profile,attributes,case['level'],case['gear'],catalog()['items'],case['hp'],case['mp'],int(row['move_point']))
    # 0x44b7b8: a record without any magic word (+0x174..+0x188 all zero) gets effect bit 0x4000 and zero MP.
    values=dict(attributes,attack=derived['attack'],defense=derived['defense'],speed=derived['speed'],max_hp=derived['max_hp'],max_mp=derived['max_mp'],
                hp=derived['current_hp'],mp=derived['current_mp'],move_point=derived['move_point'],effects=immunity|(0 if profile['source']['has_magic'] else 0x4000))
    return dict(words=words,flags=flags,values=values,calls=calls,refreshed=refreshed,random_status=selected)


def execute_status(base,mapped,case):
    from unicorn import UC_HOOK_CODE
    from unicorn.x86_const import UC_X86_REG_EAX,UC_X86_REG_EIP,UC_X86_REG_ESP
    m=gear_machine(base,mapped);owner,target,roster,stack,stop=0x10001000,0x10002000,0x10004000,0x1001ff00,0x10000000
    def put(at,value):m.mem_write(at,struct.pack('<I',value&0xffffffff))
    def get(at):return struct.unpack('<I',m.mem_read(at,4))[0]
    put(0x4c1bc8,roster);put(owner+0xa4,0);put(target+0xa4,1);record=roster+0x1fc
    put(roster+0x18c,case['effects']);put(roster+0x9c,1)
    _,items,_=sources()
    put_actor(m,record,case['actor'],case['level'],case['hp'],case['mp'],case['gear'],{k:case['words'][k] for k in ['poison','no_magic','paralysis']})
    put(record+0x38,case['words']['weaken']);put(record+0x24,sum(bit for key,bit in STATUS_BITS.items() if case['words'][key]))
    for code in case['gear']:
        if code:put(0x20000000+176*code+0xa0,sum(bit for key,bit in IMMUNITY_FIELDS.items() if int(items[code].get(key,0))))
    put(0x4c1e8c,1);put(0x4c3044,case['seed']);put(0x4c3040,0x87654321)
    allowed=[(0x4091b0,0x409208),(0x409110,0x409139),(0x409210,0x40923d),(0x409240,0x40929b),(0x4092d0,0x4094d0),(0x4095e0,0x409605),
             (0x406fe0,0x407010),(0x40e240,0x40e26e),(0x40e2f0,0x40e305),(0x42c780,0x42c7d9),(0x458bb0,0x458cb3),(0x448370,0x44b820)]
    steps=0;draws=[];returns=[];calls=[];refreshes=0;phase='initial'
    def guard(_m,at,_size,_data):
        nonlocal steps,refreshes
        steps+=1
        if phase=='initial':
            if not 0x448370<=at<0x44b820:raise ValueError(f'Unreviewed status refresh callee {at:#x}')
            return
        if not any(lo<=at<hi for lo,hi in allowed):raise ValueError(f'Unreviewed status callee {at:#x}')
        if returns and returns[-1][0]==at:
            _,bound=returns.pop();draws.append(dict(bound=bound,value=m.reg_read(UC_X86_REG_EAX)))
        if at in [helper for _,_,_,helper in STATUS_BRANCHES]:calls.append(hex(at))
        if at==0x448840:refreshes+=1
        if at==0x42c780:
            sp=m.reg_read(UC_X86_REG_ESP);returns.append((get(sp),get(sp+4)))
    m.hook_add(UC_HOOK_CODE,guard)
    m.mem_write(stack,struct.pack('<2I',stop,record));m.reg_write(UC_X86_REG_ESP,stack);m.emu_start(0x448840,stop,count=14000)
    if m.reg_read(UC_X86_REG_EIP)!=stop or m.reg_read(UC_X86_REG_ESP)!=stack+4:raise ValueError('Initial status refresh failed return')
    phase='effects';initial=steps;before_owner=bytes(m.mem_read(roster,0x1fc))
    before={off:bytes(m.mem_read(record+off,size)) for off,size in [(0x64,16),(0x88,4),(0x9c,4),(0xe8,4),(0xec,24),(0x138,32)]}
    m.mem_write(stack,struct.pack('<3I',stop,owner,target));m.reg_write(UC_X86_REG_ESP,stack);m.emu_start(0x4095e0,stop,count=16000)
    if m.reg_read(UC_X86_REG_EIP)!=stop or m.reg_read(UC_X86_REG_ESP)!=stack+4 or returns:raise ValueError('Status execution boundary differs')
    if bytes(m.mem_read(roster,0x1fc))!=before_owner:raise ValueError('Status helper mutated attacker')
    if any(bytes(m.mem_read(record+off,len(value)))!=value for off,value in before.items()):raise ValueError('Status helper changed base attributes, EXP, level, stamina, equipment or inventory')
    actual=dict(words={key:get(record+off) for key,off in STATUS_WORDS.items()},flags=get(record+0x24),
                values=dict({key:get(record+off) for key,off in zip(ATTRIBUTES,[0x4c,0x50,0x54,0x58])},
                            **{key:get(record+off) for key,off in [('attack',0xc0),('defense',0xb4),('speed',0xb8),('max_hp',0xdc),('max_mp',0xe4),('hp',0xd8),('mp',0xe0),('move_point',0x12c),('effects',0x18c)]}),
                calls=calls,refreshed=refreshes==1)
    wanted=status_expected(case,draws)
    if actual!={key:wanted[key] for key in actual} or refreshes>1:raise ValueError(f'Status model differs {case}: {actual} != {wanted}')
    return dict(input=case,native=dict(actual,random_status=wanted['random_status']),draws=draws,instructions=steps-initial,
                entry='0x4095e0',stop_address=hex(stop),normal_return=True,initial_refresh_return=True,attacker_unchanged=True)


def status_mapping_cases():
    return [dict(field=field,value=value,before=before) for field in STATUS_FLAGS for value in [0,1] for before in [0,0x200000]]


# ITEM loader 0x4477c0 windows: from the `add esp, 0xc` after the field parser returns to the
# next field's `push esi`; [esp+0x10] holds the effect word being built.
MAPPING_WINDOWS={'attack_cancel':(0x448018,0x44802b),'attack_poison':(0x4480b3,0x4480c6),'keep_status_good':(0x447eaf,0x447ec4),'attack_decmp':(0x4480d2,0x4480e5),
                 'attack_weaken':(0x448037,0x44804a),'random_status_error':(0x448056,0x448069),'attack_nomagic':(0x448075,0x448088),'attack_paralysis':(0x448094,0x4480a7)}


def gear_cases():
    return [dict(job=job,codes=codes,status=state) for job,codes in
            [(94,[]),(94,[29]),(94,[35]),(94,[37]),(94,[35,229]),(94,[29,229]),(80,[144]),(80,[144,229]),(94,[229,229])]
            for state in [0,7]]


def mapping_cases():
    return [dict(field=field,value=value,before=before) for field in FLAGS for value in [0,1] for before in [0,0x40]]


def execute_mapping(base,mapped,case):
    from unicorn import UC_HOOK_CODE
    from unicorn.x86_const import UC_X86_REG_EAX,UC_X86_REG_EBP,UC_X86_REG_ESP,UC_X86_REG_EIP
    m=machine_for(base,mapped);stack=0x1001ff00
    entry,stop=MAPPING_WINDOWS[case['field']]
    m.mem_write(stack+28,struct.pack('<I',case['before']))
    m.reg_write(UC_X86_REG_EAX,case['value']);m.reg_write(UC_X86_REG_EBP,0);m.reg_write(UC_X86_REG_ESP,stack)
    steps=0
    def guard(_m,at,_size,_data):
        nonlocal steps
        steps+=1
        if not entry<=at<stop:raise ValueError('Unreviewed weapon loader suffix')
    m.hook_add(UC_HOOK_CODE,guard);m.emu_start(entry,stop,count=32)
    actual=struct.unpack('<I',m.mem_read(stack+28,4))[0]
    flag=0x400000 if case['field']=='attack_decmp' else dict(FLAGS,**STATUS_FLAGS)[case['field']]
    if m.reg_read(UC_X86_REG_EIP)!=stop or m.reg_read(UC_X86_REG_ESP)!=stack+12 or actual!=(case['before']|(flag if case['value'] else 0)):
        raise ValueError('Weapon source field mapping differs')
    return dict(input=case,native=actual,entry=hex(entry),stop_address=hex(stop),instructions=steps,normal_return=False)


def gear_flags(case):
    _,items,_=sources();flags=0
    for code in case['codes']:
        flags |= sum(bit for key,bit in dict(FLAGS,attack_decmp=0x400000).items() if int(items[code].get(key,0)))
    return flags


def execute_gear(base,mapped,case):
    from unicorn import Uc,UC_ARCH_X86,UC_MODE_32,UC_HOOK_CODE
    from unicorn.x86_const import UC_X86_REG_EIP,UC_X86_REG_ESP
    _,items,defines=sources();m=Uc(UC_ARCH_X86,UC_MODE_32)
    m.mem_map(base,len(mapped));m.mem_write(base,bytes(mapped))
    for at,size in [(0x10000000,0x10000),(0x20000000,0x10000),(0x21000000,0x20000)]:m.mem_map(at,size)
    actor,stack,stop=0x20000000,0x1000ff00,0x10000000
    def put(at,value):m.mem_write(at,struct.pack('<I',value&0xffffffff))
    def get(at):return struct.unpack('<I',m.mem_read(at,4))[0]
    for off,value in [(0x18,case['job']),(0x28,0x10000),(0x9c,3),(0xd8,1),(0xe0,0),(0x174,1),(0x130,4),
                      (0x24,case['status']),(0x30,0x140003 if case['status'] else 0),(0x34,2 if case['status'] else 0),
                      (0x3c,1 if case['status'] else 0),(0x88,37),(0xe8,20)]:put(actor+off,value)
    for off in [0x64,0x68,0x6c,0x70]:put(actor+off,20)
    put(0x4c1b40,0x21000000);accessory=4
    for code in case['codes']:
        row=items[code];at=0x21000000+176*code;kind=defines[row['type']]
        index=0 if kind==2 else 2 if kind==4 else accessory
        if index>=4:accessory+=1
        put(actor+0xec+index*4,code)
        for off,value in [(8,kind),(0x10,-1),(0x8c,-1),(0x88,int(row.get('attack_damage',0))),
                          (0xa0,sum(bit for key,bit in dict(FLAGS,attack_decmp=0x400000).items() if int(row.get(key,0))))]:put(at+off,value)
    steps=0
    def guard(_m,at,_size,_data):
        nonlocal steps
        steps+=1
        if not 0x448370<=at<0x44b820:raise ValueError(f'Unreviewed weapon refresh callee {at:#x}')
    m.hook_add(UC_HOOK_CODE,guard);results=[]
    for _ in range(2):
        put(actor+0x18c,0x7fffffff);prior=steps
        m.mem_write(stack,struct.pack('<2I',stop,actor));m.reg_write(UC_X86_REG_ESP,stack)
        m.emu_start(0x448840,stop,count=12000)
        actual={key:get(actor+off) for key,off in [('effects',0x18c),('status',0x24),('poison',0x30),('no_magic',0x34),('paralysis',0x3c),('hp',0xd8),('mp',0xe0),('exp',0x88),('stamina',0xe8)]}
        wanted=dict(effects=gear_flags(case),status=case['status'],poison=0x140003 if case['status'] else 0,no_magic=2 if case['status'] else 0,paralysis=1 if case['status'] else 0,hp=1,mp=0,exp=37,stamina=20)
        if m.reg_read(UC_X86_REG_EIP)!=stop or m.reg_read(UC_X86_REG_ESP)!=stack+4 or actual!=wanted:raise ValueError('Weapon refresh failed full return/repeated source OR')
        results.append(dict(values=actual,normal_return=True,instructions=steps-prior))
    return dict(input=case,native=results)


def check(packet):
    if packet.get('schema')!='hsl_native_weapon_effects.v1' or packet.get('exe_sha256')!=EXE_SHA or packet.get('native_execution') is not True:raise ValueError('Weapon proof identity differs')
    if packet['sources']!={n:digest((TABLES/n).read_bytes()) for n in ['ITEM.TXT','TYPE.H']}:raise ValueError('Weapon source bytes differ')
    for key,wanted in [('effects',cases()),('queue',queue_cases()),('caller',caller_cases()),('gear',gear_cases()),('mapping',mapping_cases()),
                       ('status',status_cases()),('status_mapping',status_mapping_cases())]:
        if [row['input'] for row in packet[key]]!=wanted:raise ValueError('Weapon fixture coverage differs')
    for kind in ['effects','caller']:
        for row in packet[kind]:
            case=row['input'];enabled=kind!='caller' or ((case['remaining']==0 or case['hp']==0) and case['contribution']>0)
            predicted=expected(case,[d for d in row['draws'] if d['stage']=='effects'],enabled)
            if any(row['native'][k]!=v for k,v in predicted.items()) or not row['attacker_unchanged'] or not 0<row['instructions']<8192:raise ValueError('Weapon native output differs')
            if kind=='effects' and (not row['normal_return'] or row['stop_address']!='0x10000000'):raise ValueError('Weapon helper did not return')
            if kind=='caller':
                exp=experience_expected(dict(contribution=case['contribution'],attacker_level=1,target_level=1,target_hp=case['hp'],kill_exp=300,kill_word=0),[d for d in row['draws'] if d['stage']=='experience'])
                stop='0x4424e4' if case['remaining'] and case['hp'] else '0x44248e' if enabled else '0x10000000'
                if row['native']['experience']!=exp or row['native']['effect_called']!=enabled or row['stop_address']!=stop or row['normal_return']!=(stop=='0x10000000'):raise ValueError('Weapon caller gate differs')
    for row in packet['queue']:
        case=row['input'];index=cancel_index(case)
        if row['native']!=dict(queue=[s[1] if i!=index else 0 for i,s in enumerate(case['slots'])],cancelled_index=index,value=int(index>=0)) or not row['normal_return'] or row['entry']!='0x407550' or row['stop_address']!='0x10000000' or not 0<row['instructions']<8192:raise ValueError('Weapon queue proof differs')
    for row in packet['gear']:
        case=row['input']
        wanted=dict(effects=gear_flags(case),status=case['status'],poison=0x140003 if case['status'] else 0,no_magic=2 if case['status'] else 0,paralysis=1 if case['status'] else 0,hp=1,mp=0,exp=37,stamina=20)
        if len(row['native'])!=2 or any(not r['normal_return'] or r['values']!=wanted or not 0<r['instructions']<12000 for r in row['native']):raise ValueError('Weapon gear proof differs')
    for row in packet['mapping']+packet['status_mapping']:
        case=row['input'];entry,stop=(hex(at) for at in MAPPING_WINDOWS[case['field']]);flag=dict(FLAGS,**STATUS_FLAGS)[case['field']]
        if row['native']!=(case['before']|(flag if case['value'] else 0)) or row['normal_return'] or row['entry']!=entry or row['stop_address']!=stop or not 0<row['instructions']<32:raise ValueError('Weapon loader mapping proof differs')
    check_status(packet['status'])
    if [(int(a['address'],16),len(bytes.fromhex(a['bytes'])),a['meaning']) for a in packet['anchors']]!=ANCHORS:raise ValueError('Weapon anchors differ')
    actual=hashlib.sha256(bytes.fromhex(''.join(a['bytes'] for a in packet['anchors']))).hexdigest()
    if ANCHOR_SHA and actual!=ANCHOR_SHA:raise ValueError('Weapon instruction bytes changed')


def check_status(rows):
    """Every 0x409310 row against the independent model, plus the coverage the fixtures must reach:
    all four random selections at their segment boundaries, and each helper both called and skipped."""
    selections=set();rolls=set();chances=set();called=set();skipped=set()
    for row in rows:
        case=row['input'];wanted=status_expected(case,row['draws']);native=row['native']
        if any(native[key]!=wanted[key] for key in ['words','flags','values','calls','refreshed','random_status']):raise ValueError('Weapon status native output differs')
        if not row['normal_return'] or not row['initial_refresh_return'] or not row['attacker_unchanged'] or row['entry']!='0x4095e0' or row['stop_address']!='0x10000000' or not 0<row['instructions']<16000:raise ValueError('Weapon status boundary differs')
        if wanted['random_status']:selections.add(wanted['random_status']['bit']);rolls.add(wanted['random_status']['roll'])
        if not case['effects']&RANDOM and row['draws']:chances.add(row['draws'][0]['value']+1)
        called.update(wanted['calls'])
        skipped.update(hex(helper) for key,bit,_,helper in STATUS_BRANCHES if case['effects']&bit and not case['effects']&RANDOM and hex(helper) not in wanted['calls'])
    if selections!={hex(bit) for bit in [WEAKEN,NO_MAGIC,PARALYSIS,POISON]} or not {1,24,25,49,50,74,75,100}<=rolls:raise ValueError('Weapon random-status segments not covered')
    if not {25,26}<=chances or called!={hex(helper) for *_,helper in STATUS_BRANCHES} or skipped!=called:raise ValueError('Weapon status chance boundary or helpers not covered')


def execute_packet(exe: Path) -> dict:
    """Run the bounded original instructions on the documented EXE and assemble the packet."""
    base,mapped=image(exe.read_bytes())
    packet=dict(schema='hsl_native_weapon_effects.v1',exe_sha256=EXE_SHA,native_execution=True,evidence_tier='static-derived',
                sources={n:digest((TABLES/n).read_bytes()) for n in ['ITEM.TXT','TYPE.H']},
                effects=[execute(base,mapped,c) for c in cases()],queue=[execute(base,mapped,c,'queue') for c in queue_cases()],
                caller=[execute(base,mapped,c,'caller') for c in caller_cases()],gear=[execute_gear(base,mapped,c) for c in gear_cases()],
                mapping=[execute_mapping(base,mapped,c) for c in mapping_cases()],
                status=[execute_status(base,mapped,c) for c in status_cases()],status_mapping=[execute_mapping(base,mapped,c) for c in status_mapping_cases()],
                anchors=[dict(address=hex(at),bytes=bytes(mapped[at-base:at-base+length]).hex(),meaning=meaning) for at,length,meaning in ANCHORS],
                limits=['Cancellation, the 0x409310 status word (weaken/no-magic/paralysis/poison, random_status_error) and universal protection; the MP strike bit stays a disabled input here.',
                        'Status rows run 0x4095e0 on a full PLAYERS target whose weaken refresh is the real 0x448840; immunities come from accessory ITEM rows, not synthetic words.',
                        'Effects may alter a zero-HP native record; the remake clears dead statuses after consuming the same accepted tail draws.',
                        'Caller stops before animation/stamina; helper and gear return normally, without stubbing any original callee.',
                        'Loader field mappings execute from a supplied parser return to the next field boundary, not the whole text parser.',
                        'Synthetic source masks/queue records and fixed RNG seeds, not whole original gameplay or global dispatcher parity.'])
    return packet


def summary_line(packet: dict, executed_now: bool) -> str:
    return ' '.join(str(part) for part in ('WEAPON_EFFECT_NATIVE_PASS', {k:len(packet[k]) for k in ['effects','queue','caller','gear','mapping','status','status_mapping']}, 'executed_now=', executed_now, 'anchors_sha=', hashlib.sha256(bytes.fromhex(''.join(x['bytes'] for x in packet['anchors']))).hexdigest()))


TASK = ProbeTask('weapon_effect', PACKET, check, execute_packet, summary_line)


def tasks() -> list[ProbeTask]:
    return [TASK]
