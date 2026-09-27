"""Project the authored job formula table onto the runtime table the Godot rules read.

Registry task job_formulas (family actors): content/authored/roles/job_formulas.json (author-editable
per-job stat coefficients, caps, allocation quotas; the only place a job's arithmetic is written)
→ content/generated/hsl/roles/job_formulas.json, the same rows validated (hsltools.model.jobs) and
joined to their job symbol: the TYPE.H `#define job...` for the original codes, the row's own
`symbol` for an authored job (hsltools.model.jobs.authored_job_symbols). JobStatsRules.gd /
EntryGrowthRules.gd / EquipmentRules.gd read the generated file; hsltools.model.jobs reads the authored one. Adding a job is one row in the
authored file plus `hsl generate job_formulas`.
"""
from __future__ import annotations

import json
import re
from pathlib import Path

from hsltools.data import json_bytes
from hsltools.model.jobs import FORMULAS, FORMULAS_SCHEMA, authored_job_symbols, formulas
from hsltools.paths import ROOT
from hsltools.registry import Context, GeneratedFilesTask
from hsltools.sources.tables import TABLES, digest

OUT = Path('content/generated/hsl/roles/job_formulas.json')


def job_symbols() -> dict[int, str]:
    """{value: symbol} of every TYPE.H `#define job...` (the PLAYERS.TXT `job =` vocabulary)."""
    text = (TABLES / 'TYPE.H').read_bytes().decode('cp950')
    return {int(value, 0): symbol for symbol, value in re.findall(r'^\s*#define\s+(job\w+)\s+(0x[0-9a-fA-F]+|\d+)\b', text, re.M)}


def build() -> dict:
    authored = json.loads((ROOT / FORMULAS).read_text(encoding='utf-8'))
    rows = formulas()
    symbols = job_symbols()
    symbols.update({code: symbol for symbol, code in authored_job_symbols().items()})
    jobs = {}
    for job in rows:
        jobs[str(job)] = dict(symbol=symbols[job], **{key: value for key, value in rows[job].items() if key != 'symbol'})
    return dict(schema=FORMULAS_SCHEMA, evidence_tier=authored['evidence_tier'], evidence=authored['evidence'],
                authored=FORMULAS, sources={FORMULAS: digest((ROOT / FORMULAS).read_bytes()), 'TYPE.H': digest((TABLES / 'TYPE.H').read_bytes())},
                term_format=authored['term_format'], stat_format=authored['stat_format'], variables=authored['variables'], jobs=jobs)


class JobFormulasTask(GeneratedFilesTask):
    name = 'job_formulas'
    family = 'actors'
    inputs = (FORMULAS, 'content/imported/hsl/global/tables/TYPE.H')
    outputs = (OUT.as_posix(),)
    replaces = ()  # born as a registry task: no historical command to replace
    scripts = ('tools/hsltools/data/job_formulas.py', 'tools/hsltools/model/jobs.py')

    def render(self, ctx: Context) -> dict[str, bytes]:
        return {OUT.as_posix(): json_bytes(build())}

    def summary(self, rendered: dict[str, bytes], mode: str) -> str:
        return 'JOB_FORMULAS_PASS jobs=' + str(len(json.loads(rendered[OUT.as_posix()])['jobs']))


def tasks() -> list[JobFormulasTask]:
    return [JobFormulasTask()]
