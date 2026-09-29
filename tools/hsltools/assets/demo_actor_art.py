"""The demo actors' placeholder art (content/authored/actors/102/, 103/): recoloured chapter-one frames.

Registry task demo_actor_art (family assets). The two authored demo characters 蕾雅 (102) and 托蘭 (103)
wear the art of PLAYERS rows 003 and 004 with the hue turned: every walk frame, cut-in frame and the
face of the source row, hue shifted in HSV (colorsys, channels rounded to the nearest integer) and
re-placed on one canvas per strip so every frame shares the anchor art.json declares. The art is a
derivative of the original frames, so the public repository ships none of it; this task draws it from
the player's import, after the imports it reads (actor_portraits, combat_animation, level_actors:1,
actor_walk_manifest:chapter01) and before the tasks that read it (roster_portraits, authored_level:200).

  portrait.png          chapter01/portraits/<source>.png, same size
  cutin/<n>.png         chapter01/combat_animation/<source>/<n>.png pasted at
                        art.json cutin.anchor - the frame's draw_origin (combat manifest)
  walk/<group>-<n>.png  the source's walk frame (facing code = group index, pose n) pasted at
                        art.json walk.anchor - the frame's draw_origin (walk manifest)

A strip's canvas is the smallest that holds every pasted frame. The hue turn per look was read off
the tracked placeholder art by comparing it with the source frames pixel for pixel: 102 = 0.5 turn,
103 = 0.33 turn (all 73 PNGs reproduce RGBA-identical). check = every output's pixels equal the
rendering (png_sha256); generate writes the PNGs whose pixels differ, encoded with optimize=True (with
our Pillow build that reproduces the tracked bytes; what the level tables record is the pixel hash).
"""
from __future__ import annotations

import colorsys
import json
from pathlib import Path

from hsltools.paths import ROOT
from hsltools.registry import CheckFailed, Context, ScriptCheckTask
from hsltools.sources.shp import png_sha256

ART = 'content/authored/actors'
WALK_GROUPS = ('stand', 'down', 'right', 'up', 'left')  # facing codes 0..4 (hsltools.assets.authored_art)
POSES = 6
COMBAT = 'content/imported/hsl/chapter01/combat_animation/manifest.json'
PORTRAITS = 'content/imported/hsl/chapter01/portraits/'
# look: source row, the walk manifest that carries the source's frames, hue turn, cut-in frame count
LOOKS = {
    '102': {'source': '003', 'walk_manifest': 'content/imported/hsl/chapter01/battle001/actor_walk_frames/actor_walk_manifest.json',
            'hue_turn': 0.5, 'cutins': 6},
    '103': {'source': '004', 'walk_manifest': 'content/imported/hsl/chapter01/actor_walk_frames/actor_walk_manifest.json',
            'hue_turn': 0.33, 'cutins': 5},
}


def output_paths(art: str) -> list[str]:
    spec = LOOKS[art]
    return ([f'{ART}/{art}/portrait.png'] + [f'{ART}/{art}/cutin/{index}.png' for index in range(spec['cutins'])]
            + [f'{ART}/{art}/walk/{group}-{pose}.png' for group in WALK_GROUPS for pose in range(1, POSES + 1)])


def _recolour(image, turn: float):
    cache: dict[tuple, tuple] = {}

    def shift(pixel):
        if pixel not in cache:
            h, s, v = colorsys.rgb_to_hsv(*(channel / 255 for channel in pixel[:3]))
            cache[pixel] = (*(round(channel * 255) for channel in colorsys.hsv_to_rgb((h + turn) % 1, s, v)), pixel[3])
        return cache[pixel]

    out = image.copy()
    out.putdata([shift(pixel) for pixel in getattr(image, 'get_flattened_data', image.getdata)()])
    return out


def _strip(frames: list[tuple[str, list[int]]], anchor: list[int], turn: float) -> list:
    """[(png path, draw origin)] -> the recoloured images on one canvas with `anchor` at every origin."""
    from PIL import Image

    placed = []
    for path, origin in frames:
        with Image.open(ROOT / path) as source:
            image = source.convert('RGBA')
        offset = (anchor[0] - origin[0], anchor[1] - origin[1])
        if min(offset) < 0:
            raise ValueError(f'{path}: draw_origin {origin} lies beyond the anchor {anchor}')
        placed.append((image, offset))
    size = (max(offset[0] + image.width for image, offset in placed), max(offset[1] + image.height for image, offset in placed))
    result = []
    for image, offset in placed:
        canvas = Image.new('RGBA', size)
        canvas.paste(image, offset)
        result.append(_recolour(canvas, turn))
    return result


def render(art: str) -> dict[str, object]:
    """{output path: PIL image} of one look."""
    from PIL import Image

    spec = LOOKS[art]
    source = spec['source']
    look = json.loads((ROOT / ART / art / 'art.json').read_text(encoding='utf-8'))
    with Image.open(ROOT / PORTRAITS / f'{source}.png') as face:
        images = {f'{ART}/{art}/portrait.png': _recolour(face.convert('RGBA'), spec['hue_turn'])}
    combat = json.loads((ROOT / COMBAT).read_text(encoding='utf-8'))['actors'][source]['frames'][:spec['cutins']]
    cutins = [(frame['res_path'].removeprefix('res://'), frame['draw_origin']) for frame in combat]
    for index, image in enumerate(_strip(cutins, look['cutin']['anchor'], spec['hue_turn'])):
        images[f'{ART}/{art}/cutin/{index}.png'] = image
    walk = json.loads((ROOT / spec['walk_manifest']).read_text(encoding='utf-8'))
    entry = walk['actors'][source]
    by_pose = {(frame['facing_code'], frame['pose_index']): frame for frame in entry['frames']}
    keys = [(facing, pose) for facing in range(len(WALK_GROUPS)) for pose in range(1, POSES + 1)]
    frames = [(by_pose[key]['png_path'], by_pose[key]['draw_origin']) for key in keys]
    for (facing, pose), image in zip(keys, _strip(frames, look['walk']['anchor'], spec['hue_turn'])):
        images[f'{ART}/{art}/walk/{WALK_GROUPS[facing]}-{pose}.png'] = image
    if sorted(images) != sorted(output_paths(art)):
        raise ValueError(f'{art}: rendered {len(images)} images, expected {len(output_paths(art))}')
    return images


def _pixels(image) -> str:
    import io
    buffer = io.BytesIO()
    image.save(buffer, format='PNG')
    return png_sha256(buffer.getvalue())


class DemoActorArtTask(ScriptCheckTask):
    name = 'demo_actor_art'
    family = 'assets'
    inputs = (PORTRAITS, COMBAT, 'content/imported/hsl/chapter01/combat_animation/003/', 'content/imported/hsl/chapter01/combat_animation/004/',
              *(spec['walk_manifest'] for spec in LOOKS.values()), *(f'{ART}/{art}/art.json' for art in LOOKS))
    outputs = tuple(path for art in LOOKS for path in output_paths(art))
    scripts = ('tools/hsltools/assets/demo_actor_art.py',)

    def verify(self, ctx: Context) -> None:
        differ = [path for art in LOOKS for path, image in render(art).items()
                  if not (ctx.root / path).is_file() or png_sha256(ctx.root / path) != _pixels(image)]
        if differ:
            raise CheckFailed(f'{self.name}: {len(differ)} placeholder PNG(s) differ from the recoloured source frames, first={differ[0]}'
                              f' — `python3 tools/hsl.py generate {self.name}` rewrites them')
        print(f'DEMO_ACTOR_ART_PASS looks={len(LOOKS)} images={len(self.outputs)}')

    def build(self, ctx: Context) -> None:
        for art in LOOKS:
            for path, image in render(art).items():
                target = ctx.root / path
                if not (target.is_file() and png_sha256(target) == _pixels(image)):
                    target.parent.mkdir(parents=True, exist_ok=True)
                    image.save(target, optimize=True)


def tasks() -> list[DemoActorArtTask]:
    return [DemoActorArtTask()]
