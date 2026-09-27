extends "res://tests/support/TestSuite.gd"

## Close-up layout and aftermath floats (lane R6-P3,
## docs/evidence_packets/runtime_observations/cutin_floaters/README.md).
## Close-up: the defender object 0x4038a0 starts on the shot line and shifts by its row's hit
## move flag (aniKRight −50, aniKLeft +30), then a hit knocks it back 14+13+…+1 = 105 px and a
## miss slides it 150 px (0x45e91e) the same way; the census checks that every cut-in path
## places its actors through CutinLayout and that every combat manifest row declares a flag.
## Floats: the original glyph layout of KILL／EXP／$／LEVEL UP, the defProcShowNumber level
## fade, the aftermath queue order KILL (with the disposal) → EXP → $ → LEVEL UP, and a census
## that no other game file draws a reward float or plays the level-up sound. Vitals: the resist
## row's element gems and "07%"／"MAX" values.

const CutinLayout = preload("res://game/battle/runtime/CutinLayout.gd")
const BattleRewardFloater = preload("res://game/battle/scene/BattleRewardFloater.gd")
const BattleAftermath = preload("res://game/battle/scene/BattleAftermath.gd")
const BattleVitals = preload("res://game/battle/scene/BattleVitals.gd")
const ContentPaths = preload("res://game/sim/ContentPaths.gd")
const BattleCameraController = preload("res://game/battle/runtime/BattleCameraController.gd")
const MapSceneConfig = preload("res://game/battle/runtime/MapSceneConfig.gd")
const OriginalTick = preload("res://game/common/OriginalTick.gd")
const CHAPTER_MANIFEST := "res://content/imported/hsl/chapter01/combat_animation/manifest.json"
const AUTHORED_ROOT := "res://content/generated/hsl/authored"
## Files that stand close-up actors; each must place them through CutinLayout.
const CUTIN_FILES := ["res://game/battle/scene/BattleCombatCutin.gd", "res://game/battle/scene/SkillEffectScriptPlayer.gd",
	"res://game/battle/scene/MoonDancePresentation.gd", "res://game/battle/scene/PoisonArrowPresentation.gd"]


func _init() -> void:
	tag = "CUTIN_FLOATERS_TESTS"


func run() -> void:
	_test_defender_anchor_and_reaction()
	_test_every_row_declares_a_hit_move_flag()
	_test_cutin_paths_use_the_layout()
	await _test_float_glyph_layout()
	_test_float_level_and_rise()
	await _test_aftermath_order()
	await _test_reward_camera_focus()
	_test_reward_floats_have_one_owner()
	await _test_resist_row()


func _test_defender_anchor_and_reaction() -> void:
	var right := {"source_k_action": "aniKRight"}
	var left := {"source_k_action": "aniKLeft"}
	var stop := {"source_k_action": "aniKStop"}
	_assert_eq(CutinLayout.attacker_anchor(), Vector2(320, 330), "the attacker stands at (0x140, 0x14a) — the recording's (320,330)")
	_assert_eq(CutinLayout.defender_anchor(left).y, 330.0, "the victim shares the shot line y 0x14a")
	_assert_eq(CutinLayout.defender_anchor(right).x, 270.0, "aniKRight victims start 50 px left of the shot line (0x404560)")
	_assert_eq(CutinLayout.defender_anchor(left).x, 350.0, "aniKLeft victims start 30 px right — the recording's 拉爾斯帝國兵 at x 350")
	_assert_eq(CutinLayout.defender_anchor(stop).x, 320.0, "aniKStop stays on the line")
	var steps: Array[float] = []
	for tick in range(16):
		steps.append(CutinLayout.knockback_x(left, tick))
	_assert_eq(steps.slice(0, 3), [-14.0, -27.0, -39.0], "the knock-back starts at 14 px a tick and slows by 1")
	_assert_eq(steps[13], -105.0, "14 ticks carry it 105 px — the recording's 350 → 245")
	_assert_eq(steps[15], -105.0, "then it stops")
	_assert_eq(CutinLayout.knockback_x(right, 20), 105.0, "aniKRight is knocked to the right")
	_assert_eq(CutinLayout.knockback_x(stop, 20), 0.0, "aniKStop is not moved")
	var dodge: Array[float] = []
	for tick in range(16):
		dodge.append(CutinLayout.dodge_x(right, tick))
	_assert_eq(dodge.slice(0, 4), [36.0, 64.0, 85.0, 101.0], "the dodge steps min(36, remaining／4)")
	_assert_true(dodge[13] < 150.0 and dodge[14] == 150.0 and dodge[15] == 150.0, "14 moving ticks and the arrival land 150 px away (%s)" % str(dodge))
	_assert_eq(CutinLayout.reaction_x(left, false, 30), -150.0, "a miss slides; a hit knocks back")


func _test_every_row_declares_a_hit_move_flag() -> void:
	var manifests: Array[String] = [CHAPTER_MANIFEST]
	for directory in DirAccess.get_directories_at(AUTHORED_ROOT):
		var path := "%s/%s/combat_animation.json" % [AUTHORED_ROOT, directory]
		if FileAccess.file_exists(path): manifests.append(path)
	var rows := 0
	for path in manifests:
		var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
		for key in manifest["actors"]:
			rows += 1
			_assert_true(CutinLayout.K_ACTION_SHIFT.has(str(manifest["actors"][key].get("source_k_action", ""))), "%s row %s declares a known hit move flag" % [path, key])
	_assert_true(rows > 55, "the census reads every combat manifest row (%d)" % rows)


func _test_cutin_paths_use_the_layout() -> void:
	var literal := RegEx.create_from_string("(attacker|defender)_sprite\\.position\\s*=\\s*Vector2\\(\\s*\\d+\\s*,\\s*(320|330)\\s*\\)")
	var defender_set := RegEx.create_from_string("defender_sprite\\.position\\s*=")
	for path in CUTIN_FILES:
		var text := FileAccess.get_file_as_string(path)
		_assert_true(text != "", "read " + path)
		_assert_true(literal.search(text) == null, "%s places no close-up actor on a literal shot line" % path)
		for line in text.split("\n"):
			if defender_set.search(line) != null:
				_assert_true(line.contains("defender_anchor"), "%s: every defender placement goes through defender_anchor (%s)" % [path, line.strip_edges()])


func _test_float_glyph_layout() -> void:
	var node: Node2D = BattleRewardFloater.new()
	root.add_child(node)
	node.present("experience", 26)
	_assert_eq(node.text, "EXP 26", "the EXP float names its value")
	_assert_eq(node.glyphs.map(func(g): return g.position.x), [-35.0, 21.0, 35.0], "EXP prefix at x − 5 × 7, digits 14 px apart after 4 units (0x408580)")
	_assert_true(node.glyphs[0].texture.resource_path.ends_with("reward_floats/exp.png") and node.glyphs[1].texture.resource_path.ends_with("exp_digit_2.png"), "EXP uses NUM511 and the NUM4xx digits")
	node.present("gold", 100)
	_assert_eq(node.glyphs.map(func(g): return g.position.x), [-28.0, 0.0, 14.0, 28.0], "$ prefix at x − 4 × 7, digits after 2 units")
	_assert_eq(node.text, "$ 100", "the $ float names its value")
	node.present("kill", 3)
	_assert_eq(node.glyphs.map(func(g): return g.position.x), [-57.0, 57.0], "KILL at x − (19 + 38), its digit 114 further (0x4083e0)")
	_assert_true(node.glyphs[1].texture.resource_path.ends_with("kill_digit_3.png"), "the digit 3 is KILL_004")
	node.present("kill", 12)
	_assert_eq(node.glyphs.map(func(g): return g.position.x), [-76.0, 38.0, 76.0], "two digits 38 px apart")
	node.present("level_up")
	_assert_eq([node.text, node.glyphs.size(), node.glyphs[0].position.x], ["LEVEL UP", 1, 0.0], "LEVEL UP is NUM514 alone on the spawn point")
	node.queue_free()
	await process_frame


func _test_float_level_and_rise() -> void:
	_assert_eq([BattleRewardFloater.level(0), BattleRewardFloater.level(15), BattleRewardFloater.level(16), BattleRewardFloater.level(18), BattleRewardFloater.level(44), BattleRewardFloater.level(46)], [16.0, 16.0, 15.0, 14.0, 1.0, 0.0], "level 16 held 16 ticks, then −1 every 2 ticks to 0 at 46")
	var node: Node2D = BattleRewardFloater.new()
	node.kind = "experience"
	_assert_eq(node.rise(21), 10.0, "½ px a tick")
	node.kind = "kill"
	_assert_eq([node.rise(21), node.life_ticks()], [0.0, 40], "KILL holds still for 40 ticks")
	node.free()


func _test_aftermath_order() -> void:
	var aftermath: Node = BattleAftermath.new()
	root.add_child(aftermath)
	var units := [
		{"id": "hero", "actor_id": "001", "coord": Vector2i(2, 2), "dead_message": {"messages": []}},
		{"id": "foe", "actor_id": "021", "coord": Vector2i(2, 3), "dead_message": {"messages": []}},
	]
	var receipt := {"sequence": 1, "attacker_id": "hero", "defender_id": "foe", "defender_hp_before": 5, "defender_hp_after": 0,
		"hit": true, "kill_chain": 3, "experience": {"gained": 26, "level_before": 1, "level_after": 3, "exp_before": 90, "exp_after": 16},
		"rewards": {"gold": 100, "kills": [{"attacker_id": "hero", "defender_id": "foe"}]}}
	aftermath.prepare(receipt, units)
	_assert_eq(aftermath.jobs.map(func(job): return job["kind"]), ["death", "experience", "gold", "level_up"], "0x442720: EXP → $ → LEVEL UP after the death, one LEVEL UP for two levels")
	_assert_eq(int(aftermath.jobs[0]["kill_count"]), 3, "the victim carries its killer's chain for its KILL float")
	var countered := {"sequence": 2, "attacker_id": "foe", "defender_id": "hero", "defender_hp_before": 9, "defender_hp_after": 4,
		"hit": true, "kill_chain": 0, "counter": {"attacker_id": "hero", "defender_id": "foe", "defender_hp_before": 3, "defender_hp_after": 0, "hit": true, "kill_chain": 2}}
	aftermath.cursor = aftermath.jobs.size()
	aftermath.prepare(countered, units)
	_assert_eq(int(aftermath.jobs[0]["kill_count"]), 2, "an attacker a counter killed floats the counter's chain")
	aftermath.cursor = aftermath.jobs.size()
	var both_level := {"sequence": 3, "attacker_id": "hero", "defender_id": "foe", "defender_hp_before": 9, "defender_hp_after": 4, "hit": true,
		"experience": {"gained": 19, "level_before": 1, "level_after": 2},
		"counter": {"attacker_id": "foe", "defender_id": "hero", "defender_hp_before": 9, "defender_hp_after": 7, "hit": true, "experience": {"gained": 1, "level_before": 1, "level_after": 1}}}
	aftermath.prepare(both_level, units)
	_assert_eq(aftermath.jobs.map(func(job): return "%s@%s" % [job["kind"], str(job["coord"])]), ["experience@(2, 2)", "level_up@(2, 2)", "experience@(2, 3)"], "each recipient's EXP → LEVEL UP before the countering target's EXP (recording 501.48／502.05／502.70)")
	aftermath.cursor = aftermath.jobs.size()
	aftermath.queue_free()
	await process_frame


## The runtime seams the reward glide touches: a real camera controller on a 1600×1600 map, map
## actors, and the grid → view projection through that camera.
class FocusStubRuntime extends Node:
	var camera_controller: RefCounted
	var camera := Camera2D.new()
	var actors := {}
	func _init() -> void:
		var config := MapSceneConfig.new()
		config.world_size = Vector2i(1600, 1600)
		config.logical_viewport_size = Vector2i(640, 480)
		config.grid_projection = {"origin": Vector2.ZERO, "cell_size": Vector2(32.0, 32.0)}
		add_child(camera)
		camera_controller = BattleCameraController.create(camera, config, Vector2i(640, 480))
		camera_controller.snap_to(Vector2(320, 240))
	func actor_node_for_unit(unit_id: String) -> Node2D:
		if not actors.has(unit_id):
			actors[unit_id] = Node2D.new()
			add_child(actors[unit_id])
		return actors[unit_id]
	func grid_cell_center_to_logical_position(coord: Vector2i) -> Vector2:
		return camera_controller.grid_cell_center_to_logical(coord)


## 0x442720 phase 0: before each recipient's first float the camera glides (0x43bf30, battle
## step) until the recipient stands at the view's (320, 192); the EXP float waits for the
## landing. The countering recipient gets its own glide; an exchange with no EXP and no gold
## moves nothing. Recording 336 s／372 s: EXP centred on x 320, y 144 = recipient y 192.
func _test_reward_camera_focus() -> void:
	var runtime := FocusStubRuntime.new()
	root.add_child(runtime)
	var aftermath: Node = BattleAftermath.new()
	root.add_child(aftermath)
	var hero_cell := Vector2i(30, 30)
	var foe_cell := Vector2i(12, 34)
	var units := [{"id": "hero", "actor_id": "001", "coord": hero_cell}, {"id": "foe", "actor_id": "021", "coord": foe_cell}]
	var receipt := {"sequence": 1, "attacker_id": "hero", "defender_id": "foe", "defender_hp_before": 9, "defender_hp_after": 4, "hit": true,
		"experience": {"gained": 12, "level_before": 1, "level_after": 1},
		"counter": {"attacker_id": "foe", "defender_id": "hero", "defender_hp_before": 9, "defender_hp_after": 7, "hit": true, "experience": {"gained": 3, "level_before": 1, "level_after": 1}}}
	aftermath.prepare(receipt, units)
	var controller: RefCounted = runtime.camera_controller
	var shown: Array = []
	var early := false
	var guard := 0
	while aftermath.busy() and guard < 600:
		guard += 1
		controller.advance(OriginalTick.TICK_SECONDS)
		var before: String = aftermath.stage
		aftermath.advance(OriginalTick.TICK_SECONDS, runtime)
		if aftermath.stage == "experience" and before != "experience":
			var coord: Vector2i = aftermath.jobs[aftermath.cursor]["coord"]
			shown.append([coord, controller.grid_cell_center_to_logical(coord)])
		if aftermath.stage == "experience" and controller.is_scrolling(): early = true
	_assert_eq(aftermath.focus_count, 2, "one glide per recipient (attacker, then the countering target)")
	_assert_eq(shown, [[hero_cell, Vector2(320, 192)], [foe_cell, Vector2(320, 192)]], "each EXP appears with its recipient framed at the view's (320, 192)")
	_assert_true(not early, "no EXP float while the glide still runs")
	var idle := {"sequence": 2, "attacker_id": "hero", "defender_id": "foe", "defender_hp_before": 4, "defender_hp_after": 1, "hit": true}
	var at: Vector2 = runtime.camera.position
	aftermath.prepare(idle, units)
	_assert_true(not aftermath.busy() and aftermath.focus_count == 2 and runtime.camera.position == at, "no EXP and no gold: no round, no camera move")
	aftermath.queue_free()
	runtime.queue_free()
	await process_frame


func _test_reward_floats_have_one_owner() -> void:
	var drawing := RegEx.create_from_string("\"(KILL|LEVEL UP)|reward_floats/|play_ui_sound\\(\"level_up\"\\)")
	var owners := {}
	var scanned := 0
	for path in _game_scripts("res://game"):
		scanned += 1
		var text := FileAccess.get_file_as_string(path)
		for line in text.split("\n"):
			if line.strip_edges().begins_with("#"): continue
			if drawing.search(line) != null: owners[path] = true
	_assert_true(scanned > 100, "the census reads the game scripts (%d)" % scanned)
	_assert_eq(owners.keys().filter(func(path): return not path in ["res://game/battle/scene/BattleRewardFloater.gd", "res://game/battle/scene/BattleSceneRuntime.gd"]), [], "only BattleRewardFloater draws KILL／EXP／$／LEVEL UP art; the level-up sound has one entry (play_growth_sound on level_up_presented)")
	var runtime := FileAccess.get_file_as_string("res://game/battle/scene/BattleSceneRuntime.gd")
	_assert_true(runtime.contains("level_up_presented.connect(play_growth_sound)") and not runtime.contains("experience_presented.connect(play_growth_sound)"), "the level-up sound follows the LEVEL UP float, not EXP")


func _test_resist_row() -> void:
	_assert_eq([BattleVitals.resist_text(7), BattleVitals.resist_text(0), BattleVitals.resist_text(79), BattleVitals.resist_text(80), BattleVitals.resist_text(95)], ["07%", "00%", "79%", "MAX", "MAX"], "0x434d10 prints two digits and %, MAX from 80")
	var vitals: Control = BattleVitals.new()
	root.add_child(vitals)
	_assert_eq(vitals.resist_gems.size(), 5, "five element gems")
	for index in range(5):
		_assert_true(vitals.resist_gems[index].texture.resource_path.ends_with("panels/magicon%d.png" % (index + 1)), "gem %d is MAGICON%d" % [index, index + 1])
		_assert_eq(vitals.resist_gems[index].position, Vector2(138 + 48 * index, 128), "gem %d at the recording's (138 + 48·i, 450 − 322)" % index)
		_assert_eq(vitals.resist_values[index].position.x, 149.0 + 48 * index, "value %d starts 11 px after its gem" % index)
	vitals.queue_free()
	await process_frame


func _game_scripts(directory: String) -> Array[String]:
	var found: Array[String] = []
	for file in DirAccess.get_files_at(directory):
		if file.ends_with(".gd"): found.append("%s/%s" % [directory, file])
	for sub in DirAccess.get_directories_at(directory):
		found.append_array(_game_scripts("%s/%s" % [directory, sub]))
	return found
