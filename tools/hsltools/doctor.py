"""Read-only environment and repository preflight (`python tools/hsl.py doctor [--original]`; tools/doctor.sh
runs it). Does not launch Wine or a Godot window. Runs on macOS, Linux and Windows: the macOS-only parts
(capture route syntax needs bash, the --original Wine／helper checks) are reported as skipped elsewhere.

Every line is `OK    …`, `WARN  …`, `FAIL  …` or `INFO  …` (INFO counts as neither); exit 1 on any FAIL.
"""
from __future__ import annotations

import json
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path

from hsltools import original_content, paths

ROOT = paths.ROOT


class Report:
    def __init__(self) -> None:
        self.errors = 0
        self.warnings = 0

    def ok(self, text: str) -> None:
        print(f'OK    {text}', flush=True)

    def warn(self, text: str) -> None:
        print(f'WARN  {text}', flush=True)
        self.warnings += 1

    def fail(self, text: str) -> None:
        print(f'FAIL  {text}', flush=True)
        self.errors += 1

    def info(self, text: str) -> None:
        print(f'INFO  {text}', flush=True)

    def check(self, condition: bool, good: str, bad: str) -> None:
        if condition:
            self.ok(good)
        else:
            self.fail(bad)


def tool(env: str, name: str) -> str | None:
    """$env, else the Homebrew binary on macOS (the historical default), else `name` on PATH."""
    explicit = os.environ.get(env)
    if explicit:
        return explicit
    homebrew = Path('/opt/homebrew/bin') / name
    if sys.platform == 'darwin' and homebrew.is_file():
        return str(homebrew)
    return shutil.which(name)


def executable(path: str | None) -> bool:
    return bool(path) and Path(path).is_file() and os.access(path, os.X_OK)


def run(argv: list[str]) -> subprocess.CompletedProcess:
    return subprocess.run(argv, cwd=ROOT, capture_output=True, text=True, encoding='utf-8', errors='replace', check=False)


def version_tuple(text: str) -> tuple[int, int] | None:
    match = re.search(r'(\d+)\.(\d+)', text)
    return (int(match.group(1)), int(match.group(2))) if match else None


def check_scenario() -> None:
    # The campaign's first battle (campaign.json start_level) is a generic level battle; the
    # reviewed formation fixture keeps the same 12-unit roster for the mechanics suites.
    campaign = json.loads(Path('content/battles/campaign.json').read_text(encoding='utf-8'))
    start = str(campaign['start_level'])
    path = Path(str(campaign['battles'][start]['scenario']).removeprefix('res://'))
    assert path == Path('content/battles/battle_051.json'), path
    data = json.loads(path.read_text(encoding='utf-8'))
    assert data.get('schema') == 'hsl_level_battle.v1' and data.get('rule_adapter') == 'winfail'
    assert data.get('player_unit_id') == 'leonard'
    assert len(data.get('playable_units', [])) == 12
    fixture = json.loads(Path('content/battles/first_battle.json').read_text(encoding='utf-8'))
    assert fixture.get('rule_adapter') == 'development_battle' and len(fixture.get('playable_units', [])) == 12
    for document in (data, fixture):
        for resource in document.get('resources', {}).values():
            assert isinstance(resource, str) and resource.startswith('res://')
            assert Path(resource.removeprefix('res://')).exists(), resource


def repository(report: Report) -> None:
    top = run(['git', 'rev-parse', '--show-toplevel']).stdout.strip()
    report.check(bool(top) and Path(top).resolve() == ROOT.resolve(), f'git root: {ROOT}', 'not inside the expected git repository')
    project = Path('project.godot')
    report.check(project.is_file(), 'project.godot present', 'project.godot missing')
    text = project.read_text(encoding='utf-8') if project.is_file() else ''
    report.check('run/main_scene="res://game/title/TitleScreen.tscn"' in text,
                 'main scene is the title screen (TitleScreen.tscn -> BattleSceneRuntime.tscn)', 'project main scene is not TitleScreen')
    report.check(Path('game/title/TitleScreen.tscn').is_file() and Path('game/battle/scene/BattleSceneRuntime.tscn').is_file(),
                 'title and battle runtime scenes present', 'TitleScreen.tscn or BattleSceneRuntime.tscn missing')
    for required in ('README.md', 'AGENTS.md', 'docs/PROJECT.md', 'docs/ARCHITECTURE.md', 'docs/KNOWLEDGE_INDEX.md', 'requirements-dev.txt'):
        report.check(Path(required).is_file(), f'{required} present', f'{required} missing')
    prunable = any(line.startswith('prunable ') for line in run(['git', 'worktree', 'list', '--porcelain']).stdout.splitlines())
    report.check(not prunable, 'git worktree metadata is clean', 'stale/prunable git worktree metadata exists')


def toolchain(report: Report) -> None:
    if sys.version_info >= (3, 10):
        report.ok(f'Python: Python {sys.version.split()[0]} ({sys.executable})')
    else:
        report.fail(f'Python 3.10+ required: {sys.executable}')
    try:
        import PIL
        report.ok(f'Pillow: {PIL.__version__}')
    except ImportError:
        report.fail(f'Pillow missing; run: {sys.executable} -m pip install -r requirements-dev.txt')
    godot = tool('GODOT_BIN', 'godot')
    if not executable(godot):
        report.fail(f'Godot executable missing: {godot or "godot (not on PATH; set GODOT_BIN)"}')
        return
    found = (run([godot, '--version']).stdout.strip().splitlines() or [''])[0]
    required_match = re.search(r'config/features=PackedStringArray\("([0-9][0-9.]*)"', Path('project.godot').read_text(encoding='utf-8'))
    required = required_match.group(1) if required_match else '?'
    actual, wanted = version_tuple(found), version_tuple(required)
    if actual and wanted and actual >= wanted:
        report.ok(f'Godot: {found} (project requires {required}+)')
    else:
        report.fail(f'Godot {required}+ required; found: {found}')


def content(report: Report) -> None:
    # Original-derived content absent (a public checkout before the import, hsltools.original_content):
    # the scenario check has nothing to read.
    if not original_content.present():
        report.ok('SKIP original-absent: first battle scenario not imported (HSL_ORIGINAL_DIR=... python3 tools/hsl.py generate ...)')
    else:
        try:
            check_scenario()
            report.ok('first battle (campaign start_level -> battle_051.json) and the formation fixture reference existing resources')
        except (AssertionError, KeyError, OSError, ValueError):
            report.fail('content/battles/battle_051.json / first_battle.json is invalid or references missing resources')
    bash = shutil.which('bash')
    if sys.platform == 'win32' or not bash:
        report.info('route syntax: skipped (tools/hsl_capture.sh routes drive macOS windows through bash)')
    else:
        for route in sorted(Path('tools/routes').glob('*.txt')):
            passed = run([bash, 'tools/hsl_capture.sh', '--dry-run', route.as_posix()]).returncode == 0
            report.check(passed, f'route syntax: {route.as_posix()}', f'invalid route: {route.as_posix()}')
    tracked_imports = [name for name in run(['git', 'ls-files', '--', '*.import']).stdout.splitlines() if Path(name).exists()]
    report.check(not tracked_imports, 'no tracked Godot .import cache files', f'tracked Godot .import cache files: {" ".join(tracked_imports)}')
    scripts = [path for folder in ('game', 'tests') for path in sorted(Path(folder).rglob('*.gd'))]
    missing = [path.as_posix() for path in scripts if not path.with_name(path.name + '.uid').is_file()]
    orphans = [path.as_posix() for folder in ('game', 'tests') for path in sorted(Path(folder).rglob('*.gd.uid'))
               if not path.with_name(path.name[:-len('.uid')]).is_file()]
    if not missing and not orphans:
        report.ok('live GDScript UID sidecars are complete')
    if missing:
        report.fail(f'GDScript files missing .uid sidecars: {" ".join(missing)}')
    if orphans:
        report.fail(f'orphan .gd.uid sidecars: {" ".join(orphans)}')


def original_folder(report: Report) -> None:
    """Which original folder the importers use and why (hsltools.paths.detect_original_dir); absence is INFO."""
    folder, origin = paths.ORIGINAL_SOURCE_DIR, paths.ORIGINAL_DIR_ORIGIN
    packs = [name for name in ('hsl-cn.pak', 'hsl.pak') if (folder / name).is_file()]
    if packs:
        report.ok(f'original folder: {folder} ({origin}; packs: {", ".join(packs)}; importers read {paths.ORIGINAL_PAK})')
    else:
        probed = f'; Steam libraries probed: {", ".join(paths.ORIGINAL_DIR_PROBED)}' if paths.ORIGINAL_DIR_PROBED else ''
        report.info(f'original folder not found: {folder} ({origin}{probed}); set HSL_ORIGINAL_DIR to the folder'
                    ' holding hsl-cn.pak／hsl.pak (Steam 經典版 GAME-PAK) to import')


def original_runtime(report: Report) -> None:
    """--original: the Wine-hosted hsl01.exe and the macOS capture helpers (tools/run_original_hsl.sh)."""
    if sys.platform == 'win32':
        report.info('--original: Wine and the macOS capture helpers do not apply on Windows; run the original directly')
        return
    prefix = Path(os.environ.get('WINEPREFIX') or Path.home() / '.wine-hsl-original')
    wine = tool('WINE_BIN', 'wine')
    if executable(wine):
        report.ok(f'Wine: {run([wine, "--version"]).stdout.strip()}')
    else:
        report.fail(f'Wine missing: {wine}')
    report.check((prefix / 'drive_c/hsl/hsl01.exe').is_file(), 'original hsl01.exe present', f'original hsl01.exe missing under {prefix}')
    report.check((prefix / 'drive_c/hsl/ddraw.dll').is_file(), 'cnc-ddraw present', f'ddraw.dll missing under {prefix}')
    if sys.platform != 'darwin':
        report.info('--original: cliclick and the Swift window／input helpers are macOS-only')
        return
    cliclick = tool('CLICLICK_BIN', 'cliclick')
    if executable(cliclick):
        probe = run([cliclick, '-V'])
        lines = (probe.stdout + probe.stderr).strip().splitlines()
        report.ok(f'cliclick: {cliclick} ({lines[-1] if lines else ""})')
    else:
        report.warn(f'cliclick not found: {cliclick} (legacy/manual automation only)')

    def fresh(source: str, built: str) -> bool:
        return Path(source).stat().st_mtime <= Path(built).stat().st_mtime

    if all(executable(f'tools/{name}') for name in ('hsl_window', 'hsl_input')):
        report.ok('runtime helpers present')
        for name in ('hsl_window', 'hsl_input'):
            report.check(fresh(f'tools/{name}.swift', f'tools/{name}'), f'{name} binary matches current source timestamp',
                         f'{name} is stale; run tools/build_runtime_helpers.sh')
    else:
        report.fail('runtime helpers missing; run tools/build_runtime_helpers.sh')
    memread = Path('ignored/bin/hsl_win32_memread.exe')
    if memread.is_file():
        report.ok('optional win32-rpm scalar helper present')
        report.check(fresh('tools/hsl_win32_memread.c', str(memread)), 'win32-rpm helper matches current source timestamp',
                     'win32-rpm helper is stale; run tools/build_runtime_helpers.sh --win32-rpm')
    else:
        report.warn('win32-rpm helper missing; run tools/build_runtime_helpers.sh --win32-rpm before scalar memory probes')


def main(original: bool) -> int:
    os.chdir(ROOT)
    report = Report()
    repository(report)
    toolchain(report)
    content(report)
    original_folder(report)
    if original:
        original_runtime(report)
    if report.errors:
        print(f'doctor failed: errors={report.errors} warnings={report.warnings}', file=sys.stderr)
        return 1
    print(f'doctor passed: warnings={report.warnings}')
    return 0
