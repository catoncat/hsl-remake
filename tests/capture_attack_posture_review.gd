extends SceneTree
## Manual-acceptance recording of the cut-in playing each actor's own ANIMAL program (lane
## R30): 雷歐納德's ordinary attack (the `action` dispatch) then his 氣刃斬 (the `s_action`
## cast lead — banner over the shadowed map, insets, portrait — before the EFFECTS script),
## both from real play-loop receipts against 帝國一般兵 021. A rendering fixture, not a
## natural playthrough and not a parity verdict. Raw output stays under ignored/.
##
##   tools/play.sh --screen 0 --write-movie ignored/r30/attack-cast.avi --fixed-fps 60 \
##     --disable-vsync --script res://tests/capture_attack_posture_review.gd
const BattleFixture = preload("res://tests/support/BattleFixture.gd")
const Loop = preload("res://game/battle/scene/BattlePlayLoop.gd")
var scene: Node
var view: Node


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("The posture review needs an actual rendering window")
		quit(2)
		return
	root.title = "HSL — ANIMAL attack／cast postures"
	root.size = Vector2i(640, 480)
	scene = load("res://game/battle/scene/BattleSceneRuntime.tscn").instantiate()
	scene.scenario_path = BattleFixture.PATH
	scene.startup_mode = "dev_first_control"
	root.add_child(scene)
	current_scene = scene
	scene.start_dev_first_control_harness()
	scene.set_process(false)
	scene.get_node("BattleMusic").stop() # Isolate the action cues.
	view = scene.get_node("BattlePresentation")
	view._map_config = scene.map_config
	var loop: Dictionary = scene.play_loop.duplicate(true)
	var leonard: Dictionary = Loop._unit(loop, "leonard")
	leonard["stamina"] = 20
	var soldier: Dictionary = Loop._unit(loop, "enemy021_1")
	soldier["coord"] = leonard["coord"] + Vector2i(1, 0)
	# Both blows stay non-lethal: with the scene's own processing paused for the fixture, a
	# kill leaves the pending death disposal in place and the next clip is not redrawn.
	soldier["hp"] = 200
	soldier["max_hp"] = 200
	scene.apply_loop(loop, "test")
	scene.menus.set_action_menu_visible(false)
	scene._process(0)
	print("POSTURE_REVIEW_READY")
	await create_timer(0.5).timeout
	for command in ["attack", "special"]:
		var selected: Dictionary = Loop.choose_command(scene.play_loop.duplicate(true), command)
		# 特殊技 opens the skill page first (menus_ui/README.md#5); choosing the skill starts the targeting.
		if command == "special": selected = Loop.choose_special(selected, "special:magicOTHER:magicCode01")
		var fired: Dictionary = Loop.attack_target(selected, "enemy021_1", func(_bound): return 0)
		var strike: Dictionary = fired["last_attack"]
		print("POSTURE_REVIEW_CLIP command=", command, " skill=", str(strike.get("skill_name", "")), " frame=", Engine.get_frames_drawn())
		view._show_strike(strike, scene.play_loop, scene.map_config, false)
		view.cutin.set_process(true)
		while view.cutin.busy():
			await process_frame
		await create_timer(0.6).timeout
	print("POSTURE_REVIEW_FINISHED frame=", Engine.get_frames_drawn())
	await create_timer(0.3).timeout
	scene.queue_free()
	await process_frame
	await create_timer(0.3).timeout
	quit(0)
