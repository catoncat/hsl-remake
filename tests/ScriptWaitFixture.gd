extends RefCounted
## Authored encounter over existing source role/terrain data. No model decisions.
const TestSuite = preload("res://tests/support/TestSuite.gd")
const BattlePlayLoop = preload("res://game/sim/loop/BattlePlayLoop.gd")
const run_mobile_jobs_tests = preload("res://tests/run_mobile_jobs_tests.gd")
const ScriptDepartureFixture = preload("res://tests/ScriptDepartureFixture.gd")
const WinfailScenarioRules = preload("res://game/sim/WinfailScenarioRules.gd")
const FAR_MODES := ["guard", "double_guard", "wounded", "silenced", "paralyzed"]

static func build(mode: String) -> Dictionary:
	var loop := run_mobile_jobs_tests.fixture("006" if mode == "mage" else "004", mode in ["event", "sync", "depart", "mage"], mode == "defeat")
	var owner := BattlePlayLoop.unit_ref(loop,loop["player_unit_id"])
	var friend := BattlePlayLoop.unit_ref(loop,"tina")
	var foe := BattlePlayLoop.unit_ref(loop,"enemy026_1")
	friend["coord"] = Vector2i(14,15)
	owner["inventory"] = [232,241,244,253,0,0,0,0]
	foe["no_attack"] = false
	foe["inventory"] = [0,0,0,0,0,0,0,0]
	var profile: Dictionary = TestSuite.own(loop, "ai_profiles")["actors"]["026"]["profile"]
	profile.merge({"find_range":50,"ai_lock":0,"ai_call_range":0,"ai_check_dying":0,"ai_check_hp":0,"ai_help_otherhp":0,"ai_help_status":0,"ai_help_attack":0,"ai_att_special":0,"ai_att_magic":100},true)
	TestSuite.own(loop, "skill_book")["actors"]["026"]["supported_initial_ids"] = [run_mobile_jobs_tests.WIND]
	TestSuite.own(loop, "skill_book")["skills"]["magic:magicAIR:magicCode01"]["fields"]["use_ratio"] = "100"
	if mode in FAR_MODES:
		var selected := Vector2i(-1,-1)
		var best := 100000
		for cell in loop["tiles"]:
			var dist: int = absi(cell.x-owner["coord"].x)+absi(cell.y-owner["coord"].y)
			if dist < 12 or dist >= best: continue
			if maxi(absi(cell.x-owner["coord"].x),absi(cell.y-owner["coord"].y)) <= 9 or maxi(absi(cell.x-friend["coord"].x),absi(cell.y-friend["coord"].y)) <= 9: continue
			var proposal := foe.duplicate(true); proposal["coord"] = cell
			if BattlePlayLoop.TraversalRules.placement_error(proposal,loop["units"],loop["tiles"],loop["map_size"]) != "": continue
			selected = cell; best = dist
		assert(selected != Vector2i(-1,-1), "source map has a legal separated guard position")
		foe["coord"] = selected
		foe["ai_wait_remaining"] = 2
		if mode == "double_guard": run_mobile_jobs_tests.run_weapon_effect_tests.set_gear(foe,loop["equipment_items"],"accessory2",227)
		if mode == "wounded": foe["hp"] -= 1
		if mode in ["silenced","paralyzed"]:
			foe.merge(BattlePlayLoop.StatusEffectRules.apply(foe,"no_magic",2)["changes"],true)
			foe["mp"] = 0
			foe["inventory"] = [244,243,0,0,0,0,0,0]
			if mode == "paralyzed": foe.merge(BattlePlayLoop.StatusEffectRules.apply(foe,"paralysis",2)["changes"],true); foe["status_counters"]["paralysis"] = 1
	if mode == "support":
		loop["player_unit_id"] = "tina"
		friend["growth_profile"]["source"]["speed"] = 400
		friend["inventory"] = [232,241,253,0,0,0,0,0]
		owner["hp"] -= 30
		run_mobile_jobs_tests.run_weapon_effect_tests.set_gear(friend,loop["equipment_items"],"accessory2",227)
	if mode == "ai_chain":
		foe["hp"] -= 1
		foe["mp"] = 8
		foe["ai_wait_remaining"] = 2
		run_mobile_jobs_tests.run_weapon_effect_tests.set_gear(foe,loop["equipment_items"],"accessory2",227)
	if mode == "depart":
		var other := foe.duplicate(true); other.merge({"id":"enemy026_2","coord":Vector2i(14,17)},true); loop["units"].append(other)
	if mode in ["kill","victory"]:
		foe["hp"] = 1; owner["exp"] = 99
		if mode == "kill":
			var other := foe.duplicate(true); other.merge({"id":"enemy026_2","coord":Vector2i(18,17),"hp":other["max_hp"]},true); loop["units"].append(other)
	if mode == "defeat": owner["hp"] = 1; foe["growth_profile"]["source"].merge({"attack_power":5000,"attack_back":100},true)
	if mode == "event":
		TestSuite.own(loop, "skill_book")["actors"][owner["actor_id"]]["double_attack"] = true
		owner.merge(BattlePlayLoop.StatusEffectRules.apply(owner,"poison",3,5)["changes"],true)
		owner.merge(BattlePlayLoop.StatusEffectRules.apply(owner,"no_magic",3)["changes"],true)
	var config := BattlePlayLoop.BattleScenario.load_file(run_mobile_jobs_tests.PATH).duplicate(true)
	var bindings := {"SID_PLAYER0/1":{"unit_id":owner["id"],"actor_id":owner["actor_id"]},"SID_PLAYER1/1":{"unit_id":"tina","actor_id":"002"},"SID_ENEMY026/1":{"unit_id":"enemy026_1","actor_id":"026"}}
	var attacker_token := "SID_PLAYER1" if mode == "support" else "SID_PLAYER0"
	var target_token := "SID_PLAYER0" if mode == "support" else "SID_ENEMY026"
	var actions := [ScriptDepartureFixture.command("actCheckPlayerAttacked",[attacker_token,target_token]),ScriptDepartureFixture.command("actSetWaitRound",["SID_ENEMY026",1,2]),ScriptDepartureFixture.command("actWaitPlayer",["SID_ENEMY026",1])]
	if mode in ["event","depart"]: actions.append(ScriptDepartureFixture.command("actInsertEventStatus",[901]))
	if mode == "depart":
		actions.insert(2,ScriptDepartureFixture.command("actWalkAndDeleteWait",["SID_ENEMY026",1,16*32,18*32]))
	var win_condition := ScriptDepartureFixture.command("actCheckEnemyTotalNumber",[0]) if mode == "victory" else ScriptDepartureFixture.command("actCheckRoundNumber",[9999])
	if mode in ["escape","carry"]: win_condition = ScriptDepartureFixture.command("actCheckPlayerArrivePos",[attacker_token,1,13*32,16*32,13*32+31,16*32+31])
	var win_actions := [win_condition,ScriptDepartureFixture.command("actSetWaitRound",["SID_ENEMY026",1,7])]
	var fail_actions := [ScriptDepartureFixture.command("actCheckPlayer",[1,attacker_token if mode == "defeat" else "SID_MISSING"]),ScriptDepartureFixture.command("actSetWaitRound",["SID_ENEMY026",1,7])]
	var seed := {"schema":"hsl_battle_seed.v1","level":999,"scripts":{
		"story":{"sections":[{"name":"story","codes":[],"actions":[ScriptDepartureFixture.command("actInsertWinStatus",[0]),ScriptDepartureFixture.command("actInsertFailStatus",[0]),ScriptDepartureFixture.command("actInsertEventStatus",[901])]}]},
		"winfail":{"sections":[ScriptDepartureFixture.section("event",901,actions),ScriptDepartureFixture.section("win",0,win_actions),ScriptDepartureFixture.section("fail",0,fail_actions)]}}}
	var events: Array = [{"id":"wait_target","kind":"actor_action_wait","source_token":"actWaitPlayer","args":["SID_ENEMY026","1"],"cutscene_skip":true},
		{"id":"wait_message","kind":"dialogue_message_id","actor_token":attacker_token,"message_id":"369","message_text":"留意守備的時機；受傷或察覺近敵，都會讓對手重新行動。","speaker_name":"守備演練","args":[attacker_token,"1","369"]}]
	if mode == "sync":
		events = [{"id":"short_walk","kind":"actor_walk_disp","args":["SID_PLAYER1","1","32","0"]},
			{"id":"long_walk","kind":"actor_walk_disp","args":["SID_ENEMY026","1","0","224"]},
			{"id":"short_wait","kind":"actor_action_wait","args":["SID_PLAYER1","1"],"cutscene_skip":true},events[1],events[0]]
		actions.insert(2,ScriptDepartureFixture.command("actWaitPlayer",["SID_PLAYER1",1]))
	if mode == "depart": events.insert(0,{"id":"walk_out","kind":"actor_walk_and_delete_wait","source_token":"actWalkAndDeleteWait","args":["SID_ENEMY026","1",str(16*32),str(18*32)]})
	config["opening"] = {"actor_bindings":bindings,"speaker_resource_ids":{}}
	config["scenario_rules"] = {"player_token":attacker_token,"cell_size":32,"status_timelines":{"event_901":{"playable_event_count":events.size(),"events":events}}}
	loop["rule_adapter"] = "winfail"
	loop = WinfailScenarioRules.initialize_script_state(loop,config,seed)
	for actor in loop["units"]:
		actor.merge(BattlePlayLoop.ProgressionRules.refresh_growth_stats(actor,loop["equipment_items"]),true)
		actor["grid_coord"] = actor["coord"]; actor["ai_home_coord"] = actor["coord"]
	loop["turn_queue"] = BattlePlayLoop.CoreTurnQueue.rebuild(loop["units"])
	loop = BattlePlayLoop.return_to_player(loop,loop["player_unit_id"])
	return {"loop":loop,"scenario":config,"owner_id":loop["player_unit_id"],"first_id":loop["player_unit_id"],"target_id":owner["id"] if mode == "support" else "enemy026_1"}
