extends SceneTree
## Normal runtime control events: receive damage, earn ST, equip, and use Qi Blade.
const Loop = preload("res://game/sim/loop/BattlePlayLoop.gd")
const Rules = preload("res://game/sim/StaminaRules.gd")
const BattleFixture = preload("res://tests/support/BattleFixture.gd")
const OUT := "res://ignored/stamina-review/"
var scene: Node
var failures: Array[String] = []
var routes: Array = []
var mode := ""


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Stamina review requires a rendered window")
		quit(2)
		return
	root.title = "HSL Stamina Review"
	root.size = Vector2i(640, 480)
	create_timer(150.0).timeout.connect(func(): push_error("Stamina review timed out"); quit(2))
	DirAccess.make_dir_recursive_absolute(OUT)
	var names := ["ordinary"] if OS.get_cmdline_user_args().has("ordinary") else ["ordinary", "equipment"]
	for name in names:
		mode = name
		await route(name == "equipment")
		if is_instance_valid(scene):
			scene.queue_free()
			await process_frame
			await create_timer(0.3).timeout
		if not failures.is_empty(): break
	FileAccess.open(OUT + "receipt.json", FileAccess.WRITE).store_string(JSON.stringify({
		"schema": "hsl_stamina_control_review.v1", "fixture": true, "original_game_execution": false,
		"input": "Actual viewport mouse motion/press/release; normal Runtime AI, combat and clocks",
		"overrides": "Three-actor roster, initial queue speeds110/3/2 with equipment refresh retaining its real speed changes; ally control, hostile024 archer same level as Leonard with hit200 and low attack8; initial ST14 or8, enemy HP500, legal source-range placements, empty AI calls and no reinforcement templates. Equipment route adds actual225/169 to inventory. No RNG replacement, direct damage/ST changes after setup, or action/result calls.",
		"window_screen": root.current_screen, "window_position": root.position, "routes": routes,
		"failures": failures}, "  "))
	print("STAMINA_RENDER_REVIEW_", "PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)


func route(with_equipment: bool) -> void:
	scene = load("res://game/battle/scene/BattleSceneRuntime.tscn").instantiate()
	scene.scenario_path = BattleFixture.PATH; scene.startup_mode = "dev_first_control"
	root.add_child(scene)
	current_scene = scene
	scene.start_dev_first_control_harness()
	scene.set_process(false)
	scene.get_node("BattleMusic").stop()
	var loop: Dictionary = scene.play_loop
	var player := Loop._unit(loop, "leonard")
	var enemy := Loop._unit(loop, "enemy024_1")
	var ally := Loop._unit(loop, "enemy021_1")
	loop["units"] = [player, enemy, ally]
	loop["reinforcement_templates"] = []
	player["live_speed"] = 110
	player["stamina"] = 8 if with_equipment else 14
	if with_equipment: player["inventory"] = [225, 169, 0, 0, 0, 0, 0, 0]
	enemy["live_speed"] = 2
	enemy["battle_actor_role"] = Loop.ROLE_ENEMY
	enemy["level"] = player["level"]
	enemy["hp"] = 500
	enemy["max_hp"] = 500
	enemy["combat_profile"]["live_hit_ratio"] = 200
	enemy["combat_profile"]["live_attack_damage"] = 8
	enemy["combat_profile"]["attack_back"] = 0
	ally["live_speed"] = 3
	ally["player_commandable"] = true
	ally["battle_actor_role"] = Loop.ROLE_PLAYER
	ally["coord"] = Vector2i(2, 2)
	var placed := false
	for point in Loop.movement_cells(loop, "leonard"):
		var delta: Vector2i = point - player["coord"]
		if absi(delta.x) + absi(delta.y) != 2 or (delta.x != 0 and delta.y != 0): continue
		enemy["coord"] = point
		if Loop.attack_cells(loop, enemy["id"]).has(player["coord"]) and not Loop.attack_cells(loop, "leonard").has(point):
			placed = true
			break
	check(placed, "archer can attack from a legal cell outside physical counter range")
	if not placed: return
	for unit in loop["units"]:
		unit["grid_coord"] = unit["coord"]
		unit["ai_call_target_id"] = ""
	loop["turn_queue"] = Loop.CoreTurnQueue.rebuild(loop["units"])
	scene.apply_loop(Loop._return_to_player(loop, "leonard"), "test")
	for child in scene.actors_root.get_children():
		scene.actors_root.remove_child(child)
		child.queue_free()
	scene.apply_loop(scene.play_loop, "test")
	scene.interaction_state = scene.play_loop["interaction"]
	scene.menus.rebuild_action_menu_buttons()
	scene.center_camera_on_grid(player["coord"])
	scene._process(0.0)
	scene.set_process(true)
	await create_timer(0.35).timeout
	check(not scene.action_menu.get_node("SpecialCommand").disabled and not Loop.can_use_special(scene.play_loop, "leonard"), "below20 still opens the skill page but cannot pay the earned ability")
	await shot("before")
	var record := {"mode": mode, "initial_st": player["stamina"], "initial_positions": [player["coord"], enemy["coord"]]}
	if with_equipment:
		await open_equipment()
		await click(item_button(225))
		await click(find_button(scene.item_panel.page_root, "飾品 1"))
		check(panel_text().contains("正常 → 加倍"), "ring preview explains its actual passive effect")
		await shot("ring-preview")
		var before: Dictionary = scene.play_loop.duplicate(true)
		await click(find_button(scene.item_panel.page_root, "取消"))
		check(scene.play_loop == before, "cancelled passive preview has no gameplay effect")
		await click(item_button(225))
		await click(find_button(scene.item_panel.page_root, "飾品 1"))
		await click(scene.item_panel.confirm_button)
		check(Rules.effects(Loop.unit(scene.play_loop, "leonard"), scene.play_loop["equipment_items"])["flags"] == Rules.DOUBLE, "actual confirm equips the source ring")
		await open_equipment()
		await click(item_button(169))
		check(panel_text().contains("加倍 → 停止"), "mask preview explains override of doubling")
		await shot("mask-preview")
		await click(scene.item_panel.confirm_button)
		await enemy_cycle()
		if not failures.is_empty(): return
		check(Loop.unit(scene.play_loop, "leonard")["stamina"] == 8 and not Loop.can_use_special(scene.play_loop, "leonard"), "real masked damage does not fill stamina or enable the skill")
		record["blocked_attack"] = scene.play_loop["last_ai_action"].duplicate(true)
		await shot("blocked")
		await open_equipment()
		await click(scene.item_panel.equipment_view.slot_controls["head"])
		check(panel_text().contains("停止 → 加倍"), "real unequip preview restores the ring effect")
		await click(scene.item_panel.confirm_button)
	await enemy_cycle()
	if not failures.is_empty(): return
	var earned: Dictionary = scene.play_loop["last_ai_action"].duplicate(true)
	if not earned.has("stamina_gain"):
		print("STAMINA_REVIEW_ACTION ", JSON.stringify(earned))
		print("STAMINA_REVIEW_ACTORS ", JSON.stringify(scene.play_loop["units"].map(func(unit): return {"id": unit["id"], "hp": unit["hp"], "stamina": unit["stamina"], "level": unit["level"], "coord": unit["coord"]})))
	check(Loop.unit(scene.play_loop, "leonard")["stamina"] == 20 and Loop.can_use_special(scene.play_loop, "leonard"), "actual damage crosses the exact skill threshold")
	check(earned.has("stamina_gain"), "real ordinary hit emits its stamina receipt")
	if not earned.has("stamina_gain"): return
	check(earned["stamina_gain"]["defender"]["delta"] == (12 if with_equipment else 6), "same ordinary receiving role uses source gain or equipment double")
	record["earned_attack"] = earned
	await shot("ready")
	await click(scene.action_menu.get_node("StatusCommand"))
	check(scene.status_panel.visible and scene.status_panel.vitals.st_bar.lit_segments() == 1 and scene.status_panel.vitals.st_bar.lit_width() == 58, "actual status view lights the first ST segment at 20 (0x4368c0)")
	await shot("status20")
	await click_point(Vector2(320, 240), MOUSE_BUTTON_RIGHT)
	await create_timer(0.3).timeout
	var before_special: Dictionary = scene.play_loop.duplicate(true)
	await click(scene.action_menu.get_node("SpecialCommand"))
	if scene.play_loop["interaction"] == "special_select": await click(scene.magic_panel.choices["special:magicOTHER:magicCode01"])
	check(scene.interaction_state == "attack_select", "earned command enters actual targeting")
	await click_point(Vector2(320, 240), MOUSE_BUTTON_RIGHT)
	check(scene.play_loop["units"] == before_special["units"] and scene.play_loop["turn_queue"] == before_special["turn_queue"], "target cancel preserves earned resources and initiative")
	await create_timer(0.3).timeout
	await click(scene.action_menu.get_node("SpecialCommand"))
	if scene.play_loop["interaction"] == "special_select": await click(scene.magic_panel.choices["special:magicOTHER:magicCode01"])
	await click_point(scene.grid_cell_center_to_logical_position(Loop.unit(scene.play_loop, "enemy024_1")["coord"]))
	check(Loop.unit(scene.play_loop, "leonard")["stamina"] == 0, "actual target confirmation pays20 once")
	var presented := false
	for _tick in range(450):
		await create_timer(0.04).timeout
		var cutin = scene.get_node("BattlePresentation").cutin
		if cutin.busy() and cutin.elapsed > 0.8 and not presented:
			presented = true
			await shot("special")
		if scene.selected_unit_id == "enemy021_1" and scene.interaction_state == "action_menu" and not cutin.busy() and not scene.ai_playback_active: break
	check(presented and scene.selected_unit_id == "enemy021_1" and scene.action_menu.is_visible_in_tree(), "special effect completes into next player's actual menu")
	check(Loop.unit(scene.play_loop, "leonard")["stamina"] == 0 and scene.play_loop["turn_queue"]["index"] == 1, "no skill refund and exactly one handoff")
	record["special"] = scene.play_loop["last_combat"].duplicate(true)
	record["final_st"] = Loop.unit(scene.play_loop, "leonard")["stamina"]
	record["next_actor"] = scene.selected_unit_id
	await shot("handoff")
	routes.append(record)


func enemy_cycle() -> void:
	await create_timer(0.3).timeout
	await click(scene.action_menu.get_node("WaitCommand"))
	check(scene.selected_unit_id == "enemy021_1", "actual player Wait hands to friendly actor")
	await create_timer(0.3).timeout
	await click(scene.action_menu.get_node("WaitCommand"))
	var seen_before := false
	var seen_after := false
	for _tick in range(450):
		await create_timer(0.04).timeout
		var cutin = scene.get_node("BattlePresentation").cutin
		if cutin.busy() and not cutin.clips[0]["strike"].has("magic_key"):
			var clip: Dictionary = cutin.clips[0]
			if clip["strike"].has("stamina_gain") and cutin.defender_sprite.visible:
				var impacted: bool = clip["impact_emitted"]
				check(cutin.vitals.st_bar.value == clip["strike"]["stamina_gain"]["defender"]["after" if impacted else "before"], "visible receiver stamina follows this hit's actual impact")
				if not impacted and not seen_before:
					seen_before = true
					await shot("hit-before")
				elif impacted and not seen_after:
					seen_after = true
					await shot("hit-after")
		if scene.selected_unit_id == "leonard" and scene.interaction_state == "action_menu" and not scene.ai_playback_active and not scene.get_node("BattlePresentation").combat_busy(scene.play_loop): break
	await create_timer(0.3).timeout
	check(seen_before and seen_after, "normal playback has distinct pre-hit and post-hit resource views")
	check(scene.selected_unit_id == "leonard" and scene.play_loop["last_ai_actions"].size() == 1, "one normal AI strike reaches next-round player control")


func open_equipment() -> void:
	await create_timer(0.3).timeout
	await click(scene.action_menu.get_node("ItemCommand"))
	await create_timer(0.3).timeout
	await click(scene.item_panel.menu.get_node("EquipCommand"))


func item_button(code: int) -> Control:
	for child in scene.item_panel.rows.get_children():
		if child.get_meta("item_code", "") == str(code): return child
	check(false, "source item row exists")
	return null


func find_button(node: Node, caption: String) -> Control:
	if node is Button and node.text == caption: return node
	for child in node.get_children():
		var found := find_button(child, caption)
		if found != null: return found
	return null


func panel_text() -> String:
	var text := ""
	for child in scene.item_panel.page_root.find_children("*", "Label", true, false):
		if child is Label: text += child.text + "\n"
	return text


func click(control: Control) -> void:
	check(control != null and control.is_visible_in_tree(), "real control available")
	if control == null: return
	await click_point(control.get_global_rect().get_center())


func click_point(point: Vector2, button: int = MOUSE_BUTTON_LEFT) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = point
	root.push_input(motion, true)
	var event := InputEventMouseButton.new()
	event.position = point
	event.button_index = button
	event.pressed = true
	root.push_input(event, true)
	event = event.duplicate()
	event.pressed = false
	root.push_input(event, true)
	await create_timer(0.2).timeout


func shot(name: String) -> void:
	await process_frame
	RenderingServer.force_draw(false)
	check(root.get_texture().get_image().save_png(OUT + mode + "-" + name + ".png") == OK, "render capture")


func check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(mode + ": " + label)
		push_error(mode + ": " + label)
