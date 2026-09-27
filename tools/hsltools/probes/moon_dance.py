"""Execute Moon Dance's original special applicator and bounded receiver stages.

The direct 0x40b8f0 call returns normally. Actual opcode17 dispatch stops before
the first presentation call. No original instruction or callee is replaced.

Registry task moon_dance (family probe, hsltools.probes._base.ProbeTask): check validates the
tracked packet against the independent model; generate executes the original instructions
(needs the documented hsl01.exe and unicorn). Bodies moved verbatim from the former hsl_native_moon_dance_probe.py.
"""
from __future__ import annotations
import hashlib
import json
from pathlib import Path
import struct

from hsltools.native.image import EXE_SHA, image
from hsltools.native.machine import machine_for
from hsltools.paths import ROOT
from hsltools.probes._base import ProbeTask
from hsltools.probes.experience import expected as exp_expected
from hsltools.probes.special_damage import expected as damage_expected
from hsltools.sources.tables import TABLES, blocks, digest

PACKET = ROOT / 'docs/evidence_packets/static_reverse/original_moon_dance.json'

EFFECTS = ROOT/'content/imported/hsl/shared/first_skill/effects.txt'
ANCHORS = [
    (0x403968,33,'Receiver decodes the actual effect opcode through its two-stage table.'),
    (0x404ee8,92,'Receiver opcode dispatch targets.'),
    (0x404f48,36,'Receiver opcode17 maps to the direct hit path; opcode18 is separate.'),
    (0x4047e9,202,'Direct hit callback calls special applicator and accumulates EXP and actual HP/MP deltas.'),
    (0x40b8f0,31,'Special wrapper selects channel1; full application returns without a number renderer.'),
    (0x403d3d,126,'After the current effect program finishes, advance to the next cached unique target and restart the defense program.'),
    (0x445290,37,'Special cost is paid once before creating the attacking animation.'),
    (0x445305,35,'Only after receiver completion does the actor enter the defeated-target scan.'),
    (0x4453a9,58,'Deferred death scan counts each death but increments the kill chain only on the first.'),
    (0x445424,60,'Death scan advances targets without repeating the already-finished damage program.'),
]


def source_fields() -> dict:
    return next(row for row in blocks((TABLES/'SPECIAL.TXT').read_bytes(),'special')
                if row['type']=='magicOTHER' and row['code']=='magicCode06')


def source_hashes() -> dict:
    return {'SPECIAL.TXT':digest((TABLES/'SPECIAL.TXT').read_bytes()),
            'ANIMAL.H':digest((TABLES/'ANIMAL.H').read_bytes()),'EFFECT.TXT':digest(EFFECTS.read_bytes())}


def fixtures() -> list[dict]:
    base = dict(level=1,target_level=1,dex=11,mind=15,con=15,kill_exp=30,kill_word=0)
    rows = [dict(base,hp=hp,seed=seed,hit=hit,callback=callback)
            for hp in [0,1,10,30,100] for seed in [1,7,19] for hit in [0,98]
            for callback in [False,True]]
    for level,target_level,word in [(1,8,3),(8,1,8),(120,120,0x10003)]:
        rows.append(dict(base,level=level,target_level=target_level,kill_word=word,
                         hp=20,seed=7,hit=98,callback=True))
    return rows


def expected(case: dict, hp: int, bonus: int, draws: list[dict]) -> dict:
    fields = source_fields(); low,high=map(int,fields['damage'].split(','))
    roll = damage_expected(dict(low=low,high=high,hit_ratio=case['hit'],
                                attackpow_ratio=int(fields['attackpow_ratio']),hit_bonus=bonus,
                                level=case['level'],dex=case['dex'],mind=case['mind'],con=case['con'],no_attack=False),
                           [d for d in draws if d['stage']=='damage'])
    loss = min(hp,roll['value']); after=hp-loss
    xp = exp_expected(dict(contribution=loss,attacker_level=case['level'],target_level=case['target_level'],
                           target_hp=after,kill_exp=case['kill_exp'],kill_word=case['kill_word']),
                      [d for d in draws if d['stage']=='experience'])
    return dict(hp=after,contribution=loss,hit_bonus=roll['hit_bonus_after'],experience=xp,raw_damage=roll['value'])


def execute(base: int, mapped: bytearray, case: dict) -> dict:
    from unicorn import UC_HOOK_CODE
    from unicorn.x86_const import UC_X86_REG_EAX,UC_X86_REG_EDI,UC_X86_REG_ESI,UC_X86_REG_EIP,UC_X86_REG_ESP
    m=machine_for(base,mapped)
    owner,target,obj,actors,record,table,program= [0x10001000+i*0x1000 for i in range(7)]
    stack,stop=0x1001ff00,0x10000000; victim=actors+0x1fc
    fields=source_fields();low,high=map(int,fields['damage'].split(','))
    def put(at,value):m.mem_write(at,struct.pack('<I',value&0xffffffff))
    def get(at):return struct.unpack('<I',m.mem_read(at,4))[0]
    put(0x4c1bc8,actors);put(owner+0xa4,0);put(target+0xa4,1)
    for off,key in [(0x9c,'level'),(0x50,'dex'),(0x54,'mind'),(0x58,'con'),(0xa8,'kill_word')]:put(actors+off,case[key])
    put(actors+0xe8,60)
    for off,key in [(0xd8,'hp'),(0x9c,'target_level'),(0x90,'kill_exp')]:put(victim+off,case[key])
    for off,value in [(4,5),(0x14,low),(0x18,high),(0x1c,case['hit']),(0x28,1),(0x2c,int(fields['attackpow_ratio']))]:put(record+off,value)
    put(0x4c3920+20,table);put(table+20,record)
    put(0x4c1e8c,1);put(0x4c3044,case['seed']);put(0x4c3040,0x87654321)
    put(obj+0xa8,owner);put(obj+0xac,target);put(0x4c2c44,5);put(0x4c2c94,5);put(program,17)
    pending=[];draws=[];stage='damage';steps=0
    allowed=[(0x40a5d0,0x40a78d),(0x40a7b0,0x40aa6b),(0x40aa80,0x40b910),
             (0x409870,0x409890),(0x42c780,0x42c7d9),(0x458bb0,0x458cb3),
             (0x403968,0x403989),(0x4047e9,0x4048b3)]
    def guard(_m,at,_size,_data):
        nonlocal steps,stage
        if case['callback'] and at==0x4048b3:m.emu_stop();return
        steps+=1
        if not any(lo<=at<hi for lo,hi in allowed):raise ValueError(f'Unreviewed Moon callee {at:#x}')
        if at==0x40a7b0:stage='damage'
        elif at==0x40a5d0:stage='experience'
        if pending and pending[-1][0]==at:
            _,bound,part=pending.pop();draws.append(dict(bound=bound,value=m.reg_read(UC_X86_REG_EAX),stage=part))
        if at==0x42c780:
            esp=m.reg_read(UC_X86_REG_ESP);pending.append((get(esp),get(esp+4),stage))
    m.hook_add(UC_HOOK_CODE,guard)
    results=[];total=0
    for pulse in range(5):
        hp,bonus=get(victim+0xd8),get(actors+0xb0);draws.clear();prior=steps
        native_total_before=get(0x4c13f0)
        if case['callback']:
            m.reg_write(UC_X86_REG_EDI,obj);m.reg_write(UC_X86_REG_ESI,program);entry=0x403968
        else:
            m.mem_write(stack,struct.pack('<5I',stop,owner,target,5,5));entry=0x40b8f0
        m.reg_write(UC_X86_REG_ESP,stack);m.emu_start(entry,stop,count=8192)
        end=m.reg_read(UC_X86_REG_EIP);normal=not case['callback']
        if end!=(stop if normal else 0x4048b3) or pending or (normal and m.reg_read(UC_X86_REG_ESP)!=stack+4):
            raise ValueError('Moon applicator return or callback boundary differs')
        predicted=expected(case,hp,bonus,draws);total+=predicted['experience']
        actual=dict(hp=get(victim+0xd8),contribution=get(0x4c13fc),hit_bonus=get(actors+0xb0),
                    experience=(get(0x4c13f0)-native_total_before) if case['callback'] else m.reg_read(UC_X86_REG_EAX))
        if actual!={k:predicted[k] for k in actual}:raise ValueError(f'Moon application mismatch: {case} {actual} {predicted}')
        if case['callback'] and (get(0x4c2c7c)!=total or get(0x4c13f0)!=total or get(0x4c6f74)!=predicted['contribution'] or m.reg_read(UC_X86_REG_ESI)!=program+4):
            raise ValueError('Moon opcode cursor or final accumulator differs')
        if get(actors+0x88)!=0 or get(actors+0xe8)!=60 or get(actors+0xa8)!=case['kill_word']:
            raise ValueError('Per-hit callback mutated final EXP, cost or deferred kill chain')
        results.append(dict(pulse=pulse+1,before=hp,bonus_before=bonus,native=actual,draws=list(draws),
                            accumulated_experience=total,instructions=steps-prior,normal_return=normal,stop_address=hex(end)))
    return dict(input=case,results=results)


def suffix_fixtures() -> list[dict]:
    return ([dict(kind='cost',stamina=n) for n in [20,40,60]] +
            [dict(kind='next_target',cursor=n) for n in [1,2]] +
            [dict(kind='kills',word=word,count=count) for word in [0,3,0x10003] for count in [1,2,3]])


def suffix_expected(case: dict) -> dict:
    if case['kind']=='cost':return dict(stamina=case['stamina']-20)
    if case['kind']=='next_target':
        return dict(target=1 if case['cursor']==1 else -1,cursor=2,
                    stage=100 if case['cursor']==1 else 0x650000,
                    restarted=case['cursor']==1)
    return dict(kill_count=case['count'],kill_word=(case['word']|0x10000)+1)


def execute_suffix(base: int, mapped: bytearray, case: dict) -> dict:
    from unicorn import UC_HOOK_CODE
    from unicorn.x86_const import UC_X86_REG_EAX,UC_X86_REG_EBX,UC_X86_REG_EDI,UC_X86_REG_ESI,UC_X86_REG_EIP,UC_X86_REG_ESP
    m=machine_for(base,mapped)
    owner,actor,receiver,table,record,program,targets,special_table= [0x10001000+i*0x1000 for i in range(8)]
    stack=0x1001fe00
    def put(at,value):m.mem_write(at,struct.pack('<I',value&0xffffffff))
    def get(at):return struct.unpack('<I',m.mem_read(at,4))[0]
    put(0x4c3920+20,special_table);put(special_table+20,record)
    put(record+0x10,1);put(record+0x24,20)
    put(0x4c1b70,table);put(table+20*4,program);put(program,1)
    put(0x4c2c44,5);put(0x4c2c94,5)
    kind=case['kind'];steps=0
    if kind=='cost':
        put(actor+0xe8,case['stamina']);entry,stops=0x445290,[0x4452b5]
        allowed=[(entry,stops[0]),(0x409980,0x4099a2)]
        m.reg_write(UC_X86_REG_EDI,actor);m.reg_write(UC_X86_REG_ESI,owner)
    elif kind=='next_target':
        put(0x4c1b88,targets);put(targets,owner);put(targets+4,owner+0x200)
        put(0x4c1a50,2);put(0x4c1a54,case['cursor'])
        put(receiver+0xac,owner);entry,stops=0x403d3d,[0x404ba6]
        allowed=[(entry,0x403dbb),(0x4104d0,0x4105f9),(0x409a20,0x409a51)]
        m.reg_write(UC_X86_REG_EDI,receiver);m.reg_write(UC_X86_REG_ESI,program+128)
    else:
        put(actor+0xa8,case['word']);entry,stops=0x4453a9,[0x4453e3,0x4453f6]
        allowed=[(entry,0x4453e3)]
        m.reg_write(UC_X86_REG_EDI,actor);m.reg_write(UC_X86_REG_EBX,0x10000)
    def guard(_m,at,_size,_data):
        nonlocal steps
        if at in stops:m.emu_stop();return
        steps+=1
        if not any(lo<=at<hi for lo,hi in allowed):raise ValueError(f'Unreviewed Moon suffix {at:#x}')
    m.hook_add(UC_HOOK_CODE,guard)
    for _repeat in range(case.get('count',1)):
        m.reg_write(UC_X86_REG_ESP,stack)
        if kind=='kills':m.reg_write(UC_X86_REG_EAX,0)
        m.emu_start(entry,0x10000000,count=2048)
        if m.reg_read(UC_X86_REG_EIP) not in stops:raise ValueError('Moon suffix missed declared stop')
    if kind=='cost':actual=dict(stamina=get(actor+0xe8))
    elif kind=='next_target':
        current=get(0x4c1cec)
        actual=dict(target=1 if current==owner+0x200 else -1,cursor=get(0x4c1a54),
                    stage=get(receiver+0x8c),restarted=get(0x4c1408)==program)
    else:actual=dict(kill_count=get(actor+0x94),kill_word=get(actor+0xa8))
    if actual!=suffix_expected(case):raise ValueError(f'Moon suffix mismatch {case}: {actual}')
    return dict(input=case,native=actual,normal_return=False,instructions=steps,
                entry=hex(entry),stop_address=hex(m.reg_read(UC_X86_REG_EIP)))


def check(packet: dict) -> None:
    if packet.get('schema')!='hsl_moon_dance_native.v1' or packet.get('exe_sha256')!=EXE_SHA or packet.get('native_execution') is not True:
        raise ValueError('Moon evidence identity missing')
    if packet['sources']!=source_hashes() or packet['fields']!=source_fields():raise ValueError('Moon source changed')
    if [row['input'] for row in packet['cases']]!=fixtures():raise ValueError('Moon coverage differs')
    for row in packet['cases']:
        case=row['input'];hp=case['hp'];bonus=0;total=0
        if len(row['results'])!=5:raise ValueError('Moon lost a receiver pulse')
        for pulse,result in enumerate(row['results'],1):
            value=expected(case,hp,bonus,result['draws']);total+=value['experience']
            if result['pulse']!=pulse or result['before']!=hp or result['bonus_before']!=bonus or result['native']!={k:value[k] for k in ['hp','contribution','hit_bonus','experience']}:
                raise ValueError('Moon hit/HP/experience differs')
            if result['accumulated_experience']!=total or result['normal_return']==case['callback'] or not 0<result['instructions']<8192 or result['stop_address']!=('0x4048b3' if case['callback'] else '0x10000000'):
                raise ValueError('Moon return or accumulator boundary differs')
            hp,bonus=value['hp'],value['hit_bonus']
    if [row['input'] for row in packet['suffixes']]!=suffix_fixtures():raise ValueError('Moon suffix coverage differs')
    for row in packet['suffixes']:
        case=row['input'];kind=case['kind']
        entry,stops={'cost':('0x445290',['0x4452b5']),
                     'next_target':('0x403d3d',['0x404ba6']),
                     'kills':('0x4453a9',['0x4453e3' if case.get('count')==1 else '0x4453f6'])}[kind]
        if row['native']!=suffix_expected(case) or row['normal_return'] is not False or row['entry']!=entry or row['stop_address'] not in stops or not 0<row['instructions']<6144:
            raise ValueError('Moon suffix boundary or result differs')
    if [(int(a['address'],16),len(bytes.fromhex(a['bytes'])),a['meaning']) for a in packet['anchors']]!=ANCHORS:
        raise ValueError('Moon original caller anchors differ')
    if hashlib.sha256(bytes.fromhex(''.join(a['bytes'] for a in packet['anchors']))).hexdigest()!='60fd76d7dd2d0f189e54c6f87df5d82fa1da498537fa193c005e8a7c34f43046':
        raise ValueError('Moon original instruction bytes differ')


def execute_packet(exe: Path) -> dict:
    """Run the bounded original instructions on the documented EXE and assemble the packet."""
    base,mapped=image(exe.read_bytes())
    packet=dict(schema='hsl_moon_dance_native.v1',exe_sha256=EXE_SHA,evidence_tier='static-derived',native_execution=True,
                sources=source_hashes(),fields=source_fields(),cases=[execute(base,mapped,c) for c in fixtures()],
                suffixes=[execute_suffix(base,mapped,c) for c in suffix_fixtures()],
                anchors=[dict(address=hex(at),bytes=bytes(mapped[at-base:at-base+length]).hex(),meaning=meaning) for at,length,meaning in ANCHORS],
                limits=['Direct special applicator returns normally; real opcode17 dispatch stops before its first presentation call.',
                        'Five source hit callbacks per unique target, then next receiver target. HP0 callbacks still sample but add no damage or experience.',
                        'Death scan follows all receiver programs: all pulses use the pre-cast kill chain; final chain increments once per action.',
                        'Synthetic register/map inputs; no original full renderer, global object scheduling or real-time playback equivalence.'])
    return packet


def summary_line(packet: dict, executed_now: bool) -> str:
    sha=hashlib.sha256(bytes.fromhex(''.join(a['bytes'] for a in packet['anchors']))).hexdigest()
    return f'MOON_DANCE_NATIVE_PASS cases={len(packet["cases"])} applications={len(packet["cases"])*5} suffixes={len(packet["suffixes"])} executed_now={executed_now} anchors_sha={sha}'


TASK = ProbeTask('moon_dance', PACKET, check, execute_packet, summary_line)


def tasks() -> list[ProbeTask]:
    return [TASK]
