"""Original movement-casting permission, weapon range index and source gear.

Getter/range/refresh return normally. Menu stops before geometry/object creation;
AI gate stops before either search branch. No original callee is stubbed.

Registry task position_equipment (family probe, hsltools.probes._base.ProbeTask): check validates the
tracked packet against the independent model; generate executes the original instructions
(needs the documented hsl01.exe and unicorn). Bodies moved verbatim from the former hsl_native_position_equipment_probe.py.
"""
from __future__ import annotations
import hashlib
import json
from pathlib import Path
import struct

from hsltools.native.image import EXE_SHA, image
from hsltools.native.machine import machine_for
from hsltools.native.sources import original_sources as sources
from hsltools.paths import ROOT
from hsltools.probes._base import ProbeTask
from hsltools.sources.tables import TABLES, digest

PACKET = ROOT / 'docs/evidence_packets/static_reverse/original_position_equipment.json'

ANCHOR_SHA = '2bf1a352ac6a4b9864f3b2fd790c3f51d7521f99452f41d7e8578f6ca46a3a76'
ANCHORS = [(0x447dc2,34,'ITEM add_attack_range sets effect bit1.'),
           (0x447f08,34,'ITEM move_magic_use sets effect1000.'),
           (0x44c48f,46,'PLAYERS move_magic_use maps to capability400.'),
           (0x448753,28,'Nonempty equipment application maps capability400 to effect1000.'),
           (0x409090,123,'Weapon range code adds one boolean flag; large actors have a separate capped17 offset.'),
           (0x43eadc,29,'Moved menu hides magic without effect1000; silence hides it independently.'),
           (0x40d3f7,17,'AI selects movable-cast search only with effect1000.'),
           (0x4097d0,41,'Magic range returns its own table range without reading weapon bonus.')]


def cases():
    return ([dict(kind='range', weapon=weapon, base=base, effects=effects, size=size)
             for weapon in [0,1] for base in [0,1,2,3,15,20] for effects in [0,1,0x1001] for size in [0,1]] +
            [dict(kind='menu', moved=moved, magic=magic, special=special, silence=silence, effects=effects)
             for moved in [0,1] for magic in [0,1] for special in [0,1] for silence in [0,2] for effects in [0,1,0x1000]] +
            [dict(kind=kind,effects=effects) for kind in ['getter','ai'] for effects in [0,1,8,0x1000,0x1001,0x8000,0xffff]] +
            [dict(kind='magic_range',base=base,effects=effects) for base in [1,2,9] for effects in [0,1,0x1001]])


def expected(case):
    kind=case['kind']; enabled=bool(case['effects'] & 0x1000)
    if kind=='getter': return dict(value=int(enabled))
    if kind=='ai': return dict(moving_search=enabled)
    if kind=='magic_range': return dict(value=case['base'])
    if kind=='range':
        value=case['base']+bool(case['effects']&1)
        return dict(value=0 if not case['weapon'] else min(20,value+17) if case['size'] else value)
    magic=case['magic'] and not case['silence'] and (not case['moved'] or enabled)
    chars=('opqz' if case['moved'] else 'nopqz')+('v' if magic else '')+('w' if case['special'] else '')
    return dict(commands=chars)


def execute(base,mapped,case):
    from unicorn import UC_HOOK_CODE
    from unicorn.x86_const import UC_X86_REG_EAX,UC_X86_REG_ECX,UC_X86_REG_ESI,UC_X86_REG_EIP,UC_X86_REG_ESP
    m=machine_for(base,mapped); obj,actor,item,stack,stop=0x10001000,0x10004000,0x10008000,0x1001ff00,0x10000000
    def put(at,value):m.mem_write(at,struct.pack('<I',value&0xffffffff))
    put(0x4c1bc8,actor);put(obj+0xa4,0);put(actor+0x18c,case['effects']);put(actor+0xec,1)
    put(0x4c1b40,item);put(item+176+0x84,case.get('base',1));put(actor+0x2c,case.get('size',0))
    put(actor+0x24,case.get('silence',0));put(actor+0x174,case.get('magic',1));put(actor+0x158,case.get('special',1))
    kind=case['kind']; args=[stop,obj]
    if kind=='range':
        put(actor+0xec,case['weapon']);entry,stops=0x409090,[stop];allowed=[(entry,0x40910b)]
    elif kind=='menu':
        entry,stops=0x43ea30,[0x43ebf3];args.append(case['moved'])
        allowed=[(entry,0x43ebf3),(0x409090,0x40910b),(0x40e240,0x40e390)]
    elif kind=='ai':
        entry,stops=0x40d3f7,[0x40d404,0x40d439];m.reg_write(UC_X86_REG_ESI,obj)
        allowed=[(entry,0x40d404),(0x40e240,0x40e283)]
    elif kind=='getter': entry,stops=0x40e270,[stop];allowed=[(0x40e240,0x40e283)]
    else:
        entry,stops=0x4097d0,[stop];allowed=[(entry,0x409800)]
        put(0x4c2ca0+8,item);put(item, item+0x100);put(item+0x108,case['base']);args.extend([2,0])
    before=bytes(m.mem_read(actor,0x1fc)); steps=0
    def guard(_m,at,_size,_data):
        nonlocal steps
        if at in stops:m.emu_stop();return
        steps+=1
        if not any(lo<=at<hi for lo,hi in allowed):raise ValueError(f'Unreviewed position callee {at:#x}')
    m.hook_add(UC_HOOK_CODE,guard)
    m.mem_write(stack,struct.pack('<'+'I'*len(args),*args));m.reg_write(UC_X86_REG_ESP,stack)
    m.emu_start(entry,stop,count=4096);end=m.reg_read(UC_X86_REG_EIP)
    if end not in stops or before!=bytes(m.mem_read(actor,0x1fc)):raise ValueError('Position boundary or actor mutation differs')
    if kind=='menu':
        n=m.reg_read(UC_X86_REG_ECX); pointer=m.reg_read(UC_X86_REG_ESI)
        actual=dict(commands=bytes(m.mem_read(pointer,n*2)).decode('utf-16le'))
    elif kind=='ai':actual=dict(moving_search=end==0x40d404)
    else:actual=dict(value=m.reg_read(UC_X86_REG_EAX))
    if actual!=expected(case):raise ValueError(f'Native position differs {case}: {actual}')
    normal=end==stop
    if normal and m.reg_read(UC_X86_REG_ESP)!=stack+4:raise ValueError('Position getter did not return normally')
    return dict(input=case,native=actual,normal_return=normal,stop_address=hex(end),instructions=steps,actor_unchanged=True)


def gear_cases():
    return [dict(codes=codes,capability=cap) for codes in [[],[232],[233],[236],[232,233],[236,236]] for cap in [0,0x400]]


def gear_expected(case):
    _,items,_=sources(); flags=0;move=3
    for code in case['codes']:
        row=items[code];flags|=(0x1000 if int(row.get('move_magic_use',0)) else 0)|(1 if int(row.get('add_attack_range',0)) else 0)
        move+=int(row.get('add_move',0))
    if case['codes'] and case['capability']&0x400:flags|=0x1000
    return dict(effects=flags,move=min(12,move))


def execute_gear(base,mapped,case):
    from unicorn import Uc,UC_ARCH_X86,UC_MODE_32,UC_HOOK_CODE
    from unicorn.x86_const import UC_X86_REG_EIP,UC_X86_REG_ESP
    _,items,defines=sources();m=Uc(UC_ARCH_X86,UC_MODE_32)
    m.mem_map(base,len(mapped));m.mem_write(base,bytes(mapped))
    for at,size in [(0x10000000,0x10000),(0x20000000,0x10000),(0x21000000,0x20000)]:m.mem_map(at,size)
    actor,stack,stop=0x20000000,0x1000ff00,0x10000000
    def put(at,value):m.mem_write(at,struct.pack('<I',value&0xffffffff))
    def get(at):return struct.unpack('<I',m.mem_read(at,4))[0]
    for off,value in [(0x18,90),(0x28,0x10000),(0x9c,3),(0xd8,1),(0x130,3),(0xa0,case['capability']),(0x174,1)]:put(actor+off,value)
    for off in [0x64,0x68,0x6c,0x70]:put(actor+off,20)
    put(0x4c1b40,0x21000000)
    for index,code in enumerate(case['codes']):
        row=items[code];at=0x21000000+176*code;put(actor+0xfc+index*4,code)
        for off,value in [(8,defines[row['type']]),(0x10,-1),(0x8c,-1),(0x34,int(row.get('add_move',0))),
                          (0xa0,(0x1000 if int(row.get('move_magic_use',0)) else 0)|(1 if int(row.get('add_attack_range',0)) else 0))]:put(at+off,value)
    steps=0
    def guard(_m,at,_size,_data):
        nonlocal steps
        steps+=1
        if not 0x448370<=at<0x44b820:raise ValueError(f'Unreviewed gear callee {at:#x}')
    m.hook_add(UC_HOOK_CODE,guard);results=[]
    for _repeat in range(2):
        put(actor+0x18c,0x7fffffff);put(actor+0x12c,999)
        prior=steps;m.mem_write(stack,struct.pack('<2I',stop,actor));m.reg_write(UC_X86_REG_ESP,stack)
        m.emu_start(0x448840,stop,count=12000)
        if m.reg_read(UC_X86_REG_EIP)!=stop or m.reg_read(UC_X86_REG_ESP)!=stack+4:raise ValueError('Position gear did not return')
        actual=dict(effects=get(actor+0x18c),move=get(actor+0x12c))
        if actual!=gear_expected(case):raise ValueError(f'Position gear mismatch {case}: {actual}')
        results.append(dict(values=actual,normal_return=True,instructions=steps-prior))
    return dict(input=case,native=results)


def check(packet):
    if packet.get('schema')!='hsl_position_equipment_native.v1' or packet.get('exe_sha256')!=EXE_SHA or packet.get('native_execution') is not True:raise ValueError('Position evidence identity differs')
    if packet['sources']!={n:digest((TABLES/n).read_bytes()) for n in ['ITEM.TXT','PLAYERS.TXT','RANGE.H','RANGE.TXT']}:raise ValueError('Position sources differ')
    if [r['input'] for r in packet['cases']]!=cases() or [r['input'] for r in packet['gear']]!=gear_cases():raise ValueError('Position coverage differs')
    for row in packet['cases']:
        case=row['input'];normal=case['kind'] not in ['menu','ai']
        stops=['0x10000000'] if normal else ['0x43ebf3'] if case['kind']=='menu' else ['0x40d404' if expected(case)['moving_search'] else '0x40d439']
        if row['native']!=expected(case) or row['normal_return']!=normal or row['stop_address'] not in stops or not 0<row['instructions']<4096 or not row['actor_unchanged']:raise ValueError('Position return/boundary differs')
    for row in packet['gear']:
        if len(row['native'])!=2 or any(r['values']!=gear_expected(row['input']) or not r['normal_return'] or not 0<r['instructions']<12000 for r in row['native']):raise ValueError('Position gear evidence differs')
    if [(int(a['address'],16),len(bytes.fromhex(a['bytes'])),a['meaning']) for a in packet['anchors']]!=ANCHORS:raise ValueError('Position anchors differ')
    if hashlib.sha256(bytes.fromhex(''.join(a['bytes'] for a in packet['anchors']))).hexdigest()!=ANCHOR_SHA:raise ValueError('Position instruction bytes differ')


def execute_packet(exe: Path) -> dict:
    """Run the bounded original instructions on the documented EXE and assemble the packet."""
    base,mapped=image(exe.read_bytes())
    packet=dict(schema='hsl_position_equipment_native.v1',exe_sha256=EXE_SHA,evidence_tier='static-derived',native_execution=True,
                sources={n:digest((TABLES/n).read_bytes()) for n in ['ITEM.TXT','PLAYERS.TXT','RANGE.H','RANGE.TXT']},
                cases=[execute(base,mapped,c) for c in cases()],gear=[execute_gear(base,mapped,c) for c in gear_cases()],
                anchors=[dict(address=hex(at),bytes=bytes(mapped[at-base:at-base+size]).hex(),meaning=meaning) for at,size,meaning in ANCHORS],
                limits=['Menu/AI stop before drawing or search; complete engine dispatch is not executed.',
                        'Large-actor range offset is recorded only, not permission to enable large actor footprints.',
                        'Equipment uses source item values and synthetic actor/slot input; no original gameplay or full source loader.'])
    return packet


def summary_line(packet: dict, executed_now: bool) -> str:
    return f'POSITION_EQUIPMENT_NATIVE_PASS cases={len(packet["cases"])} gear_returns={2*len(packet["gear"])} executed_now={executed_now} anchors_sha='+hashlib.sha256(bytes.fromhex(''.join(a['bytes'] for a in packet['anchors']))).hexdigest()


TASK = ProbeTask('position_equipment', PACKET, check, execute_packet, summary_line)


def tasks() -> list[ProbeTask]:
    return [TASK]
