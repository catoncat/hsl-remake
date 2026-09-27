#!/usr/bin/env python3
"""Bounded native proof for Leonard growth caps and stat refresh.

This executes the original 0x448840 stat refresh to full return with synthetic
Leonard attributes.  It also evaluates an independent SwordMan arithmetic model
recovered from the same instruction path.  The product never runs the EXE.
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path
import re
import struct
import sys

ROOT = Path(__file__).resolve().parents[1]
TOOLS = ROOT / "tools"
if str(TOOLS) not in sys.path:
    sys.path.insert(0, str(TOOLS))

from hsltools.data.first_skill import TABLES, blocks, digest
from hsltools.native.image import EXE_SHA, image
from hsltools.paths import ORIGINAL_EXE

PACKET = ROOT / "docs/evidence_packets/static_reverse/original_growth_refresh.json"
ATTRIBUTES = ("str", "dex", "mind", "con")
CAP_TABLE_VA = 0x4786BC
JOB_BASE = 80
REFRESH_ENTRY = 0x448840


def _number(row: dict[str, str], name: str) -> int:
    return int(row.get(name, "0"), 0)


def _level_attack_bonus(level: int) -> int:
    if level < 10:
        return max(level, 0)
    if level < 20:
        return 10 + (level - 10) // 2
    return 15 + (level - 20) // 4


def swordman_unequipped(source: dict, attrs: dict[str, int], level: int,
                        current_hp: int, current_mp: int) -> dict:
    """Positive-domain arithmetic equivalent of jobSwordMan in 0x448840."""
    strength, dexterity, mind, constitution = (int(attrs[key]) for key in ATTRIBUTES)
    resist = {str(i): int(source["base_resist_by_type"][str(i)]) for i in range(5)}
    bonuses = (
        min(40, (40 * mind) // 100 + constitution // 4),
        min(40, (26 * mind) // 100 + constitution // 5),
        min(40, (20 * mind) // 100 + constitution // 5),
        min(40, (46 * mind) // 100 + constitution // 4),
        min(40, (10 * mind) // 100 + constitution // 6),
    )
    for i, bonus in enumerate(bonuses):
        resist[str(i)] += bonus

    max_hp = level + (180 * constitution) // 100 + strength // 8
    max_mp = (80 * mind) // 100 + constitution // 6
    attack = (int(source["attack_power"])
              + (116 * (strength // 2)) // 100
              + (36 * dexterity) // 100 + 16 + _level_attack_bonus(level))
    defense = (int(source["defense"])
               + (20 * strength) // 100 + mind // 5 + dexterity // 3 + constitution // 3)
    magic_attack = int(source["magic_attack_power"]) + min((10 * mind) // 100 + level + 16, 76)
    speed = int(source["speed"]) + (90 * dexterity) // 100
    max_hp = max(1, max_hp + int(source["hit_point"]))
    max_mp = max(0, max_mp + int(source["magic_point"]))
    if not source["has_magic"]:
        max_mp = 0
        current_mp = 0
    return {
        "max_hp": max_hp,
        "current_hp": min(current_hp, max_hp),
        "max_mp": max_mp,
        "current_mp": min(current_mp, max_mp),
        "attack": attack,
        "defense": defense,
        "speed": speed,
        "hit_rate": 0,
        "magic_attack": magic_attack,
        "resist_by_type": resist,
        "exp_threshold": min(2000, (level + 1) * 50),
    }


def _with_delta(stats: dict, delta: dict) -> dict:
    result = json.loads(json.dumps(stats))
    for key in ("max_hp", "max_mp", "attack", "defense", "speed", "hit_rate", "magic_attack"):
        result[key] += int(delta[key])
    for key in result["resist_by_type"]:
        result["resist_by_type"][key] += int(delta["resist_by_type"][key])
    result["max_hp"] = max(1, result["max_hp"])
    result["max_mp"] = max(0, result["max_mp"])
    result["current_hp"] = min(result["current_hp"], result["max_hp"])
    result["current_mp"] = min(result["current_mp"], result["max_mp"])
    return result


def run(exe: Path) -> dict:
    from unicorn import Uc, UC_ARCH_X86, UC_MODE_32, UC_HOOK_CODE
    from unicorn.x86_const import UC_X86_REG_EIP, UC_X86_REG_ESP

    raw = exe.read_bytes()
    if digest(raw) != EXE_SHA:
        raise ValueError("Unsupported EXE: growth refresh probe requires the documented hsl01.exe")
    image_base, mapped = image(raw)
    defines_text = (TABLES / "TYPE.H").read_bytes().decode("cp950")
    defines = {name: int(value, 0) for name, value in
               re.findall(r"#define\s+(\w+)\s+(0x[0-9a-fA-F]+|\d+)\b", defines_text)}
    player = next(row for row in blocks((TABLES / "PLAYERS.TXT").read_bytes(), "character")
                  if row["code"] == "1")
    items = {row["code"]: row for row in blocks((TABLES / "ITEM.TXT").read_bytes(), "item")}
    job_code = defines[player["job"]]
    if player["job"] != "jobSwordMan" or job_code != 80:
        raise ValueError("Leonard source no longer maps to jobSwordMan=80")

    cap_offset = CAP_TABLE_VA - image_base
    cap_rows = [list(struct.unpack_from("<4H", mapped, cap_offset + index * 8)) for index in range(20)]
    caps = dict(zip(ATTRIBUTES, cap_rows[job_code - JOB_BASE]))
    source = {
        "actor_id": "001",
        "job": player["job"],
        "job_code": job_code,
        "attack_power": _number(player, "attack_power"),
        "magic_attack_power": _number(player, "magic_attack_power"),
        "defense": _number(player, "defense"),
        "speed": _number(player, "speed"),
        "hit_point": _number(player, "hit_point"),
        "magic_point": _number(player, "magic_point"),
        "base_resist_by_type": {str(i): _number(player, "resist_" + element)
                                for i, element in enumerate(("earth", "water", "air", "fire", "mind"))},
        "has_magic": any(player.get("magic_" + element, "0") != "0"
                         for element in ("other", "earth", "water", "wind", "fire", "mind")),
        "equipment_codes": [_number(player, field) for field in
                            ("weapon_equip", "head_equip", "armor_equip", "foot_equip",
                             "other1_equip", "other2_equip")],
    }
    actor_fields = {"str": 0x64, "dex": 0x68, "mind": 0x6C, "con": 0x70, "level": 0x9C,
                    "attack_power": 0x1A4, "magic_attack_power": 0x1A8,
                    "defense": 0x1AC, "speed": 0x1B0}
    item_fields = {"attack_damage": 0x88, "hit_ratio": 0x98, "add_attack": 0x20,
                   "add_defense": 0x3C, "add_speed": 0x38, "add_move": 0x34,
                   "add_hp": 0x2C, "add_mp": 0x28, "add_magic_attack": 0x24}
    equipment_fields = (0xEC, 0xF0, 0xF4, 0xF8, 0xFC, 0x100)
    result_fields = {"current_hp": 0xD8, "max_hp": 0xDC, "current_mp": 0xE0, "max_mp": 0xE4,
                     "attack": 0xC0, "defense": 0xB4, "speed": 0xB8,
                     "hit_rate": 0xBC, "magic_attack": 0xD0, "exp_threshold": 0x8C}

    def execute(attrs: dict[str, int], level: int, current_hp: int, current_mp: int,
                equipped: bool) -> dict:
        machine = Uc(UC_ARCH_X86, UC_MODE_32)
        machine.mem_map(image_base, len(mapped))
        machine.mem_write(image_base, bytes(mapped))
        machine.mem_map(0x10000000, 0x10000)
        machine.mem_map(0x20000000, 0x10000)
        machine.mem_map(0x21000000, 0x20000)
        actor, stack, stop = 0x20000000, 0x1000FF00, 0x10000000

        def put(address: int, value: int) -> None:
            machine.mem_write(address, struct.pack("<I", value & 0xFFFFFFFF))

        for name in ATTRIBUTES:
            put(actor + actor_fields[name], attrs[name])
        put(actor + actor_fields["level"], level)
        for name in ("attack_power", "magic_attack_power", "defense", "speed"):
            put(actor + actor_fields[name], int(source[name]))
        put(actor + 0x18, job_code)
        put(actor + 0x28, defines[player["mode"]])
        put(actor + 0xD8, current_hp)
        put(actor + 0xE0, current_mp)
        put(actor + 0x1B4, (int(source["hit_point"]) << 16) | int(source["magic_point"]))
        for i, value in source["base_resist_by_type"].items():
            put(actor + 0x118 + int(i) * 4, value)
        if source["has_magic"]:
            put(actor + 0x174, 1)
        put(0x4C1B40, 0x21000000)
        if equipped:
            for slot_offset, item_code in zip(equipment_fields, source["equipment_codes"]):
                put(actor + slot_offset, item_code)
                if not item_code:
                    continue
                item = items[str(item_code)]
                address = 0x21000000 + item_code * 176
                put(address + 8, defines[item["type"]])
                for field, offset in item_fields.items():
                    put(address + offset, _number(item, field))
        put(stack, stop)
        put(stack + 4, actor)
        machine.reg_write(UC_X86_REG_ESP, stack)

        def guard(_machine, address, _size, _data):
            if not 0x448370 <= address < 0x44B820:
                raise RuntimeError(f"Unexplained stat-refresh execution address {address:#x}")

        machine.hook_add(UC_HOOK_CODE, guard)
        machine.emu_start(REFRESH_ENTRY, stop, count=12000)
        if machine.reg_read(UC_X86_REG_EIP) != stop or machine.reg_read(UC_X86_REG_ESP) != stack + 4:
            raise RuntimeError("Native stat refresh did not return within the bounded call")
        output = {name: struct.unpack("<i", machine.mem_read(actor + offset, 4))[0]
                  for name, offset in result_fields.items()}
        output["caps"] = {name: struct.unpack("<I", machine.mem_read(actor + 0x74 + i * 4, 4))[0]
                          for i, name in enumerate(ATTRIBUTES)}
        output["resist_by_type"] = {str(i): struct.unpack("<i", machine.mem_read(actor + 0x104 + i * 4, 4))[0]
                                    for i in range(5)}
        return output

    fixtures = [
        ("baseline", {"str": 16, "dex": 16, "mind": 8, "con": 12}, 1, 17, 0),
        ("level_two_no_refill", {"str": 16, "dex": 16, "mind": 8, "con": 12}, 2, 17, 0),
        ("str_plus_one", {"str": 17, "dex": 16, "mind": 8, "con": 12}, 2, 17, 0),
        ("dex_plus_one", {"str": 16, "dex": 17, "mind": 8, "con": 12}, 2, 17, 0),
        ("mind_plus_one", {"str": 16, "dex": 16, "mind": 9, "con": 12}, 2, 17, 0),
        ("con_plus_one", {"str": 16, "dex": 16, "mind": 8, "con": 13}, 2, 17, 0),
        ("five_point_mix", {"str": 18, "dex": 17, "mind": 9, "con": 13}, 2, 17, 0),
        ("high_attributes", {"str": 61, "dex": 57, "mind": 46, "con": 60}, 40, 91, 9),
        ("near_caps", {"str": 89, "dex": 87, "mind": 79, "con": 93}, 70, 240, 20),
        ("at_caps_clamp_current", caps, 99, 9999, 9999),
    ]
    cases = []
    deltas = []
    for name, attrs, level, current_hp, current_mp in fixtures:
        unequipped = execute(attrs, level, current_hp, current_mp, False)
        equipped = execute(attrs, level, current_hp, current_mp, True)
        if unequipped["caps"] != caps or equipped["caps"] != caps:
            raise ValueError("0x448840 cap loader no longer matches the extracted job row")
        delta = {key: equipped[key] - unequipped[key]
                 for key in ("max_hp", "max_mp", "attack", "defense", "speed", "hit_rate", "magic_attack")}
        delta["resist_by_type"] = {key: equipped["resist_by_type"][key] - unequipped["resist_by_type"][key]
                                   for key in unequipped["resist_by_type"]}
        deltas.append(delta)
        model = swordman_unequipped(source, attrs, level, current_hp, current_mp)
        # Native equipment application occurs before final HP/MP clamping; all Leonard deltas are constant.
        modeled_equipped = _with_delta(model, delta)
        comparable = {key: equipped[key] for key in model}
        if comparable != modeled_equipped:
            raise ValueError(f"SwordMan arithmetic model differs from native refresh for {name}: {comparable} != {modeled_equipped}")
        cases.append({"case": name, "attributes": attrs, "level": level,
                      "input_current_hp": current_hp, "input_current_mp": current_mp,
                      "native_unequipped": unequipped, "native_equipped": equipped})
    equipment_delta = deltas[0]
    if any(delta != equipment_delta for delta in deltas[1:]):
        raise ValueError("Leonard initial equipment deltas are not constant across growth fixtures")

    spans = [
        (0x448370, 61, "job-indexed four-cap loader"),
        (0x448840, 39, "copy base attributes and enter stat refresh"),
        (0x448A64, 365, "jobSwordMan branch through derived stat setup"),
        (0x44B62C, 159, "HP/MP template additions, EXP threshold, and current-value clamps"),
    ]
    return {
        "schema": "hsl_native_growth_refresh.v1",
        "evidence_tier": "static-derived",
        "exe_sha256": EXE_SHA,
        "entry": hex(REFRESH_ENTRY),
        "cap_loader": {"entry": "0x448370", "table_va": hex(CAP_TABLE_VA),
                       "index_formula": "job_code - 80", "rows": cap_rows,
                       "leonard_caps": caps},
        "source_profile": source,
        "initial_equipment_delta": equipment_delta,
        "cases": cases,
        "instruction_budget": 12000,
        "instruction_anchors": [{"address": hex(address), "meaning": meaning,
                                 "bytes": bytes(mapped[address-image_base:address-image_base+size]).hex()}
                                for address, size, meaning in spans],
        "model_scope": [
            "Positive base attributes, no temporary status/buff flags, jobSwordMan (80), Leonard source template.",
            "Initial equipment is represented as a proven constant output delta for this growth slice; equipment transactions remain a later system.",
            "Current HP/MP are only clamped downward by 0x448840; a larger maximum does not refill either current value.",
            "No runtime EXE emulation is used by the product.",
        ],
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--exe", type=Path, default=ORIGINAL_EXE)
    parser.add_argument("--output", type=Path, default=PACKET)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    result = run(args.exe)
    if args.check:
        if json.loads(args.output.read_text(encoding="utf-8")) != result:
            raise ValueError("Native growth refresh packet changed")
    else:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
    print(f"NATIVE_GROWTH_REFRESH_PASS cases={len(result['cases'])}")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (ValueError, OSError, RuntimeError, ImportError) as error:
        print(str(error), file=sys.stderr)
        raise SystemExit(1)
