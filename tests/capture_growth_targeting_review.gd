extends SceneTree
## Windowed review captures for lane R5-L1 (level 3, 琥／緹娜／雷歐納德):
##   01 緹娜 kills a foe: the EXP + 升級 float; 02 the level-up window that follows it;
##   03 治癒之水 over full-HP 雷歐納德: the identity strip still shows;
##   04 琥's 毒魔箭 with the cursor on a cell in range: the range1Cell cross footprint.
## Lane R5-L7 additions: 04 now shows the footprint's own style (magenta fill, white outline);
##   05 a circle footprint (range3CellCircle → range2CellCircle) and 06 a line footprint
##   (range1Cell → range4CellDir), both set straight on the loop for the capture;
##   07 the final blow levels 緹娜: her level-up window over the field, no result page yet;
##   08 the victory result after the window closed.
## HSL_RNG_SEED=1 tools/godot.sh --script res://tests/capture_growth_targeting_review.gd -- --out=/abs/dir
## (the seed fixes level 3's formation and rolls; unseeded runs can miss the setups)
## Writes PNGs of the game window only; exits 0 when every capture landed.
const Loop = preload("res://game/battle/scene/BattlePlayLoop.gd")
const CampaignProgress = preload("res://game/battle/runtime/CampaignProgress.gd")
var OUT := "res://ignored/r5-l1-review/"
var scene: Node
var failures: Array[String] = []


# A finished battle fades out and leaves by itself (no result page); these captures
# inspect the finished battle, then reload or hand off explicitly.
func _init() -> void:
	preload("res://game/battle/scene/BattleSceneRuntime.gd").hold_finished_battle = true

func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="): OUT = arg.trim_prefix("--out=").trim_suffix("/") + "/"
	DirAccess.make_dir_recursive_absolute(OUT)
	CampaignProgress.reset_campaign()
	CampaignProgress.pending = {}
	root.size = Vector2i(640, 480)
	root.title = "HSL R5-L1/L7 review"
	create_timer(180).timeout.connect(func(): push_error("review timed out"); quit(2))
	scene = load("res://game/battle/scene/BattleSceneRuntime.tscn").instantiate()
	scene.scenario_path = "res://content/battles/battle_003.json"
	scene.startup_mode = "dev_first_control"
	root.add_child(scene)
	current_scene = scene
	await process_frame
	await process_frame
	scene.start_dev_first_control_harness()
	await create_timer(0.5).timeout
	await _growth_after_kill()
	await _heal_over_full_hp()
	await _poison_arrow_cross()
	await _footprint_shape("tina", "magic", "magic:magicWATER:magicCode02", Vector2i(2, 0), "05-circle-footprint")
	await _footprint_shape("leonard", "special", "special:magicOTHER:magicCode19", Vector2i(1, 0), "06-line-footprint")
	await _final_blow_growth()
	print("R5L1_REVIEW %s failures=%s" % [OUT, failures])
	quit(0 if failures.is_empty() else 1)


func _give_turn(id: String) -> void:
	var next: Dictionary = scene.play_loop.duplicate(true)
	Loop._clear_extra_action(next)
	next["turn_queue"] = Loop.CoreTurnQueue.rebuild(Loop._queue_actors(next))
	for index in range(next["turn_queue"]["slots"].size()):
		if next["turn_queue"]["slots"][index]["id"] == id: next["turn_queue"]["index"] = index; break
	scene.apply_loop(Loop._return_to_player(next, id), "test")
	scene.resume_turn_presentation()
	await create_timer(0.3).timeout


func _growth_after_kill() -> void:
	var loop: Dictionary = scene.play_loop
	var tina: Dictionary = Loop._unit(loop, "tina")
	var foe: Dictionary = Loop._unit(loop, "actor028_2")
	tina["exp"] = Loop.ProgressionRules.exp_to_next(int(tina["level"])) - 1
	tina["hit_bonus_accum"] = 1000
	foe["hp"] = 1
	foe["coord"] = tina["coord"] + Vector2i.RIGHT if Loop.unit_id_at_coord(loop, tina["coord"] + Vector2i.RIGHT) == "" else foe["coord"]
	scene.apply_loop(loop, "test")
	await _give_turn("tina")
	scene.menus.choose_command("attack")
	scene.attack_selected_target("actor028_2")
	var float_shot := false
	for frame in range(1200):
		var view = scene.get_node("BattlePresentation")
		if view.dialogue_active(): view.advance_dialogue()
		if Loop.loot_waiting(scene.play_loop):
			var settlement: Dictionary = scene.play_loop["settlement"]
			scene.apply_loop(Loop.finish_rewards(scene.play_loop, int(settlement["sequence"]), int(settlement["revision"]), false, true), "test")
		if not float_shot and view.aftermath.stage == "experience" and view.aftermath.reward_label.text.contains("升級"):
			await create_timer(0.25).timeout
			await shot("01-tina-exp-level-up-float")
			float_shot = true
		if scene.growth_panel.visible: break
		await process_frame
	check(float_shot, "the EXP／升級 float showed")
	check(scene.growth_panel.visible and str(scene.growth_panel.source_unit["id"]) == "tina", "緹娜's level-up window opened")
	await create_timer(0.4).timeout
	await shot("02-tina-level-up-window")
	scene.growth_panel.hide()
	await create_timer(0.3).timeout


func _heal_over_full_hp() -> void:
	var leonard: Dictionary = Loop._unit(scene.play_loop, "leonard")
	leonard["hp"] = int(leonard["max_hp"])
	scene.apply_loop(scene.play_loop, "test")
	await _give_turn("tina")
	await _choose("magic", "magic:magicWATER:magicCode06")
	await _hover(leonard["coord"])
	check(scene.get_node("BattlePresentation").target_vitals.visible, "治癒之水 over full-HP 雷歐納德 shows the strip")
	await shot("03-healing-water-full-hp-strip")
	scene.cancel_current_interaction()


func _poison_arrow_cross() -> void:
	Loop._unit(scene.play_loop, "hu")["stamina"] = 20
	scene.apply_loop(scene.play_loop, "test")
	await _give_turn("hu")
	await _choose("special", "special:magicMIND:magicCode03")
	var hu: Dictionary = Loop.unit(scene.play_loop, "hu")
	await _hover(hu["coord"] + Vector2i(2, 0))
	check(scene.overlays.footprint_cells.size() == 5, "毒魔箭 draws the five-cell cross")
	await shot("04-poison-arrow-cross")
	scene.cancel_current_interaction()


## A skill the member does not own, selected straight on the loop (capture only: the preview
## reads the selected skill; nothing is cast).
func _footprint_shape(id: String, channel: String, skill_id: String, offset: Vector2i, label: String) -> void:
	var saved: Dictionary = scene.play_loop.duplicate(true)
	Loop._unit(scene.play_loop, id)["stamina"] = 99
	scene.apply_loop(scene.play_loop, "test")
	await _give_turn(id)
	scene.menus.choose_command(channel)
	scene.menus.set_action_menu_visible(false)
	scene.magic_panel.hide()
	var next: Dictionary = scene.play_loop.duplicate(true)
	next.merge({"interaction": "attack_select", "selected_attack": channel, "selected_skill_id": skill_id}, true)
	scene.apply_loop(next, "test")
	scene.mirror_interaction()
	scene.overlays.refresh_attack_overlay()
	var origin: Vector2i = Loop.unit(scene.play_loop, id)["coord"]
	await _hover(origin + offset)
	check(not scene.overlays.footprint_cells.is_empty(), "%s draws a footprint" % skill_id)
	await shot(label)
	scene.cancel_current_interaction()
	scene.magic_panel.hide()
	scene.apply_loop(saved, "test")
	scene.mirror_interaction()
	scene.overlays.clear_attack_overlay()


func _final_blow_growth() -> void:
	var loop: Dictionary = scene.play_loop
	var tina: Dictionary = Loop._unit(loop, "tina")
	tina["exp"] = Loop.ProgressionRules.exp_to_next(int(tina["level"])) - 1
	tina["hit_bonus_accum"] = 1000
	var foe_id := ""
	for unit in loop["units"]:
		if unit["battle_actor_role"] != Loop.ROLE_ENEMY or not Loop.Presence.living(unit): continue
		if foe_id == "" and Loop.unit_id_at_coord(loop, tina["coord"] + Vector2i.RIGHT) in ["", str(unit["id"])]:
			foe_id = str(unit["id"])
			unit["hp"] = 1
			unit["coord"] = tina["coord"] + Vector2i.RIGHT
		else:
			Loop._set_unit_defeated(loop, str(unit["id"]), true)
	scene.apply_loop(loop, "test")
	await _give_turn("tina")
	scene.menus.choose_command("attack")
	scene.attack_selected_target(foe_id)
	var view = scene.get_node("BattlePresentation")
	for frame in range(1800):
		if view.dialogue_active(): view.advance_dialogue()
		if Loop.loot_waiting(scene.play_loop):
			var settlement: Dictionary = scene.play_loop["settlement"]
			scene.apply_loop(Loop.finish_rewards(scene.play_loop, int(settlement["sequence"]), int(settlement["revision"]), false, true), "test")
		if scene.growth_panel.visible or view.battle_finished: break
		await process_frame
	# Level 3 scans win／fail at the action's end (as the original's 0x407510), so the victory is
	# committed after the window closes; a battle decided at the strike holds its result the same way.
	check(scene.growth_panel.visible and not view.battle_finished, "the final blow's window opens before the result (foe %s outcome %s)" % [foe_id, str(scene.play_loop.get("battle_outcome"))])
	await create_timer(0.4).timeout
	await shot("07-final-blow-level-up-window")
	for _point in range(int(scene.growth_panel.source_unit.get("pending_stat_points", 0))):
		scene.growth_panel.choices["con"]["plus"].pressed.emit()
	scene.growth_panel.confirm_button.pressed.emit()
	var coordinator = scene.opening_coordinator
	for frame in range(3600):
		if view.battle_finished: break
		if coordinator != null and coordinator.active:
			if str(coordinator.summary().get("current_event_kind", "")) in ["dialogue_message_id", "section_title_resource"]:
				var click := InputEventMouseButton.new()
				click.button_index = MOUSE_BUTTON_LEFT
				click.pressed = true
				coordinator.handle_input(click)
		elif view.dialogue_active():
			view.advance_dialogue()
		elif Loop.loot_waiting(scene.play_loop):
			# The victory reopens the deferred get-item window before the result; 稍後.
			var pending: Dictionary = scene.play_loop["settlement"]
			scene.apply_loop(Loop.finish_rewards(scene.play_loop, int(pending["sequence"]), int(pending["revision"]), false, true), "test")
		await process_frame
	check(view.battle_finished and preload("res://game/sim/BattleOutcome.gd").won(scene.play_loop), "the victory result follows the closed window")
	await create_timer(0.4).timeout
	await shot("08-victory-result-after-window")


## The action ring may still be settling in a windowed run; retry until skill targeting opens.
func _choose(command: String, skill_id: String) -> void:
	for attempt in range(20):
		scene.menus.choose_command(command)
		scene.menus._choose_magic(skill_id)
		if scene.interaction_state == "attack_select": return
		scene.cancel_current_interaction()
		await create_timer(0.2).timeout
	check(false, "could not enter %s targeting (%s)" % [command, scene.interaction_state])


func _hover(cell: Vector2i) -> void:
	scene.center_camera_on_grid(cell)
	await create_timer(0.3).timeout
	var point: Vector2 = scene.grid_cell_center_to_logical_position(cell)
	scene.pointer_inside_window = false # no edge scroll while the capture rests
	scene.scene_input.handle_pointer_motion(point)
	await create_timer(0.4).timeout
	scene.scene_input.handle_pointer_motion(point)
	await process_frame


func shot(label: String) -> void:
	await process_frame
	RenderingServer.force_draw(false)
	check(root.get_texture().get_image().save_png(OUT + label + ".png") == OK, "capture " + label)


func check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)
		push_error(label)
