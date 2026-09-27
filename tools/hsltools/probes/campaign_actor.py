"""Bounded original refresh, growth, learning and party binding for campaign actors.

Original instructions and callees run without substitution. The source records,
party levels and string buffers are explicit fixtures, not a running game.

Registry task campaign_actor (family probe, hsltools.probes._base.ProbeTask): check validates the
tracked packet against the independent model; generate executes the original instructions
(needs the documented hsl01.exe and unicorn). Bodies moved verbatim from the former hsl_native_campaign_actor_probe.py.
"""
from __future__ import annotations
import hashlib
import json
from pathlib import Path
import struct

from hsltools.data.equipment import build as equipment_data
from hsltools.model.jobs import ATTRIBUTES, CAPS, SLOTS, CAMPAIGN_ACTORS, source_profile, calculate
from hsltools.native.image import EXE_SHA, image
from hsltools.native.sources import sources
from hsltools.paths import ROOT
from hsltools.probes._base import ProbeTask
from hsltools.probes.auto_growth import base_case, execute as grow, expected as growth_expected
from hsltools.probes.growth_lifecycle import Machine
from hsltools.probes.job_stats import execute as refresh
from hsltools.probes.priest import execute_binding
from hsltools.sources.tables import TABLES, digest

PACKET = ROOT / 'docs/evidence_packets/static_reverse/original_campaign_actors.json'

MAGIC_LEVELS = {93: [(26,2,2),(40,2,3),(1,2,0),(8,2,4),(12,2,1)],
                95: [], 96: [], 98: [(1,0,0),(5,4,0),(12,0,1),(16,2,4),(19,4,3)]}
SPECIAL_TABLES = {93: (0x4783fc,2), 95: (0x478444,2), 96: (0,0), 98: (0x4784ac,1)}
ANCHORS = [(0x448370,61,'Copy four caps from the job row.'),
           (0x4786bc,160,'Original twenty job cap rows, including93/95/96/98.'),
           (0x44a446,776,'WindWarrior93 resistance and shared WingWarrior numeric branch.'),
           (0x44a8a6,734,'CrazyWarrior95 resistance and shared BeastWarrior numeric branch.'),
           (0x44ab84,610,'MutantMonster96 numeric branch.'),
           (0x44b168,363,'MagicSwordMan98 resistance branch.'),
           (0x44b430,399,'MagicSwordMan family numeric branch and common speed continuation.'),
           (0x44b820,80,'Twenty numeric job dispatch addresses.'),
           (0x4373f0,1408,'Magic learning dispatch including93/95/96/98 and native fall-through order.'),
           (0x437a40,484,'Special learning job dispatch and class tiers.'),
           (0x4783fc,248,'Wing, beast and magic-sword special tables and terminators.'),
           (0x439f80,440,'Original automatic five-point allocation and refresh.'),
           (0x43a128,21,'Automatic allocation job quota dispatch.'),
           (0x42c700,21,'Set a player slot binding.'),
           (0x42caa0,67,'Forward and reverse player slot lookup.'),
           (0x407eff,21,'Player factory prefix obtains the one-based template index.'),
           (0x44cb10,66,'Complete original player template copy.')]
ANCHOR_SHA = 'caaace632d8580e5731de244cad82aea36667161386ead5865b93ff2c20426f2'


def stat_cases():
    players,_,defines=sources();rows=[]
    for code in CAMPAIGN_ACTORS:
        r=players[code];attrs={k:int(r[k]) for k in ATTRIBUTES}
        c=dict(actor=code,attributes=attrs,level=int(r.get('level',1)),
               equipment=[int(r.get(k,0)) for k in SLOTS],hp=9999,mp=9999,
               mode=defines[r['mode']],base_move=int(r.get('move_point',0)),name='initial')
        rows.append(c)
        for level in [2,9,10,19,20,40,99]:rows.append(dict(c,name='level_'+str(level),level=level,hp=1,mp=0))
        for key in ATTRIBUTES:rows.append(dict(c,name=key+'_plus1',attributes=dict(attrs,**{key:attrs[key]+1}),level=2))
        rows.extend([dict(c,name='caps',attributes=dict(zip(ATTRIBUTES,CAPS[defines[r['job']]])),level=99),
                     dict(c,name='other_mode',mode=c['mode']^0x10000,level=12),
                     dict(c,name='unequipped',equipment=[0]*6,level=19,hp=7,mp=3)])
    return rows


def growth_cases():
    rows=[]
    players,_,defines=sources()
    for code in CAMPAIGN_ACTORS:
        if defines[players[code]['job']] in (91, 99):
            continue
        c=base_case(code)
        rows.extend([dict(c,kind='infer'),dict(c,kind='adjust'),
                     dict(c,kind='adjust',range=40,dispersion=3,party=[40,42])])
    players,_,defs=sources()
    for code in ['056','033','008','009']:
        c=base_case(code);caps=dict(zip(ATTRIBUTES,CAPS[defs[players[code]['job']]]))
        for attrs in [c['attributes'],{k:v-1 for k,v in caps.items()},caps]:
            rows.append(dict(c,kind='allocate',attributes=attrs,points=10))
    return rows


def binding_cases():
    return [dict(slot=s,object_code=800+s,previous_template=29) for s in [4,6,7,8]]


def decode_table(job, raw):
    rows=[];address,tier=SPECIAL_TABLES[job]
    if not address:
        if raw:raise ValueError('A no-table job cannot borrow another special table')
    else:
        for index in range(20):
            at=index*14
            if len(raw)<at+2:raise ValueError('Missing special table terminator')
            if struct.unpack_from('<h',raw,at)[0]==-1:
                if len(raw)!=at+2:raise ValueError('Unexpected trailing special table bytes')
                break
            values=struct.unpack_from('<7h',raw,at)
            rows.append(dict(tier=values[0],attributes=dict(zip(ATTRIBUTES,values[1:5])),type=values[5],code=values[6]))
        else:raise ValueError('Unterminated special table')
    return dict(address=hex(address),tier=tier,rows=rows,bytes=raw.hex())


def read_tables(base,mapped):
    result={}
    for job,(address,_) in SPECIAL_TABLES.items():
        size=0
        if address:
            for n in range(20):
                if struct.unpack_from('<h',mapped,address-base+n*14)[0]==-1:
                    size=n*14+2;break
            if not size:raise ValueError('Missing original table terminator')
        result[str(job)]=decode_table(job,bytes(mapped[address-base:address-base+size]) if address else b'')
    return result


def learning_cases(tables):
    rows=[]
    for job,thresholds in MAGIC_LEVELS.items():
        levels={0,1,39,40,98,*[max(0,t-2) for t,_,_ in thresholds],*[t-1 for t,_,_ in thresholds]}
        for level in sorted(levels):
            for existing in [False,True]:rows.append(dict(kind='magic',job=job,level=level,attributes=[30]*4,existing=existing))
        vectors=[[1]*4,[999]*4]
        for row in tables[str(job)]['rows']:
            if row['tier']>tables[str(job)]['tier']:continue
            attrs=list(row['attributes'].values());vectors.append(attrs)
            for i in range(4):
                low=attrs.copy();low[i]-=1;vectors.append(low)
        for attrs in vectors:
            for preview in [False,True]:rows.append(dict(kind='special',job=job,level=1,attributes=attrs,preview=preview,existing=False))
    return rows


def learning_expected(c,tables):
    masks=[0xffffffff if c['existing'] else 0]*(6 if c['kind']=='magic' else 7);before=masks.copy();attempts=[]
    if c['kind']=='magic':
        for level,kind,code in MAGIC_LEVELS[c['job']]:
            if c['level']+1>=level:attempts.append([0,kind,code]);masks[kind]|=1<<code
    else:
        table=tables[str(c['job'])]
        for r in table['rows']:
            if r['tier']<=table['tier'] and all(v>=r['attributes'][k] for k,v in zip(ATTRIBUTES,c['attributes'])):
                attempts.append([1,r['type'],r['code']])
                if not before[r['type']]&(1<<r['code']):
                    if not c['preview']:masks[r['type']]|=1<<r['code']
                    break
    return dict(masks=masks,attempts=attempts,rng_unchanged=True,attributes_unchanged=True)


def learning_execute(base,mapped,c,tables):
    n=Machine(base,mapped,base_case('001'));n.learning_names();a=n.actor
    n.put(a+0x18,c['job']);n.put(a+0x9c,c['level'])
    for i,v in enumerate(c['attributes']):n.put(a+0x64+i*4,v)
    start,count=(0x174,6) if c['kind']=='magic' else (0x158,7)
    for i in range(count):n.put(a+start+i*4,0xffffffff if c['existing'] else 0)
    text=0x10010000 if c['kind']=='magic' or c.get('preview') else 0
    attrs=bytes(n.m.mem_read(a+0x64,16));rng=bytes(n.m.mem_read(0x4c3040,8))
    end,_=n.call(0x4373f0 if c['kind']=='magic' else 0x437a40,[a,text])
    result=dict(masks=[n.get(a+start+i*4) for i in range(count)],attempts=[r['args'][2:5] for r in n.calls],
                rng_unchanged=rng==bytes(n.m.mem_read(0x4c3040,8)),attributes_unchanged=attrs==bytes(n.m.mem_read(a+0x64,16)))
    if n.draws or result!=learning_expected(c,tables):raise ValueError(f'Campaign learner differs: {c}: {result}')
    return dict(input=c,native=result,normal_return=end==n.stop,instructions=n.steps,draws=n.draws)


def fingerprint(anchors):
    return digest(bytes.fromhex(''.join(r['bytes'] for r in anchors)))


def check(p):
    if p.get('schema')!='hsl_campaign_actors_native.v1' or p.get('exe_sha256')!=EXE_SHA or p.get('native_execution') is not True:raise ValueError('Campaign proof identity differs')
    if p.get('sources')!={n:digest((TABLES/n).read_bytes()) for n in ['PLAYERS.TXT','ITEM.TXT','TYPE.H','SHAPEDEF.H','mag-spc.h']}:raise ValueError('Campaign source hashes differ')
    if [(int(r['address'],16),len(bytes.fromhex(r['bytes'])),r['meaning']) for r in p['anchors']]!=ANCHORS:raise ValueError('Campaign anchor coverage differs')
    if not ANCHOR_SHA or fingerprint(p['anchors'])!=ANCHOR_SHA:raise ValueError('Campaign original instruction bytes differ')
    tables=p['special_tables']
    if list(tables)!=[str(j) for j in SPECIAL_TABLES] or p['magic_levels']!={str(j):[list(r) for r in rows] for j,rows in MAGIC_LEVELS.items()}:raise ValueError('Campaign learning job dispatch differs')
    table_bytes=bytes.fromhex(p['anchors'][10]['bytes'])
    for job,table in tables.items():
        raw=bytes.fromhex(table['bytes']);address=SPECIAL_TABLES[int(job)][0]
        if table!=decode_table(int(job),raw) or (address and raw!=table_bytes[address-0x4783fc:address-0x4783fc+len(raw)]):raise ValueError('Campaign special table source differs')
    for key,cases in [('stats',stat_cases()),('growth',growth_cases()),('bindings',binding_cases()),('learning',learning_cases(tables))]:
        if [r['input'] for r in p[key]]!=cases:raise ValueError('Campaign fixture coverage differs: '+key)
    players,_,defines=sources();catalog=equipment_data()['items']
    for row in p['stats']:
        c=row['input'];profile=source_profile(players[c['actor']],defines);profile['source']['mode']=c['mode']
        if row['profile']!=profile or len(row['native'])!=2:raise ValueError('Campaign source profile differs')
        if profile['job_code'] in (91, 99):
            continue
        expected=calculate(profile,c['attributes'],c['level'],c['equipment'],catalog,c['hp'],c['mp'],c['base_move'])
        for r in row['native']:
            if r['values']!=expected or r['normal_return'] is not True or not 0<r['instructions']<12000:raise ValueError('Campaign refresh return differs')
    for row in p['growth']:
        if row['native']!=growth_expected(row['input'],row['draws']) or row['normal_return'] is not True or row['unrelated_party_unchanged'] is not True or not 0<row['instructions']<200000:raise ValueError('Campaign growth return differs')
    for row in p['bindings']:
        c=row['input'];index=c['slot']+1
        if (row['template_index'],row['copy_return'],row['object_code'],row['normal_returns'],row['prefix_entry'],row['prefix_stop'])!=(index,index,c['object_code'],4,'0x407eff','0x407f14'):raise ValueError('Campaign player binding differs')
        if row['live_sha256']!=row['template_sha256'] or row['template_sha256']!=digest(bytes((i*13+index)%256 for i in range(0x1fc))):raise ValueError('Campaign player copy differs')
    for row in p['learning']:
        if row['native']!=learning_expected(row['input'],tables) or row['normal_return'] is not True or row['draws'] or not 0<row['instructions']<200000:raise ValueError('Campaign learner return differs')


def execute_packet(exe: Path) -> dict:
    """Run the bounded original instructions on the documented EXE and assemble the packet."""
    base,mapped=image(exe.read_bytes());tables=read_tables(base,mapped)
    p=dict(schema='hsl_campaign_actors_native.v1',evidence_tier='static-derived',exe_sha256=EXE_SHA,native_execution=True,
           sources={n:digest((TABLES/n).read_bytes()) for n in ['PLAYERS.TXT','ITEM.TXT','TYPE.H','SHAPEDEF.H','mag-spc.h']},
           anchors=[dict(address=hex(at),bytes=bytes(mapped[at-base:at-base+size]).hex(),meaning=meaning) for at,size,meaning in ANCHORS],
           magic_levels={str(j):[list(r) for r in rows] for j,rows in MAGIC_LEVELS.items()},special_tables=tables,
           stats=[refresh(base,mapped,c) for c in stat_cases()],growth=[grow(base,mapped,c) for c in growth_cases()],
           bindings=[execute_binding(base,mapped,c) for c in binding_cases()],learning=[learning_execute(base,mapped,c,tables) for c in learning_cases(tables)],
           limits=['Synthetic source records; no complete parser, object constructor, original GUI or full dispatcher.',
                   'Unspecified level1/EXP0 are explicit pre-birth construction inputs; entry adjustment owns actual encounter levels.',
                   'Normal refresh/growth/learning returns and bounded factory prefixes are recorded separately. No original callee is replaced.',
                   'New job formulas and learning tables do not implement class-change transactions or all learned skill effects.',
                   'Positive attributes and reviewed equipment only; negative/overflow domains and global random-stream equivalence remain unclaimed.'])
    return p


def summary_line(p: dict, executed_now: bool) -> str:
    return f'CAMPAIGN_ACTORS_NATIVE_PASS actors={len(CAMPAIGN_ACTORS)} full_refresh={len(p["stats"])*2} growth={len(p["growth"])} learning={len(p["learning"])} binding_helpers={len(p["bindings"])*4} executed_now={executed_now}'


TASK = ProbeTask('campaign_actor', PACKET, check, execute_packet, summary_line)


def tasks() -> list[ProbeTask]:
    return [TASK]
