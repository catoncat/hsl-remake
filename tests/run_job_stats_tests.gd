extends "res://tests/support/TestSuite.gd"
const Loop = preload("res://game/battle/scene/BattlePlayLoop.gd")
const BattleFixture = preload("res://tests/support/BattleFixture.gd")


func _init() -> void:
	tag = "JOB_STATS_TESTS"


static func fixture(code: String = "001", commandable: bool = true) -> Dictionary:
	var loop := BattleFixture.loop()
	var source: Dictionary = loop["units"].filter(func(a): return a["actor_id"] == code)[0].duplicate(true)
	var enemy := Loop.unit(loop, "enemy021_1")
	var ally := Loop.unit(loop, "enemy023_1")
	source.merge({"id": "leonard", "coord": Vector2i(8,8), "player_commandable": commandable,
		"battle_actor_role": Loop.ROLE_PLAYER if commandable else Loop.ROLE_FRIENDLY, "live_speed":120,
		"inventory":[218,223,224,193,227,241,246,0]}, true)
	# Controlled non-protagonist jobs are explicit fixtures, not default party grants.
	source["growth_profile"]["allocation"] = "manual" if commandable else "fixed_template"
	enemy.merge({"coord":Vector2i(11,8),"hp":500,"max_hp":500,"live_speed":70},true)
	ally.merge({"coord":Vector2i(16,14),"live_speed":100,"player_commandable":true},true)
	loop["units"] = [source,ally,enemy]
	loop["tiles"] = {}; loop["map_size"] = Vector2i(24,24); loop["reinforcement_templates"] = []
	loop["turn_queue"] = Loop.CoreTurnQueue.rebuild(loop["units"])
	return Loop._return_to_player(loop,"leonard") if commandable else ai_start(loop)


static func ai_start(loop: Dictionary) -> Dictionary:
	loop["selected_unit_id"] = ""; loop["interaction"] = "ai_resolving"
	return loop


func run() -> void:
	var loop := BattleFixture.loop()
	check(loop["scenario_ok"], "job initialization must complete, not merely expose partially loaded profiles")
	var packet: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://docs/evidence_packets/static_reverse/original_job_stats.json"))
	for row in packet["cases"]:
		if row["input"]["name"] != "initial" or row["input"]["actor"] == "025": continue
		for actor in loop["units"]:
			if actor["actor_id"] != row["input"]["actor"]: continue
			check(actor.get("growth_profile",{}).get("model") == "native_job_stats_v1", "every live source job owns a complete refresh profile")
			for element in range(5):
				check(actor["combat_profile"]["resist_by_type"][str(element)] == row["native"][0]["values"]["resist_by_type"][str(element)], "initial NPC and player resists include source job and equipped bonuses")
	var second := Loop.create([],"",Loop.BattleScenario.load_file("res://content/battles/battle_052.json"))
	check(second["scenario_ok"], "second battle source boss also uses the shared refresh")
	var supplied: Array = loop["units"].duplicate(true)
	supplied[0]["combat_profile"]["live_attack_damage"] = 12345
	var supplied_before := supplied.duplicate(true)
	var initialized := BattleFixture.loop(supplied)
	check(supplied == supplied_before and initialized["units"][0]["combat_profile"]["live_attack_damage"] != 12345, "init refreshes its owned copy, not the caller's template dictionaries")
	for row in packet["cases"]:
		var input: Dictionary = row["input"]
		var source_loop: Dictionary = second if input["actor"] == "025" else loop
		var actor: Dictionary = source_loop["units"].filter(func(a): return a["actor_id"] == input["actor"])[0].duplicate(true)
		actor["growth_profile"] = row["profile"].duplicate(true)
		# The native 0x448840 executions ran with live +0x28 = the case's mode word; the remake's
		# live word is the installed player_mode (other_source_mode cases: 0x0 / pmPlayerEnemy).
		actor["player_mode"] = int(row["profile"]["source"]["mode"])
		actor["combat_profile"].merge(input["attributes"],true)
		actor.merge({"hp":int(input["hp"]),"mp":int(input["mp"]),"level":int(input["level"]),"base_move_point":int(input["base_move"]),"equipment":[]},true)
		for index in range(6):
			var code := int(input["equipment"][index])
			if code: actor["equipment"].append({"slot":Loop.EquipmentRules.SLOTS[index],"item_code":code})
		for native in row["native"]:
			actor = Loop.ProgressionRules.refresh_growth_stats(actor,loop["equipment_items"])
			var expected: Dictionary = native["values"]
			for key in ["max_hp","max_mp","move_point"]:
				check(actor[key] == expected[key], "native full refresh: "+key)
			check(actor["hp"] == expected["current_hp"] and actor["mp"] == expected["current_mp"] and actor["live_speed"] == expected["speed"], "current resources and speed match full native returns")
			for pair in [["attack","live_attack_damage"],["defense","live_defense"],["magic_attack","live_magic_attack"],["hit_rate","live_hit_ratio"],["avoid_hit_ratio","avoid_hit_ratio"],["attack_back","attack_back"],["attack_damagex2","attack_damagex2"],["resist_by_type","resist_by_type"]]:
				if pair[0] == "resist_by_type":
					for element in range(5):
						check(actor["combat_profile"][pair[1]][str(element)] == expected[pair[0]][str(element)], "native job/source/equipment resistance")
				else: check(actor["combat_profile"][pair[1]] == expected[pair[0]], "native job/source/equipment: "+pair[0])
			check(Loop.ProgressionRules.exp_to_next(actor["level"]) == expected["exp_threshold"], "shared threshold follows original refreshed level")
	for code in ["001","024","026"]:
		var battle := fixture(code)
		var actor := Loop._unit(battle,"leonard")
		actor["exp"] = 99; actor["hp"] = 1; actor["mp"] = 0
		var queue: Dictionary = battle["turn_queue"].duplicate(true)
		var grew := Loop.ProgressionRules.resolve_experience(actor,1,battle["equipment_items"])
		check(grew["level"] == 2 and grew["pending_stat_points"] == 5 and grew["hp"] == 1 and grew["mp"] == 0, "manual role level-up refreshes but never heals: "+code)
		actor.merge(grew,true)
		var allocated := Loop.allocate_growth(battle,"leonard",{"str":1,"dex":1,"mind":2,"con":1})
		check(allocated["turn_queue"] == queue and Loop.unit(allocated,"leonard")["pending_stat_points"] == 0, "role growth preserves current queue snapshot: "+code)
		var before: Dictionary = Loop.unit(allocated,"leonard").duplicate(true)
		var old_code := Loop.EquipmentRules.equipped_code(before["equipment"],"accessory1")
		var equipped := Loop.change_equipment(allocated,"accessory1",1,223)
		check(Loop.EquipmentRules.equipped_code(Loop.unit(equipped,"leonard")["equipment"],"accessory1") == 223, "all three source jobs accept the all-job recovery accessory")
		var removed := Loop.change_equipment(equipped,"accessory1",-1,0)
		if old_code:
			removed = Loop.change_equipment(removed,"accessory1",Loop.unit(removed,"leonard")["inventory"].find(old_code),old_code)
		check(Loop.unit(removed,"leonard")["combat_profile"] == before["combat_profile"] and Loop.unit(removed,"leonard")["traversal"] == before["traversal"], "remove/refresh restores derived values without changing source traversal")
		var invalid := allocated.duplicate(true)
		Loop._unit(invalid,"leonard")["growth_profile"]["source"].erase("mode")
		check(Loop.change_equipment(invalid,"accessory1",1,223) == invalid, "missing source mode rejects exchange atomically")
		Loop._unit(invalid,"leonard")["growth_profile"]["job_code"] = 90.5
		check(Loop.ProgressionRules.refresh_input_error(Loop.unit(invalid,"leonard"),invalid["equipment_items"]) != "", "fractional job identity cannot truncate into a supported class")
	for actor in loop["units"]:
		if actor["actor_id"] == "001": continue
		var grown := Loop.ProgressionRules.resolve_experience(actor,500,loop["equipment_items"])
		check(actor["growth_profile"]["allocation"] == "automatic" and grown["level"] > actor["level"] and grown["pending_stat_points"] == 0, "live NPC uses the explicit automatic progression branch without player point reservations")
		check(grown["learned_skills"].is_empty() and grown["hp"] == actor["hp"] and grown["mp"] == actor["mp"], "automatic growth does not learn player abilities or refill current resources")
		var template: Dictionary = actor.duplicate(true)
		template["growth_profile"]["allocation"] = "fixed_template"
		check(Loop.ProgressionRules.resolve_experience(template,500,loop["equipment_items"]) == template, "uninstantiated source-only template still cannot acquire artificial EXP")
	live_side_hp_level(loop)


## 0x448840's hp_level term tests the live +0x28 pmPlayer bit, not the PLAYERS template mode:
## the constructor 0x407ec0 swaps a pmPlayer template to pmEnemy when obj_Data9 is set (before
## the refresh), so an L1 023 fielded as an enemy has 28 max HP — R33 runtime-measured
## (docs/evidence_packets/runtime_observations/battle_053/original_units.json, three 023 28/28)
## against the pmPlayer template's 29. The installed player_mode is the live word; a unit
## without one takes the side its role implies (ActorRoleRules.side_mask).
func live_side_hp_level(loop: Dictionary) -> void:
	var guard: Dictionary = loop["units"].filter(func(a): return a["actor_id"] == "023")[0].duplicate(true)
	guard["level"] = 1
	check(int(guard["growth_profile"]["source"]["mode"]) == 0x10000 and not guard.has("player_mode") and guard["battle_actor_role"] == Loop.ROLE_FRIENDLY, "first-battle 023 is the pmPlayer template fielded as friendly AI without an installed mode")
	var friendly := Loop.ProgressionRules.refresh_growth_stats(guard, loop["equipment_items"])
	check(int(friendly["max_hp"]) == 29, "role-implied pmPlayer side keeps the L1 level term: 29")
	var swapped := guard.duplicate(true)
	swapped["player_mode"] = Loop.ActorRoleRules.SIDE_ENEMY
	check(int(Loop.ProgressionRules.refresh_growth_stats(swapped, loop["equipment_items"])["max_hp"]) == 28, "installed pmEnemy (obj_Data9 swap) drops the level term: L1 023 = 28 like the original 53 guards")
	var enemy_role := guard.duplicate(true)
	enemy_role["battle_actor_role"] = Loop.ROLE_ENEMY
	check(int(Loop.ProgressionRules.refresh_growth_stats(enemy_role, loop["equipment_items"])["max_hp"]) == 28, "an uninstalled unit on the enemy role side has no level term either")
	var player_enemy := guard.duplicate(true)
	player_enemy["player_mode"] = Loop.ActorRoleRules.SIDE_PLAYER | Loop.ActorRoleRules.SIDE_ENEMY
	check(int(Loop.ProgressionRules.refresh_growth_stats(player_enemy, loop["equipment_items"])["max_hp"]) == 29, "pmPlayerEnemy carries the pmPlayer bit and keeps the term (original_job_stats other_source_mode)")
	for template_mode in [0x10000, 0x20000]:
		var retemplated := swapped.duplicate(true)
		retemplated["growth_profile"]["source"]["mode"] = template_mode
		check(int(Loop.ProgressionRules.refresh_growth_stats(retemplated, loop["equipment_items"])["max_hp"]) == 28, "the template mode word no longer decides the term once a mode is installed")
