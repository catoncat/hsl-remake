"""Original full stat-refresh returns for base movement, equipment and clamps.

Each case runs the unchanged refresh twice; the second call changes level and
starts with a stale live movement value. No callee is stubbed and no original
game process, save, initialization RNG or presentation is executed.

Registry task mobility (family probe, hsltools.probes._base.ProbeTask): check validates the
tracked packet against the independent model; generate executes the original instructions
(needs the documented hsl01.exe and unicorn). Bodies moved verbatim from the former hsl_native_mobility_probe.py.
"""
from __future__ import annotations
import json
from pathlib import Path
import re
import struct

from hsltools.native.image import EXE_SHA, image
from hsltools.paths import ROOT
from hsltools.probes._base import ProbeTask
from hsltools.sources.tables import TABLES, blocks, digest

PACKET = ROOT / 'docs/evidence_packets/static_reverse/original_equipment_mobility.json'

SLOTS = ['weapon_equip','head_equip','armor_equip','foot_equip','other1_equip','other2_equip']
ANCHORS = [(0x447A0B, 38, 'ITEM.add_move stores a signed additive field at item+34'),
           (0x44C261, 30, 'PLAYERS.move_point is loaded into base+130'),
           (0x448987, 12, 'Every refresh restores base+130 to live+12c before equipment'),
           (0x4486BB, 17, 'Each equipped item adds its signed movement field to live+12c'),
           (0x44B760, 30, 'Final live movement clamps to zero through twelve')]


def sources():
    players = {r['code'].zfill(3):r for r in blocks((TABLES/'PLAYERS.TXT').read_bytes(),'character')}
    items = {int(r['code']):r for r in blocks((TABLES/'ITEM.TXT').read_bytes(),'item')}
    return players, items


def fixtures():
    players, _ = sources()
    rows = []
    for actor in ['001','021','023','024','025','026']:
        source = players[actor]
        for equipped in [False,True]:
            rows.append(dict(actor=actor, base=int(source['move_point']),
                             equipment=[int(source.get(slot,0)) if equipped else 0 for slot in SLOTS]))
    for base in [-3,0,1,5,10,11,12,15]:
        for gear in [[2,161,102,181,0,0],[2,161,102,193,0,0],[2,161,138,193,231,231]]:
            rows.append(dict(actor='001',base=base,equipment=gear))
    rows.extend([dict(actor='001',base=5,equipment=gear) for gear in
                 [[2,161,138,181,0,0],[2,161,102,181,231,0],[2,161,102,181,231,231]]])
    return rows


def expected(case):
    _, items = sources()
    bonus = sum(int(items[code].get('add_move',0)) for code in case['equipment'] if code)
    return dict(base=case['base'], equipment_bonus=bonus, move_point=max(0,min(12,case['base']+bonus)))


def execute(base, mapped, case):
    from unicorn import Uc, UC_ARCH_X86, UC_MODE_32, UC_HOOK_CODE
    from unicorn.x86_const import UC_X86_REG_EIP, UC_X86_REG_ESP
    players, items = sources()
    definitions = {k:int(v,0) for k,v in re.findall(r'^\s*#define\s+(\w+)\s+(0x[0-9a-fA-F]+|\d+)\b',(TABLES/'TYPE.H').read_bytes().decode('cp950'),re.M)}
    source = players[case['actor']]
    m = Uc(UC_ARCH_X86, UC_MODE_32)
    m.mem_map(base,len(mapped)); m.mem_write(base,bytes(mapped))
    m.mem_map(0x10000000,0x10000); m.mem_map(0x20000000,0x10000); m.mem_map(0x21000000,0x20000)
    actor,stack,stop = 0x20000000,0x1000ff00,0x10000000
    def put(at,value): m.mem_write(at,struct.pack('<I',value & 0xffffffff))
    def get(at): return struct.unpack('<i',m.mem_read(at,4))[0]
    for key,offset in [('str',0x64),('dex',0x68),('mind',0x6c),('con',0x70),
                       ('attack_power',0x1a4),('magic_attack_power',0x1a8),('defense',0x1ac),('speed',0x1b0)]:
        put(actor+offset,int(source.get(key,0)))
    put(actor+0x18,definitions[source['job']]); put(actor+0x28,definitions[source['mode']])
    put(actor+0x130,case['base']); put(actor+0x12c,1234)
    put(actor+0xd8,1); put(actor+0xe0,0); put(actor+0x88,37); put(actor+0xe8,20)
    put(actor+0x1b4,(int(source.get('hit_point',0))<<16)|int(source.get('magic_point',0)))
    if any(source.get('magic_'+k,'0')!='0' for k in ['other','earth','water','wind','fire','mind']): put(actor+0x174,1)
    put(0x4c1b40,0x21000000)
    for i,code in enumerate(case['equipment']):
        put(actor+0xec+i*4,code)
        if not code: continue
        row = items[code]; at = 0x21000000+code*176
        put(at+8,definitions[row['type']]); put(at+0x10,-1); put(at+0x8c,-1)
        for key,offset in [('attack_damage',0x88),('hit_ratio',0x98),('add_attack_power',0x20),
                           ('add_magic_power',0x24),('add_mp',0x28),('add_hp',0x2c),('add_move',0x34),
                           ('add_speed',0x38),('add_defense',0x3c)]:
            put(at+offset,int(row.get(key,0)))
    steps=0
    def guard(_m,address,_size,_data):
        nonlocal steps
        steps+=1
        if not 0x448370<=address<0x44b820: raise ValueError(f'Unreviewed mobility refresh callee {address:#x}')
    m.hook_add(UC_HOOK_CODE,guard)
    outputs=[]
    for level in [1,40]:
        put(actor+0x9c,level); put(actor+0x12c,1234 if level==1 else -987)
        put(stack,stop); put(stack+4,actor); m.reg_write(UC_X86_REG_ESP,stack)
        previous=steps; m.emu_start(0x448840,stop,count=12000)
        if m.reg_read(UC_X86_REG_EIP)!=stop or m.reg_read(UC_X86_REG_ESP)!=stack+4: raise ValueError('Mobility refresh did not return normally')
        outputs.append(dict(level=level,base=get(actor+0x130),move_point=get(actor+0x12c),hp=get(actor+0xd8),mp=get(actor+0xe0),exp=get(actor+0x88),stamina=get(actor+0xe8),instructions=steps-previous))
        if outputs[-1]['move_point']!=expected(case)['move_point'] or outputs[-1]['base']!=case['base']:
            raise ValueError(f'Mobility mismatch {case}: {outputs[-1]}')
        if [get(actor+offset) for offset in [0xd8,0xe0,0x88,0xe8]] != [1,0,37,20]: raise ValueError('Refresh refilled or spent unrelated resources')
    return dict(input=case,native=outputs,normal_return=True)


def check(packet):
    if packet.get('schema')!='hsl_native_equipment_mobility.v1' or packet.get('exe_sha256')!=EXE_SHA or packet.get('native_execution') is not True: raise ValueError('Missing original mobility identity')
    if packet['sources']!={n:digest((TABLES/n).read_bytes()) for n in ['ITEM.TXT','PLAYERS.TXT','TYPE.H']}: raise ValueError('Mobility source changed')
    if [r['input'] for r in packet['cases']]!=fixtures(): raise ValueError('Mobility coverage differs')
    for row in packet['cases']:
        wanted=expected(row['input'])
        if row['normal_return'] is not True or len(row['native'])!=2: raise ValueError('Missing complete repeated refresh')
        for result,level in zip(row['native'],[1,40]):
            if any(result[k]!=v for k,v in dict(level=level,base=wanted['base'],move_point=wanted['move_point'],hp=1,mp=0,exp=37,stamina=20).items()) or not 0<result['instructions']<12000: raise ValueError('Native refresh mobility or resource result differs')
    if [(int(r['address'],16),len(bytes.fromhex(r['bytes'])),r['meaning']) for r in packet['anchors']]!=ANCHORS: raise ValueError('Mobility anchors differ')


def execute_packet(exe: Path) -> dict:
    """Run the bounded original instructions on the documented EXE and assemble the packet."""
    base,mapped=image(exe.read_bytes())
    packet=dict(schema='hsl_native_equipment_mobility.v1',evidence_tier='static-derived',exe_sha256=EXE_SHA,native_execution=True,
                sources={n:digest((TABLES/n).read_bytes()) for n in ['ITEM.TXT','PLAYERS.TXT','TYPE.H']},
                cases=[execute(base,mapped,c) for c in fixtures()],
                anchors=[dict(address=hex(at),bytes=bytes(mapped[at-base:at-base+length]).hex(),meaning=meaning) for at,length,meaning in ANCHORS],
                limits=['Complete refresh returns with synthetic source-derived actor and equipment fields; only mobility and resource non-mutation are asserted here.',
                        'Base+130 is distinct from live+12c. Negative and oversized bases are deliberate arithmetic boundary fixtures, not default actors.',
                        'No temporary movement status, original roster initialization RNG, large-footprint flags, equip UI or original save format is executed.'])
    return packet


def summary_line(packet: dict, executed_now: bool) -> str:
    return f'MOBILITY_NATIVE_PASS cases={len(packet["cases"])} full_returns={2*len(packet["cases"])} executed_now={executed_now}'


TASK = ProbeTask('mobility', PACKET, check, execute_packet, summary_line)


def tasks() -> list[ProbeTask]:
    return [TASK]
