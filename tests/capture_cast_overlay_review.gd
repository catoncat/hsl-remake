extends SceneTree
## Manual-acceptance capture for lane P5 (map overlays across a cast,
## docs/evidence_packets/static_reverse/original_cast_overlays.md): chapter-1 緹娜 治癒之水
## (battle_010) and 雷歐納德 氣刃斬 (battle_051), and the authored 龍息 (蕾雅, battle_200), each
## driven through the product route — command, spell button, pointer hover on the target cell,
## `attack_selected_coord` (the click handler) — with the scene's own `_process` running. At
## each phase (target select → confirm frame → pre-cast cue → cast lead → effect → result →
## next control) it logs which overlays are visible and, with a rendering window, saves a
## screenshot. The target is moved next to the caster and earlier units wait: a rendering
## fixture, not a natural playthrough, not a parity verdict.
##
##   tools/godot.sh --headless --script res://tests/capture_cast_overlay_review.gd          # log only
##   tools/play.sh --screen 0 --script res://tests/capture_cast_overlay_review.gd -- <out_dir>
const Loop = preload("res://game/battle/scene/BattlePlayLoop.gd")
const LoopKeys = preload("res://game/sim/LoopKeys.gd")
const CASES := [
	{"label": "ch1-tina-heal-water", "scenario": "res://content/battles/battle_010.json", "caster": "tina", "command": "magic", "skill_name": "治癒之水", "target": "leonard"},
	{"label": "ch1-leonard-qi-blade", "scenario": "res://content/battles/battle_051.json", "caster": "leonard", "command": "special", "skill_name": "氣刃斬", "target": ""},
	{"label": "authored-reia-dragon-breath", "scenario": "res://content/battles/battle_200.json", "caster": "reia", "command": "magic", "skill_name": "龍息", "target": ""},
]
var out_dir := ""
var rendering := false


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	rendering = DisplayServer.get_name() != "headless"
	var args := OS.get_cmdline_user_args()
	if rendering:
		out_dir = args[0] if not args.is_empty() else "res://ignored/p5-cast-overlays"
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir))
		root.size = Vector2i(640, 480)
	for spec in CASES:
		await run_case(spec)
	print("CAST_OVERLAY_REVIEW_FINISHED")
	quit(0)


func run_case(spec: Dictionary) -> void:
	var scene: Node = load("res://game/battle/scene/BattleSceneRuntime.tscn").instantiate()
	scene.scenario_path = spec["scenario"]
	scene.startup_mode = "dev_first_control"
	root.add_child(scene)
	current_scene = scene
	await process_frame
	scene.start_dev_first_control_harness()
	scene.get_node("BattleMusic").stop()
	await settle(scene)
	var caster_id: String = spec["caster"]
	var caster: Dictionary = Loop._unit(scene.play_loop, caster_id)
	caster["mp"] = int(caster["max_mp"])
	caster["stamina"] = 60
	# Fixture: the target (an enemy, or the named ally for a support spell) stands next to the
	# caster, sturdy enough to survive.
	var enemy_id: String = spec["target"]
	for unit in scene.play_loop[LoopKeys.UNITS]:
		if enemy_id == "" and not bool(unit.get("defeated", false)) and Loop._are_enemies(caster, unit) and Loop.Footprint.radius(unit) == 0:
			enemy_id = str(unit["id"])
	var enemy: Dictionary = Loop._unit(scene.play_loop, enemy_id)
	enemy["coord"] = caster["coord"] + Vector2i(1, 0)
	enemy["max_hp"] = 400
	enemy["hp"] = 400 if spec["target"] == "" else 200
	scene.apply_loop(scene.play_loop, "test")
	# Earlier player units of the round wait (the product 待機 command) until the caster's turn.
	for _turn in range(8):
		await settle(scene)
		if scene.selected_unit_id == caster_id or str(scene.play_loop.get(LoopKeys.SELECTED_UNIT_ID, "")) == caster_id:
			break
		if scene.interaction_state == "action_menu" and scene.selected_unit_id != "":
			scene.menus.choose_command("wait")
		else:
			scene.flush_ai_playback()
	scene.select_actor(caster_id)
	await settle(scene)
	var skill_id := ""
	var options: Array = Loop.magic_options(scene.play_loop, caster_id) if spec["command"] == "magic" else Loop.special_options(scene.play_loop, caster_id)
	for option in options:
		if str(option.get("name", "")) == spec["skill_name"]:
			skill_id = str(option["id"])
	scene.menus.choose_command(spec["command"])
	if scene.magic_panel.visible:
		scene.magic_panel.choices[skill_id].pressed.emit()
	scene.scene_input.handle_pointer_motion(scene.grid_cell_center_to_logical_position(enemy["coord"]))
	await hold(0.6)
	await sample(scene, spec, "1-target-select")
	scene.attack_selected_coord(enemy["coord"])
	var presentation: Node = scene.get_node("BattlePresentation")
	await sample(scene, spec, "2-confirm-frame")
	var shot := {}
	while presentation.combat_busy(scene.play_loop) or scene.has_actor_motion():
		var phase := phase_of(presentation)
		if phase != "" and not shot.has(phase):
			shot[phase] = true
			await sample(scene, spec, phase)
		await process_frame
	await sample(scene, spec, "7-after-result")
	await settle(scene)
	await sample(scene, spec, "8-next-control")
	scene.queue_free()
	await process_frame
	await create_timer(0.3).timeout


func phase_of(presentation: Node) -> String:
	if presentation.attack_cue.visible:
		return "3-pre-cast-cue"
	var cutin: CanvasLayer = presentation.cutin
	if cutin.busy():
		var clip: Dictionary = cutin.clips[0] if not cutin.clips.is_empty() else {}
		if not clip.get("release_emitted", false):
			return "4-cast-lead"
		if not clip.get("impact_emitted", false):
			return "5-effect"
		return "5b-effect-after-impact"
	if presentation.magic_impact.busy():
		return "6-impact-bars"
	if presentation.aftermath.busy():
		return "6b-aftermath"
	return ""


## Reads the overlays as drawn: waits for the frame's `_process` (and, rendering, its draw).
func sample(scene: Node, spec: Dictionary, phase: String) -> void:
	if rendering:
		await RenderingServer.frame_post_draw
	else:
		await process_frame
		await process_frame
	var presentation: Node = scene.get_node("BattlePresentation")
	var overlay: Node2D = scene.move_overlay
	var attack_cells := 0
	var move_cells := 0
	for child in overlay.get_children():
		if str(child.name).begins_with("AttackCell"): attack_cells += 1
		elif str(child.name).begins_with("MoveCell"): move_cells += 1
	var state := {
		"range_cells": overlay.visible and attack_cells > 0, "move_cells": overlay.visible and move_cells > 0,
		"attack_cue": presentation.attack_cue.visible, "cursor": presentation.selection_cursor.visible,
		"identity_strip": presentation.target_vitals.visible, "hit_preview": presentation.combat_label.visible,
		"action_menu": scene.action_menu.visible, "magic_panel": scene.magic_panel.visible,
		"cutin": presentation.cutin.busy(), "cutin_caption": presentation.cutin.busy() and presentation.cutin.result.visible,
	}
	print("CAST_OVERLAY ", spec["label"], " ", phase, " ", JSON.stringify(state))
	if rendering:
		var image := root.get_texture().get_image()
		image.save_png(out_dir.path_join("%s-%s.png" % [spec["label"], phase]))


func settle(scene: Node) -> void:
	var presentation: Node = scene.get_node("BattlePresentation")
	for _guard in range(600):
		if not presentation.combat_busy(scene.play_loop) and not scene.has_actor_motion() and not presentation.dialogue_active():
			return
		await process_frame


func hold(seconds: float) -> void:
	await create_timer(seconds).timeout
