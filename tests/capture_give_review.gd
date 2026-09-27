extends SceneTree
## Synthetic inventory fixtures, real viewport mouse events, one rendering window.
const OUT := "res://ignored/give-review/"
const Loop = preload("res://game/battle/scene/BattlePlayLoop.gd")
const BattleFixture = preload("res://tests/support/BattleFixture.gd")
var scene: Node
var failures: Array[String] = []
var observations: Dictionary = {}


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Give review requires a rendering window on the built-in display")
		quit(2)
		return
	root.title = "HSL Give Exchange Review"
	root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(640,480)
	DirAccess.make_dir_recursive_absolute(OUT)
	if OS.get_cmdline_user_args().has("targets"):
		await skill_target_review()
		return
	if OS.get_cmdline_user_args().has("costs") or OS.get_cmdline_user_args().has("resolve"):
		await skill_cost_review()
		return
	if OS.get_cmdline_user_args().has("actions"):
		await action_state_review()
		return
	if OS.get_cmdline_user_args().has("handoff"):
		await handoff_review()
		return
	await fixture([241,241,246,281,0,0,0,0], [246,0,0,0,0,0,0,0])
	var initial: Dictionary = scene.play_loop.duplicate(true)
	await open_give()
	await shot("give-target-choice")
	await click(scene.item_panel.target_buttons["enemy023_1"])
	await proposal(0,1)
	await shot("give-confirmation")
	var preview: Dictionary = scene.play_loop.duplicate(true)
	await click(button(scene.item_panel.page_root, "取消"))
	check(scene.play_loop == preview, "mouse proposal cancellation preserves all battle state")
	await click(scene.item_panel.give_view.destination_buttons[1])
	await click(scene.item_panel.confirm_button)
	check(scene.item_panel.page == "give_inventory" and not scene.ai_playback_active, "first give keeps same session open")
	await proposal(0,2)
	await click(scene.item_panel.confirm_button)
	await shot("give-two-items")
	check(Loop.unit(scene.play_loop,"leonard")["inventory"] == [246,281,0,0,0,0,0,0], "two gives remove exactly two source slots")
	check(Loop.unit(scene.play_loop,"enemy023_1")["inventory"] == [246,241,241,0,0,0,0,0], "recipient retains separate duplicate slots")
	check(scene.play_loop["turn_queue"] == initial["turn_queue"], "two gives do not advance before session end")
	observations["continuous"] = bags()
	await click(button(scene.item_panel.give_view, "結束給予"))
	check(scene.play_loop["turn_queue"] != initial["turn_queue"] and not scene.item_panel.visible, "ending changed session advances once")

	await fixture([241,241,241,241,241,241,241,241], [246,241,241,241,241,241,241,241])
	await open_give()
	check(not scene.item_panel.target_buttons["enemy023_1"].disabled, "full recipient remains selectable for exchange")
	await click(scene.item_panel.target_buttons["enemy023_1"])
	await proposal(0,0)
	await shot("full-exchange-confirmation")
	preview = scene.play_loop.duplicate(true)
	await click(button(scene.item_panel.page_root,"取消"))
	check(scene.play_loop == preview, "full exchange cancellation loses nothing")
	await click(scene.item_panel.give_view.destination_buttons[0])
	await click(scene.item_panel.confirm_button)
	await shot("full-exchange-result")
	check(Loop.unit(scene.play_loop,"leonard")["inventory"] == [241,241,241,241,241,241,241,246], "full source receives returned item in freed slot")
	check(Loop.unit(scene.play_loop,"enemy023_1")["inventory"] == [241,241,241,241,241,241,241,241], "full receiver compacts then inserts incoming item")
	observations["full_exchange"] = bags()

	await fixture([241,246,0,0,0,0,0,0], [241,0,0,0,0,0,0,0])
	var origin: Vector2i = Loop.unit(scene.play_loop,"leonard")["coord"]
	scene.set_process(true)
	await create_timer(0.3).timeout
	await click(scene.action_menu.get_node("MoveCommand"))
	var neighbors: Array = Loop.movement_cells(scene.play_loop,"leonard").filter(func(cell): return absi(cell.x-origin.x) + absi(cell.y-origin.y) == 1)
	check(not neighbors.is_empty(), "movement fixture has a legal adjacent cell")
	if not neighbors.is_empty():
		var destination: Vector2i = neighbors[0]
		await click_point(scene.grid_cell_center_to_logical_position(destination))
		await create_timer(0.6).timeout
		check(scene.play_loop["pending_move"], "mouse move creates pending movement")
		Loop._unit(scene.play_loop,"enemy023_1")["coord"] = destination + Vector2i.RIGHT
		scene.apply_loop(scene.play_loop, "test")
		var before_give: Dictionary = scene.play_loop.duplicate(true)
		await open_give()
		await click(scene.item_panel.target_buttons["enemy023_1"])
		await proposal(0,1)
		await click(button(scene.item_panel.page_root,"取消"))
		await click(button(scene.item_panel.give_view,"選擇同伴"))
		await click(button(scene.item_panel.page_root,"結束給予"))
		check(scene.play_loop["pending_move"] and scene.play_loop["turn_queue"] == before_give["turn_queue"], "unconfirmed Give exit preserves pending movement and actor")
		check(Loop.unit(scene.play_loop,"leonard")["inventory"] == [241,246,0,0,0,0,0,0], "cancelled Give preserves exact inventory order")
		await click_point(Vector2(320,240), MOUSE_BUTTON_RIGHT)
		check(Loop.unit(scene.play_loop,"leonard")["coord"] == origin and not scene.play_loop["pending_move"], "mouse can still undo movement after Give cancellation")
		observations["cancelled_move"] = {"restored": Loop.unit(scene.play_loop,"leonard")["coord"] == origin, "inventory": Loop.unit(scene.play_loop,"leonard")["inventory"], "queue_unchanged": scene.play_loop["turn_queue"] == before_give["turn_queue"]}
		await shot("give-cancelled-move")
	FileAccess.open(OUT+"receipt.json",FileAccess.WRITE).store_string(JSON.stringify({"fixture":true,"input_delivery":"Viewport.push_input motion/press/release; no desktop input or direct button signals","window_position":root.position,"window_size":root.size,"observations":observations,"failures":failures},"  "))
	scene.queue_free()
	await process_frame
	await create_timer(0.3).timeout
	print("GIVE_RENDER_REVIEW_", "PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)


func handoff_review() -> void:
	root.title = "HSL Action Handoff Review"
	for operation in ["wait","use","give"]:
		await fixture([241,241,246,0,0,0,0,0],[0,0,0,0,0,0,0,0])
		var actor := Loop._unit(scene.play_loop,"leonard")
		actor["live_speed"] = 30
		actor["hp"] = 10
		var ally := Loop._unit(scene.play_loop,"enemy023_1")
		ally["live_speed"] = 29
		ally["player_commandable"] = true
		ally["battle_actor_role"] = Loop.ROLE_PLAYER
		scene.play_loop["turn_queue"] = Loop.CoreTurnQueue.rebuild(scene.play_loop["units"])
		scene.apply_loop(Loop.select_player_unit(scene.play_loop,"leonard"), "test")
		scene.resume_turn_presentation()
		scene.set_process(true)
		await create_timer(0.3).timeout
		var before: Dictionary = scene.play_loop.duplicate(true)
		if operation == "wait":
			await click(scene.action_menu.get_node("WaitCommand"))
		else:
			await click(scene.action_menu.get_node("ItemCommand"))
			await create_timer(0.3).timeout
			if operation == "use":
				await click(scene.item_panel.menu.get_node("UseCommand"))
				await click(scene.item_panel.rows.get_child(0))
				await click(scene.item_panel.target_buttons["leonard"])
			else:
				await click(scene.item_panel.menu.get_node("GiveCommand"))
				await click(scene.item_panel.target_buttons["enemy023_1"])
				await proposal(0,0)
				await click(scene.item_panel.confirm_button)
				await click(button(scene.item_panel.give_view,"結束給予"))
		await create_timer(0.3).timeout
		check(scene.selected_unit_id == "enemy023_1" and not scene.ai_playback_active,"mouse " + operation + " selects the immediate player successor")
		check(scene.play_loop["turn_queue"]["index"] == 1 and scene.play_loop["turn_queue"]["round"] == 0,"mouse " + operation + " advances only one slot")
		var settled: Dictionary = scene.play_loop.duplicate(true)
		await click(scene.action_menu.get_node("StatusCommand"))
		await shot("handoff-"+operation+"-successor")
		check(scene.status_panel.visible and scene.play_loop == settled,"successor Status is read-only")
		await click_point(Vector2(320,240),MOUSE_BUTTON_RIGHT)
		await create_timer(0.3).timeout
		await click(scene.action_menu.get_node("MoveCommand"))
		check(scene.interaction_state == "move_select" and scene.selected_unit_id == "enemy023_1","successor can still select Move after " + operation)
		if operation == "wait":
			await shot("handoff-wait-move")
		observations[operation] = {"selected_actor":scene.selected_unit_id,"queue_index":scene.play_loop["turn_queue"]["index"],"round":scene.play_loop["turn_queue"]["round"],"next_player_can_move":scene.interaction_state=="move_select","source_hp_before":Loop.unit(before,"leonard")["hp"],"source_hp_after":Loop.unit(settled,"leonard")["hp"],"source_inventory":Loop.unit(settled,"leonard")["inventory"]}
	FileAccess.open(OUT+"handoff-receipt.json",FileAccess.WRITE).store_string(JSON.stringify({"fixture":true,"synthetic_second_player":true,"input_delivery":"Viewport.push_input; actual Item/Wait commands and Control selection, no desktop input or direct button signals","window_position":root.position,"window_size":root.size,"observations":observations,"failures":failures},"  "))
	scene.queue_free()
	await process_frame
	await create_timer(0.3).timeout
	print("ACTION_HANDOFF_RENDER_REVIEW_", "PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)


func action_state_review() -> void:
	root.title = "HSL Action State Review"
	for route in ["wait", "drop_attack", "move_cancel_give", "special"]:
		await fixture([241,241,246,0,0,0,0,0], [0,0,0,0,0,0,0,0])
		var actor := Loop._unit(scene.play_loop,"leonard")
		actor["live_speed"] = 30
		actor["stamina"] = 60
		var origin: Vector2i = actor["coord"]
		var ally := Loop._unit(scene.play_loop,"enemy023_1")
		ally["live_speed"] = 29
		ally["player_commandable"] = true
		ally["battle_actor_role"] = Loop.ROLE_PLAYER
		var enemy := Loop._unit(scene.play_loop,"enemy021_1")
		enemy["coord"] = origin + Vector2i.UP
		enemy["hp"] = 100
		enemy["max_hp"] = 100
		enemy["combat_profile"]["live_defense"] = 10000
		scene.play_loop["turn_queue"] = Loop.CoreTurnQueue.rebuild(scene.play_loop["units"])
		scene.apply_loop(Loop.select_player_unit(scene.play_loop,"leonard"), "test")
		scene.resume_turn_presentation()
		scene.set_process(true)
		await create_timer(0.3).timeout
		var initial: Dictionary = scene.play_loop.duplicate(true)
		var old_wait_point: Vector2 = scene.action_menu.get_node("WaitCommand").get_global_rect().get_center()
		if route == "move_cancel_give":
			await click(scene.action_menu.get_node("MoveCommand"))
			var cells: Array = Loop.movement_cells(scene.play_loop,"leonard").filter(func(cell): return absi(cell.x-origin.x)+absi(cell.y-origin.y)==1)
			check(not cells.is_empty(), "move-cancel route has a legal neighboring destination")
			if cells.is_empty(): break
			var destination: Vector2i = cells[0]
			await click_point(scene.grid_cell_center_to_logical_position(destination))
			await create_timer(0.6).timeout
			await click_point(Vector2(320,240),MOUSE_BUTTON_RIGHT)
			check(scene.interaction_state == "move_select" and Loop.unit(scene.play_loop,"leonard")["coord"] == origin, "Move/Cancel returns to the original cell with movement selection already open")
			check(scene.move_overlay.visible and not scene.play_loop["moved_this_action"], "cancelled movement restores eligibility and visible envelope")
			await shot("action-move-cancel-reselect")
			await click_point(scene.grid_cell_center_to_logical_position(destination))
			await create_timer(0.6).timeout
			check(scene.play_loop["pending_move"] and Loop.unit(scene.play_loop,"leonard")["coord"] == destination, "a new destination can be selected immediately after cancel")
			Loop._unit(scene.play_loop,"enemy023_1")["coord"] = destination + Vector2i.RIGHT
			scene.apply_loop(scene.play_loop, "test")
			await click(scene.action_menu.get_node("ItemCommand"))
			await create_timer(0.3).timeout
			await click(scene.item_panel.menu.get_node("GiveCommand"))
			await click(scene.item_panel.target_buttons["enemy023_1"])
			await proposal(0,0)
			await click(scene.item_panel.confirm_button)
			check(scene.play_loop["turn_queue"] == initial["turn_queue"], "Give remains within the owner's session before Finish")
			await click(button(scene.item_panel.give_view,"結束給予"))
		elif route == "wait":
			await click(scene.action_menu.get_node("WaitCommand"))
		else:
			if route == "drop_attack":
				await click(scene.action_menu.get_node("ItemCommand"))
				await create_timer(0.3).timeout
				await click(scene.item_panel.menu.get_node("DropCommand"))
				await click(scene.item_panel.rows.get_child(0))
				await click(scene.item_panel.confirm_button)
				check(Loop.unit(scene.play_loop,"leonard")["inventory"] == [241,246,0,0,0,0,0,0] and scene.play_loop["turn_queue"] == initial["turn_queue"], "Drop consumes one item without ending the actor")
				await create_timer(0.3).timeout
			await click(scene.action_menu.get_node("SpecialCommand" if route == "special" else "AttackCommand"))
			if scene.play_loop["interaction"] == "special_select": await click(scene.magic_panel.choices["special:magicOTHER:magicCode01"])
			await click_point(scene.grid_cell_center_to_logical_position(enemy["coord"]))
			check(scene.play_loop["attacked_this_action"] and not scene.play_loop["moved_this_action"], "unmoved offensive action is committed")
			# Bound the real-clock visual route; never accelerate animation or play an
			# unattended battle. Both target HP and second player are explicit fixtures.
			for _tick in range(100):
				if scene.selected_unit_id == "enemy023_1": break
				await create_timer(0.1).timeout
		await create_timer(0.3).timeout
		check(scene.selected_unit_id == "enemy023_1" and not scene.ai_playback_active, "route selects exactly the next player: " + route)
		check(scene.play_loop["turn_queue"]["index"] == 1 and scene.play_loop["turn_queue"]["round"] == 0, "route advances only once: " + route)
		var settled: Dictionary = scene.play_loop.duplicate(true)
		var release := InputEventMouseButton.new()
		release.position = old_wait_point
		release.button_index = MOUSE_BUTTON_LEFT
		release.pressed = false
		root.push_input(release,true)
		await process_frame
		check(scene.play_loop == settled, "a repeated release from the predecessor cannot wait the successor")
		await click(scene.action_menu.get_node("StatusCommand"))
		await shot("action-" + route + "-successor")
		observations[route] = {"current":scene.selected_unit_id, "phase":scene.interaction_state,
			"queue":scene.play_loop["turn_queue"], "source_coord":Loop.unit(scene.play_loop,"leonard")["coord"],
			"source_inventory":Loop.unit(scene.play_loop,"leonard")["inventory"],
			"next_inventory":Loop.unit(scene.play_loop,"enemy023_1")["inventory"]}
	FileAccess.open(OUT+"action-state-receipt.json",FileAccess.WRITE).store_string(JSON.stringify({"fixture":true,
		"synthetic_second_player":true,"native_gameplay_parity":false,
		"input_delivery":"real viewport motion/press/release and real-time presentation; no desktop input or direct button signals",
		"window_position":root.position,"window_size":root.size,"observations":observations,"failures":failures},"  "))
	scene.queue_free()
	await process_frame
	await create_timer(0.3).timeout
	print("ACTION_STATE_RENDER_REVIEW_", "PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)


func skill_cost_review() -> void:
	var resolution_review := OS.get_cmdline_user_args().has("resolve")
	var prefix := "resolution" if resolution_review else "cost"
	root.title = "HSL Shared Skill Resolution Review" if resolution_review else "HSL Skill Resource Review"
	await fixture([241,241,246,0,0,0,0,0],[0,0,0,0,0,0,0,0])
	var actor := Loop._unit(scene.play_loop,"leonard")
	actor["live_speed"] = 30
	actor["stamina"] = 19
	var move_origin: Vector2i = actor["coord"]
	var ally := Loop._unit(scene.play_loop,"enemy023_1")
	ally["live_speed"] = 29
	ally["player_commandable"] = true
	ally["battle_actor_role"] = Loop.ROLE_PLAYER
	var enemy := Loop._unit(scene.play_loop,"enemy021_1")
	enemy["coord"] = actor["coord"] + Vector2i.UP
	enemy["hp"] = 100
	enemy["max_hp"] = 100
	enemy["combat_profile"]["live_defense"] = 10000
	scene.play_loop["turn_queue"] = Loop.CoreTurnQueue.rebuild(scene.play_loop["units"])
	scene.apply_loop(Loop.select_player_unit(scene.play_loop,"leonard"), "test")
	scene.resume_turn_presentation()
	scene.set_process(true)
	await create_timer(0.3).timeout
	var denied: Dictionary = scene.play_loop.duplicate(true)
	# 19 ST still opens the skill page (menus_ui/README.md#5); the cost20 row is the disabled control.
	check(not scene.action_menu.get_node("SpecialCommand").disabled and not Loop.can_use_special(scene.play_loop,"leonard"),"19 ST still opens the skill page for the cost20 special")
	await click(scene.action_menu.get_node("SpecialCommand"))
	check(scene.magic_panel.visible and scene.magic_panel.choices["special:magicOTHER:magicCode01"].disabled,"19 ST visibly disables the cost20 row")
	await shot(prefix+"-st19-disabled")
	await click_point(scene.magic_panel.choices["special:magicOTHER:magicCode01"].get_global_rect().get_center())
	check(scene.play_loop["units"] == denied["units"] and scene.play_loop["turn_queue"] == denied["turn_queue"] and scene.interaction_state == "special_select","disabled row cannot alter battle state")
	await click_point(scene.magic_panel.choices["special:magicOTHER:magicCode01"].get_global_rect().get_center(), MOUSE_BUTTON_RIGHT)
	Loop._unit(scene.play_loop,"leonard")["stamina"] = 20
	scene.apply_loop(Loop.select_player_unit(scene.play_loop,"leonard"), "test")
	scene.resume_turn_presentation()
	await create_timer(0.3).timeout
	check(not scene.action_menu.get_node("SpecialCommand").disabled and Loop.can_use_special(scene.play_loop,"leonard"),"exact20 ST enables special")
	await shot(prefix+"-st20-enabled")
	if resolution_review:
		await click(scene.action_menu.get_node("MoveCommand"))
		var cells: Array = Loop.movement_cells(scene.play_loop,"leonard").filter(func(p): return absi(p.x-move_origin.x)+absi(p.y-move_origin.y)==1)
		check(not cells.is_empty(),"shared resolution review has a real legal move")
		if cells.is_empty():
			quit(1)
			return
		var destination: Vector2i = cells[0]
		await click_point(scene.grid_cell_center_to_logical_position(destination))
		await create_timer(0.6).timeout
		enemy = Loop._unit(scene.play_loop,"enemy021_1")
		enemy["coord"] = destination+Vector2i.UP
		scene.apply_loop(scene.play_loop, "test")
		check(scene.play_loop["pending_move"] and Loop.unit(scene.play_loop,"leonard")["coord"]==destination,"actual movement precedes the shared skill operation")
	var before: Dictionary = scene.play_loop.duplicate(true)
	await click(scene.action_menu.get_node("SpecialCommand"))
	if scene.play_loop["interaction"] == "special_select": await click(scene.magic_panel.choices["special:magicOTHER:magicCode01"])
	check(scene.interaction_state == "attack_select","real special command enters target selection")
	await click_point(Vector2(320,240),MOUSE_BUTTON_RIGHT)
	check(scene.interaction_state == "action_menu" and Loop.unit(scene.play_loop,"leonard")["stamina"] == 20 and scene.play_loop["turn_queue"] == before["turn_queue"],"target cancellation preserves exact ST and current initiative")
	check(scene.play_loop["pending_move"]==before["pending_move"] and scene.play_loop["units"]==before["units"],"target cancellation preserves coordinates, inventory and all units")
	await create_timer(0.3).timeout
	await click(scene.action_menu.get_node("SpecialCommand"))
	if scene.play_loop["interaction"] == "special_select": await click(scene.magic_panel.choices["special:magicOTHER:magicCode01"])
	await click_point(scene.grid_cell_center_to_logical_position(enemy["coord"]))
	check(Loop.unit(scene.play_loop,"leonard")["stamina"] == 0,"confirmation debits recovered cost20 exactly once")
	for _tick in range(100):
		if scene.selected_unit_id == "enemy023_1": break
		await create_timer(0.1).timeout
	check(scene.selected_unit_id == "enemy023_1" and scene.play_loop["turn_queue"]["index"] == 1,"paid special completes into exactly the next controllable ally")
	await create_timer(0.3).timeout
	await click(scene.action_menu.get_node("StatusCommand"))
	await shot(prefix+"-special-next-ally")
	FileAccess.open(OUT+("skill-resolution-receipt.json" if resolution_review else "skill-cost-receipt.json"),FileAccess.WRITE).store_string(JSON.stringify({
		"fixture":true,"input_delivery":"Viewport real Control motion/press/release; normal presentation clock; no desktop input",
		"move_before_skill":resolution_review,"move_origin":move_origin,"final_coord":Loop.unit(scene.play_loop,"leonard")["coord"],
		"window_position":root.position,"window_size":root.size,"st19_rejected":denied["units"].filter(func(u):return u["id"]=="leonard")[0]["stamina"]==19,
		"initial_stamina":20,"final_stamina":Loop.unit(scene.play_loop,"leonard")["stamina"],
		"payment":scene.play_loop["last_combat"]["resource_payment"],"next_actor":scene.selected_unit_id,
		"queue_index":scene.play_loop["turn_queue"]["index"],"failures":failures},"  "))
	scene.queue_free()
	await process_frame
	await create_timer(0.3).timeout
	print("SKILL_RESOLUTION_RENDER_REVIEW_" if resolution_review else "SKILL_COST_RENDER_REVIEW_", "PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)


func skill_target_review() -> void:
	root.title = "HSL Skill Target Review"
	await fixture([241,241,246,0,0,0,0,0],[0,0,0,0,0,0,0,0])
	var actor := Loop._unit(scene.play_loop,"leonard")
	actor["live_speed"] = 30
	actor["stamina"] = 20
	var origin: Vector2i = actor["coord"]
	var ally := Loop._unit(scene.play_loop,"enemy023_1")
	ally["live_speed"] = 29
	ally["player_commandable"] = true
	ally["battle_actor_role"] = Loop.ROLE_PLAYER
	var diagonal := Loop._unit(scene.play_loop,"enemy021_1")
	var axial := Loop._unit(scene.play_loop,"enemy021_2")
	diagonal["coord"] = origin+Vector2i(1,-1)
	axial["coord"] = origin+Vector2i(0,-2)
	for foe in [diagonal,axial]:
		foe["hp"] = 100
		foe["max_hp"] = 100
		foe["combat_profile"]["live_defense"] = 10000
	var index := 0
	for unit in scene.play_loop["units"]:
		if unit["id"] not in ["leonard","enemy023_1","enemy021_1","enemy021_2"]:
			unit["coord"] = Vector2i(0,index)
			index += 1
	scene.play_loop["turn_queue"] = Loop.CoreTurnQueue.rebuild(scene.play_loop["units"])
	scene.apply_loop(Loop.select_player_unit(scene.play_loop,"leonard"), "test")
	scene.resume_turn_presentation()
	scene.set_process(true)
	await create_timer(0.3).timeout
	await click(scene.action_menu.get_node("SpecialCommand"))
	if scene.play_loop["interaction"] == "special_select": await click(scene.magic_panel.choices["special:magicOTHER:magicCode01"])
	check(Loop.attack_cells(scene.play_loop).has(axial["coord"]) and not Loop.attack_cells(scene.play_loop).has(diagonal["coord"]),"source cross accepts axial distance2 but rejects diagonal distance2")
	await shot("target-special-source-cross")
	var before: Dictionary = scene.play_loop.duplicate(true)
	await click_point(scene.grid_cell_center_to_logical_position(diagonal["coord"]))
	check(scene.play_loop["units"] == before["units"] and scene.play_loop["turn_queue"] == before["turn_queue"] and not scene.play_loop["attacked_this_action"],"real invalid target click cannot damage, charge or advance")
	check(scene.play_loop["last_attack_reject"]["reason"] == "out_of_range", "invalid target is rejected by the shared range rule")
	await click_point(Vector2(320,240),MOUSE_BUTTON_RIGHT)
	check(scene.interaction_state == "action_menu" and Loop.unit(scene.play_loop,"leonard")["stamina"] == 20,"cancel after rejected target preserves command and resource")
	await create_timer(0.3).timeout
	await click(scene.action_menu.get_node("SpecialCommand"))
	if scene.play_loop["interaction"] == "special_select": await click(scene.magic_panel.choices["special:magicOTHER:magicCode01"])
	await click_point(scene.grid_cell_center_to_logical_position(axial["coord"]))
	check(Loop.unit(scene.play_loop,"leonard")["stamina"] == 0,"valid axial target pays exactly once")
	for _tick in range(100):
		if scene.selected_unit_id == "enemy023_1": break
		await create_timer(0.1).timeout
	check(scene.selected_unit_id == "enemy023_1" and scene.play_loop["turn_queue"]["index"] == 1,"valid skill returns exactly the next ally after presentation")
	await create_timer(0.3).timeout
	await click(scene.action_menu.get_node("StatusCommand"))
	await shot("target-valid-special-successor")
	FileAccess.open(OUT+"skill-target-receipt.json",FileAccess.WRITE).store_string(JSON.stringify({"fixture":true,
		"input_delivery":"Viewport real Control motion/press/release; normal animation; no desktop input",
		"window_position":root.position,"window_size":root.size,"caster":origin,"rejected_diagonal":diagonal["coord"],"accepted_axial":axial["coord"],
		"final_stamina":Loop.unit(scene.play_loop,"leonard")["stamina"],"next_actor":scene.selected_unit_id,
		"queue_index":scene.play_loop["turn_queue"]["index"],"failures":failures},"  "))
	scene.queue_free()
	await process_frame
	await create_timer(0.3).timeout
	print("SKILL_TARGET_RENDER_REVIEW_", "PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)


func fixture(sender: Array, receiver: Array) -> void:
	if is_instance_valid(scene):
		scene.queue_free()
		await process_frame
	scene = load("res://game/battle/scene/BattleSceneRuntime.tscn").instantiate()
	scene.scenario_path = BattleFixture.PATH; scene.startup_mode = "dev_first_control"
	root.add_child(scene)
	current_scene = scene
	scene.start_dev_first_control_harness()
	scene.set_process(false)
	scene.get_node("BattleMusic").stop()
	var actor := Loop._unit(scene.play_loop,"leonard")
	actor["inventory"] = sender.duplicate()
	var ally := Loop._unit(scene.play_loop,"enemy023_1")
	ally["coord"] = actor["coord"] + Vector2i.RIGHT
	ally["inventory"] = receiver.duplicate()
	scene.apply_loop(scene.play_loop, "test")
	await process_frame


func bags() -> Dictionary:
	return {"sender":Loop.unit(scene.play_loop,"leonard")["inventory"], "receiver":Loop.unit(scene.play_loop,"enemy023_1")["inventory"], "action_used":scene.play_loop["give_session"]["action_used"]}


func open_give() -> void:
	scene.menus.choose_command("item")
	await create_timer(0.3).timeout
	await click(scene.item_panel.menu.get_node("GiveCommand"))
	check(scene.item_panel.page == "give_target", "mouse Give reaches target selection")


func proposal(source: int, destination: int) -> void:
	await click(scene.item_panel.give_view.source_buttons[source])
	await click(scene.item_panel.give_view.destination_buttons[destination])
	check(scene.item_panel.page == "give_confirm", "mouse selects source and destination before confirm")


func button(parent: Node, title: String) -> Control:
	for child in parent.get_children():
		if child is Button and child.text == title:
			return child
	check(false,"missing visible button: " + title)
	return null


func click(control: Control) -> void:
	if control == null: return
	check(control.is_visible_in_tree() and not control.disabled, "requested control is visible and enabled")
	await click_point(control.get_global_rect().get_center())


func click_point(point: Vector2, mouse_button: MouseButton = MOUSE_BUTTON_LEFT) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = point
	root.push_input(motion,true)
	var event := InputEventMouseButton.new()
	event.position = point
	event.button_index = mouse_button
	event.pressed = true
	root.push_input(event,true)
	event = event.duplicate()
	event.pressed = false
	root.push_input(event,true)
	await process_frame
	await process_frame


func shot(name: String) -> void:
	await process_frame
	RenderingServer.force_draw(false)
	check(root.get_texture().get_image().save_png(OUT+name+".png") == OK, "render capture " + name)


func check(value: bool, label: String) -> void:
	if not value:
		failures.append(label)
		push_error(label)
