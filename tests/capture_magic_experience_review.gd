extends "res://tests/capture_support_magic_review.gd"
## Reuses actual mouse/scroll/keyboard and bounded audio cleanup from the support
## capture, not its fixture or assertions. All new battle setup is declared here.
const run_magic_experience_tests = preload("res://tests/run_magic_experience_tests.gd")
const DEST := "res://ignored/magic-experience-review/"
var phases := {}
var experience_events: Array = []
var expected_receipt: Dictionary = {}


func run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Magic/EXP review needs a built-in-display rendered window")
		quit(2)
		return
	root.title = "HSL Native Magic & Experience"
	root.size = Vector2i(640, 480)
	root.position = DisplayServer.screen_get_position(root.current_screen) + Vector2i(60, 80)
	DirAccess.make_dir_recursive_absolute(DEST)
	create_timer(180).timeout.connect(func(): push_error("MAGIC_EXPERIENCE_REVIEW_TIMEOUT"); quit(2))
	var names: Array = ["wind", "fire_kill", "mixed_area", "heal_xp", "cure_xp", "empty_mp", "silence", "final_kill"]
	if not OS.get_cmdline_user_args().is_empty(): names = Array(OS.get_cmdline_user_args())
	for name in names:
		mode = name
		phases = {}
		experience_events = []
		expected_receipt = {}
		await prepare_case()
		await play_case()
		await close_scene()
		if not failures.is_empty(): break
	FileAccess.open(DEST + "receipt.json", FileAccess.WRITE).store_string(JSON.stringify({
		"fixture": true, "native_execution": false, "normal_clock": Engine.time_scale,
		"actual_input": "Inherited Viewport.push_input mouse, wheel and key events; no combat RNG replacement or result assignment",
		"overrides": "Four source-rendered actors with fixed positions/speed and no reinforcements; Leonard explicitly granted test magic and compatible synthetic 100MP source growth; HP100 enemies except declared 1HP kills; controlled successor. Base skill hit_ratio100 for this deterministic success capture. Mixed-area fire has synthetic range1Cell, not original Wind/Fire geometry. Cure adds poison to two allies and silence to the recipient. Fire-kill carries guaranteed important loot; final route starts after report with one enemy. Original default grants and values are unchanged.",
		"screen": root.current_screen, "window_position": root.position, "window_size": root.size,
		"routes": routes, "failures": failures}, "  "))
	print("MAGIC_EXPERIENCE_RENDER_", "PASS" if failures.is_empty() else "FAIL", " routes=", routes.size())
	quit(0 if failures.is_empty() else 1)


func prepare_case() -> void:
	scene = load("res://game/battle/scene/BattleSceneRuntime.tscn").instantiate()
	scene.scenario_path = BattleFixture.PATH; scene.startup_mode = "dev_first_control"
	root.add_child(scene)
	current_scene = scene
	scene.start_dev_first_control_harness()
	scene.set_process(false)
	await create_timer(0.15).timeout
	scene.get_node("BattleMusic").stop()
	var loop := run_magic_experience_tests.fixture()
	loop["tiles"] = scene.play_loop["tiles"]
	loop["map_size"] = scene.play_loop["map_size"]
	var owner := BattlePlayLoop._unit(loop, "leonard")
	owner["exp"] = 0 if mode in ["wind", "empty_mp", "silence"] else 99
	owner["kill_chain_word"] = 1 if mode == "fire_kill" else 0
	for id in [run_magic_experience_tests.WIND, run_magic_experience_tests.FIRE]: BattlePlayLoop.skill_fields(loop, id)["hit_ratio"] = "100"
	for unit in loop["units"]: unit["inventory"] = [0, 0, 0, 0, 0, 0, 0, 0]
	if mode in ["fire_kill", "final_kill"]:
		BattlePlayLoop._unit(loop, "enemy021_1")["hp"] = 1
		BattlePlayLoop._unit(loop, "enemy021_1")["inventory"][0] = 281
	if mode == "mixed_area":
		BattlePlayLoop.skill_fields(loop, run_magic_experience_tests.FIRE)["effect_range"] = "range1Cell"
		BattlePlayLoop._unit(loop, "enemy021_2")["hp"] = 1
	if mode == "cure_xp":
		for unit in [owner, BattlePlayLoop._unit(loop, "enemy023_1")]: unit.merge(BattlePlayLoop.StatusEffectRules.apply(unit, "poison", 2, 10)["changes"], true)
		var target := BattlePlayLoop._unit(loop, "enemy023_1")
		target.merge(BattlePlayLoop.StatusEffectRules.apply(target, "no_magic", 2)["changes"], true)
	if mode == "empty_mp": owner["mp"] = 0
	if mode == "silence": owner.merge(BattlePlayLoop.StatusEffectRules.apply(owner, "no_magic", 2)["changes"], true)
	if mode == "final_kill":
		loop["units"] = loop["units"].filter(func(unit): return unit["id"] in ["leonard", "enemy021_1"])
		loop["turn"] = 6
		var view = scene.get_node("BattlePresentation")
		view._shown_story_events.assign(loop["event_log"])
	loop["turn_queue"] = BattlePlayLoop.CoreTurnQueue.rebuild(loop["units"])
	scene.apply_loop(BattlePlayLoop._return_to_player(loop, "leonard"), "test")
	scene.settlement_controller.checkpoint_path = DEST + mode + ".save"
	for actor in scene.actors_root.get_children(): scene.actors_root.remove_child(actor); actor.queue_free()
	scene.unit_grid_coords.clear()
	for unit in scene.play_loop["units"]: unit["grid_coord"] = unit["coord"]
	scene.resume_turn_presentation()
	scene.center_camera_on_grid(Vector2i(9, 8))
	scene.get_node("BattlePresentation").experience_presented.connect(func(growth): experience_events.append(growth.duplicate(true)))
	scene.set_process(true)
	await create_timer(0.3).timeout


func play_case() -> void:
	var id: String = run_magic_experience_tests.WIND if mode == "wind" else run_magic_experience_tests.HEAL if mode == "heal_xp" else run_magic_experience_tests.CURE if mode == "cure_xp" else run_magic_experience_tests.FIRE
	var target := "enemy023_1" if mode in ["heal_xp", "cure_xp"] else "enemy021_1"
	var before: Dictionary = scene.play_loop.duplicate(true)
	await click(scene.action_menu.get_node("MagicCommand"))
	check(scene.magic_panel.visible and scene.magic_panel.choices.has(id), "actual spell list opens")
	if mode in ["empty_mp", "silence"]:
		check(scene.magic_panel.choices[id].disabled, "unaffordable/silenced native spell is visibly disabled")
		await click(scene.magic_panel.choices[id])
		check(scene.play_loop["units"] == before["units"] and scene.play_loop.get("last_combat", {}) == before.get("last_combat", {}), "disabled click has no damage, EXP, MP or sequence side effects")
		await shot("disabled")
		await escape()
		await create_timer(0.25).timeout
		await click(scene.action_menu.get_node("WaitCommand"))
		await create_timer(0.4).timeout
		check(scene.selected_unit_id == "enemy023_1" and experience_events.is_empty(), "normal Wait remains usable with no fabricated EXP")
	else:
		await click(scene.magic_panel.choices[id])
		await hover(scene.grid_cell_center_to_logical_position(BattlePlayLoop.unit(scene.play_loop, target)["coord"]))
		check(scene.interaction_state == "attack_select" and scene.get_node("BattlePresentation").target_vitals.visible, "actual map preview uses the selected native skill")
		await shot("preview")
		await escape()
		check(scene.play_loop["units"] == before["units"] and scene.play_loop["turn_queue"] == before["turn_queue"], "target cancellation does not debit or award")
		await create_timer(0.25).timeout
		await click(scene.action_menu.get_node("MagicCommand"))
		await click(scene.magic_panel.choices[id])
		await point(scene.grid_cell_center_to_logical_position(BattlePlayLoop.unit(scene.play_loop, target)["coord"]))
		expected_receipt = scene.play_loop["last_attack"].duplicate(true)
		check(expected_receipt.get("skill_id") == id and expected_receipt.has("experience"), "actual click commits one native effect and final EXP award")
		if not expected_receipt.has("experience"): return
		await await_settlement()
		check(experience_events.size() == 1 and experience_events[0] == expected_receipt["experience"], "final earned EXP is presented once after the complete cast")
		check(scene.play_loop["last_combat"]["sequence"] == expected_receipt["sequence"], "presentation never replays the cast")
		if mode == "mixed_area":
			check(expected_receipt["affected_targets"].size() == 2 and BattlePlayLoop.unit(scene.play_loop, "enemy021_1")["hp"] > 0 and BattlePlayLoop.unit(scene.play_loop, "enemy021_2")["hp"] == 0, "mixed multi-target survivor/kill settle together")
		if mode == "cure_xp":
			check(expected_receipt["affected_targets"].size() == 2 and BattlePlayLoop.unit(scene.play_loop, target)["status_counters"] == {"poison": 0, "paralysis": 0, "no_magic": 2}, "two real cure contributions preserve recipient silence")
		var earned := BattlePlayLoop.unit(scene.play_loop, "leonard")
		var saved: Dictionary = scene.play_loop.duplicate(true)
		await key(KEY_F5)
		check(FileAccess.file_exists(scene.settlement_controller.checkpoint_path), "actual F5 saves awarded EXP and growth")
		await key(KEY_F9)
		check(scene.play_loop == saved and BattlePlayLoop.unit(scene.play_loop, "leonard")["exp"] == earned["exp"], "actual F9 does not re-award contribution, kill count, MP or loot")
		if mode == "final_kill":
			check(scene.get_node("BattlePresentation").battle_finished and earned["pending_stat_points"] > 0, "final kill retains earned growth even at victory")
			await shot("restored-result")
		else:
			await point(scene.grid_cell_center_to_logical_position(earned["coord"]))
			check(scene.status_panel.visible and scene.status_panel.vitals.values["exp"].text.begins_with(str(earned["exp"]) + " /"), "normal post-cast inspection reports the final EXP")
			await shot("status")
	routes.append({"mode": mode, "receipt": expected_receipt, "actor": compact(BattlePlayLoop.unit(scene.play_loop, "leonard")),
		"exp": BattlePlayLoop.unit(scene.play_loop, "leonard")["exp"], "level": BattlePlayLoop.unit(scene.play_loop, "leonard")["level"],
		"pending_points": BattlePlayLoop.unit(scene.play_loop, "leonard")["pending_stat_points"], "phases": phases,
		"outcome": scene.play_loop["battle_outcome"], "next_actor": scene.selected_unit_id, "experience_events": experience_events})


func await_settlement() -> void:
	for _attempt in range(1200):
		var view = scene.get_node("BattlePresentation")
		if view.magic_impact.busy():
			var phase: String = "receiver-bars" if view.magic_impact.entries[0]["panel"].visible else "damage-number"
			if not phases.has(phase):
				phases[phase] = true
				for entry in view.magic_impact.entries:
					check(entry["panel"].get_child(0).size == Vector2(42, 7), "map HP bar remains a seven-pixel strip under the real theme")
				check(not scene.action_menu.visible and not view.aftermath.reward_label.visible and not view.dialogue_active(), "receiver stage excludes early EXP, dialogue or controls")
				await shot(phase)
		if view.cutin.busy() and view.cutin.clips[0]["impact_emitted"] and mode in ["heal_xp", "cure_xp"] and not phases.has("support"):
			phases["support"] = true
			await shot("support")
		if view.dialogue_active():
			if not phases.has("last-words"):
				phases["last-words"] = true
				await shot("last-words")
			await key(KEY_SPACE)
		if view.aftermath.reward_label.visible and not phases.has(view.aftermath.stage):
			phases[view.aftermath.stage] = true
			if view.aftermath.stage == "experience":
				check(view.aftermath.reward_label.text.contains("EXP %d" % expected_receipt["experience"]["gained"]), "visible EXP is the final native converted amount")
				check(not view.cutin.busy() and not view.magic_impact.busy(), "EXP appears after all hit feedback")
			await shot(view.aftermath.stage)
		var loot = scene.settlement_controller.panel
		if loot.visible:
			if not phases.has("loot"): phases["loot"] = true; await shot("loot")
			if not loot.rows.is_empty() and loot.first_empty_slot() >= 0:
				await click(loot.rows[0])
				await click(loot.slots[loot.first_empty_slot()])
			else: await click(loot.finish_button)
		if scene.growth_panel.visible:
			if not phases.has("growth"): phases["growth"] = true; await shot("growth")
			if mode == "fire_kill":
				for attribute in ["str", "str", "dex", "mind", "con"]: await click(scene.growth_panel.choices[attribute]["plus"])
				await click(scene.growth_panel.confirm_button)
				check(BattlePlayLoop.unit(scene.play_loop, "leonard")["pending_stat_points"] == 0, "actual five-point growth confirmation consumes the native award's budget once")
			else: scene.growth_panel.hide() # harness skip seam
		if mode == "final_kill" and view.battle_finished:
			check(phases.has("experience") and phases.has("loot"), "final EXP and loot both precede the victory result")
			return
		if mode != "final_kill" and scene.selected_unit_id == "enemy023_1" and scene.action_menu.is_visible_in_tree() and not view.combat_busy(scene.play_loop) and not scene.action_menu.is_expanding():
			check(scene.play_loop["turn_queue"]["index"] == 1, "one complete cast reaches the exact next actor")
			return
		await create_timer(0.025).timeout
	check(false, "bounded cast/EXP route reached its expected next control or result")


func key(code: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.pressed = true
	root.push_input(event, true)
	event = event.duplicate()
	event.pressed = false
	root.push_input(event, true)
	await process_frame
	await process_frame


func shot(label: String) -> void:
	await process_frame
	RenderingServer.force_draw(false)
	check(root.get_texture().get_image().save_png(DEST + mode + "-" + label + ".png") == OK, "capture " + label)
