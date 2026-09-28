extends SceneTree
const BattleOutcome = preload("res://game/sim/BattleOutcome.gd")
const ScriptActorPresentation = preload("res://game/battle/scene/BattleScriptActorPresentation.gd")
## Rendered acceptance driver. Normal clocks, real scene commands and input events;
## never writes HP, inventory, coordinates, EXP, RNG, turn, or outcome.
## godot --path . --script res://tests/run_first_battle_playthrough.gd -- hold
var policy := "hold"
var report := {"opening": [], "dialogue": [], "actions": [], "outcome": "", "restart": false, "time_scale": 1.0}
var output := ""
var scene: Node
var failed := false
var visual_samples: Dictionary = {}
var captured_views: Dictionary = {}
var mouse_entered := false


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		policy = args[0]
	if policy not in ["hold", "advance"]:
		push_error("Playthrough policy must be hold or advance")
		quit(2)
		return
	output = "res://ignored/first-battle-playthrough/" + policy
	report["policy"] = policy
	DirAccess.make_dir_recursive_absolute(output)
	create_timer(600.0).timeout.connect(func():
		push_error("FIRST_BATTLE_PLAYTHROUGH_TIMEOUT policy=" + policy)
		_store()
		quit(2))
	root.size = Vector2i(640, 480)
	if not _require(Engine.time_scale == 1.0, "normal-speed acceptance must not accelerate clocks"):
		return
	# Select an untouched first battle without deleting the user's campaign save
	# or accepting a concurrent worktree's resume destination.
	preload("res://game/common/CampaignProgress.gd").pending = {"scenario_path":"res://content/battles/battle_051.json","carry":{}}
	# The finished battle would fade out and leave by itself; this route inspects it and
	# then checks that a reload re-enters the same battle with the same party.
	preload("res://game/battle/scene/BattleSceneRuntime.gd").hold_finished_battle = true
	scene = load("res://game/battle/scene/BattleSceneRuntime.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	await process_frame
	var started := Time.get_ticks_msec()
	var presentation = scene.get_node("BattlePresentation")
	while true:
		await create_timer(0.02).timeout
		if failed:
			return
		await _sample_presentation()
		for unit in scene.play_loop["units"]:
			if scene.BattlePlayLoop.Presence.living(unit):
				# A script-inserted unit is on the map only once its winfail token has fired on the
				# presentation side (the original creates the object when the token executes).
				if ScriptActorPresentation.defer_spawn(scene, unit):
					continue
				var actor = scene.actor_node_for_unit(str(unit["id"]))
				if not _require(actor != null and actor.visible, "living unit vanished: " + str(unit["id"])):
					return
		if presentation.attack_cue.visible:
			await _capture_once("map-" + presentation.attack_cue.stage())
		if presentation.cutin.busy() and presentation.cutin.attacker_sprite.texture != null:
			await _capture_once("attacker-shot" if presentation.cutin.attacker_sprite.visible else "defender-shot")
		if presentation.cutin.busy() or presentation.has_pending_combat(scene.play_loop) or scene.has_actor_motion():
			continue
		if scene.opening_coordinator != null and scene.opening_coordinator.active:
			var opening: Dictionary = scene.opening_coordinator.summary()
			if str(opening.get("current_event_kind", "")) == "dialogue_message_id":
				var message_id := str(scene.scene_timeline.current_event().get("message_id", ""))
				report["dialogue" if bool(opening.get("cutscene_mode", false)) else "opening"].append(message_id)
				await _confirm_when_settled()
			continue
		if presentation.dialogue_active():
			report["dialogue"].append(presentation.current_message_id())
			await _confirm_when_settled()
			continue
		var loot = scene.settlement_controller.panel
		if loot.visible:
			await _capture_once("loot")
			var bag: Array = scene.BattlePlayLoop.unit(scene.play_loop, "leonard")["inventory"]
			if loot.rows.is_empty() or not bag.has(0):
				await _click(loot.finish_button)
			else:
				await _click(loot.rows[0])
				await _click(loot.slots[bag.find(0)])
			continue
		if presentation.battle_finished:
			report["outcome"] = scene.play_loop["battle_outcome"]
			report["turn"] = scene.play_loop["turn"]
			report["player"] = scene.BattlePlayLoop.unit(scene.play_loop, "leonard")
			break
		if scene.growth_panel.visible:
			var available := int(scene.growth_panel.source_unit["pending_stat_points"])
			for i in range(available):
				await _click(scene.growth_panel.choices[["str", "dex", "mind", "con"][i % 4]]["plus"])
			await _snapshot("growth-preview")
			await _click(scene.growth_panel.confirm_button)
			_record("allocate_growth", {"points": available})
			continue
		if scene.interaction_state != "action_menu" or scene.ai_playback_active or not scene.action_menu.is_visible_in_tree():
			continue
		var player: Dictionary = scene.BattlePlayLoop.unit(scene.play_loop, "leonard")
		if not captured_views.has("status"):
			await _command("status")
			await _capture_once("status")
			await _key(KEY_ESCAPE)
			continue
		if policy == "advance" and scene.play_loop["objective_phase"] == "hold" and not scene.play_loop["attacked_this_action"]:
			var ability := "special" if scene.BattlePlayLoop.can_use_special(scene.play_loop, "leonard") else "attack"
			await _command(ability)
			var target := ""
			for foe in scene.play_loop["units"]:
				if foe["battle_actor_role"] == "enemy_ai" and scene.BattlePlayLoop.Presence.living(foe) and scene.attack_overlay_cells.has(foe["coord"]):
					target = str(foe["id"])
					break
			if target != "":
				var foe: Dictionary = scene.BattlePlayLoop.unit(scene.play_loop, target)
				await _click_point(scene.grid_cell_center_to_logical_position(foe["coord"]))
				_record(ability, {"target": target})
				continue
			await _key(KEY_ESCAPE)
			if not scene.play_loop["moved_this_action"]:
				var best: Vector2i = player["coord"]
				var distance := 10000
				for cell in scene.BattlePlayLoop.movement_cells(scene.play_loop, "leonard"):
					for foe in scene.play_loop["units"]:
						if foe["battle_actor_role"] == "enemy_ai" and scene.BattlePlayLoop.Presence.living(foe):
							var candidate := absi(cell.x - foe["coord"].x) + absi(cell.y - foe["coord"].y)
							if candidate < distance:
								best = cell
								distance = candidate
				if best != player["coord"]:
					await _move(best)
					continue
		if scene.play_loop["pending_move"]:
			await _command("wait")
			_record("commit_move")
			continue
		if not scene.play_loop["attacked_this_action"] and int(player["hp"]) <= int(player["max_hp"]) / 2 and player["inventory"].has(241):
			await _command("item")
			await create_timer(0.25).timeout
			await _click(scene.item_panel.menu.get_node("UseCommand"))
			if not _require(scene.item_panel.page == "inventory", "Use input must open inventory"):
				break
			for button in scene.item_panel.rows.get_children():
				if button.get_meta("item_code", "") == "241" and not button.disabled:
					await _click(button)
					await _click(scene.item_panel.target_buttons["leonard"])
					_record("recovery_item")
					break
			continue
		if scene.play_loop["objective_phase"] == "escape":
			# Long-range COPY is only a direction planner. Every committed destination
			# is taken from the real unit's legal movement envelope.
			var mover: Dictionary = player.duplicate(true)
			var gate: Vector2i = scene.play_loop["escape_zone"][0]
			var reach: Dictionary = scene.BattlePlayLoop.TacticalGridRules.movement_reachability_envelope(mover, scene.play_loop["units"], scene.play_loop["tiles"], scene.play_loop["map_size"], 1000)
			var path: Array = reach["reachable_by_coord"].get(gate, {}).get("path", [])
			var legal: Array = scene.BattlePlayLoop.movement_cells(scene.play_loop, "leonard")
			var moved := false
			for index in range(path.size() - 1, -1, -1):
				if legal.has(path[index]):
					await _move(path[index])
					moved = true
					break
			if moved:
				continue
		await _command("wait")
		_record("wait")
	report["elapsed_seconds"] = (Time.get_ticks_msec() - started) / 1000.0
	await _snapshot("result")
	reload_current_scene()
	await process_frame
	await process_frame
	var fresh: Dictionary = current_scene.BattlePlayLoop.unit(current_scene.play_loop, "leonard")
	report["restart"] = current_scene != scene and fresh["hp"] == 30 and fresh["inventory"] == [241, 241, 241, 246, 0, 0, 0, 0] and fresh["stamina"] == 20 and fresh["pending_stat_points"] == 0 and not BattleOutcome.decided(current_scene.play_loop)
	report["policy"] = policy
	_store()
	var passed: bool = not failed and report["opening"] == ["363", "364", "365", "366", "367", "364", "1101"] and report["restart"] and report["outcome"] in [BattleOutcome.VICTORY_ESCAPE, BattleOutcome.VICTORY_ENEMIES_CLEARED, BattleOutcome.DEFEAT_FALLEN]
	if policy == "hold":
		passed = passed and report["outcome"] in [BattleOutcome.VICTORY_ESCAPE, BattleOutcome.VICTORY_ENEMIES_CLEARED]
	print("FIRST_BATTLE_PLAYTHROUGH_", "PASS" if passed else "FAIL", " policy=", policy, " outcome=", report["outcome"], " turn=", report["turn"], " seconds=", report["elapsed_seconds"], " restart=", report["restart"])
	current_scene.queue_free()
	await process_frame
	await create_timer(0.4).timeout
	quit(0 if passed else 1)


func _capture_once(name: String) -> void:
	if captured_views.has(name):
		return
	captured_views[name] = true
	report["captured_views"] = captured_views.keys()
	await _snapshot(name)


func _command(name: String) -> void:
	# Wait for layout/input to settle after scene/queue transitions, without
	# accelerating any animation. process_frame is emitted before node processing.
	await create_timer(0.25).timeout
	var button = scene.action_menu.get_node_or_null(name.capitalize() + "Command")
	if not _require(button != null and button.is_visible_in_tree() and not button.disabled, "route requested an unavailable command: " + name):
		return
	var before: Dictionary = scene.play_loop.duplicate(true)
	await _click(button)
	await create_timer(0.08).timeout
	var expected := {"move": "move_select", "attack": "attack_select", "special": "attack_select"}
	if expected.has(name):
		_require(scene.interaction_state == expected[name], "command was not accepted: %s state=%s" % [name, scene.interaction_state])
	elif name == "wait":
		_require(scene.play_loop != before, "Wait input did not commit the actor action")
	elif name == "item":
		_require(scene.item_panel.visible, "Item input did not open inventory")


func _move(cell: Vector2i) -> void:
	await _command("move")
	if failed:
		return
	var point: Vector2 = scene.grid_cell_center_to_logical_position(cell)
	if not _require(Rect2(Vector2.ZERO, Vector2(640, 480)).has_point(point), "route attempted an offscreen click: %s screen=%s camera=%s" % [cell, point, scene.camera.position]):
		return
	await _click_point(point)
	await create_timer(0.08).timeout
	var actual: Vector2i = scene.BattlePlayLoop.unit(scene.play_loop, "leonard")["coord"]
	if not _require(actual == cell, "movement input was not accepted: target=%s actual=%s point=%s interaction=%s" % [cell, actual, point, scene.interaction_state]):
		return
	_record("move", {"cell": [cell.x, cell.y]})


func _click(button: Control) -> void:
	await _click_point(button.get_global_rect().get_center())


func _click_point(point: Vector2) -> void:
	if not mouse_entered:
		root.notify_mouse_entered()
		mouse_entered = true
	var motion := InputEventMouseMotion.new()
	motion.position = point
	root.push_input(motion, true)
	await process_frame
	var event := InputEventMouseButton.new()
	event.position = point
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	root.push_input(event, true)
	await process_frame
	event = event.duplicate()
	event.pressed = false
	root.push_input(event, true)
	await process_frame


func _key(code: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.pressed = true
	Input.parse_input_event(event)
	await process_frame
	event = event.duplicate()
	event.pressed = false
	Input.parse_input_event(event)
	await process_frame


func _record(action: String, details: Dictionary = {}) -> void:
	var player: Dictionary = scene.BattlePlayLoop.unit(scene.play_loop, "leonard")
	var entry := {"action": action, "turn": scene.play_loop["turn"], "hp": player["hp"], "stamina": player["stamina"], "exp": player["exp"], "level": player["level"]}
	entry.merge(details)
	report["actions"].append(entry)
	print("PLAYTHROUGH_ACTION ", policy, " ", entry)


func _snapshot(name: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await process_frame
	RenderingServer.force_draw(false)
	_require(root.get_texture().get_image().save_png(output + "/" + name + ".png") == OK, "failed to write rendered screenshot")


func _store() -> void:
	report["visual_samples"] = visual_samples
	FileAccess.open(output + "/receipt.json", FileAccess.WRITE).store_string(JSON.stringify(report, "  "))


func _sample_presentation() -> void:
	if DisplayServer.get_name() == "headless":
		return
	var presentation = scene.get_node("BattlePresentation")
	var name := ""
	if presentation.attack_cue.visible:
		name = "live-cue-" + presentation.attack_cue.stage()
	elif presentation.cutin.busy():
		var clip: Dictionary = presentation.cutin.clips[0]
		if clip["strike"].has("magic_key") and clip["impact_emitted"]:
			name = "live-magic-" + str(clip["strike"]["magic_key"])
		elif not clip["strike"].has("magic_key"):
			name = "live-hurt" if clip["impact_emitted"] else "live-windup"
	if name != "" and not visual_samples.has(name):
		visual_samples[name] = {"turn": scene.play_loop["turn"], "sequence": scene.play_loop.get("last_combat", {}).get("sequence", 0)}
		await _snapshot(name)


func _require(condition: bool, message: String) -> bool:
	if not condition:
		failed = true
		report["error"] = message
		_store()
		push_error("FIRST_BATTLE_PLAYTHROUGH_FAIL " + message)
		quit(1)
	return condition


## The dialogue board reads confirm only once its wipe or scroll has settled (0x414280 state 2);
## press Space the way a player does — after the marker — instead of during the wipe.
func _confirm_when_settled() -> void:
	var presentation = scene.get_node("BattlePresentation")
	for _i in range(400):
		var holding := false
		if scene.opening_overlay != null and scene.opening_overlay.has_method("holds_confirm"):
			holding = holding or scene.opening_overlay.holds_confirm()
		if presentation.dialogue_view != null and presentation.dialogue_view.has_method("holds_confirm"):
			holding = holding or presentation.dialogue_view.holds_confirm()
		if not holding:
			break
		await process_frame
	await _key(KEY_SPACE)
