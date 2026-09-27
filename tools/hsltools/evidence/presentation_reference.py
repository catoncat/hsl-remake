"""Record one game window with audio, validate coverage, or build an event-aligned comparison.

No gameplay automation, microphone, whole-desktop capture, or automatic parity verdict.
Raw movies/receipts/report stay in ignored/. Curated case definitions live in docs/.

Registry task presentation_reference (family evidence): the curated case catalog
docs/evidence_packets/runtime_observations/presentation_reference/cases.json, validated as the
`check` action does (media files, then the JSON coverage report whose last line is the
result). The module command line keeps the actions the registry has no verb for:

  PYTHONPATH=tools python3 -m hsltools.evidence.presentation_reference record --window ID --seconds N --kind original|remake --label L --precondition P [--dry-run]
  PYTHONPATH=tools python3 -m hsltools.evidence.presentation_reference report [--output ignored/presentation-reference/compare.html]
"""
from __future__ import annotations

import argparse
import hashlib
import html
import json
import math
import os
from pathlib import Path
import re
import subprocess
import time

from hsltools.registry import Context, ScriptCheckTask

ROOT = Path(__file__).resolve().parents[3]
CATALOG = ROOT / 'docs/evidence_packets/runtime_observations/presentation_reference/cases.json'


def digest(path: Path) -> str:
    result = hashlib.sha256()
    with path.open('rb') as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b''):
            result.update(chunk)
    return result.hexdigest()


def media_info(path: Path) -> dict:
    result = subprocess.run(['ffprobe', '-v', 'error', '-show_entries',
                             'stream=codec_type,width,height,r_frame_rate:format=duration',
                             '-of', 'json', str(path)], check=True, capture_output=True, text=True, timeout=20)
    data = json.loads(result.stdout)
    streams = data.get('streams', [])
    if not any(s['codec_type'] == 'video' for s in streams):
        raise ValueError('Recording has no video stream')
    if not any(s['codec_type'] == 'audio' for s in streams):
        raise ValueError('Recording has no audio track; it cannot certify sound or sound timing')
    duration = float(data['format']['duration'])
    if not math.isfinite(duration) or duration <= 0:
        raise ValueError('Invalid recording duration')
    level = subprocess.run(['ffmpeg', '-hide_banner', '-i', str(path), '-vn',
                            '-af', 'volumedetect', '-f', 'null', '-'], capture_output=True, text=True, timeout=30)
    if level.returncode:
        raise ValueError('Audio decode failed: ' + level.stderr[-400:])
    peak = re.search(r'max_volume: ([-\d.]+) dB', level.stderr)
    data['audio_peak_db'] = float(peak[1]) if peak else None
    data['audio_has_signal'] = peak is not None and float(peak[1]) > -80
    return data


def validate_recording_duration(info: dict, seconds: float) -> None:
    actual = float(info['format']['duration'])
    if not math.isfinite(actual) or actual < seconds - max(0.25, seconds * 0.03):
        raise ValueError(f'Recording truncated: requested {seconds:.2f}s, received {actual:.2f}s; inspect screen lock or window closure before retrying')


def validate(catalog: dict, require_complete: bool = False) -> list[str]:
    """Check recorded coverage, not screenshot similarity or human approval."""
    if catalog.get('schema') != 'hsl_presentation_reference.v1':
        raise ValueError('Unsupported catalog schema')
    missing, ids = [], set()
    for case in catalog['cases']:
        key = case['id']
        if key in ids or not re.fullmatch(r'[a-z0-9_-]+', key):
            raise ValueError('Invalid/duplicate case id: ' + key)
        ids.add(key)
        required = case['required_events']
        if not required or len(required) != len(set(required)):
            raise ValueError('Required events must be nonempty and unique: ' + key)
        for side in ('original', 'remake'):
            sample = case.get(side)
            if not sample:
                missing.append(f'{key}/{side}: not captured')
                continue
            if not re.fullmatch(r'[0-9a-f]{64}', sample.get('sha256', '')):
                raise ValueError('Missing media identity: ' + key)
            duration = float(sample['duration'])
            if not math.isfinite(duration) or duration <= 0 or not sample.get('precondition'):
                raise ValueError('Missing precondition/valid duration: ' + key)
            times = sample['events']
            last = -1.0
            for event in required:
                if event not in times:
                    missing.append(f'{key}/{side}: {event}')
                    continue
                when = float(times[event])
                if not math.isfinite(when) or not 0 <= when < duration or when < last:
                    raise ValueError('Invalid/unordered event time: ' + key + '/' + event)
                last = when
            if case.get('sound_required') and not sample.get('audio_has_signal'):
                missing.append(f'{key}/{side}: audible signal not verified')
        if case.get('verdict') == 'matched' and (any(x.startswith(key + '/') for x in missing) or not case.get('review_notes')):
            raise ValueError('Cannot mark an uncovered/unreviewed case matched: ' + key)
    if require_complete and missing:
        raise ValueError('Coverage incomplete:\n' + '\n'.join(missing))
    return missing


def validate_media_files(catalog: dict, root: Path = ROOT) -> None:
    checked = {}
    for case in catalog['cases']:
        for side in ('original', 'remake'):
            sample = case.get(side)
            if not sample:
                continue
            path = (root / sample['path']).resolve()
            if not path.is_file():
                raise ValueError('Missing reference media: ' + str(path))
            if path not in checked:
                checked[path] = digest(path)
            if checked[path] != sample['sha256']:
                raise ValueError('Changed reference media: ' + str(path))


def record(args) -> None:
    if not re.fullmatch(r'[a-z0-9_-]{1,64}', args.label) or not 1 <= args.seconds <= 60:
        raise ValueError('Use a simple label and 1..60 seconds')
    folder = ROOT / 'ignored/presentation-reference' / (args.label + '-' + time.strftime('%Y%m%d-%H%M%S'))
    executable = ROOT / 'ignored/bin/hsl_record_window'
    command = [str(executable), str(args.window), str(args.seconds), str(folder / 'recording.mp4')]
    if args.dry_run:
        print(json.dumps({'command': command, 'kind': args.kind, 'precondition': args.precondition}))
        return
    folder.mkdir(parents=True, exist_ok=False)
    receipt = {'schema': 'hsl_window_recording.v1', 'kind': args.kind,
               'window': args.window, 'precondition': args.precondition, 'events': {},
               'recorded_at': time.time(), 'behavior_reviewed': False, 'capture_complete': False, 'command': command}
    dest = folder / 'receipt.json'
    try:
        source = ROOT / 'tools/hsl_record_window.swift'
        if not executable.exists() or executable.stat().st_mtime < source.stat().st_mtime:
            executable.parent.mkdir(parents=True, exist_ok=True)
            subprocess.run(['swiftc', '-parse-as-library', str(source), '-o', str(executable)], check=True, timeout=60)
        subprocess.run(command, check=True, timeout=args.seconds + 25)
        movie = folder / 'recording.mp4'
        receipt.update(path=str(movie.relative_to(ROOT)), sha256=digest(movie), media=media_info(movie))
        validate_recording_duration(receipt['media'], args.seconds)
        receipt['capture_complete'] = True
        print('REFERENCE_RECORDED ' + str(dest))
    except Exception as error:
        receipt['error'] = str(error)
        raise
    finally:
        dest.write_text(json.dumps(receipt, ensure_ascii=False, indent=2) + '\n')


def report(catalog: dict, target: Path) -> None:
    missing = validate(catalog)
    validate_media_files(catalog)
    target.parent.mkdir(parents=True, exist_ok=True)
    cards = []
    for case in catalog['cases']:
        videos = []
        for side, title in [('original', '原版'), ('remake', '重制版')]:
            sample = case.get(side)
            if sample:
                movie = (ROOT / sample['path']).resolve()
                if not movie.is_file() or digest(movie) != sample['sha256']:
                    raise ValueError('Missing/changed comparison media: ' + str(movie))
                url = html.escape(os.path.relpath(movie, target.parent), quote=True)
                videos.append(f'<div><h3>{title}</h3><video data-side="{side}" controls preload="metadata" src="{url}"></video></div>')
            else:
                videos.append(f'<div><h3>{title}</h3><p>尚未采样，不能判定通过。</p></div>')
        events = json.dumps({s: case.get(s, {}).get('events', {}) for s in ('original', 'remake')}, ensure_ascii=False)
        buttons = ''.join(f'<button data-event="{html.escape(e, quote=True)}"' +
                          ('' if all(e in case.get(s, {}).get('events', {}) for s in ('original', 'remake')) else ' disabled title="两侧事件尚未完整覆盖"') +
                          f'>{html.escape(e)}</button>' for e in case['required_events'])
        cards.append(f'<section data-events="{html.escape(events, quote=True)}"><h2>{html.escape(case["title"])}</h2><p>{html.escape(case["review_notes"])}</p><div class="pair">{"".join(videos)}</div><nav>{buttons}<button data-step="-1">前一帧</button><button data-step="1">后一帧</button><button data-play>同时播放</button><button data-pause>暂停</button></nav></section>')
    target.write_text('''<!doctype html><html lang="zh"><meta charset="utf-8"><title>原版与重制版 · 表现对照</title>
<style>body{max-width:1400px;margin:32px auto;padding:0 24px;background:#171817;color:#ece9de;font:16px system-ui}h1{font-size:28px}h2{font-size:21px}p{line-height:1.6;color:#c0c0b8}section{padding:24px 0;border-top:1px solid #444}.pair{display:grid;grid-template-columns:1fr 1fr;gap:24px}video{width:100%;background:#000}nav{display:flex;gap:8px;flex-wrap:wrap;margin-top:16px}button{padding:8px 12px;cursor:pointer}h3{margin:8px 0}</style>
<h1>原版与重制版 · 表现对照</h1><p>按同名事件定位，保持原速，不拉伸时间。音轨分别试听；无证据的状态明确留空。截图不是时序证明，此页不会自动判定还原完成。</p>'''
                      + f'<p>缺失证据项：{len(missing)}</p>' + ''.join(cards) + '''
<script>document.querySelectorAll('section').forEach(s=>{const v=[...s.querySelectorAll('video')], e=JSON.parse(s.dataset.events);s.addEventListener('click',a=>{const b=a.target;if(b.dataset.event){v.forEach((x,i)=>{x.pause();const t=e[x.dataset.side][b.dataset.event];if(t!==undefined)x.currentTime=t;});}if(b.dataset.step)v.forEach(x=>{x.pause();x.currentTime=Math.max(0,x.currentTime+Number(b.dataset.step)/60);});if(b.hasAttribute('data-play'))v.forEach(x=>x.play());if(b.hasAttribute('data-pause'))v.forEach(x=>x.pause());});});</script></html>''', encoding='utf-8')
    print('REFERENCE_REPORT ' + str(target))


class PresentationReferenceTask(ScriptCheckTask):
    name = 'presentation_reference'
    family = 'evidence'
    inputs = ('docs/evidence_packets/runtime_observations/presentation_reference/media/',)
    outputs = (CATALOG.relative_to(ROOT).as_posix(),)
    replaces = ('tools/hsl_presentation_reference.py check',)
    scripts = ('tools/hsltools/evidence/presentation_reference.py',)

    def verify(self, ctx: Context) -> None:
        data = json.loads(CATALOG.read_text())
        validate_media_files(data)
        print(json.dumps({'catalog_valid': True, 'missing': validate(data, False)}, ensure_ascii=False, indent=2))


def tasks() -> list[PresentationReferenceTask]:
    return [PresentationReferenceTask()]


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest='action', required=True)
    rec = sub.add_parser('record')
    rec.add_argument('--window', required=True, type=int)
    rec.add_argument('--seconds', type=float, default=15)
    rec.add_argument('--kind', choices=['original', 'remake'], required=True)
    rec.add_argument('--label', required=True)
    rec.add_argument('--precondition', required=True)
    rec.add_argument('--dry-run', action='store_true')
    for name in ['check', 'report']:
        cmd = sub.add_parser(name)
        cmd.add_argument('--catalog', type=Path, default=CATALOG)
        if name == 'check': cmd.add_argument('--require-complete', action='store_true')
        else: cmd.add_argument('--output', type=Path, default=ROOT / 'ignored/presentation-reference/compare.html')
    args = parser.parse_args()
    if args.action == 'record':
        record(args)
    else:
        data = json.loads(args.catalog.read_text())
        if args.action == 'check':
            validate_media_files(data)
            print(json.dumps({'catalog_valid': True, 'missing': validate(data, args.require_complete)}, ensure_ascii=False, indent=2))
        else: report(data, args.output)


if __name__ == '__main__':
    main()
