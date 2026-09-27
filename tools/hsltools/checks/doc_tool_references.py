"""Tool references inside the documentation's code: every `tools/...` file path, every
`python3 -m hsltools.<module>` and every `hsl check | generate | list <task>` argument written
in a fenced code block or an inline code span must name something that exists.

tools/hsl_docs_check.py validates navigation (links, anchors) and deliberately ignores code;
this task closes the gap it leaves: a README that tells the reader to run a deleted script or
an unregistered task passed every gate before (T1's ablation of hsl_combat_resolution_probe.py).

Scope: the Markdown the reader is told to act on — the root *.md, docs/, tests/, tools/ — minus
docs/external/ (vendored documentation names its own paths) and docs/collaboration/ (message
logs: a past message names the tool of its day). Generated READMEs under content/ are the
generators' output and are not documentation (their strings change only with a regeneration).
Rules, per code span or code-block line:

  tools/<path>.{py,sh,swift,c,json}   the file exists (paths containing shell metacharacters or
                                      placeholders — `*`, `$`, `<`, `{` — are skipped)
  hsl_<name>.py (bare)                tools/hsl_<name>.py exists (the stand-alone tools are named
                                      bare in the tools/README.md table and in evidence packets)
  python3 -m hsltools.a.b             tools/hsltools/a/b.py or tools/hsltools/a/b/__init__.py exists
  hsl check|generate|list ARG...      each ARG selects at least one registry task (registry.select:
                                      task name, family or fnmatch glob). `family:N`, `family:5NN`,
                                      `family:<preset>` are documentation shorthand: the family must
                                      exist; `family:a|b` names alternatives: each `family:a` must
                                      select. Options, option values (--exe PATH, -j N, --root DIR,
                                      --since REF), placeholders (`[PATTERN...]`, `<name>`, ALL-CAPS
                                      words) and everything after a shell / prose terminator (#, |,
                                      ;, ), a non-ASCII token) are not arguments. `hsl affected`
                                      takes no task arguments.

Registry task docs:tool_references (family docs, CheckTask, replaces=()).
PASS line: DOC_TOOL_REFERENCES_PASS files=N paths=N modules=N task_args=N.
"""
from __future__ import annotations

import fnmatch
import re
from pathlib import Path

from hsltools.checks import CheckTask
from hsltools.registry import CheckFailed, Context, Task, all_tasks

SCOPE_DIRECTORIES = ('docs', 'tests', 'tools')
EXCLUDED_PREFIXES = ('docs/external/', 'docs/collaboration/')
TOOL_PATH = re.compile(r'(?<![\w/.\-@])(tools/[\w./\-]+\.(?:py|sh|swift|c|json))(?![\w/])')
BARE_SCRIPT = re.compile(r'(?<![\w/.\-@])(hsl_\w+\.py)(?![\w/])')
MODULE = re.compile(r'python3?\s+-m\s+(hsltools(?:\.\w+)+)')
HSL_COMMAND = re.compile(r'(?<![\w/.\-])(?:python3\s+)?(?:tools/)?hsl(?:\.py)?\s+(check|generate|list|affected)\b(.*)')
CODE_SPAN = re.compile(r'(`+)(.+?)\1')
OPTIONS_WITH_VALUE = ('--exe', '-j', '--root', '--since')
# Where the argument list ends: a shell operator, a closing bracket, anything non-ASCII (prose).
# A pipe ends it only as its own token: `story_scene:902|903` is the documentation's alternative shorthand.
TERMINATOR = re.compile(r'#|;|&|\)|\]|`|<-|[^\x20-\x7e]|^\|')
PLACEHOLDER = re.compile(r'^(?:\[.*|<.*|\.\.\.|[A-Z][A-Z0-9_]*(?:\.\.\.)?|\$\{?[A-Za-z_]\w*\}?.*)$')
# `level_battle:N`, `battle_seed:5NN`, `original_save:<preset>`: a family with a shorthand suffix.
SHORTHAND_SUFFIX = re.compile(r'^[^:]+:(?:.*[A-Z<>].*)$')


def markdown_files(root: Path) -> list[Path]:
    """The in-scope *.md files, sorted (tracked or not: the tree is the truth)."""
    files = list(root.glob('*.md'))
    for directory in SCOPE_DIRECTORIES:
        files.extend(path for path in (root / directory).rglob('*.md')
                     if not path.relative_to(root).as_posix().startswith(EXCLUDED_PREFIXES))
    return sorted(files)


def code_lines(text: str) -> list[tuple[int, str]]:
    """(line number, code) for every fenced-block line and every inline code span, in order."""
    result: list[tuple[int, str]] = []
    fence = ''
    fence_length = 0
    for number, line in enumerate(text.splitlines(), 1):
        marker = re.match(r'^ {0,3}(`{3,}|~{3,})(.*)$', line)
        if fence:
            if marker and marker[1][0] == fence and len(marker[1]) >= fence_length and not marker[2].strip():
                fence = ''
                continue
            result.append((number, line))
        elif marker:
            fence, fence_length = marker[1][0], len(marker[1])
        else:
            result.extend((number, span[2]) for span in CODE_SPAN.finditer(line))
    return result


def command_arguments(rest: str) -> list[str]:
    """The task arguments of `hsl check|generate|list REST`: quoted tokens unquoted, options and their
    values dropped, the list cut at the first terminator or placeholder."""
    arguments: list[str] = []
    skip_value = False
    for token in rest.split():
        terminator = TERMINATOR.search(token)
        if terminator:
            token = token[:terminator.start()]
        if skip_value:
            skip_value = False
        elif token in OPTIONS_WITH_VALUE:
            skip_value = True
        elif not token.startswith('-'):
            token = token.strip('\'"')
            if not token or PLACEHOLDER.match(token):
                break
            arguments.append(token)
        if terminator:
            break
    return arguments


def module_exists(root: Path, module: str) -> bool:
    relative = Path('tools', *module.split('.'))
    return (root / relative.with_suffix('.py')).exists() or (root / relative / '__init__.py').exists()


def path_is_literal(path: str) -> bool:
    return not any(character in path for character in '*$<>{}')


def selects_task(tasks: list[Task], argument: str) -> bool:
    """registry.select's rule (name, family, fnmatch glob) plus the documentation shorthands."""
    if any(task.name == argument or task.family == argument or fnmatch.fnmatchcase(task.name, argument)
           for task in tasks):
        return True
    if ':' not in argument:
        return False
    family, suffix = argument.split(':', 1)
    if SHORTHAND_SUFFIX.match(argument):
        return any(task.family == family for task in tasks)
    if '|' in suffix:
        return all(selects_task(tasks, f'{family}:{alternative}') for alternative in suffix.split('|'))
    return False


def scan(root: Path, files: list[Path], tasks: list[Task]) -> tuple[list[str], dict[str, int]]:
    issues: list[str] = []
    counts = {'paths': 0, 'modules': 0, 'task_args': 0}
    for path in files:
        label = path.relative_to(root).as_posix()
        for number, code in code_lines(path.read_text(encoding='utf-8')):
            for match in TOOL_PATH.finditer(code):
                if not path_is_literal(match[1]):
                    continue
                counts['paths'] += 1
                if not (root / match[1]).exists():
                    issues.append(f'{label}:{number}: tool path does not exist: {match[1]}')
            for match in BARE_SCRIPT.finditer(code):
                counts['paths'] += 1
                if not (root / 'tools' / match[1]).exists():
                    issues.append(f'{label}:{number}: stand-alone tool does not exist: tools/{match[1]}')
            for match in MODULE.finditer(code):
                counts['modules'] += 1
                if not module_exists(root, match[1]):
                    issues.append(f'{label}:{number}: hsltools module does not exist: {match[1]}')
            for match in HSL_COMMAND.finditer(code):
                if match[1] == 'affected':
                    continue
                for argument in command_arguments(match[2]):
                    counts['task_args'] += 1
                    if not selects_task(tasks, argument):
                        issues.append(f'{label}:{number}: `hsl {match[1]} {argument}` selects no registry task')
    return issues, counts


def check(root: Path, tasks: list[Task] | None = None) -> str:
    files = markdown_files(root)
    issues, counts = scan(root, files, all_tasks() if tasks is None else tasks)
    if issues:
        raise ValueError(f'{len(issues)} stale tool reference(s) in documentation code:\n  ' + '\n  '.join(issues))
    return (f'DOC_TOOL_REFERENCES_PASS files={len(files)} paths={counts["paths"]} '
            f'modules={counts["modules"]} task_args={counts["task_args"]}')


class DocToolReferencesTask(CheckTask):
    name = 'docs:tool_references'
    family = 'docs'
    inputs = ('docs/', 'tests/README.md', 'tools/README.md', 'README.md', 'AGENTS.md', 'CONTEXT.md', 'content/')
    replaces = ()  # born as a registry task: no historical command to replace
    scripts = ('tools/hsltools/checks/doc_tool_references.py',)

    def check(self, ctx: Context) -> str:
        try:
            return check(ctx.root)
        except (ValueError, OSError) as error:
            raise CheckFailed(f'{self.name}: {error}') from error


def tasks() -> list[DocToolReferencesTask]:
    return [DocToolReferencesTask()]


if __name__ == '__main__':
    import sys
    from hsltools.paths import ROOT
    try:
        print(check(ROOT))
    except ValueError as error:
        print(f'DOC_TOOL_REFERENCES_FAIL {error}', file=sys.stderr)
        raise SystemExit(1)
