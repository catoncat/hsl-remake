extends RefCounted
## Pure native entry-level/allocation proposals and a birth layer drawing the caller's source.
## No battle/queue/UI ownership. Equipment and permanent gains remain separate.
## provenance:
##   rules: static-derived docs/evidence_packets/static_reverse/original_auto_growth.md; resource-derived content/generated/hsl/roles/job_formulas.json; resource-derived content/generated/hsl/roles/entry_growth.json; static-derived docs/evidence_packets/static_reverse/original_enemy_turn.md
##   layout: n/a
##   strings: n/a
##   timing: n/a
##   audio: n/a
const POLICY := "source_entry_growth_v1"
const READJUST_ORIGIN := "adjust_all_level"
const KEYS := ["str", "dex", "mind", "con"]
const SOURCE_KEYS := ["hit_point", "magic_point", "speed", "attack_power", "magic_attack_power"]
const Number = preload("res://game/sim/SkillResourceRules.gd")
const JobStats = preload("res://game/sim/JobStatsRules.gd")
const MAX_PARAMETER := 1000 # Supported bounded domain, not the original16-bit limit.

static func inferred_level(attributes: Dictionary) -> int:
	var total := 0
	for key in KEYS: total += int(attributes[key])
	return 1 + maxi(0, (total - 52 + 4) / 5)

static func average(levels: Array) -> int:
	var sum := 0
	for level in levels: sum += int(level)
	return 1 if levels.is_empty() else maxi(1, sum / levels.size())

static func parameters_error(values: Variant) -> String:
	if not values is Array or values.size() != 2: return "missing_entry_adjustment_parameters"
	for value in values:
		if Number._integer(value) < 0 or Number._integer(value) > MAX_PARAMETER: return "invalid_entry_adjustment_parameter"
	return ""

static func allocate(attributes: Dictionary, level: int, exp: int, first_threshold: int, caps: Dictionary, job: int, requested: int) -> Dictionary:
	var result := attributes.duplicate(true)
	var capacity := 0
	for key in KEYS: capacity += int(caps[key]) - int(result[key])
	var remaining := maxi(0, mini(requested, capacity))
	var quota: Array = JobStats.allocation_quota(job)
	if quota.is_empty():
		return {"attributes": result, "level": level, "exp": exp, "cap_fallback": false, "reason": "unsupported_entry_job"}
	var threshold := first_threshold
	var fallback := false
	while remaining > 0:
		var budget := mini(5, remaining)
		remaining -= budget
		exp = maxi(0, exp - threshold)
		level += 1
		threshold = mini(2000, (level+1)*50)
		for index in range(KEYS.size()):
			var key: String = KEYS[index]
			var count := maxi(0, mini(mini(int(quota[index]), budget), int(caps[key])-int(result[key])))
			result[key] = int(result[key]) + count
			budget -= count
		if budget > 0:
			# The checked native fallback fills uncapped attributes without an inner
			# remaining-budget guard. Do not substitute balanced manual allocation.
			fallback = true
			for key in KEYS: result[key] = maxi(int(result[key]), int(caps[key]))
	return {"attributes": result, "level": level, "exp": exp, "cap_fallback": fallback}

static func propose(input: Dictionary, rng: Callable) -> Dictionary:
	var error := parameters_error(input.get("parameters"))
	if error != "": return {"ok":false,"reason":error}
	if not input.get("party_levels") is Array or input["party_levels"].size() > 20: return {"ok":false,"reason":"invalid_entry_party"}
	for level in input["party_levels"]:
		if Number._integer(level) < 0 or Number._integer(level) > 1000: return {"ok":false,"reason":"invalid_entry_party_level"}
	for key in ["level", "exp", "stamina", "gold", "kill_exp", "job", "object_kind"]:
		if Number._integer(input.get(key)) < 0 or Number._integer(input.get(key)) > 1000000: return {"ok":false,"reason":"invalid_entry_"+key}
	if int(input["level"]) < 1 or int(input["level"]) > 1000 or not JobStats.has_job(int(input["job"])): return {"ok":false,"reason":"unsupported_entry_job"}
	# An attribute may start above its job cap: PLAYERS 101 (the level-12／26 hull pieces) births
	# with str 120／con 200 over caps 107／99, kept as is in the original's round-1 record
	# (opening snapshot); `allocate` only raises attributes below their caps.
	for key in KEYS:
		if not input.get("attributes") is Dictionary or not input.get("caps") is Dictionary or Number._integer(input["attributes"].get(key)) < 1 or Number._integer(input["caps"].get(key)) < 1: return {"ok":false,"reason":"invalid_entry_attributes"}
	var attrs: Dictionary = input["attributes"].duplicate(true)
	var level := inferred_level(attrs)
	var source_level := level
	var target := level
	var exp := int(input["exp"])
	var gold := int(input["gold"])
	var kill_exp := int(input["kill_exp"])
	var stamina := int(input["stamina"])
	var gains := {}
	for key in SOURCE_KEYS: gains[key] = 0
	var draws: Array = []
	var spread := int(input["parameters"][0])
	var dispersion := int(input["parameters"][1])
	var applied := false
	var fallback := false
	if int(input["object_kind"]) != 3 and (spread != 0 or dispersion != 0):
		var low := maxi(1, level-spread)
		var high := maxi(low+1, level+spread)
		var center := clampi(average(input["party_levels"]), low, high)
		low = maxi(1, center-mini(4,dispersion))
		high = maxi(low+1, center+dispersion)
		var width := high-low+1
		target = low+_draw((width+1)/2+1,rng,draws)+_draw(width/2,rng,draws)
		if target > level:
			applied = true
			var delta := target-level
			kill_exp += kill_exp*clampi((_draw(4,rng,draws)+7)*delta,15,150)/100
			gold += gold*clampi((_draw(4,rng,draws)+7)*delta,10,80)/100
			gold = (gold+9)/10*10
			for spec in [["hit_point",100,250],["magic_point",150,150],["speed",20,20],["attack_power",60,50],["magic_attack_power",10,10]]:
				gains[spec[0]] = (_draw(spec[1],rng,draws)+int(spec[2]))*delta/100
			if stamina == 0: stamina = _draw(11,rng,draws)
			var allocation := allocate(attrs,level,exp,mini(2000,(int(input["level"])+1)*50),input["caps"],input["job"],delta*5)
			attrs = allocation["attributes"]; level = allocation["level"]; exp = allocation["exp"]; fallback = allocation["cap_fallback"]
	var result := {"attributes":attrs,"level":level,"exp":exp,"stamina":stamina,"gold":gold,"kill_exp":kill_exp,"source_gains":gains,
		"source_level":source_level,"sampled_level":target,"raised":applied,"cap_fallback":fallback}
	return {"ok":true,"result":result,"draws":draws}

static func _draw(bound: int, rng: Callable, draws: Array) -> int:
	var value := clampi(int(rng.call(bound)),0,bound-1)
	draws.append({"bound":bound,"value":value})
	return value

static func input_error(actor: Dictionary) -> String:
	if not actor.has("entry_growth"): return "entry_readjust_without_birth" if actor.has("entry_readjust") else "" # No birth adjustment on this actor.
	var error := _record_error(actor, actor["entry_growth"])
	if error != "": return error
	var last: Dictionary = actor["entry_growth"]
	if actor.has("entry_readjust"):
		# Opcode 73 re-runs 0x40e870 on the birth's already-raised live words.
		error = _record_error(actor, actor["entry_readjust"])
		if error != "": return error
		var readjust: Dictionary = actor["entry_readjust"]
		if last.get("origin") != "initial_roster" or readjust.get("origin") != READJUST_ORIGIN: return "invalid_entry_readjust_origin"
		for key in ["level", "exp", "stamina", "kill_exp", "gold", "attributes"]:
			if readjust["input"].get(key) != last["result"][key]: return "entry_readjust_chain_mismatch"
		for key in ["caps", "job", "object_kind", "parameters"]:
			if readjust["input"].get(key) != last["input"][key]: return "entry_readjust_chain_mismatch"
		last = readjust
	var profile:Variant=actor.get("growth_profile")
	var attributes:Variant=actor.get("combat_profile")
	if not profile is Dictionary or not attributes is Dictionary: return "invalid_entry_growth_actor"
	if Number._integer(profile.get("job_code")) != int(last["input"]["job"]) or profile.get("caps") != last["input"]["caps"]: return "entry_growth_profession_mismatch"
	if actor.get("kill_exp") != last["result"]["kill_exp"]: return "entry_growth_reward_mismatch"
	if int(actor.get("level",0)) < int(last["result"]["level"]): return "entry_growth_level_rollback"
	for key in KEYS:
		if Number._integer(attributes.get(key)) < int(last["result"]["attributes"][key]): return "entry_growth_attribute_rollback"
	return ""

## One adjustment record replays from its own draws to its own result.
static func _record_error(actor: Dictionary, record: Variant) -> String:
	if not record is Dictionary or record.get("policy") != POLICY or not record.get("input") is Dictionary or not record.get("draws") is Array or not record.get("result") is Dictionary: return "invalid_entry_growth_record"
	var cursor := [0]
	var mismatch := [false]
	var replay := propose(record["input"],func(bound):
		if cursor[0] >= record["draws"].size(): mismatch[0]=true; return 0
		var draw: Variant = record["draws"][cursor[0]]; cursor[0]+=1
		if not draw is Dictionary or draw.get("bound") != bound or Number._integer(draw.get("value")) < 0 or Number._integer(draw.get("value")) >= bound: mismatch[0]=true; return 0
		return int(draw["value"]))
	if not replay["ok"] or mismatch[0] or cursor[0] != record["draws"].size() or replay["result"] != record["result"]: return "inconsistent_entry_growth_record"
	if actor.get("actor_id") != record.get("actor_id"): return "entry_growth_actor_mismatch"
	return ""

## Adjustment records of an actor in the order they were applied (birth, then the opcode 73 re-adjust).
static func records(actor: Dictionary) -> Array:
	var result: Array = []
	for key in ["entry_growth", "entry_readjust"]:
		if actor.has(key): result.append(actor[key])
	return result

## Source-word gain of one SOURCE_KEYS key summed over the actor's adjustment records.
static func source_gain(actor: Dictionary, key: String) -> int:
	var total := 0
	for record in records(actor): total += int(record["result"]["source_gains"].get(key, 0))
	return total

static func effective_profile(actor: Dictionary, profile: Dictionary) -> Dictionary:
	var result := profile.duplicate(true)
	for record in records(actor):
		for key in SOURCE_KEYS: result["source"][key] = int(result["source"][key]) + int(record["result"]["source_gains"][key])
	return result

static func gold(actor: Dictionary, source_value: int) -> int:
	var applied := records(actor)
	return int(applied.back()["result"]["gold"]) if not applied.is_empty() else source_value

static func description(actor: Dictionary) -> String:
	if not actor.has("entry_growth"): return ""
	var applied := records(actor)
	return "入場成長：Lv.%d → %d" % [applied.front()["result"]["source_level"], applied.back()["result"]["level"]]
