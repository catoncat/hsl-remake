"""Table-driven model of the original 0x448840 stat refresh: one evaluator over the per-job
formula rows of content/authored/roles/job_formulas.json (the same rows the runtime reads
through content/generated/hsl/roles/job_formulas.json, see JobStatsRules.gd).

This is analysis/generation code, not the Godot implementation or an EXE runner. The bounded
native probes (hsltools.probes.job_stats and friends) check its arithmetic against original
instructions, so `hsl check probe` is the proof that the table reproduces the native returns.
Adding a job is a data row in the authored table; there is no per-job branch here.

A row's job code is its key. Codes 80..100 are named by TYPE.H `#define job...` (the
PLAYERS.TXT `job =` vocabulary); any other code is an authored job and declares its own
`symbol` (authored_job_symbols), so a sequel job needs no edit of the imported TYPE.H.
"""
from __future__ import annotations

import json
import re
from collections.abc import Mapping
from functools import lru_cache

from hsltools.paths import ROOT, TABLES

ATTRIBUTES = ('str', 'dex', 'mind', 'con')
FORMULAS = 'content/authored/roles/job_formulas.json'
FORMULAS_SCHEMA = 'hsl_job_formulas.v1'
STATS = ('max_hp', 'max_mp', 'attack', 'defense', 'speed')
VARIABLES = ATTRIBUTES + ('level', 'hp_level')
SLOTS = ('weapon_equip', 'head_equip', 'armor_equip', 'foot_equip', 'other1_equip', 'other2_equip')
CAMPAIGN_ACTORS = ('037','038','034','035','005','007','049','044','041','043','033','032','027','030','031','045','055','056','065','051','064','008','009','048','024','022','050','052','053','054','057','058','059','060','066','067','068','069','100','101','010','011','012','013','014','015','016','017','018','019','020')
CAMPAIGN_PROOF = 'docs/evidence_packets/static_reverse/original_campaign_actors.json'


@lru_cache(maxsize=1)
def formulas() -> dict:
    """The authored formula table, validated once per process: {job code (int): row}."""
    table = json.loads((ROOT / FORMULAS).read_text(encoding='utf-8'))
    if table.get('schema') != FORMULAS_SCHEMA:
        raise ValueError(f'{FORMULAS}: schema {table.get("schema")!r} is not {FORMULAS_SCHEMA}')
    rows = {}
    for key, row in table['jobs'].items():
        if not key.isdecimal():
            raise ValueError(f'{FORMULAS}: job key {key!r} is not a numeric job code')
        validate_row(int(key), row)
        rows[int(key)] = row
    return rows


def type_h_job_symbols() -> dict[str, int]:
    """{symbol: code} of every TYPE.H `#define job...` (the imported original vocabulary)."""
    text = (TABLES / 'TYPE.H').read_bytes().decode('cp950')
    return {symbol: int(value, 0) for symbol, value in re.findall(r'^\s*#define\s+(job\w+)\s+(0x[0-9a-fA-F]+|\d+)\b', text, re.M)}


@lru_cache(maxsize=1)
def authored_job_symbols() -> dict[str, int]:
    """{symbol: code} of the formula rows that declare `symbol` — the authored jobs TYPE.H does
    not name. A declared symbol may not reuse a TYPE.H symbol or code; a row without one must
    be a TYPE.H job (otherwise no character row could name it)."""
    original = type_h_job_symbols()
    result = {}
    for job, row in formulas().items():
        symbol = row.get('symbol')
        if symbol is None:
            if job not in original.values():
                raise ValueError(f'{FORMULAS}: job {job} has no `#define job...` in TYPE.H and declares no `symbol`, so no character row can name it')
            continue
        if not isinstance(symbol, str) or not re.fullmatch(r'job\w+', symbol):
            raise ValueError(f'{FORMULAS}: job {job} symbol {symbol!r} must be a job… identifier')
        if symbol in original or job in original.values() or symbol in result:
            raise ValueError(f'{FORMULAS}: job {job} symbol {symbol} collides with TYPE.H or another row (TYPE.H jobs keep their own symbol)')
        result[symbol] = job
    return result


def validate_row(job: int, row: dict) -> None:
    def terms(name, values):
        if not isinstance(values, list) or not values:
            raise ValueError(f'{FORMULAS}: job {job} {name} must be a non-empty term list')
        for term in values:
            if isinstance(term, int) and not isinstance(term, bool):
                continue
            if (not isinstance(term, list) or len(term) not in (3, 4) or not isinstance(term[0], int)
                    or term[1] not in VARIABLES or not isinstance(term[2], int) or term[2] <= 0
                    or (len(term) == 4 and (not isinstance(term[3], int) or term[3] <= 0))):
                raise ValueError(f'{FORMULAS}: job {job} {name} term {term!r} is not [mul, var, div] / [mul, var, div, pre] / int')
    for stat in STATS:
        terms(stat, row.get(stat))
    magic = row.get('magic_attack')
    if not isinstance(magic, dict) or not isinstance(magic.get('bonus'), int):
        raise ValueError(f'{FORMULAS}: job {job} magic_attack needs terms and an integer bonus')
    terms('magic_attack.terms', magic.get('terms'))
    for key in ('cap', 'soft_knee'):
        if key in magic and not isinstance(magic[key], int):
            raise ValueError(f'{FORMULAS}: job {job} magic_attack.{key} must be an integer')
    resist = row.get('resist')
    if (not isinstance(resist, dict) or not isinstance(resist.get('cap'), int) or not isinstance(resist.get('rows'), list)
            or len(resist['rows']) != 5 or any(not isinstance(r, list) or len(r) != 2 or not all(isinstance(v, int) for v in r) or r[1] <= 0 for r in resist['rows'])):
        raise ValueError(f'{FORMULAS}: job {job} resist needs an integer cap and five [percent, divisor] rows')
    caps = row.get('caps')
    if not isinstance(caps, dict) or list(caps) != list(ATTRIBUTES) or not all(isinstance(caps[k], int) and caps[k] > 0 for k in ATTRIBUTES):
        raise ValueError(f'{FORMULAS}: job {job} caps must give str dex mind con in that order')
    quota = row.get('allocation_quota')
    if not isinstance(quota, list) or len(quota) != 4 or not all(isinstance(v, int) and v >= 0 for v in quota):
        raise ValueError(f'{FORMULAS}: job {job} allocation_quota must be four non-negative integers')


def caps_of(job: int) -> list[int]:
    return [formulas()[job]['caps'][k] for k in ATTRIBUTES]


class _Caps(Mapping):
    """{job code: [str, dex, mind, con] caps} read from the table on first use."""
    def __getitem__(self, job: int) -> list[int]:
        return caps_of(job)

    def __iter__(self):
        return iter(formulas())

    def __len__(self) -> int:
        return len(formulas())


CAPS = _Caps()


def allocation_quota(job: int) -> list[int]:
    return list(formulas()[job]['allocation_quota'])


def sum_terms(terms: list, variables: dict) -> int:
    total = 0
    for term in terms:
        if isinstance(term, int):
            total += term
        elif len(term) == 4:
            total += term[0] * (variables[term[1]] // term[3]) // term[2]
        else:
            total += term[0] * variables[term[1]] // term[2]
    return total


def base_values(job: int, attrs: dict, level: int, hp_level: int) -> dict:
    """The pre-source, pre-equipment job terms: the 0x448840 branch body for one job row."""
    row = formulas()[job]
    variables = {k: int(attrs[k]) for k in ATTRIBUTES}
    variables.update(level=level, hp_level=hp_level)
    result = {stat: sum_terms(row[stat], variables) for stat in STATS}
    magic_row = row['magic_attack']
    magic = sum_terms(magic_row['terms'], variables)
    if 'cap' in magic_row:
        magic = min(magic, magic_row['cap'])
    if 'soft_knee' in magic_row and magic > magic_row['soft_knee']:
        magic = (magic - magic_row['soft_knee']) // 2 + magic_row['soft_knee']
    result['magic_attack'] = magic + magic_row['bonus']
    cap, mind, con = row['resist']['cap'], variables['mind'], variables['con']
    result['resist'] = [min(cap, p * mind // 100 + con // div) for p, div in row['resist']['rows']]
    return result


def source_profile(row: dict, defines: dict) -> dict:
    job = defines[row['job']]
    if job not in formulas():
        raise ValueError(f'Job {row["job"]}={job} has no row in {FORMULAS}')
    source = {key: int(row.get(key, 0)) for key in
              ('attack_power', 'magic_attack_power', 'defense', 'speed',
               'hit_point', 'magic_point', 'avoid_hit_ratio', 'attack_back', 'attack_damagex2')}
    source['mode'] = defines[row['mode']]
    source['has_magic'] = any(row.get('magic_' + key, '0') != '0'
                              for key in ('other', 'earth', 'water', 'wind', 'fire', 'mind'))
    source['base_resist_by_type'] = {str(i): int(row.get('resist_' + key, 0))
                                    for i, key in enumerate(('earth', 'water', 'air', 'fire', 'mind'))}
    # PLAYERS rows 1-9 are the registered party (manual allocation); an authored character
    # row (content/authored/roles/characters.json) declares `allocation` itself and carries
    # no evidence packet.
    profile = dict(model='native_job_stats_v1', job_code=job,
                   allocation=row.get('allocation') or ('manual' if 1 <= int(row['code']) <= 9 else 'fixed_template'),
                   caps=dict(zip(ATTRIBUTES, caps_of(job))), source=source)
    if row.get('evidence_tier') != 'authored':
        profile['evidence'] = (CAMPAIGN_PROOF if row['code'].zfill(3) in CAMPAIGN_ACTORS and int(row['code']) != 24 else 'docs/evidence_packets/static_reverse/original_ohm_growth.json' if int(row['code']) in [3,61,62] else 'docs/evidence_packets/static_reverse/original_mobile_jobs.json' if job in [88,92] else 'docs/evidence_packets/static_reverse/original_priest.json' if job == 85 else 'docs/evidence_packets/static_reverse/original_job_stats.json')
    return profile


def level_bonus(level: int) -> int:
    if level < 10:
        return max(0, level)
    if level < 20:
        return 10 + (level - 10) // 2
    return 15 + (level - 20) // 4


def calculate(profile: dict, attrs: dict, level: int, gear: list[int],
              catalog: dict, hp: int, mp: int, base_move: int, mode: int | None = None) -> dict:
    """One 0x448840 refresh. `mode` is the live +0x28 word the refresh reads — the HP level
    term counts only when its pmPlayer bit is set (0x448851) — and defaults to the template's
    PLAYERS mode; an installed actor passes its constructor-applied `player_mode` (obj_Data9
    swap／obj_X1 override happen before the birth refresh, 0x407ec0)."""
    src, job = profile['source'], profile['job_code']
    side = src['mode'] if mode is None else mode
    base = base_values(job, attrs, level, level if side & 0x10000 else 0)
    result = dict(max_hp=base['max_hp']+src['hit_point'], max_mp=base['max_mp']+src['magic_point'],
                  attack=base['attack']+src['attack_power']+level_bonus(level),
                  defense=base['defense']+src['defense'], magic_attack=base['magic_attack']+src['magic_attack_power'],
                  speed=base['speed']+src['speed'], hit_rate=0, move_point=base_move,
                  avoid_hit_ratio=src['avoid_hit_ratio'], attack_back=src['attack_back'] or 12,
                  attack_damagex2=src['attack_damagex2'] or 8,
                  resist_by_type={str(i):base['resist'][i]+src['base_resist_by_type'][str(i)] for i in range(5)})
    for code in gear:
        if not code:
            continue
        delta = catalog[str(code)]['effects']
        for key in ('max_hp','max_mp','attack','defense','magic_attack','speed','hit_rate',
                    'move_point','avoid_hit_ratio','attack_back','attack_damagex2'):
            result[key] += delta[key]
        for k in result['resist_by_type']:
            result['resist_by_type'][k] += delta['resist_by_type'][k]
    result['max_hp'] = max(1, result['max_hp'])
    result['max_mp'] = max(0, result['max_mp']) if src['has_magic'] else 0
    # The shared native tail clamps these after source and equipment additions.
    # Source032's negative magic offset reaches this boundary at its base level.
    for key in ('attack', 'defense', 'magic_attack', 'speed'):
        result[key] = max(0, result[key])
    result['move_point'] = max(0, min(12, result['move_point']))
    result['resist_by_type'] = {k:max(0,min(80,v)) for k,v in result['resist_by_type'].items()}
    result.update(current_hp=min(hp,result['max_hp']), current_mp=min(mp,result['max_mp']),
                  exp_threshold=min(2000,(level+1)*50))
    return result
