extends RefCounted
## The party storage (倉庫): the original's two growable (code, qty) tables — important items
## at 0x4c1d10 (capacity 0x4c1d14, count 0x4c1d18), the rest at 0x4c1d1c (0x4c1d20／0x4c1d24).
## 0x44f670 starts both at capacity 5, count 0; 0x44ef70／0x44f100 add one code (an existing
## live entry of that code takes the quantity, otherwise it appends and 0x44ee30／0x44ee90 grow
## the table by 5 — no upper bound); 0x44efe0／0x44f170 take one and close the gap at 0. The
## window shows both as one list, important first (0x42aa50); a click with the hand puts the
## held item in (0x44f2d0), an empty-handed click takes one out unless the item is important
## (0x4154cd → 0x40e690). Both tables are in the save (0x44f720／0x44f8a0).
## Stored in the campaign carry as carry.loop.party_storage (CampaignCarryRules loop key), so it
## crosses battles unchanged; a carry without it has an empty storage.
## provenance:
##   rules: static-derived docs/evidence_packets/static_reverse/original_storage_window.md

const SCHEMA := "hsl_party_storage.v1"
const LOOP_KEY := "party_storage"


static func empty() -> Dictionary:
	return {"schema": SCHEMA, "important": [], "normal": []}


static func valid(storage: Variant) -> bool:
	if not storage is Dictionary or storage.get("schema") != SCHEMA:
		return false
	for key in ["important", "normal"]:
		if not storage.get(key) is Array:
			return false
		for entry in storage[key]:
			if not entry is Dictionary or typeof(entry.get("code")) not in [TYPE_INT, TYPE_FLOAT] or typeof(entry.get("qty")) not in [TYPE_INT, TYPE_FLOAT] or int(entry["code"]) <= 0 or int(entry["qty"]) <= 0:
				return false
	return true


## The carry's storage, or an empty one (older carries, or an unreadable field).
static func of_carry(carry: Dictionary) -> Dictionary:
	var stored: Variant = (carry.get("loop", {}) as Dictionary).get(LOOP_KEY) if carry.get("loop") is Dictionary else null
	return (stored as Dictionary).duplicate(true) if valid(stored) else empty()


## The carry with `storage` written into carry.loop (every other field kept).
static func with_carry(carry: Dictionary, storage: Dictionary) -> Dictionary:
	var next := carry.duplicate(true)
	var loop_values: Dictionary = (next.get("loop", {}) as Dictionary) if next.get("loop") is Dictionary else {}
	loop_values[LOOP_KEY] = storage.duplicate(true)
	next["loop"] = loop_values
	return next


## The window's list: important entries, then the rest ([{code, qty}]).
static func entries(storage: Dictionary) -> Array:
	var out: Array = []
	for key in ["important", "normal"]:
		for entry in storage.get(key, []):
			out.append({"code": int(entry["code"]), "qty": int(entry["qty"])})
	return out


static func _important(code: int, catalog: Dictionary) -> bool:
	return bool((catalog.get(str(code), {}) as Dictionary).get("important", false))


## Puts one `code` in (0x44ef70 important／0x44f100 otherwise).
static func put(storage: Dictionary, code: int, catalog: Dictionary) -> Dictionary:
	if code <= 0 or not catalog.has(str(code)):
		return {"ok": false, "reason": "unknown_item", "storage": storage}
	var next := storage.duplicate(true)
	var table: Array = next["important" if _important(code, catalog) else "normal"]
	for entry in table:
		if int(entry["code"]) == code:
			entry["qty"] = int(entry["qty"]) + 1
			return {"ok": true, "storage": next}
	table.append({"code": code, "qty": 1})
	return {"ok": true, "storage": next}


## Takes one item of list row `index` out; important items stay (0x4154cd).
static func take(storage: Dictionary, index: int, catalog: Dictionary) -> Dictionary:
	var rows := entries(storage)
	if index < 0 or index >= rows.size():
		return {"ok": false, "reason": "empty_row", "storage": storage}
	var code := int(rows[index]["code"])
	if _important(code, catalog):
		return {"ok": false, "reason": "important_item", "storage": storage}
	var next := storage.duplicate(true)
	var table: Array = next["normal"]
	var at := index - (next["important"] as Array).size()
	table[at]["qty"] = int(table[at]["qty"]) - 1
	if int(table[at]["qty"]) <= 0:
		table.remove_at(at)
	return {"ok": true, "code": code, "storage": next}
