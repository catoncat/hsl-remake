"""Machine-readable evidence packet headers: check them and render the generated index.

Every packet under docs/evidence_packets/{resource_inventory,runtime_observations,static_reverse}
(every *.md there, recursively) carries one header line directly under its H1 title:

    > evidence: static-derived; provisional: synthetic initialization · status: live · functions: 0x448840 · tools: hsl_native_stats_probe.py · updated: 2026-09-10

Fields are separated by " · " and appear in this order:

  evidence   one or more of the seven tiers, separated by "; ", each optionally scoped with
             ": <which part>": resource-derived / static-derived / runtime-measured /
             user-confirmed / user-hypothesis / provisional / negative-evidence
  status     live (a game/ module, Rules class or tests/ suite consumes it) | record-only |
             superseded: <path relative to the packet> (the replacement packet must exist)
  functions  optional; original hsl01.exe addresses 0x4xxxxx, lowercase, unique, ascending
  tools      optional; repro entry points, unique, sorted: file names under tools/ or tests/, or
             hsltools/<family>/<module>.py for a registry task module (run it with
             `python3 tools/hsl.py check <task>`; `hsl list` maps modules to task names)
  updated    YYYY-MM-DD

The header is the single source of truth. docs/KNOWLEDGE_INDEX.md carries a generated block
between <!-- evidence-index:start --> and <!-- evidence-index:end --> rendered from it; there is
deliberately no tracked index.json (nothing consumes one — use --json when a program needs it).

Registry task evidence_index (family evidence, GeneratedFilesTask): render() is
docs/KNOWLEDGE_INDEX.md with the generated block re-rendered from every packet header, so check
is byte-for-byte against the tracked document and generate rewrites it. The module command line
(`PYTHONPATH=tools python3 -m hsltools.evidence.index`) keeps the two modes the registry has no
verb for:

  --check   validate every header and confirm the generated block is current (== hsl check evidence_index)
  --write   rewrite the generated block in docs/KNOWLEDGE_INDEX.md (== hsl generate evidence_index)
  --json    print all parsed headers as JSON to stdout
  --lint    non-failing hints: functions missing from the function catalog, tools that do not
            exist, tier words used in a body that the header does not declare
"""
from __future__ import annotations

import argparse
import datetime as _dt
import json
import re
import sys
from pathlib import Path

from hsltools.registry import CheckFailed, Context, GeneratedFilesTask

ROOT = Path(__file__).resolve().parents[3]
PACKET_ROOT = Path("docs") / "evidence_packets"
PACKET_DIRS = ("resource_inventory", "runtime_observations", "static_reverse")
INDEX_DOC = Path("docs") / "KNOWLEDGE_INDEX.md"
FUNCTION_CATALOG = Path("content") / "generated" / "hsl" / "static" / "hsl01" / "function_catalog.json"
START_MARK = "<!-- evidence-index:start -->"
END_MARK = "<!-- evidence-index:end -->"

TIERS = (
    "resource-derived",
    "static-derived",
    "runtime-measured",
    "user-confirmed",
    "user-hypothesis",
    "provisional",
    "negative-evidence",
)
STATUSES = ("live", "record-only", "superseded")
FIELD_ORDER = ("evidence", "status", "functions", "tools", "updated")
REQUIRED_FIELDS = ("evidence", "status", "updated")
SEPARATOR = " · "
HEADER_PREFIX = "> evidence:"
ADDRESS = re.compile(r"^0x4[0-9a-f]{5}$")
TOOL_NAME = re.compile(r"^(?:hsltools/[a-z_]+/)?[A-Za-z0-9_.-]+\.(?:py|sh|gd|swift|c)$")
TIER_WORD = re.compile(r"(?<![\w-])(" + "|".join(TIERS) + r")(?![\w-])")


class HeaderError(ValueError):
    """A packet header is missing or malformed."""


def packet_paths(root: Path) -> list[Path]:
    """Every packet markdown file, as a path relative to root, sorted."""
    paths: list[Path] = []
    for directory in PACKET_DIRS:
        base = root / PACKET_ROOT / directory
        if base.is_dir():
            paths.extend(path.relative_to(root) for path in base.rglob("*.md") if path.is_file())
    return sorted(paths, key=lambda path: path.as_posix())


def split_header(text: str) -> tuple[str, int, str | None]:
    """Return (title, header_line_index, header_line) for a packet text.

    The header must be the first non-blank line after the H1; header_line is None when that
    line is not a header.
    """
    lines = text.splitlines()
    title_index = next((index for index, line in enumerate(lines) if line.startswith("# ")), None)
    if title_index is None:
        raise HeaderError("no H1 title")
    title = lines[title_index][2:].strip()
    for index in range(title_index + 1, len(lines)):
        if lines[index].strip():
            line = lines[index]
            return title, index, (line if line.startswith(HEADER_PREFIX) else None)
    return title, len(lines), None


def parse_evidence(value: str) -> list[dict[str, str | None]]:
    terms: list[dict[str, str | None]] = []
    seen: set[str] = set()
    for raw in value.split(";"):
        raw = raw.strip()
        if not raw:
            raise HeaderError("empty evidence term")
        tier, _, scope = raw.partition(":")
        tier = tier.strip()
        if tier not in TIERS:
            raise HeaderError(f"evidence tier {tier!r} is not one of {', '.join(TIERS)}")
        if tier in seen:
            raise HeaderError(f"evidence tier {tier!r} listed twice")
        seen.add(tier)
        scope = scope.strip()
        if ":" in scope:
            raise HeaderError(f"evidence scope for {tier!r} must not contain ':'")
        terms.append({"tier": tier, "scope": scope or None})
    return terms


def parse_status(value: str) -> tuple[str, str | None]:
    status, _, target = value.partition(":")
    status = status.strip()
    if status not in STATUSES:
        raise HeaderError(f"status {status!r} is not one of {', '.join(STATUSES)}")
    target = target.strip()
    if status == "superseded":
        if not target:
            raise HeaderError("superseded status needs ': <replacement packet path>'")
        return status, target
    if target:
        raise HeaderError(f"status {status!r} takes no argument")
    return status, None


def parse_list(value: str, field: str, pattern: re.Pattern[str], what: str) -> list[str]:
    items = [item.strip() for item in value.split(",")]
    if any(not item for item in items):
        raise HeaderError(f"{field}: empty entry")
    for item in items:
        if not pattern.match(item):
            raise HeaderError(f"{field}: {item!r} is not {what}")
    if items != sorted(set(items)):
        raise HeaderError(f"{field}: entries must be unique and sorted ascending")
    return items


def parse_header_line(line: str) -> dict:
    if not line.startswith(HEADER_PREFIX):
        raise HeaderError(f"header line must start with {HEADER_PREFIX!r}")
    body = line[1:].strip()
    fields: dict[str, str] = {}
    for part in body.split(SEPARATOR):
        key, sep, value = part.partition(":")
        key = key.strip()
        if not sep or key not in FIELD_ORDER:
            raise HeaderError(f"unknown header field {part.strip()!r}")
        if key in fields:
            raise HeaderError(f"header field {key!r} repeated")
        if not value.strip():
            raise HeaderError(f"header field {key!r} is empty")
        fields[key] = value.strip()
    for key in REQUIRED_FIELDS:
        if key not in fields:
            raise HeaderError(f"header field {key!r} is required")
    order = [key for key in FIELD_ORDER if key in fields]
    if list(fields) != order:
        raise HeaderError(f"header fields must be ordered {', '.join(FIELD_ORDER)}")
    status, superseded_by = parse_status(fields["status"])
    try:
        updated = _dt.date.fromisoformat(fields["updated"])
    except ValueError as error:
        raise HeaderError(f"updated: {error}") from None
    return {
        "evidence": parse_evidence(fields["evidence"]),
        "status": status,
        "superseded_by": superseded_by,
        "functions": parse_list(fields["functions"], "functions", ADDRESS, "an original EXE address 0x4xxxxx (lowercase)") if "functions" in fields else [],
        "tools": parse_list(fields["tools"], "tools", TOOL_NAME, "a tools/ or tests/ file name or hsltools/<family>/<module>.py") if "tools" in fields else [],
        "updated": updated.isoformat(),
    }


def format_header(header: dict) -> str:
    parts = ["evidence: " + "; ".join(term["tier"] + (f": {term['scope']}" if term.get("scope") else "") for term in header["evidence"])]
    parts.append("status: " + (f"superseded: {header['superseded_by']}" if header["status"] == "superseded" else header["status"]))
    if header.get("functions"):
        parts.append("functions: " + ", ".join(header["functions"]))
    if header.get("tools"):
        parts.append("tools: " + ", ".join(header["tools"]))
    parts.append("updated: " + header["updated"])
    return "> " + SEPARATOR.join(parts)


def parse_packet(root: Path, path: Path) -> dict:
    text = (root / path).read_text(encoding="utf-8")
    title, line_index, line = split_header(text)
    if line is None:
        raise HeaderError(f"missing header line under the title (expected {HEADER_PREFIX!r} ...)")
    header = parse_header_line(line)
    if header["superseded_by"] is not None:
        target = ((root / path).parent / header["superseded_by"]).resolve()
        try:
            relative = target.relative_to(root.resolve())
        except ValueError:
            raise HeaderError("superseded target leaves the repository") from None
        if not target.is_file() or relative not in set(packet_paths(root)):
            raise HeaderError(f"superseded target is not a packet: {header['superseded_by']}")
    header.update({
        "path": path.as_posix(),
        "directory": path.relative_to(PACKET_ROOT).parts[0],
        "title": title,
        "header_line": line_index + 1,
    })
    return header


def load_packets(root: Path) -> tuple[list[dict], list[str]]:
    packets: list[dict] = []
    errors: list[str] = []
    for path in packet_paths(root):
        try:
            packets.append(parse_packet(root, path))
        except (HeaderError, OSError, UnicodeError) as error:
            errors.append(f"{path.as_posix()}: {error}")
    return packets, errors


def _cell(text: str) -> str:
    return text.replace("|", "\\|").replace("\n", " ").strip() or "—"


def render_index(packets: list[dict]) -> str:
    """The generated block, markers included, with links relative to docs/."""
    lines = [START_MARK,
             f"_Generated from each packet's header line by `python3 tools/hsl.py generate evidence_index` "
             f"({len(packets)} packets; `hsl check evidence_index` runs in the gate). Edit the packet header, not this block._",
             ""]
    for directory in PACKET_DIRS:
        rows = [packet for packet in packets if packet["directory"] == directory]
        if not rows:
            continue
        lines.append(f"### {directory} ({len(rows)})")
        lines.append("")
        lines.append("| Packet | Evidence | Status | Functions | Tools |")
        lines.append("| --- | --- | --- | --- | --- |")
        for packet in rows:
            link = Path(packet["path"]).relative_to("docs").as_posix()
            evidence = "; ".join(term["tier"] + (f": {term['scope']}" if term.get("scope") else "") for term in packet["evidence"])
            status = packet["status"] if packet["status"] != "superseded" else f"superseded → {packet['superseded_by']}"
            functions = ", ".join(f"`{address}`" for address in packet["functions"])
            tools = ", ".join(f"`{tool}`" for tool in packet["tools"])
            lines.append(f"| [{_cell(packet['title'])}]({link}) | {_cell(evidence)} | {_cell(status)} | {_cell(functions)} | {_cell(tools)} |")
        lines.append("")
    lines.append(END_MARK)
    return "\n".join(lines)


def replace_block(document: str, block: str) -> str:
    start = document.find(START_MARK)
    end = document.find(END_MARK)
    if start < 0 or end < 0 or document.count(START_MARK) != 1 or document.count(END_MARK) != 1 or end < start:
        raise HeaderError(f"{INDEX_DOC.as_posix()} must contain exactly one {START_MARK} ... {END_MARK} block")
    return document[:start] + block + document[end + len(END_MARK):]


def lint(root: Path, packets: list[dict]) -> list[str]:
    hints: list[str] = []
    catalog_path = root / FUNCTION_CATALOG
    known: set[str] | None = None
    if catalog_path.is_file():
        known = {key.lower() for key in json.loads(catalog_path.read_text(encoding="utf-8")).get("functions", {})}
    for packet in packets:
        if known is not None:
            missing = [address for address in packet["functions"] if address not in known]
            if missing:
                hints.append(f"{packet['path']}: functions not in {FUNCTION_CATALOG.as_posix()}: {', '.join(missing)}")
        for tool in packet["tools"]:
            if not any((root / folder / tool).is_file() for folder in ("tools", "tests")):
                hints.append(f"{packet['path']}: tool not found under tools/ or tests/: {tool}")
        text = (root / packet["path"]).read_text(encoding="utf-8").splitlines()
        body = "\n".join(line for index, line in enumerate(text, 1) if index != packet["header_line"])
        declared = {term["tier"] for term in packet["evidence"]}
        undeclared = sorted({match.lower() for match in TIER_WORD.findall(body)} - declared)
        if undeclared:
            hints.append(f"{packet['path']}: body mentions tiers not in header: {', '.join(undeclared)}")
    return hints


class EvidenceIndexTask(GeneratedFilesTask):
    name = 'evidence_index'
    family = 'evidence'
    inputs = tuple((PACKET_ROOT / name).as_posix() + '/' for name in PACKET_DIRS)
    outputs = (INDEX_DOC.as_posix(),)
    replaces = ('tools/hsl_evidence_index.py --check',)
    scripts = ('tools/hsltools/evidence/index.py',)

    def render(self, ctx: Context) -> dict[str, bytes]:
        packets, errors = load_packets(ctx.root)
        if errors:
            raise CheckFailed("EVIDENCE_INDEX_FAIL\n" + "\n".join(errors))
        document = (ctx.root / INDEX_DOC).read_text(encoding="utf-8")
        try:
            updated = replace_block(document, render_index(packets))
        except HeaderError as error:
            raise CheckFailed(f"EVIDENCE_INDEX_FAIL\n{error}") from error
        self.packet_count = len(packets)
        return {INDEX_DOC.as_posix(): updated.encode("utf-8")}

    def check(self, ctx: Context) -> str:
        try:
            return super().check(ctx)
        except CheckFailed as error:
            if 'stale tracked output' in str(error):
                raise CheckFailed(f"EVIDENCE_INDEX_FAIL\n{INDEX_DOC.as_posix()}: generated block is stale; run python3 tools/hsl.py generate evidence_index") from error
            raise

    def summary(self, rendered: dict[str, bytes], mode: str) -> str:
        if mode == 'check':
            return f"EVIDENCE_INDEX_PASS packets={self.packet_count}"
        return f"EVIDENCE_INDEX_WRITTEN packets={self.packet_count} file={INDEX_DOC.as_posix()}"


def tasks() -> list[EvidenceIndexTask]:
    return [EvidenceIndexTask()]


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--root", type=Path, default=ROOT, help="repository root")
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--check", action="store_true")
    mode.add_argument("--write", action="store_true")
    mode.add_argument("--json", action="store_true")
    mode.add_argument("--lint", action="store_true")
    args = parser.parse_args(argv)
    root = args.root.resolve()

    packets, errors = load_packets(root)
    if errors:
        print("EVIDENCE_INDEX_FAIL\n" + "\n".join(errors), file=sys.stderr)
        return 1
    if args.json:
        json.dump(packets, sys.stdout, ensure_ascii=False, indent=1)
        sys.stdout.write("\n")
        return 0
    if args.lint:
        hints = lint(root, packets)
        print("\n".join(hints) if hints else "(no hints)")
        print(f"EVIDENCE_INDEX_LINT packets={len(packets)} hints={len(hints)}")
        return 0
    block = render_index(packets)
    index_path = root / INDEX_DOC
    document = index_path.read_text(encoding="utf-8")
    if args.write:
        try:
            updated = replace_block(document, block)
        except HeaderError as error:
            print(f"EVIDENCE_INDEX_FAIL\n{error}", file=sys.stderr)
            return 1
        index_path.write_text(updated, encoding="utf-8")
        print(f"EVIDENCE_INDEX_WRITTEN packets={len(packets)} file={INDEX_DOC.as_posix()}")
        return 0
    try:
        if replace_block(document, block) != document:
            print(f"EVIDENCE_INDEX_FAIL\n{INDEX_DOC.as_posix()}: generated block is stale; run python3 tools/hsl.py generate evidence_index", file=sys.stderr)
            return 1
    except HeaderError as error:
        print(f"EVIDENCE_INDEX_FAIL\n{error}", file=sys.stderr)
        return 1
    print(f"EVIDENCE_INDEX_PASS packets={len(packets)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
