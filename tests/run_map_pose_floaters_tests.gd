extends "res://tests/support/TestSuite.gd"

## Map actor pose, LEVEL UP stars and the red damage digits (lane R7-POSE,
## docs/evidence_packets/runtime_observations/map_pose_floaters/README.md).
## Pose: 0x4071e0 plays the SHAPEDEF use_magic frames forward at delay 3, holds the last one
## 40 ticks, plays them back and returns to standing (8 × frames + 40 ticks); its three caller
## classes (map spell lead end, item use, level-up) are the only callers in the game scripts.
## Stars: 0x415c10(x, y, 149, 64, 24, 0, 6, 36) and effProcFlyUpShape → effProcFlyUp2.
## Digits: defProcShowNumber kind 0 (0x40863e) replayed tick by tick — digits appear from the
## left every 10 ticks, the number does not rise, life 10 × digits + 34 ticks.

const ActorRuntime = preload("res://game/battle/runtime/ActorRuntime.gd")
const LevelUpStars = preload("res://game/battle/scene/LevelUpStars.gd")
const DamageNumberFloat = preload("res://game/battle/scene/DamageNumberFloat.gd")
const OriginalTick = preload("res://game/common/OriginalTick.gd")
const WALK_MANIFEST := "res://content/imported/hsl/chapter01/actor_walk_frames/actor_walk_manifest.json"
const POSE_MANIFEST := "res://content/imported/hsl/shared/actor_magic_poses/manifest.json"


func _init() -> void:
	tag = "MAP_POSE_FLOATERS_TESTS"


func run() -> void:
	_test_pose_schedule()
	_test_pose_census()
	await _test_actor_plays_the_pose()
	_test_pose_callers()
	await _test_star_shower()
	_test_damage_digit_states()
	await _test_damage_digit_node()


func _test_pose_schedule() -> void:
	var frames: Array[int] = []
	for tick in range(90):
		frames.append(ActorRuntime.magic_pose_frame(tick, 6))
	_assert_eq([frames[0], frames[3], frames[4], frames[19], frames[20]], [0, 0, 1, 4, 5], "forward at delay 3: each use_magic frame shows 4 ticks (0x45e575)")
	_assert_eq([frames[23], frames[24], frames[63], frames[64], frames[67]], [5, 5, 5, 5, 5], "the last frame holds through +0x92 = 40 (ticks 20–67)")
	_assert_eq([frames[68], frames[72], frames[76], frames[80], frames[84], frames[87]], [4, 3, 2, 1, 0, 0], "played back one frame per 4 ticks (0x45e660)")
	_assert_eq([frames[88], frames[89]], [-1, -1], "the pose is over at 8 × 6 + 40 = 88 ticks; standing resumes")
	_assert_eq(ActorRuntime.magic_pose_frame(8 * 5 + 40 - 1, 5), 0, "five frames (044 lacks M0002) end at 8 × 5 + 40")
	_assert_eq(ActorRuntime.magic_pose_frame(8 * 5 + 40, 5), -1, "and not a tick later")


func _test_pose_census() -> void:
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(POSE_MANIFEST))
	_assert_eq(manifest["program"]["frame_delay"], 3, "the manifest records 0x4071e0's delay 3")
	_assert_eq(manifest["program"]["hold_ticks"], ActorRuntime.MAGIC_POSE_HOLD_TICKS, "and its 40-tick hold, the constant the runtime uses")
	var walk: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(WALK_MANIFEST))
	var undeclared: Array = []
	for key in walk["actors"]:
		if ActorRuntime.magic_pose_entry(key).is_empty() and not key in manifest["use_magic_is_stand"] and not key in manifest["without_use_magic"]:
			undeclared.append(key)
	_assert_eq(undeclared, [], "every first-chapter walk key has use_magic frames or a declared reason not to")
	_assert_eq(ActorRuntime.magic_pose_entry("001")["frames"].size(), 6, "雷歐納德 has the six 001-M frames")
	_assert_eq(ActorRuntime.magic_pose_entry("026")["frames"].size(), 6, "帝國法師 026 (the recording's caster) has six")


func _test_actor_plays_the_pose() -> void:
	var walk: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(WALK_MANIFEST))
	var actor: Node2D = ActorRuntime.new()
	root.add_child(actor)
	actor.configure_from_manifest("probe", walk["actors"]["026"])
	actor.play_state("idle", "0")
	var standing: String = actor.get_node("Sprite2D").texture.resource_path
	_assert_true(actor.play_use_magic(), "026 takes the use_magic pose")
	_assert_true(actor.is_posing() and _sprite(actor).ends_with("/026-M0001.png"), "the pose starts on M0001 (%s)" % _sprite(actor))
	actor._process(OriginalTick.seconds(20.5))
	_assert_true(_sprite(actor).ends_with("/026-M0006.png"), "tick 20 reaches the last frame (%s)" % _sprite(actor))
	actor._process(OriginalTick.seconds(40.0))
	_assert_true(_sprite(actor).ends_with("/026-M0006.png"), "held at tick 60 (%s)" % _sprite(actor))
	actor._process(OriginalTick.seconds(10.0))
	_assert_true(_sprite(actor).ends_with("/026-M0005.png"), "one frame back by tick 70 (%s)" % _sprite(actor))
	actor._process(OriginalTick.seconds(18.0))
	_assert_true(not actor.is_posing() and actor.animation_state == "idle" and _sprite(actor) == standing, "standing again after 88 ticks (%s)" % _sprite(actor))
	_assert_true(actor.play_use_magic(), "a second pose starts over")
	actor.set_shape_override([{"res_path": "res://content/imported/hsl/shared/actor_hit_poses/026-P.png", "draw_origin": [30, 50]}])
	_assert_true(not actor.is_posing() and _sprite(actor).ends_with("/026-P.png"), "a death hit pose ends the casting pose")
	actor.clear_shape_override()
	_assert_true(actor.play_use_magic(), "posing again")
	actor.move_along([actor.position + Vector2(32, 0)], 0.2)
	_assert_true(not actor.is_posing(), "walking ends the pose")
	actor.queue_free()
	await process_frame
	var stand_only: Node2D = ActorRuntime.new()
	root.add_child(stand_only)
	stand_only.actor_id = "060"
	_assert_true(not stand_only.play_use_magic() and not stand_only.is_posing(), "060, whose use_magic is its stand shape, keeps its frames")
	stand_only.queue_free()
	await process_frame


func _sprite(actor: Node2D) -> String:
	return actor.get_node("Sprite2D").texture.resource_path


## The original's three 0x4071e0 caller classes are the remake's only play_use_magic callers.
func _test_pose_callers() -> void:
	var callers := {}
	for path in _game_scripts("res://game"):
		if path.ends_with("/ActorRuntime.gd"): continue
		var text := FileAccess.get_file_as_string(path)
		if text.contains("play_use_magic("): callers[path] = true
	_assert_eq(callers.keys().map(func(path): return path.get_file()), ["BattleAftermath.gd", "BattlePresentation.gd"], "only the aftermath (level-up) and the presentation (spell lead end, item use) pose actors")
	var aftermath := FileAccess.get_file_as_string("res://game/battle/scene/BattleAftermath.gd")
	var level_up := aftermath.substr(aftermath.find("func _present_level_up"), 900)
	_assert_true(level_up.contains("play_use_magic()") and level_up.contains("LevelUpStars.new()"), "the LEVEL UP stage poses the recipient and scatters its stars (0x442720 phase 6)")
	var presentation := FileAccess.get_file_as_string("res://game/battle/scene/BattlePresentation.gd")
	var item_use := FileAccess.get_file_as_string("res://game/battle/scene/BattleItemUsePresentation.gd")
	_assert_true(item_use.substr(item_use.find("func _start_effect"), 700).contains("_pose_unit("), "item use poses its user (0x4449a7／0x440366／0x4404c7)")
	_assert_true(presentation.contains("\t_sync_cast_pose()\n"), "every refresh checks the running spell clip for the caster pose")


func _test_star_shower() -> void:
	var stars: Node2D = LevelUpStars.new()
	root.add_child(stars)
	stars.begin(12345)
	_assert_eq(stars.stars.size(), 36, "0x415c10 scatters 0x24 = 36 stars")
	_assert_eq(stars.get_child_count(), 36, "one additive sprite each")
	var bad_offsets := 0
	var bad_speeds := 0
	var bad_holds := 0
	var bad_steps := 0
	var last_appear := 0
	for index in range(stars.stars.size()):
		var star: Dictionary = stars.stars[index]
		var offset: Vector2 = star["offset"]
		if offset.x < -31 or offset.x > 32 or offset.y < -11 or offset.y > 12: bad_offsets += 1
		var steps := (float(star["speed"]) - 0.25) * 16.0
		if steps < 0.0 or steps > 31.0 or not is_equal_approx(steps, roundf(steps)): bad_speeds += 1
		if int(star["hold"]) < 6 or int(star["hold"]) > 13: bad_holds += 1
		if index > 1 and (int(star["appear"]) - last_appear < 1 or int(star["appear"]) - last_appear > 6): bad_steps += 1
		last_appear = int(star["appear"])
	_assert_eq([bad_offsets, bad_speeds, bad_holds, bad_steps], [0, 0, 0, 0], "stars within x + [−31, 32], y + [−11, 12]; speed 0.25 + k／16 px; hold 6..13; delays 1..6 apart")
	_assert_eq(stars.stars[0]["appear"], 0, "the first star draws at once")
	var texture_ok := true
	for index in range(36):
		var sprite: Sprite2D = stars.get_child(index)
		texture_ok = texture_ok and sprite.texture.resource_path.ends_with("level_up_star_%d.png" % int(stars.stars[index]["frame"])) and sprite.material.blend_mode == CanvasItemMaterial.BLEND_MODE_ADD
	_assert_true(texture_ok, "each star holds one random AIR06_03..06 frame, drawn additively")
	_assert_eq([LevelUpStars.level(0, 8), LevelUpStars.level(9, 8), LevelUpStars.level(10, 8), LevelUpStars.level(24, 8), LevelUpStars.level(25, 8)], [16, 16, 15, 1, 0], "full level for hold + 1 ticks after the first, then −1 a tick (0x422c9a)")
	_assert_eq([LevelUpStars.rise_at(0, 1.5), LevelUpStars.rise_at(1, 1.5), LevelUpStars.rise_at(3, 1.5)], [0.0, 1.0, 4.0], "straight up by floor(speed × age) (0x45ebdc keeps the fraction)")
	stars.advance(OriginalTick.seconds(0.5))
	var first: Sprite2D = stars.get_child(0)
	_assert_true(first.visible and first.position == Vector2(stars.stars[0]["offset"]), "the first star is drawn at its spawn offset on tick 0")
	var end_tick := 0
	for star in stars.stars:
		end_tick = maxi(end_tick, int(star["appear"]) + int(star["hold"]) + 17)
	_assert_true(stars.advance(OriginalTick.seconds(end_tick - 1.5)), "stars are alive until the last one fades")
	_assert_true(not stars.advance(OriginalTick.seconds(1.5)) and not stars.visible, "then the shower is over (%d ticks)" % end_tick)
	var again: Node2D = LevelUpStars.new()
	root.add_child(again)
	again.begin(12345)
	_assert_eq(again.stars, stars.stars, "the same exchange and recipient scatter the same stars")
	stars.queue_free()
	again.queue_free()
	await process_frame


func _test_damage_digit_states() -> void:
	_assert_eq(DamageNumberFloat.state_at(0, 2)["visible"], 0, "the hold tick draws nothing")
	var tick1 := DamageNumberFloat.state_at(1, 2)
	_assert_eq([tick1["visible"], tick1["newest"], tick1["previous"], tick1["flash"], tick1["flash_level"]], [1, 1, 0, 1, 16], "tick 1: only the first (leftmost) digit, at 2×, with the NUM510 flash at level 16")
	_assert_eq([DamageNumberFloat.state_at(6, 2)["flash_level"], DamageNumberFloat.state_at(7, 2)["flash"]], [11, 0], "the flash burns 6 ticks, 16 → 11")
	var tick10 := DamageNumberFloat.state_at(10, 2)
	_assert_eq([tick10["visible"], tick10["newest"], tick10["previous"], tick10["flash"]], [2, 2, 1, 2], "tick 10: the second digit joins at 2×, the first at 1.5×, the flash moves to it")
	_assert_eq(DamageNumberFloat.state_at(11, 2)["previous"], 0, "the 1.5× step lasts to the next half-step")
	var tick20 := DamageNumberFloat.state_at(20, 2)
	_assert_eq([tick20["visible"], tick20["newest"], tick20["previous"]], [2, 0, 2], "tick 20: past the last digit only the 1.5× step remains")
	var tick21 := DamageNumberFloat.state_at(21, 2)
	_assert_eq([tick21["visible"], tick21["newest"], tick21["previous"], tick21["level"]], [2, 0, 0, 16], "then the whole number stands at 1×")
	_assert_eq([DamageNumberFloat.state_at(38, 2)["level"], DamageNumberFloat.state_at(39, 2)["level"], DamageNumberFloat.state_at(53, 2)["level"]], [16, 15, 1], "18 settle ticks, then the level drops a tick")
	_assert_true(not DamageNumberFloat.state_at(54, 2)["alive"], "deleted at level 0")
	_assert_eq([DamageNumberFloat.life_ticks(1), DamageNumberFloat.life_ticks(2), DamageNumberFloat.life_ticks(3)], [44, 54, 64], "life 10 × digits + 34 (original_tick_counts §1)")
	_assert_true(DamageNumberFloat.state_at(43, 1)["alive"] and not DamageNumberFloat.state_at(44, 1)["alive"], "a one-digit number lives 44 ticks")
	var three := []
	for tick in [1, 10, 20, 30]:
		three.append(DamageNumberFloat.state_at(tick, 3)["visible"])
	_assert_eq(three, [1, 2, 3, 3], "digits appear one by one, left to right, every 10 ticks")


func _test_damage_digit_node() -> void:
	var number: Node2D = DamageNumberFloat.new()
	root.add_child(number)
	number.position = Vector2(200, 150)
	number.present(57)
	_assert_true(number.glyphs[0].texture.resource_path.ends_with("damage_digit_5.png") and number.glyphs[1].texture.resource_path.ends_with("damage_digit_7.png"), "NUM105 then NUM107: the digits in reading order")
	_assert_eq([number.glyphs[0].position, number.glyphs[1].position], [Vector2(-7, 0), Vector2(7, 0)], "first digit at x − 7 × (digits − 1), 14 px apart")
	number.set_process(false)
	number.advance(OriginalTick.seconds(1.5))
	_assert_true(number.glyphs[0].visible and not number.glyphs[1].visible and number.glyphs[0].scale == Vector2(2, 2), "tick 1 shows the leftmost digit at 2× — the recording's 203.25 s 「2」 of 「22」")
	_assert_true(number.flash.visible and number.flash.scale == Vector2(4, 4) and number.flash.material.blend_mode == CanvasItemMaterial.BLEND_MODE_ADD, "behind it the 4× additive NUM510 flash")
	number.advance(OriginalTick.seconds(9.0))
	_assert_true(number.glyphs[1].visible and number.glyphs[1].scale == Vector2(2, 2) and number.glyphs[0].scale == Vector2(1.5, 1.5), "tick 10 completes 「57」")
	var positions := []
	for tick in range(40):
		number.advance(OriginalTick.TICK_SECONDS)
		positions.append(number.position.y + number.glyphs[0].position.y)
	_assert_eq(positions.filter(func(y): return y != 150.0), [], "kind 0 does not rise (no 0x10000 toggle)")
	var finished := [false]
	number.finished.connect(func(): finished[0] = true)
	number.advance(OriginalTick.seconds(20.0))
	_assert_true(finished[0] and not number.visible, "finished once the level reaches 0")
	number.queue_free()
	await process_frame


func _game_scripts(directory: String) -> Array[String]:
	var found: Array[String] = []
	for file in DirAccess.get_files_at(directory):
		if file.ends_with(".gd"): found.append("%s/%s" % [directory, file])
	for sub in DirAccess.get_directories_at(directory):
		found.append_array(_game_scripts("%s/%s" % [directory, sub]))
	return found
