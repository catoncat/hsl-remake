extends "res://tests/support/TestSuite.gd"

## Camera glide (lane R6-P2). The original moves the battle view with 0x43bf30: every tick
## 0x45e80d moves each axis by half the remaining distance, clamped to ±32 px (±16 in story
## phases), landing within 4 px (static-derived, original_script_camera_scroll.md). The
## 2026-09-24 recording shows the same shape per frame — 32→24→12→6 px, 64→24→12→6
## (runtime-measured, camera_panel_motion/README.md). The census half checks that no game
## file writes the camera position except BattleCameraController, so every camera move
## (battle focus, script scroll, speed scroll, edge pan, cut) goes through the controller.

const BattleCameraController = preload("res://game/common/BattleCameraController.gd")
const OpeningCinematics = preload("res://game/battle/runtime/opening/OpeningCinematics.gd")
const MapSceneConfig = preload("res://game/battle/runtime/MapSceneConfig.gd")
const OriginalTick = preload("res://game/common/OriginalTick.gd")
const BattlePanelMotion = preload("res://game/battle/scene/BattlePanelMotion.gd")
const RuntimeReadback = preload("res://tests/support/RuntimeReadback.gd")
const CONTROLLER_PATH := "res://game/common/BattleCameraController.gd"
## Panels that must open and close through BattlePanelMotion (the modal list and the loot
## window; checked in BattleSceneMenus／BattleSettlementController by the attach census).
const PANEL_SCRIPTS := ["BattleStatusPanel.gd", "BattleItemPanel.gd", "BattleMagicPanel.gd", "BattleGrowthPanel.gd", "BattleLootPanel.gd"]


func _init() -> void:
	tag = "CAMERA_PANEL_MOTION_TESTS"


func run() -> void:
	_test_glide_steps()
	_test_glide_through_controller()
	_test_focus_frames_at_view_320_192()
	_test_story_step_matches_script_seconds()
	_test_walk_follow_request()
	_test_walk_follow_through_controller()
	_test_panel_open_curve()
	await _test_status_panel_motion()
	await _test_panel_shade_fade()
	_test_every_panel_attaches_motion()
	run_opening_camera()


func _test_glide_steps() -> void:
	# One axis, 110 px: 32, 32, 23, 11, 6, 3 then land (remaining 3 ≤ 4).
	var current := Vector2i(0, 0)
	var steps: Array[int] = []
	while not BattleCameraController.scroll_landed(current, Vector2i(110, 0), BattleCameraController.SCROLL_TOLERANCE):
		var next := BattleCameraController.scroll_step(current, Vector2i(110, 0), BattleCameraController.BATTLE_SCROLL_STEP)
		steps.append(next.x - current.x)
		current = next
	_assert_eq(steps, [32, 32, 23, 11, 6, 3], "the battle glide halves the rest per tick, capped at 32 px")
	# Diagonal: both axes move in the same call, each capped separately (not a straight line).
	var diagonal := BattleCameraController.scroll_step(Vector2i(0, 0), Vector2i(-300, -40), 32)
	_assert_eq(diagonal, Vector2i(-32, -20), "each axis is halved and clamped on its own")
	_assert_eq(BattleCameraController.scroll_ticks(Vector2.ZERO, Vector2(110, 0), 32), 7, "six steps plus the landing tick")
	_assert_eq(BattleCameraController.scroll_ticks(Vector2.ZERO, Vector2(3, 0), 32), 1, "a target inside the tolerance lands at once")


func _test_glide_through_controller() -> void:
	var config := MapSceneConfig.new()
	config.world_size = Vector2i(1600, 1600)
	config.logical_viewport_size = Vector2i(640, 480)
	config.grid_projection = {"origin": Vector2.ZERO, "cell_size": Vector2(32.0, 32.0)}
	var camera := Camera2D.new()
	var controller = BattleCameraController.create(camera, config, Vector2i(640, 480))
	controller.snap_to(Vector2(320, 240))
	var seconds: float = controller.scroll_to(Vector2(520, 240))
	_assert_true(controller.is_scrolling(), "a distant focus glides instead of cutting")
	_assert_eq(camera.position, Vector2(320, 240), "starting a glide does not move the view yet")
	_assert_true(is_equal_approx(seconds, OriginalTick.seconds(BattleCameraController.scroll_ticks(Vector2(320, 240), Vector2(520, 240), 32))), "the glide reports its tick count in seconds")
	var trace: Array[float] = []
	while controller.is_scrolling() and trace.size() < 64:
		controller.advance(OriginalTick.TICK_SECONDS)
		trace.append(camera.position.x)
	_assert_eq(trace, [352.0, 384.0, 416.0, 448.0, 480.0, 500.0, 510.0, 515.0, 517.0, 520.0], "one 0x45e80d step per 16 ms tick, then the landing")
	_assert_eq(camera.position, Vector2(520, 240), "the glide lands on its target")
	controller.scroll_to(Vector2(900, 900))
	controller.advance(OriginalTick.TICK_SECONDS)
	controller.pan(Vector2.LEFT, 0.016, 750.0)
	_assert_true(not controller.is_scrolling(), "edge or arrow input stops a running glide")
	controller.scroll_to(Vector2(900, 900))
	controller.finish_scroll()
	_assert_eq(camera.position, Vector2(900, 900), "fast-forward lands the glide on its target")
	controller.scroll_to(Vector2(100, 100))
	controller.snap_to(Vector2(700, 700))
	_assert_true(not controller.is_scrolling() and camera.position == Vector2(700, 700), "a cut replaces a running glide")
	# actScrollBGToPosSpeed (0x43c140): step = the script speed, tolerance 1 — linear at the
	# speed while far, then halving, landing within 1 px.
	var speed_seconds: float = controller.scroll_to(Vector2(720, 700), 8, BattleCameraController.SPEED_SCROLL_TOLERANCE)
	var speed_trace: Array[float] = []
	while controller.is_scrolling() and speed_trace.size() < 64:
		controller.advance(OriginalTick.TICK_SECONDS)
		speed_trace.append(camera.position.x)
	_assert_eq(speed_trace, [708.0, 714.0, 717.0, 718.0, 719.0, 720.0], "the speed token halves the rest at most 8 px a tick and lands within 1 px")
	_assert_true(is_equal_approx(speed_seconds, OriginalTick.seconds(speed_trace.size())), "the speed glide reports its ticks, the landing included")
	camera.free()


## 0x43bf30 frames an object at the view's (320, 192): top-left = point − (0x140, 0xc0). The
## recording's 212.45 s AI turn shows the framed mage standing there (runtime-measured). Battle
## focus (glide and cut) and the script's object／position framing all use it; the map clamp
## still wins near an edge. Map 1600×1600.
func _test_focus_frames_at_view_320_192() -> void:
	var config := MapSceneConfig.new()
	config.world_size = Vector2i(1600, 1600)
	config.logical_viewport_size = Vector2i(640, 480)
	config.grid_projection = {"origin": Vector2.ZERO, "cell_size": Vector2(32.0, 32.0)}
	var camera := Camera2D.new()
	var controller = BattleCameraController.create(camera, config, Vector2i(640, 480))
	controller.snap_to(Vector2(320, 240))
	var cell := Vector2i(20, 20)
	_assert_eq(BattleCameraController.focus_centre(Vector2(656, 656)), Vector2(656, 704), "a framed point's view centre is the point + (0, 48)")
	_assert_true(controller.scroll_to_grid(cell) and controller.is_scrolling(), "battle focus glides")
	controller.finish_scroll()
	_assert_eq(controller.grid_cell_center_to_logical(cell), BattleCameraController.FOCUS_VIEW_POINT, "battle focus lands the cell centre at the view's (320, 192)")
	controller.snap_to(Vector2(320, 240))
	controller.center_on_grid(cell)
	_assert_eq(controller.grid_cell_center_to_logical(cell), Vector2(320, 192), "the cut (first frame, Home) frames the cell the same way")
	controller.center_on_grid(Vector2i(0, 49))
	_assert_eq(camera.position, Vector2(320, 1360), "near the map corner the clamp still wins")
	_assert_eq(OpeningCinematics.script_position_camera_centre([640, 448], true), Vector2(656, 512), "script position tokens share the framing (cell centre + (0, 48))")
	camera.free()


func _test_story_step_matches_script_seconds() -> void:
	for pair in [[Vector2(320, 240), Vector2(900, 700)], [Vector2(500, 300), Vector2(460, 330)], [Vector2(320, 240), Vector2(322, 239)]]:
		var ticks := BattleCameraController.scroll_ticks(pair[0], pair[1], BattleCameraController.STORY_SCROLL_STEP)
		_assert_true(is_equal_approx(OriginalTick.seconds(ticks), OpeningCinematics.camera_scroll_seconds(pair[0], pair[1])), "script scroll seconds and the controller's story glide count the same ticks (%s)" % [pair])
	_assert_eq(OpeningCinematics.SCROLL_STEP_MAX, BattleCameraController.STORY_SCROLL_STEP, "the script scroll uses the story-phase step")


## Walk follow (0x4411cb／0x443f5a／0x453fbd): the walker's step is requested for the camera on
## an axis unless the walker, before the step, stands within half a view (320／240 px, set by
## 0x46bb02(640, 480)) of the map edge it walks toward. Map 1600×1600.
func _test_walk_follow_request() -> void:
	var half := Vector2(320, 240)
	var world := Vector2(1600, 1600)
	_assert_eq(BattleCameraController.walk_follow_request(Vector2(400, 400), Vector2(4, 0), half, world), Vector2(4, 0), "walking right past x 320 moves the camera 4 px with the walker")
	_assert_eq(BattleCameraController.walk_follow_request(Vector2(320, 400), Vector2(4, 0), half, world), Vector2.ZERO, "right needs x > 320 strictly (0x441278 jle)")
	_assert_eq(BattleCameraController.walk_follow_request(Vector2(1280, 400), Vector2(-4, 0), half, world), Vector2.ZERO, "left needs x < map width − 320 (0x441257 jge)")
	_assert_eq(BattleCameraController.walk_follow_request(Vector2(1276, 400), Vector2(-4, 0), half, world), Vector2(-4, 0), "walking left inside the map moves the camera left")
	_assert_eq(BattleCameraController.walk_follow_request(Vector2(400, 240), Vector2(0, 4), half, world), Vector2.ZERO, "down needs y > 240 (0x441236 jle)")
	_assert_eq(BattleCameraController.walk_follow_request(Vector2(400, 244), Vector2(0, 4), half, world), Vector2(0, 4), "walking down past y 240 moves the camera down")
	_assert_eq(BattleCameraController.walk_follow_request(Vector2(400, 1360), Vector2(0, -4), half, world), Vector2.ZERO, "up needs y < map height − 240 (0x441216 jge)")
	_assert_eq(BattleCameraController.walk_follow_request(Vector2(400, 1356), Vector2(0, -2), half, world), Vector2(0, -2), "a speed-2 script walker requests its own 2 px")
	_assert_eq(BattleCameraController.walk_follow_request(Vector2(100, 100), Vector2(4, 0), half, world), Vector2.ZERO, "near the top-left corner a rightward walker leaves the camera alone")


func _test_walk_follow_through_controller() -> void:
	var config := MapSceneConfig.new()
	config.world_size = Vector2i(1600, 1600)
	config.logical_viewport_size = Vector2i(640, 480)
	config.grid_projection = {"origin": Vector2.ZERO, "cell_size": Vector2(32.0, 32.0)}
	var camera := Camera2D.new()
	var controller = BattleCameraController.create(camera, config, Vector2i(640, 480))
	# A walker centred in the view walks one cell right, then one cell down.
	controller.snap_to(Vector2(800, 800))
	var ticks: int = controller.follow_walk(Vector2(800, 800), [Vector2(832, 800), Vector2(832, 832)])
	_assert_eq(ticks, 16, "two cells at 4 px per tick are 16 ticks (8 per cell, +0x9e = 8)")
	_assert_true(controller.is_scrolling() and controller.scroll_target == Vector2(832, 832), "the follow runs and reports where it ends")
	_assert_eq(camera.position, Vector2(800, 800), "starting a follow does not move the view yet")
	var trace: Array[Vector2] = []
	while controller.is_scrolling() and trace.size() < 64:
		controller.advance(OriginalTick.TICK_SECONDS)
		trace.append(camera.position)
	_assert_eq(trace.slice(0, 3), [Vector2(804, 800), Vector2(808, 800), Vector2(812, 800)] as Array[Vector2], "the camera takes the walker's 4 px each tick")
	_assert_eq(trace[7], Vector2(832, 800), "one cell right after eight ticks")
	_assert_eq(trace[8], Vector2(832, 804), "then it turns down with the walker")
	_assert_eq(trace.size(), 16, "one camera step per walker tick")
	_assert_eq(camera.position, Vector2(832, 832), "the walker stays where it was in the view")
	# Near the left edge a walker heading right does not drag the camera until it passes x 320.
	controller.snap_to(Vector2(320, 800))
	controller.follow_walk(Vector2(304, 800), [Vector2(336, 800)])
	var xs: Array[float] = []
	while controller.is_scrolling() and xs.size() < 64:
		controller.advance(OriginalTick.TICK_SECONDS)
		xs.append(camera.position.x)
	_assert_eq(xs, [320.0, 320.0, 320.0, 320.0, 320.0, 324.0, 328.0, 332.0], "the request starts on the first step taken from beyond x 320")
	# The clamp (0x46bede) holds the view inside the map at the far edge.
	controller.snap_to(Vector2(1280, 800))
	_assert_eq(controller.follow_walk(Vector2(1260, 800), [Vector2(1292, 800)]), 0, "a follow that cannot move the view does not start")
	_assert_true(not controller.is_scrolling(), "no follow runs at the clamped edge")
	# Fast-forward lands the follow on its end; a cut or a new glide replaces it.
	controller.snap_to(Vector2(800, 800))
	controller.follow_walk(Vector2(800, 800), [Vector2(800, 704)])
	controller.advance(OriginalTick.TICK_SECONDS)
	controller.finish_scroll()
	_assert_true(not controller.is_scrolling() and camera.position == Vector2(800, 704), "fast-forward lands the follow where the walk ends")
	controller.follow_walk(Vector2(800, 704), [Vector2(800, 640)])
	controller.scroll_to(Vector2(500, 500))
	_assert_eq(controller.scroll_mode, "step", "a battle focus replaces a running follow")
	camera.free()


func _scripts(directory: String) -> Array[String]:
	var found: Array[String] = []
	var dir := DirAccess.open(directory)
	if dir == null:
		return found
	for name in dir.get_files():
		if name.ends_with(".gd"):
			found.append(directory.path_join(name))
	for name in dir.get_directories():
		found.append_array(_scripts(directory.path_join(name)))
	return found


## Status page 58.17–58.78 s (camera_panel_motion §2): the right window comes in from the
## right, the left one from the left, the top strip from above, each losing about an eighth
## of the rest per frame (260→230→202→178→156→136→120→104…) and ending in 2 px steps.
func _test_panel_open_curve() -> void:
	var offset := Vector2(260, 0)
	var trace: Array[int] = []
	while offset != Vector2.ZERO and trace.size() < 80:
		offset = BattlePanelMotion.open_step(offset)
		trace.append(int(offset.x))
	_assert_eq(trace.slice(0, 7), [228, 200, 175, 154, 135, 119, 105], "an eighth of the rest per tick, as the recording's 230, 202, 178, 156, 136, 120, 104")
	_assert_true(trace.size() >= 25 and trace.size() <= 36, "a 260 px slide takes about 0.4–0.6 s of ticks (%d)" % trace.size())
	_assert_true(trace[-3] - trace[-2] == 2 and trace[-1] == 0, "the slide ends in 2 px steps")
	_assert_eq(BattlePanelMotion.side_of(Rect2(0, 0, 640, 168)), "top", "the vitals strip comes from above")
	_assert_eq(BattlePanelMotion.side_of(Rect2(12, 174, 224, 264)), "left", "the left column comes from the left")
	_assert_eq(BattlePanelMotion.side_of(Rect2(252, 174, 376, 160)), "right", "the right column comes from the right")
	_assert_eq(BattlePanelMotion.off_screen_offset(Rect2(252, 174, 376, 160), "right"), Vector2(388, 0), "a right part starts just past the right edge")
	_assert_eq(BattlePanelMotion.off_screen_offset(Rect2(12, 174, 224, 264), "left"), Vector2(-236, 0), "a left part starts just past the left edge")


## The motion never moves a Control: layout and hit testing stay the panel's own, only the
## draw transform slides; the opening ends by itself and a close stops it at once.
func _test_status_panel_motion() -> void:
	var loop := preload("res://tests/support/BattleFixture.gd").loop()
	var unit: Dictionary = preload("res://game/sim/loop/BattlePlayLoop.gd").unit_ref(loop, "leonard").duplicate(true)
	var panel = preload("res://game/battle/scene/BattleStatusPanel.gd").new()
	root.add_child(panel)
	await process_frame
	var motion = BattlePanelMotion.attach(panel)
	_assert_true(BattlePanelMotion.attach(panel) == motion, "a panel carries one motion")
	var positions := {}
	for child in panel.get_children():
		if child is Control:
			positions[child] = child.position
	panel.show_unit(unit, true)
	_assert_true(motion.opening() and motion.opened_count == 1, "showing the page starts its slide")
	var sides := {}
	for part in motion._parts:
		sides[part["side"]] = true
	_assert_true(sides.has("top") and sides.has("left") and sides.has("right"), "the status page slides from the top, the left and the right (%s)" % [sides.keys()])
	var unmoved := true
	for child in positions:
		unmoved = unmoved and child.position == positions[child]
	_assert_true(unmoved, "the slide leaves every Control's position alone")
	var ticks := 0
	while motion.opening() and ticks < 120:
		motion._tick()
		ticks += 1
	_assert_true(not motion.opening() and ticks >= 30 and ticks <= 50, "the page settles after about 0.5–0.8 s of ticks, the right column first (%d)" % ticks)
	panel.show_unit(unit, true)
	panel.hide()
	_assert_true(not motion.opening() and motion.closed_count == 1, "hiding the page stops its motion at once")
	_assert_eq(motion.ghost_count, 0, "without a renderer there is no close snapshot to slide")
	panel.queue_free()
	await process_frame


## The page shade fades like the original's (status page 58.2–58.6 s, 65.4–65.8 s): in from
## level 2 to 9 of 16 one level per 3 ticks, and after the close a shade left in the panel's
## place steps 9→2 and vanishes, with or without a renderer.
func _test_panel_shade_fade() -> void:
	var loop := preload("res://tests/support/BattleFixture.gd").loop()
	var unit: Dictionary = preload("res://game/sim/loop/BattlePlayLoop.gd").unit_ref(loop, "leonard").duplicate(true)
	var host := Control.new()
	root.add_child(host)
	var panel = preload("res://game/battle/scene/BattleStatusPanel.gd").new()
	host.add_child(panel)
	await process_frame
	var motion = BattlePanelMotion.attach(panel)
	_assert_eq(motion.shades_of(panel).size(), 1, "the status page has one screen-wide shade")
	var shade: ColorRect = motion.shades_of(panel)[0]
	for part in motion.parts_of(panel):
		_assert_true(part != shade, "the shade never slides")
	panel.show_unit(unit, true)
	var opening: Array[int] = [motion.shade_level]
	for tick in range(24):
		motion._tick()
		opening.append(motion.shade_level)
	_assert_eq([opening[0], opening[3], opening[6], opening[18], opening[21], opening[24]], [2, 3, 4, 8, 9, 9], "the shade darkens from level 2 one level per 3 ticks to 9")
	_assert_true(is_equal_approx(shade.color.a, 9.0 / 16.0), "at rest the shade is 9／16 black (map luma × 0.46 in the recording)")
	panel.hide()
	var ghost: ColorRect = RuntimeReadback.shade_ghost(motion)
	_assert_true(ghost != null and ghost.get_parent() == host and ghost.get_index() < panel.get_index(), "a closed page leaves its shade in its place, under where the panel was")
	var closing: Array[int] = [motion.shade_level]
	for tick in range(24):
		motion._tick()
		closing.append(motion.shade_level)
	_assert_eq([closing[0], closing[2], closing[3], closing[21], closing[23], closing[24]], [9, 9, 8, 2, 2, 0], "the shade lightens one level per 3 ticks and drops from 2 to nothing")
	_assert_true(RuntimeReadback.shade_ghost(motion) == null and not motion.shading(), "the fade ends by itself after 24 ticks")
	panel.show_unit(unit, true)
	panel.hide()
	motion.finish()
	_assert_true(RuntimeReadback.shade_ghost(motion) == null and motion.shade_level == 0, "fast-forward drops a closing shade at once")
	host.queue_free()
	await process_frame


func _test_every_panel_attaches_motion() -> void:
	var menus := FileAccess.get_file_as_string("res://game/battle/scene/BattleSceneMenus.gd")
	var settlement := FileAccess.get_file_as_string("res://game/battle/scene/BattleSettlementController.gd")
	_assert_true(menus.contains("for panel in runtime.modal_panels:\n\t\tBattlePanelMotion.attach(panel)"), "every modal panel gets the shared motion")
	_assert_true(settlement.contains("BattlePanelMotion.gd\").attach(panel)"), "the loot window gets the shared motion")
	var modal_line := ""
	for line in menus.split("\n"):
		if line.contains("runtime.modal_panels.assign("):
			modal_line = line
	for script in PANEL_SCRIPTS:
		if script == "BattleLootPanel.gd":
			continue
		var key: String = str(script).trim_prefix("Battle").trim_suffix(".gd").to_snake_case()
		_assert_true(modal_line.contains("runtime." + key), "%s is in the modal list the motion attaches to" % script)


# ---- run_camera_panel_motion_tests.gd ----
## Script position cameras (actScrollBGToPos／actSetBGToPos／actScrollBGToPosSpeed) frame what
## the script shows next. The original puts the token's point at the view's (320,192)
## (0x43bf30, original_script_camera_scroll.md); the remake used to read x,y as the view's
## top-left, which left STORY006's entering party on the top edge of the view. The census
## walks every registered scenario's opening timeline and winfail chains: after each
## position token, the actors the script inserts before the next camera or dialogue token
## (actInsertObject, obj_Story_PlayerN installs) must stand inside the view, sprite
## included. The token's own framing (static-derived) is counted separately from the
## remake's keep-in-view pull (OpeningCinematics.keep_in_view_centre, remake-invented) that
## the runtime applies to each insert; the old top-left reading is the ablation.

const WrdTerrainTiles = preload("res://game/sim/WrdTerrainTiles.gd")
const BattleScenario = preload("res://game/sim/BattleScenario.gd")
const VIEW := Vector2(640, 480)
const CELL := 32.0
## A standing sprite around its cell-centre foot point (about one cell wide, two tall).
const SPRITE_UP := 56.0
const SPRITE_SIDE := 16.0
const POSITION_KINDS := {"camera_position_target": true, "camera_position_set": false, "camera_position_target_speed": true}

var _census := {"cameras": 0, "focused": 0, "visible": 0, "visible_by_token": 0, "visible_old_reading": 0}
var _hidden: Array[String] = []


func run_opening_camera() -> void:
	var centre := OpeningCinematics.script_position_camera_centre([1024, 224], true)
	check(centre == Vector2(1040, 288), "actScrollBGToPos rounds to the cell centre and puts it at the view's (320,192): %s" % str(centre))
	check(OpeningCinematics.script_position_camera_centre([0, 96], false) == Vector2(0, 144), "actSetBGToPos keeps the raw point")
	var directory := DirAccess.open("res://content/battles")
	for file in directory.get_files():
		if not file.ends_with(".json") or file == "campaign.json":
			continue
		var scenario: Dictionary = BattleScenario.load_file("res://content/battles/" + file)
		if not scenario.has("opening"):
			continue
		var terrain := WrdTerrainTiles.load_tiles(BattleScenario.resource_path(scenario, "terrain"))
		if not bool(terrain.get("ok", false)):
			continue
		var world := Vector2(terrain["map_size"]) * CELL
		var timelines: Array = []
		var opening_path := BattleScenario.resource_path(scenario, "opening_timeline")
		if opening_path != "" and FileAccess.file_exists(opening_path):
			var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(opening_path))
			if parsed is Dictionary:
				timelines.append(["opening", parsed.get("events", [])])
		var chains: Dictionary = scenario.get("scenario_rules", {}).get("status_timelines", {})
		for key in chains:
			timelines.append([key, chains[key].get("events", [])])
		for timeline in timelines:
			_scan(file, scenario, world, timeline[0], timeline[1])
	print("OPENING_CAMERA_CENSUS cameras=%d focused=%d visible=%d visible_by_token=%d visible_old_reading=%d" % [_census["cameras"], _census["focused"], _census["visible"], _census["visible_by_token"], _census["visible_old_reading"]])
	for line in _hidden:
		print("OPENING_CAMERA_HIDDEN " + line)
	check(_census["focused"] > 20, "the census reaches the position cameras that frame an entrance: %s" % str(_census))
	check(_census["visible"] == _census["focused"], "every inserted actor after a position camera is inside the view: %s" % str(_census))
	check(_census["visible_old_reading"] < _census["focused"], "ablation: the old top-left reading leaves some of them outside: %s" % str(_census))


func _clamp(centre: Vector2, world: Vector2) -> Vector2:
	var half := VIEW * 0.5
	return Vector2(clampf(centre.x, half.x, maxf(half.x, world.x - half.x)), clampf(centre.y, half.y, maxf(half.y, world.y - half.y)))


func _sees(centre: Vector2, foot: Vector2) -> bool:
	var view := Rect2(centre - VIEW * 0.5, VIEW)
	return view.has_point(foot + Vector2(-SPRITE_SIDE, -SPRITE_UP)) and view.has_point(foot + Vector2(SPRITE_SIDE, 0))


func _scan(file: String, scenario: Dictionary, world: Vector2, key: String, events: Array) -> void:
	var story_objects: Dictionary = scenario.get("opening", {}).get("story_objects", {})
	for index in range(events.size()):
		var event: Dictionary = events[index]
		var kind := str(event.get("kind", ""))
		if not POSITION_KINDS.has(kind) or (event.get("args", []) as Array).size() < 2 or bool(event.get("cutscene_skip", false)):
			continue
		_census["cameras"] += 1
		var args: Array = event["args"]
		var centre := _clamp(OpeningCinematics.script_position_camera_centre(args, POSITION_KINDS[kind]), world)
		var old_centre := _clamp(Vector2(float(str(args[0])), float(str(args[1]))) + VIEW * 0.5, world)
		for next_index in range(index + 1, events.size()):
			var next: Dictionary = events[next_index]
			var next_kind := str(next.get("kind", ""))
			if POSITION_KINDS.has(next_kind) or next_kind in ["dialogue_message_id", "background_object_target", "camera_object_target"]:
				break
			var next_args: Array = next.get("args", [])
			var inserts_actor := next_kind == "object_insert" or (next_kind == "story_object_insert" and next_args.size() >= 3 and str(story_objects.get(str(next_args[0]), {}).get("spawns_unit_id", "")) != "")
			if not inserts_actor or next_args.size() < 3:
				continue
			var foot := Vector2(float(str(next_args[1])), float(str(next_args[2]))) + Vector2(CELL, CELL) * 0.5
			if foot.x < 0.0 or foot.y < 0.0 or foot.x > world.x or foot.y > world.y:
				continue  # an off-map insert walks in; the view cannot hold it yet
			_census["focused"] += 1
			if _sees(centre, foot):
				_census["visible_by_token"] += 1
			centre = _clamp(OpeningCinematics.keep_in_view_centre(centre, foot, VIEW), world)
			if _sees(centre, foot):
				_census["visible"] += 1
			else:
				_hidden.append("%s %s %s camera=%s actor_foot=%s" % [file, key, str(next.get("id", "")), str(centre), str(foot)])
			if _sees(old_centre, foot):
				_census["visible_old_reading"] += 1
