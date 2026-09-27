"""Map casting poses (SHAPEDEF `use_magic`, the NNN-M0001..6 frames) of every actor, shared by
every battle.

0x4071e0 puts a map actor into this pose: 0x446c40(actor, SID, 7, 3) — state 7 reads the shape
and count at offset 0x34／0x38 of the actor's SHAPEDEF record, where the parser stores
`use_magic`／`use_magic_num` (0x446a8c), with a frame delay of 3 — then +0x92 = 40, +0x98 = 0,
+0x90 = −1 and +0x80 |= 0x1000. The enemy／player processes (0x43f1dc..0x43f24c,
0x4436f9..0x443770) play it once forward (0x45e575), hold the last frame 40 ticks, play it back
(0x45e660) and clear 0x1000, after which the standing sequence is selected again (+0x90 = −1
differs from state 0, 0x44212a..0x442161). Callers: the end of a map spell's cast lead
(0x402fd1／0x403128, with Cast_Star and sfx 0x193), item use (player 0x4449a7, AI
0x440366／0x4404c7) and a level-up (0x442720 phase 6). Static-derived, docs/evidence_packets/
runtime_observations/map_pose_floaters/README.md.

Keys are the walk-frame actor keys (ActorRuntime.actor_id), resolved to their SHAPEDEF block
the way the walk frames are (sources.actor_walk_frames._shape_fields: the SID's own block, else
the block whose stand shape carries the number). A frame named by use_magic + count that hsl.pak
lacks (044-M0002) is listed under the key's `missing_members` and skipped. A block whose use_magic shape is its stand
shape (060's one-frame boss, 068, the level-18 door) has no separate pose and is listed in
`use_magic_is_stand`.

Registry task actor_magic_poses (family assets): output content/imported/hsl/shared/
actor_magic_poses/manifest.json plus one PNG per frame. The check takes the census: every actor
key of every tracked walk-frame manifest must be a pose, a `use_magic_is_stand` row or a key
SHAPEDEF gives no block (`without_use_magic`).
"""
from __future__ import annotations

import hashlib
import json
import re
import struct
from pathlib import Path

from hsltools.assets.actor_hit_poses import walk_keys
from hsltools.paths import ROOT
from hsltools.registry import Context, ScriptCheckTask, original_archive
from hsltools.sources.shp import png_sha256

SHAPEDEF = Path('content/imported/hsl/global/tables/SHAPEDEF.TXT')
OUTPUT_ROOT = Path('content/imported/hsl/shared/actor_magic_poses')
MANIFEST = OUTPUT_ROOT / 'manifest.json'
SCHEMA = 'hsl_actor_magic_poses.v1'
## 0x4071e0／0x45e525: frame delay 3 (4 ticks a frame); 0x4071e0 +0x92: the last frame held 40 ticks.
PROGRAM = {'frame_delay': 3, 'hold_ticks': 40,
           'note': '0x4071e0 → 0x446c40(actor, SID, 7, 3): use_magic frames at delay 3 (4 ticks each), played once '
                   'forward (0x45e575), the last frame held 40 ticks (+0x92), played back (0x45e660), then the '
                   'standing sequence (+0x90 = −1 forces 0x442161 to reselect state 0)'}


def _sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def _blocks() -> list[dict[str, str]]:
    return [{k: v.strip() for k, v in re.findall(r'^\s*(\w+)\s*=\s*([^;\r\n]+)', block, re.M)}
            for block in (ROOT / SHAPEDEF).read_bytes().decode('cp950').split('[define]')[1:]]


def _block(key: str, blocks: list[dict[str, str]]) -> dict[str, str] | None:
    """The key's SHAPEDEF block: its own SID_ENEMY block, else the first whose stand carries the number."""
    for fields in blocks:
        if fields.get('code') == f'SID_ENEMY{key}':
            return fields
    prefixes = {key, str(int(key))}
    for fields in blocks:
        stand = fields.get('stand', '').lower()
        if any(stand.startswith(f'shape\\{prefix}-') for prefix in prefixes):
            return fields
    return None


def _members(first: str, count: int) -> list[str]:
    """The `count` consecutive shape names from `first` (001-M0001 → 001-M0002 …, same width)."""
    match = re.fullmatch(r'(.*?)(\d+)(\.shp)', first, re.I)
    if not match:
        raise ValueError(f'unsupported use_magic shape name: {first}')
    head, number, tail = match[1], match[2], match[3]
    return [f'@:\\{head}{int(number) + index:0{len(number)}d}{tail}'.lower() for index in range(count)]


def plan() -> tuple[dict[str, list[str]], list[str], list[str]]:
    """key -> use_magic members; keys whose use_magic is the stand shape; keys without a block."""
    blocks = _blocks()
    poses: dict[str, list[str]] = {}
    same: list[str] = []
    without: list[str] = []
    for key in sorted(walk_keys()):
        fields = _block(key, blocks)
        if fields is None or 'use_magic' not in fields:
            without.append(key)
            continue
        if fields['use_magic'].lower() == fields.get('stand', '').lower():
            same.append(key)
            continue
        poses[key] = _members(fields['use_magic'], int(fields['use_magic_num']))
    return poses, same, without


def check() -> None:
    poses, same, without = plan()
    manifest = json.loads((ROOT / MANIFEST).read_text(encoding='utf-8'))
    assert manifest['schema'] == SCHEMA
    assert manifest['source_sha256'] == _sha((ROOT / SHAPEDEF).read_bytes()), 'SHAPEDEF.TXT changed: regenerate'
    assert manifest['program'] == PROGRAM
    assert sorted(manifest['poses']) == sorted(poses), 'magic poses differ from SHAPEDEF use_magic fields'
    assert manifest['use_magic_is_stand'] == same and manifest['without_use_magic'] == without, 'use_magic census drifted'
    frames = 0
    for key, entry in manifest['poses'].items():
        imported = [frame['source_member'] for frame in entry['frames']]
        assert sorted(imported + entry['missing_members']) == sorted(poses[key]), f'{key}: use_magic members drifted'
        assert imported, f'{key}: no use_magic frame imported'
        for frame in entry['frames']:
            data = (ROOT / frame['png_path']).read_bytes()
            assert png_sha256(data) == frame['sha256'], f'{key}: pose PNG differs from the manifest'
            assert frame['res_path'] == 'res://' + frame['png_path'] and len(frame['draw_origin']) == 2
            frames += 1
    print(f'ACTOR_MAGIC_POSES_CHECK_PASS poses={len(poses)} frames={frames} use_magic_is_stand={len(same)} '
          f'without_use_magic={len(without)}')


def build(pak: Path) -> None:
    from hsltools.levels.actors import _read_member
    from hsltools.sources.pak import find_decoded_paks_packages
    from hsltools.sources.shp import parse_shp, write_shp_preview

    poses, same, without = plan()
    packages = find_decoded_paks_packages(pak)
    entries = {}
    for key, members in poses.items():
        frames = []
        missing = []
        for member in members:
            try:
                payload = _read_member(packages, member)
            except ValueError:
                missing.append(member)  # 044-M0002: named by use_magic + count, absent from hsl.pak
                continue
            name = member.rsplit('\\', 1)[1].rsplit('.', 1)[0].upper() + '.png'
            target = OUTPUT_ROOT / name
            write_shp_preview(payload, parse_shp(payload), ROOT / target)
            frames.append({'source_member': member, 'source_sha256': _sha(payload),
                           'draw_origin': list(struct.unpack_from('<ii', payload, 0x1C)),
                           'png_path': target.as_posix(), 'res_path': 'res://' + target.as_posix(),
                           'sha256': png_sha256((ROOT / target))})
        entries[key] = {'frames': frames, 'missing_members': missing}
    manifest = {'schema': SCHEMA, 'evidence_tier': 'resource-derived', 'source': SHAPEDEF.as_posix(),
                'source_sha256': _sha((ROOT / SHAPEDEF).read_bytes()),
                'use': '0x4071e0 map casting pose: state 7 = SHAPEDEF offset 0x34／0x38 (use_magic, use_magic_num) (static-derived)',
                'draw_origin_evidence': 'static-derived:0x45fa75-0x45fab4',
                'program': PROGRAM, 'poses': entries,
                'missing_members_evidence': 'negative-evidence: these names follow from use_magic + use_magic_num but hsl.pak '
                                            'has no such record; the pose plays the frames that exist', 'use_magic_is_stand': same, 'without_use_magic': without}
    (ROOT / MANIFEST).write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print(f'ACTOR_MAGIC_POSES_IMPORT_PASS poses={len(entries)}')


class ActorMagicPosesTask(ScriptCheckTask):
    name = 'actor_magic_poses'
    family = 'assets'

    @property
    def inputs(self) -> tuple[str, ...]:
        from hsltools.assets.actor_hit_poses import walk_manifest_inputs
        return (SHAPEDEF.as_posix(), *walk_manifest_inputs())

    outputs = (OUTPUT_ROOT.as_posix() + '/',)
    replaces = ()
    scripts = ('tools/hsltools/assets/actor_magic_poses.py',)

    def verify(self, ctx: Context) -> None:
        check()

    def build(self, ctx: Context) -> None:
        build(original_archive(ctx))


def tasks() -> list[ActorMagicPosesTask]:
    return [ActorMagicPosesTask()]
