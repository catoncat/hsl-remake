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
##   rules: static-derived docs/evidence_packets/static_reverse/original_storage_window.md
##     (hand_action: hand kept across members, storage put／take, 丟棄 non-important, 使用 via 0x409e40, full-bag swap)
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
const ContentPaths = preload("res://game/sim/ContentPaths.gd")
const InventoryRules = preload("res://game/sim/InventoryRules.gd")
const StorageRules = preload("res://game/sim/PartyStorageRules.gd")
const ItemUseRules = preload("res://game/sim/ItemUseRules.gd")

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
		var parsed: Variant = ContentPaths.read_json(path)
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


## The window's hand (0x4c1ce4): a bag item still in its slot ({unit_id, slot, code} — the
## original lifts it out with 0x436e80; here it leaves the bag only when it lands) or a loose
## item ({loose: true, code} — taken from the storage or swapped out of a full bag). 上一位／
## 下一位 keep it (0x4282c0 never writes 0x4c1ce4). remove_hand takes the hand's item out of its
## bag (a loose item has none). {ok, loop, code, reason}.
static func remove_hand(loop: Dictionary, hand: Dictionary) -> Dictionary:
	var code := int(hand.get("code", 0))
	if code <= 0:
		return {"ok": false, "loop": loop, "code": 0, "reason": "empty_hand"}
	var next := BattleLoopConfig.copy(loop)
	if bool(hand.get("loose", false)):
		return {"ok": true, "loop": next, "code": code, "reason": ""}
	var unit := _live_unit(next, str(hand.get("unit_id", "")))
	var removed := InventoryRules.remove(unit.get("inventory", []), int(hand.get("slot", -1)), code)
	if unit.is_empty() or not removed["ok"]:
		return {"ok": false, "loop": loop, "code": code, "reason": "inventory_selection_changed"}
	unit["inventory"] = removed["inventory"]
	return {"ok": true, "loop": next, "code": code, "reason": ""}


## The hand clicked on bag slot `slot` of `unit_id` (0x42923b): the item goes to the first empty
## slot; only a full bag (slot 7 occupied, 0x436ed0) gives the clicked item to the hand.
## {ok, loop, hand, reason}; the new hand is {} or a loose item.
static func place_hand(loop: Dictionary, hand: Dictionary, unit_id: String, slot: int) -> Dictionary:
	var lifted := remove_hand(loop, hand)
	if not lifted["ok"]:
		return {"ok": false, "loop": loop, "hand": hand, "reason": lifted["reason"]}
	var next: Dictionary = lifted["loop"]
	var unit := _live_unit(next, unit_id)
	if unit.is_empty() or not InventoryRules.valid(unit.get("inventory")):
		return {"ok": false, "loop": loop, "hand": hand, "reason": "unknown_member"}
	var inventory: Array = unit["inventory"]
	var swapped := 0
	if int(inventory[InventoryRules.CAPACITY - 1]) > 0:
		if slot < 0 or slot >= InventoryRules.CAPACITY:
			return {"ok": false, "loop": loop, "hand": hand, "reason": "inventory_full"}
		swapped = int(inventory[slot])
		inventory = InventoryRules.remove(inventory, slot, swapped)["inventory"]
	var inserted := InventoryRules.insert(inventory, int(lifted["code"]))
	if not inserted["ok"]:
		return {"ok": false, "loop": loop, "hand": hand, "reason": str(inserted["reason"])}
	unit["inventory"] = inserted["inventory"]
	return {"ok": true, "loop": next, "hand": {"loose": true, "code": swapped} if swapped > 0 else {}, "reason": "", "slot": int(inserted["slot"])}


## One hand gesture of the shared status window over (sandbox loop, party storage, hand);
## `catalog` is EquipmentCatalog.items() (the `important` flag, 0x40e690). Actions:
##   place {unit_id, slot}  the hand onto a bag slot (place_hand)
##   store                  the hand into the storage list (0x44f2d0 in the window,音 400)
##   retrieve {index}       empty hand takes one of list row `index`; important rows stay (0x4154cd)
##   drop                   丟棄: a non-important hand is thrown away (0x42a7e2)
##   use {unit_id}          使用: 0x409e40(member, hand, 0, 1) — spends the hand on the member
##   equip {unit_id, slot}  the hand onto an equipment slot (0x436f30 via change())
##   back {unit_id}         right click: the hand into the member's first empty slot (0x436e30)
## Returns {ok, loop, storage, hand, reason}; a refusal returns the inputs unchanged.
static func hand_action(loop: Dictionary, storage: Dictionary, hand: Dictionary, action: String, args: Dictionary, catalog: Dictionary) -> Dictionary:
	var refused := {"ok": false, "loop": loop, "storage": storage, "hand": hand}
	var code := int(hand.get("code", 0))
	match action:
		"place":
			var placed := place_hand(loop, hand, str(args.get("unit_id", "")), int(args.get("slot", -1)))
			refused["reason"] = placed["reason"]
			return {"ok": true, "loop": placed["loop"], "storage": storage, "hand": placed["hand"], "reason": ""} if placed["ok"] else refused
		"store":
			var lifted := remove_hand(loop, hand)
			var stored := StorageRules.put(storage, code, catalog) if lifted["ok"] else {"ok": false, "reason": lifted["reason"]}
			refused["reason"] = stored["reason"] if not stored["ok"] else ""
			return {"ok": true, "loop": lifted["loop"], "storage": stored["storage"], "hand": {}, "reason": ""} if stored["ok"] else refused
		"retrieve":
			if code > 0:
				refused["reason"] = "hand_full"
				return refused
			var taken := StorageRules.take(storage, int(args.get("index", -1)), catalog)
			refused["reason"] = taken.get("reason", "")
			return {"ok": true, "loop": loop, "storage": taken["storage"], "hand": {"loose": true, "code": int(taken["code"])}, "reason": ""} if taken["ok"] else refused
		"drop":
			if code <= 0 or bool((catalog.get(str(code), {}) as Dictionary).get("important", true)):
				refused["reason"] = "important_item" if code > 0 else "empty_hand"
				return refused
			var lifted := remove_hand(loop, hand)
			refused["reason"] = lifted["reason"]
			return {"ok": true, "loop": lifted["loop"], "storage": storage, "hand": {}, "reason": ""} if lifted["ok"] else refused
		"use":
			var definition: Dictionary = (loop.get("consumables", {}) as Dictionary).get(str(code), {})
			var target := _live_unit(loop, str(args.get("unit_id", "")))
			if code <= 0 or definition.is_empty() or target.is_empty():
				refused["reason"] = "not_usable"
				return refused
			var effect := ItemUseRules.prepare(target, definition, true)
			# The between-battle window applies HP／MP／status only; an item whose effect is a
			# permanent or temporary stat change stays in the hand (ItemResolutionRules owns those).
			if not effect["ok"] or not effect["permanent_proposals"].is_empty() or not effect["stat_proposals"].is_empty():
				refused["reason"] = str(effect.get("reason", "not_usable_here"))
				return refused
			var lifted := remove_hand(loop, hand)
			if not lifted["ok"]:
				refused["reason"] = lifted["reason"]
				return refused
			_live_unit(lifted["loop"], str(args["unit_id"])).merge(effect["changes"], true)
			return {"ok": true, "loop": lifted["loop"], "storage": storage, "hand": {}, "reason": ""}
		"equip":
			var unit_id := str(args.get("unit_id", ""))
			var working := loop
			var index := int(hand.get("slot", -1))
			if bool(hand.get("loose", false)) or str(hand.get("unit_id", "")) != unit_id:
				var placed := place_hand(loop, hand, unit_id, -1)
				if not placed["ok"]:
					refused["reason"] = placed["reason"]
					return refused
				working = placed["loop"]
				index = int(placed["slot"])
			var changed := change(working, unit_id, str(args.get("slot", "")), index, code)
			refused["reason"] = changed["error"]
			return {"ok": true, "loop": changed["loop"], "storage": storage, "hand": {}, "reason": ""} if changed["ok"] else refused
		"back":
			var unit_id := str(args.get("unit_id", ""))
			if code <= 0 or (not bool(hand.get("loose", false)) and str(hand.get("unit_id", "")) == unit_id):
				return {"ok": true, "loop": loop, "storage": storage, "hand": {}, "reason": ""}
			var placed := place_hand(loop, hand, unit_id, -1)
			if placed["ok"]:
				return {"ok": true, "loop": placed["loop"], "storage": storage, "hand": {}, "reason": ""}
			# Full bag (remake reading): a loose item goes to the storage, a bag item stays in its bag.
			if bool(hand.get("loose", false)):
				return {"ok": true, "loop": loop, "storage": StorageRules.put(storage, code, catalog)["storage"], "hand": {}, "reason": ""}
			return {"ok": true, "loop": loop, "storage": storage, "hand": {}, "reason": ""}
	refused["reason"] = "unknown_action"
	return refused


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
