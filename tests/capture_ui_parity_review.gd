extends SceneTree
## ≤30 s review clip for lane P2-battle-ui-parity: pulsing original range cells (move,
## then attack) and the hover identity strip (??? before the enemy is fought, revealed
## after). Controlled fixture, not a natural playthrough. Run with Movie Maker:
##   tools/godot.sh --write-movie ignored/p2-ui-parity/ui_parity.avi --fixed-fps 60 --script res://tests/capture_ui_parity_review.gd
var scene: Node
var presentation: Node
var enemy_coord: Vector2i
var friend_coord: Vector2i


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("capture_ui_parity_review needs an actual rendering window (Movie Maker)")
		quit(2)
		return
	root.title = "HSL UI parity review"
	root.size = Vector2i(640, 480)
	scene = load("res://game/battle/scene/BattleSceneRuntime.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	scene.start_dev_first_control_harness()
	scene.get_node("BattleMusic").stop()
	presentation = scene.get_node("BattlePresentation")
	# Let the first-control handoff settle before the fixture moves units next to the player.
	await hold(1.0)
	var player: Dictionary = scene.BattlePlayLoop._unit(scene.play_loop, "leonard")
	var enemy: Dictionary = scene.BattlePlayLoop._unit(scene.play_loop, "actor021_1")
	var friend: Dictionary = scene.BattlePlayLoop._unit(scene.play_loop, "actor023_1")
	enemy["coord"] = player["coord"] + Vector2i(1, 0)
	friend["coord"] = player["coord"] + Vector2i(-2, 0)
	player["hit_bonus_accum"] = 9
	# Fixture only: a sturdier target survives the exchange so the revealed strip can be shown.
	enemy["max_hp"] = 400
	enemy["hp"] = 400
	scene.apply_loop(scene.play_loop, "test")
	enemy_coord = enemy["coord"]
	friend_coord = friend["coord"]
	assert(scene.scene_input.unit_id_at_grid(enemy_coord) == "actor021_1" and scene.scene_input.unit_id_at_grid(friend_coord) == "actor023_1", "fixture units must sit on their cells")
	scene.menus.choose_command("move")
	await hover(player["coord"] + Vector2i(0, 3), 3.0)
	await hover(enemy_coord, 3.0)
	await hover(friend_coord, 2.5)
	scene.cancel_current_interaction()
	await hold(0.8)
	scene.menus.choose_command("attack")
	await hover(enemy_coord, 3.0)
	scene.attack_selected_coord(enemy_coord)
	print("UI_PARITY_REVIEW reject=", scene.play_loop[scene.LoopKeys.LAST_ATTACK_REJECT], " hp_after=", scene.BattlePlayLoop.unit(scene.play_loop, "actor021_1")["hp"], " combat=", scene.play_loop[scene.LoopKeys.LAST_COMBAT].get("defender_hp_after"), scene.play_loop[scene.LoopKeys.LAST_COMBAT].get("damage"))
	while presentation.combat_busy(scene.play_loop) or scene.has_actor_motion():
		await process_frame
	await hold(0.5)
	print("UI_PARITY_REVIEW known=", scene.play_loop[scene.LoopKeys.KNOWN_UNIT_IDS])
	# The attack ends Leonard's action; flush the enemy phase (the test seam) so the clip
	# stays within 30 s, then hover the fought enemy from the next move selection.
	scene.flush_ai_playback()
	while scene.interaction_state != "action_menu" or scene.has_actor_motion() or presentation.combat_busy(scene.play_loop):
		scene.flush_ai_playback()
		await process_frame
	await hold(0.5)
	scene.menus.choose_command("move")
	var fought: Dictionary = scene.BattlePlayLoop.unit(scene.play_loop, "actor021_1")
	print("UI_PARITY_REVIEW interaction=", scene.interaction_state, " known=", scene.BattlePlayLoop.unit_known(scene.play_loop, "actor021_1"), " hp=", fought["hp"], " coord=", fought["coord"])
	scene.center_camera_on_grid(fought["coord"])
	await hover(fought["coord"], 3.0)
	print("UI_PARITY_REVIEW_FINISHED")
	scene.queue_free()
	await process_frame
	quit(0)


func hover(coord: Vector2i, seconds: float) -> void:
	var point: Vector2 = scene.grid_cell_center_to_logical_position(coord)
	scene.scene_input.handle_pointer_motion(point)
	await hold(seconds)


func hold(seconds: float) -> void:
	var frames := int(round(seconds * 60.0))
	for _index in range(frames):
		await process_frame
