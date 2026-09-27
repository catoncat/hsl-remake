extends RefCounted
## Declared source-terrain encounters. All growth happens at the real spawn seam.
const TestSuite = preload("res://tests/support/TestSuite.gd")
const T = preload("res://tests/run_entry_growth_tests.gd")
const Loop = preload("res://game/battle/scene/BattlePlayLoop.gd")
const Mobile = preload("res://tests/run_mobile_jobs_tests.gd")
const Events = preload("res://tests/ScriptDepartureFixture.gd")
const Rules = preload("res://game/sim/WinfailScenarioRules.gd")

static func build(mode: String) -> Dictionary:
	var loop := Mobile.fixture("006" if mode in ["wing","states"] else "004", true)
	var leader := Loop._unit(loop,loop["player_unit_id"])
	var priest := Loop._unit(loop,"tina")
	var seed := Loop._unit(loop,"enemy026_1")
	var code: String = {"thief":"028","wing":"036","large":"039","blocked":"039"}.get(mode,"026")
	var template := T.source_actor(code)
	template.merge({"class_id":"Enemy"+code,"battle_actor_role":Loop.ROLE_ENEMY,"player_commandable":false,
		"pending_stat_points":0,"exp":0,"no_attack":false,"inventory":[0,0,0,0,0,0,0,0]},true)
	template["growth_profile"]["allocation"] = "fixed_template"
	var center := Vector2i(18,16) if code == "039" or mode == "states" else Vector2i(16,16)
	priest["coord"] = Vector2i(12,18)
	if mode in ["blocked","class_blocked"]: priest["coord"] = center
	for actor in [leader,priest]:
		actor["level"] = 12
		actor["inventory"] = [232,241,247,253,257,0,0,0]
	leader["permanent_gains"]["defense"] = 5
	if mode == "states":
		leader["mp"] = 0
		leader.merge(Loop.StatusEffectRules.apply(leader,"no_magic",3)["changes"],true)
		leader.merge(Loop.StatusEffectRules.apply(leader,"poison",3,5)["changes"],true)
	if mode == "paralysis":
		template.merge(Loop.StatusEffectRules.apply(template,"paralysis",2)["changes"],true)
		template["status_counters"]["paralysis"] = 1
		template.merge(Loop.StatusEffectRules.apply(template,"no_magic",3)["changes"],true)
		template.merge(Loop.StatusEffectRules.apply(template,"poison",3,5)["changes"],true)
	if mode in ["mage","repeat","paralysis"]: Mobile.Gear.set_gear(template,loop["equipment_items"],"accessory2",227)
	var profile:Dictionary=TestSuite.own(loop, "ai_profiles")["actors"][code]["profile"]
	profile.merge({"find_range":20,"ai_lock":0,"ai_call_range":0,"ai_check_dying":0,"ai_check_hp":0,"ai_help_otherhp":0,"ai_help_status":0,"ai_help_attack":0,"ai_att_special":0,"ai_att_magic":100},true)
	if code == "026":
		TestSuite.own(loop, "skill_book")["actors"][code]["supported_initial_ids"]=[Mobile.WIND]
		TestSuite.own(loop, "skill_book")["skills"]["magic:magicAIR:magicCode01"]["fields"]["use_ratio"]="100"
	if mode == "defeat":
		leader["hp"]=1
		template["growth_profile"]["source"]["attack_power"]=5000
		template["growth_profile"]["source"]["hit_point"]+=2000
		template["hit_bonus_accum"]=1000
		template.merge(Loop.StatusEffectRules.apply(template,"no_magic",3)["changes"],true)
		profile["ai_att_magic"]=0
	if mode in ["victory","class_blocked"]:
		seed["hp"]=1
		leader["exp"]=Loop.ProgressionRules.exp_to_next(leader["level"])-1
		leader["growth_profile"]["source"]["attack_power"]=4000
	if mode == "support":
		leader["hp"]-=40
		loop["player_unit_id"]="tina"
		priest["growth_profile"]["source"]["speed"]=400
		priest["growth_profile"]["source"]["hit_point"]+=2000
		Mobile.Gear.set_gear(priest,loop["equipment_items"],"accessory2",227)
	var owner:Dictionary=priest if mode=="support" else leader
	var target:Dictionary=leader if mode=="support" else seed
	for actor in loop["units"]:
		actor.merge(Loop.ProgressionRules.refresh_growth_stats(actor,loop["equipment_items"]),true)
		if mode=="support" and actor["id"]=="tina":actor["hp"]=actor["max_hp"]
		actor["grid_coord"]=actor["coord"];actor["ai_home_coord"]=actor["coord"]
	template=Loop.ProgressionRules.refresh_growth_stats(template,loop["equipment_items"])
	loop["reinforcement_templates"]=[template]
	loop["reinforcement_spawn_cells"]=[center,Vector2i(17,17)]
	if mode=="class_blocked":loop["reinforcement_spawn_cells"]=[center]
	var config:=Loop.BattleScenario.load_file(Mobile.PATH).duplicate(true)
	var bindings:Dictionary={"SID_PLAYER0/1":{"unit_id":leader["id"],"actor_id":leader["actor_id"]},"SID_PLAYER1/1":{"unit_id":"tina","actor_id":"002"},"SID_ENEMY026/1":{"unit_id":seed["id"],"actor_id":"026"}}
	var owner_token:="SID_PLAYER1" if mode=="support" else "SID_PLAYER0"
	var target_token:="SID_PLAYER0" if mode=="support" else "SID_ENEMY026"
	var params:Array=[0,0] if mode=="zero" else [20,1]
	var actions:Array=[Events.command("actCheckPlayerAttacked",[owner_token,target_token]),
		Events.command("actInsertObject",["obj_recruit",center.x*32,(center.y+3)*32]),
		Events.command("actSetPrevInsertObjectAdjustLevel",params),
		Events.command("actSetPrevInsertObjectWaitRound",[2]),
		Events.command("actWalkPrevInsertObjectWait",[center.x*32,center.y*32,0])]
	if mode=="repeat": actions.append(Events.command("actInsertEventStatus",[901]))
	if mode=="defeat": actions.append(Events.command("actDeleteObject",["SID_ENEMY026",1]))
	var win_condition:=Events.command("actCheckEnemyTotalNumber",[0]) if mode=="victory" else Events.command("actCheckRoundNumber",[9999])
	if mode=="class_blocked":win_condition=Events.command("actCheckEnemyNumber",["SID_ENEMY026",1])
	if mode in ["escape","carry"]:win_condition=Events.command("actCheckPlayerArrivePos",[owner_token,1,13*32,16*32,13*32+31,16*32+31])
	var seed_data:Dictionary={"schema":"hsl_battle_seed.v1","level":999,"script_objects":[{"symbol":"obj_recruit","object_data_fields":{"obj_Data7":code}}],"scripts":{
		"story":{"sections":[{"name":"story","codes":[],"actions":[Events.command("actInsertEventStatus",[901]),Events.command("actInsertWinStatus",[0]),Events.command("actInsertFailStatus",[0])]}]},
		"winfail":{"sections":[Events.section("event",901,actions),Events.section("win",0,[win_condition]),Events.section("fail",0,[Events.command("actCheckPlayer",[1,owner_token if mode=="defeat" else "SID_MISSING"])])]}}}
	var events:Array=[{"id":"arrival_note","kind":"dialogue_message_id","actor_token":owner_token,"args":[owner_token,"1","369"],"message_id":"369","message_text":"增援到了。留意對手的等級與能力，再決定站位和出手時機。","speaker_name":"增援演練"}]
	config["opening"]={"actor_bindings":bindings,"speaker_resource_ids":{}}
	config["scenario_rules"]={"player_token":owner_token,"cell_size":32,"reinforcement_class_id":"Enemy"+code,
		"events":{"event901":{"inserts":[{"object_symbol":"obj_recruit","walk_cell_candidate":[center.x,center.y],"insert_xy":[center.x*32,(center.y+3)*32]}]}},
		"status_timelines":{"event_901":{"playable_event_count":events.size(),"events":events}}}
	loop["rule_adapter"]="winfail"
	loop=Rules.initialize_script_state(loop,config,seed_data)
	loop["turn_queue"]=Loop.CoreTurnQueue.rebuild(loop["units"])
	loop=Loop._return_to_player(loop,owner["id"])
	return {"loop":loop,"scenario":config,"owner_id":owner["id"],"target_id":target["id"],"code":code,"center":center,"parameters":params}
