extends RefCounted
## First creation boundary after campaign carry, before actors become playable.
## Object kind3 infers its source level without random scaling. Other actors use
## the same birth proposal as reinforcements, drawing from the loop's global stream
## (`global_rng`, 0x40e870 → 0x458c80) back to back in creation order; an enemy_ai
## draws its carry item (0x407c40) on that stream just before its adjustment.
## Each birth sees the players registered before it (`opening_birth.story_insert`);
## an opening that runs actAdjustAllPlayerLevel (opcode 73, level 6) then re-adjusts
## every unit alive at that point once (`opening_birth.adjust_all_level`).
## provenance:
##   rules: static-derived docs/evidence_packets/static_reverse/original_growth_lifecycle.md
##   rules: static-derived docs/evidence_packets/static_reverse/original_auto_growth.md
##   rules: runtime-measured docs/evidence_packets/runtime_observations/battle_053/README.md
##     (STORY053 pursuers L1 28 HP under 0,0)
##   rules: static-derived docs/evidence_packets/static_reverse/original_enemy_turn.md
##   rules: runtime-measured tools/hsltools/probes/_reward_rng_trace.py
##     (birth per object: frame delay 0x407dba, pmEnemy carry 0x407c86, adjustment 0x40e92c, all global)
##   rules: static-derived docs/evidence_packets/static_reverse/original_script_entry.md
##     (0x407dba: every birth adds rand(24) to the shape-delay word +0x7c, players first)
##   rules: remake-invented (creation order among players and among NPCs, fill to maxima)
const BattleLoopConfig = preload("res://game/sim/BattleLoopConfig.gd")
const ReinforcementGrowthRules = preload("res://game/sim/ReinforcementGrowthRules.gd")
const ProgressionRules = preload("res://game/sim/ProgressionRules.gd")
const BattleOutcome = preload("res://game/sim/BattleOutcome.gd")
const GlobalRandomStream = preload("res://game/sim/GlobalRandomStream.gd")
const BattleRewardRules = preload("res://game/sim/BattleRewardRules.gd")
const Values = preload("res://game/sim/Values.gd")
const BattleLoopInit = preload("res://game/sim/loop/BattleLoopInit.gd")
const POLICY := "source_initial_roster_v1"


static func prepare(loop: Dictionary) -> Dictionary:
	if loop.has("initial_roster_growth"): return {"ok": state_error(loop) == "", "loop": BattleLoopConfig.copy(loop), "reason": state_error(loop)}
	if not loop.get("scenario_ok", false) or BattleOutcome.decided(loop): return {"ok": false, "reason": "invalid_initial_roster_boundary"}
	var next := BattleLoopConfig.copy(loop)
	if not GlobalRandomStream.valid(next.get(GlobalRandomStream.LOOP_KEY)): return {"ok": false, "reason": "invalid_global_rng"}
	var receipt := {"policy": POLICY, "players": [], "npcs": [], "carried": []}
	var carried: Array = next.get("campaign_carry_receipt", {}).get("applied_unit_ids", [])
	# Registered players provide the level baseline before unregistered instances.
	# Their order is a declared remake scheduling choice, not native object-table order.
	# Players are born inside their construction (0x40805d → 0x44341b → 0x407cc0), NPCs on
	# their first tick, so every player's frame delay 0x407dba is drawn before any NPC birth.
	for actor in next["units"]:
		if actor["growth_profile"]["allocation"] != "manual": continue
		draw_frame_delay(next, actor)
		if carried.has(actor["id"]): receipt["carried"].append(actor["id"]); continue
		if actor.has("entry_growth") or int(actor["pending_stat_points"]) != 0 or not actor.get("learned_skills", []).is_empty(): return {"ok": false, "reason": "already_progressed_initial_actor"}
		var born := prepare_player(actor, next["equipment_items"])
		if not born["ok"]: return born
		actor.merge(born["actor"], true)
		receipt["players"].append(born["receipt"])
	# Opcode 106's slot shuffle (0x451d0f) runs on the story VM after the pre-placed players'
	# births and before the inserts' births (BattleLoopInit.settle_random_slots).
	BattleLoopInit.settle_random_slots(next, true)
	for index in range(next["units"].size()):
		var actor: Dictionary = next["units"][index]
		if actor["growth_profile"]["allocation"] == "manual": continue
		# A pre-baked STORY insert carries its actSetPrevInsertObjectAdjustLevel halves
		# (`script_insert.adjust_level`, opcode 56) exactly like a runtime insert request;
		# other units fall back to the PLAYERS template / EVEF override inside ReinforcementGrowthRules.prepare.
		# The birth 0x407cc0 draws the frame delay (0x407dba), then rolls a pmEnemy's carry
		# (0x407c40) on the same stream, before the adjustment.
		draw_frame_delay(next, actor)
		if BattleRewardRules.install_carry(next, actor) != "": return {"ok": false, "reason": "initial_carry_inventory_full"}
		var born := ReinforcementGrowthRules.prepare(next, actor, actor.get("script_insert", {}), "initial_roster")
		if not born["ok"]: return born
		next["units"][index] = born["actor"]
		next[GlobalRandomStream.LOOP_KEY] = born["rng"]
		receipt["npcs"].append(actor["id"])
	# Opcode 73 runs after the opening's inserts: every non-player unit alive then re-runs
	# 0x40e870 once. kind3 players only re-infer their unchanged level, an identity step.
	var readjusted: Array = []
	for index in range(next["units"].size()):
		var actor: Dictionary = next["units"][index]
		if actor["growth_profile"]["allocation"] == "manual" or not bool(actor.get("opening_birth", {}).get("adjust_all_level", false)): continue
		var again := ReinforcementGrowthRules.readjust(next, actor)
		if not again["ok"]: return again
		next["units"][index] = again["actor"]
		next[GlobalRandomStream.LOOP_KEY] = again["rng"]
		readjusted.append(actor["id"])
	if not readjusted.is_empty(): receipt["readjusted"] = readjusted
	next["initial_roster_growth"] = receipt
	return {"ok": true, "loop": next}


## Birth frame delay 0x407dba: 0x407cc0 sets the standing loop (0x446c40, delay 10) and adds
## rand(24) on the global stream to the shape-delay word +0x7c, so the first standing frame
## is held that many extra ticks (`birth_frame_delay`, read by ActorRuntime). Players and
## NPCs alike; the only callers are the birth branches 0x43eef6 and 0x44343e.
static func draw_frame_delay(loop: Dictionary, actor: Dictionary) -> void:
	var draw := GlobalRandomStream.rand(loop[GlobalRandomStream.LOOP_KEY], 24)
	loop[GlobalRandomStream.LOOP_KEY] = draw["state"]
	actor["birth_frame_delay"] = int(draw["value"])


static func prepare_player(template: Dictionary, equipment: Dictionary) -> Dictionary:
	var error := ProgressionRules.refresh_input_error(template, equipment)
	if error != "": return {"ok": false, "reason": error}
	if template["growth_profile"]["allocation"] != "manual" or template.has("entry_growth") or int(template["pending_stat_points"]) != 0 or not template.get("learned_skills", []).is_empty():
		return {"ok": false, "reason": "already_progressed_initial_actor"}
	var actor := template.duplicate(true)
	var before := int(actor["level"])
	var attrs := {}
	for key in ReinforcementGrowthRules.Entry.KEYS: attrs[key] = int(actor["combat_profile"][key])
	actor["level"] = ReinforcementGrowthRules.Entry.inferred_level(attrs)
	# The birth refresh (0x40e870 → 0x40eb18 → 0x448840) takes its hp_level term from the +0x28
	# the actor was born with (0x448851 tests 0x10000). A scripted mode change the level
	# assembly pre-baked into player_mode (birth_player_mode keeps the born word: level 3's
	# 漢克斯) comes later, and actSetPlayerMode 0x450710 rewrites +0x28 without a refresh.
	var born := actor
	if actor.has("birth_player_mode"):
		born = actor.duplicate(true); born["player_mode"] = actor["birth_player_mode"]
	var refreshed := ProgressionRules.refresh_growth_stats(born, equipment)
	refreshed.erase("player_mode")
	actor.merge(refreshed, true)
	actor["hp"] = actor["max_hp"]; actor["mp"] = actor["max_mp"]
	return {"ok": true, "actor": actor, "receipt": {"unit_id": actor["id"], "actor_id": actor["actor_id"], "attributes": attrs, "before": before, "level": actor["level"]}}


static func state_error(loop: Dictionary) -> String:
	if not loop.has("initial_roster_growth"): return "" # Explicit template-only simulation fixtures.
	var record: Variant = loop["initial_roster_growth"]
	if not record is Dictionary or record.get("policy") != POLICY: return "invalid_initial_roster_receipt"
	for key in ["players", "npcs", "carried"]:
		if not record.get(key) is Array: return "invalid_initial_roster_receipt"
	var seen := {}
	for id in record["npcs"]:
		var matches: Array = loop["units"].filter(func(a): return a["id"] == id)
		if matches.size() != 1 or matches[0].get("entry_growth", {}).get("origin") != "initial_roster" or seen.has(id): return "missing_initial_birth"
		seen[id] = true
	var readjusted: Variant = record.get("readjusted", [])
	if not readjusted is Array: return "invalid_initial_roster_receipt"
	var again := {}
	for id in readjusted:
		var matches: Array = loop["units"].filter(func(a): return a["id"] == id)
		if matches.size() != 1 or not seen.has(id) or again.has(id) or not matches[0].has("entry_readjust"): return "missing_initial_readjust"
		again[id] = true
	for actor in loop["units"]:
		var marked: bool = actor.get("growth_profile", {}).get("allocation") != "manual" and bool(actor.get("opening_birth", {}).get("adjust_all_level", false)) and seen.has(actor["id"])
		if marked != again.has(actor["id"]) or actor.has("entry_readjust") != again.has(actor["id"]): return "unrecorded_initial_readjust"
	for row in record["players"]:
		if not row is Dictionary or not row.get("attributes") is Dictionary: return "invalid_initial_player_record"
		var matches: Array = loop["units"].filter(func(a): return a["id"] == row.get("unit_id"))
		if matches.size() != 1 or matches[0]["actor_id"] != row.get("actor_id") or seen.has(row["unit_id"]): return "initial_player_identity_mismatch"
		for key in ReinforcementGrowthRules.Entry.KEYS:
			if ReinforcementGrowthRules.Entry.Values.non_negative_int(row["attributes"].get(key)) < 1 or int(matches[0]["combat_profile"][key]) < int(row["attributes"][key]): return "initial_player_attribute_rollback"
		if row.get("level") != ReinforcementGrowthRules.Entry.inferred_level(row["attributes"]) or int(matches[0]["level"]) < int(row["level"]): return "initial_player_level_rollback"
		seen[row["unit_id"]] = true
	for id in record["carried"]:
		if seen.has(id) or not loop.get("campaign_carry_receipt", {}).get("applied_unit_ids", []).has(id): return "invalid_carried_initial_actor"
		seen[id] = true
	for actor in loop["units"]:
		if actor.get("entry_growth", {}).get("origin") == "initial_roster" and not seen.has(actor["id"]): return "unrecorded_initial_birth"
	return ""
