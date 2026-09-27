extends SceneTree
## Manual-acceptance capture for lane R7-CUE (AI lead-in camera and per-stage overlays,
## docs/evidence_packets/static_reverse/original_cast_overlays.md#起手的镜头与各段覆盖层) on
## battle_051: `ai-attack` — actor021_1's settled attack on 雷歐納德 one cell right; `ai-cast` —
## actor026_1's 風刃 at 雷歐納德 three cells right. The view starts on the map's far corner, so the
## lead-in first glides it to the actor (camera stage, nothing drawn), then shows the range, the
## glide (a cast frames the cursor every tick and draws the effect area at the cursor's cell; an
## attack carries the view with the cursor) and the target hold (a cast keeps range＋area, an
## attack shows the cursor alone). The AI receipts are settled by the loop's own seam and applied
## as a fixture, then the scene's `_process` runs in real time. Logs each stage's first frame and
## a few glide frames (camera position, cursor, range／area visibility) and, with a rendering
## window, saves a screenshot at each. A rendering fixture, not a natural playthrough, not a
## parity verdict.
##
##   tools/godot.sh --headless --script res://tests/capture_ai_cue_review.gd            # log only
##   tools/play.sh --resolution 640x480 --script res://tests/capture_ai_cue_review.gd -- <out_dir> [case]
const BattlePlayLoop = preload("res://game/sim/loop/BattlePlayLoop.gd")
const BattleLoopCombat = preload("res://game/sim/loop/BattleLoopCombat.gd")
const OriginalTick = preload("res://game/common/OriginalTick.gd")
const CASES := ["ai-attack", "ai-cast"]
var out_dir := ""
var rendering := false


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	rendering = DisplayServer.get_name() != "headless"
	var args := OS.get_cmdline_user_args()
	out_dir = args[0] if not args.is_empty() else "res://ignored/r7-cue"
	if rendering:
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir))
		root.size = Vector2i(640, 480)
	var only := args[1] if args.size() > 1 else ""
	for label in CASES:
		if only == "" or only == label:
			await run_case(label)
	print("AI_CUE_REVIEW_FINISHED")
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
	var loop: Dictionary = scene.play_loop.duplicate(true)
	var attacker_id := "actor021_1" if label == "ai-attack" else "actor026_1"
	var attacker: Dictionary = BattlePlayLoop._unit(loop, attacker_id)
	var target: Dictionary = BattlePlayLoop._unit(loop, "leonard")
	target["coord"] = attacker["coord"] + (Vector2i(1, 0) if label == "ai-attack" else Vector2i(3, 0))
	target["hp"] = 200
	target["max_hp"] = 200
	attacker["mp"] = int(attacker.get("max_mp", 0))
	var receipt: Dictionary
	if label == "ai-attack":
		receipt = BattleLoopCombat._resolve_exchange(loop, attacker_id, "leonard", func(_n): return 0)
	else:
		var spell := "magic:magicAIR:magicCode01"
		receipt = BattleLoopCombat._resolve_skill(loop, attacker_id, "leonard", spell, BattlePlayLoop.skill_fields(loop, spell), attacker["coord"], func(_n): return 0)
	print("AI_CUE ", label, " receipt ", not receipt.is_empty())
	scene.center_camera_on_grid(Vector2i.ZERO)
	scene.apply_loop(loop, "test")
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
			await sample(scene, label, "1-" + stage, elapsed_ticks)
		elif stage == "cue-cursor" and glide_samples < 4 and int(elapsed_ticks) % 5 == 0:
			glide_samples += 1
			await sample(scene, label, "1-cue-cursor-%02d" % int(elapsed_ticks), elapsed_ticks)
		if stage == "cutin": break
		await process_frame
	scene.queue_free()
	await process_frame
	await create_timer(0.3).timeout


func sample(scene: Node, label: String, phase: String, elapsed_ticks: float) -> void:
	if rendering:
		await RenderingServer.frame_post_draw
	else:
		await process_frame
	var cue: Node2D = scene.get_node("BattlePresentation").attack_cue
	var state := {
		"stage": str(cue.stage()), "elapsed_ticks": snappedf(elapsed_ticks, 0.1), "camera_ticks": int(cue.get("camera_ticks")),
		"camera": str(scene.camera.position), "cursor": str(cue.cursor_position()) if cue.visible else "",
		"range": cue.visible and cue.range_visible(), "cursor_drawn": cue.visible and cue.cursor_visible(),
		"area_cells": cue.area_rects().size() if cue.visible else 0, "caption": cue.caption_layer.visible,
	}
	print("AI_CUE ", label, " ", phase, " ", JSON.stringify(state))
	if rendering:
		root.get_texture().get_image().save_png(out_dir.path_join("%s-%s.png" % [label, phase]))


func settle(scene: Node) -> void:
	var presentation: Node = scene.get_node("BattlePresentation")
	for _guard in range(600):
		if not presentation.combat_busy(scene.play_loop) and not scene.has_actor_motion() and not presentation.dialogue_active():
			return
		await process_frame
