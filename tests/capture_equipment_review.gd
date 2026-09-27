extends SceneTree
## Visible controls in a bounded synthetic inventory fixture. No original-game parity claim.
const OUT := "res://ignored/equipment-review/"
const BattlePlayLoop = preload("res://game/sim/loop/BattlePlayLoop.gd")
var scene: Node
var failures: Array[String] = []
var observations: Dictionary = {}


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Equipment review needs a rendering window on the built-in display")
		quit(2)
		return
	root.title = "HSL Equipment Review"
	root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(640, 480)
	DirAccess.make_dir_recursive_absolute(OUT)
	scene = load("res://game/battle/scene/BattleSceneRuntime.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	scene.start_dev_first_control_harness()
	scene.set_process(false)
	scene.get_node("BattleMusic").stop()
	if OS.get_cmdline_user_args().has("discard"):
		await discard_action_review()
		scene.queue_free()
		await process_frame
		await create_timer(0.3).timeout
		print("DISCARD_ACTION_RENDER_REVIEW_", "PASS" if failures.is_empty() else "FAIL")
		quit(0 if failures.is_empty() else 1)
		return
	if OS.get_cmdline_user_args().has("important"):
		await important_item_review()
		scene.queue_free()
		await process_frame
		await create_timer(0.3).timeout
		print("ITEM_RULES_RENDER_REVIEW_", "PASS" if failures.is_empty() else "FAIL")
		quit(0 if failures.is_empty() else 1)
		return
	var actor := BattlePlayLoop.unit_ref(scene.play_loop, "leonard")
	actor["inventory"] = [241, 3, 241, 246, 0, 0, 0, 0]
	actor["hp"] = 17
	scene.apply_loop(scene.play_loop, "test")
	var before: Dictionary = scene.play_loop.duplicate(true)
	await open_equipment()
	await shot("inventory-before")
	await click(scene.item_panel.rows.get_child(0))
	await shot("weapon-preview")
	check(scene.item_panel.page == "equip_confirm" and scene.play_loop == before, "preview only")
	await click(find_button(scene.item_panel.page_root, "取消"))
	check(scene.item_panel.page == "inventory" and scene.play_loop == before, "mouse cancellation preserves inventory and equipment")
	await click(scene.item_panel.rows.get_child(0))
	await click(scene.item_panel.confirm_button)
	var after := BattlePlayLoop.unit(scene.play_loop, "leonard")
	check(not scene.item_panel.visible and int(after["weapon_code"]) == 3, "mouse confirmation equips selected weapon")
	check(after["inventory"] == [241, 241, 246, 2, 0, 0, 0, 0], "old weapon returned")
	check(after["combat_profile"]["live_attack_damage"] == 59 and after["combat_profile"]["live_magic_attack"] == 22 and after["live_speed"] == 16 and after["hp"] == 17, "confirmed derived values")
	observations["weapon_swap"] = after
	scene.menus.choose_command("status")
	await shot("weapon-confirmed-status")
	scene.status_panel.hide()
	await open_equipment()
	await shot("inventory-after")
	await click(scene.item_panel.equipment_view.slot_controls["head"])
	await shot("helmet-remove-preview")
	await click(scene.item_panel.confirm_button)
	check(BattlePlayLoop.unit(scene.play_loop, "leonard")["combat_profile"]["live_defense"] == 37, "mouse helmet removal refreshes defense")
	await open_equipment()
	var helmet := find_item(153)
	await click(helmet)
	await click(scene.item_panel.confirm_button)
	check(BattlePlayLoop.unit(scene.play_loop, "leonard")["combat_profile"]["live_defense"] == 43, "mouse re-equipping restores defense")
	var accessory := 0
	for code in scene.play_loop["equipment_items"]:
		var item: Dictionary = scene.play_loop["equipment_items"][code]
		if int(item["type_code"]) == 6 and item["supported"] and (int(item["job_mask"]) & 1) != 0:
			accessory = int(code)
			break
	check(accessory > 0, "supported accessory fixture exists")
	if accessory > 0:
		BattlePlayLoop.unit_ref(scene.play_loop, "leonard")["inventory"] = [accessory, 241, 0, 0, 0, 0, 0, 0]
		await open_equipment()
		await click(find_item(accessory))
		await shot("accessory-slot-choice")
		await click(find_button(scene.item_panel.page_root, "飾品 2"))
		await click(scene.item_panel.confirm_button)
		var equipment: Array = BattlePlayLoop.unit(scene.play_loop, "leonard")["equipment"]
		check(BattlePlayLoop.EquipmentRules.equipped_code(equipment, "accessory2") == accessory and BattlePlayLoop.EquipmentRules.equipped_code(equipment, "accessory1") == 0, "mouse accessory choice affects only the selected slot")
		observations["accessory_fixture_code"] = accessory
	# Full-bag fixture must refuse a standalone unequip without losing the item.
	BattlePlayLoop.unit_ref(scene.play_loop, "leonard")["inventory"] = [241, 241, 241, 241, 241, 241, 241, 2]
	var full: Dictionary = scene.play_loop.duplicate(true)
	await open_equipment()
	await click(scene.item_panel.equipment_view.slot_controls["head"])
	await shot("full-backpack-refusal")
	check(scene.item_panel.confirm_button.disabled and scene.play_loop == full, "full bag disables confirmation without mutation")
	observations["full_bag_unchanged"] = scene.play_loop == full
	FileAccess.open(OUT + "receipt.json", FileAccess.WRITE).store_string(JSON.stringify({"fixture": true, "real_control_mouse_events": true, "input_delivery": "Viewport.push_input motion/press/release; no direct button signals or desktop input", "window_position": root.position, "window_size": root.size, "observations": observations, "failures": failures}, "  "))
	scene.queue_free()
	await process_frame
	await create_timer(0.3).timeout
	print("EQUIPMENT_RENDER_REVIEW_", "PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)


func open_equipment() -> void:
	scene.menus.choose_command("item")
	await create_timer(0.3).timeout
	await click(scene.item_panel.menu.get_node("EquipCommand"))


func important_item_review() -> void:
	root.title = "HSL Item Rules Review"
	var actor := BattlePlayLoop.unit_ref(scene.play_loop, "leonard")
	actor["inventory"] = [281, 241, 246, 0, 0, 0, 0, 0]
	scene.play_loop["pending_move"] = true
	scene.play_loop["pending_move_from"] = actor["coord"] - Vector2i.DOWN
	scene.play_loop["moved_this_action"] = true
	scene.apply_loop(scene.play_loop, "test")
	var before: Dictionary = scene.play_loop.duplicate(true)
	scene.menus.choose_command("item")
	await create_timer(0.3).timeout
	await click(scene.item_panel.menu.get_node("DropCommand"))
	check(find_item(281).disabled and not find_item(241).disabled, "important and ordinary items have distinct discard eligibility")
	await shot("important-item-protection")
	await click(find_item(281))
	check(scene.item_panel.page == "inventory" and scene.play_loop == before, "mouse cannot discard the protected source item")
	await click(find_item(241))
	await shot("ordinary-discard-confirmation")
	await click(find_button(scene.item_panel.page_root, "取消"))
	check(scene.play_loop == before and scene.item_panel.page == "inventory", "ordinary discard cancellation preserves pending movement and all items")
	await click(find_item(241))
	await click(scene.item_panel.confirm_button)
	check(BattlePlayLoop.unit(scene.play_loop, "leonard")["inventory"] == [281, 246, 0, 0, 0, 0, 0, 0], "mouse confirmation removes only the ordinary item")
	check(not scene.item_panel.visible and scene.play_loop["pending_move"] and not scene.ai_playback_active and scene.play_loop["turn_queue"] == before["turn_queue"], "ordinary discard preserves player control and pending movement")
	var receipt := {"fixture": true, "real_control_mouse_events": true, "input_delivery": "Viewport.push_input; no desktop input or direct button signal", "window_position": root.position, "window_size": root.size, "initial_inventory": before["units"].filter(func(unit): return unit["id"] == "leonard")[0]["inventory"], "final_inventory": BattlePlayLoop.unit(scene.play_loop, "leonard")["inventory"], "failures": failures}
	FileAccess.open(OUT + "important-receipt.json", FileAccess.WRITE).store_string(JSON.stringify(receipt, "  "))


func discard_action_review() -> void:
	root.title = "HSL Discard Action Review"
	var actor := BattlePlayLoop.unit_ref(scene.play_loop, "leonard")
	actor["inventory"] = [281, 241, 241, 246, 0, 0, 0, 0]
	actor["hp"] = 17
	var origin: Vector2i = actor["coord"]
	var before: Dictionary = scene.play_loop.duplicate(true)
	scene.set_process(true)
	await create_timer(0.3).timeout
	await open_discard()
	check(find_item(281).disabled, "important item remains protected")
	await click(find_item(241))
	await click(find_button(scene.item_panel.page_root, "取消"))
	check(scene.play_loop == before, "discard preview cancellation changes no battle state")
	await click(find_item(241))
	await click(scene.item_panel.confirm_button)
	check(BattlePlayLoop.unit(scene.play_loop, "leonard")["inventory"] == [281, 241, 246, 0, 0, 0, 0, 0], "one duplicate removed")
	check(scene.play_loop["turn_queue"] == before["turn_queue"] and not scene.ai_playback_active, "no action handoff after discard")
	await create_timer(0.3).timeout
	await shot("discard-action-menu")
	await click(scene.action_menu.get_node("MoveCommand"))
	check(scene.interaction_state == "move_select", "mouse Move works after discard")
	await shot("discard-move-select")
	var neighbors: Array = BattlePlayLoop.movement_cells(scene.play_loop, "leonard").filter(func(cell): return absi(cell.x - origin.x) + absi(cell.y - origin.y) == 1)
	check(not neighbors.is_empty(), "fixture has a legal neighboring cell")
	if neighbors.is_empty():
		return
	var destination: Vector2i = neighbors[0]
	var point: Vector2 = scene.grid_cell_center_to_logical_position(destination)
	check(Rect2(0, 0, 640, 480).has_point(point), "movement cell is visible")
	await click_point(point)
	await create_timer(0.6).timeout
	check(BattlePlayLoop.unit(scene.play_loop, "leonard")["coord"] == destination and scene.play_loop["pending_move"], "mouse move reaches selected cell")
	await open_discard()
	await click(find_item(241))
	await click(scene.item_panel.confirm_button)
	check(scene.play_loop["pending_move"] and scene.play_loop["turn_queue"] == before["turn_queue"], "second discard preserves the pending move and queue")
	await click_point(point, MOUSE_BUTTON_RIGHT)
	check(BattlePlayLoop.unit(scene.play_loop, "leonard")["coord"] == origin and not scene.play_loop["pending_move"], "right click still cancels the move")
	check(BattlePlayLoop.unit(scene.play_loop, "leonard")["inventory"] == [281, 246, 0, 0, 0, 0, 0, 0], "movement cancellation does not restore discarded items")
	check(scene.interaction_state == "move_select", "movement cancellation reopens the original movement selection")
	await click_point(point, MOUSE_BUTTON_RIGHT)
	await create_timer(0.3).timeout
	await click(scene.action_menu.get_node("AttackCommand"))
	check(scene.interaction_state == "attack_select", "mouse Attack remains available")
	await click_point(point, MOUSE_BUTTON_RIGHT)
	await open_discard()
	await shot("discard-inventory-after")
	var receipt := {"fixture": true, "input_delivery": "Viewport.push_input motion/press/release; no desktop input or direct button signals", "window_position": root.position, "window_size": root.size, "initial_inventory": [281, 241, 241, 246, 0, 0, 0, 0], "final_inventory": BattlePlayLoop.unit(scene.play_loop, "leonard")["inventory"], "queue_unchanged": scene.play_loop["turn_queue"] == before["turn_queue"], "move_origin": [origin.x, origin.y], "move_destination": [destination.x, destination.y], "move_cancelled": not scene.play_loop["pending_move"], "ai_playback_active": scene.ai_playback_active, "failures": failures}
	FileAccess.open(OUT + "discard-receipt.json", FileAccess.WRITE).store_string(JSON.stringify(receipt, "  "))


func open_discard() -> void:
	await create_timer(0.3).timeout
	await click(scene.action_menu.get_node("ItemCommand"))
	await create_timer(0.3).timeout
	await click(scene.item_panel.menu.get_node("DropCommand"))


func find_item(code: int) -> Control:
	for child in scene.item_panel.rows.get_children():
		if child is Button and int(child.get_meta("item_code", 0)) == code:
			return child
	check(false, "missing visible item " + str(code))
	return null


func find_button(parent: Node, label: String) -> Control:
	for child in parent.get_children():
		if child is Button and child.text == label:
			return child
	check(false, "missing visible button " + label)
	return null


func click(control: Control) -> void:
	if control == null:
		return
	check(control.is_visible_in_tree(), "control visible before mouse input")
	await click_point(control.get_global_rect().get_center())


func click_point(point: Vector2, mouse_button: MouseButton = MOUSE_BUTTON_LEFT) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = point
	root.push_input(motion, true)
	var event := InputEventMouseButton.new()
	event.position = point
	event.button_index = mouse_button
	event.pressed = true
	# Route genuine GUI events through one viewport without allowing desktop
	# pointer motion to interleave between our synthetic press and release.
	root.push_input(event, true)
	event = event.duplicate()
	event.pressed = false
	root.push_input(event, true)
	await process_frame
	await process_frame


func shot(label: String) -> void:
	await process_frame
	await process_frame
	RenderingServer.force_draw(false)
	check(root.get_texture().get_image().save_png(OUT + label + ".png") == OK, "render capture " + label)


func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error(message)
