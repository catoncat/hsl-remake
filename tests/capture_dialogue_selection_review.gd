extends SceneTree
const BattleFixture = preload("res://tests/support/BattleFixture.gd")
## Normal-clock input review; synthetic resources/positions only in selection cases.
const OUT := "res://ignored/dialogue-selection-review/"
var scene: Node
var view: Node
var failures: Array[String] = []
var records: Array = []
var mouse_entered := false


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Dialogue/selection review requires a rendering window")
		quit(2)
		return
	root.title = "HSL Dialogue Selection Review"
	root.size = Vector2i(640, 480)
	create_timer(90).timeout.connect(func(): push_error("Dialogue/selection review timed out"); quit(2))
	DirAccess.make_dir_recursive_absolute(OUT)
	scene = load("res://game/battle/scene/BattleSceneRuntime.tscn").instantiate()
	scene.scenario_path = BattleFixture.PATH; scene.startup_mode = "dev_first_control"
	root.add_child(scene)
	current_scene = scene
	view = scene.get_node("BattlePresentation")
	# The fixture has no opening since S5 (ded491cc): dev_first_control starts at first control.
	# The level-51 product opening (seven confirmations to first control) is covered headless by
	# run_battle_scene_runtime_tests.gd _test_first_battle_opening_through_coordinator.
	await process_frame
	while scene.ai_playback_active or scene.has_actor_motion() or view.cutin.busy() or view.has_pending_combat(scene.play_loop):
		await process_frame
	check(not view.dialogue_active(), "fixture starts at first control with no opening dialogue")
	await shot("first-control")
	records.append({"case": "fixture_first_control", "interaction": scene.interaction_state, "time_scale": Engine.time_scale})
	await command("status")
	var player: Dictionary = scene.BattlePlayLoop.unit(scene.play_loop, "leonard")
	check(scene.status_panel.stat_values["magic"].text == "%d%%" % int(player["combat_profile"]["live_magic_attack"]), "visible status uses the live percentage without scaling")
	await shot("status")
	await key(KEY_ESCAPE)
	# Controlled selection setup: grant 20 ST and put one enemy adjacent.
	player = scene.BattlePlayLoop.unit_ref(scene.play_loop, "leonard")
	player["stamina"] = 20
	var enemy: Dictionary = scene.BattlePlayLoop.unit_ref(scene.play_loop, "enemy021_1")
	enemy["coord"] = player["coord"] + Vector2i.RIGHT
	scene.apply_loop(scene.play_loop, "test")
	scene.select_actor("leonard") # Refresh derived command availability after the fixture grant.
	await command("special")
	await page_choice("special:magicOTHER:magicCode01")
	var before: Dictionary = scene.play_loop.duplicate(true)
	for coord in scene.BattlePlayLoop.attack_cells(scene.play_loop):
		if scene.scene_input.unit_id_at_grid(coord) == "":
			await motion(scene.grid_cell_center_to_logical_position(coord))
			check(view.selection_cursor.caption.text == "氣刃斬" and not view.target_vitals.visible, "empty target shows the skill name without stale unit data")
			await shot("special-empty")
			break
	await motion(scene.grid_cell_center_to_logical_position(enemy["coord"]))
	check(view.target_vitals.visible and not view.combat_label.visible, "special target shows the identity strip and no overhead hit line (UI6: 命中率 is on the skill page)")
	await shot("special-target")
	# Actual camera key input brings the target to the lower edge.
	await key_hold(KEY_UP, 0.5)
	await motion(scene.grid_cell_center_to_logical_position(enemy["coord"]))
	check(scene.grid_cell_center_to_logical_position(enemy["coord"]).y >= 300, "held camera key actually reaches a lower-screen target")
	check(view.target_vitals.visible and view.selection_cursor.visible and not view.target_vitals.get_global_rect().intersects(view.selection_cursor.cell_rect), "lower target remains visible beside relocated information")
	await shot("lower-target")
	check(scene.play_loop == before, "hover and camera movement never spend resources or an action")
	await key(KEY_ESCAPE)
	check(not view.selection_cursor.visible and not view.target_vitals.visible, "cancel removes all target feedback")
	await command("move")
	for coord in scene.BattlePlayLoop.movement_cells(scene.play_loop):
		if Rect2(24, 24, 592, 416).has_point(scene.grid_cell_center_to_logical_position(coord)):
			await motion(scene.grid_cell_center_to_logical_position(coord))
			check(view.selection_cursor.eligible, "move cursor agrees with the legal movement cells")
			await shot("move-selection")
			break
	await key(KEY_ESCAPE)
	# Source rally text through the same live modal, with no event or battle mutation.
	view._append_dialogue("0", "369")
	await process_frame
	before = scene.play_loop.duplicate(true)
	var page := 0
	while view.dialogue_active():
		var top_row: int = view.dialogue_view.top_row
		var rows: PackedStringArray = view.dialogue_view.window_rows()
		records.append({"case": "rally_page", "page": page, "top_row": top_row, "window_rows": Array(rows)})
		await shot("story-%d" % page)
		check(not view.selection_cursor.visible and not scene.action_menu.visible, "dialogue pauses map controls and selection")
		await key(KEY_SPACE)
		check(scene.play_loop == before, "page confirmation cannot advance a battle action")
		page += 1
	check(page > 1, "long rally is reviewed across all pages")
	await command("status")
	check(scene.status_panel.visible, "normal controls return after the final dialogue page")
	await key(KEY_ESCAPE)
	FileAccess.open(OUT + "receipt.json", FileAccess.WRITE).store_string(JSON.stringify({
		"normal_clock": Engine.time_scale, "input": "Viewport.push_input mouse and Input.parse_input_event keyboard through actual Control and Runtime handlers",
		"window_position": root.position, "window_size": root.size, "opening_is_product_path": false,
		"selection_fixture": "20 ST, one adjacent enemy; no attack/HP/queue overrides; camera uses KEY_UP",
		"story_fixture": "enqueue source message 369 after player control; normal modal and input, no event mutation",
		"records": records, "failures": failures}, "  "))
	scene.queue_free()
	await process_frame
	await create_timer(0.3).timeout
	print("DIALOGUE_SELECTION_REVIEW_", "PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)


func command(id: String) -> void:
	await create_timer(0.35).timeout
	var point: Vector2 = scene.scene_input.command_center_logical_position(id)
	check(scene.action_menu.is_visible_in_tree() and scene.scene_input.command_id_at_logical_position(point) == id, "visible command can be selected: " + id)
	await motion(point)
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


## The skill page row: hover writes the 0x436d70 description box, the click starts targeting.
func page_choice(id: String) -> void:
	var point: Vector2 = scene.magic_panel.choices[id].get_global_rect().get_center()
	await motion(point)
	await shot("special-page")
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


func motion(point: Vector2) -> void:
	if not mouse_entered:
		root.notify_mouse_entered()
		mouse_entered = true
	var event := InputEventMouseMotion.new()
	event.position = point
	root.push_input(event, true)
	await process_frame
	await process_frame


func key(code: Key) -> void:
	await key_hold(code, 0.05)


func key_hold(code: Key, seconds: float) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.pressed = true
	Input.parse_input_event(event)
	await create_timer(seconds).timeout
	event = event.duplicate()
	event.pressed = false
	Input.parse_input_event(event)
	await process_frame
	await process_frame


func shot(label: String) -> void:
	await create_timer(0.15).timeout
	if label in ["special-empty", "special-target", "lower-target", "move-selection"]:
		check(view.selection_cursor.is_visible_in_tree(), "cursor persists in captured frame: " + label)
	if label in ["special-target", "lower-target"]:
		check(view.target_vitals.is_visible_in_tree(), "unit information persists in captured frame: " + label)
	records.append({"capture": label, "interaction": scene.interaction_state,
		"pointer": scene.pointer_logical_position, "grid": scene.hovered_grid_cell, "hovered_unit": scene.hovered_unit_id,
		"cursor_visible": view.selection_cursor.visible, "vitals_visible": view.target_vitals.visible,
		"camera": scene.camera.position, "motion": scene.has_actor_motion()})
	RenderingServer.force_draw(false)
	check(root.get_texture().get_image().save_png(OUT + "after-" + label + ".png") == OK, "capture " + label)


func check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)
		push_error(label)
