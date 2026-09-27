extends SceneTree
## GUI review of the section title card (OpeningCinematics, original_tick_counts.md §2):
## level 51's 棄卒 card captured at the moments the user's 2026-09-24 recording shows, with the
## hold cut on its first tick as in the recording. Run with a window and the fixed 60 fps
## clock so one frame is about one original tick:
##   tools/godot.sh --fixed-fps 60 --script res://tests/capture_section_title_review.gd
## Output: ignored/section-title-review/NN_<moment>.png + manifest.json (title tick, sub-state,
## band level／zoom, name level and the recording second the moment matches). Visual review
## input only, not a parity proof.
const RuntimeReadback = preload("res://tests/support/RuntimeReadback.gd")
const TestSuite = preload("res://tests/support/TestSuite.gd")
const OUT := "res://ignored/section-title-review"
## Recording second of title tick t (hold cut on its first tick): the first darkening frame is
## 27.60 s and the recording advances one tick per 1/60 s (fit to 29.36 band settled, 30.19
## name full, 31.07 name gone, 31.91 band gone — see original_tick_counts.md §2).
const RECORDING_TICK0 := 27.60
const RECORDING_TICK_SECONDS := 1.0 / 60.0
## [name, title tick] captured on the way in; the exit moments are counted from the skip.
const ENTRY := [["01_full_screen_darkening", 30], ["02_full_screen_dark", 52], ["03_band_shrinking", 80], ["04_band_settled", 108], ["05_name_shown", 159]]
const EXIT := [["06_name_fading_mid", 25], ["07_band_opening_mid", 76], ["08_band_gone", 100]]

var scene
var records: Array = []


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	scene = load("res://game/battle/scene/BattleSceneRuntime.tscn").instantiate()
	root.add_child(scene)
	create_timer(120).timeout.connect(func():
		if records.size() < ENTRY.size() + EXIT.size() + 1 and is_instance_valid(scene):
			print("SECTION_TITLE_CAPTURE_TIMEOUT ", RuntimeReadback.opening_timeline_summary(scene))
			quit(2))
	var coordinator = scene.opening_coordinator
	# Walks and delays before the card are sped up; the card keeps its product pacing.
	coordinator.walk_pixels_per_second = 6400.0
	coordinator.delay_token_seconds = 0.001
	var entry_index := 0
	var exit_index := 0
	var skip_tick := -1
	var board_captured := false
	while true:
		await process_frame
		if not coordinator.active:
			break
		var kind := str(coordinator.summary().get("current_event_kind", ""))
		if kind == "dialogue_message_id":
			var click := InputEventMouseButton.new()
			click.button_index = MOUSE_BUTTON_LEFT
			click.pressed = true
			coordinator.handle_input(click)
			continue
		var cinematics = coordinator.cinematics
		if kind == "section_title_resource" and cinematics._title != null and cinematics._title.visible:
			var tick: int = cinematics.title_ticks_done()
			if entry_index < ENTRY.size() and tick >= int(ENTRY[entry_index][1]):
				await _capture(str(ENTRY[entry_index][0]), tick, tick)
				entry_index += 1
			if skip_tick < 0 and entry_index >= ENTRY.size() and cinematics.title_hold_accepts_input():
				var key := InputEventKey.new()
				key.keycode = KEY_SPACE
				key.pressed = true
				skip_tick = cinematics.title_ticks_done()
				coordinator.handle_input(key)
			tick = cinematics.title_ticks_done()
			if skip_tick >= 0 and exit_index < EXIT.size() and tick - skip_tick - 1 >= int(EXIT[exit_index][1]):
				await _capture(str(EXIT[exit_index][0]), tick, 160 + int(EXIT[exit_index][1]))
				exit_index += 1
		var board = coordinator.winfail_board
		if kind == "winfail_board_refresh" and board != null and board.busy() and not board_captured and board.stage == "hold":
			await _capture("09_winfail_board", -1, 263 + 6 + 32)
			board_captured = true
	FileAccess.open(OUT + "/manifest.json", FileAccess.WRITE).store_string(JSON.stringify({"records": records, "skip_tick": skip_tick}, "  "))
	scene.queue_free()
	await process_frame
	var leaks: Array = await TestSuite.settle_audio_before_quit(self, 0.3)
	var passed := records.size() == ENTRY.size() + EXIT.size() + 1 and leaks.is_empty()
	print("SECTION_TITLE_CAPTURE_PASS" if passed else "SECTION_TITLE_CAPTURE_FAIL records=%d %s" % [records.size(), str(leaks)])
	quit(0 if passed else 1)


## `recording_tick`: the title tick on the recording's timeline (hold cut on its first tick).
func _capture(moment: String, tick: int, recording_tick: int) -> void:
	var file := "%s/%s.png" % [OUT, moment]
	# A headless dry run (flow check only) has no framebuffer to save.
	if DisplayServer.get_name() == "headless":
		file = ""
	else:
		RenderingServer.force_draw(false)
		root.get_texture().get_image().save_png(file)
	var state: Dictionary = scene.opening_coordinator.cinematics._title_state
	records.append({"moment": moment, "image": file, "title_tick": tick, "sub_state": int(state.get("sub", -1)),
		"band_level": int(state.get("band_level", 0)), "zoom": float(int(state.get("zoom", 0))) / 65536.0, "name_level": int(state.get("name_level", 0)),
		"recording_seconds": snappedf(RECORDING_TICK0 + recording_tick * RECORDING_TICK_SECONDS, 0.01)})
	await process_frame
