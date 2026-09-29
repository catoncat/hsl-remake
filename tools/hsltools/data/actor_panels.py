"""The panel display rows every identity board reads (game/sim/ContentPaths.ACTOR_PANELS).

Registry task actor_panels (family roles, GeneratedFilesTask): output
content/generated/hsl/roles/actor_panels.json = the imported panel manifest's `actors` rows
(content/imported/hsl/shared/panels/manifest.json, hsltools.assets.panel_assets from PLAYERS /
TYPE.H / RESOURCE) copied with one key added — `name`, the 姓名 the board prints: the PLAYERS
`name` field resolved verbatim (hsltools.assets.portraits.panel_name, 0x434d10 → 0x4477b0(+4)),
so the nameless placeholder 306 prints ??? even on a known unit — followed by one row per authored character
(content/authored/roles/characters.json) built by the same rule: 稱號 = the RESOURCE name of the
row's job type (an authored job — a job_formulas.json row with its own `symbol` — shows that row's
`name_text` instead), 種族 = the RESOURCE name of its class, 姓名 = its `name_text`, mind / con / gold from the row,
magic_attack from the generated role profile. The WINDOW10 board (map identity strip, cut-in,
target preview), the item panel and the town screens index this table by PLAYERS code, so an
authored character needs its row here or the board fails on it.
"""
from __future__ import annotations

import hashlib
import json

from hsltools.assets.panel_assets import NAMES
from hsltools.assets.portraits import RESOURCE_HEADER, panel_name, resource_defines
from hsltools.data import json_bytes
from hsltools.data.ai_profiles import definitions as type_definitions
from hsltools.model.jobs import FORMULAS, authored_job_symbols, formulas as job_formulas
from hsltools.paths import ROOT
from hsltools.registry import CheckFailed, Context, GeneratedFilesTask
from hsltools.sources.tables import AUTHORED_CHARACTERS, TABLES, authored_characters, parse_table, table_rows

IMPORTED = 'content/imported/hsl/shared/panels/manifest.json'
PROFILES = 'content/generated/hsl/roles/profiles.json'
OUTPUT = 'content/generated/hsl/roles/actor_panels.json'
SCHEMA = 'hsl_actor_panels.v1'


def build() -> dict:
    imported = json.loads((ROOT / IMPORTED).read_text(encoding='utf-8'))
    profiles = json.loads((ROOT / PROFILES).read_text(encoding='utf-8'))['actors']
    names = parse_table((ROOT / NAMES).read_bytes())
    types = type_definitions(ROOT / TABLES / 'TYPE.H')
    players = {f'{int(row["code"]):03d}': row for row in table_rows('PLAYERS.TXT')}
    defines = resource_defines()
    actors = {code: {**row, 'name': panel_name(players[code], names, defines)} for code, row in imported['actors'].items()}
    authored_jobs = authored_job_symbols()
    for row in authored_characters():
        code = row['code'].zfill(3)
        if code in actors:
            raise ValueError(f'{AUTHORED_CHARACTERS}: character {code} already has an imported panel row')
        job = row.get('job', '')
        if job in authored_jobs:
            title = job_formulas()[authored_jobs[job]].get('name_text')
            if not isinstance(title, str) or not title:
                raise ValueError(f'{FORMULAS}: authored job {job} (code {authored_jobs[job]}) needs a `name_text`: the 稱號 its characters show')
        elif job in types and str(types[job]) in names:
            title = names[str(types[job])]
        else:
            raise ValueError(f'{AUTHORED_CHARACTERS}: character {code} job {job!r} is neither an authored job symbol nor a TYPE.H code with a RESOURCE name')
        klass = row.get('class', '')
        if klass not in types or str(types[klass]) not in names:
            raise ValueError(f'{AUTHORED_CHARACTERS}: character {code} class {klass!r} has no TYPE.H code with a RESOURCE name')
        if code not in profiles:
            raise ValueError(f'{PROFILES}: no role profile for authored character {code} (add it to content/authored/roles/roster.json)')
        actors[code] = {'mind': int(row['mind']), 'con': int(row['con']), 'magic_attack': int(profiles[code]['initial']['magic_attack']),
                        'gold': int(row.get('gold', 0)), 'job': row['job'], 'title': title, 'name': row['name_text'],
                        'race': names[str(types[row['class']])], 'evidence_tier': 'authored'}
    return {
        'schema': SCHEMA,
        'evidence_tier': 'resource-derived',
        'sources': {'imported': {'path': IMPORTED, 'sha256': hashlib.sha256((ROOT / IMPORTED).read_bytes()).hexdigest()},
                    'authored': AUTHORED_CHARACTERS, 'profiles': PROFILES},
        'note': 'Panel display rows: imported rows plus `name` (the PLAYERS name field verbatim — 306 prints ???), authored characters appended by the same job／class → RESOURCE rule (their rows carry evidence_tier authored).',
        'actors': actors,
    }


class ActorPanelsTask(GeneratedFilesTask):
    name = 'actor_panels'
    family = 'roles'
    inputs = (IMPORTED, AUTHORED_CHARACTERS, FORMULAS, PROFILES, NAMES.as_posix(), 'content/imported/hsl/global/tables/TYPE.H',
              'content/imported/hsl/global/tables/PLAYERS.TXT', RESOURCE_HEADER.as_posix())
    outputs = (OUTPUT,)
    replaces = ()  # born as a registry task
    scripts = ('tools/hsltools/data/actor_panels.py', 'tools/hsltools/sources/tables.py', 'tools/hsltools/model/jobs.py',
               'tools/hsltools/assets/portraits.py')

    def render(self, ctx: Context) -> dict[str, bytes]:
        try:
            return {OUTPUT: json_bytes(build())}
        except (ValueError, KeyError) as error:
            raise CheckFailed(f'{self.name}: {error}') from error

    def summary(self, rendered: dict[str, bytes], mode: str) -> str:
        table = json.loads(rendered[OUTPUT])
        authored = sum(1 for row in table['actors'].values() if row.get('evidence_tier') == 'authored')
        return f'ACTOR_PANELS_PASS actors={len(table["actors"])} authored={authored}'


def tasks() -> list[ActorPanelsTask]:
    return [ActorPanelsTask()]
