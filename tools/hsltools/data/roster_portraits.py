"""The roster face table every panel reads (game/sim/ContentPaths.ACTOR_PORTRAITS).

Registry task roster_portraits (family roles, GeneratedFilesTask): output
content/generated/hsl/roles/actor_portraits.json = the imported chapter-01 portrait manifest
rows (content/imported/hsl/chapter01/portraits/manifest.json, PLAYERS picture fields decoded
from the PAK) followed by one row per authored character (content/authored/roles/characters.json
`portrait` = the PNG it is drawn with, `name_text` = its panel name). The status panels, the
give view and the party equipment screen index this table by the unit's PLAYERS code, so a
sequel character needs a row here or the panel fails on it; the imported rows are copied
unchanged (byte-identical `actors` entries), only the table's home moves.
"""
from __future__ import annotations

import hashlib
import json

from hsltools.data import json_bytes
from hsltools.paths import ROOT
from hsltools.registry import Context, GeneratedFilesTask
from hsltools.sources.tables import AUTHORED_CHARACTERS, authored_characters
from hsltools.sources.shp import png_sha256

IMPORTED = 'content/imported/hsl/chapter01/portraits/manifest.json'
OUTPUT = 'content/generated/hsl/roles/actor_portraits.json'
SCHEMA = 'hsl_actor_portraits.v1'


def build() -> dict:
    imported = json.loads((ROOT / IMPORTED).read_text(encoding='utf-8'))
    if imported.get('schema') != SCHEMA:
        raise ValueError(f'{IMPORTED}: schema {imported.get("schema")!r} is not {SCHEMA}')
    actors = dict(imported['actors'])
    for row in authored_characters():
        code = row['code'].zfill(3)
        portrait = row.get('portrait', '')
        if not portrait.startswith('res://') or not (ROOT / portrait.removeprefix('res://')).is_file():
            raise ValueError(f'{AUTHORED_CHARACTERS}: character {code} needs a `portrait` res:// path to an existing PNG')
        if code in actors:
            raise ValueError(f'{AUTHORED_CHARACTERS}: character {code} already has an imported portrait row')
        actors[code] = {'name': row['name_text'], 'res_path': portrait, 'evidence_tier': 'authored',
                        'png_sha256': png_sha256((ROOT / portrait.removeprefix('res://')))}
    return {
        'schema': SCHEMA,
        'evidence_tier': 'resource-derived',
        'sources': {'imported': {'path': IMPORTED, 'sha256': hashlib.sha256((ROOT / IMPORTED).read_bytes()).hexdigest()},
                    'authored': AUTHORED_CHARACTERS},
        'presentation': str(imported.get('presentation', '')),
        'note': 'Roster face table for the panels: imported chapter-01 rows unchanged, authored characters appended (their rows carry evidence_tier authored).',
        'actors': actors,
    }


class RosterPortraitsTask(GeneratedFilesTask):
    name = 'roster_portraits'
    family = 'roles'
    inputs = (IMPORTED, AUTHORED_CHARACTERS)
    outputs = (OUTPUT,)
    replaces = ()  # born as a registry task
    scripts = ('tools/hsltools/data/roster_portraits.py', 'tools/hsltools/sources/tables.py')

    def render(self, ctx: Context) -> dict[str, bytes]:
        return {OUTPUT: json_bytes(build())}

    def summary(self, rendered: dict[str, bytes], mode: str) -> str:
        table = json.loads(rendered[OUTPUT])
        authored = sum(1 for row in table['actors'].values() if row.get('evidence_tier') == 'authored')
        return f'ROSTER_PORTRAITS_PASS actors={len(table["actors"])} authored={authored}'


def tasks() -> list[RosterPortraitsTask]:
    return [RosterPortraitsTask()]
