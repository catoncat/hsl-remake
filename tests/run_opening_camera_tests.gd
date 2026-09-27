extends "res://tests/support/TestSuite.gd"

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

const OpeningCinematics = preload("res://game/battle/runtime/opening/OpeningCinematics.gd")
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


func _init() -> void:
	tag = "OPENING_CAMERA_TESTS"


func run() -> void:
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
