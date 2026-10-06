"""Provenance headers on every game/**/*.gd module: check them and render docs/PROVENANCE.md.

Every GDScript module under game/ declares, in its header comment, where each of its dimensions
came from — the vocabulary AGENTS.md「证据用语」uses for conclusions, plus two tags for
what the remake itself decided:

    ## provenance:
    ##   rules: static-derived docs/evidence_packets/static_reverse/original_growth_lifecycle.md
    ##   rules: static-derived content/generated/hsl/static/hsl01/core_logic.json
    ##   layout: runtime-reference docs/evidence_packets/runtime_observations/original_gameplay_reference/README.md#16
    ##   timing: remake-invented
    ##     (menu fade lengths chosen for the remake; a note too long for its line continues
    ##     on `##     ` lines, joined with one space)

  dimensions  rules (rule semantics), layout (positions, sizes, window art), strings (text),
              timing (sequencing, animation), audio — in this order; a dimension the module does
              not touch is omitted (it counts as n/a); at least one line names a source
  line        one term per line, `##   <dimension>: <term>`; a dimension repeats on as many lines
              as it has terms; a line starting `##     ` continues the term above (joined with one
              space); every line is at most MAX_LINE_CHARS (120) characters
  term        `<tag> [<path>[#<anchor>]] [(<note>)]`; the same tag may recur with different paths,
              never twice for one path
  rejected    the pre-09-27 form: a dimension line whose value is `n/a` (omit the dimension
              instead) or several terms on one line separated by ";" (one term per line)
  tag         resource-derived / static-derived / runtime-measured / user-confirmed /
              user-hypothesis / provisional / negative-evidence (AGENTS.md tiers), plus
              runtime-reference (recreated by eye from original frames, no measurement) and
              remake-invented (the remake's own choice; allowed, but it must be visible)
  path        repository-relative, must exist; required for resource-derived, static-derived,
              runtime-measured and runtime-reference (the derivation must be locatable);
              optional otherwise. `#anchor` is free text (a section or line), not validated.
  note        free text in parentheses; the generated document lists every provisional and
              remake-invented note, so put the doubt or the design decision there. A
              static-derived / resource-derived term is `tag path` alone: the addresses and
              readings belong in the evidence packet the path names.
  length      each term (tag, path and note) is at most MAX_TERM_CHARS (200) characters; a longer
              reading goes into the evidence packet (09-25 audit: 135,874 header bytes, about a third of
              them static／resource notes that repeated the packets, one term 1,498 characters).

The block sits in the module's header: after `extends` / `class_name` / the leading `##`
description, before the first signal, var, enum or func (preload consts may precede it).

Registry task provenance (family checks, GeneratedFilesTask): render() is docs/PROVENANCE.md
with the block between <!-- provenance:start --> and <!-- provenance:end --> re-rendered from
every module header (module matrix, the complete remake-invented list, provisional doubts,
tag x dimension counts); check fails when any module is missing a header or has an invalid one
(or the document lost its start/end markers); a stale generated block is only a warning
(PROVENANCE_WARN line, `stale_document=1` on the PASS line), because the document is re-rendered
by the lead's `tools/lane_merge.sh merge` and lanes no longer regenerate it (09-25 audit: two
commits existed only to refresh it); generate rewrites the document.
PASS line: PROVENANCE_PASS modules=N missing=0 invalid=0 [stale_document=1].
"""
from __future__ import annotations

import re
from collections import Counter
from pathlib import Path

from hsltools import original_content
from hsltools.registry import CheckFailed, Context, GeneratedFilesTask

MODULE_ROOT = Path("game")
DOC = Path("docs") / "PROVENANCE.md"
START_MARK = "<!-- provenance:start -->"
END_MARK = "<!-- provenance:end -->"

DIMENSIONS = ("rules", "layout", "strings", "timing", "audio")
EVIDENCE_TIERS = (
    "resource-derived",
    "static-derived",
    "runtime-measured",
    "user-confirmed",
    "user-hypothesis",
    "provisional",
    "negative-evidence",
)
REMAKE_TAGS = ("runtime-reference", "remake-invented")
TAGS = EVIDENCE_TIERS + REMAKE_TAGS
PATH_REQUIRED = frozenset({"resource-derived", "static-derived", "runtime-measured", "runtime-reference"})
NOT_APPLICABLE = "n/a"
MAX_TERM_CHARS = 200
MAX_LINE_CHARS = 120

GENERIC_NAMES = frozenset({"manifest.json", "README.md"})
HEADER_LINE = "## provenance:"
DIMENSION_LINE = re.compile(r"^##   ([a-z]+): (.*)$")
CONTINUATION_LINE = re.compile(r"^##     (\S.*)$")
TERM = re.compile(r"^(?P<tag>[a-z-]+)(?:\s+(?P<path>[^\s()]+))?(?:\s*\((?P<note>.*)\))?$")
# The header region ends at the first member definition; preload consts may precede the block.
BODY_START = re.compile(r"^(?:static\s+func|func|signal|var|enum|@export|@onready)\b")


class HeaderError(ValueError):
    """A module's provenance block is missing or malformed."""


class MissingHeader(HeaderError):
    """The module has no `## provenance:` block at all."""


def module_paths(root: Path) -> list[Path]:
    """Every game/**/*.gd module, as a path relative to root, sorted."""
    base = root / MODULE_ROOT
    return sorted((path.relative_to(root) for path in base.rglob("*.gd") if path.is_file()), key=lambda path: path.as_posix())


def parse_term(raw: str, root: Path) -> dict:
    if len(raw.strip()) > MAX_TERM_CHARS:
        raise HeaderError(f"term {raw.strip()[:60]!r}... is {len(raw.strip())} characters, over {MAX_TERM_CHARS}"
                          " — move the reading into the evidence packet")
    match = TERM.match(raw.strip())
    if match is None:
        raise HeaderError(f"term {raw.strip()!r} is not '<tag> [<path>[#anchor]] [(<note>)]'")
    tag = match["tag"]
    if tag not in TAGS:
        raise HeaderError(f"tag {tag!r} is not one of {', '.join(TAGS)}")
    location = match["path"]
    path = anchor = None
    if location is not None:
        path, _, anchor = location.partition("#")
        anchor = anchor or None
        if not path or path.startswith(("/", "res://")) or ".." in Path(path).parts:
            raise HeaderError(f"path {location!r} must be repository-relative")
        if not (root / path).exists() and not original_content.stands_in(path):
            raise HeaderError(f"path {path!r} does not exist")
    elif tag in PATH_REQUIRED:
        raise HeaderError(f"tag {tag!r} requires a repository path")
    note = (match["note"] or "").strip() or None
    if match["note"] is not None and note is None:
        raise HeaderError(f"term {raw.strip()!r} has an empty note")
    return {"tag": tag, "path": path, "anchor": anchor, "note": note}


def split_terms(value: str) -> list[str]:
    """Split on ';' outside parentheses, so a note may contain ';'."""
    terms: list[str] = []
    depth = 0
    current = ""
    for char in value:
        if char == "(":
            depth += 1
        elif char == ")":
            depth = max(0, depth - 1)
        if char == ";" and depth == 0:
            terms.append(current)
            current = ""
        else:
            current += char
    terms.append(current)
    return terms


def parse_value(value: str, root: Path) -> list[dict]:
    value = value.strip()
    if not value:
        raise HeaderError("empty value")
    if value == NOT_APPLICABLE:
        raise HeaderError("`n/a` is not written any more; omit the dimension instead")
    raw_terms = split_terms(value)
    if len(raw_terms) > 1:
        raise HeaderError("one term per line; put each further term on its own `##   <dimension>:` line")
    terms = [parse_term(raw, root) for raw in raw_terms]
    keys = [(term["tag"], term["path"]) for term in terms]
    if len(keys) != len(set(keys)):
        raise HeaderError(f"tag listed twice for the same path in {value!r}")
    return terms


def parse_module(root: Path, path: Path) -> dict:
    """{path, dimensions: {dim: [term...]}} for one module; [] for n/a."""
    lines = (root / path).read_text(encoding="utf-8").splitlines()
    starts = [index for index, line in enumerate(lines) if line.rstrip() == HEADER_LINE]
    if not starts:
        raise MissingHeader(f"no {HEADER_LINE!r} block")
    if len(starts) > 1:
        raise HeaderError(f"{HEADER_LINE!r} appears {len(starts)} times")
    start = starts[0]
    body_start = next((index for index, line in enumerate(lines) if BODY_START.match(line)), len(lines))
    if start > body_start:
        raise HeaderError(f"{HEADER_LINE!r} at line {start + 1} must precede the first member (line {body_start + 1})")
    entries: list[list] = []  # [first line index, dimension, value, line indices]
    index = start + 1
    while index < len(lines):
        if match := DIMENSION_LINE.match(lines[index]):
            entries.append([index, match[1], match[2], [index]])
        elif entries and (match := CONTINUATION_LINE.match(lines[index])):
            entries[-1][2] += " " + match[1]
            entries[-1][3].append(index)
        else:
            break
        index += 1
    dimensions: dict[str, list[dict]] = {name: [] for name in DIMENSIONS}
    seen: list[str] = []
    for first, name, value, indices in entries:
        if name not in DIMENSIONS:
            raise HeaderError(f"line {first + 1}: dimension {name!r} is not one of {', '.join(DIMENSIONS)}")
        if seen and name != seen[-1] and (name in seen or DIMENSIONS.index(name) < DIMENSIONS.index(seen[-1])):
            raise HeaderError(f"line {first + 1}: dimensions must be {', '.join(DIMENSIONS)} in that order, "
                              f"each dimension's lines together; {name!r} comes after {seen[-1]!r}")
        if not seen or seen[-1] != name:
            seen.append(name)
        for line_index in indices:
            if len(lines[line_index]) > MAX_LINE_CHARS:
                raise HeaderError(f"line {line_index + 1}: {len(lines[line_index])} characters, over {MAX_LINE_CHARS}"
                                  " — continue the note on a `##     ` line")
        try:
            terms = parse_value(value, root)
        except HeaderError as error:
            raise HeaderError(f"line {first + 1} ({name}): {error}") from None
        for term in terms:
            if any((known["tag"], known["path"]) == (term["tag"], term["path"]) for known in dimensions[name]):
                raise HeaderError(f"line {first + 1} ({name}): tag listed twice for the same path")
            dimensions[name].append(term)
    if not entries:
        raise HeaderError(f"no dimension line under {HEADER_LINE!r}")
    if all(not terms for terms in dimensions.values()):
        raise HeaderError("every dimension is n/a; at least one must name a source")
    return {"path": path.as_posix(), "dimensions": dimensions}


def load_modules(root: Path) -> tuple[list[dict], list[str], list[str]]:
    """(parsed modules, missing-header paths, invalid-header messages)."""
    modules: list[dict] = []
    missing: list[str] = []
    invalid: list[str] = []
    for path in module_paths(root):
        try:
            modules.append(parse_module(root, path))
        except MissingHeader:
            missing.append(path.as_posix())
        except (HeaderError, OSError, UnicodeError) as error:
            invalid.append(f"{path.as_posix()}: {error}")
    return modules, missing, invalid


def _cell(text: str) -> str:
    return text.replace("|", "\\|").replace("\n", " ").strip() or "—"


def _link(path: str, anchor: str | None) -> str:
    """A link from docs/ to a repository path; the anchor is shown, not linked (docs check)."""
    target = Path("..") / path
    name = Path(path).name
    if name in GENERIC_NAMES:  # manifest.json / README.md alone would not say which one
        name = Path(path).parent.name + "/" + name
    return f"[{name}]({target.as_posix()})" + (f" `#{anchor}`" if anchor else "")


def _term_text(term: dict, with_note: bool = True) -> str:
    text = term["tag"]
    if term["path"]:
        text += " " + _link(term["path"], term["anchor"])
    if with_note and term["note"]:
        text += f" _({term['note']})_"
    return text


def _module_link(path: str) -> str:
    return f"[{Path(path).stem}]({(Path('..') / path).as_posix()})"


def _group(path: str) -> str:
    return Path(path).parent.as_posix()


def render_block(modules: list[dict]) -> str:
    """The generated block, markers included, with links relative to docs/."""
    invented = [(module["path"], dim, term) for module in modules for dim in DIMENSIONS
                for term in module["dimensions"][dim] if term["tag"] == "remake-invented"]
    doubts = [(module["path"], dim, term) for module in modules for dim in DIMENSIONS
              for term in module["dimensions"][dim] if term["tag"] == "provisional"]
    counts: Counter[tuple[str, str]] = Counter()
    for module in modules:
        for dim in DIMENSIONS:
            for term in module["dimensions"][dim]:
                counts[(term["tag"], dim)] += 1
    lines = [START_MARK,
             f"_Generated from each module's `## provenance:` block by `python3 tools/hsl.py generate provenance` "
             f"({len(modules)} modules, {len(invented)} remake-invented cells, {len(doubts)} provisional cells; "
             f"`hsl check provenance` runs in the gate). Edit the module header, not this block._",
             ""]
    lines.append(f"### 模块矩阵 ({len(modules)})")
    lines.append("")
    for group in sorted({_group(module["path"]) for module in modules}):
        rows = [module for module in modules if _group(module["path"]) == group]
        lines.append(f"#### {group} ({len(rows)})")
        lines.append("")
        lines.append("| Module | " + " | ".join(DIMENSIONS) + " |")
        lines.append("| --- |" + " --- |" * len(DIMENSIONS))
        for module in rows:
            cells = [_module_link(module["path"])]
            for dim in DIMENSIONS:
                terms = module["dimensions"][dim]
                cells.append(_cell("; ".join(_term_text(term, with_note=False) for term in terms)) if terms else NOT_APPLICABLE)
            lines.append("| " + " | ".join(cells) + " |")
        lines.append("")
    lines.append(f"### remake-invented 清单 ({len(invented)})")
    lines.append("")
    lines.append("每一格都是重制自己决定、原版没有对应证据的内容；用户允许改善，但必须在这里可见。")
    lines.append("")
    lines.append("| Module | Dimension | Note |")
    lines.append("| --- | --- | --- |")
    for path, dim, term in invented:
        reference = f" {_link(term['path'], term['anchor'])}" if term["path"] else ""
        lines.append(f"| {_module_link(path)} | {dim} | {_cell((term['note'] or '') + reference)} |")
    lines.append("")
    lines.append(f"### provisional 疑点 ({len(doubts)})")
    lines.append("")
    lines.append("暂定读法，等待更强证据替换；note 写替换点或疑点。")
    lines.append("")
    lines.append("| Module | Dimension | Reference | Note |")
    lines.append("| --- | --- | --- | --- |")
    for path, dim, term in doubts:
        reference = _link(term["path"], term["anchor"]) if term["path"] else "—"
        lines.append(f"| {_module_link(path)} | {dim} | {reference} | {_cell(term['note'] or '')} |")
    lines.append("")
    lines.append("### 计数（标签 × 维度）")
    lines.append("")
    lines.append("| Tag | " + " | ".join(DIMENSIONS) + " | total |")
    lines.append("| --- |" + " --- |" * (len(DIMENSIONS) + 1))
    for tag in TAGS:
        row = [counts[(tag, dim)] for dim in DIMENSIONS]
        lines.append(f"| {tag} | " + " | ".join(str(value) for value in row) + f" | {sum(row)} |")
    na = [sum(1 for module in modules if not module["dimensions"][dim]) for dim in DIMENSIONS]
    lines.append(f"| {NOT_APPLICABLE} | " + " | ".join(str(value) for value in na) + f" | {sum(na)} |")
    lines.append("")
    lines.append(END_MARK)
    return "\n".join(lines)


def replace_block(document: str, block: str) -> str:
    start = document.find(START_MARK)
    end = document.find(END_MARK)
    if start < 0 or end < 0 or document.count(START_MARK) != 1 or document.count(END_MARK) != 1 or end < start:
        raise HeaderError(f"{DOC.as_posix()} must contain exactly one {START_MARK} ... {END_MARK} block")
    return document[:start] + block + document[end + len(END_MARK):]


def summary_counts(modules: list[dict], missing: list[str], invalid: list[str], verdict: str) -> str:
    total = len(modules) + len(missing) + len(invalid)
    return f"PROVENANCE_{verdict} modules={total} missing={len(missing)} invalid={len(invalid)}"


class ProvenanceTask(GeneratedFilesTask):
    name = 'provenance'
    family = 'checks'
    inputs = (MODULE_ROOT.as_posix() + '/', DOC.as_posix())
    outputs = (DOC.as_posix(),)
    replaces = ()  # born as a registry task: no historical command to replace
    scripts = ('tools/hsltools/checks/provenance.py',)

    def render(self, ctx: Context) -> dict[str, bytes]:
        modules, missing, invalid = load_modules(ctx.root)
        if missing or invalid:
            details = [f"{path}: missing {HEADER_LINE!r} block" for path in missing] + invalid
            raise CheckFailed(summary_counts(modules, missing, invalid, 'FAIL') + "\n" + "\n".join(details))
        document = (ctx.root / DOC).read_text(encoding="utf-8")
        try:
            updated = replace_block(document, render_block(modules))
        except HeaderError as error:
            raise CheckFailed(f"PROVENANCE_FAIL\n{error}") from error
        self.module_count = len(modules)
        return {DOC.as_posix(): updated.encode("utf-8")}

    def check(self, ctx: Context) -> str:
        rendered = self.render(ctx)
        line = self.summary(rendered, 'check')
        if (ctx.root / DOC).read_bytes() != rendered[DOC.as_posix()]:
            print(f"PROVENANCE_WARN {DOC.as_posix()}: generated block is stale (advisory; tools/lane_merge.sh merge "
                  "re-renders it, python3 tools/hsl.py generate provenance does it now)")
            line += " stale_document=1"
        return line

    def summary(self, rendered: dict[str, bytes], mode: str) -> str:
        if mode == 'check':
            return f"PROVENANCE_PASS modules={self.module_count} missing=0 invalid=0"
        return f"PROVENANCE_WRITTEN modules={self.module_count} file={DOC.as_posix()}"


def tasks() -> list[ProvenanceTask]:
    return [ProvenanceTask()]
