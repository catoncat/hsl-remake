extends RefCounted
## Read-only self-preservation plans. Source buckets/rates and selector kernels
## are reused; the supported-effect dispatcher is explicitly a remake adapter.
## provenance:
##   rules: static-derived docs/evidence_packets/static_reverse/original_ai_priority.md
##   rules: static-derived docs/evidence_packets/static_reverse/original_support_magic.md
##   rules: provisional (supported-effect dispatcher is a remake adapter; MAGIC-then-SPECIAL cure order)
const SkillResolutionRules = preload("res://game/sim/SkillResolutionRules.gd")
const AISkillDecisionRules = preload("res://game/sim/AISkillDecisionRules.gd")
const AIDecisionRules = preload("res://game/sim/AIDecisionRules.gd")
const SkillResourceRules = preload("res://game/sim/SkillResourceRules.gd")
const SkillTargetRules = preload("res://game/sim/SkillTargetRules.gd")
const StatusEffectRules = preload("res://game/sim/StatusEffectRules.gd")
const ItemUseRules = preload("res://game/sim/ItemUseRules.gd")
const Values = preload("res://game/sim/Values.gd")
const AISkillPlanning = preload("res://game/sim/AISkillPlanning.gd")
const AISupportPlanning = preload("res://game/sim/AISupportPlanning.gd")
const AINavigationRules = preload("res://game/sim/AINavigationRules.gd")
const PositionCapabilityRules = preload("res://game/sim/PositionCapabilityRules.gd")
## RANGE.H index 0: the effect range 0x40cdd3 tests (skill record +0xc via 0x4097f0／0x409810).
const SINGLE_CELL_RANGE := "range0Cell"


static func prepare(loop: Dictionary, actor: Dictionary, envelope: Dictionary = {}, profile: Dictionary = {}) -> Dictionary:
	var item := ItemUseRules.first_status_slot(actor["inventory"],loop["consumables"],int(actor["status_flags"]))
	if not item["ok"]: return item
	var healing: Array = []
	var curing: Array = []
	var book: Dictionary = loop["skill_book"]
	# Self heal (0x43fa29 case): 0x40c570(actor, magic=0x40dc50(), special=0x40e0e0()) offers both channels'
	# heal buckets; the SPECIAL rows come from the same 0x40c620 bucket fill (expend*20 <= stamina).
	for id in book["skills"]:
		var entry: Dictionary = book["skills"][id]
		if not SkillResolutionRules.is_kind(entry["damage_policy"], ["support"]) or SkillResolutionRules.ownership_error(actor, id, book) != "": continue
		var fields: Dictionary = entry["fields"]
		var rate := Values.non_negative_int(fields.get("use_ratio"), true)
		var order := Values.non_negative_int(entry.get("source_order"))
		if rate < 0 or rate > 100 or order < 0 or order > 223: return {"ok": false, "reason": "invalid_support_ai_definition"}
		var ready := SkillResolutionRules.prepare_cast(actor, actor, loop["units"], id, fields, book, loop["skill_target_data"], loop["equipment_items"], actor["coord"], loop["map_size"])
		if not ready["ok"]:
			if ready["reason"] in ["insufficient_mp", "insufficient_stamina", "magic_disabled_by_status", "caster_unavailable", "skill_has_no_effect"]: continue
			return ready
		var bucket := AISkillDecisionRules.buckets(SkillTargetRules.function_mask(fields["function"], loop["skill_target_data"]["function_bits"]), int(loop["skill_target_data"]["ranges"][fields["effect_range"]]["size"]) > 1)
		if bucket.is_empty(): continue # 0x407010 gives pure HealMP (萬息降靈法) no bucket
		var candidate := {"skill_id": id, "source_order": order, "use_ratio": rate, "bucket": bucket[0], "channel": entry["channel"]}
		if bucket[0] in [1, 2] and int(actor["hp"]) < int(actor["max_hp"]): healing.append(candidate)
		elif bucket[0] == 7 and StatusEffectRules.poisoned(actor): curing.append(candidate)
	for group in [healing, curing]: group.sort_custom(func(a, b): return int(a["source_order"]) > int(b["source_order"]))
	var result := {"ok": true, "healing": healing, "curing": curing, "curing_slot":item["index"]}
	if envelope.is_empty() or (healing.is_empty() and curing.is_empty()): return result
	var searched := _cast_search_plan(loop, actor, envelope, profile, healing + curing)
	if not searched["ok"]: return searched
	result["cast_plan"] = searched["plan"]
	return result


## The self cast goes through 0x40d340／0x40df70 with the actor as target, so a moving cast
## (SPECIAL always, MAGIC with move_magic_use; AISkillPlanning.moves_to_cast) runs 0x40cca0:
## the plan carries the threat scan inputs, the flee field and, per row, the (station,
## centre) intents that help the actor itself (AISupportPlanning's support intents with the
## actor as the only recipient; a range0Cell row only needs its own-cell intent).
static func _cast_search_plan(loop: Dictionary, actor: Dictionary, envelope: Dictionary, profile: Dictionary, rows: Array) -> Dictionary:
	var book: Dictionary = loop["skill_book"]
	var capability := PositionCapabilityRules.effects(actor, book, loop["equipment_items"])
	if not capability["ok"]: return capability
	var scan := AISkillPlanning.threat_scan(loop, actor, profile, bool(capability["effects"]["move_magic_use"]))
	if not scan["ok"]: return scan
	var field := flee_field(loop, actor, envelope)
	if not field["ok"]: return field
	var cells: Array = [actor["coord"]]
	for cell in envelope["reachable_coords"]:
		if not cells.has(cell): cells.append(cell)
	cells.sort_custom(AISkillPlanning.cell_before)
	var ctx := {"loop": loop, "actor": actor, "envelope": envelope, "book": book, "capability": capability, "cells": cells}
	for row in rows:
		var id: String = str(row["skill_id"])
		var entry: Dictionary = book["skills"][id]
		var own := {"skill_id": id, "target_id": str(actor["id"]), "primary_target_id": str(actor["id"]), "center_is_primary": true,
			"destination": actor["coord"], "score": 1, "movement_cost": 0, "path": []}
		if field["range0"].has(id):
			row["intents"] = [own]
			continue
		var by_primary := {}
		var failed := AISupportPlanning._collect_support_intents(ctx, id, entry, [actor], by_primary)
		if not failed.is_empty(): return failed
		row["intents"] = by_primary.get(actor["id"], [own])
	var plan := AISkillPlanning.target_plan(str(actor["id"]), "magic", profile, actor, scan)
	plan["flee"] = field
	return {"ok": true, "plan": plan}


## The flee field of a self-targeted moving cast plus the actor's range0Cell skills
## (0x40cdd3 → 0x40cdd9 flees straight away for those).
static func flee_field(loop: Dictionary, actor: Dictionary, envelope: Dictionary) -> Dictionary:
	var field := AINavigationRules.flee_field(loop, actor, envelope)
	if not field["ok"]: return field
	field["range0"] = {}
	var book: Dictionary = loop["skill_book"]
	for id in book["skills"]:
		if str(book["skills"][id]["fields"].get("effect_range", "")) == SINGLE_CELL_RANGE and SkillResolutionRules.ownership_error(actor, id, book) == "":
			field["range0"][id] = true
	return field


## An ally buff that falls back to the caster (0x43fce1..0x43fd46) casts on itself too, so
## its plan carries the same flee field.
static func attach_buff_flee(loop: Dictionary, actor: Dictionary, envelope: Dictionary, self_support: Dictionary, ally_support: Dictionary) -> Dictionary:
	if not ally_support["buff"].has(actor["id"]): return {"ok": true}
	var field: Dictionary = self_support["cast_plan"]["flee"] if self_support.has("cast_plan") else flee_field(loop, actor, envelope)
	if not field["ok"]: return field
	ally_support["buff"][actor["id"]]["flee"] = field
	return {"ok": true}


static func choose_healing(plan: Dictionary, actor: Dictionary, profile: Dictionary, item_slot: int, rng: Variant) -> Dictionary:
	if plan["healing"].is_empty(): return {"kind": "use_item", "item_slot": item_slot} if item_slot >= 0 else {"kind": "ordinary"}
	var order := AIDecisionRules.select_action(profile, int(actor["status_flags"]), _has_channel(plan["healing"], "magic"), _has_channel(plan["healing"], "special"), rng)
	var decision := {"action_selection": order, "composition_evidence": "provisional", "attempts": []}
	for kind in order["order"]:
		if kind == 0 and item_slot >= 0: return {"kind": "use_item", "item_slot": item_slot, "self_skill_decision": decision}
		if kind == 0: continue
		var channel := "special" if kind == 2 else "magic"
		if not _has_channel(plan["healing"], channel): continue
		var area := AISkillDecisionRules.area_order(int(profile["ai_magic_multi_first"]), rng)
		decision["area_order"] = area
		for offensive_bucket in area["order"]:
			var bucket := int(offensive_bucket) - 2
			var members: Array = plan["healing"].filter(func(row): return int(row["bucket"]) == bucket and str(row["channel"]) == channel)
			var chosen := _choose(members, actor, rng, channel, plan.get("cast_plan", {}))
			decision["attempts"].append(chosen["selection"])
			if chosen.has("intent"): return {"kind": "self_skill", "intent": chosen["intent"], "self_skill_decision": decision}
	return {"kind": "ordinary", "self_skill_decision": decision}


static func choose_cure(plan: Dictionary, actor: Dictionary, rng: Variant) -> Dictionary:
	var fallback := {"kind":"use_item","item_slot":int(plan.get("curing_slot",-1))} if int(plan.get("curing_slot",-1))>=0 else {"kind":"ordinary"}
	if plan["curing"].is_empty(): return fallback
	# provisional: the self-cure adapter has no native channel order; the MAGIC bucket is walked
	# first, then the SPECIAL one (萬息秘孔術), then the matching item.
	for channel in ["magic", "special"]:
		var members: Array = plan["curing"].filter(func(row): return str(row["channel"]) == channel)
		if members.is_empty(): continue
		var chosen := _choose(members, actor, rng, channel, plan.get("cast_plan", {}))
		if chosen.has("intent"):
			return {"kind": "self_skill", "intent": chosen["intent"], "self_skill_decision": {"selection": chosen["selection"], "composition_evidence": "provisional", "priority": "self cure before ordinary offense, after HP/dying checks; magic then special bucket, matching item fallback"}}
	return fallback


static func _has_channel(rows: Array, channel: String) -> bool:
	return rows.any(func(row): return str(row["channel"]) == channel)


static func _choose(members: Array, actor: Dictionary, rng: Variant, channel: String = "magic", cast_plan: Dictionary = {}) -> Dictionary:
	var bucket := int(members[0]["bucket"]) if not members.is_empty() else -1
	var selection := AISkillDecisionRules.select_index(members.map(func(row): return int(row["use_ratio"])), rng, channel, bucket)
	selection["skill_ids"] = members.map(func(row): return str(row["skill_id"]))
	var result := {"selection": selection}
	if int(selection["index"]) >= 0:
		var row: Dictionary = members[int(selection["index"])]
		result["intent"] = {"skill_id": row["skill_id"], "destination": actor["coord"], "target_id": str(actor["id"])}
		if cast_plan.is_empty() or not row.has("intents"): return result
		var plan := cast_plan.duplicate()
		plan["channel"] = channel
		# Without a move search (MAGIC lacking move_magic_use, 0x40d402 → 0x40d439) it casts in place.
		if not AISkillPlanning.moves_to_cast(plan): return result
		var searched := AISkillPlanning.cast_station(plan, row, rng, {})
		selection["cast_search"] = searched["decision"]
		if not searched["intent"].is_empty(): result["intent"] = searched["intent"]
	return result
