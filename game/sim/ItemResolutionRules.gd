extends RefCounted
## Immutable inventory/effect/random proposals. Only PlayLoop commits them.
## provenance:
##   rules: static-derived docs/evidence_packets/static_reverse/original_tactical_items.md
##   rules: static-derived docs/evidence_packets/static_reverse/original_damage_random.md
##   rules: static-derived docs/evidence_packets/static_reverse/original_item_actions.md
const ItemUseRules = preload("res://game/sim/ItemUseRules.gd")
const InventoryRules = preload("res://game/sim/InventoryRules.gd")
const ProgressionRules = preload("res://game/sim/ProgressionRules.gd")
const BattleRewardRules = preload("res://game/sim/BattleRewardRules.gd")
const DamageRandom = preload("res://game/sim/DamageRandomStream.gd")
const StatusEffectRules = preload("res://game/sim/StatusEffectRules.gd")
const ResourceRecoveryRules = preload("res://game/sim/ResourceRecoveryRules.gd")
const Values = preload("res://game/sim/Values.gd")
## v3: samples come from the loop's damage stream (DamageRandomStream, [word0, word1]); v2
## drew them from a separate Park-Miller item_rng.
const POLICY := "source_tactical_items_v3"


## `spend`: the player's Use — a use without effect still spends the item (0x444aba clears the
## held code after 0x409e40). The AI keeps the default refusal as its stale-plan guard (its
## triggers always leave an effect, BattleLoopInventory.resolve_item_use). `script`: actUseItem (case 0x5d 0x451669) calls 0x409e40(actor, id,
## vm, 0) alone — no ownership, paralysis or benefit check, and the inventory is not touched.
static func prepare(actor: Dictionary, target: Dictionary, code: String, slot: int, definition: Dictionary, catalog: Dictionary, rng_state: Array, sequence: int, spend: bool = false, script: bool = false) -> Dictionary:
	if not DamageRandom.valid(rng_state) or not Values.is_integer_in(sequence, 1, Values.MAX_SIGNED): return {"ok":false,"reason":"invalid_item_sequence_state"}
	if not actor.get("id") is String or not target.get("id") is String or not actor.get("inventory") is Array or not InventoryRules.valid(actor["inventory"]): return {"ok":false,"reason":"invalid_item_actor"}
	if actor["id"].is_empty() or target["id"].is_empty() or ResourceRecoveryRules.health_error(actor) != "" or ResourceRecoveryRules.health_error(target) != "" or not Values.is_integer_in(target.get("stamina"), 0, 60): return {"ok":false,"reason":"invalid_item_vitals"}
	if actor["id"] == target["id"] and actor != target: return {"ok":false,"reason":"inconsistent_self_item_snapshot"}
	if not code.is_valid_int() or int(code)<=0 or not catalog.has(code): return {"ok":false,"reason":"unsupported_item"}
	if StatusEffectRules.input_error(actor) != "" or (StatusEffectRules.paralyzed(actor) and not script) or int(actor.get("hp",0)) <= 0 or actor.get("defeated",false) or actor.get("departed",false): return {"ok":false,"reason":"item_owner_unavailable"}
	if ProgressionRules.Permanent.input_error(actor) != "": return {"ok":false,"reason":"invalid_item_owner_capabilities"}
	var index := InventoryRules.find_item(actor["inventory"],int(code),slot)
	if index<0 and not script: return {"ok":false,"reason":"item_not_owned"}
	var effect := ItemUseRules.prepare(target,definition,spend or script)
	if not effect["ok"]: return effect
	var removal := {"ok": true, "inventory": actor["inventory"].duplicate()} if script else InventoryRules.remove(actor["inventory"],index,int(code))
	if not removal["ok"]: return removal
	var error := ProgressionRules.enhancement_profile_error(target,catalog)
	if error != "": return {"ok":false,"reason":error}
	if not effect["stat_proposals"].is_empty() or not effect["permanent_proposals"].is_empty() or effect["cured_weaken"]:
		error = ProgressionRules.refresh_input_error(target,catalog)
		if error != "": return {"ok":false,"reason":error}
	var next := target.duplicate(true)
	next.merge(effect["changes"],true)
	var state := rng_state.duplicate()
	var draws: Array = []
	var stat_effects: Array = []
	var permanent_effects: Array = []
	for proposal in effect["permanent_proposals"]:
		var bound := int(proposal["high"]) - int(proposal["low"]) + 1
		var sample := DamageRandom.rand(state,bound)
		state = sample["state"]
		draws.append({"bound":bound,"value":sample["value"]})
		permanent_effects.append(ProgressionRules.Permanent.apply_sample(next,proposal,int(proposal["low"])+int(sample["value"])))
	for proposal in effect["stat_proposals"]:
		var before := int(proposal["before_word"])
		var strength := before >> 16
		if proposal["roll_required"]:
			var bound := int(proposal["high"]) - int(proposal["low"]) + 1
			var sample := DamageRandom.rand(state,bound)
			state = sample["state"]
			draws.append({"bound":bound,"value":sample["value"]})
			strength = int(proposal["low"]) + int(sample["value"])
		var after := StatusEffectRules.Enhancements.item_word(before,strength)
		next["status_counters"][proposal["kind"]] = after
		next["status_flags"] = int(next["status_flags"]) | int(StatusEffectRules.Enhancements.FLAGS[proposal["kind"]])
		stat_effects.append({"kind":proposal["kind"],"before_word":before,"after_word":after,
			"before_power":before >> 16,"after_power":strength,"duration":int(proposal["duration"]),"sampled":proposal["roll_required"]})
	var changes: Dictionary = effect["changes"].duplicate(true)
	# 0x40a337: the cure block ends in 0x448840, so a cured 衰弱 returns the derived stats to the unweakened attributes.
	if not stat_effects.is_empty() or not permanent_effects.is_empty() or effect["cured_weaken"]:
		var refreshed := ProgressionRules.refresh_growth_stats(next,catalog)
		if refreshed.is_empty() or ProgressionRules.enhancement_profile_error(refreshed,catalog) != "": return {"ok":false,"reason":"invalid_item_stat_refresh"}
		for key in ["combat_profile","live_speed","move_point","status_flags","status_counters"]: changes[key] = refreshed[key]
		if not permanent_effects.is_empty(): changes["permanent_gains"] = refreshed["permanent_gains"]
	var after := target.duplicate(true)
	after.merge(changes,true)
	var receipt := {"actor_id":actor["id"],"target_id":target["id"],"item_code":code,"inventory_index":index,"sequence":sequence,
		"hp_before":target["hp"],"hp_after":after["hp"],"mp_before":target["mp"],"mp_after":after["mp"],
		"stamina_before":target["stamina"],"stamina_after":after["stamina"],"restored_hp":effect["restored_hp"],"restored_mp":effect["restored_mp"],
		"restored_stamina":effect["restored_stamina"],"heal_numbers":effect["heal_numbers"].duplicate(),"cured_poison":effect["cured_poison"],"cured_paralysis":effect["cured_paralysis"],"cured_no_magic":effect["cured_no_magic"],"cured_weaken":effect["cured_weaken"],
		"stat_effects":stat_effects,"permanent_effects":permanent_effects,"draws":draws,
		"actor_before":actor.duplicate(true),"target_before":target.duplicate(true),"target_changes":changes.duplicate(true),"inventory_after":removal["inventory"].duplicate(true)}
	if script: receipt["source"] = "script"
	return {"ok":true,"target_changes":changes,"inventory":removal["inventory"],"rng":state,"receipt":receipt}


static func state_error(loop: Dictionary) -> String:
	if loop.get("item_use_policy") != POLICY or not DamageRandom.valid(loop.get(DamageRandom.LOOP_KEY)) or not Values.is_integer_in(loop.get("item_use_sequence"), 0, Values.MAX_SIGNED): return "invalid_item_random_state"
	var receipt: Variant = loop.get("last_item_use")
	if not receipt is Dictionary: return "missing_item_use_receipt"
	if int(loop["item_use_sequence"]) == 0: return "" if receipt.is_empty() else "inconsistent_item_use_sequence"
	if receipt.get("sequence") != loop["item_use_sequence"] or not receipt.get("actor_before") is Dictionary or not receipt.get("target_before") is Dictionary: return "invalid_item_use_receipt"
	if not Values.is_integer_in(receipt.get("inventory_index"), -1 if receipt.get("source") == "script" else 0, 7) or not receipt.get("item_code") is String: return "invalid_item_use_receipt"
	return ""
