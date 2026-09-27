"""Read the OBS map object's exact resource; never guess from level or terrain.

The source loader's reviewed shape-property/name-lookup prefix is separate from
the complete native renderer. Missing/ambiguous input fails in this importer;
that refusal is not a claim about the original's unexecuted symbol fallback.

Registry task source_map_binding (family checks, CheckTask): every content/generated/hsl/chapter01/
battleNNN_seed.json names the reviewed level-map shape. Bodies moved verbatim from the former hsl_source_map_binding.py.
"""
from __future__ import annotations

import json
from pathlib import Path
import re
from typing import Any

from hsltools.checks import CheckTask
from hsltools.paths import ROOT
from hsltools.registry import CheckFailed, Context



def archive_member(value: Any) -> str:
    """Canonical archive root only; retain every source folder and its case."""
    if not isinstance(value, str) or not value or value != value.strip():
        raise ValueError('missing_source_map_shape')
    relative = value[3:] if value.startswith('@:\\') else value
    parts = relative.split('\\')
    if (len(parts) < 2 or any(part in ('', '.', '..') for part in parts)
            or any(character in relative for character in ('/', ':', '\0', '\r', '\n'))
            or not relative.lower().endswith('.shp')):
        raise ValueError('invalid_source_map_shape: ' + repr(value))
    return '@:\\' + relative


def source_map_member(objects: dict[str, Any]) -> str:
    rows = objects.get('objects')
    if not isinstance(rows, list):
        raise ValueError('missing_source_map_objects')
    managers = [row for row in rows if isinstance(row, dict)
                and row.get('obj_process_code') == 'defProcIconBG']
    if len(managers) != 1:
        raise ValueError(f'expected_one_source_map_manager: found {len(managers)}')
    manager = managers[0]
    # 153 reviewed level-map objects use the shape-backed branch. Level49's
    # ICONRECT controller lacks Data9; its world-map callback is not this loader.
    if str(manager.get('obj_data_fields', {}).get('obj_Data9')) != '1':
        raise ValueError('unsupported_source_map_callback')
    return archive_member(manager.get('obj_shape_name'))


def alias_metadata(level: int, member: str, legacy: dict[str, Any] | None) -> dict[str, Any]:
    """Preserve compatible old provenance strings, never use them to select data."""
    match = re.fullmatch(r'level(\d+)\.shp', archive_member(member).split('\\')[-1], re.I)
    source_level = int(match[1]) if match else None
    if source_level is None or source_level == level:
        return {'alias_of_level': None, 'alias_evidence': None}
    evidence = (str(legacy['evidence']) if legacy and int(legacy['map_level']) == source_level
                else f'obj-{level:03d}.obs defProcIconBG.obj_Shape_Name names {member}; resource-derived binding, with loader prefix evidence in original_map_binding.md')
    return {'alias_of_level': source_level, 'alias_evidence': evidence}


def reviewed_bindings() -> dict[int, dict[str, Any]]:
    from hsltools.probes.map_binding import PACKET, check
    packet = json.loads(PACKET.read_text())
    check(packet)
    return {int(row['level']): row for row in packet['sources']['bindings']}


def check_seed_binding(seed: dict[str, Any], bindings: dict[int, dict[str, Any]]) -> None:
    level = int(seed['level'])
    if level not in bindings:
        raise ValueError(f'unreviewed_source_map_level: {level}')
    source = bindings[level]
    if source['object'].get('obj_Data9') != '1':
        raise ValueError(f'unsupported_source_map_callback: {level}')
    actual = seed['sources']['map']
    if (archive_member(actual['member']).casefold() != archive_member(source['shape_member']).casefold()
            or actual['sha256'] != source['shape_sha256']
            or seed['sources']['objects']['sha256'] != source['obs_sha256']
            or seed['map']['source_size'] != source['shape_size']):
        raise ValueError(f'seed_source_map_binding_mismatch: {level}')


def check_seeds(paths: list[Path]) -> str:
    """The legacy body for a seed list; returns the PASS line."""
    bindings = reviewed_bindings()
    if not paths:
        raise ValueError('no_battle_seeds_to_check')
    for path in paths:
        check_seed_binding(json.loads(path.read_text()), bindings)
    level_maps = sum(row['object'].get('obj_Data9') == '1' for row in bindings.values())
    return f'SOURCE_MAP_BINDING_CHECK_PASS seeds={len(paths)} level_maps={level_maps} source_objects={len(bindings)}'


class SourceMapBindingTask(CheckTask):
    name = 'source_map_binding'
    family = 'checks'
    inputs = ('content/generated/hsl/chapter01/', 'docs/evidence_packets/static_reverse/original_map_binding.json')
    replaces = ('tools/hsl_source_map_binding.py --check',)
    scripts = ('tools/hsltools/checks/source_map_binding.py', 'tools/hsltools/probes/map_binding.py')

    def check(self, ctx: Context) -> str:
        try:
            return check_seeds(sorted((ctx.root/'content/generated/hsl/chapter01').glob('battle*_seed.json')))
        except ValueError as error:
            raise CheckFailed(f'{self.name}: {error}') from error


def tasks() -> list[SourceMapBindingTask]:
    return [SourceMapBindingTask()]
