"""Original attack/defense enhancement, dispel, complete refresh and duration.

Applications stop at0x40b831 before contribution conversion/display. Calls to
0x448840 are real complete refreshes, with source actor/item inputs. No stubs.

Registry task stat_magic (family probe, hsltools.probes._base.ProbeTask): check validates the
tracked packet against the independent model; generate executes the original instructions
(needs the documented hsl01.exe and unicorn). Bodies moved verbatim from the former hsl_native_stat_magic_probe.py.
"""
from __future__ import annotations
import hashlib
import json
from pathlib import Path
import struct

from hsltools.data.equipment import build as catalog
from hsltools.model.jobs import source_profile, calculate, ATTRIBUTES, SLOTS
from hsltools.native.image import EXE_SHA, image
from hsltools.native.machine import machine_for
from hsltools.native.sources import sources
from hsltools.paths import ROOT
from hsltools.probes._base import ProbeTask
from hsltools.probes.status_roll import independent
from hsltools.sources.tables import TABLES, blocks, digest

PACKET = ROOT / 'docs/evidence_packets/static_reverse/original_stat_magic.json'

ANCHOR_SHA='c0f18b4b0e27e92262dd052bb8c012c09277f3de455b2284d34b8df4513c9dc1'
WORDS={'poison':(0x30,1),'no_magic':(0x34,2),'paralysis':(0x3c,4),'attack_up':(0x40,0x10),'defense_up':(0x44,0x20)}
SPELLS={'defense_up':('magicEARTH','magicCode06',0,5,0x20),'attack_up':('magicFIRE','magicCode05',3,4,0x40),'dispel':('magicMIND','magicCode06',4,5,0x4000)}
ANCHORS=[(0x40b01c,246,'Defense enhancement consumes proc1, duration rand4+2, proc3 magnitude12..100; merges and refreshes.'),
         (0x40b112,262,'Attack enhancement consumes proc3, duration rand4+2 and proc3 magnitude16..96; adds duration contribution.'),
         (0x40b299,114,'Dispel clears attack/defense only, refreshes and contributes12 times removed durations plus one per effect.'),
         (0x44b5bf,31,'Current attack+defense receive signed high-word flat bonuses before equipment application.'),
         (0x40b910,258,'Complete original duration function decrements counters and clears expired flags/words.'),
         (0x440eb5,60,'ai_help_attack is a separate attempted bit10 and mode6 gate after healing/status help.'),
         (0x40c2d0,29,'Enhancement scan reads only positive combat-state bits70.'),
         (0x40dcf0,143,'Magic buff usefulness ignores a candidate whose matching positive state is already present.')]


def fields(kind):
    typ,code,*_=SPELLS[kind]
    return next(r for r in blocks((TABLES/'MAGIC.TXT').read_bytes(),'magic') if r['type']==typ and r['code']==code)


def flags(words):return sum(bit for key,(_,bit) in WORDS.items() if words.get(key,0))


def initial_words():return dict(poison=0x70003,no_magic=2,paralysis=2,attack_up=0,defense_up=0)


def fixtures():
    rows=[]
    for kind in ['attack_up','defense_up']:
        for old in [0,(25<<16)|2,(70<<16)|8,(96 if kind=='attack_up' else 100)<<16|9]:
            for seed in [1,7,19]:
                words=initial_words();words[kind]=old
                for hit in [0,100]:rows.append(dict(kind=kind,words=words,seed=seed,hit=hit,hit_bonus=0,magic_hit_bonus=0,
                                                 actor='002',level=5,hp=20,mp=5,low=None,high=None,no_attack=False))
        for low,high in [(1,1),(200,200)]:
            rows.append(dict(rows[-1],words=initial_words(),hit=100,low=low,high=high))
    for a in [0,0x190002,0x600009]:
        for d in [0,0x200003,0x640009]:
            rows.append(dict(kind='dispel',words=dict(initial_words(),attack_up=a,defense_up=d),
                             seed=7,hit=100,hit_bonus=7,magic_hit_bonus=0,actor='002',level=5,hp=20,mp=5,low=None,high=None,no_attack=False))
    return rows


def model(case,draws):
    source=fields(case['kind']);low,high=map(int,source['damage'].split(','))
    if case['low'] is not None:low,high=case['low'],case['high']
    words=dict(case['words']);cursor=0;bonus=case['hit_bonus']
    def take(bound):
        nonlocal cursor
        if cursor>=len(draws) or draws[cursor]['bound']!=bound:raise ValueError('Stat spell random-call order differs')
        value=draws[cursor]['value'];cursor+=1
        if not 0<=value<bound:raise ValueError('Stat spell random range differs')
        return value
    def roll(proc):
        nonlocal cursor,bonus
        count=3 if case['no_attack'] or draws[cursor]['value']+1<=case['hit']+bonus+case['magic_hit_bonus'] else 1
        value=independent(dict(proc=proc,channel=0,low=low,high=high,hit_ratio=case['hit'],status_hit_ratio=0,
                               hit_bonus=bonus,magic_hit_bonus=case['magic_hit_bonus'],no_attack=case['no_attack'],
                               level=3,mind=15,magic_attack=40,resistance=80),draws[cursor:cursor+count])
        cursor+=count;bonus=value['hit_bonus_after'];return value['value']
    contribution=0
    if case['hp']>0:
        if case['kind']=='dispel':
            contribution=12*sum((words[k]&65535)+1 for k in ['attack_up','defense_up'] if words[k])
            words['attack_up']=0;words['defense_up']=0
        else:
            kind=case['kind'];roll(1 if kind=='defense_up' else 3)
            duration=take(4)+2;power=roll(3)
            if kind=='defense_up':
                if power>100:power-=10*((power-91)//10)
                if power<12:power+=12*((23-power)//12)
            else:
                if power>96:power-=8*((power-89)//8)
                if power<16:power+=16*((31-power)//16)
            old=words[kind];oldpower=old>>16
            power=max(oldpower,(oldpower+power)//2) if oldpower else power
            turns=min(9,(old&65535)+duration);words[kind]=power<<16|turns
            contribution=(turns-(old&65535))*2
    if cursor!=len(draws):raise ValueError('Stat spell has unexplained random draws')
    return dict(words=words,flags=flags(words),contribution=contribution,hit_bonus=bonus)


def put_actor(m,at,code,level,hp,mp,gear,words):
    players,items,defines=sources();row=players[code];profile=source_profile(row,defines)
    def put(off,value):m.mem_write(at+off,struct.pack('<I',value&0xffffffff))
    for key,off in zip(ATTRIBUTES,[0x64,0x68,0x6c,0x70]):put(off,int(row[key]))
    for key,off in [('attack_power',0x1a4),('magic_attack_power',0x1a8),('defense',0x1ac),('speed',0x1b0),
                    ('avoid_hit_ratio',0x198),('attack_back',0x19c),('attack_damagex2',0x1a0)]:put(off,profile['source'][key])
    for off,value in [(0x18,profile['job_code']),(0x28,profile['source']['mode']),(0x9c,level),(0xd8,hp),(0xe0,mp),
                      (0x130,int(row['move_point'])),(0x1b4,int(row.get('hit_point',0))<<16|int(row.get('magic_point',0))),
                      (0x174,1 if profile['source']['has_magic'] else 0),(0x88,37),(0xe8,20),(0x24,flags(words))]:put(off,value)
    for index in range(5):put(0x118+4*index,profile['source']['base_resist_by_type'][str(index)])
    for key,(off,_) in WORDS.items():put(off,words.get(key,0))
    m.mem_write(0x4c1b40,struct.pack('<I',0x20000000))
    for index,code in enumerate(gear):
        put(0xec+index*4,code)
        if not code:continue
        item=items[code];dest=0x20000000+176*code
        def itemput(off,value):m.mem_write(dest+off,struct.pack('<I',value&0xffffffff))
        itemput(8,defines[item['type']]);itemput(0x10,-1);itemput(0x8c,-1)
        if 'add_resist' in item:
            kind,amount=map(str.strip,item['add_resist'].split(','));itemput(0x10,defines[kind]);itemput(0x14,int(amount))
        for key,off in [('attack_damage',0x88),('hit_ratio',0x98),('add_weapon_hit',0x18),('add_attack_power',0x20),
                        ('add_magic_power',0x24),('add_mp',0x28),('add_hp',0x2c),('add_move',0x34),('add_speed',0x38),
                        ('add_defense',0x3c),('add_miss_hit',0x44),('add_attack_back',0x48),('add_weapon_dmgx2',0x4c)]:itemput(off,int(item.get(key,0)))
    base=calculate(profile,{key:int(row[key]) for key in ATTRIBUTES},level,gear,catalog()['items'],hp,mp,int(row['move_point']))
    return base


def machine(base,mapped):
    m=machine_for(base,mapped);m.mem_map(0x20000000,0x20000);return m


def execute(base,mapped,case):
    from unicorn import UC_HOOK_CODE
    from unicorn.x86_const import UC_X86_REG_EAX,UC_X86_REG_EIP,UC_X86_REG_ESP
    m=machine(base,mapped);owner,target,actors,record,table,stack,stop=0x10001000,0x10002000,0x10004000,0x10008000,0x10009000,0x1001ff00,0x10000000
    victim=actors+0x1fc
    def put(at,value):m.mem_write(at,struct.pack('<I',value&0xffffffff))
    def get(at):return struct.unpack('<I',m.mem_read(at,4))[0]
    put(0x4c1bc8,actors);put(owner+0xa4,0);put(target+0xa4,1)
    for off,value in [(0x9c,3),(0x54,15),(0xd0,40),(0xb0,case['hit_bonus']),(0xd4,case['magic_hit_bonus'])]:put(actors+off,value)
    players,_,_=sources();row=players[case['actor']];gear=[int(row.get(k,0)) for k in SLOTS]
    numeric=put_actor(m,victim,case['actor'],case['level'],case['hp'],case['mp'],gear,case['words'])
    source=fields(case['kind']);_,_,element,index,mask=SPELLS[case['kind']];low,high=map(int,source['damage'].split(','))
    if case['low'] is not None:low,high=case['low'],case['high']
    for off,value in [(4,element),(0x14,low),(0x18,high),(0x1c,case['hit']),(0x24,mask)]:put(record+off,value)
    put(victim+0xa0,2 if case['no_attack'] else 0)
    put(0x4c2ca0+4*element,table);put(table+4*index,record)
    put(0x4c1e8c,1);put(0x4c3044,case['seed']);put(0x4c3040,0x87654321)
    draws=[];pending=[];steps=0;refresh_returns=0
    allowed=[(0x40aa80,0x40b831),(0x409850,0x40986c),(0x40a7b0,0x40aa6b),(0x406fe0,0x407010),
             (0x42c780,0x42c7d9),(0x458bb0,0x458cb3),(0x448370,0x44b820)]
    def guard(_m,at,_size,_data):
        nonlocal steps,refresh_returns
        steps+=1
        if not any(a<=at<b for a,b in allowed):raise ValueError(f'Unreviewed stat spell callee {at:#x}')
        if at in [0x40b0eb,0x40b1ef,0x40b30d]:refresh_returns+=1
        if pending and pending[-1][0]==at:
            _,bound=pending.pop();draws.append(dict(bound=bound,value=m.reg_read(UC_X86_REG_EAX)))
        if at==0x42c780:
            esp=m.reg_read(UC_X86_REG_ESP);pending.append((get(esp),get(esp+4)))
    m.hook_add(UC_HOOK_CODE,guard);m.mem_write(stack,struct.pack('<6I',stop,owner,target,element,index,0));m.reg_write(UC_X86_REG_ESP,stack)
    m.emu_start(0x40aa80,0x40b831,count=18000)
    if m.reg_read(UC_X86_REG_EIP)!=0x40b831 or pending:raise ValueError('Stat spell missed prefix boundary')
    actual=dict(words={k:get(victim+off) for k,(off,_) in WORDS.items()},flags=get(victim+0x24),contribution=get(0x4c13fc),hit_bonus=get(actors+0xb0))
    wanted=model(case,draws)
    if actual!=wanted:raise ValueError(f'Stat spell mismatch {case}: {actual} != {wanted}')
    values={k:get(victim+off) for k,off in [('attack',0xc0),('defense',0xb4),('max_hp',0xdc),('max_mp',0xe4),('move_point',0x12c),('speed',0xb8)]}
    numeric['attack']+=wanted['words']['attack_up']>>16;numeric['defense']+=wanted['words']['defense_up']>>16
    if case['hp']>0 and values!={k:numeric[k] for k in values}:raise ValueError(f'Full source refresh differs {case}: {values} != {numeric}')
    if get(victim+0x88)!=37 or get(victim+0xe8)!=20:raise ValueError('Buff application changed finalEXP/stamina')
    return dict(input=case,native=actual,derived=values,draws=draws,instructions=steps,normal_return=False,stop_address='0x40b831')


def refresh_fixtures():
    return [dict(actor=code,level=level,equipped=equipped,attack_up=a,defense_up=d)
            for code in ['001','002','026','024'] for level in [1,20] for equipped in [False,True]
            for a,d in [(0,0),(16<<16|2,0),(0,100<<16|1),(70<<16|9,40<<16|3)]]


def execute_refresh(base,mapped,case):
    from unicorn import UC_HOOK_CODE
    from unicorn.x86_const import UC_X86_REG_EIP,UC_X86_REG_ESP
    m=machine(base,mapped);at,stack,stop=0x10004000,0x1001ff00,0x10000000
    players,_,_=sources();row=players[case['actor']]
    gear=[int(row.get(k,0)) for k in SLOTS] if case['equipped'] else [0]*6
    words=dict(attack_up=case['attack_up'],defense_up=case['defense_up'])
    wanted=put_actor(m,at,case['actor'],case['level'],1,0,gear,words)
    wanted['attack']+=case['attack_up']>>16;wanted['defense']+=case['defense_up']>>16
    steps=0
    def guard(_m,pc,_size,_data):
        nonlocal steps
        steps+=1
        if not 0x448370<=pc<0x44b820:raise ValueError(f'Unexpected stat refresh {pc:#x}')
    m.hook_add(UC_HOOK_CODE,guard);results=[]
    for repeat in range(2):
        for off in [0xb4,0xc0,0x12c]:m.mem_write(at+off,struct.pack('<I',999))
        prior=steps;m.mem_write(stack,struct.pack('<2I',stop,at));m.reg_write(UC_X86_REG_ESP,stack);m.emu_start(0x448840,stop,count=14000)
        if m.reg_read(UC_X86_REG_EIP)!=stop or m.reg_read(UC_X86_REG_ESP)!=stack+4:raise ValueError('Buff refresh did not return')
        values={k:struct.unpack('<I',m.mem_read(at+off,4))[0] for k,off in [('attack',0xc0),('defense',0xb4),('max_hp',0xdc),('max_mp',0xe4),('move_point',0x12c),('speed',0xb8),('magic_attack',0xd0)]}
        if values!={k:wanted[k] for k in values}:raise ValueError('Flat stat enhancement source mismatch')
        results.append(dict(values=values,instructions=steps-prior,normal_return=True))
    return dict(input=case,native=results)


def tick_fixtures():
    return [dict(initial_words(),attack_up=(20<<16|a) if a else 0,defense_up=(35<<16|d) if d else 0) for a in [0,1,2,9] for d in [0,1,3,9]]


def execute_tick(base,mapped,words):
    from unicorn import UC_HOOK_CODE
    from unicorn.x86_const import UC_X86_REG_EIP,UC_X86_REG_ESP
    m=machine(base,mapped);obj,actor,stack,stop=0x10001000,0x10004000,0x1001ff00,0x10000000
    def put(at,v):m.mem_write(at,struct.pack('<I',v))
    put(0x4c1bc8,actor);put(obj+0xa4,0);put(actor+0x24,flags(words))
    players,_,_=sources()
    numeric=put_actor(m,actor,'002',3,10,5,[int(players['002'].get(k,0)) for k in SLOTS],words)
    put(actor+0xc0,numeric['attack']+(words['attack_up']>>16))
    put(actor+0xb4,numeric['defense']+(words['defense_up']>>16))
    for key,(off,_) in WORDS.items():put(actor+off,words[key])
    steps=0
    def guard(_m,pc,_size,_data):
        nonlocal steps
        steps+=1
        if not (0x40b910<=pc<0x40ba12 or 0x448370<=pc<0x44b820):raise ValueError(f'Buff tick entered an unreviewed callee {pc:#x}')
    m.hook_add(UC_HOOK_CODE,guard);m.mem_write(stack,struct.pack('<2I',stop,obj));m.reg_write(UC_X86_REG_ESP,stack);m.emu_start(0x40b910,stop,count=18000)
    if m.reg_read(UC_X86_REG_EIP)!=stop or m.reg_read(UC_X86_REG_ESP)!=stack+4:raise ValueError('Buff duration did not return')
    after={k:struct.unpack('<I',m.mem_read(actor+off,4))[0] for k,(off,_) in WORDS.items()}
    wanted={k:(w-1 if w&65535>1 else 0) for k,w in words.items()}
    if after!=wanted or struct.unpack('<I',m.mem_read(actor+0x24,4))[0]!=flags(after):raise ValueError('Buff duration/expiry mismatch')
    derived={key:struct.unpack('<I',m.mem_read(actor+off,4))[0] for key,off in [('attack',0xc0),('defense',0xb4)]}
    if derived!={'attack':numeric['attack']+(after['attack_up']>>16),'defense':numeric['defense']+(after['defense_up']>>16)}:raise ValueError('Expired buff did not refresh source derived values')
    return dict(input=words,native=after,derived=derived,normal_return=True,instructions=steps)


def check(packet):
    if packet.get('schema')!='hsl_stat_magic_native.v1' or packet.get('exe_sha256')!=EXE_SHA or packet.get('native_execution') is not True:raise ValueError('Stat magic native identity missing')
    if packet['sources']!={n:digest((TABLES/n).read_bytes()) for n in ['MAGIC.TXT','PLAYERS.TXT','ITEM.TXT','TYPE.H']}:raise ValueError('Stat magic source mismatch')
    if [r['input'] for r in packet['applications']]!=fixtures() or [r['input'] for r in packet['refresh']]!=refresh_fixtures() or [r['input'] for r in packet['ticks']]!=tick_fixtures():raise ValueError('Stat magic case coverage differs')
    for row in packet['applications']:
        if row['native']!=model(row['input'],row['draws']) or row['normal_return'] is not False or row['stop_address']!='0x40b831' or not 0<row['instructions']<18000:raise ValueError('Stat application differs')
    players,_,defines=sources();items=catalog()['items']
    for row in packet['applications']:
        c=row['input'];src=players[c['actor']];gear=[int(src.get(k,0)) for k in SLOTS]
        v=calculate(source_profile(src,defines),{k:int(src[k]) for k in ATTRIBUTES},c['level'],gear,items,c['hp'],c['mp'],int(src['move_point']))
        v['attack']+=row['native']['words']['attack_up']>>16;v['defense']+=row['native']['words']['defense_up']>>16
        if row['derived']!={k:v[k] for k in row['derived']}:raise ValueError('Application refresh evidence differs')
    for row in packet['refresh']:
        c=row['input'];src=players[c['actor']];gear=[int(src.get(k,0)) for k in SLOTS] if c['equipped'] else [0]*6
        v=calculate(source_profile(src,defines),{k:int(src[k]) for k in ATTRIBUTES},c['level'],gear,items,1,0,int(src['move_point']))
        v['attack']+=c['attack_up']>>16;v['defense']+=c['defense_up']>>16
        if len(row['native'])!=2 or any(r['values']!={k:v[k] for k in r['values']} or r['normal_return'] is not True or not 0<r['instructions']<14000 for r in row['native']):raise ValueError('Full stat refresh differs')
    for row in packet['ticks']:
        if row['native']!={k:(w-1 if w&65535>1 else 0) for k,w in row['input'].items()} or not row['normal_return'] or not 0<row['instructions']<18000:raise ValueError('Stat duration differs')
        src=players['002'];gear=[int(src.get(k,0)) for k in SLOTS]
        v=calculate(source_profile(src,defines),{k:int(src[k]) for k in ATTRIBUTES},3,gear,items,10,5,int(src['move_point']))
        if row['derived']!={'attack':v['attack']+(row['native']['attack_up']>>16),'defense':v['defense']+(row['native']['defense_up']>>16)}:raise ValueError('Expiry refresh evidence differs')
    if [(int(r['address'],16),len(bytes.fromhex(r['bytes'])),r['meaning']) for r in packet['anchors']]!=ANCHORS:raise ValueError('Stat magic instruction anchors differ')
    if hashlib.sha256(bytes.fromhex(''.join(r['bytes'] for r in packet['anchors']))).hexdigest()!=ANCHOR_SHA:raise ValueError('Stat magic original instruction bytes differ')


def execute_packet(exe: Path) -> dict:
    """Run the bounded original instructions on the documented EXE and assemble the packet."""
    base,mapped=image(exe.read_bytes())
    packet=dict(schema='hsl_stat_magic_native.v1',exe_sha256=EXE_SHA,evidence_tier='static-derived',native_execution=True,
                sources={n:digest((TABLES/n).read_bytes()) for n in ['MAGIC.TXT','PLAYERS.TXT','ITEM.TXT','TYPE.H']},
                applications=[execute(base,mapped,c) for c in fixtures()],refresh=[execute_refresh(base,mapped,c) for c in refresh_fixtures()],
                ticks=[execute_tick(base,mapped,c) for c in tick_fixtures()],
                anchors=[dict(address=hex(at),bytes=bytes(mapped[at-base:at-base+n]).hex(),meaning=meaning) for at,n,meaning in ANCHORS],
                limits=['Application stops before EXP conversion/display but executes original full stat refresh. Only the four proven jobs are exercised.',
                        'Dispel clears attack/defense enhancements only; other positive or negative states are preserved.',
                        'Duration helper refreshes after each expired enhancement; the full return restores source derived values.',
                        'Original full dispatcher/global RNG/frame timing and learning are separate.'])
    return packet


def summary_line(packet: dict, executed_now: bool) -> str:
    return ' '.join(str(part) for part in ('STAT_MAGIC_NATIVE_PASS applications=', len(packet['applications']), 'refresh_returns=', 2*len(packet['refresh']), 'tick_returns=', len(packet['ticks']), 'executed_now=', executed_now, 'anchors_sha=', hashlib.sha256(bytes.fromhex(''.join(r['bytes'] for r in packet['anchors']))).hexdigest()))


TASK = ProbeTask('stat_magic', PACKET, check, execute_packet, summary_line)


def tasks() -> list[ProbeTask]:
    return [TASK]
