"""Compile the runtime learning book: per-actor declared masks and per-job learning tables.

Registry task growth_lifecycle_data (family actors): output content/generated/hsl/roles/growth_lifecycle.json.
Inputs are tables only — PLAYERS.TXT (declared masks), MAGIC.TXT／SPECIAL.TXT／RESOURCE.TXT (ability ids
and names) and the authored content/authored/roles/learning_tables.json (per-job magic levels, special rows,
class tier). The native learning packets are no longer read for content; hsltools.checks.learning_tables_proof
compares this table with their receipts, and their sha256 is carried through as the proof ledger.
Adding a job's learning rows is a data row in the authored table; a row may name an authored skill
(content/authored/roles/skills.json, hsltools.data.authored_skills), whose name it resolves here.
"""
from __future__ import annotations
import hashlib
import json
from pathlib import Path
from hsltools.data import json_bytes
from hsltools.data import authored_skills
from hsltools.data.skill_book import aliases, declared_mask
from hsltools.paths import ROOT
from hsltools.registry import GeneratedFilesTask, Context
from hsltools.sources.tables import TABLES, blocks, character_rows, parse_table

OUT=Path('content/generated/hsl/roles/growth_lifecycle.json')
LEARNING='content/authored/roles/learning_tables.json'
LEARNING_SCHEMA='hsl_learning_tables.v1'
ELEMENTS=['magicEARTH','magicWATER','magicAIR','magicFIRE','magicMIND','magicOTHER','magicOTHER2']
FIELDS=['earth','water','wind','fire','mind','other','other2']
# Evidence ledger carried through unchanged: the native learning receipts this table is checked against
# (hsltools.checks.learning_tables_proof); only their hashes are read here.
PROOF_PACKETS={'proof_sha256':'docs/evidence_packets/static_reverse/original_growth_lifecycle.json',
               'bow_proof_sha256':'docs/evidence_packets/static_reverse/original_ohm_growth.json',
               'campaign_proof_sha256':'docs/evidence_packets/static_reverse/original_campaign_actors.json',
               'job_up_proof_sha256':'docs/evidence_packets/static_reverse/original_job_up_learning.json'}


def identity(channel,element,code):
    return f'{channel}:{ELEMENTS[element]}:magicCode{code+1:02d}'


def learning_tables() -> dict:
    """The authored per-job learning table, validated: {job code string: {tier, magic, special}}."""
    table=json.loads((ROOT/LEARNING).read_text(encoding='utf-8'))
    if table.get('schema')!=LEARNING_SCHEMA:raise ValueError(f'{LEARNING}: schema {table.get("schema")!r} is not {LEARNING_SCHEMA}')
    for job,row in table['jobs'].items():
        if not job.isdecimal():raise ValueError(f'{LEARNING}: job key {job!r} is not a numeric job code')
        if not isinstance(row.get('tier'),int) or row['tier']<0 or (row['tier']==0 and row.get('special')):
            raise ValueError(f'{LEARNING}: job {job} tier must be a positive integer (0 only for a job with no special rows)')
        for entry in row.get('magic',[]):
            if not isinstance(entry.get('id'),str) or not entry['id'].startswith('magic:') or not isinstance(entry.get('level'),int):
                raise ValueError(f'{LEARNING}: job {job} magic entry {entry!r} needs a magic:… id and an integer level')
        for entry in row.get('special',[]):
            if (not isinstance(entry.get('id'),str) or not entry['id'].startswith('special:') or not isinstance(entry.get('tier'),int)
                    or not isinstance(entry.get('attributes'),dict) or list(entry['attributes'])!=['str','dex','mind','con']
                    or not all(isinstance(v,int) for v in entry['attributes'].values())):
                raise ValueError(f'{LEARNING}: job {job} special entry {entry!r} needs a special:… id, an integer tier and str dex mind con attributes')
    return table['jobs']


def definitions() -> dict[str,str]:
    """{ability id: display name} for every MAGIC.TXT／SPECIAL.TXT row and every authored skill."""
    names=parse_table(Path('content/imported/hsl/chapter01/source_texts/RESOURCE.TXT').read_bytes())
    result={}
    for channel,filename in [('magic','MAGIC.TXT'),('special','SPECIAL.TXT')]:
        for row in blocks((TABLES/filename).read_bytes(),channel):
            result[f'{channel}:{row["type"]}:{row["code"]}']=names[row['name']]
    result.update(authored_skills.names())
    return result


def build():
    symbols=aliases();actors={}
    authored_names=frozenset(authored_skills.names().values())
    for actor in character_rows():
        masks={}
        for channel in ['magic','special']:
            for element,field in enumerate(FIELDS[:6 if channel=='magic' else 7]):
                masks[f'{channel}:{ELEMENTS[element]}']=declared_mask(actor.get(channel+'_'+field,'0'),symbols,authored_names)
        actors[f'{int(actor["code"]):03d}']=masks
    defined=definitions()
    jobs={}
    for job,table in learning_tables().items():
        rows=[]
        for entry in table['magic']:
            if entry['id'] not in defined:raise ValueError('Missing learned magic definition '+entry['id'])
            rows.append(dict(id=entry['id'],name=defined[entry['id']],level=entry['level']))
        specials=[]
        for entry in table['special']:
            if entry['id'] not in defined:raise ValueError('Missing learned special definition '+entry['id'])
            specials.append(dict(id=entry['id'],name=defined[entry['id']],tier=entry['tier'],attributes=entry['attributes']))
        jobs[job]=dict(magic=rows,special=specials,tier=table['tier'])
    proofs={key:hashlib.sha256((ROOT/path).read_bytes()).hexdigest() for key,path in PROOF_PACKETS.items()}
    return dict(schema='hsl_growth_lifecycle.v1',policy='source_growth_lifecycle_v1',evidence_tier='static-derived',
                **proofs,
                source_hashes={n:hashlib.sha256((TABLES/n).read_bytes()).hexdigest() for n in ['PLAYERS.TXT','MAGIC.TXT','SPECIAL.TXT','mag-spc.h']},
                actors=actors,jobs=jobs,
                limits=['Thresholds for twenty reviewed jobs80..99. Up-tier jobs81/82/84/86/87/89/93/95/99 reuse the base-job special table at class tier2/3 and fall through into the base-job magic thresholds;97 has its own two-row table;90/91/96 learn no special;80/83/84/88/89/94..97 learn no magic.',
                        'A learner reads the member\'s current job code: after a job-up the up-tier table applies to later level-ups/allocations; records learned under the previous job stay under that job.',
                        'Magic checks the incoming level; special commits one missing eligible bit after base-point allocation.',
                        'NPC automatic allocation does not learn player abilities. Initial declarations and learned masks are independent.',
                        'Source learned but unimplemented abilities remain recorded and unavailable, never mapped to a substitute.'])


class GrowthLifecycleDataTask(GeneratedFilesTask):
    name = 'growth_lifecycle_data'
    family = 'actors'
    inputs = ('content/imported/hsl/global/tables/', 'content/imported/hsl/chapter01/source_texts/RESOURCE.TXT', LEARNING,
              *PROOF_PACKETS.values())
    outputs = (OUT.as_posix(),)
    replaces = ('tools/hsl_growth_lifecycle_data.py --check',)
    scripts = ('tools/hsltools/data/growth_lifecycle.py',)

    def render(self, ctx: Context) -> dict[str, bytes]:
        return {OUT.as_posix(): json_bytes(build())}

    def summary(self, rendered: dict[str, bytes], mode: str) -> str:
        data = json.loads(rendered[OUT.as_posix()])
        return f"GROWTH_LIFECYCLE_DATA_PASS {len(data['actors'])} {len(data['jobs'])}"


def tasks() -> list[GrowthLifecycleDataTask]:
    return [GrowthLifecycleDataTask()]
