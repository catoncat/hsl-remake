extends RefCounted
## One source-template normalization for initial actors and later script installs.
## This does not place, register, level-adjust, draw RNG or grant a turn.
## provenance:
##   rules: static-derived docs/evidence_packets/static_reverse/original_priest.md
##   rules: static-derived docs/evidence_packets/static_reverse/original_ai_navigation.md
##   rules: runtime-measured docs/evidence_packets/static_reverse/original_stamina.md (template stamina 0x44cb41)
##   rules: provisional (normalisation order of skill book／AI／inventory／equipment inputs is the remake's)
const StatusEffectRules = preload("res://game/sim/StatusEffectRules.gd")
const ActorTraversalRules = preload("res://game/sim/ActorTraversalRules.gd")
const AINavigationRules = preload("res://game/sim/AINavigationRules.gd")
const ProgressionRules = preload("res://game/sim/ProgressionRules.gd")
const MobilityRules = preload("res://game/sim/MobilityRules.gd")
const InventoryRules = preload("res://game/sim/InventoryRules.gd")
const SkillResourceRules = preload("res://game/sim/SkillResourceRules.gd")
const Values = preload("res://game/sim/Values.gd")


## `stamina_pin` >= 0 is a development fixture's skill_rules.initial_stamina; -1 keeps the
## PLAYERS template word (progression `stamina`). A carried player's word is CampaignCarryRules'.
static func prepare(template: Dictionary, book: Dictionary, ai: Dictionary, progression: Dictionary, inventories: Dictionary, equipment: Dictionary, stamina_pin: int = -1) -> Dictionary:
	var actor := template.duplicate(true)
	var error := StatusEffectRules.input_error(actor)
	if error != "": return {"ok": false, "reason": error}
	actor["status_flags"] = int(actor["status_flags"])
	for key in StatusEffectRules.COUNTERS: actor["status_counters"][key] = int(actor["status_counters"][key])
	for key in StatusEffectRules.Enhancements.FLAGS:
		if actor["status_counters"].has(key): actor["status_counters"][key] = int(actor["status_counters"][key])
	var traversal := ActorTraversalRules.source(actor, book)
	if not traversal["ok"]: return traversal
	actor["traversal"] = traversal["traits"]
	actor["ai_call_target_id"] = ""
	var code := str(actor.get("actor_id", ""))
	var instance_error := instance_input_error(actor)
	if instance_error != "": return {"ok": false, "reason": instance_error}
	var navigation: Dictionary = AINavigationRules.instance_profile(actor, ai.get("actors", {}).get(code, {}).get("profile", {}))
	if Values.non_negative_int(navigation.get("wait_round")) < 0: return {"ok": false, "reason": "missing_ai_wait_source"}
	AINavigationRules.initialize(actor, navigation)
	actor["hit_bonus_accum"] = int(actor.get("hit_bonus_accum", 0))
	if not progression.has(code): return {"ok": false, "reason": "missing_actor_progression"}
	# 0x44cb10 copies the whole PLAYERS template record, stamina word +0xe8 included: 0x44cb41
	# for a first registration, 0x44cb88 for an NPC (001 20, 006 8, every other row 0).
	var stamina := stamina_pin if stamina_pin >= 0 else Values.non_negative_int(progression[code].get("stamina"))
	if stamina < 0 or stamina > 60: return {"ok": false, "reason": "missing_actor_template_stamina"}
	actor.merge(progression[code], true)
	actor["pending_stat_points"] = 0
	actor["kill_chain_word"] = 0
	actor["kill_count"] = 0
	actor["permanent_gains"] = ProgressionRules.Permanent.empty()
	actor["learned_skills"] = []
	if actor["growth_profile"]["allocation"] == "fixed_template": actor["growth_profile"]["allocation"] = "automatic"
	actor["stamina"] = stamina
	actor["inventory"] = inventories.get(code, [0, 0, 0, 0, 0, 0, 0, 0]).duplicate()
	apply_instance_words(actor)
	error = ProgressionRules.refresh_input_error(actor, equipment)
	if error != "": return {"ok": false, "reason": error}
	actor.merge(ProgressionRules.refresh_growth_stats(actor, equipment), true)
	var mobility := MobilityRules.prepare(actor, equipment)
	if not mobility["ok"]: return mobility
	actor["move_point"] = mobility["value"]
	if not InventoryRules.valid(actor["inventory"]): return {"ok": false, "reason": "invalid_inventory_slots"}
	actor["inventory"] = actor["inventory"].map(func(value): return int(value))
	return {"ok": true, "actor": actor}


static func instance_input_error(actor: Dictionary) -> String:
	if not actor.has("evef_instance"): return ""
	var instance: Variant = actor["evef_instance"]
	if not instance is Dictionary: return "invalid_evef_instance"
	if instance.has("items") and (not instance["items"] is Array or instance["items"].size() > 8 or instance["items"].any(func(code): return Values.non_negative_int(code) <= 0)):
		return "invalid_evef_instance_items"
	var overrides: Variant = instance.get("overrides", {})
	if not overrides is Dictionary: return "invalid_evef_instance_overrides"
	for key in overrides:
		var value: Variant = overrides[key]
		if key == "fixed_point":
			if not value is Array or value.size() != 2 or Values.non_negative_int(value[0]) < 0 or Values.non_negative_int(value[1]) < 0: return "invalid_evef_fixed_point"
		elif Values.non_negative_int(value) < 0: return "invalid_evef_instance_override_" + str(key)
	return ""


static func apply_instance_words(actor: Dictionary) -> void:
	## EVEF instance words the original install callback 0x42bd50 writes onto the live
	## record after the PLAYERS template: items 0x10..0x2C into the first empty slots
	## (0x42be2e..0x42be79), stamina (index 24 -> +0xe8). Strategy fields and the fixed
	## point are read live through AINavigationRules.instance_profile / initialize;
	## level adjustment halves (16/17) through ReinforcementGrowthRules.prepare.
	var instance: Variant = actor.get("evef_instance")
	if not instance is Dictionary: return
	for code in instance.get("items", []):
		# Slots arrive from JSON as floats (0.0): Array.find(0) never matches them, which dropped every
		# EVEF item until 2026-09-26 (OPENSNAP: level 52 knight 024 carried one 回復藥 instead of two).
		var slot := -1
		for index in actor["inventory"].size():
			if int(actor["inventory"][index]) == 0:
				slot = index
				break
		if slot < 0: break
		actor["inventory"][slot] = int(code)
	var overrides: Dictionary = instance.get("overrides", {})
	if overrides.has("stamina"): actor["stamina"] = int(overrides["stamina"])
