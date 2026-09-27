extends RefCounted
## Original contribution -> per-target EXP (0x40a5d0), not raw damage as EXP.
## The caller accumulates a cast, applies final doubling, then grows once.
## provenance:
##   rules: static-derived docs/evidence_packets/static_reverse/original_experience.md; static-derived docs/evidence_packets/static_reverse/original_skill_function_bits.md
##   layout: n/a
##   strings: n/a
##   timing: n/a
##   audio: n/a
const Number = preload("res://game/sim/SkillResourceRules.gd")
const Combat = preload("res://game/sim/CoreCombatRules.gd")
const Progression = preload("res://game/sim/ProgressionRules.gd")
const KILL_MARK := 0x10000
const MAX_VALUE := 1000000


static func actor_error(actor: Dictionary) -> String:
	for key in ["exp", "level", "kill_exp", "kill_count", "kill_chain_word", "pending_stat_points"]:
		var value := Number._integer(actor.get(key))
		if value < 0 or value > MAX_VALUE or (key == "level" and (value == 0 or value > 1000)):
			return "invalid_experience_" + key
	if int(actor["kill_chain_word"]) > 0x1ffff: return "invalid_experience_kill_chain_word"
	return ""


## The experience gate an action or equipment change checks before it may award EXP.
## `enhancement_checked`: the caller has just found `enhancement_profile_error` empty for
## this actor and equipment table (`BattlePlayLoop._skill_input_error`, after
## `_resource_input_error`), so it is not run again.
static func input_error(loop: Dictionary, actor: Dictionary, enhancement_checked: bool = false) -> String:
	if not enhancement_checked:
		var stat_error := Progression.enhancement_profile_error(actor, loop["equipment_items"])
		if stat_error != "": return stat_error
	var error := actor_error(actor)
	if error != "": return error
	var rate := multiplier(actor, loop["equipment_items"])
	if not rate["ok"]: return rate["reason"]
	# A roster without an implemented growth model retains its computed basis but
	# cannot manufacture level-ups. A present, malformed model must fail closed. An empty
	# enhancement check that read the growth has already found the refresh input empty.
	if not actor.has("growth_profile") or Progression.enhancement_reads_growth(actor): return ""
	return Progression.refresh_input_error(actor, loop["equipment_items"])


static func multiplier(actor: Dictionary, equipment: Dictionary) -> Dictionary:
	if not actor.get("equipment") is Array: return {"ok": false, "reason": "missing_experience_equipment"}
	var double_exp := false
	for slot in actor["equipment"]:
		if not slot is Dictionary or Number._integer(slot.get("item_code")) <= 0:
			return {"ok": false, "reason": "invalid_experience_equipment"}
		var item: Variant = equipment.get(str(int(slot["item_code"])))
		if not item is Dictionary or not item.get("experience_double") is bool:
			return {"ok": false, "reason": "missing_experience_equipment_effect"}
		double_exp = double_exp or item["experience_double"]
	return {"ok": true, "value": 2 if double_exp else 1}


static func from_contribution(contribution: int, attacker_level: int, target_level: int, target_hp: int, kill_exp: int, kill_word: int, rng: Variant) -> Dictionary:
	var draws: Array = []
	if contribution == 0:
		return {"points": 0, "contribution": 0, "draws": draws, "kill_multiplier": 100}
	var reward := kill_exp if target_hp == 0 else 0
	var delta := attacker_level - target_level
	var subtotal := 0
	if delta >= 0:
		var noise := _draw(contribution / 2, rng, draws)
		subtotal = (contribution * 40 / 100 + reward + noise) * 100 / (maxi(1, mini(5, delta)) * 80)
	else:
		subtotal = mini(5, -delta) * contribution + reward
	var reduction := _draw(subtotal * 30 / 100, rng, draws)
	var points := maxi(1, subtotal - reduction)
	var chain := mini(8, kill_word & 0xffff) if target_hp == 0 else 0
	var percent := 100 + chain * 50
	points = points * percent / 100
	return {"points": points, "contribution": contribution, "draws": draws, "kill_multiplier": percent,
		"subtotal": subtotal, "attacker_level": attacker_level, "target_level": target_level,
		"kill_exp": reward, "kill_chain_before": kill_word & 0xffff, "source": "0x40a5d0"}


## `strike.immediate_contributions`: 0x40aa80 HealMP (0x40b49e) / StealItem (0x40b674) / ActiveAgain
## (0x40b6fa) / CancelActive (0x40b770) / StealHP (0x40b7fe) swap the running contribution for one
## value, call 0x40a5d0 at once, then restore the original for the tail call (0x40b866 / 0x40b8b5).
## Both conversions read the same caster level, target level, post-effect target HP and chain word.
static func record(actor: Dictionary, target: Dictionary, strike: Dictionary, rng: Variant, already_killed: bool = false, counter: bool = false) -> Dictionary:
	var contribution := int(strike.get("native_contribution", mini(int(strike["defender_hp_before"]), int(strike["damage"]))))
	var immediate: Array = []
	var immediate_points := 0
	for value in strike.get("immediate_contributions", []):
		var converted := from_contribution(int(value), int(actor["level"]), int(target["level"]), int(strike["defender_hp_after"]), int(target["kill_exp"]), int(actor["kill_chain_word"]), rng)
		immediate.append(converted)
		immediate_points += int(converted["points"])
	var result := from_contribution(contribution, int(actor["level"]), int(target["level"]), int(strike["defender_hp_after"]), int(target["kill_exp"]), int(actor["kill_chain_word"]), rng)
	if not immediate.is_empty():
		result["tail_points"] = int(result["points"])
		result["immediate_experience"] = immediate
		result["points"] = int(result["points"]) + immediate_points
	var killed := int(strike["defender_hp_before"]) > 0 and int(strike["defender_hp_after"]) == 0
	var word := int(actor["kill_chain_word"])
	if killed:
		# Native area handlers count all deaths, but advance the chain only once.
		if not already_killed: word = ((word & 0xffff) + 1) | (0 if counter else KILL_MARK)
	elif counter:
		word = 0 # Native nonlethal counter clears the counterattacker's chain.
	result.merge({"kill_word_after": word, "kills_added": 1 if killed else 0, "killed": killed})
	return result


static func after_action(word: int) -> int:
	return word & 0xffff if word & KILL_MARK else 0


static func _draw(bound: int, rng: Variant, draws: Array) -> int:
	# Original rand(0) returns zero without advancing the stream (0x458c80,
	# original_damage_random.md). Do not turn that into rand(1), nor silently omit the
	# call from callable/native replay evidence.
	var value := 0
	if bound == 0:
		if rng is Callable: rng.call(0)
	else:
		value = Combat._rand_range(bound, rng)
	draws.append({"bound": bound, "value": value})
	return value
