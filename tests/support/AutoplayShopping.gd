extends RefCounted

## Town shopping for the chapter autoplay (tests/run_chapter_autoplay_tests.gd): when the
## story explorer's walk opens a town shop, every carried member buys the best gear the shop
## sells for its job in each of GEAR_SLOTS (bought through TownRuntime.shop_buy →
## WorldPartyRules.buy, so price and bag room are the rules' own), wears it at once through
## PartyEquipmentRules (sandbox → change — the between-battle 整理裝備 screen's own transaction;
## the town has no equip entry of its own, so the member's bag, equipment and weapon code go
## back into the carry the way that screen's close projects them: TownRuntime.carry +
## party_changed), and sells the piece it took off. Healing items come first: gear is bought
## only with the gold above the restock reserve (_restock_reserve: what filling every recorded
## member up to POTIONS_PER_MEMBER of the cheapest healing item in the price list costs), and a
## shop that sells healing items fills the members (the hero first) before any gear — a player
## restocks before upgrading. Level 6 (chapter hand-off): 席達鎮's weapon and armor shops come
## before its item shop, spent the purse down to 240 and the party entered with 2 回復藥 bought,
## 雷歐納德 at 12/41 after the soldiers' first strikes and nothing to drink.
## HSL_AUTOPLAY_GOLD=unlimited is a harness diagnostic: the carry's gold is topped up before
## buying and restored afterwards, so purchases cost nothing and every member gets the best
## gear the town sells; potions still stop at the bag's free slots (InventoryRules.insert).
## Nothing here is product behaviour or evidence about the original economy.

const PlayLoop = preload("res://game/sim/loop/BattlePlayLoop.gd")
const PartyEquipment = preload("res://game/sim/PartyEquipmentRules.gd")
const EquipmentRules = preload("res://game/sim/EquipmentRules.gd")
const Inventory = preload("res://game/sim/InventoryRules.gd")
const ItemUse = preload("res://game/sim/ItemUseRules.gd")
const BattleScenario = preload("res://game/sim/BattleScenario.gd")

## Slots bought for, in priority order (weapon first, then body armor, head, foot).
const GEAR_SLOTS := ["weapon", "armor", "head", "foot"]
## Carry record keys an equipment change writes (CampaignCarryRules.DEFAULT_POLICY unit keys
## the transaction touches); the member's level, growth and history stay as carried.
const EQUIPMENT_KEYS := ["inventory", "equipment", "weapon_code"]
## Healing items each member is restocked to before the gear is bought (bag room permitting).
## 2 before lane B3: the town-6 gear run spent the purse and the level-6 party had 2 回復藥 in all.
const POTIONS_PER_MEMBER := 4
const GOLD_ENV := "HSL_AUTOPLAY_GOLD"
const GOLD_UNLIMITED := "unlimited"
const GOLD_NORMAL := "normal"
const UNLIMITED_GOLD := 1000000


static func gold_mode() -> String:
	return GOLD_UNLIMITED if OS.get_environment(GOLD_ENV) == GOLD_UNLIMITED else GOLD_NORMAL


## Shops in the open shop of `town`. Returns the receipt {ok, reason, gold_mode, gold_before,
## gold_after, purchases: [{unit, item, name, cost, slot, equipped, sold}], skipped: [...]};
## ok false (with reason) when the carry has no member records or no template scenario.
static func shop(town: Node, campaign: Dictionary) -> Dictionary:
	var receipt := {"ok": false, "reason": "", "gold_mode": gold_mode(), "gold_before": 0, "gold_after": 0, "purchases": [], "skipped": []}
	if str(town.mode) != "shop":
		receipt["reason"] = "not_in_shop"
		return receipt
	var carry: Dictionary = town.carry
	if (carry.get("units", {}) as Dictionary).is_empty():
		receipt["reason"] = "no_member_records"
		return receipt
	var template := PartyEquipment.template_scenario_path(campaign, str(carry.get("from_scenario_id", "")))
	if template == "":
		receipt["reason"] = "no_template_scenario:%s" % str(carry.get("from_scenario_id", ""))
		return receipt
	var scenario := BattleScenario.load_file(template)
	var box := PartyEquipment.sandbox(PlayLoop.create([], "", scenario), carry)
	if not bool(box["ok"]):
		receipt["reason"] = "sandbox:%s" % str(box["error"])
		return receipt
	receipt["ok"] = true
	var gold_before := _gold(town)
	receipt["gold_before"] = gold_before
	var unlimited := gold_mode() == GOLD_UNLIMITED
	if unlimited:
		_set_gold(town, UNLIMITED_GOLD)
	var goods: Array = town.shop_goods()
	var catalog: Dictionary = town.shop_catalog
	var loop: Dictionary = box["loop"]
	var trace := OS.get_environment("HSL_AUTOPLAY_SHOP_TRACE") != ""
	if trace:
		print("AUTOPLAY_SHOP goods=%s gold=%d members=%s" % [str(goods), _gold(town), str(PartyEquipment.members(loop).map(func(unit): return str(unit["id"])))])
	var potion := _cheapest_healing(loop, goods, catalog)
	if potion > 0:
		for unit_id in restock_order(loop, town.carry.get("units", {})):
			var held := _healing_count(town, unit_id, loop["consumables"])
			var wanted := _restock_wanted(town, unit_id, held)
			if trace:
				print("AUTOPLAY_SHOP %s potion=%d held=%d bag=%s" % [unit_id, potion, held, str(((town.carry.get("units", {}) as Dictionary).get(unit_id, {}) as Dictionary).get("inventory", []))])
			while held < wanted:
				var bought: Dictionary = town.shop_buy(potion, unit_id)
				if not bool(bought.get("ok", false)):
					receipt["skipped"].append({"unit": unit_id, "item": potion, "slot": "potion", "reason": str(bought.get("reason", ""))})
					break
				held += 1
				receipt["purchases"].append({"unit": unit_id, "item": potion, "name": str((catalog.get(str(potion), {}) as Dictionary).get("name", "")), "cost": int(bought.get("cost", 0)), "slot": "potion", "equipped": false, "sold": 0})
		var restocked := PartyEquipment.sandbox(PlayLoop.create([], "", scenario), town.carry)
		if bool(restocked["ok"]):
			loop = restocked["loop"]
	var reserve := 0 if unlimited else _restock_reserve(loop, town, catalog)
	for member in PartyEquipment.members(loop):
		var unit_id := str(member["id"])
		for slot in GEAR_SLOTS:
			var unit := PlayLoop.unit(loop, unit_id)
			var best := _best_gear(loop, unit, slot, goods, catalog, _gold(town) - reserve)
			if trace:
				print("AUTOPLAY_SHOP %s %s worn=%d job=%s best=%s" % [unit_id, slot, EquipmentRules.equipped_code(unit.get("equipment", []), slot), str(unit.get("growth_profile", {}).get("job_code", "")), JSON.stringify(best)])
			if best.is_empty():
				continue
			var bought: Dictionary = town.shop_buy(int(best["code"]), unit_id)
			if not bool(bought.get("ok", false)):
				receipt["skipped"].append({"unit": unit_id, "item": int(best["code"]), "slot": slot, "reason": str(bought.get("reason", ""))})
				continue
			var row := {"unit": unit_id, "item": int(best["code"]), "name": str(best["name"]), "cost": int(bought.get("cost", 0)), "slot": slot, "equipped": false, "sold": 0}
			var worn := _equip(town, scenario, unit_id, slot, int(best["code"]))
			row["equipped"] = bool(worn["ok"])
			if not bool(worn["ok"]):
				row["reason"] = str(worn["reason"])
			elif int(worn["old_code"]) > 0:
				row["sold"] = _sell(town, unit_id, int(worn["old_code"]))
			receipt["purchases"].append(row)
			var refreshed := PartyEquipment.sandbox(PlayLoop.create([], "", scenario), town.carry)
			if bool(refreshed["ok"]):
				loop = refreshed["loop"]
	if unlimited:
		_set_gold(town, gold_before)
	receipt["gold_after"] = _gold(town)
	return receipt


## Recorded members (`records`: the carry's member records; the shop sells to no one else), the
## scenario's hero first, then in roster order.
static func restock_order(loop: Dictionary, records: Dictionary) -> Array:
	var hero := str(loop.get("player_unit_id", ""))
	var out: Array = []
	if records.has(hero):
		out.append(hero)
	for member in PartyEquipment.members(loop):
		var unit_id := str(member["id"])
		if records.has(unit_id) and not out.has(unit_id):
			out.append(unit_id)
	return out


static func _gold(town: Node) -> int:
	return int((town.carry.get("loop", {}) as Dictionary).get("gold", 0))


## Harness top-up / restore of the carry's gold (HSL_AUTOPLAY_GOLD=unlimited only); written back
## the way a shop transaction is.
static func _set_gold(town: Node, gold: int) -> void:
	var carry: Dictionary = town.carry.duplicate(true)
	var loop: Dictionary = carry.get("loop", {})
	loop["gold"] = gold
	carry["loop"] = loop
	town.carry = carry
	town.party_changed.emit(town.state, carry)


## Best affordable item the shop sells for `slot` that the member can wear
## (PartyEquipmentRules.preview on a sandbox copy holding the item) and that beats what it
## wears now by GEAR value; {} when none. {code, name, value}.
static func _best_gear(loop: Dictionary, unit: Dictionary, slot: String, goods: Array, catalog: Dictionary, gold: int) -> Dictionary:
	var items: Dictionary = loop["equipment_items"]
	var worn := _gear_value(items.get(str(EquipmentRules.equipped_code(unit.get("equipment", []), slot)), {}), slot)
	var best := {}
	for code in goods:
		var item: Dictionary = items.get(str(int(code)), {})
		if item.is_empty() or int(item.get("type_code", 0)) != EquipmentRules.TYPES[EquipmentRules.SLOTS.find(slot)]:
			continue
		var cost := int((catalog.get(str(int(code)), {}) as Dictionary).get("cost", 0))
		if cost > gold:
			continue
		var value := _gear_value(item, slot)
		if value <= worn or (not best.is_empty() and value <= float(best["value"])):
			continue
		var trial: Dictionary = PlayLoop.copy(loop)
		var trial_unit := _live_unit(trial, str(unit["id"]))
		var inserted := Inventory.insert(trial_unit.get("inventory", []), int(code))
		if not bool(inserted.get("ok", false)):
			continue
		trial_unit["inventory"] = inserted["inventory"]
		if not bool(PartyEquipment.preview(trial, str(unit["id"]), slot, int(inserted["slot"]), int(code))["ok"]):
			continue
		best = {"code": int(code), "name": str(item.get("name", "")), "value": value}
	return best


## The unit dictionary inside `loop` itself (BattlePlayLoop.unit returns a copy).
static func _live_unit(loop: Dictionary, unit_id: String) -> Dictionary:
	for unit in loop.get("units", []):
		if str(unit.get("id", "")) == unit_id:
			return unit
	return {}


## Weapon: attack + magic attack; armor pieces: defense + max HP / 4 + avoid.
static func _gear_value(item: Dictionary, slot: String) -> float:
	if item.is_empty():
		return 0.0
	var effects: Dictionary = item.get("effects", {})
	if slot == "weapon":
		return float(int(effects.get("attack", 0)) + int(effects.get("magic_attack", 0)))
	return float(int(effects.get("defense", 0))) + float(int(effects.get("max_hp", 0))) / 4.0 + float(int(effects.get("avoid_hit_ratio", 0)))


## Wears `code` (just bought, in the member's bag) in `slot` through PartyEquipmentRules and
## writes the projected carry back to the town. {ok, reason, old_code}.
static func _equip(town: Node, scenario: Dictionary, unit_id: String, slot: String, code: int) -> Dictionary:
	var box := PartyEquipment.sandbox(PlayLoop.create([], "", scenario), town.carry)
	if not bool(box["ok"]):
		return {"ok": false, "reason": "sandbox:%s" % str(box["error"]), "old_code": 0}
	var unit := PlayLoop.unit(box["loop"], unit_id)
	var index := Inventory.find_item(unit.get("inventory", []), code)
	if index < 0:
		return {"ok": false, "reason": "not_in_bag", "old_code": 0}
	var old_code := EquipmentRules.equipped_code(unit.get("equipment", []), slot)
	var changed := PartyEquipment.change(box["loop"], unit_id, slot, index, code)
	if not bool(changed["ok"]):
		return {"ok": false, "reason": str(changed["error"]), "old_code": 0}
	var next_carry: Dictionary = town.carry.duplicate(true)
	var record: Dictionary = next_carry["units"][unit_id]
	var worn := PlayLoop.unit(changed["loop"], unit_id)
	for key in EQUIPMENT_KEYS:
		if worn.has(key):
			record[key] = worn[key].duplicate(true) if typeof(worn[key]) in [TYPE_ARRAY, TYPE_DICTIONARY] else worn[key]
	town.carry = next_carry
	town.party_changed.emit(town.state, next_carry)
	return {"ok": true, "reason": "", "old_code": old_code}


## Sells the piece the member took off (its bag slot holds it after the change); the price
## paid, 0 when the shop refused (important item) or the piece is not in the bag.
static func _sell(town: Node, unit_id: String, code: int) -> int:
	var inventory: Array = ((town.carry.get("units", {}) as Dictionary).get(unit_id, {}) as Dictionary).get("inventory", [])
	var index := Inventory.find_item(inventory, code)
	if index < 0:
		return 0
	var sold: Dictionary = town.shop_sell(unit_id, index)
	return int(sold.get("price", 0)) if bool(sold.get("ok", false)) else 0


## Gold that restocking every recorded member up to POTIONS_PER_MEMBER healing items would
## cost at the cheapest healing item of the price list (`catalog`: every shop item's price —
## the player has seen them), so a weapon or armor shop visited before the item shop leaves it.
static func _restock_reserve(loop: Dictionary, town: Node, catalog: Dictionary) -> int:
	var potion := _cheapest_healing(loop, catalog.keys(), catalog)
	if potion <= 0:
		return 0
	var missing := 0
	for unit_id in restock_order(loop, town.carry.get("units", {})):
		var held := _healing_count(town, unit_id, loop["consumables"])
		missing += maxi(0, _restock_wanted(town, unit_id, held) - held)
	return missing * int((catalog.get(str(potion), {}) as Dictionary).get("cost", 0))


## Cheapest healing item (ItemUseRules heal_hp > 0) among `goods`; 0 when none.
static func _cheapest_healing(loop: Dictionary, goods: Array, catalog: Dictionary) -> int:
	var consumables: Dictionary = loop["consumables"]
	var best := 0
	var best_cost := 0
	for code in goods:
		var slots: Array = [int(code), 0, 0, 0, 0, 0, 0, 0]
		var healing := ItemUse.first_healing_slot(slots, consumables)
		if not bool(healing.get("ok", false)) or int(healing.get("index", -1)) != 0:
			continue
		var cost := int((catalog.get(str(int(code)), {}) as Dictionary).get("cost", 0))
		if best == 0 or cost < best_cost:
			best = int(code)
			best_cost = cost
	return best


## Healing items `unit_id` is restocked to: POTIONS_PER_MEMBER, but never into its last free
## bag slot — a new piece of gear goes into the bag before it is worn (level 5, chapter hand-off:
## 琥's bag filled 8 of 8 with 回復藥 beside his spare 短劍 and herbs, and 鎖子甲 could not be bought).
static func _restock_wanted(town: Node, unit_id: String, held: int) -> int:
	var inventory: Array = ((town.carry.get("units", {}) as Dictionary).get(unit_id, {}) as Dictionary).get("inventory", [])
	var free := inventory.filter(func(code): return int(code) <= 0).size()
	return clampi(held + free - 1, held, maxi(held, POTIONS_PER_MEMBER))


static func _healing_count(town: Node, unit_id: String, consumables: Dictionary) -> int:
	var inventory: Array = ((town.carry.get("units", {}) as Dictionary).get(unit_id, {}) as Dictionary).get("inventory", [])
	var count := 0
	for code in inventory:
		if int(code) > 0 and consumables.has(str(int(code))) and int((consumables[str(int(code))] as Dictionary).get("heal_hp", 0)) > 0:
			count += 1
	return count
