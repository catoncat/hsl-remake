"""Join live role sources to their PLAYERS.TXT entry-adjustment parameters.

Registry task entry_growth_data (family actors): output content/generated/hsl/roles/entry_growth.json.
Inputs are the tables and the job formula table (which jobs exist); the native auto-growth packet is
checked by its own probe task (`hsl check auto_growth`), not read here.
"""
from __future__ import annotations
import json
from pathlib import Path
from hsltools.data import json_bytes
from hsltools.model.jobs import formulas, ATTRIBUTES
from hsltools.native.sources import sources
from hsltools.registry import GeneratedFilesTask, Context
from hsltools.sources.tables import TABLES, digest

OUT = Path('content/generated/hsl/roles/entry_growth.json')

def build():
    players,_,defines=sources();actors={}
    for code,row in players.items():
        if defines.get(row.get('job')) not in formulas():continue
        fields=['level_adjust_range','level_adjust_disp_range']
        # The PLAYERS parser presets each output to 0 (ebp) before reading a field
        # (0x44ca5c level_adjust_range, 0x44ca8f level_adjust_disp_range — the idiom whose
        # missing-field zeros original_large_actor.json executes for the six AI rates), so an
        # undeclared pair installs +0x1f8 = 0,0: no level adjustment (PLAYERS 67, the gems).
        actors[code]={'job_code':defines[row['job']], 'attributes':{k:int(row[k]) for k in ATTRIBUTES},
                      'parameters':[int(row.get(k,0)) for k in fields],
                      'parameters_declared':all(k in row for k in fields), 'gold':int(row.get('gold',0)),
                      'kill_exp':int(row.get('kill_exp',0))}
    return {'schema':'hsl_entry_growth_sources.v1','evidence_tier':'resource-derived',
            'source_sha256':digest((TABLES/'PLAYERS.TXT').read_bytes()),'actors':actors,
            'native_evidence':'docs/evidence_packets/static_reverse/original_auto_growth.json',
            'limits':['Only reviewed numeric jobs are represented. Undeclared adjustment parameters read 0,0 like the original parser (static-derived, 0x44ca5c／0x44ca8f preset idiom); parameters_declared keeps which rows declare them.',
                      'Runtime activation is limited to new script reinforcements with reviewed source data. Existing initial/control actors retain their separately documented policy.']}


class EntryGrowthDataTask(GeneratedFilesTask):
    name = 'entry_growth_data'
    family = 'actors'
    inputs = ('content/imported/hsl/global/tables/', 'content/authored/roles/job_formulas.json')
    outputs = (OUT.as_posix(),)
    replaces = ('tools/hsl_entry_growth_data.py --check',)
    scripts = ('tools/hsltools/data/entry_growth.py', 'tools/hsltools/model/jobs.py')

    def render(self, ctx: Context) -> dict[str, bytes]:
        return {OUT.as_posix(): json_bytes(build())}

    def summary(self, rendered: dict[str, bytes], mode: str) -> str:
        result = json.loads(rendered[OUT.as_posix()])
        return f'ENTRY_GROWTH_DATA_PASS actors={len(result["actors"])}'


def tasks() -> list[EntryGrowthDataTask]:
    return [EntryGrowthDataTask()]
