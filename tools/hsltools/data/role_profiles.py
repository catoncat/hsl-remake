"""Build the live role profiles from the tables alone; original files stay read-only.

Registry task role_data (family actors): output content/generated/hsl/roles/profiles.json.
Inputs: PLAYERS.TXT rows (attributes, source template, equipment, declared level), TYPE.H (job／mode
symbols), the equipment catalog, the authored job formula table (through hsltools.model.jobs) and the
authored roster content/authored/roles/roster.json naming which rows become live profiles. Each actor's
`initial` is the model's pre-birth refresh (initial level, declared gear, full vitals); the native
refresh receipts are no longer read here — hsltools.checks.role_profiles_proof compares this output
with them. Adding an actor is its PLAYERS.TXT row plus its code in the roster.
"""
from __future__ import annotations
import json
import re
from pathlib import Path
from hsltools.data import json_bytes
from hsltools.data.equipment import build as equipment_data
from hsltools.model.jobs import ATTRIBUTES, CAMPAIGN_ACTORS, SLOTS, calculate, source_profile
from hsltools.native.sources import sources
from hsltools.paths import ROOT
from hsltools.registry import GeneratedFilesTask, Context
from hsltools.sources.tables import TABLES, digest

OUTPUT = Path('content/generated/hsl/roles/profiles.json')
ROSTER = 'content/authored/roles/roster.json'
ROSTER_SCHEMA = 'hsl_role_roster.v1'
SOURCE_TABLES = ('PLAYERS.TXT', 'ITEM.TXT', 'TYPE.H')
# Field order of the native refresh receipts (the actor record offsets the probes read back).
INITIAL_FIELDS = ('max_hp', 'max_mp', 'current_hp', 'current_mp', 'attack', 'defense', 'speed', 'hit_rate', 'magic_attack',
                  'move_point', 'exp_threshold', 'resist_by_type', 'avoid_hit_ratio', 'attack_back', 'attack_damagex2')


def roster() -> list[str]:
    table = json.loads((ROOT / ROSTER).read_text(encoding='utf-8'))
    if table.get('schema') != ROSTER_SCHEMA:
        raise ValueError(f'{ROSTER}: schema {table.get("schema")!r} is not {ROSTER_SCHEMA}')
    codes = table['actors']
    if not isinstance(codes, list) or any(not isinstance(c, str) or not re.fullmatch(r'\d{3}', c) for c in codes) or len(set(codes)) != len(codes):
        raise ValueError(f'{ROSTER}: actors must be distinct three-digit PLAYERS.TXT codes')
    return codes


def source_rows():
    path=TABLES/'PLAYERS.TXT';raw=path.read_bytes();lines=raw.decode('cp950').splitlines()
    starts=[i for i,line in enumerate(lines) if line.split(';')[0].strip()=='[character]']
    result={}
    for start,end in zip(starts,starts[1:]+[len(lines)]):
        fields={}
        for i in range(start+1,end):
            match=re.match(r'\s*(\w+)\s*=\s*(.+)',lines[i].split(';')[0])
            if match:fields[match[1]]=dict(line=i+1,value=match[2].strip())
        code=fields['code']['value'].zfill(3)
        result[code]=dict(path=path.as_posix(),sha256=digest(raw),start_line=start+1,end_line=end,fields=fields)
    return result


def initial_refresh(row: dict, defines: dict, catalog: dict) -> dict:
    """The pre-birth refresh every native probe ran as its `initial` case: declared level (1 when
    undeclared), declared equipment, full vitals (9999／9999 clamp to the maxima)."""
    profile = source_profile(row, defines)
    values = calculate(profile, {k: int(row[k]) for k in ATTRIBUTES}, int(row.get('level', 1)),
                       [int(row.get(slot, 0)) for slot in SLOTS], catalog, 9999, 9999, int(row.get('move_point', 0)))
    return {key: values[key] for key in INITIAL_FIELDS}


def build():
    players,_,defines=sources();catalog=equipment_data()['items'];rows=source_rows()
    actors={}
    for code in roster():
        if code not in players:raise ValueError(f'{ROSTER}: actor {code} has no PLAYERS.TXT row')
        row=players[code]
        actors[code]=dict(profile=source_profile(row,defines),attributes={k:int(row[k]) for k in ATTRIBUTES},
                          initial=initial_refresh(row,defines,catalog),base_move_point=int(row.get('move_point',0)))
    for code in CAMPAIGN_ACTORS:
        if code not in actors:raise ValueError(f'{ROSTER}: campaign actor {code} is missing from the roster')
        row=players[code]
        actors[code]['evidence_tier']='static-derived'
        actors[code]['source_record']=rows[code]
        actors[code]['job_source']=dict(symbol=row['job'],code=defines[row['job']],path=(TABLES/'TYPE.H').as_posix(),sha256=digest((TABLES/'TYPE.H').read_bytes()))
        actors[code]['initial_level']=dict(value=int(row.get('level',1)),declared='level' in row,
            evidence_tier='resource-derived' if 'level' in row else 'provisional',
            policy='Pre-birth refresh input only. Replace an undeclared level with original level inference and entry adjustment; never assert an encounter level from this value.')
        actors[code]['native_evidence']='docs/evidence_packets/static_reverse/original_campaign_actors.json'
    return dict(schema='hsl_live_role_profiles.v1',evidence_tier='static-derived',sources={n:digest((TABLES/n).read_bytes()) for n in SOURCE_TABLES},
                actors=actors,evidence='docs/evidence_packets/static_reverse/original_job_stats.json',
                limits=['Source mode is independent of battle side/control; these are pre-birth templates, not final encounter levels.',
                        'Job80/83/85/88/90/92/93/94/95/96/98 have full-refresh proofs. Each campaign entry records its PLAYERS row and original execution. Class-change transactions remain separate.'])


class RoleDataTask(GeneratedFilesTask):
    name = 'role_data'
    family = 'actors'
    inputs = ('content/imported/hsl/global/tables/', ROSTER, 'content/authored/roles/job_formulas.json', 'content/generated/hsl/equipment/items.json')
    outputs = (OUTPUT.as_posix(),)
    replaces = ('tools/hsl_role_data.py --check',)
    scripts = ('tools/hsltools/data/role_profiles.py', 'tools/hsltools/model/jobs.py', 'tools/hsltools/data/equipment.py')

    def render(self, ctx: Context) -> dict[str, bytes]:
        return {OUTPUT.as_posix(): json_bytes(build())}

    def summary(self, rendered: dict[str, bytes], mode: str) -> str:
        return 'ROLE_DATA_PASS actors='+str(len(json.loads(rendered[OUTPUT.as_posix()])['actors']))


def tasks() -> list[RoleDataTask]:
    return [RoleDataTask()]
