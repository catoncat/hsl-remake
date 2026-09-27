"""No chapter folder in the engine: game/ reaches content through ContentPaths (the shared/ art
and tables every level reads) or through the scenario's `resources` (the per-level battleNNN/
folders a level names), never through a path spelling the chapter-1 import folder.

A sequel author reading engine code that loads `…/chapter01/…` would take a shared asset for
chapter-1-only; C1 moved the engine-read assets to content/imported/hsl/shared/ and this task
keeps the chapter name out of the engine.

Rule, over every file under game/ except Godot's `.uid`／`.import` sidecars:

  `chapter01` may appear only as the repository path of a term in a module's `## provenance:`
  header (`resource-derived content/imported/hsl/chapter01/battle052/opening_timeline.json`):
  such a term cites the chapter-1 import a rule was derived from — evidence, not a load path —
  and `hsl check provenance` already proves the cited file exists. Anywhere else (code,
  `res://` strings, scene and resource files, doc comments, a provenance note) the task fails
  and names file:line.

Registry task engine:chapter_paths (family checks, CheckTask, replaces=()).
PASS line: ENGINE_CHAPTER_PATHS_PASS files=N code_literals=0 provenance_citations=N.
"""
from __future__ import annotations

from pathlib import Path

from hsltools.checks import CheckTask
from hsltools.checks.provenance import DIMENSION_LINE, HEADER_LINE, TERM, split_terms
from hsltools.registry import CheckFailed, Context

ENGINE = Path("game")
CHAPTER = "chapter01"
SIDECARS = (".uid", ".import")


def engine_files(root: Path) -> list[Path]:
    """Every file under game/ but the Godot sidecars, repository-relative, sorted."""
    return sorted((path.relative_to(root) for path in (root / ENGINE).rglob("*")
                   if path.is_file() and path.suffix not in SIDECARS), key=lambda path: path.as_posix())


def provenance_lines(lines: list[str]) -> set[int]:
    """Indices of the `##   <dimension>: …` lines of the module's provenance header."""
    found: set[int] = set()
    for start, line in enumerate(lines):
        if line.rstrip() != HEADER_LINE:
            continue
        index = start + 1
        while index < len(lines) and DIMENSION_LINE.match(lines[index]):
            found.add(index)
            index += 1
    return found


def uncited_mentions(value: str) -> int:
    """How many `chapter01` mentions of a provenance value sit outside a term's path."""
    mentions = 0
    for raw in split_terms(value):
        match = TERM.match(raw.strip())
        path = (match["path"] or "") if match else ""
        mentions += raw.count(CHAPTER) - path.count(CHAPTER)
    return mentions


def scan(root: Path, files: list[Path]) -> tuple[list[str], int]:
    """(file:line issues, provenance citations naming the chapter folder)."""
    issues: list[str] = []
    citations = 0
    for relative in files:
        try:
            lines = (root / relative).read_text(encoding="utf-8").splitlines()
        except UnicodeDecodeError:
            continue  # binary art under game/ carries no path text
        header = provenance_lines(lines) if relative.suffix == ".gd" else set()
        for index, line in enumerate(lines):
            if CHAPTER not in line:
                continue
            if index in header and uncited_mentions(DIMENSION_LINE.match(line)[2]) == 0:
                citations += line.count(CHAPTER)
                continue
            issues.append(f"{relative.as_posix()}:{index + 1}: {line.strip()[:160]}")
    return issues, citations


def check(root: Path) -> str:
    files = engine_files(root)
    issues, citations = scan(root, files)
    if issues:
        raise ValueError(f"{len(issues)} engine line(s) name the {CHAPTER} folder — read shared assets through "
                         "game/sim/ContentPaths.gd and per-level ones through the scenario's `resources`:\n  "
                         + "\n  ".join(issues))
    return f"ENGINE_CHAPTER_PATHS_PASS files={len(files)} code_literals=0 provenance_citations={citations}"


class EngineChapterPathsTask(CheckTask):
    name = "engine:chapter_paths"
    family = "checks"
    inputs = ("game/",)
    replaces = ()  # born as a registry task: no historical command to replace
    scripts = ("tools/hsltools/checks/engine_chapter_paths.py", "tools/hsltools/checks/provenance.py")

    def check(self, ctx: Context) -> str:
        try:
            return check(ctx.root)
        except (ValueError, OSError) as error:
            raise CheckFailed(f"{self.name}: {error}") from error


def tasks() -> list[EngineChapterPathsTask]:
    return [EngineChapterPathsTask()]


if __name__ == "__main__":
    import sys
    from hsltools.paths import ROOT
    try:
        print(check(ROOT))
    except ValueError as error:
        print(f"ENGINE_CHAPTER_PATHS_FAIL {error}", file=sys.stderr)
        raise SystemExit(1)
