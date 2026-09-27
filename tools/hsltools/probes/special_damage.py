"""Original Qi Blade numeric returns and capped-HP application prefixes.

Registry task special_damage (family probe, hsltools.probes._base.ProbeTask): check validates the
tracked packet against the independent model; generate executes the original instructions
(needs the documented hsl01.exe and unicorn). Bodies moved verbatim from the former hsl_native_special_damage_probe.py.
"""
from __future__ import annotations
import json
from pathlib import Path
import struct

from hsltools.native.image import EXE_SHA, image
from hsltools.paths import ROOT
from hsltools.probes._base import ProbeTask
from hsltools.sources.tables import TABLES, digest
from hsltools.data.first_skill import definition
PACKET = ROOT / 'docs/evidence_packets/static_reverse/original_special_damage.json'

def fixtures():
    fields=definition()['source_fields'];low,high=map(int,fields['damage'].split(','))
    template=dict(low=low,high=high,hit_ratio=int(fields['hit_ratio']),attackpow_ratio=int(fields['attackpow_ratio']),
                  hit_bonus=0,magic_hit_bonus=0,level=1,dex=16,mind=8,con=12,no_attack=False,defense=0,resistance=0)
    rows=[dict(template,seed=seed,level=level,dex=dex,mind=mind,con=con)
          for seed in [1,7,19] for level,dex,mind,con in [(1,16,8,12),(20,30,20,28),(120,99,99,99),(200,99,99,99)]]
    rows += [dict(template,seed=7,**changes) for changes in [dict(defense=500,resistance=80),dict(hit_ratio=0),
               dict(hit_ratio=0,magic_hit_bonus=100),dict(hit_ratio=0,hit_bonus=100),dict(hit_ratio=0,no_attack=True),
               dict(attackpow_ratio=50),dict(attackpow_ratio=0),dict(attackpow_ratio=200)]]
    # Elemental specials (SPECIAL type 0..4, e.g. magicAIR 天雷猛襲劍): channel1/proc0 reaches the
    # same resist_by_type switch as magic; type 5 (magicOTHER, the rows above) skips it.
    rows += [dict(template,seed=7,level=20,dex=30,mind=20,con=28,element=element,resistance=resistance)
             for element,resistance in [(2,0),(2,40),(2,80),(2,100),(3,25),(0,80),(4,40),(5,80)]]
    return rows


def applications():
    rows=fixtures()
    return [dict(rows[index],hp=hp) for index in [0,1,5,12,13,15,16,18] for hp in [1,20,1000]]


def expected(case,draws):
    cursor=0
    def draw(bound):
        nonlocal cursor
        if cursor>=len(draws) or draws[cursor]['bound']!=bound:raise ValueError('Special random-call order differs')
        value=draws[cursor]['value'];cursor+=1
        if not (value==0 if bound==0 else 0<=value<bound):raise ValueError('Special random outside bound')
        return value
    roll=draw(100)+1;bonus=case['hit_bonus'];hit=roll<=case['hit_ratio']+bonus or case['no_attack']
    value=0
    if not hit:bonus+=roll//10
    else:
        bonus=0;half=abs(case['high']-case['low'])//2
        sampled=max(case['low'],case['low']+half-draw(half+1)+draw(half+1))
        level=min(120,max(1,case['level']))
        value=sampled+draw(level*180//100)+draw(level*150//100)+case['con']//8+case['mind']//4+case['dex']//3
        value=value*case['attackpow_ratio']//100
        if value<3:value+=3*((5-value)//3)
        if case.get('element',5)<5 and case['resistance']!=0:value=(100-min(80,case['resistance']))*value//100
    if cursor!=len(draws):raise ValueError('Special has unused native random calls')
    result=dict(value=value,hit_bonus_after=bonus)
    if 'hp' in case:
        damage=min(case['hp'],value)
        result=dict(hp=case['hp']-damage,damage=damage,contribution=damage,hit_bonus_local=bonus)
    return result


def execute(base,mapped,case):
    from unicorn import Uc,UC_ARCH_X86,UC_MODE_32,UC_HOOK_CODE
    from unicorn.x86_const import UC_X86_REG_EAX,UC_X86_REG_EIP,UC_X86_REG_ESP
    m=Uc(UC_ARCH_X86,UC_MODE_32);m.mem_map(base,len(mapped));m.mem_write(base,bytes(mapped));m.mem_map(0x10000000,0x20000)
    obj,other,actor,target,record,table,bonus,stack,stop=0x10001000,0x10002000,0x10004000,0x100041fc,0x10008000,0x10009000,0x10009100,0x1001ff00,0x10000000
    def put(at,value):m.mem_write(at,struct.pack('<I',value&0xffffffff))
    def get(at):return struct.unpack('<I',m.mem_read(at,4))[0]
    put(0x4c1bc8,actor);put(obj+0xa4,0);put(other+0xa4,1)
    for offset,key in [(0x9c,'level'),(0x50,'dex'),(0x54,'mind'),(0x58,'con'),(0xb0,'hit_bonus'),(0xd4,'magic_hit_bonus')]:put(actor+offset,case[key])
    put(target+0xa0,2 if case['no_attack'] else 0);put(target+0xb4,case['defense']);put(target+0xd8,case.get('hp',1000))
    for index in range(5):put(target+0x104+index*4,case['resistance'])
    # SPECIAL stores its function at +0x28 (0x409870); MAGIC uses +0x24.
    put(record+4,case.get('element',5));put(record+0x28,1)
    for offset,key in [(0x14,'low'),(0x18,'high'),(0x1c,'hit_ratio'),(0x2c,'attackpow_ratio')]:put(record+offset,case[key])
    put(0x4c3920+5*4,table);put(table,record);put(bonus,case['hit_bonus'])
    put(0x4c1e8c,1);put(0x4c3044,case['seed']);put(0x4c3040,0x87654321)
    normal='hp' not in case;entry=0x40a7b0 if normal else 0x40aa80
    stops=[stop] if normal else [0x40ab87,0x40abb0]
    args=[actor,target,record,bonus,0,1] if normal else [obj,other,5,0,1]
    draws=[];pending=[];steps=0
    def guard(_m,address,_size,_data):
        nonlocal steps
        if not normal and address in stops:m.emu_stop();return
        steps+=1
        if not any(lo<=address<hi for lo,hi in [(0x40a7b0,0x40aa6b),(0x40aa80,0x40ab87),(0x409870,0x409890),
                                               (0x42c780,0x42c7d9),(0x458bb0,0x458cb3)]):raise ValueError(f'Unknown special callee {address:#x}')
        if pending and pending[-1][0]==address:
            _,bound=pending.pop();draws.append(dict(bound=bound,value=m.reg_read(UC_X86_REG_EAX)))
        if address==0x42c780:
            sp=m.reg_read(UC_X86_REG_ESP);pending.append((get(sp),get(sp+4)))
    before=bytes(m.mem_read(actor,0x400));m.hook_add(UC_HOOK_CODE,guard)
    m.mem_write(stack,struct.pack('<'+'I'*(len(args)+1),stop,*args));m.reg_write(UC_X86_REG_ESP,stack)
    m.emu_start(entry,stop,count=4096);end=m.reg_read(UC_X86_REG_EIP)
    if end not in stops or pending or normal and m.reg_read(UC_X86_REG_ESP)!=stack+4:raise ValueError('Special probe exceeded boundary')
    if normal:
        result=dict(value=m.reg_read(UC_X86_REG_EAX),hit_bonus_after=get(bonus))
        if before!=bytes(m.mem_read(actor,0x400)):raise ValueError('Special numeric helper changed an actor')
    else:result=dict(hp=get(target+0xd8),damage=get(0x4c13fc),contribution=get(0x4c13fc),hit_bonus_local=get(stack-28))
    if result!=expected(case,draws):raise ValueError(f'Special mismatch {case}: {result} expected={expected(case,draws)}')
    return dict(input=case,native=result,draws=draws,normal_return=normal,entry=hex(entry),stop_address=hex(end),instructions=steps)


def check(packet):
    if packet.get('schema')!='hsl_native_special_damage.v1' or packet.get('exe_sha256')!=EXE_SHA or packet.get('native_execution') is not True:raise ValueError('Invalid special identity')
    if packet['special_sha256']!=digest((TABLES/'SPECIAL.TXT').read_bytes()):raise ValueError('Special source changed')
    if [r['input'] for r in packet['rolls']]!=fixtures() or [r['input'] for r in packet['applications']]!=applications():raise ValueError('Special coverage differs')
    for row in packet['rolls']+packet['applications']:
        normal='hp' not in row['input']
        if row['normal_return'] is not normal or not 0<row['instructions']<4096 or row['native']!=expected(row['input'],row['draws']):raise ValueError('Special result or boundary differs')
        if row['stop_address'] not in (['0x10000000'] if normal else ['0x40ab87','0x40abb0']):raise ValueError('Invalid special stop')


def execute_packet(exe: Path) -> dict:
    """Run the bounded original instructions on the documented EXE and assemble the packet."""
    base,mapped=image(exe.read_bytes())
    packet=dict(schema='hsl_native_special_damage.v1',exe_sha256=EXE_SHA,evidence_tier='static-derived',native_execution=True,
                special_sha256=digest((TABLES/'SPECIAL.TXT').read_bytes()),rolls=[execute(base,mapped,c) for c in fixtures()],
                applications=[execute(base,mapped,c) for c in applications()],
                limits=['Numeric helper channel1/proc0 returns normally. HP application prefixes stop before display and EXP callbacks.',
                        'Qi Blade magicOTHER ignores elemental resistance and defense; source scale and level/DEX/MIND/CON branches are explicit.',
                        'Elemental special rows (element 0..4) multiply by (100-min(80,resist_by_type[element]))/100 after the low-value fold; magic power, magic-hit equipment and defense still do not enter.',
                        'Synthetic positive actor data; full native initialization, skill animation and global RNG identity not asserted.'])
    return packet


def summary_line(packet: dict, executed_now: bool) -> str:
    return f'SPECIAL_NATIVE_PASS rolls={len(packet["rolls"])} applications={len(packet["applications"])} executed_now={executed_now}'


TASK = ProbeTask('special_damage', PACKET, check, execute_packet, summary_line)


def tasks() -> list[ProbeTask]:
    return [TASK]
