extends SceneTree
## Manual-acceptance capture for lane P6 (lead-in beats,
## docs/evidence_packets/static_reverse/original_cast_overlays.md#起手节拍) on battle_051:
## `player-attack` — 雷歐納德's normal attack through the product route (command, pointer
## hover, `attack_selected_coord`); `ai-attack` — actor021_1's settled attack on an adjacent
## 雷歐納德; `ai-cast` — actor026_1's 風刃 at 雷歐納德 three cells away. The AI receipts are
## settled by the loop's own seam and applied as a fixture, then the scene's `_process` runs
## the presentation in real time. Logs the cue stage per frame (first frame of each stage with
## its elapsed ticks) and, with a rendering window, saves a screenshot at each stage. A
## rendering fixture, not a natural playthrough, not a parity verdict.
##
##   tools/godot.sh --headless --script res://tests/capture_lead_in_review.gd            # log only
##   tools/play.sh --resolution 640x480 --script res://tests/capture_lead_in_review.gd -- <out_dir> [case]
const Loop = preload("res://game/sim/loop/BattlePlayLoop.gd")
const LoopCombat = preload("res://game/sim/loop/BattleLoopCombat.gd")
const LoopKeys = preload("res://game/sim/LoopKeys.gd")
const OriginalTick = preload("res://game/common/OriginalTick.gd")
const CASES := ["player-attack", "ai-attack", "ai-cast"]
var out_dir := ""
var rendering := false


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	rendering = DisplayServer.get_name() != "headless"
	var args := OS.get_cmdline_user_args()
	out_dir = args[0] if not args.is_empty() else "res://ignored/p6-lead-ins"
	if rendering:
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir))
		root.size = Vector2i(640, 480)
	var only := args[1] if args.size() > 1 else ""
	for label in CASES:
		if only == "" or only == label:
			await run_case(label)
	print("LEAD_IN_REVIEW_FINISHED")
	quit(0)


func run_case(label: String) -> void:
	var scene: Node = load("res://game/battle/scene/BattleSceneRuntime.tscn").instantiate()
	scene.scenario_path = "res://content/battles/battle_051.json"
	scene.startup_mode = "dev_first_control"
	root.add_child(scene)
	current_scene = scene
	await process_frame
	scene.start_dev_first_control_harness()
	scene.get_node("BattleMusic").stop()
	await settle(scene)
	var presentation: Node = scene.get_node("BattlePresentation")
	var leonard: Dictionary = Loop._unit(scene.play_loop, "leonard")
	if label == "player-attack":
		var enemy: Dictionary = Loop._unit(scene.play_loop, "actor021_1")
		enemy["coord"] = leonard["coord"] + Vector2i(1, 0)
		enemy["max_hp"] = 400
		enemy["hp"] = 400
		scene.apply_loop(scene.play_loop, "test")
		await settle(scene)
		scene.menus.choose_command("attack")
		# The real pointer would keep re-deciding hover in a window; drive it by hand for the shot.
		scene.set_process_input(false)
		scene.scene_input.handle_pointer_motion(scene.grid_cell_center_to_logical_position(enemy["coord"]))
		await hold(0.5)
		await sample(scene, label, "1-target-select", 0.0)
		scene.attack_selected_coord(enemy["coord"])
		await sample(scene, label, "2-confirm-frame", 0.0)
	else:
		var loop: Dictionary = scene.play_loop.duplicate(true)
		var attacker_id := "actor021_1" if label == "ai-attack" else "actor026_1"
		var attacker: Dictionary = Loop._unit(loop, attacker_id)
		var target: Dictionary = Loop._unit(loop, "leonard")
		target["coord"] = attacker["coord"] + (Vector2i(1, 0) if label == "ai-attack" else Vector2i(3, 0))
		target["hp"] = 200
		target["max_hp"] = 200
		attacker["mp"] = int(attacker.get("max_mp", 0))
		var receipt: Dictionary
		if label == "ai-attack":
			receipt = LoopCombat._resolve_exchange(loop, attacker_id, "leonard", func(_n): return 0)
		else:
			var spell := "magic:magicAIR:magicCode01"
			receipt = LoopCombat._resolve_skill(loop, attacker_id, "leonard", spell, Loop.skill_fields(loop, spell), attacker["coord"], func(_n): return 0)
		print("LEAD_IN ", label, " receipt ", not receipt.is_empty())
		scene.center_camera_on_grid(attacker["coord"])
		scene.apply_loop(loop, "test")
	var started := Time.get_ticks_usec()
	var last := ""
	var glide_samples := 0
	for _guard in range(3000):
		if not presentation.combat_busy(scene.play_loop): break
		var cue: Node2D = presentation.attack_cue
		var stage := "cue-" + str(cue.stage()) if cue.visible else ("cutin" if presentation.cutin.busy() else "")
		var elapsed_ticks: float = OriginalTick.ticks(float(cue.get("elapsed"))) if cue.visible else -1.0
		if stage != "" and stage != last:
			last = stage
			glide_samples = 0
			await sample(scene, label, "3-" + stage, elapsed_ticks)
		elif stage == "cue-cursor" and glide_samples < 3 and int(elapsed_ticks) % 4 == 0:
			glide_samples += 1
			await sample(scene, label, "3-cue-cursor-%02d" % int(elapsed_ticks), elapsed_ticks)
		if stage == "cutin": break
		await process_frame
	print("LEAD_IN ", label, " wall_ms_to_cutin ", (Time.get_ticks_usec() - started) / 1000)
	await hold(0.6)
	await sample(scene, label, "4-cutin-running", -1.0)
	scene.queue_free()
	await process_frame
	await create_timer(0.3).timeout


func sample(scene: Node, label: String, phase: String, elapsed_ticks: float) -> void:
	if rendering:
		await RenderingServer.frame_post_draw
	else:
		await process_frame
	var presentation: Node = scene.get_node("BattlePresentation")
	var cue: Node2D = presentation.attack_cue
	var caption_layer: Variant = cue.get("caption_layer")
	var caption_label: Variant = cue.get("caption_label")
	var state := {
		"cue": cue.visible, "stage": str(cue.stage()), "elapsed_ticks": snappedf(elapsed_ticks, 0.1),
		"cursor": str(cue.cursor_position() - cue.source) if cue.visible else "",
		"cue_caption": caption_layer != null and caption_layer.visible, "cue_caption_text": caption_label.text if caption_label != null else "",
		"cutin": presentation.cutin.busy(), "cutin_caption_visible": presentation.cutin.busy() and presentation.cutin.result.visible,
		"cutin_caption_y": presentation.cutin.result.position.y, "cutin_caption_text": presentation.cutin.result.text if presentation.cutin.busy() else "",
		"selection_cursor": presentation.selection_cursor.visible, "action_menu": scene.action_menu.visible,
	}
	print("LEAD_IN ", label, " ", phase, " ", JSON.stringify(state))
	if rendering:
		root.get_texture().get_image().save_png(out_dir.path_join("%s-%s.png" % [label, phase]))


func settle(scene: Node) -> void:
	var presentation: Node = scene.get_node("BattlePresentation")
	for _guard in range(600):
		if not presentation.combat_busy(scene.play_loop) and not scene.has_actor_motion() and not presentation.dialogue_active():
			return
		await process_frame


func hold(seconds: float) -> void:
	await create_timer(seconds).timeout
