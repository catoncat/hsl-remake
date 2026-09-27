extends SceneTree
## Windowed review of the GameClear sequence (level 998): one frame per phase — Over001 over
## the dusk castle, the STORYOVER dialogue on black, Over002, the party showcase cards and the
## credits scroll — at normal remake pacing, skipping ahead by key. Output ignored/game-clear-review/.

const GameClearScene = preload("res://game/title/GameClearScreen.tscn")

var OUT := "res://ignored/game-clear-review/"
var scene: Node
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("GameClear review requires a rendering window")
		quit(2)
		return
	root.title = "HSL GameClear Review"
	root.size = Vector2i(640, 480)
	DirAccess.make_dir_recursive_absolute(OUT)
	var clear_script: Script = load("res://game/title/GameClearScreen.gd")
	var members: Array = []
	for pair in [["001", "雷歐納德"], ["002", "緹娜"], ["003", "琥"], ["004", "漢克斯"], ["005", "雪拉"]]:
		members.append({"actor_id": pair[0], "name": pair[1], "portrait": "res://content/imported/hsl/chapter01/portraits/%s.png" % pair[0]})
	clear_script.set("showcase", members)
	scene = GameClearScene.instantiate()
	root.add_child(scene)
	current_scene = scene
	# Over001 over the dusk castle (defProcClearBOSS state 1), then a key into the dialogue.
	await create_timer(3.0).timeout
	await shot("00-epilogue-1")
	scene.advance()
	# STORYOVER on black (state 3): the first line after its 1 s pause, then confirm through
	# to the footsteps pause (step 16) and the last line.
	await create_timer(1.4).timeout
	await shot("01-storyover-line-2396")
	var deadline := Time.get_ticks_msec() + 20000
	while str(scene.summary().get("phase", "")) == "epilogue" and int(scene.summary().get("epilogue_step", -1)) < 16 and Time.get_ticks_msec() < deadline:
		if bool(scene.summary().get("epilogue_waiting_confirm", false)):
			scene.advance()
		await process_frame
	await create_timer(0.3).timeout
	await shot("01b-storyover-footsteps-pause")
	deadline = Time.get_ticks_msec() + 30000
	var last_shot := false
	while str(scene.summary().get("phase", "")) == "epilogue" and Time.get_ticks_msec() < deadline:
		if bool(scene.summary().get("epilogue_waiting_confirm", false)):
			if not last_shot and (scene.summary().get("epilogue_messages", []) as Array).size() == 10:
				last_shot = true
				await shot("01c-storyover-last-line-2404")
			scene.advance()
		await process_frame
	check(str(scene.summary().get("phase", "")) == "epilogue_2", "the STORYOVER dialogue ends within its pauses and reveals Over002")
	await create_timer(1.6).timeout
	await shot("02-epilogue-2")
	scene.advance()
	await create_timer(1.6).timeout
	await shot("03-showcase-leonard")
	await create_timer(2.4).timeout
	await shot("04-showcase-tina")
	scene.advance()
	await create_timer(6.0).timeout
	await shot("05-credits-rolling")
	var credits_deadline := Time.get_ticks_msec() + 60000
	while str(scene.summary().get("phase", "")) != "waiting" and Time.get_ticks_msec() < credits_deadline:
		await process_frame
	await shot("06-credits-end")
	check(str(scene.summary().get("phase", "")) == "waiting", "the credits end waiting for input")
	# Quitting while the score streams intermittently leaks its Ogg playback (audio-thread
	# race at exit); silence it before freeing the scene.
	var music = scene.get_node_or_null("ClearMusic")
	if music != null:
		music.stop()
		await create_timer(0.3).timeout
	scene.queue_free()
	await process_frame
	await process_frame
	if failures.is_empty():
		print("GAME_CLEAR_REVIEW_PASS output=%s" % OUT)
		quit(0)
	else:
		print("GAME_CLEAR_REVIEW_FAIL count=%d" % failures.size())
		quit(1)


func shot(label: String) -> void:
	await create_timer(0.12).timeout
	RenderingServer.force_draw(false)
	check(root.get_texture().get_image().save_png(OUT + label + ".png") == OK, "capture " + label)


func check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)
		push_error(label)
