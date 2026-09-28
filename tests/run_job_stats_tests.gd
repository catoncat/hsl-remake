extends "res://tests/support/TestSuite.gd"
const BattlePlayLoop = preload("res://game/sim/loop/BattlePlayLoop.gd")
const BattleFixture = preload("res://tests/support/BattleFixture.gd")


func _init() -> void:
	tag = "JOB_STATS_TESTS"


static func fixture(code: String = "001", commandable: bool = true) -> Dictionary:
	var loop := BattleFixture.loop()
	var source: Dictionary = loop["units"].filter(func(a): return a["actor_id"] == code)[0].duplicate(true)
	var enemy := BattlePlayLoop.unit(loop, "enemy021_1")
	var ally := BattlePlayLoop.unit(loop, "enemy023_1")
	source.merge({"id": "leonard", "coord": Vector2i(8,8), "player_commandable": commandable,
		"battle_actor_role": BattlePlayLoop.ROLE_PLAYER if commandable else BattlePlayLoop.ROLE_FRIENDLY, "live_speed":120,
		"inventory":[218,223,224,193,227,241,246,0]}, true)
	# Controlled non-protagonist jobs are explicit fixtures, not default party grants.
	source["growth_profile"]["allocation"] = "manual" if commandable else "fixed_template"
	enemy.merge({"coord":Vector2i(11,8),"hp":500,"max_hp":500,"live_speed":70},true)
	ally.merge({"coord":Vector2i(16,14),"live_speed":100,"player_commandable":true},true)
	loop["units"] = [source,ally,enemy]
	loop["tiles"] = {}; loop["map_size"] = Vector2i(24,24); loop["reinforcement_templates"] = []
	loop["turn_queue"] = BattlePlayLoop.CoreTurnQueue.rebuild(loop["units"])
	return BattlePlayLoop.return_to_player(loop,"leonard") if commandable else ai_start(loop)


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
			for element in range(5):
				check(actor["combat_profile"]["resist_by_type"][str(element)] == row["native"][0]["values"]["resist_by_type"][str(element)], "initial NPC and player resists include source job and equipped bonuses")
	var second := BattlePlayLoop.create([],"",BattlePlayLoop.BattleScenario.load_file("res://content/battles/battle_052.json"))
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
			if code: actor["equipment"].append({"slot":BattlePlayLoop.EquipmentRules.SLOTS[index],"item_code":code})
		for native in row["native"]:
			actor = BattlePlayLoop.ProgressionRules.refresh_growth_stats(actor,loop["equipment_items"])
			var expected: Dictionary = native["values"]
			for key in ["max_hp","max_mp","move_point"]:
				check(actor[key] == expected[key], "native full refresh: "+key)
			check(actor["hp"] == expected["current_hp"] and actor["mp"] == expected["current_mp"] and actor["live_speed"] == expected["speed"], "current resources and speed match full native returns")
			for pair in [["attack","live_attack_damage"],["defense","live_defense"],["magic_attack","live_magic_attack"],["hit_rate","live_hit_ratio"],["avoid_hit_ratio","avoid_hit_ratio"],["attack_back","attack_back"],["attack_damagex2","attack_damagex2"],["resist_by_type","resist_by_type"]]:
				if pair[0] == "resist_by_type":
					for element in range(5):
						check(actor["combat_profile"][pair[1]][str(element)] == expected[pair[0]][str(element)], "native job/source/equipment resistance")
				else: check(actor["combat_profile"][pair[1]] == expected[pair[0]], "native job/source/equipment: "+pair[0])
			check(BattlePlayLoop.ProgressionRules.exp_to_next(actor["level"]) == expected["exp_threshold"], "shared threshold follows original refreshed level")
	for code in ["001","024","026"]:
		var battle := fixture(code)
		var actor := BattlePlayLoop.unit_ref(battle,"leonard")
		actor["exp"] = 99; actor["hp"] = 1; actor["mp"] = 0
		var queue: Dictionary = battle["turn_queue"].duplicate(true)
		var grew := BattlePlayLoop.ProgressionRules.resolve_experience(actor,1,battle["equipment_items"])
		check(grew["level"] == 2 and grew["pending_stat_points"] == 5 and grew["hp"] == 1 and grew["mp"] == 0, "manual role level-up refreshes but never heals: "+code)
		actor.merge(grew,true)
		var allocated := BattlePlayLoop.allocate_growth(battle,"leonard",{"str":1,"dex":1,"mind":2,"con":1})
		check(allocated["turn_queue"] == queue and BattlePlayLoop.unit(allocated,"leonard")["pending_stat_points"] == 0, "role growth preserves current queue snapshot: "+code)
		var before: Dictionary = BattlePlayLoop.unit(allocated,"leonard").duplicate(true)
		var old_code := BattlePlayLoop.EquipmentRules.equipped_code(before["equipment"],"accessory1")
		var equipped := BattlePlayLoop.change_equipment(allocated,"accessory1",1,223)
		check(BattlePlayLoop.EquipmentRules.equipped_code(BattlePlayLoop.unit(equipped,"leonard")["equipment"],"accessory1") == 223, "all three source jobs accept the all-job recovery accessory")
		var removed := BattlePlayLoop.change_equipment(equipped,"accessory1",-1,0)
		if old_code:
			removed = BattlePlayLoop.change_equipment(removed,"accessory1",BattlePlayLoop.unit(removed,"leonard")["inventory"].find(old_code),old_code)
		check(BattlePlayLoop.unit(removed,"leonard")["combat_profile"] == before["combat_profile"] and BattlePlayLoop.unit(removed,"leonard")["traversal"] == before["traversal"], "remove/refresh restores derived values without changing source traversal")
		var invalid := allocated.duplicate(true)
		BattlePlayLoop.unit_ref(invalid,"leonard")["growth_profile"]["source"].erase("mode")
		check(BattlePlayLoop.change_equipment(invalid,"accessory1",1,223) == invalid, "missing source mode rejects exchange atomically")
		BattlePlayLoop.unit_ref(invalid,"leonard")["growth_profile"]["job_code"] = 90.5
		check(BattlePlayLoop.ProgressionRules.refresh_input_error(BattlePlayLoop.unit(invalid,"leonard"),invalid["equipment_items"]) != "", "fractional job identity cannot truncate into a supported class")
	for actor in loop["units"]:
		if actor["actor_id"] == "001": continue
		var grown := BattlePlayLoop.ProgressionRules.resolve_experience(actor,500,loop["equipment_items"])
		check(actor["growth_profile"]["allocation"] == "automatic" and grown["level"] > actor["level"] and grown["pending_stat_points"] == 0, "live NPC uses the explicit automatic progression branch without player point reservations")
		check(grown["learned_skills"].is_empty() and grown["hp"] == actor["hp"] and grown["mp"] == actor["mp"], "automatic growth does not learn player abilities or refill current resources")
		var template: Dictionary = actor.duplicate(true)
		template["growth_profile"]["allocation"] = "fixed_template"
		check(BattlePlayLoop.ProgressionRules.resolve_experience(template,500,loop["equipment_items"]) == template, "uninstantiated source-only template still cannot acquire artificial EXP")
	live_side_hp_level(loop)
	run_campaign_actor()


## 0x448840's hp_level term tests the live +0x28 pmPlayer bit, not the PLAYERS template mode:
## the constructor 0x407ec0 swaps a pmPlayer template to pmEnemy when obj_Data9 is set (before
## the refresh), so an L1 023 fielded as an enemy has 28 max HP — R33 runtime-measured
## (docs/evidence_packets/runtime_observations/battle_053/original_units.json, three 023 28/28)
## against the pmPlayer template's 29. The installed player_mode is the live word; a unit
## without one takes the side its role implies (ActorRoleRules.side_mask).
func live_side_hp_level(loop: Dictionary) -> void:
	var guard: Dictionary = loop["units"].filter(func(a): return a["actor_id"] == "023")[0].duplicate(true)
	guard["level"] = 1
	check(int(guard["growth_profile"]["source"]["mode"]) == 0x10000 and not guard.has("player_mode") and guard["battle_actor_role"] == BattlePlayLoop.ROLE_FRIENDLY, "first-battle 023 is the pmPlayer template fielded as friendly AI without an installed mode")
	var friendly := BattlePlayLoop.ProgressionRules.refresh_growth_stats(guard, loop["equipment_items"])
	check(int(friendly["max_hp"]) == 29, "role-implied pmPlayer side keeps the L1 level term: 29")
	var swapped := guard.duplicate(true)
	swapped["player_mode"] = BattlePlayLoop.ActorRoleRules.SIDE_ENEMY
	check(int(BattlePlayLoop.ProgressionRules.refresh_growth_stats(swapped, loop["equipment_items"])["max_hp"]) == 28, "installed pmEnemy (obj_Data9 swap) drops the level term: L1 023 = 28 like the original 53 guards")
	var enemy_role := guard.duplicate(true)
	enemy_role["battle_actor_role"] = BattlePlayLoop.ROLE_ENEMY
	check(int(BattlePlayLoop.ProgressionRules.refresh_growth_stats(enemy_role, loop["equipment_items"])["max_hp"]) == 28, "an uninstalled unit on the enemy role side has no level term either")
	var player_enemy := guard.duplicate(true)
	player_enemy["player_mode"] = BattlePlayLoop.ActorRoleRules.SIDE_PLAYER | BattlePlayLoop.ActorRoleRules.SIDE_ENEMY
	check(int(BattlePlayLoop.ProgressionRules.refresh_growth_stats(player_enemy, loop["equipment_items"])["max_hp"]) == 29, "pmPlayerEnemy carries the pmPlayer bit and keeps the term (original_job_stats other_source_mode)")
	for template_mode in [0x10000, 0x20000]:
		var retemplated := swapped.duplicate(true)
		retemplated["growth_profile"]["source"]["mode"] = template_mode
		check(int(BattlePlayLoop.ProgressionRules.refresh_growth_stats(retemplated, loop["equipment_items"])["max_hp"]) == 28, "the template mode word no longer decides the term once a mode is installed")


# ---- run_job_stats_tests.gd ----
const ActorInitializationRules = preload("res://game/sim/ActorInitializationRules.gd")
const ProgressionRules = preload("res://game/sim/ProgressionRules.gd")
const EntryGrowthRules = preload("res://game/sim/EntryGrowthRules.gd")
const EquipmentRules = preload("res://game/sim/EquipmentRules.gd")
const ELEMENTS := ["magicEARTH","magicWATER","magicAIR","magicFIRE","magicMIND","magicOTHER","magicOTHER2"]

## Actors whose template declares source.runtime_blockers (collected while iterating the
## packet): the remake refuses their source equipment at initialization instead of
## substituting another item, and only 008 carries unequipped native rows to compare.
var blocked_actors: Array = []


static func load_data(path: String) -> Dictionary:
	return integral_values(JSON.parse_string(FileAccess.get_file_as_string("res://"+path)))

static func integral_values(value: Variant) -> Variant:
	# JSON numbers are floats in Godot. These source packets contain integer rules;
	# normalize before nested Dictionary/Array equality, which also compares types.
	if value is Dictionary:
		var result := {}
		for key in value: result[key] = integral_values(value[key])
		return result
	if value is Array: return value.map(integral_values)
	if value is float and value == floor(value): return int(value)
	return value

func run_campaign_actor() -> void:
	var packet := load_data("docs/evidence_packets/static_reverse/original_campaign_actors.json")
	var roles: Dictionary = load_data("content/generated/hsl/roles/profiles.json")["actors"]
	var equipment: Dictionary = load_data("content/generated/hsl/equipment/items.json")["items"]
	var progression: Dictionary = load_data("content/imported/hsl/chapter01/progression.json")["actors"]
	var book := load_data("content/generated/hsl/skills/initial_book.json")
	book["learning"] = load_data("content/generated/hsl/roles/growth_lifecycle.json")
	var ai := load_data("content/generated/hsl/ai/profiles.json")
	var entry_sources: Dictionary = load_data("content/generated/hsl/roles/entry_growth.json")["actors"]
	var templates := {}
	var initial_rows := 0
	for row in packet["stats"]:
		var c: Dictionary = row["input"]
		if c["name"] != "initial": continue
		var code: String = c["actor"]
		var data := load_data("content/generated/hsl/actors/"+code+".json")
		var actor: Dictionary = data["actor"].duplicate(true)
		actor["coord"] = Vector2i.ZERO
		var before := actor.duplicate(true)
		var prepared := ActorInitializationRules.prepare(actor,book,ai,progression,{},equipment,0)
		check(actor == before,"initialization leaves source template immutable: "+code)
		var blockers: Array = data["source"].get("runtime_blockers", [])
		if not blockers.is_empty():
			# The template declares its own runtime blocker (source weapons whose attack_range
			# the reviewed equipment contract does not model: 008 range 32, 052 weapon 58,
			# 057 weapon 53, 058 weapon 57, 060 weapon 55). Initialization must refuse them
			# explicitly, never substitute; the numeric rows below run on the unarmed template.
			blocked_actors.append(code)
			check(not prepared["ok"] and prepared["reason"] == "unsupported_equipment","source blocker is explicit, not a silent substitute: "+code)
			actor["equipment"] = []
			prepared = ActorInitializationRules.prepare(actor,book,ai,progression,{},equipment,0)
		check(prepared["ok"],"source actor initializes with complete dependencies: "+code)
		if not prepared["ok"]: continue
		templates[code] = prepared["actor"]
		initial_rows += 1
		check(prepared["actor"]["traversal"] == data["source"]["traversal"],"source traversal survives initialization: "+code)
		check(ProgressionRules.JobStats.supported(prepared["actor"]["growth_profile"]),"source numeric job is supported: "+code)
	check(templates.size() == initial_rows and initial_rows >= 25,"all requested and encounter source templates exist (%d)" % initial_rows)
	for row in packet["stats"]:
		var c: Dictionary = row["input"]
		if c["actor"] in blocked_actors and c["name"] != "unequipped": continue # Source weapon geometry has an explicit blocker; only 008 carries unequipped native rows.
		if not templates.has(c["actor"]): continue
		var actor: Dictionary = templates[c["actor"]].duplicate(true)
		actor["growth_profile"] = row["profile"].duplicate(true)
		actor["player_mode"] = int(row["profile"]["source"]["mode"]) # the native rows ran with live +0x28 = this word
		actor["combat_profile"].merge(c["attributes"],true)
		actor.merge({"hp":int(c["hp"]),"mp":int(c["mp"]),"level":int(c["level"]),"base_move_point":int(c["base_move"]),"equipment":[]},true)
		for i in range(6):
			if int(c["equipment"][i]): actor["equipment"].append({"slot":EquipmentRules.SLOTS[i],"item_code":int(c["equipment"][i])})
		check(ProgressionRules.refresh_input_error(actor,equipment) == "","numeric input remains valid: "+str(c))
		for native in row["native"]:
			actor = ProgressionRules.refresh_growth_stats(actor,equipment)
			var expected: Dictionary = native["values"]
			for key in ["max_hp","max_mp","move_point"]: check(actor[key] == expected[key],"complete native refresh "+key)
			check(actor["hp"] == expected["current_hp"] and actor["mp"] == expected["current_mp"] and actor["live_speed"] == expected["speed"],"native current-resource clamps and speed")
			for pair in [["attack","live_attack_damage"],["defense","live_defense"],["magic_attack","live_magic_attack"],["hit_rate","live_hit_ratio"],["avoid_hit_ratio","avoid_hit_ratio"],["attack_back","attack_back"],["attack_damagex2","attack_damagex2"]]:
				check(actor["combat_profile"][pair[1]] == expected[pair[0]],"source refresh "+pair[0]+" ("+str(c["actor"])+" "+str(c["name"])+": "+str(actor["combat_profile"][pair[1]])+" vs "+str(expected[pair[0]])+")")
			check(actor["combat_profile"]["resist_by_type"] == expected["resist_by_type"],"native five resistance values ("+str(c["actor"])+" "+str(c["name"])+": "+str(actor["combat_profile"]["resist_by_type"])+" vs "+str(expected["resist_by_type"])+")")
	for row in packet["growth"]:
		var c: Dictionary = row["input"]
		var expected: Dictionary = row["native"]
		var profile: Dictionary = roles[c["actor"]]["profile"]
		if c["kind"] == "infer":
			check(EntryGrowthRules.inferred_level(c["attributes"]) == int(expected["level"]),"source level inference")
			continue
		if c["kind"] == "allocate":
			var allocation := EntryGrowthRules.allocate(c["attributes"],int(c["level"]),int(c["exp"]),mini(2000,(int(c["level"])+1)*50),profile["caps"],int(profile["job_code"]),int(c["points"]))
			check(allocation["attributes"] == expected["attributes"] and allocation["level"] == int(expected["level"]) and allocation["exp"] == int(expected["exp"]),"new job native quotas and cap fallback")
			continue
		var source: Dictionary = entry_sources[c["actor"]]
		var input := {"job":int(profile["job_code"]),"caps":profile["caps"],"attributes":c["attributes"],"level":int(c["level"]),"exp":int(c["exp"]),"stamina":int(c["stamina"]),"object_kind":int(c["object_kind"]),"parameters":[int(c["range"]),int(c["dispersion"])],"party_levels":c["party"],"gold":int(source["gold"]),"kill_exp":int(source["kill_exp"])}
		var cursor := [0]
		var proposal := EntryGrowthRules.propose(input,func(bound):
			check(cursor[0] < row["draws"].size(),"no extra birth draw")
			if cursor[0] >= row["draws"].size(): return 0
			var draw: Dictionary = row["draws"][cursor[0]]; cursor[0] += 1
			check(int(draw["bound"]) == bound,"original birth random bound")
			return int(draw["value"]))
		check(proposal["ok"] and cursor[0] == row["draws"].size(),"new job entry adjustment completes")
		if not proposal["ok"]: continue
		for key in ["level","exp","stamina","gold","kill_exp","attributes"]: check(proposal["result"][key] == expected[key],"original adjusted "+key)
		for key in EntryGrowthRules.SOURCE_KEYS: check(int(profile["source"][key])+int(proposal["result"]["source_gains"][key]) == int(expected["source"][key]),"independent birth source layer")
	learning_cases(packet,book)

func learning_cases(packet: Dictionary, book: Dictionary) -> void:
	for row in packet["learning"]:
		var c: Dictionary = row["input"]
		if c.get("preview",false): continue # The product commits after allocation; native preview is checked in Python.
		var sample := book.duplicate(true)
		var masks := {}
		for element in ELEMENTS: masks[c["kind"]+":"+element] = 0xffffffff if c["existing"] else 0
		sample["learning"]["actors"]["fixture"] = masks
		var attrs := {}
		for i in range(4): attrs[EntryGrowthRules.KEYS[i]] = int(c["attributes"][i])
		var actor := {"actor_id":"fixture","growth_profile":{"job_code":int(c["job"]),"allocation":"manual"},"level":int(c["level"])+1,"combat_profile":attrs,"learned_skills":[]}
		var acquired := ProgressionRules.Learning.acquire(actor,sample,c["kind"])
		var actual: Array = row["native"]["masks"].map(func(_x):return 0xffffffff if c["existing"] else 0)
		for learned in acquired["added"]:
			var pieces: PackedStringArray = learned["id"].split(":")
			actual[ELEMENTS.find(pieces[1])] |= 1 << (pieces[2].trim_prefix("magicCode").to_int()-1)
		check(actual == row["native"]["masks"],"native class learning order and masks: "+str(c))
		check(actor["learned_skills"].is_empty(),"learning leaves caller immutable")
