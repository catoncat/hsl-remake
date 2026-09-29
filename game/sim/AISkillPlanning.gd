extends RefCounted
## Read-only plans over the current PlayLoop. No battle state is stored here.
## provenance:
##   rules: static-derived docs/evidence_packets/static_reverse/original_ai_skills.md
##   rules: static-derived docs/evidence_packets/static_reverse/original_player_mode_sides.md
##   rules: provisional (legal-intent enumeration over the current WRD grid, per-channel draw of 0x40d4e0)
const AISkillDecisionRules = preload("res://game/sim/AISkillDecisionRules.gd")
const SkillResolutionRules = preload("res://game/sim/SkillResolutionRules.gd")
const SkillTargetRules = preload("res://game/sim/SkillTargetRules.gd")
const SkillResourceRules = preload("res://game/sim/SkillResourceRules.gd")
const CoreCombatRules = preload("res://game/sim/CoreCombatRules.gd")
const PositionCapabilityRules = preload("res://game/sim/PositionCapabilityRules.gd")
const StatusCatalog = preload("res://game/sim/StatusCatalog.gd")
const Values = preload("res://game/sim/Values.gd")
const TacticalGridRules = preload("res://game/sim/TacticalGridRules.gd")
const BattlePresenceRules = preload("res://game/sim/BattlePresenceRules.gd")
const RangePropagationRules = preload("res://game/sim/RangePropagationRules.gd")
const TerrainEditRules = preload("res://game/sim/TerrainEditRules.gd")
const AIDecisionRules = preload("res://game/sim/AIDecisionRules.gd")
const CoreTurnQueue = preload("res://game/sim/CoreTurnQueue.gd")


static func prepare(loop: Dictionary, actor: Dictionary, foes: Array, channel: String, fields_by_id: Dictionary, envelope: Dictionary) -> Dictionary:
	var book: Dictionary = loop["skill_book"]
	var targeting: Dictionary = loop["skill_target_data"]
	var origin: Vector2i = actor["coord"]
	var cells: Array = [origin]
	var capability := PositionCapabilityRules.effects(actor, book, loop["equipment_items"])
	if not capability["ok"]: return capability
	if channel != "magic" or capability["effects"]["move_magic_use"]:
		for cell in envelope["reachable_coords"]:
			if not cells.has(cell): cells.append(cell)
	cells.sort_custom(cell_before)
	var primaries: Array = []
	for unit in loop["units"]:
		if not BattlePresenceRules.living(unit) or unit.get("battle_actor_role") not in SkillTargetRules.ROLES: continue
		if not SkillTargetRules.ActorRoleRules.hostile(actor, unit): continue
		if foes.any(func(foe): return foe.get("id") == unit.get("id")): primaries.append(unit)
	var targets := {}
	var offensive_targets := {}
	var any_skills: Array = []
	var profile: Dictionary = loop["ai_profiles"]["actors"].get(str(actor["actor_id"]), {}).get("profile", {})
	var scan := {}
	if not fields_by_id.is_empty():
		scan = threat_scan(loop, actor, profile, bool(capability["effects"]["move_magic_use"]))
		if not scan["ok"]: return scan
	var ctx := {"loop": loop, "actor": actor, "book": book, "targeting": targeting, "origin": origin, "cells": cells,
		"primaries": primaries, "envelope": envelope}
	for id in fields_by_id:
		var fields: Dictionary = fields_by_id[id]
		var descriptor: Dictionary = book["skills"][id]
		var rate := Values.non_negative_int(fields.get("use_ratio"), true)
		if rate < 0 or rate > 100: return {"ok": false, "reason": "invalid_ai_skill_use_ratio"}
		var source_order := Values.non_negative_int(descriptor.get("source_order"))
		if source_order < 0 or source_order > 223: return {"ok": false, "reason": "invalid_ai_skill_source_order"}
		# 0x43f7bf draws 0x40d4e0 before 0x40c570 picks the channel; both 0x40d340 (MAGIC) and
		# 0x40df70 (SPECIAL) receive the same (first, fallback) offensive bucket pair.
		var flag := Values.non_negative_int(profile.get("ai_magic_multi_first"))
		if flag not in [0, 1]: return {"ok": false, "reason": "missing_ai_magic_multi_first"}
		var eligibility := SkillResolutionRules.available(actor, id, fields, book, targeting, loop["equipment_items"])
		if not eligibility["ok"]:
			if eligibility["reason"] in ["insufficient_mp", "insufficient_stamina", "magic_disabled_by_status", "caster_unavailable"]: continue
			return eligibility
		var mask := SkillTargetRules.function_mask(fields["function"], targeting["function_bits"])
		var area: bool = int(targeting["ranges"][fields["effect_range"]]["size"]) > 1
		var source_buckets := AISkillDecisionRules.buckets(mask, area)
		if SkillTargetRules.is_support(fields, targeting): continue
		var offense_bucket := 3 if source_buckets.has(3) else 4 if source_buckets.has(4) else -1
		# 0x40d4e0 only dispatches buckets 1..7; a CancelActive/StealItem row has none, so the
		# native planner never picks it. Skip it instead of failing the whole AI turn.
		if offense_bucket < 0: continue
		var by_primary := {}
		var every: Array = []
		var failed := _collect_offense_intents(ctx, id, fields, every, by_primary)
		if not failed.is_empty(): return failed
		# 0x40c620 buckets every affordable row whether or not it can land this turn; the
		# held-target-free planners (0x40d340／0x40df70 with flag 0) pick among all of them.
		any_skills.append({"skill_id": id, "source_order": source_order, "use_ratio": rate, "bucket": offense_bucket, "intents": every})
		for primary_id in by_primary:
			var candidate := {"skill_id": id, "source_order": source_order,
				"use_ratio": rate, "bucket": offense_bucket, "intents": by_primary[primary_id]}
			if not targets.has(primary_id): targets[primary_id] = target_plan(primary_id, channel, profile, actor, scan)
			targets[primary_id]["skills"].append(candidate)
			if mask & 1:
				if not offensive_targets.has(primary_id): offensive_targets[primary_id] = target_plan(primary_id, channel, profile, actor, scan)
				offensive_targets[primary_id]["skills"].append(candidate)
	var any_target := target_plan("", channel, profile, actor, scan)
	any_target.merge({"skills": any_skills, "available": not any_skills.is_empty(),
		"move_search": channel != "magic" or bool(capability["effects"]["move_magic_use"])}, true)
	return {"ok": true, "targets": targets, "offensive_targets": offensive_targets, "any_target": any_target}


## Every useful (station cell, cast centre) of one offensive row: all into `every`, and per
## affected primary into `by_primary[primary id]` ({} or the failing cast receipt).
static func _collect_offense_intents(ctx: Dictionary, id: Variant, fields: Dictionary, every: Array, by_primary: Dictionary) -> Dictionary:
	var loop: Dictionary = ctx["loop"]
	var actor: Dictionary = ctx["actor"]
	var targeting: Dictionary = ctx["targeting"]
	var envelope: Dictionary = ctx["envelope"]
	var origin: Vector2i = ctx["origin"]
	var lifted := lifted_words(loop, actor)
	for cell in ctx["cells"]:
		var terrain := cast_terrain(actor, cell, lifted)
		var cast_cells := SkillTargetRules.cells(cell, fields, targeting, loop["map_size"], terrain)
		for coord in SkillTargetRules.candidate_centers(actor, loop["units"], fields, targeting, loop["map_size"], cell):
			if not cast_cells.has(coord): continue
			# The shared resolver validates every footprint member before any RNG.
			var center := target_for_center(actor, loop["units"], fields, targeting, loop["map_size"], cell, coord, terrain)
			var ready := SkillResolutionRules.prepare_cast(actor, center, loop["units"], id, fields, ctx["book"], targeting, loop["equipment_items"], cell, loop["map_size"], coord, {"range_terrain": terrain})
			if not ready["ok"]:
				if ready["reason"] not in ["out_of_range", "not_enemy", "target_unavailable", "skill_has_no_effect"]: return ready
				continue
			var affected: Array = ready["targets"].map(func(unit): return str(unit["id"]))
			var useful := useful_ids(ready)
			if useful.is_empty(): continue
			var route_any: Dictionary = envelope["reachable_by_coord"].get(cell, {})
			every.append({"skill_id": id, "target_id": str(center["id"]), "cast_center": coord, "destination": cell,
				"affected_ids": affected, "useful_ids": useful, "score": useful.size(),
				"movement_cost": 0 if cell == origin else int(route_any["cost"]), "path": [] if cell == origin else route_any["path"]})
			for primary in ctx["primaries"]:
				if not affected.has(str(primary["id"])): continue
				if not by_primary.has(primary["id"]): by_primary[primary["id"]] = []
				var route: Dictionary = envelope["reachable_by_coord"].get(cell, {})
				by_primary[primary["id"]].append({"skill_id": id, "target_id": str(center["id"]), "cast_center": coord,
					"primary_target_id": str(primary["id"]), "center_is_primary": SkillTargetRules.Footprint.contains(primary,coord), "destination": cell, "affected_ids": affected,
					"useful_ids": useful, "score": useful.size(), "movement_cost": 0 if cell == origin else int(route["cost"]),
					"path": [] if cell == origin else route["path"]})
	return {}


## 0x40bb00: the support builder mode from the actor's player_mode (P 8, else E 9, else
## N 10); a sideless actor gets the value 0x20000, which no table lists.
static func support_mode(actor: Dictionary) -> int:
	var side := RangePropagationRules.side_word(actor)
	if side & RangePropagationRules.P: return 8
	if side & RangePropagationRules.E: return 9
	if side & RangePropagationRules.N: return 10
	return 0x20000


## The map words with the caster's own occupancy lifted (0x40cca0 runs 0x411b90 before it
## tries a cast cell, 0x40cf47).
static func lifted_words(loop: Dictionary, actor: Dictionary) -> Dictionary:
	return RangePropagationRules.cell_words(TerrainEditRules.tiles(loop), loop["units"].filter(func(unit): return unit["id"] != actor["id"]))


## The AI's skill terrain from `cell` (SkillTargetRules／SkillResolutionRules range_terrain):
## the caster placed on the cell (0x4119f0, 0x40cf55); cast range 0x40f8b0(cell, range, -1, 0)
## (planner 0x40cfb0／0x40d459, execution 0x441779 MAGIC／0x441a73 SPECIAL via 0x40fa80);
## effect area 0x4100e0(actor, x, y, range, mode) (planner 0x40ca71 in 0x40c9a0, execution
## 0x4417a6／0x4418fd／0x441aa0／0x441c02 reading 0x4c2c78) with the mode the AI branch
## stored there: offensive 0x40bab0 (0x43f851／0x43f8d4／0x43fe3f／0x43febb), support
## 0x40bb00 (0x43fad6／0x43faf9／0x440adb／0x440af8).
static func cast_terrain(actor: Dictionary, cell: Vector2i, lifted: Dictionary) -> Dictionary:
	var words := lifted.duplicate()
	var placed := actor.duplicate()
	placed["coord"] = cell
	var side := RangePropagationRules.side_word(placed) | RangePropagationRules.ACTOR
	for point in SkillTargetRules.Footprint.cells(placed): words[point] = int(words.get(point, 0)) | side
	return {"words": words, "cast_mode": RangePropagationRules.PLAYER_CAST_MODE,
		"area_modes": {"offensive": RangePropagationRules.offensive_mode(actor), "support": support_mode(actor)}}


## The inputs of the move-cast threat scan. 0x40cca0 calls 0x40bb80(actor, 3, 0, 8) — find_type
## 3 (nearest, score 32×Manhattan), find_flag 0, radius arg4×32 (0x40bb95) — with the caster's
## own find_no_id (+0x1bc read at 0x40bbf3, compared at 0x40bd88..0x40bd9a) and near range
## (+0x12c, move_point×32, 0x40bbe6), over the object array 0x4c34c0 in slot order: the rows
## are every living object from the actor's pre-move board (null for a dead slot), the layout
## CoreTurnQueue.registry_layout, the same the acquisition scan walks. No guard radius: that
## filter sits in the acquisition caller, not in 0x40bb80. The coins are drawn at cast time
## (`threat`), once the stations are known.
static func threat_scan(loop: Dictionary, actor: Dictionary, profile: Dictionary, move_magic_use: bool) -> Dictionary:
	var rows: Array = []
	var owner_index := -1
	for index in range(loop["units"].size()):
		var unit: Dictionary = loop["units"][index]
		if unit["id"] == actor["id"]: owner_index = index
		if not BattlePresenceRules.living(unit):
			rows.append(null)
			continue
		var source: Dictionary = loop["ai_profiles"]["actors"].get(str(unit["actor_id"]), {})
		if source.get("sid") == null or not source.get("profile") is Dictionary: return {"ok": false, "reason": "missing_ai_actor_identity"}
		rows.append({"coord": unit["coord"], "side": SkillTargetRules.ActorRoleRules.side_mask(unit), "job": source["profile"].get("job"),
			"sid": source["sid"], "level": unit.get("level"), "hp": unit["hp"], "removed": false})
	var search := profile.duplicate()
	search.merge({"find_type": 3, "find_flag": 0, "find_range": 8}, true)
	var layout := CoreTurnQueue.registry_layout(loop["units"])
	var error := AIDecisionRules.profile_error(search)
	if error == "": error = AIDecisionRules.rows_error(AIDecisionRules.registry_rows(rows, layout), layout.find(owner_index) if not layout.is_empty() else owner_index)
	if error != "": return {"ok": false, "reason": error}
	return {"ok": true, "rows": rows, "layout": layout, "owner_index": owner_index, "profile": search,
		"near_range": int(actor["move_point"]), "move_magic_use": move_magic_use}


## The threat 0x40cca0 flees from, scanned when the move search has at least one station
## (0x40d1a8; none: 0x40d0d2 skips to 0x40d31b with no scan). A plan without scan inputs
## carries a fixed `threat` instead.
static func threat(plan: Dictionary, rng: Variant) -> Dictionary:
	var scan: Dictionary = plan.get("threat_scan", {})
	if scan.is_empty(): return {"coord": plan.get("threat"), "draws": [], "source": "fixed"}
	var selected := AIDecisionRules.select_registered_target(scan["rows"], scan["layout"], int(scan["owner_index"]), scan["profile"], int(scan["near_range"]), rng)
	var found := bool(selected["ok"]) and int(selected["index"]) >= 0
	return {"coord": scan["rows"][int(selected["index"])]["coord"] if found else null, "target_index": int(selected.get("index", -1)),
		"draws": selected.get("draws", []), "reason": selected.get("reason", ""), "source": "0x40bb80(actor, 3, 0, 8) at 0x40d1a8"}


## A magic plan without move_magic_use casts from its own cell and never enters 0x40cca0.
static func moves_to_cast(plan: Dictionary) -> bool:
	return plan["channel"] != "magic" or bool(plan.get("threat_scan", {}).get("move_magic_use", plan.has("threat")))


static func target_plan(primary_id: String, channel: String, profile: Dictionary, actor: Dictionary, scan: Dictionary) -> Dictionary:
	return {"primary_target_id": primary_id, "channel": channel, "skills": [], "threat_scan": scan,
		"area_flag": profile.get("ai_magic_multi_first"), "origin": actor["coord"]}


static func choose(plan: Dictionary, rng: Variant, requested_buckets: Array = []) -> Dictionary:
	var skills: Array = plan["skills"].duplicate()
	# 0x40c620 traverses ascending type/code; 0x407010 prepends each node.
	skills.sort_custom(func(a, b): return int(a["source_order"]) > int(b["source_order"]))
	var decision := {"primary_target_id": plan["primary_target_id"], "attempts": [],
		"composition_evidence": "provisional", "source": "original_ai_skills",
		"threat_policy": "0x40bb80(actor, 3, 0, 8) at cast time: registry-order nearest non-own-side object within radius 8, retain-old coin 0x40bd4f"}
	var skill: Dictionary = {}
	# Offense walks the 0x40d4e0 (first, fallback) pair: 0x40d340 through 0x40c770 for MAGIC,
	# 0x40df70 through 0x40dd80 for SPECIAL (same rand(32)%count start and per-node use_ratio roll,
	# no bucket 3/4 weighting). Support callers pass the native bucket (heal 1/2, buff 5, cure 7).
	# The dying check passes the pair it drew once before its candidate loop (0x43f7bf);
	# without one the order is drawn here.
	var order := AISkillDecisionRules.area_order(int(plan["area_flag"]), rng) if requested_buckets.is_empty() else {"order": requested_buckets}
	decision["bucket_order"] = order
	for bucket in order["order"]:
		var members := skills.filter(func(row): return int(row["bucket"]) == int(bucket))
		var selected := AISkillDecisionRules.select_index(members.map(func(row): return int(row["use_ratio"])), rng, plan["channel"], int(bucket))
		selected["skill_ids"] = members.map(func(row): return str(row["skill_id"]))
		selected["bucket"] = bucket
		decision["attempts"].append(selected)
		if int(selected["index"]) >= 0:
			skill = members[int(selected["index"])]
			break
	if skill.is_empty(): return {"intent": {}, "decision": decision}
	var intents: Array = skill["intents"]
	# 0x40cca0 never scans the actor's own cell (0x40cf34 skips an occupied word, test 0x74000):
	# the stations are the best cells away from it, even when the own cell covers more. With
	# none ([0x4c1a00] 0: 0x40d0d2 → 0x40d31b, no threat scan) 0x40d340 casts from its own
	# cell (0x40d439), 0x40df70 likewise (0x40e059).
	# Not matched: 0x40cf34 tests the word before 0x411b90 lifts the caster (0x40cf47), so a
	# 3×3 actor skips every anchor cell its body covers; the filter below drops only `origin`.
	# 0x410a50 failing on the picked station (0x40d2ed → 0x40d31b) keeps the initial 0 return
	# (0x40ccbf) and the actor casts in place; the remake has no such fallback.
	var moving := moves_to_cast(plan)
	if moving and plan.get("origin") is Vector2i:
		var away := intents.filter(func(intent): return intent["destination"] != plan["origin"] and int(intent["score"]) > 0)
		moving = not away.is_empty()
		intents = away if moving else intents.filter(func(intent): return intent["destination"] == plan["origin"])
		if intents.is_empty(): return {"intent": {}, "decision": decision}
	var best := 0
	for intent in intents: best = maxi(best, int(intent["score"]))
	var finalists := intents.filter(func(intent): return int(intent["score"]) == best)
	# Compare every center in row-major order for each legal destination. Native
	# equal coverage can replace the prior center; a single covered primary prefers
	# its own castable cell. The WRD candidate composition remains an adapter.
	var destinations: Array = []
	var distinct: Array = []
	var center_draws: Array = []
	for intent in finalists:
		var previous := destinations.find(intent["destination"])
		if previous >= 0:
			var replace := AISkillDecisionRules.recorded_draw(2, rng, center_draws) != 0
			if best == 1:
				var old_at_target: bool = distinct[previous].get("center_is_primary", false)
				var new_at_target: bool = intent.get("center_is_primary", false)
				if old_at_target != new_at_target: replace = new_at_target
			if replace: distinct[previous] = intent
			continue
		destinations.append(intent["destination"])
		distinct.append(intent)
	decision["center_tie_draws"] = center_draws
	# 0x40d340 (MAGIC) and 0x40df70 (SPECIAL, push 1 at 0x40e030 → 0x40cca0 at 0x40e03d) share
	# the move search: the threat scan after the stations, then the farthest one from it.
	var index := 0
	var found := {"coord": null}
	if moving:
		found = threat(plan, rng)
		decision["threat_scan"] = found
	if found["coord"] is Vector2i:
		var position := AISkillDecisionRules.farthest_index(destinations, found["coord"], rng)
		index = int(position["index"])
		decision["position_selection"] = position
	elif distinct.size() > 1:
		index = CoreCombatRules.rand_range(distinct.size(), rng)
	decision["coverage"] = best
	decision["threat"] = found["coord"]
	decision["skill_id"] = skill["skill_id"]
	return {"intent": distinct[index], "decision": decision}


## State 0xa's skill cast (0x43fea7 → 0x40d340, 0x43fe3e → 0x40df70, both with flag 0): the
## held target only feeds the bucket mask and the contains-target bookkeeping, the centre
## is the best coverage anywhere in reach. The (first, fallback) pair walks 0x40c770 (MAGIC)
## or 0x40dd80 (SPECIAL) over every affordable row of the bucket (0x40c620 does not ask
## whether the row can land); a picked row with no centre falls to the fallback bucket
## (0x40d494 → 0x40d3bc, 0x40e0d2 → 0x40dfee), the fallback is tried once. The search is
## 0x40cca0 first when the actor moves to cast (SPECIAL always; MAGIC when 0x40e270, called
## at 0x40d3f8, returns non-zero — zero jumps at 0x40d402 to the own-cell scan 0x40d439):
## every stoppable flood cell but its own (0x40cf34 skips an occupied word)
## scanned row-major, each keeping its 0x40c9a0 best, the cells of the highest count
## collected (0x40cfea..0x40d02f) and the one farthest from the threat taken (0x40d200..
## 0x40d2b0; no threat: rand(count), 0x40d1c8); nothing there, or no move search, scans
## the actor's own cell (0x40d439..0x40d47e, 0x40e059..0x40e09f).
static func choose_any(plan: Dictionary, held_id: String, rng: Variant) -> Dictionary:
	var skills: Array = plan["skills"].duplicate()
	skills.sort_custom(func(a, b): return int(a["source_order"]) > int(b["source_order"]))
	var decision := {"primary_target_id": held_id, "attempts": [], "held_target_free": true,
		"source": "0x40d340／0x40df70 flag 0 (0x43fedd／0x43fe61)",
		"threat_policy": "0x40bb80(actor, 3, 0, 8) at cast time: registry-order nearest non-own-side object within radius 8, retain-old coin 0x40bd4f"}
	var order := AISkillDecisionRules.area_order(int(plan["area_flag"]), rng)
	decision["bucket_order"] = order
	for bucket in order["order"]:
		var members := skills.filter(func(row): return int(row["bucket"]) == int(bucket))
		var selected := AISkillDecisionRules.select_index(members.map(func(row): return int(row["use_ratio"])), rng, plan["channel"], int(bucket))
		selected["skill_ids"] = members.map(func(row): return str(row["skill_id"]))
		selected["bucket"] = bucket
		decision["attempts"].append(selected)
		if int(selected["index"]) < 0: continue
		var skill: Dictionary = members[int(selected["index"])]
		var search := _cast_search(skill["intents"], plan, held_id, rng)
		selected["search"] = search["receipt"]
		if search["intent"].is_empty(): continue
		decision["coverage"] = int(search["count"])
		if search["receipt"].has("position_selection"): decision["position_selection"] = search["receipt"]["position_selection"]
		decision["threat"] = search["receipt"].get("threat")
		decision["skill_id"] = skill["skill_id"]
		return {"intent": search["intent"], "decision": decision}
	return {"intent": {}, "decision": decision}


## Same two gaps as `choose`: only `origin` leaves the station cells (0x40cf34 skips every
## body cell of a 3×3 caster), and no fallback for a failed 0x410a50 (0x40d2ed).
static func _cast_search(intents: Array, plan: Dictionary, held_id: String, rng: Variant) -> Dictionary:
	var origin: Vector2i = plan["origin"]
	var by_cell := {}
	for intent in intents:
		var cell: Vector2i = intent["destination"]
		if not by_cell.has(cell): by_cell[cell] = []
		by_cell[cell].append(intent)
	var receipt := {"centre_draws": [], "stations": [], "position_draws": []}
	if bool(plan["move_search"]):
		var cells: Array = by_cell.keys().filter(func(cell): return cell != origin)
		cells.sort_custom(cell_before)
		var best := 0
		var stations: Array = []
		for cell in cells:
			var scan := centre_scan(by_cell[cell], held_id, rng, receipt["centre_draws"])
			if scan["count"] > best:
				best = int(scan["count"])
				stations = [scan["intent"]]
			elif scan["count"] == best and best > 0:
				stations.append(scan["intent"])
		receipt["stations"] = stations.map(func(intent): return intent["destination"])
		if not stations.is_empty():
			var index := 0
			var found := threat(plan, rng)
			receipt["threat_scan"] = found
			receipt["threat"] = found["coord"]
			if found["coord"] is Vector2i:
				var position := AISkillDecisionRules.farthest_index(receipt["stations"], found["coord"], rng)
				index = int(position["index"])
				receipt["position_draws"] = position["draws"]
				receipt["position_selection"] = position
			elif stations.size() > 1:
				index = AISkillDecisionRules.recorded_draw(stations.size(), rng, receipt["position_draws"])
			return {"intent": stations[index], "count": best, "receipt": receipt}
	var scan := centre_scan(by_cell.get(origin, []), held_id, rng, receipt["centre_draws"])
	return {"intent": scan["intent"], "count": scan["count"], "receipt": receipt}


## 0x40c9a0 over one cast cell's centres in row-major order: the count is the covered
## non-own-side occupants (here the useful affected foes, the remake's usefulness policy).
## A centre whose area holds the held target runs the contains-target best first — an
## equal count draws raw & 1 at 0x40cb54 — then every counted centre runs the general
## best: a higher count replaces it, an equal one replaces it on raw & 1 (0x40cb99). Flag 0
## returns the general best (0x40cc6f..0x40cc77), wherever the held target is.
static func centre_scan(intents: Array, held_id: String, rng: Variant, draws: Array) -> Dictionary:
	var ordered := intents.duplicate()
	ordered.sort_custom(func(a, b): return cell_before(a["cast_center"], b["cast_center"]))
	var best := 0
	var best_holding := 0
	var chosen := {}
	for intent in ordered:
		var count := int(intent["score"])
		if count <= 0: continue
		if held_id != "" and intent["affected_ids"].has(held_id):
			if count > best_holding: best_holding = count
			elif count == best_holding: AISkillDecisionRules.recorded_draw(2, rng, draws)
		if count > best:
			best = count
			chosen = intent
		elif count == best and AISkillDecisionRules.recorded_draw(2, rng, draws) & 1:
			chosen = intent
	return {"intent": chosen, "count": best}


static func target_for_center(actor: Dictionary, units: Array, fields: Dictionary, targeting: Dictionary, map_size: Vector2i, origin: Vector2i, center: Vector2i, terrain: Dictionary = {}) -> Dictionary:
	var footprint := SkillTargetRules.effect_cells(center, fields, targeting, map_size, origin, terrain)
	var first := {}
	for unit in units:
		if not BattlePresenceRules.living(unit) or unit.get("battle_actor_role") not in SkillTargetRules.ROLES or not SkillTargetRules.side_matches(actor, unit, fields, targeting): continue
		var coord: Vector2i = origin if unit["id"] == actor["id"] else unit["coord"]
		if not SkillTargetRules.Footprint.overlaps(unit,footprint,coord): continue
		if SkillTargetRules.Footprint.contains(unit,center,coord): return unit
		if first.is_empty(): first = unit
	return first


static func useful_ids(ready: Dictionary) -> Array:
	var result: Array = []
	for index in range(ready["targets"].size()):
		var prepared: Dictionary = ready["prepared"][index]
		var target: Dictionary = ready["targets"][index]
		if prepared.has("stat_effect"):
			var stat: Dictionary = prepared["stat_effect"]
			# The reviewed buff selector skips an already present matching buff,
			# even though a player may legally extend its duration or strength.
			if stat["useful"] and (stat["kind"] == "dispel" or SkillResolutionRules.StatMagic.StatEnhancementRules.word(target, stat["kind"]) == 0):
				result.append(str(target["id"]))
			continue
		if prepared.has("support"):
			if prepared["support"]["useful"]: result.append(str(target["id"]))
			continue
		if not prepared.has("status") or int(prepared["status"]["function_mask"]) not in [4, 8]:
			result.append(str(target["id"]))
			continue
		if int(prepared["status"]["function_mask"]) == 4:
			if not int(prepared["status"]["immunities"]) & 0x4000080 and int(target["status_counters"][StatusCatalog.PARALYSIS_KEY]) < 9:
				result.append(str(target["id"]))
			continue
		if int(prepared["status"]["immunities"]) & 0x800080: continue
		var word := int(target["status_counters"].get(StatusCatalog.POISON_KEY, 0))
		if (word & 0xffff) < 9 or (word >> 16) < 50: result.append(str(target["id"]))
	return result


static func cell_before(a: Vector2i, b: Vector2i) -> bool:
	return a.y < b.y or (a.y == b.y and a.x < b.x)
