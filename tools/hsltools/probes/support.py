"""Bounded original heal-value returns and heal/cure application prefixes.

Heal stops before its display callback at 0x40ac04. Cure stops before the
applicator's common callbacks at 0x40b831. Neither is a whole spell return.

Registry task support (family probe, hsltools.probes._base.ProbeTask): check validates the
tracked packet against the independent model; generate executes the original instructions
(needs the documented hsl01.exe and unicorn). Bodies moved verbatim from the former hsl_native_support_probe.py.
"""
from __future__ import annotations
import json
from pathlib import Path
import struct

from hsltools.paths import ROOT
from hsltools.probes._base import ProbeTask
from hsltools.probes.status_roll import EXE_SHA, image, independent, run_case

PACKET = ROOT / 'docs/evidence_packets/static_reverse/original_support_magic.json'

def fixtures():
    return [dict(seed=[seed,0x87654321],proc=1,channel=0,low=24,high=36,hit_ratio=100,
                 status_hit_ratio=100,level=level,mind=mind,magic_attack=power,hit_bonus=7,
                 magic_hit_bonus=0,no_attack=False,element=1,resistance=resistance)
            for seed in [1,7,101] for level,mind,power in [(1,10,24),(80,36,80),(100,50,110)]
            for resistance in [0,80]]


def applications():
    heal = [dict(fixtures()[index],kind='heal',hp=hp,max_hp=100,
                 poison=(9<<16)|3,no_magic=2)
            for index in [0,4,12,16] for hp in [1,95,100]]
    cure = [dict(fixtures()[0],kind='cure',hp=hp,max_hp=100,
                 poison=word,no_magic=silence)
            for hp in [1,100] for word in [0,(5<<16)|1,(50<<16)|9] for silence in [0,2]]
    return heal+cure


def expected(case, draws):
    value = independent(case,draws) if case['kind']=='heal' else {'value':0,'hit_bonus_after':case['hit_bonus']}
    amount = min(case['max_hp']-case['hp'],value['value'])
    poison = 0 if case['kind']=='cure' else case['poison']
    return dict(hp=case['hp']+amount,poison=poison,no_magic=case['no_magic'],
                status_flags=(1 if poison else 0)|(2 if case['no_magic'] else 0),
                contribution=amount//2 if case['kind']=='heal' else (((case['poison']&0xffff)+1)*12 if case['poison'] else 0),
                hit_bonus_local=value['hit_bonus_after'])


def execute(base,mapped,case):
    from unicorn import Uc, UC_ARCH_X86, UC_MODE_32, UC_HOOK_CODE
    from unicorn.x86_const import UC_X86_REG_EAX, UC_X86_REG_EIP, UC_X86_REG_ESP
    machine=Uc(UC_ARCH_X86,UC_MODE_32)
    machine.mem_map(base,len(mapped)); machine.mem_write(base,bytes(mapped))
    machine.mem_map(0x10000000,0x20000)
    obj,target_obj,caster,record,table=0x10001000,0x10002000,0x10004000,0x10008000,0x10009000
    target=caster+0x1fc; stack=0x1001ff00; sentinel=0x10000000
    def put(at,value): machine.mem_write(at,struct.pack('<I',value&0xffffffff))
    def get(at): return struct.unpack('<I',machine.mem_read(at,4))[0]
    put(0x4c1bc8,caster); put(obj+0xa4,0); put(target_obj+0xa4,1)
    for offset,key in [(0x9c,'level'),(0x54,'mind'),(0xd0,'magic_attack'),(0xd4,'magic_hit_bonus'),(0xb0,'hit_bonus')]: put(caster+offset,case[key])
    for offset,key in [(0xd8,'hp'),(0xdc,'max_hp'),(0x30,'poison'),(0x34,'no_magic')]: put(target+offset,case[key])
    put(target+0x24,(1 if case['poison'] else 0)|(2 if case['no_magic'] else 0))
    put(target+0x108,case['resistance'])
    for offset,key in [(4,'element'),(0x14,'low'),(0x18,'high'),(0x1c,'hit_ratio'),(0x20,'status_hit_ratio')]: put(record+offset,case[key])
    put(record+0x24,2 if case['kind']=='heal' else 0x400)
    put(0x4c2ca0+case['element']*4,table); put(table,record)
    put(0x4c1e8c,1); put(0x4c3044,case['seed'][0]); put(0x4c3040,case['seed'][1])
    allowed=[(0x40aa80,0x40b831),(0x409850,0x40986c),(0x40a7b0,0x40aa6b),
             (0x406fe0,0x407010),(0x42c780,0x42c7d9),(0x458bb0,0x458cb3)]
    stop=0x40ac04 if case['kind']=='heal' else 0x40b831
    steps=0; draws=[]; returning=[]
    def guard(_m,address,_size,_data):
        nonlocal steps
        steps+=1
        if not any(lo<=address<hi for lo,hi in allowed): raise ValueError(f'Unreviewed support callee {address:#x}')
        if returning and returning[-1][0]==address:
            _,bound=returning.pop(); draws.append(dict(bound=bound,value=machine.reg_read(UC_X86_REG_EAX)))
        if address==0x42c780:
            esp=machine.reg_read(UC_X86_REG_ESP); returning.append((get(esp),get(esp+4)))
    machine.hook_add(UC_HOOK_CODE,guard)
    machine.mem_write(stack,struct.pack('<6I',sentinel,obj,target_obj,case['element'],0,0))
    machine.reg_write(UC_X86_REG_ESP,stack)
    machine.emu_start(0x40aa80,stop,count=4096)
    if machine.reg_read(UC_X86_REG_EIP)!=stop or returning: raise ValueError('Support prefix exceeded its boundary')
    actual=dict(hp=get(target+0xd8),poison=get(target+0x30),no_magic=get(target+0x34),
                status_flags=get(target+0x24),contribution=get(0x4c13fc),hit_bonus_local=get(stack-28))
    if actual!=expected(case,draws): raise ValueError(f'Support mismatch: {case} {draws} {actual} expected={expected(case,draws)}')
    return dict(input=case,native=actual,draws=draws,instructions=steps,stop_address=hex(stop),normal_return=False)


def check(data):
    if data.get('schema')!='hsl_support_magic_native.v1' or data.get('evidence_tier')!='static-derived' or data.get('exe_sha256')!=EXE_SHA or data.get('native_execution') is not True: raise ValueError('Native support identity missing')
    if [r['input'] for r in data['rolls']]!=fixtures() or [r['input'] for r in data['applications']]!=applications(): raise ValueError('Native support fixture coverage differs')
    for row in data['rolls']:
        if row['native']!=independent(row['input'],row['draws']) or row['normal_return'] is not True or not 0<row['instructions']<4096: raise ValueError('Saved support roll differs')
    for row in data['applications']:
        stop='0x40ac04' if row['input']['kind']=='heal' else '0x40b831'
        if row['input']['kind']=='cure' and row['draws']: raise ValueError('Cure branch unexpectedly consumes RNG')
        if row['native']!=expected(row['input'],row['draws']) or row['normal_return'] is not False or row['stop_address']!=stop or not 0<row['instructions']<4096: raise ValueError('Saved support application boundary differs')


def execute_packet(exe: Path) -> dict:
    """Run the bounded original instructions on the documented EXE and assemble the packet."""
    base,mapped=image(exe.read_bytes())
    data=dict(schema='hsl_support_magic_native.v1',evidence_tier='static-derived',exe_sha256=EXE_SHA,native_execution=True,
              rolls=[run_case(base,mapped,case) for case in fixtures()],applications=[execute(base,mapped,case) for case in applications()],
              limits=['Only the isolated numeric helper returns normally. Heal/cure are applicator prefixes before callbacks.',
                      'No original spell UI, whole AI dispatcher, experience distribution or battle initialization is asserted.',
                      'Living targets only; cure clears poison and preserves silence. Supplied state is synthetic.'])
    return data


def summary_line(data: dict, executed_now: bool) -> str:
    return f'SUPPORT_NATIVE_PASS rolls={len(data["rolls"])} application_prefixes={len(data["applications"])} executed_now={executed_now}'


TASK = ProbeTask('support', PACKET, check, execute_packet, summary_line)


def tasks() -> list[ProbeTask]:
    return [TASK]
