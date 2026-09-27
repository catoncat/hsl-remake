extends "res://tests/support/TestSuite.gd"
const BattlePlayLoop = preload("res://game/sim/loop/BattlePlayLoop.gd")
const PoisonArrowRules = preload("res://game/sim/PoisonArrowRules.gd")
const BattleCheckpoint = preload("res://game/battle/runtime/BattleCheckpoint.gd")
const JobStatsRules = preload("res://game/sim/JobStatsRules.gd")
const ScriptDepartureFixture = preload("res://tests/ScriptDepartureFixture.gd")
const WinfailScenarioRules = preload("res://game/sim/WinfailScenarioRules.gd")
const BattleOutcome = preload("res://game/sim/BattleOutcome.gd")
const SCENE := "res://content/battles/ohm_village_battle.json"
const VIEW := {"camera":Vector2(512,608),"shown_story_events":[],"story_complete":true,"growth_notified_level":4}


func _init() -> void:
	tag = "OHM_VILLAGE_TESTS"


static func fresh(initialize: bool = true) -> Dictionary:
	var loop := BattlePlayLoop.create([], "", BattlePlayLoop.BattleScenario.load_file(SCENE))
	return BattlePlayLoop.initialize_roster_growth(loop) if initialize and loop["scenario_ok"] else loop

static func fixture() -> Dictionary:
	var loop := fresh()
	if not loop["scenario_ok"]: return loop
	var hu := BattlePlayLoop.unit_ref(loop,"hu")
	hu["growth_profile"]["source"]["speed"] += 300 # Explicit fast-turn fixture, not the formal level.
	hu.merge(BattlePlayLoop.ProgressionRules.refresh_growth_stats(hu,loop["equipment_items"]),true)
	hu["stamina"] = 40 # Actual formal scene remains ST0; fixture isolates paid special resolution.
	for pair in [["actor028_1",Vector2i(15,21)],["actor028_2",Vector2i(16,21)]]:
		var target := BattlePlayLoop.unit_ref(loop,pair[0])
		target["coord"] = pair[1]
		target["ai_home_coord"] = pair[1]
		target["growth_profile"]["source"]["hit_point"] += 800
		target.merge(BattlePlayLoop.ProgressionRules.refresh_growth_stats(target,loop["equipment_items"]),true)
		target["hp"] = target["max_hp"]
	loop["turn_queue"] = BattlePlayLoop.CoreTurnQueue.rebuild(loop["units"])
	return BattlePlayLoop.begin_battle(loop)

static func cast(loop: Dictionary, rng: Variant = null) -> Dictionary:
	var selected := BattlePlayLoop.choose_command(loop,"special")
	if selected["interaction"] == "special_select": selected = BattlePlayLoop.choose_special(selected,PoisonArrowRules.ID)
	return BattlePlayLoop.attack_target(selected,"actor028_1",rng,Vector2i(15,21))


static func ai_fixture(paralyzed: bool = false) -> Dictionary:
	# Explicit control/strategy fixture, not a newly inferred source003 AI default.
	# Hu keeps his own job, bow and declared special; no ability is copied from a mage.
	var loop := fixture()
	var hu := BattlePlayLoop.unit_ref(loop,"hu")
	hu["player_commandable"] = false
	hu["battle_actor_role"] = BattlePlayLoop.ROLE_FRIENDLY
	hu["stamina"] = 20
	hu["equipment"].append({"slot":"accessory2","item_code":227})
	hu.merge(BattlePlayLoop.ProgressionRules.refresh_growth_stats(hu,loop["equipment_items"]),true)
	var strategy: Dictionary = own(loop, "ai_profiles")["actors"]["003"]
	strategy["missing_required"] = []
	strategy["profile"].merge({"find_type":3,"find_range":20,"ai_call_range":6,"ai_fixed":0,"ai_lock":60,
		"ai_check_dying":0,"ai_check_hp":0,"ai_att_special":100},true)
	var leader := BattlePlayLoop.unit_ref(loop,"leonard")
	leader["growth_profile"]["source"]["speed"] += 500
	leader.merge(BattlePlayLoop.ProgressionRules.refresh_growth_stats(leader,loop["equipment_items"]),true)
	if paralyzed:
		hu.merge(BattlePlayLoop.StatusEffectRules.apply(hu,"paralysis",2)["changes"],true)
		hu["status_counters"]["paralysis"] = 1 # A valid application on its last remaining turn.
	else:
		hu.merge(BattlePlayLoop.StatusEffectRules.apply(hu,"no_magic",3)["changes"],true)
	loop["turn_queue"] = BattlePlayLoop.CoreTurnQueue.rebuild(loop["units"])
	return BattlePlayLoop.return_to_player(loop,"leonard")

static func insertion_fixture(code: String = "061") -> Dictionary:
	# Explicit event on the real village map. STORY001 itself contains no insert.
	var loop:=fixture()
	for id in ["hu","leonard"]:
		var actor:=BattlePlayLoop.unit_ref(loop,id)
		actor["level"]=12
		actor.merge(BattlePlayLoop.ProgressionRules.refresh_growth_stats(actor,loop["equipment_items"]),true)
	var hu:=BattlePlayLoop.unit_ref(loop,"hu")
	hu["equipment"].append({"slot":"accessory2","item_code":227})
	hu["permanent_gains"]["defense"]=5
	hu["exp"]=BattlePlayLoop.ProgressionRules.exp_to_next(12)-1
	hu["hit_bonus_accum"]=1000
	hu.merge(BattlePlayLoop.ProgressionRules.refresh_growth_stats(hu,loop["equipment_items"]),true)
	hu.merge(BattlePlayLoop.StatusEffectRules.apply(hu,"poison",3,6)["changes"],true)
	var template:=BattlePlayLoop.unit(fresh(false),"actor"+code+"_1").duplicate(true)
	loop["reinforcement_templates"]=[template]
	loop["reinforcement_spawn_cells"]=[Vector2i(14,21),Vector2i(14,22)]
	var config:=BattlePlayLoop.BattleScenario.load_file(SCENE).duplicate(true)
	var seed:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(config["resources"]["battle_seed"]))
	var symbol:="obj_Story_Level1_Enemy"+str(int(code))
	seed["scripts"]["story"]["sections"][0]["actions"].append(ScriptDepartureFixture.command("actInsertEventStatus",[901]))
	seed["scripts"]["winfail"]["sections"].append(ScriptDepartureFixture.section("event",901,[
		ScriptDepartureFixture.command("actCheckPlayerAttacked",["SID_琥","SID_ENEMY028"]),
		ScriptDepartureFixture.command("actInsertObject",[symbol,448,768]),
		ScriptDepartureFixture.command("actSetPrevInsertObjectAdjustLevel",[20,3]),
		ScriptDepartureFixture.command("actSetPrevInsertObjectWaitRound",[2]),
		ScriptDepartureFixture.command("actWalkPrevInsertObjectWait",[448,672,8]),
		ScriptDepartureFixture.command("actInsertEventStatus",[901])]))
	config["scenario_rules"]["events"]={"event901":{"inserts":[{"object_symbol":symbol,"walk_cell_candidate":[14,21],"insert_xy":[448,768]}]}}
	loop=WinfailScenarioRules.initialize_script_state(loop,config,seed)
	loop["turn_queue"]=BattlePlayLoop.CoreTurnQueue.rebuild(loop["units"])
	loop=BattlePlayLoop.return_to_player(loop,"hu")
	return {"loop":loop,"scenario":config,"code":code}

func run() -> void:
	var loop := fresh()
	check(loop["scenario_ok"],"real Ohm source scenario initializes: "+str(loop.get("scenario_error")))
	if not loop["scenario_ok"]: return
	native_stats()
	native_arrow()
	creation_and_range(loop)
	transactions()
	insertion_and_actions()
	double_bow()

func native_stats() -> void:
	var packet: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://docs/evidence_packets/static_reverse/original_ohm_growth.json"))
	var catalog: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://content/generated/hsl/equipment/items.json"))["items"]
	for row in packet["stats"]:
		var c: Dictionary = row["input"]
		# player_mode: the native rows ran with live +0x28 = the profile's mode word (0x448840 hp_level term).
		var actor := {"id":"native", "actor_id":c["actor"], "growth_profile":row["profile"].duplicate(true), "player_mode":int(row["profile"]["source"]["mode"]),
			"combat_profile":c["attributes"].duplicate(true), "level":int(c["level"]),"hp":int(c["hp"]),"max_hp":10000,"mp":int(c["mp"]),"max_mp":10000,
			"equipment":[],"base_move_point":int(c["base_move"]),"status_flags":0,"status_counters":{"poison":0,"paralysis":0,"no_magic":0},
			"permanent_gains":BattlePlayLoop.ProgressionRules.Permanent.empty(),"learned_skills":[]}
		actor["combat_profile"]["base_steal_ratio"] = 0  # 003／061／062 declare no PLAYERS steal_ratio (refresh input, not a receipt field)
		for index in range(6):
			if int(c["equipment"][index])>0: actor["equipment"].append({"slot":BattlePlayLoop.EquipmentRules.SLOTS[index],"item_code":int(c["equipment"][index])})
		var actual := BattlePlayLoop.ProgressionRules.refresh_growth_stats(actor,catalog)
		for expected in row["native"]:
			var values: Dictionary = expected["values"]
			for key in ["max_hp","max_mp","move_point"]:check(actual[key]==int(values[key]),"native own job result "+c["actor"]+" "+key)
			for pair in [["live_attack_damage","attack"],["live_defense","defense"],["live_magic_attack","magic_attack"],["live_hit_ratio","hit_rate"]]:
				check(actual["combat_profile"][pair[0]]==int(values[pair[1]]),"native independent derived component "+str(pair))
			check(actual["live_speed"]==int(values["speed"]),"native bow/villager speed")
			for element in range(5):check(actual["combat_profile"]["resist_by_type"][str(element)]==int(values["resist_by_type"][str(element)]),"native bow/villager resistance "+str(element))
		check(BattlePlayLoop.ProgressionRules.refresh_growth_stats(actual,catalog)==actual,"refresh cannot compound source/job/equipment")

func native_arrow() -> void:
	var packet: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://docs/evidence_packets/static_reverse/original_poison_arrow.json"))
	for row in packet["rolls"]:
		var draws: Array = row["draws"].duplicate(true)
		var result := PoisonArrowRules.roll(row["input"],func(bound):
			check(not draws.is_empty() and bound==int(draws[0]["bound"]),"original special channel1 exact draw boundary")
			return int(draws.pop_front()["value"]) if not draws.is_empty() else 0)
		check(draws.is_empty() and result["value"]==int(row["native"]["value"]) and result["hit_bonus_after"]==int(row["native"]["hit_bonus_after"]),"original special numeric full return")
	for row in packet["applications"]:
		var c: Dictionary = row["input"]
		var target := {"hp":int(c["hp"]),"status_flags":(1 if int(c["poison"]) else 0)|2,"status_counters":{"poison":int(c["poison"]),"paralysis":0,"no_magic":int(c["no_magic"])}}
		var draws: Array = row["draws"].duplicate(true)
		var actual := PoisonArrowRules.resolve({"input":c,"immunities":int(c["effects"])},target,func(bound):
			check(not draws.is_empty() and bound==int(draws[0]["bound"]),"original damage -> poison check -> duration -> independent30-percent power draws")
			return int(draws.pop_front()["value"]) if not draws.is_empty() else 0)
		var changes: Dictionary = actual["target_changes"]
		check(draws.is_empty() and changes["hp"]==int(row["native"]["hp"]) and changes["status_counters"]["poison"]==int(row["native"]["poison"]),"actual HP and merged poison equal unchanged native application prefix")
		check(changes["status_counters"]["no_magic"]==2 and actual["native_contribution"]==int(row["native"]["contribution"]),"poison preserves silence and contributes only actual added duration")

func creation_and_range(loop: Dictionary) -> void:
	check(loop["units"].size()==18 and loop["units"].filter(func(a):return a["player_commandable"]).size()==2,"actual source level1 has two controlled actors and16 source NPCs")
	for id in ["actor061_1","actor062_1"]:
		var actor := BattlePlayLoop.unit(loop,id)
		check(actor["battle_actor_role"]==BattlePlayLoop.ROLE_FRIENDLY and not actor["player_commandable"] and actor["growth_profile"]["source"]["mode"]==0x50000,"villager allegiance is not command authority")
		check(actor["equipment"].is_empty() and actor["inventory"].all(func(v):return int(v)==0) and actor["max_mp"]==0,"no invented weapon, inventory or spells for villagers")
		check(actor["entry_growth"]["input"]["object_kind"]==5 and actor["entry_growth"]["input"]["parameters"].map(func(v):return int(v))==[3,0],"villager original range3 parameters create a genuine NPC instance")
		check(BattlePlayLoop.weapon_pattern(loop,actor)["offsets"].is_empty(),"unarmed range0 has no hostile ordinary attack or counter")
	var hu := BattlePlayLoop.unit(loop,"hu")
	check(hu["weapon_code"]==61 and hu["growth_profile"]["job_code"]==83 and hu["stamina"]==0,"Hu keeps original bow/job/zero stamina before earning combat resources")
	check(loop["skill_book"]["actors"]["003"]["supported_initial_ids"].has(PoisonArrowRules.ID) and hu["learned_skills"].is_empty(),"source Poison Arrow is initial ownership, not fabricated learned progress")
	var shape := BattlePlayLoop.weapon_pattern(loop,hu)
	check(shape["ok"] and shape["index"]==4,"ordinary bow uses the source shooting range index")
	var cells: Array = shape["offsets"].map(func(v):return Vector2i(int(v[0]),int(v[1])))
	check(not cells.has(Vector2i.RIGHT) and cells.has(Vector2i(3,0)) and cells.has(Vector2i(1,1)),"bow close exclusion and off-axis source cells survive actor generation")
	var state := loop.duplicate(true)
	check(BattlePlayLoop.initialize_roster_growth(state)==state,"second initialization never allocates or rerolls a completed roster")
	check(not BattleCheckpoint.encode(loop,VIEW)["ok"],"unstarted idle initialization is not advertised as a player-save boundary")
	for snapshot in [BattlePlayLoop.begin_battle(loop)]:
		var encoded := BattleCheckpoint.encode(snapshot,VIEW)
		check(encoded["ok"],"source NPC/dual-player birth checkpoint: "+str(encoded.get("reason")))
		if encoded["ok"]:check(BattleCheckpoint.decode(encoded["bytes"], snapshot)["snapshot"]["loop"]==snapshot,"restore preserves exact generation sequence and actor ownership")

func transactions() -> void:
	var loop := fixture()
	check(loop["scenario_ok"] and BattlePlayLoop.CoreTurnQueue.current(loop["turn_queue"])["id"]=="hu","legally current Hu owns the transaction fixture")
	var after := cast(loop,zero)
	check(after.get("last_attack",{}).get("skill_id")==PoisonArrowRules.ID,"real shared Poison Arrow transaction settles")
	if after.get("last_attack",{}).get("skill_id")!=PoisonArrowRules.ID:return
	var receipt: Dictionary = after["last_attack"]
	check(receipt["affected_targets"].size()==2 and BattlePlayLoop.unit(after,"hu")["stamina"]==20,"two unique victims pay exactly one20ST debit")
	for target in receipt["affected_targets"]:
		check(target["actual_damage"]>0 and target["status_effects"][0]["applied"],"each living victim receives own damage and poison")
	check(BattlePlayLoop.unit(loop,"hu")["stamina"]==40 and not BattlePlayLoop.StatusEffectRules.poisoned(BattlePlayLoop.unit(loop,"actor028_1")),"pure proposal never modifies input")
	for variant in ["stamina","paralysis","missing_second_resist","unowned","terminal"]:
		var invalid := fixture()
		match variant:
			"stamina":BattlePlayLoop.unit_ref(invalid,"hu")["stamina"]=19
			"paralysis":BattlePlayLoop.unit_ref(invalid,"hu").merge(BattlePlayLoop.StatusEffectRules.apply(BattlePlayLoop.unit(invalid,"hu"),"paralysis",2)["changes"],true)
			"missing_second_resist":BattlePlayLoop.unit_ref(invalid,"actor028_2")["combat_profile"]["resist_by_type"].erase("4")
			"unowned":own(invalid, "skill_book")["actors"]["003"]["supported_initial_ids"]=[]
			"terminal":invalid["battle_outcome"]=BattleOutcome.DEFEAT_FALLEN
		var before := invalid.duplicate(true)
		var count := [0]
		var rejected := cast(invalid,func(_bound):count[0]+=1;return 0)
		check(count[0]==0 and rejected["units"]==before["units"],"invalid entire special rejects without payment/effect/RNG: "+variant)
	var silenced := fixture()
	BattlePlayLoop.unit_ref(silenced,"hu").merge(BattlePlayLoop.StatusEffectRules.apply(BattlePlayLoop.unit(silenced,"hu"),"no_magic",2)["changes"],true)
	silenced["moved_this_action"] = true
	check(cast(silenced,zero).get("last_attack",{}).get("skill_id")==PoisonArrowRules.ID,"silence and moving do not misclassify an earned special as magic")
	var empty := BattlePlayLoop.change_equipment(loop,"weapon",-1,0)
	check(BattlePlayLoop.unit(empty,"hu")["weapon_code"]==0 and BattlePlayLoop.unit(empty,"hu")["inventory"].has(61),"actual equip transaction returns bow to a real free inventory slot")
	check(BattlePlayLoop.weapon_pattern(empty,BattlePlayLoop.unit(empty,"hu"))["offsets"].is_empty(),"unarmed removal never grants an invented melee attack")
	check(not BattlePlayLoop.command_available(empty,"attack") and BattlePlayLoop.choose_command(empty,"attack")==empty,"unarmed menu and direct command share the same empty source range")
	check(empty["command_menu"]["commands"].any(func(c):return c["command"]=="attack" and not c["enabled"]),"unarmed Attack is visibly disabled without hiding legitimate items, skills or wait")
	check(BattlePlayLoop.command_available(empty,"special") and BattlePlayLoop.command_available(empty,"item") and BattlePlayLoop.command_available(empty,"wait"),"unarmed refusal does not force wait or remove owned special/item options")
	var restored := BattlePlayLoop.change_equipment(empty,"weapon",BattlePlayLoop.unit(empty,"hu")["inventory"].find(61),61)
	check(BattlePlayLoop.unit(restored,"hu")["combat_profile"]==BattlePlayLoop.unit(loop,"hu")["combat_profile"],"re-equipping recomputes once without losing or doubling source growth")
	var saved := BattleCheckpoint.encode(after,VIEW)
	check(saved["ok"],"committed multi-target poison checkpoint validates: "+str(saved.get("reason")))
	if saved["ok"]:check(BattleCheckpoint.decode(saved["bytes"], after)["snapshot"]["loop"]==after,"F9 does not replay special payment, effects or EXP")

func insertion_and_actions() -> void:
	for code in ["061","062"]:
		var sample:=insertion_fixture(code)
		var loop:Dictionary=sample["loop"]
		var before:=loop.duplicate(true)
		var first_half:=BattlePlayLoop.attack_target(BattlePlayLoop.choose_command(loop,"attack"),"actor028_1",zero)
		check(first_half["scenario_ok"] and first_half["units"].size()==18,"the strike itself scans nothing: "+code)
		var repeat:=BattlePlayLoop.finish_exhausted_action(first_half)
		check(repeat["selected_unit_id"]=="hu" and repeat["extra_action"]["pending"] and repeat["units"].size()==18 and BattlePlayLoop.unit(repeat,"hu")["status_counters"]["poison"]==BattlePlayLoop.unit(before,"hu")["status_counters"]["poison"],"the first half of the extra action completes without a scan or an early poison tail (its repeat re-enters phase 0, clearing the attacker global)")
		var after:=BattlePlayLoop.attack_target(BattlePlayLoop.choose_command(repeat,"attack"),"actor028_1",zero)
		after=BattlePlayLoop.finish_exhausted_action(after)
		check(after["scenario_ok"] and after["units"].size()==19,"actual bow attack triggers one scripted villager insert at its action's completion scan: "+code)
		if not after["scenario_ok"] or after["units"].size()!=19:continue
		var born:Dictionary=after["units"].back()
		check(born["battle_actor_role"]==BattlePlayLoop.ROLE_FRIENDLY and not born["player_commandable"] and born["source_object_kind"]==5,"spawn preserves pmNPCPlayer without converting ally to enemy or commandable player")
		check(born["entry_growth"]["input"]["parameters"]==[20,3] and born["level"]>1,"script words change real birth stats at current saved RNG cursor")
		check(born["growth_profile"]["allocation"]=="automatic" and born["equipment"].is_empty() and born["inventory"].all(func(v):return int(v)==0),"new source villager has automatic growth but no invented attack/skill/item")
		var saved:=BattleCheckpoint.encode(after,VIEW)
		check(saved["ok"],"script-adjusted friendly creation is checkpointable: "+str(saved.get("reason")))
		if saved["ok"]:check(BattleCheckpoint.decode(saved["bytes"], after)["snapshot"]["loop"]==after,"F9 preserves exact initial and new generation results without reapplying")
		# hu's next attack action: its completion scan reads the attack again (the event re-armed).
		var next_attack:=after.duplicate(true)
		next_attack["last_attack"]={"attacker_id":"hu","defender_id":"actor028_1"}
		var second:=BattlePlayLoop.resolve_outcome(BattlePlayLoop.BattleScenarioRuleAdapter.run_event_hooks(next_attack,true))
		check(second["units"].size()==20,"rearmed event on second independent action creates a new identity at the next stream cursor")
		check(BattlePlayLoop.ReinforcementGrowth.state_error(second)=="" and BattlePlayLoop.unit(second,born["id"])["entry_growth"]==born["entry_growth"],"second cast cannot reroll first birth or duplicate permanent stats")
		var upgraded:=BattlePlayLoop.ProgressionRules.resolve_experience(born,5000,loop["equipment_items"])
		check(upgraded["level"]>born["level"] and upgraded["pending_stat_points"]==0 and upgraded["entry_growth"]==born["entry_growth"],"later multi-level NPC EXP uses automatic quotas and never replays birth")

func double_bow() -> void:
	var loop:=fixture()
	BattlePlayLoop.unit_ref(loop,"hu")["inventory"]=[69,227,0,0,0,0,0,0]
	loop=BattlePlayLoop.change_equipment(loop,"weapon",0,69)
	loop=BattlePlayLoop.change_equipment(loop,"accessory2",BattlePlayLoop.unit(loop,"hu")["inventory"].find(227),227)
	check(BattlePlayLoop.unit(loop,"hu")["weapon_code"]==69 and BattlePlayLoop.attack_count(loop,BattlePlayLoop.unit(loop,"hu"))["count"]==2,"actual bow69 equipment grants two strikes, not two whole actions")
	BattlePlayLoop.unit_ref(loop,"actor028_1")["coord"]=Vector2i(15,22)
	BattlePlayLoop.unit_ref(loop,"actor028_1")["ai_home_coord"]=Vector2i(15,22)
	var after:=BattlePlayLoop.attack_target(BattlePlayLoop.choose_command(loop,"attack"),"actor028_1",zero)
	var blows:Array=BattlePlayLoop.CombatSequence.strikes(after["last_combat"]).filter(func(r):return not r.get("is_counter",false))
	check(blows.size()==2 and blows[0]["defender_hp_after"]>0 and blows[1]["defender_hp_after"]>0,"two nonlethal source bow hits use one attack sequence")
	after=BattlePlayLoop.finish_exhausted_action(after)
	check(after["selected_unit_id"]=="hu" and after["extra_action"]["pending"] and not after["moved_this_action"],"White Wings independently returns fresh second-action control after both bow strikes")
	var save:=BattleCheckpoint.encode(after,VIEW)
	check(save["ok"] and BattleCheckpoint.decode(save["bytes"], after)["snapshot"]["loop"]==after,"F9 preserves two completed strikes and exactly one pending independent action")
	var selected:=BattlePlayLoop.choose_command(after,"special")
	if selected["interaction"]=="special_select":selected=BattlePlayLoop.choose_special(selected,PoisonArrowRules.ID)
	var second:=BattlePlayLoop.attack_target(selected,"actor028_2",zero,Vector2i(15,21))
	if second["last_attack"].get("skill_id")!=PoisonArrowRules.ID:
		print("BOW_SECOND_DIAGNOSTIC ",JSON.stringify({"selected":selected["interaction"],"skill":selected.get("selected_skill_id"),"reason":second.get("last_action_reject"),"attack_reason":second.get("last_attack_reject"),"stamina":BattlePlayLoop.unit(selected,"hu")["stamina"],"targets":BattlePlayLoop.SkillTargetRules.cells(BattlePlayLoop.unit(selected,"hu")["coord"],BattlePlayLoop.skill_fields(selected,PoisonArrowRules.ID),selected["skill_target_data"],selected["map_size"])}))
	check(second["last_attack"].get("skill_id")==PoisonArrowRules.ID and second["last_attack"]["resource_payment"]["amount"]==20 and BattlePlayLoop.CombatSequence.strikes(second["last_combat"]).size()==1,"double-bow equipment never duplicates the second action's Poison Arrow payment or cast")
	var pointer:=BattlePlayLoop.attack_coord(selected,Vector2i(15,21),zero)
	check(pointer["last_attack"].get("skill_id")==PoisonArrowRules.ID and pointer["last_attack"]["affected_targets"].size()==2 and pointer["last_attack"]["cast_center"]==Vector2i(15,21),"real pointer dispatch resolves the same empty-center area special, not only direct-ID tests")
	var ordinary:=BattlePlayLoop.choose_command(after,"attack")
	var rejected:=BattlePlayLoop.attack_coord(ordinary,Vector2i(15,21),func(_n):check(false,"empty ordinary cell cannot consume random draws");return 0)
	check(rejected["units"]==ordinary["units"] and rejected["last_combat"]==ordinary["last_combat"],"ordinary attacks retain their separate occupied-target contract")
