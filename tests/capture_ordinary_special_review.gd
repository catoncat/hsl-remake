extends "res://tests/capture_support_magic_review.gd"
## Actual controls and normal presentation clocks for the native physical/Qi chain.
const run_ordinary_special_tests = preload("res://tests/run_ordinary_special_tests.gd")
const BattleOutcome = preload("res://game/sim/BattleOutcome.gd")
const DEST := "res://ignored/ordinary-special-review/"
var observed := {}
var sound_paths := {}
var cues: Array = []
var experience_events: Array = []
var receipt := {}


func run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Ordinary/special review needs a rendered built-in-display window")
		quit(2)
		return
	root.title = "HSL Native Ordinary & Qi Blade"
	root.size = Vector2i(640,480)
	root.position = DisplayServer.screen_get_position(root.current_screen) + Vector2i(60,80)
	DirAccess.make_dir_recursive_absolute(DEST)
	create_timer(300).timeout.connect(func():push_error("ORDINARY_SPECIAL_REVIEW_TIMEOUT");quit(2))
	var names: Array = ["ordinary", "critical_kill", "counter", "elemental_equipment", "critical_equipment", "special", "special_silenced", "insufficient", "final_kill"]
	if not OS.get_cmdline_user_args().is_empty(): names = Array(OS.get_cmdline_user_args())
	for name in names:
		mode = name
		await prepare_case()
		await play_case()
		await close_scene()
		if not failures.is_empty(): break
	FileAccess.open(DEST + "receipt.json",FileAccess.WRITE).store_string(JSON.stringify({
		"fixture":true,"native_execution":false,"real_control_events":true,"normal_clock":Engine.time_scale,
		"overrides":"Three source-rendered actors; explicit positions, speeds, HP500 (1HP lethal targets), source-compatible growth and inventory fixture6/7/216. Actual WRD retained. Ordinary accuracy100 and controlled effective counter/critical rates0/100 for reproducible branch observation; equipment routes use the actual refreshed rates. Special hit100 in success routes. Critical kill starts at99EXP and chain1; final kill after report, no reinforcements. No RNG replacement, direct result assignment or clock acceleration. Default first-battle values and grants are unchanged.",
		"screen":root.current_screen,"window_position":root.position,"window_size":root.size,"routes":routes,"failures":failures},"  "))
	print("ORDINARY_SPECIAL_RENDER_", "PASS" if failures.is_empty() else "FAIL", " routes=",routes.size())
	quit(0 if failures.is_empty() else 1)


func prepare_case() -> void:
	observed = {}
	sound_paths = {}
	cues = []
	experience_events = []
	receipt = {}
	scene = load("res://game/battle/scene/BattleSceneRuntime.tscn").instantiate()
	scene.scenario_path = BattleFixture.PATH; scene.startup_mode = "dev_first_control"
	root.add_child(scene)
	current_scene = scene
	scene.start_dev_first_control_harness()
	scene.set_process(false)
	await create_timer(0.15).timeout
	scene.get_node("BattleMusic").stop()
	var loop := run_ordinary_special_tests.fixture()
	loop["tiles"] = scene.play_loop["tiles"]
	loop["map_size"] = scene.play_loop["map_size"]
	for unit in loop["units"]: unit["hp"] = 500; unit["max_hp"] = 500
	var owner := BattlePlayLoop.unit_ref(loop,"leonard")
	var target := BattlePlayLoop.unit_ref(loop,"enemy021_1")
	if mode in ["ordinary","critical_kill"]: owner["combat_profile"]["attack_damagex2"] = 100
	if mode == "counter": target["combat_profile"].merge({"attack_damagex2":100,"attack_back":100},true)
	if mode.ends_with("equipment"): owner["inventory"] = [6,7,216,0,0,0,0,0]
	if mode in ["critical_kill","final_kill"]:
		target["hp"] = 1
		owner["exp"] = 99
		owner["kill_chain_word"] = 1
	if mode.begins_with("special") or mode == "final_kill":
		BattlePlayLoop.skill_fields(loop,"special:magicOTHER:magicCode01")["hit_ratio"] = "100"
		target["combat_profile"]["live_defense"] = 10000
	if mode == "special_silenced": owner.merge(BattlePlayLoop.StatusEffectRules.apply(owner,"no_magic",2)["changes"],true)
	if mode == "insufficient": owner["stamina"] = 19
	if mode == "final_kill":
		loop["units"] = loop["units"].filter(func(unit):return unit["id"] in ["leonard","enemy021_1"])
		loop["turn"] = 6
		scene.get_node("BattlePresentation")._shown_story_events.assign(loop["event_log"])
	loop["turn_queue"] = BattlePlayLoop.CoreTurnQueue.rebuild(loop["units"])
	scene.apply_loop(BattlePlayLoop.return_to_player(loop,"leonard"), "test")
	scene.settlement_controller.checkpoint_path = DEST + mode + ".save"
	for actor in scene.actors_root.get_children(): scene.actors_root.remove_child(actor); actor.queue_free()
	scene.unit_grid_coords.clear()
	for unit in scene.play_loop["units"]: unit["grid_coord"] = unit["coord"]
	scene.resume_turn_presentation()
	scene.center_camera_on_grid(Vector2i(9,8))
	var view = scene.get_node("BattlePresentation")
	view.experience_presented.connect(func(growth):experience_events.append(growth.duplicate(true)))
	view.cutin.released.connect(func(_s,_a,_d,c):cues.append({"phase":"release","counter":c}))
	view.cutin.impact.connect(func(_s,_a,_d,c):cues.append({"phase":"impact","counter":c}))
	scene.set_process(true)
	await create_timer(0.3).timeout


func play_case() -> void:
	if mode.ends_with("equipment"):
		await equip(6,true)
		if mode == "critical_equipment":
			await equip(7,false)
			await equip(216,false)
		var owner := BattlePlayLoop.unit(scene.play_loop,"leonard")
		check(owner["combat_profile"]["weapon_magic_attack_type"] == (2 if mode == "elemental_equipment" else -1), "actual replacement sets/clears weapon element")
		check(owner["combat_profile"]["attack_damagex2"] == (14 if mode == "elemental_equipment" else 40), "actual equipped working critical rate includes source and all modifiers")
	var before: Dictionary = scene.play_loop.duplicate(true)
	var special := mode.begins_with("special") or mode in ["final_kill","insufficient"]
	var control: Control = scene.action_menu.get_node("SpecialCommand" if special else "AttackCommand")
	if mode == "insufficient":
		# 19ST still opens the skill page (the original opens it with the gauge empty); the row it cannot pay is disabled.
		check(not control.disabled and not BattlePlayLoop.can_use_special(scene.play_loop,"leonard"),"19ST opens the actual skill page but cannot pay it")
		await click(control)
		check(scene.magic_panel.visible and scene.magic_panel.choices["special:magicOTHER:magicCode01"].disabled,"19ST keeps the page row disabled")
		await click(scene.magic_panel.choices["special:magicOTHER:magicCode01"])
		check(scene.play_loop["units"] == before["units"] and cues.is_empty(),"disabled click creates no payment, EXP or presentation")
		await shot("disabled")
		await escape()
		await create_timer(0.3).timeout # the menu re-expands after the page closes
		await click(scene.action_menu.get_node("WaitCommand"))
		await await_control("enemy023_1")
	else:
		await click(control)
		if scene.play_loop["interaction"] == "special_select": await click(scene.magic_panel.choices["special:magicOTHER:magicCode01"])
		await hover(scene.grid_cell_center_to_logical_position(BattlePlayLoop.unit(scene.play_loop,"enemy021_1")["coord"]))
		check(scene.interaction_state == "attack_select" and scene.get_node("BattlePresentation").target_vitals.visible,"real map targeting exposes live target information")
		await shot("target")
		await escape()
		check(scene.play_loop["units"] == before["units"] and scene.play_loop["turn_queue"] == before["turn_queue"],"cancel preserves resources, status, damage and queue")
		await create_timer(0.3).timeout
		await click(scene.action_menu.get_node("SpecialCommand" if special else "AttackCommand"))
		if scene.play_loop["interaction"] == "special_select": await click(scene.magic_panel.choices["special:magicOTHER:magicCode01"])
		await point(scene.grid_cell_center_to_logical_position(BattlePlayLoop.unit(scene.play_loop,"enemy021_1")["coord"]))
		receipt = scene.play_loop["last_attack"].duplicate(true)
		check(receipt.get("attacker_id") == "leonard" and receipt.has("actual_damage"),"real target click produces one native transaction")
		if not receipt.has("actual_damage"): return
		await await_control("enemy023_1",mode == "final_kill")
		check(cues == ([{"phase":"release","counter":false},{"phase":"impact","counter":false},{"phase":"release","counter":true},{"phase":"impact","counter":true}] if mode == "counter" else [{"phase":"release","counter":false},{"phase":"impact","counter":false}]), "each strike emits exactly one ordered release/impact")
		if receipt.has("experience"):
			check(experience_events.size() == 1 and experience_events[0] == receipt["experience"],"the final player EXP is displayed once after the complete exchange")
		else:
			check(not receipt["hit"] and receipt["actual_damage"] == 0 and experience_events.is_empty(),"source equipment's legitimate miss has no fabricated EXP")
		check(not sound_paths.is_empty(),"actual source audio playback advances during this route")
		if mode == "critical_kill": check(receipt["critical"] and receipt["actual_damage"] == 1 and observed.has("growth"),"critical overkill displays1HP and leads through earned growth")
		if mode == "counter": check(receipt["counter"]["critical"] and observed.has("counter-impact"),"real normal-clock counter shows its own critical impact")
		if special: check(BattlePlayLoop.unit(scene.play_loop,"leonard")["stamina"] == 0 and receipt["actual_damage"] > 0,"special pays20 once and ignores physical defense, including under silence")
		if mode == "elemental_equipment": check(receipt["damage_detail"]["variance_bonus"] > 0,"newly equipped source wind bonus enters the actual physical strike")
		if mode == "critical_equipment": check(receipt["critical_rate"] == 40,"actual strike uses the refreshed40 percent rate")
		if mode == "final_kill":
			var saved: Dictionary = scene.play_loop.duplicate(true)
			await key(KEY_F5)
			await key(KEY_F9)
			check(scene.play_loop == saved and scene.get_node("BattlePresentation").battle_finished,"terminal save/load preserves the complete native award without replay")
			await shot("restored-victory")
		else:
			check(scene.play_loop["turn_queue"]["index"] == 1,"full action reaches the exact controllable successor")
			await shot("handoff")
		if mode == "ordinary":
			var initial_sequence: int = scene.play_loop["last_combat"]["sequence"]
			var initial_round: int = scene.play_loop["turn_queue"]["round"]
			await click(scene.action_menu.get_node("WaitCommand"))
			await await_control("leonard")
			check(scene.play_loop["last_combat"]["sequence"] == initial_sequence + 1 and scene.play_loop["turn_queue"]["round"] == initial_round + 1,"actual successor Wait and one enemy action reach the next round")
			await shot("next-round")
	var owner := BattlePlayLoop.unit(scene.play_loop,"leonard")
	routes.append({"mode":mode,"receipt":receipt,"actor":compact(owner),"exp":owner["exp"],"level":owner["level"],"observed":observed,"sounds":sound_paths.keys(),"cues":cues,"outcome":scene.play_loop["battle_outcome"],"next_actor":scene.selected_unit_id})


func await_control(id: String, terminal: bool = false) -> void:
	for _attempt in range(1800):
		var view = scene.get_node("BattlePresentation")
		for sound in scene.find_children("*","AudioStreamPlayer",true,false):
			if sound.playing and sound.stream != null and sound.get_playback_position() > 0: sound_paths[sound.stream.resource_path] = true
		if view.cutin.busy():
			var clip: Dictionary = view.cutin.clips[0]
			var tag := ("counter-" if clip["counter"] else "primary-") + ("impact" if clip["impact_emitted"] else "windup")
			if not observed.has(tag):
				observed[tag] = true
				check(not scene.action_menu.visible and not view.aftermath.reward_label.visible,"commands and EXP wait for complete strike feedback")
				await shot(tag)
			# The number spawns after the hit (ordinary: 40 ticks; a miss spawns none).
			if clip["impact_emitted"] and not observed.has(tag + "-number") and view.cutin.result_number.visible and view.cutin.result_number.get_children().any(func(number): return number.showing()):
				observed[tag + "-number"] = true
				check(view.cutin.result_text().split("\n")[0] == ("%d" % clip["strike"]["actual_damage"] if clip["strike"]["hit"] else "MISS"),"visible number matches actual HP delta, alone")
		if view.dialogue_active():
			if not observed.has("dialogue"): observed["dialogue"] = true; await shot("dialogue")
			await key(KEY_SPACE)
		if view.aftermath.reward_label.visible and not observed.has(view.aftermath.stage):
			observed[view.aftermath.stage] = true
			check(not view.cutin.busy(),"EXP/gold appear only after all strike clips")
			await shot(view.aftermath.stage)
		var loot = scene.settlement_controller.panel
		if loot.visible:
			if not loot.rows.is_empty() and loot.first_empty_slot() >= 0: await click(loot.rows[0]); await click(loot.slots[loot.first_empty_slot()])
			else: await click(loot.finish_button)
		if scene.growth_panel.visible:
			if not observed.has("growth"): observed["growth"] = true; await shot("growth")
			for attribute in ["str","str","dex","mind","con"]: await click(scene.growth_panel.choices[attribute]["plus"])
			await click(scene.growth_panel.confirm_button)
		if terminal and view.battle_finished:
			check(BattleOutcome.won(scene.play_loop) and observed.has("experience"),"final kill plays earned EXP before victory")
			await shot("victory")
			return
		if not terminal and scene.selected_unit_id == id and scene.action_menu.is_visible_in_tree() and not scene.ai_playback_active and not view.combat_busy(scene.play_loop) and not scene.action_menu.is_expanding(): return
		await create_timer(0.02).timeout
	check(false,"bounded native combat route reaches expected control/result")


func equip(code: int, cancel_first: bool) -> void:
	await create_timer(0.3).timeout
	await click(scene.action_menu.get_node("ItemCommand"))
	await create_timer(0.3).timeout
	await click(scene.item_panel.menu.get_node("EquipCommand"))
	await click(item_button(code))
	if code == 216: await click(find_button(scene.item_panel.page_root,"飾品 1"))
	check(scene.item_panel.page == "equip_confirm" and not scene.item_panel.confirm_button.disabled,"source elemental/critical equipment has a usable confirmation")
	var before: Dictionary = scene.play_loop.duplicate(true)
	if cancel_first:
		await click(find_button(scene.item_panel.page_root,"取消"))
		check(scene.play_loop == before,"actual equipment cancellation preserves the sole battle state")
		await click(item_button(code))
	var scroll: ScrollContainer
	for child in scene.item_panel.page_root.get_children():
		if child is ScrollContainer: scroll = child
	check(scroll != null,"long source effect previews remain inside their own scroll area")
	if scroll != null:
		for _scroll in range(12):
			var bar := scroll.get_v_scroll_bar()
			if bar.value >= bar.max_value - bar.page: break
			await hover(scroll.get_global_rect().get_center())
			var wheel := InputEventMouseButton.new()
			wheel.position = scroll.get_global_rect().get_center()
			wheel.button_index = MOUSE_BUTTON_WHEEL_DOWN
			wheel.pressed = true
			root.push_input(wheel,true)
			wheel = wheel.duplicate(); wheel.pressed = false; root.push_input(wheel,true)
			await process_frame
		check(scroll.get_v_scroll_bar().value >= scroll.get_v_scroll_bar().max_value - scroll.get_v_scroll_bar().page,"actual wheel reaches the last source effect line")
		check(not scroll.get_global_rect().intersects(scene.item_panel.confirm_button.get_global_rect()),"preview and native confirm control cannot overlap")
	await shot("equip-%d" % code)
	await click(scene.item_panel.confirm_button)
	await create_timer(0.3).timeout
	check(not scene.item_panel.visible and scene.play_loop["turn_queue"] == before["turn_queue"],"confirmed equipment closes freely without handing off the action")


func item_button(code: int) -> Control:
	for child in scene.item_panel.rows.get_children():
		if child.get_meta("item_code","") == str(code): return child
	check(false,"source equipment row exists")
	return null


func find_button(node: Node, caption: String) -> Control:
	if node is Button and node.text == caption: return node
	for child in node.get_children():
		var found := find_button(child,caption)
		if found != null: return found
	return null


func key(code: Key) -> void:
	var event := InputEventKey.new(); event.keycode = code; event.pressed = true
	root.push_input(event,true)
	event = event.duplicate(); event.pressed = false; root.push_input(event,true)
	await process_frame
	await process_frame


func shot(label: String) -> void:
	await process_frame
	RenderingServer.force_draw(false)
	check(root.get_texture().get_image().save_png(DEST + mode + "-" + label + ".png") == OK,"capture " + label)
