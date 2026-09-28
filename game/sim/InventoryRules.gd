extends RefCounted
## Original actor +0x138: eight item-code slots. Zero is empty.
## 0x436e30 inserts at the first empty slot; 0x436e80 removes and shifts left.
## provenance:
##   rules: static-derived docs/evidence_packets/static_reverse/original_inventory_equipment.md
##   rules: static-derived docs/evidence_packets/static_reverse/original_item_actions.md

const CAPACITY := 8


static func valid(slots: Variant) -> bool:
	if not slots is Array or slots.size() != CAPACITY:
		return false
	for code in slots:
		if typeof(code) not in [TYPE_INT, TYPE_FLOAT] or code < 0 or code != int(code):
			return false
	return true


static func find_item(slots: Array, code: int, selected_index: int = -1) -> int:
	if not valid(slots) or code <= 0:
		return -1
	if selected_index >= 0:
		return selected_index if selected_index < CAPACITY and int(slots[selected_index]) == code else -1
	if selected_index != -1:
		return -1
	for index in range(CAPACITY):
		if int(slots[index]) == code:
			return index
	return -1


static func insert(slots: Array, code: int) -> Dictionary:
	if not valid(slots) or code <= 0:
		return {"ok": false, "reason": "invalid_inventory"}
	var next: Array = slots.map(func(value): return int(value))
	var index := next.find(0)
	if index < 0:
		return {"ok": false, "reason": "inventory_full"}
	next[index] = code
	return {"ok": true, "inventory": next, "slot": index}


static func remove(slots: Array, index: int, expected_code: int) -> Dictionary:
	if find_item(slots, expected_code, index) < 0 or index < 0:
		return {"ok": false, "reason": "inventory_selection_changed"}
	var next: Array = slots.map(func(value): return int(value))
	next.remove_at(index)
	next.append(0)
	return {"ok": true, "inventory": next, "item_code": expected_code}


## A lifted item put back: 0x436e80 already closed its gap, 0x436e30 puts it in the first empty
## slot — the end of the compacted bag.
static func put_back(slots: Array, index: int, expected_code: int) -> Dictionary:
	var removed := remove(slots, index, expected_code)
	if not removed["ok"]:
		return removed
	return insert(removed["inventory"], expected_code)


## ITEM.important -> item+0xa0 bit 27 -> 0x40e690 -> discard guards.
## This restriction applies to discarding, not ordinary transfer or equipment.
static func discard_error(code: int, catalog: Dictionary) -> String:
	var item: Variant = catalog.get(str(code))
	if not item is Dictionary or not item.get("important") is bool:
		return "missing_item_discard_rule"
	return "important_item" if item["important"] else ""


static func discard(slots: Array, index: int, expected_code: int, catalog: Dictionary) -> Dictionary:
	var error := discard_error(expected_code, catalog)
	if error != "":
		return {"ok": false, "reason": error}
	return remove(slots, index, expected_code)


## Give mode7: take from sender; take the selected receiver item (if occupied);
## first-hole insert incoming; return outgoing receiver item to sender's first hole.
## 0x438cbf..0x438d0c and 0x444def..0x444e36. No stacking or incremental mutation.
static func exchange(sender: Array, index: int, expected_code: int, receiver: Array, target_index: int, expected_return: int) -> Dictionary:
	if not valid(sender) or not valid(receiver):
		return {"ok": false, "reason": "invalid_inventory"}
	if find_item(sender, expected_code, index) < 0 or index < 0:
		return {"ok": false, "reason": "inventory_selection_changed"}
	if target_index == -1 and expected_return == 0:
		target_index = receiver.map(func(code): return int(code)).find(0)
		if target_index < 0:
			return {"ok": false, "reason": "inventory_full"}
	if target_index < 0 or target_index >= CAPACITY or expected_return < 0 or int(receiver[target_index]) != expected_return:
		return {"ok": false, "reason": "target_selection_changed"}
	var sender_next: Array = remove(sender, index, expected_code)["inventory"]
	var receiver_next: Array = receiver.duplicate()
	if expected_return > 0:
		receiver_next = remove(receiver, target_index, expected_return)["inventory"]
	var received := insert(receiver_next, expected_code)
	if not received["ok"]:
		return received
	if expected_return > 0:
		var returned := insert(sender_next, expected_return)
		if not returned["ok"]:
			return returned
		sender_next = returned["inventory"]
	return {"ok": true, "sender": sender_next, "receiver": received["inventory"], "sent": expected_code, "returned": expected_return, "action_used": expected_return != expected_code}
