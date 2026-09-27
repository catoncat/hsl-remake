"""Original weapon MP loss, HP-capped contribution and final-series caller.

The HP prefix stops before its sound callback; the MP leaf then returns normally.
Independent caller slices execute actual EXP/effects before the stamina boundary.

Registry task mana_strike (family probe, hsltools.probes._base.ProbeTask): check validates the
tracked packet against the independent model; generate executes the original instructions
(needs the documented hsl01.exe and unicorn). Bodies moved verbatim from the former hsl_native_mana_strike_probe.py.
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
from hsltools.probes.weapon_effect import execute, execute_mapping, execute_gear, expected, gear_flags
from hsltools.sources.tables import TABLES, digest

PACKET = ROOT / 'docs/evidence_packets/static_reverse/original_mana_strike.json'

MP_FLAG=0x400000
ANCHOR_SHA='b6dba3e88705cf8845581ca8207bfbc576a8e343c94e49efcfe22975eda73807'
ANCHORS=[(0x4480c6,31,'Source attack_decmp parser result maps to equipment bit400000.'),
         (0x409460,95,'Weapon MP loss uses signed contribution/3, clamps at zero, returns without RNG or attacker gain.'),
         (0x404089,57,'Impact stores actual HP-capped damage in4c13fc before sound/presentation callbacks.'),
         (0x4095e0,37,'The same ordinary tail calls cancellation, status, then MP loss.'),
         (0x442483,40,'Positive per-target EXP allows weapon effects before final stamina, including lethal final hits.'),
         (0x4424be,38,'An alive target with remaining blows bypasses the final weapon tail.')]

def cases():
    base=dict(seed=[7,0x87654321],effects=MP_FLAG,immunity=0,poison=0,hp=100,mp=77,index=0,
              slots=[[0,0],[2,1],[1,1],[3,1]],contribution=20,remaining=0)
    rows=[dict(base,contribution=amount,mp=mp,remaining=remaining,hp=hp)
          for amount in [0,1,2,3,4,8,100] for mp in [0,1,77] for remaining,hp in [(0,100),(1,100),(1,0)]]
    rows += [dict(base,effects=bits,immunity=immune,poison=0x140003,seed=[seed,0x87654321])
             for bits in [0,MP_FLAG|0x210000] for immune in [0,0x80,0x800000] for seed in [1,19]]
    return rows

def impacts():
    return [dict(hp=hp,damage=damage,mp=mp,effects=bits)
            for hp,damage in [(1,300),(2,300),(3,300),(4,300),(7,7),(7,8),(100,2),(100,3),(100,8)]
            for mp in [0,1,77] for bits in [0,MP_FLAG]]

def mappings():return [dict(field='attack_decmp',value=v,before=b) for v in [0,1] for b in [0,0x200000]]
def gears():return [dict(job=88,codes=codes,status=s) for codes in [[],[108],[102],[108,229]] for s in [0,7]]

def execute_impact(base,mapped,case):
    from unicorn import UC_HOOK_CODE
    from unicorn.x86_const import UC_X86_REG_ESP,UC_X86_REG_EIP,UC_X86_REG_EDX,UC_X86_REG_EBX,UC_X86_REG_EDI
    m=machine_for(base,mapped);owner,target,impact,actor,stack,stop=0x10001000,0x10002000,0x10003000,0x10004000,0x1001ff00,0x10000000
    def put(at,value):m.mem_write(at,struct.pack('<I',value&0xffffffff))
    def get(at):return struct.unpack('<I',m.mem_read(at,4))[0]
    victim=actor+0x1fc
    put(0x4c1bc8,actor);put(owner+0xa4,0);put(target+0xa4,1);put(actor+0x18c,case['effects'])
    put(actor+0xe0,51);put(victim+0xd8,case['hp']);put(victim+0xe0,case['mp'])
    m.mem_write(impact+0xa0,struct.pack('<H',case['damage']))
    m.reg_write(UC_X86_REG_EDI,impact);m.reg_write(UC_X86_REG_EDX,victim);m.reg_write(UC_X86_REG_EBX,0);m.reg_write(UC_X86_REG_ESP,stack)
    steps=0
    def guard(_m,address,_size,_data):
        nonlocal steps
        steps+=1
        if not (0x404089<=address<0x4040c2 or 0x409460<=address<0x4094bf):raise ValueError(f'Unreviewed MP/HP callee {address:#x}')
    m.hook_add(UC_HOOK_CODE,guard);m.emu_start(0x404089,0x4040c2,count=256)
    if m.reg_read(UC_X86_REG_EIP)!=0x4040c2:raise ValueError('HP application prefix exceeded sound boundary')
    m.mem_write(stack,struct.pack('<3I',stop,owner,target));m.reg_write(UC_X86_REG_ESP,stack)
    m.emu_start(0x409460,stop,count=256)
    value=dict(hp=get(victim+0xd8),contribution=get(0x4c13fc),mp=get(victim+0xe0),attacker_mp=get(actor+0xe0))
    amount=min(case['damage'],case['hp'])
    wanted=dict(hp=case['hp']-amount,contribution=amount,mp=max(0,case['mp']-amount//3) if case['effects']&MP_FLAG else case['mp'],attacker_mp=51)
    if value!=wanted or m.reg_read(UC_X86_REG_EIP)!=stop or m.reg_read(UC_X86_REG_ESP)!=stack+4:raise ValueError('Native capped HP -> MP return differs')
    return dict(input=case,native=value,prefix_stop='0x4040c2',leaf_entry='0x409460',normal_return=True,instructions=steps)

def check(packet):
    if packet.get('schema')!='hsl_mana_strike_native.v1' or packet.get('exe_sha256')!=EXE_SHA or packet.get('native_execution') is not True:raise ValueError('Mana strike identity differs')
    if packet['sources']!={n:digest((TABLES/n).read_bytes()) for n in ['ITEM.TXT','TYPE.H']}:raise ValueError('Mana strike sources differ')
    for key,inputs in [('caller',cases()),('impact',impacts()),('mapping',mappings()),('gear',gears())]:
        if [r['input'] for r in packet[key]]!=inputs:raise ValueError('Mana strike coverage differs: '+key)
    for row in packet['caller']:
        c=row['input'];enabled=(c['remaining']==0 or c['hp']==0) and c['contribution']>0
        wanted=expected(c,[{k:r[k] for k in ['bound','value']} for r in row['draws'] if r['stage']=='effects'],enabled)
        if any(row['native'][k]!=v for k,v in wanted.items()) or row['native']['effect_called']!=enabled or row['stop_address'] not in ['0x4424e4','0x44248e','0x10000000'] or row['normal_return']!=(row['stop_address']=='0x10000000') or not row['attacker_unchanged']:raise ValueError('Mana caller result/return differs: '+str(row))
    for row in packet['impact']:
        c=row['input'];amount=min(c['hp'],c['damage'])
        wanted=dict(hp=c['hp']-amount,contribution=amount,mp=max(0,c['mp']-amount//3) if c['effects']&MP_FLAG else c['mp'],attacker_mp=51)
        if row['native']!=wanted or not row['normal_return'] or row['prefix_stop']!='0x4040c2' or not 0<row['instructions']<256:raise ValueError('Mana HP-prefix/leaf differs')
    for row in packet['mapping']:
        c=row['input']
        if row['native']!=(c['before']|(MP_FLAG if c['value'] else 0)) or row['normal_return'] or row['stop_address']!='0x4480e5':raise ValueError('Mana field mapping differs')
    for row in packet['gear']:
        if len(row['native'])!=2 or any(not r['normal_return'] or r['values']['effects']!=gear_flags(row['input']) for r in row['native']):raise ValueError('Mana gear source refresh differs')
    if [(int(r['address'],16),len(bytes.fromhex(r['bytes'])),r['meaning']) for r in packet['anchors']]!=ANCHORS:raise ValueError('Mana anchors differ')
    if hashlib.sha256(bytes.fromhex(''.join(r['bytes'] for r in packet['anchors']))).hexdigest()!=ANCHOR_SHA or packet['anchors_sha256']!=ANCHOR_SHA:raise ValueError('Mana instruction fingerprint differs')


def execute_packet(exe: Path) -> dict:
    """Run the bounded original instructions on the documented EXE and assemble the packet."""
    base,mapped=image(exe.read_bytes());anchors=[dict(address=hex(at),bytes=bytes(mapped[at-base:at-base+length]).hex(),meaning=meaning) for at,length,meaning in ANCHORS]
    packet=dict(schema='hsl_mana_strike_native.v1',exe_sha256=EXE_SHA,native_execution=True,evidence_tier='static-derived',sources={n:digest((TABLES/n).read_bytes()) for n in ['ITEM.TXT','TYPE.H']},
                caller=[execute(base,mapped,c,'caller') for c in cases()],impact=[execute_impact(base,mapped,c) for c in impacts()],
                mapping=[execute_mapping(base,mapped,c) for c in mappings()],gear=[execute_gear(base,mapped,c) for c in gears()],anchors=anchors,
                anchors_sha256=hashlib.sha256(bytes.fromhex(''.join(r['bytes'] for r in anchors))).hexdigest(),
                limits=['HP application stops before its sound call; MP leaf returns normally. Caller stops before stamina/presentation, not a whole native exchange.',
                        'The effect consumes actual capped final-strike HP loss, not queued pre-critical damage, total series loss, or awarded EXP; it gives no attacker MP.',
                        'Original caller gate and source modifier are proven; Godot global random identity and new feedback timings remain independent.'])
    return packet


def summary_line(packet: dict, executed_now: bool) -> str:
    return f'MANA_STRIKE_NATIVE_PASS caller={len(packet["caller"])} hp_leaf={len(packet["impact"])} gear_returns={2*len(packet["gear"])} executed_now={executed_now} sha={packet["anchors_sha256"]}'


TASK = ProbeTask('mana_strike', PACKET, check, execute_packet, summary_line)


def tasks() -> list[ProbeTask]:
    return [TASK]
