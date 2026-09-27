"""Provisional initial town menu trees for the te interpreter (TownEventRules.gd).

TOWNDEF.TXT has no "which town owns this event / which events are on the menu at
game start" field, and the initial TE table inside the EXE has not been located.
This tool derives a *candidate* initial tree per town from two data sources and
records exactly what each entry rests on:

1. TOWNDEF section-header comments ('[town_event] ; 歐姆村武器店') name the town
   and, for tavern/hall sub-menus, the parent by prefix ('米蘭多酒館老闆' under
   '米蘭多酒館'). Comments are not engine-consumed data -> provisional.
2. Every node that some script adds at runtime is excluded: children (or the
   node itself when num = 0) of teAddSelfTE / teAddTE in TOWNDEF and of
   actAddTE in the PAK's STORY*/winfail* scripts, and every event only reached
   through teExecEvent / teSetExecEvent / teSetTownExecEvent /
   teSetTownExitExecEvent / select branches / check jumps (te and act spellings).
   These references are resource-derived structure; that "everything else is on
   the menu from the start" is the provisional step.
3. A town whose every teCreateShop event is script-added starts empty in the
   data (薛維斯港, 兩棲族部落, 瑪哈亞鎮, 沙羅尼亞, 斐達克, 戈黎塔尼港, 亞雷比斯):
   candidates left there (e.g. 50, 150-156) are never added by any script and
   are recorded under "excluded", not placed.
4. A sub-menu that is only the parent of AddTE(num > 0) calls and has no
   candidate child (命運神殿大廳／港口／神殿中樞, 克里夫的家) is treated as
   script-ensured too (provisional reading of AddTE: the call ensures the
   parent node, then appends children).

Replacement evidence: the initial TE table in hsl01.exe (or a bounded original
probe of each town's first menu). Nothing here claims runtime equivalence.

Usage:

    PYTHONPATH=tools python3 -m hsltools.data.town_initial_trees            # rebuild (reads tracked towndef.json + PAK scripts)
    PYTHONPATH=tools python3 -m hsltools.data.town_initial_trees --check    # with PAK: rebuild and compare; without: offline consistency

Registry task town_initial_trees (family world, OriginalArchiveTask): tracked output content/world/town_initial_trees.json;
check = the script's --check (offline, or rebuild-and-compare when the original install is present), generate = rebuild
from the original scripts. Bodies moved verbatim from the former hsl_town_initial_trees.py.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import re
from pathlib import Path
from typing import Any

from hsltools.data import OriginalArchiveTask, printed_last_line
from hsltools.paths import ORIGINAL_ROOT, ROOT
from hsltools.registry import Context

DEFAULT_PAK_ROOT = ORIGINAL_ROOT
DEFAULT_TOWNDEF = ROOT / "content/imported/hsl/global/world_map/towndef.json"
DEFAULT_OUTPUT = ROOT / "content/world/town_initial_trees.json"
SCHEMA = "hsl_town_initial_trees.v1"
TOWNDEF_SCHEMA = "hsl_towndef.v1"
ENCODING = "cp950"

SCRIPT_MEMBER_RE = re.compile(r"^@:\\data\\(STORY|WINFAIL)(\d+)\.TXT$", re.IGNORECASE)
# act tokens that add/remove menu nodes or select the exec event of a town; the
# argument order is the te signature from TOWNDEF.H (town id first for *TE).
# Several act commands may be chained on one line ('actAddTE,...,0,actAddTE,...'):
# the argument run stops at the next act token.
ACT_LINE_RE = re.compile(r"(act(?:AddTE|DeleteTE|SetTownExecEvent|SetTownExitExecEvent))\b((?:,(?!\s*act[A-Z])[^,;\r\n]*)*)")

# Tokens whose arguments name an event executed through a jump / insert, never
# through the menu tree: token -> argument positions (or a callable on args).
EXEC_TARGET_POSITIONS: dict[str, Any] = {
    "teExecEvent": [0],
    "teSetExecEvent": [1],
    "teSetTownExecEvent": [1],
    "teSetTownExitExecEvent": [1],
    "teCheckItemExecEvent": [1],
    "teCheckJobUp": [2],
    "teCheckJobUp2": [2],
    "teCheckTEExist": [3],
    "teSecretManBuyThing": [3],
    "teSelectInsertEvent": lambda args: list(range(3, len(args), 2)),
    "tePlayerSelectInsertEvent": lambda args: list(range(4, len(args), 2)),
    "actSetTownExecEvent": [1],
    "actSetTownExitExecEvent": [1],
}
ADD_TOKENS = {"teAddSelfTE": False, "teAddTE": True, "actAddTE": True}  # value: first argument is the town id
INTEGER_RE = re.compile(r"-?\d+")


def _sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


# ---------------------------------------------------------------- PAK scripts
def scan_script_actions(pak_root: Path) -> tuple[list[dict[str, Any]], list[dict[str, Any]]]:
    """[{script, token, args}] for every act*TE / actSetTown*ExecEvent in STORY*/winfail*, plus the members that carried one."""
    from hsltools.data.world_map import PakReader

    reader = PakReader(pak_root)
    actions: list[dict[str, Any]] = []
    members: list[dict[str, Any]] = []

    def order(name: str) -> tuple[str, int]:
        match = SCRIPT_MEMBER_RE.match(name)
        return (match.group(1).upper(), int(match.group(2))) if match else ("", 0)

    for name in sorted((n for n in reader.names() if SCRIPT_MEMBER_RE.match(n)), key=order):
        raw = reader.read(name)
        text = raw.decode(ENCODING, "replace")
        script = Path(name.replace("\\", "/")).stem.lower()
        found = 0
        for line in text.splitlines():
            line = line.split(";", 1)[0]
            for match in ACT_LINE_RE.finditer(line):
                args = [part.strip() for part in match.group(2).split(",")[1:]]
                while args and args[-1] == "":
                    args.pop()
                actions.append({"script": script, "token": match.group(1), "args": args})
                found += 1
        if found:
            members.append({"member": name, "byte_length": len(raw), "sha256": _sha(raw), "actions": found})
    return actions, members


# ---------------------------------------------------------------- classification
def _town_symbols(towndef: dict[str, Any]) -> dict[str, int]:
    return {symbol: int(value) for symbol, value in towndef.get("symbols", {}).items() if symbol.startswith("town_") and value is not None}


def _int(arg: str) -> int | None:
    return int(arg) if INTEGER_RE.fullmatch(arg or "") else None


def _town_of_comment(comment: str | None, town_symbols: dict[str, int]) -> str | None:
    """Longest town short name (symbol without 'town_') contained in the comment."""
    if not comment:
        return None
    best = None
    for symbol in town_symbols:
        short = symbol[len("town_"):]
        if short in comment and (best is None or len(short) > len(best) - len("town_")):
            best = symbol
    return best


def build_trees(towndef: dict[str, Any], script_actions: list[dict[str, Any]], script_members: list[dict[str, Any]] | None = None) -> dict[str, Any]:
    if towndef.get("schema") != TOWNDEF_SCHEMA:
        raise ValueError(f"towndef schema {towndef.get('schema')!r} != {TOWNDEF_SCHEMA!r}")
    town_symbols = _town_symbols(towndef)
    symbol_by_id = {value: symbol for symbol, value in town_symbols.items()}
    events = {int(record["code"]): record for record in towndef["town_events"]}

    runtime_added: dict[int, list[str]] = {}
    exec_targets: dict[int, list[str]] = {}
    ensured_parents: dict[int, list[str]] = {}  # parent of an AddTE with num > 0 (provisional: the add ensures the parent node)
    added_by_town: dict[int, str] = {}  # event -> town symbol some AddTE placed it in (report only)

    def note(bucket: dict[int, list[str]], code: int | None, source: str) -> None:
        if code is None or code <= 0:
            return
        bucket.setdefault(code, [])
        if source not in bucket[code]:
            bucket[code].append(source)

    def scan(token: str, args: list[str], source: str, self_town: str | None) -> None:
        if token in ADD_TOKENS:
            has_town = ADD_TOKENS[token]
            town = self_town
            if has_town and args:
                town = args[0] if args[0] in town_symbols else symbol_by_id.get(_int(args[0]))
            rest = args[1:] if has_town else args
            if len(rest) < 2:
                return
            parent, num = _int(rest[0]), _int(rest[1])
            targets = [parent] if num == 0 else [_int(child) for child in rest[2:]]
            if num != 0:
                note(ensured_parents, parent, source)
                if parent and town:
                    added_by_town.setdefault(parent, town)
            for target in targets:
                note(runtime_added, target, source)
                if target and town:
                    added_by_town.setdefault(target, town)
            return
        positions = EXEC_TARGET_POSITIONS.get(token)
        if positions is None:
            return
        for position in (positions(args) if callable(positions) else positions):
            if position < len(args):
                note(exec_targets, _int(args[position]), source)

    comment_town = {code: _town_of_comment(record.get("comment"), town_symbols) for code, record in events.items()}
    for code, record in events.items():
        for command in record.get("events", []):
            scan(str(command.get("token", "")), [str(a) for a in command.get("args", [])], f"TOWNDEF town_event {code} {command.get('token')}", comment_town[code])
    for action in script_actions:
        scan(str(action["token"]), [str(a) for a in action.get("args", [])], f"{action['script']} {action['token']}", None)

    towns: dict[str, dict[str, Any]] = {}
    for symbol, point_id in sorted(town_symbols.items(), key=lambda kv: kv[1]):
        towns[symbol] = {"point_id": point_id, "tree": {"0": []}, "entries": [], "excluded": []}
    unassigned: list[dict[str, Any]] = []
    candidates_by_town: dict[str, list[int]] = {symbol: [] for symbol in towns}
    for code in sorted(events):
        record = events[code]
        town = comment_town[code] or added_by_town.get(code)
        reasons: list[dict[str, Any]] = []
        if record.get("show_name") is None:
            reasons.append({"reason": "no_show_name"})
        if code in runtime_added:
            reasons.append({"reason": "added_at_runtime", "by": runtime_added[code]})
        if code in exec_targets:
            reasons.append({"reason": "exec_target_only", "by": exec_targets[code]})
        entry = {"code": code, "comment": record.get("comment"), "reasons": reasons}
        if not reasons and code in ensured_parents and not comment_town[code]:
            reasons.append({"reason": "sub_menu_script_populated", "by": ensured_parents[code]})
        if town is None:
            unassigned.append(entry)
        elif reasons:
            towns[town]["excluded"].append(entry)
        else:
            candidates_by_town[town].append(code)

    def is_sub_menu(code: int) -> bool:
        return any(str(c.get("token")) == "teCreateSubEventMenu" for c in events[code].get("events", []))

    def prefix_parent(code: int, parents: list[int]) -> int:
        comment = events[code].get("comment") or ""
        parent, best_len = 0, 0
        for candidate in parents:
            parent_comment = events[candidate].get("comment") or ""
            if candidate != code and parent_comment and comment.startswith(parent_comment) and len(parent_comment) > best_len:
                parent, best_len = candidate, len(parent_comment)
        return parent

    # A town whose every shop event (teCreateShop) is script-added starts with an
    # empty menu in the data; candidates left there are never added by any
    # script (dead table rows or an EXE-side default) and are recorded, not placed.
    for symbol, codes in candidates_by_town.items():
        shops = [code for code, record in events.items() if (comment_town[code] or added_by_town.get(code)) == symbol and any(str(c.get("token")) == "teCreateShop" for c in record.get("events", []))]
        if shops and all(code in runtime_added for code in shops):
            for code in list(codes):
                codes.remove(code)
                reason = {"reason": "town_script_populated", "by": [f"shop events {shops} are all script-added"]}
                if code in ensured_parents:
                    reason["ensured_by"] = ensured_parents[code]
                else:
                    reason["by"].append(f"no script adds {code} (dead row or EXE-side default)")
                towns[symbol]["excluded"].append({"code": code, "comment": events[code].get("comment"), "reasons": [reason]})

    # A sub-menu that scripts populate (it is the parent of an AddTE with num > 0)
    # and that has no candidate child of its own starts empty in the data, so its
    # node is treated as script-ensured too; children orphaned by that pruning
    # follow it. Iterate until stable.
    for symbol, codes in candidates_by_town.items():
        while True:
            parents = [code for code in codes if is_sub_menu(code)]
            children = {parent: [code for code in codes if code != parent and prefix_parent(code, parents) == parent] for parent in parents}
            pruned = [parent for parent in parents if parent in ensured_parents and not children[parent]]
            if not pruned:
                break
            for parent in pruned:
                codes.remove(parent)
                towns[symbol]["excluded"].append({"code": parent, "comment": events[parent].get("comment"), "reasons": [{"reason": "sub_menu_script_populated", "by": ensured_parents[parent]}]})
        for code in list(codes):
            comment = events[code].get("comment") or ""
            lost = [parent for parent in ensured_parents if is_sub_menu(parent) and parent not in codes and (events[parent].get("comment") or "") and comment.startswith(events[parent].get("comment") or "")]
            if lost:
                codes.remove(code)
                towns[symbol]["excluded"].append({"code": code, "comment": comment, "reasons": [{"reason": "child_of_script_populated_sub_menu", "by": [f"sub-menu {parent}" for parent in lost]}]})

    for symbol, codes in candidates_by_town.items():
        parents = [code for code in codes if is_sub_menu(code)]
        tree: dict[str, list[int]] = {"0": []}
        entries: list[dict[str, Any]] = []
        for code in codes:
            comment = events[code].get("comment") or ""
            parent = prefix_parent(code, parents)
            tree.setdefault(str(parent), []).append(code)
            show = events[code].get("show_name") or {}
            source = f"TOWNDEF comment '{comment}'"
            if parent:
                source += f" (prefix '{events[parent].get('comment')}' = sub-menu {parent})"
            entries.append({"code": code, "parent": parent, "show_name_id": show.get("resource_id"), "show_name_text": show.get("text"), "source": source})
        for parent in parents:
            tree.setdefault(str(parent), [])
        towns[symbol]["tree"] = {key: tree[key] for key in sorted(tree, key=int)}
        towns[symbol]["entries"] = entries

    return {
        "schema": SCHEMA,
        "evidence_tier": "static-derived",
        "claim": (
            "Initial menu tree per town. Confirmed by source-research SR-069: two complete executions of the original town "
            "initialiser 0x454ae0 -> 0x454a20 (docs/evidence_packets/static_reverse/original_world_town.md) produce exactly "
            "these roots and children (town 1 roots [1,2,3]; town 4 roots [4,5,6,7] with 7 -> [8,12,13,14]; town 6 roots "
            "[16,17,18,20] with 20 -> [21,22,23]; the other nine towns start empty). The generation below is the earlier "
            "derivation path kept as a record: TOWNDEF town_events grouped by the town named in their section comment, minus "
            "every node a TOWNDEF te*TE or PAK STORY/winfail act*TE adds at runtime, every event reached only by jump/insert "
            "tokens, every candidate of a town whose shop events are all script-added, and every script-ensured sub-menu "
            "without a candidate child; tavern children nest under the sub-menu whose comment prefixes theirs."
        ),
        "confirmed_by": "SR-069 original_world_town.md: 0x454a20 executable town-id/event-id calls (100x264-byte records, 8 root slots x 7 children)",
        "replacement_evidence": "none needed for the initial roots/children; later tree changes stay with the te/act add/delete tokens at runtime",
        "not_supported": [
            "menu order inside a level (TOWNDEF code order is used)",
            "that an excluded node is absent at game start for any reason other than the listed script reference",
            "towns without any candidate (their whole menu is script-populated in the data; an EXE-side default is not ruled out)",
        ],
        "sources": {
            "towndef_json": {"path": "content/imported/hsl/global/world_map/towndef.json", "schema": TOWNDEF_SCHEMA, "town_event_count": len(events)},
            "pak_scripts": script_members or [],
        },
        "script_actions": script_actions,
        "towns": towns,
        "unassigned": unassigned,
        "statistics": {
            "towns": len(towns),
            "towns_with_roots": sum(1 for town in towns.values() if town["tree"].get("0")),
            "root_entries": sum(len(town["tree"].get("0", [])) for town in towns.values()),
            "nested_entries": sum(len(town["entries"]) - len(town["tree"].get("0", [])) for town in towns.values()),
            "excluded": sum(len(town["excluded"]) for town in towns.values()),
            "unassigned": len(unassigned),
            "runtime_added_events": len(runtime_added),
            "script_ensured_sub_menus": len(ensured_parents),
            "exec_target_events": len(exec_targets),
            "script_actions": len(script_actions),
        },
    }


# ---------------------------------------------------------------- check
def check_offline(output: Path, towndef_path: Path) -> list[str]:
    failures: list[str] = []
    if not output.exists():
        return [f"missing {output}"]
    data = json.loads(output.read_text(encoding="utf-8"))
    towndef = json.loads(towndef_path.read_text(encoding="utf-8"))
    if data.get("schema") != SCHEMA:
        failures.append(f"schema={data.get('schema')}")
    if data.get("evidence_tier") != "static-derived":
        failures.append("evidence_tier must be static-derived (SR-069 confirmed the initial roots/children)")
    # The SR-069 executed result the generated trees must keep matching.
    confirmed = {"town_歐姆村": {"0": [1, 2, 3]}, "town_米蘭多": {"0": [4, 5, 6, 7], "7": [8, 12, 13, 14]}, "town_席達鎮": {"0": [16, 17, 18, 20], "20": [21, 22, 23]}}
    for symbol, town in data.get("towns", {}).items():
        tree = {key: list(value) for key, value in town.get("tree", {}).items() if value}
        if tree != confirmed.get(symbol, {}):
            failures.append(f"{symbol} tree {tree} differs from the SR-069 executed initial tree {confirmed.get(symbol, {})}")
    codes = {int(record["code"]) for record in towndef.get("town_events", [])}
    town_symbols = _town_symbols(towndef)
    if set(data.get("towns", {})) != set(town_symbols):
        failures.append("town set differs from towndef.json town_* symbols")
    seen: set[int] = set()
    for symbol, town in data.get("towns", {}).items():
        if town.get("point_id") != town_symbols.get(symbol):
            failures.append(f"{symbol}: point_id differs from extras.h")
        tree = town.get("tree", {})
        entry_codes = {entry["code"] for entry in town.get("entries", [])}
        listed: set[int] = set()
        for parent, children in tree.items():
            if parent != "0" and int(parent) not in entry_codes:
                failures.append(f"{symbol}: sub-menu parent {parent} is not an entry")
            for child in children:
                if child not in codes:
                    failures.append(f"{symbol}: child {child} is not a TOWNDEF town_event")
                if child in seen:
                    failures.append(f"{symbol}: event {child} listed twice")
                seen.add(child)
                listed.add(child)
        if listed != entry_codes:
            failures.append(f"{symbol}: tree children {sorted(listed)} != entries {sorted(entry_codes)}")
    stats = data.get("statistics", {})
    if stats.get("root_entries") != sum(len(town.get("tree", {}).get("0", [])) for town in data.get("towns", {}).values()):
        failures.append("statistics.root_entries differs from trees")
    return failures


def check(output: Path, towndef_path: Path, pak_root: Path) -> int:
    failures = check_offline(output, towndef_path)
    mode = "offline"
    if pak_root.exists() and not failures:
        mode = "rebuild"
        towndef = json.loads(towndef_path.read_text(encoding="utf-8"))
        actions, members = scan_script_actions(pak_root)
        fresh = build_trees(towndef, actions, members)
        if json.loads(output.read_text(encoding="utf-8")) != json.loads(json.dumps(fresh)):
            failures.append(f"{output.relative_to(ROOT)} differs from a fresh build")
    if failures:
        print("TOWN_INITIAL_TREES_CHECK_FAIL " + "; ".join(failures))
        return 1
    stats = json.loads(output.read_text(encoding="utf-8"))["statistics"]
    print(
        f"TOWN_INITIAL_TREES_CHECK_PASS mode={mode} towns={stats['towns']} towns_with_roots={stats['towns_with_roots']} "
        f"root_entries={stats['root_entries']} nested_entries={stats['nested_entries']} excluded={stats['excluded']} unassigned={stats['unassigned']}"
    )
    return 0


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--pak", type=Path, default=DEFAULT_PAK_ROOT)
    parser.add_argument("--towndef", type=Path, default=DEFAULT_TOWNDEF)
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    parser.add_argument("--check", action="store_true", help="rebuild and compare with the tracked output (offline consistency only when the PAK is absent)")
    args = parser.parse_args(argv)
    if args.check:
        return check(args.output, args.towndef, args.pak)
    if not args.pak.exists():
        print(f"TOWN_INITIAL_TREES_BUILD_FAIL pak_missing={args.pak}")
        return 1
    towndef = json.loads(args.towndef.read_text(encoding="utf-8"))
    actions, members = scan_script_actions(args.pak)
    data = build_trees(towndef, actions, members)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    stats = data["statistics"]
    print(
        f"TOWN_INITIAL_TREES_BUILD_PASS output={args.output.relative_to(ROOT)} towns={stats['towns']} towns_with_roots={stats['towns_with_roots']} "
        f"root_entries={stats['root_entries']} nested_entries={stats['nested_entries']} excluded={stats['excluded']} unassigned={stats['unassigned']} script_actions={stats['script_actions']}"
    )
    return 0


class TownInitialTreesTask(OriginalArchiveTask):
    name = 'town_initial_trees'
    family = 'world'
    archive = ORIGINAL_ROOT
    inputs = (DEFAULT_TOWNDEF.relative_to(ROOT).as_posix(),)
    outputs = (DEFAULT_OUTPUT.relative_to(ROOT).as_posix(),)
    replaces = ('tools/hsl_town_initial_trees.py --check',)
    scripts = ('tools/hsltools/data/town_initial_trees.py',)

    def verify(self, ctx: Context) -> str:
        return printed_last_line(check, DEFAULT_OUTPUT, DEFAULT_TOWNDEF, DEFAULT_PAK_ROOT)

    def rebuild(self, ctx: Context) -> None:
        printed_last_line(main, [])


def tasks() -> list[TownInitialTreesTask]:
    return [TownInitialTreesTask()]


if __name__ == '__main__':
    raise SystemExit(main())
