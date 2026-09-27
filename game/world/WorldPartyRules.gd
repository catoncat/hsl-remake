extends RefCounted
## Bridge between the campaign carry (hsl_campaign_carry.v1: per-unit 8-slot
## inventories + loop gold) and the flat party view the town interpreter reads
## (gold, items [{id, count}], members [SID tokens]). Pure functions: every call
## returns new dictionaries and a receipt; nothing here touches scene state.
##
## Prices follow the original shop code (static-derived, docs/evidence_packets/
## static_reverse/original_shop_transaction.md): goods cost their ITEM.TXT price
## (hsl01.exe 0x414c00 reads ITEM+0x9c, compares the gold global 0x4c1bcc and
## deducts at once), selling pays 0x414ab0's price * 50 / 100 (floor half for the
## non-negative table prices), and an item flagged important (0x40e690, bit
## 0x08000000) is refused. Remake policy (provisional): a bought item goes to one
## chosen member's first empty slot instead of the original hand cursor; items
## granted by a town event (teGetItem) fill the first member with room, and a
## party with no room gets a visible "dropped" receipt instead of a silent loss.
## provenance:
##   rules: static-derived docs/evidence_packets/static_reverse/original_shop_transaction.md
##   rules: remake-invented
##     (bought item to a chosen member's first empty slot instead of the hand cursor; dropped receipt when the party has
##     no room)
##   strings: resource-derived content/imported/hsl/global/tables/EXTRAS.H

const CarryRules = preload("res://game/sim/CampaignCarryRules.gd")
const InventoryRules = preload("res://game/sim/InventoryRules.gd")

## 0x414ab0: (price * 0x32) / 100.
const SELL_PRICE_PERCENT := 50
## Carry unit fields the town job-up (JobUpRules.merge_source_template) writes.
const JOB_UP_KEYS := ["job_up_flags", "job_up_target_actor_id", "job_up_history"]


## Flat town party from a carry: gold, counted items across every member's
## inventory, and members as the SID_* speaker tokens the te scripts test
## (teCheckPlayerExist / tePlayerSelectInsertEvent), matched by PLAYERS row.
static func party_from_carry(carry: Dictionary, speakers: Dictionary) -> Dictionary:
	var party := {"gold": 0, "items": [], "members": [], "member_ids": [], "member_records": {}}
	if str(carry.get("schema", "")) != CarryRules.SCHEMA:
		return party
	party["gold"] = int((carry.get("loop", {}) as Dictionary).get("gold", 0))
	var counts := {}
	var units: Dictionary = carry.get("units", {})
	for unit_id in units.keys():
		var record: Dictionary = units[unit_id]
		(party["member_ids"] as Array).append(str(unit_id))
		var token := speaker_token(speakers, str(record.get("actor_id", "")))
		if token != "":
			(party["members"] as Array).append(token)
			# The job-up tokens (teCheckJobUp*) read attributes and write the
			# job-up layer of this member; apply_party copies the layer back.
			var view := {"unit_id": str(unit_id), "actor_id": str(record.get("actor_id", "")), "attributes": (record.get("attributes", {}) as Dictionary).duplicate(true)}
			for key in JOB_UP_KEYS:
				if record.has(key):
					view[key] = record[key].duplicate(true) if typeof(record[key]) in [TYPE_ARRAY, TYPE_DICTIONARY] else record[key]
			(party["member_records"] as Dictionary)[token] = view
		for code in record.get("inventory", []):
			if int(code) > 0:
				counts[int(code)] = int(counts.get(int(code), 0)) + 1
	for code in counts.keys():
		(party["items"] as Array).append({"id": int(code), "count": int(counts[code])})
	return party


## SID_* token whose PLAYERS row is the actor id (001 -> row 1 -> SID_雷歐納德).
static func speaker_token(speakers: Dictionary, actor_id: String) -> String:
	if not actor_id.is_valid_int():
		return ""
	for token in speakers.keys():
		var entry: Dictionary = speakers[token]
		if int(entry.get("players_row", -1)) == int(actor_id):
			return str(token)
	return ""


static func member_name(speakers: Dictionary, actor_id: String, fallback: String) -> String:
	var token := speaker_token(speakers, actor_id)
	if token == "":
		return fallback
	return str((speakers[token] as Dictionary).get("name_text", fallback))


## Ordered member summaries for the town UI: unit id, actor id, display name,
## inventory slots and free-slot count.
static func members(carry: Dictionary, speakers: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if str(carry.get("schema", "")) != CarryRules.SCHEMA:
		return result
	var units: Dictionary = carry.get("units", {})
	for unit_id in units.keys():
		var record: Dictionary = units[unit_id]
		var inventory: Array = record.get("inventory", [])
		var free := 0
		for code in inventory:
			if int(code) == 0:
				free += 1
		result.append({
			"unit_id": str(unit_id),
			"actor_id": str(record.get("actor_id", "")),
			"name": member_name(speakers, str(record.get("actor_id", "")), str(unit_id)),
			"inventory": inventory.duplicate(),
			"free_slots": free,
		})
	return result


## Writes a town run's party result back into the carry: gold is copied; item
## count deltas between before/after are applied as first-hole inserts (gains)
## or removals (losses) across the members' inventories.
static func apply_party(carry: Dictionary, before: Dictionary, after: Dictionary) -> Dictionary:
	var receipt := {"ok": true, "gold_before": int(before.get("gold", 0)), "gold_after": int(after.get("gold", 0)), "placed": [], "removed": [], "dropped": [], "job_ups": []}
	if str(carry.get("schema", "")) != CarryRules.SCHEMA:
		receipt["ok"] = false
		receipt["reason"] = "invalid_carry_schema"
		return {"carry": carry.duplicate(true), "receipt": receipt}
	var next := carry.duplicate(true)
	var loop: Dictionary = next.get("loop", {})
	loop["gold"] = int(after.get("gold", 0))
	next["loop"] = loop
	var after_records: Dictionary = after.get("member_records", {}) if typeof(after.get("member_records")) == TYPE_DICTIONARY else {}
	var before_records: Dictionary = before.get("member_records", {}) if typeof(before.get("member_records")) == TYPE_DICTIONARY else {}
	for token in after_records.keys():
		var view: Dictionary = after_records[token]
		var previous: Dictionary = before_records.get(token, {}) if typeof(before_records.get(token)) == TYPE_DICTIONARY else {}
		if str(view.get("job_up_target_actor_id", "")) == str(previous.get("job_up_target_actor_id", "")):
			continue
		var unit_id := str(view.get("unit_id", ""))
		if not (next.get("units", {}) as Dictionary).has(unit_id):
			continue
		var unit: Dictionary = next["units"][unit_id]
		for key in JOB_UP_KEYS:
			if view.has(key):
				unit[key] = view[key].duplicate(true) if typeof(view[key]) in [TYPE_ARRAY, TYPE_DICTIONARY] else view[key]
		(receipt["job_ups"] as Array).append({"unit_id": unit_id, "token": str(token), "to_actor_id": str(view.get("job_up_target_actor_id", "")), "flags": int(view.get("job_up_flags", 0))})
	var delta := {}
	for item in before.get("items", []):
		delta[int(item["id"])] = int(delta.get(int(item["id"]), 0)) - int(item.get("count", 0))
	for item in after.get("items", []):
		delta[int(item["id"])] = int(delta.get(int(item["id"]), 0)) + int(item.get("count", 0))
	var codes: Array = delta.keys()
	codes.sort()
	for code in codes:
		var count := int(delta[code])
		while count > 0:
			var placed := _insert_first_room(next, int(code))
			if placed == "":
				(receipt["dropped"] as Array).append({"item_id": int(code)})
			else:
				(receipt["placed"] as Array).append({"item_id": int(code), "unit_id": placed})
			count -= 1
		while count < 0:
			var removed := _remove_any(next, int(code))
			if removed != "":
				(receipt["removed"] as Array).append({"item_id": int(code), "unit_id": removed})
			count += 1
	return {"carry": next, "receipt": receipt}


## Shop purchase into one member: price checked against loop gold, the item goes
## to the member's first empty slot (InventoryRules.insert); nothing changes on
## failure.
static func buy(carry: Dictionary, unit_id: String, item_id: int, cost: int) -> Dictionary:
	if str(carry.get("schema", "")) != CarryRules.SCHEMA:
		return {"ok": false, "reason": "invalid_carry_schema"}
	var gold := int((carry.get("loop", {}) as Dictionary).get("gold", 0))
	if cost < 0 or item_id <= 0:
		return {"ok": false, "reason": "invalid_goods"}
	if gold < cost:
		return {"ok": false, "reason": "insufficient_gold", "gold": gold, "cost": cost}
	var units: Dictionary = carry.get("units", {})
	if not units.has(unit_id):
		return {"ok": false, "reason": "unknown_member"}
	var inserted := InventoryRules.insert((units[unit_id] as Dictionary).get("inventory", []), item_id)
	if not bool(inserted.get("ok", false)):
		return {"ok": false, "reason": str(inserted.get("reason", "inventory_full"))}
	var next := carry.duplicate(true)
	(next["units"][unit_id] as Dictionary)["inventory"] = inserted["inventory"]
	var loop: Dictionary = next.get("loop", {})
	loop["gold"] = gold - cost
	next["loop"] = loop
	return {"ok": true, "carry": next, "unit_id": unit_id, "item_id": item_id, "cost": cost, "gold": gold - cost, "slot": int(inserted.get("slot", -1))}


## Sell price as the original computes it (static-derived): cost * 50 / 100,
## which is half the ITEM.TXT cost rounded down for the table's non-negative prices.
static func sell_price(cost: int) -> int:
	return (maxi(cost, 0) * SELL_PRICE_PERCENT) / 100


## Sells the item in one member's slot (InventoryRules.remove keeps the slot
## order contract); important items cannot be sold.
static func sell(carry: Dictionary, unit_id: String, slot: int, item_id: int, price: int, catalog: Dictionary) -> Dictionary:
	if str(carry.get("schema", "")) != CarryRules.SCHEMA:
		return {"ok": false, "reason": "invalid_carry_schema"}
	var units: Dictionary = carry.get("units", {})
	if not units.has(unit_id):
		return {"ok": false, "reason": "unknown_member"}
	var entry: Variant = catalog.get(str(item_id))
	if typeof(entry) == TYPE_DICTIONARY and bool((entry as Dictionary).get("important", false)):
		return {"ok": false, "reason": "important_item"}
	var removed := InventoryRules.remove((units[unit_id] as Dictionary).get("inventory", []), slot, item_id)
	if not bool(removed.get("ok", false)):
		return {"ok": false, "reason": str(removed.get("reason", "inventory_selection_changed"))}
	var next := carry.duplicate(true)
	(next["units"][unit_id] as Dictionary)["inventory"] = removed["inventory"]
	var loop: Dictionary = next.get("loop", {})
	var gold := int(loop.get("gold", 0)) + maxi(price, 0)
	loop["gold"] = gold
	next["loop"] = loop
	return {"ok": true, "carry": next, "unit_id": unit_id, "item_id": item_id, "price": maxi(price, 0), "gold": gold}


static func _insert_first_room(carry: Dictionary, code: int) -> String:
	var units: Dictionary = carry.get("units", {})
	for unit_id in units.keys():
		var inserted := InventoryRules.insert((units[unit_id] as Dictionary).get("inventory", []), code)
		if bool(inserted.get("ok", false)):
			(units[unit_id] as Dictionary)["inventory"] = inserted["inventory"]
			return str(unit_id)
	return ""


static func _remove_any(carry: Dictionary, code: int) -> String:
	var units: Dictionary = carry.get("units", {})
	for unit_id in units.keys():
		var inventory: Array = (units[unit_id] as Dictionary).get("inventory", [])
		var index := InventoryRules.find_item(inventory, code)
		if index >= 0:
			var removed := InventoryRules.remove(inventory, index, code)
			if bool(removed.get("ok", false)):
				(units[unit_id] as Dictionary)["inventory"] = removed["inventory"]
				return str(unit_id)
	return ""
