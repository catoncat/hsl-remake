extends SceneTree
## Two separate rendered processes: prepare claims the loot (F5 is refused while it is
## still pending: the loot window is not a quiet boundary) and saves after the hand-off,
## resume loads that save with F9 in a new process. Fixtures change HP/stock/initiative,
## never rewards.
const Loop = preload("res://game/battle/scene/BattlePlayLoop.gd")
const Cases = preload("res://tests/run_battle_reward_tests.gd")
const Save = preload("res://game/battle/runtime/BattleCheckpoint.gd")
const BattleFixture = preload("res://tests/support/BattleFixture.gd")
const BattleOutcome = preload("res://game/sim/BattleOutcome.gd")
const OUT := "res://ignored/battle-reward-review/"
const PATH := OUT + "partial.save"
var scene: Node
var mode := "prepare"
var failures: Array[String] = []
var records: Array = []
var entered := false
var snapshots := {}


# A finished battle fades out and leaves by itself (no result page); these captures
# inspect the finished battle, then reload or hand off explicitly.
func _init() -> void:
	preload("res://game/battle/scene/BattleSceneRuntime.gd").hold_finished_battle = true

func _initialize() -> void: call_deferred("run")


func run() -> void:
	if DisplayServer.get_name() == "headless" or Engine.time_scale != 1.0:
		push_error("Reward review requires a real rendering window and normal clock")
		quit(2)
		return
	var args := OS.get_cmdline_user_args()
	if not args.is_empty(): mode = args[0]
	if mode not in ["prepare", "resume"]: quit(2); return
	root.title = "HSL Reward Review — " + mode
	root.size = Vector2i(640, 480)
	DirAccess.make_dir_recursive_absolute(OUT)
	create_timer(150).timeout.connect(func(): push_error("Reward review timed out"); quit(2))
	if mode == "prepare":
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))
		await setup(Cases.fixture())
		await attack_to_loot("initial")
		var panel = scene.settlement_controller.panel
		check(scene.play_loop["gold"] == 100 and panel.rows.size() == 2, "one real strike generates the two carried important items and $100")
		var before: Dictionary = scene.play_loop.duplicate(true)
		check(panel._recipient == "leonard", "the killer owns the get-item window like the original")
		await click(panel.rows[0])
		await shot("claim-preview")
		await click(panel.storage_button)
		check(scene.play_loop == before and not panel.holding(), "倉庫 returns the held item to the pool without moving inventory")
		await click(panel.rows[0])
		await key(KEY_ESCAPE)
		check(scene.play_loop["settlement"]["pending"].size() == 1 and Loop.unit(scene.play_loop, "leonard")["inventory"].count(281) == 1, "Esc drops the held item into the first free bag slot, claiming exactly one instance")
		await key(KEY_F5)
		check(not FileAccess.file_exists(PATH), "F5 is refused while loot is still pending (Loop.loot_waiting is not a quiet boundary)")
		await shot("partial-save-refused")
		await click(panel.rows[0])
		await click(panel.slots[panel.first_empty_slot()])
		await shot("fully-claimed")
		await click(panel.finish_button)
		for _attempt in range(400): # the LEVEL UP float plays first (in-process: no restore skip)
			if scene.growth_panel.visible: break
			await create_timer(0.025).timeout
		check(scene.growth_panel.visible, "earned growth follows completed loot")
		scene.growth_panel.hide() # harness skip seam: right click／Esc cannot close the window before OK
		for _attempt in range(200):
			if scene.selected_unit_id == "enemy023_1": break
			await create_timer(0.025).timeout
		await create_timer(0.4).timeout
		check(scene.selected_unit_id == "enemy023_1" and scene.play_loop["turn_queue"]["index"] == 1, "completed loot hands off exactly once to the next controlled actor")
		await key(KEY_F5)
		var saved := Save.read(PATH, scene.play_loop)
		check(saved["ok"] and saved["snapshot"]["loop"] == scene.play_loop, "F5 after the hand-off saves the claimed state")
		await shot("claimed-saved")
	else:
		# The fixture scenario has no product opening (so no Continue Save button): F9 loads the checkpoint.
		await setup({})
		await shot("startup-resume")
		var saved := Save.read(PATH, scene.play_loop)
		check(saved["ok"], "previous process left a valid checkpoint")
		await key(KEY_F9)
		await create_timer(0.4).timeout
		check(scene.play_loop == saved["snapshot"]["loop"] and not scene.settlement_controller.panel.visible, "new process restores exact stock, wallet and EXP with no loot window")
		check(not scene.get_node("BattlePresentation").combat_busy(scene.play_loop), "restoration does not rerun the attack, death, experience or money animation")
		check(scene.selected_unit_id == "enemy023_1" and scene.play_loop["settlement"]["pending"].is_empty() and scene.play_loop["gold"] == 100, "the reloaded save cannot reopen already claimed rewards")
		await shot("completed-handoff")
		await full_inventory()
		await terminal_loot()
	var report := {"mode": mode, "pid": OS.get_process_id(), "normal_clock": Engine.time_scale,
		"actual_input": "Viewport.push_input through visible controls and Runtime keyboard handlers",
		"fixture": "1HP adjacent enemy carrying source-important 281/282, player99EXP and hit bonus9, two controlled actors with speed100/99; full-bag and terminal variants are explicitly set up; no RNG callback or outcome override",
		"window_position": root.position, "window_size": root.size, "records": records, "failures": failures}
	FileAccess.open(OUT + mode + "-receipt.json", FileAccess.WRITE).store_string(JSON.stringify(report, "  "))
	await dispose()
	print("BATTLE_REWARD_RENDER_", "PASS" if failures.is_empty() else "FAIL", " mode=", mode)
	quit(0 if failures.is_empty() else 1)


func setup(loop: Dictionary, post_report: bool = false) -> void:
	await dispose()
	scene = load("res://game/battle/scene/BattleSceneRuntime.tscn").instantiate()
	scene.scenario_path = BattleFixture.PATH; scene.startup_mode = "dev_first_control"
	root.add_child(scene)
	current_scene = scene
	scene.settlement_controller.checkpoint_path = PATH
	if not loop.is_empty():
		scene.start_dev_first_control_harness()
		Loop._unit(loop, "leonard")["hit_bonus_accum"] = 9
		scene.apply_loop(loop, "test")
		for actor in scene.actors_root.get_children(): scene.actors_root.remove_child(actor); actor.queue_free()
		scene.unit_grid_coords.clear()
		scene.resume_turn_presentation()
		if post_report:
			scene.get_node("BattlePresentation")._shown_story_events.assign(loop["event_log"])
	scene.get_node("BattleMusic").stop()
	await create_timer(0.4).timeout


func attack_to_loot(label: String) -> void:
	await click(scene.action_menu.get_node("AttackCommand"))
	check(scene.interaction_state == "attack_select", "visible Attack enters target selection")
	await click_point(scene.grid_cell_center_to_logical_position(Loop.unit(scene.play_loop, "enemy021_1")["coord"]))
	var view = scene.get_node("BattlePresentation")
	for _attempt in range(1200):
		await create_timer(0.025).timeout
		if view.dialogue_active(): await key(KEY_SPACE)
		if view.aftermath.stage == "gold" and not snapshots.has(label + "-gold"):
			await shot(label + "-gold")
		if scene.settlement_controller.panel.visible:
			check(not scene.action_menu.visible and not scene.growth_panel.visible and not view.battle_finished, "loot owns input before growth, successor or victory")
			await shot(label + "-loot")
			return
	check(false, "normal-clock attack reaches loot")


func full_inventory() -> void:
	await setup(Cases.fixture(true))
	await attack_to_loot("full")
	var panel = scene.settlement_controller.panel
	var before: Dictionary = scene.play_loop.duplicate(true)
	await click(panel.rows[0])
	check(panel.holding() and panel.first_empty_slot() < 0, "full bag leaves the picked item in hand with no free slot")
	await key(KEY_ESCAPE)
	check(scene.play_loop == before and panel.holding(), "Esc cannot auto-place into a full bag; the item stays in hand")
	await click(panel.storage_button)
	check(scene.play_loop == before and not panel.holding(), "returned item preserves both pools")
	await click(panel.rows[0])
	await click(panel.slots[0])
	check(Loop.unit(scene.play_loop, "leonard")["inventory"].has(281) and scene.play_loop["settlement"]["pending"][0]["code"] == 241, "displaced medicine remains in loot after exchange")
	await shot("full-exchanged")
	await click(panel.rows[1])
	await click(panel.slots[1])
	check(not panel.drop_button.disabled, "only ordinary displaced medicine remains")
	await click(panel.drop_button)
	await shot("abandon-confirmation")
	await click(panel.rows[0])
	await click(panel.storage_button)
	check(scene.play_loop["settlement"]["pending"].size() == 2 and not panel._abandon_armed, "leaving the 丟棄 icon cancels the discard and retains both medicines")
	await click(panel.finish_button)
	for _attempt in range(400): # the LEVEL UP float plays before the growth window
		if scene.growth_panel.visible: break
		await create_timer(0.025).timeout
	if scene.growth_panel.visible: scene.growth_panel.hide() # harness skip seam
	for _attempt in range(200):
		if scene.action_menu.get_node("StatusCommand").is_visible_in_tree(): break
		await create_timer(0.025).timeout
	await create_timer(0.2).timeout
	# 待領物品 is an OPT-GUIDE 提示 button (the original status page has no button bar).
	preload("res://game/settings/GameOptions.gd").environment_preset = "comfort"
	await click(scene.action_menu.get_node("StatusCommand"))
	await click(scene.status_panel.rewards_button)
	preload("res://game/settings/GameOptions.gd").environment_preset = ""
	check(panel.visible and panel.rows.size() == 1 and scene.play_loop["settlement"]["pending"].size() == 2, "next actor can reopen deferred items through Status as one (code, 2) row")
	await click(panel.drop_button)
	await click(panel.drop_button)
	check(scene.play_loop["settlement"]["abandoned"].size() == 2 and scene.play_loop["gold"] == 100 and Loop.unit(scene.play_loop, "leonard")["inventory"].has(282), "confirmed abandonment preserves accepted items and wallet")


func terminal_loot() -> void:
	var loop := Cases.fixture()
	loop["units"] = loop["units"].filter(func(actor): return actor["id"] in ["leonard", "enemy021_1"])
	loop["turn_queue"] = Loop.CoreTurnQueue.rebuild(loop["units"])
	loop["turn"] = 6
	await setup(loop, true) # Explicit post-report fixture; victory itself is not overridden.
	await attack_to_loot("terminal")
	check(scene.play_loop["battle_outcome"] == BattleOutcome.VICTORY_ENEMIES_CLEARED, "last-enemy kill commits the actual scenario victory")
	var panel = scene.settlement_controller.panel
	while not panel.rows.is_empty():
		await click(panel.rows[0])
		await click(panel.slots[panel.first_empty_slot()])
	await click(panel.finish_button)
	for _attempt in range(600):
		await create_timer(0.025).timeout
		if scene.growth_panel.visible: scene.growth_panel.hide() # harness skip seam
		if scene.get_node("BattlePresentation").dialogue_active(): await key(KEY_SPACE)
		if scene.get_node("BattlePresentation").battle_finished: break
	check(scene.get_node("BattlePresentation").battle_finished and scene.play_loop["gold"] == 100, "victory becomes visible only after rewards and closing dialogue")
	await key(KEY_F5)
	await key(KEY_F9)
	# The reload restores the loop (outcome, wallet, empty loot); the held victory view is not part of a save.
	check(scene.play_loop["battle_outcome"] == BattleOutcome.VICTORY_ENEMIES_CLEARED and not panel.visible and scene.play_loop["gold"] == 100 and scene.play_loop["settlement"]["pending"].is_empty(), "terminal restoration neither reopens loot nor reissues rewards")
	await shot("terminal-result")


func click(control: Control) -> void:
	check(control.is_visible_in_tree() and not (control is BaseButton and control.disabled), "click targets an available control: " + str(control.name))
	await click_point(control.get_global_rect().get_center())


func click_point(point: Vector2) -> void:
	if not entered: root.notify_mouse_entered(); entered = true
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
	await create_timer(0.06).timeout


func key(code: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.pressed = true
	root.push_input(event, true)
	await process_frame
	event = event.duplicate()
	event.pressed = false
	root.push_input(event, true)
	await process_frame


func shot(label: String) -> void:
	await process_frame
	RenderingServer.force_draw(false)
	check(root.get_texture().get_image().save_png(OUT + label + ".png") == OK, "capture " + label)
	snapshots[label] = true
	records.append({"capture": label, "gold": scene.play_loop["gold"], "settlement": scene.play_loop["settlement"].duplicate(true), "next_actor": scene.selected_unit_id, "queue_index": scene.play_loop["turn_queue"]["index"]})


func dispose() -> void:
	if is_instance_valid(scene):
		stop_audio(scene)
		await process_frame
		await create_timer(0.15).timeout
		scene.queue_free()
		await process_frame
		await create_timer(0.3).timeout
	scene = null


func stop_audio(node: Node) -> void:
	if node is AudioStreamPlayer: node.stop()
	for child in node.get_children(): stop_audio(child)


func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error(message)
