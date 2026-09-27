"""The native receipts as checks on the table-driven role chain, not as its inputs.

Registry tasks (family checks, CheckTask, replaces=()):

  role_profiles_proof   every `initial` refresh in content/generated/hsl/roles/profiles.json that a native
                        stat probe executed (job_stats, priest, mobile_jobs, ohm_growth, campaign_actor
                        packets, case name `initial`) equals the receipt field by field, the recorded
                        profile equals the generated one, and every job formula row not tagged
                        `authored` is exercised by at least one receipt
  learning_tables_proof every job in content/authored/roles/learning_tables.json not tagged `authored`
                        has the magic levels and special rows the learning packets (growth_lifecycle,
                        ohm_growth, campaign_actor, job_up_learning) read from the original, and every
                        job those packets prove is in the table

Adding an `authored` job／actor (a sequel job with no original receipt) is therefore a data row: the
proofs skip what has no receipt and still pin every original row.
"""
from __future__ import annotations

import json
from pathlib import Path

from hsltools.checks import CheckTask
from hsltools.data.growth_lifecycle import LEARNING, identity, learning_tables
from hsltools.model.jobs import FORMULAS, formulas
from hsltools.registry import CheckFailed, Context

PROFILES = 'content/generated/hsl/roles/profiles.json'
STATIC_REVERSE = 'docs/evidence_packets/static_reverse/'
# packet → the key holding its refresh cases (each case: input.actor, input.name, native[0].values, profile)
STAT_PACKETS = {'original_job_stats.json': 'cases', 'original_priest.json': 'stats', 'original_mobile_jobs.json': 'cases',
                'original_ohm_growth.json': 'stats', 'original_campaign_actors.json': 'stats'}
LEARNING_PACKETS = ('original_growth_lifecycle.json', 'original_campaign_actors.json', 'original_job_up_learning.json')
OHM_PACKET = 'original_ohm_growth.json'
OHM_SPECIAL_JOB = '83'  # the bow learning table the ohm packet decoded; job 83 learns no magic


def _load(root: Path, name: str) -> dict:
    return json.loads((root / STATIC_REVERSE / name).read_text())


def initial_receipts(root: Path) -> dict[str, tuple[str, dict, dict]]:
    """{actor code: (packet, profile, native initial values)} from every stat packet's `initial` case."""
    receipts: dict[str, tuple[str, dict, dict]] = {}
    for name, key in STAT_PACKETS.items():
        for case in _load(root, name)[key]:
            if case['input']['name'] != 'initial':
                continue
            code = case['input']['actor']
            if code not in receipts:  # 024 is in two packets with the same receipt; the first wins
                receipts[code] = (name, case['profile'], case['native'][0]['values'])
    return receipts


def check_role_profiles(root: Path) -> str:
    profiles = json.loads((root / PROFILES).read_text())['actors']
    receipts = initial_receipts(root)
    errors = []
    exercised: set[int] = set()
    for code, (packet, profile, native) in sorted(receipts.items()):
        if code not in profiles:
            errors.append(f'{code}: native initial receipt in {packet} but no live profile')
            continue
        exercised.add(int(profile['job_code']))
        generated = profiles[code]
        if generated['profile'] != profile:
            errors.append(f'{code}: generated profile differs from {packet}')
        for field, value in native.items():
            if generated['initial'].get(field) != value:
                errors.append(f'{code}: initial.{field} {generated["initial"].get(field)!r} != native {value!r} ({packet})')
    unproved = sorted(job for job, row in formulas().items() if row.get('evidence_tier') != 'authored' and job not in exercised)
    if unproved:
        errors.append(f'{FORMULAS}: jobs {unproved} have no native initial receipt; tag them "evidence_tier": "authored" or add a probe')
    if errors:
        raise ValueError('role profiles differ from the native receipts:\n  ' + '\n  '.join(errors))
    return f'ROLE_PROFILES_PROOF_PASS actors={len(receipts)} jobs={len(exercised)} packets={len(STAT_PACKETS)}'


def learning_receipts(root: Path) -> dict[str, dict]:
    """{job: {'magic': [ids by level], 'special': {'tier', 'rows': [{id, tier, attributes}]}}} from the learning packets."""
    receipts: dict[str, dict] = {}
    for name in LEARNING_PACKETS:
        packet = _load(root, name)
        for job, thresholds in packet['magic_levels'].items():
            receipts.setdefault(job, {})['magic'] = [dict(id=identity('magic', element, code), level=level) for level, element, code in thresholds]
        for job, table in packet['special_tables'].items():
            receipts.setdefault(job, {})['special'] = dict(tier=table['tier'], rows=[
                dict(id=identity('special', row['type'], row['code']), tier=row['tier'], attributes=row['attributes']) for row in table['rows']])
    ohm = _load(root, OHM_PACKET)['learning_table']
    receipts[OHM_SPECIAL_JOB] = dict(magic=[], special=dict(tier=ohm['tier'], rows=[
        dict(id=identity('special', row['type'], row['code']), tier=row['tier'], attributes=row['attributes']) for row in ohm['rows']]))
    return receipts


def check_learning_tables(root: Path) -> str:
    table = learning_tables()
    receipts = learning_receipts(root)
    errors = []
    for job, receipt in sorted(receipts.items()):
        if job not in table:
            errors.append(f'job {job}: proved by the learning packets but missing from {LEARNING}')
            continue
        authored = table[job]
        if authored['magic'] != receipt['magic']:
            errors.append(f'job {job}: magic levels differ from the native receipt')
        if authored['tier'] != receipt['special']['tier'] or authored['special'] != receipt['special']['rows']:
            errors.append(f'job {job}: special tier／rows differ from the native receipt')
    unproved = sorted(job for job, row in table.items() if row.get('evidence_tier') != 'authored' and job not in receipts)
    if unproved:
        errors.append(f'{LEARNING}: jobs {unproved} have no native learning receipt; tag them "evidence_tier": "authored" or add a probe')
    if errors:
        raise ValueError('learning tables differ from the native receipts:\n  ' + '\n  '.join(errors))
    return f'LEARNING_TABLES_PROOF_PASS jobs={len(receipts)} packets={len(LEARNING_PACKETS) + 1}'


class RoleProfilesProofTask(CheckTask):
    name = 'role_profiles_proof'
    family = 'checks'
    inputs = (PROFILES, FORMULAS, *(STATIC_REVERSE + name for name in STAT_PACKETS))
    replaces = ()  # born as a registry task: no historical command to replace
    scripts = ('tools/hsltools/checks/role_chain_proof.py', 'tools/hsltools/model/jobs.py')

    def check(self, ctx: Context) -> str:
        try:
            return check_role_profiles(ctx.root)
        except (ValueError, OSError, KeyError) as error:
            raise CheckFailed(f'{self.name}: {error}') from error


class LearningTablesProofTask(CheckTask):
    name = 'learning_tables_proof'
    family = 'checks'
    inputs = (LEARNING, *(STATIC_REVERSE + name for name in LEARNING_PACKETS), STATIC_REVERSE + OHM_PACKET)
    replaces = ()  # born as a registry task: no historical command to replace
    scripts = ('tools/hsltools/checks/role_chain_proof.py', 'tools/hsltools/data/growth_lifecycle.py')

    def check(self, ctx: Context) -> str:
        try:
            return check_learning_tables(ctx.root)
        except (ValueError, OSError, KeyError) as error:
            raise CheckFailed(f'{self.name}: {error}') from error


def tasks() -> list[CheckTask]:
    return [RoleProfilesProofTask(), LearningTablesProofTask()]
