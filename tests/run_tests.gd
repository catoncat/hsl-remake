extends "res://tests/support/TestSuite.gd"

const ActorRoleRules = preload("res://game/sim/ActorRoleRules.gd")
const ProgressionRules = preload("res://game/sim/ProgressionRules.gd")
const EquipmentCatalog = preload("res://game/battle/runtime/EquipmentCatalog.gd")
const TacticalGridRules = preload("res://game/sim/TacticalGridRules.gd")
const CoreCombatRules = preload("res://game/sim/CoreCombatRules.gd")
const CoreTurnQueue = preload("res://game/sim/CoreTurnQueue.gd")
const BattlePlayLoop = preload("res://game/battle/scene/BattlePlayLoop.gd")
const BattleFixture = preload("res://tests/support/BattleFixture.gd")
const WrdTerrainTiles = preload("res://game/battle/runtime/WrdTerrainTiles.gd")
const BattleCameraController = preload("res://game/battle/runtime/BattleCameraController.gd")
const BattleScenario = preload("res://game/battle/runtime/BattleScenario.gd")
const BattleScenarioRuleAdapter = preload("res://game/sim/BattleScenarioRuleAdapter.gd")
const WinfailScenarioRules = preload("res://game/sim/WinfailScenarioRules.gd")
const WinfailCompiler = preload("res://game/sim/WinfailCompiler.gd")
const MapSceneConfig = preload("res://game/battle/runtime/MapSceneConfig.gd")
const BattleOutcome = preload("res://game/sim/BattleOutcome.gd")
const DamageRandom = preload("res://game/sim/DamageRandomStream.gd")


func _init() -> void:
	tag = "CORE_RULE_TESTS"
	report_checks = false


func run() -> void:
	_test_movement_respects_terrain_and_blocking()
	_test_attack_range()
	_test_core_combat_rules_hit_and_damage_packet()
	_test_core_turn_queue_speed_sort_and_bcmd_icons()
	_test_real_equal_speed_pairs_follow_registration_slots()
	_test_first_battle_fixture_contract()
	_test_first_battle_scenario_contract()
	_test_battle_camera_controller_contract()
	_test_shared_battle_scenario_normalization()
	_test_second_battle_rule_adapter_seed()
	_test_second_battle_play_loop_bootstrap()
	_test_initial_npc_turns()
	_test_battle_scene_play_loop_mechanics()
	_test_live_hit_resolution()
	_test_first_battle_live_handoff()
	_test_live_weapon_ranges()
	_test_live_counter_exchange()
	_test_experience_and_level_up()
	_test_class_change_rule_check()
	_test_battle_actor_roles_gate_player_control_and_targets()
	_test_project_uses_640x480_viewport()


func _has_coord(coords: Array, coord: Vector2i) -> bool:
	return coords.find(coord) != -1


func _sample_tiles() -> Dictionary:
	var tiles := {}
	for y in range(4):
		for x in range(5):
			tiles[Vector2i(x, y)] = {
				"terrain": "road",
				"move_cost": 1,
				"defense_bonus": 0,
				"evasion_bonus": 0,
				"blocks_movement": false,
			}
	tiles[Vector2i(2, 1)]["move_cost"] = 3
	tiles[Vector2i(3, 1)]["blocks_movement"] = true
	return tiles


func _test_movement_respects_terrain_and_blocking() -> void:
	var unit := {"id": "leonard", "team": "player", "battle_actor_role": "player_controlled", "traversal": {"flying": false, "no_block": false, "size_type": 0}, "coord": Vector2i(1, 1), "move_point": 3, "hp": 28}
	var units := [
		unit,
		{"id": "ally", "team": "ally", "battle_actor_role": "friendly_ai", "traversal": {"flying": false, "no_block": false, "size_type": 0}, "coord": Vector2i(1, 2), "move_point": 3, "hp": 20},
	]
	var reachable: Array = TacticalGridRules.movement_range(unit, units, _sample_tiles(), Vector2i(5, 4))
	_assert_true(_has_coord(reachable, Vector2i(0, 1)), "road tile inside range should be reachable")
	_assert_true(not _has_coord(reachable, Vector2i(1, 2)), "occupied ally tile should block movement")
	_assert_true(not _has_coord(reachable, Vector2i(3, 1)), "blocked terrain should not be reachable")
	_assert_true(not _has_coord(reachable, Vector2i(4, 1)), "expensive terrain should limit travel budget")
	var envelope: Dictionary = TacticalGridRules.movement_reachability_envelope(unit, units, _sample_tiles(), Vector2i(5, 4))
	_assert_eq(envelope.get("schema", ""), "hsl_movement_reachability.v1", "movement envelope should expose a stable schema")
	_assert_eq(envelope.get("start_coord", Vector2i.ZERO), Vector2i(1, 1), "movement envelope should retain start coord")
	_assert_eq(int(envelope.get("move_budget", 0)), 3, "movement envelope should retain move budget")
	_assert_eq(int(envelope.get("reachable_by_coord", {}).get(Vector2i(0, 1), {}).get("cost", 0)), 1, "movement envelope should retain tile cost")
	_assert_eq(envelope.get("reachable_by_coord", {}).get(Vector2i(0, 1), {}).get("path", []), [Vector2i(1, 1), Vector2i(0, 1)], "movement envelope should retain path")
	_assert_true(envelope.get("blocked_coords", {}).has(Vector2i(1, 2)), "movement envelope should retain occupied blocker")
	_assert_true(envelope.get("blocked_coords", {}).has(Vector2i(3, 1)), "movement envelope should retain terrain blocker")


func _test_attack_range() -> void:
	var mage := {"id": "mage", "team": "enemy", "coord": Vector2i(4, 1), "stats": {"str": 4, "agi": 7, "mind": 11, "vit": 4}}
	var leonard := {"id": "leonard", "team": "player", "coord": Vector2i(1, 1), "hp": 22, "stats": {"str": 12, "agi": 8, "mind": 4, "vit": 9}}
	var skill := {"id": "arcane_bolt", "damage_type": "magic", "power": 5, "multiplier": 1.0, "base_hit": 82, "min_range": 1, "max_range": 3}
	var attack_tiles: Array = TacticalGridRules.attack_range(mage["coord"], 1, 3, Vector2i(6, 4))
	_assert_true(_has_coord(attack_tiles, Vector2i(1, 1)), "range 3 mage should threaten Leonard")


func _stable_half_rng(n: int) -> int:
	if n <= 0:
		return 0
	return n / 2


func _test_core_turn_queue_speed_sort_and_bcmd_icons() -> void:
	var summary: Dictionary = CoreTurnQueue.packet_summary()
	_assert_eq(summary.get("schema", ""), "hsl_core_turn_queue_surface.v1", "turn queue surface should expose stable schema")
	_assert_eq(summary.get("rebuild_function", ""), "0x407340", "turn queue should cite rebuild address")
	_assert_eq(summary.get("advance_function", ""), "0x407510", "turn queue should cite advance address")
	_assert_eq(summary.get("sort_key", ""), "live_speed", "turn queue sort key must be live_speed")

	var queue: Dictionary = CoreTurnQueue.rebuild([
		{"id": "slow", "live_speed": 4, "action_ready": true},
		{"id": "fast", "live_speed": 12, "action_ready": true},
		{"id": "mid", "live_speed": 8, "action_ready": true},
	])
	_assert_eq(str((queue.get("slots", [])[0] as Dictionary).get("id", "")), "fast", "rebuild should sort descending by live_speed")
	_assert_eq(str((queue.get("slots", [])[1] as Dictionary).get("id", "")), "mid", "mid speed should be second")
	_assert_eq(str((queue.get("slots", [])[2] as Dictionary).get("id", "")), "slow", "slow should be last")
	var cur: Dictionary = CoreTurnQueue.current(queue)
	_assert_eq(str(cur.get("id", "")), "fast", "current should be fastest actor")

	var after: Dictionary = CoreTurnQueue.end_turn(queue, [
		{"id": "slow", "live_speed": 4},
		{"id": "fast", "live_speed": 12},
		{"id": "mid", "live_speed": 8},
	])
	_assert_eq(str(CoreTurnQueue.current(after).get("id", "")), "mid", "end_turn should advance to next speed slot")
	_assert_eq(after.get("advanced_via", ""), "0x407510", "advance should cite recovered address")
	var changed_speeds := [
		{"id": "slow", "live_speed": 20},
		{"id": "fast", "live_speed": 4},
		{"id": "mid", "live_speed": 8},
	]
	var before_wrap: Dictionary = CoreTurnQueue.end_turn(after, changed_speeds)
	_assert_eq(str(CoreTurnQueue.current(before_wrap).get("id", "")), "slow", "live speed changes must not retroactively reorder the current round")
	var after_wrap: Dictionary = CoreTurnQueue.end_turn(before_wrap, changed_speeds)
	_assert_eq(str(CoreTurnQueue.current(after_wrap).get("id", "")), "slow", "round wrap must rebuild from current live speeds")
	_assert_eq(int(CoreTurnQueue.current(after_wrap).get("live_speed", 0)), 20, "rebuilt queue must consume the refreshed live speed")
	_assert_eq(int(after_wrap.get("round", 0)), int(queue.get("round", 0)) + 1, "queue wrap should advance the round once")
	# 0x407660 reserves registration slots 0..19 for players (+0xa0 = PLAYERS code − 1) and
	# gives NPCs the next free slot from 20 in creation order; 0x407340 collects from slot 0
	# before its stable descending sort, so equal speeds put players first (by slot), then
	# NPCs in roster order. Faster NPCs still lead.
	var registration: Dictionary = CoreTurnQueue.rebuild([
		{"id": "npc_a", "live_speed": 14},
		{"id": "tina", "live_speed": 14, "actor_id": "002", "growth_profile": {"allocation": "manual"}},
		{"id": "npc_b", "live_speed": 14},
		{"id": "leonard", "live_speed": 14, "actor_id": "001", "growth_profile": {"allocation": "manual"}},
		{"id": "npc_fast", "live_speed": 15},
		{"id": "npc_c", "live_speed": 14, "actor_id": "023", "growth_profile": {"allocation": "fixed_template"}},
	])
	_assert_eq(registration["slots"].map(func(slot): return slot["id"]), ["npc_fast", "leonard", "tina", "npc_a", "npc_b", "npc_c"], "equal speed: registered players first by PLAYERS slot, then NPCs in creation order (0x407660 / 0x407340)")
	_assert_eq([CoreTurnQueue.registration_slot({"actor_id": "001", "growth_profile": {"allocation": "manual"}}), CoreTurnQueue.registration_slot({"actor_id": "023", "growth_profile": {"allocation": "fixed_template"}})], [0, -1], "registration slot: player code − 1, NPC none")

	_assert_eq(CoreTurnQueue.command_name(110), "move", "BCMD 110 must be move")
	_assert_eq(CoreTurnQueue.command_name(111), "attack", "BCMD 111 must be attack")
	_assert_eq(CoreTurnQueue.command_name(113), "wait", "BCMD 113 must be wait")
	_assert_eq(CoreTurnQueue.command_name(122), "status", "BCMD 122 must be status")
	var menu: Dictionary = CoreTurnQueue.build_command_menu(false, false)
	var cmds: Array = menu.get("commands", [])
	_assert_eq(cmds.size(), 5, "default menu without magic/special should be 5 icons")
	_assert_eq(str((cmds[0] as Dictionary).get("command", "")), "move", "default menu should start with move")
	_assert_eq(str((cmds[3] as Dictionary).get("command", "")), "wait", "default menu should include wait")
	_assert_eq(str((cmds[4] as Dictionary).get("command", "")), "status", "default menu should end with status")
	_assert_eq(menu.get("source_address", ""), "0x43ea30", "menu builder should cite 0x43ea30")


## Real equal-speed pairs on the opening queues the PlayLoop builds. static-derived
## docs/evidence_packets/static_reverse/initial_battle_initiative.md «Registration order is
## not simply EVEF order»: 0x407660 gives registered players slot PLAYERS code − 1 (< 20) and
## every other actor the cursor slot from 20 (reset once per level load, 0x407260 via
## 0x42da92) in creation order — EVEF record order, then the STORY inserts; 0x407340 walks
## slots 0..199 and stable-sorts by +0xb8. tools/hsltools/checks/registration_order.py
## (check registration_order) pins every battlefield roster; this pins real pairs end to end.
static func equal_speed_npc_inversions(loop: Dictionary) -> Array:
	var roster := {}
	var units: Array = loop.get("units", [])
	for index in range(units.size()):
		roster[str(units[index].get("id", ""))] = {"index": index, "npc": CoreTurnQueue.registration_slot(units[index]) < 0}
	var slots: Array = loop["turn_queue"]["slots"]
	var inversions: Array = []
	for i in range(slots.size()):
		for j in range(i + 1, slots.size()):
			var first: Dictionary = roster.get(str(slots[i]["id"]), {})
			var second: Dictionary = roster.get(str(slots[j]["id"]), {})
			if int(slots[i]["live_speed"]) == int(slots[j]["live_speed"]) and first.get("npc", false) and second.get("npc", false) and int(first["index"]) > int(second["index"]):
				inversions.append("%s/%s" % [slots[i]["id"], slots[j]["id"]])
	return inversions


func _queue_window(loop: Dictionary, ids: Array) -> Array:
	var slots: Array = loop["turn_queue"]["slots"]
	var order: Array = slots.map(func(slot): return str(slot["id"]))
	var speeds: Array = []
	var positions: Array = []
	for id in ids:
		var at := order.find(id)
		positions.append(at)
		speeds.append(int(slots[at]["live_speed"]) if at >= 0 else -1)
	return [positions, speeds]


func _test_real_equal_speed_pairs_follow_registration_slots() -> void:
	# First battle (level 51): runtime-measured battle_051_ai_moves — Leonard (reserved slot 0)
	# acts before the speed-14 friendly 023s (EVEF records 17, 18 → cursor slots in that order).
	var first := BattlePlayLoop.create([], "", BattleScenario.load_file("res://content/battles/battle_051.json"), 7)
	_assert_eq(_queue_window(first, ["leonard", "actor023_1", "actor023_2"]), [[5, 6, 7], [14, 14, 14]], "level 51 opening: Leonard 5, 023_1 6, 023_2 7 at equal speed 14 (player slot, then EVEF records 17/18)")
	_assert_eq(equal_speed_npc_inversions(first), [], "level 51 opening: equal-speed NPCs act in registration (creation) order")
	# Level 6: seven EVEF 023s (records 45..51) take cursor slots before the three STORY006
	# inserted 023 guards (story_insert 5..7); EVEF 062s (records 33..37) before 061s (38..44).
	var sixth := BattlePlayLoop.create([], "", BattleScenario.load_file("res://content/battles/battle_006.json"), 7)
	var guards := _queue_window(sixth, ["leonard", "actor023_7", "guard023_1", "guard023_2", "guard023_3"])
	_assert_eq(guards[1], [14, 14, 14, 14, 14], "level 6 opening: Leonard, EVEF 023_7 and the inserted 023 guards share speed 14")
	var at: Array = guards[0]
	_assert_true(at[0] >= 0 and at[0] < at[1] and at[1] + 1 == at[2] and at[2] + 1 == at[3] and at[3] + 1 == at[4], "level 6 opening: Leonard, then EVEF 023_7 directly before STORY inserts 023 guard 1, 2, 3 (%s)" % str(at))
	var sixty := _queue_window(sixth, ["actor062_5", "actor061_1"])
	_assert_eq([sixty[1], int(sixty[0][0]) + 1 == int(sixty[0][1])], [[10, 10], true], "level 6 opening: EVEF record 37 (062_5) directly before record 38 (061_1) at speed 10")
	_assert_eq(equal_speed_npc_inversions(sixth), [], "level 6 opening: equal-speed NPCs act in registration (creation) order")


func _test_shared_battle_scenario_normalization() -> void:
	var synthetic := {
		"resources": {"terrain": "res://example.json"},
		"playable_units": [
			{"id": "hero", "coord": [3, 4], "move_point": 6, "live_speed": 9},
			"not-a-unit",
		],
		"view": {
			"logical_viewport": [800, 600],
			"grid_projection": {"origin": [8, 12], "cell_size": [24, 20]},
		},
		"commands": {"has_magic": true},
	}
	_assert_eq(BattleScenario.resource_path(synthetic, "terrain"), "res://example.json", "shared scenario loader should expose resource paths without first-battle semantics")
	var units: Array = BattleScenario.units(synthetic)
	_assert_eq(units.size(), 1, "shared scenario normalization should ignore malformed roster entries")
	_assert_eq((units[0] as Dictionary).get("grid_coord"), Vector2i(3, 4), "shared scenario normalization should normalize grid coordinates")
	_assert_eq((units[0] as Dictionary).get("move_point"), 6, "shared scenario retains the live source movement budget")
	_assert_eq((units[0] as Dictionary).get("speed"), 9, "shared scenario normalization should map live speed")
	_assert_eq(BattleScenario.logical_viewport_size(synthetic), Vector2i(800, 600), "shared scenario normalization should not assume first-battle viewport size")
	var projection: Dictionary = BattleScenario.grid_projection(synthetic)
	_assert_eq(projection.get("origin"), Vector2(8, 12), "shared scenario normalization should preserve arbitrary projection origins")
	_assert_eq(projection.get("cell_size"), Vector2(24, 20), "shared scenario normalization should preserve arbitrary cell sizes")
	_assert_eq(BattleScenario.command_flags(synthetic), {"has_magic": true, "has_special": false}, "shared scenario command flags should normalize absent values")


func _test_second_battle_rule_adapter_seed() -> void:
	var seed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://content/generated/hsl/chapter01/battle052_seed.json"))
	_assert_true(typeof(seed) == TYPE_DICTIONARY, "tracked battle-52 seed should parse")
	if typeof(seed) != TYPE_DICTIONARY:
		return
	var rules := WinfailScenarioRules.rules_from_seed(seed)
	_assert_eq(int(rules.get("source_level", 0)), 52, "battle 52 rules come from the level-52 seed")
	_assert_eq(rules.get("unsupported_tokens", []), [], "WINFAIL052 uses only supported tokens")
	var win: Dictionary = rules["statuses"]["win"][0]
	var fail: Dictionary = rules["statuses"]["fail"][0]
	_assert_eq(win["conditions"][0]["args"], ["1", "SID_ENEMY025"], "battle 52 win rule should preserve the source boss SID")
	_assert_eq(fail["conditions"][0]["args"], ["1", "SID_PLAYER0"], "battle 52 fail rule should preserve the source player SID")
	_assert_eq(WinfailCompiler.first_next_level_event(rules), [58, 58], "battle 52 win rule should preserve next level/event")
	var event0: Dictionary = rules["statuses"]["event"][0]
	var event1: Dictionary = rules["statuses"]["event"][1]
	_assert_eq(event0["conditions"][0]["args"], ["SID_PLAYER0", "SID_ENEMY025"], "battle 52 event 0 should preserve its attacked pair")
	_assert_eq(event1["conditions"][0]["args"], ["SID_ENEMY021", "2"], "battle 52 event 1 should preserve its reinforcement class SID and enemy-count threshold")
	_assert_eq((event1["inserts"] as Array).size(), 4, "battle 52 event 1 should preserve its four scripted inserts")
	_assert_eq(int((seed.get("scripts", {}).get("story", {}).get("action_counts", {}) as Dictionary).get("actInsertObject", 0)), 8, "battle 52 opening should preserve eight active scripted object inserts")

	var scenario := {
		"rule_adapter": "winfail",
		"scenario_rules": {"reinforcement_class_id": "Enemy021"},
		"opening": {"actor_bindings": {"SID_PLAYER0/1": {"unit_id": "leonard"}, "SID_ENEMY025/1": {"unit_id": "emperor"}}},
	}
	var battle := {
		"rule_adapter": "winfail",
		"scenario_ok": true,
		"player_unit_id": "leonard",
		"units": [
			{"id": "leonard", "hp": 30, "defeated": false, "class_id": "Player001"},
			{"id": "emperor", "hp": 30, "defeated": false, "class_id": "Enemy025"},
			{"id": "enemy021_1", "hp": 20, "defeated": false, "class_id": "Enemy021"},
		],
		"last_attack": {},
	}
	battle = BattleScenarioRuleAdapter.initialize_script_state(battle, scenario, seed)
	_assert_eq(battle["winfail_runtime"]["token_resolution"]["SID_ENEMY025"]["unit_ids"], ["emperor"], "the interpreter should map the source boss token to the bound scenario unit id")
	battle = BattleScenarioRuleAdapter.run_event_hooks(battle)
	_assert_eq(BattleScenarioRuleAdapter.reinforcement_deficits(battle), {"Enemy021": 4}, "the interpreter should preserve the four-insert reinforcement event when the threshold is reached")
	_assert_eq(BattleScenarioRuleAdapter.victory_state(battle), {}, "battle 52 should continue while player and boss live")
	battle["last_attack"] = {"attacker_id": "leonard", "defender_id": "emperor"}
	battle = BattleScenarioRuleAdapter.run_event_hooks(battle, true)
	_assert_true((battle.get("event_log", []) as Array).has("event_0"), "battle 52 attack event should fire only through the adapter seam")
	for unit in battle["units"]:
		if unit["id"] == "emperor":
			unit["defeated"] = true
	_assert_eq(BattleScenarioRuleAdapter.victory_state(battle), BattleOutcome.VICTORY_BOSS, "battle 52 should win when its mapped boss is defeated")
	for unit in battle["units"]:
		if unit["id"] == "leonard":
			unit["defeated"] = true
	_assert_eq(BattleScenarioRuleAdapter.victory_state(battle), BattleOutcome.DEFEAT_FALLEN, "player defeat should take precedence if both terminal actors are down")

	_assert_eq(BattleScenarioRuleAdapter.adapter_id({"schema": "hsl_first_battle.v1"}), "", "the retired first_battle adapter has no schema default: a scenario names its rule_adapter or fails")
	_assert_eq(BattleScenarioRuleAdapter.initialize_script_state({"rule_adapter": "first_battle"}, {"rule_adapter": "first_battle"}, seed).get("scenario_error", ""), "unsupported_rule_adapter", "the retired first_battle adapter id fails explicitly")
	_assert_eq(BattlePlayLoop.create().get("scenario_error", ""), "missing_scenario", "create() has no default battle to fall back to")
	_assert_eq(BattleScenarioRuleAdapter.initialize_script_state({"rule_adapter": "second_battle"}, {"rule_adapter": "second_battle"}, seed).get("scenario_error", ""), "unsupported_rule_adapter", "the retired second_battle adapter id fails explicitly")


func _test_second_battle_play_loop_bootstrap() -> void:
	var scenario := BattleScenario.load_file("res://content/battles/battle_052.json", "hsl_level_battle.v1")
	_assert_true(bool(scenario.get("ok", false)), "second-battle scenario should load through the shared scenario boundary")
	var loop := BattlePlayLoop.create([], "", scenario)
	_assert_true(bool(loop.get("scenario_ok", false)), "the existing PlayLoop should accept the second-battle scenario")
	_assert_eq(loop.get("rule_adapter"), "winfail", "the existing PlayLoop should dispatch second-battle script policy through the interpreter adapter")
	_assert_eq(loop.get("map_size"), Vector2i(20, 40), "the existing PlayLoop should consume level-52 WRD dimensions")
	# 16 → 18: the two code-069 placements are enemy objects the original installs (0x407ec0).
	_assert_eq((loop.get("units", []) as Array).size(), 18, "the existing PlayLoop should normalize the bounded M2 roster")
	_assert_eq(loop["winfail_runtime"]["token_resolution"]["SID_ENEMY025"]["unit_ids"], ["emperor025"], "the interpreter should map the source boss token into live PlayLoop state")
	_assert_eq(int(BattlePlayLoop.unit(loop, "emperor025").get("hp", 0)), 91, "the level-52 boss should use the tracked synthetic baseline")
	loop = BattlePlayLoop.begin_battle(loop)
	_assert_eq(loop.get("interaction"), "ai_resolving", "level-52 should enter the same stepped AI path when its fastest actor is not player-controlled")
	# The two 069 objects hold the lower 0x4c34c0 slots and act before the boss, as the
	# original's first round on this board does (oracle, _enemy_level.py L052).
	var ai_order: Array = []
	for _step in range(4):
		loop = BattlePlayLoop.step_ai_turn(loop)
		ai_order.append(str((loop.get("last_ai_action", {}) as Dictionary).get("actor_id", "")))
		if ai_order.back() == "emperor025": break
	_assert_eq(ai_order, ["enemy069_1", "enemy069_2", "emperor025"], "the level-52 boss should execute through the shared AI turn path")
	_assert_true(not BattleOutcome.decided(loop), "one bounded level-52 AI step should not fabricate a terminal result")


func _test_battle_camera_controller_contract() -> void:
	var config := MapSceneConfig.new()
	config.world_size = Vector2i(768, 768)
	config.logical_viewport_size = Vector2i(640, 480)
	config.grid_projection = {"origin": Vector2.ZERO, "cell_size": Vector2(32.0, 32.0)}
	var camera := Camera2D.new()
	var controller = BattleCameraController.create(camera, config, Vector2i(640, 480))
	_assert_eq(controller.grid_cell_center_world(Vector2i(15, 17)), Vector2(496, 560), "camera controller should share the map grid-center contract")
	_assert_true(controller.center_on_grid(Vector2i(15, 17)), "camera controller should center a valid map cell")
	_assert_eq(camera.position, Vector2(448, 528), "camera center should clamp against the logical viewport and world bounds")
	_assert_eq(controller.world_to_logical(Vector2(496, 560)), Vector2(368, 272), "world-to-logical should use the camera center")
	_assert_eq(controller.logical_to_world(Vector2(368, 272)), Vector2(496, 560), "logical-to-world should invert world-to-logical")
	_assert_eq(controller.grid_at_logical(Vector2(368, 272)), Vector2i(15, 17), "logical hit testing should resolve through the shared projection")
	_assert_eq(controller.viewport_to_logical(Vector2(640, 480), Vector2(1280, 960)), Vector2(320, 240), "viewport scaling should preserve logical coordinates")
	_assert_eq(controller.logical_to_viewport(Vector2(320, 240), Vector2(1280, 960)), Vector2(640, 480), "logical scaling should invert viewport conversion")
	_assert_true(controller.pan(Vector2.UP, 0.25, 240.0), "camera controller should pan when movement is available")
	_assert_eq(camera.position, Vector2(448, 468), "camera controller should preserve the existing 240px/s pan contract")
	camera.free()


func _test_battle_scene_play_loop_mechanics() -> void:
	var terrain: Dictionary = WrdTerrainTiles.load_tiles()
	_assert_eq(terrain.get("ok", false), true, "level051 terrain tiles should load")
	_assert_eq(terrain.get("map_size", Vector2i.ZERO), Vector2i(24, 24), "level051 should be 24x24")
	_assert_eq(int(terrain.get("blocking_count", 0)), 123, "level051 should report 123 blocking cells")

	var loop: Dictionary = _player_turn_loop()
	_assert_eq(loop.get("schema", ""), "hsl_first_scene_play_loop.v1", "play loop should expose stable schema")
	_assert_eq(loop.get("scenario_schema", ""), BattleFixture.SCHEMA, "play loop should load the fixture scenario schema")
	_assert_eq(loop.get("scenario_path", ""), BattleFixture.PATH, "play loop should identify its fixture scenario path")
	_assert_eq(loop.get("terrain_ok", false), true, "play loop should load WRD terrain")
	_assert_eq(loop.get("formula_source", ""), "core_logic", "play loop should default to core combat formulas")
	var summary: Dictionary = BattlePlayLoop.summary(loop)
	_assert_eq(summary.get("current_actor_id", ""), "leonard", "This command fixture starts at Leonard’s turn")

	loop = BattlePlayLoop.select_player_unit(loop, "leonard")
	_assert_eq(loop.get("interaction", ""), "action_menu", "select Leonard should open action menu")
	var menu_ids: Array = BattlePlayLoop.summary(loop).get("command_ids", [])
	_assert_eq(menu_ids, ["move", "attack", "item", "wait", "status", "special"], "product action menu should expose only implemented move/attack/wait/status commands")
	var unsupported_reject: Dictionary = BattlePlayLoop.choose_command(loop, "steal").get("last_command_reject", {})
	_assert_eq(unsupported_reject.get("reason", ""), "not_implemented", "unimplemented Steal calls should reject honestly; Magic now has a source-owned public path")

	var cells: Array = BattlePlayLoop.movement_cells(loop, "leonard")
	_assert_true(cells.size() > 0, "Leonard should have WRD-reachable cells")
	_assert_true(cells.size() < 61, "WRD blocking should reduce Manhattan diamond")
	var target: Vector2i = cells[0]
	loop = BattlePlayLoop.choose_command(loop, "move")
	loop = BattlePlayLoop.move_unit_to(loop, target)
	_assert_eq(bool(loop.get("moved_this_action", false)), true, "move should mark moved_this_action")
	_assert_eq((_unit_coord(loop, "leonard")), target, "Leonard coord should update")

	# Place an enemy adjacent for attack path.
	_force_unit_coord(loop, "enemy021_1", target + Vector2i(1, 0))
	loop = BattlePlayLoop.choose_command(loop, "attack")
	_assert_eq(loop.get("interaction", ""), "attack_select", "attack command should enter attack select")
	loop = BattlePlayLoop.attack_target(loop, "enemy021_1", Callable(self, "_stable_half_rng"))
	_assert_eq(bool(loop.get("attacked_this_action", false)), true, "attack should mark attacked_this_action")
	_assert_eq(str((loop.get("last_attack", {}) as Dictionary).get("formula_source", "")), "core_logic", "attack should use core_logic")
	_assert_true(int((loop.get("last_attack", {}) as Dictionary).get("damage", 0)) > 0, "core attack should deal damage")

	# Out-of-range reject should stay in attack_select with reason.
	var reject_loop: Dictionary = _player_turn_loop()
	reject_loop = BattlePlayLoop.select_player_unit(reject_loop, "leonard")
	reject_loop = BattlePlayLoop.choose_command(reject_loop, "attack")
	reject_loop = BattlePlayLoop.attack_target(reject_loop, "enemy021_1")
	# With playable spawn, enemy may already be in range after create — force far.
	reject_loop = _player_turn_loop()
	reject_loop = BattlePlayLoop.select_player_unit(reject_loop, "leonard")
	_force_unit_coord(reject_loop, "enemy021_1", Vector2i(0, 0))
	reject_loop = BattlePlayLoop.choose_command(reject_loop, "attack")
	reject_loop = BattlePlayLoop.attack_target(reject_loop, "enemy021_1")
	_assert_eq(bool(reject_loop.get("attacked_this_action", false)), false, "out-of-range attack should not consume")
	_assert_eq(str((reject_loop.get("last_attack_reject", {}) as Dictionary).get("reason", "")), "out_of_range", "out-of-range should report reject reason")
	_assert_eq(reject_loop.get("interaction", ""), "attack_select", "failed attack should remain in attack_select")

	# Instant commit_wait for headless; choose_command(wait) only begins AI resolution.
	loop = BattlePlayLoop.commit_wait(loop, Callable(self, "_stable_half_rng"))
	var after: Dictionary = BattlePlayLoop.summary(loop)
	_assert_eq(after.get("current_actor_id", ""), "leonard", "after AI turns control should return to Leonard")
	_assert_true(int(after.get("last_ai_action_count", 0)) >= 1, "wait should process non-player actors")
	_assert_eq(after.get("interaction", ""), "action_menu", "Leonard should regain action menu")

	var stepped: Dictionary = _player_turn_loop()
	stepped = BattlePlayLoop.select_player_unit(stepped, "leonard")
	stepped = BattlePlayLoop.choose_command(stepped, "wait")
	_assert_eq(stepped.get("interaction", ""), "ai_resolving", "choose wait should begin stepped AI resolution")
	var guard := 0
	while str(stepped.get("interaction", "")) == "ai_resolving" and guard < 16:
		stepped = BattlePlayLoop.step_ai_turn(stepped, Callable(self, "_stable_half_rng"))
		guard += 1
	_assert_eq(stepped.get("interaction", ""), "action_menu", "stepped AI should return to Leonard menu")
	_assert_true(int(BattlePlayLoop.summary(stepped).get("last_ai_action_count", 0)) >= 1, "stepped AI should record actions")


func _test_live_hit_resolution() -> void:
	var isolated_scenario := BattleFixture.scenario()
	var roster := BattleScenario.units(BattleFixture.scenario())
	var player: Dictionary = roster.filter(func(u): return u["id"] == "leonard")[0]
	var enemy: Dictionary = roster.filter(func(u): return u["id"] == "enemy021_1")[0]
	player["combat_profile"]["dex"] = 5
	enemy["combat_profile"]["dex"] = 5 # Isolate the 80% boundary from roster attribute changes.
	player["combat_profile"]["live_hit_ratio"] = 80
	enemy["combat_profile"]["live_hit_ratio"] = 80 # Same controlled boundary for the AI branch below.
	enemy["coord"] = player["coord"] + Vector2i.LEFT
	var boundary_hit := CoreCombatRules.resolve_attack(player, enemy, func(n: int) -> int: return mini(79, n - 1))
	var boundary_miss := CoreCombatRules.resolve_attack(player, enemy, func(n: int) -> int: return mini(80, n - 1))
	_assert_eq(boundary_hit["hit"], true, "raw roll 79 hits an 80 percent chance")
	_assert_eq(boundary_miss["hit"], false, "raw roll 80 misses an 80 percent chance")
	_assert_eq(boundary_miss["damage"], 0, "miss has no damage")
	var draws: Array = []
	var ordered := CoreCombatRules.resolve_attack(player, enemy, func(n: int) -> int:
		draws.append(n)
		return n - 1
	)
	_assert_eq(ordered["hit_roll"], 99, "live raw hit roll is zero-based")
	_assert_true(draws.size() > 1, "damage is sampled even for a miss")
	_assert_eq(draws.back(), 100, "normal strike draws hit only after damage randomness")
	var loop := _player_turn_loop([player, enemy], "", isolated_scenario)
	loop = BattlePlayLoop.select_player_unit(loop, "leonard")
	loop = BattlePlayLoop.choose_command(loop, "attack")
	var before := loop.duplicate(true)
	loop = BattlePlayLoop.attack_target(loop, str(enemy["id"]), Callable(self, "_last_roll_rng"))
	_assert_eq(BattlePlayLoop.unit(loop, str(enemy["id"]))["hp"], enemy["hp"], "player miss preserves target HP")
	_assert_eq(loop["last_attack"]["hit"], false, "miss is recorded for player feedback")
	_assert_eq(BattlePlayLoop.unit(loop, "leonard")["hit_bonus_accum"], 8, "player miss stores compensation in battle owner")
	_assert_eq(loop["attacked_this_action"], true, "miss consumes attack")
	_assert_eq(loop["pending_move"], false, "miss commits the action")
	_assert_eq(before["attacked_this_action"], false, "resolution does not mutate its input")
	loop = BattlePlayLoop.choose_command(loop, "attack")
	_assert_eq(loop["interaction"], "action_menu", "miss cannot be rerolled by reopening Attack")
	var compensated: Dictionary = player.duplicate(true)
	for expected_rate in [80, 88, 96, 100]:
		var strike := CoreCombatRules.resolve_attack(compensated, enemy, Callable(self, "_last_roll_rng"))
		_assert_eq(strike["hit_rate"], expected_rate, "miss compensation increases later normal strike chances")
		_assert_eq(strike["hit"], expected_rate == 100, "accumulated compensation eventually guarantees a hit")
		compensated["hit_bonus_accum"] = strike["hit_bonus_after"]
	_assert_eq(compensated["hit_bonus_accum"], 0, "a damaging hit resets compensation")
	_assert_eq(CoreCombatRules.resolve_attack(compensated, enemy, Callable(self, "_last_roll_rng"))["hit_rate"], 80, "next chance returns to base after hit")
	# Both adjacent and move-then-attack AI paths use the same hit rule.
	for distance in [1, 2]:
		# Right of Leonard: 0x413390 ranks a station right of the target farthest, and the
		# max roll here walks to the first station (0x440b2c), which is then its own cell.
		enemy["coord"] = player["coord"] + Vector2i.RIGHT * distance
		var ai_loop := _player_turn_loop([player, enemy], "", isolated_scenario)
		ai_loop["tiles"] = {}
		_assert_true(not BattlePlayLoop.movement_cells(ai_loop, "leonard").has(enemy["coord"]), "player cannot move into a living enemy")
		ai_loop = BattlePlayLoop.select_player_unit(ai_loop, "leonard")
		# The AI's settlement draws from the loop's damage stream (0x42c780), not from its
		# decision source: take the first seeded stream whose exchange misses uncountered.
		var waited := {}
		for seed in range(1, 400):
			var trial := BattlePlayLoop.copy(ai_loop)
			seed_stream(trial, "damage", seed)
			waited = BattlePlayLoop.commit_wait(trial, Callable(self, "_last_roll_rng"))
			var shown: Dictionary = waited.get("last_ai_action", {})
			if not bool(shown.get("hit", true)) and (shown.get("counter", {}) as Dictionary).is_empty(): break
		ai_loop = waited
		_assert_eq(BattlePlayLoop.unit(ai_loop, "leonard")["hp"], player["hp"], "AI miss must not reduce Leonard HP")
		_assert_eq(bool(ai_loop["last_ai_action"].get("hit", true)), false, "AI miss is visible")
		_assert_eq(ai_loop["last_ai_action"]["kind"], "attack" if distance == 1 else "move_then_attack", "both AI attack paths resolve")
		_assert_eq(ai_loop["turn"], 2, "AI miss still completes its turn")
		# The AI's exchange is the NPC process's (0x4414a0 mode 2): 0x442405 `test mode, 2` skips
		# the +0xb0 write-back, so its miss leaves its compensation as it was.
		_assert_eq(BattlePlayLoop.unit(ai_loop, str(enemy["id"])).get("hit_bonus_accum", 0), 0, "an AI miss leaves its compensation unchanged (NPC process, 0x442405)")
		_assert_eq(BattlePlayLoop.unit(ai_loop, "leonard").get("hit_bonus_accum", 0), 0, "being missed does not increase defender compensation")


func _last_roll_rng(n: int) -> int:
	return n - 1


func _test_first_battle_fixture_contract() -> void:
	# The reviewed level-51 formation stays a pure-loop fixture (development_battle):
	# same roster, positions and unit ids the mechanics suites were written against.
	var scenario: Dictionary = BattleFixture.scenario()
	_assert_true(bool(scenario.get("ok", false)), "first-battle fixture should load")
	_assert_eq(scenario.get("schema", ""), BattleFixture.SCHEMA, "the fixture is a development battle, not a playable scenario")
	_assert_eq(BattleScenarioRuleAdapter.adapter_id(scenario), BattleScenarioRuleAdapter.DEVELOPMENT, "the fixture runs the development objectives")
	var units: Array = BattleScenario.units(scenario)
	_assert_eq(units.size(), 12, "fixture should include every level-51 actor placement")
	_assert_eq(str((units[0] as Dictionary).get("id", "")), "enemy021_1", "fixture should preserve source EVEF order")
	_assert_eq((units.filter(func(u): return u["id"] == "leonard")[0] as Dictionary).get("coord", Vector2i.ZERO), Vector2i(15, 17), "Leonard should stand at his script-derived opening destination")
	var loop := BattleFixture.loop()
	_assert_true(bool(loop.get("scenario_ok", false)), "fixture loop should create: " + str(loop.get("scenario_error", "")))
	_assert_eq(loop.get("objective_phase"), "escape", "the fixture opens in its escape objective")
	_assert_eq(loop.get("escape_zone"), [Vector2i(14, 10)], "the fixture keeps the legacy provisional escape cell")


func _test_first_battle_scenario_contract() -> void:
	# The playable first battle is assembled by level_battle:51 and interpreted by the
	# same winfail rules as every other level: same roster as the reviewed fixture,
	# the arrival cell derived from WINFAIL051 (267,209).
	var scenario := BattleScenario.load_file("res://content/battles/battle_051.json")
	_assert_true(bool(scenario.get("ok", false)), "battle_051 should load")
	_assert_eq(scenario.get("schema", ""), "hsl_level_battle.v1", "the first battle uses the generic level battle schema")
	_assert_eq(int(scenario.get("level", 0)), 51, "the first battle is level 51")
	_assert_eq(BattleScenarioRuleAdapter.adapter_id(scenario), BattleScenarioRuleAdapter.WINFAIL, "the first battle runs the winfail interpreter")
	_assert_eq(scenario.get("player_unit_id", ""), "leonard", "level 51 names Leonard as the controlled unit")
	var units: Array = BattleScenario.units(scenario)
	var fixture_units: Array = BattleScenario.units(BattleFixture.scenario())
	_assert_eq(units.size(), 12, "level 51 should field every EVEF placement")
	for index in range(units.size()):
		var unit: Dictionary = units[index]
		var reviewed: Dictionary = fixture_units[index]
		_assert_eq([unit["actor_id"], unit["battle_actor_role"], unit["grid_coord"], unit["hp"]], [reviewed["actor_id"], reviewed["battle_actor_role"], reviewed["grid_coord"], reviewed["hp"]], "level 51 unit %d matches the reviewed formation" % index)
	_assert_eq(BattleScenario.logical_viewport_size(scenario), Vector2i(640, 480), "scenario should preserve the 640x480 logical viewport")
	var projection: Dictionary = BattleScenario.grid_projection(scenario)
	_assert_eq(projection.get("origin", Vector2.ZERO), Vector2.ZERO, "original actor initialization uses the map grid without a display offset")
	_assert_eq(projection.get("cell_size", Vector2.ZERO), Vector2(32.0, 32.0), "scenario should own the grid cell size")
	_assert_true(BattleScenario.resource_path(scenario, "terrain").ends_with("level051_terrain.json"), "scenario should point to tracked WRD terrain")
	_assert_eq((scenario.get("scenario_rules", {}) as Dictionary).get("script_fallback", {}).get("escape_zone"), [[8.0, 6.0]], "the arrival cell comes from WINFAIL051 actCheckPlayerArrivePos 267,209")
	_assert_eq((scenario.get("scenario_rules", {}) as Dictionary).get("status_timelines", {}).keys(), ["win_0", "win_1", "fail_0", "event_0", "event_1", "event_2", "event_3"], "every WINFAIL051 status compiles to a cutscene timeline")


func _first_battle_hold_loop() -> Dictionary:
	# The playable level 51 at Leonard's first turn with every NPC pinned (move 0, no
	# attack): the winfail counts stay at 5×021 / 2×026 so no reinforcement event fires
	# and the round hooks alone drive the script.
	var scenario := BattleScenario.load_file("res://content/battles/battle_051.json")
	var roster: Array = BattleScenario.units(scenario)
	for unit in roster:
		if str(unit.get("battle_actor_role", "")) != BattlePlayLoop.ROLE_PLAYER:
			unit["move_point"] = 0
			unit["base_move_point"] = 0
			unit["no_attack"] = true
	var loop := _player_turn_loop(roster, "", scenario)
	return BattlePlayLoop.select_player_unit(loop, "leonard")


func _test_first_battle_live_handoff() -> void:
	var loop := _first_battle_hold_loop()
	_assert_true(bool(loop.get("scenario_ok", false)), "level 51 should create through the winfail adapter: " + str(loop.get("scenario_error", "")))
	_assert_eq(loop.get("rule_adapter"), "winfail", "level 51 rules come from the interpreter")
	_assert_eq(loop.get("event_statuses"), [0, 1, 2, 3], "STORY051 arms the four event statuses")
	_assert_eq(loop.get("fail_statuses"), [0], "STORY051 arms the fail status")
	_assert_eq(loop.get("win_statuses"), [], "no win status is armed before the round-6 event")
	_assert_eq(loop.get("objective_phase"), "hold", "the first battle opens in the hold phase")
	for turn in range(2, 7):
		loop = BattlePlayLoop.commit_wait(loop, Callable(self, "_stable_half_rng"))
		_assert_eq(loop.get("turn"), turn, "one completed queue traversal advances one round")
		_assert_eq(loop.get("objective_phase"), "hold" if turn < 6 else "escape", "only round six enables retreat")
		_assert_eq((loop.get("event_log", []) as Array).has("event_2"), turn >= 4, "round four fires the waiting-lines event")
	_assert_eq(loop.get("win_statuses"), [0, 1], "escape and enemy-clear hooks activate together")
	_assert_eq(loop.get("event_statuses"), [], "the switch deletes the reinforcement events and the fired round events disarm themselves")
	_assert_eq(loop.get("escape_zone"), [Vector2i(8, 6)], "the gate cell is the escape zone")
	var departed: Array = (loop.get("winfail_runtime", {}) as Dictionary).get("departed_unit_ids", [])
	_assert_eq(departed, ["actor026_1", "actor021_1", "Enemy021_script_1_2"], "one mage, one soldier and the messenger object leave through the gate")
	var event_messages: Array = BattleScenarioRuleAdapter.story_dialogue_messages(loop).map(func(item): return str(item["message_id"]))
	_assert_eq(event_messages, ["396", "397", "368", "369"], "round 4 and round 6 speak the source lines (companions alive)")
	var fired_keys: Array = (loop.get("winfail_runtime", {}) as Dictionary).get("fired", []).map(func(item): return str(item["key"]))
	_assert_eq(fired_keys, ["event_2", "event_3"], "the round hooks fire the two round-check events once each")
	loop = BattlePlayLoop.commit_wait(loop, Callable(self, "_stable_half_rng"))
	_assert_eq((loop.get("winfail_runtime", {}) as Dictionary).get("fired", []).size(), 2, "script notifications must not repeat on later rounds")
	# Arrival is only committed by Wait/Attack; cancelling a tentative move cannot win.
	_force_unit_coord(loop, "leonard", Vector2i(8, 7))
	loop = BattlePlayLoop.choose_command(loop, "move")
	loop = BattlePlayLoop.move_unit_to(loop, Vector2i(8, 6))
	_assert_eq(loop.get("battle_outcome"), {}, "tentative arrival must remain cancellable")
	loop = BattlePlayLoop.cancel_pending_move(loop)
	_assert_eq(_unit_coord(loop, "leonard"), Vector2i(8, 7), "cancel restores pre-arrival coordinate")
	loop = BattlePlayLoop.choose_command(loop, "move")
	loop = BattlePlayLoop.move_unit_to(loop, Vector2i(8, 6))
	loop = BattlePlayLoop.commit_wait(loop)
	_assert_eq(loop.get("battle_outcome"), BattleOutcome.VICTORY_ESCAPE, "committed Leonard arrival wins before any AI action")
	_assert_eq(loop.get("interaction"), "battle_result", "victory is terminal")
	_assert_eq(loop.get("next_level_event"), [52, 52], "WINFAIL051 win 1 hands the campaign to level 52")
	_assert_eq(BattlePlayLoop.select_player_unit(loop, "leonard"), loop, "selection cannot reopen a finished battle")
	_assert_eq(BattlePlayLoop.commit_wait(loop), loop, "waiting cannot advance a finished battle")
	var clear := _first_battle_hold_loop()
	for unit in clear["units"]:
		if str(unit.get("battle_actor_role", "")) == BattlePlayLoop.ROLE_ENEMY:
			BattlePlayLoop._set_unit_defeated(clear, str(unit["id"]), true)
	clear = BattlePlayLoop.commit_wait(clear, Callable(self, "_stable_half_rng"))
	_assert_eq(clear.get("battle_outcome"), {}, "clearing enemies before the retreat event must not win")
	_assert_true(BattlePlayLoop.unit_coords(clear).keys().any(func(id): return str(id).begins_with("Enemy021_script")), "the depleted hold phase inserts a soldier at the gate instead of ending the battle")
	var late := _first_battle_hold_loop()
	for turn in range(2, 7):
		late = BattlePlayLoop.commit_wait(late, Callable(self, "_stable_half_rng"))
	for unit in late["units"]:
		if str(unit.get("battle_actor_role", "")) == BattlePlayLoop.ROLE_ENEMY:
			BattlePlayLoop._set_unit_defeated(late, str(unit["id"]), true)
	late = BattlePlayLoop.commit_wait(late, Callable(self, "_stable_half_rng"))
	_assert_eq(late.get("battle_outcome"), BattleOutcome.VICTORY_ENEMIES_CLEARED, "enemy clear wins once win status 0 is armed")
	_assert_eq(late.get("next_level_event"), [52, 52], "WINFAIL051 win 0 hands the campaign to level 52")
	var lost := _first_battle_hold_loop()
	BattlePlayLoop._set_unit_defeated(lost, "leonard", true)
	lost = BattlePlayLoop._resolve_outcome(lost)
	_assert_eq(lost.get("battle_outcome"), BattleOutcome.DEFEAT_FALLEN, "Leonard falling fails during hold")


func _test_live_weapon_ranges() -> void:
	var scenario := BattleFixture.scenario()
	var roster := BattleScenario.units(scenario)
	var player: Dictionary = roster.filter(func(u): return u["id"] == "leonard")[0]
	var enemy: Dictionary = roster.filter(func(u): return u["id"] == "enemy021_1")[0]
	player["weapon_code"] = 41
	enemy["coord"] = player["coord"] + Vector2i(2, 0)
	var loop := _player_turn_loop([player, enemy], "", scenario)
	var cells := BattlePlayLoop.attack_cells(loop, "leonard")
	_assert_true(cells.has(enemy["coord"]), "weapon 41 reaches two cardinal cells")
	_assert_true(not cells.has(player["coord"] + Vector2i(1, 1)), "weapon 41 does not invent diagonal reach")
	loop = BattlePlayLoop.select_player_unit(loop, "leonard")
	loop = BattlePlayLoop.choose_command(loop, "attack")
	loop = BattlePlayLoop.attack_target(loop, str(enemy["id"]), Callable(self, "_stable_half_rng"))
	_assert_eq(loop["attacked_this_action"], true, "player resolves a valid two-cell weapon attack")
	player["weapon_code"] = 2
	enemy["weapon_code"] = 41
	loop = _player_turn_loop([player, enemy], "", scenario)
	loop = BattlePlayLoop.select_player_unit(loop, "leonard")
	loop = BattlePlayLoop.commit_wait(loop, Callable(self, "_last_roll_rng"))
	_assert_eq(loop["last_ai_action"]["kind"], "attack", "AI attacks within weapon mask before trying to move")
	_assert_eq(BattlePlayLoop.unit(loop, str(enemy["id"]))["coord"], enemy["coord"], "AI ranged attack preserves position")
	player["weapon_code"] = 99999
	var invalid := _player_turn_loop([player, enemy], "", scenario)
	_assert_eq(invalid["interaction"], "scenario_error", "missing range data cannot silently become melee")
	_assert_eq(invalid["scenario_error"], "missing_unit_attack_range", "missing weapon data is explicit")

	# Source range3CellCircle is consumed as its manifest offsets, with map-edge clipping.
	var circle_player: Dictionary = player.duplicate(true)
	circle_player["coord"] = Vector2i(0, 0)
	circle_player["weapon_code"] = 32
	circle_player["equipment"] = [{"slot": "weapon", "item_code": 32}]
	var circle_loop := _player_turn_loop([circle_player, enemy], "", scenario)
	var circle_cells: Array = BattlePlayLoop.attack_cells(circle_loop, "leonard")
	var expected_circle: Array = []
	for offset in circle_loop["attack_patterns"]["range3CellCircle"]["offsets"]:
		var cell: Vector2i = (circle_player["coord"] as Vector2i) + Vector2i(int(offset[0]), int(offset[1]))
		if cell.x >= 0 and cell.y >= 0 and cell.x < circle_loop["map_size"].x and cell.y < circle_loop["map_size"].y:
			expected_circle.append(cell)
	_assert_eq(circle_cells, expected_circle, "3CellCircle attack cells equal source offsets after boundary clipping")

	# AI target selection and counter eligibility use the same circle offsets.
	var ai_enemy: Dictionary = enemy.duplicate(true)
	ai_enemy["weapon_code"] = 32
	ai_enemy["equipment"] = [{"slot": "weapon", "item_code": 32}]
	ai_enemy["coord"] = circle_player["coord"] + Vector2i(2, 1)
	ai_enemy["combat_profile"]["attack_back"] = 100
	var ai_loop := _player_turn_loop([circle_player, ai_enemy], "", scenario)
	ai_loop = BattlePlayLoop.select_player_unit(ai_loop, "leonard")
	ai_loop = BattlePlayLoop.commit_wait(ai_loop, Callable(self, "_last_roll_rng"))
	_assert_eq(ai_loop["last_ai_action"]["kind"], "attack", "AI attacks a target inside source 3CellCircle offsets")
	_assert_eq(BattlePlayLoop.unit(ai_loop, str(ai_enemy["id"]))["coord"], ai_enemy["coord"], "circle-range AI attacks without moving")

	var counter_loop := _player_turn_loop([circle_player, ai_enemy], "", scenario)
	counter_loop = BattlePlayLoop.select_player_unit(counter_loop, "leonard")
	counter_loop = BattlePlayLoop.choose_command(counter_loop, "attack")
	counter_loop = BattlePlayLoop.attack_target(counter_loop, str(ai_enemy["id"]), Callable(self, "_stable_half_rng"))
	_assert_true(not (counter_loop["last_attack"].get("counter", {}) as Dictionary).is_empty(), "defender in source 3CellCircle can counter")

	# Source item 57 is equipped range0Cell: it remains valid but exposes no hostile target.
	var zero_loop := _player_turn_loop([circle_player, ai_enemy], "", scenario)
	var zero_enemy: Dictionary = BattlePlayLoop.unit(zero_loop, str(ai_enemy["id"]))
	zero_enemy["weapon_code"] = 57
	zero_enemy["equipment"] = [{"slot": "weapon", "item_code": 57}]
	var zero_pattern := BattlePlayLoop.weapon_pattern(zero_loop, zero_enemy)
	_assert_true(bool(zero_pattern.get("ok", false)) and (zero_pattern["offsets"] as Array).is_empty(), "range0Cell source weapon remains equipped without a normal target")


func _test_live_counter_exchange() -> void:
	var scenario := BattleFixture.scenario()
	for route in ["normal", "killed_defender", "out_of_range", "status_block", "no_attack", "counter_kills", "primary_miss"]:
		var roster := BattleScenario.units(scenario)
		var player: Dictionary = roster.filter(func(u): return u["id"] == "leonard")[0]
		var enemy: Dictionary = roster.filter(func(u): return u["id"] == "enemy021_1")[0]
		player["hp"] = 1 if route == "counter_kills" else 100
		enemy["hp"] = 1 if route == "killed_defender" else 100
		player["combat_profile"]["attack_back"] = 100
		enemy["combat_profile"]["attack_back"] = 100
		enemy["coord"] = player["coord"] + Vector2i.LEFT
		if route == "out_of_range":
			player["weapon_code"] = 41
			enemy["coord"] = player["coord"] + Vector2i.LEFT * 2
		if route == "status_block":
			enemy["status_flags"] = 4
			enemy["status_counters"]["paralysis"] = 2
		if route == "no_attack":
			enemy["no_attack"] = true
		var loop := _player_turn_loop([player, enemy], "", scenario)
		loop = BattlePlayLoop.select_player_unit(loop, "leonard")
		loop = BattlePlayLoop.choose_command(loop, "attack")
		var percent_draws: Array = [0]
		loop = BattlePlayLoop.attack_target(loop, str(enemy["id"]), func(n: int) -> int:
			if n == 100:
				percent_draws[0] += 1
			return 99 if route == "primary_miss" and n == 100 and percent_draws[0] == 2 else 0
		)
		var counter: Dictionary = loop["last_attack"]["counter"]
		if route in ["normal", "counter_kills", "primary_miss"]:
			_assert_true(not counter.is_empty(), "eligible survivor counters: " + route)
			_assert_eq(counter.get("attacker_id", ""), enemy["id"], "counter swaps attacker and defender")
			_assert_true(not counter.has("counter"), "100 percent counter on both actors cannot recurse")
			var ordinary := CoreCombatRules.resolve_attack(enemy, player, func(_n: int) -> int: return 0)
			_assert_eq(counter["queued_damage"], maxi(1, int(ordinary["queued_damage"]) * 80 / 100), "counter applies the recovered80 percent scale before its separate critical impact")
		else:
			_assert_true(counter.is_empty(), "counter eligibility gate rejects: " + route)
		if route == "primary_miss":
			_assert_eq(loop["last_attack"]["hit"], false, "primary miss still permits preselected counter")
		if route == "counter_kills":
			_assert_eq(loop["battle_outcome"], BattleOutcome.DEFEAT_FALLEN, "counter kill ends battle before player can act again")
		else:
			_assert_eq(loop["attacked_this_action"], true, "primary action remains consumed")
	var roster := BattleScenario.units(scenario)
	var player: Dictionary = roster.filter(func(u): return u["id"] == "leonard")[0]
	var enemy: Dictionary = roster.filter(func(u): return u["id"] == "enemy021_1")[0]
	player["hp"] = 100
	enemy["hp"] = 100
	player["combat_profile"]["attack_back"] = 100
	enemy["coord"] = player["coord"] + Vector2i.LEFT
	var ai_loop := _player_turn_loop([player, enemy], "", scenario)
	ai_loop = BattlePlayLoop.select_player_unit(ai_loop, "leonard")
	ai_loop = BattlePlayLoop.commit_wait(ai_loop, func(_n: int) -> int: return 0)
	_assert_eq(ai_loop["last_ai_action"]["counter"].get("attacker_id", ""), "leonard", "player can counter an AI attack")
	_assert_true(int(BattlePlayLoop.unit(ai_loop, str(enemy["id"]))["hp"]) < 100, "counter applies real damage to AI attacker")


func _unit_coord(loop: Dictionary, unit_id: String) -> Vector2i:
	for unit_value in loop.get("units", []):
		if typeof(unit_value) == TYPE_DICTIONARY and str((unit_value as Dictionary).get("id", "")) == unit_id:
			return (unit_value as Dictionary).get("coord", Vector2i.ZERO)
	return Vector2i.ZERO


func _force_unit_coord(loop: Dictionary, unit_id: String, coord: Vector2i) -> void:
	var units: Array = loop.get("units", [])
	for i in range(units.size()):
		if typeof(units[i]) != TYPE_DICTIONARY:
			continue
		var unit: Dictionary = units[i]
		if str(unit.get("id", "")) == unit_id:
			unit["coord"] = coord
			unit["grid_coord"] = coord
			units[i] = unit
			loop["units"] = units
			return


func _test_core_combat_rules_hit_and_damage_packet() -> void:
	var summary: Dictionary = CoreCombatRules.packet_summary()
	_assert_eq(summary.get("schema", ""), "hsl_core_combat_rules_surface.v1", "core combat surface should expose stable schema")
	_assert_eq(summary.get("hit_function", ""), "0x409a60", "core combat surface should cite hit address")
	_assert_eq(summary.get("damage_function", ""), "0x409be0", "core combat surface cites the actual entry, not preceding padding")

	var leonard_profile := {
		"live_hit_ratio": 98,
		"live_attack_damage": 23,
		"live_defense": 6,
		"avoid_hit_ratio": 0,
		"dex": 1,
		"str": 1,
		"weapon_damage_variance_lo": -1,
	}
	var enemy_profile := {
		"live_hit_ratio": 90,
		"live_attack_damage": 15,
		"live_defense": 8,
		"avoid_hit_ratio": 0,
		"dex": 1,
		"str": 1,
		"weapon_damage_variance_lo": -1,
	}
	var hit: Dictionary = CoreCombatRules.hit_chance(leonard_profile, enemy_profile)
	_assert_eq(int(hit.get("hit_chance", 0)), 98, "equal-level hit should equal weapon hit_ratio when avoid is 0")
	_assert_eq(hit.get("source_address", ""), "0x409a60", "hit packet should cite recovered address")

	var dmg: Dictionary = CoreCombatRules.preview_damage(leonard_profile, enemy_profile, Callable(self, "_stable_half_rng"))
	_assert_true(int(dmg.get("damage", 0)) >= 1, "core damage preview should return positive damage")
	_assert_eq(int(dmg.get("base_attack_minus_defense", -1)), 15, "core damage should start from attack_damage - defense")
	_assert_eq(dmg.get("source_address", ""), "0x409be0", "damage packet cites the independently executed entry")
	_assert_eq(dmg.get("confidence", ""), "native_numeric_returns", "numeric return evidence remains separate from whole-game equivalence")

	var attacker := {"id": "leonard", "hp": 32, "level": 1, "combat_profile": leonard_profile}
	var defender := {"id": "enemy021", "hp": 18, "level": 1, "combat_profile": enemy_profile}
	var core_preview: Dictionary = CoreCombatRules.preview_attack(attacker, defender, Callable(self, "_stable_half_rng"))
	_assert_eq(core_preview.get("formula_source", ""), "core_logic_packet", "opt-in preview should use core logic packet")
	_assert_eq(int(core_preview.get("hit_rate", 0)), 98, "opt-in core preview hit rate should match hit_chance")
	_assert_true(int(core_preview.get("damage", 0)) >= 1, "opt-in core preview should expose positive damage")


func _test_experience_and_level_up() -> void:
	var unit: Dictionary = BattlePlayLoop.unit(BattleFixture.loop(), "leonard").duplicate(true)
	var equipment_items := EquipmentCatalog.items()
	unit["exp"] = 90
	unit["hp"] = 12
	var before_attack := int(unit["combat_profile"]["live_attack_damage"])
	var result: Dictionary = ProgressionRules.resolve_experience(unit, 30, equipment_items)
	_assert_eq(result["level"], 2, "earned experience must level up")
	_assert_eq(result["exp"], 20, "final awarded experience overflow must be retained")
	_assert_eq(result["pending_stat_points"], 5, "native level-up grants a five-point budget across four attributes")
	_assert_eq(result["max_hp"], 31, "level increment must run the native-derived SwordMan stat refresh")
	_assert_eq(result["hp"], 12, "native stat refresh must not refill current HP")
	_assert_eq(result["combat_profile"]["live_attack_damage"], before_attack + 1, "level itself contributes to refreshed SwordMan attack")
	_assert_eq(result["combat_profile"]["str"], 16, "unconfirmed growth must not change base strength")
	var grown := ProgressionRules.apply_allocation(result, {"str": 2, "dex": 1, "mind": 1, "con": 1}, equipment_items)
	_assert_eq(grown["max_hp"], 33, "four-attribute allocation must recompute health cap")
	_assert_eq(grown["hp"], 12, "confirmed growth must preserve current HP when the maximum rises")
	_assert_eq(grown["combat_profile"]["live_attack_damage"], 57, "strength/dex allocation must use the recovered SwordMan attack formula")
	_assert_eq(grown["combat_profile"]["live_defense"], 43, "derived defense must follow native integer rounding")
	_assert_eq(grown["live_speed"], 15, "dexterity allocation must refresh live speed")
	_assert_eq(grown["combat_profile"]["mind"], 9, "mental allocation must become authoritative live state")
	_assert_eq(grown["combat_profile"]["con"], 13, "constitution allocation must become authoritative live state")
	_assert_eq(grown["pending_stat_points"], 0, "confirmation spends the selected points")
	_assert_eq(ProgressionRules.apply_allocation(grown, {"str": 1}, equipment_items), grown, "spent points cannot be replayed")
	for invalid in [{}, {"str": 6}, {"str": -1}, {"str": 0.5}, {"str": true}, {"other": 1}]:
		_assert_eq(ProgressionRules.apply_allocation(result, invalid, equipment_items), result, "invalid allocation must be atomic and inert")
	var multiple := ProgressionRules.resolve_experience(unit, 300, equipment_items)
	_assert_eq(multiple["level"], 3, "multiple thresholds must be consumed")
	_assert_eq(multiple["pending_stat_points"], 10, "every crossed level contributes up to five points")
	var partial := ProgressionRules.apply_allocation(multiple, {"str": 2}, equipment_items)
	_assert_eq(partial["pending_stat_points"], 8, "partial allocation preserves remaining points")
	var capped := result.duplicate(true)
	capped["combat_profile"]["str"] = int(capped["growth_profile"]["caps"]["str"])
	_assert_eq(ProgressionRules.apply_allocation(capped, {"str": 1}, equipment_items), capped, "an attribute at its native job cap rejects the entire allocation")
	var dead := result.duplicate(true)
	dead["hp"] = 0
	_assert_eq(ProgressionRules.apply_allocation(dead, {"con": 3}, equipment_items), dead, "growth cannot resurrect a defeated unit")
	_assert_eq(ProgressionRules.resolve_experience(result, 0, equipment_items), result, "a zero final award cannot create growth")
	_assert_eq(unit["level"], 1, "pure growth must preserve input")
	_assert_eq(ProgressionRules.exp_to_next(2), 150, "native level-two threshold is 150")
	_assert_eq(ProgressionRules.exp_to_next(39), 2000, "native threshold reaches cap at level 39")
	_assert_eq(ProgressionRules.exp_to_next(50), 2000, "native threshold stays capped")


func _test_class_change_rule_check() -> void:
	var unit := {
		"class_id": "swordsman",
		"level": 12,
		"stats": {"str": 30, "agi": 24, "mind": 7, "vit": 28},
	}
	var rule := {
		"from_class": "swordsman",
		"to_class": "swordmaster",
		"min_level": 12,
		"min_stats": {"str": 30, "agi": 24, "vit": 28},
		"required_items": ["class_token_alpha"],
		"required_flags": {"chapter_one_survived": true},
	}
	_assert_true(ProgressionRules.can_class_change(unit, rule, ["class_token_alpha"], {"chapter_one_survived": true}), "matching unit should qualify for class change")
	_assert_true(not ProgressionRules.can_class_change(unit, rule, [], {"chapter_one_survived": true}), "missing item should block class change")


func _test_battle_actor_roles_gate_player_control_and_targets() -> void:
	var scenario := BattleFixture.scenario()
	var role_model: Dictionary = scenario.get("role_evidence", {})
	var rules := ActorRoleRules.new()
	_assert_true(rules.has_method("battle_actor_role"), "battle actor role should be explicit in ActorRoleRules")
	_assert_true(rules.has_method("can_player_control_actor"), "player control should be gated through ActorRoleRules")
	_assert_true(rules.has_method("can_player_attack_actor"), "player target filtering should be gated through ActorRoleRules")
	if not rules.has_method("battle_actor_role"):
		return

	var leonard := {"id": "leonard_placeholder", "fixture_role": "player_install", "team": "player", "hp": 32}
	var enemy := {"id": "enemy021_1", "team": "enemy", "fixture_object_code": 99, "hp": 18}
	var ally := {"id": "ally_support", "team": "ally", "hp": 24}
	var map_object := {"id": "tree07", "fixture_role": "map_object", "hp": 0}
	var manager := {"id": "battle_manager", "fixture_role": "battle_manager", "hp": 0}

	_assert_eq(rules.call("battle_actor_role", leonard, role_model), "player_controlled", "player_install should resolve to player_controlled")
	_assert_eq(rules.call("battle_actor_role", enemy, role_model), "enemy_ai", "enemy team should resolve to enemy_ai")
	_assert_eq(rules.call("battle_actor_role", ally, role_model), "friendly_ai", "ally team should resolve to friendly_ai")
	_assert_eq(rules.call("battle_actor_role", map_object, role_model), "map_object", "map object fixture role should stay non-combat")
	_assert_eq(rules.call("battle_actor_role", manager, role_model), "battle_manager", "battle manager fixture role should stay non-combat")
	_assert_true(rules.call("can_player_control_actor", leonard, role_model), "Leonard should be player-controllable in this slice")
	_assert_true(not rules.call("can_player_control_actor", ally, role_model), "friendly AI should not be directly player-controllable")
	_assert_true(rules.call("can_player_attack_actor", leonard, enemy, role_model), "player-controlled actor should be allowed to target enemy AI")
	_assert_true(not rules.call("can_player_attack_actor", leonard, ally, role_model), "player-controlled actor should not target friendly AI as an enemy")
	_assert_true(not rules.call("can_player_attack_actor", leonard, map_object, role_model), "map objects should not become enemy targets without explicit evidence")

	var annotated: Dictionary = rules.call("annotate_actor_role", enemy, role_model)
	_assert_eq(annotated.get("battle_actor_role", ""), "enemy_ai", "annotation should write the resolved role")
	var summary: Dictionary = rules.call("battle_actor_role_summary", [leonard, enemy, ally, map_object, manager], role_model)
	_assert_eq(int(summary.get("counts", {}).get("player_controlled", 0)), 1, "role summary should count player-controlled actors")
	_assert_eq(int(summary.get("counts", {}).get("enemy_ai", 0)), 1, "role summary should count enemy AI actors")
	_assert_eq(int(summary.get("counts", {}).get("map_object", 0)), 1, "role summary should count map objects separately")


func _test_project_uses_640x480_viewport() -> void:
	_assert_eq(ProjectSettings.get_setting("display/window/size/viewport_width"), 640, "project viewport should be 640px wide")
	_assert_eq(ProjectSettings.get_setting("display/window/size/viewport_height"), 480, "project viewport should be 480px tall")


func _load_json(path: String) -> Dictionary:
	var text := FileAccess.get_file_as_string(path)
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		failures.append("Failed to parse JSON: %s" % path)
		return {}
	return parsed


func _player_turn_loop(units: Array = [], terrain_path: String = "", scenario: Dictionary = {}) -> Dictionary:
	# Command/combat fixtures begin at the player's turn, independently of chapter opening.
	var loop := BattlePlayLoop.create(units, terrain_path, scenario if not scenario.is_empty() else BattleFixture.scenario())
	# These tests isolate hit/counter boundaries with authored working values.
	# Production initialization now refreshes all jobs, so install this controlled
	# encounter after initialization rather than relying on it to skip refresh.
	for source in units:
		var actor := BattlePlayLoop._unit(loop, source["id"])
		for key in ["combat_profile", "hp", "max_hp", "mp", "max_mp", "live_speed"]:
			if source.has(key): actor[key] = source[key].duplicate(true) if source[key] is Dictionary else source[key]
		actor["max_hp"] = maxi(int(actor["max_hp"]), int(actor["hp"]))
		actor["max_mp"] = maxi(int(actor["max_mp"]), int(actor["mp"]))
	loop["turn_queue"] = BattlePlayLoop.CoreTurnQueue.rebuild(loop["units"])
	for index in range(loop["turn_queue"]["slots"].size()):
		if loop["turn_queue"]["slots"][index]["id"] == "leonard":
			loop["turn_queue"]["index"] = index
			break
	return loop


func _test_initial_npc_turns() -> void:
	var loop := BattleFixture.loop()
	_assert_eq(BattlePlayLoop.unit(loop, "leonard")["live_speed"], 14, "Sword job, boots and weapon penalty determine Leonard's baseline speed")
	_assert_eq(BattlePlayLoop.unit(loop, "enemy021_1")["live_speed"], 15, "Enemy sword baseline is faster than Leonard")
	var player_profile := CoreCombatRules.combat_profile_from_unit(BattlePlayLoop.unit(loop, "leonard"))
	var mage_profile := CoreCombatRules.combat_profile_from_unit(BattlePlayLoop.unit(loop, "enemy026_1"))
	_assert_eq(CoreCombatRules.hit_chance(player_profile, mage_profile)["dex_delta"], 2, "Live combat must consume original baseline dex rather than equal test attributes")
	var before: Dictionary = BattlePlayLoop.unit_coords(loop)
	loop = BattlePlayLoop.begin_battle(loop)
	_assert_eq(loop["interaction"], "ai_resolving", "Battle opening must respect the first queued NPC")
	loop = BattlePlayLoop.select_player_unit(loop, "leonard")
	_assert_eq(loop["selected_unit_id"], "", "Player cannot steal a faster NPC's opening turn")
	var order: Array = []
	while loop["interaction"] == "ai_resolving" and order.size() < 12:
		order.append(CoreTurnQueue.current(loop["turn_queue"])["id"])
		var actor_id: String = order.back()
		var action_before := loop.duplicate(true)
		loop = BattlePlayLoop.step_ai_turn(loop)
		var path: Array = loop["last_ai_action"].get("path", [])
		var actor_before := BattlePlayLoop.unit(action_before, actor_id)
		for index in range(1, path.size()):
			_assert_eq(BattlePlayLoop._manhattan(path[index-1], path[index]), 1, "opening AI uses adjacent shared-grid path edges")
			var occupant_id := BattlePlayLoop.unit_id_at_coord(action_before, path[index])
			var occupant := BattlePlayLoop.unit(action_before, occupant_id)
			_assert_true(not action_before["tiles"].get(path[index], {}).get("blocks_movement", false) and (occupant.is_empty() or not BattlePlayLoop._are_enemies(actor_before, occupant)), "opening ground pursuit may pass allies but cannot cross terrain or an enemy")
		if path.size() > 1:
			var costs := TacticalGridRules.path_costs(path, action_before["units"], action_before["tiles"], actor_id)
			_assert_true(not costs.is_empty() and costs.back() <= actor_before["move_point"], "opening route respects native clearance and the actor's live budget")
			_assert_eq(BattlePlayLoop.unit_id_at_coord(action_before, path.back()), "", "opening pursuit stops on an unoccupied destination")
	# Registered Leonard (slot 0) precedes the equal-speed (14) friendly soldiers, whose NPC
	# slots follow him (0x407660 / 0x407340; runtime-measured in the user's first-battle
	# recording: speed-14 023_1 acts after Leonard — battle_051_ai_moves).
	_assert_eq(order, ["enemy021_1", "enemy021_2", "enemy021_3", "enemy021_4", "enemy021_5"], "Opening: equal-speed Leonard acts before the level-1 friendly soldiers")
	_assert_eq(loop["selected_unit_id"], "leonard", "NPC prefix must hand off to the player automatically")
	_assert_eq(loop["turn"], 1, "The opening NPC prefix must not invent an extra round")
	for id in ["enemy023_1", "enemy023_2"]:
		_assert_eq(BattlePlayLoop.unit(loop, id)["coord"], before[id], "equal-speed friendly soldiers have not acted before first control")
	var after_leonard: Dictionary = BattlePlayLoop.choose_command(loop, "wait")
	var followers: Array = []
	while after_leonard["interaction"] == "ai_resolving" and followers.size() < 2:
		followers.append(CoreTurnQueue.current(after_leonard["turn_queue"])["id"])
		after_leonard = BattlePlayLoop.step_ai_turn(after_leonard, Callable(self, "_stable_half_rng"))
	_assert_eq(followers, ["enemy023_1", "enemy023_2"], "equal-speed friendly soldiers act right after Leonard, in creation order")
	# The curated original first-control frame shows ordinary allies ahead of Leonard: an
	# opening level-up (0x40e870) makes a 023 level 2 at speed 15, which then leads him.
	var raised := BattleFixture.loop()
	BattlePlayLoop._unit(raised, "enemy023_2")["live_speed"] = 15
	raised["turn_queue"] = CoreTurnQueue.rebuild(BattlePlayLoop._queue_actors(raised))
	var raised_ids: Array = raised["turn_queue"]["slots"].map(func(slot): return slot["id"])
	_assert_true(raised_ids.find("enemy023_2") < raised_ids.find("leonard") and raised_ids.find("enemy023_1") > raised_ids.find("leonard"), "a speed-15 (level-2) friendly soldier acts before Leonard, a speed-14 one after him")
	# The recorded original round-1 order (battle_051_ai_moves) follows from the recorded
	# opening levels: 021_3 L2 (16), 023_2 L3 (16), 024_2 L3 (13), the rest level 1.
	var recorded := BattlePlayLoop.create([], "", BattleScenario.load_file("res://content/battles/battle_051.json"), 1)
	for pair in [["actor021_3", 16], ["actor023_2", 16], ["actor024_2", 13]]:
		BattlePlayLoop._unit(recorded, pair[0])["live_speed"] = pair[1]
	recorded["turn_queue"] = CoreTurnQueue.rebuild(BattlePlayLoop._queue_actors(recorded))
	_assert_eq(recorded["turn_queue"]["slots"].map(func(slot): return slot["id"]), ["actor021_3", "actor023_2", "actor021_1", "actor021_2", "actor021_4", "actor021_5", "leonard", "actor023_1", "actor024_2", "actor024_1", "actor026_1", "actor026_2"], "recorded level-51 opening levels reproduce the original round-1 order")
	_assert_true(BattlePlayLoop.unit(loop, "enemy021_2")["coord"] != before["enemy021_2"], "Opening NPC turns must change real battle positions")
	_assert_eq(BattlePlayLoop.unit(loop, "leonard")["coord"], before["leonard"], "Opening NPC resolution preserves Leonard's script destination")
