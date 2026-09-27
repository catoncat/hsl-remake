extends RefCounted
## Source ordinary-series aftereffects. No HP/EXP/turn ownership in this module.
## provenance:
##   rules: static-derived docs/evidence_packets/static_reverse/original_weapon_effects.md
const SkillResourceRules = preload("res://game/sim/SkillResourceRules.gd")
const CoreCombatRules = preload("res://game/sim/CoreCombatRules.gd")
const StatusEffectRules = preload("res://game/sim/StatusEffectRules.gd")
const StatusApplicationRules = preload("res://game/sim/StatusApplicationRules.gd")
const CoreTurnQueue = preload("res://game/sim/CoreTurnQueue.gd")
const ProgressionRules = preload("res://game/sim/ProgressionRules.gd")
const Catalog = preload("res://game/sim/StatusCatalog.gd")
const Values = preload("res://game/sim/Values.gd")
## live +0x18c bits the ITEM loader 0x4477c0 ORs from attack_cancel／attack_weaken／random_status_error／
## attack_nomagic／attack_paralysis／attack_poison／attack_decmp (status bits: catalog weapon_bit).
const CANCEL := 0x10000
const WEAKEN: int = Catalog.ENTRIES[Catalog.WEAKEN_KEY]["weapon_bit"]
const RANDOM := 0x40000
const NO_MAGIC: int = Catalog.ENTRIES[Catalog.NO_MAGIC_KEY]["weapon_bit"]
const PARALYSIS: int = Catalog.ENTRIES[Catalog.PARALYSIS_KEY]["weapon_bit"]
const POISON: int = Catalog.ENTRIES[Catalog.POISON_KEY]["weapon_bit"]
const MANA := 0x400000
## 0x409310 visit order with the 0x40e2f0 immunity bit each branch tests (OR 0x80 keep_status_good).
static var STATUS_BRANCHES: Array = _branches()
static var STATUS_WORD: int = _status_word()


static func _branches() -> Array:
	var result := []
	for key in Catalog.WEAPON_ORDER:
		result.append([key, int(Catalog.ENTRIES[key]["weapon_bit"]), int(Catalog.ENTRIES[key]["immunity_bit"])])
	result.make_read_only()
	return result


static func _status_word() -> int:
	var word := 0
	for key in Catalog.WEAPON_ORDER: word |= int(Catalog.ENTRIES[key]["weapon_bit"])
	return word


static func effects(actor: Dictionary, catalog: Dictionary) -> Dictionary:
	if not actor.get("equipment") is Array: return {"ok": false, "reason": "missing_weapon_effect_equipment"}
	var flags := 0
	for slot in actor["equipment"]:
		if not slot is Dictionary or Values.non_negative_int(slot.get("item_code")) <= 0:
			return {"ok": false, "reason": "invalid_weapon_effect_equipment"}
		var item: Variant = catalog.get(str(int(slot["item_code"])))
		if not item is Dictionary or Values.non_negative_int(item.get("weapon_effect_flags")) < 0 or int(item["weapon_effect_flags"]) & ~(CANCEL | RANDOM | STATUS_WORD | MANA):
			return {"ok": false, "reason": "invalid_weapon_effect_source"}
		flags |= int(item["weapon_effect_flags"])
	return {"ok": true, "flags": flags}


static func prepare(attacker: Dictionary, target: Dictionary, book: Dictionary, catalog: Dictionary, queue: Dictionary) -> Dictionary:
	var source := effects(attacker, catalog)
	if not source["ok"]: return source
	var protection := StatusApplicationRules.modifiers(target, book, catalog)
	if not protection["ok"]: return protection
	var error := StatusEffectRules.input_error(target)
	if error != "": return {"ok": false, "reason": error}
	if int(source["flags"]) & MANA and (Values.non_negative_int(target.get("mp")) < 0 or Values.non_negative_int(target.get("max_mp")) < Values.non_negative_int(target.get("mp"))):
		return {"ok": false, "reason": "invalid_weapon_mana_target"}
	error = CoreTurnQueue.cancellation_input_error(queue)
	if error != "": return {"ok": false, "reason": error}
	if int(source["flags"]) & (WEAKEN | RANDOM):
		# 0x409240 ends in 0x448840: the target must be refreshable before any draw.
		error = ProgressionRules.refresh_input_error(target, catalog)
		if error != "": return {"ok": false, "reason": error}
	return {"ok": true, "flags": source["flags"], "protection": protection["effects"],
		"target": target.duplicate(true), "queue": queue.duplicate(true), "catalog": catalog}


## `struck` is the target as it stands after the strike (HP already applied); the 0x409240 weaken
## refresh clamps its vitals to the weakened maxima, so the prepared pre-strike snapshot is not enough.
static func resolve(prepared: Dictionary, rng: Variant, contribution: int = 0, struck: Dictionary = {}) -> Dictionary:
	var target: Dictionary = prepared["target"]
	var queue: Dictionary = prepared["queue"].duplicate(true)
	var changes := {"status_flags": target["status_flags"], "status_counters": target["status_counters"].duplicate(true)}
	var receipt := {"source": "0x4095e0", "scope": "final_ordinary_strike", "flags": prepared["flags"],
		"target_id": target["id"], "draws": [], "cancel": {}, Catalog.POISON_KEY: {}}
	if int(prepared["flags"]) & CANCEL:
		var roll := _draw(100, rng, receipt["draws"]) + 1
		var cancelled := {"ok": true, "queue": queue, "index": -1, "cancelled": false}
		if roll <= 10: cancelled = CoreTurnQueue.cancel_pending(queue, str(target["id"]))
		queue = cancelled["queue"]
		receipt["cancel"] = {"roll": roll, "chance": 10, "triggered": roll <= 10,
			"cancelled": cancelled["cancelled"], "slot_index": cancelled["index"], "round": queue["round"]}
	# 0x409310: the status word is the equipment OR; random_status_error replaces it with one bit
	# from rand(100)+1 (1..24 weaken, 25..49 no-magic, 50..74 paralysis, 75..100 poison).
	var word := int(prepared["flags"]) & STATUS_WORD
	if int(prepared["flags"]) & RANDOM:
		var roll := _draw(100, rng, receipt["draws"]) + 1
		word = WEAKEN if roll < 25 else NO_MAGIC if roll < 50 else PARALYSIS if roll < 75 else POISON
		receipt["random_status"] = {"roll": roll, "selected": _status_key(word)}
	var afflicted := target.duplicate(true)
	var refreshed_keys: Array[String] = []
	for branch in STATUS_BRANCHES:
		var key: String = branch[0]
		if (word & int(branch[1])) == 0: continue
		var immune := (int(prepared["protection"]) & (int(branch[2]) | 0x80)) != 0
		var roll := 0 if immune else _draw(100, rng, receipt["draws"]) + 1
		var before := int(afflicted["status_counters"].get(key, 0))
		receipt[key] = {"immune": immune, "roll": roll, "chance": 25, "applied": false, "before_word": before, "after_word": before}
		if immune or roll > 25: continue
		var duration := 1 + _draw(2, rng, receipt["draws"])
		var power := 0
		if Catalog.ENTRIES[key]["power"]:
			# 0x406fe0(lo, hi): mid − rand(half+1) + rand(half+1); poison (16, 32), weaken (3, 7).
			var domain: Array = Catalog.ENTRIES[key]["weapon_power"]
			var half: int = (int(domain[1]) - int(domain[0])) / 2
			power = int(domain[0]) + half - _draw(half + 1, rng, receipt["draws"]) + _draw(half + 1, rng, receipt["draws"])
		var application := StatusEffectRules.weapon_status(afflicted, key, duration, power)
		afflicted.merge(application["changes"], true)
		changes = application["changes"]
		if Catalog.ENTRIES[key]["refresh"]: refreshed_keys.append(key)
		receipt[key].merge({"applied": true, "added_turns": duration, "sampled_power": power, "after_word": int(application["after_word"])}, true)
	if not refreshed_keys.is_empty():
		# 0x409240 -> 0x448840: derived stats and maxima follow the weakened attributes; the clamp
		# reads the struck target's HP/MP, not the pre-strike snapshot.
		var current := struck.duplicate(true) if not struck.is_empty() else afflicted
		current.merge(changes, true)
		var refreshed := ProgressionRules.refresh_growth_stats(current, prepared["catalog"])
		for key in ["hp", "mp", "max_hp", "max_mp", "combat_profile", "live_speed", "move_point"]:
			changes[key] = refreshed[key]
		for key in refreshed_keys: receipt[key]["refreshed"] = true
	if int(prepared["flags"]) & MANA:
		# 0x409460 runs after 0x409310, so a weaken refresh's MP clamp is the starting value.
		var before := int(changes.get("mp", target["mp"]))
		var after := maxi(0, before - maxi(0, contribution) / 3)
		changes["mp"] = after
		receipt["mana"] = {"before": before, "after": after, "loss": before - after,
			"contribution": contribution, "source": "0x404089_hp_cap_then_0x409460"}
	return {"queue": queue, "changes": changes, "receipt": receipt}


static func feedback(receipt: Dictionary, target_alive: bool = true) -> String:
	if not target_alive: return ""
	var messages: Array[String] = []
	if int(receipt.get("mana", {}).get("loss", 0)) > 0:
		messages.append("魔力 −%d" % int(receipt["mana"]["loss"]))
	if receipt.get("cancel", {}).get("cancelled", false): messages.append("本回合行動取消")
	for branch in STATUS_BRANCHES:
		var key: String = branch[0]
		var label := Catalog.name_of(key)
		var status: Dictionary = receipt.get(key, {})
		if status.get("immune", false): messages.append(label + "免疫")
		elif status.get("applied", false):
			var before := int(status["before_word"])
			var after := int(status["after_word"])
			if before == 0: messages.append(label)
			elif (after & 0xffff) > (before & 0xffff): messages.append(label + "延長")
			elif (after >> 16) > (before >> 16): messages.append(str(Catalog.ENTRIES[key]["stronger_label"]))
			else: messages.append(label + "維持")
	return " · ".join(messages)


static func _status_key(bit: int) -> String:
	for branch in STATUS_BRANCHES:
		if int(branch[1]) == bit: return branch[0]
	return ""


static func _draw(bound: int, rng: Variant, draws: Array) -> int:
	var value := CoreCombatRules.native_draw(bound, rng)
	draws.append({"bound": bound, "value": value})
	return value
