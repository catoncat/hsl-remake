extends RefCounted
## Authored status chains over the existing source-terrain/source-role trial.
## Setup is explicit; all later effects are triggered by ordinary player/AI acts.
const TestSuite = preload("res://tests/support/TestSuite.gd")
const BattlePlayLoop = preload("res://game/sim/loop/BattlePlayLoop.gd")
const run_mobile_jobs_tests = preload("res://tests/run_mobile_jobs_tests.gd")
const run_large_actor_tests = preload("res://tests/run_large_actor_tests.gd")
const WinfailScenarioRules = preload("res://game/sim/WinfailScenarioRules.gd")
const run_weapon_effect_tests = preload("res://tests/run_weapon_effect_tests.gd")
const WIND := "magic:magicAIR:magicCode01"
const HEAL := "magic:magicWATER:magicCode06"

static func command(name: String, args: Array = []) -> Dictionary:
	return {"primary":name,"chain":[{"name":name,"args":args.map(func(a):return str(a))}]}

static func section(kind: String, code: int, actions: Array) -> Dictionary:
	return {"index":code,"name":kind,"codes":[str(code)],"messages":[],"actions":actions}

static func build(mode: String) -> Dictionary:
	var loop := run_mobile_jobs_tests.fixture("006" if mode in ["mage","blocked","ai"] else "004",true,mode == "defeat")
	var owner := BattlePlayLoop._unit(loop,loop["player_unit_id"])
	var friend := BattlePlayLoop._unit(loop,"tina")
	var foe := BattlePlayLoop._unit(loop,"enemy026_1")
	var config := BattlePlayLoop.BattleScenario.load_file(run_mobile_jobs_tests.PATH).duplicate(true)
	owner["inventory"] = [232,241,244,253,0,0,0,0]
	friend["coord"] = Vector2i(14,15)
	foe["mp"] = 0 if mode == "ai" else foe["mp"]
	if mode == "support":
		loop["player_unit_id"] = "tina"
		var previous: Dictionary = owner
		owner = friend; friend = previous
		owner["growth_profile"]["source"]["speed"] = 400
		friend["hp"] -= 30
		run_weapon_effect_tests.set_gear(owner,loop["equipment_items"],"accessory2",227)
		owner["inventory"] = [232,241,244,0,0,0,0,0]
	if mode == "giant":
		var giant := run_large_actor_tests.source_large()
		giant["coord"] = Vector2i(16,16)
		giant["no_attack"] = true
		giant["inventory"] = [0,0,0,0,0,0,0,0]
		giant["growth_profile"]["source"]["hit_point"] += 4000
		giant.merge(BattlePlayLoop.ProgressionRules.refresh_growth_stats(giant,loop["equipment_items"]),true)
		giant["hp"] = giant["max_hp"]
		loop["units"][2] = giant; foe = giant
	if mode in ["blocked","second"]:
		owner["hp"] -= 35
		for key in ["poison","no_magic"]:owner.merge(BattlePlayLoop.StatusEffectRules.apply(owner,key,3,7 if key=="poison" else 0)["changes"],true)
	if mode == "blocked":owner["mp"] = 0
	if mode == "paralysis":
		owner.merge(BattlePlayLoop.StatusEffectRules.apply(owner,"paralysis",2)["changes"],true)
		owner["hp"] -= 35
		loop["player_unit_id"] = "tina"
		friend["growth_profile"]["source"]["speed"] = 400
	if mode in ["kill","victory"]:
		foe["hp"] = 1
		owner["exp"] = 99
	if mode == "defeat":
		owner["hp"] = 1
		foe["growth_profile"]["source"].merge({"attack_power":1000,"attack_back":100},true)
	if mode == "escape":foe["coord"] = Vector2i(18,16)
	if mode == "ai":
		owner["player_commandable"] = false;owner["battle_actor_role"] = BattlePlayLoop.ROLE_FRIENDLY;owner["no_attack"] = true
		friend["growth_profile"]["source"]["speed"] = 400
		loop["player_unit_id"] = "tina"
		# Player006 has no complete source AI strategy. This explicitly authored
		# controlled-AI route supplies every missing field; it is not a default grant.
		TestSuite.own(loop, "ai_profiles")["actors"]["006"]["missing_required"] = []
		TestSuite.own(loop, "ai_profiles")["actors"]["006"]["profile"].merge({"find_type":3,"find_range":12,"ai_call_range":4,"ai_fixed":0,"ai_lock":0,"ai_att_special":0,"ai_check_dying":0,"ai_check_hp":0,"ai_help_otherhp":0,"ai_help_status":0,"ai_help_attack":0,"ai_att_magic":100},true)
		TestSuite.own(loop, "skill_book")["skills"]["magic:magicAIR:magicCode01"]["fields"]["use_ratio"] = "100"
	if mode == "rearm":
		var other := foe.duplicate(true)
		other.merge({"id":"enemy026_2","coord":Vector2i(14,17)},true)
		loop["units"].append(other)
	for actor in loop["units"]:
		actor.merge(BattlePlayLoop.ProgressionRules.refresh_growth_stats(actor,loop["equipment_items"]),true)
		actor["grid_coord"] = actor["coord"];actor["ai_home_coord"] = actor["coord"]
	var retiring := owner if mode in ["second","ai","paralysis"] else friend if mode in ["support","kill","victory"] else foe
	var attacker := friend if mode == "paralysis" else owner
	var target := owner if mode == "paralysis" else friend if mode == "support" else foe
	var bindings := {}
	var tokens := {}
	for pair in [[owner,"SID_PLAYER0"],[friend,"SID_PLAYER1"],[foe,"SID_ENEMY"+str(foe["actor_id"])]]:
		bindings[pair[1]+"/1"] = {"unit_id":pair[0]["id"],"actor_id":pair[0]["actor_id"]}
		tokens[pair[0]["id"]] = pair[1]
	var departure_token: String = tokens[retiring["id"]]
	if mode == "rearm":bindings[departure_token+"/2"]={"unit_id":"enemy026_2","actor_id":foe["actor_id"]}
	var deletion := "actDeleteObject" if mode == "delete" else "actWalkAndDeleteWait"
	var destination: Vector2i = retiring["coord"] + Vector2i(0,2)
	var delete_args: Array = [departure_token,1] if mode == "delete" else [departure_token,1,destination.x*32,destination.y*32]
	var actions := [command("actCheckPlayerAttacked",[tokens[attacker["id"]],tokens[target["id"]]]),command("actMessage",[departure_token,1,369]),command(deletion,delete_args)]
	if mode == "rearm":actions.append(command("actInsertEventStatus",[901]))
	var condition := command("actCheckEnemyTotalNumber",[0]) if mode == "victory" else command("actCheckRoundNumber",[9999])
	if mode == "escape":condition = command("actCheckPlayerArrivePos",[tokens[owner["id"]],1,13*32,16*32,13*32+31,16*32+31])
	var win_actions := [condition]
	var fail_actions := [command("actCheckPlayer",[1,tokens[owner["id"]]] if mode == "defeat" else [1,"SID_MISSING"])]
	if mode == "escape":win_actions.append(command(deletion,delete_args))
	if mode == "defeat":fail_actions.append(command(deletion,delete_args))
	var seed := {"schema":"hsl_battle_seed.v1","level":999,"evidence_tier":"test-fixture","script_objects":[],"scripts":{
		"story":{"sections":[{"name":"story","codes":[],"messages":[],"actions":[command("actInsertWinStatus",[0]),command("actInsertFailStatus",[0]),command("actInsertEventStatus",[901])]}]},
		"winfail":{"sections":[section("event",901,actions if mode not in ["escape","defeat"] else [command("actCheckRoundNumber",[9999])]),section("win",0,win_actions),section("fail",0,fail_actions)]}}}
	var key := "win_0" if mode == "escape" else "fail_0" if mode == "defeat" else "event_901"
	var events: Array = []
	if mode not in ["escape","defeat"]:events.append({"id":"departure_message","kind":"dialogue_message_id","actor_token":departure_token,"message_id":"369","message_text":"先離開這裡，我們稍後再會合。","speaker_name":"離場演練","args":[departure_token,"1","369"]})
	events.append({"id":"departure_motion","kind":"actor_delete" if mode == "delete" else "actor_walk_and_delete_wait","source_token":deletion,"args":delete_args.map(func(a):return str(a))})
	events.append({"id":"departure_after","kind":"opening_delay","args":["4"]})
	config["opening"] = {"actor_bindings":bindings,"speaker_resource_ids":{}}
	config["scenario_rules"] = {"player_token":tokens[loop["player_unit_id"]],"cell_size":32,"status_timelines":{key:{"playable_event_count":events.size(),"events":events}}}
	loop["rule_adapter"] = "winfail"
	loop = WinfailScenarioRules.initialize_script_state(loop,config,seed)
	loop["turn_queue"] = BattlePlayLoop.CoreTurnQueue.rebuild(loop["units"])
	var first_id: String = friend["id"] if mode in ["ai","paralysis"] else owner["id"]
	loop = BattlePlayLoop._return_to_player(loop,first_id)
	return {"loop":loop,"scenario":config,"owner_id":owner["id"],"target_id":target["id"],"retiring_id":retiring["id"],"first_id":first_id,"attacker_id":attacker["id"]}
