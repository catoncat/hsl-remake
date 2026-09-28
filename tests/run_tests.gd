extends "res://tests/support/TestSuite.gd"

const ActorRoleRules = preload("res://game/sim/ActorRoleRules.gd")
const ProgressionRules = preload("res://game/sim/ProgressionRules.gd")
const EquipmentCatalog = preload("res://game/sim/EquipmentCatalog.gd")
const TacticalGridRules = preload("res://game/sim/TacticalGridRules.gd")
const CoreCombatRules = preload("res://game/sim/CoreCombatRules.gd")
const CoreTurnQueue = preload("res://game/sim/CoreTurnQueue.gd")
const BattlePlayLoop = preload("res://game/sim/loop/BattlePlayLoop.gd")
const BattleFixture = preload("res://tests/support/BattleFixture.gd")
const WrdTerrainTiles = preload("res://game/sim/WrdTerrainTiles.gd")
const BattleCameraController = preload("res://game/common/BattleCameraController.gd")
const BattleScenario = preload("res://game/sim/BattleScenario.gd")
const BattleScenarioRuleAdapter = preload("res://game/sim/BattleScenarioRuleAdapter.gd")
const WinfailScenarioRules = preload("res://game/sim/WinfailScenarioRules.gd")
const WinfailCompiler = preload("res://game/sim/WinfailCompiler.gd")
const MapSceneConfig = preload("res://game/battle/runtime/MapSceneConfig.gd")
const BattleOutcome = preload("res://game/sim/BattleOutcome.gd")
const RulesReadback = preload("res://tests/support/RulesReadback.gd")


func _init() -> void:
	tag = "CORE_RULE_TESTS"
	report_checks = false


func run() -> void:
	_test_movement_respects_terrain_and_blocking()
	_test_attack_range()
	_test_core_combat_rules_hit_and_damage_packet()
	_test_core_turn_queue_speed_sort_and_bcmd_icons()
	_test_real_equal_speed_pairs_follow_registration_slots()
	_test_second_battle_play_loop_bootstrap()
	_test_initial_npc_turns()
	_test_live_hit_resolution()
	_test_live_weapon_ranges()
	_test_live_counter_exchange()
	_test_experience_and_level_up()
	_test_battle_actor_roles_gate_player_control_and_targets()
	_test_project_uses_640x480_viewport()
	run_range_propagation()
	run_player_mode_sides()
	run_random_stream()


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
	var reachable: Array = RulesReadback.movement_range(unit, units, _sample_tiles(), Vector2i(5, 4))
	_assert_true(_has_coord(reachable, Vector2i(0, 1)), "road tile inside range should be reachable")
	_assert_true(not _has_coord(reachable, Vector2i(1, 2)), "occupied ally tile should block movement")
	_assert_true(not _has_coord(reachable, Vector2i(3, 1)), "blocked terrain should not be reachable")
	_assert_true(not _has_coord(reachable, Vector2i(4, 1)), "expensive terrain should limit travel budget")
	var envelope: Dictionary = TacticalGridRules.movement_reachability_envelope(unit, units, _sample_tiles(), Vector2i(5, 4))
	_assert_eq(int(envelope.get("reachable_by_coord", {}).get(Vector2i(0, 1), {}).get("cost", 0)), 1, "movement envelope should retain tile cost")
	_assert_eq(envelope.get("reachable_by_coord", {}).get(Vector2i(0, 1), {}).get("path", []), [Vector2i(1, 1), Vector2i(0, 1)], "movement envelope should retain path")
	_assert_true(envelope.get("blocked_coords", {}).has(Vector2i(1, 2)), "movement envelope should retain occupied blocker")
	_assert_true(envelope.get("blocked_coords", {}).has(Vector2i(3, 1)), "movement envelope should retain terrain blocker")


func _test_attack_range() -> void:
	var mage := {"id": "mage", "team": "enemy", "coord": Vector2i(4, 1), "stats": {"str": 4, "agi": 7, "mind": 11, "vit": 4}}
	var attack_tiles: Array = RulesReadback.attack_range(mage["coord"], 1, 3, Vector2i(6, 4))
	_assert_true(_has_coord(attack_tiles, Vector2i(1, 1)), "range 3 mage should threaten Leonard")


func _stable_half_rng(n: int) -> int:
	if n <= 0:
		return 0
	return n / 2


func _test_core_turn_queue_speed_sort_and_bcmd_icons() -> void:

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


func _test_second_battle_play_loop_bootstrap() -> void:
	var scenario := BattleScenario.load_file("res://content/battles/battle_052.json", "hsl_level_battle.v1")
	_assert_true(bool(scenario.get("ok", false)), "second-battle scenario should load through the shared scenario boundary")
	var loop := BattlePlayLoop.create([], "", scenario)
	_assert_true(bool(loop.get("scenario_ok", false)), "the existing PlayLoop should accept the second-battle scenario")
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
	loop = BattlePlayLoop.attack_target(loop, str(enemy["id"]), Callable(self, "_last_roll_rng"))
	_assert_eq(BattlePlayLoop.unit(loop, str(enemy["id"]))["hp"], enemy["hp"], "player miss preserves target HP")
	_assert_eq(loop["last_attack"]["hit"], false, "miss is recorded for player feedback")
	_assert_eq(BattlePlayLoop.unit(loop, "leonard")["hit_bonus_accum"], 8, "player miss stores compensation in battle owner")
	_assert_eq(loop["attacked_this_action"], true, "miss consumes attack")
	_assert_eq(loop["pending_move"], false, "miss commits the action")
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


func _test_core_combat_rules_hit_and_damage_packet() -> void:

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

	var dmg: Dictionary = CoreCombatRules.preview_damage(leonard_profile, enemy_profile, Callable(self, "_stable_half_rng"))
	_assert_true(int(dmg.get("damage", 0)) >= 1, "core damage preview should return positive damage")
	_assert_eq(int(dmg.get("base_attack_minus_defense", -1)), 15, "core damage should start from attack_damage - defense")

	var attacker := {"id": "leonard", "hp": 32, "level": 1, "combat_profile": leonard_profile}
	var defender := {"id": "enemy021", "hp": 18, "level": 1, "combat_profile": enemy_profile}
	var core_preview: Dictionary = RulesReadback.preview_attack(attacker, defender, Callable(self, "_stable_half_rng"))
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


func _test_battle_actor_roles_gate_player_control_and_targets() -> void:
	var scenario := BattleFixture.scenario()
	var role_model: Dictionary = scenario.get("role_evidence", {})
	var rules := ActorRoleRules.new()

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
	_assert_true(RulesReadback.can_player_control_actor(leonard, role_model), "Leonard should be player-controllable in this slice")
	_assert_true(not RulesReadback.can_player_control_actor(ally, role_model), "friendly AI should not be directly player-controllable")
	_assert_true(RulesReadback.can_player_attack_actor(leonard, enemy, role_model), "player-controlled actor should be allowed to target enemy AI")
	_assert_true(not RulesReadback.can_player_attack_actor(leonard, ally, role_model), "player-controlled actor should not target friendly AI as an enemy")
	_assert_true(not RulesReadback.can_player_attack_actor(leonard, map_object, role_model), "map objects should not become enemy targets without explicit evidence")

	var annotated: Dictionary = RulesReadback.annotate_actor_role(enemy, role_model)
	_assert_eq(annotated.get("battle_actor_role", ""), "enemy_ai", "annotation should write the resolved role")


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
		var actor := BattlePlayLoop.unit_ref(loop, source["id"])
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
			_assert_eq(TacticalGridRules.manhattan(path[index-1], path[index]), 1, "opening AI uses adjacent shared-grid path edges")
			var occupant_id := BattlePlayLoop.unit_id_at_coord(action_before, path[index])
			var occupant := BattlePlayLoop.unit(action_before, occupant_id)
			_assert_true(not action_before["tiles"].get(path[index], {}).get("blocks_movement", false) and (occupant.is_empty() or not BattlePlayLoop.are_enemies(actor_before, occupant)), "opening ground pursuit may pass allies but cannot cross terrain or an enemy")
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
	BattlePlayLoop.unit_ref(raised, "enemy023_2")["live_speed"] = 15
	raised["turn_queue"] = CoreTurnQueue.rebuild(BattlePlayLoop.queue_actors(raised))
	var raised_ids: Array = raised["turn_queue"]["slots"].map(func(slot): return slot["id"])
	_assert_true(raised_ids.find("enemy023_2") < raised_ids.find("leonard") and raised_ids.find("enemy023_1") > raised_ids.find("leonard"), "a speed-15 (level-2) friendly soldier acts before Leonard, a speed-14 one after him")
	# The recorded original round-1 order (battle_051_ai_moves) follows from the recorded
	# opening levels: 021_3 L2 (16), 023_2 L3 (16), 024_2 L3 (13), the rest level 1.
	var recorded := BattlePlayLoop.create([], "", BattleScenario.load_file("res://content/battles/battle_051.json"), 1)
	for pair in [["actor021_3", 16], ["actor023_2", 16], ["actor024_2", 13]]:
		BattlePlayLoop.unit_ref(recorded, pair[0])["live_speed"] = pair[1]
	recorded["turn_queue"] = CoreTurnQueue.rebuild(BattlePlayLoop.queue_actors(recorded))
	_assert_eq(recorded["turn_queue"]["slots"].map(func(slot): return slot["id"]), ["actor021_3", "actor023_2", "actor021_1", "actor021_2", "actor021_4", "actor021_5", "leonard", "actor023_1", "actor024_2", "actor024_1", "actor026_1", "actor026_2"], "recorded level-51 opening levels reproduce the original round-1 order")
	_assert_true(BattlePlayLoop.unit(loop, "enemy021_2")["coord"] != before["enemy021_2"], "Opening NPC turns must change real battle positions")
	_assert_eq(BattlePlayLoop.unit(loop, "leonard")["coord"], before["leonard"], "Opening NPC resolution preserves Leonard's script destination")


# ---- run_tests.gd ----
## Original range propagation (RangePropagationRules, original_weapon_ranges.md):
## every native 0x40f8b0／0x4100e0 return of original_range_terrain.json byte for byte, and
## real battlefield cells through the player's weapon range, cast range and cast check.

const RangePropagationRules = preload("res://game/sim/RangePropagationRules.gd")
const SkillResolutionRules = preload("res://game/sim/SkillResolutionRules.gd")
const TerrainEditRules = preload("res://game/sim/TerrainEditRules.gd")
const Autoplay = preload("res://tests/support/Autoplay.gd")
const PACKET := "res://docs/evidence_packets/static_reverse/original_range_terrain.json"
const LINE_SIZES := {"range3CellDir": 3, "range4CellDir": 4, "range5CellDir": 5}
const POISON_ARROW := "special:magicMIND:magicCode03"
const QUAKE := "magic:magicEARTH:magicCode02"
const DRAGON := "special:magicOTHER:magicCode02"


func run_range_propagation() -> void:
	_native_returns()
	_wall_stop_battle_003()
	_h255_and_ally_battle_005()
	_open_ground_first_battle()
	_walled_pocket_battle_504()
	_cast_range_battle_003()
	_area_wall_battle_003()
	_area_matrix_battle_504()
	_line_wall_battle_504()
	_autoplay_destination()


func _native_returns() -> void:
	var packet: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(PACKET))
	var rows := {}
	var weapons: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://content/generated/hsl/chapter01/attack_ranges.json"))["patterns"]
	var skills: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://content/generated/hsl/skills/targeting.json"))["ranges"]
	for table in [weapons, skills]:
		for code in table:
			if table[code].get("data") is Array: rows[code] = table[code]["data"]
	var grids := {}
	for name in packet["grids"]:
		var words := {}
		for entry in packet["grids"][name]["words"]:
			words[Vector2i(int(entry[0]), int(entry[1]))] = int(entry[2])
		grids[name] = {"words": words, "size": Vector2i(int(packet["grids"][name]["size"]), int(packet["grids"][name]["size"]))}
	var counts := {"weapon": 0, "area": 0, "line": 0}
	for case in packet["cases"]:
		var input: Dictionary = case["input"]
		var grid: Dictionary = grids[input["grid"]]
		var code := str(input["code"])
		var got: Dictionary
		var kind := str(input["builder"])
		if kind == "weapon":
			got = RangePropagationRules.weapon_coverage(rows[code], _cell(input["origin"]), grid["words"], grid["size"], int(input["mode"]), int(input["flag5"]) != 0)
		elif LINE_SIZES.has(code):
			kind = "line"
			got = RangePropagationRules.line_coverage(LINE_SIZES[code], _cell(input["caster"]), _cell(input["target"]), grid["words"], grid["size"], int(input["mode"]))
		else:
			got = RangePropagationRules.area_coverage(rows[code], _cell(input["target"]), grid["words"], grid["size"], int(input["mode"]))
		counts[kind] += 1
		check(got == _native(case), "native %s %s %s %s mode %d: expected %s got %s" % [kind, input["grid"], code, str(input.get("origin", input.get("target"))), int(input["mode"]), str(_native(case)), str(got)])
	check(counts["weapon"] == 124 and counts["area"] + counts["line"] == 230, "all 354 native returns compared: %s" % str(counts))


## battle_003 opening: 胡 (4,9) with range3CellShoot. (4,7) carries the WRD 0x4000 flag; the
## flat record covers it and (4,6) behind it, the original flood stops at it. (3,10)／(5,10)
## hold allies (mode 2 leaves pmPLAYER occupants unwritten).
func _wall_stop_battle_003() -> void:
	var loop := _loop("battle_003")
	var hu := BattlePlayLoop.unit(loop, "hu")
	var tiles: Dictionary = TerrainEditRules.tiles(loop)
	check(hu["coord"] == Vector2i(4, 9) and str(BattlePlayLoop.weapon_pattern(loop, hu)["name"]) == "range3CellShoot", "battle_003 胡 opens at (4,9) with range3CellShoot")
	check(int(tiles[Vector2i(4, 7)]["movement_flags"]) & 0x4000 != 0 and int(tiles[Vector2i(4, 6)]["movement_flags"]) & 0x4000 != 0, "battle_003 (4,7) and (4,6) are 0x4000 walls")
	var flat: Array = BattlePlayLoop.TacticalGridRules.attack_pattern_cells(hu["coord"], BattlePlayLoop.weapon_pattern(loop, hu)["offsets"], loop["map_size"])
	var cells := BattlePlayLoop.attack_cells(loop, "hu")
	check(flat.has(Vector2i(4, 7)) and not cells.has(Vector2i(4, 7)), "battle_003 胡: the 0x4000 cell (4,7) is in the flat record but not attackable")
	check(flat.has(Vector2i(2, 10)) and not cells.has(Vector2i(2, 10)), "battle_003 胡: (2,10) next to the (2,9)／(3,9) walls loses its power at the onward check")
	check(cells.has(Vector2i(5, 8)) and cells.has(Vector2i(4, 12)), "battle_003 胡: (5,8) beside the wall and (4,12) on open ground stay attackable")
	_assert_eq(cells, [Vector2i(5, 8), Vector2i(6, 8), Vector2i(6, 9), Vector2i(7, 9), Vector2i(6, 10), Vector2i(3, 11), Vector2i(4, 11), Vector2i(5, 11), Vector2i(4, 12)], "battle_003 胡 weapon cells")


## battle_005 opening: 胡 (10,11) with range3CellShoot. (8,11) and (7,11) are height 255
## without 0x4000: the range builders never read heights, so both stay covered. (9,10)
## holds an ally: left out, and the flood carries on to (8,10) behind it.
func _h255_and_ally_battle_005() -> void:
	var loop := _loop("battle_005")
	var hu := BattlePlayLoop.unit(loop, "hu")
	var tiles: Dictionary = TerrainEditRules.tiles(loop)
	check(hu["coord"] == Vector2i(10, 11), "battle_005 胡 opens at (10,11)")
	for cell in [Vector2i(8, 11), Vector2i(7, 11)]:
		check(int(tiles[cell]["elevation"]) == 255 and int(tiles[cell]["movement_flags"]) & 0x4000 == 0, "battle_005 %s is h255 without 0x4000" % str(cell))
	var cells := BattlePlayLoop.attack_cells(loop, "hu")
	check(cells.has(Vector2i(8, 11)) and cells.has(Vector2i(7, 11)), "battle_005 胡: the range passes over the h255 cells (8,11) and (7,11)")
	check(RangePropagationRules.side_word(_at(loop, Vector2i(9, 10))) & RangePropagationRules.P != 0 and not cells.has(Vector2i(9, 10)) and cells.has(Vector2i(8, 10)), "battle_005 胡: the ally at (9,10) is left out, (8,10) behind it stays")
	_assert_eq(cells.size(), 19, "battle_005 胡 weapon cell count (20 flat minus the ally)")


## first_battle opening: 萊納德 (15,17) with range1Cell on open ground — the flood equals
## the flat record.
func _open_ground_first_battle() -> void:
	var loop := _loop("first_battle")
	var leonard := BattlePlayLoop.unit(loop, "leonard")
	var flat: Array = BattlePlayLoop.TacticalGridRules.attack_pattern_cells(leonard["coord"], BattlePlayLoop.weapon_pattern(loop, leonard)["offsets"], loop["map_size"])
	check(leonard["coord"] == Vector2i(15, 17), "first_battle 萊納德 opens at (15,17)")
	_assert_eq(BattlePlayLoop.attack_cells(loop, "leonard"), [Vector2i(15, 16), Vector2i(14, 17), Vector2i(16, 17), Vector2i(15, 18)], "first_battle 萊納德 open-ground weapon cells")
	_assert_eq(BattlePlayLoop.attack_cells(loop, "leonard"), flat, "first_battle 萊納德: flood equals the flat record on open ground")


## battle_504 opening: 咕嚕 (7,15) range3CellCircle inside a walled pocket.
func _walled_pocket_battle_504() -> void:
	var loop := _loop("battle_504")
	check(BattlePlayLoop.unit(loop, "gulu")["coord"] == Vector2i(7, 15), "battle_504 咕嚕 opens at (7,15)")
	_assert_eq(BattlePlayLoop.attack_cells(loop, "gulu"), [Vector2i(7, 12), Vector2i(6, 13), Vector2i(7, 13), Vector2i(5, 14), Vector2i(6, 14), Vector2i(7, 14), Vector2i(8, 14), Vector2i(6, 15), Vector2i(6, 16), Vector2i(7, 16), Vector2i(8, 16), Vector2i(7, 17)], "battle_504 咕嚕 weapon cells (24 flat)")


## battle_003 opening: 胡's 毒魔箭 cast range range3CellThrust through the player's
## selection (mode -1, flag 0: walls stop, no side exclusion) and the settled cast check.
func _cast_range_battle_003() -> void:
	var loop := _loop("battle_003")
	var hu := BattlePlayLoop.unit(loop, "hu")
	var fields := BattlePlayLoop.skill_fields(loop, POISON_ARROW)
	check(str(fields.get("range", "")) == "range3CellThrust", "毒魔箭 cast range is range3CellThrust")
	var flat: Array = BattlePlayLoop.SkillTargetRules.cells(hu["coord"], fields, loop["skill_target_data"], loop["map_size"])
	var selecting := loop.duplicate()
	selecting.merge({"selected_attack": "special", "interaction": "attack_select", "selected_unit_id": "hu", "selected_skill_id": POISON_ARROW}, true)
	var cells := BattlePlayLoop.attack_cells(selecting, "hu")
	check(flat.has(Vector2i(4, 7)) and flat.has(Vector2i(4, 6)) and not cells.has(Vector2i(4, 7)) and not cells.has(Vector2i(4, 6)), "毒魔箭 from (4,9): the 0x4000 cell (4,7) and (4,6) behind it are not castable")
	check(cells.has(Vector2i(4, 8)) and cells.has(Vector2i(3, 10)), "毒魔箭 from (4,9): (4,8) before the wall and the ally cell (3,10) stay castable")
	_assert_eq(cells, [Vector2i(4, 8), Vector2i(5, 8), Vector2i(5, 9), Vector2i(6, 9), Vector2i(7, 9), Vector2i(3, 10), Vector2i(4, 10), Vector2i(5, 10), Vector2i(4, 11), Vector2i(4, 12)], "毒魔箭 cast cells from (4,9)")
	var caster: Dictionary = hu.duplicate(true)
	caster["stamina"] = 60
	var walled := SkillResolutionRules.prepare_cast(caster, caster, loop["units"], POISON_ARROW, fields, loop["skill_book"], loop["skill_target_data"], loop["equipment_items"], caster["coord"], loop["map_size"], Vector2i(4, 7), {"range_terrain": BattlePlayLoop.skill_terrain(loop)})
	var bare := SkillResolutionRules.prepare_cast(caster, caster, loop["units"], POISON_ARROW, fields, loop["skill_book"], loop["skill_target_data"], loop["equipment_items"], caster["coord"], loop["map_size"], Vector2i(4, 7))
	check(walled.get("reason") == "out_of_range" and bare.get("reason") != "out_of_range", "毒魔箭 aimed at the wall (4,7): out_of_range with the terrain (got %s), in range without (got %s)" % [str(walled.get("reason")), str(bare.get("reason"))])


## battle_003 opening: 胡's 毒魔箭 area (range1Cell) through the player's effect area
## (0x444f08／0x4450e0 → 0x4100e0 mode 2): the 0x4000 cells and the P occupants are left
## out, the centre is written unless a P occupant stands on it (0x410498[2]).
func _area_wall_battle_003() -> void:
	var loop := _loop("battle_003")
	var selecting := loop.duplicate()
	selecting.merge({"selected_attack": "special", "interaction": "attack_select", "selected_unit_id": "hu", "selected_skill_id": POISON_ARROW}, true)
	var fields := BattlePlayLoop.skill_fields(loop, POISON_ARROW)
	var hu := BattlePlayLoop.unit(loop, "hu")
	var flat: Array = BattlePlayLoop.SkillTargetRules.cast_footprint(hu["coord"], Vector2i(4, 8), fields, loop["skill_target_data"], loop["map_size"])
	_assert_eq(flat, [Vector2i(4, 7), Vector2i(3, 8), Vector2i(4, 8), Vector2i(5, 8), Vector2i(4, 9)], "毒魔箭 at (4,8): the flat cross")
	_assert_eq(BattlePlayLoop.Combat.skill_cast_footprint(selecting, Vector2i(4, 8)), [Vector2i(4, 8), Vector2i(5, 8)], "毒魔箭 at (4,8) against the (4,7)／(3,8) walls, 胡 at (4,9) left out")
	_assert_eq(BattlePlayLoop.Combat.skill_cast_footprint(selecting, Vector2i(4, 10)), [Vector2i(4, 10), Vector2i(4, 11)], "毒魔箭 at (4,10) between 胡, 緹娜 and 雷歐納德: only the open cells")
	_assert_eq(BattlePlayLoop.Combat.skill_cast_footprint(selecting, Vector2i(3, 10)), [Vector2i(2, 10), Vector2i(4, 10), Vector2i(3, 11)], "毒魔箭 on 緹娜's cell (3,10): the P centre and the (3,9) wall left out")
	_assert_eq(BattlePlayLoop.Combat.skill_cast_footprint(selecting, Vector2i(4, 11)), [Vector2i(4, 10), Vector2i(3, 11), Vector2i(4, 11), Vector2i(5, 11), Vector2i(4, 12)], "毒魔箭 at (4,11) on open ground: the whole cross")
	# The settled context carries the same terrain only in the player's command cast.
	check(BattlePlayLoop.Combat.skill_context(selecting).get("range_terrain") == BattlePlayLoop.skill_terrain(selecting), "the player's command cast settles with the player's skill terrain")
	check(not BattlePlayLoop.Combat.skill_context(loop).has("range_terrain"), "outside the player's skill targeting the settled context carries no terrain")
	var ai_casting := selecting.duplicate()
	ai_casting["interaction"] = "ai_resolving"
	check(not BattlePlayLoop.Combat.skill_context(ai_casting).has("range_terrain"), "an AI cast (ai_resolving) settles flat")
	# The area modes 2／3 are the P side's: a commandable caster of another side keeps the flat area.
	var hu_e: Dictionary = BattlePlayLoop.unit(selecting, "hu").merged({"player_mode": RangePropagationRules.E}, true)
	check(BattlePlayLoop.skill_terrain(selecting).has("area_modes") and not BattlePlayLoop.skill_terrain(selecting, hu_e).has("area_modes") and BattlePlayLoop.skill_terrain(selecting, hu_e).has("cast_mode"), "the area half needs a P-side caster; the mode -1 cast range applies to any")


## battle_504 opening: 克勞蒂 (7,11) casts 地龍震 (range3CellCircle → range2CellCircle) on a
## foe at (7,14). 胡 (8,13), 漢克斯 (9,14) and 咕嚕 (7,15) are P and left out, (8,15) is
## 0x4000; at (7,15) the onward check sees the (8,15) wall and ends the flood, so the foe
## at (7,16) is outside the area the flat record would reach. Preview, target line and
## the settled strike read that one area.
func _area_matrix_battle_504() -> void:
	var loop := _loop("battle_504")
	BattlePlayLoop.unit_ref(loop, "actor036_1")["coord"] = Vector2i(7, 14)
	BattlePlayLoop.unit_ref(loop, "actor036_2")["coord"] = Vector2i(7, 16)
	BattlePlayLoop.unit_ref(loop, "actor036_3")["coord"] = Vector2i(6, 14)
	var casting := BattlePlayLoop.choose_magic(BattlePlayLoop.choose_command(_turn(loop, "claudie"), "magic"), QUAKE)
	check(casting["interaction"] == "attack_select" and casting["selected_skill_id"] == QUAKE, "克勞蒂 selects 地龍震")
	var fields := BattlePlayLoop.skill_fields(casting, QUAKE)
	var flat: Array = BattlePlayLoop.SkillTargetRules.cast_footprint(Vector2i(7, 11), Vector2i(7, 14), fields, casting["skill_target_data"], casting["map_size"])
	var area: Array = BattlePlayLoop.Combat.skill_cast_footprint(casting, Vector2i(7, 14))
	check(flat.has(Vector2i(7, 16)) and flat.has(Vector2i(8, 15)), "地龍震 at (7,14): the flat record reaches (7,16) and the (8,15) wall")
	_assert_eq(area, [Vector2i(7, 12), Vector2i(6, 13), Vector2i(7, 13), Vector2i(5, 14), Vector2i(6, 14), Vector2i(7, 14), Vector2i(8, 14), Vector2i(6, 15)], "地龍震 at (7,14) beside the (8,15) wall")
	check(BattlePlayLoop.magic_target_id_at_coord(casting, Vector2i(7, 14)) == "actor036_1", "the target line at (7,14) names the centre foe")
	var before := int(BattlePlayLoop.unit(casting, "actor036_2")["hp"])
	var cast := BattlePlayLoop.attack_target(casting, "actor036_1", func(_n): return 0, Vector2i(7, 14))
	var hit: Array = cast.get("last_attack", {}).get("affected_targets", []).map(func(receipt): return receipt["defender_id"])
	check(cast.get("last_attack_reject", {}).is_empty() and hit == ["actor036_1", "actor036_3"], "地龍震 settles on the two foes inside the area (got %s)" % [hit])
	check(int(BattlePlayLoop.unit(cast, "actor036_2")["hp"]) == before, "the foe at (7,16) past the wall-side stop keeps its HP")
	_assert_eq(hit, _foes_on(casting, area), "地龍震: the settled targets are the foes on the previewed area")


## battle_504: 咕嚕 (moved to (7,16)) slashes 皇龍閃 (range1Cell → range3CellDir) at the foe
## on (8,16). (9,16) is 0x4000: the 0x4100e0 line ends there as a whole, so the foe on
## (10,16) — on the flat line — is not struck, and the settled cue shows the one cell.
func _line_wall_battle_504() -> void:
	var loop := _loop("battle_504")
	var gulu := BattlePlayLoop.unit_ref(loop, "gulu")
	own(loop, "skill_book")["actors"][str(gulu["actor_id"])]["supported_initial_ids"].append(DRAGON)
	gulu["coord"] = Vector2i(7, 16)
	gulu["stamina"] = 80
	BattlePlayLoop.unit_ref(loop, "actor036_1")["coord"] = Vector2i(8, 16)
	BattlePlayLoop.unit_ref(loop, "actor036_2")["coord"] = Vector2i(10, 16)
	var tiles: Dictionary = TerrainEditRules.tiles(loop)
	check(int(tiles[Vector2i(9, 16)]["movement_flags"]) & 0x4000 != 0 and int(tiles[Vector2i(10, 16)]["movement_flags"]) & 0x4000 == 0, "battle_504 (9,16) is a 0x4000 wall, (10,16) open")
	var casting := BattlePlayLoop.choose_special(BattlePlayLoop.choose_command(_turn(loop, "gulu"), "special"), DRAGON)
	check(casting["interaction"] == "attack_select" and casting["selected_skill_id"] == DRAGON, "咕嚕 selects 皇龍閃")
	var fields := BattlePlayLoop.skill_fields(casting, DRAGON)
	_assert_eq(BattlePlayLoop.SkillTargetRules.cast_footprint(Vector2i(7, 16), Vector2i(8, 16), fields, casting["skill_target_data"], casting["map_size"]), [Vector2i(8, 16), Vector2i(9, 16), Vector2i(10, 16)], "皇龍閃 from (7,16) at (8,16): the flat line")
	_assert_eq(BattlePlayLoop.Combat.skill_cast_footprint(casting, Vector2i(8, 16)), [Vector2i(8, 16)], "皇龍閃 at (8,16): the line ends at the (9,16) wall")
	var before := int(BattlePlayLoop.unit(casting, "actor036_2")["hp"])
	var slashed := BattlePlayLoop.attack_target(casting, "actor036_1", func(_n): return 0)
	var hit: Array = slashed.get("last_attack", {}).get("affected_targets", []).map(func(receipt): return receipt["defender_id"])
	check(slashed.get("last_attack_reject", {}).is_empty() and hit == ["actor036_1"], "皇龍閃 settles on the foe before the wall only (got %s)" % [hit])
	check(int(BattlePlayLoop.unit(slashed, "actor036_2")["hp"]) == before, "the foe on (10,16) behind the wall keeps its HP")
	_assert_eq(BattlePlayLoop.strike_range_cells(slashed, slashed.get("last_attack", {})), [Vector2i(8, 16)], "the settled cue shows the cut line")


## The autoplay driver's destination (tests/support/Autoplay.gd `_destination`): the flat
## pattern proposes the cheapest cell, the weapon's flood from it decides. 胡 (range3CellShoot)
## on real walls: battle_003 foe (6,6) — from (6,9) the flat record covers it but (6,7)／(6,8)
## sit beside the walls; foe (1,10) — from (4,10) the flood dies at (2,10) beside (2,9)／(3,9);
## battle_504 foe (7,16) — from (8,14) the (8,15) wall is in the way. Each time the driver
## lands on another cell and strikes from it in the same action.
func _autoplay_destination() -> void:
	for case in [["battle_003", "actor028_1", Vector2i(6, 6), Vector2i(6, 9)], ["battle_003", "actor028_1", Vector2i(1, 10), Vector2i(4, 10)], ["battle_504", "actor036_1", Vector2i(7, 16), Vector2i(8, 14)]]:
		var loop := _loop(case[0])
		var foe := BattlePlayLoop.unit_ref(loop, case[1])
		foe["coord"] = case[2]
		var turn := _turn(loop, "hu")
		var hu := BattlePlayLoop.unit(turn, "hu")
		var pattern := BattlePlayLoop.weapon_pattern(turn, hu)
		var flat_cell: Vector2i = case[3]
		var label := "%s 胡 %s → foe %s" % [case[0], str(hu["coord"]), str(case[2])]
		check(BattlePlayLoop.Footprint.contact(foe, BattlePlayLoop.attack_cells(turn, "hu")) == null, "%s: not in reach before the move" % label)
		var from_flat: Array = Autoplay.weapon_cells_from(turn, hu, pattern, flat_cell)
		check(BattlePlayLoop.movement_cells(turn, "hu").has(flat_cell) and BattlePlayLoop.TacticalGridRules.attack_pattern_cells(flat_cell, pattern["offsets"], turn["map_size"]).has(case[2]) and not from_flat.has(case[2]), "%s: the flat record covers the foe from %s, the flood does not" % [label, str(flat_cell)])
		var destination: Variant = Autoplay.attack_destination(turn, "hu")
		check(destination is Vector2i and destination != flat_cell and BattlePlayLoop.movement_path(turn, "hu", flat_cell).size() <= BattlePlayLoop.movement_path(turn, "hu", destination).size(), "%s: the driver passes over the cheaper flat cell %s (chose %s)" % [label, str(flat_cell), str(destination)])
		var step := Autoplay.take_player_action(turn, RandomNumberGenerator.new())
		check(step["action"] == "move_then_attack" and BattlePlayLoop.unit(step["loop"], "hu")["coord"] == destination, "%s: lands on %s and strikes (got %s)" % [label, str(destination), str(step["action"])])


## The living foes standing on `cells`, in roster order.
func _foes_on(loop: Dictionary, cells: Array) -> Array:
	var result: Array = []
	for unit in loop["units"]:
		if int(unit["hp"]) > 0 and cells.has(unit["coord"]) and unit.get("battle_actor_role") == "enemy_ai": result.append(unit["id"])
	return result


## Hands the action to `id` (its slot becomes current) and opens its action menu.
func _turn(loop: Dictionary, id: String) -> Dictionary:
	for index in range(loop["turn_queue"]["slots"].size()):
		if loop["turn_queue"]["slots"][index]["id"] == id: loop["turn_queue"]["index"] = index
	return BattlePlayLoop.select_player_unit(loop, id)


func _loop(level: String) -> Dictionary:
	return BattlePlayLoop.create([], "", BattlePlayLoop.BattleScenario.load_file("res://content/battles/%s.json" % level), 1)


func _at(loop: Dictionary, cell: Vector2i) -> Dictionary:
	for unit in loop["units"]:
		if unit.get("coord") == cell: return unit
	return {}


func _cell(pair: Array) -> Vector2i:
	return Vector2i(int(pair[0]), int(pair[1]))


func _native(case: Dictionary) -> Dictionary:
	var frame: Array = case["frame"]
	var bytes: PackedByteArray = str(case["coverage"]).hex_decode()
	var result := {}
	for y in range(int(frame[1])):
		for x in range(int(frame[0])):
			var value := int(bytes[y * int(frame[0]) + x])
			if value != 0: result[Vector2i(int(frame[2]) + x, int(frame[3]) + y)] = value
	return result


# ---- run_tests.gd ----
## Side bits of the installed player mode (docs/evidence_packets/static_reverse/
## original_player_mode_sides.md): who may target whom, who the win/fail counters count,
## and the level-6 / level-531 all-wait rounds the packet's comparison table quotes.
## Prints one `PLAYER_MODE_SIDES_ATTACK level=… round=… attacker=… defender=…` line per AI
## exchange so the remake column of the table is reproducible from this suite.

const WinfailConditions = preload("res://game/sim/WinfailConditions.gd")
const WinfailActions = preload("res://game/sim/WinfailActions.gd")
const PM_PLAYER := 0x10000
const PM_ENEMY := 0x20000
const PM_PLAYER_ENEMY := 0x30000
const PM_NPC := 0x40000
const PM_NPC_PLAYER := 0x50000


func run_player_mode_sides() -> void:
	_test_side_mask_reads_player_mode_then_role()
	_test_hostility_matrix_follows_disjoint_side_bits()
	_test_counters_follow_register_side_rule()
	_test_player_attack_gate_and_skill_side()
	_test_set_player_mode_writes_mode_and_role()
	_test_pm_all_occupant_ranges()
	_test_level6_soldiers_never_attack_villagers()
	_test_level531_npc_rider_is_hostile_to_both_camps()


func _unit(role: String, mode: Variant = null, id: String = "u") -> Dictionary:
	var unit := {"id": id, "battle_actor_role": role, "hp": 10}
	if mode != null:
		unit["player_mode"] = mode
	return unit


func _test_side_mask_reads_player_mode_then_role() -> void:
	check(ActorRoleRules.side_mask(_unit("player_controlled")) == PM_PLAYER, "player_controlled without player_mode is pmPlayer")
	check(ActorRoleRules.side_mask(_unit("friendly_ai")) == PM_PLAYER, "friendly_ai without player_mode keeps the player side it always implied")
	check(ActorRoleRules.side_mask(_unit("enemy_ai")) == PM_ENEMY, "enemy_ai without player_mode is pmEnemy")
	check(ActorRoleRules.side_mask(_unit("friendly_ai", PM_PLAYER_ENEMY)) == PM_PLAYER_ENEMY, "installed pmPlayerEnemy wins over the role")
	check(ActorRoleRules.side_mask(_unit("enemy_ai", PM_NPC)) == PM_NPC, "installed pmNPC wins over the role")
	check(ActorRoleRules.side_mask(_unit("friendly_ai", 0x850000)) == PM_NPC_PLAYER, "pmNPCPlayerNoMagic masks to its pmALL side bits")
	check(ActorRoleRules.side_mask({"id": "tree", "fixture_role": "map_object"}) == 0, "a map object has no side")


func _test_hostility_matrix_follows_disjoint_side_bits() -> void:
	var player := _unit("player_controlled", PM_PLAYER, "p")
	var enemy := _unit("enemy_ai", PM_ENEMY, "e")
	var npc := _unit("enemy_ai", PM_NPC, "n")
	var villager := _unit("friendly_ai", PM_PLAYER_ENEMY, "v")
	var ally := _unit("friendly_ai", PM_NPC_PLAYER, "a")
	# 0x40bb80: own & other & 0x870000 != 0 excludes the candidate.
	check(ActorRoleRules.hostile(player, enemy) and ActorRoleRules.hostile(enemy, player), "pmPlayer and pmEnemy are mutual targets")
	check(ActorRoleRules.hostile(player, npc) and ActorRoleRules.hostile(npc, player), "pmNPC and pmPlayer are mutual targets")
	check(ActorRoleRules.hostile(enemy, npc) and ActorRoleRules.hostile(npc, enemy), "pmNPC and pmEnemy are mutual targets (three-way battle)")
	check(not ActorRoleRules.hostile(enemy, villager) and not ActorRoleRules.hostile(villager, enemy), "pmPlayerEnemy shares pmEnemy: the enemy AI never selects a villager")
	check(not ActorRoleRules.hostile(player, villager) and not ActorRoleRules.hostile(villager, player), "pmPlayerEnemy shares pmPlayer: the player cannot target a villager")
	check(ActorRoleRules.hostile(villager, npc), "a pmPlayerEnemy villager is hostile only to pmNPC")
	check(not ActorRoleRules.hostile(ally, player) and ActorRoleRules.hostile(ally, enemy) and not ActorRoleRules.hostile(ally, npc), "pmNPCPlayer sides with the player, fights pmEnemy, shares pmNPC")
	check(not ActorRoleRules.hostile(player, {"id": "tree", "fixture_role": "map_object"}), "no side is never hostile")
	check(ActorRoleRules.same_side(player, ally) and ActorRoleRules.same_side(villager, player) and ActorRoleRules.same_side(villager, enemy), "support same-side is an overlapping side")
	check(not ActorRoleRules.same_side(npc, player) and not ActorRoleRules.same_side(enemy, player), "disjoint sides are not the same side")
	# Units without player_mode keep the pre-R22 contract.
	check(ActorRoleRules.hostile(_unit("player_controlled"), _unit("enemy_ai")) and not ActorRoleRules.hostile(_unit("player_controlled"), _unit("friendly_ai")), "role-only units: player vs enemy hostile, player vs friendly not")


func _test_counters_follow_register_side_rule() -> void:
	# 0x407660 / 0x407720: enemy total counts pmEnemy without pmPlayer, player total pmPlayer without pmEnemy.
	check(ActorRoleRules.counts_as_enemy(_unit("enemy_ai", PM_ENEMY)) and ActorRoleRules.counts_as_enemy(_unit("enemy_ai", 0x60000)), "pmEnemy and pmNPCEnemy count as enemies")
	check(not ActorRoleRules.counts_as_enemy(_unit("enemy_ai", PM_NPC)), "pmNPC does not count as an enemy")
	check(not ActorRoleRules.counts_as_enemy(_unit("friendly_ai", PM_PLAYER_ENEMY)) and not ActorRoleRules.counts_as_player(_unit("friendly_ai", PM_PLAYER_ENEMY)), "pmPlayerEnemy counts for neither side")
	check(ActorRoleRules.counts_as_player(_unit("player_controlled", PM_PLAYER)) and ActorRoleRules.counts_as_player(_unit("friendly_ai", PM_NPC_PLAYER)), "pmPlayer and pmNPCPlayer count as players")
	check(ActorRoleRules.counts_as_enemy(_unit("enemy_ai")) and ActorRoleRules.counts_as_player(_unit("friendly_ai")), "role-only units count by their implied side")
	var battle := {"units": [
		_unit("player_controlled", PM_PLAYER, "p"), _unit("enemy_ai", PM_ENEMY, "e1"), _unit("enemy_ai", PM_ENEMY, "e2"),
		_unit("enemy_ai", PM_NPC, "n"), _unit("friendly_ai", PM_PLAYER_ENEMY, "v"),
	]}
	check(WinfailConditions.alive_enemy_total(battle) == 2, "actCheckEnemyTotalNumber counts the two pmEnemy units, not the pmNPC rider or the villager")
	check(WinfailConditions.alive_player_side_total(battle) == 1, "actCheckPlayerTotalNumber counts the pmPlayer unit only")


func _test_player_attack_gate_and_skill_side() -> void:
	var player := _unit("player_controlled", PM_PLAYER, "p")
	check(RulesReadback.can_player_attack_actor(player, _unit("enemy_ai", PM_NPC, "n")), "the player may attack a pmNPC unit")
	check(not RulesReadback.can_player_attack_actor(player, _unit("friendly_ai", PM_PLAYER_ENEMY, "v")), "the player may not attack a pmPlayerEnemy villager (0x40f8b0 mode 2 skips pmPlayer cells)")
	var dead := _unit("enemy_ai", PM_ENEMY, "d")
	dead["hp"] = 0
	check(not RulesReadback.can_player_attack_actor(player, dead), "a fallen unit is no target")
	var skill_data := {"skills": {}}
	var offensive := {"function_bits": 0, "range": "range1Cell", "effect_range": "range0Cell"}
	check(BattlePlayLoop.SkillTargetRules.side_matches(player, _unit("enemy_ai", PM_NPC, "n"), offensive, skill_data), "an offensive skill reaches a pmNPC unit")
	check(not BattlePlayLoop.SkillTargetRules.side_matches(player, _unit("friendly_ai", PM_PLAYER_ENEMY, "v"), offensive, skill_data), "an offensive skill does not reach a villager")


## 0x40f5d0 keeps a pmALL occupant in every player range except the weapon range (0x409090,
## flag 1), which drops pmMagicAttack's 0x800000; the AI keeps disjoint sides (0x40bb80).
## The level-37 gems: magic／specials only; an undeclared gem with nothing to target waits.
func _test_pm_all_occupant_ranges() -> void:
	var player := _unit("player_controlled", PM_PLAYER, "p")
	var gem := _unit("friendly_ai", 0x870000, "gem")
	var door := _unit("friendly_ai", 0x70000, "door")
	var villager := _unit("friendly_ai", PM_PLAYER_ENEMY, "v")
	var enemy := _unit("enemy_ai", PM_ENEMY, "e")
	check(not ActorRoleRules.player_range_selectable(player, gem, false) and ActorRoleRules.player_range_selectable(player, gem, true), "a pmMagicAttack gem is out of the weapon range, inside the magic／special range")
	check(ActorRoleRules.player_range_selectable(player, door, false) and ActorRoleRules.player_range_selectable(player, door, true), "a plain pmALL occupant stays in every player range")
	check(not ActorRoleRules.player_range_selectable(player, villager, false) and not ActorRoleRules.player_range_selectable(player, villager, true), "a pmPlayerEnemy occupant (a gem switched off) stays out of both")
	check(ActorRoleRules.player_range_selectable(player, enemy, false) and not ActorRoleRules.player_range_selectable(gem, gem, true), "hostile units stay selectable; nobody selects itself")
	var skill_data := {"skills": {}}
	var offensive := {"function_bits": 0, "range": "range1Cell", "effect_range": "range0Cell"}
	check(BattlePlayLoop.SkillTargetRules.side_matches(player, gem, offensive, skill_data), "a player offensive skill reaches a gem")
	check(not BattlePlayLoop.SkillTargetRules.side_matches(enemy, gem, offensive, skill_data), "an AI caster never targets a pmALL gem (0x40bb80)")
	# 0x40fdc0 (the area mask 0x4104d0 walks): a pmALL occupant is kept whatever the caster's
	# excluded side, so an AI's offensive area around its target takes a gem in too (R6-L11).
	check(BattlePlayLoop.SkillTargetRules.area_side_matches(enemy, gem, offensive, skill_data) and BattlePlayLoop.SkillTargetRules.area_side_matches(player, gem, offensive, skill_data), "every caster's offensive area takes in a pmALL gem")
	check(not BattlePlayLoop.SkillTargetRules.area_side_matches(enemy, villager, offensive, skill_data) and not BattlePlayLoop.SkillTargetRules.area_side_matches(gem, gem, offensive, skill_data), "the area keeps excluding the caster's own side (a switched-off gem is pmPlayerEnemy) and the caster itself")
	var profiles := {"actors": {"067": {"missing_required": ["find_type", "find_range", "ai_call_range", "ai_fixed"]}}}
	gem["actor_id"] = "067"
	var board := {"ai_profiles": profiles, "units": [gem, player, enemy]}
	check(BattlePlayLoop.AI.idle_without_strategy(board, gem), "an undeclared gem with no hostile unit waits")
	var npc := _unit("enemy_ai", PM_NPC, "n")
	gem["player_mode"] = PM_PLAYER_ENEMY
	board["units"].append(npc)
	check(not BattlePlayLoop.AI.idle_without_strategy(board, gem), "a switched-off gem facing a pmNPC unit is not idle: the missing strategy still fails")
	profiles["actors"]["067"]["missing_required"] = []
	check(not BattlePlayLoop.AI.idle_without_strategy({"ai_profiles": profiles, "units": [gem, player]}, gem), "a declared strategy takes the ordinary AI turn")


func _test_set_player_mode_writes_mode_and_role() -> void:
	var next := {"units": [{"id": "claudie", "actor_id": "009", "battle_actor_role": "enemy_ai", "player_commandable": false, "player_mode": PM_ENEMY, "hp": 30}],
		"winfail_runtime": {"actor_bindings": {"SID_克羅蒂/1": "claudie"}}}
	var runtime := {"mode_changes": [], "unsupported_encountered": []}
	WinfailActions.apply_player_mode(next, runtime, "event_6", ["SID_克羅蒂", "1", "pmPlayerEnemy", "0"])
	var unit: Dictionary = next["units"][0]
	check(runtime["mode_changes"].size() == 1 and runtime["mode_changes"][0]["unit_ids"] == ["claudie"], "the bound token resolves to the unit")
	check(unit["battle_actor_role"] == "friendly_ai" and unit["player_mode"] == PM_PLAYER_ENEMY and not unit["player_commandable"], "WINFAIL036 event 6 pmPlayerEnemy: AI-driven, side pmPlayerEnemy")
	WinfailActions.apply_player_mode(next, runtime, "event_7", ["SID_克羅蒂", "1", "pmPlayer", "1"])
	check(unit["battle_actor_role"] == "player_controlled" and unit["player_mode"] == PM_PLAYER and unit["player_commandable"], "pmPlayer returns control and the pmPlayer side")
	# R6-L10: WINFAIL037 swaps the level-37 gems between pmPlayerEnemy and pmMagicAttack; the
	# pmALL side is now read by ActorRoleRules.player_range_selectable (0x40f5d0 callers).
	WinfailActions.apply_player_mode(next, runtime, "event_x", ["SID_克羅蒂", "1", "pmMagicAttack", "0"])
	check(runtime["unsupported_encountered"].is_empty() and unit["player_mode"] == 0x870000 and unit["battle_actor_role"] == "friendly_ai" and not unit["player_commandable"], "pmMagicAttack is a supported mode: AI-driven, side pmALL plus 0x800000")


func _reach_player(loop: Dictionary, label: String, attacks: Array, level: int, rng: RandomNumberGenerator) -> Dictionary:
	## Every AI unit takes its ordinary step_ai_turn (as the autoplay sweep does) until the
	## next controlled action menu; each settled exchange is recorded and printed.
	var next := loop
	for _step in range(4096):
		if str(next.get("interaction", "")) == "action_menu" or BattleOutcome.decided(next):
			return next
		if BattlePlayLoop.loot_waiting(next):
			var settlement: Dictionary = next["settlement"]
			next = BattlePlayLoop.finish_rewards(next, int(settlement["sequence"]), int(settlement["revision"]), false, true)
			continue
		if str(next.get("interaction", "")) != "ai_resolving":
			_assert_true(false, "%s stops in %s (%s)" % [label, str(next.get("interaction", "")), str(next.get("scenario_error", ""))])
			return next
		var before := int(next.get("last_combat", {}).get("sequence", 0))
		var stepped := BattlePlayLoop.step_ai_turn(next, rng)
		if stepped == next:
			_assert_true(false, "%s: step_ai_turn made no progress" % label)
			return next
		next = stepped
		var combat: Dictionary = next.get("last_combat", {})
		# A caster buffing itself (0x43fce1..0x43fd46: no ally in need, own mask useful) is a support cast, not an exchange.
		if int(combat.get("sequence", 0)) > before and str(combat.get("attacker_id", "")) != str(combat.get("defender_id", "")):
			var attacker := BattlePlayLoop.unit_ref(next, str(combat.get("attacker_id", "")))
			var defender := BattlePlayLoop.unit_ref(next, str(combat.get("defender_id", "")))
			attacks.append({"attacker": attacker, "defender": defender, "round": int(next.get("turn", 0))})
			print("PLAYER_MODE_SIDES_ATTACK level=%d round=%d attacker=%s(%s,0x%x) defender=%s(%s,0x%x)" % [level, int(next.get("turn", 0)),
				str(attacker.get("id", "")), str(attacker.get("actor_id", "")), ActorRoleRules.side_mask(attacker),
				str(defender.get("id", "")), str(defender.get("actor_id", "")), ActorRoleRules.side_mask(defender)])
	_assert_true(false, "%s did not return to a player action" % label)
	return next


func _all_wait_rounds(level: int, rounds: int, attacks: Array) -> Dictionary:
	var scenario: Dictionary = BattleScenario.load_file("res://content/battles/battle_%03d.json" % level)
	var loop := BattlePlayLoop.create([], "", scenario, level)
	_assert_true(bool(loop.get("scenario_ok", false)), "level %d PlayLoop creates (%s)" % [level, str(loop.get("scenario_error", ""))])
	if not bool(loop.get("scenario_ok", false)):
		return loop
	var rng := RandomNumberGenerator.new()
	rng.seed = 22
	loop = BattlePlayLoop.begin_battle(loop)
	loop = _reach_player(loop, "level %d battle start" % level, attacks, level, rng)
	var guard := 0
	while int(loop.get("turn", 0)) < rounds and guard < 64 and not BattleOutcome.decided(loop):
		if str(loop.get("interaction", "")) != "action_menu":
			print("PLAYER_MODE_SIDES_STOP level=%d turn=%d interaction=%s error=%s" % [level, int(loop.get("turn", 0)), str(loop.get("interaction", "")), str(loop.get("scenario_error", ""))])
			break
		loop = BattlePlayLoop.choose_command(loop, "wait")
		loop = _reach_player(loop, "level %d round %d" % [level, rounds], attacks, level, rng)
		guard += 1
	return loop


func _test_level6_soldiers_never_attack_villagers() -> void:
	var attacks: Array = []
	var loop := _all_wait_rounds(6, 3, attacks)
	if not bool(loop.get("scenario_ok", false)):
		return
	var villagers: Array = loop["units"].filter(func(unit): return str(unit.get("actor_id", "")) in ["061", "062"])
	check(villagers.size() == 12 and villagers.all(func(unit): return int(unit.get("player_mode", 0)) == PM_PLAYER_ENEMY and str(unit["battle_actor_role"]) == "friendly_ai"), "level 6 fields twelve pmPlayerEnemy villagers as uncommandable AI")
	var captain := BattlePlayLoop.unit(loop, "guard024_1")
	# 0x448840 drops the hp_level term for a live pmEnemy side (JobStatsRules.base_values):
	# the swapped 024 is 42 at L1, not the pmPlayer template's 43, before the +30 word.
	check(int(captain.get("max_hp", 0)) == 72 and int(captain.get("object_hit_point", 0)) == 30, "the inserted captain carries the +30 obj_HitPoint word (42 -> 72)")
	check(int(loop.get("turn", 0)) >= 2, "level 6 all-wait reaches round 2 (turn=%d)" % int(loop.get("turn", 0)))
	for record in attacks:
		var attacker: Dictionary = record["attacker"]
		var defender: Dictionary = record["defender"]
		check(ActorRoleRules.hostile(attacker, defender), "every exchange is between disjoint sides: %s -> %s" % [str(attacker.get("id", "")), str(defender.get("id", ""))])
		check(not (str(defender.get("actor_id", "")) in ["061", "062"]), "no soldier attacks a villager: %s -> %s" % [str(attacker.get("id", "")), str(defender.get("id", ""))])
		check(not (str(attacker.get("actor_id", "")) in ["061", "062"]), "no villager attacks anyone: %s -> %s" % [str(attacker.get("id", "")), str(defender.get("id", ""))])
	check(attacks.size() > 0, "the soldiers do engage the party in the first two rounds")
	print("PLAYER_MODE_SIDES_LEVEL6 rounds=%d exchanges=%d villagers_attacked=0 outcome=%s" % [int(loop.get("turn", 0)), attacks.size(), BattleOutcome.of(loop)])


func _test_level531_npc_rider_is_hostile_to_both_camps() -> void:
	var attacks: Array = []
	var loop := _all_wait_rounds(531, 3, attacks)
	if not bool(loop.get("scenario_ok", false)):
		return
	var rider := BattlePlayLoop.unit(loop, "actor049_1")
	check(not rider.is_empty() and int(rider.get("player_mode", 0)) == PM_NPC and str(rider.get("battle_actor_role", "")) == "enemy_ai", "encounter 531 fields the pmNPC 049 rider as AI")
	var captain := BattlePlayLoop.unit(loop, "actor024_1")
	check(int(captain.get("player_mode", 0)) == PM_ENEMY and int(captain.get("object_hit_point", 0)) == 50 and int(captain.get("max_hp", 0)) == 92, "the swapped 024 captain carries +50 HP (42 -> 92; no hp_level term on the pmEnemy side)")
	check(ActorRoleRules.hostile(rider, captain) and ActorRoleRules.hostile(rider, BattlePlayLoop.unit(loop, "leonard")), "the pmNPC rider is hostile to the pmEnemy captain and to the party")
	check(not ActorRoleRules.counts_as_enemy(rider), "the rider does not count for actCheckEnemyTotalNumber")
	var three_way := 0
	for record in attacks:
		check(ActorRoleRules.hostile(record["attacker"], record["defender"]), "every 531 exchange is between disjoint sides")
		if str(record["attacker"].get("actor_id", "")) == "049" or str(record["defender"].get("actor_id", "")) == "049":
			three_way += 1
	check(three_way > 0, "the pmNPC rider and the pmEnemy escort exchange blows (three-way battle)")
	print("PLAYER_MODE_SIDES_LEVEL531 rounds=%d exchanges=%d rider_exchanges=%d outcome=%s" % [int(loop.get("turn", 0)), attacks.size(), three_way, BattleOutcome.of(loop)])


# ---- run_tests.gd ----
## The two original random streams against the original. The damage／hit stream:
## DamageRandomStream replays original_damage_random.json (0x458c10 raw and 0x458c80 rand(n),
## executed on hsl01.exe by `hsl generate damage_random`) value for value from every recorded
## state, one exchange draws in the original order, and the save carries it. The global stream
## (0x4795d4／0x4795d8): the same generator, the static initial words, the clock seed of
## 0x458c10, and the emulated enemy turn of original_enemy_turn.json (`hsl generate
## enemy_turn`), whose every global draw GlobalRandomStream replays value for value from the
## turn's words; the save leaves it out.
const BattleCheckpoint = preload("res://game/battle/runtime/BattleCheckpoint.gd")
const PACKET_random_stream := "res://docs/evidence_packets/static_reverse/original_damage_random.json"
const ORACLE := "res://docs/evidence_packets/static_reverse/original_enemy_turn.json"
const FIRST_BATTLE := "res://content/battles/battle_051.json"
const VIEW := {"camera": Vector2(320, 240), "shown_story_events": [], "story_complete": true, "growth_notified_level": 1}
## The AI's decision stream is the global one; the damage-stream replay pins it so only the
## damage stream carried by the save decides whether the results repeat.
const DECISION_SEED := 11


func run_random_stream() -> void:
	damage_native_cases()
	damage_order_cases()
	damage_save_load_cases()
	global_native_cases()
	oracle_cases()
	session_cases()
	global_save_load_cases()
	new_campaign_cases()


static func words(text: String) -> Array:
	var out: Array = []
	for index in range(0, text.length(), 8):
		out.append(text.substr(index, 8).hex_to_int())
	return out


static func state_of(value: Variant) -> Array:
	return DamageRandomStream.from_words(value)


func damage_native_cases() -> void:
	var packet: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(PACKET_random_stream))
	var bounds: Array = packet["bounds"].map(func(b): return int(b))
	var draws := int(packet["draws"])
	check(packet["states"].size() >= 3 and draws == 1000, "native packet covers at least 3 states × 1000 draws")
	for row in packet["states"]:
		var start := state_of(row["state"])
		check(DamageRandomStream.valid(start), "native start state is two u32 words")
		var native_raw := words(row["raw_hex"])
		var state := start.duplicate()
		var raw_ok := native_raw.size() == draws
		for index in range(draws):
			var step := DamageRandomStream.raw(state)
			state = step["state"]
			if not raw_ok or int(step["value"]) != int(native_raw[index]):
				raw_ok = false
				break
		check(raw_ok and state == state_of(row["raw_end"]), "0x458c10 raw draws match the original value for value from %s" % str(start))
		var native_rand := words(row["rand_hex"])
		state = start.duplicate()
		var rand_ok := native_rand.size() == draws
		for index in range(draws):
			var step := DamageRandomStream.rand(state, int(bounds[index % bounds.size()]))
			state = step["state"]
			if not rand_ok or int(step["value"]) != int(native_rand[index]):
				rand_ok = false
				break
		check(rand_ok and state == state_of(row["rand_end"]), "0x458c80 rand(n) matches the original for every cycled bound from %s" % str(start))
		var drawn := DamageRandomStream.rand(start, 0)
		check(drawn["value"] == 0 and drawn["state"] == start and row["rand_zero"]["state_unchanged"] == true, "rand(0) returns 0 without advancing, as 0x458c80 does")
		check(state_of(row["damage_wrapper"]["rand_end"]) == state_of(row["rand_end"]) and row["damage_wrapper"]["global_state_kept"] == true,
			"0x42c780 advances only the damage words, exactly like the generator on them")
	check(DamageRandomStream.seeded(0x12d687) == [0x12d687, 0xffed2978] and DamageRandomStream.seeded(-1) == [0xffffffff, 0], "new-game seed is [t, ~t] on 32-bit words")
	var loop := {DamageRandomStream.LOOP_KEY: DamageRandomStream.seeded(7)}
	var source := DamageRandomStream.loop_source(loop)
	var expected := DamageRandomStream.rand(DamageRandomStream.seeded(7), 100)
	check(int(source.call(100)) == int(expected["value"]) and loop[DamageRandomStream.LOOP_KEY] == expected["state"], "the loop source draws rand(n) and writes the state back at once")
	check(int(source.call(0)) == 0 and loop[DamageRandomStream.LOOP_KEY] == expected["state"], "the loop source's rand(0) leaves the stream where it was")
	var raw := DamageRandomStream.raw(expected["state"])
	check(int(source.call(-1)) == int(raw["value"]) and loop[DamageRandomStream.LOOP_KEY] == raw["state"], "a negative bound is the raw 0x42c720 draw")
	check(DamageRandomStream.advance(DamageRandomStream.seeded(7), 2) == raw["state"], "advance(n) walks the same chain")
	check(DamageRandomStream.from_words([1.0, 4294967295.0]) == [1, 0xffffffff] and DamageRandomStream.from_words([1.5, 2]).is_empty() and DamageRandomStream.from_words([-1, 2]).is_empty(), "carried JSON words are accepted only as exact u32 pairs")


## Leonard next to enemy021_1 (who always counters), Leonard to act. He carries one 會心
## (262: first use draws its 5–10 strength) and wears an HP auto-restore accessory (223:
## every final action below full HP draws rand(6)), so items and the turn-end tail share
## the stream with the exchanges.
static func duel(seed: int) -> Dictionary:
	var loop := BattleFixture.loop([], "", seed)
	var player := BattlePlayLoop.unit_ref(loop, "leonard")
	player["inventory"] = [262, 0, 0, 0, 0, 0, 0, 0]
	player["equipment"] = player["equipment"].filter(func(slot): return not str(slot["slot"]).begins_with("accessory"))
	player["equipment"].append({"slot": "accessory2", "item_code": 223})
	player.merge(BattlePlayLoop.ProgressionRules.refresh_growth_stats(player, loop["equipment_items"]), true)
	player["hp"] = int(player["max_hp"]) - 5
	player["live_speed"] = 100
	player["coord"] = Vector2i(15, 15)
	var target := BattlePlayLoop.unit_ref(loop, "enemy021_1")
	target["coord"] = player["coord"] + Vector2i.RIGHT
	target["combat_profile"]["attack_back"] = 100
	target["max_hp"] = 400
	target["hp"] = 400
	loop["turn_queue"] = BattlePlayLoop.CoreTurnQueue.rebuild(loop["units"])
	return BattlePlayLoop.select_player_unit(loop, "leonard")


## What a player sees of one step: every actor's HP／EXP／status, the last exchange's rolls
## and the stream.
static func observed(loop: Dictionary) -> Dictionary:
	var vitals := {}
	for actor in loop["units"]:
		vitals[actor["id"]] = [actor["hp"], actor["exp"], actor["status_flags"]]
	var combat: Dictionary = loop.get("last_combat", {})
	var strikes: Array = []
	for receipt in [combat, combat.get("counter", {})]:
		if receipt.is_empty(): continue
		for strike in [receipt] + receipt.get("followups", []):
			strikes.append([strike["attacker_id"], strike["hit_roll"], strike["hit"], strike["damage"], strike["critical"], strike["critical_roll"], strike["damage_detail"]["noise"]])
	return {"vitals": vitals, "strikes": strikes, "sequence": combat.get("sequence", 0), "stream": loop[DamageRandomStream.LOOP_KEY],
		"item": loop.get("last_item_use", {}).get("draws", []), "tail": loop.get("last_action_end", {}).get("draws", [])}


## Leonard drinks 會心 first, then three rounds of Leonard attacking and the AI side
## answering: the observed trace.
static func damage_play(loop: Dictionary) -> Array:
	var trace: Array = []
	var decisions := RandomNumberGenerator.new()
	decisions.seed = DECISION_SEED
	var next := loop
	for round in range(3):
		if str(next.get("interaction", "")) != "action_menu" or next.get("selected_unit_id") != "leonard": break
		if round == 0:
			next = BattlePlayLoop.use_item(next, "262")
			trace.append(observed(next))
		next = BattlePlayLoop.attack_target(BattlePlayLoop.choose_command(next, "attack"), "enemy021_1")
		trace.append(observed(next))
		if BattlePlayLoop.action_exhausted(next):
			next = BattlePlayLoop.finish_exhausted_action(next)
		for _step in range(60):
			if str(next.get("interaction", "")) != "ai_resolving": break
			next = BattlePlayLoop.step_ai_turn(next, decisions)
			trace.append(observed(next))
	trace.append(next.get("interaction", ""))
	return trace


## One exchange draws in the original order (0x4423c0 → 0x409be0 → 0x403860): counter gate
## rand(100), then the damage draws, then hit rand(100), then the critical rand(100).
func damage_order_cases() -> void:
	var loop := duel(5)
	var shadow := {DamageRandomStream.LOOP_KEY: loop[DamageRandomStream.LOOP_KEY]}
	var bounds: Array = []
	var logging := func(bound: int) -> int:
		bounds.append(bound)
		return DamageRandomStream.loop_draw(shadow, bound)
	var done := BattlePlayLoop.attack_target(BattlePlayLoop.choose_command(loop, "attack"), "enemy021_1", logging)
	var strike: Dictionary = done.get("last_combat", {})
	check(not strike.is_empty(), "the duel fixture settles one exchange")
	if strike.is_empty(): return
	var detail: Dictionary = strike["damage_detail"]
	var expected: Array = [100]
	if detail["path"] == "base_non_positive_floor": expected.append(5)
	elif detail["path"] == "base_weak_band": expected.append(int(detail["base_attack_minus_defense"]) + 4)
	var half := absi(int(detail["str_term"])) / 2
	expected.append_array([int(detail["effective_before_noise"]) * 30 / 100, half, half])
	if detail["used_nonpositive_fallback"]: expected.append(-1)
	check(int(detail["variance_bonus"]) == 0, "the fixture weapon has no element variance draws")
	expected.append(100)
	if strike["hit"]: expected.append(100)
	_assert_eq(bounds.slice(0, expected.size()), expected, "one exchange draws gate → damage → hit → critical in the original order")
	var live := BattlePlayLoop.attack_target(BattlePlayLoop.choose_command(loop, "attack"), "enemy021_1")
	check(observed(live)["strikes"] == observed(done)["strikes"] and live[DamageRandomStream.LOOP_KEY] == shadow[DamageRandomStream.LOOP_KEY],
		"the product exchange draws exactly those values from the loop's own stream and keeps where it stopped")


## Save → act and record → load → repeat → identical, as the original's reload (0x42e980
## restores the damage words) makes it. A different saved stream changes the results.
func damage_save_load_cases() -> void:
	var loop := duel(20260925)
	var saved := BattleCheckpoint.encode(loop, VIEW)
	check(saved["ok"], "the duel fixture is a savable boundary: " + str(saved.get("reason", "")))
	if not saved["ok"]: return
	var first := damage_play(loop)
	var decoded := BattleCheckpoint.decode(saved["bytes"], loop)
	check(decoded["ok"], "the save loads back")
	if not decoded["ok"]: return
	var restored: Dictionary = decoded["snapshot"]["loop"]
	check(restored[DamageRandomStream.LOOP_KEY] == loop[DamageRandomStream.LOOP_KEY], "the save keeps the damage stream words exactly")
	var again := damage_play(restored)
	var strikes := 0
	for step in first:
		if step is Dictionary: strikes += step["strikes"].size()
	check(strikes >= 3, "the replayed stretch settles at least three strikes (%d)" % strikes)
	var item_draws := 0
	var tail_draws := 0
	for step in first:
		if step is Dictionary:
			item_draws = maxi(item_draws, step["item"].size())
			tail_draws = maxi(tail_draws, step["tail"].size())
	check(item_draws == 1 and tail_draws >= 1, "the stretch also draws an item strength and a turn-end recovery from the same stream (item %d, tail %d)" % [item_draws, tail_draws])
	_assert_eq(again, first, "after loading, the same actions repeat the same HP, hits, damage, criticals and stream")
	check(first[first.size() - 2]["stream"] != loop[DamageRandomStream.LOOP_KEY], "the stretch advanced the saved stream")
	var other := BattlePlayLoop.copy(restored)
	other[DamageRandomStream.LOOP_KEY] = DamageRandomStream.advance(restored[DamageRandomStream.LOOP_KEY], 1)
	check(damage_play(other) != first, "a different saved stream gives different results: the save, not luck, repeats them")


func global_native_cases() -> void:
	var state: Array = GlobalRandomStream.STATIC_STATE.duplicate()
	var values: Array = []
	for _index in range(5):
		var step := GlobalRandomStream.raw(state)
		state = step["state"]
		values.append(int(step["value"]))
	_assert_eq(values, [0x75308ecb, 0x10a9752a, 0xc6c87601, 0xa18611ff, 0xb50b4dc4], "the static words 0x12345678／0x87654321 give the original's first five raw values")
	var probe := GlobalRandomStream.seeded(0x2a)
	check(GlobalRandomStream.raw(probe) == DamageRandomStream.raw(probe) and GlobalRandomStream.rand(probe, 99) == DamageRandomStream.rand(probe, 99) and GlobalRandomStream.advance(probe, 7) == DamageRandomStream.advance(probe, 7),
		"the global stream runs the damage stream's generator 0x458c10／0x458c80, not a second implementation")
	check(GlobalRandomStream.seeded(12) == [12, 12 ^ 0xe54a231c] and GlobalRandomStream.seeded(-1) == [0xffffffff, 0x1ab5dce3], "0x458c10's lazy seed stores [t, t ^ 0xe54a231c] on 32-bit words")
	check(GlobalRandomStream.seeded(12) != DamageRandomStream.seeded(12), "the same clock value seeds the two streams to different words")
	var loop := {GlobalRandomStream.LOOP_KEY: GlobalRandomStream.seeded(9)}
	var source := GlobalRandomStream.loop_source(loop)
	var expected := GlobalRandomStream.rand(GlobalRandomStream.seeded(9), 100)
	check(int(source.call(100)) == int(expected["value"]) and loop[GlobalRandomStream.LOOP_KEY] == expected["state"], "the loop source draws rand(n) and writes the state back at once")
	check(int(source.call(0)) == 0 and loop[GlobalRandomStream.LOOP_KEY] == expected["state"], "rand(0) leaves the stream where it was")
	var raw := GlobalRandomStream.raw(expected["state"])
	check(int(source.call(-1)) == int(raw["value"]) and loop[GlobalRandomStream.LOOP_KEY] == raw["state"], "a negative bound is the raw 0x458c10 draw")


## Every global draw of the emulated turn, in order, from the turn's starting words: the
## recorded values follow from rand(n)／raw alone, so nothing else drew from the stream
## between them (the damage draws of the one attack sit on the damage words).
func oracle_cases() -> void:
	var packet: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(ORACLE))
	var turn: Dictionary = packet["turns"][0]
	var streams := {"global": GlobalRandomStream.from_words(turn["rng"]["global"]), "damage": DamageRandomStream.from_words(turn["rng"]["damage"])}
	check(GlobalRandomStream.valid(streams["global"]) and DamageRandomStream.valid(streams["damage"]), "the oracle turn starts from two word pairs")
	var counts := {"global": 0, "damage": 0}
	var first_miss := ""
	for action in turn["actions"]:
		for draw in action["draws"]:
			var stream := str(draw["stream"])
			var bound := -1 if draw["n"] == null else int(draw["n"])
			var step := GlobalRandomStream.raw(streams[stream]) if bound < 0 else GlobalRandomStream.rand(streams[stream], bound)
			streams[stream] = step["state"]
			counts[stream] += 1
			if first_miss == "" and int(step["value"]) != int(draw["value"]):
				first_miss = "%s %s draw %d at %s" % [action["actor"], stream, counts[stream], draw["site"]]
	check(counts["global"] >= 500 and counts["damage"] >= 1, "the oracle turn records hundreds of global draws and the attack's damage draws (%s)" % str(counts))
	check(first_miss == "", "every oracle draw replays from the turn's words value for value (first miss: %s)" % first_miss)


## The process stream: seeded once on first use, by HSL_RNG_SEED when a headless run names
## one; the running battle hands its words back.
func session_cases() -> void:
	var saved := OS.get_environment(GlobalRandomStream.SEED_ENV)
	OS.set_environment(GlobalRandomStream.SEED_ENV, "77")
	GlobalRandomStream.reset_session()
	check(GlobalRandomStream.session() == GlobalRandomStream.seeded(77), "headless with HSL_RNG_SEED, the first use seeds the process stream from it")
	var first := GlobalRandomStream.session_draw(100)
	check(first == int(GlobalRandomStream.rand(GlobalRandomStream.seeded(77), 100)["value"]) and GlobalRandomStream.session() == GlobalRandomStream.rand(GlobalRandomStream.seeded(77), 100)["state"], "a session draw advances the process stream")
	OS.set_environment(GlobalRandomStream.SEED_ENV, "78")
	check(GlobalRandomStream.session() == GlobalRandomStream.rand(GlobalRandomStream.seeded(77), 100)["state"], "the process stream is seeded once; a later seed does not re-seed it")
	var loop := {GlobalRandomStream.LOOP_KEY: GlobalRandomStream.session()}
	GlobalRandomStream.loop_draw(loop, 99)
	GlobalRandomStream.loop_draw(loop, -1)
	GlobalRandomStream.remember(loop)
	check(GlobalRandomStream.session() == loop[GlobalRandomStream.LOOP_KEY], "remember adopts the battle loop's words as the process stream")
	GlobalRandomStream.reset_session()
	check(GlobalRandomStream.session() == GlobalRandomStream.seeded(78), "reset forgets the stream and the next use seeds it again")
	if saved == "": OS.unset_environment(GlobalRandomStream.SEED_ENV)
	else: OS.set_environment(GlobalRandomStream.SEED_ENV, saved)
	GlobalRandomStream.reset_session()


## The duel above with the product AI: every AI step draws from the
## loop's own global words (no decision source handed in). Per step: what a player sees,
## the AI's decision, and the global words.
static func global_play(loop: Dictionary) -> Array:
	var trace: Array = []
	var next := loop
	for round in range(3):
		if str(next.get("interaction", "")) != "action_menu" or next.get("selected_unit_id") != "leonard": break
		next = BattlePlayLoop.attack_target(BattlePlayLoop.choose_command(next, "attack"), "enemy021_1")
		trace.append({"seen": observed(next), "ai": {}, "global": next[GlobalRandomStream.LOOP_KEY]})
		if BattlePlayLoop.action_exhausted(next):
			next = BattlePlayLoop.finish_exhausted_action(next)
		for _step in range(60):
			if str(next.get("interaction", "")) != "ai_resolving": break
			next = BattlePlayLoop.step_ai_turn(next)
			var act: Dictionary = next.get("last_ai_action", {})
			trace.append({"seen": observed(next), "global": next[GlobalRandomStream.LOOP_KEY],
				"ai": {"actor": act.get("actor_id", ""), "kind": act.get("kind", ""), "to": act.get("to", act.get("from")), "target": act.get("target_id", "")}})
	return trace


static func first_ai(trace: Array) -> int:
	for index in range(trace.size()):
		if not trace[index]["ai"].is_empty(): return index
	return -1


## Save → play → load into a battle whose global stream has moved on → play again: the
## save holds the damage words, not the global ones (the original keeps 0x4795d4／0x4795d8
## out of its save and seeds them from the clock), so everything up to the first AI step
## repeats exactly and the AI may then choose differently — the first live advance of the
## global words that turns its first choice is searched, not pinned; the same global words
## replay the whole stretch.
## The target stands left of Leonard: 0x413390 ranks the station right of him first, and
## with a foe beside it the actor walks round there only on rand(99) + 1 above 92
## (0x440b2c state 0xb sub 0), so the global words can change its first choice. (Right of
## him, that station is its own cell and both outcomes are the same attack in place.)
func global_save_load_cases() -> void:
	var loop := duel(20260925)
	BattlePlayLoop.unit_ref(loop, "enemy021_1")["coord"] = BattlePlayLoop.unit_ref(loop, "leonard")["coord"] + Vector2i.LEFT
	loop["turn_queue"] = BattlePlayLoop.CoreTurnQueue.rebuild(loop["units"])
	loop = BattlePlayLoop.select_player_unit(loop, "leonard")
	check(not BattleCheckpoint.state(loop).has(GlobalRandomStream.LOOP_KEY) and BattleCheckpoint.state(loop).has(DamageRandomStream.LOOP_KEY), "the saved half of the loop holds the damage stream and not the global stream")
	var saved := BattleCheckpoint.encode(loop, VIEW)
	check(saved["ok"], "the duel fixture is a savable boundary: " + str(saved.get("reason", "")))
	if not saved["ok"]: return
	var first := global_play(loop)
	var ai_at := first_ai(first)
	check(ai_at >= 1, "the stretch reaches an AI step after the player's strike (%d)" % ai_at)
	if ai_at < 1: return
	var live := {}
	var restored := {}
	var again: Array = []
	for advance in range(1, 65):
		live = BattlePlayLoop.copy(loop)
		live[GlobalRandomStream.LOOP_KEY] = GlobalRandomStream.advance(loop[GlobalRandomStream.LOOP_KEY], advance)
		var decoded := BattleCheckpoint.decode(saved["bytes"], live)
		check(decoded["ok"], "the save loads back into the running battle: " + str(decoded.get("reason", "")))
		if not decoded["ok"]: return
		restored = decoded["snapshot"]["loop"]
		again = global_play(restored)
		if first_ai(again) == ai_at and again[ai_at]["ai"] != first[ai_at]["ai"]: break
	check(restored[DamageRandomStream.LOOP_KEY] == loop[DamageRandomStream.LOOP_KEY] and restored[GlobalRandomStream.LOOP_KEY] == live[GlobalRandomStream.LOOP_KEY], "the load restores the saved damage words and keeps the running battle's global words")
	check(first_ai(again) == ai_at, "the loaded stretch reaches its AI step at the same point (%d)" % first_ai(again))
	_assert_eq(again.slice(0, ai_at).map(func(step): return step["seen"]), first.slice(0, ai_at).map(func(step): return step["seen"]), "after loading, the player's strike repeats the same hits, damage, criticals and damage stream")
	check(again.size() > ai_at and again[ai_at]["ai"] != first[ai_at]["ai"], "some live global words within 64 advances change the AI's first choice after the load (%s)" % str(first[ai_at]["ai"]))
	var pinned := BattlePlayLoop.copy(restored)
	pinned[GlobalRandomStream.LOOP_KEY] = (loop[GlobalRandomStream.LOOP_KEY] as Array).duplicate()
	_assert_eq(global_play(pinned), first, "the loaded battle with the save-time global words replays the whole stretch, AI included")


## A new battle's NPC opening levels (InitialRosterGrowthRules, 0x40e870 rand draws) come
## from the process stream: the same HSL_RNG_SEED gives the same levels, other seeds other
## levels.
static func opening_levels(scenario: Dictionary, seed: int) -> Array:
	OS.set_environment(GlobalRandomStream.SEED_ENV, str(seed))
	GlobalRandomStream.reset_session()
	var loop := BattlePlayLoop.initialize_roster_growth(BattlePlayLoop.create([], "", scenario, 1, GlobalRandomStream.session()))
	var levels: Array = []
	for unit in loop["units"]:
		if unit.has("entry_growth"): levels.append([unit["id"], unit["level"], unit["max_hp"]])
	return levels


func new_campaign_cases() -> void:
	var saved := OS.get_environment(GlobalRandomStream.SEED_ENV)
	var scenario := BattlePlayLoop.BattleScenario.load_file(FIRST_BATTLE)
	check(bool(scenario.get("ok", false)), "battle 051 loads")
	if not bool(scenario.get("ok", false)): return
	var rosters := {}
	for seed in [1, 2, 3, 4]:
		var levels := opening_levels(scenario, seed)
		check(not levels.is_empty(), "battle 051 has NPCs with an opening level adjustment (seed %d)" % seed)
		_assert_eq(opening_levels(scenario, seed), levels, "the same HSL_RNG_SEED gives the same opening levels (seed %d)" % seed)
		rosters[str(levels)] = seed
	check(opening_levels(scenario, 1) != opening_levels(scenario, 2) and rosters.size() >= 3, "different seeds give different opening levels (%d distinct rosters of 4)" % rosters.size())
	if saved == "": OS.unset_environment(GlobalRandomStream.SEED_ENV)
	else: OS.set_environment(GlobalRandomStream.SEED_ENV, saved)
	GlobalRandomStream.reset_session()
