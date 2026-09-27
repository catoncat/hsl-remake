extends "res://tests/capture_ordinary_special_review.gd"
## Equipment, map selection and restoration through actual controls and clocks.
const run_position_equipment_tests = preload("res://tests/run_position_equipment_tests.gd")
const MobilityRules = preload("res://game/sim/MobilityRules.gd")
const BattleLoopAI = preload("res://game/sim/loop/BattleLoopAI.gd")
const OUTPUT := "res://ignored/equipment-mobility-review/"
var changes: Array = []
var landing := Vector2i.ZERO
var original_foot := 0


func run() -> void:
	if DisplayServer.get_name() == "headless": push_error("Mobility review needs a rendered built-in window"); quit(2); return
	root.title = "HSL Equipment Mobility Review"
	root.size = Vector2i(640,480)
	root.position = DisplayServer.screen_get_position(root.current_screen) + Vector2i(60,80)
	DirAccess.make_dir_recursive_absolute(OUTPUT)
	create_timer(300).timeout.connect(func():push_error("MOBILITY_REVIEW_TIMEOUT");quit(2))
	var names: Array = ["equip_growth","pending_restore","ai_without","ai_boots","victory","defeat","escape"]
	if not OS.get_cmdline_user_args().is_empty(): names = Array(OS.get_cmdline_user_args())
	for name in names:
		mode = name
		await setup_mobility()
		if failures.is_empty(): await play_mobility()
		await close_scene()
		FileAccess.open(OUTPUT+"progress.json",FileAccess.WRITE).store_string(JSON.stringify({"routes":routes,"failures":failures},"  "))
		if not failures.is_empty(): break
	FileAccess.open(OUTPUT+"receipt.json",FileAccess.WRITE).store_string(JSON.stringify({
		"fixture":true,"native_execution":false,"real_control_events":true,"time_scale":Engine.time_scale,
		"overrides":"Three source-rendered actors on the actual WRD, initial HP/maxHP100, ordinary fixture STR/DEX20 attack20 defense0 hit100 critical/counter0, reordered speeds and controllable successor. Gear193/138/231/231 explicitly added to test inventory; source base5 remains. Actual player equipment uses native refresh and its real derived stats/probabilities. Growth/final-clear target1HP and caster99EXP, targetDEX1 ensure source hit gate rather than injected RNG. Defeat sets player1HP/enemyattack200. AI test gear prepared with same source mobility, positions selected by legal native-cost envelopes. Escape/final-clear begin after report. No change to default source grants, no RNG replacement, assigned damage/result, or accelerated clocks.",
		"screen":root.current_screen,"window_position":root.position,"window_size":root.size,"routes":routes,"failures":failures},"  "))
	print("EQUIPMENT_MOBILITY_RENDER_","PASS" if failures.is_empty() else "FAIL"," routes=",routes.size())
	quit(0 if failures.is_empty() else 1)


func setup_mobility() -> void:
	observed = {}; changes = []; cues = []; sound_paths = {}; experience_events = []; receipt = {}
	scene = load("res://game/battle/scene/BattleSceneRuntime.tscn").instantiate()
	scene.scenario_path = BattleFixture.PATH; scene.startup_mode = "dev_first_control"
	root.add_child(scene); current_scene = scene
	scene.start_dev_first_control_harness()
	scene.set_process(false)
	await create_timer(0.15).timeout
	scene.get_node("BattleMusic").stop()
	var loop := run_position_equipment_tests.mobility_fixture()
	loop["tiles"] = scene.play_loop["tiles"]
	loop["map_size"] = scene.play_loop["map_size"]
	var player := BattlePlayLoop.unit_ref(loop,"leonard")
	var enemy := BattlePlayLoop.unit_ref(loop,"enemy021_1")
	var ally := BattlePlayLoop.unit_ref(loop,"enemy023_1")
	player["coord"] = Vector2i(8,8); enemy["coord"] = Vector2i(9,8); ally["coord"] = Vector2i(17,19)
	player["live_speed"] = 120; ally["live_speed"] = 100; enemy["live_speed"] = 90
	original_foot = BattlePlayLoop.EquipmentRules.equipped_code(player["equipment"],"foot")
	enemy["combat_profile"]["dex"] = 1
	if mode in ["equip_growth","victory"]: player["exp"] = 99; enemy["hp"] = 1
	if mode in ["pending_restore","escape"]: enemy["coord"] = Vector2i(2,17)
	if mode in ["ai_without","ai_boots"]:
		enemy["coord"] = Vector2i(8,8); enemy["live_speed"] = 110
		player["coord"] = Vector2i(17,15)
		enemy["equipment"] = enemy["equipment"].filter(func(slot):return slot["slot"] != "foot")
		TestSuite.own(loop, "ai_profiles")["actors"]["021"]["profile"].merge({"find_range":10,"ai_check_dying":0,"ai_help_selfhp":0,"ai_help_otherhp":0,"ai_help_status":0,"ai_att_magic":0},true)
		check(position_extended_encounter(loop,"enemy021_1","leonard"),"real WRD offers a target reachable for attack only with the extra mobility")
		if mode == "ai_boots": enemy["equipment"].append({"slot":"foot","item_code":193,"name":"舞空之靴"})
		enemy["move_point"] = MobilityRules.prepare(enemy,loop["equipment_items"])["value"]
	if mode == "victory": check(position_extended_encounter(loop,"leonard","enemy021_1"),"source terrain supports the gear-enabled player approach")
	if mode == "defeat":
		player["hp"] = 1; enemy["live_speed"] = 110; enemy["combat_profile"]["live_attack_damage"] = 200
	if mode in ["victory","escape"]:
		loop["turn"] = 6
		scene.get_node("BattlePresentation")._shown_story_events.assign(loop["event_log"])
		if mode == "escape":
			player = BattlePlayLoop.unit_ref(loop,"leonard")
			landing = loop["escape_zone"][0]
			var placed := false
			for y in range(loop["map_size"].y):
				for x in range(loop["map_size"].x):
					var cell := Vector2i(x,y)
					if bool(loop["tiles"].get(cell,{}).get("blocks_movement",false)) or BattlePlayLoop.unit_id_at_coord(loop,cell) not in ["","leonard"]: continue
					player["coord"] = cell; player["move_point"] = 5
					var before := BattlePlayLoop.movement_path(loop,"leonard",landing)
					player["move_point"] = 6
					if before.is_empty() and not BattlePlayLoop.movement_path(loop,"leonard",landing).is_empty(): placed = true; break
				if placed: break
			player["move_point"] = 5
			check(placed,"the actual escape zone has a legal source-cost6 approach")
	loop["turn_queue"] = BattlePlayLoop.CoreTurnQueue.rebuild(loop["units"])
	scene.apply_loop(BattlePlayLoop.return_to_player(loop,"leonard"), "test")
	scene.settlement_controller.checkpoint_path = OUTPUT+mode+".save"
	for actor in scene.actors_root.get_children(): scene.actors_root.remove_child(actor); actor.queue_free()
	scene.unit_grid_coords.clear()
	for unit in scene.play_loop["units"]: unit["grid_coord"] = unit["coord"]
	scene.resume_turn_presentation()
	scene.center_camera_on_grid(BattlePlayLoop.unit(scene.play_loop,"leonard")["coord"])
	var view = scene.get_node("BattlePresentation")
	view.experience_presented.connect(func(growth):experience_events.append(growth.duplicate(true)))
	view.cutin.released.connect(func(s,_a,_d,c):cues.append(["release",s["attacker_id"],c]))
	view.cutin.impact.connect(func(s,_a,_d,c):cues.append(["impact",s["attacker_id"],c]))
	scene.set_process(true)
	await create_timer(0.3).timeout


func position_extended_encounter(loop: Dictionary, actor_id: String, foe_id: String) -> bool:
	var actor := BattlePlayLoop.unit_ref(loop,actor_id)
	var foe := BattlePlayLoop.unit_ref(loop,foe_id)
	for y in range(maxi(1,actor["coord"].y-6),mini(loop["map_size"].y,actor["coord"].y+7)):
		for x in range(maxi(1,actor["coord"].x-6),mini(loop["map_size"].x,actor["coord"].x+7)):
			var cell := Vector2i(x,y)
			if bool(loop["tiles"].get(cell,{}).get("blocks_movement",false)) or BattlePlayLoop.unit_id_at_coord(loop,cell) not in ["",foe_id]: continue
			foe["coord"] = cell; actor["move_point"] = 5
			var before := BattleLoopAI.ai_physical_choice(loop,actor,foe,BattlePlayLoop.movement_envelope(loop,actor_id))
			actor["move_point"] = 6
			var after := BattleLoopAI.ai_physical_choice(loop,actor,foe,BattlePlayLoop.movement_envelope(loop,actor_id))
			actor["move_point"] = 5
			if before.is_empty() and not after.is_empty():
				landing = after["to"]
				return true
	return false


func wear(code: int, slot: String, expected: int, cancel_first: bool = false) -> void:
	await create_timer(0.3).timeout
	await click(scene.action_menu.get_node("ItemCommand"))
	await create_timer(0.3).timeout
	await click(scene.item_panel.menu.get_node("EquipCommand"))
	await click(item_button(code))
	if slot.begins_with("accessory"): await click(find_button(scene.item_panel.page_root,"飾品 "+slot.right(1)))
	var before: Dictionary = scene.play_loop.duplicate(true)
	var preview := ""
	for label in scene.item_panel.page_root.find_children("*","Label",true,false): preview += label.text + "\n"
	check(preview.contains("移動力  %d → %d" % [BattlePlayLoop.unit(before,"leonard")["move_point"],expected]) and not scene.item_panel.confirm_button.disabled,"actual equipment preview quotes the same final source mobility")
	await shot("equip-"+str(code)+"-"+slot)
	if cancel_first:
		await click(find_button(scene.item_panel.page_root,"取消"))
		check(scene.play_loop == before,"cancelling equipment spends no item/resource/movement")
		await click(item_button(code))
		if slot.begins_with("accessory"): await click(find_button(scene.item_panel.page_root,"飾品 "+slot.right(1)))
	await click(scene.item_panel.confirm_button)
	await create_timer(0.3).timeout
	var actor := BattlePlayLoop.unit(scene.play_loop,"leonard")
	check(actor["move_point"] == expected and actor["base_move_point"] == 5 and scene.play_loop["turn_queue"] == before["turn_queue"],"real confirmation changes current mobility once without changing queue/base")
	changes.append({"item":code,"slot":slot,"before":BattlePlayLoop.unit(before,"leonard")["move_point"],"after":actor["move_point"],"pending":scene.pending_move_revert})


func status_mobility(expected: int) -> void:
	await create_timer(0.3).timeout
	await click(scene.action_menu.get_node("StatusCommand"))
	check(scene.status_panel.visible and scene.status_panel.stat_values["move"].text == str(expected),"real Status shows the current equipped movement")
	await shot("status-"+str(expected))
	await escape()
	await create_timer(0.3).timeout


func move_to(cell: Vector2i) -> void:
	await click(scene.action_menu.get_node("MoveCommand"))
	check(scene.move_overlay_cells.has(cell),"actual move overlay includes the new legal destination")
	await hover(scene.grid_cell_center_to_logical_position(cell))
	await shot("range")
	var path := BattlePlayLoop.movement_path(scene.play_loop,"leonard",cell)
	await point(scene.grid_cell_center_to_logical_position(cell))
	check(not path.is_empty(),"selected destination has one source-cost route")
	for _attempt in range(300):
		if scene.has_actor_motion(): observed["movement"] = true; check(not scene.action_menu.visible,"movement keeps controls closed")
		if not scene.has_actor_motion() and scene.action_menu.visible and not scene.action_menu.is_expanding(): break
		await create_timer(0.02).timeout
	check(BattlePlayLoop.unit(scene.play_loop,"leonard")["coord"] == cell and scene.pending_move_revert,"normal-clock source walk reaches its pending destination")
	observed["last_path"] = path


func play_mobility() -> void:
	var before_cells := BattlePlayLoop.movement_cells(scene.play_loop)
	if mode in ["ai_without","ai_boots"]:
		await click(scene.action_menu.get_node("WaitCommand"))
		await finish_battle(false)
		var action: Dictionary = scene.play_loop["last_ai_action"]
		check(action["kind"] == ("move_then_attack" if mode == "ai_boots" else "move") and scene.play_loop["last_ai_actions"].size() == 1,"AI uses its equipped budget to decide pursuit versus move-and-attack")
		receipt = action.duplicate(true)
	else:
		await wear(193,"foot",6,true)
		await status_mobility(6)
		if mode == "equip_growth":
			await wear(138,"armor",7)
			await wear(231,"accessory1",8)
			await wear(231,"accessory2",9)
			await status_mobility(9)
			await attack_target()
			await finish_battle(false)
			check(BattlePlayLoop.unit(scene.play_loop,"leonard")["level"] == 2 and BattlePlayLoop.unit(scene.play_loop,"leonard")["move_point"] == 9 and observed.has("growth"),"actual kill, finalEXP and five-point growth retain all four movement bonuses")
		elif mode == "pending_restore":
			var selected := false
			for cell in BattlePlayLoop.movement_cells(scene.play_loop):
				var logical: Vector2 = scene.grid_cell_center_to_logical_position(cell)
				if not before_cells.has(cell) and Rect2(28,28,584,398).has_point(logical): landing = cell; selected = true; break
			check(selected,"real visible terrain exposes a newly reachable source-cost6 cell")
			if not selected: return
			var origin: Vector2i = BattlePlayLoop.unit(scene.play_loop,"leonard")["coord"]
			await move_to(landing)
			await wear(original_foot,"foot",5,true)
			check(BattlePlayLoop.unit(scene.play_loop,"leonard")["coord"] == landing and scene.pending_move_revert,"changing boots after a move cannot teleport or spend another action")
			await save_restore()
			await status_mobility(5)
			var equipment: Array = BattlePlayLoop.unit(scene.play_loop,"leonard")["equipment"]
			await escape()
			check(scene.interaction_state == "move_select" and BattlePlayLoop.unit(scene.play_loop,"leonard")["coord"] == origin and not scene.move_overlay_cells.has(landing),"real cancel restores origin and removes the no-longer-affordable destination")
			await shot("cancel-shrink")
			await point(scene.grid_cell_center_to_logical_position(landing))
			check(BattlePlayLoop.unit(scene.play_loop,"leonard")["coord"] == origin and BattlePlayLoop.unit(scene.play_loop,"leonard")["equipment"] == equipment,"clicking stale destination does not move or restore old gear")
			await escape()
			await wear(193,"foot",6)
			await move_to(landing)
			await click(scene.action_menu.get_node("WaitCommand"))
			await finish_battle(false)
		elif mode == "victory":
			check(not before_cells.has(landing),"clear route needs the new mobility")
			await move_to(landing)
			await attack_target()
			await finish_battle(true)
		elif mode == "escape":
			check(not before_cells.has(landing),"the escape destination was outside old budget")
			await move_to(landing)
			await click(scene.action_menu.get_node("WaitCommand"))
			await finish_battle(true)
		else:
			await click(scene.action_menu.get_node("WaitCommand"))
			await finish_battle(true)
	var terminal := mode in ["victory","defeat","escape"]
	if terminal: await save_restore()
	var owner := BattlePlayLoop.unit(scene.play_loop,"leonard")
	routes.append({"mode":mode,"changes":changes,"observed":observed,"receipt":receipt,"cues":cues,"experience":experience_events,
		"base_move_point":owner["base_move_point"],"move_point":owner["move_point"],"level":owner["level"],"exp":owner["exp"],"equipment":owner["equipment"],"outcome":scene.play_loop["battle_outcome"],"next_actor":scene.selected_unit_id,"sounds":sound_paths.keys()})
	if terminal:
		reload_current_scene()
		for _attempt in range(20):
			if is_instance_valid(current_scene): break
			await process_frame
		scene = current_scene
		var ready: bool = is_instance_valid(scene) and not BattleOutcome.decided(scene.play_loop) and BattlePlayLoop.unit(scene.play_loop,"leonard")["move_point"] == 5
		check(ready,"actual retry restores default gear/base/current mobility")
		routes.back()["restarted"] = ready


func attack_target() -> void:
	await click(scene.action_menu.get_node("AttackCommand"))
	await point(scene.grid_cell_center_to_logical_position(BattlePlayLoop.unit(scene.play_loop,"enemy021_1")["coord"]))
	receipt = scene.play_loop["last_attack"].duplicate(true)
	check(not receipt.is_empty(),"actual attack accepts the equipped movement endpoint")


func save_restore() -> void:
	var before: Dictionary = scene.play_loop.duplicate(true)
	await key(KEY_F5); await key(KEY_F9)
	check(scene.play_loop == before,"F5/F9 preserves source/current mobility, gear, pending path and rewards without replay")
	await shot("restored")


func finish_battle(terminal: bool) -> void:
	for _attempt in range(1600):
		var view = scene.get_node("BattlePresentation")
		for sound in scene.find_children("*","AudioStreamPlayer",true,false):
			if sound.playing and sound.stream != null and sound.get_playback_position()>0: sound_paths[sound.stream.resource_path] = true
		if scene.has_actor_motion() and not observed.has("ai_move"):
			observed["ai_move"] = true; await shot("ai-move")
		if view.cutin.busy() and not observed.has("impact") and view.cutin.clips[0]["impact_emitted"]:
			observed["impact"] = true
			check(not scene.action_menu.visible and not view.battle_finished,"source impact precedes successor control and terminal UI")
			await shot("impact")
		if view.dialogue_active():
			if not observed.has("dialogue"): observed["dialogue"] = true; await shot("dialogue")
			await key(KEY_SPACE)
		if view.aftermath.reward_label.visible and not observed.has(view.aftermath.stage):
			observed[view.aftermath.stage] = true; await shot(view.aftermath.stage)
		var loot = scene.settlement_controller.panel
		if loot.visible:
			observed["loot"] = true
			if not loot.rows.is_empty() and loot.first_empty_slot() >= 0: await click(loot.rows[0]); await click(loot.slots[loot.first_empty_slot()])
			else: await click(loot.finish_button)
		if scene.growth_panel.visible:
			observed["growth"] = true
			var before: int = BattlePlayLoop.unit(scene.play_loop,"leonard")["move_point"]
			for attribute in ["str","str","dex","mind","con"]: await click(scene.growth_panel.choices[attribute]["plus"])
			await shot("growth")
			check(scene.growth_panel.derived_values["move"].text == str(before) and scene.growth_panel.remaining_label.text == "0","the original-layout 移動力 row keeps the equipped movement while 殘餘點數 reads 0")
			await shot("growth-mobility")
			await click(scene.growth_panel.confirm_button)
			check(BattlePlayLoop.unit(scene.play_loop,"leonard")["move_point"] == before,"real growth confirmation preserves current equipped movement")
		if terminal and view.battle_finished:
			var expected := BattleOutcome.VICTORY_ENEMIES_CLEARED if mode == "victory" else BattleOutcome.DEFEAT_FALLEN if mode == "defeat" else BattleOutcome.VICTORY_ESCAPE
			check(scene.play_loop["battle_outcome"] == expected,"the new equipment chain reaches the intended outcome")
			await shot("result")
			return
		if not terminal and scene.selected_unit_id == "enemy023_1" and scene.action_menu.visible and not scene.ai_playback_active and not view.combat_busy(scene.play_loop) and not scene.action_menu.is_expanding():
			await shot("handoff")
			return
		await create_timer(0.02).timeout
	check(false,"bounded mobility route reaches successor or terminal state")


func shot(label: String) -> void:
	await process_frame
	RenderingServer.force_draw(false)
	check(root.get_texture().get_image().save_png(OUTPUT+mode+"-"+label+".png") == OK,"capture "+label)
