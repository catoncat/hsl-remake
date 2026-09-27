extends SceneTree
## Windowed review of the title screen: the framed title (item 1 selected, V1.06 bottom-left), the mouse
## hovering 戰場記錄 (red lit shape), keyboard selection on 離開遊戲, the 沒有戰場記錄 hint,
## the confirmed 開始新故事 holding lit, the fade into the intro film (movie.pak start.ani paged from the WebP
## sheets), the skipped film handing over to the product opening, and the ending film.
## Output: ignored/title-review/*.png + manifest.json (visual review input, not parity proof).
const CampaignProgress = preload("res://game/battle/runtime/CampaignProgress.gd")
const OUT := "res://ignored/title-review/"
var scene: Node
var failures: Array[String] = []
var records: Array = []


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Title review requires a rendering window")
		quit(2)
		return
	CampaignProgress.reset_campaign()
	root.title = "HSL Title Review"
	root.size = Vector2i(640, 480)
	create_timer(90).timeout.connect(func(): push_error("Title review timed out"); quit(2))
	DirAccess.make_dir_recursive_absolute(OUT)
	scene = load("res://game/title/TitleScreen.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	await process_frame
	await process_frame
	await shot("00-title-framed")
	# The real pointer would keep re-deciding hover in a window; drive it by hand for the shot.
	scene.set_process_unhandled_input(false)
	scene.hover_at(Vector2(197 + 50 + 70, 161 + 113 + 18))
	await shot("01-hover-battle-record-lit")
	scene.hover_at(Vector2(10, 10))
	scene.select(2)
	await shot("02-select-quit")
	scene.select(1)
	scene.confirm()
	await shot("03-no-record-hint")
	await create_timer(scene.HINT_SECONDS + 0.2).timeout
	scene.select(0)
	scene.confirm()
	await create_timer(scene.CONFIRM_HOLD_SECONDS * 0.5).timeout
	await shot("04-new-story-confirm-hold")
	await create_timer(scene.CONFIRM_HOLD_SECONDS * 0.5 + scene.FADE_TO_BLACK_SECONDS * 0.5).timeout
	await shot("04b-new-story-fading")
	await create_timer(scene.FADE_TO_BLACK_SECONDS * 0.5 + 0.4).timeout
	await process_frame
	await process_frame
	check(str(scene.transition.get("status", "")) == "movie" and scene.intro_player != null, "the fade leads into the intro film")
	await create_timer(1.0).timeout
	await shot("05-intro-film-1s")
	if scene.intro_player != null:
		# Jump the film clock to a frame on the second sheet (sheet boundary at frame 204).
		scene.intro_player.elapsed = 20.0
		await process_frame
		await shot("06-intro-film-20s")
		scene.skip_intro()
	await process_frame
	await process_frame
	var runtime = current_scene
	check(runtime != null and runtime.has_method("apply_loop"), "the skipped intro hands over to BattleSceneRuntime")
	await create_timer(1.0).timeout
	await shot("07-product-opening")
	# The ending film (winfail059's actPlayMovie), played directly at a mid-film frame.
	var film = load("res://game/title/MoviePlayer.gd").new()
	root.add_child(film)
	scene = film
	film.play("end")
	film.elapsed = 15.0
	await process_frame
	await shot("08-ending-film-15s")
	film.queue_free()
	await process_frame
	scene = runtime
	# GAME OVER screen (reached from a defeat result's 回主選單): capture it after its fade-in,
	# then dismiss it back to the title.
	if is_instance_valid(runtime):
		runtime.queue_free()
		await process_frame
	var game_over = load("res://game/title/GameOverScreen.tscn").instantiate()
	root.add_child(game_over)
	current_scene = game_over
	scene = game_over
	await create_timer(3.4).timeout # the unhurried 0x42aea0 timeline reaches its wait ≈190 ticks
	await shot("09-game-over")
	game_over.dismiss()
	await create_timer(game_over.FADE_OUT_SECONDS + 0.4).timeout
	await process_frame
	await process_frame
	check(current_scene != null and current_scene.has_method("summary") and str(current_scene.summary().get("schema", "")) == "hsl_title_screen.v1", "GAME OVER hands back to the title")
	finish()


func shot(label: String) -> void:
	await create_timer(0.12).timeout
	records.append({"capture": label, "summary": scene.summary() if is_instance_valid(scene) and scene.has_method("summary") else {}})
	RenderingServer.force_draw(false)
	check(root.get_texture().get_image().save_png(OUT + label + ".png") == OK, "capture " + label)


func check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)
		push_error(label)


func finish() -> void:
	var file := FileAccess.open(OUT + "manifest.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"schema": "hsl_title_review.v1", "records": records, "failures": failures}, "  "))
	file.close()
	CampaignProgress.reset_campaign()
	# Quitting while the title theme streams intermittently leaks its Ogg playback
	# (audio-thread race at exit); silence it first so the diagnostics stay clean.
	var music = current_scene.get_node_or_null("TitleMusic") if current_scene != null else null
	if music != null:
		music.stop()
		await create_timer(0.3).timeout
	await process_frame
	if failures.is_empty():
		print("TITLE_REVIEW_PASS shots=%d output=%s" % [records.size(), OUT])
		quit(0)
	else:
		print("TITLE_REVIEW_FAIL count=%d" % failures.size())
		quit(1)
