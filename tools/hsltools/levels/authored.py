"""Assemble a battle written for the remake from content/authored/levelNNN/ (authored_level:N).

A sequel level has no PAK record behind it. The author writes, in one folder:

  level.json     map texture, presentation manifests (walk frames / audio / portraits /
                 combat cut-in, with `sprite_aliases` for characters drawn with another row's
                 or another authored look's art — content/authored/actors/, hsltools.assets.authored_art), the
                 units (id, PLAYERS code, script token, role, start cell) and the header
                 symbols the winfail script inserts (`objects`)
  story.txt      the opening in the original STORY grammar ([story] / action = …)
  winfail.txt    win / fail / event statuses in the original winfail grammar
  messages.json  every message id the two scripts name, plus the speaker names
  terrain.txt    the 32 px grid as text rows (`#` blocked, `.` ground, 1–9 heights)

and the level's knowledge in content/battles/levels/NNN.json `battle` (title, labels,
focus, objective phase — hsltools.levels.profile). This task renders the same tracked
shapes the imported chain produces, so the runtime needs no authored branch:

  content/generated/hsl/authored/battleNNN_seed.json          hsl_battle_seed.v1 (evidence_tier authored)
  content/generated/hsl/authored/levelNNN_terrain.json        hsl_wrd_terrain.v2
  content/generated/hsl/authored/battleNNN/opening_timeline.json      (hsltools.levels.timeline)
  content/generated/hsl/authored/battleNNN/message_text_evidence.json
  content/generated/hsl/authored/battleNNN/progression.json
  content/generated/hsl/authored/battleNNN/{actor_walk_manifest,actor_audio,portraits,combat_animation}.json
  content/battles/battle_NNN.json                             hsl_level_battle.v1

Scripts are parsed by the original grammar parser (hsltools.sources.scripts.parse_text_metadata),
winfail statuses are interpreted live by WinfailScenarioRules, opening walks are traced with
hsltools.levels.battle.trace_opening, unit templates come from the role chain
(content/authored/roles/characters.json rows through hsltools.data.first_battle_formation).
Every unit is labelled `authored` (no evidence ledgers); nothing here claims an original
counterpart. Registration is one campaign.json row, like any level.
"""
from __future__ import annotations

import copy
import hashlib
import json
from pathlib import Path

from PIL import Image

from hsltools.assets import authored_art
from hsltools.data.campaign_actors import COMBAT_KEYS
from hsltools.data.first_battle_formation import actor_templates
from hsltools.legacy import authored_levels
from hsltools.levels import battle as level_battle
from hsltools.levels import profile as level_profile
from hsltools.levels.scenario import SHARED_RESOURCES, impassable, status_timelines
from hsltools.sources.scripts import parse_text_metadata
from hsltools.levels.timeline import compile_documents, level_table_music
from hsltools.native.sources import sources
from hsltools.paths import ROOT
from hsltools.registry import CheckFailed, Context, GeneratedFilesTask
from hsltools.schema import unit as unit_schema
from hsltools.sources.tables import AUTHORED_CHARACTERS, authored_characters
from hsltools.sources.shp import png_sha256

AUTHORED = 'content/authored'
GENERATED = 'content/generated/hsl/authored'
LEVEL_SCHEMA = 'hsl_authored_level.v1'
MESSAGES_SCHEMA = 'hsl_authored_messages.v1'
SEED_SCHEMA = 'hsl_battle_seed.v1'
TERRAIN_SCHEMA = 'hsl_wrd_terrain.v2'
EVIDENCE_SCHEMA = 'hsl_authored_message_text_evidence.v1'
MESSAGE_STATUS = 'resolved_from_authored_messages'
TIER = unit_schema.AUTHORED_TIER
CELL = level_battle.CELL
ROLES = ('player_controlled', 'friendly_ai', 'enemy_ai')
INPUT_FILES = ('level.json', 'story.txt', 'winfail.txt', 'messages.json', 'terrain.txt')
# STORY / winfail tokens that name a message id (and its argument index).
MESSAGE_ARGS = {'actMessage': 2, 'actMessageIfExist': 2, 'actSetDeadMessage': 2}
# level.json presentation: the source manifest each generated presentation manifest copies from.
PRESENTATION_KEYS = ('actor_walk_manifest', 'actor_audio', 'portraits', 'combat_animation')
# Terrain text: `#` a cliff (source height 255, blocked), `.` ground, a digit a walkable height.
BLOCKED_HEIGHT = 255


def folder(level: int) -> Path:
    return ROOT / AUTHORED / f'level{level:03d}'


def outputs(level: int) -> dict[str, str]:
    tag = f'{level:03d}'
    return {
        'seed': f'{GENERATED}/battle{tag}_seed.json',
        'terrain': f'{GENERATED}/level{tag}_terrain.json',
        'opening_timeline': f'{GENERATED}/battle{tag}/opening_timeline.json',
        'message_text_evidence': f'{GENERATED}/battle{tag}/message_text_evidence.json',
        'progression': f'{GENERATED}/battle{tag}/progression.json',
        'actor_walk_manifest': f'{GENERATED}/battle{tag}/actor_walk_manifest.json',
        'actor_audio': f'{GENERATED}/battle{tag}/actor_audio.json',
        'portraits': f'{GENERATED}/battle{tag}/portraits.json',
        'combat_animation': f'{GENERATED}/battle{tag}/combat_animation.json',
        'battle': f'content/battles/battle_{tag}.json',
    }


def _sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def _load_json(path: Path) -> dict:
    return json.loads(path.read_text(encoding='utf-8'))


def _repo(res_path: str) -> Path:
    if not res_path.startswith('res://'):
        raise ValueError(f'expected a res:// path, got {res_path!r}')
    return ROOT / res_path.removeprefix('res://')


def load_inputs(level: int) -> dict:
    """The five authored files plus the level profile, validated for shape."""
    base = folder(level)
    missing = [name for name in INPUT_FILES if not (base / name).is_file()]
    if missing:
        raise ValueError(f'{base.relative_to(ROOT).as_posix()}: missing {missing}')
    manifest = _load_json(base / 'level.json')
    if manifest.get('schema') != LEVEL_SCHEMA or int(manifest.get('level', -1)) != level:
        raise ValueError(f'level{level:03d}/level.json must declare schema {LEVEL_SCHEMA} and level {level}')
    for key in ('map_texture', 'presentation', 'units'):
        if key not in manifest:
            raise ValueError(f'level{level:03d}/level.json lacks {key!r}')
    for key in PRESENTATION_KEYS:
        if key not in manifest['presentation']:
            raise ValueError(f'level{level:03d}/level.json presentation lacks {key!r}')
    ids: set[str] = set()
    for unit in manifest['units']:
        for key in ('id', 'actor', 'token', 'role', 'cell'):
            if key not in unit:
                raise ValueError(f'level{level:03d}/level.json unit {unit.get("id", "?")!r} lacks {key!r}')
        if unit['role'] not in ROLES:
            raise ValueError(f'level{level:03d}/level.json unit {unit["id"]!r}: role must be one of {ROLES}')
        if unit['id'] in ids:
            raise ValueError(f'level{level:03d}/level.json: unit id {unit["id"]!r} appears twice')
        ids.add(unit['id'])
    messages = _load_json(base / 'messages.json')
    if messages.get('schema') != MESSAGES_SCHEMA or not isinstance(messages.get('messages'), dict) or not isinstance(messages.get('speakers'), dict):
        raise ValueError(f'level{level:03d}/messages.json must declare schema {MESSAGES_SCHEMA} with `messages` and `speakers` objects')
    profile = level_profile.load(level)
    if 'battle' not in profile:
        raise ValueError(f'content/battles/levels/{level:03d}.json needs a `battle` section (title, labels, focus, objective phase)')
    return {
        'manifest': manifest,
        'story': (base / 'story.txt').read_bytes(),
        'winfail': (base / 'winfail.txt').read_bytes(),
        'messages': messages,
        'terrain_text': (base / 'terrain.txt').read_text(encoding='utf-8'),
        'profile': profile['battle'],
    }


# --- terrain ---------------------------------------------------------------------------------

def terrain_packet(level: int, text: str, map_size: list[int]) -> dict:
    rows = [line.rstrip() for line in text.splitlines() if line.strip() and not line.lstrip().startswith(';')]
    if not rows or any(len(row) != len(rows[0]) for row in rows):
        raise ValueError(f'level{level:03d}/terrain.txt: every row needs the same number of cells')
    width, height = len(rows[0]), len(rows)
    if [width * CELL, height * CELL] != list(map_size):
        raise ValueError(f'level{level:03d}/terrain.txt is {width}x{height} cells but the map texture is {map_size[0]}x{map_size[1]} px ({CELL} px cells)')
    grid = []
    blocking = 0
    for row in rows:
        cells = []
        for char in row:
            if char == '#':
                cells.append({'t': 0, 'b': 1, 'h': BLOCKED_HEIGHT})
                blocking += 1
            elif char == '.':
                cells.append({'t': 0, 'b': 0, 'h': 0})
            elif char.isdigit():
                cells.append({'t': 0, 'b': 0, 'h': int(char)})
            else:
                raise ValueError(f'level{level:03d}/terrain.txt: unknown cell {char!r} (use # . or a digit)')
        grid.append(cells)
    return {
        'schema': TERRAIN_SCHEMA,
        'evidence_tier': TIER,
        'source_format': {'magic': 'authored', 'version': 0, 'flags': 0, 'width': width, 'height': height, 'element_size': 0,
                          'entry_encoding': f'content/authored/level{level:03d}/terrain.txt: `#` = height {BLOCKED_HEIGHT} (blocked), `.` = 0, digit = height; no tile ids'},
        'stats': {'tile_count': width * height, 'blocking_count': blocking, 'blocking_pct': round(100 * blocking / (width * height), 1),
                  'unique_tile_count': 0, 'tile_id_min': 0, 'tile_id_max': 0},
        'grid': grid,
        'unresolved_semantics': ['Authored grid: blocking and heights are the author\'s; the map texture is drawn independently.'],
        'source': {'member': f'content/authored/level{level:03d}/terrain.txt', 'byte_length': len(text.encode('utf-8')),
                   'sha256': _sha(text.encode('utf-8')), 'storage_policy': 'authored text, tracked'},
    }


# --- scripts and seed ------------------------------------------------------------------------

def _compact_script(metadata: dict) -> dict:
    """The seed's script shape (hsltools.levels.seed._compact_script), from the grammar parser."""
    sections = [{'index': int(block.get('index', 0)), 'name': str(block.get('name', '')), 'codes': list(block.get('codes', [])),
                 'messages': list(block.get('messages', [])), 'actions': list(block.get('actions', []))}
                for block in metadata.get('section_blocks', []) if isinstance(block, dict)]
    return {'encoding': metadata.get('encoding'), 'line_count': metadata.get('line_count'), 'includes': metadata.get('includes', []),
            'section_counts': metadata.get('section_counts', {}), 'action_counts': metadata.get('action_counts', {}),
            'resource_refs': metadata.get('resource_refs', []), 'sections': sections}


def _commands(script: dict):
    for section in script['sections']:
        for action in section.get('actions', []):
            for command in action.get('chain', []):
                yield section, command


def _token_serials(units: list[dict]) -> dict[str, int]:
    """token/serial keys in unit order: the first unit of a token is serial 1, the next 2, …"""
    counters: dict[str, int] = {}
    result = {}
    for unit in units:
        counters[unit['token']] = counters.get(unit['token'], 0) + 1
        result[unit['id']] = counters[unit['token']]
    return result


def build_seed(level: int, inputs: dict, terrain: dict, map_size: list[int], paths: dict[str, str]) -> dict:
    manifest = inputs['manifest']
    story = parse_text_metadata(inputs['story'], 'utf-8')
    winfail = parse_text_metadata(inputs['winfail'], 'utf-8')
    if not story.get('section_blocks'):
        raise ValueError(f'level{level:03d}/story.txt has no [story] section')
    if not any(block.get('name') in ('win', 'fail', 'event') for block in winfail.get('section_blocks', [])):
        raise ValueError(f'level{level:03d}/winfail.txt has no [win] / [fail] / [event] section')
    serials = _token_serials(manifest['units'])
    records = []
    role_counts: dict[str, int] = {}
    for index, unit in enumerate(manifest['units']):
        player = unit['role'] == 'player_controlled'
        role = 'player_install' if player else 'enemy_object'
        role_counts[role] = role_counts.get(role, 0) + 1
        fields = {'obj_Data6': unit['token'], 'obj_Data7': str(int(unit['actor']))}
        records.append({'record_index': index, 'object_code': index + 1, 'placement_xy_candidate': [int(unit['cell'][0]) * CELL, int(unit['cell'][1]) * CELL],
                        'join_status': 'joined', 'object_name': unit['id'], 'object_process': 'defProcPlayerInstall' if player else 'defProcEnemy',
                        'shape_resource': None, 'role_from_process': role, 'object_data_fields': fields, 'serial': serials[unit['id']]})
    objects = manifest.get('objects', {})
    defines = {symbol: str(len(manifest['units']) + 1 + index) for index, symbol in enumerate(objects)}
    script_objects = [{'symbol': symbol, 'object_code': int(defines[symbol]), 'join_status': 'joined', 'object_name': symbol, 'object_process': 'defProcEnemy',
                       'shape_resource': None, 'role_from_process': 'enemy_object',
                       'object_data_fields': {'obj_Data6': spec['token'], 'obj_Data7': str(int(spec['actor']))}}
                      for symbol, spec in objects.items()]
    inserted = {command['args'][0] for _, command in _commands(_compact_script(winfail)) if str(command.get('name', '')).lower().startswith('actinsert') and command.get('args') and str(command['args'][0]).startswith('obj_')}
    unknown = sorted(inserted - set(objects))
    if unknown:
        raise ValueError(f'level{level:03d}/winfail.txt inserts {unknown} but level.json `objects` does not declare them')
    story_source = f'content/authored/level{level:03d}/story.txt'
    winfail_source = f'content/authored/level{level:03d}/winfail.txt'
    return {
        'schema': SEED_SCHEMA,
        'level': level,
        'level_code': f'{level:03d}',
        'level_kind': 'battle',
        'level_kind_claim_limit': 'Authored battle: the winfail script decides the outcome.',
        'evidence_tier': TIER,
        'source_policy': f'authored content under content/authored/level{level:03d}/; no original record',
        'sources': {
            'story': {'member': story_source, 'byte_length': len(inputs['story']), 'sha256': _sha(inputs['story'])},
            'winfail': {'member': winfail_source, 'byte_length': len(inputs['winfail']), 'sha256': _sha(inputs['winfail'])},
            'terrain': {'member': terrain['source']['member'], 'byte_length': terrain['source']['byte_length'], 'sha256': terrain['source']['sha256']},
            'map': {'member': manifest['map_texture'], 'sha256': png_sha256(_repo(manifest['map_texture']))},
        },
        'map': {'source_size': list(map_size), 'decoded_png': manifest['map_texture'], 'decoded_png_size': list(map_size),
                'decoded_png_sha256': png_sha256(_repo(manifest['map_texture'])), 'rows_decode': True},
        'terrain': {'packet': 'res://' + paths['terrain'], 'grid_size': [terrain['source_format']['width'], terrain['source_format']['height']],
                    'tile_count': terrain['stats']['tile_count'], 'blocking_count': terrain['stats']['blocking_count'],
                    'cell_size_from_map_division_candidate': [CELL, CELL], 'cell_size_candidate_status': 'dimension-consistent',
                    'cell_size_claim_limit': 'Authored grid at the remake cell size.'},
        'placements': {'evef_record_count': len(records), 'non_zero_record_count': len(records), 'role_counts_from_object_process': dict(sorted(role_counts.items())),
                       'records': records, 'claim_limit': 'level.json units: cells are the authored start positions before the STORY walks.'},
        'object_header': {'defines': defines},
        'script_objects': script_objects,
        'scripts': {'story': _compact_script(story), 'winfail': _compact_script(winfail),
                    'claim_limit': 'Authored scripts in the original grammar; WinfailScenarioRules and BattleOpeningCoordinator interpret them like an imported level.'},
    }


# --- message evidence ------------------------------------------------------------------------

def _script_message_ids(script: dict) -> list[str]:
    ids: list[str] = []
    for section in script['sections']:
        for entry in section.get('messages', []):
            parts = str(entry).split(',')
            if len(parts) >= 2 and parts[1].strip() not in ids:
                ids.append(parts[1].strip())
        for action in section.get('actions', []):
            for command in action.get('chain', []):
                index = MESSAGE_ARGS.get(str(command.get('name', '')))
                if index is not None and len(command.get('args', [])) > index and str(command['args'][index]) not in ids:
                    ids.append(str(command['args'][index]))
    return ids


def build_message_evidence(level: int, inputs: dict, seed: dict) -> dict:
    authored = inputs['messages']
    texts = {str(key): str(value) for key, value in authored['messages'].items()}
    speakers = {str(token): str(name) for token, name in authored['speakers'].items()}
    per_script = {key: _script_message_ids(seed['scripts'][key]) for key in ('story', 'winfail')}
    used = [rid for key in ('story', 'winfail') for rid in per_script[key]]
    missing = sorted({rid for rid in used if rid not in texts})
    if missing:
        raise ValueError(f'level{level:03d}/messages.json lacks message ids the scripts name: {missing}')
    tokens = sorted({str(command['args'][0]) for _, command in _commands(seed['scripts']['story']) if command.get('name') in MESSAGE_ARGS and command.get('args')}
                    | {str(command['args'][0]) for _, command in _commands(seed['scripts']['winfail']) if command.get('name') in MESSAGE_ARGS and command.get('args')}
                    | {str(entry).split(',')[0] for section in seed['scripts']['winfail']['sections'] for entry in section.get('messages', [])})
    unnamed = [token for token in tokens if token.startswith('SID_') and token not in speakers]
    if unnamed:
        raise ValueError(f'level{level:03d}/messages.json `speakers` lacks {unnamed}')
    messages = {rid: texts[rid] for rid in sorted(set(used), key=lambda value: (len(value), value))}
    # Winfail-time lines name their speaker by a message id (the original's RESOURCE row);
    # an authored level uses the token itself as that id (opening.speaker_resource_ids).
    for token in tokens:
        if token in speakers:
            messages[token] = speakers[token]
    raw = (folder(level) / 'messages.json').read_bytes()
    return {
        'schema': EVIDENCE_SCHEMA,
        'level': level,
        'source_policy': f'Authored dialogue: content/authored/level{level:03d}/messages.json; ids come from the authored STORY / winfail scripts.',
        'evidence_tier': TIER,
        'sources': {'messages': f'content/authored/level{level:03d}/messages.json', 'sha256': _sha(raw)},
        'message_text_status': MESSAGE_STATUS,
        'script_message_sources': [{'source_id': Path(seed['sources'][key]['member']).name, 'message_ids': per_script[key], 'evidence_tier': TIER}
                                   for key in ('story', 'winfail')],
        'messages': messages,
        'speaker_names': speakers,
        'summary': {'message_id_count': len(used), 'speaker_count': len(speakers)},
        'section_title': None,
    }


# --- presentation manifests ------------------------------------------------------------------

def _alias_rows(level: int, manifest: dict, fielded: list[str]) -> dict[str, str]:
    aliases = {str(key): str(value).zfill(3) for key, value in manifest['presentation'].get('sprite_aliases', {}).items()}
    for code, base in aliases.items():
        if code == base:
            raise ValueError(f'level{level:03d}/level.json sprite_aliases: {code} aliases itself')
    return {code: aliases.get(code, code) for code in fielded}


def _authored_codes() -> set[str]:
    return {row['code'].zfill(3) for row in authored_characters()}


def _require_art(level: int, code: str, row: str) -> None:
    """An authored character is drawn by an authored look (its own folder or an aliased one)
    or an aliased imported row; it never falls through to a same-numbered imported row."""
    if code in _authored_codes() and row == code and not authored_art.has_art(code):
        raise ValueError(f'level{level:03d}: authored character {code} has no look: add {authored_art.ART}/{code}/ or name one in presentation.sprite_aliases')


def build_walk_manifest(level: int, manifest: dict, fielded: list[str]) -> dict:
    base = _load_json(_repo(manifest['presentation']['actor_walk_manifest']))
    shared = _load_json(ROOT / 'content/imported/hsl/chapter01/actor_walk_frames/actor_walk_manifest.json')
    rows = _alias_rows(level, manifest, fielded)
    actors = {}
    for code in fielded:
        _require_art(level, code, rows[code])
        if authored_art.has_art(rows[code]):
            entry = authored_art.walk_entry(rows[code], code)
        else:
            entry = base.get('actors', {}).get(rows[code]) or shared.get('actors', {}).get(rows[code])
            if entry is None:
                raise ValueError(f'level{level:03d}: no walk frames for actor {rows[code]} (fielded as {code}) in {manifest["presentation"]["actor_walk_manifest"]}, the shared manifest or {authored_art.ART}/; alias it in presentation.sprite_aliases')
            entry = copy.deepcopy(entry)
            entry['actor_id'] = code
        if rows[code] != code:
            entry['frames_of_actor'] = rows[code]
        actors[code] = entry
    return {'schema': 'hsl_actor_walk_manifest.v1', 'evidence_tier': TIER, 'level': level, 'actor_ids': list(fielded), 'actors': actors,
            'source_manifest': manifest['presentation']['actor_walk_manifest'],
            'source_policy': 'walk frames of the fielded rows: authored looks from content/authored/actors/, imported rows copied from the source manifest; sprite_aliases draw a character with another look\'s frames'}


def build_combat_manifest(level: int, manifest: dict, fielded: list[str]) -> dict:
    """The level's cut-in table: the source manifest's shared keys (backdrop, opening shape,
    policies) and one row per fielded actor that has cut-in art — an authored look's row
    (hsltools.assets.authored_art.combat_row) or the imported row copied. A fielded imported
    row without an imported cut-in, or a look whose art.json says `cutin: null`, has no row
    (the runtime plays its no-art clip, as on any chapter-1 level)."""
    source = manifest['presentation']['combat_animation']
    base = _load_json(_repo(source))
    rows = _alias_rows(level, manifest, fielded)
    actors, without = {}, []
    for code in fielded:
        _require_art(level, code, rows[code])
        if authored_art.has_art(rows[code]):
            row = authored_art.combat_row(rows[code], base)
        else:
            row = copy.deepcopy(base['actors'].get(rows[code])) if rows[code] in base['actors'] else None
        if row is None:
            without.append(code)
            continue
        if rows[code] != code:
            row['frames_of_actor'] = rows[code]
        actors[code] = row
    result = {key: copy.deepcopy(value) for key, value in base.items() if key != 'actors'}
    result.update(evidence_tier=TIER, level=level, actors=actors, actors_without_cutin=without, source_manifest=source,
                  source_policy='backdrop, opening shape and policies copied from the source manifest; fielded rows: authored looks (content/authored/actors/<art>/cutin, strike program of art.json program_of) or the imported row copied')
    return result


def build_audio_manifest(level: int, manifest: dict, fielded: list[str]) -> dict:
    base = _load_json(_repo(manifest['presentation']['actor_audio']))
    rows = _alias_rows(level, manifest, fielded)
    characters = {}
    for code in fielded:
        sound_row = rows[code]
        if authored_art.has_art(rows[code]):
            sound_row = authored_art.sounds_of(rows[code])
            if sound_row is None:
                continue
            if str(int(sound_row)) not in base.get('characters', {}):
                raise ValueError(f'level{level:03d}: {authored_art.ART}/{rows[code]}/art.json sounds_of {sound_row} has no row in {manifest["presentation"]["actor_audio"]}')
        row = base.get('characters', {}).get(str(int(sound_row)))
        if row is not None:
            characters[str(int(code))] = copy.deepcopy(row)
    return {'schema': 'hsl_actor_audio.v1', 'evidence_tier': TIER, 'level': level, 'characters': characters,
            'sounds': copy.deepcopy(base.get('sounds', {})), 'source_manifest': manifest['presentation']['actor_audio'],
            'shared_manifest': base.get('shared_manifest', ''), 'limits': ['sound rows of the fielded actors copied from the source manifest (aliases included)']}


def build_portraits(level: int, manifest: dict, speakers: dict[str, str], names: dict[str, str]) -> dict:
    """actor id -> face for every speaking actor; the authored character shows the source row's
    face under its own name (a new face is a PNG path change here)."""
    base = _load_json(_repo(manifest['presentation']['portraits']))
    shared = _load_json(ROOT / 'content/imported/hsl/chapter01/portraits/manifest.json')
    authored = {row['code'].zfill(3): row for row in authored_characters()}
    rows = _alias_rows(level, manifest, list(speakers))
    actors = {}
    for code in speakers:
        entry = base.get('actors', {}).get(rows[code]) or shared.get('actors', {}).get(rows[code])
        if code in authored:
            entry = {'res_path': authored[code]['portrait'], 'name': authored[code]['name_text']}
        if entry is None:
            raise ValueError(f'level{level:03d}: no portrait for speaking actor {rows[code]} (fielded as {code})')
        actors[code] = {'res_path': entry['res_path'], 'name': names.get(code, entry.get('name', ''))}
    return {'schema': 'hsl_actor_portraits.v1', 'evidence_tier': TIER, 'level': level, 'actors': actors,
            'source_manifest': manifest['presentation']['portraits'],
            'presentation': 'faces of the speaking actors copied from the source manifest; authored characters name their own PNG'}


# --- units -----------------------------------------------------------------------------------

def authored_template(code: str, row: dict) -> dict:
    """A unit template in the rule-key form (content/schema/unit.schema.json RULE_KEYS) from the
    role chain: the same numbers hsltools.data.campaign_actors writes, without the evidence
    ledgers an original row carries."""
    stats = actor_templates([code])[code]
    growth = copy.deepcopy(stats['growth_profile'])
    growth.pop('evidence', None)
    return {'id': '', 'actor_id': code, 'battle_actor_role': 'enemy_ai', 'player_commandable': False, 'coord': [0, 0],
            'hp': stats['max_hp'], 'max_hp': stats['max_hp'], 'mp': stats['max_mp'], 'max_mp': stats['max_mp'],
            'live_speed': stats['live_speed'], 'action_ready': True, 'move_point': stats['move_point'], 'base_move_point': stats['base_move_point'],
            'no_attack': stats['no_attack'], 'weapon_code': int(row.get('weapon_equip', 0)), 'equipment': stats['equipment'],
            'combat_profile': {key: stats[key] for key in COMBAT_KEYS}, 'growth_profile': growth,
            'status_flags': 0, 'status_counters': {'poison': 0, 'paralysis': 0, 'no_magic': 0}}


def _strip_ledgers(unit: dict) -> dict:
    """The unit with the rule keys only: an authored level's units carry no evidence ledgers
    (the runtime labels them `authored`, UnitSchema.AUTHORED_TIER)."""
    return {key: value for key, value in unit.items() if key in unit_schema.RULE_KEYS}


def templates(codes: list[str], players: dict) -> dict[str, dict]:
    """Rule-key templates for every fielded PLAYERS / authored code: the reviewed source
    templates where they exist, the role chain otherwise (authored characters, rows without a
    reviewed placement)."""
    reviewed = level_battle.templates()
    result = {}
    for code in codes:
        if code not in players:
            raise ValueError(f'actor {code} has no PLAYERS.TXT or {AUTHORED_CHARACTERS} row')
        source = reviewed.get(code) or authored_template(code, players[code])
        result[code] = _strip_ledgers(copy.deepcopy(source))
        result[code]['growth_profile'].pop('evidence', None)
    return result


def build_battle(level: int, inputs: dict, seed: dict, evidence: dict, paths: dict[str, str], first: dict, players: dict, grid: list) -> tuple[dict, list[str], dict[str, str]]:
    manifest, profile = inputs['manifest'], inputs['profile']
    units = manifest['units']
    serials = _token_serials(units)
    bindings = {f"{unit['token']}/{serials[unit['id']]}": {'unit_id': unit['id'], 'actor_id': str(unit['actor']).zfill(3),
                                                            'placement_xy': [int(unit['cell'][0]) * CELL, int(unit['cell'][1]) * CELL]}
                for unit in units}
    preview = {'opening': {'actor_bindings': bindings, 'story_objects': {}},
               'story_actors': [{'id': unit['id'], 'actor_id': str(unit['actor']).zfill(3), 'placement_xy': bindings[f"{unit['token']}/{serials[unit['id']]}"]['placement_xy'],
                                 'role': 'player' if unit['role'] == 'player_controlled' else 'enemy'} for unit in units]}
    trace = level_battle.trace_opening(seed, preview)
    codes = sorted({str(unit['actor']).zfill(3) for unit in units} | {str(spec['actor']).zfill(3) for spec in manifest.get('objects', {}).values()})
    source = templates(codes, players)
    roster = []
    taken: set[tuple[int, int]] = set()
    for unit in units:
        if unit['id'] in trace['deleted']:
            continue
        xy = trace['state'][unit['id']]
        if any(value % CELL for value in xy):
            raise ValueError(f'level{level:03d}: {unit["id"]} ends the opening off the {CELL} px grid at {xy}')
        actor = copy.deepcopy(source[str(unit['actor']).zfill(3)])
        role = unit['role']
        actor.update(id=unit['id'], class_id=('Player' if role == 'player_controlled' else 'Enemy') + str(unit['actor']).zfill(3),
                     battle_actor_role=role, player_commandable=role == 'player_controlled',
                     source_object_kind=3 if role == 'player_controlled' else 5, coord=[value // CELL for value in xy])
        for key, value in unit.get('initial_state', {}).items():
            actor[key] = copy.deepcopy(value)
        cell = (actor['coord'][0], actor['coord'][1])
        if cell in taken:
            raise ValueError(f'level{level:03d}: two units end the opening on cell {list(cell)}')
        taken.add(cell)
        roster.append(actor)
    script_actor_templates = level_battle.script_templates(level, seed, source, preview)
    for spec in script_actor_templates.values():
        spec['actor'] = _strip_ledgers(spec['actor'])
        spec['evidence'] = 'level.json objects (token / actor) and the role chain template'
    fielded = codes
    speaking = {}
    for token in evidence['speaker_names']:
        for key, binding in bindings.items():
            if key.split('/')[0] == token:
                speaking[binding['actor_id']] = evidence['speaker_names'][token]
        for spec in script_actor_templates.values():
            if spec.get('token') == token:
                speaking[spec['actor']['actor_id']] = evidence['speaker_names'][token]
    resources = {
        'map_texture': manifest['map_texture'],
        'terrain': 'res://' + paths['terrain'],
        'actor_walk_manifest': 'res://' + paths['actor_walk_manifest'],
        'actor_audio': 'res://' + paths['actor_audio'],
        'portraits': 'res://' + paths['portraits'],
        'opening_timeline': 'res://' + paths['opening_timeline'],
        'message_text_evidence': 'res://' + paths['message_text_evidence'],
    }
    resources['combat_animation'] = 'res://' + paths['combat_animation']
    for key in ('attack_ranges', 'consumables', 'interface_audio', 'fire_animation'):
        resources[key] = first['resources'].get(key, SHARED_RESOURCES[key])
    resources['progression'] = 'res://' + paths['progression']
    resources['battle_seed'] = 'res://' + paths['seed']
    timelines = status_timelines(level, seed, evidence)
    for program in timelines.values():
        for event in program['events']:
            if event.get('script_action_name') in ['actInsertObject', 'actWalkPrevInsertObject', 'actWalkPrevInsertObjectWait']:
                event.pop('cutscene_skip', None)
        program['playable_event_count'] = sum(not event.get('cutscene_skip', False) for event in program['events'])
        program['evidence_tier'] = TIER
    speaker_ids = {token: token for token in evidence['speaker_names']}
    result = dict(schema='hsl_level_battle.v1', id=profile['id'], level=level, level_kind='battle', title=profile['title'],
                  status='authored', rule_adapter='winfail', player_unit_id=profile['initial_focus_unit_id'], resources=resources,
                  # Levels >= 100 have no table track: loading the battle record stays silent (original_music.md §3.1).
                  level_table_music=level_table_music(level),
                  view={'logical_viewport': [640, 480], 'grid_projection': {'origin': [0, 0], 'cell_size': [CELL, CELL], 'evidence_tier': TIER}},
                  commands=copy.deepcopy(first['commands']),
                  opening={'source_script': f'story{level:03d}', 'status': 'coordinator_driven_remake_pacing', 'actor_bindings': bindings,
                           'speaker_resource_ids': speaker_ids, 'story_objects': {},
                           'claim_limit': 'Authored opening: bindings follow level.json unit order (token/serial); the coordinator plays the compiled timeline with remake pacing.',
                           'first_control_event_id': 'first_control_ready', 'initial_focus_unit_id': profile['initial_focus_unit_id']},
                  playable_units=roster,
                  **({'script_actor_templates': script_actor_templates} if script_actor_templates else {}),
                  result_labels=profile['result_labels'],
                  scenario_rules={'initial_objective_phase': profile['initial_objective_phase'], 'allow_optional_clear_after_switch': False,
                                  'events': {}, 'reinforcements': [], 'reinforcement_spawn_cells': [],
                                  'script_fallback': {'escape_zone': []}, 'status_timelines': timelines},
                  provenance={'evidence_tier': TIER, 'authored_inputs': {name: _sha((folder(level) / name).read_bytes()) for name in INPUT_FILES},
                              'unit_templates': 'PLAYERS.TXT / content/authored/roles/characters.json rows through the role chain (evidence ledgers not carried: the level is authored)',
                              'assembly': 'tools/hsltools/levels/authored.py: level.json units and objects, STORY endpoints (hsltools.levels.battle.trace_opening), winfail interpreted live'},
                  unresolved_semantics=[*profile.get('unresolved_semantics', [])])
    for actor in roster:
        x, y = actor['coord']
        if not (0 <= y < len(grid) and 0 <= x < len(grid[0])) or impassable(grid[y][x]):
            raise ValueError(f'level{level:03d}: {actor["id"]} ends the opening on a blocked or outside cell {actor["coord"]}')
    expected = profile.get('expected')
    if expected and (len(roster) != expected['units'] or sum(a['player_commandable'] for a in roster) != expected['players']):
        raise ValueError(f'level{level:03d}: roster {len(roster)} units / {sum(a["player_commandable"] for a in roster)} players differs from the profile')
    return result, fielded, speaking


def build_progression(level: int, fielded: list[str], players: dict) -> dict:
    actors = {code: {'level': int(players[code].get('level', 1)), 'exp': int(players[code].get('exp', 0)), 'kill_exp': int(players[code].get('kill_exp', 0)),
                     'stamina': int(players[code].get('stamina', 0))}
              for code in fielded}
    return {'schema': 'hsl_progression_templates.v1', 'evidence_tier': TIER, 'level': level, 'actors': actors,
            'note': 'level / exp / kill_exp / stamina of every fielded row (PLAYERS.TXT or the authored character table); entry growth applies the reviewed adjustment as in any level.'}


def render_level(level: int) -> dict[str, dict]:
    inputs = load_inputs(level)
    paths = outputs(level)
    manifest = inputs['manifest']
    with Image.open(_repo(manifest['map_texture'])) as image:
        map_size = list(image.size)
    terrain = terrain_packet(level, inputs['terrain_text'], map_size)
    seed = build_seed(level, inputs, terrain, map_size, paths)
    evidence = build_message_evidence(level, inputs, seed)
    timeline = compile_documents(seed, paths['seed'], evidence, paths['message_text_evidence'])
    first = _load_json(level_battle.FIRST)
    players, _, _ = sources()
    battle, fielded, speaking = build_battle(level, inputs, seed, evidence, paths, first, players, terrain['grid'])
    return {
        paths['seed']: seed,
        paths['terrain']: terrain,
        paths['opening_timeline']: timeline,
        paths['message_text_evidence']: evidence,
        paths['progression']: build_progression(level, fielded, players),
        paths['actor_walk_manifest']: build_walk_manifest(level, manifest, fielded),
        paths['actor_audio']: build_audio_manifest(level, manifest, fielded),
        paths['portraits']: build_portraits(level, manifest, speaking, speaking),
        paths['combat_animation']: build_combat_manifest(level, manifest, fielded),
        paths['battle']: battle,
    }


class AuthoredLevelTask(GeneratedFilesTask):
    family = 'authored_level'
    replaces = ()  # born as a registry task: the authored chain has no historical command

    def __init__(self, level: int) -> None:
        self.level = level
        self.name = f'authored_level:{level}'
        paths = outputs(level)
        self.outputs = tuple(paths.values())
        self.inputs = (f'{AUTHORED}/level{level:03d}/', *level_profile.input_path(level), AUTHORED_CHARACTERS, 'content/authored/roles/roster.json',
                       level_battle.FIRST.relative_to(ROOT).as_posix(), unit_schema.SCHEMA_PATH, 'content/generated/hsl/actors/',
                       'content/generated/hsl/roles/profiles.json', 'content/generated/hsl/equipment/items.json',
                       'content/imported/hsl/global/tables/', 'content/imported/hsl/chapter01/actor_walk_frames/actor_walk_manifest.json',
                       'content/imported/hsl/chapter01/portraits/manifest.json', 'content/imported/hsl/chapter01/combat_animation/manifest.json',
                       f'{authored_art.ART}/')
        self.scripts = ('tools/hsltools/levels/authored.py', 'tools/hsltools/assets/authored_art.py', 'tools/hsltools/levels/battle.py', 'tools/hsltools/levels/timeline.py',
                        'tools/hsltools/levels/scenario.py', 'tools/hsltools/sources/scripts.py')

    def render(self, ctx: Context) -> dict[str, bytes]:
        try:
            documents = render_level(self.level)
        except (ValueError, FileNotFoundError, KeyError) as error:
            raise CheckFailed(f'{self.name}: {error}') from error
        schema = unit_schema.load(ctx.root)
        errors = level_battle.unit_schema_errors(documents[outputs(self.level)['battle']], schema)
        if errors:
            raise CheckFailed(f'{self.name}: unit schema violation(s): ' + '; '.join(errors[:5]))
        return {path: level_battle.encode(document) for path, document in documents.items()}

    def summary(self, rendered: dict[str, bytes], mode: str) -> str:
        battle = json.loads(rendered[outputs(self.level)['battle']])
        units = battle['playable_units']
        return (f'AUTHORED_LEVEL_{"CHECK" if mode == "check" else "BUILD"}_PASS level={self.level} units={len(units)} '
                f'players={sum(u["player_commandable"] for u in units)} templates={len(battle.get("script_actor_templates", {}))} '
                f'statuses={len(battle["scenario_rules"]["status_timelines"])} events={json.loads(rendered[outputs(self.level)["opening_timeline"]])["event_count"]}')


def tasks() -> list[AuthoredLevelTask]:
    return [AuthoredLevelTask(level) for level in authored_levels()]
