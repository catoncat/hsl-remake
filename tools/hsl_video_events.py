#!/usr/bin/env python3
"""Pixel inventory of screen changes in a gameplay video (original recording or remake movie).

Research tool for event-diff lanes: it answers "when and where did the picture change", not "what
changed" or "is it the same as the original". Raw scans, event lists and clips belong in ignored/.

  scan    decode VIDEO (ffmpeg, PTS kept, variable frame rate respected), crop the game area, downscale
          to 320x240 gray and store, per decoded frame, the count of changed pixels in each 4x4 block
          (an 80x60 grid; one block = 8x8 logical 640x480 pixels) plus mean luma.  Needs numpy
          (`uv run --with numpy python3 tools/hsl_video_events.py scan ...`).
  events  turn a scan into change events: contiguous runs of active frames (gaps up to --gap seconds
          merged), split where the change switches between full-screen, camera pan (phase correlation
          explains the frame) and local, with per-event PTS range, union box (logical 640x480
          pixels), peak area, cluster list and summed pan vector.  Segmentation is pure Python;
          reading the .npz needs numpy.
  camera  camera-motion runs of a scan: consecutive translation-explained frames (one idle frame
          bridged) with per-run frame count, peak and total step in logical pixels.  A smooth scroll
          is a multi-frame run of small steps; a camera cut to a new spot is a one-frame jump.

  region  one logical box at the source frame rate between --start and --end: per frame the pixels that
          differ from a reference frame (box, centroid, mean luma change, mean colour, per-row-band
          counts), the fraction changed since the previous frame, transition runs (a hard cut is one
          frame, a dissolve several) and the dominant period of the box's mean luma (a pulsing
          highlight).  Pure Python; use small boxes.
  audio   sound onsets (10 ms RMS envelope rising >= 12 dB) in the video's audio between --start and
          --end, and for each --match WAV the best normalised cross-correlation and its time (which
          source sound this is).  Needs numpy.
  sprite  where and when a known sprite (an RGBA PNG decoded from the original SHP, e.g. the KILL or
          LEVEL UP art) is on screen inside one logical box between --start and --end: per frame the
          best placement (masked mean absolute RGB difference over the sprite's opaque pixels) and,
          as runs of frames at or under --max-score, when it appeared, how long it stayed and how its
          centre moved.  Needs numpy for the matching; the run logic is pure Python.

Times are the decoded frame PTS in seconds; never convert frame numbers to seconds.
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path
import re
import subprocess
import sys
import threading

GRID_W, GRID_H = 80, 60          # blocks; each block is 4x4 scan pixels = 8x8 logical pixels
SCAN_W, SCAN_H = 320, 240
LOGICAL_PER_BLOCK = 8
PAN_RESIDUAL = 0.15              # changed fraction left after undoing the camera shift
PTS_RE = re.compile(r'pts_time:\s*(-?[0-9.]+)')


# ----------------------------------------------------------------------------------------- scan

def scan(video: str, crop: str | None, out: Path, threshold: int, threads: int) -> dict:
    import numpy as np  # scan only; events stays pure Python

    filters = ([f'crop={crop}'] if crop else []) + [f'scale={SCAN_W}:{SCAN_H}:flags=area', 'format=gray', 'showinfo']
    command = ['ffmpeg', '-nostdin', '-hide_banner', '-v', 'info', '-threads', str(threads), '-i', video, '-an',
               '-vf', ','.join(filters), '-fps_mode', 'passthrough', '-f', 'rawvideo', '-']
    process = subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    pts: list[float] = []

    def read_stderr() -> None:
        for raw in process.stderr:
            line = raw.decode('utf-8', 'replace')
            if 'showinfo' in line and ' n:' in line:
                match = PTS_RE.search(line)
                if match:
                    pts.append(float(match.group(1)))

    reader = threading.Thread(target=read_stderr, daemon=True)
    reader.start()
    frame_bytes = SCAN_W * SCAN_H
    blocks, luma, shifts = [], [], []
    previous = None
    window = np.outer(np.hanning(SCAN_H), np.hanning(SCAN_W))
    while True:
        data = process.stdout.read(frame_bytes)
        if len(data) < frame_bytes:
            break
        frame = np.frombuffer(data, np.uint8).reshape(SCAN_H, SCAN_W).astype(np.int16)
        shift = (0, 0, 0.0)
        if previous is None:
            changed = np.zeros((SCAN_H, SCAN_W), bool)
        else:
            changed = np.abs(frame - previous) > threshold
            if changed.mean() > 0.02:
                shift = pan_shift(np, previous, frame, window, threshold)
        blocks.append(changed.reshape(GRID_H, 4, GRID_W, 4).sum(axis=(1, 3)).astype(np.uint8))
        luma.append(float(frame.mean()))
        shifts.append(shift)
        previous = frame
    process.wait()
    reader.join()
    if process.returncode != 0:
        raise SystemExit(f'ffmpeg failed with {process.returncode}')
    if len(pts) != len(blocks):
        raise SystemExit(f'PTS count {len(pts)} != frame count {len(blocks)}; refusing to guess times')
    meta = {'schema': 'hsl_video_events.scan.v1', 'video': video, 'crop': crop, 'threshold': threshold,
            'grid': [GRID_W, GRID_H], 'logical_per_block': LOGICAL_PER_BLOCK, 'frames': len(pts)}
    out.parent.mkdir(parents=True, exist_ok=True)
    np.savez_compressed(out, pts=np.array(pts), blocks=np.stack(blocks), luma=np.array(luma, np.float32),
                        shifts=np.array(shifts, np.float32), meta=json.dumps(meta, ensure_ascii=False))
    return meta


def pan_shift(np, previous, frame, window, threshold):
    """Phase-correlation camera shift (dx, dy in scan pixels) and the changed fraction left after
    undoing it on the overlap; a small residual means the frame change is a camera pan."""
    a = np.fft.fft2((previous - previous.mean()) * window)
    b = np.fft.fft2((frame - frame.mean()) * window)
    cross = a.conj() * b
    cross /= np.abs(cross) + 1e-9
    corr = np.abs(np.fft.ifft2(cross))
    dy, dx = np.unravel_index(int(np.argmax(corr)), corr.shape)
    dy = dy - SCAN_H if dy > SCAN_H // 2 else dy
    dx = dx - SCAN_W if dx > SCAN_W // 2 else dx
    if dx == 0 and dy == 0:
        return (0, 0, 1.0)
    h, w = SCAN_H - abs(dy), SCAN_W - abs(dx)
    if h < SCAN_H // 2 or w < SCAN_W // 2:
        return (dx, dy, 1.0)
    new = frame[max(dy, 0):max(dy, 0) + h, max(dx, 0):max(dx, 0) + w]
    old = previous[max(-dy, 0):max(-dy, 0) + h, max(-dx, 0):max(-dx, 0) + w]
    return (dx, dy, float((np.abs(new - old) > threshold).mean()))


def load_scan(path: Path) -> tuple[list[float], list[list[int]], list[float], dict]:
    """Return pts, per-frame active block indices (count >= 2), luma, shifts, meta."""
    import numpy as np

    data = np.load(path)
    active = [np.flatnonzero(frame.ravel() >= 2).tolist() for frame in data['blocks']]
    return (data['pts'].tolist(), active, data['luma'].tolist(), data['shifts'].tolist(),
            json.loads(str(data['meta'])))


# --------------------------------------------------------------------------------------- events

def ambient_blocks(active: list[list[int]], min_rate: float) -> set[int]:
    """Blocks active in at least min_rate of all frames (looping map animation, clock, watermark)."""
    counts: dict[int, int] = {}
    for frame in active:
        for block in frame:
            counts[block] = counts.get(block, 0) + 1
    total = max(1, len(active))
    return {block for block, count in counts.items() if count / total >= min_rate}


def clusters(blocks: set[int]) -> list[dict]:
    """4-connected components (with a one-block bridge) of a block set, largest first."""
    remaining = set(blocks)
    found = []
    while remaining:
        seed = remaining.pop()
        stack, members = [seed], [seed]
        while stack:
            block = stack.pop()
            x, y = block % GRID_W, block // GRID_W
            for dx in (-2, -1, 0, 1, 2):
                for dy in (-2, -1, 0, 1, 2):
                    nx, ny = x + dx, y + dy
                    if 0 <= nx < GRID_W and 0 <= ny < GRID_H:
                        other = ny * GRID_W + nx
                        if other in remaining:
                            remaining.discard(other)
                            stack.append(other)
                            members.append(other)
        found.append({'blocks': len(members), 'box': box(members)})
    return sorted(found, key=lambda item: -item['blocks'])


def box(blocks) -> list[int]:
    """Union box in logical 640x480 pixels: [x, y, w, h]."""
    xs = [block % GRID_W for block in blocks]
    ys = [block // GRID_W for block in blocks]
    x0, y0 = min(xs) * LOGICAL_PER_BLOCK, min(ys) * LOGICAL_PER_BLOCK
    return [x0, y0, (max(xs) + 1) * LOGICAL_PER_BLOCK - x0, (max(ys) + 1) * LOGICAL_PER_BLOCK - y0]


def frame_kind(count: int, full_fraction: float, shift=None) -> str:
    if count == 0:
        return 'idle'
    if shift and (shift[0] or shift[1]) and shift[2] < PAN_RESIDUAL:
        return 'pan'
    return 'full' if count >= full_fraction * GRID_W * GRID_H else 'local'


def segment(pts: list[float], active: list[list[int]], luma: list[float], shifts=None, *, gap: float = 0.25,
            full_fraction: float = 0.35, ambient_rate: float = 0.5, min_frames: int = 1) -> dict:
    """Group frames into change events. An event ends after `gap` seconds without change or when the
    frame kind switches between full-screen and local (hysteresis: two frames of the other kind)."""
    ambient = ambient_blocks(active, ambient_rate)
    filtered = [[block for block in frame if block not in ambient] for frame in active]
    shifts = shifts or [None] * len(pts)
    kinds = [frame_kind(len(frame), full_fraction, shift) for frame, shift in zip(filtered, shifts)]
    events: list[dict] = []
    current = None

    def close() -> None:
        nonlocal current
        if current and current['frames'] >= min_frames:
            union = current.pop('union')
            peak = current.pop('peak')
            current['box'] = box(union) if union else None
            current['area_blocks'] = len(union)
            current['peak_blocks'] = peak
            current['clusters'] = clusters(union)[:6] if current['kind'] == 'local' else []
            if current['kind'] == 'pan':
                current['pan_logical'] = [round(v * 2) for v in current['pan']]
            current.pop('pan')
            current['luma'] = [round(current.pop('luma0'), 1), round(current.pop('luma1'), 1)]
            current['duration'] = round(current['end'] - current['start'], 3)
            events.append(current)
        current = None

    for index, (time, frame, kind) in enumerate(zip(pts, filtered, kinds)):
        if kind == 'idle':
            if current and time - current['last_active'] > gap:
                close()
            continue
        switch = (current is not None and current['kind'] != kind
                  and index + 1 < len(kinds) and kinds[index + 1] == kind)
        if current and (time - current['last_active'] > gap or switch):
            close()
        if current is None:
            start = pts[index - 1] if index > 0 else time
            current = {'start': round(start, 3), 'end': round(time, 3), 'last_active': time, 'kind': kind,
                       'frames': 0, 'union': set(), 'peak': 0, 'luma0': luma[index - 1] if index else luma[index],
                       'luma1': luma[index], 'pan': [0.0, 0.0]}
        current['end'] = round(time, 3)
        current['last_active'] = time
        current['frames'] += 1
        current['union'].update(frame)
        current['peak'] = max(current['peak'], len(frame))
        current['luma1'] = luma[index]
        if kind == 'pan':
            current['pan'][0] += shifts[index][0]
            current['pan'][1] += shifts[index][1]
    close()
    for number, event in enumerate(events):
        event.pop('last_active', None)
        event['id'] = f'e{number:04d}'
    summary = {'events': len(events), 'full': sum(1 for e in events if e['kind'] == 'full'),
               'local': sum(1 for e in events if e['kind'] == 'local'),
               'pan': sum(1 for e in events if e['kind'] == 'pan'),
               'ambient_blocks': len(ambient), 'frames': len(pts),
               'params': {'gap': gap, 'full_fraction': full_fraction, 'ambient_rate': ambient_rate,
                          'min_frames': min_frames}}
    return {'schema': 'hsl_video_events.events.v1', 'summary': summary, 'events': events}


def frame_clusters(frame: list[int]) -> list[set[int]]:
    """Spatial components of one frame's active blocks (8-connected with a one-block bridge)."""
    remaining = set(frame)
    found = []
    while remaining:
        seed = remaining.pop()
        stack, members = [seed], {seed}
        while stack:
            block = stack.pop()
            x, y = block % GRID_W, block // GRID_W
            for dx in (-2, -1, 0, 1, 2):
                for dy in (-2, -1, 0, 1, 2):
                    nx, ny = x + dx, y + dy
                    other = ny * GRID_W + nx
                    if 0 <= nx < GRID_W and 0 <= ny < GRID_H and other in remaining:
                        remaining.discard(other)
                        stack.append(other)
                        members.add(other)
        found.append(members)
    return found


def dilate(blocks: set[int], radius: int) -> set[int]:
    grown = set()
    for block in blocks:
        x, y = block % GRID_W, block // GRID_W
        for dx in range(-radius, radius + 1):
            for dy in range(-radius, radius + 1):
                nx, ny = x + dx, y + dy
                if 0 <= nx < GRID_W and 0 <= ny < GRID_H:
                    grown.add(ny * GRID_W + nx)
    return grown


def tracks(pts: list[float], active: list[list[int]], shifts=None, *, gap: float = 0.4,
           full_fraction: float = 0.35, link_radius: int = 2) -> list[dict]:
    """Local change tracks: per-frame spatial clusters linked over time when they touch the track's
    latest footprint (dilated by link_radius blocks) within `gap` seconds.  A full-screen or pan
    frame closes every open track (the picture underneath changed).  Each track keeps its PTS range,
    union box, peak size, first/last centre (logical pixels) and active-frame duty cycle."""
    shifts = shifts or [None] * len(pts)
    open_tracks: list[dict] = []
    done: list[dict] = []

    def finish(track: dict) -> None:
        union = track.pop('union')
        track.pop('footprint')
        track['box'] = box(union)
        track['area_blocks'] = len(union)
        span = max(track['end'] - track['start'], 1e-6)
        track['duration'] = round(track['end'] - track['start'], 3)
        track['duty'] = round(min(1.0, track.pop('active_time') / span), 3)
        done.append(track)

    def centre(blocks: set[int]) -> list[int]:
        xs = [b % GRID_W for b in blocks]
        ys = [b // GRID_W for b in blocks]
        return [round((sum(xs) / len(xs) + 0.5) * LOGICAL_PER_BLOCK), round((sum(ys) / len(ys) + 0.5) * LOGICAL_PER_BLOCK)]

    previous_time = pts[0] if pts else 0.0
    for time, frame, shift in zip(pts, active, shifts):
        dt = time - previous_time
        previous_time = time
        kind = frame_kind(len(frame), full_fraction, shift)
        still_open = []
        for track in open_tracks:
            if time - track['end'] <= gap and kind in ('idle', 'local'):
                still_open.append(track)
            else:
                finish(track)
        open_tracks = still_open
        if kind != 'local':
            continue
        for members in frame_clusters(frame):
            touching = [t for t in open_tracks if t['footprint'] & members]
            if touching:
                track = touching[0]
                for other in touching[1:]:
                    track['start'] = min(track['start'], other['start'])
                    track['union'] |= other['union']
                    track['peak_blocks'] = max(track['peak_blocks'], other['peak_blocks'])
                    track['frames'] += other['frames']
                    track['active_time'] += other['active_time']
                    if other['start'] < track['start_first']:
                        track['first_centre'], track['start_first'] = other['first_centre'], other['start']
                    open_tracks.remove(other)
                if track.get('_frame_time') != time:
                    track['frames'] += 1
                    track['active_time'] += dt
                    track['_frame_time'] = time
                    track['_now'] = set()
                track['_now'] |= members
                track['footprint'] = dilate(track['_now'], link_radius)
                track['union'] |= members
                track['peak_blocks'] = max(track['peak_blocks'], len(track['_now']))
                track['end'] = round(time, 3)
                track['last_centre'] = centre(track['_now'])
            else:
                open_tracks.append({'start': round(time - dt, 3), 'start_first': time - dt, 'end': round(time, 3),
                                    'frames': 1, 'active_time': dt, 'union': set(members), 'peak_blocks': len(members),
                                    'footprint': dilate(members, link_radius), 'first_centre': centre(members),
                                    'last_centre': centre(members), '_frame_time': time, '_now': set(members)})
    for track in open_tracks:
        finish(track)
    for track in done:
        for key in ('_frame_time', '_now', 'start_first'):
            track.pop(key, None)
    done.sort(key=lambda t: (t['start'], t['box']))
    for number, track in enumerate(done):
        track['id'] = f't{number:05d}'
    return done


def camera_runs(pts: list[float], shifts: list) -> dict:
    """Runs of camera-motion frames (translation with a small residual); a single non-motion frame
    inside a run is bridged.  Steps are reported in logical 640x480 pixels (scan pixel x2)."""
    moving = [bool(s) and bool(s[0] or s[1]) and s[2] < PAN_RESIDUAL for s in shifts]
    runs, i = [], 0
    while i < len(moving):
        if not moving[i]:
            i += 1
            continue
        j = i
        while j + 1 < len(moving) and (moving[j + 1] or (j + 2 < len(moving) and moving[j + 2])):
            j += 1
        steps = [2 * (shifts[k][0] ** 2 + shifts[k][1] ** 2) ** 0.5 for k in range(i, j + 1) if moving[k]]
        runs.append({'start': round(pts[i - 1] if i else pts[i], 3), 'end': round(pts[j], 3), 'frames': len(steps),
                     'peak_step': round(max(steps)), 'total_step': round(sum(steps))})
        i = j + 1
    ordered = sorted(r['peak_step'] for r in runs)
    summary = {'runs': len(runs), 'single_frame': sum(1 for r in runs if r['frames'] == 1),
               'multi_frame': sum(1 for r in runs if r['frames'] >= 3),
               'median_peak_step': ordered[len(ordered) // 2] if ordered else 0}
    return {'schema': 'hsl_video_events.camera.v1', 'summary': summary, 'runs': runs}


# --------------------------------------------------------------------------------------- region

LOGICAL_W, LOGICAL_H = 640, 480


def luma_of(rgb: bytes) -> list[int]:
    """BT.601 integer luma of packed RGB24 bytes."""
    return [(299 * rgb[i] + 587 * rgb[i + 1] + 114 * rgb[i + 2]) // 1000 for i in range(0, len(rgb), 3)]


def region_frame(luma: list[int], rgb: bytes | None, ref: list[int], previous: list[int] | None, width: int,
                 origin: tuple[int, int], threshold: int, band: int, brighter: bool = False,
                 bright: int | None = None) -> dict:
    """One frame of a region track, measured against a reference frame of the same box.

    `mask` pixels differ from the reference by more than `threshold` luma.  Reported: their count,
    union box and centroid in logical 640x480 pixels, the mean signed luma change over the mask
    (positive = brighter than the reference), the mean RGB over the mask, the per-`band`-row mask
    counts (text rows appearing one after another show as bands filling in order), the fraction of
    the box that changed by more than `threshold` since the previous frame and the mean absolute
    luma step since the previous frame (a dissolve moves every pixel a little each frame).  `brighter` keeps
    only pixels brighter than the reference (an additive glow over a background).  With `bright`,
    `bright_rows` counts per band the pixels at or above that luma (white text on a dim board: the
    rows of a text line light up when the line is drawn, whatever the board does)."""
    xs = ys = count = excess = 0
    x0 = y0 = 1 << 30
    x1 = y1 = -1
    red = green = blue = 0
    rows = [0] * ((len(luma) // width + band - 1) // band)
    for index, value in enumerate(luma):
        change = value - ref[index]
        if change > threshold or (-change > threshold and not brighter):
            x, y = index % width, index // width
            count += 1
            xs += x
            ys += y
            excess += change
            x0, y0, x1, y1 = min(x0, x), min(y0, y), max(x1, x), max(y1, y)
            rows[y // band] += 1
            if rgb is not None:
                red += rgb[3 * index]
                green += rgb[3 * index + 1]
                blue += rgb[3 * index + 2]
    changed_prev = step_prev = 0.0
    if previous is not None:
        steps = [abs(a - b) for a, b in zip(luma, previous)]
        changed_prev = sum(1 for step in steps if step > threshold) / len(luma)
        step_prev = sum(steps) / len(luma)
    frame = {'mean_luma': round(sum(luma) / len(luma), 2), 'mask_pixels': count,
             'changed_prev': round(changed_prev, 4), 'step_prev': round(step_prev, 2), 'band_rows': rows}
    if bright is not None:
        lit = [0] * len(rows)
        for index, value in enumerate(luma):
            if value >= bright:
                lit[index // width // band] += 1
        frame['bright_rows'] = lit
    if count:
        ox, oy = origin
        frame.update({'box': [ox + x0, oy + y0, x1 - x0 + 1, y1 - y0 + 1],
                      'centroid': [round(ox + xs / count, 1), round(oy + ys / count, 1)],
                      'mean_excess': round(excess / count, 1)})
        if rgb is not None:
            frame['mask_rgb'] = [round(red / count), round(green / count), round(blue / count)]
    return frame


def transition_runs(pts: list[float], changed: list[float], fraction: float) -> list[dict]:
    """Runs of consecutive frames whose per-frame change (`step_prev`, the mean absolute luma step)
    is at least `fraction`: a one-frame hard cut is a run of 1, a dissolve or slide several frames."""
    runs, current = [], None
    for index, value in enumerate(changed):
        if value >= fraction:
            if current is None:
                current = {'start': round(pts[index - 1] if index else pts[index], 3), 'frames': 0, 'peak': 0.0}
            current['frames'] += 1
            current['end'] = round(pts[index], 3)
            current['peak'] = max(current['peak'], value)
        elif current is not None:
            runs.append(current)
            current = None
    if current is not None:
        runs.append(current)
    return runs


def periodicity(pts: list[float], values: list[float], min_period: float = 0.05, max_period: float = 2.0) -> dict:
    """Dominant period of a brightness series by autocorrelation on a 60 Hz resample (a highlight that
    pulses shows a clear peak; a steady region does not).  `strength` is the normalised
    autocorrelation at the period (1 = perfectly periodic), `amplitude` half the peak-to-peak range."""
    if len(pts) < 4 or pts[-1] - pts[0] < 2 * min_period:
        return {'period_seconds': None, 'strength': 0.0, 'amplitude': 0.0}
    step = 1 / 60
    samples, cursor, t = [], 0, pts[0]
    while t <= pts[-1]:
        while cursor + 1 < len(pts) and pts[cursor + 1] <= t:
            cursor += 1
        samples.append(values[cursor])
        t += step
    mean = sum(samples) / len(samples)
    centred = [v - mean for v in samples]
    energy = sum(v * v for v in centred)
    amplitude = round((max(samples) - min(samples)) / 2, 2)
    if energy <= 1e-9:
        return {'period_seconds': None, 'strength': 0.0, 'amplitude': amplitude}
    best_lag, best = None, 0.0
    lags = range(max(1, round(min_period / step)), min(len(samples) // 2, round(max_period / step)) + 1)
    scores = {lag: sum(centred[i] * centred[i + lag] for i in range(len(centred) - lag)) / energy for lag in lags}
    for lag in lags:   # the first interior local maximum above 0.3 is the fundamental, not a multiple
        score = scores[lag]
        if lag - 1 in scores and lag + 1 in scores and score > 0.3 and score > scores[lag - 1] and score >= scores[lag + 1]:
            best_lag, best = lag, score
            break
    return {'period_seconds': round(best_lag * step, 3) if best_lag else None, 'strength': round(best, 3),
            'amplitude': amplitude}


def decode_region(video: str, crop: str | None, start: float, end: float, box: list[int]):
    """Frames of logical box x,y,w,h between start and end at the source frame rate: (pts, rgb bytes)."""
    x, y, w, h = box
    filters = ([f'crop={crop}'] if crop else []) + [f'scale={LOGICAL_W}:{LOGICAL_H}:flags=area',
                                                   f'crop={w}:{h}:{x}:{y}', 'format=rgb24', 'showinfo']
    # -ss counts from the file's first timestamp; -copyts keeps the source PTS (a clip cut from the
    # recording with -copyts starts at its source second).
    probe = subprocess.run(['ffprobe', '-v', 'error', '-show_entries', 'format=start_time', '-of', 'csv=p=0', video],
                           capture_output=True, text=True)
    first = float(probe.stdout.strip() or 0.0)
    command = ['ffmpeg', '-nostdin', '-hide_banner', '-v', 'info', '-ss', f'{max(0.0, start - 1.0 - first):.3f}', '-copyts',
               '-i', video, '-an', '-vf', ','.join(filters), '-fps_mode', 'passthrough', '-f', 'rawvideo', '-']
    process = subprocess.run(command, capture_output=True)
    if process.returncode != 0:
        raise SystemExit(f'ffmpeg failed with {process.returncode}')
    pts = [float(m.group(1)) for line in process.stderr.decode('utf-8', 'replace').splitlines()
           if 'showinfo' in line and ' n:' in line for m in [PTS_RE.search(line)] if m]
    size = w * h * 3
    frames = [process.stdout[i * size:(i + 1) * size] for i in range(len(process.stdout) // size)]
    if len(pts) != len(frames):
        raise SystemExit(f'PTS count {len(pts)} != frame count {len(frames)}; refusing to guess times')
    return [(t, f) for t, f in zip(pts, frames) if start <= t <= end]


def region(frames: list[tuple[float, bytes]], box: list[int], ref_at: float | None, threshold: int, band: int,
           fraction: float, brighter: bool = False, bright: int | None = None) -> dict:
    """Track one logical box over time: per-frame mask against the reference frame (the frame
    nearest `ref_at`, default the last frame), transition runs and the mean-luma periodicity."""
    if not frames:
        raise SystemExit('no frames in the requested window')
    width = box[2]
    lumas = [luma_of(rgb) for _, rgb in frames]
    ref_index = len(frames) - 1 if ref_at is None else min(range(len(frames)), key=lambda i: abs(frames[i][0] - ref_at))
    out, previous = [], None
    for (t, rgb), luma in zip(frames, lumas):
        frame = region_frame(luma, rgb, lumas[ref_index], previous, width, (box[0], box[1]), threshold, band, brighter, bright)
        frame['pts'] = round(t, 4)
        out.append(frame)
        previous = luma
    pts = [f['pts'] for f in out]
    return {'schema': 'hsl_video_events.region.v1', 'box': box, 'ref_pts': out[ref_index]['pts'],
            'threshold': threshold, 'band': band, 'brighter': brighter,
            'transitions': transition_runs(pts, [f['step_prev'] for f in out], fraction),
            'periodicity': periodicity(pts, [f['mean_luma'] for f in out]), 'frames': out}


# --------------------------------------------------------------------------------------- sprite

def load_sprite(path: Path):
    """(rgb array h×w×3 float, opaque mask h×w bool) of an RGBA PNG; needs numpy and Pillow."""
    import numpy as np
    from PIL import Image

    with Image.open(path) as image:
        rgba = np.asarray(image.convert('RGBA'), dtype=np.float32)
    return rgba[:, :, :3], rgba[:, :, 3] > 0


def sprite_match(np, frame, sprite, mask, step: int = 2) -> tuple[int, int, float]:
    """Best placement of `sprite` in `frame` (h×w×3 arrays): (x, y, score) where (x, y) is the
    sprite's top-left corner and score the mean absolute RGB difference over every `step`-th opaque
    sprite pixel (0 = identical).  A sprite larger than the frame scores infinity."""
    height, width = frame.shape[:2]
    sh, sw = mask.shape
    ny, nx = height - sh + 1, width - sw + 1
    if ny < 1 or nx < 1:
        return 0, 0, float('inf')
    points = np.argwhere(mask)[::step]
    total = np.zeros((ny, nx), dtype=np.float32)
    for i, j in points:
        total += np.abs(frame[i:i + ny, j:j + nx, :] - sprite[i, j]).sum(axis=2)
    index = int(np.argmin(total))
    y, x = divmod(index, nx)
    return x, y, float(total[y, x]) / (3 * len(points))


def sprite_runs(pts: list[float], hits: list[dict], max_score: float, gap: int = 2) -> list[dict]:
    """Runs of frames whose best match scores at most `max_score` (the sprite is visible), bridging up
    to `gap` missed frames: start／end PTS, duration, frame count, first／last centre and the drift
    (last minus first centre, logical pixels; negative y = rose)."""
    runs, current, missed = [], None, 0
    for t, hit in zip(pts, hits):
        if hit['score'] <= max_score:
            if current is None:
                current = {'start': round(t, 4), 'frames': 0, 'first_centre': hit['centre'], 'best_score': hit['score']}
            current['frames'] += 1
            current['end'] = round(t, 4)
            current['last_centre'] = hit['centre']
            current['best_score'] = min(current['best_score'], hit['score'])
            missed = 0
        elif current is not None:
            missed += 1
            if missed > gap:
                runs.append(current)
                current, missed = None, 0
    if current is not None:
        runs.append(current)
    for run in runs:
        run['duration'] = round(run['end'] - run['start'], 4)
        run['drift'] = [run['last_centre'][0] - run['first_centre'][0], run['last_centre'][1] - run['first_centre'][1]]
    return runs


def sprite(frames: list[tuple[float, bytes]], box: list[int], paths: list[Path], max_score: float, step: int = 6) -> dict:
    import numpy as np

    x0, y0, w, h = box
    arrays = [np.frombuffer(rgb, dtype=np.uint8).reshape(h, w, 3).astype(np.float32) for _, rgb in frames]
    pts = [t for t, _ in frames]
    result = {'schema': 'hsl_video_events.sprite.v1', 'box': box, 'max_score': max_score, 'step': step, 'sprites': []}
    for path in paths:
        rgb, mask = load_sprite(path)
        hits = []
        for frame in arrays:
            x, y, score = sprite_match(np, frame, rgb, mask, step)
            hits.append({'box': [x0 + x, y0 + y, mask.shape[1], mask.shape[0]], 'score': round(score, 1),
                         'centre': [x0 + x + mask.shape[1] // 2, y0 + y + mask.shape[0] // 2]})
        result['sprites'].append({'sprite': str(path), 'runs': sprite_runs(pts, hits, max_score),
                                  'frames': [dict(hit, pts=round(t, 4)) for t, hit in zip(pts, hits)]})
    return result


# ---------------------------------------------------------------------------------------- audio

AUDIO_RATE = 11025
ENVELOPE_SECONDS = 0.01


def envelope_db(samples: list[float], rate: int, window: float = ENVELOPE_SECONDS) -> list[float]:
    """RMS level per `window` seconds in dBFS (samples in -1..1)."""
    import math

    size = max(1, round(rate * window))
    levels = []
    for start in range(0, len(samples) - size + 1, size):
        chunk = samples[start:start + size]
        rms = math.sqrt(sum(v * v for v in chunk) / size)
        levels.append(round(20 * math.log10(max(rms, 1e-6)), 1))
    return levels


def onsets(levels: list[float], window: float, rise_db: float = 12.0, lookback: int = 5) -> list[dict]:
    """Sound starts in an envelope: a window at least `rise_db` above the quietest of the previous
    `lookback` windows, merged while the level keeps rising.  Times are seconds from the envelope start."""
    found, last = [], -10
    for index in range(lookback, len(levels)):
        floor = min(levels[index - lookback:index])
        if levels[index] - floor >= rise_db and index - last > lookback:
            peak = max(levels[index:index + 20])
            found.append({'t': round(index * window, 3), 'floor_db': floor, 'peak_db': peak})
            last = index
    return found


def best_match(signal, template) -> tuple[int, float]:
    """Offset (samples) and normalised cross-correlation of the best alignment of `template` in
    `signal` (numpy arrays).  1.0 = the same waveform (any gain); unrelated sounds stay well below."""
    import numpy as np

    n = len(signal) + len(template)
    size = 1 << (n - 1).bit_length()
    corr = np.fft.irfft(np.fft.rfft(signal, size) * np.conj(np.fft.rfft(template, size)), size)[:len(signal)]
    energy = np.sqrt(np.convolve(signal * signal, np.ones(len(template)), 'full')[len(template) - 1:len(template) - 1 + len(signal)])
    score = corr / (np.sqrt((template * template).sum()) * np.maximum(energy, 1e-9))
    best = int(np.argmax(score[:max(1, len(signal) - len(template) + 1)]))
    return best, float(score[best])


def audio(video: str, start: float, end: float, matches: list[str]) -> dict:
    """Sound onsets of VIDEO's audio in [start, end] and, per candidate WAV, where it matches best."""
    import numpy as np

    def pcm(path: str, seek: float | None = None, length: float | None = None):
        command = ['ffmpeg', '-nostdin', '-v', 'error'] + (['-ss', f'{seek:.3f}'] if seek is not None else []) \
            + ['-i', path] + (['-t', f'{length:.3f}'] if length is not None else []) \
            + ['-vn', '-ac', '1', '-ar', str(AUDIO_RATE), '-f', 's16le', '-']
        data = subprocess.run(command, capture_output=True, check=True).stdout
        return np.frombuffer(data, np.int16).astype(np.float64) / 32768.0

    signal = pcm(video, start, end - start)
    levels = envelope_db(signal.tolist(), AUDIO_RATE)
    result = {'schema': 'hsl_video_events.audio.v1', 'video': video, 'start': start, 'end': end,
              'envelope_window': ENVELOPE_SECONDS,
              'onsets': [dict(o, t=round(start + o['t'], 3)) for o in onsets(levels, ENVELOPE_SECONDS)],
              'matches': []}
    for path in matches:
        template = pcm(path)
        offset, score = best_match(signal, template)
        result['matches'].append({'wav': path, 'at': round(start + offset / AUDIO_RATE, 3), 'ncc': round(score, 3),
                                  'seconds': round(len(template) / AUDIO_RATE, 3)})
    result['matches'].sort(key=lambda m: -m['ncc'])
    return result


def markdown(result: dict, title: str) -> str:
    lines = [f'# {title}', '', '```json', json.dumps(result['summary'], ensure_ascii=False), '```', '',
             '| id | kind | start | end | dur | frames | box x,y,w,h | area | peak | clusters |', '|' + '---|' * 10]
    for event in result['events']:
        cl = '; '.join(f"{c['box']}×{c['blocks']}" for c in event['clusters'][:3]) or str(event.get('pan_logical', ''))
        lines.append(f"| {event['id']} | {event['kind']} | {event['start']:.3f} | {event['end']:.3f} | "
                     f"{event['duration']:.2f} | {event['frames']} | {event['box']} | {event['area_blocks']} | "
                     f"{event['peak_blocks']} | {cl} |")
    return '\n'.join(lines) + '\n'


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest='action', required=True)
    s = sub.add_parser('scan')
    s.add_argument('video')
    s.add_argument('--crop', help='ffmpeg crop W:H:X:Y of the game area (omit for a bare 640x480 movie)')
    s.add_argument('--out', type=Path, required=True)
    s.add_argument('--threshold', type=int, default=10)
    s.add_argument('--threads', type=int, default=2)
    e = sub.add_parser('events')
    e.add_argument('scan', type=Path)
    e.add_argument('--out', type=Path, required=True, help='events JSON; a .md table is written beside it')
    e.add_argument('--gap', type=float, default=0.25)
    e.add_argument('--full-fraction', type=float, default=0.35)
    e.add_argument('--ambient-rate', type=float, default=0.5)
    e.add_argument('--track-gap', type=float, default=0.4)
    e.add_argument('--title', default='video change events')
    c = sub.add_parser('camera')
    c.add_argument('scan', type=Path)
    c.add_argument('--out', type=Path, required=True, help='camera-run JSON')
    r = sub.add_parser('region')
    r.add_argument('video')
    r.add_argument('--crop', help='ffmpeg crop W:H:X:Y of the game area (omit for a bare 640x480 movie)')
    r.add_argument('--start', type=float, required=True)
    r.add_argument('--end', type=float, required=True)
    r.add_argument('--box', required=True, help='logical 640x480 box x,y,w,h')
    r.add_argument('--ref', type=float, help='PTS of the reference frame (default: the last frame)')
    r.add_argument('--threshold', type=int, default=24)
    r.add_argument('--band', type=int, default=8, help='row band height for band_rows')
    r.add_argument('--min-step', dest='fraction', type=float, default=1.5,
                   help='mean absolute luma step from the previous frame that counts as a transition frame')
    r.add_argument('--brighter', action='store_true', help='mask only pixels brighter than the reference')
    r.add_argument('--bright', type=int, help='also count, per row band, pixels at or above this luma (bright_rows)')
    r.add_argument('--out', type=Path, required=True)
    a = sub.add_parser('audio')
    a.add_argument('video')
    a.add_argument('--start', type=float, required=True)
    a.add_argument('--end', type=float, required=True)
    a.add_argument('--match', action='append', default=[], help='candidate WAV (repeatable)')
    a.add_argument('--out', type=Path, required=True)
    p = sub.add_parser('sprite')
    p.add_argument('video')
    p.add_argument('--crop', help='ffmpeg crop W:H:X:Y of the game area (omit for a bare 640x480 movie)')
    p.add_argument('--start', type=float, required=True)
    p.add_argument('--end', type=float, required=True)
    p.add_argument('--box', required=True, help='logical 640x480 search box x,y,w,h')
    p.add_argument('--sprite', action='append', type=Path, required=True, help='RGBA PNG (repeatable)')
    p.add_argument('--max-score', type=float, default=40.0, help='mean absolute RGB difference that still counts as visible')
    p.add_argument('--step', type=int, default=6, help='compare every STEP-th opaque sprite pixel (speed／accuracy)')
    p.add_argument('--out', type=Path, required=True)
    args = parser.parse_args(argv)
    if args.action in ('region', 'audio', 'sprite'):
        if args.action == 'sprite':
            box = [int(v) for v in args.box.split(',')]
            result = sprite(decode_region(args.video, args.crop, args.start, args.end, box), box, args.sprite, args.max_score, args.step)
            result.update(video=args.video, crop=args.crop)
            brief = {'sprites': [{'sprite': s['sprite'], 'runs': s['runs']} for s in result['sprites']]}
        elif args.action == 'region':
            box = [int(v) for v in args.box.split(',')]
            result = region(decode_region(args.video, args.crop, args.start, args.end, box), box, args.ref,
                            args.threshold, args.band, args.fraction, args.brighter, args.bright)
            result.update(video=args.video, crop=args.crop)
            brief = {'frames': len(result['frames']), 'transitions': result['transitions'][:8],
                     'periodicity': result['periodicity']}
        else:
            result = audio(args.video, args.start, args.end, args.match)
            brief = {'onsets': result['onsets'][:8], 'matches': result['matches'][:4]}
        args.out.parent.mkdir(parents=True, exist_ok=True)
        args.out.write_text(json.dumps(result, ensure_ascii=False) + '\n', encoding='utf-8')
        print(json.dumps(brief, ensure_ascii=False))
        return 0
    if args.action == 'scan':
        print(json.dumps(scan(args.video, args.crop, args.out, args.threshold, args.threads), ensure_ascii=False))
        return 0
    pts, active, luma, shifts, meta = load_scan(args.scan)
    if args.action == 'camera':
        result = camera_runs(pts, shifts)
        result['scan'] = meta
        args.out.parent.mkdir(parents=True, exist_ok=True)
        args.out.write_text(json.dumps(result, ensure_ascii=False, indent=1) + '\n', encoding='utf-8')
        print(json.dumps(result['summary'], ensure_ascii=False))
        return 0
    result = segment(pts, active, luma, shifts, gap=args.gap, full_fraction=args.full_fraction, ambient_rate=args.ambient_rate)
    result['scan'] = meta
    result['tracks'] = tracks(pts, active, shifts, gap=args.track_gap)
    result['summary']['tracks'] = len(result['tracks'])
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(json.dumps(result, ensure_ascii=False, indent=1) + '\n', encoding='utf-8')
    args.out.with_suffix('.md').write_text(markdown(result, args.title), encoding='utf-8')
    print(json.dumps(result['summary'], ensure_ascii=False))
    return 0


if __name__ == '__main__':
    sys.exit(main())
