"""Measure how much of the original winfail scripts WinfailScenarioRules can run.

Scans every WINFAIL*.txt record of the original PAK (read-only, outside the
repository), collects the action/condition token set of each level and diffs it
against the interpreter's support set, which is read from the constants in
game/sim/WinfailCompiler.gd (the interpreter's vocabulary) so there is a single source of truth. Writes the
compact resource-derived report content/generated/hsl/static/hsl01/
winfail_token_coverage.json; --check re-derives every per-level verdict from the
stored token sets and the current GDScript constants without touching the PAK.

Token presence is script structure only. "fully_supported" means every token of
the level is evaluated, applied or explicitly recorded by the interpreter; it does
not claim native handler equivalence.

Registry task winfail_coverage (family static, OriginalArchiveTask): tracked output
content/generated/hsl/static/hsl01/winfail_token_coverage.json; check validates the tracked report against the
current WinfailScenarioRules support set (no PAK), generate rescans hsl.pak. Bodies (main included) moved verbatim
from the former hsl_winfail_coverage.py.

Registry task winfail_token_table (family static, GeneratedFilesTask): renders docs/WINFAIL_TOKENS.md, the
author-readable vocabulary — one row per token of the four support constants: category, the argument shape
from ACTION.H (resource-derived), the one-line remake reading written as the trailing `# ...` comment on the
token's line in WinfailCompiler.gd, and the occurrence count across the 130 original scripts from the tracked
coverage report. check is byte-for-byte and fails first when a token lacks its comment or its ACTION.H define,
so a new token cannot enter the vocabulary undocumented. PASS line: WINFAIL_TOKEN_TABLE_PASS tokens=N ...
"""
from __future__ import annotations

import argparse
import hashlib
import json
import re
from pathlib import Path
from typing import Any

from hsltools.data import OriginalArchiveTask, printed_last_line
from hsltools.paths import ORIGINAL_PAK, ROOT
from hsltools.registry import CheckFailed, Context, GeneratedFilesTask, Task
from hsltools.sources.scripts import parse_text_metadata
from hsltools.sources.pak import find_decoded_paks_packages, read_paks_record_bytes

DEFAULT_PAK = ORIGINAL_PAK
DEFAULT_RULES = ROOT / "game/sim/WinfailCompiler.gd"
DEFAULT_OUTPUT = ROOT / "content/generated/hsl/static/hsl01/winfail_token_coverage.json"
ACTION_HEADER = ROOT / "content/imported/hsl/global/tables/ACTION.H"
TOKEN_TABLE = ROOT / "docs/WINFAIL_TOKENS.md"
SCHEMA = "hsl_winfail_token_coverage.v1"
RULES_SCHEMA = "hsl_winfail_script_rules.v1"
MAIN_LEVEL_LIMIT = 100
RECORD_PATTERN = re.compile(r"^@:\\data\\winfail(\d+)\.txt$", re.IGNORECASE)

# GDScript constants that together form the interpreter's support set. The
# first group is evaluated/applied; the second group is recorded only.
APPLIED_CONSTANTS = ("SUPPORTED_CONDITIONS", "APPLIED_ACTIONS")
RECORDED_CONSTANTS = ("WORLD_FLAG_ACTIONS", "PRESENTATION_ACTIONS")
DIAGNOSTIC_CONSTANTS = ("KNOWN_UNSUPPORTED_CONDITIONS",)


def parse_gd_string_array(source: str, name: str) -> list[str]:
    """Return the string literals of `const NAME := [ ... ]` in GDScript source."""
    # An empty array written on one line ("const X := []") must not swallow the next
    # constant's body: match the inline empty form first, then the multi-line form
    # whose closing bracket starts a line.
    match = re.search(r"^const %s\s*:=\s*\[([ \t]*)\]" % re.escape(name), source, re.M)
    if match is None:
        match = re.search(r"^const %s\s*:=\s*\[(.*?)^\]" % re.escape(name), source, re.S | re.M)
    if match is None:
        raise ValueError(f"constant {name} not found in the winfail vocabulary source")
    body = re.sub(r"#[^\n]*", "", match.group(1))
    return re.findall(r'"([^"]+)"', body)


def support_sets(rules_path: Path = DEFAULT_RULES) -> dict[str, list[str]]:
    source = rules_path.read_text(encoding="utf-8")
    schema = re.search(r'const RULES_SCHEMA\s*:=\s*"([^"]+)"', source)
    if schema is None or schema.group(1) != RULES_SCHEMA:
        raise ValueError(f"expected {RULES_SCHEMA} in {rules_path}")
    result: dict[str, list[str]] = {}
    for name in APPLIED_CONSTANTS + RECORDED_CONSTANTS + DIAGNOSTIC_CONSTANTS:
        values = parse_gd_string_array(source, name)
        if len(values) != len(set(values)):
            raise ValueError(f"duplicate tokens in {name}")
        result[name] = values
    return result


def applied_tokens(sets: dict[str, list[str]]) -> set[str]:
    return {token for name in APPLIED_CONSTANTS for token in sets[name]}


def recorded_tokens(sets: dict[str, list[str]]) -> set[str]:
    return {token for name in RECORDED_CONSTANTS for token in sets[name]}


def level_tokens(metadata: dict[str, Any]) -> tuple[dict[str, int], dict[str, int]]:
    """Token counts and win/fail/event section counts of one parsed winfail script."""
    tokens: dict[str, int] = {}
    sections: dict[str, int] = {}
    for block in metadata.get("section_blocks", []):
        if not isinstance(block, dict):
            continue
        kind = str(block.get("name", ""))
        sections[kind] = sections.get(kind, 0) + 1
        for action in block.get("actions", []):
            if not isinstance(action, dict):
                continue
            for command in action.get("chain", []):
                if not isinstance(command, dict):
                    continue
                name = str(command.get("name", ""))
                if name:
                    tokens[name] = tokens.get(name, 0) + 1
    return dict(sorted(tokens.items())), dict(sorted(sections.items()))


def classify(tokens: dict[str, int], sets: dict[str, list[str]]) -> dict[str, Any]:
    applied = applied_tokens(sets)
    recorded = recorded_tokens(sets)
    unsupported = sorted(token for token in tokens if token not in applied and token not in recorded)
    recorded_only = sorted(token for token in tokens if token in recorded)
    return {
        "unsupported_tokens": unsupported,
        "recorded_only_tokens": recorded_only,
        "fully_supported": not unsupported,
        "fully_applied": not unsupported and not recorded_only,
    }


def scan_pak(pak: Path) -> list[dict[str, Any]]:
    """Every winfail record of the PAK as {level, member, byte_length, sha256, tokens, section_counts}."""
    packages = find_decoded_paks_packages(pak)
    if not packages:
        raise ValueError(f"no PAKS container found at {pak}")
    result: list[dict[str, Any]] = []
    seen: dict[int, str] = {}
    for package in packages:
        for record in package["records"]:
            member = str(record["name"])
            match = RECORD_PATTERN.match(member)
            if match is None:
                continue
            level = int(match.group(1))
            if level in seen:
                raise ValueError(f"duplicate winfail record for level {level}: {seen[level]} and {member}")
            seen[level] = member
            data = read_paks_record_bytes(
                package["path"], record, data_end_offset=int(package["paks"]["candidate_index_offset"])
            )
            tokens, sections = level_tokens(parse_text_metadata(data))
            result.append(
                {
                    "level": level,
                    "member": member,
                    "byte_length": len(data),
                    "sha256": hashlib.sha256(data).hexdigest(),
                    "section_counts": sections,
                    "tokens": tokens,
                }
            )
    result.sort(key=lambda row: row["level"])
    return result


def build_report(levels: list[dict[str, Any]], sets: dict[str, list[str]], rules_path: Path = DEFAULT_RULES) -> dict[str, Any]:
    rows: dict[str, dict[str, Any]] = {}
    token_totals: dict[str, int] = {}
    blocking: dict[str, int] = {}
    main_count = main_supported = main_applied = all_supported = 0
    for entry in levels:
        level = int(entry["level"])
        tokens = {str(key): int(value) for key, value in entry["tokens"].items()}
        verdict = classify(tokens, sets)
        row = {
            "level": level,
            "member": str(entry["member"]),
            "byte_length": int(entry["byte_length"]),
            "sha256": str(entry["sha256"]),
            "main_level": level < MAIN_LEVEL_LIMIT,
            "section_counts": dict(entry.get("section_counts", {})),
            "tokens": dict(sorted(tokens.items())),
        }
        row.update(verdict)
        rows[f"{level:03d}"] = row
        for token, count in tokens.items():
            token_totals[token] = token_totals.get(token, 0) + count
        all_supported += int(verdict["fully_supported"])
        if level < MAIN_LEVEL_LIMIT:
            main_count += 1
            main_supported += int(verdict["fully_supported"])
            main_applied += int(verdict["fully_applied"])
            for token in verdict["unsupported_tokens"]:
                blocking[token] = blocking.get(token, 0) + 1
    ordered_blocking = dict(sorted(blocking.items(), key=lambda item: (-item[1], item[0])))
    return {
        "schema": SCHEMA,
        "evidence_tier": "resource-derived",
        "source_policy": "token names and counts per original winfail script; raw PAK records stay outside the repository",
        "support_source": rules_path.relative_to(ROOT).as_posix() if rules_path.is_relative_to(ROOT) else rules_path.name,
        "support_schema": RULES_SCHEMA,
        "support_sets": {name: list(sets[name]) for name in APPLIED_CONSTANTS + RECORDED_CONSTANTS + DIAGNOSTIC_CONSTANTS},
        "main_level_limit": MAIN_LEVEL_LIMIT,
        "levels": rows,
        "totals": {
            "file_count": len(rows),
            "main_level_count": main_count,
            "main_fully_supported": main_supported,
            "main_fully_applied": main_applied,
            "all_fully_supported": all_supported,
            "token_totals": dict(sorted(token_totals.items(), key=lambda item: (-item[1], item[0]))),
            "unsupported_token_main_level_counts": ordered_blocking,
        },
        "claim_limit": (
            "fully_supported: every token of the level is evaluated, applied or explicitly recorded by "
            "WinfailScenarioRules (recorded_only_tokens are presentation/town/big-map requests, not executed); "
            "fully_applied excludes recorded-only tokens. Token presence is script structure and says nothing "
            "about native handler timing or remake equivalence."
        ),
    }


def check(report: dict[str, Any], sets: dict[str, list[str]]) -> list[str]:
    """Errors when the tracked report disagrees with the current support set or itself."""
    errors: list[str] = []
    if report.get("schema") != SCHEMA:
        errors.append(f"schema mismatch: {report.get('schema')!r}")
        return errors
    if report.get("support_schema") != RULES_SCHEMA:
        errors.append(f"support_schema mismatch: {report.get('support_schema')!r}")
    stored_sets = report.get("support_sets", {})
    for name in APPLIED_CONSTANTS + RECORDED_CONSTANTS + DIAGNOSTIC_CONSTANTS:
        if list(stored_sets.get(name, [])) != list(sets[name]):
            errors.append(f"support set {name} differs from WinfailCompiler.gd; rebuild the report")
    levels = report.get("levels", {})
    if not isinstance(levels, dict) or not levels:
        errors.append("levels must be a non-empty object")
        return errors
    rebuilt = build_report(
        [
            {
                "level": row["level"],
                "member": row["member"],
                "byte_length": row["byte_length"],
                "sha256": row["sha256"],
                "section_counts": row.get("section_counts", {}),
                "tokens": row["tokens"],
            }
            for row in levels.values()
        ],
        sets,
    )
    for code, row in levels.items():
        expected = rebuilt["levels"].get(code)
        if expected is None:
            errors.append(f"level {code}: key does not match its level number")
            continue
        for field in ("unsupported_tokens", "recorded_only_tokens", "fully_supported", "fully_applied", "main_level"):
            if row.get(field) != expected[field]:
                errors.append(f"level {code}: {field} is stale (expected {expected[field]!r})")
    if report.get("totals") != rebuilt["totals"]:
        errors.append("totals are stale")
    if report.get("main_level_limit") != MAIN_LEVEL_LIMIT:
        errors.append("main_level_limit mismatch")
    return errors


def summary_line(prefix: str, report: dict[str, Any]) -> str:
    totals = report["totals"]
    return "{} files={} main_levels={} main_fully_supported={} main_fully_applied={} all_fully_supported={}".format(
        prefix,
        totals["file_count"],
        totals["main_level_count"],
        totals["main_fully_supported"],
        totals["main_fully_applied"],
        totals["all_fully_supported"],
    )


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--pak", type=Path, default=DEFAULT_PAK)
    parser.add_argument("--rules", type=Path, default=DEFAULT_RULES, help="WinfailCompiler.gd to read the support set from")
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    parser.add_argument("--check", action="store_true", help="validate the tracked report against the current support set without reading the PAK")
    args = parser.parse_args(argv)
    sets = support_sets(args.rules)
    if args.check:
        report = json.loads(args.output.read_text(encoding="utf-8"))
        errors = check(report, sets)
        if errors:
            for error in errors:
                print(f"WINFAIL_COVERAGE_CHECK_FAIL {error}")
            return 1
        print(summary_line("WINFAIL_COVERAGE_CHECK_PASS", report))
        return 0
    if not args.pak.is_file():
        parser.error(f"original PAK not found: {args.pak}")
    report = build_report(scan_pak(args.pak), sets, args.rules)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(summary_line("WINFAIL_COVERAGE_BUILD_PASS", report))
    return 0


# --- author-readable token table ---------------------------------------------------------

TOKEN_CATEGORIES = (
    ("SUPPORTED_CONDITIONS", "条件", "status 的前导条件链；全部成立才触发（WinfailConditions.condition_holds）"),
    ("APPLIED_ACTIONS", "动作", "结果链里改 loop 或写 PlayLoop 消费记录的 token（WinfailActions.apply_actions）"),
    ("WORLD_FLAG_ACTIONS", "世界旗标", "只记 winfail_runtime.pending_world_flags，交接时 WorldScriptActions 按 TownEventRules 读法执行"),
    ("PRESENTATION_ACTIONS", "演出", "只记 winfail_runtime.presentation_requests，由演出协调器消费；规则不等待、不走位、不播放"),
)
TOKEN_LINE = re.compile(r'^\t"(act\w+)",(?:[ \t]*#[ \t]*(.*?))?[ \t]*$', re.M)
ACTION_DEFINE = re.compile(r"^#define\s+(act\w+)\s+(\d+)\s*(?://\s*(.*?))?\s*$", re.M)


def parse_gd_token_meanings(source: str, name: str) -> dict[str, str]:
    """{token: trailing `# ...` comment} for every string line of `const NAME := [ ... ]`
    (empty string when the line carries no comment)."""
    match = re.search(r"^const %s\s*:=\s*\[(.*?)^\]" % re.escape(name), source, re.S | re.M)
    if match is None:
        return {}
    return {token: (comment or "").strip() for token, comment in TOKEN_LINE.findall(match.group(1))}


def action_header_shapes(path: Path = ACTION_HEADER) -> dict[str, tuple[int, str]]:
    """{token: (opcode, argument shape comment)} from the original ACTION.H defines."""
    text = path.read_text(encoding="utf-8", errors="replace")
    return {name: (int(code), (shape or "").strip()) for name, code, shape in ACTION_DEFINE.findall(text)}


def token_table_rows(rules_path: Path, shapes: dict[str, tuple[int, str]], totals: dict[str, int]) -> tuple[list[dict[str, Any]], list[str]]:
    """One row per vocabulary token in constant order plus the problems that block the table
    (a token without its one-line comment or without an ACTION.H define)."""
    source = rules_path.read_text(encoding="utf-8")
    sets = support_sets(rules_path)
    rows: list[dict[str, Any]] = []
    problems: list[str] = []
    for constant, category, _ in TOKEN_CATEGORIES:
        meanings = parse_gd_token_meanings(source, constant)
        for token in sets[constant]:
            meaning = meanings.get(token, "")
            if not meaning:
                problems.append(f"{constant}: {token} has no `# meaning` comment on its line in {rules_path.name}")
            if token not in shapes:
                problems.append(f"{constant}: {token} is not defined in ACTION.H")
            opcode, shape = shapes.get(token, (-1, ""))
            rows.append({"token": token, "constant": constant, "category": category, "opcode": opcode,
                         "args": shape, "meaning": meaning, "occurrences": int(totals.get(token, 0))})
    return rows, problems


def render_token_table(rows: list[dict[str, Any]], report: dict[str, Any]) -> str:
    totals = report["totals"]
    by_constant: dict[str, list[dict[str, Any]]] = {}
    for row in rows:
        by_constant.setdefault(row["constant"], []).append(row)
    lines = [
        "# winfail 脚本 token 表",
        "",
        "_由 `python3 tools/hsl.py generate winfail_token_table` 从 `game/sim/WinfailCompiler.gd` 的词表常量生成；"
        "`hsl check winfail_token_table` 在门禁内逐字节核对。不要手改本文件——改 token 行尾的 `# 语义` 注释后重生成。_",
        "",
        "每场战斗 seed 的 `scripts.winfail` 由 win／fail／event 三类 status 组成，每个 status 是**前导条件链**（全部成立才触发，"
        "触发后从武装列表移除）接**结果动作链**。本表列出解释器认识的全部 token：",
        "",
        "- **参数**：原版 `ACTION.H` 的形状注释（resource-derived；`[code][serial]` 指 `SID_*` actor token 与其序号）。",
        "- **语义**：重制解释器当前的读法（测试合同 `tests/run_winfail_rules_tests.gd`，不是原版等价声明；"
        "边界见 [winfail_claim_limits](evidence_packets/static_reverse/winfail_claim_limits.md)）。",
        f"- **出现**：原版 PAK 全部 {totals['file_count']} 个 winfail 脚本中的出现次数"
        "（[winfail_token_coverage.json](../content/generated/hsl/static/hsl01/winfail_token_coverage.json)）。",
        "",
        "不在本表的 token 会被编译为 `unsupported`：以它开头的 status 永不触发，结果链里遇到它记入 `unsupported_encountered` 后继续。"
        "模块分工见 [BATTLE_SYSTEMS](architecture/BATTLE_SYSTEMS.md#winfailscenariorulesgd)。",
        "",
    ]
    for constant, category, note in TOKEN_CATEGORIES:
        group = by_constant.get(constant, [])
        lines.append(f"## {category}（`{constant}`，{len(group)} 个）")
        lines.append("")
        lines.append(note + "。")
        lines.append("")
        lines.append("| token | 参数（ACTION.H） | 语义（重制读法） | 出现 |")
        lines.append("| --- | --- | --- | ---: |")
        for row in group:
            args = f"`{row['args']}`" if row["args"] else "—"
            lines.append(f"| `{row['token']}` | {args} | {row['meaning']} | {row['occurrences']} |")
        lines.append("")
    return "\n".join(lines).rstrip("\n") + "\n"


def token_table_summary(prefix: str, rows: list[dict[str, Any]]) -> str:
    counts = {constant: sum(row["constant"] == constant for row in rows) for constant, _, _ in TOKEN_CATEGORIES}
    return "{} tokens={} conditions={} applied={} world_flags={} presentation={}".format(
        prefix, len(rows), counts["SUPPORTED_CONDITIONS"], counts["APPLIED_ACTIONS"],
        counts["WORLD_FLAG_ACTIONS"], counts["PRESENTATION_ACTIONS"])


class WinfailTokenTableTask(GeneratedFilesTask):
    name = 'winfail_token_table'
    family = 'static'
    inputs = (DEFAULT_RULES.relative_to(ROOT).as_posix(), ACTION_HEADER.relative_to(ROOT).as_posix(),
              DEFAULT_OUTPUT.relative_to(ROOT).as_posix())
    outputs = (TOKEN_TABLE.relative_to(ROOT).as_posix(),)
    replaces = ()  # born as a registry task: no historical command to replace
    scripts = ('tools/hsltools/data/winfail_coverage.py',)

    def render(self, ctx: Context) -> dict[str, bytes]:
        report = json.loads((ctx.root / DEFAULT_OUTPUT.relative_to(ROOT)).read_text(encoding="utf-8"))
        rows, problems = token_table_rows(ctx.root / DEFAULT_RULES.relative_to(ROOT), action_header_shapes(ctx.root / ACTION_HEADER.relative_to(ROOT)),
                                          report["totals"]["token_totals"])
        if problems:
            raise CheckFailed("WINFAIL_TOKEN_TABLE_FAIL\n" + "\n".join(problems))
        self.rows = rows
        return {self.outputs[0]: render_token_table(rows, report).encode("utf-8")}

    def summary(self, rendered: dict[str, bytes], mode: str) -> str:
        return token_table_summary("WINFAIL_TOKEN_TABLE_PASS" if mode == 'check' else "WINFAIL_TOKEN_TABLE_WRITTEN", self.rows)


class WinfailCoverageTask(OriginalArchiveTask):
    name = 'winfail_coverage'
    family = 'static'
    inputs = (DEFAULT_RULES.relative_to(ROOT).as_posix(),)
    outputs = (DEFAULT_OUTPUT.relative_to(ROOT).as_posix(),)
    replaces = ('tools/hsl_winfail_coverage.py --check',)
    scripts = ('tools/hsltools/data/winfail_coverage.py',)

    def verify(self, ctx: Context) -> str:
        return printed_last_line(main, ['--check'])

    def rebuild(self, ctx: Context) -> None:
        printed_last_line(main, [])


def tasks() -> list[Task]:
    return [WinfailCoverageTask(), WinfailTokenTableTask()]


if __name__ == '__main__':
    raise SystemExit(main())
