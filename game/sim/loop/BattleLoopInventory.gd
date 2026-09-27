extends RefCounted
## Battle loop inventory and equipment transactions: the shared player／AI item commit
## (`resolve_item_use`) and the player's Use, Drop, Give session
## (`begin_give` → `confirm_give*` → `finish_give`) and Equip (`change_equipment`:
## validate every current-equipment effect, then commit inventory, equipped codes and the
## refreshed attributes together), plus the equipment screen's projection of a carry into
## the live battle (`apply_battle_equipment_carry`). Each transaction ends in
## BattlePlayLoop.settle_action, which owns the action budget and turn hand-off.
## Static functions over the one loop dictionary; BattlePlayLoop forwards to them and
## stays the single mutable battle-state owner.
## provenance:
##   rules: static-derived docs/evidence_packets/static_reverse/original_tactical_items.md
##   rules: static-derived docs/evidence_packets/static_reverse/original_give_exchange.md
##   rules: static-derived docs/evidence_packets/static_reverse/original_item_actions.md
##   rules: static-derived docs/evidence_packets/static_reverse/original_ohm_village.md
##   rules: static-derived docs/evidence_packets/static_reverse/original_equipment_mobility.md
##   rules: remake-invented
##     (give confirmation／revision guards, free equip confirmation, storage projection —
##     docs/architecture/BATTLE_SYSTEMS.md#inventory-and-equipment)
##   rules: provisional (large user Use range: body-edge distance 1 stands in for the range-2 flood)

const BattlePlayLoop = preload("res://game/sim/loop/BattlePlayLoop.gd")
const BattleLoopRewards = preload("res://game/sim/loop/BattleLoopRewards.gd")
const BattleLoopCombat = preload("res://game/sim/loop/BattleLoopCombat.gd")
const WeaponEffects = preload("res://game/sim/WeaponEffectRules.gd")
const ProgressionRules = preload("res://game/sim/ProgressionRules.gd")
const ExperienceRules = preload("res://game/sim/ExperienceRules.gd")
const InventoryRules = preload("res://game/sim/InventoryRules.gd")
const StatusApplicationRules = preload("res://game/sim/StatusApplicationRules.gd")
const ActionBudgetRules = preload("res://game/sim/ActionBudgetRules.gd")
const EquipmentRules = preload("res://game/sim/EquipmentRules.gd")
const ExtraActionRules = preload("res://game/sim/ExtraActionRules.gd")
const PositionCapabilities = preload("res://game/sim/PositionCapabilityRules.gd")
const Footprint = preload("res://game/sim/FootprintRules.gd")
const ResourceRecoveryRules = preload("res://game/sim/ResourceRecoveryRules.gd")
const StaminaRules = preload("res://game/sim/StaminaRules.gd")
const CampaignCarryRules = preload("res://game/sim/CampaignCarryRules.gd")
const ItemResolutionRules = preload("res://game/sim/ItemResolutionRules.gd")
const DamageRandomStream = preload("res://game/sim/DamageRandomStream.gd")
const Presence = preload("res://game/sim/BattlePresenceRules.gd")
const ActorRoleRules = preload("res://game/sim/ActorRoleRules.gd")
const BattleOutcome = preload("res://game/sim/BattleOutcome.gd")


static func use_item(loop: Dictionary, item_code: String, target_id: String = "", inventory_index: int = -1) -> Dictionary:
	if not BattlePlayLoop.player_action_valid(loop, "action_menu"):
		return BattlePlayLoop.copy(loop)
	var next := BattlePlayLoop.copy(loop)
	var unit_id := str(next.get("selected_unit_id", ""))
	var recipient_id := target_id if target_id != "" else unit_id
	if not recovery_target_ids(next).has(recipient_id):
		return next
	if resolve_item_use(next, unit_id, recipient_id, item_code, inventory_index, true).is_empty(): return next
	return BattlePlayLoop.settle_action(next, "use")


static func resolve_item_use(loop: Dictionary, actor_id: String, recipient_id: String, item_code: String, inventory_index: int, spend: bool = false) -> Dictionary:
	# Shared player/AI commit. The caller owns command eligibility and exactly one handoff.
	# Only the player's Use passes `spend` (a use without effect still spends the item);
	# the AI callers keep the refusal until AI-PRIO-2 decides their original behaviour.
	if BattleOutcome.decided(loop) or not loop.get("scenario_ok", false) or ItemResolutionRules.state_error(loop) != "": return {}
	var actor := BattlePlayLoop.unit_ref(loop, actor_id)
	var recipient := BattlePlayLoop.unit_ref(loop, recipient_id)
	var proposed := ItemResolutionRules.prepare(actor,recipient,item_code,inventory_index,loop["consumables"].get(item_code,{}),loop["equipment_items"],loop[DamageRandomStream.LOOP_KEY],int(loop["item_use_sequence"])+1,spend)
	if not proposed["ok"]: return {}
	recipient.merge(proposed["target_changes"],true)
	actor["inventory"] = proposed["inventory"]
	loop[DamageRandomStream.LOOP_KEY] = proposed["rng"]
	loop["item_use_sequence"] = proposed["receipt"]["sequence"]
	loop["last_item_use"] = proposed["receipt"]
	return proposed["receipt"]


static func discard_item(loop: Dictionary, item_code: String, inventory_index: int = -1) -> Dictionary:
	# Ordinary Drop changes only inventory. Give has its own checked session.
	if not BattlePlayLoop.player_action_valid(loop, "action_menu"):
		return BattlePlayLoop.copy(loop)
	var next := BattlePlayLoop.copy(loop)
	var unit_id := str(next.get("selected_unit_id", ""))
	var actor := BattlePlayLoop.unit_ref(next, unit_id)
	var index := InventoryRules.find_item(actor["inventory"], int(item_code), inventory_index)
	if index < 0:
		return next
	var discarded := InventoryRules.discard(actor["inventory"], index, int(item_code), next["equipment_items"])
	if not discarded["ok"]:
		return next
	actor["inventory"] = discarded["inventory"]
	return BattlePlayLoop.settle_action(next, "drop")


static func begin_give(loop: Dictionary) -> Dictionary:
	if not BattlePlayLoop.player_action_valid(loop, "action_menu"):
		return BattlePlayLoop.copy(loop)
	var next := BattlePlayLoop.copy(loop)
	next["give_session"] = {"owner_id": next["selected_unit_id"], "action_used": false}
	next["item_revision"] = int(next["item_revision"]) + 1
	next["interaction"] = "give_session"
	return next


static func give_target_ids(loop: Dictionary) -> Array:
	return _item_recipient_ids(loop, false)


static func confirm_give(loop: Dictionary, target_id: String, index: int, expected_code: int, target_index: int, expected_return: int, revision: int) -> Dictionary:
	if not BattlePlayLoop.player_action_valid(loop, "give_session") or loop["give_session"].get("owner_id") != loop["selected_unit_id"] or revision != int(loop["item_revision"]):
		return BattlePlayLoop.copy(loop)
	if not give_target_ids(loop).has(target_id) or not loop["equipment_items"].has(str(expected_code)) or (expected_return > 0 and not loop["equipment_items"].has(str(expected_return))):
		return BattlePlayLoop.copy(loop)
	var actor := BattlePlayLoop.unit_ref(loop, str(loop["selected_unit_id"]))
	var target := BattlePlayLoop.unit_ref(loop, target_id)
	if not InventoryRules.valid(actor.get("inventory")) or not InventoryRules.valid(target.get("inventory")):
		return BattlePlayLoop.copy(loop)
	var result := InventoryRules.exchange(actor["inventory"], index, expected_code, target["inventory"], target_index, expected_return)
	if not result["ok"]:
		return BattlePlayLoop.copy(loop)
	var next := BattlePlayLoop.copy(loop)
	BattlePlayLoop.unit_ref(next, str(loop["selected_unit_id"]))["inventory"] = result["sender"]
	BattlePlayLoop.unit_ref(next, target_id)["inventory"] = result["receiver"]
	next["give_session"]["action_used"] = ActionBudgetRules.give_used(bool(next["give_session"]["action_used"]), expected_code, int(result["returned"]))
	next["item_revision"] = int(next["item_revision"]) + 1
	return next


static func finish_give(loop: Dictionary, revision: int) -> Dictionary:
	if not BattlePlayLoop.player_action_valid(loop, "give_session") or loop["give_session"].get("owner_id") != loop["selected_unit_id"] or revision != int(loop["item_revision"]):
		return BattlePlayLoop.copy(loop)
	var next := BattlePlayLoop.copy(loop)
	var used := bool(next["give_session"]["action_used"])
	next["give_session"] = {}
	next["item_revision"] = int(next["item_revision"]) + 1
	next["interaction"] = "action_menu"
	return BattlePlayLoop.settle_action(next, "give", used)


static func change_equipment(loop: Dictionary, slot: String, inventory_index: int, expected_code: int) -> Dictionary:
	if not BattlePlayLoop.player_action_valid(loop, "action_menu"):
		return BattlePlayLoop.copy(loop)
	var id := str(loop.get("selected_unit_id", ""))
	var actor := BattlePlayLoop.unit_ref(loop, id)
	if ProgressionRules.refresh_input_error(actor, loop["equipment_items"]) != "":
		return BattlePlayLoop.copy(loop)
	if StaminaRules.input_error(actor, loop["equipment_items"]) != "": return BattlePlayLoop.copy(loop)
	if ExperienceRules.input_error(loop, actor) != "": return BattlePlayLoop.copy(loop)
	var result := EquipmentRules.replace(actor, slot, inventory_index, expected_code, loop["equipment_items"])
	if not result["ok"]:
		return BattlePlayLoop.copy(loop)
	# Native409090 uses range0 for an empty weapon slot: no hostile normal target.
	# Removing a weapon is a real equip transaction, not a substitute melee attack.
	var weapon := EquipmentRules.equipped_code(result["equipment"], "weapon")
	if not loop["weapon_ranges"].has(str(weapon)):
		return BattlePlayLoop.copy(loop)
	var next := BattlePlayLoop.copy(loop)
	var changed := BattlePlayLoop.unit_ref(next, id)
	changed["inventory"] = result["inventory"]
	changed["equipment"] = result["equipment"]
	changed["weapon_code"] = weapon
	if not StaminaRules.effects(changed, next["equipment_items"])["ok"]: return BattlePlayLoop.copy(loop)
	if not BattleLoopCombat.attack_count(next, changed)["ok"]: return BattlePlayLoop.copy(loop)
	if not ExtraActionRules.equipment(changed, next["equipment_items"])["ok"]: return BattlePlayLoop.copy(loop)
	if not WeaponEffects.effects(changed, next["equipment_items"])["ok"]: return BattlePlayLoop.copy(loop)
	if not ResourceRecoveryRules.effects(changed, next["equipment_items"])["ok"]: return BattlePlayLoop.copy(loop)
	if not StatusApplicationRules.modifiers(changed, next["skill_book"], next["equipment_items"])["ok"]: return BattlePlayLoop.copy(loop)
	if not PositionCapabilities.effects(changed, next["skill_book"], next["equipment_items"])["ok"] or not BattlePlayLoop.weapon_pattern(next, changed)["ok"]: return BattlePlayLoop.copy(loop)
	if not ExperienceRules.multiplier(changed, next["equipment_items"])["ok"]: return BattlePlayLoop.copy(loop)
	if ProgressionRules.refresh_input_error(changed, next["equipment_items"]) != "": return BattlePlayLoop.copy(loop)
	changed.merge(ProgressionRules.refresh_growth_stats(changed, next["equipment_items"]), true)
	# Confirmed exchange, not a UI-held item. Preserve this round's queue snapshot.
	# Native ordinary Equip is free; confirmation/move rollback are remake choices.
	return BattlePlayLoop.settle_action(next, "equip")


static func recovery_target_ids(loop: Dictionary) -> Array:
	return _item_recipient_ids(loop, true)


## Use marks 0x40f440(user, 1, mode 4) (2 for a large user, 0x444901) with the user's own cell;
## Give marks range 1 and 0x40f520 clears the centre. A pick needs a marked cell whose word has
## pmPlayer 0x10000 (0x444976／0x444c6f) and, for Use only, no no_attack (0x446b00). Mode 4 does
## not enter a 0x20000 cell unless the user is no_block. Body-edge distance 1 stands in for the
## flood; a large user's range-2 flood is not modelled.
static func _item_recipient_ids(loop: Dictionary, use: bool) -> Array:
	var actor := BattlePlayLoop.unit_ref(loop, str(loop.get("selected_unit_id", "")))
	if not Presence.living(actor):
		return []
	var targets: Array = []
	var units: Array = [actor]
	for unit in loop["units"]:
		if str(unit["id"]) != str(actor["id"]): units.append(unit)
	for recipient in units:
		var own := str(recipient["id"]) == str(actor["id"])
		if not Presence.living(recipient) or (own and not use):
			continue
		var side := ActorRoleRules.side_mask(recipient)
		if (side & ActorRoleRules.SIDE_PLAYER) == 0 or (use and bool(recipient.get("no_attack", false))):
			continue
		if not own and (((side & ActorRoleRules.SIDE_ENEMY) != 0 and not bool(actor["traversal"]["no_block"])) or Footprint.distance(actor, recipient) > 1):
			continue
		targets.append(str(recipient["id"]))
	return targets


static func apply_battle_equipment_carry(loop: Dictionary, carry: Dictionary) -> Dictionary:
	## Project only the equipment screen's changed party fields into the live battle.
	## HP, statuses, experience and queue ownership remain battle state.
	var next := BattlePlayLoop.copy(loop)
	if str(carry.get("schema", "")) != CampaignCarryRules.SCHEMA:
		return {"ok": false, "error": "invalid_storage_carry_schema", "loop": next}
	var records: Dictionary = carry.get("units", {})
	var applied: Array = []
	for unit_value in next.get("units", []):
		if typeof(unit_value) != TYPE_DICTIONARY:
			continue
		var unit: Dictionary = unit_value
		var unit_id := str(unit.get("id", ""))
		if str(unit.get("battle_actor_role", "")) != BattlePlayLoop.ROLE_PLAYER or not records.has(unit_id):
			continue
		var record: Variant = records[unit_id]
		if typeof(record) != TYPE_DICTIONARY or str((record as Dictionary).get("actor_id", "")) != str(unit.get("actor_id", "")):
			return {"ok": false, "error": "storage_actor_mismatch:" + unit_id, "loop": next}
		var candidate := unit.duplicate(true)
		for key in ["equipment", "weapon_code", "inventory"]:
			if (record as Dictionary).has(key):
				candidate[key] = (record as Dictionary)[key].duplicate(true) if typeof((record as Dictionary)[key]) in [TYPE_ARRAY, TYPE_DICTIONARY] else (record as Dictionary)[key]
		if not InventoryRules.valid(candidate.get("inventory")):
			return {"ok": false, "error": "storage_invalid_inventory:" + unit_id, "loop": next}
		var item_error := ProgressionRules.refresh_input_error(candidate, next.get("equipment_items", {}))
		if item_error != "":
			return {"ok": false, "error": "storage_invalid_equipment:%s:%s" % [unit_id, item_error], "loop": next}
		var refreshed := ProgressionRules.refresh_growth_stats(candidate, next.get("equipment_items", {}))
		unit["inventory"] = candidate["inventory"]
		unit["equipment"] = candidate["equipment"]
		unit["weapon_code"] = candidate["weapon_code"]
		unit.merge(refreshed, true)
		applied.append(unit_id)
	next["storage_window_projection"] = {"schema": "hsl_battle_storage_projection.v1", "applied_unit_ids": applied}
	return {"ok": true, "error": "", "loop": next}
