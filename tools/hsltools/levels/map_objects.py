"""Promote one level's stand objects (EVEF placements joined to obj-<level>.obs) into
runtime map-object manifests: previews, native SHP draw origins and layer hints
(level_map_objects:N).

Reads the tracked battle seed for placements and the original PAK for SHP bytes.
Outputs live next to the level's other assets; previews share the chapter's
map-object preview folder so the runtime's fixed preview root keeps working.
Registry task (tools/hsl.py check|generate level_map_objects:N): check validates the tracked outputs
without the PAK, generate rebuilds them from the original hsl.pak next to the documented EXE.
"""
from __future__ import annotations

import hashlib
import json
import struct
from pathlib import Path

from hsltools.legacy import imported_levels
from hsltools.levels import legacy_failures, original_pak, profile
from hsltools.paths import ORIGINAL_PAK, ROOT
from hsltools.registry import Context, NotGeneratable, Task
from hsltools.sources.shp import png_sha256

DEFAULT_PAK = ORIGINAL_PAK
PREVIEW_ROOT = ROOT / 'content/imported/hsl/shared/shape_previews/map_object'
MAP_OBJECTS_SCHEMA = 'hsl_chapter01_imported_map_objects_ir.v1'
ALIGNMENT_SCHEMA = 'hsl_chapter01_map_object_alignment.v1'

# Remake presentation layering for stand-object classes; the source only proves the
# object process, mode and data fields, not the original plane order.
LAYER_HINTS = {
    'engADDCOLOR': 'foreground',      # additive light glows and fire sit above actors
    'mapobjMoveBG': 'backdrop',       # sky/mountain pictures seen through the map's transparent area sit under the map
    'mapobjShadow': 'back',           # floor shadows stay under actors
    'collide': 'foreground',          # pillars with collision boxes occlude actors
    'default': 'back',                # lamp bases and other decoration under actors
}


def level_dir(level: int) -> Path:
    return (ROOT / f'content/imported/hsl/chapter01/battle{level:03d}')


def seed_path(level: int) -> Path:
    return (ROOT / f'content/generated/hsl/chapter01/battle{level:03d}_seed.json')


def _basename(member: str) -> str:
    return member.split('\\')[-1]


def _sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def _static_enemy_object(row: dict) -> bool:
    """EVEF enemy-process objects whose shape has no SHAPEDEF walk groups (level 12's
    62 Enemy101 船殼 hull pieces) are drawn as stand objects, not spawned as actors."""
    from hsltools.sources.actor_walk_frames import is_walking_shape, standing_actor_code
    if row.get('role_from_process') != 'enemy_object' or row.get('join_status') != 'joined' or not row.get('shape_resource'):
        return False
    # An EVEF standing-only actor with a generated template (level 80's 怨念體 068) is a
    # PlayLoop unit the story scene casts, not a stand sprite (script-inserted ones keep
    # their per-level spec: level 59's standing_actor_inserts).
    if 'record_index' in row and standing_actor_code(row):
        return False
    # SHAPEDEF keys walk groups by the shape prefix (SHAPE\\022-00001 -> 022), which can
    # differ from the character code in obj_Data7 (level 52's Enemy069 wears shape 022).
    return not is_walking_shape(str(row['shape_resource']))


def _treasure_box(row: dict) -> bool:
    """EVEF 寶藏 records (defProcTreasureBox, SHAPE\\BOX0001.SHP) are drawn as closed chests
    at their EVEF anchor; opening/pickup is battle-body behaviour that is not remade yet."""
    return row.get('object_process') == 'defProcTreasureBox' and row.get('join_status') == 'joined' and bool(row.get('shape_resource'))


def stand_objects(seed: dict) -> list[dict]:
    return [row for row in seed['placements']['records']
            if row.get('role_from_process') == 'map_object' or _static_enemy_object(row) or _treasure_box(row)]


def _stand_role(row: dict) -> tuple[str, str]:
    if row.get('role_from_process') == 'enemy_object':
        return 'static_enemy_object', 'defProcEnemy'
    if _treasure_box(row):
        return 'treasure_box', 'defProcTreasureBox'
    if row.get('object_data_fields', {}).get('obj_Data9') == 'mapobjPlayBGSound':
        # EVEF-placed ambience emitters (the camp levels' 夜晚聲 NIGHT001.WAV / 鳥聲
        # YELL010.WAV) carry the engine's I_RECT01 marker shape; they name a looping
        # WAV (imported by hsl_level_sounds.py), not a sprite to draw.
        return 'background_sound', 'defProcStandObject'
    return 'map_object', 'defProcStandObject'


def layer_hint(fields: dict) -> str:
    if str(fields.get('obj_Mode', '')).startswith('engADDCOLOR'):
        return LAYER_HINTS['engADDCOLOR']
    if fields.get('obj_Data9') == 'mapobjMoveBG':
        return LAYER_HINTS['mapobjMoveBG']
    if fields.get('obj_Data9') == 'mapobjShadow':
        return LAYER_HINTS['mapobjShadow']
    if any(key.startswith('obj_Collide_') for key in fields):
        return LAYER_HINTS['collide']
    return LAYER_HINTS['default']


def blend_hint(mode: str) -> str:
    """obj_Mode token -> remake blend reading: engADDCOLOR* additive, engGLASS* translucent
    ('glass', e.g. the level-1 cloud shadows CLOUD102), anything else plain mix."""
    if mode.startswith('engADDCOLOR'):
        return 'add'
    if mode.startswith('engGLASS'):
        return 'glass'
    return 'mix'


def presentation_hint(fields: dict) -> dict:
    return {
        'blend': blend_hint(str(fields.get('obj_Mode', ''))),
        'flash': fields.get('obj_Data9') == 'mapobjFlash',
        'shadow': fields.get('obj_Data9') == 'mapobjShadow',
        'animated': fields.get('obj_Data9') == 'mapobjNextShape',
        'evidence_tier': 'provisional',
        'source': 'obj_Mode/obj_Data9 tokens from obj-<level>.obs; flicker rate, shadow alpha and blend math are remake choices',
    }


def layer_overrides(level: int) -> dict[int, str]:
    """content/battles/levels/NNN.json map_objects.layer_overrides: {EVEF record_index: layer}
    where the observed original draw order contradicts the generic obj-field reading."""
    section = profile.section('map_objects').get(level, {})
    return {int(record): str(layer) for record, layer in section.get('layer_overrides', {}).items()}


def build_placements(seed: dict) -> list[dict]:
    result = []
    for row in stand_objects(seed):
        fields = row.get('object_data_fields', {})
        shape_resource = str(row['shape_resource'])
        role, process = _stand_role(row)
        result.append({
            'record_index': int(row['record_index']),
            'object_code': int(row['object_code']),
            'role': role,
            'process': process,
            'object_name': row.get('object_name'),
            'shape_resource': shape_resource,
            'shape_resource_id': _basename(shape_resource),
            'candidate_x': int(row['placement_xy_candidate'][0]),
            'candidate_y': int(row['placement_xy_candidate'][1]),
            'coordinate_interpretation': {
                'source_kind': 'resource-derived',
                'evidence_tier': 'resource_parser_candidate',
                'interpretation_status': 'provisional',
                'semantics': 'EVEF placement coordinate candidates minus native SHP draw origin; not proven as original plane order',
            },
            'object_fields': {key: {'value': str(value)} for key, value in fields.items()},
            'join': {'status': 'joined'},
            'runtime_layer_hint': layer_hint(fields),
            'presentation_hint': presentation_hint(fields),
            **({'plane': row['plane']} if row.get('plane') else {}),
        })
    overrides = layer_overrides(int(seed['level']))
    for placement in result:
        if placement['record_index'] in overrides:
            placement['runtime_layer_hint'] = overrides[placement['record_index']]
            placement['runtime_layer_source'] = 'level profile map_objects.layer_overrides (observed original draw order)'
    return result


def shape_exists(packages, member: str) -> bool:
    from hsltools.sources.pak import find_paks_record_by_name
    return sum(1 for p in packages if find_paks_record_by_name(p['records'], member)) == 1


def read_shape(packages, member: str) -> bytes:
    from hsltools.sources.pak import find_paks_record_by_name, read_paks_record_bytes
    matches = [(p, r) for p in packages if (r := find_paks_record_by_name(p['records'], member))]
    if len(matches) != 1:
        raise ValueError('missing or ambiguous SHP: ' + member)
    package, record = matches[0]
    raw = read_paks_record_bytes(package['path'], record, data_end_offset=int(package['paks']['candidate_index_offset']))
    if raw[:4] != b'TLHS' or len(raw) < 36:
        raise ValueError('invalid SHP: ' + member)
    return raw


SCRIPT_OBJECT_ROLES = {'other', 'map_object'}
INSERT_ACTIONS = {'actinsertstoryobject', 'actinsertobject', 'actinsertrandomobject'}
# lane ch2c: random-position / x-range insert variants (STORY037 白光 + guardians, winfail039)
INSERT_ACTIONS |= {'actinsertobjectrandompos', 'actinsertstoryobjectrandompos', 'actinsertstoryobjectxrange'}
# end lane ch2c


def inserted_symbols(seed: dict) -> set[str]:
    """Header symbols the level's STORY/WINFAIL scripts actually insert; shared headers
    such as OBJ-007.H define hundreds of objects the level never draws."""
    result: set[str] = set()
    for key in ('story', 'winfail'):
        script = seed.get('scripts', {}).get(key) or {}
        for section in script.get('sections', []):
            for action in section.get('actions', []):
                for command in action.get('chain', []):
                    if str(command.get('name', '')).lower() in INSERT_ACTIONS and command.get('args'):
                        result.add(str(command['args'][0]))
    # Objects an inserted object spawns through its data fields (level 10's 降雨BOSS names
    # obj_Story_Level10_Rain in obj_Data4) are drawn too, so they count as inserted.
    known = {str(row['symbol']): row for row in seed.get('script_objects', [])}
    pending = list(result)
    while pending:
        row = known.get(pending.pop())
        for value in (row or {}).get('object_data_fields', {}).values():
            if str(value) in known and str(value) not in result:
                result.add(str(value))
                pending.append(str(value))
    return result


def frame_shape_ids(shape_resource_id: str, shape_number: int | None) -> list[str]:
    """obj_Shape_Number > 1 names a frame run whose members increment the shape's
    numeric suffix at the same width (FIR03_01 -> FIR03_02, 10_RAIN001 -> 10_RAIN002).
    Shapes without a numeric suffix stay single-frame."""
    stem, dot, ext = shape_resource_id.rpartition('.')
    count = int(shape_number or 1)
    digits = len(stem) - len(stem.rstrip('0123456789'))
    if count <= 1 or digits == 0:
        return [shape_resource_id]
    prefix, start = stem[:-digits], int(stem[-digits:])
    return [f'{prefix}{start + index:0{digits}d}{dot}{ext}' for index in range(count)]


def build_script_objects(seed: dict) -> list[dict]:
    """Script-inserted objects (actInsertStoryObject / actInsertObject symbols) that are
    not actors: their shape becomes a presentation sprite (with its obj_Shape_Number frame
    run when the shape names one); the motion/effect process itself stays unresolved."""
    result = []
    used = inserted_symbols(seed)
    for row in seed.get('script_objects', []):
        if row.get('join_status') != 'joined' or not row.get('shape_resource'):
            continue
        # Enemy-process inserts whose shape has no SHAPEDEF walk groups (STORY018's
        # obj_Story_Level_Door 18_DOOR01) are drawn as static sprites, like the EVEF
        # static_enemy_object placements; walking enemies stay script actors.
        static_enemy = _static_enemy_object(row)
        if row.get('role_from_process') not in SCRIPT_OBJECT_ROLES and not static_enemy:
            continue
        if str(row['symbol']) not in used:
            continue
        shape_resource = str(row['shape_resource'])
        shape_id = _basename(shape_resource)
        entry = {
            'symbol': str(row['symbol']),
            'object_code': int(row['object_code']),
            'object_name': row.get('object_name'),
            'process': row.get('object_process'),
            'shape_resource': shape_resource,
            'shape_resource_id': shape_id,
            'object_fields': {key: {'value': str(value)} for key, value in row.get('object_data_fields', {}).items()},
            'presentation_hint': {'evidence_tier': 'provisional',
                                  'source': 'object process token only; movement, lifetime and blend are remake presentation choices'},
        }
        if row.get('shape_number') is not None:
            entry['shape_number'] = int(row['shape_number'])
            entry['plane'] = row.get('plane')
            if row.get('shape_delay') is not None:
                entry['shape_delay'] = int(row['shape_delay'])
            frames = frame_shape_ids(shape_id, entry['shape_number'])
            if len(frames) > 1:
                entry['frame_shape_ids'] = frames
        if row.get('definition_source'):
            entry['definition_source'] = row['definition_source']
        result.append(entry)
    return result


def shape_ids_for(items: list[dict]) -> set[str]:
    ids = set()
    for item in items:
        ids.add(item['shape_resource_id'])
        ids.update(item.get('frame_shape_ids', []))
    return ids


def build_combined_placements(seed: dict) -> list[dict]:
    """EVEF placements whose code carries the 0x80000000 flag reference a combined
    object (level BIN trailing table, slots named by LEVEL<code>.H). Each child is a
    stand object drawn at anchor + (child offset - first child offset): the original
    installer 0x46bd67 (called from the EVEF loop 0x46be17) subtracts the first
    child's table x/y from the EVEF x/y and adds that delta to every child, so the
    first child stands on the EVEF point (static-derived). Kept apart from
    `placements`; plane order stays provisional."""
    entries = {int(entry['index']): entry for entry in seed.get('combined_objects', {}).get('entries', [])}
    result = []
    for row in seed['placements']['records']:
        if row.get('role_from_process') != 'combined_map_object':
            continue
        entry = entries.get(int(row.get('combined_object_index', -1)))
        if entry is None or not entry['children']:
            continue
        anchor_x, anchor_y = (int(v) for v in row['placement_xy_candidate'])
        reference_x, reference_y = (int(v) for v in entry['children'][0]['offset_xy_candidate'])
        children = []
        for child in entry['children']:
            if child.get('join_status') != 'joined' or child.get('role_from_process') != 'map_object' or not child.get('shape_resource'):
                continue
            fields = child.get('object_data_fields', {})
            shape_resource = str(child['shape_resource'])
            offset_x, offset_y = (int(v) for v in child['offset_xy_candidate'])
            children.append({
                'child_index': int(child['child_index']),
                'object_code': int(child['object_code']),
                'object_name': child.get('object_name'),
                'process': child.get('object_process'),
                'shape_resource': shape_resource,
                'shape_resource_id': _basename(shape_resource),
                'offset_xy_candidate': [offset_x, offset_y],
                'candidate_x': anchor_x + offset_x - reference_x,
                'candidate_y': anchor_y + offset_y - reference_y,
                'object_fields': {key: {'value': str(value)} for key, value in fields.items()},
                'runtime_layer_hint': layer_hint(fields),
                'presentation_hint': presentation_hint(fields),
                **({'plane': child['plane']} if child.get('plane') else {}),
            })
        result.append({
            'record_index': int(row['record_index']),
            'combined_object_index': int(row['combined_object_index']),
            'symbol': row.get('object_name'),
            'anchor_x': anchor_x,
            'anchor_y': anchor_y,
            'coordinate_interpretation': {
                'source_kind': 'resource-derived',
                'evidence_tier': 'resource_parser_candidate',
                'interpretation_status': 'provisional',
                'semantics': 'EVEF anchor plus (child offset minus first child offset), minus native SHP draw origin: the first child stands on the EVEF point (static-derived, installer 0x46bd67)',
            },
            'children': children,
        })
    return result


def build(level: int, pak: Path) -> dict[str, int]:
    from hsltools.sources.shp import parse_shp, write_shp_preview
    from hsltools.sources.pak import find_decoded_paks_packages
    seed = json.loads(seed_path(level).read_text(encoding='utf-8'))
    placements = build_placements(seed)
    script_objects = build_script_objects(seed)
    combined = build_combined_placements(seed)
    combined_children = [child for group in combined for child in group['children']]
    packages = find_decoded_paks_packages(pak)
    # Header symbols whose shape is absent from the PAK (obj-<level>.h entries the level
    # never draws) are listed instead of exported; frame runs stop at the first missing member.
    skipped_script_objects: list[dict] = []
    kept_script_objects: list[dict] = []
    for item in script_objects:
        folder = item['shape_resource'].rsplit('\\', 1)[0]
        if not shape_exists(packages, '@:\\' + item['shape_resource']):
            skipped_script_objects.append({'symbol': item['symbol'], 'shape_resource': item['shape_resource'], 'reason': 'shape_missing_in_pak'})
            continue
        if item.get('frame_shape_ids'):
            present = []
            for shape_id in item['frame_shape_ids']:
                if not shape_exists(packages, '@:\\' + folder + '\\' + shape_id):
                    break
                present.append(shape_id)
            if len(present) > 1:
                item['frame_shape_ids'] = present
            else:
                item.pop('frame_shape_ids')
        kept_script_objects.append(item)
    script_objects = kept_script_objects
    shapes: dict[str, dict] = {}
    previews: dict[str, dict] = {}
    for item in placements + script_objects + combined_children:
        folder = item['shape_resource'].rsplit('\\', 1)[0]
        for shape_id in [item['shape_resource_id']] + list(item.get('frame_shape_ids', [])):
            if shape_id in shapes:
                continue
            member = '@:\\' + folder + '\\' + shape_id
            raw = read_shape(packages, member)
            shapes[shape_id] = {'source_member': member, 'source_sha256': _sha(raw),
                                'draw_origin': list(struct.unpack_from('<ii', raw, 28)), 'evidence_tier': 'resource-derived'}
            target = PREVIEW_ROOT / f'{shape_id}.png'
            if not target.is_file():
                write_shp_preview(raw, parse_shp(raw), target)
            previews[shape_id] = {'res_path': 'res://' + target.relative_to(ROOT).as_posix(), 'png_sha256': png_sha256(target)}
    out_dir = level_dir(level)
    out_dir.mkdir(parents=True, exist_ok=True)
    manifest = {
        'schema': MAP_OBJECTS_SCHEMA,
        'level': level,
        'source_policy': 'Stand-object placements from the tracked battle seed (EVEF joined to obj-<level>.obs); SHP previews and draw origins read from the original PAK. Layer/blend hints are remake presentation choices.',
        'evidence_tier': 'resource-derived',
        'sources': {'battle_seed': seed_path(level).relative_to(ROOT).as_posix(), 'seed_sources': {k: v['sha256'] for k, v in seed['sources'].items() if k in ('level', 'objects')}},
        'preview_root': 'res://' + PREVIEW_ROOT.relative_to(ROOT).as_posix(),
        'previews': previews,
        'placements': placements,
        'script_objects': script_objects,
        **({'skipped_script_objects': skipped_script_objects} if skipped_script_objects else {}),
        'unresolved_semantics': [
            'original object plane order, blend math, flash cadence and shadow alpha are not proven by the object fields',
            'fire objects reuse the shared FIRE01 frame sequence; FIRE01-06 starts at frame 0 instead of its source phase',
        ],
    }
    if combined:
        # Only levels with a combined-object table carry this key (keeps other manifests byte-identical).
        manifest['combined_placements'] = combined
        manifest['unresolved_semantics'].append('combined-object children are placed relative to the first child (static-derived, 0x46bd67); their plane order is not proven')
    (out_dir / 'map_objects.json').write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    alignment = {
        'schema': ALIGNMENT_SCHEMA,
        'path': 'res://' + (out_dir / 'map_object_alignment.json').relative_to(ROOT).as_posix(),
        'level': level,
        'source_policy': 'EVEF world coordinates minus the original SHP draw_origin; no per-level calibrations exist yet.',
        'placement_policy': 'Godot consumes this manifest through MapObjectPlacement; scene scripts must not hardcode per-shape placement patches.',
        'coordinate_space': 'BattleSceneRuntime Godot world pixels under the 640x480 logical viewport camera contract',
        'evidence_tier': 'static-derived',
        'provisional': True,
        'calibrations': [],
        'not_proven': ['original plane order and occlusion against actors', 'blend modes, flash cadence and shadow alpha', 'collision boxes as gameplay footprint'],
        'shapes': shapes,
    }
    (out_dir / 'map_object_alignment.json').write_text(json.dumps(alignment, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    return {'placements': len(placements), 'shapes': len(shapes), 'combined': len(combined)}


def check(level: int) -> dict[str, int]:
    seed = json.loads(seed_path(level).read_text(encoding='utf-8'))
    out_dir = level_dir(level)
    manifest = json.loads((out_dir / 'map_objects.json').read_text(encoding='utf-8'))
    alignment = json.loads((out_dir / 'map_object_alignment.json').read_text(encoding='utf-8'))
    if manifest.get('schema') != MAP_OBJECTS_SCHEMA or alignment.get('schema') != ALIGNMENT_SCHEMA:
        raise SystemExit('level map object manifests use unexpected schemas')
    if manifest['placements'] != build_placements(seed):
        raise SystemExit('level map object placements differ from the tracked seed')
    expected_script_objects = build_script_objects(seed)
    skipped = {item['symbol'] for item in manifest.get('skipped_script_objects', [])}
    expected_script_objects = [item for item in expected_script_objects if item['symbol'] not in skipped]
    recorded = {item['symbol']: item for item in manifest.get('script_objects', [])}
    for item in expected_script_objects:
        # Frame runs may stop early when the PAK lacks later members; the tracked
        # prefix is authoritative for what was exported.
        tracked = recorded.get(item['symbol'], {}).get('frame_shape_ids')
        if item.get('frame_shape_ids') and tracked != item['frame_shape_ids']:
            if tracked and item['frame_shape_ids'][:len(tracked)] == tracked:
                item['frame_shape_ids'] = tracked
            elif tracked is None:
                item.pop('frame_shape_ids')
    if manifest.get('script_objects', []) != expected_script_objects:
        raise SystemExit('level script objects differ from the tracked seed')
    combined = build_combined_placements(seed)
    if manifest.get('combined_placements', []) != combined:
        raise SystemExit('level combined placements differ from the tracked seed')
    combined_children = [child for group in combined for child in group['children']]
    for shape_id, preview in manifest['previews'].items():
        path = ROOT / preview['res_path'].removeprefix('res://')
        if not path.is_file() or png_sha256(path) != preview['png_sha256']:
            raise SystemExit(f'map object preview differs or is missing: {path}')
        origin = alignment['shapes'].get(shape_id, {}).get('draw_origin')
        if not (isinstance(origin, list) and len(origin) == 2 and all(isinstance(v, int) for v in origin)):
            raise SystemExit(f'missing draw origin for {shape_id}')
    if set(alignment['shapes']) != shape_ids_for(manifest['placements'] + manifest.get('script_objects', []) + combined_children):
        raise SystemExit('alignment shapes do not match placements')
    return {'placements': len(manifest['placements']), 'shapes': len(alignment['shapes']), 'combined': len(combined)}


class LevelMapObjectsTask(Task):
    family = 'level_map_objects'

    def __init__(self, level: int) -> None:
        self.level = level
        self.name = f'level_map_objects:{level}'
        folder = level_dir(level).relative_to(ROOT).as_posix()
        # PREVIEW_ROOT is shared: each level writes the previews of its own shapes when missing (all 235
        # tracked ones), so every level task declares the directory.
        self.outputs = (f'{folder}/map_objects.json', f'{folder}/map_object_alignment.json', PREVIEW_ROOT.relative_to(ROOT).as_posix() + '/')
        self.inputs = (seed_path(level).relative_to(ROOT).as_posix(), *profile.input_path(level))
        self.replaces = (f'tools/hsl_level_map_objects.py --level {level} --check',)
        self.scripts = ('tools/hsltools/levels/map_objects.py', 'tools/hsltools/levels/profile.py', 'tools/hsltools/sources/actor_walk_frames.py')

    def check(self, ctx: Context) -> str:
        with legacy_failures(self.name):
            summary = check(self.level)
        return f"LEVEL_MAP_OBJECTS_CHECK_PASS level={self.level} placements={summary['placements']} shapes={summary['shapes']} combined={summary['combined']}"

    def generate(self, ctx: Context) -> str:
        pak = original_pak(ctx)
        if not pak.is_file():
            raise NotGeneratable(f'{self.name}: original PAK not found at {pak}')
        summary = build(self.level, pak)
        return f"LEVEL_MAP_OBJECTS_BUILD_PASS level={self.level} placements={summary['placements']} shapes={summary['shapes']} combined={summary['combined']}"


def tasks() -> list[LevelMapObjectsTask]:
    return [LevelMapObjectsTask(level) for level in imported_levels()]
