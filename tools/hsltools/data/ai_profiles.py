"""Derive explicit AI declarations; missing required strategies stay unsupported.

Registry task ai_profiles (family actors): output content/generated/hsl/ai/profiles.json.
Bodies moved verbatim from the former hsl_ai_profiles.py.
"""
from __future__ import annotations

import hashlib
import json
from pathlib import Path
import re

from hsltools.data import json_bytes
from hsltools.registry import GeneratedFilesTask, Context
from hsltools.sources.tables import TABLES, blocks, character_rows

OUT = Path('content/generated/hsl/ai/profiles.json')
REQUIRED = ['find_type', 'find_range', 'ai_att_special', 'ai_att_magic', 'ai_call_range', 'ai_fixed']


def definitions(path: Path) -> dict[str, int]:
    return {name: int(value, 0) for name, value in re.findall(
        r'^\s*#define\s+(\w+)\s+(-?(?:0x[0-9a-fA-F]+|\d+))\b', path.read_bytes().decode('cp950'), re.M)}


def build() -> dict:
    from hsltools.probes.large_actor import PACKET, check
    proof=json.loads(PACKET.read_text());check(proof)
    zero_defaults={r['field']:r['native'] for r in proof['ai_defaults']}
    types, shape_ids = definitions(TABLES / 'TYPE.H'), definitions(TABLES / 'SHAPEDEF.H')
    # An authored character may name an authored job symbol (its formula row declares it).
    from hsltools.model.jobs import authored_job_symbols
    symbols = {**types, **shape_ids, **authored_job_symbols()}

    def integer(value: str) -> int:
        if value in symbols: return symbols[value]
        try: return int(value, 0)
        except ValueError as error: raise ValueError('Unknown AI source expression: ' + value) from error

    actors = {}
    for actor in character_rows():
        code = f'{int(actor["code"]):03d}'
        declarations = {key: value for key, value in actor.items() if key.startswith(('find_', 'ai_'))}
        profile = {key: integer(value) for key, value in declarations.items()}
        defaulted={key:value for key,value in zero_defaults.items() if key not in actor}
        profile.update(defaulted)
        profile.update(job=integer(actor['job']), find_flag=integer(actor.get('find_flag', '0')),
                       find_no_id=integer(actor.get('find_no_id', '-1')),
                       wait_round=integer(actor.get('wait_round', '0')))
        # The same explicit source-character binding is used by hsl_combat_animation. An
        # authored character (content/authored/roles/characters.json) has no SHAPEDEF row;
        # its AI identity is its own code, the number SHAPEDEF gives every SID_ENEMYnnn.
        sid_token = f'SID_PLAYER{int(code)-1}' if 1 <= int(code) <= 9 else 'SID_ENEMY'+code
        authored = actor.get('evidence_tier') == 'authored'
        actors[code] = {'declarations': declarations, 'profile': profile,
                        'missing_required': [key for key in REQUIRED if key not in profile],
                        'defaulted_fields': defaulted,
                        'sid_token': sid_token if sid_token in shape_ids or authored else None,
                        'sid': int(code) if authored else shape_ids.get(sid_token),
                        'absent_optional': [key for key in ['find_flag', 'find_no_id'] if key not in actor]}
    return {'schema': 'hsl_ai_profiles.v1', 'evidence_tier': 'resource-derived',
            'sources': {name: hashlib.sha256((TABLES / name).read_bytes()).hexdigest()
                        for name in ['PLAYERS.TXT', 'TYPE.H', 'SHAPEDEF.H']},
            'find_types': {key: types[key] for key in ['AI_NORMAL', 'AI_HPMIN', 'AI_HPMAX', 'AI_NEAREST', 'AI_FAREST', 'AI_LEVELMIN', 'AI_LEVELMAX']},
            'actors': actors, 'limits': [
                'Strategy/radius/call/guard require source declarations; six absent action/support rates use original missing-field loader zeros verified in original_large_actor.json, never another actor profile.',
                'Absent optional find_flag/no_id serialize no preference/no exclusion; original parser defaults are not newly proven.',
                'Source001..009 -> SID_PLAYER0..8 are checked by independent binding/copy execution, including original_campaign_actors for005/007/008/009. Missing player strategies are not filled from another actor.',
                'Unit alliance, level and movement come from current battle state, not a second AI-owned copy.',
                'wait_round defaults to zero at original loader 0x44c7e0; ai_fixed is a home radius, ai_lock a probability.',
                'Original whole dispatcher, object-slot lifecycle and native path floods remain separate from current legal-grid composition.']}


class AiProfilesTask(GeneratedFilesTask):
    name = 'ai_profiles'
    family = 'actors'
    inputs = ('content/imported/hsl/global/tables/',)
    outputs = (OUT.as_posix(),)
    replaces = ('tools/hsl_ai_profiles.py --check',)
    scripts = ('tools/hsltools/data/ai_profiles.py',)

    def render(self, ctx: Context) -> dict[str, bytes]:
        return {OUT.as_posix(): json_bytes(build())}

    def summary(self, rendered: dict[str, bytes], mode: str) -> str:
        result = json.loads(rendered[OUT.as_posix()])
        return f'AI_PROFILES_PASS actors={len(result["actors"])} native_execution=False'


def tasks() -> list[AiProfilesTask]:
    return [AiProfilesTask()]
