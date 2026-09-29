"""`hsl bootstrap`: import every original-derived file the game reads from the player's own copy
(HSL_ORIGINAL_DIR), in one resumable command; tools/play.sh and tools/play.ps1 run it on a fresh
checkout.

The work list is the tracked manifest (hsltools.original_content.MANIFEST): every entry names the
registry task that writes it. A task runs when any file it owns is absent; a task whose files are all
present is skipped (so a checkout that already has the content — the private repository — is not
touched). Tasks run producers before consumers (registry.generation_order); a task that fails because
an input written later in the run was not there yet gets another round, as long as a round makes
progress. Whether a task runs depends on existence only; hashes are compared for the tasks this run
generated (settle, in main) and by `hsl check original_derived_manifest` afterwards.

Manifest entries without a task (screenshots and other evidence of the original, the placeholder art of
the demo actors) have no generator; they are counted in the summary, never imported here. A task that
needs an input the player's copy does not have (the documented hsl01.exe, a memory dump) is counted as
original_missing, a pure checker or a task whose declared input no task writes (an output of the
chapter-one payload inspector) as no_generator, and a task whose input waits on either inherits its
status; none of these is retried or counted as a failure.

INCOMPLETE marks a run that has not finished cleanly: written at the start, removed when no task is
left failed. tools/play.sh runs the bootstrap when the original tables are absent or this marker exists,
so an interrupted import resumes on the next launch and a complete checkout pays nothing.
GENERATED is written as soon as a task generates its files; tools/play.ps1, which has no import-change
detection of its own, imports the Godot resources while it exists and removes it after a successful
import.
"""
from __future__ import annotations

import contextlib
import io
import time
import traceback

from hsltools import original_content, paths, registry

INCOMPLETE = paths.ROOT / 'ignored/hsl-bootstrap/incomplete'
GENERATED = paths.ROOT / 'ignored/hsl-bootstrap/generated'
MAX_ROUNDS = 4


def owned_files() -> dict[str, list[str]]:
    """{task name: manifest paths it owns}."""
    owned: dict[str, list[str]] = {}
    for path, entry in original_content.manifest().items():
        if entry['task']:
            owned.setdefault(entry['task'], []).append(path)
    return owned


def missing(files: list[str]) -> list[str]:
    return [path for path in files if not (paths.ROOT / path).is_file()]


def generate(task: registry.Task, ctx: registry.Context) -> tuple[str, str]:
    """(status, captured output): ok, original_missing, no_generator or failed."""
    buffer = io.StringIO()
    try:
        with contextlib.redirect_stdout(buffer):
            task.generate(ctx)
        return 'ok', buffer.getvalue()
    except registry.NoRegenerationPath as error:
        return 'no_generator', f'{buffer.getvalue()}{error}'
    except registry.NotGeneratable as error:
        return 'original_missing', f'{buffer.getvalue()}{error}'
    except Exception:  # noqa: BLE001 - reported with its traceback, retried next round
        return 'failed', buffer.getvalue() + traceback.format_exc()


def covers(output: str, path: str) -> bool:
    return path == output or (output.endswith('/') and path.startswith(output)) or (path.endswith('/') and output.startswith(path))


def blocked(task: registry.Task, writers: list[tuple[str, str]], status: dict[str, str]) -> tuple[str, str] | None:
    """(status, reason) for a failed task that cannot run in this checkout: a declared input is absent and
    no task this command runs writes it (an output of the chapter-one payload inspector, which is not a
    registry task, or of a packet task), or every task that writes it could not run (it needs hsl01.exe,
    say). Asked only after the task failed: a declared input the generator does not read (evidence its
    check compares against) must not keep it from running."""
    for path in task.inputs:
        if (paths.ROOT / path).exists():
            continue
        names = [name for output, name in writers if name != task.name and covers(output, path)]
        if not names:
            return 'no_generator', f'input {path} is absent and no task this command runs writes it'
        stuck = [name for name in names if status.get(name) in ('original_missing', 'no_generator')]
        if len(stuck) == len(names):
            return status[stuck[0]], f'input {path} waits on {stuck[0]} ({status[stuck[0]]})'
    return None


def differing(names: list[str], owned: dict[str, list[str]], manifest: dict[str, dict]) -> dict[str, str]:
    """{task: its first present owned file whose content hash is not the manifest's} for the tasks among `names`."""
    from hsltools.checks.original_derived_manifest import content_hash
    stale = {}
    for name in names:
        for path in owned[name]:
            if (paths.ROOT / path).is_file() and content_hash(paths.ROOT / path) != {
                    key: value for key, value in manifest[path].items() if key != 'task'}:
                stale[name] = path
                break
    return stale


def tail(text: str, lines: int = 6) -> str:
    kept = [line for line in text.splitlines() if line.strip()][-lines:]
    return '\n'.join('    ' + line for line in kept)


def main(exe, dry_run: bool = False) -> int:
    started = time.monotonic()
    manifest = original_content.manifest()
    if not manifest:
        print(f'HSL_BOOTSTRAP_FAIL no manifest at {original_content.MANIFEST_RELATIVE}')
        return 1
    owned = owned_files()
    unowned = sum(1 for entry in manifest.values() if not entry['task'])
    tasks = {task.name: task for task in registry.all_tasks()}
    writers = [(output, name) for name in owned if name in tasks for output in tasks[name].outputs]
    unknown = sorted(name for name in owned if name not in tasks)
    if unknown:
        print(f'HSL_BOOTSTRAP_FAIL manifest names {len(unknown)} unregistered task(s), first={unknown[0]}')
        return 1
    pending = [tasks[name] for name in tasks if name in owned and missing(owned[name])]
    skipped = len(owned) - len(pending)
    if dry_run or not pending:
        files = sum(len(missing(owned[task.name])) for task in pending)
        print(f'HSL_BOOTSTRAP_{"PLAN" if pending else "PASS"} generated=0 skipped={skipped} pending={len(pending)}'
              f' missing_files={files} unowned={unowned}')
        if not pending:
            INCOMPLETE.unlink(missing_ok=True)
        return 0
    if not paths.ORIGINAL_PAK.is_file():
        print(f'HSL_BOOTSTRAP_FAIL original data not found: {paths.ORIGINAL_PAK} ({paths.ORIGINAL_DIR_ORIGIN});'
              ' set HSL_ORIGINAL_DIR to the GAME-PAK folder of your copy (python3 tools/hsl.py doctor shows the search)')
        return 1
    INCOMPLETE.parent.mkdir(parents=True, exist_ok=True)
    INCOMPLETE.touch()
    print(f'HSL_BOOTSTRAP start tasks={len(pending)} skipped={skipped} original={paths.ORIGINAL_SOURCE_DIR}', flush=True)
    ctx = registry.Context(original_exe=exe)
    status: dict[str, str] = {}
    logs: dict[str, str] = {}
    todo = registry.generation_order(pending)
    for round_no in range(1, MAX_ROUNDS + 1):
        progressed = False
        for index, task in enumerate(todo, 1):
            task_started = time.monotonic()
            result, output = generate(task, ctx)
            if result == 'failed' and (cause := blocked(task, writers, status)):
                result, output = cause[0], f'{cause[1]}\n{output}'
            if result == 'ok' and missing(owned[task.name]):
                absent = missing(owned[task.name])
                result, output = 'failed', f'{output}\n{len(absent)} owned file(s) still absent, first={absent[0]}'
            status[task.name], logs[task.name] = result, output
            if result == 'ok':
                GENERATED.touch()
            progressed |= result == 'ok'
            seconds = time.monotonic() - task_started
            if index % 100 == 0 or seconds >= 20:
                print(f'[bootstrap round {round_no} {index}/{len(todo)} {time.monotonic() - started:.0f}s] {task.name} ({seconds:.0f}s)', flush=True)
        todo = [task for task in todo if status[task.name] == 'failed']
        if not todo or not progressed:
            break
    # Settle: a task that reads an input it does not declare (generation_order cannot put that input's
    # writer first) may have run before the input existed and written other content than the manifest
    # records. The tasks generated in this run whose files differ are generated once more, in order, now
    # that every input this copy can produce is present; what still differs is counted as differ=.
    stale = differing([name for name, result in status.items() if result == 'ok'], owned, manifest)
    if stale:
        print(f'[bootstrap settle] {len(stale)} task(s) wrote content the manifest does not record; generating them again', flush=True)
        for task in registry.generation_order([tasks[name] for name in stale]):
            result, output = generate(task, ctx)
            if result != 'ok':
                status[task.name], logs[task.name] = result, output
        stale = differing([name for name in stale if status[name] == 'ok'], owned, manifest)
    for name, path in stale.items():
        print(f'[bootstrap differ] {name}: {path} (and possibly more) differs from the manifest', flush=True)
    for name, result in sorted(status.items()):
        if result != 'ok':
            print(f'[bootstrap {result}] {name}\n{tail(logs[name], 6 if result == "failed" else 2)}', flush=True)
    counts = {key: sum(1 for value in status.values() if value == key) for key in ('ok', 'original_missing', 'no_generator', 'failed')}
    files = sum(len(missing(owned[name])) for name in status)
    if counts['failed'] == 0:
        INCOMPLETE.unlink(missing_ok=True)
    # original_missing (an input this copy lacks: hsl01.exe, a recording of the original) and no_generator
    # (evidence only a pure checker keeps) are listed above but are not failures: PASS means every task
    # this copy of the game can feed produced its files.
    verdict = 'PASS' if counts['failed'] == 0 else 'FAIL'
    print(f'HSL_BOOTSTRAP_{verdict} generated={counts["ok"]} skipped={skipped} original_missing={counts["original_missing"]}'
          f' no_generator={counts["no_generator"]} failed={counts["failed"]} differ={len(stale)} missing_files={files} unowned={unowned}'
          f' rounds={round_no} seconds={time.monotonic() - started:.0f}')
    return 0 if verdict == 'PASS' else 1
