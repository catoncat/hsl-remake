extends RefCounted
## Battle loop inventory and equipment transactions: the shared player／AI item commit
## (`resolve_item_use`) and the player's Use, Drop, Give session
## (`begin_give` → `confirm_give*` → `finish_give`) and Equip (`change_equipment`:
## validate every current-equipment effect, then commit inventory, equipped codes and the
## refreshed attributes together) with the full-bag hand of the Equip／Drop window
## (`unequip_to_hand`, `swap_hand_with_bag`, `equip_from_hand`, `return_hand`, `discard_hand`
## over HAND_KEY), plus the equipment screen's projection of a carry into
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
const Traversal = preload("res://game/sim/ActorTraversalRules.gd")
const Navigation = preload("res://game/sim/AINavigationRules.gd")
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
	# The player's Use passes `spend` (a use without effect still spends the item, 0x444aba).
	# The AI applies 0x409e40 without a benefit check too (0x4402ed), but its triggers already
	# guarantee one (0x40c110 needs 10 HP missing, 0x40c230 matches a present status), so its
	# callers keep the refusal only as the stale-plan guard.
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


## Equip／Drop window (mode 4／5): the held bag item goes back (0x438868 right click, 0x438c84 a
## bag row) — 0x436e80 closed its gap when it was lifted, 0x436e30 puts it first-empty. Free.
static func return_held_item(loop: Dictionary, inventory_index: int, expected_code: int) -> Dictionary:
	if not BattlePlayLoop.player_action_valid(loop, "action_menu"):
		return BattlePlayLoop.copy(loop)
	var next := BattlePlayLoop.copy(loop)
	var actor := BattlePlayLoop.unit_ref(next, str(next.get("selected_unit_id", "")))
	var put := InventoryRules.put_back(actor.get("inventory", []), inventory_index, expected_code)
	if not put["ok"]:
		return BattlePlayLoop.copy(loop)
	actor["inventory"] = put["inventory"]
	return next


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
	var committed := _equip(loop, slot, inventory_index, expected_code)
	if committed.is_empty():
		return BattlePlayLoop.copy(loop)
	# Confirmed exchange, not a UI-held item. Preserve this round's queue snapshot.
	# Native ordinary Equip is free; confirmation/move rollback are remake choices.
	return BattlePlayLoop.settle_action(committed["loop"], "equip")


## One equipment commit for the selected actor: validate every current-equipment effect, run
## EquipmentRules.replace, then commit inventory, equipped codes and refreshed attributes
## together. `hand`: the Equip／Drop window's hand swaps with the slot without the bag
## (0x437020 take-off, 0x436f30 put-on) — replace() runs on a bag holding only the hand's item
## (the PartyEquipmentRules._prepare reading) and the actor keeps its own bag. {} when refused,
## else {loop, old_item_code}.
static func _equip(loop: Dictionary, slot: String, inventory_index: int, expected_code: int, hand: bool = false) -> Dictionary:
	var id := str(loop.get("selected_unit_id", ""))
	var actor := BattlePlayLoop.unit_ref(loop, id)
	if ProgressionRules.refresh_input_error(actor, loop["equipment_items"]) != "":
		return {}
	if StaminaRules.input_error(actor, loop["equipment_items"]) != "": return {}
	if ExperienceRules.input_error(loop, actor) != "": return {}
	var probe := actor
	if hand:
		if not InventoryRules.valid(actor.get("inventory")): return {}
		var scratch: Array = []
		scratch.resize(InventoryRules.CAPACITY)
		scratch.fill(0)
		if expected_code > 0: scratch[0] = expected_code
		probe = actor.duplicate()
		probe["inventory"] = scratch
	var result := EquipmentRules.replace(probe, slot, inventory_index, expected_code, loop["equipment_items"])
	if not result["ok"]:
		return {}
	# Native409090 uses range0 for an empty weapon slot: no hostile normal target.
	# Removing a weapon is a real equip transaction, not a substitute melee attack.
	var weapon := EquipmentRules.equipped_code(result["equipment"], "weapon")
	if not loop["weapon_ranges"].has(str(weapon)):
		return {}
	var next := BattlePlayLoop.copy(loop)
	var changed := BattlePlayLoop.unit_ref(next, id)
	if not hand: changed["inventory"] = result["inventory"]
	changed["equipment"] = result["equipment"]
	changed["weapon_code"] = weapon
	if not StaminaRules.effects(changed, next["equipment_items"])["ok"]: return {}
	if not BattleLoopCombat.attack_count(next, changed)["ok"]: return {}
	if not ExtraActionRules.equipment(changed, next["equipment_items"])["ok"]: return {}
	if not WeaponEffects.effects(changed, next["equipment_items"])["ok"]: return {}
	if not ResourceRecoveryRules.effects(changed, next["equipment_items"])["ok"]: return {}
	if not StatusApplicationRules.modifiers(changed, next["skill_book"], next["equipment_items"])["ok"]: return {}
	if not PositionCapabilities.effects(changed, next["skill_book"], next["equipment_items"])["ok"] or not BattlePlayLoop.weapon_pattern(next, changed)["ok"]: return {}
	if not ExperienceRules.multiplier(changed, next["equipment_items"])["ok"]: return {}
	if ProgressionRules.refresh_input_error(changed, next["equipment_items"]) != "": return {}
	changed.merge(ProgressionRules.refresh_growth_stats(changed, next["equipment_items"]), true)
	return {"loop": next, "old_item_code": int(result["old_item_code"])}


## Equip／Drop window hand ([0x4c1ce4]) while the bag is full. With room in the bag a take-off
## still goes to the first empty slot and the window holds it as a draft (change_equipment,
## return_held_item); only a full bag leaves the piece outside bag and equipment, so the loop
## keeps it under HAND_KEY as {owner_id, item_code}. The key is absent while the hand is empty,
## and every other player command is refused while it is present (player_action_valid), so a
## held piece never meets a turn hand-off or a checkpoint. Bag＋equipment＋hand keep their count
## except through 丟棄. Each command is free and keeps the window open.
const HAND_KEY := "held_item"


## The selected actor's held item code, 0 when the hand is empty.
static func held_item_code(loop: Dictionary) -> int:
	var hand: Variant = loop.get(HAND_KEY, {})
	if not hand is Dictionary or str(hand.get("owner_id", "")) != str(loop.get("selected_unit_id", "")):
		return 0
	return int(hand.get("item_code", 0))


## The action gate for a hand command: the hand does not block its own commands; a held item
## must belong to the selected actor and match `expected_hand` (0: the hand must be empty).
static func _hand_ready(loop: Dictionary, expected_hand: int) -> bool:
	var view := loop.duplicate()
	view.erase(HAND_KEY)
	if not BattlePlayLoop.player_action_valid(view, "action_menu"):
		return false
	if not loop.has(HAND_KEY):
		return expected_hand == 0
	return expected_hand > 0 and held_item_code(loop) == expected_hand


static func _set_hand(loop: Dictionary, code: int) -> void:
	if code > 0:
		loop[HAND_KEY] = {"owner_id": str(loop.get("selected_unit_id", "")), "item_code": code}
	else:
		loop.erase(HAND_KEY)


static func _bag(loop: Dictionary) -> Array:
	return BattlePlayLoop.unit_ref(loop, str(loop.get("selected_unit_id", ""))).get("inventory", [])


## Empty hand on a worn slot with a full bag (0x439997..0x4399e1): 0x437020 takes the piece off
## into the hand without looking at the bag. unequip_blocked pieces stay (replace refuses).
static func unequip_to_hand(loop: Dictionary, slot: String, expected_code: int) -> Dictionary:
	if expected_code <= 0 or not _hand_ready(loop, 0):
		return BattlePlayLoop.copy(loop)
	var bag := _bag(loop)
	if not InventoryRules.valid(bag) or bag.any(func(code): return int(code) == 0):
		return BattlePlayLoop.copy(loop)
	var actor := BattlePlayLoop.unit_ref(loop, str(loop.get("selected_unit_id", "")))
	if EquipmentRules.equipped_code(actor.get("equipment", []), slot) != expected_code:
		return BattlePlayLoop.copy(loop)
	var committed := _equip(loop, slot, -1, 0, true)
	if committed.is_empty():
		return BattlePlayLoop.copy(loop)
	_set_hand(committed["loop"], int(committed["old_item_code"]))
	return BattlePlayLoop.settle_action(committed["loop"], "equip")


## Held item on a worn slot (0x43993e..0x439995): 0x436f30(member, held, slot); a refusal (-1)
## keeps the hand, otherwise the old piece (or nothing) comes into the hand.
static func equip_from_hand(loop: Dictionary, slot: String, expected_hand: int) -> Dictionary:
	if expected_hand <= 0 or not _hand_ready(loop, expected_hand):
		return BattlePlayLoop.copy(loop)
	var committed := _equip(loop, slot, 0, expected_hand, true)
	if committed.is_empty():
		return BattlePlayLoop.copy(loop)
	_set_hand(committed["loop"], int(committed["old_item_code"]))
	return BattlePlayLoop.settle_action(committed["loop"], "equip")


## Held item on a bag row (0x438c84..0x438d5e): a full bag (last slot occupied, 0x436ed0) gives
## the row's item to the hand, closes its gap (0x436e80) and puts the held item into slot 8;
## otherwise the held item goes first-empty (0x436e30) and the hand is empty.
static func swap_hand_with_bag(loop: Dictionary, inventory_index: int, expected_code: int, expected_hand: int) -> Dictionary:
	if expected_hand <= 0 or not _hand_ready(loop, expected_hand):
		return BattlePlayLoop.copy(loop)
	var bag := _bag(loop)
	if not InventoryRules.valid(bag):
		return BattlePlayLoop.copy(loop)
	if int(bag[InventoryRules.CAPACITY - 1]) == 0:
		return return_hand(loop, expected_hand)
	var removed := InventoryRules.remove(bag, inventory_index, expected_code)
	if not removed["ok"]:
		return BattlePlayLoop.copy(loop)
	var inserted := InventoryRules.insert(removed["inventory"], expected_hand)
	if not inserted["ok"]:
		return BattlePlayLoop.copy(loop)
	var next := BattlePlayLoop.copy(loop)
	BattlePlayLoop.unit_ref(next, str(next["selected_unit_id"]))["inventory"] = inserted["inventory"]
	_set_hand(next, expected_code)
	return next


## Right click with a held item (0x438868): first empty slot (0x436e30) → 0x438882 clears the
## hand; no room → 0x438872 keeps hand and window (refused, loop unchanged).
static func return_hand(loop: Dictionary, expected_hand: int) -> Dictionary:
	if expected_hand <= 0 or not _hand_ready(loop, expected_hand):
		return BattlePlayLoop.copy(loop)
	var inserted := InventoryRules.insert(_bag(loop), expected_hand)
	if not inserted["ok"]:
		return BattlePlayLoop.copy(loop)
	var next := BattlePlayLoop.copy(loop)
	BattlePlayLoop.unit_ref(next, str(next["selected_unit_id"]))["inventory"] = inserted["inventory"]
	_set_hand(next, 0)
	next["command_menu"] = BattlePlayLoop.menu_for_unit(next, str(next["selected_unit_id"])) # built while the hand held
	return next


## Mode 5's 丟棄 on the held item (0x43aacb..0x43aae6): only a non-important item (0x40e690)
## leaves the hand.
static func discard_hand(loop: Dictionary, expected_hand: int) -> Dictionary:
	if expected_hand <= 0 or not _hand_ready(loop, expected_hand):
		return BattlePlayLoop.copy(loop)
	if InventoryRules.discard_error(expected_hand, loop["equipment_items"]) != "":
		return BattlePlayLoop.copy(loop)
	var next := BattlePlayLoop.copy(loop)
	_set_hand(next, 0)
	return BattlePlayLoop.settle_action(next, "drop")


static func recovery_target_ids(loop: Dictionary) -> Array:
	return _item_recipient_ids(loop, true)


## 0x40f440(user, range, mode 4) → 0x40f200／0x40ed50 (AINavigationRules.native_flood, mode 4):
## range 2 for a 3×3 user (+0x2c, 0x444901), else 1, for Use; Give floods range 1 and 0x40f520
## clears the centre (0x444bc7). The user's own cells carry no side bits (0x411990 clears a
## 3×3 user's ring; the traversal context leaves the user out). Marked cells, origin included.
static func item_range_cells(loop: Dictionary, user: Dictionary, give: bool = false) -> Array:
	if not Presence.living(user): return []
	var context: Dictionary = Traversal.prepare(user, loop["units"], BattlePlayLoop.TerrainEdits.tiles(loop), {}, loop["map_size"])
	if not context["ok"]: return []
	context = context.duplicate()
	context["mode"] = Navigation.ITEM_MODE
	context["mask"] = Navigation.ITEM_MASK
	var origin: Vector2i = user["coord"]
	var flood: Dictionary = Navigation.native_flood(context, origin, 2 if Footprint.radius(user) == 1 and not give else 1)
	var cells: Array = []
	var radius: int = flood["radius"]
	var width: int = flood["width"]
	for by in range(width):
		for bx in range(width):
			if flood["values"][by * width + bx] <= 0: continue
			var cell := Vector2i(origin.x - radius + bx, origin.y - radius + by)
			if not (give and cell == origin): cells.append(cell)
	return cells


## The AI's Use lead-in range (low-word state 7, 0x440176): 0x40f440(user, 2 for a 3×3 user
## else 1, 0x40bab0(user)) — the ground flood of 0x40ed50 in the user's side mode (P 2／E 3／
## N 7, a flyer too, RangePropagationRules.offensive_mode) with that mode's mask
## (ActorTraversalRules.MASKS), the centre kept (no 0x40f520). A 3×3 user sets 0x4c1a78, so
## 0x40ed50 first stops at a cell whose 3×3, the flood origin excepted, holds a 0x74000 word or
## a height-255 cell (0x40ee5f..0x40eec4 → 0x40ecc0); such a cell is priced past any budget
## here. Presentation-only query: the AI's item choice and commit never read it.
static func ai_item_range_cells(loop: Dictionary, user: Dictionary) -> Array:
	if not Presence.living(user): return []
	var context: Dictionary = Traversal.prepare(user, loop["units"], BattlePlayLoop.TerrainEdits.tiles(loop), {}, loop["map_size"])
	var mode := BattlePlayLoop.RangePropagationRules.offensive_mode(user)
	if not context["ok"] or not Traversal.MASKS.has(mode): return []
	context = context.duplicate()
	context["mode"] = mode
	context["mask"] = Traversal.MASKS[mode]
	var origin: Vector2i = user["coord"]
	var large := Footprint.radius(user) == 1
	var radius := 2 if large else 1
	if large:
		var costs: PackedInt32Array = context["cell_costs"].duplicate()
		var size: Vector2i = context["size"]
		for y in range(origin.y - radius, origin.y + radius + 1):
			for x in range(origin.x - radius, origin.x + radius + 1):
				var cell := Vector2i(x, y)
				if cell != origin and x >= 0 and y >= 0 and x < size.x and y < size.y and _large_step_blocked(cell, origin, context):
					costs[y * size.x + x] = 0x10000
		context["cell_costs"] = costs
	var flood: Dictionary = Navigation.native_flood(context, origin, radius)
	var cells: Array = []
	var width: int = flood["width"]
	for by in range(width):
		for bx in range(width):
			if flood["values"][by * width + bx] > 0: cells.append(Vector2i(origin.x - radius + bx, origin.y - radius + by))
	return cells


## 0x40ecc0(x, y, 0x74000) with 0x4c1a78 = 1 outside mode 6: any side bit or 0x4000 word, or a
## height-255 cell, in the 3×3 around `cell` minus the flood origin.
static func _large_step_blocked(cell: Vector2i, origin: Vector2i, context: Dictionary) -> bool:
	for y in range(-1, 2):
		for x in range(-1, 2):
			var point := cell + Vector2i(x, y)
			if point == origin: continue
			if int(context["flags"].get(point, 0)) & 0x74000 or int(context["heights"].get(point, 0)) == 255: return true
	return false


## A pick needs a marked cell (0x40f560) whose word has pmPlayer 0x10000 (0x444976／0x444c6f)
## and, for Use only, a recipient that is not no_attack (0x446b00). The user's word is only on
## its centre cell (its ring is cleared), so it is a Use target and never a Give target.
static func _item_recipient_ids(loop: Dictionary, use: bool) -> Array:
	var actor := BattlePlayLoop.unit_ref(loop, str(loop.get("selected_unit_id", "")))
	if not Presence.living(actor):
		return []
	var marked := item_range_cells(loop, actor, not use)
	var targets: Array = []
	var units: Array = [actor]
	for unit in loop["units"]:
		if str(unit["id"]) != str(actor["id"]): units.append(unit)
	for recipient in units:
		var own := str(recipient["id"]) == str(actor["id"])
		if not Presence.living(recipient):
			continue
		var side := ActorRoleRules.side_mask(recipient)
		if (side & ActorRoleRules.SIDE_PLAYER) == 0 or (use and bool(recipient.get("no_attack", false))):
			continue
		var cells: Array = [actor["coord"]] if own else Footprint.cells(recipient)
		if not cells.any(func(cell): return marked.has(cell)):
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
