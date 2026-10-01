#!/usr/bin/env python3
"""Browser (Web) build driver: stage the project, shrink what the browser build does not need, export, serve.

The output is a derived artifact: it carries original-derived textures, sound and data, so it must never be
hosted publicly (`serve` binds 127.0.0.1; web_deploy.py and web_gate.py publish it privately, behind a password)
and everything lands under ignored/web/. The stage step never
edits the checkout: it clones the files it needs (APFS clone on macOS, a plain copy elsewhere) and edits only
the clones. Godot web exports need the Compatibility renderer (project.godot already uses it) and, without
thread support, no special server headers.

    python3 tools/web_build.py fetch-templates      # Web templates only, by HTTP range requests (~24 MB of the 1.2 GB .tpz)
    python3 tools/web_build.py stage [--quality Q]  # clone game/ content/ .godot/, minify JSON, lossy movie sheets, pack plan, preset
    python3 tools/web_build.py export [--debug]     # export the core to ignored/web/dist/index.html and the packs to dist/packs/
    python3 tools/web_build.py build                # stage + export (--no-packs: one big .pck, no downloads)
    python3 tools/web_build.py serve [--port 8060] [--auth USER:PASSWORD]  # serve dist/ on 127.0.0.1
    python3 tools/web_build.py list PCK             # entries and bytes by directory of an exported .pck
"""
from __future__ import annotations

import argparse
import base64
import functools
import http.server
import io
import hmac
import json
import os
import re
import shutil
import struct
import subprocess
import sys
import time
import urllib.request
import zipfile
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
WORK = ROOT / 'ignored' / 'web'
STAGE = WORK / 'stage'
DIST = WORK / 'dist'
TEMPLATES = WORK / 'templates'
PLAN = WORK / 'plan.json'
PACKS_TOOL = ROOT / 'tools' / 'web_packs.py'

GODOT_RELEASE = '4.7.2-stable'
TPZ_URL = f'https://github.com/godotengine/godot/releases/download/{GODOT_RELEASE}/Godot_v{GODOT_RELEASE}_export_templates.tpz'
TEMPLATE_FILES = ('web_nothreads_release.zip', 'web_nothreads_debug.zip')

# What the browser build takes from the checkout. docs/ holds the evidence screenshots (255 MB once imported),
# tests/ and tools/ are not game files; nothing under game/ refers to them.
STAGE_PATHS = ('project.godot', 'game', 'content', '.godot')
# Dev-only data that nothing under game/ reads (grep-checked): the original-derived manifest, the function
# catalog, development outputs and the resource reference index.
DEV_ONLY = (
    'content/generated/hsl/original_derived_manifest.json',
    'content/generated/hsl/static/hsl01/function_catalog.json',
    'content/generated/hsl/development/*',
    'content/imported/hsl/chapter01/resource_refs.json',
)
# The seven movie sheets are lossy WebP sources (21.6 MB); a lossless import inflates them to 104 MB.
MOVIE_IMPORTS = 'content/imported/hsl/movie/*.webp.import'
# Touch play (game/input/TouchControls.gd): Godot's shell already has the viewport meta with user-scalable=no and
# body touch-action: none, and its canvas touch handlers call preventDefault. This adds what phones still do on
# their own: pull-to-refresh and overscroll, the long-press callout and text selection, the tap highlight, and
# Safari's pinch zoom (gesture* events, which ignore user-scalable=no). One line, single quotes only: it is a
# string value in export_presets.cfg.
HEAD_INCLUDE = (
    '<style>html, body { overscroll-behavior: none; -webkit-touch-callout: none; -webkit-user-select: none;'
    ' user-select: none; -webkit-tap-highlight-color: transparent; }</style>'
    "<script>for (const type of ['gesturestart', 'gesturechange', 'gestureend'])"
    ' document.addEventListener(type, (event) => event.preventDefault(), { passive: false });</script>'
)
PCK_MAGIC = 0x43504447


def say(message: str) -> None:
    print(message, flush=True)


def godot_bin() -> str:
    found = os.environ.get('GODOT_BIN') or shutil.which('godot')
    if not found:
        raise SystemExit('Godot executable not found; set GODOT_BIN or install Godot.')
    return found


def run_godot(args: list[str]) -> subprocess.CompletedProcess:
    started = time.time()
    done = subprocess.run([godot_bin(), '--headless', *args], capture_output=True, text=True)
    errors = [line for line in (done.stdout + done.stderr).splitlines() if 'ERROR' in line]
    say(f'  godot {" ".join(args[:3])}… exit={done.returncode} {time.time() - started:.0f}s errors={len(errors)}')
    for line in errors[:8]:
        say(f'    {line.strip()}')
    return done


def run_tool(command: list[str]) -> int:
    return subprocess.run(command).returncode


def clone(src: Path, dst: Path) -> None:
    dst.parent.mkdir(parents=True, exist_ok=True)
    if sys.platform == 'darwin':
        if subprocess.run(['/bin/cp', '-c', '-R', '-p', str(src), str(dst)], capture_output=True).returncode == 0:
            return
        if dst.exists():
            shutil.rmtree(dst) if dst.is_dir() else dst.unlink()
    if src.is_dir():
        shutil.copytree(src, dst, symlinks=True)
    else:
        shutil.copy2(src, dst)


def mb(count: int | float) -> str:
    return f'{count / 1048576:.1f} MB'


# ---------------------------------------------------------------- templates

class RangeFile(io.RawIOBase):
    """Read-only seekable view of a remote file through HTTP range requests."""

    def __init__(self, url: str, size: int) -> None:
        self.url, self.size, self.pos = url, size, 0

    def seekable(self) -> bool:
        return True

    def readable(self) -> bool:
        return True

    def tell(self) -> int:
        return self.pos

    def seek(self, offset: int, whence: int = 0) -> int:
        self.pos = offset if whence == 0 else (self.pos + offset if whence == 1 else self.size + offset)
        return self.pos

    def readinto(self, buffer) -> int:
        count = min(len(buffer), self.size - self.pos)
        if count <= 0:
            return 0
        request = urllib.request.Request(self.url, headers={'Range': f'bytes={self.pos}-{self.pos + count - 1}'})
        with urllib.request.urlopen(request) as response:
            data = response.read()
        buffer[:len(data)] = data
        self.pos += len(data)
        return len(data)


def cmd_fetch_templates(args: argparse.Namespace) -> int:
    TEMPLATES.mkdir(parents=True, exist_ok=True)
    request = urllib.request.Request(TPZ_URL, headers={'Range': 'bytes=0-0'})
    with urllib.request.urlopen(request) as response:
        total = int(response.headers['Content-Range'].split('/')[1])
        final_url = response.geturl()
    say(f'templates package {mb(total)}; taking only {", ".join(TEMPLATE_FILES)}')
    with zipfile.ZipFile(io.BufferedReader(RangeFile(final_url, total), buffer_size=1 << 22)) as archive:
        members = {item.filename: item for item in archive.infolist()}
        for name in TEMPLATE_FILES:
            item = members.get('templates/' + name)
            if item is None:
                raise SystemExit(f'{name} not in the templates package')
            with archive.open(item) as source, (TEMPLATES / name).open('wb') as target:
                shutil.copyfileobj(source, target)
            say(f'  {TEMPLATES / name} {mb((TEMPLATES / name).stat().st_size)}')
    return 0


# ---------------------------------------------------------------- stage

def set_params(path: Path, updates: dict[str, str]) -> None:
    text = path.read_text(encoding='utf-8')
    for key, value in updates.items():
        text, count = re.subn(rf'^{re.escape(key)}=.*$', f'{key}={value}', text, count=1, flags=re.M)
        if count != 1:
            raise SystemExit(f'{path}: no {key} line')
    path.write_text(text, encoding='utf-8')


def minify_json(root: Path) -> tuple[int, int, int]:
    """Rewrite every .json under root without whitespace; files that do not round-trip as strict JSON stay as they are."""
    before = after = skipped = 0
    for path in root.rglob('*.json'):
        raw = path.read_bytes()
        try:
            data = json.dumps(json.loads(raw), ensure_ascii=False, separators=(',', ':'), allow_nan=False).encode('utf-8')
        except ValueError:
            skipped += 1
            continue
        before += len(raw)
        if len(data) < len(raw):
            path.write_bytes(data)
            after += len(data)
        else:
            after += len(raw)
    return before, after, skipped


def lossy_movie_sheets(quality: float) -> int:
    count = 0
    for imp in sorted(STAGE.glob(MOVIE_IMPORTS)):
        text = imp.read_text(encoding='utf-8')
        # the imported ctex and md5 go, so Godot must re-import with the new parameters
        for rel in re.findall(r'"res://(\.godot/imported/[^"]+)"', text):
            (STAGE / rel).unlink(missing_ok=True)
        set_params(imp, {'compress/mode': '1', 'compress/lossy_quality': f'{quality}'})
        count += 1
    return count


def preset_text(exclude: list[str], dist: Path = DIST) -> str:
    template = lambda name: TEMPLATES / name  # noqa: E731
    return '\n'.join([
        '[preset.0]',
        '',
        'name="Web"',
        'platform="Web"',
        'runnable=true',
        'advanced_options=false',
        'dedicated_server=false',
        'custom_features=""',
        'export_filter="all_resources"',
        'include_filter="*.json"',
        f'exclude_filter="{", ".join(exclude)}"',
        f'export_path="{dist / "index.html"}"',
        'patches=PackedStringArray()',
        'encryption_include_filters=""',
        'encryption_exclude_filters=""',
        'seed=0',
        'encrypt_pck=false',
        'encrypt_directory=false',
        'script_export_mode=2',
        '',
        '[preset.0.options]',
        '',
        f'custom_template/debug="{template("web_nothreads_debug.zip")}"',
        f'custom_template/release="{template("web_nothreads_release.zip")}"',
        'variant/extensions_support=false',
        'variant/thread_support=false',
        'vram_texture_compression/for_desktop=true',
        'vram_texture_compression/for_mobile=false',
        'html/export_icon=true',
        'html/custom_html_shell=""',
        f'html/head_include="{HEAD_INCLUDE}"',
        'html/canvas_resize_policy=2',
        'html/focus_canvas_on_start=true',
        'html/experimental_virtual_keyboard=false',
        'progressive_web_app/enabled=false',
        '',
    ])


def cmd_stage(args: argparse.Namespace) -> int:
    for name in TEMPLATE_FILES:
        if not (TEMPLATES / name).exists():
            raise SystemExit(f'missing {TEMPLATES / name}; run: python3 tools/web_build.py fetch-templates')
    started = time.time()
    if STAGE.exists():
        shutil.rmtree(STAGE)
    STAGE.mkdir(parents=True)
    for name in STAGE_PATHS:
        clone(ROOT / name, STAGE / name)
    say(f'cloned {", ".join(STAGE_PATHS)} {time.time() - started:.0f}s')

    if not args.no_minify:
        before, after, skipped = minify_json(STAGE / 'content')
        say(f'json minified {mb(before)} -> {mb(after)} ({skipped} files left as they were)')
    sheets = lossy_movie_sheets(args.quality)
    say(f'movie sheets set to lossy quality {args.quality}: {sheets}')

    if run_godot(['--path', str(STAGE), '--import']).returncode != 0:
        return 1
    PLAN.unlink(missing_ok=True)
    core_exclude: list[str] = []
    if not args.no_packs:
        # the plan reads the staged files as they are (minified JSON, lossy movie sheets), so it sizes the real packs
        if run_tool([sys.executable, str(PACKS_TOOL), 'plan', '--project', str(STAGE), '--out', str(PLAN)]) != 0:
            return 1
        core_exclude = json.loads(PLAN.read_text(encoding='utf-8'))['core_exclude']
    (STAGE / 'export_presets.cfg').write_text(preset_text([*DEV_ONLY, *core_exclude, *args.exclude]), encoding='utf-8')
    say(f'stage done {time.time() - started:.0f}s ({"core + packs" if core_exclude else "single pack"})')
    return 0


# ---------------------------------------------------------------- export / list

def read_pck(path: Path) -> list[tuple[str, int]]:
    with path.open('rb') as handle:
        magic, version, _major, _minor, _patch, _flags = struct.unpack('<6I', handle.read(24))
        if magic != PCK_MAGIC:
            raise SystemExit(f'{path}: not a Godot pack')
        struct.unpack('<Q', handle.read(8))  # file base
        directory = struct.unpack('<Q', handle.read(8))[0] if version >= 3 else None
        handle.read(64)  # reserved
        if directory is not None:
            handle.seek(directory)
        entries = []
        for _ in range(struct.unpack('<I', handle.read(4))[0]):
            length = struct.unpack('<I', handle.read(4))[0]
            name = handle.read(length).rstrip(b'\0').decode('utf-8')
            _offset, size = struct.unpack('<QQ', handle.read(16))
            handle.read(16 + 4)  # md5, flags
            entries.append((name, size))
        return entries


def summarize_pck(path: Path, depth: int = 4, top: int = 12) -> None:
    entries = read_pck(path)
    by_dir: Counter = Counter()
    count: Counter = Counter()
    for name, size in entries:
        key = '/'.join(name.replace('res://', '').split('/')[:depth])
        by_dir[key] += size
        count[key] += 1
    say(f'{path.name}: {len(entries)} entries, {mb(sum(size for _, size in entries))}')
    for key, size in by_dir.most_common(top):
        say(f'  {mb(size):>9}  n={count[key]:<6} {key}')


def out_dir(args: argparse.Namespace) -> Path:
    return Path(args.out).resolve() if getattr(args, 'out', None) else DIST


def cmd_export(args: argparse.Namespace) -> int:
    dist = out_dir(args)
    if not (STAGE / 'export_presets.cfg').exists():
        raise SystemExit('nothing staged; run: python3 tools/web_build.py stage')
    if dist.exists():
        shutil.rmtree(dist)
    dist.mkdir(parents=True)
    done = run_godot(['--path', str(STAGE), '--export-debug' if args.debug else '--export-release', 'Web', str(dist / 'index.html')])
    files = sorted(dist.glob('index*'))
    for file in files:
        say(f'  {file.name:<28} {mb(file.stat().st_size)}')
    if done.returncode != 0 or not (dist / 'index.pck').exists():
        say(done.stdout[-1500:] + done.stderr[-1500:])
        return 1
    summarize_pck(dist / 'index.pck')
    code = export_packs(dist) if PLAN.exists() else 0
    write_build_info(dist)
    return code


def write_build_info(dist: Path) -> None:
    def git(*a: str) -> str:
        return subprocess.run(['git', '-C', str(ROOT), *a], capture_output=True, text=True).stdout.strip()
    info = {'git': git('rev-parse', '--short', 'HEAD'),
            'dirty': bool(git('status', '--porcelain', '--', 'game', 'tools', 'project.godot')),
            'built': time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime()),
            'packs': PLAN.exists()}
    (dist / 'build.json').write_text(json.dumps(info) + '\n', encoding='utf-8')


def export_packs(dist: Path) -> int:
    if run_tool([sys.executable, str(PACKS_TOOL), 'build', '--project', str(STAGE), '--plan', str(PLAN), '--out', str(dist / 'packs')]) != 0:
        return 1
    plan = json.loads(PLAN.read_text(encoding='utf-8'))
    core = {name for name, _ in read_pck(dist / 'index.pck')}
    # a pack-owned file or its .import in the core pack would be shipped twice
    leaked = sorted(res for row in plan['packs'].values() for res in row['files']
                    if res.replace('res://', '') in core or res.replace('res://', '') + '.import' in core)
    manifest = json.loads((dist / 'packs' / 'manifest.json').read_text(encoding='utf-8'))
    sizes = {pack: row['bytes'] for pack, row in manifest['packs'].items()}
    first = {pack for group in ('movie:start', 'level:51') for pack in manifest['groups'].get(group, [])}
    core_bytes = (dist / 'index.pck').stat().st_size
    say(f'core carries {len(leaked)} pack-owned files')
    say(f'first play (title -> new story -> player battle 1): core {mb(core_bytes)} + {len(first)} packs '
        f'{mb(sum(sizes[p] for p in first))} = {mb(core_bytes + sum(sizes[p] for p in first))}; wasm {mb((dist / "index.wasm").stat().st_size)}')
    say(f'whole game: core {mb(core_bytes)} + {len(sizes)} packs {mb(sum(sizes.values()))}')
    return 1 if leaked else 0


def cmd_list(args: argparse.Namespace) -> int:
    summarize_pck(Path(args.pck), depth=args.depth)
    return 0


# ---------------------------------------------------------------- serve

class Handler(http.server.SimpleHTTPRequestHandler):
    extensions_map = {**http.server.SimpleHTTPRequestHandler.extensions_map,
                      '.wasm': 'application/wasm', '.pck': 'application/octet-stream', '.js': 'text/javascript'}
    auth: str | None = None  # 'user:password' for HTTP Basic, set by cmd_serve

    def authorized(self) -> bool:
        if not self.auth:
            return True
        header = self.headers.get('Authorization', '')
        if not header.startswith('Basic '):
            return False
        try:
            given = base64.b64decode(header[6:]).decode('utf-8', 'replace')
        except ValueError:
            return False
        return hmac.compare_digest(given, self.auth)

    def challenge(self) -> None:
        self.send_response(401)
        self.send_header('WWW-Authenticate', 'Basic realm="hsl"')
        self.send_header('Content-Length', '0')
        self.end_headers()

    def do_GET(self) -> None:
        super().do_GET() if self.authorized() else self.challenge()

    def do_HEAD(self) -> None:
        super().do_HEAD() if self.authorized() else self.challenge()

    def end_headers(self) -> None:
        self.send_header('Cache-Control', 'no-store')
        super().end_headers()

    def log_message(self, fmt: str, *a) -> None:
        if os.environ.get('HSL_WEB_VERBOSE'):
            super().log_message(fmt, *a)


def cmd_serve(args: argparse.Namespace) -> int:
    dist = out_dir(args)
    if not (dist / 'index.html').exists():
        raise SystemExit('nothing exported; run: python3 tools/web_build.py build')
    Handler.auth = args.auth
    server = http.server.ThreadingHTTPServer(('127.0.0.1', args.port), functools.partial(Handler, directory=str(dist)))
    say(f'http://127.0.0.1:{args.port}/' + ('  (password protected)' if args.auth else '') + '  (Ctrl-C to stop)')
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    return 0


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest='command', required=True)
    sub.add_parser('fetch-templates').set_defaults(func=cmd_fetch_templates)

    def add_stage_options(p: argparse.ArgumentParser) -> None:
        p.add_argument('--quality', type=float, default=0.9, help='lossy WebP quality for the movie sheets (default 0.9)')
        p.add_argument('--no-minify', action='store_true', help='keep JSON as it is')
        p.add_argument('--no-packs', action='store_true', help='export one big .pck instead of core + downloadable packs')
        p.add_argument('--exclude', action='append', default=[], help='extra exclude_filter pattern relative to res:// (repeatable)')

    p = sub.add_parser('stage')
    add_stage_options(p)
    p.set_defaults(func=cmd_stage)
    p = sub.add_parser('export')
    p.add_argument('--debug', action='store_true', help='use the debug template')
    p.add_argument('--out', help='output directory (default ignored/web/dist)')
    p.set_defaults(func=cmd_export)
    p = sub.add_parser('build')
    add_stage_options(p)
    p.add_argument('--debug', action='store_true')
    p.add_argument('--out', help='output directory (default ignored/web/dist)')
    p.set_defaults(func=lambda a: cmd_stage(a) or cmd_export(a))
    p = sub.add_parser('serve')
    p.add_argument('--port', type=int, default=8060)
    p.add_argument('--out', help='directory to serve (default ignored/web/dist)')
    p.add_argument('--auth', metavar='USER:PASSWORD', help='require HTTP Basic auth (use this before putting the server behind a tunnel)')
    p.set_defaults(func=cmd_serve)
    p = sub.add_parser('list')
    p.add_argument('pck')
    p.add_argument('--depth', type=int, default=4)
    p.set_defaults(func=cmd_list)
    args = parser.parse_args(argv)
    return args.func(args)


if __name__ == '__main__':
    sys.exit(main())
