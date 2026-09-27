"""Task registry behind tools/hsl.py: what each generator reads, writes and how to check it.

A Task names its inputs and outputs (repository-relative), can `check` (prove the tracked
outputs are exactly what the current sources and code produce) and `generate` (rewrite
them). Three shapes exist:

  GeneratedFilesTask   render() -> {path: bytes}; check = byte-for-byte comparison with the
                       tracked files, generate = write them (data generators, per-level
                       assemblers)
  PacketTask           a native probe whose output is one evidence packet; check validates
                       the tracked packet against the independent model, generate executes
                       the original instructions (needs the documented EXE and unicorn)
  ScriptCheckTask      a checker kept as its migrated function: verify() prints its own PASS
                       line (asset importer --check, evidence checkers); build() optionally
                       regenerates from the original PAK when it is installed

Every task runs in-process. all_tasks() is the complete gate check set of `hsl check --all`
(docs/CONSOLIDATION.md P1); its invariant is the command ledger of hsltools.legacy: every
ledger command is `replaces`d by exactly one task and every `replaces` names a ledger
command, so the PASS-line set is fixed by the ledger and a task cannot silently drop out.
"""
from __future__ import annotations

import contextlib
import dataclasses
import fnmatch
import importlib
import io
import json
import pkgutil
import re
import subprocess
import sys
import time
import traceback
from concurrent.futures import ProcessPoolExecutor
from pathlib import Path
from typing import Callable, Iterable

from hsltools import original_content
from hsltools.legacy import check_commands
from hsltools.paths import ORIGINAL_EXE, ROOT
from hsltools.runner import Job, Result, last_line, run_parallel

# The packages whose modules expose tasks() -> list[Task]; discovered, never listed.
TASK_PACKAGES = ('hsltools.probes', 'hsltools.levels', 'hsltools.data', 'hsltools.checks',
                 'hsltools.assets', 'hsltools.evidence', 'hsltools.schema')
# Changes here affect every task (core code, the gate itself, the CLI).
CORE_PATHS = ('tools/hsltools/', 'tools/verify_runner.py', 'tools/hsl.py')
# Shared original sources most scripts read through the table readers without naming them
# on their command line, plus the authored role tables hsltools.model.jobs reads for every
# job computation: a change there is treated as affecting every task (conservative).
SHARED_SOURCE_PATHS = ('content/imported/hsl/global/', 'content/imported/hsl/chapter01/source_texts/', 'content/authored/roles/')


class CheckFailed(Exception):
    """A task's tracked outputs (or an evidence packet) differ from what the sources produce."""


class NotGeneratable(Exception):
    """The task cannot regenerate because a required input is absent (the original install
    under WINEPREFIX / --exe, a dump, a sample). `hsl generate` reports it as a failure: a
    missing input is never a silent skip (AGENTS.md: 必要输入缺失应明确失败)."""


class NoRegenerationPath(NotGeneratable):
    """The task is a pure checker: there is nothing to regenerate. `hsl generate` skips it
    (a family or glob pattern may sweep pure checkers in) and still passes."""


@dataclasses.dataclass(frozen=True)
class Context:
    root: Path = ROOT
    original_exe: Path = ORIGINAL_EXE


class Task:
    name: str
    family: str
    inputs: tuple[str, ...] = ()
    outputs: tuple[str, ...] = ()
    replaces: tuple[str, ...] = ()
    scripts: tuple[str, ...] = ()   # tools/*.py files whose change affects this task
    level: int | None = None

    def check(self, ctx: Context) -> str:
        raise NotImplementedError

    def generate(self, ctx: Context) -> str:
        raise NotImplementedError

    def describe(self) -> str:
        return f'{self.name}\t{self.family}\t' + ' '.join(self.outputs)


class GeneratedFilesTask(Task):
    def render(self, ctx: Context) -> dict[str, bytes]:
        raise NotImplementedError

    def summary(self, rendered: dict[str, bytes], mode: str) -> str:
        """The PASS line; mode is 'check' or 'generate'."""
        raise NotImplementedError

    def check(self, ctx: Context) -> str:
        rendered = self.render(ctx)
        stale = [path for path, data in rendered.items()
                 if not (ctx.root / path).exists() or (ctx.root / path).read_bytes() != data]
        if stale:
            missing = [path for path in stale if not (ctx.root / path).exists()]
            hint = f' (not yet written: {", ".join(missing)})' if missing else ''
            raise CheckFailed(f'{self.name}: stale tracked output(s): ' + ', '.join(stale) + hint
                              + f' — `python3 tools/hsl.py generate {self.name}` rewrites them')
        return self.summary(rendered, 'check')

    def generate(self, ctx: Context) -> str:
        rendered = self.render(ctx)
        for path, data in rendered.items():
            target = ctx.root / path
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(data)
        return self.summary(rendered, 'generate')


class PacketTask(Task):
    packet: str  # repository-relative evidence packet path (== outputs[0])

    def validate(self, packet: dict) -> None:
        raise NotImplementedError

    def execute(self, ctx: Context) -> dict:
        raise NotImplementedError

    def summary(self, packet: dict, executed_now: bool) -> str:
        raise NotImplementedError

    def load(self, ctx: Context) -> dict:
        return json.loads((ctx.root / self.packet).read_text())

    def render_packet(self, packet: dict) -> str:
        """The tracked text generate writes (indent=2 unless the task renders compactly)."""
        return json.dumps(packet, ensure_ascii=False, indent=2) + '\n'

    def check(self, ctx: Context) -> str:
        packet = self.load(ctx)
        try:
            self.validate(packet)
        except ValueError as error:
            raise CheckFailed(f'{self.name}: {error}') from error
        return self.summary(packet, False)

    def generate(self, ctx: Context) -> str:
        if not ctx.original_exe.exists():
            raise NotGeneratable(f'{self.name}: original EXE not found at {ctx.original_exe} (needs the documented hsl01.exe and unicorn)')
        packet = self.execute(ctx)
        self.validate(packet)
        target = ctx.root / self.packet
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(self.render_packet(packet))
        return self.summary(packet, True)


def printed_pass_line(name: str, run: Callable[[], None]) -> str:
    """Run a checker that prints its result: every line but the last is re-emitted, the last
    (the PASS line) is returned; its assert / ValueError / `raise SystemExit(message)` failures
    become CheckFailed (a SystemExit(0) is a normal return)."""
    buffer = io.StringIO()
    try:
        with contextlib.redirect_stdout(buffer):
            run()
    except SystemExit as error:
        if error.code not in (None, 0):
            raise CheckFailed(f'{name}: {error.code}\n{buffer.getvalue()}'.rstrip()) from error
    except (AssertionError, ValueError, KeyError) as error:
        raise CheckFailed(f'{name}: {type(error).__name__}: {error}\n{buffer.getvalue()}'.rstrip()) from error
    lines = [line for line in buffer.getvalue().splitlines() if line.strip()]
    if not lines:
        raise CheckFailed(f'{name}: checker printed no result line')
    for line in lines[:-1]:
        print(line)
    return lines[-1]


class ScriptCheckTask(Task):
    def verify(self, ctx: Context) -> None:
        """Prints the PASS line (or raises AssertionError / ValueError)."""
        raise NotImplementedError

    def build(self, ctx: Context) -> None:
        """Rewrites the tracked outputs from the original sources; NotGeneratable when absent."""
        raise NoRegenerationPath(f'{self.name}: pure checker, no regeneration path')

    def check(self, ctx: Context) -> str:
        return printed_pass_line(self.name, lambda: self.verify(ctx))

    def generate(self, ctx: Context) -> str:
        self.build(ctx)
        return printed_pass_line(self.name, lambda: self.verify(ctx))


def original_archive(ctx: Context, filename: str = 'hsl.pak') -> Path:
    """The original PAK next to the documented EXE, or NotGeneratable when not installed."""
    pak = ctx.original_exe.with_name(filename)
    if not pak.exists():
        raise NotGeneratable(f'original {filename} not found at {pak} (needs the original install; WINEPREFIX or --exe)')
    return pak


def task_modules() -> list[str]:
    """Every module under TASK_PACKAGES that defines tasks(), sorted by name. Helper modules
    (hsltools.probes._base, hsltools.schema.validate) define none and contribute nothing.
    The order is only for determinism: generation order comes from inputs / outputs."""
    names: list[str] = []
    for package_name in TASK_PACKAGES:
        package = importlib.import_module(package_name)
        for info in pkgutil.iter_modules(package.__path__, package_name + '.'):
            if callable(getattr(importlib.import_module(info.name), 'tasks', None)):
                names.append(info.name)
    return sorted(names)


def discovered_tasks() -> list[Task]:
    """Every task the task modules expose, before the registry invariants are checked."""
    tasks: list[Task] = []
    for module_name in task_modules():
        tasks.extend(importlib.import_module(module_name).tasks())
    return tasks


def check_ledger(tasks: list[Task], ledger: list[str]) -> None:
    """The registry invariant: task names are unique, every ledger command is replaced by
    exactly one task, and every `replaces` names a ledger command. ValueError names the
    offending commands / tasks."""
    names = [task.name for task in tasks]
    duplicates = sorted({name for name in names if names.count(name) > 1})
    if duplicates:
        raise ValueError(f'duplicate task names: {duplicates}')
    replaced_by: dict[str, list[str]] = {}
    for task in tasks:
        for command in task.replaces:
            replaced_by.setdefault(command, []).append(task.name)
    problems = [f'ledger command replaced by no task: {command!r}' for command in ledger if command not in replaced_by]
    problems += [f'ledger command replaced by {len(owners)} tasks {owners}: {command!r}'
                 for command, owners in replaced_by.items() if len(owners) > 1]
    known = set(ledger)
    problems += [f'task {owners[0]} replaces a command missing from the ledger: {command!r}'
                 for command, owners in replaced_by.items() if command not in known]
    if problems:
        raise ValueError('registry ledger invariant broken:\n  ' + '\n  '.join(problems))


def all_tasks() -> list[Task]:
    tasks = discovered_tasks()
    check_ledger(tasks, check_commands())
    return tasks


def select(tasks: list[Task], patterns: Iterable[str]) -> list[Task]:
    """Tasks whose name, family or family:level matches any pattern (fnmatch); order kept."""
    patterns = list(patterns)
    chosen: list[Task] = []
    for pattern in patterns:
        matches = [task for task in tasks
                   if task.name == pattern or task.family == pattern or fnmatch.fnmatchcase(task.name, pattern)]
        if not matches:
            raise KeyError(f'no task matches {pattern!r} (see `hsl list`)')
        chosen.extend(task for task in matches if task not in chosen)
    return chosen


def _overlaps(a: str, b: str) -> bool:
    """Path a names path b, a file inside directory b, or a directory containing b."""
    return a == b or a.startswith(b.rstrip('/') + '/') or b.startswith(a.rstrip('/') + '/')


def generation_order(tasks: list[Task]) -> list[Task]:
    """The selected tasks with producers before consumers: a task that reads what another
    selected task writes (declared inputs vs outputs) is generated after it. Stable order
    otherwise; no separate dependency declaration exists."""
    producers = {task.name: [other for other in tasks if other is not task
                             and any(_overlaps(inp, out) for inp in task.inputs for out in other.outputs)]
                 for task in tasks}
    ordered: list[Task] = []
    visiting: set[str] = set()

    def visit(task: Task) -> None:
        if task in ordered:
            return
        if task.name in visiting:
            raise ValueError(f'generation cycle through {task.name}')
        visiting.add(task.name)
        for producer in producers[task.name]:
            visit(producer)
        visiting.discard(task.name)
        ordered.append(task)

    for task in tasks:
        visit(task)
    return ordered


# --- affected -----------------------------------------------------------------------------

def import_graph(tools_dir: Path = ROOT / 'tools') -> dict[str, set[str]]:
    """{script stem: set of tools module stems it imports} from static import statements."""
    graph: dict[str, set[str]] = {}
    pattern = re.compile(r'^\s*(?:from\s+(?:tools\.)?(hsl_\w+)\s+import|import\s+(?:tools\.)?(hsl_\w+))', re.M)
    for path in tools_dir.glob('*.py'):
        text = path.read_text(encoding='utf-8', errors='replace')
        graph[path.stem] = {a or b for a, b in pattern.findall(text)}
    return graph


def dependents(changed_modules: set[str], graph: dict[str, set[str]]) -> set[str]:
    """Modules that transitively import any changed module (plus the changed ones)."""
    result = set(changed_modules)
    grown = True
    while grown:
        grown = False
        for module, imports in graph.items():
            if module not in result and imports & result:
                result.add(module)
                grown = True
    return result


def affected(tasks: list[Task], changed_paths: Iterable[str]) -> list[Task]:
    changed = [path.replace('\\', '/').lstrip('./') for path in changed_paths]
    if any(_overlaps(path, core) for path in changed for core in CORE_PATHS + SHARED_SOURCE_PATHS):
        return list(tasks)
    changed_modules = {Path(path).stem for path in changed if path.startswith('tools/') and path.endswith('.py')}
    touched = dependents(changed_modules, import_graph()) if changed_modules else set()
    result: list[Task] = []
    for task in tasks:
        if any(Path(script).stem in touched for script in task.scripts):
            result.append(task)
            continue
        if any(_overlaps(path, declared) for declared in task.inputs + task.outputs for path in changed):
            result.append(task)
    return result


# --- running ------------------------------------------------------------------------------

def run_task(task: Task, mode: str, ctx: Context, capture: bool = True) -> Result:
    """Run one task in this process; (code, output, seconds): 0 ok, 1 failed (CheckFailed,
    a missing input under generate, any other exception), 2 nothing to regenerate.

    capture=True also collects what the task prints (sys.stdout is swapped process-wide, so
    only do this from a single-threaded context: the process-pool workers, hsl generate)."""
    started = time.monotonic()
    buffer = io.StringIO()
    try:
        with contextlib.redirect_stdout(buffer) if capture else contextlib.nullcontext():
            line = task.check(ctx) if mode == 'check' else task.generate(ctx)
        return 0, (buffer.getvalue() + line).rstrip('\n') + '\n', time.monotonic() - started
    except CheckFailed as error:
        return 1, buffer.getvalue() + str(error), time.monotonic() - started
    except NoRegenerationPath as error:
        return 2, buffer.getvalue() + str(error), time.monotonic() - started
    except NotGeneratable as error:
        return 1, buffer.getvalue() + str(error), time.monotonic() - started
    except Exception:  # noqa: BLE001 - the runner reports the traceback as the job log
        return 1, buffer.getvalue() + traceback.format_exc(), time.monotonic() - started


def _run_named(name: str, mode: str, exe: str) -> Result:
    """Process-pool entry: rebuild the task list in the worker and run one task."""
    ctx = Context(original_exe=Path(exe))
    task = next(task for task in discovered_tasks() if task.name == name)
    return run_task(task, mode, ctx)


def run_tasks(label: str, tasks: list[Task], mode: str, ctx: Context, jobs: int) -> int:
    """Run the tasks in a process pool (in this process, uncaptured, when jobs == 1).
    Prints the sorted result block; 0 on success.

    While the original-derived content is absent (a public checkout before the player's import,
    hsltools.original_content) a check of a task declaring an original-derived path is not run:
    one `<LABEL>_SKIP original-absent tasks=N` line counts them — neither PASS nor a silent skip."""
    if mode == 'check' and not original_content.present():
        skipped = {task.name for task in tasks if original_content.needs_original(task)}
        if skipped:
            print(f'{label}_SKIP original-absent tasks={len(skipped)} of={len(tasks)}'
                  ' (import the original first: HSL_ORIGINAL_DIR=... python3 tools/hsl.py generate ...)', flush=True)
            tasks = [task for task in tasks if task.name not in skipped]
    pool = ProcessPoolExecutor(max_workers=jobs) if jobs > 1 and tasks else None
    try:
        def thunk(task: Task) -> Callable[[], Result]:
            if pool is not None:
                return lambda: pool.submit(_run_named, task.name, mode, str(ctx.original_exe)).result()
            return lambda: run_task(task, mode, ctx, capture=False)

        job_list: list[Job] = [(task.name, thunk(task)) for task in tasks]
        return run_parallel(label, job_list, jobs, lambda name, output, seconds: f'{last_line(output)}{RESULT_SUFFIX}{name}')
    finally:
        if pool is not None:
            pool.shutdown()


# Result block line: '<PASS line>  <- <task name>'.
RESULT_SUFFIX = '  <- '


def cli_check_lines(names: Iterable[str], root: Path = ROOT) -> dict[str, str]:
    """{task name: PASS line} as one `python3 tools/hsl.py check NAME... -j 1` subprocess prints
    them (the tests' parity oracle: the CLI prints exactly what check() returns)."""
    names = list(names)
    output = subprocess.run([sys.executable, 'tools/hsl.py', 'check', *names, '-j', '1'],
                            cwd=root, capture_output=True, text=True, check=True).stdout
    lines: dict[str, str] = {}
    for line in output.splitlines():
        body, suffix, name = line.rpartition(RESULT_SUFFIX)
        if suffix and name in names:
            lines[name] = body
    return lines
