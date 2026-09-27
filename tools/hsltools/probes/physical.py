"""Execute original physical numeric helpers and bounded impact/refresh slices.

The hit, base-damage and weapon-bonus helpers return normally. Critical impact,
minimum-damage fallback and chance refresh stop before unreviewed callbacks;
no native return values, random helpers or callees are stubbed.

Registry task physical (family probe, hsltools.probes._base.ProbeTask): check validates the
tracked packet against the independent model; generate executes the original instructions
(needs the documented hsl01.exe and unicorn). Bodies moved verbatim from the former hsl_native_physical_probe.py.
"""
from __future__ import annotations
import json
from pathlib import Path
import struct

from hsltools.native.image import EXE_SHA, image
from hsltools.paths import ROOT
from hsltools.probes._base import ProbeTask

PACKET = ROOT / 'docs/evidence_packets/static_reverse/original_physical_combat.json'

ANCHORS = [
    (0x409BE0, 8, 'Actual physical damage entry; 0x409bca is padding after the preceding helper, not an entry.'),
    (0x409D49, 26, 'Weapon element at actor+c4: -1 disables the bonus helper.'),
    (0x448634, 41, 'Weapon element/low/high copy from item+8c/90/94 to actor+c4/c8/cc.'),
    (0x4486E8, 33, 'Equipment modifies working avoidance/counter/critical 16-bit rates.'),
    (0x4425A3, 30, 'Impact object is constructed with effective critical rate, combined hit chance and queued damage.'),
    (0x44248E, 16, 'Ordinary stamina uses the queued pre-impact damage at 0x4c2ae0, not the later critical value.'),
    (0x403F39, 51, 'Ordinary impact checks the saved hit roll before drawing its critical chance.'),
    (0x401AC0, 20, 'Critical callback submits engine event0x302; it is not evidence of a named WAV asset.'),
    (0x44BFE5, 39, 'Source attack_damagex2 is loaded with cleared default and stored at base+1a0.'),
]


def fixtures() -> list[dict]:
    base = dict(kind='damage', attack=40, defense=30, strength=20, target_strength=20,
                element=-1, low=0, high=0, resistance=0, seed=7)
    rows = [dict(base, attack=max(value,0)+30, defense=30 if value>=0 else 30-value,
                 strength=max(delta,0)+40, target_strength=40+max(-delta,0), seed=seed)
            for value in [-10,0,1,2,3,6,7,9,10,39,100] for delta in [-80,-13,0,11,100] for seed in [1,19]]
    for element in [0,1,2,3,4,5]:
        for resistance in [0,80,100]:
            rows.append(dict(base, element=element, low=5, high=10, resistance=resistance))
    for low, high in [(0,0),(0,1),(1,1),(1,2),(2,3),(5,10),(10,5)]:
        for resistance in [0,80]: rows.append(dict(base, kind='weapon', element=2, low=low, high=high, resistance=resistance))
    for raw, chance, critical in [(0,96,0),(95,96,100),(96,96,100),(99,100,8),(0,0,100),(0,100,100)]:
        for damage in [1,5,22,32760]: rows.append(dict(kind='impact',damage=damage,hit_roll=raw,hit_rate=chance,critical_rate=critical,seed=7))
    rows += [dict(kind='fallback',seed=seed) for seed in [1,7,19,101,117,212]]
    rows += [dict(kind='chances',avoid=avoid,counter=counter,critical=critical)
             for avoid,counter,critical in [(0,0,0),(3,12,14),(12,30,80),(0,1,1)]]
    rows += [dict(kind='hit',hit_rate=rate,dex=dex,target_dex=target,avoid=avoid)
             for rate,dex,target,avoid in [(96,16,15,0),(96,1,200,0),(20,100,1,80),(10,1,100,70),(110,16,16,0),(96,16,15,99)]]
    return rows


def expected(case: dict, draws: list[dict]) -> dict:
    cursor = 0
    def draw(bound):
        nonlocal cursor
        if cursor >= len(draws) or draws[cursor]['bound'] != bound: raise ValueError('Physical random bound/order differs')
        value = draws[cursor]['value']; cursor += 1
        if bound == 0 and value != 0 or bound > 0 and not 0 <= value < bound: raise ValueError('Physical random value out of range')
        return value
    def minimum(value):
        return value + 3*((5-value)//3) if value < 3 else value
    def bonus():
        sampled = case['low'] + draw(abs(case['high']-case['low']))
        if sampled == 0: sampled = 1
        value = minimum(sampled+draw(sampled//2))
        if case['element'] in range(5): value = value*(100-min(80,case['resistance']))//100
        return value
    kind = case['kind']
    if kind == 'damage':
        base = case['attack']-case['defense']
        delta = max(-20,min(30,int((case['strength']-case['target_strength'])/2)))
        if base <= 0:
            value = draw(5)+3
            delta = max(0,delta)
        elif base < 10:
            value = draw(base+4) + (7 if base<=2 else 8 if base<=6 else 9)
            delta = max(0,delta)
        else:
            value = base
            delta = max(-(base//2),delta)
        damage = value+delta-draw(value*30//100)-draw(abs(delta)//2)+draw(abs(delta)//2)
        if damage <= 0:
            damage = draw(-1)&15
            if damage > 10: damage -= 10*((damage-1)//10)
            damage = minimum(damage)
        if case['element'] != -1: damage += bonus()
        result = dict(damage=damage)
    elif kind == 'weapon': result = dict(damage=bonus())
    elif kind == 'hit':
        delta = max(-30,min(30,int((case['dex']-case['target_dex'])/2)))
        result = dict(hit_rate=max(10,max(20,min(100,case['hit_rate']+delta))-case['avoid']))
    elif kind == 'impact':
        hit = case['hit_roll'] < case['hit_rate']
        damage = case['damage']; critical = False
        if hit:
            critical = draw(100)+1 <= case['critical_rate']
            if critical:
                while damage < 6: damage += 2+draw(5)
                low = damage*150//100
                damage = min(32767,low+draw(abs(damage*2-low))+1)
        result = dict(hit=hit,critical=critical,damage=damage,queued_damage=case['damage'])
    elif kind == 'chances':
        result = dict(avoid=case['avoid'],counter=case['counter'] or 12,critical=case['critical'] or 8)
    else:
        damage = draw(-1)&15
        if damage > 10: damage -= 10*((damage-1)//10)
        result = dict(damage=minimum(damage))
    if cursor != len(draws): raise ValueError('Physical unused native random calls')
    return result


def execute(base: int, mapped: bytearray, case: dict) -> dict:
    from unicorn import Uc, UC_ARCH_X86, UC_MODE_32, UC_HOOK_CODE
    from unicorn.x86_const import UC_X86_REG_EAX, UC_X86_REG_EBX, UC_X86_REG_EDX, UC_X86_REG_EDI, UC_X86_REG_ESI, UC_X86_REG_ESP, UC_X86_REG_EIP
    m = Uc(UC_ARCH_X86,UC_MODE_32)
    m.mem_map(base,len(mapped)); m.mem_write(base,bytes(mapped)); m.mem_map(0x10000000,0x20000)
    obj, other, actor, target, stack, stop = 0x10001000,0x10002000,0x10004000,0x100041fc,0x1001ff00,0x10000000
    def put(at,value): m.mem_write(at,struct.pack('<I',value&0xffffffff))
    def get(at): return struct.unpack('<I',m.mem_read(at,4))[0]
    def word(at): return struct.unpack('<H',m.mem_read(at,2))[0]
    put(0x4c1bc8,actor); put(obj+0xa4,0); put(other+0xa4,1)
    put(0x4c1e8c,1); put(0x4c3044,case.get('seed',7)); put(0x4c3040,0x87654321)
    kind = case['kind']; normal = kind in ['damage','weapon','hit']; args=[]
    if kind in ['damage','weapon']:
        for offset,key in [(0xc0,'attack'),(0x4c,'strength'),(0xc4,'element'),(0xc8,'low'),(0xcc,'high')]: put(actor+offset,case[key])
        put(target+0x4c,case['target_strength']); put(target+0xb4,case['defense'])
        for index in range(5): put(target+0x104+index*4,case['resistance'])
        entry = 0x409be0 if kind=='damage' else 0x409af0; stops=[stop]
        args = [obj,other] if kind=='damage' else [actor,target]
    elif kind == 'hit':
        put(actor+0xbc,case['hit_rate']); put(actor+0x50,case['dex']); put(target+0x50,case['target_dex'])
        m.mem_write(target+0x19a,struct.pack('<h',case['avoid']))
        entry=0x409a60; stops=[stop]; args=[obj,other]
    elif kind == 'impact':
        m.reg_write(UC_X86_REG_EDI,obj)
        for offset,key in [(0xa0,'damage'),(0xa6,'hit_rate'),(0x4e,'critical_rate')]: m.mem_write(obj+offset,struct.pack('<H',case[key]))
        put(0x4c1418,case['hit_roll']); put(0x4c2ae0,case['damage'])
        entry=0x403f39; stops=[0x403ff6,0x403ff1,0x4041ea]
    elif kind == 'chances':
        for offset,key in [(0x198,'avoid'),(0x19c,'counter'),(0x1a0,'critical')]: put(actor+offset,case[key])
        m.reg_write(UC_X86_REG_ESI,actor); m.reg_write(UC_X86_REG_EBX,8); m.reg_write(UC_X86_REG_EDX,0)
        entry=0x4489bd; stops=[0x448a1e]
    else:
        entry=0x409d06; stops=[0x409d49]
    before=bytes(m.mem_read(actor,0x400)); steps=0;draws=[];pending=[]
    def guard(_m,address,_size,_data):
        nonlocal steps
        if address in stops and not normal: m.emu_stop(); return
        steps+=1
        if not any(lo<=address<hi for lo,hi in [(0x409a60,0x409bc9+1),(0x409be0,0x409df8),(0x403f39,0x403ff7),(0x4489bd,0x448a1e),(0x42c720,0x42c7d9),(0x458bb0,0x458cb3)]):
            raise ValueError(f'Unknown physical callee {address:#x}')
        if pending and pending[-1][0] == address:
            _,bound=pending.pop();draws.append(dict(bound=bound,value=m.reg_read(UC_X86_REG_EAX)))
        if address in [0x42c720,0x42c780]:
            sp=m.reg_read(UC_X86_REG_ESP);pending.append((get(sp),get(sp+4) if address==0x42c780 else -1))
    m.hook_add(UC_HOOK_CODE,guard)
    m.mem_write(stack,struct.pack('<'+'I'*(len(args)+1),stop,*args));m.reg_write(UC_X86_REG_ESP,stack)
    m.emu_start(entry,stop,count=4096)
    end=m.reg_read(UC_X86_REG_EIP)
    if end not in stops or pending or normal and m.reg_read(UC_X86_REG_ESP)!=stack+4: raise ValueError('Physical probe exceeded its boundary')
    if kind=='impact': result=dict(hit=end!=0x4041ea,critical=end==0x403ff1,damage=word(obj+0xa0),queued_damage=get(0x4c2ae0))
    elif kind=='chances': result=dict(avoid=word(actor+0x19a),counter=word(actor+0x19e),critical=word(actor+0x1a2))
    else: result={('hit_rate' if kind=='hit' else 'damage'):m.reg_read(UC_X86_REG_ESI if kind=='fallback' else UC_X86_REG_EAX)}
    if normal and before!=bytes(m.mem_read(actor,0x400)): raise ValueError('Pure physical helper changed a participant')
    if result!=expected(case,draws): raise ValueError(f'Physical mismatch {case}: {result} {draws} expected={expected(case,draws)}')
    return dict(input=case,native=result,draws=draws,normal_return=normal,entry=hex(entry),stop_address=hex(end),instructions=steps)


def check(packet:dict) -> None:
    if packet.get('schema')!='hsl_native_physical_combat.v1' or packet.get('exe_sha256')!=EXE_SHA or packet.get('native_execution') is not True: raise ValueError('Invalid original physical identity')
    if [r['input'] for r in packet['cases']]!=fixtures(): raise ValueError('Physical fixture coverage differs')
    for row in packet['cases']:
        normal=row['input']['kind'] in ['damage','weapon','hit']
        if row['normal_return'] is not normal or not 0<row['instructions']<4096 or row['native']!=expected(row['input'],row['draws']): raise ValueError('Physical result/boundary differs')
        allowed=['0x10000000'] if normal else {'impact':['0x403ff6','0x403ff1','0x4041ea'],'fallback':['0x409d49'],'chances':['0x448a1e']}[row['input']['kind']]
        if row['stop_address'] not in allowed: raise ValueError('Physical stop changed')
    if [(int(r['address'],16),len(bytes.fromhex(r['bytes'])),r['meaning']) for r in packet['anchors']]!=ANCHORS: raise ValueError('Physical anchors differ')


def execute_packet(exe: Path) -> dict:
    """Run the bounded original instructions on the documented EXE and assemble the packet."""
    base,mapped=image(exe.read_bytes())
    packet=dict(schema='hsl_native_physical_combat.v1',exe_sha256=EXE_SHA,evidence_tier='static-derived',native_execution=True,
                cases=[execute(base,mapped,c) for c in fixtures()],
                anchors=[dict(address=hex(at),bytes=bytes(mapped[at-base:at-base+size]).hex(),meaning=meaning) for at,size,meaning in ANCHORS],
                limits=['Hit, ordinary-damage and weapon-bonus helpers return normally. Critical impact, fallback and refresh are bounded slices before callbacks.',
                        'Synthetic positive-domain actor/weapon profiles; no full native initialization, presentation, counters or whole exchange execution.',
                        'RNG bounds/order checked, including rand0 and raw fallback; Godot is not asserted to use identical global PRNG state.'])
    return packet


def summary_line(packet: dict, executed_now: bool) -> str:
    return f'PHYSICAL_NATIVE_PASS normal={sum(c["normal_return"] for c in packet["cases"])} suffixes={sum(not c["normal_return"] for c in packet["cases"])} executed_now={executed_now}'


TASK = ProbeTask('physical', PACKET, check, execute_packet, summary_line)


def tasks() -> list[ProbeTask]:
    return [TASK]
