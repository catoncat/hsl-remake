extends SceneTree
const GameOptions = preload("res://game/settings/GameOptions.gd")

## Scripted walks in play (BattleOpeningCoordinator + ScriptWalkPath), on level 6 席達鎮's
## captain-down retreat (WINFAIL006 win_0: nine actWalkAndDelete with actDelay 2 between
## them, then one actWalkAndDeleteWait). The original VM only parks on a Wait walker
## (0x453b90 state 0x32), so the ten soldiers leave together, each stepping cell by cell
## around the stairs and walls (0x4111d0 path buffer) instead of gliding through them.
## Asserts: the soldiers walk at the same time, every walked cell is passable, the retreat
## is over in a few seconds, and Enter during the retreat (remake fast-forward) lands every
## walker at once without changing where it ends.

const RuntimeScene = preload("res://game/battle/scene/BattleSceneRuntime.tscn")
const CampaignProgress = preload("res://game/battle/runtime/CampaignProgress.gd")
const ForceWin = preload("res://tests/support/BattleForceWin.gd")
const TestSuite = preload("res://tests/support/TestSuite.gd")
const ScriptWalkPath = preload("res://game/battle/runtime/opening/ScriptWalkPath.gd")
const OriginalTick = preload("res://game/battle/runtime/OriginalTick.gd")
const RETREAT_SOLDIERS := 10

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _assert_true(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _run() -> void:
	CampaignProgress.pending = {}
	CampaignProgress.resume_prompt_in_headless = false
	await _retreat(false)
	await _retreat(true)
	await _rope()
	await TestSuite.settle_wall_clock(self, 0.3)
	await process_frame
	if failures.is_empty():
		print("SCRIPT_WALK_TESTS_PASS")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		print("SCRIPT_WALK_TESTS_FAIL count=%d" % failures.size())
		quit(1)


## Boots level 6, plays the opening to first control, defeats the captain and plays the
## win_0 retreat at the script's own walk speed.
func _retreat(fast_forward: bool) -> void:
	var label := "level 6 retreat%s" % (" (fast-forward)" if fast_forward else "")
	GameOptions.environment_preset = "comfort" if fast_forward else ""  # OPT-PACE 快: confirm fast-forwards (原版 has no skip)
	var scene = RuntimeScene.instantiate()
	scene.scenario_path = "res://content/battles/battle_006.json"
	scene.startup_mode = "product_opening"
	root.add_child(scene)
	await process_frame
	await process_frame
	await ForceWin.play_opening(self, scene, label, _assert_true)
	var coordinator = scene.opening_coordinator
	coordinator.walk_pixels_per_second = coordinator.DEFAULT_WALK_SPEED * OriginalTick.TICKS_PER_SECOND
	var rules = scene.BattlePlayLoop
	scene.set_process(false)
	var loop: Dictionary = rules.copy(scene.play_loop)
	loop["fail_statuses"] = []
	rules._set_unit_defeated(loop, "guard024_1", true)
	loop = rules._resolve_outcome(rules.BattleScenarioRuleAdapter.run_event_hooks(loop))
	scene.apply_loop(loop, "test")
	scene.set_process(true)
	var tiles: Dictionary = scene.play_loop["tiles"]
	var map_size: Vector2i = scene.play_loop["map_size"]
	var retreat_ids := {}
	var most_walking := 0
	var first_walk_ms := -1.0
	var last_walk_ms := -1.0
	var elapsed := 0.0
	var pressed := false
	for _frame in range(3000):
		await process_frame
		elapsed += root.get_process_delta_time()
		if coordinator.active and coordinator.cutscene_mode:
			var walking := 0
			for record in coordinator.motion_records:
				if str(record.get("source_event_id", "")).begins_with("winfail006_win_0") and str(record.get("kind", "")) == "walk":
					retreat_ids[str(record["unit_id"])] = record
			for id in retreat_ids:
				var actor: Node = scene.actor_node_for_unit(id)
				if actor != null and actor.is_moving():
					walking += 1
			most_walking = maxi(most_walking, walking)
			if walking > 0:
				if first_walk_ms < 0.0:
					first_walk_ms = elapsed
				last_walk_ms = elapsed
			if fast_forward and not pressed and retreat_ids.size() == RETREAT_SOLDIERS and walking > 0:
				var enter := InputEventKey.new()
				enter.keycode = KEY_ENTER
				enter.pressed = true
				coordinator.handle_input(enter)
				pressed = true
				var still := 0
				for id in retreat_ids:
					if scene.actor_node_for_unit(id).is_moving():
						still += 1
				_assert_true(still == 0, "%s: Enter lands every walking soldier at once (%d still walking)" % [label, still])
			if str(coordinator.summary().get("current_event_kind", "")) in ForceWin.CLICK_THROUGH_KINDS:
				coordinator.handle_input(ForceWin.click())
		if scene.get_node("BattlePresentation").battle_finished:
			break
	print("SCRIPT_WALK_RETREAT %s most_walking=%d walking_seconds=%.2f" % [label, most_walking, last_walk_ms - first_walk_ms])
	_assert_true(retreat_ids.size() == RETREAT_SOLDIERS, "%s: all ten soldiers walk off (%d)" % [label, retreat_ids.size()])
	for id in retreat_ids:
		var record: Dictionary = retreat_ids[id]
		var cells: Array = record.get("route_cells", [])
		_assert_true(str(record.get("route_status", "")) == "grid_path", "%s: %s reaches its exit on a grid path (%s)" % [label, id, str(record.get("route_status", ""))])
		for index in range(1, cells.size()):
			_assert_true(ScriptWalkPath.can_step(tiles, map_size, cells[index - 1], cells[index], false), "%s: %s never steps onto an impassable cell (%s)" % [label, id, str(cells[index])])
		_assert_true(is_equal_approx(float(record.get("speed_arg", 0.0)), 8.0), "%s: %s walks at the script speed 8 (%s)" % [label, id, str(record.get("speed_arg"))])
		var actor: Node = scene.actor_node_for_unit(id)
		_assert_true(actor == null or not actor.visible, "%s: %s has left the scene" % [label, id])
	GameOptions.environment_preset = ""
	if fast_forward:
		_assert_true(pressed and coordinator.story_records.any(func(record): return str(record.get("kind", "")) == "motion_fast_forward"), "%s: the fast-forward is recorded" % label)
	else:
		_assert_true(most_walking >= RETREAT_SOLDIERS - 2, "%s: the soldiers retreat together, not one by one (at most %d walking at once)" % [label, most_walking])
		_assert_true(last_walk_ms - first_walk_ms < 4.0, "%s: the retreat is over in a few seconds (%.2f s)" % [label, last_walk_ms - first_walk_ms])
	_assert_true(scene.get_node("BattlePresentation").battle_finished, "%s: the victory result page follows the retreat" % label)
	scene.queue_free()
	await process_frame
	await process_frame


## STORY053's rope (obj_Story_Level53_Rope, engRANGE) stands on the raw script pixel like
## every story object and hangs down from the balcony edge, unrolling over the following
## actDelay 80 (provisional reading), so 緹娜's slide runs along it.
func _rope() -> void:
	var scene = RuntimeScene.instantiate()
	scene.scenario_path = "res://content/battles/battle_053.json"
	scene.startup_mode = "product_opening"
	root.add_child(scene)
	await process_frame
	await process_frame
	await ForceWin.play_opening(self, scene, "level 53 rope", _assert_true)
	var rope_record: Dictionary = {}
	for record in scene.opening_coordinator.story_records:
		if str(record.get("symbol", "")) == "obj_Story_Level53_Rope":
			rope_record = record
	_assert_true(rope_record.get("anchor_world") == Vector2(656, 464), "level 53: the rope stands on the raw script pixel (%s)" % str(rope_record.get("anchor_world")))
	_assert_true(rope_record.get("presentation") == "range_unroll" and rope_record.get("hang_top_world") == Vector2(655, 464), "level 53: the rope hangs down from the balcony edge (%s)" % str(rope_record))
	_assert_true(is_equal_approx(float(rope_record.get("unroll_seconds", 0.0)), OriginalTick.seconds(80)), "level 53: the rope unrolls over the 80-tick actDelay")
	var sprite: Sprite2D = scene.world_root.get_node_or_null("StoryObject_obj_Story_Level53_Rope")
	_assert_true(sprite != null and sprite.region_rect.size.y > 200.0 and sprite.position.y + sprite.region_rect.size.y > 700.0, "level 53: the unrolled rope reaches the ground 緹娜 slides to (%s)" % (str(sprite.region_rect) if sprite != null else "missing"))
	scene.queue_free()
	await process_frame
	await process_frame
