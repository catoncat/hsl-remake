"""Bounded original player learning for the job-up tier codes 81/82/84/86/87/89/91/97/99.

The town/battle job-up writes the up-tier code into actor+0x18; this executes the
original magic learner 0x4373f0 and special learner 0x437a40 with those codes on
the same synthetic actor/string fixtures as the base-job proof. Up-tier magic
cases fall through into the base-job case (native order kept), up-tier special
cases reuse the base-job table with a higher class tier; 97 has its own table.
No callee is skipped, patched or replaced.

Registry task job_up_learning (family probe, PacketTask): check validates the tracked
packet against the independent expectations; generate executes the original learners
(needs the documented hsl01.exe and unicorn). Bodies moved verbatim from the former hsl_native_job_up_learning_probe.py.
"""
from __future__ import annotations
import json
from pathlib import Path
import struct

from hsltools.model.jobs import ATTRIBUTES
from hsltools.native.image import EXE_SHA, image
from hsltools.paths import ROOT, TABLES
from hsltools.probes.auto_growth import base_case
from hsltools.probes.campaign_actor import MAGIC_LEVELS as CAMPAIGN_MAGIC
from hsltools.probes.growth_lifecycle import Machine, MAGIC_LEVELS as BASE_MAGIC
from hsltools.registry import Context, PacketTask
from hsltools.sources.tables import digest

PACKET = ROOT/'docs/evidence_packets/static_reverse/original_job_up_learning.json'
# Native fall-through order: the up-tier case body first, then the base case it jumps into.
MAGIC_LEVELS = {
    81: [(24,1,5),(31,1,6),(34,5,0)],
    82: [(45,1,7),(24,1,5),(31,1,6),(34,5,0)],
    84: [],
    86: [(26,3,5),(28,0,6),(30,0,7),(32,1,7),*BASE_MAGIC[85]],
    87: [(48,5,3),(48,0,8),(56,5,2),(26,3,5),(28,0,6),(30,0,7),(32,1,7),*BASE_MAGIC[85]],
    89: [],
    91: [(25,3,2),(25,2,2),(27,1,2),(27,1,6),(30,0,2),(39,3,3),(40,1,3),*BASE_MAGIC[90]],
    97: [],
    99: [(26,0,4),(27,4,1),(28,0,2),(30,4,2),(37,0,3),(42,4,4),*CAMPAIGN_MAGIC[98]],
}
SPECIAL_TABLES = {81:(0x4782b0,2),82:(0x4782b0,3),84:(0x478378,2),86:(0x478314,2),87:(0x478314,3),
                  89:(0x4783c0,2),91:(0,0),97:(0x47848c,2),99:(0x4784ac,2)}
ANCHORS = [
    (0x4373f0,1408,'Magic learner: job-81 index bytes at437950 (81→0,82→1,85→2,86→3,87→4,90→5,91→6,92→7,93→8,98→9,99→10, others no magic), case table at437920; up-tier cases fall through into the base-job case.'),
    (0x437a40,484,'Special learner jump table at437bd4 for job-80 in0..19: 81/82 warrior table tier2/3, 84 bow tier2, 86/87 priest tier2/3, 89 thief tier2, 93 wing tier2, 95 beast tier2, 97 own table tier2, 99 magic-sword tier2; 90/91/96 no table.'),
    (0x4782b0,332,'Warrior, priest, bow and thief special tables with terminators.'),
    (0x4783fc,248,'Wing, beast, job97 and magic-sword special tables with terminators.'),
]
ANCHOR_SHA = '36c8f0e67dadc0564a260151aff262dc3a19bf811020578b47a3bc5efe1e4161'


def read_tables(base,mapped):
    result={}
    for job,(address,tier) in SPECIAL_TABLES.items():
        rows=[];raw=b''
        if address:
            for index in range(20):
                at=address-base+index*14
                if struct.unpack_from('<h',mapped,at)[0]==-1:
                    raw=bytes(mapped[address-base:at+2]);break
                values=struct.unpack_from('<7h',mapped,at)
                rows.append(dict(tier=values[0],attributes=dict(zip(ATTRIBUTES,values[1:5])),type=values[5],code=values[6]))
            else:raise ValueError('Unterminated job-up special table')
        result[str(job)]=dict(address=hex(address),tier=tier,rows=rows,bytes=raw.hex())
    return result


def decode_table(job,raw):
    address,tier=SPECIAL_TABLES[job];rows=[]
    if not address:
        if raw:raise ValueError('A no-table job cannot borrow another special table')
    else:
        if len(raw)<2 or raw[-2:]!=b'\xff\xff' or (len(raw)-2)%14:raise ValueError('Job-up special table shape differs')
        for values in struct.iter_unpack('<7h',raw[:-2]):
            rows.append(dict(tier=values[0],attributes=dict(zip(ATTRIBUTES,values[1:5])),type=values[5],code=values[6]))
    return dict(address=hex(address),tier=tier,rows=rows,bytes=raw.hex())


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
    if n.draws or result!=learning_expected(c,tables):raise ValueError(f'Job-up learner differs: {c}: {result}')
    return dict(input=c,native=result,normal_return=end==n.stop,instructions=n.steps,draws=n.draws)


def fingerprint(anchors):
    return digest(bytes.fromhex(''.join(r['bytes'] for r in anchors)))


def check(p):
    if p.get('schema')!='hsl_job_up_learning_native.v1' or p.get('exe_sha256')!=EXE_SHA or p.get('native_execution') is not True:raise ValueError('Job-up learning proof identity differs')
    if p.get('sources')!={n:digest((TABLES/n).read_bytes()) for n in ['PLAYERS.TXT','MAGIC.TXT','SPECIAL.TXT','mag-spc.h']}:raise ValueError('Job-up learning source hashes differ')
    if [(int(r['address'],16),len(bytes.fromhex(r['bytes'])),r['meaning']) for r in p['anchors']]!=ANCHORS:raise ValueError('Job-up learning anchor coverage differs')
    if not ANCHOR_SHA or fingerprint(p['anchors'])!=ANCHOR_SHA:raise ValueError('Job-up learning original instruction bytes differ')
    tables=p['special_tables']
    if list(tables)!=[str(j) for j in SPECIAL_TABLES] or p['magic_levels']!={str(j):[list(r) for r in rows] for j,rows in MAGIC_LEVELS.items()}:raise ValueError('Job-up learning job dispatch differs')
    table_bytes={0x4782b0:bytes.fromhex(p['anchors'][2]['bytes']),0x4783fc:bytes.fromhex(p['anchors'][3]['bytes'])}
    for job,table in tables.items():
        raw=bytes.fromhex(table['bytes']);address=SPECIAL_TABLES[int(job)][0]
        if table!=decode_table(int(job),raw):raise ValueError('Job-up special table decode differs')
        if address:
            block=0x4782b0 if address<0x4783fc else 0x4783fc
            if raw!=table_bytes[block][address-block:address-block+len(raw)]:raise ValueError('Job-up special table source differs')
    if [r['input'] for r in p['learning']]!=learning_cases(tables):raise ValueError('Job-up learning coverage differs')
    for row in p['learning']:
        if row['native']!=learning_expected(row['input'],tables) or row['normal_return'] is not True or row['draws'] or not 0<row['instructions']<200000:raise ValueError('Job-up learner return differs')


def execute_packet(exe: Path) -> dict:
    """Run the original learners on the documented EXE and assemble the packet."""
    base,mapped=image(exe.read_bytes());tables=read_tables(base,mapped)
    return dict(schema='hsl_job_up_learning_native.v1',evidence_tier='static-derived',exe_sha256=EXE_SHA,native_execution=True,
           sources={n:digest((TABLES/n).read_bytes()) for n in ['PLAYERS.TXT','MAGIC.TXT','SPECIAL.TXT','mag-spc.h']},
           anchors=[dict(address=hex(at),bytes=bytes(mapped[at-base:at-base+size]).hex(),meaning=meaning) for at,size,meaning in ANCHORS],
           magic_levels={str(j):[list(r) for r in rows] for j,rows in MAGIC_LEVELS.items()},special_tables=tables,
           learning=[learning_execute(base,mapped,c,tables) for c in learning_cases(tables)],
           limits=['Learners run on the synthetic actor/string fixtures of the base-job proof; the job-up transaction itself (0x4348f0) is a separate packet.',
                   'Magic uses job and stored level+1; special uses the base-job table with the up-tier class tier and commits one missing bit per call.',
                   'Up-tier magic includes the base-job thresholds by native fall-through; already learned bits are preserved, not re-granted.',
                   'No claim about the original level-up UI, message timing, or when a job-up member re-checks thresholds without a level-up.'])


def summary_line(p: dict, executed_now: bool) -> str:
    return f'JOB_UP_LEARNING_NATIVE_PASS jobs={len(MAGIC_LEVELS)} learning={len(p["learning"])} executed_now={executed_now}'


class JobUpLearningTask(PacketTask):
    name = 'job_up_learning'
    family = 'probe'
    packet = PACKET.relative_to(ROOT).as_posix()
    outputs = (packet,)
    inputs = ('content/imported/hsl/global/tables/',)
    replaces = ('tools/hsl_native_job_up_learning_probe.py',)
    scripts = ('tools/hsltools/probes/job_up_learning.py',)

    def validate(self, packet: dict) -> None:
        check(packet)

    def execute(self, ctx: Context) -> dict:
        return execute_packet(ctx.original_exe)

    def summary(self, packet: dict, executed_now: bool) -> str:
        return summary_line(packet, executed_now)


def tasks() -> list[JobUpLearningTask]:
    return [JobUpLearningTask()]
