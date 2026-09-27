"""Original-scope inventory versus remake coverage.

Counts what the original hsl.pak contains (levels, level scripts, global
table records) and what the remake campaign currently registers, so planning
can rank remaining work against the whole game instead of the current chapter.

The original-side numbers are resource-derived (record names and INI-style
section headers inside the PAK). The remake-side numbers are derived from the
tracked content/battles/campaign.json and the scenario files it references.
Nothing here establishes semantics for unimplemented levels or claims original
equivalence for implemented ones.

Usage:

    PYTHONPATH=tools python3 -m hsltools.data.scope_inventory --pak ~/.wine-hsl-original/drive_c/hsl
    PYTHONPATH=tools python3 -m hsltools.data.scope_inventory --check            # offline (== hsl check scope_inventory)
    PYTHONPATH=tools python3 -m hsltools.data.scope_inventory --check --rescan   # also re-read the PAK

Registry task scope_inventory (family static, OriginalArchiveTask): tracked output
content/generated/hsl/static/hsl01/scope_inventory.json; check validates it offline against campaign.json, generate
rescans the original hsl directory. Bodies moved verbatim from the former hsl_scope_inventory.py.
"""
from __future__ import annotations

import argparse
import json
import re
from pathlib import Path
from typing import Any

from hsltools.data import OriginalArchiveTask, printed_last_line
from hsltools.paths import ORIGINAL_ROOT, ROOT
from hsltools.registry import Context

DEFAULT_OUTPUT = ROOT / "content/generated/hsl/static/hsl01/scope_inventory.json"
DEFAULT_CAMPAIGN = ROOT / "content/battles/campaign.json"
DEFAULT_PAK_ROOT = ORIGINAL_ROOT
SCHEMA = "hsl_scope_inventory.v1"

TABLE_SECTIONS = {
    "MAGIC.TXT": "magic",
    "SPECIAL.TXT": "special",
    "ITEM.TXT": "item",
    "PLAYERS.TXT": "character",
    "TRACK.TXT": "track",
}
TOWNDEF_NAME = "TOWNDEF.TXT"
BIGMAP_NAME = "BIGMAP.DAT"

LEVEL_RE = re.compile(r"^(STORY|WINFAIL|LEVEL)0*(\d+)\.(TXT|BIN)$", re.IGNORECASE)
SECTION_RE = re.compile(r"^\s*\[([A-Za-z_][A-Za-z0-9_]*)\]")
MESSAGE_RE = re.compile(r"\bactMessage\b")


def classify_level(level: int) -> str:
    if level < 100:
        return "main"
    if 500 <= level < 600:
        return "battle_stub_500"
    if level >= 900:
        return "special_900"
    return "other"


def _live_lines(text: str):
    for line in text.splitlines():
        stripped = line.strip()
        if stripped and not stripped.startswith(";"):
            yield stripped


def count_sections(text: str, section: str) -> int:
    count = 0
    for stripped in _live_lines(text):
        match = SECTION_RE.match(stripped)
        if match and match.group(1).lower() == section.lower():
            count += 1
    return count


def count_sections_by_name(text: str) -> dict[str, int]:
    counts: dict[str, int] = {}
    for stripped in _live_lines(text):
        match = SECTION_RE.match(stripped)
        if match:
            key = match.group(1).lower()
            counts[key] = counts.get(key, 0) + 1
    return dict(sorted(counts.items()))


def count_messages(text: str) -> int:
    return sum(len(MESSAGE_RE.findall(stripped)) for stripped in _live_lines(text))


def _basename(name: str) -> str:
    return str(name).replace("/", "\\").split("\\")[-1].upper()


def scan_pak(pak_root: Path) -> dict[str, Any]:
    from hsltools.sources.pak import find_decoded_paks_packages, read_paks_record_bytes

    packages = find_decoded_paks_packages(pak_root)
    levels: dict[int, dict[str, Any]] = {}
    tables: dict[str, Any] = {}
    towndef_sections: dict[str, int] = {}
    bigmap_bytes = 0
    record_total = 0
    for package in packages:
        data_end = int(package["paks"]["candidate_index_offset"])

        def text_of(record: dict[str, Any]) -> str:
            return read_paks_record_bytes(package["path"], record, data_end_offset=data_end).decode("cp950", "replace")

        for record in package["records"]:
            record_total += 1
            base = _basename(record["name"])
            level_match = LEVEL_RE.match(base)
            if level_match:
                kind = level_match.group(1).upper()
                level = int(level_match.group(2))
                entry = levels.setdefault(
                    level,
                    {"level": level, "range": classify_level(level), "story": False, "winfail": False, "level_bin": False, "story_messages": 0},
                )
                if kind == "STORY":
                    entry["story"] = True
                    entry["story_messages"] = count_messages(text_of(record))
                elif kind == "WINFAIL":
                    entry["winfail"] = True
                elif kind == "LEVEL":
                    entry["level_bin"] = True
                continue
            if base in TABLE_SECTIONS:
                tables[base] = {"section": TABLE_SECTIONS[base], "records": count_sections(text_of(record), TABLE_SECTIONS[base])}
            elif base == TOWNDEF_NAME:
                towndef_sections = count_sections_by_name(text_of(record))
            elif base == BIGMAP_NAME:
                bigmap_bytes = int(record.get("length", 0) or 0)
    return {
        "record_total": record_total,
        "levels": levels,
        "tables": dict(sorted(tables.items())),
        "towndef_sections": towndef_sections,
        "bigmap_bytes": bigmap_bytes,
    }


def summarize_levels(levels: dict[int, dict[str, Any]]) -> dict[str, Any]:
    ranges: dict[str, dict[str, int]] = {}
    for entry in levels.values():
        bucket = ranges.setdefault(
            entry["range"],
            {"levels": 0, "battles": 0, "story_only": 0, "story_scripts": 0, "winfail_scripts": 0, "level_bins": 0, "story_messages": 0},
        )
        bucket["levels"] += 1
        bucket["story_scripts"] += int(entry["story"])
        bucket["winfail_scripts"] += int(entry["winfail"])
        bucket["level_bins"] += int(entry["level_bin"])
        bucket["story_messages"] += int(entry["story_messages"])
        if entry["winfail"]:
            bucket["battles"] += 1
        elif entry["story"]:
            bucket["story_only"] += 1
    return dict(sorted(ranges.items()))


def remake_coverage(campaign_path: Path, root: Path = ROOT) -> dict[str, Any]:
    campaign = json.loads(campaign_path.read_text(encoding="utf-8"))
    entries = []
    for key, battle in sorted(campaign.get("battles", {}).items(), key=lambda item: int(item[0])):
        scenario_ref = str(battle.get("scenario", ""))
        scenario: dict[str, Any] = {}
        if scenario_ref.startswith("res://") and scenario_ref.endswith(".json"):
            # Non-JSON registrations (the GameClear screen, a .tscn under "998") carry
            # no scenario metadata; they count as registered with their entry kind only.
            scenario_path = root / scenario_ref[len("res://"):]
            if scenario_path.exists():
                scenario = json.loads(scenario_path.read_text(encoding="utf-8"))
        entries.append(
            {
                "level": int(key),
                "title": battle.get("title"),
                "kind": battle.get("kind", "battle"),
                "scenario": scenario_ref,
                "scenario_id": scenario.get("id"),
                "status": scenario.get("status"),
                "level_kind": scenario.get("level_kind", "battle"),
            }
        )
    battle_scenarios = [e for e in entries if e["level_kind"] == "battle" and e["kind"] != "story"]
    previews = [e for e in entries if "preview" in str(e["status"] or "")]
    story_only = [e for e in entries if e["kind"] == "story" and e not in previews]
    return {
        "campaign": campaign_path.name,
        "registered_levels": [e["level"] for e in entries],
        "entries": entries,
        "counts": {
            "registered": len(entries),
            "battle_scenarios": len(battle_scenarios),
            "story_only_scenes": len(story_only),
            "opening_previews": len(previews),
        },
    }


def build(pak_root: Path, campaign_path: Path) -> dict[str, Any]:
    scan = scan_pak(pak_root)
    levels = scan["levels"]
    main_levels = {k: v for k, v in levels.items() if v["range"] == "main"}
    remake = remake_coverage(campaign_path)
    remade_main = [lvl for lvl in remake["registered_levels"] if lvl in main_levels]
    remade_battles = [e["level"] for e in remake["entries"] if e["level_kind"] == "battle" and e["kind"] != "story" and e["level"] in main_levels]
    remade_messages = sum(int(main_levels[lvl]["story_messages"]) for lvl in remade_main)
    total_messages = sum(int(v["story_messages"]) for v in main_levels.values())
    return {
        "schema": SCHEMA,
        "evidence_tier": "resource-derived",
        "claim": (
            "Counts only. Original-side numbers are record names and INI section headers read from the PAK; "
            "remake-side numbers come from the tracked campaign registry. No semantics for unimplemented levels "
            "and no original-equivalence claim for implemented ones follow from this file."
        ),
        "source": {"pak_root_basename": pak_root.name, "record_total": scan["record_total"]},
        "original": {
            "level_ranges": summarize_levels(levels),
            "levels": [levels[k] for k in sorted(levels)],
            "tables": scan["tables"],
            "towndef_sections": scan["towndef_sections"],
            "bigmap_dat_bytes": scan["bigmap_bytes"],
        },
        "remake": remake,
        "coverage": {
            "main_levels_total": len(main_levels),
            "main_levels_registered": len(remade_main),
            "main_battles_total": sum(1 for v in main_levels.values() if v["winfail"]),
            "main_battles_with_battle_scenario": len(remade_battles),
            "main_story_messages_total": total_messages,
            "main_story_messages_in_registered_levels": remade_messages,
            "note": "Registered means the level is reachable through campaign.json; opening previews and provisional scenarios count as registered, not as original-equivalent.",
        },
    }


def check(output: Path, pak_root: Path | None, campaign_path: Path) -> int:
    if not output.exists():
        print(f"SCOPE_INVENTORY_CHECK_FAIL missing={output}")
        return 1
    failures: list[str] = []
    data = json.loads(output.read_text(encoding="utf-8"))
    if data.get("schema") != SCHEMA:
        failures.append(f"schema={data.get('schema')}")
    if data.get("remake") != remake_coverage(campaign_path):
        failures.append("remake coverage differs from campaign.json / scenario files")
    coverage = data.get("coverage", {})
    main_levels = [lvl for lvl in data.get("original", {}).get("levels", []) if lvl.get("range") == "main"]
    if coverage.get("main_levels_total") != len(main_levels):
        failures.append("main_levels_total inconsistent with level list")
    if coverage.get("main_battles_total") != sum(1 for lvl in main_levels if lvl.get("winfail")):
        failures.append("main_battles_total inconsistent with level list")
    if pak_root is not None and pak_root.exists():
        if build(pak_root, campaign_path)["original"] != data.get("original"):
            failures.append("original-side counts differ from the PAK")
    if failures:
        print("SCOPE_INVENTORY_CHECK_FAIL " + "; ".join(failures))
        return 1
    print(
        "SCOPE_INVENTORY_CHECK_PASS "
        f"main_levels={coverage.get('main_levels_total')} main_battles={coverage.get('main_battles_total')} "
        f"registered={coverage.get('main_levels_registered')} battle_scenarios={coverage.get('main_battles_with_battle_scenario')}"
    )
    return 0


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--pak", type=Path, default=DEFAULT_PAK_ROOT, help="original hsl directory containing hsl.pak")
    parser.add_argument("--campaign", type=Path, default=DEFAULT_CAMPAIGN)
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    parser.add_argument("--check", action="store_true", help="validate the tracked output offline against campaign.json and its own totals")
    parser.add_argument("--rescan", action="store_true", help="with --check: also rescan the PAK and compare the original-side counts")
    args = parser.parse_args(argv)
    if args.check:
        return check(args.output, args.pak if args.rescan else None, args.campaign)
    if not args.pak.exists():
        print(f"SCOPE_INVENTORY_FAIL pak_missing={args.pak}")
        return 1
    data = build(args.pak, args.campaign)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    cov = data["coverage"]
    print(
        f"SCOPE_INVENTORY_BUILD_PASS output={args.output.relative_to(ROOT)} records={data['source']['record_total']} "
        f"main_levels={cov['main_levels_total']} main_battles={cov['main_battles_total']} registered={cov['main_levels_registered']}"
    )
    return 0


class ScopeInventoryTask(OriginalArchiveTask):
    name = 'scope_inventory'
    family = 'static'
    archive = ORIGINAL_ROOT
    inputs = (DEFAULT_CAMPAIGN.relative_to(ROOT).as_posix(), 'content/battles/')
    outputs = (DEFAULT_OUTPUT.relative_to(ROOT).as_posix(),)
    replaces = ('tools/hsl_scope_inventory.py --check',)
    scripts = ('tools/hsltools/data/scope_inventory.py',)

    def verify(self, ctx: Context) -> str:
        return printed_last_line(check, DEFAULT_OUTPUT, None, DEFAULT_CAMPAIGN)

    def rebuild(self, ctx: Context) -> None:
        printed_last_line(main, [])


def tasks() -> list[ScopeInventoryTask]:
    return [ScopeInventoryTask()]


if __name__ == '__main__':
    raise SystemExit(main())
