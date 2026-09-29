"""Authored actor art (content/authored/actors/<art>/) -> manifest rows of the imported shapes.

A sequel character has no SHP behind it. The author draws PNGs into one folder per look:

  art.json              hsl_authored_actor_art.v1: `walk.anchor` (the foot point inside every
                        walk PNG), `walk.fps`, `cutin` (null = no cut-in, or `program_of` — the
                        PLAYERS row whose ANIMAL strike program the frames follow — and `anchor`,
                        the point inside every cut-in PNG that stands on the cut-in stage anchor),
                        `sounds_of` (null or the row whose walk / attack / miss / dead sounds it uses),
                        optional `sounds` ({event: WAV path inside the folder}: the look's own sound
                        for that event, replacing the `sounds_of` row's one)
  walk/<group>-<n>.png  group stand / down / right / up / left, n = 1, 2, … (same count in every group)
  cutin/<n>.png         n = 0 … (count = the program row's frame count; the program's aniSetShape
                        indices name these frames)
  sounds/<name>.wav     PCM WAV files `sounds` names (convention; any path inside the folder works)
  portrait.png          the face (characters.json `portrait` names it; not read here)

The folder name is the art id: a character's default look is the folder named by its code; a
level's presentation.sprite_aliases may name any folder (a second look). This module turns a
folder into the rows hsltools.levels.authored copies into a level's manifests:

  walk_entry(art)        an `hsl_actor_walk_manifest.v1` actor entry (hsltools.sources.actor_walk_frames shape)
  combat_row(art, base)  an imported combat manifest row (hsltools.assets.combat_animation shape):
                         the frames are the folder's, the strike program (timeline, dispatch,
                         hurt frame, flash, facing) is copied from `program_of` in `base`
  sounds_of(art)         the row whose sound bindings the look uses (or None)
  sounds(art)            event -> the look's own WAV as an `hsl_actor_audio.v1` sounds entry

s_shape / m_shape strips are not part of the convention: an authored row declares
special_frames / magic_frames [] (the cut-in shows the standing caster; the manifest's
special_frames_policy). Missing files or keys fail; nothing falls back to another row's art.
"""
from __future__ import annotations

import hashlib
import json
import re
import wave
from pathlib import Path

from PIL import Image

from hsltools.checks import CheckTask
from hsltools.paths import ROOT
from hsltools.registry import CheckFailed, Context

ART = 'content/authored/actors'
SCHEMA = 'hsl_authored_actor_art.v1'
TIER = 'authored'
# Walk groups in the imported entry's frame order: (file group, animation_state, direction, facing code).
WALK_GROUPS = (('stand', 'idle', '0', 0), ('down', 'walk', 'down', 1), ('right', 'walk', 'right', 2),
               ('up', 'walk', 'up', 3), ('left', 'walk', 'left', 4))
# Copied from the program row: the strike program and how its frames are read.
PROGRAM_KEYS = ('timeline', 'source_k_action', 'sprite_facing', 'flash', 'attack_flash_offset', 'hurt_frame', 'dispatch')
ART_ID = re.compile(r'[0-9A-Za-z_]+')
# The actor sound events of a PLAYERS row (hsl_actor_audio.v1 characters keys).
SOUND_EVENTS = ('walk', 'attack', 'miss', 'dead')


def folder(art: str) -> Path:
    return ROOT / ART / art


def art_ids() -> list[str]:
    base = ROOT / ART
    return sorted(path.name for path in base.iterdir() if path.is_dir()) if base.is_dir() else []


def has_art(art: str) -> bool:
    return (folder(art) / 'art.json').is_file()


def _rel(path: Path) -> str:
    return path.relative_to(ROOT).as_posix()


def _png(path: Path) -> tuple[int, int]:
    if not path.is_file():
        raise ValueError(f'{_rel(path)} is missing')
    with Image.open(path) as image:
        return image.size


def _point(value, where: str) -> list[int]:
    if not (isinstance(value, list) and len(value) == 2 and all(isinstance(v, int) for v in value)):
        raise ValueError(f'{where} must be [x, y] integers, got {value!r}')
    return list(value)


def load(art: str) -> dict:
    if not ART_ID.fullmatch(art):
        raise ValueError(f'{ART}/{art}: an art id is letters, digits and _ only')
    path = folder(art) / 'art.json'
    if not path.is_file():
        raise ValueError(f'{ART}/{art}/art.json is missing')
    spec = json.loads(path.read_text(encoding='utf-8'))
    if spec.get('schema') != SCHEMA or spec.get('art') != art:
        raise ValueError(f'{ART}/{art}/art.json must declare schema {SCHEMA} and art {art!r}')
    for key in ('walk', 'cutin', 'sounds_of'):
        if key not in spec:
            raise ValueError(f'{ART}/{art}/art.json lacks {key!r} (cutin / sounds_of may be null)')
    return spec


def walk_entry(art: str, actor_id: str) -> dict:
    """The fielded actor's walk entry drawn from the folder (keyed as `actor_id`)."""
    spec = load(art)
    anchor = _point(spec['walk'].get('anchor'), f'{ART}/{art}/art.json walk.anchor')
    fps = int(spec['walk'].get('fps', 8))
    base = folder(art) / 'walk'
    counts = {group: len(list(base.glob(f'{group}-*.png'))) for group, *_ in WALK_GROUPS}
    if len(set(counts.values())) != 1 or not counts['stand']:
        raise ValueError(f'{_rel(base)}: every group (stand/down/right/up/left) needs the same number of frames >= 1, found {counts}')
    per_group = counts['stand']
    frames, animations, facing_set = [], {}, {}
    for group, state, direction, facing in WALK_GROUPS:
        indices = []
        for pose in range(1, per_group + 1):
            path = base / f'{group}-{pose}.png'
            width, height = _png(path)
            if not (0 <= anchor[0] <= width and 0 <= anchor[1] <= height):
                raise ValueError(f'{_rel(path)}: walk.anchor {anchor} lies outside the {width}x{height} image')
            indices.append(len(frames))
            frames.append({'index': len(frames), 'draw_origin': list(anchor), 'draw_origin_evidence': 'authored: art.json walk.anchor',
                           'actor_id': actor_id, 'source_member': _rel(path), 'png_path': _rel(path), 'res_path': 'res://' + _rel(path),
                           'animation_state': state, 'direction': direction, 'facing_code': facing, 'pose_index': pose, 'tier': TIER,
                           'unresolved_semantics': []})
        animations.setdefault(state, {})[direction] = {'frames': indices, 'fps': fps, 'timing_evidence_tier': TIER, 'loop': True,
                                                       'tier': TIER, 'source_field': f'walk/{group}-*.png'}
        facing_set[str(facing)] = {'source_facing_code': facing, 'semantic_status': 'stand' if group == 'stand' else f'walk_{group}', 'tier': TIER}
    return {'actor_id': actor_id, 'frame_count': len(frames), 'expected_frame_count': len(frames), 'frames': frames,
            'animations': animations, 'facing_set': facing_set,
            'fallback': {'mode': 'single_frame', 'src': frames[0]['res_path'], 'reason': 'first stand frame of the authored look', 'tier': TIER},
            'missing_source_members': [], 'unresolved': [], 'art': art, 'evidence_tier': TIER}


def combat_row(art: str, base: dict) -> dict | None:
    """The cut-in row of the look, or None when art.json declares `cutin: null`. `base` is the
    combat manifest the level names (it must carry the `program_of` row)."""
    spec = load(art)
    cutin = spec['cutin']
    if cutin is None:
        return None
    program_of = str(cutin.get('program_of', ''))
    program = base.get('actors', {}).get(program_of)
    if program is None:
        raise ValueError(f'{ART}/{art}/art.json cutin.program_of {program_of!r} is not a row of the combat manifest')
    anchor = _point(cutin.get('anchor'), f'{ART}/{art}/art.json cutin.anchor')
    count = len(program['frames'])
    present = sorted(folder(art).glob('cutin/*.png'))
    if len(present) != count:
        raise ValueError(f'{ART}/{art}/cutin: {len(present)} PNGs, but program_of {program_of} has {count} frames (cutin/0.png … cutin/{count - 1}.png)')
    frames = []
    for index in range(count):
        path = folder(art) / 'cutin' / f'{index}.png'
        width, height = _png(path)
        if not (0 <= anchor[0] <= width and 0 <= anchor[1] <= height):
            raise ValueError(f'{_rel(path)}: cutin.anchor {anchor} lies outside the {width}x{height} image')
        digest = hashlib.sha256(path.read_bytes()).hexdigest()
        frames.append({'res_path': 'res://' + _rel(path), 'draw_origin': list(anchor), 'source_member': _rel(path), 'sha256': digest, 'png_sha256': digest})
    row = {'frames': frames}
    for key in PROGRAM_KEYS:
        if key in program:
            row[key] = json.loads(json.dumps(program[key]))
    row.update(facing_evidence=f'authored: the look is drawn facing as program row {program_of} ({program.get("sprite_facing", "")})',
               hurt_frame_evidence=f'program row {program_of}', special_frames=[], magic_frames=[], cast_program=[], magic_cast_program=[],
               program_of=program_of, art=art, evidence_tier=TIER)
    return row


def sounds_of(art: str) -> str | None:
    value = load(art)['sounds_of']
    return None if value is None else str(value).zfill(3)


def sounds(art: str) -> dict[str, dict]:
    """art.json `sounds`: event -> the sounds entry of the look's own WAV (keyed by its repository
    path in a level's actor_audio `sounds` table). {} when art.json names none."""
    own = load(art).get('sounds') or {}
    if not isinstance(own, dict) or not set(own) <= set(SOUND_EVENTS):
        raise ValueError(f'{ART}/{art}/art.json sounds must map events {SOUND_EVENTS} to WAV paths, got {own!r}')
    result = {}
    for event, relative in own.items():
        path = (folder(art) / str(relative)).resolve()
        if folder(art).resolve() not in path.parents or path.suffix.lower() != '.wav' or not path.is_file():
            raise ValueError(f'{ART}/{art}/art.json sounds.{event}: {relative!r} is not a WAV file inside the folder')
        try:
            with wave.open(str(path), 'rb') as handle:
                profile = {'channels': handle.getnchannels(), 'sample_rate': handle.getframerate(),
                           'sample_width': handle.getsampwidth(), 'frame_count': handle.getnframes()}
        except (wave.Error, EOFError) as error:
            raise ValueError(f'{_rel(path)}: not a PCM WAV ({error})') from error
        result[event] = {'path': _rel(path), 'res_path': 'res://' + _rel(path),
                         'sha256': hashlib.sha256(path.read_bytes()).hexdigest(), 'profile': profile, 'evidence_tier': TIER}
    return result


class AuthoredArtTask(CheckTask):
    """Every look under content/authored/actors/ builds its walk entry and cut-in row (a look no
    level fields yet is still checked)."""
    name = 'authored_art'
    family = 'assets'
    inputs = (f'{ART}/', 'content/imported/hsl/chapter01/combat_animation/manifest.json')
    replaces = ()  # born as a registry task
    scripts = ('tools/hsltools/assets/authored_art.py',)

    def check(self, ctx: Context) -> str:
        base = json.loads((ctx.root / 'content/imported/hsl/chapter01/combat_animation/manifest.json').read_text(encoding='utf-8'))
        walk = cutins = own_sounds = 0
        try:
            for art in art_ids():
                walk += walk_entry(art, art)['frame_count']
                cutins += combat_row(art, base) is not None
                sounds_of(art)
                own_sounds += len(sounds(art))
        except (ValueError, KeyError, OSError) as error:
            raise CheckFailed(f'{self.name}: {error}') from error
        return f'AUTHORED_ART_PASS looks={len(art_ids())} walk_frames={walk} cutins={cutins} sounds={own_sounds}'


def tasks() -> list[AuthoredArtTask]:
    return [AuthoredArtTask()]
