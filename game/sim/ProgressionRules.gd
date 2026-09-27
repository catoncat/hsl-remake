extends RefCounted
## Shared initialization/equipment/growth refresh for the six proved source jobs.
## Manual player points, live automatic NPCs and inert templates stay distinct.
## provenance:
##   rules: static-derived docs/evidence_packets/static_reverse/original_growth_refresh.md
##   rules: static-derived docs/evidence_packets/static_reverse/original_job_stats.md
##   rules: static-derived docs/evidence_packets/static_reverse/original_experience.md
##   rules: remake-invented
##     (a multi-level award settles into one pending pool reserving the capacity left, split one window per level by
##     BattleGrowthPanel; the original counts each as it opens)
##   strings: remake-invented (GROWTH_CHOICES attribute names and effect prose shown by the growth panel)

const POINTS_PER_LEVEL := 5
const EquipmentRules = preload("res://game/sim/EquipmentRules.gd")
const MobilityRules = preload("res://game/sim/MobilityRules.gd")
const JobStats = preload("res://game/sim/JobStatsRules.gd")
const StatEnhancementRules = preload("res://game/sim/StatEnhancementRules.gd")
const Permanent = preload("res://game/sim/PermanentCapabilityRules.gd")
const EntryGrowthRules = preload("res://game/sim/EntryGrowthRules.gd")
const Learning = preload("res://game/sim/LearningRules.gd")
const StatusEffectRules = preload("res://game/sim/StatusEffectRules.gd")
const ActorRoleRules = preload("res://game/sim/ActorRoleRules.gd")
const Values = preload("res://game/sim/Values.gd")
const GROWTH_CHOICES := {
	"str": {"name": "力量", "effect": "基礎力量 +1；確認後按職業公式刷新派生數值"},
	"dex": {"name": "反應", "effect": "基礎反應 +1；確認後按職業公式刷新派生數值"},
	"mind": {"name": "精神", "effect": "基礎精神 +1；確認後按職業公式刷新派生數值"},
	"con": {"name": "體質", "effect": "基礎體質 +1；確認後按職業公式刷新派生數值"},
}


# Receives a final awarded amount. Contribution/level/kill conversion and equipment
# doubling belong to ExperienceRules and the single PlayLoop settlement seam.
static func resolve_experience(unit: Dictionary, amount: int, equipment_items: Dictionary) -> Dictionary:
	var next := unit.duplicate(true)
	if amount <= 0 or refresh_input_error(unit, equipment_items) != "" or growth_capacity(unit) <= int(unit.get("pending_stat_points", 0)):
		return next
	next["exp"] = int(next["exp"]) + amount
	return apply_level_ups(next, equipment_items)


static func apply_level_ups(unit: Dictionary, equipment_items: Dictionary) -> Dictionary:
	var next := unit.duplicate(true)
	if refresh_input_error(unit, equipment_items) != "":
		return next
	while int(next["exp"]) >= exp_to_next(int(next["level"])) and growth_capacity(next) > int(next.get("pending_stat_points", 0)):
		if next["growth_profile"]["allocation"] == "automatic":
			var attrs := {}
			for key in GROWTH_CHOICES: attrs[key] = int(next["combat_profile"][key])
			var allocated := EntryGrowthRules.allocate(attrs, int(next["level"]), int(next["exp"]), exp_to_next(int(next["level"])), next["growth_profile"]["caps"], int(next["growth_profile"]["job_code"]), POINTS_PER_LEVEL)
			for key in GROWTH_CHOICES: next["combat_profile"][key] = allocated["attributes"][key]
			next["level"] = allocated["level"]
			next["exp"] = allocated["exp"]
			next = refresh_growth_stats(next, equipment_items)
			continue
		next["exp"] -= exp_to_next(int(next["level"]))
		next["level"] += 1
		next = refresh_growth_stats(next, equipment_items)
		var available := maxi(0, growth_capacity(next) - int(next.get("pending_stat_points", 0)))
		next["pending_stat_points"] = int(next.get("pending_stat_points", 0)) + mini(POINTS_PER_LEVEL, available)
	return next


static func allocation_cost(allocation: Dictionary) -> int:
	var cost := 0
	for key in allocation:
		if not GROWTH_CHOICES.has(key) or typeof(allocation[key]) != TYPE_INT or int(allocation[key]) < 0:
			return -1
		cost += int(allocation[key])
		if cost < 0 or cost > 1000000:
			return -1
	return cost


static func apply_allocation(unit: Dictionary, allocation: Dictionary, equipment_items: Dictionary) -> Dictionary:
	var next := unit.duplicate(true)
	var cost := allocation_cost(allocation)
	if cost <= 0 or refresh_input_error(unit, equipment_items) != "" or not can_allocate(unit, allocation) or int(unit.get("hp", 0)) <= 0 or bool(unit.get("defeated", false)):
		return next
	var profile: Dictionary = next["combat_profile"]
	for key in GROWTH_CHOICES:
		profile[key] = int(profile.get(key, 0)) + int(allocation.get(key, 0))
	next["pending_stat_points"] -= cost
	return refresh_growth_stats(next, equipment_items)


static func can_allocate(unit: Dictionary, allocation: Dictionary) -> bool:
	var cost := allocation_cost(allocation)
	if cost < 0 or cost > int(unit.get("pending_stat_points", 0)):
		return false
	var growth: Dictionary = unit.get("growth_profile", {})
	if not JobStats.supported(growth) or growth.get("allocation") != "manual":
		return false
	var caps: Dictionary = growth.get("caps", {})
	var profile: Dictionary = unit.get("combat_profile", {})
	for key in GROWTH_CHOICES:
		if not caps.has(key) or not profile.has(key):
			return false
		if int(profile[key]) + int(allocation.get(key, 0)) > int(caps[key]):
			return false
	return true


static func growth_capacity(unit: Dictionary) -> int:
	var growth: Dictionary = unit.get("growth_profile", {})
	var caps: Dictionary = growth.get("caps", {})
	var profile: Dictionary = unit.get("combat_profile", {})
	if not JobStats.supported(growth) or growth.get("allocation") not in ["manual", "automatic"]:
		return 0
	var remaining := 0
	for key in GROWTH_CHOICES:
		if not caps.has(key) or not profile.has(key):
			return 0
		remaining += int(caps[key]) - int(profile[key])
	return maxi(0, remaining)


## Check the entire refresh input before callers spend points or exchange items.
static func refresh_input_error(unit: Dictionary, equipment_items: Dictionary) -> String:
	var learning_error := Learning.basic_error(unit)
	if learning_error != "": return learning_error
	var entry_error := EntryGrowthRules.input_error(unit)
	if entry_error != "": return entry_error
	var enhancement_error := StatEnhancementRules.input_error(unit)
	if enhancement_error != "": return enhancement_error
	var mobility := MobilityRules.prepare(unit, equipment_items)
	if not mobility["ok"]: return mobility["reason"]
	if not unit.get("growth_profile") is Dictionary:
		return "missing_growth_profile"
	var growth: Dictionary = unit["growth_profile"]
	if not JobStats.supported(growth) or growth.get("allocation") not in ["manual", "automatic", "fixed_template"]:
		return "unsupported_growth_model"
	if not growth.get("source") is Dictionary or not growth.get("caps") is Dictionary:
		return "missing_growth_source"
	var source: Dictionary = growth["source"]
	if not Values.is_integer(source.get("mode")) or source["mode"] < 0 or source["mode"] > 0x7fffffff:
		return "invalid_growth_source_mode"
	for key in ["attack_power", "magic_attack_power", "defense", "speed", "hit_point", "magic_point", "avoid_hit_ratio", "attack_back", "attack_damagex2"]:
		if not Values.is_integer(source.get(key)):
			return "invalid_growth_source_" + key
	if not source.get("has_magic") is bool or not source.get("base_resist_by_type") is Dictionary:
		return "invalid_growth_source_resists_or_magic"
	for index in range(5):
		if not Values.is_integer(source["base_resist_by_type"].get(str(index))):
			return "missing_growth_source_resist"
	var permanent_error := Permanent.input_error(unit)
	if permanent_error != "": return permanent_error
	if not unit.get("combat_profile") is Dictionary:
		return "missing_growth_attributes"
	for key in GROWTH_CHOICES:
		if not Values.is_integer(unit["combat_profile"].get(key)) or int(unit["combat_profile"][key]) <= 0 or not Values.is_integer(growth["caps"].get(key)):
			return "invalid_growth_attribute_" + key
	# PLAYERS steal_ratio word (+0x194); 0 means the 0x448840 default 12. Summed by the job-up merge like the other source words.
	if not Values.is_integer(unit["combat_profile"].get("base_steal_ratio")) or int(unit["combat_profile"]["base_steal_ratio"]) < 0:
		return "invalid_growth_attribute_base_steal_ratio"
	for key in ["hp", "mp", "level"]:
		if not Values.is_integer(unit.get(key)) or int(unit[key]) < (1 if key == "level" else 0):
			return "invalid_growth_vital_" + key
	if not unit.get("equipment") is Array or equipment_items.is_empty():
		return "missing_equipment_input"
	var effects := EquipmentRules.effect_delta(unit["equipment"], equipment_items)
	return "" if effects["ok"] else str(effects["reason"])


## True when `enhancement_profile_error` compares the unit against a growth refresh (an
## active enhancement, an acquired permanent gain or an entry growth); it has then already
## found `refresh_input_error` empty for this unit whenever it returns "".
static func enhancement_reads_growth(unit: Dictionary) -> bool:
	return (int(unit.get("status_flags", 0)) & 0x78) != 0 or Permanent.active(unit) or unit.has("entry_growth")


static func enhancement_profile_error(unit: Dictionary, equipment_items: Dictionary) -> String:
	var permanent_error := Permanent.input_error(unit)
	if permanent_error != "": return permanent_error
	var acquired := Permanent.active(unit)
	if not enhancement_reads_growth(unit): return ""
	var error := refresh_input_error(unit, equipment_items)
	if error != "": return error
	var refreshed := refreshed_growth_stats(unit, equipment_items)
	for key in ["live_attack_damage", "live_defense"]:
		if unit["combat_profile"].get(key) != refreshed["combat_profile"][key]: return "inconsistent_enhanced_" + key
	if (int(unit.get("status_flags", 0)) & 0x40) != 0 and unit["combat_profile"].get("resist_by_type") != refreshed["combat_profile"]["resist_by_type"]: return "inconsistent_enhanced_resist_by_type"
	if acquired or unit.has("entry_growth"):
		for key in ["live_magic_attack","resist_by_type"]:
			if unit["combat_profile"].get(key) != refreshed["combat_profile"][key]: return "inconsistent_permanent_" + key
		if unit.get("live_speed") != refreshed["live_speed"]: return "inconsistent_permanent_speed"
	return ""


static func refresh_growth_stats(unit: Dictionary, equipment_items: Dictionary) -> Dictionary:
	var error := refresh_input_error(unit, equipment_items)
	if error != "":
		push_error("Cannot refresh growth: " + error)
		return unit.duplicate(true)
	return refreshed_growth_stats(unit, equipment_items)


## `refresh_growth_stats` for a unit whose `refresh_input_error` the caller has just found
## empty (`enhancement_profile_error`, the hot per-action check, would otherwise run it twice).
static func refreshed_growth_stats(unit: Dictionary, equipment_items: Dictionary) -> Dictionary:
	var next := unit.duplicate(true)
	var effective := EntryGrowthRules.effective_profile(next, Permanent.effective_profile(next))
	# Campaign JSON represents numbers as floats. Normalize only after the full
	# input check, so fractional or out-of-domain gains still fail without change.
	for key in Permanent.KEYS: next["permanent_gains"][key] = int(next["permanent_gains"][key])
	for acquisition in next.get("learned_skills", []):
		acquisition["job"] = int(acquisition["job"])
		acquisition["level"] = int(acquisition["level"])
		for key in Learning.ATTRIBUTES: acquisition["attributes"][key] = int(acquisition["attributes"][key])
	var source: Dictionary = effective["source"]
	source["has_magic"] = source["has_magic"] or Learning.has_magic(next)
	var equipment := EquipmentRules.effect_delta(next["equipment"], equipment_items)
	var delta: Dictionary = equipment["delta"]
	var profile: Dictionary = next["combat_profile"]
	var level := int(next["level"])
	# 0x448840 subtracts an active 衰弱 power from the live attributes first; its hp_level
	# term reads the live +0x28 side (installed player_mode, else the role-implied side).
	var base := JobStats.base_values(effective, StatusEffectRules.weakened_attributes(next), level, ActorRoleRules.side_mask(next))
	var max_hp := int(base["max_hp"]) + int(delta["max_hp"])
	var max_mp := int(base["max_mp"]) + int(delta["max_mp"])
	if not source["has_magic"]:
		max_mp = 0
	var attack := int(base["attack"]) + int(delta["attack"]) + StatEnhancementRules.power(unit, "attack_up")
	var defense := int(base["defense"]) + int(delta["defense"]) + StatEnhancementRules.power(unit, "defense_up")
	var magic_attack := int(base["magic_attack"]) + int(delta["magic_attack"])
	var speed := int(base["speed"]) + int(delta["speed"])
	var base_resists: Dictionary = source["base_resist_by_type"]
	var equip_resists: Dictionary = delta["resist_by_type"]
	var bonuses: Array = base["resist_bonuses"]
	var resists := {}
	# 0x448903: an active 魔障壁 (flag 0x40) adds its +0x4a strength to all five resistances, cap 80.
	var resist_up := StatEnhancementRules.power(unit, "resist_up")
	for index in range(5):
		var key := str(index)
		resists[key] = clampi(int(base_resists[key]) + int(bonuses[index]) + int(equip_resists[key]) + resist_up, 0, 80)
	profile["live_attack_damage"] = maxi(0, attack)
	profile["live_defense"] = maxi(0, defense)
	profile["live_hit_ratio"] = int(delta["hit_rate"])
	profile["avoid_hit_ratio"] = int(source["avoid_hit_ratio"]) + int(delta["avoid_hit_ratio"])
	profile["attack_back"] = (12 if int(source["attack_back"]) == 0 else int(source["attack_back"])) + int(delta["attack_back"])
	profile["attack_damagex2"] = (8 if int(source["attack_damagex2"]) == 0 else int(source["attack_damagex2"])) + int(delta["attack_damagex2"])
	# 0x448840: +0x196 = +0x194 word or 12 when it is 0; 0x448420 adds each equipped item +0x40 (add_steal_ratio).
	profile["steal_ratio"] = (12 if int(profile["base_steal_ratio"]) == 0 else int(profile["base_steal_ratio"])) + int(delta["steal_ratio"])
	profile.merge(equipment["weapon"], true)
	profile["live_magic_attack"] = maxi(0, magic_attack)
	profile["resist_by_type"] = resists
	next["combat_profile"] = profile
	next["max_hp"] = maxi(1, max_hp)
	next["hp"] = mini(int(next["hp"]), int(next["max_hp"]))
	next["max_mp"] = maxi(0, max_mp)
	next["mp"] = mini(int(next["mp"]), int(next["max_mp"]))
	next["live_speed"] = maxi(0, speed)
	next["move_point"] = MobilityRules.value(int(next["base_move_point"]), int(delta["move_point"]))
	return next


static func exp_to_next(level: int) -> int:
	# Native stat refresh 0x44b678..0x44b69e; threshold consumed at 0x43a235.
	return mini(2000, (maxi(1, level) + 1) * 50)


static func can_job_up(unit: Dictionary, rule: Dictionary, inventory: Array, flags: Dictionary) -> bool:
	if str(unit.get("class_id", "")) != str(rule.get("from_class", "")):
		return false
	if int(unit.get("level", 1)) < int(rule.get("min_level", 1)):
		return false

	var stats: Dictionary = unit.get("stats", {})
	for stat in rule.get("min_stats", {}).keys():
		if int(stats.get(stat, 0)) < int(rule["min_stats"][stat]):
			return false
	for item in rule.get("required_items", []):
		if inventory.find(item) == -1:
			return false
	for flag in rule.get("required_flags", {}).keys():
		if flags.get(flag) != rule["required_flags"][flag]:
			return false
	return true
