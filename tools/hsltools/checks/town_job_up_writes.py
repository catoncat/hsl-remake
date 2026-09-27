"""Validate content/world/town_job_up_writes.json — the town rewrite TownEventRules replays after a
teCheckJobUp2 success (hsl01.exe 0x434680; docs/evidence_packets/static_reverse/original_town_job_up.md).

Registry task town_job_up_writes (family world, CheckTask, replaces=()): every reference resolves in
content/imported/hsl/global/world_map/towndef.json (members are SID_* player symbols, the town is a
town_* symbol, every write is a te tree / exec-event writer whose town argument is that town and whose
event arguments are TOWNDEF town_event codes with the TOWNDEF.H argument shape). The 回憶錄 preset
generator (hsltools.data.original_save) applies this same file, and `hsl check original_save:native_second_tier`
pins the resulting town table byte for byte to the native HSL_second_tier_native.SAV (runtime-measured,
R11) — that pin, not a second copy of the list, is what keeps a `static-derived` file honest. A sequel
that rewrites the list for another town tags the file `authored` and regenerates the presets.
"""
from __future__ import annotations

import json
from pathlib import Path

from hsltools.checks import CheckTask
from hsltools.registry import CheckFailed, Context

OUTPUT = 'content/world/town_job_up_writes.json'
TOWNDEF = 'content/imported/hsl/global/world_map/towndef.json'
SCHEMA = 'hsl_town_job_up_writes.v1'
TOWNDEF_SCHEMA = 'hsl_towndef.v1'
EVIDENCE_TIERS = ('static-derived', 'authored')
# te tokens 0x434680 reaches through the tree / exec-event helpers: token -> positions of the event
# arguments after the town id (None = teAddTE / teDeleteTE's [node][num][children...] shape).
WRITER_TOKENS: dict[str, tuple[int, ...] | None] = {
    'teAddTE': None, 'teDeleteTE': None, 'teSetTownExecEvent': (1,), 'teSetTownExitExecEvent': (1,),
}


def _issues(data: dict, towndef: dict) -> list[str]:
    issues: list[str] = []
    if data.get('schema') != SCHEMA:
        issues.append(f'schema {data.get("schema")!r} != {SCHEMA!r}')
    if data.get('evidence_tier') not in EVIDENCE_TIERS:
        issues.append(f'evidence_tier {data.get("evidence_tier")!r} not in {EVIDENCE_TIERS}')
    if towndef.get('schema') != TOWNDEF_SCHEMA:
        issues.append(f'{TOWNDEF}: schema {towndef.get("schema")!r} != {TOWNDEF_SCHEMA!r}')
        return issues
    symbols = towndef.get('symbols', {})
    codes = {int(record['code']) for record in towndef.get('town_events', [])}
    block = data.get('second_tier')
    if not isinstance(block, dict):
        return issues + ['second_tier block missing']
    members = block.get('members')
    if not isinstance(members, list) or not members:
        issues.append('second_tier.members must be a non-empty list of SID_* symbols')
    else:
        for member in members:
            if not (isinstance(member, str) and member.startswith('SID_') and member in symbols):
                issues.append(f'member {member!r} is not a SID_* symbol of {TOWNDEF}')
    town = block.get('town')
    if not (isinstance(town, str) and town.startswith('town_') and symbols.get(town) is not None):
        issues.append(f'town {town!r} is not a town_* symbol of {TOWNDEF}')
    writes = block.get('writes')
    if not isinstance(writes, list) or not writes:
        return issues + ['second_tier.writes must be a non-empty list']
    for index, write in enumerate(writes):
        label = f'write {index}'
        if not isinstance(write, dict) or not isinstance(write.get('args'), list):
            issues.append(f'{label}: expected {{"token", "args"}}')
            continue
        token, args = write.get('token'), [str(arg) for arg in write['args']]
        if token not in WRITER_TOKENS:
            issues.append(f'{label}: token {token!r} is not one of {sorted(WRITER_TOKENS)}')
            continue
        if not args or args[0] != town:
            issues.append(f'{label}: first argument {args[:1]} must be the town {town!r}')
        positions = WRITER_TOKENS[token]
        if positions is None:
            if len(args) < 3 or not args[2].isdigit() or len(args) != 3 + int(args[2]):
                issues.append(f'{label}: {token} needs [town][node][num][num children], got {args}')
                continue
            events = [args[1]] if int(args[2]) == 0 else args[3:]
            if int(args[2]) > 0:
                events.append(args[1])
        else:
            if len(args) != 1 + len(positions):
                issues.append(f'{label}: {token} needs [town][event], got {args}')
                continue
            events = [args[position] for position in positions]
        for event in events:
            if not event.isdigit() or int(event) not in codes:
                issues.append(f'{label}: event {event!r} is not a TOWNDEF town_event code')
    return issues


def check(root: Path) -> str:
    data = json.loads((root / OUTPUT).read_text(encoding='utf-8'))
    towndef = json.loads((root / TOWNDEF).read_text(encoding='utf-8'))
    issues = _issues(data, towndef)
    if issues:
        raise ValueError(f'{OUTPUT}:\n  ' + '\n  '.join(issues))
    block = data['second_tier']
    return (f'TOWN_JOB_UP_WRITES_PASS tier={data["evidence_tier"]} town={block["town"]} '
            f'members={len(block["members"])} writes={len(block["writes"])}')


class TownJobUpWritesTask(CheckTask):
    name = 'town_job_up_writes'
    family = 'world'
    inputs = (OUTPUT, TOWNDEF)
    replaces = ()  # born as a registry task: no historical command to replace
    scripts = ('tools/hsltools/checks/town_job_up_writes.py',)

    def check(self, ctx: Context) -> str:
        try:
            return check(ctx.root)
        except (ValueError, OSError, KeyError) as error:
            raise CheckFailed(f'{self.name}: {error}') from error


def tasks() -> list[TownJobUpWritesTask]:
    return [TownJobUpWritesTask()]
