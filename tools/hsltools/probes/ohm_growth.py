"""Bounded original BowMan83 and Ohm villagers; no whole-engine claims.

Reuse reviewed native refresh/growth implementations on newly scoped source
inputs. Keep complete numeric returns separate from the factory-prefix proof.

Registry task ohm_growth (family probe, hsltools.probes._base.ProbeTask): check validates the
tracked packet against the independent model; generate executes the original instructions
(needs the documented hsl01.exe and unicorn). Bodies moved verbatim from the former hsl_native_ohm_growth_probe.py.
"""
from __future__ import annotations
import copy
import hashlib
import json
from pathlib import Path
import struct

from hsltools.data.equipment import build as equipment_data
from hsltools.model.jobs import ATTRIBUTES, CAPS, SLOTS, source_profile, calculate
from hsltools.native.image import EXE_SHA, image
from hsltools.native.sources import sources
from hsltools.paths import ROOT
from hsltools.probes._base import ProbeTask
from hsltools.probes.ai import execute as ai_execute, expected as ai_expected
from hsltools.probes.auto_growth import base_case, execute as grow, expected as growth_expected
from hsltools.probes.growth_lifecycle import Machine, reward_execute, reward_expected
from hsltools.probes.job_stats import execute as refresh
from hsltools.probes.position_equipment import execute as range_execute, expected as range_expected
from hsltools.sources.tables import TABLES, digest

PACKET = ROOT / 'docs/evidence_packets/static_reverse/original_ohm_growth.json'

ANCHOR_SHA = '9f24845556869fc91eb8ea80c7f24448605d02326045162decb1c70132d7ebd5'
ACTORS = ['003', '061', '062']
BOW_SPECIALS = [(1,28,24,12,25,5,8),(1,42,40,16,36,2,1),(2,52,48,24,50,4,3),
                (2,65,52,29,60,2,2),(2,80,55,32,70,2,3)]
ANCHORS = [(0x449032, 353, 'BowMan83 cap row3 and five independent resistance terms.'),
           (0x4492f3, 380, 'Bow-family ordered integer HP/MP/attack/defense/magic/speed arithmetic.'),
           (0x4786d4, 8, 'BowMan83 caps96/98/70/88.'),
           (0x44b82c, 4, 'Derived-stat dispatch row3 selects449032.'),
           (0x407ef5, 141, 'Kind3 uses registered party slots; kind5 copies into a separate free actor record.'),
           (0x44cb10, 125, 'Template copy: fixed party slot or first free slot21..198, zero on exhaustion.'),
           (0x40ba20, 82, 'AI side mask preserves combined pmNPCPlayer bits rather than granting player control.')]

def stat_cases():
    players, _, defines = sources()
    rows = []
    for code in ACTORS:
        source = players[code]
        first = dict(actor=code, name='initial', attributes={k:int(source[k]) for k in ATTRIBUTES},
                     level=int(source.get('level', 1)), equipment=[int(source.get(k, 0)) for k in SLOTS],
                     hp=9999, mp=9999, mode=defines[source['mode']], base_move=int(source['move_point']))
        rows.append(first)
        for level in [2, 9, 10, 19, 20, 40, 99]:
            rows.append(dict(first, name=f'level_{level}', level=level, hp=7, mp=0))
        for key in ATTRIBUTES:
            rows.append(dict(first, name=key+'_plus1', attributes=dict(first['attributes'], **{key:first['attributes'][key]+1})))
        rows.append(dict(first, name='caps', level=99, attributes=dict(zip(ATTRIBUTES,CAPS[defines[source['job']]]))))
        rows.append(dict(first, name='empty', equipment=[0]*6, hp=1, mp=0))
        for mode in [0x10000, 0x20000, 0x50000]:
            rows.append(dict(first, name=f'mode_{mode}', mode=mode, level=12))
    rows.append(dict(rows[0],name='equipped_double_bow',equipment=[69,153,123,181,227,0],level=12,hp=7,mp=0))
    return rows

def growth_cases():
    rows = []
    for code in ACTORS:
        for party in [[1], [8,12], [30]]:
            for spread, dispersion in [(0,0), (3,0), (20,3)]:
                rows.append(dict(base_case(code), kind='adjust', object_kind=3 if code=='003' else 5,
                                 party=party, range=spread, dispersion=dispersion))
        for points in [1,5,10,15]:
            rows.append(dict(base_case(code), kind='allocate', points=points))
    return rows

def reward_cases():
    return [dict(base_case(code), kind='reward', object_kind=3 if code=='003' else 5, exp=exp)
            for code in ACTORS for exp in [99,100,999]]

def range_cases():
    return [dict(kind='range',weapon=weapon,base=4,effects=effects,size=size)
            for weapon in [0,1] for effects in [0,1] for size in [0,1]]

def ai_cases():
    return [dict(kind='target',owner=0,range=20,near_range=20,excluded_sid=-1,
                 mode=3,preference=1,seed=[seed,0x87654321],units=[
                     dict(coord=[10,10],side=0x50000,hp=52,level=2,job=80,sid=61,removed=False),
                     dict(coord=[11,10],side=0x10000,hp=30,level=4,job=83,sid=2,removed=False),
                     dict(coord=[11,11],side=0x50000,hp=58,level=2,job=80,sid=62,removed=False),
                     dict(coord=[13,10],side=0x20000,hp=40,level=3,job=88,sid=28,removed=False),
                     dict(coord=[14,11],side=0x20000,hp=35,level=3,job=90,sid=26,removed=removed)])
            for seed in [1,19] for removed in [False,True]]

def copy_cases():
    return [dict(source=code, occupied=count) for code in [61,62] for count in [0,2,178]]

def learning_cases():
    cases=[dict(kind='magic',level=level,attributes=[30]*4,preview=False,existing=False) for level in [0,1,4,20,99]]
    vectors=[[24,16,7,20],[100]*4]
    for row in BOW_SPECIALS[:2]:
        attrs=list(row[1:5]);vectors.append(attrs)
        for index in range(4):
            low=attrs.copy();low[index]-=1;vectors.append(low)
    cases += [dict(kind='special',level=4,attributes=attrs,preview=preview,existing=existing)
              for attrs in vectors for preview in [True,False] for existing in [False,True]]
    return cases

def learning_expected(c):
    masks=[0xffffffff if c['existing'] else 0]*(6 if c['kind']=='magic' else 7)
    attempts=[]
    if c['kind']=='special':
        for tier,s,d,m,h,element,code in BOW_SPECIALS:
            if tier>1 or any(a<b for a,b in zip(c['attributes'],[s,d,m,h])):continue
            attempts.append([1,element,code])
            if not masks[element]&(1<<code):
                if not c['preview']:masks[element]|=1<<code
                break
    return dict(masks=masks,attempts=attempts,rng_unchanged=True,attributes_unchanged=True)

def learning_execute(base,mapped,c):
    n=Machine(base,mapped,base_case('003'));n.learning_names();a=n.actor
    n.put(a+0x9c,c['level'])
    for i,value in enumerate(c['attributes']):n.put(a+0x64+i*4,value)
    start=0x174 if c['kind']=='magic' else 0x158;count=6 if c['kind']=='magic' else 7
    for i in range(count):n.put(a+start+i*4,0xffffffff if c['existing'] else 0)
    text=0x10010000 if c['kind']=='magic' or c['preview'] else 0
    attrs=bytes(n.m.mem_read(a+0x64,16));rng=bytes(n.m.mem_read(0x4c3040,8))
    end,_=n.call(0x4373f0 if c['kind']=='magic' else 0x437a40,[a,text])
    actual=dict(masks=[n.get(a+start+i*4) for i in range(count)],attempts=[r['args'][2:5] for r in n.calls],
                rng_unchanged=rng==bytes(n.m.mem_read(0x4c3040,8)),attributes_unchanged=attrs==bytes(n.m.mem_read(a+0x64,16)))
    if end!=n.stop or n.draws or actual!=learning_expected(c):raise ValueError(f'Bow learning differs {c}: {actual}')
    return dict(input=c,native=actual,normal_return=True,instructions=n.steps,draws=n.draws)

def learning_table(mapped,base):
    raw=bytes(mapped[0x478378-base:0x478378-base+72])
    if [struct.unpack_from('<7h',raw,i*14) for i in range(5)]!=BOW_SPECIALS or struct.unpack_from('<h',raw,70)[0]!=-1:raise ValueError('Original bow learning table differs')
    if struct.unpack_from('<I',mapped,0x437bd4-base+3*4)[0]!=0x437ab4:raise ValueError('Bow special dispatch differs')
    return dict(address='0x478378',tier=1,rows=[dict(tier=r[0],attributes=dict(zip(ATTRIBUTES,r[1:5])),type=r[5],code=r[6]) for r in BOW_SPECIALS],bytes=raw.hex())

def copy_execute(base, mapped, case):
    from unicorn import Uc, UC_ARCH_X86, UC_MODE_32, UC_HOOK_CODE
    from unicorn.x86_const import UC_X86_REG_EAX,UC_X86_REG_EBX,UC_X86_REG_ECX,UC_X86_REG_ESI,UC_X86_REG_ESP,UC_X86_REG_EIP
    m=Uc(UC_ARCH_X86,UC_MODE_32);m.mem_map(base,len(mapped));m.mem_write(base,bytes(mapped))
    m.mem_map(0x10000000,0x40000)
    templates, live, obj, stack, stop = 0x10001000,0x10010000,0x10030000,0x1003ff00,0x10000000
    def put(at,v):m.mem_write(at,struct.pack('<I',v&0xffffffff))
    def get(at):return struct.unpack('<I',m.mem_read(at,4))[0]
    source=bytearray((i*13+case['source'])%256 for i in range(0x1fc))
    struct.pack_into('<I',source,0,case['source']);struct.pack_into('<I',source,0x28,0x50000)
    m.mem_write(templates+case['source']*0x1fc,bytes(source))
    put(0x4c1afc,templates);put(0x4c1bc8,live)
    for index in range(21,21+case['occupied']):put(live+index*0x1fc,999)
    put(obj+0xa4,case['source']);put(obj+0x64,5)
    before=bytes(m.mem_read(live,200*0x1fc));steps=0
    def guard(_m,at,_size,_data):
        nonlocal steps
        if at==0x407f80:m.emu_stop();return
        steps+=1
        if not (0x407ef5<=at<0x407f80 or 0x44cb10<=at<0x44cb8d):raise ValueError(f'Unreviewed NPC copy instruction {at:#x}')
    m.hook_add(UC_HOOK_CODE,guard)
    m.reg_write(UC_X86_REG_ESI,obj);m.reg_write(UC_X86_REG_EBX,0);m.reg_write(UC_X86_REG_ECX,case['source'])
    m.reg_write(UC_X86_REG_ESP,stack)
    m.emu_start(0x407ef5,stop,count=4096)
    if m.reg_read(UC_X86_REG_EIP)!=0x407f80:raise ValueError('NPC copy did not reach declared factory boundary')
    expected_index=21+case['occupied'] if case['occupied']<178 else case['source']
    wanted=bytearray(before)
    if case['occupied']<178:wanted[expected_index*0x1fc:(expected_index+1)*0x1fc]=source
    if get(obj+0xa4)!=expected_index or bytes(m.mem_read(live,len(before)))!=bytes(wanted):raise ValueError('NPC slot copy or unrelated records differ')
    return dict(input=case,normal_return=False,entry='0x407ef5',stop_address='0x407f80',
                instructions=steps,copy_return=m.reg_read(UC_X86_REG_EAX),live_index=expected_index,
                copied=case['occupied']<178,source_mode=0x50000,unrelated_records_unchanged=True)

def check(packet):
    if packet.get('schema')!='hsl_ohm_growth_native.v1' or packet.get('exe_sha256')!=EXE_SHA or packet.get('native_execution') is not True:raise ValueError('Ohm source execution identity missing')
    if packet['sources']!={n:digest((TABLES/n).read_bytes()) for n in ['PLAYERS.TXT','ITEM.TXT','TYPE.H','RANGE.H','RANGE.TXT']}:raise ValueError('Ohm source table changed')
    players,_,defines=sources();catalog=equipment_data()['items']
    for key,inputs in [('stats',stat_cases()),('growth',growth_cases()),('rewards',reward_cases()),('ranges',range_cases()),('copies',copy_cases()),('ai',ai_cases())]:
        if [r['input'] for r in packet[key]]!=inputs:raise ValueError('Ohm native coverage changed: '+key)
    for r in packet['stats']:
        c=r['input'];p=source_profile(players[c['actor']],defines);p['source']['mode']=c['mode']
        wanted=calculate(p,c['attributes'],c['level'],c['equipment'],catalog,c['hp'],c['mp'],c['base_move'])
        if r['profile']!=p or len(r['native'])!=2 or any(v['values']!=wanted or not v['normal_return'] or not 0<v['instructions']<12000 for v in r['native']):raise ValueError('Ohm stat return differs')
    for r in packet['growth']:
        if r['native']!=growth_expected(r['input'],r['draws']) or not r['normal_return'] or not r['unrelated_party_unchanged'] or not 0<r['instructions']<200000:raise ValueError('Ohm growth return differs')
    for r in packet['rewards']:
        manual = r['input']['object_kind']==3 and r['input']['exp'] >= 100
        if r['native']!=reward_expected(r['input']) or r['draws'] or r['normal_return'] is manual or r['stop_address']!=('0x442a45' if manual else '0x10000000') or not 0<r['instructions']<200000:raise ValueError('Ohm reward result differs')
    for r in packet['ranges']:
        if r['native']!=range_expected(r['input']) or not r['normal_return'] or not r['actor_unchanged']:raise ValueError('Ohm weapon range result differs')
    for r in packet['copies']:
        c=r['input'];index=21+c['occupied'] if c['occupied']<178 else c['source']
        if r['normal_return'] or r['stop_address']!='0x407f80' or r['live_index']!=index or not r['unrelated_records_unchanged'] or r['source_mode']!=0x50000 or r['copied']!=(c['occupied']<178) or not 0<r['instructions']<4096:raise ValueError('Ohm factory prefix differs')
    for r in packet['ai']:
        if not r['normal_return'] or not 0<r['instructions']<16384 or r['native']!=ai_expected(r['input'],r['draws']):raise ValueError('Villager allegiance result differs')
    if [(a['address'],len(bytes.fromhex(a['bytes'])),a['meaning']) for a in packet['anchors']]!=[(hex(at),n,text) for at,n,text in ANCHORS]:raise ValueError('Ohm anchor identity differs')
    if hashlib.sha256(bytes.fromhex(''.join(a['bytes'] for a in packet['anchors']))).hexdigest()!=ANCHOR_SHA:raise ValueError('Ohm original instruction bytes differ')
    if not packet.get('learning'):raise ValueError('Missing bow learning proof')
    if [r['input'] for r in packet['learning']]!=learning_cases():raise ValueError('Bow learning coverage differs')
    for r in packet['learning']:
        if not r['normal_return'] or r['draws'] or r['native']!=learning_expected(r['input']):raise ValueError('Bow learning output differs')
    expected_table=[dict(tier=r[0],attributes=dict(zip(ATTRIBUTES,r[1:5])),type=r[5],code=r[6]) for r in BOW_SPECIALS]
    table=packet['learning_table']
    expected_bytes=b''.join(struct.pack('<7h',*r) for r in BOW_SPECIALS)+struct.pack('<h',-1)
    if table['rows']!=expected_table or table['tier']!=1 or table['address']!='0x478378' or bytes.fromhex(table['bytes'])!=expected_bytes:raise ValueError('Bow learning source rows differ')


def execute_packet(exe: Path, learning_only: bool = False) -> dict:
    """Run the bounded original instructions on the documented EXE and assemble the packet
    (learning_only: keep the tracked packet and re-execute only the bow learning proof)."""
    base,mapped=image(exe.read_bytes())
    packet=json.loads(PACKET.read_text()) if learning_only else dict(schema='hsl_ohm_growth_native.v1',exe_sha256=EXE_SHA,native_execution=True,evidence_tier='static-derived',
                sources={n:digest((TABLES/n).read_bytes()) for n in ['PLAYERS.TXT','ITEM.TXT','TYPE.H','RANGE.H','RANGE.TXT']},
                stats=[refresh(base,mapped,c) for c in stat_cases()],growth=[grow(base,mapped,c) for c in growth_cases()],
                rewards=[reward_execute(base,mapped,c) for c in reward_cases()],ranges=[range_execute(base,mapped,c) for c in range_cases()],
                copies=[copy_execute(base,mapped,c) for c in copy_cases()],ai=[ai_execute(base,mapped,c) for c in ai_cases()],
                anchors=[dict(address=hex(at),bytes=bytes(mapped[at-base:at-base+n]).hex(),meaning=text) for at,n,text in ANCHORS],
                limits=['New source003/061/062 inputs execute full numeric refresh and growth; this does not execute the source parser or full game boot.',
                        'Kind5 factory prefix stops before object callbacks, after an actual complete44cb10 copy. Combined source mode remains copied, not command authority.',
                        'Source061/062 AI target fixtures prove allegiance; full escape/self-preservation dispatcher remains a separate claim.',
                        'Original global RNG is exercised by growth, not asserted identical to the remake separately saved initialization stream.',
                        'STORY001 has no insert/adjust token or player escape condition. Additional insertion acceptance uses an explicit development event.'])
    packet['learning_table']=learning_table(mapped,base)
    packet['learning']=[learning_execute(base,mapped,c) for c in learning_cases()]
    return packet


def summary_line(packet: dict, executed_now: bool) -> str:
    if not packet.get('learning'):raise ValueError('Missing bow learning proof')
    return 'OHM_GROWTH_NATIVE_PASS '+json.dumps({k:len(packet[k]) for k in ['stats','growth','rewards','ranges','copies','ai','learning']})+' executed_now='+str(executed_now)


TASK = ProbeTask('ohm_growth', PACKET, check, execute_packet, summary_line)


def tasks() -> list[ProbeTask]:
    return [TASK]
