"""The battle scenario contract: content/schema/battle.schema.json.

Hand-written (unlike unit.schema.json, which is derived): it names what
BattlePlayLoop.create reads from a battle JSON — the keys no default can stand in
for are `required`, every other key it reads carries a `default` that
BattleScenario.load_file fills before the loop runs. Registry task battle_schema (family
schema, CheckTask): every tracked content/battles/*.json whose rule_adapter is one of
the schema's battle adapters must validate; the story／world-map scenes are not battles
and are skipped.
"""
from __future__ import annotations

import json
from pathlib import Path

from hsltools.checks import CheckTask
from hsltools.paths import ROOT
from hsltools.registry import CheckFailed, Context
from hsltools.schema.validate import error

SCHEMA_PATH = 'content/schema/battle.schema.json'
SCHEMA_ID = 'hsl_battle.v1'
BATTLES = 'content/battles/'


def load(root: Path = ROOT) -> dict:
    return json.loads((root / SCHEMA_PATH).read_text(encoding='utf-8'))


def battle_adapters(schema: dict) -> list[str]:
    return list(schema['properties']['rule_adapter']['enum'])


def is_battle(document: object, schema: dict) -> bool:
    return isinstance(document, dict) and document.get('rule_adapter') in battle_adapters(schema)


def scenario_error(document: dict, schema: dict) -> str:
    """First violation of a battle document, "" when valid."""
    return error(document, schema)


class BattleSchemaTask(CheckTask):
    name = 'battle_schema'
    family = 'schema'
    inputs = (SCHEMA_PATH, BATTLES)
    scripts = ('tools/hsltools/schema/battle.py', 'tools/hsltools/schema/validate.py')

    def check(self, ctx: Context) -> str:
        schema = load(ctx.root)
        if schema.get('$id') != SCHEMA_ID:
            raise CheckFailed(f'{self.name}: {SCHEMA_PATH} $id must be {SCHEMA_ID}')
        battles = 0
        failures: list[str] = []
        for path in sorted((ctx.root / BATTLES).glob('*.json')):
            document = json.loads(path.read_text(encoding='utf-8'))
            if not is_battle(document, schema):
                continue
            battles += 1
            found = scenario_error(document, schema)
            if found:
                failures.append(f'{path.name}: {found}')
        if failures:
            raise CheckFailed(f'{self.name}: ' + '; '.join(failures[:5]))
        return f'BATTLE_SCHEMA_CHECK_PASS battles={battles} required={len(schema["required"])}'


def tasks() -> list[BattleSchemaTask]:
    return [BattleSchemaTask()]
