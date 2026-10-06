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
##     (hand_action: hand across members, storage, 丟棄, 使用 0x409e40(…, 0, 1), take-off 0x437020, bag swap)
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
const ItemResolution = preload("res://game/sim/ItemResolutionRules.gd")
const DamageRandom = preload("res://game/sim/DamageRandomStream.gd")

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
	# The menus list the registered party only (0x4c4360 slot codes): a scenario member the
	# carry does not hold — a 有才產生 slot never carried, a deregistered member — is not in
	# the party and must not show up as its template.
	var carried: Dictionary = carry.get("units", {}) if carry.get("units") is Dictionary else {}
	if not carried.is_empty():
		var kept: Array = []
		for unit_value in applied.get("units", []):
			var unit: Dictionary = unit_value if typeof(unit_value) == TYPE_DICTIONARY else {}
			if str(unit.get("battle_actor_role", "")) == ROLE_PLAYER and not carried.has(str(unit.get("id", ""))):
				continue
			kept.append(unit_value)
		applied["units"] = kept
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


## The window's slot setter 0x436f30(member, hand code, slot) with a loose hand: the job
## (0x4464f0 → ITEM +0xa8), the slot type (ITEM +8 via the table at 0x437004) and the old piece's
## +0xa4 bit 1 lock are checked; -1 leaves everything as is, otherwise the code is written into the
## slot and the old one (0 when the slot was empty) returned for the hand. The bag is never looked
## at, so a full bag does not matter; the held and worn codes are never compared, so the same piece
## is written back and returned (the hand keeps it). Same checks as change() (_prepare in hand mode).
## {ok, loop, old, error}; on failure loop is the input untouched.
static func equip_from_hand(loop: Dictionary, unit_id: String, slot: String, code: int) -> Dictionary:
	var old := EquipmentRules.equipped_code(_live_unit(loop, unit_id).get("equipment", []), slot)
	var prepared := _prepare(loop, unit_id, slot, -1, code, true)
	if not prepared["ok"]:
		return {"ok": false, "loop": loop, "old": 0, "error": str(prepared.get("reason", "rejected"))}
	return {"ok": true, "loop": prepared["loop"], "old": old, "error": ""}


## `to_hand`: the window's take-off (0x437020) and hand setter (0x436f30) move pieces between the
## slot and the hand without looking at the bag, so the bag takes no part — replace() runs on a bag
## holding only the hand's code (none for a take-off) and the member keeps its own.
static func _prepare(loop: Dictionary, unit_id: String, slot: String, inventory_index: int, expected_code: int, to_hand: bool = false) -> Dictionary:
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
	var bag: Variant = actor.get("inventory")
	if to_hand and InventoryRules.valid(bag):
		var empty: Array = []
		empty.resize(InventoryRules.CAPACITY)
		empty.fill(0)
		if expected_code > 0:
			empty[0] = expected_code
			inventory_index = 0
		actor["inventory"] = empty
	var result := EquipmentRules.replace(actor, slot, inventory_index, expected_code, items, to_hand)
	if to_hand and result["ok"]:
		result["inventory"] = (bag as Array).duplicate()
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


## The window's hand (0x4c1ce4): a loose item ({loose: true, code} — lifted out of a bag
## (0x436e80), taken off (0x437020／0x436f30), bought (0x41553c), taken from the storage or
## swapped out of a full bag) or, for callers that hold a bag item in place, {unit_id, slot,
## code}. 上一位／
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
##   use {unit_id}          使用: 0x409e40(member, hand, 0, 1) — a non-zero return spends the hand (_use_stored)
##   equip {unit_id, slot}  the hand onto an equipment slot (0x436f30): a loose／other member's item through
##                          equip_from_hand (no bag slot needed), a held own-bag item through change(); the old piece onto the hand
##   lift {unit_id, slot}   empty hand takes a bag item out, the bag closes up (0x436e80)
##   unequip {unit_id, slot} empty hand takes a worn piece off onto the hand (0x437020; no bag slot needed)
##   back {unit_id}         right click under OPT-GUIDE＝提示: the hand into the member's first empty slot (remake reading, see below)
## Returns {ok, loop, storage, hand, reason}; a refusal returns the inputs unchanged, except that a
## 使用 whose return is zero keeps its damage-stream draws on the refused loop.
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
			# 0x42a887: a zero return keeps the hand (0x42a8a6); otherwise 0x434d10 and the hand is cleared.
			var lifted := remove_hand(loop, hand)
			if not lifted["ok"]:
				refused["reason"] = lifted["reason"]
				return refused
			var used := _use_stored(lifted["loop"], str(args.get("unit_id", "")), code)
			if not used["ok"]:
				refused["reason"] = used["reason"]
				if used.has("rng"):
					refused["loop"] = BattleLoopConfig.copy(loop)
					refused["loop"][DamageRandom.LOOP_KEY] = used["rng"]
				return refused
			return {"ok": true, "loop": used["loop"], "storage": storage, "hand": {}, "reason": ""}
		"equip":
			var unit_id := str(args.get("unit_id", ""))
			var old := EquipmentRules.equipped_code(_live_unit(loop, unit_id).get("equipment", []), str(args.get("slot", "")))
			if bool(hand.get("loose", false)) or str(hand.get("unit_id", "")) != unit_id or old == code:
				# 0x436f30 straight from the hand: no bag slot needed; an item held in a bag leaves it
				# first (the original lifts with 0x436e80, so its hand is always loose). The same code
				# as the worn piece is written back and returned: the hand keeps it (音 400).
				var lifted := remove_hand(loop, hand)
				var worn := equip_from_hand(lifted["loop"], unit_id, str(args.get("slot", "")), code) if lifted["ok"] else {"ok": false, "error": lifted["reason"]}
				refused["reason"] = worn["error"]
				if not worn["ok"]:
					return refused
				return {"ok": true, "loop": worn["loop"], "storage": storage, "hand": {"loose": true, "code": worn["old"]} if int(worn["old"]) > 0 else {}, "reason": ""}
			var index := int(hand.get("slot", -1))
			var changed := change(loop, unit_id, str(args.get("slot", "")), index, code)
			refused["reason"] = changed["error"]
			if not changed["ok"]:
				return refused
			# 0x436f30: the old piece goes onto the hand, not into the bag.
			var swapped := _lift_last(changed["loop"], unit_id, old)
			return {"ok": true, "loop": swapped["loop"], "storage": storage, "hand": swapped["hand"], "reason": ""}
		"lift":
			# 0x436e80: an empty hand takes the bag item out; the slots after it close up.
			if code > 0:
				refused["reason"] = "hand_full"
				return refused
			var unit := _live_unit(loop, str(args.get("unit_id", "")))
			var inventory: Array = unit.get("inventory", [])
			var index := int(args.get("slot", -1))
			var picked := int(inventory[index]) if index >= 0 and index < inventory.size() else 0
			var lifted := remove_hand(loop, {"unit_id": str(args.get("unit_id", "")), "slot": index, "code": picked})
			refused["reason"] = lifted["reason"]
			return {"ok": true, "loop": lifted["loop"], "storage": storage, "hand": {"loose": true, "code": picked}, "reason": ""} if lifted["ok"] else refused
		"unequip":
			# 0x437020: an empty hand takes the worn piece off onto the hand (399): the slot is cleared
			# and the code returned without a bag check (a full bag does not matter); item +0xa4 bit 2
			# (unequip_blocked) returns 0 and nothing moves. 0x429e75 then refreshes (0x448840).
			if code > 0:
				refused["reason"] = "hand_full"
				return refused
			var unit_id := str(args.get("unit_id", ""))
			var old := EquipmentRules.equipped_code(_live_unit(loop, unit_id).get("equipment", []), str(args.get("slot", "")))
			var prepared := _prepare(loop, unit_id, str(args.get("slot", "")), -1, 0, true)
			if not prepared["ok"]:
				refused["reason"] = str(prepared.get("reason", "rejected"))
				return refused
			return {"ok": true, "loop": prepared["loop"], "storage": storage, "hand": {"loose": true, "code": old}, "reason": ""}
		"back":
			# The original root (0x428dac) closes on right click／Esc only while the hand is empty
			# (0x428dc7) and moves no held item; putting the hand into the first empty slot is a remake
			# reading. A full bag keeps a loose hand on the cursor — the original's outcome for it.
			var unit_id := str(args.get("unit_id", ""))
			if code <= 0 or (not bool(hand.get("loose", false)) and str(hand.get("unit_id", "")) == unit_id):
				return {"ok": true, "loop": loop, "storage": storage, "hand": {}, "reason": ""}
			var placed := place_hand(loop, hand, unit_id, -1)
			if placed["ok"]:
				return {"ok": true, "loop": placed["loop"], "storage": storage, "hand": {}, "reason": ""}
			if bool(hand.get("loose", false)):
				refused["reason"] = str(placed["reason"])
				return refused
			return {"ok": true, "loop": loop, "storage": storage, "hand": {}, "reason": ""}
	refused["reason"] = "unknown_action"
	return refused


## change() returns a taken-off piece to the bag's first empty slot (the last occupied one of the
## packed bag); the window puts it on the hand instead. {loop, hand}.
static func _lift_last(loop: Dictionary, unit_id: String, code: int) -> Dictionary:
	if code <= 0:
		return {"loop": loop, "hand": {}}
	var inventory: Array = _live_unit(loop, unit_id).get("inventory", [])
	var last := -1
	for index in range(inventory.size()):
		if int(inventory[index]) > 0:
			last = index
	var lifted := remove_hand(loop, {"unit_id": unit_id, "slot": last, "code": code})
	return {"loop": lifted["loop"], "hand": {"loose": true, "code": code}} if lifted["ok"] else {"loop": loop, "hand": {}}


## 使用 on the 倉庫 page: 0x409e40(member, code, 0, 1). The fourth argument zeroes ebp and skips the
## temporary attack／defense block (0x40a121／0x40a125) and, after the 402 cue (0x40a347, played
## whenever the return is non-zero), the floating numbers (0x40a39b); the permanent block before it
## (0x409ef8–0x40a115) still draws from the damage stream (ItemResolutionRules.draw_permanent). The
## return (0x40a369–0x40a391) is non-zero when the HP, MP, stamina or cure field is set or a permanent
## field took: 力／禦／魔／速之源 whenever set, 土／火／水／風／靈之源 only with a gain under the 80 cap
## (0x409fb3). So 會心之素／鐵壁之素 (temporary fields only) and a resistance source on a member already
## at 80 return 0 and stay in the hand — the latter after its draw. {ok, loop, reason[, rng]}.
static func _use_stored(loop: Dictionary, unit_id: String, code: int) -> Dictionary:
	var definition: Dictionary = (loop.get("consumables", {}) as Dictionary).get(str(code), {})
	var target := _live_unit(loop, unit_id)
	if code <= 0 or definition.is_empty() or target.is_empty():
		return {"ok": false, "reason": "not_usable"}
	var effect := ItemUseRules.prepare(target, definition, true)
	if not effect["ok"]:
		return {"ok": false, "reason": str(effect.get("reason", "not_usable"))}
	var items: Dictionary = loop.get("equipment_items", {})
	var proposals: Array = effect["permanent_proposals"]
	if not proposals.is_empty() and not DamageRandom.valid(loop.get(DamageRandom.LOOP_KEY)):
		return {"ok": false, "reason": "invalid_item_random_state"}
	var next := BattleLoopConfig.copy(loop)
	var changed := _live_unit(next, unit_id)
	changed.merge(effect["changes"], true)
	var took := false
	if not proposals.is_empty():
		var drawn := ItemResolution.draw_permanent(changed, proposals, loop[DamageRandom.LOOP_KEY])
		next[DamageRandom.LOOP_KEY] = drawn["state"]
		for row in drawn["effects"]:
			took = took or not str(row["kind"]).begins_with("resist_") or int(row["amount"]) > 0
		if not took and not _fields_set(definition):
			return {"ok": false, "reason": "item_has_no_effect", "rng": drawn["state"]}
	elif not _fields_set(definition):
		return {"ok": false, "reason": "item_has_no_effect"}
	# 0x40a2ac／0x40a337: a permanent gain and the cure block end in 0x448840.
	if took or bool(effect["cured_weaken"]):
		var error := ProgressionRules.refresh_input_error(changed, items)
		if error != "":
			return {"ok": false, "reason": error}
		changed.merge(ProgressionRules.refresh_growth_stats(changed, items), true)
	return {"ok": true, "loop": next, "reason": ""}


## The non-permanent return terms of 0x409e40: the HP (+0x2c), MP (+0x28) and stamina (+0x30) fields
## and the +0xa0 cure word (0x409eed: only its 0xf0000080 bits count) — set, whatever the target's state.
static func _fields_set(item: Dictionary) -> bool:
	for key in ["heal_hp", "heal_mp", "restore_stamina", "cure_poison", "cure_paralysis", "cure_no_magic", "cure_weaken"]:
		if int(item.get(key, 0)) > 0:
			return true
	return false


## In-place lookup by unit id ({} when absent); callers duplicate when they must not mutate.
static func _live_unit(loop: Dictionary, unit_id: String) -> Dictionary:
	for unit_value in loop.get("units", []):
		if typeof(unit_value) == TYPE_DICTIONARY and str((unit_value as Dictionary).get("id", "")) == unit_id:
			return unit_value
	return {}


## The carry with units re-captured from the sandbox loop. Only carry.units entries
## whose id exists in both are replaced, and a carried damage stream takes the sandbox's (使用
## draws from it); every other top-level field is kept as is.
static func project(carry: Dictionary, loop: Dictionary) -> Dictionary:
	var next := carry.duplicate(true)
	if next.has(DamageRandom.LOOP_KEY):
		CarryRules.keep_damage_stream(next, loop)
	var captured: Dictionary = CarryRules.capture(loop).get("units", {})
	var units: Dictionary = (next.get("units", {}) as Dictionary).duplicate(true) if typeof(next.get("units")) == TYPE_DICTIONARY else {}
	for unit_id in units.keys():
		if captured.has(unit_id):
			# A kept ST (keep_stamina) rides on the record; equipment never changes it.
			if units[unit_id] is Dictionary and units[unit_id].has("stamina"): captured[unit_id]["stamina"] = units[unit_id]["stamina"]
			units[unit_id] = captured[unit_id]
	next["units"] = units
	return next
