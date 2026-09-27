"""Original Poison Arrow channel1 returns and complete HP/status application prefix.

The special channel bypasses the magic floating-number callback naturally. The
application runs unchanged to40b831, before final display/EXP, never past a stub.

Registry task poison_arrow (family probe, hsltools.probes._base.ProbeTask): check validates the
tracked packet against the independent model; generate executes the original instructions
(needs the documented hsl01.exe and unicorn). Bodies moved verbatim from the former hsl_native_poison_arrow_probe.py.
"""
from __future__ import annotations
import json
from pathlib import Path
import struct

from hsltools.native.image import EXE_SHA, image
from hsltools.paths import ROOT
from hsltools.probes._base import ProbeTask
from hsltools.sources.tables import TABLES, blocks, digest

PACKET = ROOT / 'docs/evidence_packets/static_reverse/original_poison_arrow.json'

ID='special:magicMIND:magicCode03'

def fields():
    return next(r for r in blocks((TABLES/'SPECIAL.TXT').read_bytes(),'special') if r['type']=='magicMIND' and r['code']=='magicCode03')

def fixtures():
    source=fields();low,high=map(int,source['damage'].split(','))
    base=dict(low=low,high=high,hit_ratio=int(source['hit_ratio']),attackpow_ratio=int(source['attackpow_ratio']),
              level=4,dex=16,mind=7,con=20,hit_bonus=0,magic_hit_bonus=0,no_attack=False,resistance=0,proc=0)
    rows=[dict(base,level=level,resistance=resist,seed=seed,proc=proc)
          for level in [4,20,120] for resist in [0,40,80] for seed in [1,19] for proc in [0,6]]
    rows += [dict(base,seed=7,proc=proc,**extra) for proc in [0,6] for extra in
             [dict(hit_ratio=0),dict(hit_ratio=0,hit_bonus=100),dict(hit_ratio=0,magic_hit_bonus=100),dict(hit_ratio=0,no_attack=True)]]
    return rows

def applications():
    base=fixtures()[0]
    return [dict(base,seed=seed,resistance=resist,hp=hp,effects=effects,poison=word,no_magic=2)
            for seed in [1,7,19] for resist in [0,80] for hp in [1,1000]
            for effects,word in [(0,0),(0,(25<<16)|2),(0,(50<<16)|9),(0x800000,0)]] + [
            dict(base,seed=7,hit_ratio=0,hp=1000,effects=0,poison=0,no_magic=2)]

def roll_model(c, draw, proc, bonus):
    hit=draw(100)+1
    if not c['no_attack'] and hit>c['hit_ratio']+bonus:
        return 0, bonus if proc&4 else bonus+hit//10
    if not proc&4:bonus=0
    half=(c['high']-c['low'])//2
    value=c['low']+half-draw(half+1)+draw(half+1)
    if not proc&2:
        level=min(120,max(1,c['level']))
        value=max(c['low'],value)+draw(level*180//100)+draw(level*150//100)+c['con']//8+c['mind']//4+c['dex']//3
        value=value*c['attackpow_ratio']//100
    if value<3:value+=3*((5-value)//3)
    if not proc&1:value=value*(100-min(80,c['resistance']))//100
    return value,bonus

def expected(c,draws):
    cursor=0
    def draw(bound):
        nonlocal cursor
        if cursor>=len(draws) or draws[cursor]['bound']!=bound:raise ValueError('Poison Arrow random order differs')
        value=draws[cursor]['value'];cursor+=1
        if not (value==0 if bound==0 else 0<=value<bound):raise ValueError('Poison Arrow draw outside bounds')
        return value
    value,bonus=roll_model(c,draw,c['proc'],c['hit_bonus'])
    if 'hp' not in c:result=dict(value=value,hit_bonus_after=bonus)
    else:
        damage=min(c['hp'],value);hp=c['hp']-damage;poison=c['poison'];contribution=damage
        if hp>0 and not c['effects']&(0x800000|0x80):
            success,bonus=roll_model(c,draw,6,bonus)
            if success:
                duration=2+draw(2);power,bonus=roll_model(c,draw,0,bonus)
                #40ada2 tests the saved Attack-function flag, not the hit outcome.
                power=power*30//100
                if power>50:power-=10*((power-41)//10)
                if power<5:power+=5*((9-power)//5)
                before=poison&0xffff;old=poison>>16
                turns=min(9,before+duration);power=max(old,(old+power)//2) if old else power
                poison=(power<<16)|turns;contribution+=(turns-before)*10
        result=dict(hp=hp,poison=poison,no_magic=c['no_magic'],status_flags=(1 if poison else 0)|(2 if c['no_magic'] else 0),
                    contribution=contribution,hit_bonus_after=bonus)
    if cursor!=len(draws):raise ValueError('Unused Poison Arrow random draws')
    return result

def execute(base,mapped,c):
    from unicorn import Uc,UC_ARCH_X86,UC_MODE_32,UC_HOOK_CODE
    from unicorn.x86_const import UC_X86_REG_EAX,UC_X86_REG_EIP,UC_X86_REG_ESP
    m=Uc(UC_ARCH_X86,UC_MODE_32);m.mem_map(base,len(mapped));m.mem_write(base,bytes(mapped));m.mem_map(0x10000000,0x20000)
    obj,other,actor,target,record,table,bonus,stack,stop=0x10001000,0x10002000,0x10004000,0x100041fc,0x10008000,0x10009000,0x10009100,0x1001ff00,0x10000000
    def put(at,v):m.mem_write(at,struct.pack('<I',v&0xffffffff))
    def get(at):return struct.unpack('<I',m.mem_read(at,4))[0]
    put(0x4c1bc8,actor);put(obj+0xa4,0);put(other+0xa4,1)
    for offset,key in [(0x9c,'level'),(0x50,'dex'),(0x54,'mind'),(0x58,'con'),(0xb0,'hit_bonus'),(0xd4,'magic_hit_bonus')]:put(actor+offset,c[key])
    put(target+0xa0,2 if c['no_attack'] else 0);put(target+0xd8,c.get('hp',1000));put(target+0x114,c['resistance']);put(target+0x18c,c.get('effects',0))
    put(target+0x30,c.get('poison',0));put(target+0x34,c.get('no_magic',0));put(target+0x24,(1 if c.get('poison',0) else 0)|(2 if c.get('no_magic',0) else 0))
    put(record+4,4);put(record+0x28,9)
    for offset,key in [(0x14,'low'),(0x18,'high'),(0x1c,'hit_ratio'),(0x2c,'attackpow_ratio')]:put(record+offset,c[key])
    put(0x4c3920+4*4,table);put(table+2*4,record);put(bonus,c['hit_bonus'])
    put(0x4c1e8c,1);put(0x4c3044,c['seed']);put(0x4c3040,0x87654321)
    normal='hp' not in c;entry=0x40a7b0 if normal else 0x40aa80;end=stop if normal else 0x40b831
    args=[actor,target,record,bonus,c['proc'],1] if normal else [obj,other,4,2,1]
    draws=[];pending=[];steps=0
    def guard(_m,at,_size,_data):
        nonlocal steps
        steps+=1
        if not any(lo<=at<hi for lo,hi in [(0x40a7b0,0x40aa6b),(0x40aa80,0x40b831),(0x409870,0x409890),
                                         (0x40e240,0x40e305),(0x406fe0,0x407010),(0x42c780,0x42c7d9),(0x458bb0,0x458cb3)]):raise ValueError(f'Unreviewed Poison Arrow instruction {at:#x}')
        if pending and pending[-1][0]==at:
            _,bound=pending.pop();draws.append(dict(bound=bound,value=m.reg_read(UC_X86_REG_EAX)))
        if at==0x42c780:
            esp=m.reg_read(UC_X86_REG_ESP);pending.append((get(esp),get(esp+4)))
    before=bytes(m.mem_read(actor,0x400));m.hook_add(UC_HOOK_CODE,guard)
    m.mem_write(stack,struct.pack('<'+'I'*(len(args)+1),stop,*args));m.reg_write(UC_X86_REG_ESP,stack)
    m.emu_start(entry,end,count=8192)
    if m.reg_read(UC_X86_REG_EIP)!=end or pending:raise ValueError('Poison Arrow native boundary exceeded')
    if normal:
        actual=dict(value=m.reg_read(UC_X86_REG_EAX),hit_bonus_after=get(bonus))
        if before!=bytes(m.mem_read(actor,0x400)) or m.reg_read(UC_X86_REG_ESP)!=stack+4:raise ValueError('Poison Arrow numeric return mutates actor or stack')
    else:actual=dict(hp=get(target+0xd8),poison=get(target+0x30),no_magic=get(target+0x34),status_flags=get(target+0x24),contribution=get(0x4c13fc),hit_bonus_after=get(actor+0xb0))
    wanted=expected(c,draws)
    if actual!=wanted:raise ValueError(f'Poison Arrow result differs {c}: {actual} != {wanted}; draws={draws}')
    return dict(input=c,native=actual,draws=draws,normal_return=normal,entry=hex(entry),stop_address=hex(end),instructions=steps)

def check(packet):
    if packet.get('schema')!='hsl_poison_arrow_native.v1' or packet.get('exe_sha256')!=EXE_SHA or packet.get('native_execution') is not True:raise ValueError('Poison Arrow execution identity missing')
    if packet['special_sha256']!=digest((TABLES/'SPECIAL.TXT').read_bytes()) or packet['fields']!=fields():raise ValueError('Poison Arrow source definition changed')
    for key,cases in [('rolls',fixtures()),('applications',applications())]:
        if [r['input'] for r in packet[key]]!=cases:raise ValueError('Poison Arrow coverage differs')
        for r in packet[key]:
            normal=key=='rolls'
            if r['native']!=expected(r['input'],r['draws']) or r['normal_return'] is not normal or r['stop_address']!=('0x10000000' if normal else '0x40b831') or not 0<r['instructions']<8192:raise ValueError('Poison Arrow recorded return differs')


def execute_packet(exe: Path) -> dict:
    """Run the bounded original instructions on the documented EXE and assemble the packet."""
    base,mapped=image(exe.read_bytes())
    packet=dict(schema='hsl_poison_arrow_native.v1',exe_sha256=EXE_SHA,native_execution=True,evidence_tier='static-derived',
                special_sha256=digest((TABLES/'SPECIAL.TXT').read_bytes()),fields=fields(),
                rolls=[execute(base,mapped,c) for c in fixtures()],applications=[execute(base,mapped,c) for c in applications()],
                limits=['Channel1/proc0 and proc6 numeric functions return normally; HP plus poison applies through40b831 before final display/EXP.',
                        'Synthetic current stats, seed, resistance, HP and prior statuses exercise source-defined30..45/hit98/Attack+Poison.',
                        'Compound poison uses30 percent of a separate channel1 magnitude, not the primary damage, and preserves silence.',
                        'Full cast targeting, turn/reward dispatcher, original global-stream identity and rendering remain independent.'])
    return packet


def summary_line(packet: dict, executed_now: bool) -> str:
    return f'POISON_ARROW_NATIVE_PASS returns={len(packet["rolls"])} applications={len(packet["applications"])} executed_now={executed_now}'


TASK = ProbeTask('poison_arrow', PACKET, check, execute_packet, summary_line)


def tasks() -> list[ProbeTask]:
    return [TASK]
