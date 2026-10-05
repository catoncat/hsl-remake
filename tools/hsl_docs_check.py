"""Check repository Markdown navigation without fetching URLs or reading raw archives.

Checks inline links/images, explicit reference links, and Markdown heading/HTML
anchors. Fenced/indented code and inline code examples are not navigation. Bare
paths in prose or code are deliberately not interpreted as links or live inputs.

Three content rules ride along:
- A superseded document (first line after its title a blockquote opening with 已取代; a
  directory's README.md so marked covers the directory) is kept only for the record: a live
  document may not point at it by link or code-style path unless that line says 已取代.
- A document whose file name contains 守则 (a standing rule set) carries no dates or commit ids.
- No document quotes the user (用户原话, 用户说「…」, 用户拍板 and the like in prose; code
  examples excluded, so a rule can name the phrases in code style): rules are written neutrally.
"""
from __future__ import annotations

import argparse
from collections import Counter
import html
import os
from pathlib import Path
import re
import subprocess
import sys
from urllib.parse import unquote, urlsplit

sys.path.insert(0, str(Path(__file__).resolve().parent))
from hsltools import original_content  # noqa: E402
from hsltools.checks.doc_tool_references import Superseded  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent
# Docs that tools/oss_export.sh leaves out of the public tree (its DROPPED_PREFIXES: process docs and the
# third-party TypeSafe mirror): a link to them from any exported document would break there, so only private
# docs may link private docs.
PRIVATE_DOCS = ('docs/internal/', 'docs/audits/', 'docs/external/typesafe/')
DESTINATION = r'(<[^>\n]+>|(?:[^()\s]|\\[()]|\([^()\n]*\))+)'
TITLE = r'''(?:\s+(?:"[^"\n]*"|'[^'\n]*'|\([^()\n]*\)))?'''
INLINE_LINK = re.compile(r'!?\[[^\]\n]*\]\(\s*' + DESTINATION + TITLE + r'\s*\)')
REFERENCE = re.compile(r'!?\[([^\]\n]*)\]\[([^\]\n]*)\]')
DEFINITION = re.compile(r'^ {0,3}\[([^\]]+)\]:\s*' + DESTINATION + TITLE + r'\s*$')
HEADING = re.compile(r'^ {0,3}#{1,6}\s+(.+?)(?:\s+#+)?\s*$')
HTML_ANCHOR = re.compile(r'''<(?:a|h[1-6])\b[^>]*\b(?:id|name)=["']([^"']+)["']''', re.I)
SUPERSEDED_WORD = '已取代'
CODE_SPAN = re.compile(r'(`+)(.+?)\1')
USER_QUOTE = re.compile(r'用[户戶]的?原[话話]|用[户戶][说說]\s*[「“"：:]|用[户戶]拍板')
GUIDE_DATE = re.compile(r'20\d\d\s*[-/.年]\s*\d{1,2}|(?<![\d.])(?:0[1-9]|1[0-2])-(?:0[1-9]|[12]\d|3[01])(?!\d)|\d{1,2}\s*月\s*\d{1,2}\s*日')
COMMIT_ID = re.compile(r'(?<![0-9A-Za-z_])(?=[0-9a-f]*[a-f])(?=[0-9a-f]*\d)[0-9a-f]{7,40}(?![0-9A-Za-z_])')


def prose_lines(text: str) -> list[tuple[int, str]]:
    """Keep line numbers for actionable diagnostics, excluding code blocks."""
    result = []
    fence = ""
    fence_length = 0
    for number, line in enumerate(text.splitlines(), 1):
        marker = re.match(r'^ {0,3}(`{3,}|~{3,})(.*)$', line)
        if fence:
            if marker and marker[1][0] == fence and len(marker[1]) >= fence_length and not marker[2].strip():
                fence = ""
            continue
        if marker:
            fence, fence_length = marker[1][0], len(marker[1])
        elif not line.startswith(("    ", "\t")):
            result.append((number, line))
    return result


def heading_anchors(text: str) -> set[str]:
    anchors: set[str] = set()
    counts: Counter[str] = Counter()
    lines = prose_lines(text)
    for index, (_, line) in enumerate(lines):
        anchors.update(HTML_ANCHOR.findall(line))
        heading = HEADING.match(line)
        title = heading[1] if heading else ""
        if not title and index and re.fullmatch(r' {0,3}(?:=+|-+)\s*', line):
            title = lines[index - 1][1].strip()
        if not title:
            continue
        title = re.sub(r'<[^>]*>', '', title)
        title = re.sub(r'!?\[([^\]]*)\]\([^)]*\)', r'\1', title)
        slug = re.sub(r'[^\w\s-]', '', html.unescape(title).lower())
        slug = re.sub(r'\s', '-', slug)
        # GFM disambiguates duplicate headings, including explicit suffixes.
        suffix = counts[slug]
        candidate = f"{slug}-{suffix}" if suffix else slug
        while candidate in anchors:
            suffix += 1
            candidate = f"{slug}-{suffix}"
        counts[slug] = suffix + 1
        anchors.add(candidate)
    return anchors


def navigation(text: str) -> tuple[list[tuple[int, str]], list[str]]:
    lines = [(number, re.sub(r'(`+).*?\1', '', line)) for number, line in prose_lines(text)]
    definitions = {}
    links = []
    errors = []
    for number, line in lines:
        definition = DEFINITION.match(line)
        if definition:
            definitions[' '.join(definition[1].lower().split())] = definition[2]
            links.append((number, definition[2]))
    for number, line in lines:
        if DEFINITION.match(line):
            continue
        links.extend((number, match[1]) for match in INLINE_LINK.finditer(line))
        for match in REFERENCE.finditer(line):
            label = ' '.join((match[2] or match[1]).lower().split())
            if label not in definitions:
                errors.append(f"{number}: undefined reference [{label}]")
    return links, errors


def markdown_files(root: Path) -> list[Path]:
    raw = subprocess.check_output(
        ["git", "ls-files", "-co", "--exclude-standard", "-z", "--", "*.md"], cwd=root,
    )
    paths = {root / os.fsdecode(item) for item in raw.split(b"\0") if item}
    # Sort by the POSIX string: WindowsPath ordering is case-insensitive, so plain sorted() differs by OS.
    return sorted((path for path in paths if path.is_file()), key=Path.as_posix)


def code_path(root: Path, source: Path, token: str) -> Path | None:
    """A path written in code style, resolved against the document's folder, then each folder above it
    (a folder's documents name its files from the folder: 剧本/draft/), then the root; None when nothing
    exists there."""
    token = token.strip('''"'()[]（）「」''').rstrip('.,;:。，；：、')
    if not token or token.startswith(('/', '~')) or '://' in token or any(c in token for c in '*$<>{}'):
        return None
    if '/' not in token and not token.endswith('.md'):
        return None
    folder = source.parent
    while True:
        candidate = folder / token
        if candidate.exists():
            return candidate.resolve()
        if folder == root or root not in folder.parents:
            return None
        folder = folder.parent


def rule_errors(root: Path, files: list[Path], superseded: Superseded) -> list[str]:
    """The content rules of the module docstring: superseded references by code-style path (links are
    checked in check_files), dates and commit ids in a 守则 document, quoting the user."""
    errors = []
    for path in files:
        source = path.resolve()
        label = source.relative_to(root).as_posix()
        text = source.read_text(encoding="utf-8")
        if '守则' in source.name:
            for number, line in enumerate(text.splitlines(), 1):
                found = GUIDE_DATE.search(line) or COMMIT_ID.search(line)
                if found:
                    errors.append(f"{label}:{number}: a 守则 document carries no date or commit id: {found[0]}")
        live = source not in superseded
        for number, line in prose_lines(text):
            quote = USER_QUOTE.search(CODE_SPAN.sub('', line))
            if quote:
                errors.append(f"{label}:{number}: quotes the user ({quote[0]}): write the rule neutrally")
            if not live or SUPERSEDED_WORD in line:
                continue
            for span in CODE_SPAN.finditer(line):
                for token in span[2].split():
                    target = code_path(root, source, token)
                    if target is not None and target in superseded:
                        errors.append(f"{label}:{number}: points at a superseded document (say 已取代 on the line, "
                                      f"or point at what replaced it): {token}")
    return errors


def check_files(root: Path, files: list[Path], absent: list[str] | None = None,
                superseded: Superseded | None = None) -> tuple[list[str], int]:
    """(errors, links). A link to an original-derived target that this checkout lacks but the
    original-derived manifest lists (a public checkout before the import, hsltools.original_content)
    is not an error: it is appended to `absent`. With `superseded`, a live document's link to a
    superseded one is an error unless its line says 已取代."""
    root = root.resolve()
    errors = []
    count = 0
    absent = [] if absent is None else absent
    anchors: dict[Path, set[str]] = {}
    for path in files:
        source = path.resolve()
        if not source.is_relative_to(root):
            errors.append(f"{path}: document leaves repository")
            continue
        label = source.relative_to(root).as_posix()
        try:
            text = source.read_text(encoding="utf-8")
            text_lines = text.splitlines()
            live = superseded is not None and source not in superseded
            links, reference_errors = navigation(text)
            errors.extend(f"{label}:{error}" for error in reference_errors)
            for line, raw in links:
                count += 1
                destination = html.unescape(raw.strip('<>'))
                parts = urlsplit(destination)
                if parts.scheme or parts.netloc:
                    continue
                path = unquote(parts.path)
                target = (root / path.lstrip('/') if path.startswith('/')
                          else source.parent / path if path else source).resolve()
                if not target.is_relative_to(root):
                    errors.append(f"{label}:{line}: link leaves repository: {raw}")
                elif (not label.startswith(PRIVATE_DOCS)
                      and target.relative_to(root).as_posix().startswith(PRIVATE_DOCS)):
                    errors.append(f"{label}:{line}: exported document links a private doc: {raw}")
                elif not target.exists() and original_content.stands_in(target.relative_to(root).as_posix()):
                    absent.append(f"{label}:{line}: {raw}")
                elif not target.exists():
                    errors.append(f"{label}:{line}: missing target: {raw}")
                elif live and target in superseded and SUPERSEDED_WORD not in text_lines[line - 1]:
                    errors.append(f"{label}:{line}: links a superseded document (say 已取代 on the line, "
                                  f"or link what replaced it): {raw}")
                elif parts.fragment and target.suffix.lower() == '.md':
                    if target not in anchors:
                        anchors[target] = heading_anchors(target.read_text(encoding="utf-8"))
                    if unquote(parts.fragment) not in anchors[target]:
                        errors.append(f"{label}:{line}: missing heading: {raw}")
        except (OSError, UnicodeError, ValueError) as error:
            errors.append(f"{label}: {error}")
    return errors, count


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', type=Path, default=ROOT, help='Git checkout to check')
    args = parser.parse_args()
    root = args.root.resolve()
    try:
        files = markdown_files(root)
        absent: list[str] = []
        superseded = Superseded(files)
        errors, count = check_files(root, files, absent, superseded)
        errors += rule_errors(root, files, superseded)
    except (OSError, subprocess.CalledProcessError) as error:
        print(f"DOC_LINKS_FAIL: {error}", file=sys.stderr)
        return 1
    if errors:
        print("DOC_LINKS_FAIL\n" + '\n'.join(errors), file=sys.stderr)
        return 1
    print(f"DOC_LINKS_PASS files={len(files)} links={count}" + (f" skipped_original_absent={len(absent)}" if absent else "")
          + (f" superseded={len(superseded)}" if len(superseded) else ""))
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
