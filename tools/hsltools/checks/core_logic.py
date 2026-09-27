"""Validate tracked hsl core_logic packet against schema and function-index anchors.

Registry task core_logic_check (family checks, CheckTask): the detail lines the script prints after
"PASS hsl_core_logic_check" are still printed, the PASS line is the task summary. Bodies (main included)
moved verbatim from the former hsl_core_logic_check.py; main takes argv for in-process use.
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

from hsltools.checks import CheckTask
from hsltools.data import printed_last_line
from hsltools.registry import Context

REQUIRED_TOP = (
    "schema",
    "globals",
    "struct_maps",
    "stat_refresh",
    "equip_apply",
    "combat_resolution",
    "wrd_terrain_format",
    "not_yet_recovered",
    "godot_constraints",
)
FORBIDDEN_KEYS = {
    "raw_bytes",
    "disassembly",
    "instruction_text",
    "private_path",
    "hash",
    "sha256",
    "md5",
}
# Provisional field names that must NOT appear in live_actor_combat_fields
# after the str/dex join landed.
DEPRECATED_LIVE_NAMES = {
    "level_like_or_exp_proxy",
    "speed_or_level_proxy",
    "live_magic_or_alt_damage",
    "stamina_like",
}


def _walk(obj, path="$"):
    if isinstance(obj, dict):
        for key, value in obj.items():
            low = str(key).lower()
            if low in FORBIDDEN_KEYS or low.endswith("_hash"):
                yield path + "." + key
            yield from _walk(value, path + "." + key)
    elif isinstance(obj, list):
        for i, value in enumerate(obj):
            yield from _walk(value, f"{path}[{i}]")


def _collect_addrs(obj, found: set[str]) -> None:
    if isinstance(obj, dict):
        for key, value in obj.items():
            if key in {
                "address",
                "source_function",
                "also_seen_as",
                "also_seen_mid_body_as",
                "parent_address",
                "damage_call",
                "hit_call",
                "queue_call",
                "exp_call",
                "end_address",
                "registration_site",
                "player_twin_address",
                "jump_table",
                "remap_table",
                "entry",
            } and isinstance(value, str):
                if value.startswith("0x"):
                    # Some historical address references contain multiple anchors.
                    for part in value.split("/"):
                        part = part.strip()
                        if part.startswith("0x"):
                            found.add(part.lower())
            if key == "address_window" and isinstance(value, str) and ".." in value:
                for part in value.split(".."):
                    part = part.strip().lower()
                    if part.startswith("0x"):
                        found.add(part)
            if key in {"source_functions", "address_examples", "calls", "driver_sites"} and isinstance(value, list):
                for item in value:
                    if isinstance(item, str) and item.startswith("0x"):
                        found.add(item.lower())
            _collect_addrs(value, found)
    elif isinstance(obj, list):
        for item in obj:
            _collect_addrs(item, found)


def load_function_addrs(functions_json: Path) -> set[str]:
    data = json.loads(functions_json.read_text(encoding="utf-8"))
    out: set[str] = set()
    rows = data if isinstance(data, list) else data.get("functions") or data.get("entries") or []
    for row in rows:
        if not isinstance(row, dict):
            continue
        for key in ("offset", "addr", "address", "vaddr", "minbound"):
            if key in row:
                raw = row[key]
                if isinstance(raw, int):
                    out.add(f"0x{raw:x}")
                elif isinstance(raw, str):
                    try:
                        out.add(f"0x{int(raw, 0):x}")
                    except ValueError:
                        pass
                break
    return out


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "packet",
        nargs="?",
        default="content/generated/hsl/static/hsl01/core_logic.json",
    )
    parser.add_argument(
        "--functions-json",
        default="ignored/static/hsl01/functions.json",
        help="Optional local function index for address existence checks",
    )
    parser.add_argument("--require-functions-index", action="store_true")
    args = parser.parse_args(argv)

    path = Path(args.packet)
    if not path.is_file():
        print(f"FAIL missing packet: {path}", file=sys.stderr)
        return 2
    packet = json.loads(path.read_text(encoding="utf-8"))
    errors: list[str] = []

    if packet.get("schema") != "hsl_core_logic.v1":
        errors.append(f"unexpected schema: {packet.get('schema')!r}")
    for key in REQUIRED_TOP:
        if key not in packet:
            errors.append(f"missing top-level key: {key}")

    bad = list(_walk(packet))
    if bad:
        errors.append("forbidden raw/private-like keys: " + ", ".join(bad[:12]))

    cr = packet.get("combat_resolution") or {}
    hit = cr.get("hit_chance") or {}
    if hit.get("address") != "0x409a60":
        errors.append("hit_chance.address must be 0x409a60")
    if not isinstance(hit.get("pseudocode"), list) or len(hit.get("pseudocode") or []) < 5:
        errors.append("hit_chance.pseudocode must list the recovered formula steps")
    dmg = cr.get("damage") or {}
    if dmg.get("address") != "0x409be0":
        errors.append("damage.address must point at the executed entry0x409be0, not preceding padding")
    item_fields = (((packet.get("struct_maps") or {}).get("item_record") or {}).get("fields") or {})
    for required in ("attack_damage", "hit_ratio"):
        if required not in item_fields:
            errors.append(f"item_record.fields missing {required}")

    # stat_refresh section
    sr = packet.get("stat_refresh") or {}
    if sr.get("address") != "0x448840":
        errors.append("stat_refresh.address must be 0x448840")
    sr_map = sr.get("field_copy_map") or {}
    if "base_str_0x64" not in sr_map or "base_dex_0x68" not in sr_map:
        errors.append("stat_refresh.field_copy_map must contain base_str/base_dex entries")

    # live_actor field naming — provisional names must be gone
    live_fields = (((packet.get("struct_maps") or {}).get("live_actor_combat_fields") or {}).get("fields") or {})
    for bad_name in DEPRECATED_LIVE_NAMES:
        if bad_name in live_fields:
            errors.append(f"live_actor_combat_fields still uses deprecated name: {bad_name}")
    for required in ("str", "dex", "mind", "con"):
        if required not in live_fields:
            errors.append(f"live_actor_combat_fields.fields missing resolved name: {required}")
    if live_fields.get("str") != "0x4c":
        errors.append("live_actor str must be at 0x4c")
    if live_fields.get("dex") != "0x50":
        errors.append("live_actor dex must be at 0x50")
    if live_fields.get("live_speed") != "0xb8":
        errors.append("live_actor live_speed must be at 0xb8 (corrected from magic_or_alt)")
    if live_fields.get("live_magic_attack_power") != "0xd0":
        errors.append("live_actor live_magic_attack_power must be at 0xd0")

    # WRD pathfinding
    wrd_pf = packet.get("wrd_pathfinding") or {}
    if wrd_pf:
        loader = wrd_pf.get("loader") or {}
        if loader.get("wrd_load") != "0x46bb65":
            errors.append("wrd_pathfinding.loader.wrd_load must be 0x46bb65")
        flood = wrd_pf.get("reachability_flood") or {}
        if flood.get("entry") != "0x40f8b0":
            errors.append("wrd_pathfinding.reachability_flood.entry must be 0x40f8b0")
        if flood.get("recursive_expand") != "0x40f5d0":
            errors.append("wrd_pathfinding.reachability_flood.recursive_expand must be 0x40f5d0")
        step = flood.get("step_cost") or {}
        if "budget - 1" not in str(step.get("rule", "")) and "budget := budget - 1" not in str(step.get("rule", "")):
            errors.append("wrd_pathfinding step_cost.rule must document uniform budget-1")
        attr_blk = wrd_pf.get("attribute_byte_blocking") or {}
        if attr_blk.get("entry") != "0x40f200" or attr_blk.get("flood") != "0x40ed50":
            errors.append("wrd_pathfinding.attribute_byte_blocking must name 0x40f200/0x40ed50")
        join = attr_blk.get("level051_join") or {}
        if join.get("blocking_mechanism") != "attribute_delta > 2 in 0x40ed50 (walkable to 0xff yields delta 0xff)":
            errors.append("wrd_pathfinding.attribute_byte_blocking.level051_join must document attribute-delta gate")
        if not wrd_pf.get("level051_observation", {}).get("blocking_mechanism_recovered"):
            errors.append("wrd_pathfinding.level051_observation.blocking_mechanism_recovered must be true")

    btg = packet.get("battle_turn_gating") or {}
    if btg:
        cq = btg.get("command_queue") or {}
        if cq.get("current_object") != "0x407540":
            errors.append("battle_turn_gating.command_queue.current_object must be 0x407540")
        gates = btg.get("ai_process_gates") or {}
        gwc = gates.get("gate_when_current_object") or {}
        reqs = gwc.get("requires") or []
        if not any("0x4c1ba0" in str(r) for r in reqs):
            errors.append("battle_turn_gating must require *0x4c1ba0 in gate_when_current_object")
        if btg.get("player_command_process", {}).get("address") != "0x4038a0":
            errors.append("battle_turn_gating.player_command_process.address must be 0x4038a0 (AnimalDefense; corrected label)")
        bcmd = btg.get("bcmd_click_process") or {}
        if bcmd.get("address") != "0x43e5d0" or bcmd.get("process_table_slot") != 14:
            errors.append("battle_turn_gating.bcmd_click_process must be slot 14 / 0x43e5d0")
        if bcmd.get("defProc_name") != "defProcBattleCommandString":
            errors.append("bcmd_click_process.defProc_name must be defProcBattleCommandString")
        sort = (btg.get("command_queue") or {}).get("sort_key") or {}
        if sort.get("field") != "live_actor+0xb8":
            errors.append("battle_turn_gating.command_queue.sort_key.field must be live_actor+0xb8")
        tick = btg.get("turn_tick") or {}
        bit4 = ((tick.get("live_actor_status_0x24_bits") or {}).get("bit_0x4") or {})
        if bit4.get("role") != "paralysis":
            errors.append("live_actor+0x24 bit 0x4 must map to paralysis, independently of queue-ready metadata")
        cap = btg.get("capability_flag_word") or {}
        if cap.get("live_offset") != "0xa0":
            errors.append("battle_turn_gating.capability_flag_word.live_offset must be 0xa0")
        helpers = cap.get("helpers") or {}
        bb = helpers.get("0x446bb0") or {}
        if "SET skips" not in str(bb.get("polarity", "")):
            errors.append("0x446bb0 polarity must document SET skips turn wake")
        pup = btg.get("player_unit_process") or {}
        if pup.get("address") != "0x443330":
            errors.append("battle_turn_gating.player_unit_process.address must be 0x443330")
        pt_fields = ((packet.get("struct_maps") or {}).get("player_template") or {}).get("fields") or {}
        capf = pt_fields.get("capability_flags") or {}
        bits = capf.get("bits") or {}
        if bits.get("0x2") != "no_attack" or bits.get("0x20") != "no_showshape":
            errors.append("player_template.capability_flags must map 0x2=no_attack and 0x20=no_showshape")
        eth = btg.get("end_turn_handoff") or {}
        if (eth.get("status_tickdown") or {}).get("address") != "0x40b910":
            errors.append("battle_turn_gating.end_turn_handoff.status_tickdown.address must be 0x40b910")
        pag = eth.get("post_action_effect_gate") or {}
        if pag.get("address") != "0x40e3b0":
            errors.append("end_turn_handoff.post_action_effect_gate.address must be 0x40e3b0")
        sites = eth.get("sites") or []
        if not any("0x407510" in str(s.get("sequence")) for s in sites):
            errors.append("end_turn_handoff.sites must include 0x407510 handoff sequence")
        menu = btg.get("player_menu_entry") or {}
        if (menu.get("menu_builder") or {}).get("address") != "0x43ea30":
            errors.append("player_menu_entry.menu_builder.address must be 0x43ea30")
        icons = btg.get("bcmd_icon_codes") or {}
        codes = icons.get("codes") or {}
        if (codes.get("n") or {}).get("command") != "move" or (codes.get("q") or {}).get("command") != "wait":
            errors.append("bcmd_icon_codes must join n→move and q→wait via obj_BCmd*")
        if (codes.get("o") or {}).get("ascii") != 111:
            errors.append("bcmd_icon_codes.o.ascii must be 111 (obj_BCmdAttack)")
        ibt = btg.get("input_bit_test") or {}
        if ibt.get("address") != "0x45b554":
            errors.append("battle_turn_gating.input_bit_test.address must be 0x45b554")
        if "input bitmap" not in str(ibt.get("summary", "")).lower() and "input bit" not in str(ibt.get("summary", "")).lower():
            errors.append("input_bit_test.summary must describe input bitmap test (not menu dispatch)")
        wr = pt_fields.get("wait_round") or {}
        if wr.get("byte") != "0x1b8":
            errors.append("player_template.wait_round.byte must be 0x1b8")

    # WRD terrain format
    wrd = packet.get("wrd_terrain_format") or {}
    if wrd.get("evidence_tier") != "static-derived":
        errors.append("wrd_terrain_format.evidence_tier must be static-derived")
    wrd_fmt = wrd.get("format") or {}
    if wrd_fmt.get("magic") != "WORL":
        errors.append("wrd_terrain_format.format.magic must be WORL")
    wrd_stats = wrd.get("level051_stats") or {}
    if wrd_stats.get("width") != 24 or wrd_stats.get("height") != 24:
        errors.append("wrd_terrain_format.level051_stats must be 24x24")

    ai = packet.get("ai_decision_layers") or {}
    if ai:
        action = ai.get("action_selection") or {}
        target = ai.get("target_selection") or {}
        if action.get("address") != "0x40c570":
            errors.append("ai action_selection.address must be 0x40c570")
        if target.get("address") != "0x40bb80":
            errors.append("ai target_selection.address must be 0x40bb80")
        consts = ai.get("type_constants") or {}
        if consts.get("AI_NEAREST") != 3 or consts.get("AI_FAREST") != 4:
            errors.append("ai type_constants must retain TYPE.H AI_NEAREST/AI_FAREST values")
        proc = ai.get("object_process_ai") or {}
        if proc:
            if proc.get("address") != "0x43ede0":
                errors.append("ai object_process_ai.address must be 0x43ede0")
            if proc.get("also_seen_mid_body_as") != "0x43f400":
                errors.append("ai object_process_ai.also_seen_mid_body_as must be 0x43f400")
            table = proc.get("process_table") or {}
            if table.get("address") != "0x477c2c":
                errors.append("ai object_process_ai.process_table.address must be 0x477c2c")
            if table.get("slot_index_ai_process") != 5:
                errors.append("ai process_table.slot_index_ai_process must be 5")
            cases = ((proc.get("main_ai_mode_cases") or {}).get("cases") or [])
            if len(cases) != 16:
                errors.append("ai main_ai_mode_cases.cases must list 16 cases")
        layers = ai.get("layer_separation") or {}
        if layers:
            ids = {row.get("id") for row in (layers.get("layers") or []) if isinstance(row, dict)}
            for required in (
                "object_process_tick",
                "action_selection",
                "target_selection",
                "movement_path_helpers",
                "actor_response_ordering",
            ):
                if required not in ids:
                    errors.append(f"ai layer_separation missing layer id: {required}")
            ordering = next(
                (
                    row
                    for row in (layers.get("layers") or [])
                    if isinstance(row, dict) and row.get("id") == "actor_response_ordering"
                ),
                {},
            )
            if ordering.get("status") not in {"partially_recovered", "unresolved"}:
                errors.append(
                    "actor_response_ordering.status must be partially_recovered or unresolved"
                )
            if ordering.get("status") == "partially_recovered":
                if ordering.get("address") != "0x45f5f7":
                    errors.append(
                        "actor_response_ordering.address must be 0x45f5f7 when partially_recovered"
                    )
            dispatch = ai.get("engine_object_process_dispatch") or {}
            if dispatch:
                if (dispatch.get("dispatcher") or {}).get("address") != "0x45f5f7":
                    errors.append(
                        "engine_object_process_dispatch.dispatcher.address must be 0x45f5f7"
                    )
                if (dispatch.get("frame_callback") or {}).get("address") != "0x42d600":
                    errors.append(
                        "engine_object_process_dispatch.frame_callback.address must be 0x42d600"
                    )
                if (dispatch.get("spawn_into_buckets") or {}).get("address") != "0x45e307":
                    errors.append(
                        "engine_object_process_dispatch.spawn_into_buckets.address must be 0x45e307"
                    )
                pnts = dispatch.get("process_name_to_slot") or {}
                battle = pnts.get("battle_relevant") or {}
                bcmd_slot = battle.get("defProcBattleCommandString") or {}
                if bcmd_slot.get("slot") != 14 or bcmd_slot.get("address") != "0x43e5d0":
                    errors.append(
                        "process_name_to_slot.defProcBattleCommandString must be slot 14 / 0x43e5d0"
                    )
                enemy = battle.get("defProcEnemy") or {}
                if enemy.get("slot") != 5 or enemy.get("address") != "0x43ede0":
                    errors.append("process_name_to_slot.defProcEnemy must be slot 5 / 0x43ede0")

    addrs: set[str] = set()
    _collect_addrs(packet, addrs)
    functions_path = Path(args.functions_json)
    if functions_path.is_file():
        known = load_function_addrs(functions_path)
        if known:
            missing = sorted(a for a in addrs if a not in known and all(not (int(a, 16) >= int(k, 16) and int(a, 16) < int(k, 16) + 0x1000) for k in list(known)[:0]))
            # soft check: core anchors must appear as function starts or near known entries
            core = {"0x409a60", "0x448420", "0x448840", "0x4423c0", "0x4477c0", "0x44b980", "0x42c780"}
            soft_missing = [a for a in core if a not in known]
            # allow if any known function start equals
            if soft_missing:
                # Also accept if functions.json uses non-zero padded keys etc — already normalized
                errors.append("function-index missing core anchors: " + ", ".join(soft_missing))
    elif args.require_functions_index:
        errors.append(f"missing functions index: {functions_path}")

    if errors:
        print("FAIL hsl_core_logic_check")
        for err in errors:
            print(" -", err)
        return 1

    print("PASS hsl_core_logic_check")
    print(f" packet={path}")
    print(f" hit={hit.get('address')} damage={dmg.get('address')} equip={packet['equip_apply']['address']} refresh={sr.get('address')}")
    print(f" tracked_addrs={len(addrs)}")
    return 0


class CoreLogicCheckTask(CheckTask):
    name = 'core_logic_check'
    family = 'checks'
    inputs = ('content/generated/hsl/static/hsl01/core_logic.json',)
    replaces = ('tools/hsl_core_logic_check.py',)
    scripts = ('tools/hsltools/checks/core_logic.py',)

    def check(self, ctx: Context) -> str:
        return printed_last_line(main, [], marker='PASS')


def tasks() -> list[CoreLogicCheckTask]:
    return [CoreLogicCheckTask()]


if __name__ == '__main__':
    raise SystemExit(main())
