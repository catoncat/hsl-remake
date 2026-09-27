extends SceneTree
## Debug freeze (game/debug/DebugPause.gd, user request 2026-09-24) on the real battle scene:
## P reaches the freeze before any scene handler and freezes everything (process, tweens, game
## timers, music, game input); N runs exactly one frame; P resumes and the same key reaches the
## game again. The census keeps game code from advancing under a freeze.
const Loop = preload("res://game/battle/scene/BattlePlayLoop.gd")
const BattleFixture = preload("res://tests/support/BattleFixture.gd")
const TestSuite = preload("res://tests/support/TestSuite.gd")
## Game scripts allowed to process while the tree is paused: what a freeze must leave usable
## (the resume prompt, the drawn mouse cursor, the Tab 重製選項 page, the freeze itself).
const ALWAYS_ALLOWED := ["res://game/debug/DebugPause.gd", "res://game/battle/runtime/CampaignProgress.gd", "res://game/cursor/GameCursor.gd", "res://game/settings/RemakeOptionsHotkey.gd"]

var failures: Array[String] = []
var checks := 0


class Probe extends Node:
	var frames := 0
	var value := 0.0

	func _process(_delta: float) -> void:
		frames += 1


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	await freeze_case()
	census()
	failures.append_array(await TestSuite.settle_audio_before_quit(self, 0.3))
	print("DEBUG_PAUSE_TESTS_", "PASS" if failures.is_empty() else "FAIL", " checks=", checks)
	quit(0 if failures.is_empty() else 1)


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		push_error(message)


func key(code: Key) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = code
	event.pressed = true
	return event


func frames(count: int) -> void:
	for i in count:
		await process_frame


func freeze_case() -> void:
	var freeze: Node = root.get_node_or_null("DebugPause")
	check(freeze != null, "the DebugPause autoload is installed")
	if freeze == null:
		return
	var scene = load("res://game/battle/scene/BattleSceneRuntime.tscn").instantiate()
	scene.scenario_path = BattleFixture.PATH
	scene.startup_mode = "dev_first_control"
	root.add_child(scene)
	scene.start_dev_first_control_harness()
	scene.apply_loop(Loop.select_player_unit(scene.play_loop, "leonard"), "test")
	scene.ai_playback_active = false
	scene.interaction_state = "action_menu"
	scene.apply_loop(scene.play_loop, "test")
	var music: AudioStreamPlayer = scene.get_node("BattleMusic")
	if not music.playing:
		if music.stream == null: # the fixture scene starts silent; any track will do for the freeze
			music.stream = load("res://content/imported/hsl/music/08.ogg")
		music.play()
	var probe := Probe.new()
	scene.add_child(probe)
	probe.create_tween().tween_property(probe, "value", 1000.0, 1000.0)
	await frames(3)
	check(root.get_child(root.get_child_count() - 1) == freeze, "the freeze keeps itself root's last child, so P／N reach it before the scene's any-key handlers")
	check(probe.frames > 0 and music.playing, "the scene runs and its music plays before the freeze")

	root.push_input(key(KEY_P))
	check(freeze.held and paused and root.is_input_handled(), "P freezes the tree and is consumed before any scene handler sees it")
	check(freeze.badge.visible, "the freeze badge shows while frozen")
	var frozen_frames: int = probe.frames
	var frozen_value: float = probe.value
	var fired := {"timer": false}
	create_timer(0.02, false).timeout.connect(func() -> void: fired["timer"] = true)
	await TestSuite.settle_wall_clock(self, 0.15)
	check(probe.frames == frozen_frames and is_equal_approx(probe.value, frozen_value), "nothing processes or tweens while frozen")
	check(not fired["timer"], "a game timer (process_always = false) waits out the freeze")
	check(music.stream_paused and not music.playing, "the music pauses with the freeze")
	root.push_input(key(KEY_ESCAPE))
	await frames(2)
	check(not scene.system_menu.active(), "game input is swallowed while frozen (Esc does not raise the system scroll)")

	root.push_input(key(KEY_N))
	await frames(3)
	check(probe.frames == frozen_frames + 1, "N runs exactly one frame (ran %d)" % (probe.frames - frozen_frames))
	check(probe.value > frozen_value, "the step frame advances tweens too")
	check(paused and freeze.stepped_frames == 1, "the tree freezes again after the step and the badge counts it")
	root.push_input(key(KEY_N))
	root.push_input(key(KEY_N))
	await frames(4)
	check(probe.frames == frozen_frames + 3 and freeze.stepped_frames == 3, "each N queues one more frame (ran %d)" % (probe.frames - frozen_frames))

	root.push_input(key(KEY_P))
	check(not freeze.held and not paused and not freeze.badge.visible, "P again resumes and hides the badge")
	await frames(3)
	check(probe.frames > frozen_frames + 3 and music.playing, "the scene and its music run again")
	await TestSuite.settle_wall_clock(self, 0.1)
	check(fired["timer"], "the waiting game timer fires once the game runs again")
	root.push_input(key(KEY_ESCAPE))
	await frames(2)
	check(scene.system_menu.active(), "the same Esc raises the system scroll once the game runs (the freeze was what swallowed it)")
	scene.queue_free()
	await frames(2)


## Game code must not advance on its own while frozen: SceneTree timers follow the pause and
## only the listed scripts process always (scripts and scenes alike).
func census() -> void:
	var timers := 0
	var offenders: Array[String] = []
	for path in game_files("res://game", ".gd"):
		var lines := FileAccess.get_file_as_string(path).split("\n")
		for index in lines.size():
			var line: String = lines[index]
			if line.strip_edges().begins_with("#"):
				continue
			var at := line.find("create_timer(")
			if at >= 0:
				timers += 1
				var args := call_args(line, at + "create_timer".length())
				if args.size() < 2 or args[1] != "false":
					offenders.append("%s:%d timer runs through a freeze" % [path, index + 1])
			if (line.contains("PROCESS_MODE_ALWAYS") and not path in ALWAYS_ALLOWED) or line.contains("PROCESS_MODE_WHEN_PAUSED"):
				offenders.append("%s:%d processes while paused" % [path, index + 1])
	for path in game_files("res://game", ".tscn"):
		var text := FileAccess.get_file_as_string(path)
		if text.contains("process_mode = 2") or text.contains("process_mode = 3"):
			offenders.append("%s processes while paused" % path)
	check(timers >= 2, "the census reads the game's SceneTree timers (%d)" % timers)
	check(offenders.is_empty(), "game code does not advance under a freeze: " + ", ".join(offenders))


func game_files(dir: String, suffix: String) -> Array[String]:
	var found: Array[String] = []
	for name in DirAccess.get_files_at(dir):
		if name.ends_with(suffix):
			found.append(dir.path_join(name))
	for sub in DirAccess.get_directories_at(dir):
		found.append_array(game_files(dir.path_join(sub), suffix))
	return found


## The top-level arguments of the call whose "(" is at `open` (quotes and nesting respected).
static func call_args(line: String, open: int) -> PackedStringArray:
	var args := PackedStringArray()
	var depth := 0
	var start := open + 1
	var quote := ""
	for i in range(open, line.length()):
		var c := line[i]
		if quote != "":
			if c == quote:
				quote = ""
		elif c == "\"" or c == "'":
			quote = c
		elif c == "(":
			depth += 1
		elif c == ")":
			depth -= 1
			if depth == 0:
				args.append(line.substr(start, i - start).strip_edges())
				return args
		elif c == "," and depth == 1:
			args.append(line.substr(start, i - start).strip_edges())
			start = i + 1
	return args
