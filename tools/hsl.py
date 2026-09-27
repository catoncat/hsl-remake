#!/usr/bin/env python3
"""hsl: one entry point for the generator / checker registry (hsltools.registry).

  hsl list [PATTERN...]                       tasks: name, family, outputs
  hsl check --all | PATTERN... [-j N]         prove tracked outputs match sources and code
  hsl check --profile=modder|parity|maintainer  the tasks of a tier and the tiers before it
                                              (registry.TIERS); modder prints one SKIP line
                                              counting the tiers it left out; --all = maintainer
  hsl generate PATTERN... [--exe PATH]        regenerate outputs (producers before consumers);
                                              a task whose original input is absent FAILs
                                              (WINEPREFIX / --exe), pure checkers are skipped
  hsl affected --since REF [--check] [-j N]   tasks touched by the paths changed since REF
  hsl doctor [--original]                     read-only environment preflight (tools/doctor.sh runs it)

PATTERN is a task name (`level_battle:37`), a family (`level_battle`) or an fnmatch glob
(`level_battle:9*`). `hsl check --all` is the complete gate check set run by tools/verify.sh.
"""
from __future__ import annotations

import argparse
import os
import subprocess
import sys
from pathlib import Path

# Windows: the repository's text is UTF-8 and every tool reads it with the platform default encoding in
# places (open()/read_text() without encoding=); UTF-8 mode makes that default UTF-8, for this process and
# the task subprocesses it starts (the registry re-runs this file).
if sys.platform == 'win32' and not sys.flags.utf8_mode:
    os.environ['PYTHONUTF8'] = '1'
    sys.exit(subprocess.call([sys.executable, '-X', 'utf8', *sys.argv]))

sys.path.insert(0, str(Path(__file__).resolve().parent))

from hsltools import registry  # noqa: E402
from hsltools.paths import ORIGINAL_EXE, ROOT  # noqa: E402


def default_jobs() -> int:
    override = os.environ.get('HSL_VERIFY_JOBS', '').strip()  # same cap as verify_runner
    if override.isdigit() and int(override) > 0:
        return int(override)
    return max(2, (os.cpu_count() or 4) - 2)


def cmd_list(args) -> int:
    tasks = registry.all_tasks()
    if args.patterns:
        tasks = registry.select(tasks, args.patterns)
    for task in tasks:
        print(task.describe())
    print(f'HSL_TASKS total={len(tasks)}', file=sys.stderr)
    return 0


def cmd_check(args) -> int:
    tasks = registry.all_tasks()
    if not args.all:
        if not args.patterns and not args.profile:
            print('hsl check: give --all, --profile=TIER or at least one task pattern', file=sys.stderr)
            return 2
        if args.patterns:
            tasks = registry.select(tasks, args.patterns)
        if args.profile:
            tasks, skipped = registry.in_profile(tasks, args.profile)
            if skipped:
                # A modder pass is not an equivalence claim: say what did not run.
                counts = ' '.join(f'{tier}={skipped[tier]}' for tier in registry.TIERS if tier in skipped)
                print(f'SOURCE_CHECKS_SKIP profile={args.profile} {counts} (--profile=maintainer or --all runs them)', flush=True)
    ctx = registry.Context(original_exe=args.exe)
    return registry.run_tasks('SOURCE_CHECKS', tasks, 'check', ctx, args.jobs)


def cmd_generate(args) -> int:
    selected = registry.select(registry.all_tasks(), args.patterns)
    ordered = registry.generation_order(selected)
    ctx = registry.Context(original_exe=args.exe)
    failed = 0
    for task in ordered:
        code, output, seconds = registry.run_task(task, 'generate', ctx)
        status = 'ok' if code == 0 else ('skipped' if code == 2 else 'FAIL')
        print(f'[generate {status} {seconds:.1f}s] {task.name}')
        print(output.rstrip())
        failed += code == 1
    unimported = unimported_resources(ordered)
    if unimported:
        print(f'HSL_GENERATE_HINT unimported={len(unimported)} first={unimported[0]}: Godot cannot load() a new resource'
              ' before its .import sidecar exists — run tools/godot.sh --headless --import')
    print(f'GENERATE_{"FAIL" if failed else "PASS"} tasks={len(ordered)} failed={failed}')
    return 1 if failed else 0


# Output file types Godot imports (a `<file>.import` sidecar must exist before load() works).
IMPORTED_SUFFIXES = {'.png', '.jpg', '.webp', '.svg', '.wav', '.ogg', '.mp3'}


def unimported_resources(tasks) -> list[str]:
    """Importable files under the tasks' outputs that have no Godot .import sidecar yet
    (directories holding a .gdignore are not imported and are skipped)."""
    found: set[str] = set()

    def gdignored(path: Path) -> bool:
        return any((ROOT / parent / '.gdignore').exists() for parent in path.relative_to(ROOT).parents)

    for task in tasks:
        for output in task.outputs:
            target = ROOT / output
            candidates = target.rglob('*') if target.is_dir() else [target]
            for path in candidates:
                if path.suffix.lower() in IMPORTED_SUFFIXES and path.is_file() \
                        and not path.with_name(path.name + '.import').exists() and not gdignored(path):
                    found.add(path.relative_to(ROOT).as_posix())
    return sorted(found)


def changed_since(ref: str) -> list[str]:
    tracked = subprocess.run(['git', 'diff', '--name-only', ref, '--'], cwd=ROOT, capture_output=True, text=True, check=True).stdout
    untracked = subprocess.run(['git', 'ls-files', '--others', '--exclude-standard'], cwd=ROOT, capture_output=True, text=True, check=True).stdout
    return sorted({line for line in (tracked + untracked).splitlines() if line.strip()})


def cmd_affected(args) -> int:
    changed = changed_since(args.since)
    tasks = registry.affected(registry.all_tasks(), changed)
    for task in tasks:
        print(task.name)
    print(f'HSL_AFFECTED since={args.since} changed_paths={len(changed)} tasks={len(tasks)}', file=sys.stderr)
    if args.check and tasks:
        ctx = registry.Context(original_exe=args.exe)
        return registry.run_tasks('SOURCE_CHECKS', tasks, 'check', ctx, args.jobs)
    return 0


def cmd_doctor(args) -> int:
    from hsltools import doctor
    return doctor.main(args.original)


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(prog='hsl', description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest='command', required=True)

    def common(p, jobs: bool = True) -> None:
        p.add_argument('--exe', type=Path, default=ORIGINAL_EXE, help='original hsl01.exe for native execution')
        if jobs:
            p.add_argument('-j', '--jobs', type=int, default=default_jobs())

    p = sub.add_parser('list', help='list tasks')
    p.add_argument('patterns', nargs='*')
    p.set_defaults(handler=cmd_list)

    p = sub.add_parser('check', help='check that tracked outputs match sources and code')
    p.add_argument('patterns', nargs='*')
    p.add_argument('--all', action='store_true', help='every task (= --profile=maintainer; tools/verify.sh and CI)')
    p.add_argument('--profile', choices=registry.TIERS, help='a tier and the tiers before it (modder < parity < maintainer)')
    common(p)
    p.set_defaults(handler=cmd_check)

    p = sub.add_parser('generate', help='regenerate outputs, producers before consumers')
    p.add_argument('patterns', nargs='+')
    common(p, jobs=False)
    p.set_defaults(handler=cmd_generate)

    p = sub.add_parser('affected', help='tasks affected by the paths changed since a git ref')
    p.add_argument('--since', required=True)
    p.add_argument('--check', action='store_true', help='also run the affected checks')
    common(p)
    p.set_defaults(handler=cmd_affected)

    p = sub.add_parser('doctor', help='read-only environment and repository preflight')
    p.add_argument('--original', action='store_true', help='also check the Wine-hosted original and the capture helpers')
    p.set_defaults(handler=cmd_doctor)

    args = parser.parse_args(argv)
    try:
        return args.handler(args)
    except KeyError as error:
        print(f'hsl: {error.args[0]}', file=sys.stderr)
        return 2


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
