extends "res://tests/support/TestSuite.gd"

## Minimum load contract for the level-53 battle scenario content/battles/battle_053.json
## (assembled by `hsl generate level_battle:53` from content/battles/levels/053.json). Only the shared BattleScenario
## loader and the pure WinfailScenarioRules interpreter are used: no PlayLoop, no adapter
## dispatch, no scene. Runtime wiring (campaign.json, BattleScenarioRuleAdapter,
## Runtime/PlayLoop) is covered by run_third_battle_runtime_tests.gd.

const BattleScenario = preload("res://game/battle/runtime/BattleScenario.gd")
const WrdTerrainTiles = preload("res://game/battle/runtime/WrdTerrainTiles.gd")
const Rules = preload("res://game/sim/WinfailScenarioRules.gd")
const WinfailCompiler = preload("res://game/sim/WinfailCompiler.gd")

const SCENARIO_PATH := "res://content/battles/battle_053.json"
const REQUIRED_RESOURCES := [
	"map_texture", "terrain", "battle_seed", "attack_ranges", "actor_walk_manifest", "actor_audio",
	"consumables", "progression", "combat_animation", "interface_audio",
	"opening_timeline", "message_text_evidence",
	"map_objects", "map_object_alignment", "fire_animation", "script_sounds", "portraits", "actor_shape_sets",
]
const REQUIRED_UNIT_KEYS := [
	"id", "actor_id", "battle_actor_role", "coord", "hp", "max_hp", "mp", "max_mp", "move_point", "base_move_point",
	"live_speed", "action_ready", "player_commandable", "combat_profile", "weapon_code", "equipment",
	"growth_profile", "status_flags", "status_counters", "no_attack",
]


func _init() -> void:
	tag = "THIRD_BATTLE_SCENARIO_LOAD_TESTS"
	report_checks = false


func _json(path: String) -> Variant:
	return JSON.parse_string(FileAccess.get_file_as_string(path))


func _cells(values: Array) -> Array:
	var result: Array = []
	for value in values:
		result.append(BattleScenario.vector2i(value))
	return result


func run() -> void:
	var scenario: Dictionary = BattleScenario.load_file(SCENARIO_PATH, "hsl_level_battle.v1")
	_assert_true(bool(scenario.get("ok", false)), "battle_053.json loads with schema hsl_level_battle.v1: %s" % str(scenario.get("error", "")))
	if not bool(scenario.get("ok", false)):
		return
	_assert_eq(scenario.get("id"), "battle_003_level53", "scenario id")
	_assert_eq(scenario.get("rule_adapter"), "winfail", "level 53 runs on the data-driven winfail interpreter")
	_assert_eq(scenario.get("status"), "product-opening-source-adapted", "status label")
	_assert_eq(scenario.get("player_unit_id"), "tina", "controlled unit id")
	_assert_eq(BattleScenario.load_file(SCENARIO_PATH, "hsl_third_battle.v1").get("error"), "unsupported_scenario_schema", "the retired dedicated schema id is rejected")

	for key in REQUIRED_RESOURCES:
		var path := BattleScenario.resource_path(scenario, key)
		_assert_true(path.begins_with("res://") and (FileAccess.file_exists(path) or ResourceLoader.exists(path)), "resource %s exists: %s" % [key, path])
	_assert_eq(BattleScenario.command_flags(scenario), {"has_magic": false, "has_special": false}, "placeholder command flags stay off")
	_assert_eq(BattleScenario.logical_viewport_size(scenario), Vector2i(640, 480), "shared logical viewport")
	_assert_eq(BattleScenario.grid_projection(scenario)["cell_size"], Vector2(32, 32), "32px cells")

	var units: Array = BattleScenario.units(scenario)
	_assert_eq(units.size(), 4, "controlled priest plus three Enemy023 guards")
	var ids: Array = []
	for unit_value in units:
		var unit: Dictionary = unit_value
		ids.append(str(unit.get("id", "")))
		for key in REQUIRED_UNIT_KEYS:
			_assert_true(unit.has(key), "unit %s has %s" % [str(unit.get("id", "")), key])
	_assert_eq(ids, ["enemy023_1", "tina", "enemy023_2", "enemy023_3"], "unit ids in opening order: EVEF gate guard, obj_Story_Player2 install, the two pursuers")
	var tina: Dictionary = units[1]
	_assert_eq(tina.get("actor_id"), "002", "controlled unit is the source002 priest template")
	_assert_eq(tina.get("battle_actor_role"), "player_controlled", "tina is player controlled")
	_assert_eq(tina.get("coord"), Vector2i(20, 23), "first-control cell from obj_Story_Player2 plus STORY053 displacements")
	_assert_eq(int((tina.get("growth_profile", {}) as Dictionary).get("job_code", 0)), 85, "jobPriest85")
	_assert_eq(int(tina.get("weapon_code", 0)), 82, "錫杖 82")
	_assert_eq(int(tina.get("max_hp", 0)), 35, "job85 refresh HP")
	_assert_eq(int(tina.get("max_mp", 0)), 19, "job85 refresh MP")
	_assert_eq(tina.get("class_id"), "Player002", "the controlled unit is registered slot 1 (Player002), never a reinforcement class")
	var first: Dictionary = BattleScenario.load_file("res://content/battles/first_battle.json")
	var first_guard: Dictionary = {}
	for unit_value in BattleScenario.units(first):
		if str((unit_value as Dictionary).get("actor_id", "")) == "023":
			first_guard = unit_value
			break
	for index in [0, 2, 3]:
		var guard: Dictionary = units[index]
		_assert_eq(guard.get("class_id"), "Enemy023", "%s class" % str(guard.get("id", "")))
		_assert_eq(guard.get("battle_actor_role"), "enemy_ai", "%s is an enemy" % str(guard.get("id", "")))
		_assert_eq(guard.get("combat_profile"), first_guard.get("combat_profile"), "%s reuses the first-battle 023 combat profile" % str(guard.get("id", "")))
		_assert_eq(guard.get("equipment"), first_guard.get("equipment"), "%s reuses the first-battle 023 equipment" % str(guard.get("id", "")))
	_assert_eq(units[0].get("coord"), Vector2i(30, 36), "EVEF gate guard cell")
	_assert_eq(units[2].get("coord"), Vector2i(29, 24), "first pursuer walk target cell")
	_assert_eq(units[3].get("coord"), Vector2i(27, 23), "second pursuer walk target cell")

	# Shared data the PlayLoop bootstrap reads per actor must know both actors.
	var attack_ranges: Dictionary = _json(BattleScenario.resource_path(scenario, "attack_ranges"))
	var progression: Dictionary = _json(BattleScenario.resource_path(scenario, "progression"))
	var consumables: Dictionary = _json(BattleScenario.resource_path(scenario, "consumables"))
	var skill_book: Dictionary = _json("res://content/generated/hsl/skills/initial_book.json")
	var ai_profiles: Dictionary = _json("res://content/generated/hsl/ai/profiles.json")
	var rewards: Dictionary = _json("res://content/generated/hsl/combat/rewards.json")
	var walk: Dictionary = _json(BattleScenario.resource_path(scenario, "actor_walk_manifest"))
	var audio: Dictionary = _json(BattleScenario.resource_path(scenario, "actor_audio"))
	for unit_value in units:
		var unit: Dictionary = unit_value
		var actor_id := str(unit.get("actor_id", ""))
		var weapon_id := str(int(unit.get("weapon_code", -1)))
		_assert_true((attack_ranges.get("weapons", {}) as Dictionary).has(weapon_id), "attack range for weapon %s" % weapon_id)
		_assert_true((progression.get("actors", {}) as Dictionary).has(actor_id), "progression for %s" % actor_id)
		_assert_true((skill_book.get("actors", {}) as Dictionary).has(actor_id), "skill book for %s" % actor_id)
		_assert_true((ai_profiles.get("actors", {}) as Dictionary).has(actor_id), "AI profile for %s" % actor_id)
		_assert_true((rewards.get("actors", {}) as Dictionary).has(actor_id), "reward data for %s" % actor_id)
		_assert_true((walk.get("actors", {}) as Dictionary).has(actor_id), "level-53 walk manifest covers %s" % actor_id)
		_assert_true((audio.get("characters", {}) as Dictionary).has(str(int(actor_id))), "level-53 actor audio covers %s" % actor_id)
	_assert_eq((consumables.get("initial_inventory", {}) as Dictionary).get("002", [])[0], 241, "source002 initial 回復藥 comes from the shared consumables")
	_assert_true((walk.get("actors", {}) as Dictionary).has("029"), "the cinematic princess keeps her walk frames for the opening")
	var skills: Dictionary = (skill_book.get("actors", {}) as Dictionary).get("002", {})
	_assert_eq((skills.get("declarations", {}) as Dictionary).get("magic_water"), "治癒之水", "the priest heal is declared by the shared skill book, not by the scenario")

	# Terrain: every roster cell, script landing cell and gate cell is inside the 32x43 grid and walkable.
	var terrain: Dictionary = WrdTerrainTiles.load_tiles(BattleScenario.resource_path(scenario, "terrain"))
	_assert_true(bool(terrain.get("ok", false)), "level053 terrain packet loads")
	_assert_eq(terrain.get("map_size"), Vector2i(32, 43), "level-53 WRD grid")
	var rules: Dictionary = scenario.get("scenario_rules", {})
	var seed: Dictionary = _json(BattleScenario.resource_path(scenario, "battle_seed"))
	_assert_eq(seed.get("schema"), "hsl_battle_seed.v1", "battle_seed payload schema (adapter script payload)")
	_assert_eq(int(seed.get("level", 0)), 53, "seed level")
	_assert_true(Rules.seed_has_winfail(seed), "the seed carries WINFAIL053")
	var derived: Dictionary = Rules.rules_from_seed(seed)
	_assert_true(bool(derived.get("fully_supported", false)), "winfail053 uses only supported tokens")
	_assert_eq(Rules.insert_walk_cells(derived), [Vector2i(5, 18), Vector2i(1, 30)], "the interpreter reads the event landing cells (160,576) / (32,960) from the seed")
	var checked: Array = []
	for unit_value in units:
		checked.append((unit_value as Dictionary).get("coord"))
	checked.append_array(Rules.insert_walk_cells(derived))
	checked.append_array(_cells((rules.get("script_fallback", {}) as Dictionary).get("escape_zone", [])))
	for cell in checked:
		var tile: Dictionary = (terrain.get("tiles", {}) as Dictionary).get(cell, {})
		_assert_true(not tile.is_empty() and not bool(tile.get("blocks_movement", true)), "cell %s is a walkable level-53 tile" % str(cell))

	# Rules: the interpreter is the live source; the scenario carries no win / fail / event
	# mirror of WINFAIL053 and no spawn-cell reinforcement policy. Its inserts are script
	# actor templates like every other level's.
	var win: Dictionary = derived["statuses"]["win"][0]
	var fail: Dictionary = derived["statuses"]["fail"][0]
	var win_args: Array = win["conditions"][0]["args"]
	var zone_cells: Array = _cells(WinfailCompiler.zone_cells([int(str(win_args[2])), int(str(win_args[3])), int(str(win_args[4])), int(str(win_args[5]))], 32))
	_assert_eq(_cells((rules.get("script_fallback", {}) as Dictionary).get("escape_zone", [])), zone_cells, "escape zone equals the win arrival zone cells")
	_assert_eq(WinfailCompiler.first_next_level_event(derived), [1, 1], "next level event [1,1]")
	for key in ["win", "fail", "reinforcement_class_id", "reinforcement_placement_evidence"]:
		_assert_true(not rules.has(key), "scenario_rules carries no %s mirror" % key)
	_assert_eq(rules.get("events", {}), {}, "no event mirror")
	_assert_eq(rules.get("reinforcements", []), [], "no spawn-cell reinforcement template")
	_assert_eq(rules.get("reinforcement_spawn_cells", []), [], "no spawn cells")
	_assert_eq((derived["statuses"]["event"] as Array).size(), 3, "three winfail053 events")
	var templates: Dictionary = scenario.get("script_actor_templates", {})
	_assert_eq(templates.keys(), ["obj_Story_Level53_Enemy23"], "one script actor template: the pursuing guard object")
	var template: Dictionary = templates.get("obj_Story_Level53_Enemy23", {})
	_assert_eq(template.get("kind"), "npc", "the guard template is an npc")
	_assert_eq(template.get("token"), "SID_ENEMY023", "the template answers to SID_ENEMY023")
	var template_actor: Dictionary = template.get("actor", {})
	_assert_eq([template_actor.get("class_id"), template_actor.get("battle_actor_role"), template_actor.get("actor_id")], ["Enemy023", "enemy_ai", "023"], "the template is an enemy 023")
	_assert_eq(template_actor.get("combat_profile"), first_guard.get("combat_profile"), "the template reuses the first-battle 023 combat profile")
	for index in range(3):
		_assert_eq(int(((rules.get("status_timelines", {}) as Dictionary).get("event_%d" % index, {}) as Dictionary).get("playable_event_count", 0)), 2, "event%d insert and walk are played by the cutscene from the committed transaction" % index)
	_assert_eq(str(win["result_message"]["message_id"]), "695", "win board label 695")
	_assert_eq(str(fail["result_message"]["message_id"]), "696", "fail board label 696")
	_assert_eq(str(derived["dead_messages"].get("SID_PLAYER1", "")), "694", "dead message 694")
	_assert_eq(scenario.get("result_labels", {}), {"win_0": "逃出克萊恩城 · 緹娜 逃出", "fail_0": "逃出克萊恩城 · 緹娜 被捕"}, "authored result page labels")

	# initialize_script_state on the loaded roster: the three guards are the initial class roster.
	var battle := {"player_unit_id": str(scenario.get("player_unit_id", "")), "turn": 1, "units": units}
	var loop: Dictionary = Rules.initialize_script_state(battle, scenario, seed)
	_assert_eq(bool(loop.get("scenario_ok", true)), true, "the interpreter accepts the seed")
	var runtime: Dictionary = loop.get("winfail_runtime", {})
	_assert_eq(runtime.get("initial_class_unit_ids", {}), {"Enemy023": ["enemy023_1", "enemy023_2", "enemy023_3"]}, "initial guards remembered")
	_assert_eq(_cells(loop.get("escape_zone_cells", [])), zone_cells, "escape cells in state")
	_assert_eq(loop.get("objective_phase"), rules.get("initial_objective_phase"), "escape objective from the start")
	_assert_eq(loop.get("next_level_event", []), [1, 1], "next level event [1,1] armed at load")
	_assert_eq(Rules.victory_state(loop), {}, "nothing decided at load")
	_assert_eq(Rules.reinforcement_deficits(loop), {}, "no deficit at load")
	_assert_eq(runtime.get("speaker_resource_ids", {}), (scenario.get("opening", {}) as Dictionary).get("speaker_resource_ids", {}), "speaker ids reach the rules state")
	_assert_eq((runtime.get("token_resolution", {}) as Dictionary).get("SID_PLAYER1", {}), {"source": "binding", "unit_ids": ["tina"]}, "SID_PLAYER1 resolves through the opening binding")
	_assert_eq((runtime.get("token_resolution", {}) as Dictionary).get("SID_ENEMY023", {}).get("unit_ids", []), ["enemy023_1", "enemy023_2", "enemy023_3"], "SID_ENEMY023 is the whole guard class despite the SID_ENEMY023/1 speaker binding")
	_assert_eq(runtime.get("unresolved_tokens", []), [], "every script token resolves")
	var board: Dictionary = Rules.objective_board(loop)
	_assert_eq((board.get("win", []) as Array).size(), 1, "win board row from the scenario speaker ids")

	# Opening bindings resolve to roster units or the declared story cast.
	var bindings: Dictionary = (scenario.get("opening", {}) as Dictionary).get("actor_bindings", {})
	var story_ids: Array = []
	for actor in scenario.get("story_actors", []):
		story_ids.append(str((actor as Dictionary).get("id", "")))
	for key in bindings:
		var unit_id := str((bindings[key] as Dictionary).get("unit_id", ""))
		_assert_true(ids.has(unit_id) or story_ids.has(unit_id), "binding %s -> %s resolves" % [str(key), unit_id])
	_assert_eq(str((bindings.get("SID_PLAYER1/1", {}) as Dictionary).get("actor_id", "")), "002", "SID_PLAYER1 binds the 002 unit")
	_assert_eq(str((bindings.get("SID_ENEMY029/1", {}) as Dictionary).get("unit_id", "")), "actor029_1", "the cinematic princess is story cast")
	_assert_eq(story_ids, ["actor029_1"], "one opening-only actor")
	var timeline: Dictionary = _json(BattleScenario.resource_path(scenario, "opening_timeline"))
	_assert_eq(timeline.get("source_script"), "story053", "STORY053 timeline")
	_assert_eq(int(timeline.get("event_count", 0)), 46, "46 compiled events")
