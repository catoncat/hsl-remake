"""Full native job80/90/94 stat refresh, with independent model and source joins.

Registry task job_stats (family probe, hsltools.probes._base.ProbeTask): check validates the
tracked packet against the independent model; generate executes the original instructions
(needs the documented hsl01.exe and unicorn). Bodies moved verbatim from the former hsl_native_job_stats_probe.py.
"""
from __future__ import annotations
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
from hsltools.sources.tables import TABLES, digest

PACKET = ROOT / 'docs/evidence_packets/static_reverse/original_job_stats.json'

ACTORS = ('001','021','023','024','025','026')
ANCHORS = [(0x448840,39,'Source mode bit10000 controls the level term in maximum HP, not player commandability.'),
           (0x448370,61,'Job-indexed four attribute caps.'),
           (0x4786bc,160,'Twenty cap-table rows; only three current job branches are enabled.'),
           (0x448800,64,'Piecewise attack level bonus is separate from the mode-gated HP level.'),
           (0x449e9c,32,'Magician job branch entry selected by original dispatch table.'),
           (0x44a74e,32,'BeastWarrior job branch entry selected by original dispatch table.'),
           (0x44b62c,492,'Shared current-value clamps, source additions, resist/movement caps and learned-magic presence.')]


def fixtures():
    players,_,defines=sources()
    rows=[]
    for code in ACTORS:
        row=players[code]
        attrs={k:int(row[k]) for k in ATTRIBUTES}
        gear=[int(row.get(s,0)) for s in SLOTS]
        base=dict(actor=code,attributes=attrs,level=int(row['level']),equipment=gear,hp=9999,mp=9999,
                  mode=defines[row['mode']],base_move=int(row['move_point']))
        rows.append(dict(base,name='initial'))
        for level in (2,9,10,19,20,40,99):
            rows.append(dict(base,name='level_'+str(level),level=level,hp=1,mp=0))
        for key in ATTRIBUTES:
            grown=attrs.copy();grown[key]+=1
            rows.append(dict(base,name=key+'_plus1',attributes=grown,level=2,hp=17,mp=3))
        rows.append(dict(base,name='caps',attributes=dict(zip(ATTRIBUTES,CAPS[defines[row['job']]])),level=99))
        rows.append(dict(base,name='other_source_mode',mode=base['mode'] ^ 0x10000,level=12))
        rows.append(dict(base,name='empty_equipment',equipment=[0]*6,level=19,hp=7,mp=3))
        for label,last in [('two_resists',[201,201]),('resources',[223,224]),('half_repeat',[218,227])]:
            rows.append(dict(base,name=label,equipment=gear[:4]+last,level=20,hp=13,mp=2))
    return rows


def execute(base,mapped,case):
    from unicorn import Uc,UC_ARCH_X86,UC_MODE_32,UC_HOOK_CODE
    from unicorn.x86_const import UC_X86_REG_EIP,UC_X86_REG_ESP
    players,items,defines=sources(); row=players[case['actor']]
    profile=source_profile(row,defines);profile['source']['mode']=case['mode']
    m=Uc(UC_ARCH_X86,UC_MODE_32);m.mem_map(base,len(mapped));m.mem_write(base,bytes(mapped))
    for start,size in [(0x10000000,0x10000),(0x20000000,0x10000),(0x21000000,0x20000)]:m.mem_map(start,size)
    actor,stack,stop=0x20000000,0x1000ff00,0x10000000
    def put(at,v):m.mem_write(at,struct.pack('<I',v & 0xffffffff))
    def get(at):return struct.unpack('<i',m.mem_read(at,4))[0]
    for key,off in [('str',0x64),('dex',0x68),('mind',0x6c),('con',0x70)]:put(actor+off,case['attributes'][key])
    for key,off in [('attack_power',0x1a4),('magic_attack_power',0x1a8),('defense',0x1ac),('speed',0x1b0),
                    ('avoid_hit_ratio',0x198),('attack_back',0x19c),('attack_damagex2',0x1a0)]:put(actor+off,profile['source'][key])
    put(actor+0x18,profile['job_code']);put(actor+0x28,case['mode']);put(actor+0x9c,case['level'])
    put(actor+0xd8,case['hp']);put(actor+0xe0,case['mp']);put(actor+0x130,case['base_move'])
    put(actor+0x1b4,(int(row.get('hit_point',0))<<16)|int(row.get('magic_point',0)))
    for i in range(5):put(actor+0x118+i*4,profile['source']['base_resist_by_type'][str(i)])
    if profile['source']['has_magic']:put(actor+0x174,1)
    put(actor+0x88,37);put(actor+0xe8,20);put(0x4c1b40,0x21000000)
    for index,code in enumerate(case['equipment']):
        put(actor+0xec+index*4,code)
        if not code:continue
        item=items[code];at=0x21000000+176*code
        put(at+8,defines[item['type']]);put(at+0x10,-1);put(at+0x8c,-1)
        if 'add_resist' in item:
            kind,amount=[v.strip() for v in item['add_resist'].split(',')]
            put(at+0x10,defines[kind]);put(at+0x14,int(amount))
        for key,off in [('attack_damage',0x88),('hit_ratio',0x98),('add_weapon_hit',0x18),
                        ('add_attack_power',0x20),('add_magic_power',0x24),('add_mp',0x28),('add_hp',0x2c),
                        ('add_move',0x34),('add_speed',0x38),('add_defense',0x3c),
                        ('add_miss_hit',0x44),('add_attack_back',0x48),('add_weapon_dmgx2',0x4c)]:put(at+off,int(item.get(key,0)))
        put(at+0xa0,sum(bit for key,bit in [('mp_use_half',2),('action_twice',8),('hp_auto_restore',256),('mp_auto_restore',512)] if int(item.get(key,0))))
    steps=0
    def guard(_m,address,_size,_data):
        nonlocal steps
        steps+=1
        if not 0x448370<=address<0x44b820:raise ValueError(f'Unreviewed stat callee {address:#x}')
    m.hook_add(UC_HOOK_CODE,guard)
    outputs=[]
    for repeat in range(2):
        # The second refresh starts with deliberately stale derived values.
        for off in [0xb4,0xb8,0xbc,0xc0,0xd0,0x12c]:put(actor+off,12345)
        previous=steps;put(stack,stop);put(stack+4,actor);m.reg_write(UC_X86_REG_ESP,stack)
        m.emu_start(0x448840,stop,count=12000)
        if m.reg_read(UC_X86_REG_EIP)!=stop or m.reg_read(UC_X86_REG_ESP)!=stack+4:raise ValueError('Refresh failed bounded full return')
        result={key:get(actor+off) for key,off in [('max_hp',0xdc),('max_mp',0xe4),('current_hp',0xd8),('current_mp',0xe0),
                  ('attack',0xc0),('defense',0xb4),('speed',0xb8),('hit_rate',0xbc),('magic_attack',0xd0),('move_point',0x12c),('exp_threshold',0x8c)]}
        result['resist_by_type']={str(i):get(actor+0x104+4*i) for i in range(5)}
        for key,off in [('avoid_hit_ratio',0x19a),('attack_back',0x19e),('attack_damagex2',0x1a2)]:result[key]=struct.unpack('<H',m.mem_read(actor+off,2))[0]
        expected=calculate(profile,case['attributes'],case['level'],case['equipment'],equipment_data()['items'],case['hp'],case['mp'],case['base_move'])
        if result!=expected:raise ValueError(f'Job model mismatch {case}: {result} != {expected}')
        if [get(actor+0x74+i*4) for i in range(4)]!=CAPS[profile['job_code']]:raise ValueError('Native cap table differs')
        if get(actor+0x88)!=37 or get(actor+0xe8)!=20:raise ValueError('Refresh mutated EXP or ST')
        outputs.append(dict(values=result,instructions=steps-previous,normal_return=True))
    return dict(input=case,profile=profile,native=outputs)


def check(packet):
    if packet.get('schema')!='hsl_native_job_stats.v1' or packet.get('exe_sha256')!=EXE_SHA or packet.get('native_execution') is not True:raise ValueError('Job proof identity differs')
    if packet['sources']!={n:digest((TABLES/n).read_bytes()) for n in ('PLAYERS.TXT','ITEM.TXT','TYPE.H')}:raise ValueError('Job source hashes differ')
    if [r['input'] for r in packet['cases']]!=fixtures():raise ValueError('Job case coverage differs')
    players,_,defines=sources();catalog=equipment_data()['items']
    for row in packet['cases']:
        c=row['input'];profile=source_profile(players[c['actor']],defines);profile['source']['mode']=c['mode']
        if row['profile']!=profile or len(row['native'])!=2:raise ValueError('Job profile differs')
        expected=calculate(profile,c['attributes'],c['level'],c['equipment'],catalog,c['hp'],c['mp'],c['base_move'])
        for result in row['native']:
            if result['values']!=expected or result['normal_return'] is not True or not 0<result['instructions']<12000:raise ValueError('Job full return differs')
    if [(int(r['address'],16),len(bytes.fromhex(r['bytes'])),r['meaning']) for r in packet['anchors']]!=ANCHORS:raise ValueError('Job anchors differ')
    if hashlib.sha256(bytes.fromhex(''.join(r['bytes'] for r in packet['anchors']))).hexdigest()!='755b75da078ae60b5c5edcb2a6b938b9aafc1d6ca970bdc8af19d7233800e342':raise ValueError('Original job instruction bytes differ')
    raw=bytes.fromhex(packet['anchors'][2]['bytes'])
    for job in range(80,80+len(raw)//8):  # every native cap row must be the table's row for that job
        if list(struct.unpack_from('<4H',raw,(job-80)*8))!=CAPS[job]:raise ValueError('Native cap bytes differ')


def execute_packet(exe: Path) -> dict:
    """Run the bounded original instructions on the documented EXE and assemble the packet."""
    base,mapped=image(exe.read_bytes())
    packet=dict(schema='hsl_native_job_stats.v1',evidence_tier='static-derived',exe_sha256=EXE_SHA,native_execution=True,
                sources={n:digest((TABLES/n).read_bytes()) for n in ('PLAYERS.TXT','ITEM.TXT','TYPE.H')},
                cases=[execute(base,mapped,c) for c in fixtures()],
                anchors=[dict(address=hex(at),bytes=bytes(mapped[at-base:at-base+size]).hex(),meaning=meaning) for at,size,meaning in ANCHORS],
                limits=['Original full refresh on synthetic source-table fields; no native parser, initial level RNG or gameplay execution.',
                        'Three current jobs only. Source pm mode gates one HP level term; command authority is independent.',
                        'Fixed NPC progression remains a remake policy. Extra source jobs, weakness/buffs and transfer passives remain separate.',
                        'Empty-equipment cases prove numeric refresh only; unarmed product attack geometry is not enabled.'])
    return packet


def summary_line(packet: dict, executed_now: bool) -> str:
    return f'JOB_STATS_NATIVE_PASS cases={len(packet["cases"])} full_returns={2*len(packet["cases"])} executed_now={executed_now}'


TASK = ProbeTask('job_stats', PACKET, check, execute_packet, summary_line)


def tasks() -> list[ProbeTask]:
    return [TASK]
