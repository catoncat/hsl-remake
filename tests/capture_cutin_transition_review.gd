extends SceneTree
## ≤15 s review clip for lane P4-presentation-tail: the ordinary cut-in's first-shot opening
## (24-tick additive ball zoom over the backdrop, then the 32-tick white-out fading over the
## attacker and the board), the held hurt pose with no return to neutral, the counter's shot
## without an opening, and the exchange-closing 16-tick darken ＋ 16-tick lighten over the
## map; then a lone killing blow (transition even on a single shot). Controlled fixture, not
## a natural playthrough. Run with Movie Maker:
##   tools/godot.sh --write-movie ignored/p4-cutin-transition/cutin_transition.avi --fixed-fps 60 --script res://tests/capture_cutin_transition_review.gd
var scene: Node
var presentation: Node


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("capture_cutin_transition_review needs an actual rendering window (Movie Maker)")
		quit(2)
		return
	root.title = "HSL cut-in opening／transition review"
	root.size = Vector2i(640, 480)
	scene = load("res://game/battle/scene/BattleSceneRuntime.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	scene.start_dev_first_control_harness()
	scene.get_node("BattleMusic").stop()
	presentation = scene.get_node("BattlePresentation")
	await hold(0.3)
	var Loop = scene.BattlePlayLoop
	var player: Dictionary = Loop._unit(scene.play_loop, "leonard")
	var enemy: Dictionary = Loop._unit(scene.play_loop, "actor021_1")
	enemy["coord"] = player["coord"] + Vector2i(1, 0)
	player["hit_bonus_accum"] = 9
	# Fixture only: both sides survive the exchange so the counter's shot closes it.
	enemy["max_hp"] = 400
	enemy["hp"] = 400
	player["max_hp"] = 400
	player["hp"] = 400
	enemy["combat_profile"]["attack_back"] = 100 # the counter's shot is the clip's subject
	scene.apply_loop(scene.play_loop, "test")
	var enemy_coord: Vector2i = enemy["coord"]
	assert(scene.scene_input.unit_id_at_grid(enemy_coord) == "actor021_1", "fixture enemy must sit on its cell")
	# 1. The player's attack answered by the enemy's counter: opening on the first shot, no
	#    transition between the shots, darken ＋ lighten after the counter.
	scene.menus.choose_command("attack")
	scene.scene_input.handle_pointer_motion(scene.grid_cell_center_to_logical_position(enemy_coord))
	await hold(0.2)
	scene.attack_selected_coord(enemy_coord)
	var receipt: Dictionary = scene.play_loop[scene.LoopKeys.LAST_COMBAT]
	print("CUTIN_TRANSITION_REVIEW reject=", scene.play_loop[scene.LoopKeys.LAST_ATTACK_REJECT], " hit=", receipt.get("hit"), " damage=", receipt.get("damage"), " counter=", not receipt.get("counter", {}).is_empty(), " clips=", Loop.CombatSequence.strikes(receipt).size())
	while presentation.combat_busy(scene.play_loop) or scene.has_actor_motion():
		await process_frame
	scene.flush_ai_playback()
	while scene.interaction_state != "action_menu" or scene.has_actor_motion() or presentation.combat_busy(scene.play_loop):
		scene.flush_ai_playback()
		await process_frame
	await hold(0.2)
	# 2. A lone killing blow: a single shot opens and closes with the transition; the hurt
	#    pose holds under the darken.
	presentation.cutin.play({"hit": true, "damage": 23, "defender_hp_before": 22, "defender_hp_after": 0, "attacker_id": "leonard", "defender_id": "actor021_1"}, Loop.unit(scene.play_loop, "leonard"), Loop.unit(scene.play_loop, "actor021_1"), false, Vector2(320, 240), Vector2(240, 240), [], [], {"leonard": true, "actor021_1": true})
	while presentation.cutin.busy():
		await process_frame
	await hold(0.2)
	print("CUTIN_TRANSITION_REVIEW_FINISHED")
	scene.queue_free()
	await process_frame
	quit(0)


func hold(seconds: float) -> void:
	var frames := int(round(seconds * 60.0))
	for _index in range(frames):
		await process_frame
