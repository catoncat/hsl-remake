extends RefCounted
## Preview/preflight only: no randomness, inventory payment or turn mutation.
## provenance:
##   rules: static-derived docs/evidence_packets/static_reverse/original_tactical_items.md
##   rules: static-derived docs/evidence_packets/static_reverse/original_item_actions.md
const StatusEffectRules = preload("res://game/sim/StatusEffectRules.gd")
const InventoryRules = preload("res://game/sim/InventoryRules.gd")
const PermanentCapabilityRules = preload("res://game/sim/PermanentCapabilityRules.gd")
const Values = preload("res://game/sim/Values.gd")


static func first_healing_slot(slots: Array, items: Dictionary) -> Dictionary:
	# 0x40c1d0 scans eight slots in order. This catalog contains only registered
	# consumables; unimplemented item types/effects are not enabled by AI.
	if not InventoryRules.valid(slots): return {"ok": false, "reason": "invalid_inventory_slots"}
	var selected := -1
	for index in range(slots.size()):
		var code := str(int(slots[index]))
		if not items.has(code): continue
		if not items[code] is Dictionary: return {"ok": false, "reason": "invalid_item_effect"}
		var error := definition_error(items[code])
		if error != "": return {"ok": false, "reason": error}
		if selected < 0 and int(items[code]["heal_hp"]) > 0: selected = index
	return {"ok": true, "index": selected}


static func definition_error(item: Dictionary) -> String:
	var permanent_error := PermanentCapabilityRules.definition_error(item)
	if permanent_error != "": return permanent_error
	if not Values.is_integer_in(item.get("heal_hp"), 0, 0x7fffffff) or not Values.is_integer_in(item.get("cure_poison"), 0, 1) or not Values.is_integer_in(item.get("cure_paralysis"), 0, 1):
		return "invalid_item_effect"
	if not Values.is_integer_in(item.get("heal_mp", 0), 0, 0x7fffffff): return "invalid_item_effect"
	if not Values.is_integer_in(item.get("restore_stamina", 0), 0, 60) or not Values.is_integer_in(item.get("cure_no_magic", 0), 0, 1) or not Values.is_integer_in(item.get("cure_weaken", 0), 0, 1): return "invalid_item_effect"
	var local := false
	for key in ["local_attack", "local_defense"]:
		var bounds: Variant = item.get(key, [])
		if not bounds is Array: return "invalid_item_effect"
		if bounds.is_empty(): continue
		if bounds.size() != 2 or not Values.is_integer_in(bounds[0], 0, 100) or not Values.is_integer_in(bounds[1], 0, 100) or int(bounds[0]) < 5 or int(bounds[0]) > int(bounds[1]) or int(bounds[1]) > (96 if key == "local_attack" else 100): return "invalid_item_effect"
		local = true
	return "" if not item.get("permanent",{}).is_empty() or local or int(item["heal_hp"]) > 0 or int(item.get("heal_mp", 0)) > 0 or int(item.get("restore_stamina", 0)) > 0 or int(item.get("cure_no_magic", 0)) == 1 or int(item.get("cure_weaken", 0)) == 1 or int(item["cure_poison"]) == 1 or int(item["cure_paralysis"]) == 1 else "unsupported_item_effect"


## Whether a validated item cures one of the set flags (catalog cure_item fields).
static func _cures_any(item: Dictionary, flags: int) -> bool:
	for key in StatusEffectRules.Catalog.ENTRIES:
		var row: Dictionary = StatusEffectRules.Catalog.ENTRIES[key]
		if (flags & int(row["flag"])) != 0 and item.get(row["cure_item"], 0) == 1: return true
	return false


static func first_status_slot(slots: Array, items: Dictionary, flags: int) -> Dictionary:
	# Original0x40c230 scans eight slots, stopping at the first matching cure; the four
	# cure bits are item+0xa0 0x80000000 poison / 0x40000000 no-magic / 0x20000000 paralysis /
	# 0x10000000 weaken against the negative mask 1／2／4／8.
	# Unregistered effects are not silently made usable by this adapter.
	if not InventoryRules.valid(slots): return {"ok": false, "reason": "invalid_inventory_slots"}
	var selected := -1
	for index in range(slots.size()):
		var code := str(int(slots[index]))
		if not items.has(code): continue
		if not items[code] is Dictionary: return {"ok": false, "reason": "invalid_item_effect"}
		var error := definition_error(items[code])
		if error != "": return {"ok": false, "reason": error}
		var item: Dictionary = items[code]
		if selected < 0 and _cures_any(item, flags):
			selected = index
	return {"ok": true, "index": selected}


## `spend`: the player's Use and target preview, script actUseItem and the AI's item pick — the
## original applies an item to a full target too (0x409e40 clamps, 0x444aba clears the held
## code; 0x40c1d0／0x40c230 do not weigh the effect). The default refusal is the AI commit's
## stale-plan guard and planning quotes.
static func prepare(target: Dictionary, item: Dictionary, spend: bool = false) -> Dictionary:
	var error := definition_error(item)
	if error != "":
		return {"ok": false, "reason": error}
	error = StatusEffectRules.input_error(target)
	if error != "":
		return {"ok": false, "reason": error}
	if not Values.is_integer_in(target.get("hp"), 0, 0x7fffffff) or not Values.is_integer_in(target.get("max_hp"), 0, 0x7fffffff) or int(target["hp"]) <= 0 or bool(target.get("defeated", false)) or bool(target.get("departed", false)):
		return {"ok": false, "reason": "item_target_unavailable"}
	var restored := mini(int(item["heal_hp"]), maxi(0, int(target["max_hp"]) - int(target["hp"])))
	var mana := 0
	if int(item.get("heal_mp", 0)) > 0:
		if not Values.is_integer_in(target.get("mp"), 0, 0x7fffffff) or not Values.is_integer_in(target.get("max_mp"), 0, 0x7fffffff) or int(target["mp"])>int(target["max_mp"]):
			return {"ok":false,"reason":"invalid_item_target_mp"}
		mana=mini(int(item["heal_mp"]),int(target["max_mp"])-int(target["mp"]))
	var cured := int(item["cure_poison"]) == 1 and StatusEffectRules.poisoned(target)
	var paralysis_cured := int(item["cure_paralysis"]) == 1 and StatusEffectRules.paralyzed(target)
	var magic_cured := int(item.get("cure_no_magic", 0)) == 1 and StatusEffectRules.magic_blocked(target)
	# 0x40a31f: item+0xa0 bit 0x10000000 clears the +0x38 weaken word and flag 8, then 0x40a337 0x448840
	# refreshes (ItemResolutionRules runs that refresh after the cure).
	var weaken_cured := int(item.get("cure_weaken", 0)) == 1 and StatusEffectRules.weakened(target)
	var stamina := 0
	if int(item.get("restore_stamina", 0)) > 0:
		if not Values.is_integer_in(target.get("stamina"), 0, 60): return {"ok":false,"reason":"invalid_item_target_stamina"}
		stamina = mini(int(item["restore_stamina"]),60-int(target["stamina"]))
	var enhancements: Array = []
	var permanent := PermanentCapabilityRules.prepare(target,item,spend)
	if not permanent["ok"]: return permanent
	for pair in [["local_attack","attack_up"],["local_defense","defense_up"]]:
		var limits: Array = item.get(pair[0],[])
		if limits.is_empty(): continue
		var before := StatusEffectRules.Enhancements.word(target,pair[1])
		if (before & 65535) == 9: continue
		enhancements.append({"kind":pair[1],"before_word":before,"duration":mini(9,(before & 65535)+3),
			"low":int(limits[0]),"high":int(limits[1]),"roll_required":before == 0})
	var useful: bool = restored > 0 or mana > 0 or stamina > 0 or cured or paralysis_cured or magic_cured or weaken_cured or not enhancements.is_empty() or permanent["proposals"].any(func(row): return not (str(row["kind"]).begins_with("resist_") and int(row["before_raw"]) >= 80))
	if not useful and not spend:
		return {"ok": false, "reason": "item_has_no_effect"}
	var changes := {"hp": int(target["hp"]) + restored}
	if mana>0: changes["mp"]=int(target["mp"])+mana
	if stamina>0: changes["stamina"]=int(target["stamina"])+stamina
	if cured:
		changes.merge(StatusEffectRules.cure_poison(target), true)
	if paralysis_cured:
		var current := target.duplicate(true)
		current.merge(changes, true)
		changes.merge(StatusEffectRules.cure_paralysis(current), true)
	if magic_cured:
		var current := target.duplicate(true)
		current.merge(changes, true)
		changes.merge(StatusEffectRules.cure_no_magic(current), true)
	if weaken_cured:
		var current := target.duplicate(true)
		current.merge(changes, true)
		changes.merge(StatusEffectRules.cure_weaken(current), true)
	# 0x409e40 starts 0x4c1a44／0x4c1a48 at -1 and writes the clamped HP／MP gain (0 when full);
	# state108 (0x444ac9) floats every number that is not -1.
	var numbers := {"hp": restored if int(item["heal_hp"]) > 0 else -1, "mp": mana if int(item.get("heal_mp", 0)) > 0 else -1}
	return {"ok": true, "useful": useful, "changes": changes, "restored_hp": restored, "restored_mp": mana, "restored_stamina":stamina, "heal_numbers": numbers,
		"cured_poison": cured, "cured_paralysis": paralysis_cured,"cured_no_magic":magic_cured,"cured_weaken":weaken_cured,"stat_proposals":enhancements,"permanent_proposals":permanent["proposals"]}
