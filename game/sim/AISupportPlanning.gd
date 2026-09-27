extends RefCounted
## Per-turn immutable support intents over the same legal movement envelope and
## skill transaction as player/offense. Native scans and current-grid policy are
## separate: no actor, resource, RNG or queue is owned by this planner.
## provenance:
##   rules: static-derived docs/evidence_packets/static_reverse/original_ai_support.md; static-derived docs/evidence_packets/static_reverse/original_player_mode_sides.md; static-derived docs/evidence_packets/static_reverse/original_skill_function_bits.md; provisional (destination enumeration, effective coverage and live-id adapters)
##   layout: n/a
##   strings: n/a
##   timing: n/a
##   audio: n/a
const Rules = preload("res://game/sim/AISupportRules.gd")
const Resolution = preload("res://game/sim/SkillResolutionRules.gd")
const Targets = preload("res://game/sim/SkillTargetRules.gd")
const Skills = preload("res://game/sim/AISkillPlanning.gd")
const Decisions = preload("res://game/sim/AISkillDecisionRules.gd")
const Actions = preload("res://game/sim/AIDecisionRules.gd")
const Costs = preload("res://game/sim/SkillResourceRules.gd")
const Status = preload("res://game/sim/StatusEffectRules.gd")
const Items = preload("res://game/sim/ItemUseRules.gd")
const Position = preload("res://game/sim/PositionCapabilityRules.gd")
const Navigation = preload("res://game/sim/AINavigationRules.gd")
## RANGE row 1 (range1Cell), the range 0x40d530 hands 0x40fa80 round the patient: its four
## orthogonal neighbours.
const ITEM_REACH := [Vector2i(0, -1), Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, 1)]
const SUPPORT_POLICIES := ["native_magic_support", "native_magic_stat", "native_special_support", "native_special_stat"]


static func prepare(loop: Dictionary, actor: Dictionary, envelope: Dictionary, rows: Array, owner_index: int, profile: Dictionary, healing_slot: int = -1) -> Dictionary:
	var result := {"ok": true, "heal": {}, "status": {}, "buff": {}, "buff_masks": [], "items": {}, "status_items": {}, "rows": rows, "owner_index": owner_index}
	var book: Dictionary = loop["skill_book"]
	var ids: Array = []
	# 0x40c620 fills the SPECIAL buckets (+0x38..) next to the MAGIC ones with the same 0x407010
	# classifier; the ally checks 0x40c570(actor, magic=0x40dc50/0x40dc70/0x40dcf0, special=0x40e0e0/0x40e100/0x40e180)
	# then offer both channels.
	for id in book["skills"]:
		var entry: Dictionary = book["skills"][id]
		if entry["damage_policy"] in SUPPORT_POLICIES and Targets.is_support(entry["fields"], loop["skill_target_data"]) and Resolution.ownership_error(actor, id, book) == "": ids.append(id)
	var curing := Items.first_status_slot(actor["inventory"], loop["consumables"], 15)
	if not curing["ok"]: return curing
	if ids.is_empty() and healing_slot < 0 and curing["index"] < 0: return result
	var capability := Position.effects(actor, book, loop["equipment_items"])
	if not capability["ok"]: return capability
	var error := Rules.profile_error(profile, true)
	if error != "": return {"ok": false, "reason": error}
	if Costs._integer(profile.get("ai_magic_multi_first")) not in [0,1]: return {"ok": false, "reason": "missing_ai_magic_multi_first"}
	var primaries: Array = []
	var foes: Array = []
	for unit in loop["units"]:
		if not Targets._living(unit): continue
		if unit.get("battle_actor_role") not in Targets.ROLES: return {"ok": false, "reason": "unsupported_target_role"}
		if Targets.Sides.hostile(actor, unit):
			foes.append(unit)
			continue
		error = Status.input_error(unit)
		if error != "": return {"ok": false, "reason": error}
		if unit["id"] != actor["id"] and Rules.Priority.within_square(unit["coord"], actor["coord"], Rules.SEARCH_RADIUS): primaries.append(unit)
	foes.sort_custom(func(a, b): return Skills._cell_before(a["coord"], b["coord"]))
	# The buff check also plans the caster itself: 0x43fce1..0x43fd46 falls back to it (see choose).
	if primaries.is_empty() and ids.is_empty(): return result
	var cells: Array = [actor["coord"]]
	for cell in envelope["reachable_coords"]:
		if not cells.has(cell): cells.append(cell)
	cells.sort_custom(Skills._cell_before)
	if healing_slot >= 0:
		var code := str(int(actor["inventory"][healing_slot]))
		for primary in primaries:
			var effect := Items.prepare(primary,loop["consumables"][code])
			if not effect["ok"]:
				if effect["reason"] == "item_has_no_effect": continue
				return effect
			var selected := _item_intent(actor, primary, envelope, healing_slot, code)
			if selected.is_empty(): continue
			result["items"][primary["id"]] = selected
			result["heal"][primary["id"]] = Skills._target_plan(primary["id"],"magic",profile,actor,foes)
	if curing["index"] >= 0:
		for primary in primaries:
			var slot := Items.first_status_slot(actor["inventory"], loop["consumables"], int(primary["status_flags"]))
			if not slot["ok"]: return slot
			if slot["index"] < 0: continue
			var code := str(int(actor["inventory"][int(slot["index"])]))
			var effect := Items.prepare(primary, loop["consumables"][code])
			if not effect["ok"]: continue
			var selected := _item_intent(actor, primary, envelope, int(slot["index"]), code)
			if selected.is_empty(): continue
			result["status_items"][primary["id"]] = selected
			result["status"][primary["id"]] = Skills._target_plan(primary["id"], "magic", profile, actor, foes)
	for id in ids:
		var entry: Dictionary = book["skills"][id]
		var fields: Dictionary = entry["fields"]
		var rate := Costs._integer(fields.get("use_ratio"), true)
		var source_order := Costs._integer(entry.get("source_order"))
		if rate < 0 or rate > 100 or source_order < 0 or source_order > 223: return {"ok": false, "reason": "invalid_support_ai_definition"}
		var available := Resolution.available(actor, id, fields, book, loop["skill_target_data"], loop["equipment_items"])
		if not available["ok"]:
			if available["reason"] in ["insufficient_mp", "insufficient_stamina", "magic_disabled_by_status", "caster_unavailable"]: continue
			return available
		var mask := Targets.function_mask(fields["function"], loop["skill_target_data"]["function_bits"])
		var area: bool = int(loop["skill_target_data"]["ranges"][fields["effect_range"]]["size"]) > 1
		# 0x407010 buckets: heal 1 (area) / 2, buff 5, cure 7. A row without one (萬息降靈法, pure HealMP) is never dispatched.
		var buckets := Decisions.buckets(mask, area)
		var bucket := 1 if buckets.has(1) else 2 if buckets.has(2) else 5 if buckets.has(5) else 7 if buckets.has(7) else -1
		if bucket < 0: continue
		var kind := "heal" if bucket in [1, 2] else "buff" if bucket == 5 else "status"
		var recipients: Array = primaries + [actor] if kind == "buff" else primaries
		if kind == "buff":
			result["buff_masks"].append(mask)
		elif not primaries.any(func(unit): return int(unit["hp"]) < int(unit["max_hp"]) if kind == "heal" else Resolution.Support.cures_something(unit, mask)): continue
		var by_primary := {}
		for cell in cells:
			if cell != actor["coord"] and entry["channel"] == "magic" and not capability["effects"]["move_magic_use"]: continue
			var cast_cells := Targets.cells(cell, fields, loop["skill_target_data"], loop["map_size"])
			for coord in Targets.candidate_centers(actor, loop["units"], fields, loop["skill_target_data"], loop["map_size"], cell):
				if not cast_cells.has(coord): continue
				var center := Skills.target_for_center(actor, loop["units"], fields, loop["skill_target_data"], loop["map_size"], cell, coord)
				var ready := Resolution.prepare_cast(actor, center, loop["units"], id, fields, book, loop["skill_target_data"], loop["equipment_items"], cell, loop["map_size"], coord)
				if not ready["ok"]:
					if ready["reason"] in ["out_of_range", "skill_has_no_effect"]: continue
					return ready
				var useful := Skills.useful_ids(ready)
				var affected: Array = ready["targets"].map(func(target): return str(target["id"]))
				for primary in recipients:
					if not useful.has(primary["id"]): continue
					if not by_primary.has(primary["id"]): by_primary[primary["id"]] = []
					var route: Dictionary = envelope["reachable_by_coord"].get(cell, {})
					by_primary[primary["id"]].append({"skill_id": id, "target_id": str(center["id"]), "cast_center": coord,
						"primary_target_id": str(primary["id"]), "center_is_primary": Targets.Footprint.contains(primary,coord), "destination": cell, "affected_ids": affected,
						"useful_ids": useful, "score": useful.size(), "movement_cost": 0 if cell == actor["coord"] else int(route["cost"]),
						"path": [] if cell == actor["coord"] else route["path"]})
		for primary_id in by_primary:
			if not result[kind].has(primary_id): result[kind][primary_id] = Skills._target_plan(primary_id, "magic", profile, actor, foes)
			result[kind][primary_id]["skills"].append({"skill_id": id, "source_order": source_order, "use_ratio": rate,
				"bucket": bucket, "channel": entry["channel"], "intents": by_primary[primary_id]})
	return result


## The medicine walk 0x40d530(actor, patient, 1): the actor's move flood (0x40f440; its own
## occupancy is NOT lifted, unlike the attack station 0x40d8b0) ∩ range 1 round the patient
## (0x40fa80; a 3×3 patient tries its body cells in LARGE_TARGET_CENTRES order, first centre
## with a station) ∩ no unit, collected row-major by 0x413390. The actor's own cell is never a
## station: a helper already beside the patient still steps to another free side (emulator-
## measured, level 51: 024_2 at (16,17) beside Leonard (15,17) moves to (15,18), then uses 241).
## `destination` here is the order before the equal-key coins, which choose() draws.
static func _item_intent(actor: Dictionary, primary: Dictionary, envelope: Dictionary, slot: int, code: String) -> Dictionary:
	var anchor: Vector2i = primary["coord"]
	var centres: Array = [anchor]
	if Targets.Footprint.radius(primary) == 1: centres = Navigation.LARGE_TARGET_CENTRES.map(func(delta): return anchor + delta)
	for centre in centres:
		var stations: Array = []
		for offset in ITEM_REACH:
			var cell: Vector2i = centre + offset
			if cell != actor["coord"] and envelope["reachable_by_coord"].has(cell):
				stations.append({"cell": cell, "cost": int(envelope["reachable_by_coord"][cell]["cost"])})
		if stations.is_empty(): continue
		stations.sort_custom(func(a, b): return Skills._cell_before(a["cell"], b["cell"]))
		return _item_station({"target_id": str(primary["id"]), "item_slot": slot, "item_code": code, "centre": centre, "stations": stations}, func(_n: int) -> int: return 0)
	return {}


## 0x413390 over the medicine stations (AINavigationRules.station_order): farthest from the
## range centre first, an equal key swapping with the entry before it on raw & 1 (0x4136ba),
## drawn when 0x40d530 runs — after 0x40c570 picked the item category.
static func _item_station(choice: Dictionary, rng: Variant) -> Dictionary:
	var sorted := Navigation.station_order(choice, rng)
	var cell: Vector2i = sorted["order"][0]
	var intent := choice.duplicate()
	intent.merge({"destination": cell, "movement_cost": int(choice["stations"].filter(func(entry): return entry["cell"] == cell)[0]["cost"]),
		"station_order": sorted["order"], "station_draws": sorted["draws"]}, true)
	return intent


static func choose(prepared: Dictionary, actor: Dictionary, profile: Dictionary, units: Array, rng: Variant, carried_roll: int = -1) -> Dictionary:
	var attempted := (4 if prepared["heal"].is_empty() else 0) | (8 if prepared["status"].is_empty() else 0) | (16 if prepared["buff"].is_empty() else 0)
	var decision := {"checks": [], "scans": [], "attempts": [], "composition_evidence": "provisional",
		"source": "original_ai_support", "search_radius": Rules.SEARCH_RADIUS,
		"geometry_policy": "current legal movement, useful allied coverage, existing farthest-threat selector"}
	if attempted == 28: return {"kind": "ordinary", "lock_roll": carried_roll}
	var roll := carried_roll
	while attempted != 28:
		if roll < 1: roll = Rules.Decision._draw(99, rng, []) + 1
		var phase := Rules.next_check(profile, attempted, roll, rng, true)
		attempted = phase["attempted"]
		decision["checks"].append(phase)
		if phase["mode"] == 0: return {"kind": "ordinary", "support_decision": decision, "lock_roll": phase["next_roll"]}
		var kind := "heal" if phase["mode"] == 3 else "buff" if phase["mode"] == 6 else "status"
		var buckets: Array = [5] if kind == "buff" else [7]
		if kind == "heal":
			var area := Decisions.area_order(int(profile["ai_magic_multi_first"]), rng)
			buckets = area["order"].map(func(bucket): return int(bucket) - 2)
			decision["healing_bucket_order"] = area
		# 0x40c2f0／0x40c3a0／0x40c480 walk the object array 0x4c34c0 (slot 0..199), the order
		# 0x40bb80 uses: the rows go in registry order and the found slot maps back to the roster.
		var layout: Array = prepared.get("registry", [])
		var scan_rows: Array = Rules.Decision.registry_rows(prepared["rows"], layout)
		var owner_slot: int = layout.find(int(prepared["owner_index"])) if not layout.is_empty() else int(prepared["owner_index"])
		var cursor := 0
		var self_target := false
		while cursor < scan_rows.size() and not self_target:
			var scan := Rules.scan(scan_rows, owner_slot, kind, cursor, Rules.SEARCH_RADIUS, rng, prepared["buff_masks"])
			decision["scans"].append(scan)
			var id: String
			if scan["index"] >= 0:
				cursor = scan["next_cursor"]
				id = units[int(layout[int(scan["index"])]) if not layout.is_empty() else int(scan["index"])]["id"]
			# 0x43fce1..0x43fd46: when the fresh ally scan 0x40c480 finds nobody, the caster's own
			# mask (0x40c2d0) through 0x40dcf0／0x40e180 makes it the target; once that fails the
			# continuation 0x440a3b stops at target == self. After an ally was found it never falls back.
			elif kind == "buff" and cursor == 0 and Rules.buff_useful(prepared["buff_masks"], int(actor["status_flags"]) & 0x70):
				self_target = true
				id = str(actor["id"])
				decision["self_target"] = {"mask": int(actor["status_flags"]) & 0x70, "source": "0x43fce1..0x43fd46"}
			else:
				break
			if not prepared[kind].has(id): continue
			var plan: Dictionary = prepared[kind][id]
			var categories: Dictionary
			if kind == "buff":
				# 0x440a86..0x440ad3: the buff aid draws one AI random (0x458c10) and its low bit orders
				# magic (0) / special (1); two attempts, no item category, no ai_att_* probability.
				var draws: Array = []
				var special_first := Rules.Decision._draw(2, rng, draws) != 0
				categories = {"ok": true, "kind": 2 if special_first else 1, "order": [2, 1] if special_first else [1, 2], "draws": draws, "source": "0x440a86..0x440ad3"}
			else:
				# 0x440796 / 0x440959: 0x40c570(actor, magic bucket non-empty, special bucket non-empty).
				categories = Actions.select_action(profile, int(actor["status_flags"]), _has_channel(plan, "magic"), _has_channel(plan, "special"), rng)
			for category in categories["order"]:
				var item_pool: Dictionary = prepared["items"] if kind == "heal" else {} if kind == "buff" else prepared["status_items"]
				if category == 0 and item_pool.has(id):
					decision["item_action_selection"] = categories
					return {"kind":"ally_item","intent":_item_station(item_pool[id], rng),"support_decision":decision}
				if category == 0: continue
				var channel := "special" if category == 2 else "magic"
				if not _has_channel(plan, channel): continue
				var chosen := Skills.choose(_channel_plan(plan, channel), rng, buckets)
				chosen["decision"]["action_selection"] = categories
				decision["attempts"].append(chosen["decision"])
				if not chosen["intent"].is_empty():
					return {"kind": "ally_skill", "intent": chosen["intent"], "support_decision": decision}
		roll = -1 # Native unavailable-category path returns to the next priority iteration.
	return {"kind": "ordinary", "support_decision": decision}


static func _has_channel(plan: Dictionary, channel: String) -> bool:
	return plan["skills"].any(func(row): return str(row["channel"]) == channel)


## One channel's slice of a support plan: 0x40c570 picks the channel before 0x40c770 / 0x40dd80 walks its bucket.
static func _channel_plan(plan: Dictionary, channel: String) -> Dictionary:
	var sliced := plan.duplicate()
	sliced["channel"] = channel
	sliced["skills"] = plan["skills"].filter(func(row): return str(row["channel"]) == channel)
	return sliced
