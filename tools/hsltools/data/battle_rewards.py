"""Compile reward source fields and carry lists; no live reward rules are implied.

Registry task battle_rewards (family actors): output content/generated/hsl/combat/rewards.json.
Bodies (including the --pak/--import-carry command line, exercised by test_hsl_battle_rewards)
moved verbatim from the former hsl_battle_rewards.py.
"""
import argparse
import hashlib
import json
from pathlib import Path

from hsltools.data import json_bytes
from hsltools.registry import GeneratedFilesTask, Context
from hsltools.sources.tables import TABLES, blocks, character_rows

# Every PLAYERS.TXT character row is compiled; the roster of a battle decides which rows are consumed
# (BattleRewardRules.data_error still refuses a unit whose actor is missing). The first-chapter templates
# below must stay present so a truncated or mis-parsed table fails instead of shrinking the data.
REQUIRED_ACTORS = {"1", "2", "3", "4", "6", "21", "23", "24", "25", "26", "28", "36", "39", "61", "62"}
CARRY = TABLES / "carry_items.json"
OUTPUT = Path("content/generated/hsl/combat/rewards.json")


def actor_rows() -> list[dict[str, str]]:
    rows = []
    seen = set()
    for row in character_rows():
        code = str(int(row["code"]))
        if code in seen:
            raise ValueError(f"Duplicate reward actor {code}")
        seen.add(code)
        rows.append(row)
    if not REQUIRED_ACTORS <= seen:
        raise ValueError("Incomplete battle reward templates")
    return rows


def carry_lists(raw: bytes, wanted: set[int]) -> dict[str, list[int]]:
    """Keep source order and duplicate entries; they may affect later selection."""
    lists = {}
    for row in blocks(raw, "item"):
        code = int(row["code"])
        if code not in wanted:
            continue
        if str(code) in lists:
            raise ValueError(f"Duplicate carry list {code}")
        lists[str(code)] = [int(part.strip()) for part in row["item_id"].split(",")]
    if set(map(int, lists)) != wanted:
        raise ValueError("Incomplete carry lists")
    return lists


def curate_carry(pak: Path):
    from hsltools.sources.pak import find_decoded_paks_packages, find_paks_record_by_name, read_paks_record_bytes
    wanted = {int(row.get("carry_item", "0")) for row in actor_rows()} - {0}
    packages = find_decoded_paks_packages(pak)
    matches = [(p, r) for p in packages if (r := find_paks_record_by_name(p["records"], "@:\\data\\towndef.txt"))]
    if len(matches) != 1:
        raise ValueError("Missing/ambiguous TOWNDEF source")
    package, record = matches[0]
    raw = read_paks_record_bytes(package["path"], record, data_end_offset=int(package["paks"]["candidate_index_offset"]))
    lists = carry_lists(raw, wanted)
    return {"schema": "hsl_carry_items.v1", "evidence_tier": "resource-derived",
            "source_member": "@:\\data\\TOWNDEF.TXT", "source_sha256": hashlib.sha256(raw).hexdigest(),
            "lists": lists,
            "scope": "Every carry list referenced by a PLAYERS.TXT character row. PLAYERS bindings use the tracked table, not an asserted original-archive match."}


def build():
    curated = json.loads(CARRY.read_text(encoding="utf-8"))
    if curated.get("schema") != "hsl_carry_items.v1":
        raise ValueError("Invalid carry source schema")
    rows = actor_rows()
    wanted = {str(int(row["carry_item"])) for row in rows if int(row.get("carry_item", "0")) != 0}
    if not isinstance(curated.get("lists"), dict) or set(curated["lists"]) != wanted:
        raise ValueError("Incomplete or unexpected carry lists")
    items = {}
    for row in blocks((TABLES / "ITEM.TXT").read_bytes(), "item"):
        code = row["code"]
        if code in items:
            raise ValueError("Duplicate item code")
        items[code] = {"get_ratio": int(row["get_ratio"]), "important": row.get("important", "0") == "1"}
    actors = {}
    for row in rows:
        code = row["code"].zfill(3)
        carry_id = int(row.get("carry_item", "0"))
        carry = [] if carry_id == 0 else curated["lists"][str(carry_id)]
        if carry_id != 0 and (not isinstance(carry, list) or not carry or any(type(item) is not int for item in carry)):
            raise ValueError(f"Invalid carry list {carry_id}")
        if any(item not in (-1, 0) and str(item) not in items for item in carry):
            raise ValueError("Carry list references missing item")
        actors[code] = {"gold": int(row.get("gold", "0")), "carry_list_id": carry_id,
                        "carry_list_declared": "carry_item" in row, "carry_items": carry,
                        "status_raw": int(row.get("status", "0"), 0)}
        if "gold" not in row:
            actors[code]["gold_note"] = "Undeclared source field uses the explicit remake zero-reward baseline, not a native loader-default claim."
    return {"schema": "hsl_battle_rewards.v1", "evidence_tier": "resource-derived", "live": True,
            "actors": actors, "items": items,
            "source_sha256": {name: hashlib.sha256((TABLES / name).read_bytes()).hexdigest() for name in ("PLAYERS.TXT", "ITEM.TXT", "carry_items.json")},
            "limits": "Source fields only. PLAYERS bindings use the tracked table, whose original-archive mismatch remains unresolved. A missing carry_item is recorded as undeclared with an empty list, not as proof of native initialization. Gold eligibility, item selection, drop probability, status flag meaning, pickup, inventory exchange and recovery are not established or implemented by this data."}


def main(argv: list[str] | None = None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true")
    parser.add_argument("--pak", type=Path)
    parser.add_argument("--import-carry", action="store_true")
    args = parser.parse_args(argv)
    if args.import_carry and not args.pak:
        parser.error("--import-carry requires --pak")
    if args.check and args.import_carry:
        parser.error("--check cannot be combined with --import-carry")
    if args.pak:
        curated = curate_carry(args.pak)
        if args.import_carry:
            CARRY.write_text(json.dumps(curated, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        elif json.loads(CARRY.read_text(encoding="utf-8")) != curated:
            raise ValueError("Original carry source differs")
    payload = build()
    if args.check:
        if json.loads(OUTPUT.read_text(encoding="utf-8")) != payload:
            raise ValueError("Stale battle reward data")
    else:
        OUTPUT.parent.mkdir(parents=True, exist_ok=True)
        OUTPUT.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print("BATTLE_REWARD_DATA_PASS", len(payload["actors"]), "actors", len(payload["items"]), "items")


class BattleRewardsTask(GeneratedFilesTask):
    name = 'battle_rewards'
    family = 'actors'
    inputs = ('content/imported/hsl/global/tables/',)
    outputs = (OUTPUT.as_posix(),)
    replaces = ('tools/hsl_battle_rewards.py --check',)
    scripts = ('tools/hsltools/data/battle_rewards.py',)

    def render(self, ctx: Context) -> dict[str, bytes]:
        return {OUTPUT.as_posix(): json_bytes(build())}

    def summary(self, rendered: dict[str, bytes], mode: str) -> str:
        payload = json.loads(rendered[OUTPUT.as_posix()])
        return f'BATTLE_REWARD_DATA_PASS {len(payload["actors"])} actors {len(payload["items"])} items'


def tasks() -> list[BattleRewardsTask]:
    return [BattleRewardsTask()]


if __name__ == '__main__':
    raise SystemExit(main())
