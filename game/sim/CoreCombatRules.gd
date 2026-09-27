extends RefCounted
## Evidence-gated combat formulas recovered from hsl01.exe.
## Source packet: content/generated/hsl/static/hsl01/core_logic.json
## Docs: docs/first_battle_core_logic_evidence.md
##
## This module is replaceable. Do not scatter formula constants into UI code.
## Field naming resolved: +0x4c=str, +0x50=dex (joined via stat_refresh 0x448840).
## provenance:
##   rules: static-derived content/generated/hsl/static/hsl01/core_logic.json
##   rules: static-derived docs/first_battle_core_logic_evidence.md
##   rules: static-derived docs/evidence_packets/static_reverse/original_ordinary_special.md

const PACKET_PATH := "res://content/generated/hsl/static/hsl01/core_logic.json"
const EVIDENCE_DOC := "docs/first_battle_core_logic_evidence.md" # repository document, never loaded at runtime
const HIT_ADDR := "0x409a60"
const DAMAGE_ADDR := "0x409be0"
const SkillResourceRules = preload("res://game/sim/SkillResourceRules.gd")
const StatusEffectRules = preload("res://game/sim/StatusEffectRules.gd")
const EQUIP_ADDR := "0x448420"
const RESOLVE_ADDR := "0x4423c0"
const REFRESH_ADDR := "0x448840"


static func receipt_vitals(unit: Dictionary) -> Dictionary:
	# Immutable pre-impact display data, not another mutable unit. In particular,
	# an earned level must not leak its new maxima into an earlier combat shot.
	var result := {}
	for key in ["hp", "max_hp", "mp", "max_mp", "stamina", "level", "exp", "status_flags", "status_counters", "combat_profile"]:
		if unit.has(key): result[key] = unit[key]
	return result.duplicate(true)

## Deterministic RNG stand-in for headless tests / previews.
## Pass a Callable(n)->int returning [0, n) to mirror fcn.0042c780.
static func _rand_range(n: int, rng: Variant = null) -> int:
	if n <= 0:
		return 0
	if rng is Callable:
		return clampi(int(rng.call(n)), 0, n - 1)
	if rng is RandomNumberGenerator:
		return int((rng as RandomNumberGenerator).randi_range(0, n - 1))
	# Stable fallback for pure preview without seeded RNG.
	return n / 2


## Native numeric helpers also call rand(0): 0x458c80 returns 0 without advancing the
## stream (original_damage_random.md), yet the call stays visible to callable replays.
## -1 requests the original raw draw used by the rare damage-floor branch.
## The null source is only the deterministic preview; live calls supply an RNG.
static func native_draw(n: int, rng: Variant) -> int:
	if n > 0: return _rand_range(n, rng)
	var raw := 0
	if rng is Callable: raw = int(rng.call(n))
	elif rng is RandomNumberGenerator and n < 0: raw = int(rng.randi())
	return raw & 0xffffffff if n < 0 else 0


static func input_error(unit: Dictionary) -> String:
	var profile: Variant = unit.get("combat_profile")
	if not profile is Dictionary: return "missing_physical_profile"
	for key in ["live_attack_damage", "live_defense", "live_hit_ratio", "avoid_hit_ratio", "attack_back", "attack_damagex2", "str", "dex"]:
		var value := SkillResourceRules._integer(profile.get(key))
		if value < 0 or value > 1000000: return "invalid_physical_" + key
	var element: Variant = profile.get("weapon_magic_attack_type")
	if typeof(element) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(element)) or element != int(element) or int(element) < -1 or int(element) > 5:
		return "invalid_physical_weapon_element"
	for key in ["weapon_damage_variance_lo", "weapon_damage_variance_hi"]:
		var value := SkillResourceRules._integer(profile.get(key))
		if value < 0 or value > 10000: return "invalid_physical_" + key
	var resists: Variant = profile.get("resist_by_type")
	if not resists is Dictionary: return "missing_physical_resists"
	for index in range(5):
		if SkillResourceRules._integer(resists.get(str(index))) < 0 or int(resists[str(index)]) > 80: return "invalid_physical_resist"
	return ""


static func packet_summary() -> Dictionary:
	return {
		"schema": "hsl_core_combat_rules_surface.v1",
		"packet_path": PACKET_PATH,
		"evidence_doc": EVIDENCE_DOC,
		"hit_function": HIT_ADDR,
		"damage_function": DAMAGE_ADDR,
		"equip_function": EQUIP_ADDR,
		"resolve_function": RESOLVE_ADDR,
		"stat_refresh_function": REFRESH_ADDR,
		"resolved_fields": {
			"str": "0x4c",
			"dex": "0x50",
			"mind": "0x54",
			"con": "0x58",
		},
		"unresolved_semantics": [
			"Whole native actor/weapon initialization and display clock remain separate from numeric helpers",
			"Full actor initial ST and whole exchange RNG; gain helper is in StaminaRules",
			"BCMD post-select handlers; see CoreTurnQueue for queue/menu surface",
		],
		"related_surfaces": {
			"turn_queue": "res://game/sim/CoreTurnQueue.gd",
		},
	}


## Build a combat profile from mixed fixture/table fields without claiming full actor init.
static func combat_profile_from_unit(unit: Dictionary) -> Dictionary:
	var stats: Dictionary = unit.get("stats", {})
	var combat: Dictionary = unit.get("combat_profile", {})
	var level := int(unit.get("level", combat.get("level", 1)))
	var live_attack := int(combat.get("live_attack_damage", combat.get("attack_damage", stats.get("str", 0))))
	var live_hit := int(combat.get("live_hit_ratio", combat.get("hit_ratio", 80)))
	var live_def := int(combat.get("live_defense", combat.get("defense", stats.get("vit", 0))))
	var avoid := int(combat.get("avoid_hit_ratio", 0))
	# 0x409a60 (+0x50 dex delta) and 0x409be0 (+0x4c str delta) read the live attributes that
	# 0x448840 derives: base minus an active 衰弱 power (floor 1), never the base +0x64.. words.
	var live: Dictionary = StatusEffectRules.weakened_attributes(unit) if combat.has_all(["str", "dex", "mind", "con"]) else combat
	var str_val := int(live.get("str", stats.get("str", level)))
	var dex_val := int(live.get("dex", stats.get("dex", level)))
	var mind_val := int(live.get("mind", stats.get("mind", 0)))
	var con_val := int(live.get("con", stats.get("con", stats.get("vit", 0))))
	return {
		"live_attack_damage": live_attack,
		"live_hit_ratio": live_hit,
		"live_defense": live_def,
		"avoid_hit_ratio": avoid,
		"attack_back": int(combat.get("attack_back", 0)),
		"attack_damagex2": int(combat.get("attack_damagex2", 0)),
		"str": str_val,
		"dex": dex_val,
		"mind": mind_val,
		"con": con_val,
		"live_magic_attack": int(combat.get("live_magic_attack", combat.get("magic_attack", 0))),
		"weapon_damage_variance_lo": int(combat.get("weapon_damage_variance_lo", -1)),
		"weapon_damage_variance_hi": int(combat.get("weapon_damage_variance_hi", -1)),
		"weapon_magic_attack_type": int(combat.get("weapon_magic_attack_type", -1)),
		"resist_by_type": combat.get("resist_by_type", {}),
	}


## Hit chance: 0x409a60
static func hit_chance(attacker_profile: Dictionary, defender_profile: Dictionary) -> Dictionary:
	var dex_delta := int((int(attacker_profile.get("dex", 1)) - int(defender_profile.get("dex", 1))) / 2)
	dex_delta = clampi(dex_delta, -30, 30)
	var raw := int(attacker_profile.get("live_hit_ratio", 0)) + dex_delta
	raw = clampi(raw, 20, 100)
	var chance := raw - int(defender_profile.get("avoid_hit_ratio", 0))
	chance = maxi(chance, 10)
	return {
		"schema": "hsl_core_hit_chance.v1",
		"hit_chance": chance,
		"raw_before_avoid": raw,
		"dex_delta": dex_delta,
		"source_address": HIT_ADDR,
		"confidence": "high",
		"resolved_field": "dex (0x50) via stat_refresh 0x448840",
	}


static func _banded_weak_bonus(base: int) -> int:
	if base <= 2:
		return 7
	if base <= 6:
		return 8
	return 9


## Element/variance bonus: full 0x409af0 returns, including equal/reversed bounds.
static func variance_bonus(attacker_profile: Dictionary, defender_profile: Dictionary, rng: Variant = null) -> int:
	var magic_type := int(attacker_profile.get("weapon_magic_attack_type", -1))
	if magic_type == -1: return 0
	var lo := int(attacker_profile.get("weapon_damage_variance_lo", -1))
	var hi := int(attacker_profile.get("weapon_damage_variance_hi", -1))
	var roll := lo + native_draw(absi(hi - lo), rng)
	if roll == 0:
		roll = 1
	var half := native_draw(roll / 2, rng)
	var value := half + roll
	if value < 3:
		value = ((5 - value) / 3) * 3 + value
	var resists: Dictionary = defender_profile.get("resist_by_type", {})
	if magic_type in range(5):
		var resist := int(resists.get(str(magic_type), resists.get(magic_type, 0)))
		resist = mini(resist, 80)
		value = int(((100 - resist) * value) / 100)
	return value


## Damage: full 0x409be0 returns; positive-domain branches and RNG order verified.
static func preview_damage(attacker_profile: Dictionary, defender_profile: Dictionary, rng: Variant = null) -> Dictionary:
	var base := int(attacker_profile.get("live_attack_damage", 0)) - int(defender_profile.get("live_defense", 0))
	var str_term := int((int(attacker_profile.get("str", 1)) - int(defender_profile.get("str", 1))) / 2)
	str_term = clampi(str_term, -20, 30)
	var effective := 0
	var path := "normal"
	if base <= 0:
		effective = _rand_range(5, rng) + 3
		path = "base_non_positive_floor"
		if str_term < 0:
			str_term = 0
	elif base < 10:
		effective = _rand_range(base + 4, rng) + _banded_weak_bonus(base)
		path = "base_weak_band"
		if str_term < 0:
			str_term = 0
	else:
		effective = base
		path = "base_normal"
		if str_term < 0:
			str_term = maxi(str_term, -int(effective / 2))

	var abs_str := absi(str_term)
	var noise_a := native_draw((effective * 30) / 100, rng)
	var noise_b := native_draw(abs_str / 2, rng)
	var noise_c := native_draw(abs_str / 2, rng)
	# Recovered polarity: damage ~= effective + str_term - noise_a - noise_b + noise_c
	# with str_term already clamped for negative weak cases.
	var damage := effective + str_term - noise_a - noise_b + noise_c
	var used_fallback := false
	if damage <= 0:
		used_fallback = true
		damage = damage_floor(rng)

	var bonus := variance_bonus(attacker_profile, defender_profile, rng)
	damage += bonus
	return {
		"schema": "hsl_core_damage_preview.v1",
		"damage": maxi(damage, 1),
		"base_attack_minus_defense": base,
		"effective_before_noise": effective,
		"str_term": str_term,
		"noise": {"a": noise_a, "b": noise_b, "c": noise_c},
		"variance_bonus": bonus,
		"path": path,
		"used_nonpositive_fallback": used_fallback,
		"source_address": DAMAGE_ADDR,
		"confidence": "native_numeric_returns",
		"resolved_field": "str (0x4c) via stat_refresh 0x448840",
		"unresolved_semantics": [
			"Positive-domain scalar inputs; original full actor initialization and global RNG state are separate",
		],
	}


static func preview_attack(attacker: Dictionary, defender: Dictionary, rng: Variant = null) -> Dictionary:
	var atk := combat_profile_from_unit(attacker)
	var dfn := combat_profile_from_unit(defender)
	var hit := hit_chance(atk, dfn)
	var dmg := preview_damage(atk, dfn, rng)
	return {
		"schema": "hsl_core_attack_preview.v1",
		"damage": int(dmg.get("damage", 1)),
		"hit_rate": int(hit.get("hit_chance", 10)),
		"would_kill": int(dmg.get("damage", 1)) >= int(defender.get("hp", 0)),
		"hit": hit,
		"damage_detail": dmg,
		"packet": packet_summary(),
		"formula_source": "core_logic_packet",
	}


## Pure accuracy shared by target inspection and actual strikes; consumes no randomness.
static func attack_accuracy(attacker: Dictionary, defender: Dictionary) -> Dictionary:
	var base := int(hit_chance(combat_profile_from_unit(attacker), combat_profile_from_unit(defender))["hit_chance"])
	return {"base_hit_rate": base, "hit_rate": mini(100, base + int(attacker.get("hit_bonus_accum", 0)))}


## Damage -> saved hit roll -> critical impact. EXP and main/counter series are composed
## by PlayLoop. queued_damage remains the original stamina input even on a critical.
static func resolve_attack(attacker: Dictionary, defender: Dictionary, rng: Variant = null, is_counter: bool = false) -> Dictionary:
	var source: Variant = rng
	if source == null:
		var live_rng := RandomNumberGenerator.new()
		live_rng.randomize()
		source = live_rng
	var atk := combat_profile_from_unit(attacker)
	var dfn := combat_profile_from_unit(defender)
	var accuracy := attack_accuracy(attacker, defender)
	var base_rate := int(accuracy["base_hit_rate"])
	var bonus := int(attacker.get("hit_bonus_accum", 0))
	var rate := int(accuracy["hit_rate"])
	var damage_detail := preview_damage(atk, dfn, source)
	var sampled_damage := int(damage_detail["damage"])
	if is_counter:
		sampled_damage = maxi(1, sampled_damage * 80 / 100)
	var roll := _rand_range(100, source)
	var hit := roll < rate
	var impact := critical_impact(sampled_damage, hit, int(atk["attack_damagex2"]), source)
	var damage := int(impact["damage"]) if hit else 0
	return {
		"hit": hit,
		"hit_rate": rate,
		"base_hit_rate": base_rate,
		"is_counter": is_counter,
		"hit_bonus_after": 0 if damage > 0 and int(defender.get("hp", 0)) > 0 else bonus + base_rate / 10,
		"hit_roll": roll,
		"damage": damage,
		"actual_damage": mini(damage, int(defender.get("hp", 0))),
		"native_contribution": mini(damage, int(defender.get("hp", 0))),
		"queued_damage": sampled_damage,
		"damage_detail": damage_detail,
		"critical": impact["critical"], "critical_rate": atk["attack_damagex2"], "critical_roll": impact["roll"],
		"defender_hp_after": maxi(0, int(defender.get("hp", 0)) - damage),
		"formula_source": "core_logic",
		"unresolved_semantics": ["whole exchange/global RNG and actor initialization; unsupported passive/extra-action effects"],
	}


static func critical_impact(queued_damage: int, hit: bool, chance: int, rng: Variant) -> Dictionary:
	var damage := queued_damage
	var roll := native_draw(100, rng) + 1 if hit else 0
	var critical := hit and roll <= chance
	if critical:
		while damage < 6: damage += 2 + native_draw(5, rng)
		var lower := damage * 150 / 100
		damage = mini(32767, lower + native_draw(absi(damage * 2 - lower), rng) + 1)
	return {"damage": damage, "critical": critical, "roll": roll}


static func damage_floor(rng: Variant) -> int:
	var value := native_draw(-1, rng) & 15
	if value > 10: value -= 10 * ((value - 1) / 10)
	if value < 3: value += 3 * ((5 - value) / 3)
	return value


## Counter gate used by resolve phase 0 (0x4423c0).
static func attack_back_triggered(defender_profile: Dictionary, rng: Variant = null) -> Dictionary:
	var chance := int(defender_profile.get("attack_back", 0))
	var roll := _rand_range(100, rng) + 1
	return {
		"schema": "hsl_core_attack_back_gate.v1",
		"chance": chance,
		"roll": roll,
		"triggered": roll <= chance,
		"source_address": RESOLVE_ADDR,
		"unresolved_semantics": [
			"counter presentation / eligibility flags need one more call-site pass",
		],
	}
