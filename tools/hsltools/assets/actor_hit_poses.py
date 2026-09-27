"""Map hit poses (SHAPEDEF `hit`, the single SHAPE\\NNN-P.SHP frame) of every actor, shared by
every battle.

A fallen actor switches to this pose as it enters its dead branch: the enemy / player process
calls 0x446c40(actor, facing, 6, 2) at 0x43ef36.. / 0x44347e.., and 0x446c40 state 6 reads the
shape at offset 0 of the actor's SHAPEDEF record with a count of 1 — the `hit` field the parser
stores there (0x4468b5 pushes "hit", 0x4468e2 writes +0) — so the last words and the upward
stretch are drawn in the NNN-P pose (static-derived, docs/evidence_packets/runtime_observations/
dialogue_death/README.md). Keys are the walk-frame actor keys (the stand shape's NNN prefix, the
key ActorRuntime.actor_id carries); a SHAPEDEF row whose hit shape is its stand shape (static
objects, 060's one-frame boss, 067's magic shape) has no separate pose and is listed in
`hit_is_stand`.

Registry task actor_hit_poses (family assets): output content/imported/hsl/shared/
actor_hit_poses/manifest.json plus one PNG per pose. The check also takes the census: every actor
key of every tracked walk-frame manifest must be a pose, a `hit_is_stand` row or a key SHAPEDEF
gives no hit field (`without_hit_field`), so no fielded actor falls without its death pose silently.
"""
from __future__ import annotations

import hashlib
import json
import re
import struct
from pathlib import Path

from hsltools.paths import ROOT
from hsltools.registry import Context, ScriptCheckTask, original_archive

SHAPEDEF = Path('content/imported/hsl/global/tables/SHAPEDEF.TXT')
OUTPUT_ROOT = Path('content/imported/hsl/shared/actor_hit_poses')
MANIFEST = OUTPUT_ROOT / 'manifest.json'
SCHEMA = 'hsl_actor_hit_poses.v1'
STAND_RE = re.compile(r'^shape\\(\d+)-', re.I)


def _sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def shape_rows() -> list[dict[str, str]]:
    """SHAPEDEF [define] blocks that declare a hit field: code, stand and hit members."""
    rows = []
    for block in (ROOT / SHAPEDEF).read_bytes().decode('cp950').split('[define]')[1:]:
        fields = {k: v.strip() for k, v in re.findall(r'^\s*(\w+)\s*=\s*([^;\r\n]+)', block, re.M)}
        if 'hit' in fields:
            rows.append({'code': fields['code'], 'stand': fields.get('stand', ''), 'hit': fields['hit']})
    return rows


def _key(row: dict[str, str]) -> str:
    """The walk-frame key: the stand shape's numeric prefix (zero-padded), else the code number."""
    match = STAND_RE.match(row['stand'])
    number = match[1] if match else re.sub(r'\D', '', row['code'])
    return f'{int(number):03d}'


def plan() -> tuple[dict[str, str], list[str]]:
    """key -> hit source member for rows with a separate hit shape; keys whose hit is the stand."""
    poses: dict[str, str] = {}
    same: list[str] = []
    for row in shape_rows():
        key = _key(row)
        member = '@:\\' + row['hit'].lower()
        if row['hit'].lower() == row['stand'].lower():
            if key not in poses and key not in same:
                same.append(key)
            continue
        if poses.get(key, member) != member:
            raise ValueError(f'actor key {key} has two different hit shapes')
        poses[key] = member
    # A row wearing another row's frames is fielded under its own code (the level-37 guardian
    # SID_ENEMY066 walks in 050's SHAPE, walk-frame key 066; the enemy 克羅蒂 SID_ENEMY053 in
    # 009's): that key takes the same hit shape — the SID's own block, as for the walk frames
    # (sources.actor_walk_frames._shape_fields), even when another block's stand prefix names
    # the number (SID_PLAYER17 wears SHAPE\\053-*).
    fielded = walk_keys()
    for row in shape_rows():
        code = re.fullmatch(r'SID_ENEMY(\d+)', row['code'])
        alias = f'{int(code[1]):03d}' if code else ''
        if not alias or alias == _key(row) or alias not in fielded:
            continue
        poses.pop(alias, None)
        if alias in same:
            same.remove(alias)
        if row['hit'].lower() == row['stand'].lower():
            same.append(alias)
        else:
            poses[alias] = '@:\\' + row['hit'].lower()
    return dict(sorted(poses.items())), sorted(same)


def walk_keys() -> set[str]:
    """Every actor key of every tracked walk-frame manifest (the actors a battle can field)."""
    keys: set[str] = set()
    for path in sorted(ROOT.glob('content/**/actor_walk_manifest.json')):
        keys.update(json.loads(path.read_text(encoding='utf-8')).get('actors', {}))
    return keys


def check() -> None:
    poses, same = plan()
    manifest = json.loads((ROOT / MANIFEST).read_text(encoding='utf-8'))
    assert manifest['schema'] == SCHEMA
    assert manifest['source_sha256'] == _sha((ROOT / SHAPEDEF).read_bytes()), 'SHAPEDEF.TXT changed: regenerate'
    assert sorted(manifest['poses']) == sorted(poses), 'hit poses differ from SHAPEDEF hit fields'
    assert manifest['hit_is_stand'] == same
    for key, entry in manifest['poses'].items():
        assert entry['source_member'] == poses[key], f'{key}: hit member drifted'
        data = (ROOT / entry['png_path']).read_bytes()
        assert _sha(data) == entry['sha256'], f'{key}: pose PNG differs from the manifest'
        assert entry['res_path'] == 'res://' + entry['png_path'] and len(entry['draw_origin']) == 2
    fielded = walk_keys()
    missing = sorted(fielded - set(poses) - set(same) - set(manifest['without_hit_field']))
    assert not missing, f'fielded actors without a declared death pose: {missing}'
    assert manifest['without_hit_field'] == sorted(fielded - set(poses) - set(same)), 'without_hit_field census drifted'
    print(f'ACTOR_HIT_POSES_CHECK_PASS poses={len(poses)} hit_is_stand={len(same)} '
          f'fielded={len(fielded)} without_hit_field={len(manifest["without_hit_field"])}')


def build(pak: Path) -> None:
    from hsltools.levels.actors import _read_member
    from hsltools.sources.pak import find_decoded_paks_packages
    from hsltools.sources.shp import parse_shp, write_shp_preview

    poses, same = plan()
    packages = find_decoded_paks_packages(pak)
    entries = {}
    for key, member in poses.items():
        payload = _read_member(packages, member)
        name = member.rsplit('\\', 1)[1].rsplit('.', 1)[0].upper() + '.png'
        target = OUTPUT_ROOT / name
        write_shp_preview(payload, parse_shp(payload), ROOT / target)
        entries[key] = {'source_member': member, 'source_sha256': _sha(payload),
                        'draw_origin': list(struct.unpack_from('<ii', payload, 0x1C)),
                        'draw_origin_evidence': 'static-derived:0x45fa75-0x45fab4',
                        'png_path': target.as_posix(), 'res_path': 'res://' + target.as_posix(),
                        'sha256': _sha((ROOT / target).read_bytes())}
    fielded = walk_keys()
    manifest = {'schema': SCHEMA, 'evidence_tier': 'resource-derived', 'source': SHAPEDEF.as_posix(),
                'source_sha256': _sha((ROOT / SHAPEDEF).read_bytes()),
                'use': 'death entry 0x446c40(actor, facing, 6, 2): state 6 = SHAPEDEF offset 0 (hit), one frame (static-derived)',
                'poses': entries, 'hit_is_stand': same,
                'without_hit_field': sorted(fielded - set(poses) - set(same)),
                'unresolved_semantics': ['the dead branch skips the pose when +0x80 has 0x800 or 0x446b60 (per-object table +0xa0 bit 0x20) is set; neither flag is modelled',
                                         'the hit pose is otherwise unused by the remake (the original also shows it elsewhere; not measured)']}
    (ROOT / MANIFEST).write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print(f'ACTOR_HIT_POSES_IMPORT_PASS poses={len(entries)}')


class ActorHitPosesTask(ScriptCheckTask):
    name = 'actor_hit_poses'
    family = 'assets'
    inputs = (SHAPEDEF.as_posix(), 'content/**/actor_walk_manifest.json')
    outputs = (OUTPUT_ROOT.as_posix() + '/',)
    replaces = ()  # born after the migration: no historical command to replace
    scripts = ('tools/hsltools/assets/actor_hit_poses.py',)

    def verify(self, ctx: Context) -> None:
        check()

    def build(self, ctx: Context) -> None:
        build(original_archive(ctx))


def tasks() -> list[ActorHitPosesTask]:
    return [ActorHitPosesTask()]
