#!/usr/bin/env python3
"""Human-review sheets for combat cut-in art: up-title (job-up) rows and sprite_facing audit.

Outputs (default ignored/g/) are review material only; nothing here upgrades a provisional
sprite_facing to reviewed. Values and asset sources are listed in the JSON so a reviewer can
judge each actor against the decoded frames.
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path

from PIL import Image, ImageDraw

import sys
sys.path.insert(0, str(Path(__file__).resolve().parent))
from hsltools.assets.combat_animation import ROOT as COMBAT_ROOT, PROVISIONAL_FACING_ACTORS, UP_TITLE_ACTORS

DEFAULT_OUTPUT = Path('ignored/g')
SHARED_WALK = Path('content/imported/hsl/shared/actor_walk_frames/actor_walk_manifest.json')
LEVEL_WALK_ROOT = Path('content/imported/hsl/chapter01')
CELL = 96
LABEL = 16
GUTTER = 6
BG = (28, 31, 35, 255)
INK = (236, 236, 220, 255)


def load(path: Path) -> dict:
    return json.loads(path.read_text(encoding='utf-8'))


def walk_manifests() -> list[tuple[str, dict]]:
    found = [(SHARED_WALK.as_posix(), load(SHARED_WALK))] if SHARED_WALK.exists() else []
    for path in sorted(LEVEL_WALK_ROOT.glob('*/actor_walk_frames/actor_walk_manifest.json')):
        found.append((path.as_posix(), load(path)))
    return found


def standing_frames(actor_id: str, manifests: list[tuple[str, dict]]) -> tuple[str, list[Path | None]]:
    """First manifest carrying the actor; facing 0..4 pose 1 (None where the row lacks it)."""
    for source, manifest in manifests:
        entry = manifest.get('actors', {}).get(actor_id)
        if not entry:
            continue
        cells: list[Path | None] = [None] * 5
        for frame in entry.get('frames', []):
            if int(frame.get('pose_index', -1)) == 1 and 0 <= int(frame.get('facing_code', -1)) < 5:
                cells[int(frame['facing_code'])] = Path(frame['png_path'])
        return source, cells
    return '', [None] * 5


def paste(sheet: Image.Image, png: Path | None, x: int, y: int) -> None:
    draw = ImageDraw.Draw(sheet)
    draw.rectangle((x, y, x + CELL - 1, y + CELL - 1), fill=(48, 52, 58, 255), outline=(94, 98, 105, 255))
    if png is None or not png.exists():
        draw.text((x + 20, y + 40), 'missing', fill=(255, 120, 120, 255))
        return
    with Image.open(png) as image:
        frame = image.convert('RGBA')
        frame.thumbnail((CELL - 8, CELL - 8), Image.Resampling.NEAREST)
        sheet.alpha_composite(frame, (x + (CELL - frame.width) // 2, y + (CELL - frame.height) // 2))


def row_sheet(title: str, rows: list[tuple[str, list[tuple[str, Path | None]]]], output: Path) -> None:
    columns = max(len(cells) for _, cells in rows)
    width = GUTTER + columns * (CELL + GUTTER) + 260
    height = 28 + len(rows) * (CELL + LABEL + GUTTER)
    sheet = Image.new('RGBA', (width, height), BG)
    draw = ImageDraw.Draw(sheet)
    draw.text((GUTTER, 6), title, fill=INK)
    for row_index, (label, cells) in enumerate(rows):
        y = 28 + row_index * (CELL + LABEL + GUTTER)
        for column, (caption, png) in enumerate(cells):
            x = GUTTER + column * (CELL + GUTTER)
            paste(sheet, png, x, y)
            draw.text((x + 2, y + CELL + 1), caption, fill=INK)
        draw.text((GUTTER + columns * (CELL + GUTTER) + 6, y + 8), label, fill=INK)
    output.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(output)


def build(output_root: Path) -> dict:
    combat = load(COMBAT_ROOT / 'manifest.json')
    actors = combat['actors']
    manifests = walk_manifests()
    # 1. Up-title rows: ordinary cut-in frames, flash and special (s_shape) strips.
    up_rows = []
    for actor_id in UP_TITLE_ACTORS + ['052']:
        entry = actors[actor_id]
        cells = [(f'P{actor_id} f{i}', Path(frame['res_path'].removeprefix('res://'))) for i, frame in enumerate(entry['frames'])]
        if entry.get('flash'):
            cells.append(('flash', Path(entry['flash']['res_path'].removeprefix('res://'))))
        for i, frame in enumerate(entry.get('special_frames', [])):
            cells.append((f's_shape {i}', Path(frame['res_path'].removeprefix('res://'))))
        up_rows.append((f'{actor_id} facing={entry["sprite_facing"]} (provisional) hurt={entry["hurt_frame"]}', cells))
    row_sheet('Up-title cut-in rows P010-P020 (018 not imported: no SHAPEDEF row) and 052: ordinary frames, flash, s_shape strip', up_rows, output_root / 'up_title_cutin_contact_sheet.png')
    # 2. sprite_facing audit for the 32 wave-6 provisional actors (up-title rows are on sheet 1): five standing walk frames + cut-in frame 0.
    audit = {}
    audit_rows = []
    for actor_id in sorted(PROVISIONAL_FACING_ACTORS - set(UP_TITLE_ACTORS)):
        entry = actors[actor_id]
        source, standing = standing_frames(actor_id, manifests)
        cells = [(f'walk f{i} p1', png) for i, png in enumerate(standing)]
        cells.append(('cut-in f0', Path(entry['frames'][0]['res_path'].removeprefix('res://'))))
        cells.append((f'hurt f{entry["hurt_frame"]}', Path(entry['frames'][entry['hurt_frame']]['res_path'].removeprefix('res://'))))
        audit_rows.append((f'{actor_id}  sprite_facing={entry["sprite_facing"]}  k_action={entry["source_k_action"]}', cells))
        audit[actor_id] = {
            'sprite_facing': entry['sprite_facing'],
            'facing_evidence': entry['facing_evidence'],
            'source_k_action': entry['source_k_action'],
            'cutin_source_member': entry['frames'][0]['source_member'],
            'cutin_frame_count': len(entry['frames']),
            'walk_frames_manifest': source,
            'standing_frames_present': [png is not None for png in standing],
            'review_status': 'awaiting_human_review',
        }
    half = (len(audit_rows) + 1) // 2
    for index, chunk in enumerate([audit_rows[:half], audit_rows[half:]], start=1):
        row_sheet(f'sprite_facing audit {index}/2: walk facing 0..4 pose 1, cut-in frame 0, hurt frame (values are provisional; runtime does not consume sprite_facing)',
                  chunk, output_root / f'sprite_facing_audit_sheet_{index}.png')
    report = {
        'schema': 'hsl_sprite_facing_audit.v1',
        'evidence_tier': 'provisional',
        'claim_limit': 'Review material only. sprite_facing values are copied from the combat manifest and stay provisional until a human confirms them against these sheets.',
        'combat_manifest': (COMBAT_ROOT / 'manifest.json').as_posix(),
        'up_title_actors': UP_TITLE_ACTORS,
        'up_title_not_imported': {'018': 'ANIMAL SID_PLAYER17 block and PAK P018 frames exist, but the SHAPEDEF walk row is commented out; a 009->018 member keeps 009 presentation (negative-evidence for the walk row).'},
        'actors': audit,
    }
    (output_root / 'sprite_facing_audit.json').write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    return report


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output-root', type=Path, default=DEFAULT_OUTPUT)
    args = parser.parse_args()
    report = build(args.output_root)
    print(f'SPRITE_FACING_AUDIT_SHEETS_OK actors={len(report["actors"])} up_title={len(report["up_title_actors"])} output={args.output_root}')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
