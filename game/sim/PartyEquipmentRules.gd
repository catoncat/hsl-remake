extends RefCounted
## Between-battle 整理裝備 (party equipment) rules — a pure transformation layer over
## the campaign carry. The carry (CampaignCarryRules) stores sparse per-unit records
## (attributes, level/exp, equipment, weapon_code, inventory, ...), not full units, so
## a change of equipment is made on a *sandbox* loop: the caller creates the source
## battle scenario of carry.from_scenario_id as a fresh loop (BattlePlayLoop.create
## — full roster, equipment_items, weapon_ranges, skill_book; this sim module never
## preloads the battle layer), sandbox() applies the carry onto it, the equipment
## transaction runs there, and CampaignCarryRules.capture projects the refreshed units
## back into the carry — replacing only carry.units (same ids) and keeping every other
## top-level field byte-for-byte.
##
## change() mirrors BattlePlayLoop.change_equipment step by step (EquipmentRules
## .replace → weapon_code → weapon_ranges → StaminaRules.effects → attack_count
## (CombatSequenceRules) → ExtraActionRules.equipment → WeaponEffects.effects →
## ResourceRecoveryRules.effects → StatusApplicationRules.modifiers →
## PositionCapabilities.effects + attack_pattern → ExperienceRules.multiplier →
## ProgressionRules.refresh_input_error → refresh_growth_stats). The only intentional
## difference is the missing _player_action_valid battle-phase gate (there is no turn
## between battles), and no _settle_action (no action budget). Layout / flow of the
## screen are remake readings.
## TODO(source-research): make BattlePlayLoop.change_equipment delegate to
## change() so the two transaction bodies stop being duplicated.
## provenance:
##   rules: remake-invented
##     (sandbox PlayLoop transaction mirroring change_equipment between battles; no original between-battle transaction
##     located)

const BattleLoopConfig = preload("res://game/sim/BattleLoopConfig.gd")
const CarryRules = preload("res://game/sim/CampaignCarryRules.gd")
const EquipmentRules = preload("res://game/sim/EquipmentRules.gd")
const ProgressionRules = preload("res://game/sim/ProgressionRules.gd")
const ExperienceRules = preload("res://game/sim/ExperienceRules.gd")
const StaminaRules = preload("res://game/sim/StaminaRules.gd")
const ExtraActionRules = preload("res://game/sim/ExtraActionRules.gd")
const WeaponEffects = preload("res://game/sim/WeaponEffectRules.gd")
const ResourceRecoveryRules = preload("res://game/sim/ResourceRecoveryRules.gd")
const StatusApplicationRules = preload("res://game/sim/StatusApplicationRules.gd")
const PositionCapabilities = preload("res://game/sim/PositionCapabilityRules.gd")
const CombatSequence = preload("res://game/sim/CombatSequenceRules.gd")

const ROLE_PLAYER := "player_controlled"
const SKIPPED_KINDS := ["story", "game_clear", "world_map"]


## The scenario JSON path whose id equals from_scenario_id, scanning only the
## campaign's battle entries (kind neither story nor game_clear). "" when none.
static func template_scenario_path(campaign: Dictionary, from_scenario_id: String) -> String:
	if from_scenario_id == "":
		return ""
	var battles: Dictionary = campaign.get("battles", {})
	for key in battles.keys():
		var entry: Variant = battles[key]
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		if str((entry as Dictionary).get("kind", "")) in SKIPPED_KINDS:
			continue
		var path := str((entry as Dictionary).get("scenario", ""))
		if path == "" or not path.ends_with(".json") or not FileAccess.file_exists(path):
			continue
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if typeof(parsed) == TYPE_DICTIONARY and str((parsed as Dictionary).get("id", "")) == from_scenario_id:
			return path
	return ""


## Sandbox loop: the fresh loop of the source scenario (BattlePlayLoop.create([],
## "", scenario), built by the caller) with the carry applied. {ok, loop, error}.
static func sandbox(loop: Dictionary, carry: Dictionary) -> Dictionary:
	if str(carry.get("schema", "")) != CarryRules.SCHEMA:
		return {"ok": false, "loop": {}, "error": "invalid_carry_schema"}
	if not bool(loop.get("scenario_ok", false)):
		return {"ok": false, "loop": {}, "error": str(loop.get("scenario_error", "scenario_error"))}
	var applied := CarryRules.apply(loop, carry)
	var receipt: Dictionary = applied.get("campaign_carry_receipt", {})
	var errors: Array = receipt.get("errors", [])
	if not errors.is_empty():
		return {"ok": false, "loop": applied, "error": "carry_apply:" + str(errors[0])}
	return {"ok": true, "loop": applied, "error": ""}


## Controlled members of the sandbox loop, in roster order (full units).
static func members(loop: Dictionary) -> Array:
	var out: Array = []
	for unit_value in loop.get("units", []):
		if typeof(unit_value) == TYPE_DICTIONARY and str((unit_value as Dictionary).get("battle_actor_role", "")) == ROLE_PLAYER:
			out.append(unit_value)
	return out


## Dry-run of the same checks change() commits; {ok, reason}. Never mutates.
static func preview(loop: Dictionary, unit_id: String, slot: String, inventory_index: int, expected_code: int) -> Dictionary:
	var result := _prepare(loop, unit_id, slot, inventory_index, expected_code)
	return {"ok": bool(result["ok"]), "reason": str(result.get("reason", ""))}


## The equipment transaction. {ok, loop, error}; on failure loop is the input untouched.
static func change(loop: Dictionary, unit_id: String, slot: String, inventory_index: int, expected_code: int) -> Dictionary:
	var prepared := _prepare(loop, unit_id, slot, inventory_index, expected_code)
	if not prepared["ok"]:
		return {"ok": false, "loop": loop, "error": str(prepared.get("reason", "rejected"))}
	return {"ok": true, "loop": prepared["loop"], "error": ""}


static func _prepare(loop: Dictionary, unit_id: String, slot: String, inventory_index: int, expected_code: int) -> Dictionary:
	var actor := _live_unit(loop, unit_id).duplicate(true)
	if actor.is_empty() or str(actor.get("battle_actor_role", "")) != ROLE_PLAYER:
		return {"ok": false, "reason": "unknown_member"}
	var items: Dictionary = loop.get("equipment_items", {})
	if items.is_empty() or not loop.has("weapon_ranges") or not loop.has("skill_book"):
		return {"ok": false, "reason": "invalid_sandbox"}
	var error := ProgressionRules.refresh_input_error(actor, items)
	if error != "": return {"ok": false, "reason": error}
	error = StaminaRules.input_error(actor, items)
	if error != "": return {"ok": false, "reason": error}
	error = ExperienceRules.input_error(loop, actor)
	if error != "": return {"ok": false, "reason": error}
	var result := EquipmentRules.replace(actor, slot, inventory_index, expected_code, items)
	if not result["ok"]:
		return {"ok": false, "reason": str(result.get("reason", "rejected"))}
	# Native409090 uses range0 for an empty weapon slot: no hostile normal target.
	var weapon := EquipmentRules.equipped_code(result["equipment"], "weapon")
	if not loop["weapon_ranges"].has(str(weapon)):
		return {"ok": false, "reason": "missing_weapon_range"}
	var next := BattleLoopConfig.copy(loop)
	var changed := _live_unit(next, unit_id) # the in-place record of the sandbox copy
	changed["inventory"] = result["inventory"]
	changed["equipment"] = result["equipment"]
	changed["weapon_code"] = weapon
	var stamina := StaminaRules.effects(changed, items)
	if not stamina["ok"]: return {"ok": false, "reason": str(stamina.get("reason", "invalid_stamina_equipment_effect"))}
	var count := CombatSequence.attack_count(changed, next["skill_book"]["actors"].get(str(changed.get("actor_id", "")), {}), items)
	if not count["ok"]: return {"ok": false, "reason": str(count.get("reason", "invalid_extra_attack_source"))}
	var extra := ExtraActionRules.equipment(changed, items)
	if not extra["ok"]: return {"ok": false, "reason": str(extra.get("reason", "invalid_extra_action_source"))}
	var effects := WeaponEffects.effects(changed, items)
	if not effects["ok"]: return {"ok": false, "reason": str(effects.get("reason", "invalid_weapon_effect_source"))}
	var recovery := ResourceRecoveryRules.effects(changed, items)
	if not recovery["ok"]: return {"ok": false, "reason": str(recovery.get("reason", "invalid_resource_effect"))}
	var casting := StatusApplicationRules.modifiers(changed, next["skill_book"], items)
	if not casting["ok"]: return {"ok": false, "reason": str(casting.get("reason", "invalid_casting_equipment"))}
	var position := PositionCapabilities.effects(changed, next["skill_book"], items)
	if not position["ok"]: return {"ok": false, "reason": str(position.get("reason", "invalid_position_capability"))}
	var pattern := PositionCapabilities.attack_pattern(changed, items, next["attack_patterns"], next["weapon_ranges"])
	if not pattern["ok"]: return {"ok": false, "reason": str(pattern.get("reason", "invalid_attack_pattern"))}
	var multiplier := ExperienceRules.multiplier(changed, items)
	if not multiplier["ok"]: return {"ok": false, "reason": str(multiplier.get("reason", "invalid_experience_equipment_effect"))}
	error = ProgressionRules.refresh_input_error(changed, items)
	if error != "": return {"ok": false, "reason": error}
	changed.merge(ProgressionRules.refresh_growth_stats(changed, items), true)
	return {"ok": true, "loop": next}


## In-place lookup by unit id ({} when absent); callers duplicate when they must not mutate.
static func _live_unit(loop: Dictionary, unit_id: String) -> Dictionary:
	for unit_value in loop.get("units", []):
		if typeof(unit_value) == TYPE_DICTIONARY and str((unit_value as Dictionary).get("id", "")) == unit_id:
			return unit_value
	return {}


## The carry with units re-captured from the sandbox loop. Only carry.units entries
## whose id exists in both are replaced; every other top-level field is kept as is.
static func project(carry: Dictionary, loop: Dictionary) -> Dictionary:
	var next := carry.duplicate(true)
	var captured: Dictionary = CarryRules.capture(loop).get("units", {})
	var units: Dictionary = (next.get("units", {}) as Dictionary).duplicate(true) if typeof(next.get("units")) == TYPE_DICTIONARY else {}
	for unit_id in units.keys():
		if captured.has(unit_id):
			# A kept ST (keep_stamina) rides on the record; equipment never changes it.
			if units[unit_id] is Dictionary and units[unit_id].has("stamina"): captured[unit_id]["stamina"] = units[unit_id]["stamina"]
			units[unit_id] = captured[unit_id]
	next["units"] = units
	return next
