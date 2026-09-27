extends "res://tests/support/TestSuite.gd"
const BattlePlayLoop = preload("res://game/sim/loop/BattlePlayLoop.gd")
const BattleLoopScript = preload("res://game/sim/loop/BattleLoopScript.gd")
const EntryGrowthRules = preload("res://game/sim/EntryGrowthRules.gd")
const ReinforcementGrowthRules = preload("res://game/sim/ReinforcementGrowthRules.gd")
const BattleCheckpoint = preload("res://game/battle/runtime/BattleCheckpoint.gd")
const run_script_wait_tests = preload("res://tests/run_script_wait_tests.gd")
const run_mobile_jobs_tests = preload("res://tests/run_mobile_jobs_tests.gd")
const WinfailScenarioRules = preload("res://game/sim/WinfailScenarioRules.gd")
const WinfailActions = preload("res://game/sim/WinfailActions.gd")
const BattleFixture = preload("res://tests/support/BattleFixture.gd")
const BattleRewardRules = preload("res://game/sim/BattleRewardRules.gd")
const BattleOutcome = preload("res://game/sim/BattleOutcome.gd")
const VIEW := {"camera":Vector2(320,240),"shown_story_events":[],"story_complete":true,"growth_notified_level":1}


func _init() -> void:
	tag = "ENTRY_GROWTH_TESTS"


static func source_actor(code: String) -> Dictionary:
	var loops := [run_mobile_jobs_tests.fresh(), BattleFixture.loop(),
		BattlePlayLoop.create([], "", BattlePlayLoop.BattleScenario.load_file("res://content/battles/battle_052.json")),
		BattlePlayLoop.create([], "", BattlePlayLoop.BattleScenario.load_file("res://content/battles/large_actor_trial.json"))]
	for loop in loops:
		for actor in loop.get("units",[]):
			if actor["actor_id"]==code:return actor.duplicate(true)
	return {}

static func fixture(code: String="026", parameters: Array=[20,3], player_level: int=16) -> Dictionary:
	var loop:=run_script_wait_tests.fixture()
	loop["rule_adapter"]="winfail"
	loop=WinfailScenarioRules.initialize_script_state(loop,BattlePlayLoop.BattleScenario.load_file(run_mobile_jobs_tests.PATH),
		{"schema":"hsl_battle_seed.v1","level":999,"scripts":{"story":{"sections":[]},"winfail":{"sections":[{"name":"event","codes":["901"],"messages":[],"actions":[]}]}}})
	for actor in loop["units"]:
		if actor["player_commandable"]:
			actor["level"]=player_level
			actor.merge(BattlePlayLoop.ProgressionRules.refresh_growth_stats(actor,loop["equipment_items"]),true)
	var template:=source_actor(code)
	template["battle_actor_role"]=BattlePlayLoop.ROLE_ENEMY;template["player_commandable"]=false
	template["growth_profile"]["allocation"]="fixed_template"
	template["class_id"]="Enemy"+code
	template["pending_stat_points"]=0;template["exp"]=0
	loop["reinforcement_templates"]=[template]
	loop["reinforcement_spawn_cells"]=[Vector2i(8,8),Vector2i(10,8),Vector2i(14,14)]
	loop["tiles"]={};loop["map_size"]=Vector2i(30,30)
	loop["winfail_runtime"]["initial_class_unit_ids"]={}
	for actor in loop["units"]:
		var klass:String=str(actor.get("class_id","Actor"+actor["actor_id"]))
		if not loop["winfail_runtime"]["initial_class_unit_ids"].has(klass):loop["winfail_runtime"]["initial_class_unit_ids"][klass]=[]
		loop["winfail_runtime"]["initial_class_unit_ids"][klass].append(actor["id"])
	request(loop,code,parameters)
	return loop

static func request(loop: Dictionary, code: String, parameters: Array) -> void:
	var insertion:Dictionary={"class_id":"Enemy"+code,"object_symbol":"obj_new","adjust_level":parameters.duplicate(),"wait_round":2}
	WinfailActions.apply_actions(loop,{"key":"event_growth","actions":[{"name":"actInsertObject","args":["obj_new","0","0"]},{"name":"actSetPrevInsertObjectWaitRound","args":["2"]}],"inserts":[insertion]},"test")
	BattleLoopScript.consume_script_waits(loop)

static func created(loop: Dictionary) -> Array:
	return loop["units"].filter(func(actor):return actor.has("entry_growth"))

func run() -> void:
	native_cases()
	adjust_level_zero_story_and_runtime()
	level6_two_phase_adjustment()
	opening_birth_leaves_other_levels()
	first_battle_recorded_levels()
	spawn_and_restore()
	layering_and_rewards()
	phase_and_campaign()
	pending_class_victory()

func native_cases() -> void:
	var packet:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://docs/evidence_packets/static_reverse/original_auto_growth.json"))
	var baseline:=BattleFixture.loop()
	for row in packet["cases"]:
		var c:Dictionary=row["input"]
		var native:Dictionary=row["native"]
		var profile:Dictionary=packet["profiles"][c["actor"]]
		if c["kind"]=="average":check(EntryGrowthRules.average(c["party"])==int(native["average"]),"native registered-party average");continue
		if c["kind"]=="infer":check(EntryGrowthRules.inferred_level(c["attributes"])==int(native["level"]),"native level inference from base attributes");continue
		if c["kind"]=="allocate":
			var result:=EntryGrowthRules.allocate(c["attributes"],int(c["level"]),int(c["exp"]),mini(2000,(int(c["level"])+1)*50),profile["caps"],int(profile["job_code"]),int(c["points"]))
			check(result["level"]==int(native["level"]) and result["exp"]==int(native["exp"]),"native automatic chunk and threshold order")
			for key in EntryGrowthRules.KEYS:check(int(result["attributes"][key])==int(native["attributes"][key]),"native quota/cap fallback "+key)
			continue
		var original_actor:=source_actor(c["actor"])
		check(not original_actor.is_empty(),"supported original template exists: "+str(c["actor"]))
		if original_actor.is_empty():continue
		var input:Dictionary={"job":int(profile["job_code"]),"caps":profile["caps"].duplicate(true),"attributes":c["attributes"].duplicate(true),"level":int(c["level"]),"exp":int(c["exp"]),"stamina":int(c["stamina"]),"object_kind":int(c["object_kind"]),"parameters":[int(c["range"]),int(c["dispersion"])],"party_levels":c["party"].duplicate(),"gold":int(baseline["entry_growth_data"]["actors"][c["actor"]]["gold"]),"kill_exp":int(baseline["entry_growth_data"]["actors"][c["actor"]]["kill_exp"])}
		var cursor:=[0]
		var proposed:=EntryGrowthRules.propose(input,func(bound):
			check(cursor[0]<row["draws"].size(),"no extra initialization draw")
			if cursor[0]>=row["draws"].size():return 0
			var draw:Dictionary=row["draws"][cursor[0]];cursor[0]+=1
			check(int(draw["bound"])==bound,"original adjustment random bound order")
			return int(draw["value"]))
		check(proposed["ok"] and cursor[0]==row["draws"].size(),"all original adjustment draws consumed once")
		if not proposed["ok"]:continue
		var result:Dictionary=proposed["result"]
		for key in ["level","exp","stamina","kill_exp","gold"]:check(result[key]==int(native[key]),"original adjustment "+key)
		for key in EntryGrowthRules.KEYS:check(result["attributes"][key]==int(native["attributes"][key]),"original adjusted base "+key)
		for key in EntryGrowthRules.SOURCE_KEYS:check(int(profile["source"][key])+int(result["source_gains"][key])==int(native["source"][key]),"separate birth-source increment "+key)
		original_actor["growth_profile"]=profile.duplicate(true)
		original_actor["growth_profile"]["source"]["mode"]=int(c["mode"]);original_actor["player_mode"]=int(c["mode"]) # live +0x28 of the native run
		original_actor["combat_profile"].merge(result["attributes"],true)
		original_actor["equipment"]=[]
		for index in range(6):
			if int(c["equipment"][index])>0:original_actor["equipment"].append({"slot":BattlePlayLoop.EquipmentRules.SLOTS[index],"item_code":int(c["equipment"][index])})
		for key in ["level","exp","stamina","kill_exp"]:original_actor[key]=result[key]
		original_actor["base_move_point"]=int(c["base_move"])
		original_actor["entry_growth"]={"policy":EntryGrowthRules.POLICY,"actor_id":c["actor"],"input":input,"result":result,"draws":proposed["draws"]}
		original_actor=BattlePlayLoop.ProgressionRules.refresh_growth_stats(original_actor,baseline["equipment_items"])
		for key in ["max_hp","max_mp","move_point"]:check(original_actor[key]==int(native["stats"][key]),"post-adjustment native derived "+key)
		for pair in [["live_attack_damage","attack"],["live_defense","defense"],["live_magic_attack","magic_attack"],["live_hit_ratio","hit_rate"]]:check(original_actor["combat_profile"][pair[0]]==int(native["stats"][pair[1]]),"native refreshed "+pair[1])
		for index in range(5):check(int(original_actor["combat_profile"]["resist_by_type"][str(index)])==int(native["stats"]["resist_by_type"][str(index)]),"native adjusted resistance")

## actSetPrevInsertObjectAdjustLevel,0,0 (opcode 56, 0x450840 → 0x450ba4 writes the previous
## insert's live +0x1f8 range／disp halves): the install adjusts no level. R33 runtime-measured
## (docs/evidence_packets/runtime_observations/battle_053/original_units.json): the two STORY053
## pursuers and every 023 the WINFAIL053 events insert are L1 28/28, 攻 45, 速 14 on the pmEnemy
## side. The pre-baked STORY roster (script_insert) and the runtime insert request must agree.
func adjust_level_zero_story_and_runtime() -> void:
	var loop := BattlePlayLoop.initialize_roster_growth(BattlePlayLoop.create([], "", BattlePlayLoop.BattleScenario.load_file("res://content/battles/battle_053.json")))
	check(loop["scenario_ok"], "level 53 roster births: " + str(loop.get("scenario_error", "")))
	var measured := {"level": 1, "max_hp": 28, "attack": 45, "speed": 14}
	for id in ["enemy023_2", "enemy023_3"]:
		var guard := BattlePlayLoop.unit(loop, id)
		var birth: Dictionary = guard.get("entry_growth", {})
		check(halves(guard.get("script_insert", {}).get("adjust_level", [])) == [0, 0] and birth.get("origin") == "initial_roster", "STORY053 pursuer %s carries the 0,0 halves into its initial birth" % id)
		check(halves(birth.get("input", {}).get("parameters", [])) == [0, 0] and (birth.get("draws", []) as Array).is_empty() and not bool(birth.get("result", {}).get("raised", true)), "0,0 halves draw nothing and raise nothing: " + id)
		check(int(guard["level"]) == measured["level"] and int(guard["max_hp"]) == measured["max_hp"] and int(guard["hp"]) == measured["max_hp"], "%s is L1 28/28 like the original pursuer" % id)
		check(int(guard["combat_profile"]["live_attack_damage"]) == measured["attack"] and int(guard["live_speed"]) == measured["speed"], "%s attacks 45 at speed 14 like the original pursuer" % id)
	var gate := BattlePlayLoop.unit(loop, "enemy023_1")
	check(not gate.has("script_insert") and halves(gate["entry_growth"]["input"]["parameters"]) == [0, 0] and int(gate["evef_instance"]["overrides"]["level_adjust_range"]) == 0, "the EVEF gate guard takes its 0,0 halves from EVEF words 16／17, not from a STORY token")
	# The same token folded into a runtime insert request (WINFAIL053 event0／event1 shape).
	var runtime := fixture("023", [0, 0])
	BattleLoopScript.maintain_script_pressure(runtime)
	check(runtime["scenario_ok"] and created(runtime).size() == 1, "runtime 023 insert under 0,0 births: " + str(runtime.get("scenario_error", "")))
	if runtime["scenario_ok"] and created(runtime).size() == 1:
		var recruit: Dictionary = created(runtime)[0]
		check(halves(recruit["entry_growth"]["input"]["parameters"]) == [0, 0] and recruit["entry_growth"]["origin"] == "script" and (recruit["entry_growth"]["draws"] as Array).is_empty(), "runtime insert request carries the 0,0 halves")
		check(int(recruit["level"]) == measured["level"] and int(recruit["max_hp"]) == measured["max_hp"] and int(recruit["combat_profile"]["live_attack_damage"]) == measured["attack"] and int(recruit["live_speed"]) == measured["speed"], "runtime 0,0 insert equals the pre-baked pursuer: L1 28 HP 攻 45 速 14")


## Level 6 (席達鎮) two-phase opening adjustment, static-derived
## (docs/evidence_packets/static_reverse/original_auto_growth.md): 0x40e7a0 averages the
## players registered in 0x4c34c0 when an object first ticks. STORY006 inserts the four
## players (obj_Story_PlayerN), so the EVEF villagers／soldiers born on frame 1 see an empty
## registry (average 1); the inserted 023×3／024 see all four. actAdjustAllPlayerLevel
## (opcode 73 → 0x4c1d48) then re-runs 0x40e870 once for everyone on the raised live words.
func level6_two_phase_adjustment() -> void:
	var scenario: Dictionary = BattlePlayLoop.BattleScenario.load_file("res://content/battles/battle_006.json")
	var created_loop := BattlePlayLoop.create([], "", scenario)
	var loop := BattlePlayLoop.initialize_roster_growth(created_loop)
	check(loop["scenario_ok"], "level 6 roster births: " + str(loop.get("scenario_error", "")))
	if not loop["scenario_ok"]: return
	var players := ["leonard", "tina", "hu", "hanks"]
	var party: Array = players.map(func(id): return int(BattlePlayLoop.unit(loop, id)["level"]))
	for index in range(players.size()):
		var player := BattlePlayLoop.unit(loop, players[index])
		check(int(player["opening_birth"]["story_insert"]) == index + 1 and not player.has("entry_growth") and not player.has("entry_readjust"), "obj_Story_Player%d %s is STORY insert #%d; kind3 is never randomly adjusted" % [index + 1, players[index], index + 1])
	var evef: Array = []
	var inserted: Array = []
	for actor in loop["units"]:
		if actor["growth_profile"]["allocation"] == "manual": continue
		(inserted if actor.get("opening_birth", {}).has("story_insert") else evef).append(actor["id"])
	check(evef.size() == 19 and inserted == ["guard023_1", "guard023_2", "guard023_3", "guard024_1"], "19 EVEF units and the four STORY-inserted soldiers: %s" % [inserted])
	for id in evef + inserted:
		var actor := BattlePlayLoop.unit(loop, id)
		var birth: Dictionary = actor["entry_growth"]
		var again: Dictionary = actor.get("entry_readjust", {})
		var expected_birth_party: Array = party if inserted.has(id) else []
		check(birth["origin"] == "initial_roster" and birth["input"]["party_levels"] == expected_birth_party, "%s births against %s (EVEF frame 1 = empty registry, average 1; STORY insert = the four players)" % [id, expected_birth_party])
		check(again.get("origin") == EntryGrowthRules.READJUST_ORIGIN and again.get("input", {}).get("party_levels") == party and again.get("party_ids") == players, "%s is re-adjusted once by opcode 73 against the four players" % id)
		if again.is_empty(): continue
		for key in ["level", "exp", "stamina", "kill_exp", "gold", "attributes"]:
			check(again["input"][key] == birth["result"][key], "%s re-adjust starts from the birth's raised %s" % [id, key])
		check(halves(again["input"]["parameters"]) == halves(birth["input"]["parameters"]) and again["result"]["source_level"] == EntryGrowthRules.inferred_level(birth["result"]["attributes"]), "%s keeps its +0x1f8 halves and re-infers the base level from raised attributes" % id)
		check(int(again["result"]["level"]) >= int(birth["result"]["level"]) and int(actor["level"]) == int(again["result"]["level"]) and int(actor["hp"]) == int(actor["max_hp"]), "%s only ever rises: L%d → L%d" % [id, int(birth["result"]["level"]), int(again["result"]["level"])])
	var receipt: Dictionary = loop["initial_roster_growth"]
	check(receipt.get("readjusted") == receipt["npcs"] and receipt["npcs"].size() == 23, "every NPC alive at opcode 73 is re-adjusted once, in roster order")
	# Distribution over stream starts: the EVEF 023 (halves 18／2) births at average 1
	# (1..3) then re-adjusts at average 3 (1 + rand(4) + rand(2) = 1..5); the inserted 023
	# draw 1..5 twice. E[max(U1..3, T)] ≈ 3.21 and E[max(T, T)] ≈ 3.69 (one adjustment at
	# average 3 gives both 3.0; birth only gives EVEF 2.0).
	var sums := {"evef": 0, "inserted": 0}
	var counts := {"evef": 0, "inserted": 0}
	for start in range(1, 41):
		var trial := created_loop.duplicate(true)
		seed_stream(trial, "global", start * 7919)
		var grown := BattlePlayLoop.InitialRosterGrowth.prepare(trial)
		if not grown["ok"]: check(false, "level 6 births from stream start %d: %s" % [start, grown.get("reason")]); return
		for actor in grown["loop"]["units"]:
			if actor["actor_id"] != "023": continue
			var group := "inserted" if actor.get("opening_birth", {}).has("story_insert") else "evef"
			sums[group] += int(actor["level"]); counts[group] += 1
	var evef_mean: float = float(sums["evef"]) / int(counts["evef"])
	var inserted_mean: float = float(sums["inserted"]) / int(counts["inserted"])
	check(inserted_mean > 3.45 and evef_mean > 2.95 and evef_mean < 3.45 and inserted_mean - evef_mean > 0.25, "inserted 023 average L%.2f above EVEF 023 L%.2f over 40 stream starts" % [inserted_mean, evef_mean])
	# Level 6 units survive save／load; the receipt and chain reject tampering.
	var live := BattlePlayLoop.begin_battle(loop)
	var saved := BattleCheckpoint.encode(live, VIEW)
	check(saved["ok"], "level 6 two-phase receipts can be saved: " + str(saved.get("reason")))
	if saved["ok"]:
		var restored := BattleCheckpoint.decode(saved["bytes"], live)
		check(restored["ok"] and restored["snapshot"]["loop"] == live, "restore keeps every level 6 unit's two-phase levels")
	for field in ["gains", "missing", "chain", "receipt"]:
		var broken := live.duplicate(true)
		var target := BattlePlayLoop.unit_ref(broken, "guard023_1")
		match field:
			"gains": target["entry_readjust"]["result"]["source_gains"]["hit_point"] += 1
			"missing": target.erase("entry_readjust")
			"chain": target["entry_readjust"]["input"]["gold"] += 10
			"receipt": broken["initial_roster_growth"].erase("readjusted")
		check(not BattleCheckpoint.encode(broken, VIEW)["ok"], "reject corrupted level 6 re-adjust " + field)


## Birth order marks change no other opening: levels whose STORY inserts only NPCs, and
## level 53 (緹娜 is obj_Story_Player2, but every 053 soldier carries 0,0 halves), give the
## same units with and without `opening_birth`.
func opening_birth_leaves_other_levels() -> void:
	for level in [1, 5, 13, 28, 37, 52, 53, 59]:
		var scenario: Dictionary = BattlePlayLoop.BattleScenario.load_file("res://content/battles/first_battle.json" if level == 1 else "res://content/battles/battle_%03d.json" % level)
		var plain := scenario.duplicate(true)
		for actor in plain["playable_units"]: actor.erase("opening_birth")
		var marked := BattlePlayLoop.initialize_roster_growth(BattlePlayLoop.create([], "", scenario))
		var unmarked := BattlePlayLoop.initialize_roster_growth(BattlePlayLoop.create([], "", plain))
		check(marked["scenario_ok"] and unmarked["scenario_ok"] and no_draw(marked, unmarked, "global") and not marked["initial_roster_growth"].has("readjusted"), "level %d births spend the same stream with or without birth order marks" % level)
		for index in range(marked["units"].size()):
			var a: Dictionary = marked["units"][index]
			var b: Dictionary = unmarked["units"][index]
			check(not a.has("entry_readjust") and a["level"] == b["level"] and a["max_hp"] == b["max_hp"] and a["kill_exp"] == b["kill_exp"] and a["combat_profile"] == b["combat_profile"] and EntryGrowthRules.gold(a, -1) == EntryGrowthRules.gold(b, -1), "level %d %s is born identically" % [level, a["id"]])
	var gate := BattlePlayLoop.unit(BattlePlayLoop.initialize_roster_growth(BattlePlayLoop.create([], "", BattlePlayLoop.BattleScenario.load_file("res://content/battles/battle_053.json"))), "enemy023_1")
	check(gate["entry_growth"]["input"]["party_levels"] == [] and gate["entry_growth"]["draws"].is_empty(), "level 53's EVEF gate guard is born before obj_Story_Player2 registers (empty registry; its 0,0 halves draw nothing)")


## The user's first-battle recording (99.5 s／151.5 s close-ups) shows friendly 023_2 at
## level 3 with 41/41 HP. The opening level-up 0x40e870 explains it from the PLAYERS 023
## template (base level 1, halves 18／2, party average 1): target 1 + rand(3) + rand(1) is
## 1..3, and level 3 with the source HP draw ≥ 50 gives 41 HP at speed 16. Only the random
## stream differs; this global stream start (seeded(4)) is one that lands there.
func first_battle_recorded_levels() -> void:
	var loop := BattlePlayLoop.create([], "", BattlePlayLoop.BattleScenario.load_file("res://content/battles/battle_051.json"), 1)
	var template: Dictionary = BattlePlayLoop.unit(loop, "actor023_2")
	check(int(template["level"]) == 1 and int(template["max_hp"]) == 29 and int(template["live_speed"]) == 14, "PLAYERS 023 template: L1 29 HP speed 14 before the opening level-up")
	seed_stream(loop, "global", 4)
	var born: Dictionary = ReinforcementGrowthRules.prepare(loop, template, {}, "initial_roster")
	check(born["ok"], "023 opening birth: " + str(born.get("reason", "")))
	if born["ok"]:
		var grown: Dictionary = born["actor"]
		var birth: Dictionary = grown["entry_growth"]
		check(halves(birth["input"]["parameters"]) == [18, 2] and birth["input"]["party_levels"] == [1] and birth["draws"][0] == {"bound": 3, "value": 2}, "0x40e870 for 023: halves 18／2, party [1], target draw rand(3) = 2")
		check(int(grown["level"]) == 3 and int(grown["max_hp"]) == 41 and int(grown["hp"]) == 41 and int(grown["live_speed"]) == 16, "the recorded 023_2 (L3, 41/41) is an outcome of the opening level-up: L%d %d HP speed %d" % [int(grown["level"]), int(grown["max_hp"]), int(grown["live_speed"])])


static func halves(values: Array) -> Array:
	return values.map(func(value): return int(value)) # campaign JSON carries the pair as floats


func spawn_and_restore() -> void:
	for code in ["021","026","028","036","039"]:
		var loop:=fixture(code)
		var prior:=loop.duplicate(true)
		BattleLoopScript.maintain_script_pressure(loop)
		check(loop["scenario_ok"] and created(loop).size()==1,"one valid adjusted recruit: "+code+" "+str(loop.get("scenario_error")))
		if not loop["scenario_ok"] or created(loop).is_empty():continue
		var actor:Dictionary=created(loop)[0]
		check(actor["level"]>=actor["entry_growth"]["result"]["source_level"] and actor["hp"]==actor["max_hp"] and actor["mp"]==actor["max_mp"],"native birth completes before first action")
		check(actor["ai_wait_remaining"]==2 and actor["permanent_gains"]==prior["reinforcement_templates"][0]["permanent_gains"],"script waiting and permanent layer remain independent")
		var before:=loop.duplicate(true);BattleLoopScript.maintain_script_pressure(loop)
		check(loop==before,"repeated pressure creates no duplicate actor or global draw")
		var saved:=BattleCheckpoint.encode(loop,VIEW)
		check(saved["ok"],"birth receipt and RNG chain can be saved: "+str(saved.get("reason")))
		if saved["ok"]:
			var restored:=BattleCheckpoint.decode(saved["bytes"], loop)
			check(restored["ok"] and restored["snapshot"]["loop"]==loop,"F9-equivalent restore preserves exact birth and order")
		for field in ["result","missing","stats","kill","profile"]:
			var broken:=loop.duplicate(true);var target:=BattlePlayLoop.unit_ref(broken,actor["id"])
			match field:
				"result":target["entry_growth"]["result"]["source_gains"]["speed"]+=1
				"missing":target.erase("entry_growth")
				"stats":target["combat_profile"]["live_attack_damage"]+=1
				"kill":target["kill_exp"]+=1
				"profile":target["growth_profile"]="corrupt"
			check(not BattleCheckpoint.encode(broken,VIEW)["ok"],"reject corrupted birth "+field)
	var blocked:=fixture("039")
	blocked["reinforcement_spawn_cells"]=[blocked["units"][0]["coord"]]
	var seed:Array=stream_of(blocked, "global").duplicate()
	BattleLoopScript.maintain_script_pressure(blocked)
	check(created(blocked).is_empty() and stream_of(blocked, "global")==seed,"blocked footprint does not spend creation RNG")
	blocked["reinforcement_spawn_cells"]=[Vector2i(8,8)]
	BattleLoopScript.maintain_script_pressure(blocked)
	check(created(blocked).size()==1,"opening a complete footprint lets the pending insertion initialize once")
	var invalid:=fixture()
	request(invalid,"026",[-1,0])
	var before:Dictionary=invalid.duplicate(true)
	BattleLoopScript.maintain_script_pressure(invalid)
	check(not invalid["scenario_ok"] and invalid["units"]==before["units"] and no_draw(invalid, before, "global"),"later invalid insertion rolls back this entire spawn batch")
	var unadjusted:=fixture("026",[0,0])
	var zero_start:Array=stream_of(unadjusted, "global").duplicate()
	BattleLoopScript.maintain_script_pressure(unadjusted)
	# The birth 0x407cc0 still draws the frame delay rand(24) (0x407dba) and rolls the pmEnemy
	# carry (0x407c86, global stream) before the suppressed adjustment 0x40e870: the stream moves
	# by exactly those draws and no more.
	var carry_only:Array=BattleRewardRules.carry(unadjusted["reward_data"]["actors"]["026"]["carry_items"], GlobalRandomStream.advance(zero_start, 1))["state"]
	check(created(unadjusted)[0]["entry_growth"]["draws"].is_empty() and stream_of(unadjusted, "global")==carry_only,"explicit source zero suppresses randomized adjustment and preserves inferred level; only the birth carry roll draws")

func layering_and_rewards() -> void:
	var loop:=fixture("026",[20,0],20);BattleLoopScript.maintain_script_pressure(loop)
	var id:String=created(loop)[0]["id"];var actor:=BattlePlayLoop.unit_ref(loop,id)
	var birth:Dictionary=actor["entry_growth"].duplicate(true)
	var source:Dictionary=actor["growth_profile"]["source"].duplicate(true)
	var original_attack:int=actor["combat_profile"]["live_attack_damage"]
	actor["permanent_gains"]["attack_power"]=7
	actor=BattlePlayLoop.ProgressionRules.refresh_growth_stats(actor,loop["equipment_items"])
	check(actor["combat_profile"]["live_attack_damage"]==original_attack+7 and actor["entry_growth"]==birth and actor["growth_profile"]["source"]==source,"permanent acquisition neither overwrites nor reapplies entry increments")
	actor["status_flags"]|=16;actor["status_counters"]["attack_up"]=10<<16|2
	actor=BattlePlayLoop.ProgressionRules.refresh_growth_stats(actor,loop["equipment_items"])
	check(actor["combat_profile"]["live_attack_damage"]==original_attack+17,"temporary enhancement adds independently")
	run_mobile_jobs_tests.run_weapon_effect_tests.set_gear(actor,loop["equipment_items"],"accessory1",233)
	var equipped:=BattlePlayLoop.ProgressionRules.refresh_growth_stats(actor,loop["equipment_items"])
	check(equipped["entry_growth"]==birth and equipped["permanent_gains"]==actor["permanent_gains"],"gear refresh does not resample entry or permanent values")
	actor["growth_profile"]["allocation"]="manual";actor["exp"]=BattlePlayLoop.ProgressionRules.exp_to_next(actor["level"])-1
	var advanced:=BattlePlayLoop.ProgressionRules.resolve_experience(actor,1,loop["equipment_items"])
	check(advanced["level"]==actor["level"]+1 and advanced["entry_growth"]==birth and advanced["growth_profile"]["source"]==source,"later manual EXP growth keeps birth-source layer")
	var after:=BattlePlayLoop.StatusEffectRules.after_action(actor)
	actor.merge(after["changes"],true);after=BattlePlayLoop.StatusEffectRules.after_action(actor);actor.merge(after["changes"],true)
	actor=BattlePlayLoop.ProgressionRules.refresh_growth_stats(actor,loop["equipment_items"])
	check(actor["combat_profile"]["live_attack_damage"]==original_attack+7,"enhancement expiration restores remaining permanent/birth contributions")
	BattlePlayLoop.unit_ref(loop,id).merge(actor,true)
	var owner:=BattlePlayLoop.unit_ref(loop,loop["player_unit_id"])
	owner["coord"]=created(loop)[0]["coord"]+Vector2i(-1,0);owner["hit_bonus_accum"]=1000
	owner["combat_profile"]["live_attack_damage"]=50000
	BattlePlayLoop.unit_ref(loop,id)["no_attack"]=true
	loop=BattlePlayLoop.return_to_player(loop,owner["id"])
	loop=BattlePlayLoop.attack_target(BattlePlayLoop.choose_command(loop,"attack"),id,zero)
	check(BattlePlayLoop.unit(loop,id)["defeated"] and loop["last_combat"]["rewards"]["gold"]==birth["result"]["gold"],"actual kill uses adjusted instance gold")
	check(loop["last_attack"].get("experience_basis",{}).get("kill_exp")==birth["result"]["kill_exp"],"actual final EXP contribution uses adjusted target kill EXP")

func phase_and_campaign() -> void:
	var scenario_fixture = load("res://tests/EntryGrowthFixture.gd")
	var setup:Dictionary=scenario_fixture.build("mage")
	var struck:Dictionary=BattlePlayLoop.attack_target(BattlePlayLoop.choose_command(setup["loop"],"attack"),setup["target_id"],zero)
	check(struck["scenario_ok"] and created(struck).is_empty(),"the strike itself scans nothing: the attacked insertion waits for the completion scan")
	# The fixture's leader acts twice (Mobile.fixture twice=true): the first half's repeat
	# re-enters phase 0, which clears the attacker global, so only the second half is read.
	var repeat:Dictionary=BattlePlayLoop.finish_exhausted_action(struck)
	check(repeat["extra_action"]["pending"] and created(repeat).is_empty(),"the first half of the extra action completes without a scan")
	var fired:Dictionary=BattlePlayLoop.finish_exhausted_action(BattlePlayLoop.attack_target(BattlePlayLoop.choose_command(repeat,"attack"),setup["target_id"],zero))
	check(fired["scenario_ok"] and created(fired).size()==1,"attack-triggered insertion is born at the attack action's completion scan: mage")
	check(not BattleOutcome.decided(fired),"the new roster prevents premature clear victory")
	var cleared:Dictionary=BattlePlayLoop.attack_target(BattlePlayLoop.choose_command(scenario_fixture.build("victory")["loop"],"attack"),"enemy026_1",zero)
	check(BattleOutcome.won(cleared) and created(cleared).is_empty(),"a killing blow on the last enemy decides the clear victory before its attacked insertion (0x44ee20 scans win before events)")
	var pending:Dictionary=_attacked_insert_requested(scenario_fixture.build("victory")["loop"])
	var held:Dictionary=BattlePlayLoop.attack_target(BattlePlayLoop.choose_command(pending,"attack"),"enemy026_1",zero)
	check(created(held).is_empty() and no_draw(held, pending, "global") and not BattleOutcome.decided(held),"blocked pending reinforcements do not become an empty-roster victory or consume birth RNG")
	var loop:=fixture();BattleLoopScript.maintain_script_pressure(loop)
	var original:=loop.duplicate(true)
	loop=BattlePlayLoop.choose_command(loop,"move")
	loop=BattlePlayLoop.cancel_interaction(loop)
	loop=BattlePlayLoop.choose_command(loop,"attack")
	loop=BattlePlayLoop.cancel_interaction(loop)
	check(no_draw(loop, original, "global") and created(loop)==created(original),"cancel/reselect cannot rerun a settled birth or its random draws")
	var config:=BattlePlayLoop.BattleScenario.load_file(run_mobile_jobs_tests.PATH)
	var next:=BattlePlayLoop.apply_campaign_carry(BattlePlayLoop.create([],"",config),BattlePlayLoop.CampaignCarryRules.capture(loop))
	check(next["campaign_carry_receipt"]["errors"].is_empty() and stream_of(next, "global")==GlobalRandomStream.seeded(1) and created(next).is_empty(),"cross-battle carries party growth but neither the old enemy instances nor the global stream (the next battle keeps its own start)")
	for outcome in [BattleOutcome.VICTORY_ENEMIES_CLEARED,BattleOutcome.DEFEAT_FALLEN,BattleOutcome.VICTORY_ESCAPE]:
		var terminal:=loop.duplicate(true);terminal["battle_outcome"]=outcome;terminal["interaction"]="battle_result"
		var before:=terminal.duplicate(true);BattleLoopScript.maintain_script_pressure(terminal)
		check(before==terminal and BattlePlayLoop.step_ai_turn(terminal)==terminal,"terminal forbids new initialization or subsequent AI: "+BattleOutcome.describe(outcome))

func pending_class_victory() -> void:
	var scenario_fixture = load("res://tests/EntryGrowthFixture.gd")
	check(WinfailScenarioRules.outcome_for({"kind":"win","conditions":[{"name":"actCheckEnemyNumber","args":["SID_ENEMY026","1"]}]})==BattleOutcome.VICTORY_BOSS,"a class objective uses the existing target-victory result instead of an unlabelled generic result")
	for token in ["SID_ENEMY026", "SID_ENEMY027", "SID_SEED"]:
		var pending:Dictionary=scenario_fixture.build("victory")["loop"]
		pending["winfail_runtime"]["actor_bindings"]["SID_SEED/1"]="enemy026_1"
		pending["winfail_script_rules"]["statuses"]["win"][0]["conditions"]=[
			{"name":"actTRUE","args":[],"supported":true},
			# actCheckEnemyNumber holds when the registered count is strictly below num
			# (0x450840 case 0x24): "fewer than one" means the class is gone.
			{"name":"actCheckEnemyNumber","args":[token,"1"],"supported":true}]
		pending=_attacked_insert_requested(pending)
		var held:=BattlePlayLoop.attack_target(BattlePlayLoop.choose_command(pending,"attack"),"enemy026_1",zero)
		check(held["scenario_ok"] and created(held).is_empty() and no_draw(held, pending, "global"),"blocked class-count route neither creates nor samples: "+token)
		if token!="SID_ENEMY026":
			check(held["battle_outcome"]==BattleOutcome.VICTORY_SCRIPT,"unrelated class and exact-instance victory do not wait for a different pending population: "+token)
			continue
		check(not BattleOutcome.decided(held) and held["winfail_runtime"]["resolved"].is_empty(),"matching class-count victory must wait for the blocked new roster")
		var current:=held.duplicate(true)
		BattleLoopScript.maintain_script_pressure(held)
		check(held==current,"polling blocked matching-class victory cannot mutate the event or random stream")
		held["reinforcement_spawn_cells"]=[Vector2i(16,16)]
		BattleLoopScript.maintain_script_pressure(held)
		held=BattlePlayLoop.resolve_outcome(held)
		check(created(held).size()==1 and not BattleOutcome.decided(held),"unblocked same-class recruit is considered before class victory")
		for ending in ["escape","defeat"]:
			var ended:=current.duplicate(true)
			if ending=="escape":
				var actor:=BattlePlayLoop.unit(ended,ended["player_unit_id"])
				ended["winfail_script_rules"]["statuses"]["win"][0]["conditions"]=[{"name":"actCheckPlayerArrivePos","args":["SID_PLAYER0","1",str(actor["coord"].x*32),str(actor["coord"].y*32),str(actor["coord"].x*32+31),str(actor["coord"].y*32+31)],"supported":true}]
			else:
				ended["winfail_script_rules"]["statuses"]["fail"][0]["conditions"]=[{"name":"actCheckPlayer","args":["1","SID_PLAYER0"],"supported":true}]
				BattlePlayLoop.set_unit_defeated(ended,ended["player_unit_id"],true)
			check(WinfailScenarioRules.victory_state(ended)==(BattleOutcome.VICTORY_ESCAPE if ending=="escape" else WinfailScenarioRules.DEFEAT_OUTCOME),"pending class cannot suppress independent "+ending)

## The attacked insertion (EntryGrowthFixture event 901) requested by an earlier attack
## action's completion scan, with its spawn cell blocked by the leader: the insert stays
## owed while the leader's next strike kills the last enemy.
func _attacked_insert_requested(loop:Dictionary)->Dictionary:
	loop["reinforcement_spawn_cells"]=[BattlePlayLoop.unit(loop,loop["player_unit_id"])["coord"]]
	loop["last_attack"]={"attacker_id":loop["player_unit_id"],"defender_id":"enemy026_1"}
	var next:Dictionary=BattlePlayLoop.resolve_outcome(BattlePlayLoop.BattleScenarioRuleAdapter.run_event_hooks(loop,true))
	check(next["winfail_runtime"]["fired"].any(func(entry): return entry["key"]=="event_901") and not BattlePlayLoop.BattleScenarioRuleAdapter.reinforcement_deficits(next).is_empty(),"the attacked insertion is requested and owed behind its blocked spawn cell")
	return next
