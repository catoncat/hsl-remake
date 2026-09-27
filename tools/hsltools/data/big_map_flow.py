"""Extract every big-map / town flow write of the original STORY and WINFAIL scripts.

Reads the original PAK (read-only, outside the repository) and collects, per
script and section, the commands that move the campaign between levels and the
big map: actSetNextPlayLevelEvent, actBMSetPointEvent(NotVisit),
actBMSetPointEncounterRatio, actBMSet/ClearPointFlag, actBMSet/ClearTrackFlag,
actBMSetPointMode, actBMSetTrackMode, actBMSetShowTrackPoint, actSetBMWalkToPoint,
actSetBMWalkerPlayerID, actSetTownExecEvent, actSetTownExitExecEvent, actAddTE and
actDeleteTE. Symbols are resolved from the tracked extras.h / TYPE.H readings in
content/imported/hsl/global/world_map/towndef.json (symbols: gameBigMapLevel = 49,
town_* ids) and world_map.json (bmpm* flag bits). Writes content/generated/hsl/static/hsl01/big_map_flow.json;
--check re-derives the summary tables from the stored commands without the PAK.

The derived readings are script conventions, not the EXE handler:
  * actSetNextPlayLevelEvent(level, event): 'event' is the level whose script set
    runs next (story-only levels 55/56/62/63 have their own LEVEL bins), and
    event == gameBigMapLevel returns to the big map standing at point 'level'
    (STORY056 "2,gameBigMapLevel" after WINFAIL002 "2,55" -> STORY055 "2,56").
  * actBMSetPointEvent(point, event, flag): the level a point opens on arrival
    with its marker type; event 0 with bmpmTown is a plain town, 5xx with
    bmpmVisit a random encounter gated by actBMSetPointEncounterRatio.
  * Main-range levels sit at the big-map point of the same id (every
    "N,gameBigMapLevel" return and every "N,5xx,bmpmVisit" post-clear write use
    the cleared level's own id); a Battle/General point without a scripted event
    therefore opens level N by default -- provisional until the arrival handler
    is located in the EXE.

Registry task big_map_flow (family static, OriginalArchiveTask): tracked output
content/generated/hsl/static/hsl01/big_map_flow.json; check re-derives the summary tables from the tracked report
(no PAK), generate rescans hsl.pak. Bodies moved verbatim from the former hsl_big_map_flow.py.
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
from hsltools.registry import Context
from hsltools.sources.scripts import parse_text_metadata
from hsltools.sources.pak import find_decoded_paks_packages, read_paks_record_bytes

DEFAULT_PAK = ORIGINAL_PAK
DEFAULT_OUTPUT = ROOT / "content/generated/hsl/static/hsl01/big_map_flow.json"
WORLD_MAP = ROOT / "content/imported/hsl/global/world_map/world_map.json"
TOWNDEF = ROOT / "content/imported/hsl/global/world_map/towndef.json"
SCHEMA = "hsl_big_map_flow.v1"
MAIN_LEVEL_LIMIT = 100
BATTLE_LEVEL_LIMIT = 48
ENCOUNTER_LEVEL_BASE = 500
RECORD_PATTERN = re.compile(r"^@:\\data\\(story|winfail)(\d+)\.txt$", re.IGNORECASE)
FLOW_COMMANDS = (
    "actSetNextPlayLevelEvent",
    "actBMSetPointEvent", "actBMSetPointEventNotVisit", "actBMSetPointEncounterRatio",
    "actBMSetPointFlag", "actBMClearPointFlag", "actBMSetTrackFlag", "actBMClearTrackFlag",
    "actBMSetPointMode", "actBMSetTrackMode", "actBMSetShowTrackPoint",
    "actSetBMWalkToPoint", "actSetBMWalkerPlayerID",
    "actSetTownExecEvent", "actSetTownExitExecEvent", "actAddTE", "actDeleteTE",
)
POINT_EVENT_COMMANDS = ("actBMSetPointEvent", "actBMSetPointEventNotVisit")


def symbols(world_map_path: Path = WORLD_MAP, towndef_path: Path = TOWNDEF) -> dict[str, int]:
    """gameBigMapLevel, town_* ids and the bmpm flag bits as the tracked readings record them."""
    table: dict[str, int] = {}
    towndef = json.loads(towndef_path.read_text(encoding="utf-8"))
    for name, value in towndef.get("symbols", {}).items():
        table[str(name)] = int(value, 16) if isinstance(value, str) else int(value)
    world_map = json.loads(world_map_path.read_text(encoding="utf-8"))
    for name, value in world_map.get("big_map_mode_constants", {}).items():
        table[str(name)] = int(value)
    for name, value in world_map.get("flag_bits", {}).items():
        table[str(name)] = int(value, 16) if isinstance(value, str) else int(value)
    if "gameBigMapLevel" not in table:
        raise ValueError(f"gameBigMapLevel missing from {towndef_path}")
    return table


def resolve(value: str, table: dict[str, int]) -> int | None:
    text = str(value).strip()
    if text in table:
        return table[text]
    try:
        return int(text, 0)
    except ValueError:
        return None


def script_commands(metadata: dict[str, Any]) -> list[dict[str, Any]]:
    """Flow commands of one parsed script in file order, tagged with their section."""
    result: list[dict[str, Any]] = []
    order = 0
    for block in metadata.get("section_blocks", []):
        if not isinstance(block, dict):
            continue
        section = str(block.get("name", ""))
        for action in block.get("actions", []):
            if not isinstance(action, dict):
                continue
            for command in action.get("chain", []):
                if not isinstance(command, dict):
                    continue
                name = str(command.get("name", ""))
                if name in FLOW_COMMANDS:
                    result.append({"order": order, "section": section, "name": name, "args": [str(arg) for arg in command.get("args", [])]})
                    order += 1
    return result


def scan_pak(pak: Path) -> list[dict[str, Any]]:
    packages = find_decoded_paks_packages(pak)
    if not packages:
        raise ValueError(f"no PAKS container found at {pak}")
    scripts: list[dict[str, Any]] = []
    for package in packages:
        for record in package["records"]:
            member = str(record["name"])
            match = RECORD_PATTERN.match(member)
            if match is None:
                continue
            data = read_paks_record_bytes(package["path"], record, data_end_offset=int(package["paks"]["candidate_index_offset"]))
            commands = script_commands(parse_text_metadata(data))
            if not commands:
                continue
            scripts.append({
                "kind": match.group(1).lower(),
                "level": int(match.group(2)),
                "member": member,
                "sha256": hashlib.sha256(data).hexdigest(),
                "commands": commands,
            })
    scripts.sort(key=lambda entry: (entry["level"], entry["kind"]))
    return scripts


def derive(scripts: list[dict[str, Any]], table: dict[str, int]) -> dict[str, Any]:
    big_map = table["gameBigMapLevel"]
    next_events: list[dict[str, Any]] = []
    point_writes: list[dict[str, Any]] = []
    return_points: dict[str, int] = {}
    for script in scripts:
        for command in script["commands"]:
            base = {"kind": script["kind"], "level": script["level"], "section": command["section"]}
            if command["name"] == "actSetNextPlayLevelEvent" and len(command["args"]) >= 2:
                level_arg = resolve(command["args"][0], table)
                event_arg = resolve(command["args"][1], table)
                to_big_map = event_arg == big_map
                next_events.append({**base, "level_arg": level_arg, "event_arg": event_arg, "event_symbol": command["args"][1], "to_big_map": to_big_map})
                if to_big_map and level_arg is not None and script["level"] < MAIN_LEVEL_LIMIT:
                    return_points.setdefault(str(script["level"]), level_arg)
            elif command["name"] in POINT_EVENT_COMMANDS and len(command["args"]) >= 2:
                flag = command["args"][2] if len(command["args"]) > 2 else ""
                point_writes.append({**base, "command": command["name"], "point": resolve(command["args"][0], table), "event": resolve(command["args"][1], table), "flag": flag})
    # Main-range battles (< 48) return to the point of their own id; story-only
    # levels (5x-7x) and 80 return to the point of the battle they follow.
    battle_returns = {level: point for level, point in return_points.items() if int(level) < BATTLE_LEVEL_LIMIT}
    same_id_returns = sum(1 for level, point in battle_returns.items() if int(level) == point)
    # Encounter levels (5xx) return to the point a script assigned them to.
    assigned_points = {w["event"]: w["point"] for w in point_writes if (w["event"] or 0) >= ENCOUNTER_LEVEL_BASE}
    encounter_returns = [e for e in next_events if e["level"] >= ENCOUNTER_LEVEL_BASE and e["to_big_map"] and e["level"] in assigned_points]
    encounter_matching = sum(1 for e in encounter_returns if assigned_points[e["level"]] == e["level_arg"])
    return {
        "next_level_events": next_events,
        "point_event_writes": point_writes,
        "level_return_points": dict(sorted(return_points.items(), key=lambda item: int(item[0]))),
        "battle_return_point_equals_level": {"same": same_id_returns, "total": len(battle_returns)},
        "encounter_return_matches_assigned_point": {"same": encounter_matching, "total": len(encounter_returns)},
        "post_clear_visit_writes": sorted({w["level"] for w in point_writes if w["kind"] == "winfail" and w["point"] == w["level"] and w["flag"] == "bmpmVisit" and (w["event"] or 0) > 0}),
    }


def build_report(scripts: list[dict[str, Any]], table: dict[str, int]) -> dict[str, Any]:
    derived = derive(scripts, table)
    return {
        "schema": SCHEMA,
        "evidence_tier": "resource-derived",
        "claim": "Every big-map / town flow command of the original STORY and WINFAIL scripts with the symbol reading of world_map.json; the derived readings are script conventions (see tool docstring), not the EXE arrival or next-level handler.",
        "source_policy": "command names and arguments only; raw PAK records stay outside the repository",
        "symbols": {name: table[name] for name in sorted(table)},
        "flow_commands": list(FLOW_COMMANDS),
        "scripts": scripts,
        **derived,
        "counts": {
            "scripts": len(scripts),
            "commands": sum(len(script["commands"]) for script in scripts),
            "next_level_events": len(derived["next_level_events"]),
            "to_big_map": sum(1 for event in derived["next_level_events"] if event["to_big_map"]),
            "point_event_writes": len(derived["point_event_writes"]),
        },
        "unresolved_semantics": [
            "The EXE big-map arrival handler is not located: whether a Battle/General point without a scripted event opens level N by default is inferred from the same-id convention (level_return_points, post_clear_visit_writes), not proven.",
            "actBMSetPointEncounterRatio units (percent assumed) and the encounter roll are unproven.",
            "How bmpmGeneral differs from bmpmBattle at arrival (marker sprite only, or a different entry path) is unproven.",
            "Encounter levels come in triples per point (501-503 return to point 2, 504-506 to point 3, ...) while scripts assign only the first (WINFAIL002: 2,501,bmpmVisit); whether the engine rolls among the triple is unproven.",
        ],
    }


def check(report: dict[str, Any], table: dict[str, int]) -> list[str]:
    errors: list[str] = []
    if report.get("schema") != SCHEMA:
        errors.append(f"schema {report.get('schema')!r} != {SCHEMA}")
    if report.get("symbols") != {name: table[name] for name in sorted(table)}:
        errors.append("symbols differ from the tracked world_map.json reading")
    scripts = report.get("scripts", [])
    derived = derive(scripts, table)
    for key, value in derived.items():
        if report.get(key) != value:
            errors.append(f"{key} does not re-derive from the stored commands")
    counts = report.get("counts", {})
    if counts.get("scripts") != len(scripts) or counts.get("commands") != sum(len(s["commands"]) for s in scripts):
        errors.append("counts differ from the stored scripts")
    for script in scripts:
        for command in script["commands"]:
            if command["name"] not in FLOW_COMMANDS:
                errors.append(f"{script['member']} stores non-flow command {command['name']}")
    return errors


def summary_line(prefix: str, report: dict[str, Any]) -> str:
    counts = report["counts"]
    same = report["battle_return_point_equals_level"]
    enc = report["encounter_return_matches_assigned_point"]
    return (f"{prefix} scripts={counts['scripts']} commands={counts['commands']} next_level_events={counts['next_level_events']} "
            f"to_big_map={counts['to_big_map']} point_event_writes={counts['point_event_writes']} "
            f"battle_return_point_equals_level={same['same']}/{same['total']} encounter_return_matches_assigned_point={enc['same']}/{enc['total']}")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--pak", type=Path, default=DEFAULT_PAK)
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    parser.add_argument("--world-map", type=Path, default=WORLD_MAP)
    parser.add_argument("--towndef", type=Path, default=TOWNDEF)
    parser.add_argument("--check", action="store_true", help="re-derive the summary tables from the tracked report without reading the PAK")
    args = parser.parse_args(argv)
    table = symbols(args.world_map, args.towndef)
    if args.check:
        report = json.loads(args.output.read_text(encoding="utf-8"))
        errors = check(report, table)
        if errors:
            for error in errors:
                print(f"BIG_MAP_FLOW_CHECK_FAIL {error}")
            return 1
        print(summary_line("BIG_MAP_FLOW_CHECK_PASS", report))
        return 0
    if not args.pak.is_file():
        parser.error(f"original PAK not found: {args.pak}")
    report = build_report(scan_pak(args.pak), table)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(summary_line("BIG_MAP_FLOW_BUILD_PASS", report))
    return 0


class BigMapFlowTask(OriginalArchiveTask):
    name = 'big_map_flow'
    family = 'static'
    inputs = (WORLD_MAP.relative_to(ROOT).as_posix(), TOWNDEF.relative_to(ROOT).as_posix())
    outputs = (DEFAULT_OUTPUT.relative_to(ROOT).as_posix(),)
    replaces = ('tools/hsl_big_map_flow.py --check',)
    scripts = ('tools/hsltools/data/big_map_flow.py',)

    def verify(self, ctx: Context) -> str:
        return printed_last_line(main, ['--check'])

    def rebuild(self, ctx: Context) -> None:
        printed_last_line(main, [])


def tasks() -> list[BigMapFlowTask]:
    return [BigMapFlowTask()]


if __name__ == '__main__':
    raise SystemExit(main())
