"""Check curated video evidence without requiring the private source recording.

Optional --video repeats RGB frame identity checks against the supplied recording.
Image integrity and source identity do not certify the accompanying interpretation.

Registry task gameplay_reference (family evidence): the tracked original_gameplay_reference
packet (manifest + frames), no source video. Bodies moved verbatim from the former hsl_gameplay_reference.py (PACKET resolved from this file's depth).
"""
from __future__ import annotations

import argparse
from fractions import Fraction
import hashlib
import json
from pathlib import Path
import subprocess

from PIL import Image

from hsltools.registry import Context, ScriptCheckTask

PACKET = Path(__file__).resolve().parents[3] / 'docs/evidence_packets/runtime_observations/original_gameplay_reference'


def sha256(path: Path) -> str:
    with path.open('rb') as stream:
        digest = hashlib.sha256()
        for block in iter(lambda: stream.read(1024 * 1024), b''):
            digest.update(block)
        return digest.hexdigest()


def local_file(root: Path, value: str) -> Path:
    path = Path(value)
    if path.is_absolute() or '..' in path.parts or not path.parts:
        raise ValueError(f'Invalid packet path: {value}')
    result = (root / path).resolve()
    if not result.is_relative_to(root.resolve()) or not result.is_file():
        raise ValueError(f'Missing or external packet asset: {value}')
    return result


def check(root: Path, data: dict) -> None:
    if data.get('schema') != 'hsl_gameplay_reference.v1':
        raise ValueError('Unsupported gameplay reference schema')
    source = data['source']
    fps = Fraction(*source['fps'])
    count = source['frame_count']
    if type(count) is not int or count <= 0 or fps <= 0:
        raise ValueError('Invalid recording clock')
    if abs(count / float(fps) - source['duration_seconds']) > 1 / float(fps):
        raise ValueError('Recording duration does not match frame count')
    if not source.get('limitations') or len(source['sha256']) != 64:
        raise ValueError('Missing source identity or evidence limitations')

    def frame_indices(values: list) -> None:
        if not values or any(type(i) is not int or not 0 <= i < count for i in values):
            raise ValueError(f'Invalid source frame indices: {values}')
        if values != sorted(set(values)):
            raise ValueError('Source frame candidates must be unique and ordered')

    assets = {}
    for asset in data['assets']:
        name = asset['path']
        if name in assets:
            raise ValueError(f'Duplicate asset: {name}')
        path = local_file(root, name)
        if sha256(path) != asset['sha256']:
            raise ValueError(f'Asset hash mismatch: {name}')
        with Image.open(path) as image:
            if list(image.size) != asset['size']:
                raise ValueError(f'Asset dimensions changed: {name}')
            if asset['kind'] == 'video_frame':
                if list(image.size) != source['recording_size']:
                    raise ValueError(f'Rescaled recording frame: {name}')
                if hashlib.md5(image.convert('RGB').tobytes()).hexdigest() != asset['rgb_md5']:
                    raise ValueError(f'Frame pixels changed: {name}')
                frame_indices(asset['source_frames'])
            elif asset['kind'] not in {'contact_sheet', 'legacy_detail'}:
                raise ValueError(f'Unknown asset kind: {name}')
        assets[name] = asset
    if not assets:
        raise ValueError('Empty evidence packet')
    actual_media = {str(p.relative_to(root)) for p in root.rglob('*')
                    if p.suffix.lower() in {'.png', '.jpg', '.jpeg', '.webp', '.mp4'}}
    if actual_media != set(assets):
        raise ValueError(f'Unindexed/missing media: {sorted(actual_media ^ set(assets))}')
    category_ids = set()
    references = set()
    for category in data['categories']:
        if category['id'] in category_ids:
            raise ValueError('Duplicate category')
        category_ids.add(category['id'])
        sheet = assets.get(category['contact_sheet'], {})
        if sheet.get('kind') != 'contact_sheet':
            raise ValueError('Category contact sheet is missing')
        if not category['retained_frames'] or not category['contact_tiles']:
            raise ValueError('Category has no traceable frames')
        for name in category['retained_frames']:
            if assets.get(name, {}).get('kind') != 'video_frame':
                raise ValueError(f'Category references a missing frame: {name}')
            references.add(name)
        for tile in category['contact_tiles']:
            frame_indices(tile['source_frames'])
    if references != {name for name, asset in assets.items() if asset['kind'] == 'video_frame'}:
        raise ValueError('Unrouted source frames')


def check_video(video: Path, data: dict) -> None:
    if sha256(video) != data['source']['sha256']:
        raise ValueError('Wrong source recording SHA-256')
    result = subprocess.run(
        ['ffmpeg', '-v', 'error', '-nostdin', '-threads', '2', '-i', str(video),
         '-map', '0:v:0', '-pix_fmt', 'rgb24', '-f', 'framemd5', '-'],
        check=True, capture_output=True, text=True,
    )
    decoded = {}
    for line in result.stdout.splitlines():
        if line and not line.startswith('#'):
            fields = [value.strip() for value in line.split(',')]
            decoded[int(fields[2])] = fields[-1]
    if len(decoded) != data['source']['frame_count']:
        raise ValueError('Unexpected decoded frame count')
    for asset in data['assets']:
        if asset['kind'] == 'video_frame':
            if any(decoded.get(i) != asset['rgb_md5'] for i in asset['source_frames']):
                raise ValueError(f'Wrong source-frame mapping: {asset["path"]}')


class GameplayReferenceTask(ScriptCheckTask):
    name = 'gameplay_reference'
    family = 'evidence'
    inputs = ()
    outputs = ('docs/evidence_packets/runtime_observations/original_gameplay_reference/',)
    replaces = ('tools/hsl_gameplay_reference.py',)
    scripts = ('tools/hsltools/evidence/gameplay_reference.py',)

    def verify(self, ctx: Context) -> None:
        data = json.loads((PACKET / 'manifest.json').read_text(encoding='utf-8'))
        check(PACKET, data)
        print(f'GAMEPLAY_REFERENCE_PASS assets={len(data["assets"])} source_video_checked=False')


def tasks() -> list[GameplayReferenceTask]:
    return [GameplayReferenceTask()]


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--packet', type=Path, default=PACKET)
    parser.add_argument('--video', type=Path)
    args = parser.parse_args()
    try:
        data = json.loads((args.packet / 'manifest.json').read_text(encoding='utf-8'))
        check(args.packet, data)
        if args.video:
            check_video(args.video, data)
    except (OSError, ValueError, KeyError, TypeError, subprocess.CalledProcessError) as error:
        parser.exit(1, f'Gameplay reference check failed: {error}\n')
    print(f'GAMEPLAY_REFERENCE_PASS assets={len(data["assets"])} source_video_checked={bool(args.video)}')


if __name__ == '__main__':
    raise SystemExit(main())
