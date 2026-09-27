#!/usr/bin/env python3
"""Measure the title-screen layout by template-matching the decoded Title shapes against
the original reference frame (01_title_and_opening/frame_001.png) and the lit item shapes
against the ring shape. Needs numpy + pillow:

    uv run --with numpy --with pillow python3 tools/hsl_title_layout_probe.py [--check]

--check compares the measured positions with the constants recorded by
tools/hsltools/assets/title_assets.py (REFERENCE_LAYOUT / ITEMS). Not part of verify.sh (no numpy there);
rerun it when the reference frame or the shapes change.
"""
import argparse
import sys
from pathlib import Path

import numpy as np
from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parent))
from hsltools.assets.title_assets import ITEMS, OUT, REFERENCE_FRAME, REFERENCE_LAYOUT, ROOT, SHAPES  # noqa: E402

# Search windows (y0, y1, x0, x1) for each shape's top-left in the reference frame.
WINDOWS = {
    'logo': (0, 120, 60, 300),
    'ring': (120, 260, 150, 300),
    'statue_left': (150, 300, 60, 250),
    'statue_right': (150, 300, 350, 500),
    'cursor_gem': (200, 330, 180, 300),
    'cursor_hand': (200, 330, 330, 420),
}


def _shape(role: str) -> np.ndarray:
    return np.array(Image.open(OUT / 'previews' / f'Title{SHAPES[role]:03d}.SHP.png').convert('RGBA')).astype(np.int32)


def _match(target: np.ndarray, shape: np.ndarray, window, mask=None, step: int = 1):
    alpha = shape[:, :, 3] > 0 if mask is None else mask
    ys, xs = np.nonzero(alpha)
    sel = np.arange(0, len(ys), max(1, len(ys) // 4000))
    ys, xs, vals = ys[sel], xs[sel], shape[:, :, :3][ys[sel], xs[sel]]
    h, w = alpha.shape
    height, width = target.shape[:2]
    best = (1e9, None)
    y0, y1, x0, x1 = window
    for oy in range(max(0, y0), min(y1, height - h + 1), step):
        for ox in range(max(0, x0), min(x1, width - w + 1), step):
            diff = np.abs(target[ys + oy, xs + ox] - vals).mean()
            if diff < best[0]:
                best = (diff, (ox, oy))
    return best


def measure() -> dict:
    frame = np.array(Image.open(ROOT / REFERENCE_FRAME).convert('RGB')).astype(np.int32)
    result = {'layout': {}, 'items': {}}
    for role, window in WINDOWS.items():
        shape = _shape(role)
        coarse = _match(frame, shape, window, step=2)
        ox, oy = coarse[1]
        diff, pos = _match(frame, shape, (oy - 3, oy + 4, ox - 3, ox + 4))
        result['layout'][role] = {'top_left': list(pos), 'match_diff': round(float(diff), 1)}
    ring = _shape('ring')[:, :, :3]
    for item in ITEMS:
        shape = _shape(item['lit'])
        rgb = shape[:, :, :3]
        red = (rgb[:, :, 0] > 150) & (rgb[:, :, 1] < 90) & (rgb[:, :, 2] < 90)
        mask = (shape[:, :, 3] > 0) & ~red
        diff, pos = _match(ring, shape, (0, ring.shape[0], 0, ring.shape[1]), mask=mask)
        result['items'][item['id']] = {'lit_offset_in_ring': list(pos), 'match_diff': round(float(diff), 1)}
    return result


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check', action='store_true')
    args = parser.parse_args()
    result = measure()
    for role, entry in result['layout'].items():
        print(f'{role}: top_left={entry["top_left"]} diff={entry["match_diff"]}')
    for item_id, entry in result['items'].items():
        print(f'{item_id}: lit_offset_in_ring={entry["lit_offset_in_ring"]} diff={entry["match_diff"]}')
    if args.check:
        for role, entry in result['layout'].items():
            if REFERENCE_LAYOUT[role]['top_left'] != entry['top_left']:
                raise SystemExit(f'layout drift for {role}: recorded {REFERENCE_LAYOUT[role]["top_left"]} measured {entry["top_left"]}')
        recorded = {item['id']: item['lit_offset_in_ring'] for item in ITEMS}
        for item_id, entry in result['items'].items():
            if recorded[item_id] != entry['lit_offset_in_ring']:
                raise SystemExit(f'item offset drift for {item_id}: recorded {recorded[item_id]} measured {entry["lit_offset_in_ring"]}')
        print('TITLE_LAYOUT_PROBE_CHECK_PASS')


if __name__ == '__main__':
    main()
