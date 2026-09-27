extends RefCounted
## Explicit adapter for a newly created script reinforcement. Not a turn effect.
## provenance:
##   rules: static-derived docs/evidence_packets/static_reverse/original_auto_growth.md; static-derived docs/evidence_packets/static_reverse/original_ai_navigation.md; static-derived docs/evidence_packets/static_reverse/original_enemy_turn.md
##   layout: n/a
##   strings: n/a
##   timing: n/a
##   audio: n/a
const Entry = preload("res://game/sim/EntryGrowthRules.gd")
const Growth = preload("res://game/sim/ProgressionRules.gd")
const Reward = preload("res://game/sim/BattleRewardRules.gd")
const Presence = preload("res://game/sim/BattlePresenceRules.gd")
const GlobalRandom = preload("res://game/sim/GlobalRandomStream.gd")

static func prepare(loop: Dictionary, actor: Dictionary, insertion: Dictionary, origin_kind: String = "") -> Dictionary:
	var source: Variant = loop.get("entry_growth_data",{}).get("actors",{}).get(str(actor.get("actor_id","")))
	if not source is Dictionary or not actor.has("growth_profile"): return {"ok":false,"reason":"unsupported_reinforcement_growth_source"}
	var parameters: Variant = insertion.get("adjust_level",[])
	var origin := "script"
	if parameters is Array and parameters.is_empty():
		parameters=source["parameters"];origin="source_template"
		# EVEF instance words 16/17 replace the +0x1f8 range / disp halves of the template (0x42c043 / 0x42c04c).
		var overrides: Dictionary = actor.get("evef_instance",{}).get("overrides",{})
		if parameters is Array and parameters.size() == 2 and (overrides.has("level_adjust_range") or overrides.has("level_adjust_disp_range")):
			parameters=[int(overrides.get("level_adjust_range",parameters[0])),int(overrides.get("level_adjust_disp_range",parameters[1]))]
	if origin_kind != "": origin = origin_kind
	if parameters is Array: parameters=parameters.map(func(value):return int(value) if str(value).is_valid_int() else value)
	var error := Entry.parameters_error(parameters)
	if error != "": return {"ok":false,"reason":error}
	error=Growth.refresh_input_error(actor,loop["equipment_items"])
	if error != "": return {"ok":false,"reason":error}
	if actor.has("entry_growth") or int(actor.get("pending_stat_points",0)) != 0: return {"ok":false,"reason":"reused_reinforcement_growth"}
	# 0x40e7a0 averages the players registered in 0x4c34c0 when the object first ticks. At
	# the opening that is an order question (original_auto_growth.md): EVEF objects are
	# born on frame 1 after the EVEF-installed players, a STORY insert after every insert
	# before it — so an EVEF object never sees an obj_Story_PlayerN player. A runtime
	# insert sees the whole registered party.
	var mine := int(actor.get("opening_birth",{}).get("story_insert",0)) if origin_kind == "initial_roster" else -1
	var party := _party(loop,func(other):
		var theirs := int(other.get("opening_birth",{}).get("story_insert",0))
		return mine < 0 or theirs == 0 or (mine > 0 and theirs < mine))
	var attrs := {}
	for key in Entry.KEYS:attrs[key]=int(actor["combat_profile"][key])
	var input := {"attributes":attrs,"caps":actor["growth_profile"]["caps"].duplicate(true),"job":int(actor["growth_profile"]["job_code"]),
		"level":int(actor["level"]),"exp":int(actor["exp"]),"stamina":int(actor["stamina"]),"kill_exp":int(actor["kill_exp"]),
		"gold":Reward.kill_gold(actor,int(source["gold"])),"object_kind":int(actor.get("source_object_kind",2)),"parameters":parameters,"party_levels":party["levels"]}
	return _apply(loop,actor,input,"entry_growth",origin,party["ids"])

## Opcode 73 (actAdjustAllPlayerLevel, only STORY006) sets 0x4c1d48 for one tick and every
## object re-runs 0x40e870 on its live words (0x43f3a5): the birth's raised attributes,
## level, EXP, stamina, kill EXP and gold, the same +0x1f8 halves, against the players
## registered by then. The base level is re-inferred from the raised attributes, so it
## only ever raises; its source gains add to the birth's.
static func readjust(loop: Dictionary, actor: Dictionary) -> Dictionary:
	var birth: Variant = actor.get("entry_growth")
	if not birth is Dictionary or birth.get("origin") != "initial_roster" or actor.has("entry_readjust"): return {"ok":false,"reason":"invalid_entry_readjust_boundary"}
	var error:=Entry.input_error(actor)
	if error != "":return {"ok":false,"reason":error}
	error=Growth.refresh_input_error(actor,loop["equipment_items"])
	if error != "": return {"ok":false,"reason":error}
	var party := _party(loop,func(other): return bool(other.get("opening_birth",{}).get("adjust_all_level",false)))
	var attrs := {}
	for key in Entry.KEYS:attrs[key]=int(actor["combat_profile"][key])
	var input := {"attributes":attrs,"caps":actor["growth_profile"]["caps"].duplicate(true),"job":int(actor["growth_profile"]["job_code"]),
		"level":int(actor["level"]),"exp":int(actor["exp"]),"stamina":int(actor["stamina"]),"kill_exp":int(actor["kill_exp"]),
		"gold":int(birth["result"]["gold"]),"object_kind":int(birth["input"]["object_kind"]),"parameters":birth["input"]["parameters"].duplicate(),"party_levels":party["levels"]}
	return _apply(loop,actor,input,"entry_readjust",Entry.READJUST_ORIGIN,party["ids"])

## Registered controlled party members `visible` accepts: the explicit remake counterpart
## of the native 20-slot registry. Dead-but-registered records still contribute.
static func _party(loop: Dictionary, visible: Callable) -> Dictionary:
	var levels: Array = []
	var ids: Array = []
	for other in loop["units"]:
		if other.get("growth_profile", {}).get("allocation") == "manual" and not bool(other.get("departed",false)) and visible.call(other):
			levels.append(int(other["level"]));ids.append(other["id"])
	return {"levels":levels,"ids":ids}

static func _apply(loop: Dictionary, actor: Dictionary, input: Dictionary, record_key: String, origin: String, party_ids: Array) -> Dictionary:
	# 0x40e870 draws rand(n) 0x458c80 on the global stream; the caller commits the words.
	if not GlobalRandom.valid(loop.get(GlobalRandom.LOOP_KEY)): return {"ok":false,"reason":"invalid_global_rng"}
	var before:Array=(loop[GlobalRandom.LOOP_KEY] as Array).duplicate()
	var state := [before]
	var proposal:=Entry.propose(input,func(bound):
		var draw:=GlobalRandom.rand(state[0],bound);state[0]=draw["state"];return draw["value"])
	if not proposal["ok"]:return proposal
	var next:=actor.duplicate(true)
	var result:Dictionary=proposal["result"]
	for key in ["level","exp","stamina","kill_exp"]:next[key]=result[key]
	for key in Entry.KEYS:next["combat_profile"][key]=result["attributes"][key]
	next[record_key]={"policy":Entry.POLICY,"actor_id":actor["actor_id"],"origin":origin,"party_ids":party_ids,"input":input,
		"draws":proposal["draws"],"result":result}
	for key in ["hit_point","magic_point"]:
		if int(next["growth_profile"]["source"][key])+Entry.source_gain(next,key) > 65535:return {"ok":false,"reason":"entry_source_word_domain_exceeded"}
	var error:=Entry.input_error(next)
	if error != "":return {"ok":false,"reason":error}
	next=Growth.refresh_growth_stats(next,loop["equipment_items"])
	next["hp"]=next["max_hp"];next["mp"]=next["max_mp"]
	return {"ok":true,"actor":next,"rng":state[0]}

static func state_error(loop: Dictionary) -> String:
	if loop.get("entry_growth_data",{}).get("schema") != "hsl_entry_growth_sources.v1":return "invalid_entry_growth_data"
	if not GlobalRandom.valid(loop.get(GlobalRandom.LOOP_KEY)):return "invalid_global_rng"
	var adjusted := {}
	for actor in loop["units"]:
		var error:=Entry.input_error(actor)
		if error != "":return error
		if actor.has("entry_growth"):adjusted[actor["id"]]=true
	for insertion in loop.get("winfail_runtime",{}).get("inserts",[]):
		var id:=str(insertion.get("unit_id",""))
		if id != "" and not adjusted.has(id):return "missing_reinforcement_growth_receipt"
	return ""
