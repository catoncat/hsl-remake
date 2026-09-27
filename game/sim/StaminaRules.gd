extends RefCounted
## Original 0x40e590. A read-only proposal; PlayLoop alone commits resources.
## Only successful ordinary strikes/counters call this, not magic or specials.
## provenance:
##   rules: static-derived docs/evidence_packets/static_reverse/original_stamina.md; runtime-measured docs/evidence_packets/static_reverse/original_stamina.md (opening ST: ActorInitializationRules, CampaignCarryRules)
##   layout: n/a
##   strings: n/a
##   timing: n/a
##   audio: n/a
const Resources = preload("res://game/sim/SkillResourceRules.gd")
const CAP := 60
const DOUBLE := 0x40
const BLOCK := 0x400


static func effects(unit: Dictionary, catalog: Dictionary) -> Dictionary:
	if not unit.get("equipment") is Array: return {"ok": false, "reason": "missing_stamina_equipment"}
	var flags := 0
	for entry in unit["equipment"]:
		if not entry is Dictionary or Resources._integer(entry.get("item_code")) <= 0:
			return {"ok": false, "reason": "invalid_stamina_equipment"}
		var item: Variant = catalog.get(str(int(entry["item_code"])))
		if not item is Dictionary: return {"ok": false, "reason": "missing_stamina_equipment_effect"}
		var value := Resources._integer(item.get("stamina_effect_flags"))
		if value < 0 or (value & ~(DOUBLE | BLOCK)) != 0:
			return {"ok": false, "reason": "invalid_stamina_equipment_effect"}
		flags |= value # Same predicate bit; two pieces never multiply the multiplier.
	return {"ok": true, "flags": flags}


static func input_error(unit: Dictionary, catalog: Dictionary) -> String:
	var stamina := Resources._integer(unit.get("stamina"))
	if stamina < 0 or stamina > CAP: return "invalid_stamina"
	if Resources._integer(unit.get("level")) <= 0: return "invalid_stamina_level"
	if Resources._integer(unit.get("max_hp")) <= 0: return "invalid_stamina_max_hp"
	var equipment := effects(unit, catalog)
	return "" if equipment["ok"] else equipment["reason"]


static func equipment_caption(unit: Dictionary, catalog: Dictionary) -> String:
	var result := effects(unit, catalog)
	if not result["ok"]: return "資料異常"
	return "停止" if result["flags"] & BLOCK else "加倍" if result["flags"] & DOUBLE else "正常"


static func amounts(max_hp: int, hp_after: int, damage: int, attacker_level: int, defender_level: int,
		attacker_st: int, defender_st: int, attacker_flags: int, defender_flags: int) -> Dictionary:
	var effective_hp := maxi(10, max_hp)
	var heavy := mini(damage, effective_hp) >= effective_hp / 2
	var defeated := hp_after <= 0
	var overleveled := attacker_level - defender_level > 3
	var base := (4 if heavy else 3) + int(defeated) - int(overleveled)
	return {"base_gain": base, "heavy_hit": heavy, "defeated": defeated, "level_penalty": overleveled,
		"attacker": _change(attacker_st, base, attacker_flags),
		"defender": _change(defender_st, base * 2, defender_flags),
		"source_address": "0x40e590"}


static func prepare(attacker: Dictionary, defender: Dictionary, damage: int, hp_after: int, catalog: Dictionary) -> Dictionary:
	for unit in [attacker, defender]:
		var error := input_error(unit, catalog)
		if error != "": return {"ok": false, "reason": error}
	if damage < 0 or hp_after < 0:
		return {"ok": false, "reason": "invalid_stamina_strike"}
	var proposal := amounts(int(defender["max_hp"]), hp_after, damage, int(attacker["level"]), int(defender["level"]),
		int(attacker["stamina"]), int(defender["stamina"]), int(effects(attacker, catalog)["flags"]), int(effects(defender, catalog)["flags"]))
	proposal["ok"] = true
	proposal["attacker"]["unit_id"] = attacker["id"]
	proposal["defender"]["unit_id"] = defender["id"]
	return proposal


static func _change(before: int, gain: int, flags: int) -> Dictionary:
	var doubled := (flags & DOUBLE) != 0
	var blocked := (flags & BLOCK) != 0
	var after := before if blocked else mini(CAP, before + gain * (2 if doubled else 1))
	return {"before": before, "after": after, "delta": after - before, "doubled": doubled, "blocked": blocked}
