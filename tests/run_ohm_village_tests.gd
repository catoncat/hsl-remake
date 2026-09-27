extends "res://tests/support/TestSuite.gd"
const Loop = preload("res://game/battle/scene/BattlePlayLoop.gd")
const Arrow = preload("res://game/sim/PoisonArrowRules.gd")
const Save = preload("res://game/battle/runtime/BattleCheckpoint.gd")
const Jobs = preload("res://game/sim/JobStatsRules.gd")
const Events = preload("res://tests/ScriptDepartureFixture.gd")
const ScriptRules = preload("res://game/sim/WinfailScenarioRules.gd")
const BattleOutcome = preload("res://game/sim/BattleOutcome.gd")
const SCENE := "res://content/battles/ohm_village_battle.json"
const VIEW := {"camera":Vector2(512,608),"shown_story_events":[],"story_complete":true,"growth_notified_level":4}


func _init() -> void:
	tag = "OHM_VILLAGE_TESTS"


static func fresh(initialize: bool = true) -> Dictionary:
	var loop := Loop.create([], "", Loop.BattleScenario.load_file(SCENE))
	return Loop.initialize_roster_growth(loop) if initialize and loop["scenario_ok"] else loop

static func fixture() -> Dictionary:
	var loop := fresh()
	if not loop["scenario_ok"]: return loop
	var hu := Loop._unit(loop,"hu")
	hu["growth_profile"]["source"]["speed"] += 300 # Explicit fast-turn fixture, not the formal level.
	hu.merge(Loop.ProgressionRules.refresh_growth_stats(hu,loop["equipment_items"]),true)
	hu["stamina"] = 40 # Actual formal scene remains ST0; fixture isolates paid special resolution.
	for pair in [["actor028_1",Vector2i(15,21)],["actor028_2",Vector2i(16,21)]]:
		var target := Loop._unit(loop,pair[0])
		target["coord"] = pair[1]
		target["ai_home_coord"] = pair[1]
		target["growth_profile"]["source"]["hit_point"] += 800
		target.merge(Loop.ProgressionRules.refresh_growth_stats(target,loop["equipment_items"]),true)
		target["hp"] = target["max_hp"]
	loop["turn_queue"] = Loop.CoreTurnQueue.rebuild(loop["units"])
	return Loop.begin_battle(loop)

static func cast(loop: Dictionary, rng: Variant = null) -> Dictionary:
	var selected := Loop.choose_command(loop,"special")
	if selected["interaction"] == "special_select": selected = Loop.choose_special(selected,Arrow.ID)
	return Loop.attack_target(selected,"actor028_1",rng,Vector2i(15,21))


static func ai_fixture(paralyzed: bool = false) -> Dictionary:
	# Explicit control/strategy fixture, not a newly inferred source003 AI default.
	# Hu keeps his own job, bow and declared special; no ability is copied from a mage.
	var loop := fixture()
	var hu := Loop._unit(loop,"hu")
	hu["player_commandable"] = false
	hu["battle_actor_role"] = Loop.ROLE_FRIENDLY
	hu["stamina"] = 20
	hu["equipment"].append({"slot":"accessory2","item_code":227})
	hu.merge(Loop.ProgressionRules.refresh_growth_stats(hu,loop["equipment_items"]),true)
	var strategy: Dictionary = own(loop, "ai_profiles")["actors"]["003"]
	strategy["missing_required"] = []
	strategy["profile"].merge({"find_type":3,"find_range":20,"ai_call_range":6,"ai_fixed":0,"ai_lock":60,
		"ai_check_dying":0,"ai_check_hp":0,"ai_att_special":100},true)
	var leader := Loop._unit(loop,"leonard")
	leader["growth_profile"]["source"]["speed"] += 500
	leader.merge(Loop.ProgressionRules.refresh_growth_stats(leader,loop["equipment_items"]),true)
	if paralyzed:
		hu.merge(Loop.StatusEffectRules.apply(hu,"paralysis",2)["changes"],true)
		hu["status_counters"]["paralysis"] = 1 # A valid application on its last remaining turn.
	else:
		hu.merge(Loop.StatusEffectRules.apply(hu,"no_magic",3)["changes"],true)
	loop["turn_queue"] = Loop.CoreTurnQueue.rebuild(loop["units"])
	return Loop._return_to_player(loop,"leonard")

static func insertion_fixture(code: String = "061") -> Dictionary:
	# Explicit event on the real village map. STORY001 itself contains no insert.
	var loop:=fixture()
	for id in ["hu","leonard"]:
		var actor:=Loop._unit(loop,id)
		actor["level"]=12
		actor.merge(Loop.ProgressionRules.refresh_growth_stats(actor,loop["equipment_items"]),true)
	var hu:=Loop._unit(loop,"hu")
	hu["equipment"].append({"slot":"accessory2","item_code":227})
	hu["permanent_gains"]["defense"]=5
	hu["exp"]=Loop.ProgressionRules.exp_to_next(12)-1
	hu["hit_bonus_accum"]=1000
	hu.merge(Loop.ProgressionRules.refresh_growth_stats(hu,loop["equipment_items"]),true)
	hu.merge(Loop.StatusEffectRules.apply(hu,"poison",3,6)["changes"],true)
	var template:=Loop.unit(fresh(false),"actor"+code+"_1").duplicate(true)
	loop["reinforcement_templates"]=[template]
	loop["reinforcement_spawn_cells"]=[Vector2i(14,21),Vector2i(14,22)]
	var config:=Loop.BattleScenario.load_file(SCENE).duplicate(true)
	var seed:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(config["resources"]["battle_seed"]))
	var symbol:="obj_Story_Level1_Enemy"+str(int(code))
	seed["scripts"]["story"]["sections"][0]["actions"].append(Events.command("actInsertEventStatus",[901]))
	seed["scripts"]["winfail"]["sections"].append(Events.section("event",901,[
		Events.command("actCheckPlayerAttacked",["SID_琥","SID_ENEMY028"]),
		Events.command("actInsertObject",[symbol,448,768]),
		Events.command("actSetPrevInsertObjectAdjustLevel",[20,3]),
		Events.command("actSetPrevInsertObjectWaitRound",[2]),
		Events.command("actWalkPrevInsertObjectWait",[448,672,8]),
		Events.command("actInsertEventStatus",[901])]))
	config["scenario_rules"]["events"]={"event901":{"inserts":[{"object_symbol":symbol,"walk_cell_candidate":[14,21],"insert_xy":[448,768]}]}}
	loop=ScriptRules.initialize_script_state(loop,config,seed)
	loop["turn_queue"]=Loop.CoreTurnQueue.rebuild(loop["units"])
	loop=Loop._return_to_player(loop,"hu")
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
	ai_current_state()
	terminal_and_carry(loop)

func native_stats() -> void:
	var packet: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://docs/evidence_packets/static_reverse/original_ohm_growth.json"))
	var catalog: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://content/generated/hsl/equipment/items.json"))["items"]
	for row in packet["stats"]:
		var c: Dictionary = row["input"]
		# player_mode: the native rows ran with live +0x28 = the profile's mode word (0x448840 hp_level term).
		var actor := {"id":"native", "actor_id":c["actor"], "growth_profile":row["profile"].duplicate(true), "player_mode":int(row["profile"]["source"]["mode"]),
			"combat_profile":c["attributes"].duplicate(true), "level":int(c["level"]),"hp":int(c["hp"]),"max_hp":10000,"mp":int(c["mp"]),"max_mp":10000,
			"equipment":[],"base_move_point":int(c["base_move"]),"status_flags":0,"status_counters":{"poison":0,"paralysis":0,"no_magic":0},
			"permanent_gains":Loop.ProgressionRules.Permanent.empty(),"learned_skills":[]}
		actor["combat_profile"]["base_steal_ratio"] = 0  # 003／061／062 declare no PLAYERS steal_ratio (refresh input, not a receipt field)
		for index in range(6):
			if int(c["equipment"][index])>0: actor["equipment"].append({"slot":Loop.EquipmentRules.SLOTS[index],"item_code":int(c["equipment"][index])})
		var actual := Loop.ProgressionRules.refresh_growth_stats(actor,catalog)
		for expected in row["native"]:
			var values: Dictionary = expected["values"]
			for key in ["max_hp","max_mp","move_point"]:check(actual[key]==int(values[key]),"native own job result "+c["actor"]+" "+key)
			for pair in [["live_attack_damage","attack"],["live_defense","defense"],["live_magic_attack","magic_attack"],["live_hit_ratio","hit_rate"]]:
				check(actual["combat_profile"][pair[0]]==int(values[pair[1]]),"native independent derived component "+str(pair))
			check(actual["live_speed"]==int(values["speed"]),"native bow/villager speed")
			for element in range(5):check(actual["combat_profile"]["resist_by_type"][str(element)]==int(values["resist_by_type"][str(element)]),"native bow/villager resistance "+str(element))
		check(Loop.ProgressionRules.refresh_growth_stats(actual,catalog)==actual,"refresh cannot compound source/job/equipment")

func native_arrow() -> void:
	var packet: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://docs/evidence_packets/static_reverse/original_poison_arrow.json"))
	for row in packet["rolls"]:
		var draws: Array = row["draws"].duplicate(true)
		var result := Arrow.roll(row["input"],func(bound):
			check(not draws.is_empty() and bound==int(draws[0]["bound"]),"original special channel1 exact draw boundary")
			return int(draws.pop_front()["value"]) if not draws.is_empty() else 0)
		check(draws.is_empty() and result["value"]==int(row["native"]["value"]) and result["hit_bonus_after"]==int(row["native"]["hit_bonus_after"]),"original special numeric full return")
	for row in packet["applications"]:
		var c: Dictionary = row["input"]
		var target := {"hp":int(c["hp"]),"status_flags":(1 if int(c["poison"]) else 0)|2,"status_counters":{"poison":int(c["poison"]),"paralysis":0,"no_magic":int(c["no_magic"])}}
		var draws: Array = row["draws"].duplicate(true)
		var actual := Arrow.resolve({"input":c,"immunities":int(c["effects"])},target,func(bound):
			check(not draws.is_empty() and bound==int(draws[0]["bound"]),"original damage -> poison check -> duration -> independent30-percent power draws")
			return int(draws.pop_front()["value"]) if not draws.is_empty() else 0)
		var changes: Dictionary = actual["target_changes"]
		check(draws.is_empty() and changes["hp"]==int(row["native"]["hp"]) and changes["status_counters"]["poison"]==int(row["native"]["poison"]),"actual HP and merged poison equal unchanged native application prefix")
		check(changes["status_counters"]["no_magic"]==2 and actual["native_contribution"]==int(row["native"]["contribution"]),"poison preserves silence and contributes only actual added duration")

func creation_and_range(loop: Dictionary) -> void:
	check(loop["units"].size()==18 and loop["units"].filter(func(a):return a["player_commandable"]).size()==2,"actual source level1 has two controlled actors and16 source NPCs")
	for id in ["actor061_1","actor062_1"]:
		var actor := Loop.unit(loop,id)
		check(actor["battle_actor_role"]==Loop.ROLE_FRIENDLY and not actor["player_commandable"] and actor["growth_profile"]["source"]["mode"]==0x50000,"villager allegiance is not command authority")
		check(actor["equipment"].is_empty() and actor["inventory"].all(func(v):return int(v)==0) and actor["max_mp"]==0,"no invented weapon, inventory or spells for villagers")
		check(actor["entry_growth"]["input"]["object_kind"]==5 and actor["entry_growth"]["input"]["parameters"].map(func(v):return int(v))==[3,0],"villager original range3 parameters create a genuine NPC instance")
		check(Loop.weapon_pattern(loop,actor)["offsets"].is_empty(),"unarmed range0 has no hostile ordinary attack or counter")
	var hu := Loop.unit(loop,"hu")
	check(hu["weapon_code"]==61 and hu["growth_profile"]["job_code"]==83 and hu["stamina"]==0,"Hu keeps original bow/job/zero stamina before earning combat resources")
	check(loop["skill_book"]["actors"]["003"]["supported_initial_ids"].has(Arrow.ID) and hu["learned_skills"].is_empty(),"source Poison Arrow is initial ownership, not fabricated learned progress")
	var shape := Loop.weapon_pattern(loop,hu)
	check(shape["ok"] and shape["index"]==4,"ordinary bow uses the source shooting range index")
	var cells: Array = shape["offsets"].map(func(v):return Vector2i(int(v[0]),int(v[1])))
	check(not cells.has(Vector2i.RIGHT) and cells.has(Vector2i(3,0)) and cells.has(Vector2i(1,1)),"bow close exclusion and off-axis source cells survive actor generation")
	var state := loop.duplicate(true)
	check(Loop.initialize_roster_growth(state)==state,"second initialization never allocates or rerolls a completed roster")
	check(not Save.encode(loop,VIEW)["ok"],"unstarted idle initialization is not advertised as a player-save boundary")
	for snapshot in [Loop.begin_battle(loop)]:
		var encoded := Save.encode(snapshot,VIEW)
		check(encoded["ok"],"source NPC/dual-player birth checkpoint: "+str(encoded.get("reason")))
		if encoded["ok"]:check(Save.decode(encoded["bytes"], snapshot)["snapshot"]["loop"]==snapshot,"restore preserves exact generation sequence and actor ownership")

func transactions() -> void:
	var loop := fixture()
	check(loop["scenario_ok"] and Loop.CoreTurnQueue.current(loop["turn_queue"])["id"]=="hu","legally current Hu owns the transaction fixture")
	var after := cast(loop,zero)
	check(after.get("last_attack",{}).get("skill_id")==Arrow.ID,"real shared Poison Arrow transaction settles")
	if after.get("last_attack",{}).get("skill_id")!=Arrow.ID:return
	var receipt: Dictionary = after["last_attack"]
	check(receipt["affected_targets"].size()==2 and Loop.unit(after,"hu")["stamina"]==20,"two unique victims pay exactly one20ST debit")
	for target in receipt["affected_targets"]:
		check(target["actual_damage"]>0 and target["status_effects"][0]["applied"],"each living victim receives own damage and poison")
	check(Loop.unit(loop,"hu")["stamina"]==40 and not Loop.StatusEffectRules.poisoned(Loop.unit(loop,"actor028_1")),"pure proposal never modifies input")
	for variant in ["stamina","paralysis","missing_second_resist","unowned","terminal"]:
		var invalid := fixture()
		match variant:
			"stamina":Loop._unit(invalid,"hu")["stamina"]=19
			"paralysis":Loop._unit(invalid,"hu").merge(Loop.StatusEffectRules.apply(Loop.unit(invalid,"hu"),"paralysis",2)["changes"],true)
			"missing_second_resist":Loop._unit(invalid,"actor028_2")["combat_profile"]["resist_by_type"].erase("4")
			"unowned":own(invalid, "skill_book")["actors"]["003"]["supported_initial_ids"]=[]
			"terminal":invalid["battle_outcome"]=BattleOutcome.DEFEAT_FALLEN
		var before := invalid.duplicate(true)
		var count := [0]
		var rejected := cast(invalid,func(_bound):count[0]+=1;return 0)
		check(count[0]==0 and rejected["units"]==before["units"],"invalid entire special rejects without payment/effect/RNG: "+variant)
	var silenced := fixture()
	Loop._unit(silenced,"hu").merge(Loop.StatusEffectRules.apply(Loop.unit(silenced,"hu"),"no_magic",2)["changes"],true)
	silenced["moved_this_action"] = true
	check(cast(silenced,zero).get("last_attack",{}).get("skill_id")==Arrow.ID,"silence and moving do not misclassify an earned special as magic")
	var empty := Loop.change_equipment(loop,"weapon",-1,0)
	check(Loop.unit(empty,"hu")["weapon_code"]==0 and Loop.unit(empty,"hu")["inventory"].has(61),"actual equip transaction returns bow to a real free inventory slot")
	check(Loop.weapon_pattern(empty,Loop.unit(empty,"hu"))["offsets"].is_empty(),"unarmed removal never grants an invented melee attack")
	check(not Loop.command_available(empty,"attack") and Loop.choose_command(empty,"attack")==empty,"unarmed menu and direct command share the same empty source range")
	check(empty["command_menu"]["commands"].any(func(c):return c["command"]=="attack" and not c["enabled"]),"unarmed Attack is visibly disabled without hiding legitimate items, skills or wait")
	check(Loop.command_available(empty,"special") and Loop.command_available(empty,"item") and Loop.command_available(empty,"wait"),"unarmed refusal does not force wait or remove owned special/item options")
	var restored := Loop.change_equipment(empty,"weapon",Loop.unit(empty,"hu")["inventory"].find(61),61)
	check(Loop.unit(restored,"hu")["combat_profile"]==Loop.unit(loop,"hu")["combat_profile"],"re-equipping recomputes once without losing or doubling source growth")
	var saved := Save.encode(after,VIEW)
	check(saved["ok"],"committed multi-target poison checkpoint validates: "+str(saved.get("reason")))
	if saved["ok"]:check(Save.decode(saved["bytes"], after)["snapshot"]["loop"]==after,"F9 does not replay special payment, effects or EXP")

func insertion_and_actions() -> void:
	for code in ["061","062"]:
		var sample:=insertion_fixture(code)
		var loop:Dictionary=sample["loop"]
		var before:=loop.duplicate(true)
		var first_half:=Loop.attack_target(Loop.choose_command(loop,"attack"),"actor028_1",zero)
		check(first_half["scenario_ok"] and first_half["units"].size()==18,"the strike itself scans nothing: "+code)
		var repeat:=Loop.finish_exhausted_action(first_half)
		check(repeat["selected_unit_id"]=="hu" and repeat["extra_action"]["pending"] and repeat["units"].size()==18 and Loop.unit(repeat,"hu")["status_counters"]["poison"]==Loop.unit(before,"hu")["status_counters"]["poison"],"the first half of the extra action completes without a scan or an early poison tail (its repeat re-enters phase 0, clearing the attacker global)")
		var after:=Loop.attack_target(Loop.choose_command(repeat,"attack"),"actor028_1",zero)
		after=Loop.finish_exhausted_action(after)
		check(after["scenario_ok"] and after["units"].size()==19,"actual bow attack triggers one scripted villager insert at its action's completion scan: "+code)
		if not after["scenario_ok"] or after["units"].size()!=19:continue
		var born:Dictionary=after["units"].back()
		check(born["battle_actor_role"]==Loop.ROLE_FRIENDLY and not born["player_commandable"] and born["source_object_kind"]==5,"spawn preserves pmNPCPlayer without converting ally to enemy or commandable player")
		check(born["entry_growth"]["input"]["parameters"]==[20,3] and born["level"]>1,"script words change real birth stats at current saved RNG cursor")
		check(born["growth_profile"]["allocation"]=="automatic" and born["equipment"].is_empty() and born["inventory"].all(func(v):return int(v)==0),"new source villager has automatic growth but no invented attack/skill/item")
		var saved:=Save.encode(after,VIEW)
		check(saved["ok"],"script-adjusted friendly creation is checkpointable: "+str(saved.get("reason")))
		if saved["ok"]:check(Save.decode(saved["bytes"], after)["snapshot"]["loop"]==after,"F9 preserves exact initial and new generation results without reapplying")
		# hu's next attack action: its completion scan reads the attack again (the event re-armed).
		var next_attack:=after.duplicate(true)
		next_attack["last_attack"]={"attacker_id":"hu","defender_id":"actor028_1"}
		var second:=Loop._resolve_outcome(Loop.BattleScenarioRuleAdapter.run_event_hooks(next_attack,true))
		check(second["units"].size()==20,"rearmed event on second independent action creates a new identity at the next stream cursor")
		check(Loop.ReinforcementGrowth.state_error(second)=="" and Loop.unit(second,born["id"])["entry_growth"]==born["entry_growth"],"second cast cannot reroll first birth or duplicate permanent stats")
		var upgraded:=Loop.ProgressionRules.resolve_experience(born,5000,loop["equipment_items"])
		check(upgraded["level"]>born["level"] and upgraded["pending_stat_points"]==0 and upgraded["entry_growth"]==born["entry_growth"],"later multi-level NPC EXP uses automatic quotas and never replays birth")

func double_bow() -> void:
	var loop:=fixture()
	Loop._unit(loop,"hu")["inventory"]=[69,227,0,0,0,0,0,0]
	loop=Loop.change_equipment(loop,"weapon",0,69)
	loop=Loop.change_equipment(loop,"accessory2",Loop.unit(loop,"hu")["inventory"].find(227),227)
	check(Loop.unit(loop,"hu")["weapon_code"]==69 and Loop.attack_count(loop,Loop.unit(loop,"hu"))["count"]==2,"actual bow69 equipment grants two strikes, not two whole actions")
	Loop._unit(loop,"actor028_1")["coord"]=Vector2i(15,22)
	Loop._unit(loop,"actor028_1")["ai_home_coord"]=Vector2i(15,22)
	var after:=Loop.attack_target(Loop.choose_command(loop,"attack"),"actor028_1",zero)
	var blows:Array=Loop.CombatSequence.strikes(after["last_combat"]).filter(func(r):return not r.get("is_counter",false))
	check(blows.size()==2 and blows[0]["defender_hp_after"]>0 and blows[1]["defender_hp_after"]>0,"two nonlethal source bow hits use one attack sequence")
	after=Loop.finish_exhausted_action(after)
	check(after["selected_unit_id"]=="hu" and after["extra_action"]["pending"] and not after["moved_this_action"],"White Wings independently returns fresh second-action control after both bow strikes")
	var save:=Save.encode(after,VIEW)
	check(save["ok"] and Save.decode(save["bytes"], after)["snapshot"]["loop"]==after,"F9 preserves two completed strikes and exactly one pending independent action")
	var selected:=Loop.choose_command(after,"special")
	if selected["interaction"]=="special_select":selected=Loop.choose_special(selected,Arrow.ID)
	var second:=Loop.attack_target(selected,"actor028_2",zero,Vector2i(15,21))
	if second["last_attack"].get("skill_id")!=Arrow.ID:
		print("BOW_SECOND_DIAGNOSTIC ",JSON.stringify({"selected":selected["interaction"],"skill":selected.get("selected_skill_id"),"reason":second.get("last_action_reject"),"attack_reason":second.get("last_attack_reject"),"stamina":Loop.unit(selected,"hu")["stamina"],"targets":Loop.SkillTargetRules.cells(Loop.unit(selected,"hu")["coord"],Loop.skill_fields(selected,Arrow.ID),selected["skill_target_data"],selected["map_size"])}))
	check(second["last_attack"].get("skill_id")==Arrow.ID and second["last_attack"]["resource_payment"]["amount"]==20 and Loop.CombatSequence.strikes(second["last_combat"]).size()==1,"double-bow equipment never duplicates the second action's Poison Arrow payment or cast")
	var pointer:=Loop.attack_coord(selected,Vector2i(15,21),zero)
	check(pointer["last_attack"].get("skill_id")==Arrow.ID and pointer["last_attack"]["affected_targets"].size()==2 and pointer["last_attack"]["cast_center"]==Vector2i(15,21),"real pointer dispatch resolves the same empty-center area special, not only direct-ID tests")
	var ordinary:=Loop.choose_command(after,"attack")
	var rejected:=Loop.attack_coord(ordinary,Vector2i(15,21),func(_n):check(false,"empty ordinary cell cannot consume random draws");return 0)
	check(rejected["units"]==ordinary["units"] and rejected["last_combat"]==ordinary["last_combat"],"ordinary attacks retain their separate occupied-target contract")

func ai_current_state() -> void:
	var initial := ai_fixture()
	var ready := Loop.choose_command(initial,"wait")
	check(ready["interaction"]=="ai_resolving" and Loop.CoreTurnQueue.current(ready["turn_queue"])["id"]=="hu","real player Wait hands the next slot to the explicitly configured friendly Hu")
	var first := Loop.step_ai_turn(ready,zero)
	check(first["scenario_ok"],"current Hu AI preflight stays valid: "+str(first.get("scenario_error")))
	if not first["scenario_ok"]:return
	check(first["last_ai_action"].get("skill_id")==Arrow.ID and Loop.unit(first,"hu")["stamina"]==0,"silenced AI can use its actual ST special and pays its last twenty stamina once")
	check(first["extra_action"]["pending"] and first["interaction"]=="ai_resolving","first complete AI special leaves one independent decision, not a cached cast")
	var second := Loop.step_ai_turn(first,zero)
	check(second["scenario_ok"] and second["last_ai_action"].get("actor_id")=="hu" and second["last_ai_action"].get("skill_id")!=Arrow.ID,"AI second action recalculates after ST depletion and cannot reuse Poison Arrow")
	check(second["last_ai_action"].get("kind") in ["attack","move_then_attack","move","wait"],"depleted AI retains legal bow movement/attack/wait fallbacks")
	var skip := ai_fixture(true)
	var before := Loop.unit(skip,"hu").duplicate(true)
	skip = Loop.step_ai_turn(Loop.choose_command(skip,"wait"),zero)
	check(skip["scenario_ok"] and skip["last_ai_action"].get("kind")=="paralysis_skip","current paralysis is checked before the owned special or White Wings")
	check(Loop.unit(skip,"hu")["stamina"]==before["stamina"] and not Loop.StatusEffectRules.paralyzed(Loop.unit(skip,"hu")),"paralysis consumes one status tail, not twenty stamina or a second skipped action")
	check(not skip["extra_action"]["pending"] and Loop.CoreTurnQueue.current(skip["turn_queue"])["id"]!="hu","expiry does not create an extra Hu action in the consumed queue slot")

func terminal_and_carry(loop: Dictionary) -> void:
	var carry: Dictionary = JSON.parse_string(JSON.stringify(Loop.CampaignCarryRules.capture(loop)))
	var resumed := Loop.apply_campaign_carry(fresh(false),carry)
	check(resumed["campaign_carry_receipt"]["errors"].is_empty() and resumed["campaign_carry_receipt"]["applied_unit_ids"].has("hu"),"both actual controlled party members carry through JSON; villagers do not join the persistent party")
	var ready := Loop.initialize_roster_growth(resumed)
	check(ready["scenario_ok"] and Loop.unit(ready,"hu")["level"]==Loop.unit(loop,"hu")["level"],"carried Hu is not reinitialized or reallocated")
	for mode in ["hero_dead","villagers_dead","clear","retreat"]:
		var terminal := loop.duplicate(true)
		for actor in terminal["units"]:
			var remove: bool = (mode=="hero_dead" and actor["id"]=="leonard") or (mode=="villagers_dead" and actor["actor_id"] in ["061","062"]) or (mode=="clear" and actor["battle_actor_role"]==Loop.ROLE_ENEMY) or (mode=="retreat" and actor["id"] in ["actor028_3","actor028_4","actor028_5","actor028_6"])
			if remove:actor["hp"]=0;actor["defeated"]=true
		var outcome := Loop.BattleScenarioRuleAdapter.victory_state(terminal)
		check(BattleOutcome.is_defeat(outcome) if mode in ["hero_dead","villagers_dead"] else BattleOutcome.is_victory(outcome),"actual WINFAIL001 terminal condition: "+mode+" -> "+BattleOutcome.describe(outcome))
