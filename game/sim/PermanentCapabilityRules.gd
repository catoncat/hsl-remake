extends RefCounted
## Persistent acquired offsets, separate from source templates, equipment and
## packed temporary statuses. Every derived refresh consumes this same model.
## provenance:
##   rules: static-derived docs/evidence_packets/static_reverse/original_permanent_items.md
const SkillResourceRules = preload("res://game/sim/SkillResourceRules.gd")
const Values = preload("res://game/sim/Values.gd")
const KEYS := ["attack_power","magic_attack_power","defense","speed","resist_0","resist_1","resist_2","resist_3","resist_4"]
const LABELS := {"attack_power":"攻擊","magic_attack_power":"魔擊","defense":"防禦","speed":"敏捷度",
	"resist_0":"地抗性","resist_1":"水抗性","resist_2":"風抗性","resist_3":"火抗性","resist_4":"心抗性"}
const MAX_GAIN := 1000000 # Supported save domain, not a native signed-overflow claim.

static func empty() -> Dictionary:
	var gains := {}
	for key in KEYS: gains[key] = 0
	return gains

static func base_value(actor: Dictionary, key: String) -> int:
	var growth: Variant = actor.get("growth_profile")
	if not growth is Dictionary or not growth.get("source") is Dictionary: return -1
	var source: Dictionary = growth["source"]
	if key.begins_with("resist_"):
		if not source.get("base_resist_by_type") is Dictionary: return -1
		return Values.non_negative_int(source["base_resist_by_type"].get(key.trim_prefix("resist_")))
	return Values.non_negative_int(source.get(key))

static func input_error(actor: Dictionary) -> String:
	var gains: Variant = actor.get("permanent_gains")
	if not gains is Dictionary or gains.size() != KEYS.size(): return "missing_permanent_capability_state"
	for key in KEYS:
		var amount := Values.non_negative_int(gains.get(key))
		if amount < 0 or amount > MAX_GAIN: return "invalid_permanent_capability"
		# Existing actors without a supported growth model may fight, but they
		# cannot hold acquired offsets whose original source is unknown.
		if not actor.has("growth_profile"):
			if amount != 0: return "missing_permanent_source"
			continue
		var base := base_value(actor,key)
		if base < 0: return "invalid_permanent_capability"
		if key.begins_with("resist_") and base + amount > 80: return "permanent_resistance_above_source_cap"
	return ""

static func effective_profile(actor: Dictionary) -> Dictionary:
	var result: Dictionary = actor["growth_profile"].duplicate(true)
	for key in KEYS:
		var amount := int(actor["permanent_gains"][key])
		if key.begins_with("resist_"): result["source"]["base_resist_by_type"][key.trim_prefix("resist_")] = base_value(actor,key) + amount
		else: result["source"][key] = base_value(actor,key) + amount
	return result

static func definition_error(item: Dictionary) -> String:
	var effects: Variant = item.get("permanent",{})
	if not effects is Dictionary: return "invalid_permanent_item_definition"
	for key in effects:
		if key not in KEYS: return "invalid_permanent_item_definition"
		var bounds: Variant = effects[key]
		if not bounds is Array or bounds.size() != 2: return "invalid_permanent_item_definition"
		var lo := Values.non_negative_int(bounds[0]); var hi := Values.non_negative_int(bounds[1])
		if lo < 1 or hi < lo or hi > (1 if key.begins_with("resist_") else 5): return "invalid_permanent_item_definition"
	return ""

## `spend`: a raw resistance already at 80 still gets its proposal — the original draws the
## sample and re-clamps to the same 80 (original_permanent_items.json cap rows).
static func prepare(actor: Dictionary, item: Dictionary, spend: bool = false) -> Dictionary:
	var error := definition_error(item)
	if error != "": return {"ok":false,"reason":error}
	var effects: Dictionary = item.get("permanent",{})
	if effects.is_empty(): return {"ok":true,"proposals":[]}
	error = input_error(actor)
	if error != "": return {"ok":false,"reason":error}
	if not actor.has("growth_profile"): return {"ok":false,"reason":"missing_permanent_source"}
	var proposals: Array = []
	# Original handler order is attack, magic, defense, speed, earth/water/air/fire/mind.
	for key in KEYS:
		if not effects.has(key): continue
		var before := int(actor["permanent_gains"][key]); var raw := base_value(actor,key) + before
		if key.begins_with("resist_") and raw == 80 and not spend: continue
		var bounds: Array = effects[key]
		if before > MAX_GAIN - int(bounds[1]): return {"ok":false,"reason":"permanent_capability_domain_exhausted"}
		proposals.append({"kind":key,"source_value":base_value(actor,key),"before_gain":before,
			"before_raw":raw,"low":int(bounds[0]),"high":int(bounds[1])})
	return {"ok":true,"proposals":proposals}

static func apply_sample(actor: Dictionary, proposal: Dictionary, value: int) -> Dictionary:
	var key: String = proposal["kind"]
	var raw := int(proposal["before_raw"]) + value
	if key.begins_with("resist_"): raw = mini(80,raw)
	actor["permanent_gains"][key] = raw - int(proposal["source_value"])
	return {"kind":key,"sampled":value,"amount":raw-int(proposal["before_raw"]),
		"before_raw":proposal["before_raw"],"after_raw":raw,
		"before_gain":proposal["before_gain"],"after_gain":actor["permanent_gains"][key]}

static func active(actor: Dictionary) -> bool:
	return actor["permanent_gains"].values().any(func(value):return int(value) != 0)

static func description(actor: Dictionary) -> String:
	if input_error(actor) != "": return ""
	var entries: Array[String] = []
	for key in KEYS:
		var amount := int(actor["permanent_gains"][key])
		if amount > 0: entries.append("%s +%d" % [LABELS[key],amount])
	return "永久獲得：" + "、".join(entries) if not entries.is_empty() else ""
