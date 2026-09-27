extends RefCounted
## Pure job-up exchange (0x4348f0) for both callers: the battle token
## actPlayerJobUpProcess (flag 0x80000000, WinfailScenarioRules) and the 命運神殿
## teCheckJobUp / teCheckJobUp2 (TownEventRules). The caller supplies the reviewed
## target template; this rule never loads a second source or guesses a replacement
## when the target is missing.
## provenance:
##   rules: static-derived docs/evidence_packets/static_reverse/original_town_job_up.md
##   rules: static-derived docs/evidence_packets/static_reverse/original_level37_tokens.md
##   rules: resource-derived content/imported/hsl/global/tables/OBJ-ALL.H
##   rules: negative-evidence (018 has no SHAPEDEF row)

const NATIVE_JOB_UP_FLAG := 0x80000000
## 0x454e20 case 0x20 (teCheckJobUp2) writes this second-tier flag instead
## (static-derived, docs/evidence_packets/static_reverse/original_town_job_up.md).
const SECOND_TIER_FLAG := 0x40000000
const MERGE_POLICY := "native_job_up_merge_v1"
## PLAYERS job_up_code -> OBJ-ALL.H obj_Player1Up1..9Up1 (809..817) / 1Up2, 2Up2
## (818, 819) -> global.obs obj_Data7 rows 10..20 (resource-derived). Rows 012–018
## declare job-up 0, so the chain ends there; 010/011 continue to 019/020. 008 → 017 is
## also what the level-37 actPlayerJobUpProcess resolves (same record+0x60 chain,
## original_level37_tokens.md). 018 (魍魎劍士) is a rules target only: SHAPEDEF.TXT keeps
## its shape row commented out (negative-evidence), so presentation falls back to 009's
## frames (ActorSpriteKey.frame_key) while the 018 stats, title and sounds apply.
const TOWN_TARGETS := {"001": "010", "002": "011", "003": "012", "004": "013", "005": "014", "006": "015", "007": "016", "008": "017", "009": "018", "010": "019", "011": "020"}
## 0x434770: every base attribute must reach its job cap minus this margin.
const CONDITION_MARGIN := 50
const SOURCE_TEMPLATE_DIR := "res://content/generated/hsl/actors/%s.json"
const SOURCE_TEMPLATE_SCHEMA := "hsl_source_actor_template.v1"
const EquipmentRules = preload("res://game/sim/EquipmentRules.gd")
const ContentPaths = preload("res://game/sim/ContentPaths.gd")
const ADDITIVE_SOURCE_KEYS := ["attack_power", "magic_attack_power", "defense", "speed", "hit_point", "magic_point", "avoid_hit_ratio", "attack_back", "attack_damagex2"]


## ---------------------------------------------------------------------------
## 0x4348f0 for both the town tokens and actPlayerJobUpProcess: the registered member
## keeps its record — level, exp, attributes, equipment, inventory, learned skills and
## its actor id as the resource key — and the target PLAYERS row is merged into it
## (static-derived, original_town_job_up.md). The target row is recorded as
## job_up_target_actor_id / job_up_history, which is what the campaign carry replays
## in the next battle (CampaignCarryRules.apply) for either caller. No second stat
## refresh: the merged growth_profile is fed to the shared ProgressionRules refresh.

## The template row the member currently stands on ("001" before any job-up, the
## last target afterwards).
static func current_template_actor_id(record: Dictionary) -> String:
	var target := str(record.get("job_up_target_actor_id", ""))
	return target if target != "" else str(record.get("actor_id", ""))


## Next PLAYERS row for this member, "" when its job_up_code is 0 (chain ended).
static func town_target_actor_id(record: Dictionary) -> String:
	return str(TOWN_TARGETS.get(current_template_actor_id(record), ""))


## 0x434770 on carry-shaped inputs: {ok, reason, target_actor_id, checks}.
static func town_condition(record: Dictionary, attributes: Dictionary, caps: Dictionary) -> Dictionary:
	var target := town_target_actor_id(record)
	var result := {"ok": false, "reason": "", "target_actor_id": target, "checks": {}}
	if target == "":
		result["reason"] = "job_up_code_zero"
		return result
	for key in ["str", "dex", "mind", "con"]:
		if not (attributes.get(key) is int or attributes.get(key) is float) or not (caps.get(key) is int or caps.get(key) is float):
			result["reason"] = "missing_attribute_or_cap_" + key
			return result
		var needed := int(caps[key]) - CONDITION_MARGIN
		result["checks"][key] = {"value": int(attributes[key]), "needed": needed}
		if int(attributes[key]) < needed:
			result["reason"] = "attribute_below_cap_margin_" + key
			return result
	result["ok"] = true
	return result


static func load_source_template(actor_id: String) -> Dictionary:
	var path := SOURCE_TEMPLATE_DIR % actor_id
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = ContentPaths.read_json(path)
	if typeof(parsed) != TYPE_DICTIONARY or str((parsed as Dictionary).get("schema", "")) != SOURCE_TEMPLATE_SCHEMA:
		return {}
	var actor: Variant = (parsed as Dictionary).get("actor", {})
	return actor if typeof(actor) == TYPE_DICTIONARY else {}


static func merge_input_error(unit: Dictionary, template: Dictionary) -> String:
	if unit.is_empty(): return "missing_job_up_unit"
	if template.is_empty(): return "missing_job_up_template"
	if not unit.get("growth_profile") is Dictionary or not (unit["growth_profile"] as Dictionary).get("source") is Dictionary:
		return "missing_job_up_unit_growth_profile"
	if not template.get("growth_profile") is Dictionary or not (template["growth_profile"] as Dictionary).get("source") is Dictionary or not (template["growth_profile"] as Dictionary).get("caps") is Dictionary:
		return "missing_job_up_template_growth_profile"
	if not template.has("actor_id") or not template.has("base_move_point") or not template.has("weapon_code"):
		return "missing_job_up_template_fields"
	return ""


## 0x4348f0 as a merge into the live/carry unit: job code and caps come from the
## target, additive source fields are summed, base resists and move point are
## summed with the native caps (80 / 12), a declared target weapon replaces the
## current one, flag is ORed into job_up_flags. Attributes, level, exp, inventory,
## learned skills and the actor id stay.
static func merge_source_template(unit: Dictionary, template: Dictionary, flag: int) -> Dictionary:
	var error := merge_input_error(unit, template)
	if error != "":
		return {"ok": false, "reason": error, "actor": unit.duplicate(true)}
	var next := unit.duplicate(true)
	var growth: Dictionary = next["growth_profile"]
	var target_growth: Dictionary = template["growth_profile"]
	var source: Dictionary = growth["source"]
	var target_source: Dictionary = target_growth["source"]
	var from_job_code := int(growth.get("job_code", -1))
	growth["job_code"] = int(target_growth["job_code"])
	var caps := {}
	for key in (target_growth["caps"] as Dictionary).keys():
		caps[str(key)] = int(target_growth["caps"][key])  # JSON floats → the integer caps the refresh compares
	growth["caps"] = caps
	for key in ADDITIVE_SOURCE_KEYS:
		source[key] = int(source.get(key, 0)) + int(target_source.get(key, 0))
	source["has_magic"] = bool(source.get("has_magic", false)) or bool(target_source.get("has_magic", false))
	var resists: Dictionary = (source.get("base_resist_by_type", {}) as Dictionary).duplicate(true)
	var target_resists: Dictionary = target_source.get("base_resist_by_type", {})
	for index in range(5):
		var key := str(index)
		resists[key] = mini(80, int(resists.get(key, 0)) + int(target_resists.get(key, 0)))
	source["base_resist_by_type"] = resists
	if target_growth.has("evidence"):
		growth["evidence"] = target_growth["evidence"]
	growth["source"] = source
	next["growth_profile"] = growth
	next["base_move_point"] = mini(12, int(next.get("base_move_point", 0)) + int(template.get("base_move_point", 0)))
	# 0x434aa6: the +0x194 steal_ratio word is summed like the other three words; the +0x196 work
	# value is the refresh's. The town caller's minimal view has no combat_profile (replayed later).
	if next.get("combat_profile") is Dictionary:
		var profile: Dictionary = next["combat_profile"]
		profile["base_steal_ratio"] = int(profile.get("base_steal_ratio", 0)) + int((template.get("combat_profile", {}) as Dictionary).get("base_steal_ratio", 0))
		next["combat_profile"] = profile
	var target_weapon := int(template.get("weapon_code", 0))
	if target_weapon != 0:
		# +0xec: a declared target weapon replaces the member's weapon slot. Equipment is
		# the unit's six-slot list ({slot, item_code, name}, EquipmentRules.SLOTS order).
		var equipment: Array = []
		for entry in next.get("equipment", []):
			if entry is Dictionary and str((entry as Dictionary).get("slot", "")) != "weapon":
				equipment.append((entry as Dictionary).duplicate(true))
		var weapon_entry := {"slot": "weapon", "item_code": target_weapon, "name": ""}
		for entry in template.get("equipment", []):
			if entry is Dictionary and str((entry as Dictionary).get("slot", "")) == "weapon" and int((entry as Dictionary).get("item_code", 0)) == target_weapon:
				weapon_entry["name"] = str((entry as Dictionary).get("name", ""))
		equipment.append(weapon_entry)
		equipment.sort_custom(func(a, b): return EquipmentRules.SLOTS.find(a["slot"]) < EquipmentRules.SLOTS.find(b["slot"]))
		next["equipment"] = equipment
		next["weapon_code"] = target_weapon
	var from_actor_id := current_template_actor_id(next)
	next["job_up_flags"] = int(next.get("job_up_flags", 0)) | flag
	next["job_up_target_actor_id"] = str(template["actor_id"])
	next["job_up_policy"] = MERGE_POLICY
	var history: Array = (next.get("job_up_history", []) as Array).duplicate(true)
	history.append({"from_actor_id": from_actor_id, "to_actor_id": str(template["actor_id"]), "flag": flag, "from_job_code": from_job_code, "job_code": int(target_growth["job_code"])})
	next["job_up_history"] = history
	return {"ok": true, "actor": next, "receipt": {
		"policy": MERGE_POLICY,
		"unit_id": str(unit.get("id", "")),
		"actor_id": str(unit.get("actor_id", "")),
		"from_actor_id": from_actor_id,
		"to_actor_id": str(template["actor_id"]),
		"job_code": int(target_growth["job_code"]),
		"flag": flag,
	}}


## Replays a carried job-up history onto a freshly built scenario unit (the base
## template): every step's target template is loaded and merged in order, so a
## two-step chain accumulates like the original record. {ok, reason, actor}.
static func replay_history(unit: Dictionary, history: Array) -> Dictionary:
	var next := unit.duplicate(true)
	for key in ["job_up_flags", "job_up_target_actor_id", "job_up_history", "job_up_policy"]:
		next.erase(key)
	for step_value in history:
		if typeof(step_value) != TYPE_DICTIONARY:
			return {"ok": false, "reason": "invalid_job_up_history", "actor": unit.duplicate(true)}
		var step: Dictionary = step_value
		var template := load_source_template(str(step.get("to_actor_id", "")))
		if template.is_empty():
			return {"ok": false, "reason": "missing_job_up_template_" + str(step.get("to_actor_id", "")), "actor": unit.duplicate(true)}
		var merged := merge_source_template(next, template, int(step.get("flag", NATIVE_JOB_UP_FLAG)))
		if not merged["ok"]:
			return merged
		next = merged["actor"]
	return {"ok": true, "actor": next}
