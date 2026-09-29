"""Per-level actor asset manifests (walk frames, portraits, audio) for scenes whose
cast is not covered by the shared chapter-01 manifests (level_actors:N).

Actors already present in the shared manifests are referenced, not re-imported;
new actors are decoded from the original PAK into the level folder. The shared
chapter manifests are never modified. The per-level cast (actor ids the scene's EVEF
placements and STORY tokens bind, speakers, script-only shape sets) is the `cast` section of
content/battles/levels/NNN.json (hsltools.levels.profile); the formal battle assembler
(hsltools.levels.battle) requires every winfail speaker to be in it.
Registry task (tools/hsl.py check|generate level_actors:N): check validates the tracked manifests and
their PNG / WAV files without the PAK, generate decodes the missing actors from hsl.pak.
Level 500 is the shared random-encounter pool (hsltools.legacy.SHARED_ACTOR_POOL).
"""
from __future__ import annotations

import hashlib
import json
import re
import struct
import tempfile
from pathlib import Path

from hsltools.legacy import SHARED_ACTOR_POOL
from hsltools.levels import actor_chain_levels, legacy_failures, original_pak, profile
from hsltools.paths import ORIGINAL_PAK, ROOT
from hsltools.registry import Context, NotGeneratable, Task
from hsltools.sources.shp import png_sha256

DEFAULT_PAK = ORIGINAL_PAK
SHARED_WALK = ROOT / 'content/imported/hsl/chapter01/actor_walk_frames/actor_walk_manifest.json'
SHARED_PORTRAITS = ROOT / 'content/imported/hsl/chapter01/portraits/manifest.json'
SHARED_AUDIO = ROOT / 'content/imported/hsl/chapter01/actor_audio.json'
PLAYERS = ROOT / 'content/imported/hsl/global/tables/PLAYERS.TXT'
NAMES = ROOT / 'content/imported/hsl/chapter01/source_texts/RESOURCE.TXT'
AUDIO_EVENTS = ('walk', 'attack', 'miss', 'dead')
# A speaker the shared chapter table (hsltools.assets.portraits) already imports is mirrored
# verbatim, including its `name` (the PLAYERS name field — 克里夫 / 法蘭克 — or, for the 306 ???
# rows, the job_show_name: 一般兵 / 村民); only a level-only import is labelled here, by the
# PLAYERS `name` field with ??? kept. The runtime never reads a
# level manifest's `name`: dialogue labels come from the script's name id, the list labels
# (GiveView, PartyEquipmentScreen, CampaignProgress) read the roster table
# content/generated/hsl/roles/actor_portraits.json, which the shared table feeds, and the
# BattleVitals 姓名 reads roles/actor_panels.json `name` (the +0x04 text verbatim, ??? kept).
PORTRAIT_NAME_POLICY = 'PLAYERS.TXT name field (resource id or resource.h name_N symbol) resolved through RESOURCE.TXT; ??? stays as the original unnamed label'

# Level cast (content/battles/levels/NNN.json `cast`): actor ids that the scene's EVEF placements
# and STORY tokens bind, the speakers with portraits, script-only shape sets / faces.
LEVEL_CASTS: dict[int, dict] = profile.casts()
SHAPE_SETS_SCHEMA = 'hsl_level_actor_shape_sets.v1'


def death_message_rows() -> frozenset[str]:
    """PLAYERS rows with a nonzero `dead_message`: BattleAftermath speaks their line with the
    row's portrait when they fall (content/generated/hsl/combat/aftermath.json declares the text)."""
    rows = set()
    for code, fields in _players().items():
        ids = [value.strip() for value in fields.get('dead_message', '').split(',') if value.strip() not in ('', '0')]
        if ids:
            rows.add(f'{code:03d}')
    return frozenset(rows)


def cast_speakers(level: int) -> tuple[str, ...]:
    """Portrait rows of a level: the scripted speakers plus every cast actor that speaks a
    death line (derived, so a monster added to `actors` never falls with an unimported face)."""
    cast = LEVEL_CASTS[level]
    speakers = list(cast['speakers'])
    for actor in cast['actors']:
        if actor in death_message_rows() and actor not in speakers:
            speakers.append(actor)
    return tuple(speakers)


def level_dir(level: int) -> Path:
    return ROOT / f'content/imported/hsl/chapter01/battle{level:03d}'


def _sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def _res(path: Path) -> str:
    return 'res://' + path.relative_to(ROOT).as_posix()


def _players() -> dict[int, dict[str, str]]:
    result = {}
    from hsltools.sources.tables import override_rows
    for fields in override_rows('PLAYERS.TXT', [{k: v.strip() for k, v in re.findall(r'^\s*(\w+)\s*=\s*([^;\r\n]+)', block, re.M)}
                                                for block in PLAYERS.read_bytes().decode('cp950').split('[character]')[1:]]):
        if fields.get('code'):
            result[int(fields['code'])] = fields
    return result


RESOURCE_HEADER = ROOT / 'content/imported/hsl/global/tables/resource.h'


def _name_table() -> dict[str, str]:
    from hsltools.sources.tables import parse_table
    return parse_table(NAMES.read_bytes())


def _resolve_name(field: str, names: dict[str, str]) -> str:
    """PLAYERS name fields are resource ids or resource.h symbols (name_1 -> 1)."""
    key = field.strip()
    if not key.isdigit():
        for line in RESOURCE_HEADER.read_text(encoding='latin-1').splitlines():
            parts = line.split()
            if len(parts) >= 3 and parts[0] == '#define' and parts[1] == key:
                key = parts[2]
                break
    return names.get(key, field)


def _read_member(packages, member: str) -> bytes:
    from hsltools.sources.pak import find_paks_record_by_name, read_paks_record_bytes
    matches = [(p, r) for p in packages if (r := find_paks_record_by_name(p['records'], member))]
    if len(matches) != 1:
        raise ValueError(f'missing or ambiguous PAK member: {member}')
    package, record = matches[0]
    return read_paks_record_bytes(package['path'], record, data_end_offset=int(package['paks']['candidate_index_offset']))


def build_walk(level: int, cast: tuple[str, ...], pak: Path) -> dict:
    from hsltools.sources.actor_walk_frames import build_actor_walk_manifest, collect_actor_walk_records
    shared = json.loads(SHARED_WALK.read_text(encoding='utf-8'))
    new_ids = [actor for actor in cast if actor not in shared['actors']]
    out_root = level_dir(level) / 'actor_walk_frames'
    manifest = {'schema': shared['schema'], 'evidence_tier': 'resource-derived', 'level': level,
                'actor_ids': list(cast), 'actors': {}, 'shared_manifest': _res(SHARED_WALK),
                'shape_definitions': shared.get('shape_definitions'), 'shape_definitions_sha256': shared.get('shape_definitions_sha256'),
                'source_policy': 'shared chapter-01 actors referenced by id; level-only actors decoded from the original PAK into this folder'}
    for actor in cast:
        if actor in shared['actors']:
            manifest['actors'][actor] = shared['actors'][actor]
    if new_ids:
        records = collect_actor_walk_records(pak, new_ids)
        built = build_actor_walk_manifest(new_ids, records, out_root, decode_png=True, res_root=_res(out_root))
        for actor in new_ids:
            entry = built['actors'][actor]
            if entry['frame_count'] != entry['expected_frame_count']:
                raise ValueError(f'actor {actor} walk frames incomplete: {entry["missing_source_members"]}')
            for frame in entry['frames']:
                frame['png_path'] = Path(frame['png_path']).resolve().relative_to(ROOT).as_posix() if Path(frame['png_path']).is_absolute() else frame['png_path']
            manifest['actors'][actor] = entry
    manifest['level_actor_ids'] = new_ids
    return manifest


def build_portraits(level: int, speakers: tuple[str, ...], pak: Path, shape_faces: tuple[str, ...] = ()) -> dict:
    from hsltools.sources.shp import parse_shp, write_shp_preview
    shared = json.loads(SHARED_PORTRAITS.read_text(encoding='utf-8'))
    players = _players()
    names = _name_table()
    out_root = level_dir(level) / 'portraits'
    result = {'schema': shared['schema'], 'evidence_tier': 'resource-derived', 'level': level, 'actors': {},
              'shared_manifest': _res(SHARED_PORTRAITS),
              'presentation': 'Original SHP pixels; dialogue-view placement is remake presentation.'}
    packages = None
    for member in shape_faces:
        # actShapeMessage,<face shape>,<name id>,<message id>: a portrait named by the
        # script itself (no PLAYERS row); the speaker label comes from the name id.
        if packages is None:
            from hsltools.sources.pak import find_decoded_paks_packages
            packages = find_decoded_paks_packages(pak)
        raw = _read_member(packages, '@:\\' + member)
        target = out_root / (Path(member.replace('\\', '/')).stem + '.png')
        target.parent.mkdir(parents=True, exist_ok=True)
        write_shp_preview(raw, parse_shp(raw), target)
        result.setdefault('shape_faces', {})[member] = {
            'source_member': member, 'res_path': _res(target), 'source_sha256': _sha(raw), 'png_sha256': png_sha256(target),
            'usage': 'actShapeMessage portrait; the speaker name is the token\'s resource id, resolved through RESOURCE.TXT at runtime'}
    for code in speakers:
        if code in shared['actors']:
            result['actors'][code] = shared['actors'][code]
            continue
        row = players[int(code)]
        if packages is None:
            from hsltools.sources.pak import find_decoded_paks_packages
            packages = find_decoded_paks_packages(pak)
        raw = _read_member(packages, '@:\\' + row['picture'])
        target = out_root / f'{code}.png'
        write_shp_preview(raw, parse_shp(raw), target)
        result['actors'][code] = {'source_member': row['picture'], 'name': _resolve_name(row['name'], names),
                                  'name_policy': PORTRAIT_NAME_POLICY,
                                  'res_path': _res(target), 'source_sha256': _sha(raw), 'png_sha256': png_sha256(target)}
    return result


def build_audio(level: int, cast: tuple[str, ...], pak: Path) -> dict:
    from hsltools.assets.actor_audio import profile
    from hsltools.sources.pak import decoded_xor_a8_wave_bytes, parse_xor_a8_wave_candidate
    shared = json.loads(SHARED_AUDIO.read_text(encoding='utf-8'))
    players = _players()
    out_root = level_dir(level) / 'actor_audio'
    characters = {}
    sounds = dict(shared['sounds'])
    packages = None
    for code in cast:
        row = players[int(code)]
        # PLAYERS rows may omit events (character 35, a jobPriest, has no walk/miss sound).
        characters[str(int(code))] = {event: row['sound_' + event].replace('\\', '/').lower() for event in AUDIO_EVENTS if row.get('sound_' + event)}
        for name in characters[str(int(code))].values():
            if name in sounds:
                continue
            if packages is None:
                from hsltools.sources.pak import find_decoded_paks_packages
                packages = find_decoded_paks_packages(pak)
            raw = _read_member(packages, '@:\\' + name.replace('/', '\\'))
            with tempfile.TemporaryDirectory() as tmp:
                source = Path(tmp) / 'source.wav'
                source.write_bytes(raw)
                candidate = parse_xor_a8_wave_candidate(source, 0, len(raw))
                if candidate is None:
                    raise ValueError('unsupported sound format: ' + name)
                audio = decoded_xor_a8_wave_bytes(source, candidate)
            target = out_root / (Path(name).stem + '.wav')
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(audio)
            sounds[name] = {'path': target.relative_to(ROOT).as_posix(), 'res_path': _res(target), 'sha256': _sha(audio), 'profile': profile(audio)}
    used = sorted({name for entry in characters.values() for name in entry.values()})
    return {'schema': shared['schema'], 'evidence_tier': 'resource-derived', 'level': level, 'source_sha256': shared['source_sha256'],
            'characters': characters, 'sounds': {name: sounds[name] for name in used},
            'shared_manifest': _res(SHARED_AUDIO), 'limits': shared.get('limits', [])}


def build_shape_sets(level: int, sets: dict[str, dict], pak: Path) -> dict:
    """Script-only shape sequences (actChangeShape) decoded like walk frames: SHP
    pixels plus the header draw origin at 0x1C, so the runtime anchors them exactly
    like the actor's own frames."""
    from hsltools.sources.shp import parse_shp, write_shp_preview
    out_root = level_dir(level) / 'actor_shape_sets'
    result = {'schema': SHAPE_SETS_SCHEMA, 'evidence_tier': 'resource-derived', 'level': level, 'sets': {},
              'claim_limit': 'Frame pixels and draw origins are original; cycle rate, loop and the change/restore timing are remake pacing.'}
    packages = None
    for name, spec in sets.items():
        frames = []
        for index, member in enumerate(spec['members']):
            if packages is None:
                from hsltools.sources.pak import find_decoded_paks_packages
                packages = find_decoded_paks_packages(pak)
            raw = _read_member(packages, '@:\\' + member)
            if len(raw) < 36 or raw[:4] != b'TLHS':
                raise ValueError(f'invalid SHP header: {member}')
            target = out_root / f"{spec['actor_id']}_{name}_{index + 1}.png"
            write_shp_preview(raw, parse_shp(raw), target)
            frames.append({'index': index, 'source_member': member, 'draw_origin': list(struct.unpack_from('<ii', raw, 0x1C)),
                           'draw_origin_evidence': 'static-derived:0x45fa75-0x45fab4', 'res_path': _res(target),
                           'source_sha256': _sha(raw), 'png_sha256': png_sha256(target)})
        result['sets'][name] = {'actor_id': spec['actor_id'], 'source_token': spec['source_token'], 'frame_count': len(frames),
                                'fps': 8, 'fps_evidence_tier': 'provisional', 'frames': frames}
    return result


def build(level: int, pak: Path) -> dict[str, int]:
    cast = LEVEL_CASTS[level]
    out = level_dir(level)
    if cast.get('shape_sets'):
        shape_sets = build_shape_sets(level, cast['shape_sets'], pak)
        (out / 'actor_shape_sets').mkdir(parents=True, exist_ok=True)
        (out / 'actor_shape_sets/manifest.json').write_text(json.dumps(shape_sets, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    walk = build_walk(level, cast['actors'], pak)
    (out / 'actor_walk_frames').mkdir(parents=True, exist_ok=True)
    (out / 'actor_walk_frames/actor_walk_manifest.json').write_text(json.dumps(walk, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    portraits = build_portraits(level, cast_speakers(level), pak, tuple(cast.get('shape_faces', ())))
    (out / 'portraits').mkdir(parents=True, exist_ok=True)
    (out / 'portraits/manifest.json').write_text(json.dumps(portraits, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    audio = build_audio(level, cast['actors'], pak)
    (out / 'actor_audio.json').write_text(json.dumps(audio, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    return {'actors': len(walk['actors']), 'level_actors': len(walk['level_actor_ids']), 'portraits': len(portraits['actors']), 'sounds': len(audio['sounds'])}


def check(level: int) -> dict[str, int]:
    from hsltools.assets.actor_audio import profile
    cast = LEVEL_CASTS[level]
    out = level_dir(level)
    walk = json.loads((out / 'actor_walk_frames/actor_walk_manifest.json').read_text(encoding='utf-8'))
    shared_walk = json.loads(SHARED_WALK.read_text(encoding='utf-8'))
    if tuple(walk['actor_ids']) != cast['actors'] or set(walk['actors']) != set(cast['actors']):
        raise SystemExit('level walk manifest cast differs from the level profile cast')
    for actor, entry in walk['actors'].items():
        if actor in shared_walk['actors'] and entry != shared_walk['actors'][actor]:
            raise SystemExit(f'shared actor {actor} entry drifted from the chapter manifest; rebuild')
        if entry['frame_count'] != entry['expected_frame_count']:
            raise SystemExit(f'actor {actor} walk frames incomplete')
        for frame in entry['frames']:
            if not (ROOT / frame['res_path'].removeprefix('res://')).is_file():
                raise SystemExit(f'missing walk frame {frame["res_path"]}')
    portraits = json.loads((out / 'portraits/manifest.json').read_text(encoding='utf-8'))
    if set(portraits['actors']) != set(cast_speakers(level)):
        raise SystemExit(f'level portrait cast differs from the level profile cast speakers + death-line rows: {sorted(set(portraits["actors"]) ^ set(cast_speakers(level)))}')
    shared_portraits = json.loads(SHARED_PORTRAITS.read_text(encoding='utf-8'))
    players = _players()
    names = _name_table()
    for code, row in portraits['actors'].items():
        if code in shared_portraits['actors']:
            if row != shared_portraits['actors'][code]:
                raise SystemExit(f'shared speaker {code} entry drifted from the chapter portrait table; rebuild')
        elif row['name'] != _resolve_name(players[int(code)]['name'], names) or row.get('name_policy') != PORTRAIT_NAME_POLICY:
            raise SystemExit(f'level-only portrait {code} label is not the PLAYERS name-field policy; rebuild')
        data = (ROOT / row['res_path'].removeprefix('res://')).read_bytes()
        if png_sha256(data) != row['png_sha256']:
            raise SystemExit(f'portrait {code} differs from manifest')
    if set(portraits.get('shape_faces', {})) != set(cast.get('shape_faces', ())):
        raise SystemExit('level shape-message faces differ from the level profile cast')
    for member, row in portraits.get('shape_faces', {}).items():
        data = (ROOT / row['res_path'].removeprefix('res://')).read_bytes()
        if png_sha256(data) != row['png_sha256']:
            raise SystemExit(f'shape face {member} differs from manifest')
    if cast.get('shape_sets'):
        shape_sets = json.loads((out / 'actor_shape_sets/manifest.json').read_text(encoding='utf-8'))
        if set(shape_sets['sets']) != set(cast['shape_sets']):
            raise SystemExit('level shape sets differ from the level profile cast')
        for name, entry in shape_sets['sets'].items():
            if [f['source_member'] for f in entry['frames']] != cast['shape_sets'][name]['members']:
                raise SystemExit(f'shape set {name} members differ from the level profile cast')
            for frame in entry['frames']:
                data = (ROOT / frame['res_path'].removeprefix('res://')).read_bytes()
                if png_sha256(data) != frame['png_sha256'] or len(frame['draw_origin']) != 2:
                    raise SystemExit(f'shape set frame {frame["res_path"]} differs from manifest')
    audio = json.loads((out / 'actor_audio.json').read_text(encoding='utf-8'))
    if set(audio['characters']) != {str(int(code)) for code in cast['actors']}:
        raise SystemExit('level audio cast differs from the level profile cast')
    shared_audio = json.loads(SHARED_AUDIO.read_text(encoding='utf-8'))
    for name, item in audio['sounds'].items():
        if name in shared_audio['sounds'] and item != shared_audio['sounds'][name]:
            raise SystemExit(f'shared actor sound {name} entry drifted from the chapter audio table; rebuild')
        data = (ROOT / item['path']).read_bytes()
        if _sha(data) != item['sha256'] or profile(data) != item['profile']:
            raise SystemExit(f'actor sound {name} differs from manifest')
    return {'actors': len(walk['actors']), 'portraits': len(portraits['actors']), 'sounds': len(audio['sounds'])}


class LevelActorsTask(Task):
    family = 'level_actors'

    def __init__(self, level: int) -> None:
        self.level = level
        self.name = f'level_actors:{level}'
        folder = level_dir(level).relative_to(ROOT).as_posix()
        outputs = [f'{folder}/actor_walk_frames/actor_walk_manifest.json', f'{folder}/portraits/manifest.json', f'{folder}/actor_audio.json']
        if LEVEL_CASTS[level].get('shape_sets'):
            outputs.append(f'{folder}/actor_shape_sets/manifest.json')
        self.outputs = tuple(outputs)
        self.inputs = (SHARED_WALK.relative_to(ROOT).as_posix(), SHARED_PORTRAITS.relative_to(ROOT).as_posix(),
                       SHARED_AUDIO.relative_to(ROOT).as_posix(), PLAYERS.relative_to(ROOT).as_posix(), NAMES.relative_to(ROOT).as_posix(),
                       *profile.input_path(level))
        self.replaces = (f'tools/hsl_level_actors.py --level {level} --check',)
        self.scripts = ('tools/hsltools/levels/actors.py', 'tools/hsltools/sources/actor_walk_frames.py', 'tools/hsltools/assets/actor_audio.py')

    def check(self, ctx: Context) -> str:
        with legacy_failures(self.name):
            summary = check(self.level)
        return f"LEVEL_ACTORS_CHECK_PASS level={self.level} actors={summary['actors']} portraits={summary['portraits']} sounds={summary['sounds']}"

    def generate(self, ctx: Context) -> str:
        pak = original_pak(ctx)
        if not pak.is_file():
            raise NotGeneratable(f'{self.name}: original PAK not found at {pak}')
        summary = build(self.level, pak)
        return f"LEVEL_ACTORS_BUILD_PASS level={self.level} actors={summary['actors']} level_actors={summary['level_actors']} portraits={summary['portraits']} sounds={summary['sounds']}"


def cast_levels() -> list[int]:
    """Every story level with a per-level actor chain plus the shared encounter pool; the `cast`
    sections of content/battles/levels/NNN.json must cover exactly these (a level folder without
    a cast, or a cast without a folder, fails)."""
    levels = [*actor_chain_levels(), SHARED_ACTOR_POOL]
    missing = [level for level in levels if level not in LEVEL_CASTS]
    extra = sorted(set(LEVEL_CASTS) - set(levels))
    if missing or extra:
        raise ValueError(f'cast sections of content/battles/levels/ and the imported level folders disagree: missing={missing} extra={extra}')
    return levels


def tasks() -> list[LevelActorsTask]:
    return [LevelActorsTask(level) for level in cast_levels()]
