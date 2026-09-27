extends SceneTree
## ≤20 s review clip for lane P3-identity-and-cutin-leftovers: the ??? mask on the
## attack-target strip and the WINDOW20 status page of an enemy the player has not fought,
## the cut-in strip of a friendly AI's hit on that enemy (???), then the player's own hit
## (numbers, 32-tick neutral shot ＋ 78-tick hurt hold) and a miss (56-tick dodge hold).
## Controlled fixture, not a natural playthrough. Run with Movie Maker:
##   tools/godot.sh --write-movie ignored/p3-identity-mask/identity_mask.avi --fixed-fps 60 --script res://tests/capture_identity_mask_review.gd
var scene: Node
var presentation: Node


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("capture_identity_mask_review needs an actual rendering window (Movie Maker)")
		quit(2)
		return
	root.title = "HSL identity mask review"
	root.size = Vector2i(640, 480)
	scene = load("res://game/battle/scene/BattleSceneRuntime.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	scene.start_dev_first_control_harness()
	scene.get_node("BattleMusic").stop()
	presentation = scene.get_node("BattlePresentation")
	await hold(0.6)
	var Loop = scene.BattlePlayLoop
	var player: Dictionary = Loop._unit(scene.play_loop, "leonard")
	var enemy: Dictionary = Loop._unit(scene.play_loop, "actor021_1")
	var friend: Dictionary = Loop._unit(scene.play_loop, "actor023_1")
	enemy["coord"] = player["coord"] + Vector2i(1, 0)
	friend["coord"] = player["coord"] + Vector2i(1, 1)
	player["hit_bonus_accum"] = 9
	# Fixture only: a sturdier target survives every exchange in the clip.
	enemy["max_hp"] = 400
	enemy["hp"] = 400
	scene.apply_loop(scene.play_loop, "test")
	var enemy_coord: Vector2i = enemy["coord"]
	assert(scene.scene_input.unit_id_at_grid(enemy_coord) == "actor021_1", "fixture enemy must sit on its cell")
	# 1. Attack-target strip of the unknown enemy: ??? with the hit chance.
	scene.menus.choose_command("attack")
	await hover(enemy_coord, 2.0)
	scene.cancel_current_interaction()
	await hold(0.3)
	# 2. A click on the unknown enemy opens no page (0x443cfa); OPT-INFO=公開 opens it unmasked.
	scene.scene_input.handle_pointer_left_pressed(scene.grid_cell_center_to_logical_position(enemy_coord))
	await hold(2.4)
	scene.status_panel.hide()
	scene.menus.set_action_menu_visible(true)
	await hold(0.3)
	# 3. A friendly AI weapon hit on the unknown enemy: the victim shot's strip stays ???.
	var friend_view: Dictionary = Loop.unit(scene.play_loop, "actor023_1")
	var enemy_view: Dictionary = Loop.unit(scene.play_loop, "actor021_1")
	presentation.cutin.play({"hit": true, "damage": 7, "defender_hp_before": 400, "defender_hp_after": 393, "attacker_id": "actor023_1", "defender_id": "actor021_1"}, friend_view, enemy_view, false, Vector2(320, 240), Vector2(240, 240), [], [], {"actor023_1": true, "actor021_1": false})
	while presentation.cutin.busy():
		await process_frame
	await hold(0.3)
	# 4. The player's own hit: target confirmation makes the enemy known — numbers in the strip.
	scene.menus.choose_command("attack")
	await hover(enemy_coord, 0.8)
	scene.attack_selected_coord(enemy_coord)
	print("IDENTITY_MASK_REVIEW reject=", scene.play_loop[scene.LoopKeys.LAST_ATTACK_REJECT], " hit=", scene.play_loop[scene.LoopKeys.LAST_COMBAT].get("hit"), " damage=", scene.play_loop[scene.LoopKeys.LAST_COMBAT].get("damage"), " known=", scene.play_loop[scene.LoopKeys.KNOWN_UNIT_IDS])
	while presentation.combat_busy(scene.play_loop) or scene.has_actor_motion():
		await process_frame
	# The attack ends Leonard's action; flush the enemy phase (the test seam) so the clip
	# stays within 20 s.
	scene.flush_ai_playback()
	while scene.interaction_state != "action_menu" or scene.has_actor_motion() or presentation.combat_busy(scene.play_loop):
		scene.flush_ai_playback()
		await process_frame
	await hold(0.3)
	# 5. A miss on the same (now known) enemy: the 56-tick dodge hold.
	presentation.cutin.play({"hit": false, "damage": 0, "defender_hp_before": 393, "defender_hp_after": 393, "attacker_id": "leonard", "defender_id": "actor021_1"}, Loop.unit(scene.play_loop, "leonard"), Loop.unit(scene.play_loop, "actor021_1"), false, Vector2(320, 240), Vector2(240, 240), [], [], {"leonard": true, "actor021_1": true})
	while presentation.cutin.busy():
		await process_frame
	await hold(0.4)
	print("IDENTITY_MASK_REVIEW_FINISHED")
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
