extends RefCounted
## Player input for BattleSceneRuntime: the InputEvent dispatch order, pointer
## hit-testing (logical → grid / unit / command) and the pointer hover state the
## runtime exposes (`pointer_*`, `hovered_*`, `held_command_id`). Owns no state of its
## own; every mutation lands on the runtime mirror and every rule call goes to the
## PlayLoop through the runtime's interaction operations. Coordinates stay on the
## runtime chain viewport → logical → world → grid; hit-test values are not tuned here.
## provenance:
##   rules: remake-invented (mouse／keyboard dispatch order, right-click cancel, Home recenter)
##   layout: runtime-measured docs/evidence_packets/runtime_observations/first_battle_visual_evidence_index.md
##     (hit-test shares the measured grid projection; not tuned here)

const BattlePlayLoop = preload("res://game/sim/loop/BattlePlayLoop.gd")
const ScriptPresentation = preload("res://game/battle/scene/BattleScriptPresentation.gd")
const Interaction = preload("res://game/sim/Interaction.gd")
const LoopKeys = preload("res://game/sim/LoopKeys.gd")
const BattleOutcome = preload("res://game/sim/BattleOutcome.gd")

var runtime: Node


static func create(scene_runtime: Node) -> RefCounted:
	var input := new()
	input.runtime = scene_runtime
	return input


func handle_input(event: InputEvent) -> void:
	var presentation: Node = runtime.get_node("BattlePresentation")
	if runtime.treasure_view != null and runtime.treasure_view.busy(): return
	# Opening is replaceable by a saved battle; battle cutscenes remain atomic.
	# Route its real F9 before the coordinator consumes ordinary dialogue input.
	if runtime.settlement_controller != null and runtime.interaction_state == Interaction.OPENING_TIMELINE and event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F9 and (runtime.opening_coordinator == null or not runtime.opening_coordinator.cutscene_mode):
		runtime.settlement_controller.load_battle()
		return
	# The between-battle equipment screen owns Esc / right click while it is up.
	if runtime.party_equipment_screen != null and runtime.party_equipment_screen.active:
		if runtime.party_equipment_screen.handle_input(event):
			runtime.get_viewport().set_input_as_handled()
		return
	# A raised system scroll (battle or world variant) owns all input until it closes.
	for scroll in [runtime.system_menu, runtime.world_system_menu]:
		if scroll != null and scroll.active():
			if scroll.handle_input(event):
				runtime.get_viewport().set_input_as_handled()
			return
	if runtime.opening_coordinator != null and runtime.opening_coordinator.active:
		runtime.opening_coordinator.handle_input(event)
		return
	if runtime.world_map_runtime != null and runtime.world_map_runtime.active:
		runtime.world_map_runtime.handle_input(event)
		return
	if runtime.settlement_controller != null and runtime.settlement_controller.handle_input(event): return
	if ScriptPresentation.pending(runtime) and not runtime.growth_panel.visible and not presentation.dialogue_active(): return
	if event is InputEventMouseMotion:
		runtime.pointer_logical_position = runtime.viewport_to_logical_position(event.position)
		runtime.pointer_inside_window = Rect2(Vector2.ZERO, Vector2(runtime.logical_viewport_size)).has_point(runtime.pointer_logical_position)
	# An open battle modal owns the event: it closes itself on right click / Esc and
	# swallows everything else (each panel's handle_input).
	for panel in runtime.modal_panels:
		if panel.visible:
			panel.handle_input(event)
			return
	if presentation.cutin.busy() or presentation.has_pending_combat(runtime.play_loop):
		return
	if presentation.dialogue_active():
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			presentation.advance_dialogue()
		elif event is InputEventKey and event.pressed and not event.echo and event.keycode in [KEY_SPACE, KEY_ENTER]:
			presentation.advance_dialogue()
		return
	if presentation.combat_busy(runtime.play_loop):
		return
	# A decided battle takes no map input: it fades out and leaves by itself
	# (BattleSceneRuntime.leave_finished_battle; the original has no result page).
	if BattleOutcome.decided(runtime.play_loop):
		return
	if runtime.interaction_state == Interaction.OPENING_TIMELINE:
		if str(runtime.scene_timeline.current_event().get("kind", "")) != "dialogue_message_id":
			return
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			runtime.advance_opening_timeline("left_click")
		elif event is InputEventKey and event.pressed and not event.echo and (event.keycode == KEY_ENTER or event.keycode == KEY_SPACE):
			runtime.advance_opening_timeline("key_confirm")
		return
	if event is InputEventMouseMotion:
		handle_pointer_motion(runtime.viewport_to_logical_position(event.position))
	elif event is InputEventMouseButton:
		var logical_position: Vector2 = runtime.viewport_to_logical_position(event.position)
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				handle_pointer_left_pressed(logical_position)
			else:
				handle_pointer_left_released(logical_position)
		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			if not _raise_system_scroll():
				handle_pointer_cancel(logical_position)
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_HOME and runtime.interaction_state in Interaction.PLAYER_CONTROL and not runtime.has_actor_motion():
			runtime.center_camera_on_grid(runtime.unit_grid_coords[runtime.selected_unit_id])
			update_pointer_hit(runtime.pointer_logical_position)
		elif event.keycode == KEY_ESCAPE:
			if not _raise_system_scroll():
				handle_pointer_cancel(runtime.pointer_logical_position)


## Esc and right click both raise the battle scroll (defProcBattleBOSS 0x4082c4 reads
## [0x4c6390] & 0x100000 or [0x4c6398] & 0x20000) on a fresh ring; otherwise they cancel.
## BattleSystemMenu.open holds the original gate. The skill page's slide-out and the unit ticks
## after it (cast_pick_hold) raise nothing: a ring press sets [0x4c1b00] |= 0x2000000 (0x43e91a)
## and only the next ring build clears it (0x443a52), so 0x4082ab's test of 0x7e000000 skips both keys.
func _raise_system_scroll() -> bool:
	if runtime.system_menu == null or runtime.has_actor_motion() or runtime.held_command_id != "":
		return false
	if runtime.menus.cast_pick_hold:
		return false
	if not bool(runtime.system_menu.open().get("ok", false)):
		return false
	# State 99 (0x444860): a right click on the ring glides the camera back to the actor.
	if runtime.interaction_state == Interaction.ACTION_MENU and runtime.selected_unit_id != "":
		runtime.focus_camera_on_grid(runtime.unit_grid_coord(runtime.selected_unit_id))
	return true


func command_id_at_logical_position(logical_position: Vector2) -> String:
	if runtime.action_menu == null or not runtime.action_menu.visible or runtime.action_menu.is_expanding():
		return ""
	for child in runtime.action_menu.get_children():
		if child is Control:
			if child is BaseButton and (child as BaseButton).disabled:
				continue
			var command_id := command_id_for_control(child)
			if command_id != "" and Rect2(runtime.action_menu.position + child.position, child.size).has_point(logical_position):
				return command_id
	return ""


func handle_pointer_motion(logical_position: Vector2) -> void:
	update_pointer_hit(logical_position)


func handle_pointer_left_pressed(logical_position: Vector2) -> void:
	if BattlePlayLoop.loot_waiting(runtime.play_loop): return
	update_pointer_hit(logical_position)
	if runtime.ai_playback_active or runtime.interaction_state == Interaction.AI_RESOLVING or runtime.has_actor_motion():
		return
	# The skill page's slide-out after a row click or a cancel (unit 0x77) reads no clicks.
	if runtime.menus.cast_pick_hold:
		return
	if runtime.hovered_command_id != "":
		runtime.held_command_id = runtime.hovered_command_id
		return
	if runtime.interaction_state == Interaction.MOVE_SELECT and runtime.move_overlay_cells.has(runtime.hovered_grid_cell):
		runtime.move_selected_actor_to_grid(runtime.hovered_grid_cell)
		return
	if runtime.interaction_state == Interaction.ATTACK_SELECT:
		if runtime.play_loop.get(LoopKeys.SELECTED_ATTACK) == "magic":
			runtime.attack_selected_coord(runtime.hovered_grid_cell)
		elif runtime.hovered_unit_id != "":
			runtime.attack_selected_coord(runtime.hovered_grid_cell)
		elif runtime.attack_overlay_cells.has(runtime.hovered_grid_cell):
			runtime.attack_selected_coord(runtime.hovered_grid_cell)
		return
	if runtime.hovered_unit_id != "":
		if runtime.interaction_state == Interaction.MOVE_SELECT and not runtime.is_player_commandable_unit(runtime.hovered_unit_id):
			# Move-select (phase 20 sub 0 0x443c63) is the only state with a unit-click branch:
			# 0x443cfa opens the page (mode 1, no gold box) for a known unit the player does not
			# command; an unknown one falls to 0x443d9d like a click on empty ground (OPT-INFO=公開
			# knows everyone). The action ring (98／74 → default 0x4447a7) has no such branch.
			# The state stays MOVE_SELECT, so closing returns to move-select (sub 11 0x4440b7 → 0).
			var known := BattlePlayLoop.unit_known(runtime.play_loop, runtime.hovered_unit_id)
			if not preload("res://game/battle/scene/BattleStatusPanel.gd").opens_for(known):
				return
			runtime.status_panel.show_unit(BattlePlayLoop.unit(runtime.play_loop, runtime.hovered_unit_id), known, false, runtime.play_loop)
		elif runtime.interaction_state != Interaction.MOVE_SELECT:
			runtime.select_actor(runtime.hovered_unit_id)


func handle_pointer_left_released(logical_position: Vector2) -> void:
	var pressed_command_id: String = runtime.held_command_id
	update_pointer_hit(logical_position)
	runtime.held_command_id = ""
	if pressed_command_id != "" and runtime.hovered_command_id == pressed_command_id:
		runtime.play_ui_sound("confirm")
		runtime.menus.choose_command(pressed_command_id)


func handle_pointer_cancel(logical_position: Vector2) -> void:
	update_pointer_hit(logical_position)
	runtime.held_command_id = ""
	if runtime.menus.cast_pick_hold:
		return
	if runtime.interaction_state == Interaction.MOVE_SELECT or runtime.interaction_state == Interaction.ATTACK_SELECT:
		runtime.cancel_current_interaction()
	elif runtime.pending_move_revert:
		runtime.cancel_pending_move()


func command_id_for_control(control: Control) -> String:
	var name := str(control.name)
	if name.ends_with("Command"):
		return name.substr(0, name.length() - "Command".length()).to_lower()
	return ""


func update_pointer_hit(logical_position: Vector2) -> void:
	runtime.pointer_logical_position = logical_position
	runtime.pointer_world_position = runtime.logical_to_world_position(logical_position)
	runtime.hovered_grid_cell = runtime.grid_at_logical_position(logical_position) if Rect2(Vector2.ZERO, Vector2(runtime.logical_viewport_size)).has_point(logical_position) else Interaction.NO_CELL
	runtime.hovered_command_id = command_id_at_logical_position(logical_position)
	runtime.hovered_unit_id = unit_id_at_grid(runtime.hovered_grid_cell)
	runtime.action_menu.set_hovered_command(runtime.hovered_command_id)


func unit_id_at_grid(coord: Vector2i) -> String:
	if coord.x < 0 or coord.y < 0:
		return ""
	var unit_id := BattlePlayLoop.unit_id_at_coord(runtime.play_loop, coord)
	return unit_id if unit_id != "" and runtime.actor_node_for_unit(unit_id) != null else ""


func disarm_pointer_scroll() -> void:
	# Mouse return requires fresh motion; never continue scrolling from an old
	# edge coordinate while the game is unfocused or the pointer is elsewhere.
	runtime.pointer_inside_window = false
	runtime.hovered_grid_cell = Interaction.NO_CELL
	runtime.hovered_unit_id = ""
	var presentation: Node = runtime.get_node("BattlePresentation")
	presentation.selection_cursor.hide()
	presentation.movement_preview.clear()
	presentation.target_vitals.hide()
	presentation.combat_label.hide()
