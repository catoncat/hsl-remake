extends SceneTree
const TestSuite = preload("res://tests/support/TestSuite.gd")
const Rules = preload("res://game/sim/AIPriorityRules.gd")
const Loop = preload("res://game/battle/scene/BattlePlayLoop.gd")
const Items = preload("res://game/sim/ItemUseRules.gd")
const Fixtures = preload("res://tests/run_ai_decision_tests.gd")
const BattleFixture = preload("res://tests/support/BattleFixture.gd")
var failures: Array[String] = []
var checks := 0


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	native_cases()
	healing_cases()
	opportunity_cases()
	given_medicine()
	atomic_failures()
	await runtime_feedback()
	failures.append_array(await TestSuite.settle_audio_before_quit(self, 0.3))
	print("AI_PRIORITY_TESTS_", "PASS" if failures.is_empty() else "FAIL", " checks=", checks)
	quit(0 if failures.is_empty() else 1)


func native_cases() -> void:
	var packet: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://docs/evidence_packets/static_reverse/original_ai_priority.json"))
	for row in packet["cases"]:
		var input: Dictionary = row["input"]
		var before := input.duplicate(true)
		var cursor := [0]
		var rng := func(bound):
			check(cursor[0] < row["draws"].size(), "no additional priority RNG")
			if cursor[0] >= row["draws"].size(): return 0
			var draw: Dictionary = row["draws"][cursor[0]]
			cursor[0] += 1
			check(bound == int(draw["bound"]), "priority RNG bound matches original")
			return int(draw["value"])
		var result: Dictionary
		match input["kind"]:
			"priority":
				result = Rules.choose_check({"ai_check_hp": input["self_rate"], "ai_check_dying": input["dying_rate"]}, int(input["attempted"]), rng)
				for key in ["kind", "attempted", "next_roll"]:
					check(result["ok"] and result[key] == int(row["result"][key]), "priority prefix output " + key)
			"self_hp":
				result = Rules.self_recovery(input, rng)
				check(result["ok"] and int(result["needed"]) == int(row["result"]["native"]) and result["threshold"] == int(row["result"]["threshold"]), "self HP remainder threshold matches original")
			"dying":
				var units: Array = input["units"].duplicate(true)
				for unit in units:
					if unit != null:
						unit["coord"] = Vector2i(int(unit["coord"][0]), int(unit["coord"][1]))
						unit.merge({"level": 1, "job": 80})
				result = Rules.low_hp_target(units, int(input["owner"]), int(input["radius"]), int(input["excluded"]), int(input["cursor"]), rng)
				check(result["ok"] and result["native_index"] == int(row["result"]["native"]), "dying target matches original full return")
				check(result["evaluated"] == row["result"]["evaluated"].map(func(value): return {"index": int(value["index"]), "threshold": int(value["threshold"])}), "every absolute threshold and cursor matches original")
			"heal_item":
				var catalog := {}
				for code in input["items"]:
					var item: Dictionary = input["items"][code]
					# Live catalog is a registered subset of source type1 consumables.
					if int(item["type"]) == 1: catalog[code] = {"heal_hp": int(item["heal_hp"]), "cure_poison": 1 if int(item["heal_hp"]) == 0 else 0, "cure_paralysis": 0}
				result = Items.first_healing_slot(input["slots"], catalog)
				check(result["ok"] and result["index"] + 1 == int(row["result"]["native"]), "first registered healing slot follows native inventory order")
		check(input == before and cursor[0] == row["draws"].size(), "immutable input and exact source random consumption")


static func healing_code(loop: Dictionary) -> int:
	for code in loop["consumables"]:
		if int(loop["consumables"][code]["heal_hp"]) > 0: return int(code)
	return 0


static func opportunity_fixture(owner: String = "enemy021_1") -> Dictionary:
	var loop := Fixtures.live_fixture(owner)
	var wounded := Loop.unit(loop, "leonard")
	wounded.merge({"id": "priority-wounded", "coord": Vector2i(6, 3), "hp": 8, "max_hp": 100, "live_speed": 1, "player_commandable": false}, true)
	loop["units"].append(wounded)
	loop["turn_queue"] = Loop.CoreTurnQueue.rebuild(loop["units"])
	return loop


static func recovery_fixture() -> Dictionary:
	var loop := opportunity_fixture()
	var actor := Loop._unit(loop, "enemy021_1")
	actor["hp"] = 4
	actor["inventory"] = [healing_code(loop), healing_code(loop), 0, 0, 0, 0, 0, 0]
	return loop


func healing_cases() -> void:
	var before := recovery_fixture()
	var saved := before.duplicate(true)
	var actor := Loop.unit(before, "enemy021_1")
	var after := Loop.step_ai_turn(before, func(_n): return 0)
	check(after["scenario_ok"], "self recovery preflight accepts valid source inputs")
	if not after["scenario_ok"]: return
	var action: Dictionary = after["last_ai_action"]
	var healed := Loop.unit(after, actor["id"])
	check(action["kind"] == "use_item" and action["ai_decision"]["priority"]["checks"][0]["kind"] == 2, "source self-recovery priority precedes reachable dying foe")
	check(healed["hp"] == 4 + mini(int(before["consumables"][str(healing_code(before))]["heal_hp"]), 396), "one shared healing effect is applied")
	check(healed["inventory"] == [healing_code(before), 0, 0, 0, 0, 0, 0, 0] and healed["coord"] == actor["coord"], "one ordered item is consumed without movement")
	check(after["selected_unit_id"] == "enemy023_1" and after["turn_queue"]["index"] == 1 and after["last_ai_actions"].size() == 1, "AI item ends exactly one action")
	check(before == saved and not action.has("damage") and Loop.unit(after, "priority-wounded")["hp"] == 8, "healing cannot also attack or mutate input")
	check(Loop.step_ai_turn(after, func(_n): check(false, "completed AI cannot act again"); return 0) == after, "duplicate AI step is inert after player handoff")
	var player := before.duplicate(true)
	Loop._unit(player, actor["id"])["player_commandable"] = true
	Loop._unit(player, actor["id"])["battle_actor_role"] = Loop.ROLE_PLAYER
	player = Loop._return_to_player(player, actor["id"])
	var used := Loop.use_item(player, str(healing_code(player)), actor["id"], 0)
	var player_effect:Dictionary = used["last_item_use"].duplicate(true)
	var ai_effect:Dictionary = after["last_item_use"].duplicate(true)
	check(player_effect["actor_before"]["battle_actor_role"] == Loop.ROLE_PLAYER and ai_effect["actor_before"]["battle_actor_role"] == Loop.ROLE_ENEMY, "item replay snapshots retain the actual caller's role and decision provenance")
	for receipt in [player_effect,ai_effect]:
		for key in ["actor_before","target_before"]: receipt.erase(key)
	check(player_effect == ai_effect and Loop.unit(used, actor["id"])["inventory"] == healed["inventory"], "player and AI share the complete effect, inventory, RNG and sequence receipt despite distinct caller snapshots")
	var poisoned := before.duplicate(true)
	Loop._unit(poisoned, actor["id"])["status_flags"] = 3
	Loop._unit(poisoned, actor["id"])["status_counters"] = {"poison": (5 << 16) | 2, "paralysis": 0, "no_magic": 1}
	var settled := Loop.step_ai_turn(poisoned, func(_n): return 0)
	check(settled["last_ai_action"]["kind"] == "use_item" and Loop.unit(settled, actor["id"])["hp"] == healed["hp"] - 5 and Loop.unit(settled, actor["id"])["status_counters"] == {"poison": (5 << 16) | 1, "paralysis": 0, "no_magic": 0}, "self medicine is allowed under silence and ticks poison/status once")
	for health in [395, 400]:
		var healthy := before.duplicate(true)
		Loop._unit(healthy, actor["id"])["hp"] = health
		var attacked := Loop.step_ai_turn(healthy, func(_n): return 0)
		# The strike kills priority-wounded; 0x442720 state 4 hands its rolled drops to this non-player
		# killer through 0x44f600 (0x4428cd), so only the slots the hand-over filled may differ.
		var taken: Array = attacked.get("last_combat", {}).get("rewards", {}).get("taken", [])
		var kept: Array = Loop.unit(attacked, actor["id"])["inventory"].duplicate()
		for row in taken:
			if int(row["slot"]) >= 0: kept[int(row["slot"])] = 0
		check(attacked["last_ai_action"]["kind"] != "use_item" and kept == actor["inventory"], "full or nearly full HP preserves medicine and allows offense")
		check(taken.map(func(row): return [int(row["code"]), int(row["slot"])]) == [[246, 2]] and Loop.unit(attacked, actor["id"])["inventory"] == [healing_code(attacked), healing_code(attacked), 246, 0, 0, 0, 0, 0], "the kill hands the victim's drop to the AI killer's first empty slot (0x44f600): " + str(taken))


func opportunity_cases() -> void:
	for owner in ["enemy021_1", "enemy026_1"]:
		var loop := opportunity_fixture(owner)
		var after := Loop.step_ai_turn(loop, func(_n): return 0)
		check(after["scenario_ok"], "priority offensive preflight " + owner)
		if not after["scenario_ok"]: continue
		var action: Dictionary = after["last_ai_action"]
		check(action["ai_decision"]["target_selection"]["index"] == 1 and action["defender_id"] == "priority-wounded" and action["ai_decision"]["priority"]["kind"] == "dying", "dying opportunity overrides ordinary healthy target " + owner)
		check(after["selected_unit_id"] == "enemy023_1" and after["last_ai_actions"].size() == 1, "priority offense hands to player once")
		if owner == "enemy026_1":
			check(action.has("skill_id") and Loop.unit(after, owner)["mp"] == Loop.unit(loop, owner)["mp"] - action["resource_payment"]["amount"], "priority magic uses one shared resource debit")
		else:
			check(action["kind"] == "move_then_attack" and Loop.movement_cells(loop, owner).has(action["to"]), "priority melee executes a legal real movement path")
	var disabled := opportunity_fixture()
	TestSuite.own(disabled, "ai_profiles")["actors"]["021"]["profile"]["ai_check_dying"] = 0
	check(Loop.step_ai_turn(disabled, func(_n): return 0)["last_ai_action"]["defender_id"] == "leonard", "zero source tendency preserves ordinary target")
	var corner := opportunity_fixture()
	TestSuite.own(corner, "ai_profiles")["actors"]["021"]["profile"]["find_range"] = 1
	Loop._unit(corner, "priority-wounded")["coord"] = Vector2i(4, 4)
	check(Loop.step_ai_turn(corner, func(_n): return 0)["last_ai_action"]["defender_id"] == "priority-wounded", "source square scan reaches diagonal excluded by ordinary circular search")
	var blocked := opportunity_fixture()
	var sealed := Loop.unit(blocked, "priority-wounded")
	sealed.merge({"id": "sealed-foe", "coord": Vector2i(8, 8), "hp": 1}, true)
	blocked["units"].insert(1, sealed)
	for offset in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]: TestSuite.own(blocked, "tiles")[sealed["coord"] + offset] = {"blocks_movement": true}
	var bypass := Loop.step_ai_turn(blocked, func(_n): return 0)
	check(bypass["last_ai_action"]["defender_id"] == "priority-wounded" and bypass["last_ai_action"]["ai_decision"]["priority"]["scans"].size() >= 2, "unreachable dying foe resumes scanner and cannot suppress later legal strike")
	var prohibited := opportunity_fixture()
	Loop._unit(prohibited, "enemy021_1")["no_attack"] = true
	check(not Loop.step_ai_turn(prohibited, func(_n): return 0)["last_ai_action"].has("damage"), "no-attack capability cannot be bypassed by low-HP priority")


func given_medicine() -> void:
	var loop := BattleFixture.loop()
	var player := Loop.unit(loop, "leonard")
	var ally := Loop.unit(loop, "enemy023_1")
	var enemy := Loop.unit(loop, "enemy021_1")
	player.merge({"coord": Vector2i(3, 3), "live_speed": 100}, true)
	ally.merge({"coord": Vector2i(4, 3), "live_speed": 90, "hp": 4, "max_hp": 400}, true)
	enemy.merge({"coord": Vector2i(6, 3), "live_speed": 10, "hp": 400, "max_hp": 400}, true)
	loop["units"] = [player, ally, enemy]
	loop["tiles"] = {}
	loop["reinforcement_templates"] = []
	loop["turn_queue"] = Loop.CoreTurnQueue.rebuild(loop["units"])
	loop = Loop._return_to_player(loop, player["id"])
	var code := healing_code(loop)
	var slot := Loop.InventoryRules.find_item(player["inventory"], code)
	loop = Loop.begin_give(loop)
	loop = Loop.confirm_give(loop, ally["id"], slot, code, -1, 0, int(loop["item_revision"]))
	loop = Loop.finish_give(loop, int(loop["item_revision"]))
	check(Loop.CoreTurnQueue.current(loop["turn_queue"])["id"] == ally["id"], "giving medicine hands to the real friendly AI")
	var healed := Loop.step_ai_turn(loop, func(_n): return 0)
	check(healed["last_ai_action"]["kind"] == "use_item" and Loop.unit(healed, ally["id"])["hp"] > 4 and Loop.unit(healed, ally["id"])["inventory"].all(func(value): return value == 0), "AI actually uses medicine received through player Give")


func atomic_failures() -> void:
	for corruption in ["rate", "max_hp", "inventory", "item", "diagonal_skill_target"]:
		var loop := recovery_fixture() if corruption != "diagonal_skill_target" else opportunity_fixture("enemy026_1")
		match corruption:
			"rate": TestSuite.own(loop, "ai_profiles")["actors"]["021"]["profile"].erase("ai_check_dying")
			"max_hp": Loop._unit(loop, "priority-wounded")["max_hp"] = null
			"inventory": Loop._unit(loop, "enemy021_1")["inventory"] = [healing_code(loop)]
			"item": TestSuite.own(loop, "consumables")[str(healing_code(loop))]["heal_hp"] = "bad"
			"diagonal_skill_target":
				TestSuite.own(loop, "ai_profiles")["actors"]["026"]["profile"]["find_range"] = 1
				Loop._unit(loop, "priority-wounded")["coord"] = Vector2i(4, 4)
				Loop._unit(loop, "priority-wounded")["combat_profile"].erase("resist_by_type")
		var saved := loop.duplicate(true)
		var rejected := Loop.step_ai_turn(loop, func(_n): check(false, "invalid priority data rejects before RNG: " + corruption); return 0)
		check(not rejected["scenario_ok"] and rejected["interaction"] == "scenario_error", "priority input is explicitly rejected: " + corruption)
		check(loop == saved and rejected["units"] == saved["units"] and rejected["turn_queue"] == saved["turn_queue"] and rejected.get("last_item_use", {}) == saved.get("last_item_use", {}) and rejected["last_ai_actions"] == saved["last_ai_actions"], "failed priority preserves inventory, HP, call tags, queue and receipts: " + corruption)


func runtime_feedback() -> void:
	var scene = load("res://game/battle/scene/BattleSceneRuntime.tscn").instantiate()
	scene.scenario_path = BattleFixture.PATH; scene.startup_mode = "dev_first_control"
	root.add_child(scene)
	await process_frame
	scene.start_dev_first_control_harness()
	scene.set_process(false)
	scene.apply_loop(recovery_fixture(), "test")
	scene.resume_turn_presentation()
	scene.tick_ai_playback(1.0)
	var presentation = scene.get_node("BattlePresentation")
	check(presentation.item_feedback_busy() and scene.ai_playback_active and not scene.action_menu.is_visible_in_tree(), "AI medicine keeps next controls hidden during feedback")
	var settled: Dictionary = scene.play_loop.duplicate(true)
	# sfxUseItem plays as the item applies, after the AI lead-in.
	var lead_deadline := Time.get_ticks_msec() + 3000
	while presentation.item_use.stage == "lead" and Time.get_ticks_msec() < lead_deadline: await create_timer(0.02).timeout
	await wait_for_mixer(scene.ui_audio)
	var feedback_voice: WeakRef = weakref(scene.ui_audio.get_stream_playback())
	scene.flush_ai_playback()
	check(not presentation.item_feedback_busy() and not scene.ai_playback_active and scene.selected_unit_id == "enemy023_1", "existing explicit fast-forward also completes new item feedback")
	check(scene.play_loop == settled and not presentation.show_item_use(settled["last_item_use"], Vector2.ZERO), "finishing/replaying visual feedback cannot repeat item or queue settlement")
	# Let the independent mixer observe the started/stopped voices before teardown.
	await create_timer(0.1).timeout
	scene.ui_audio.stop()
	scene.ui_audio.stream = null
	scene.queue_free()
	await process_frame
	var deadline := Time.get_ticks_msec() + 2000
	while feedback_voice.get_ref() != null and Time.get_ticks_msec() < deadline:
		await create_timer(0.02).timeout
	check(feedback_voice.get_ref() == null, "stopped feedback voice releases before the test exits")


func wait_for_mixer(player: AudioStreamPlayer) -> void:
	# Visual fast-forward can start and stop a voice before the audio thread has
	# consumed its start. Observe an actual mix before exercising the stop path.
	var deadline := Time.get_ticks_msec() + 2000
	while player.playing and player.get_playback_position() <= 0.0 and Time.get_ticks_msec() < deadline:
		await create_timer(0.01).timeout
	check(player.get_playback_position() > 0.0, "audio mixer observes the started feedback voice")


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error(label)
