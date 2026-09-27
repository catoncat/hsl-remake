extends SceneTree
## Windowed review captures for lane R7-NPC (level 51, 棄卒):
##   01 first control under the loop seed: equal-speed Leonard now acts before the
##      level-1 friendly 023 (0x407660 registration order); the queue prints alongside.
##   02 the recording's round-3 board (R3-24): 021_3 at (12,11) strikes 023_2 at (14,10)
##      from (14,11) — the 0x413390 station below the target keys farther than (13,10) left of it
##   03 the same board with the coin at 0: still (14,11) — the half-cell bias leaves no tie to draw on.
## HSL_RNG_SEED=1 tools/godot.sh --script res://tests/capture_npc_station_review.gd -- --out=/abs/dir
## Writes PNGs of the game window only; exits 0 when every capture landed.
const Loop = preload("res://game/battle/scene/BattlePlayLoop.gd")
const LoopAI = preload("res://game/battle/scene/BattleLoopAI.gd")
const CampaignProgress = preload("res://game/battle/runtime/CampaignProgress.gd")
const R3_24 := {"actor021_3": Vector2i(12, 11), "actor023_2": Vector2i(14, 10), "actor021_1": Vector2i(12, 9),
	"actor021_5": Vector2i(9, 9), "actor026_1": Vector2i(11, 9), "actor026_2": Vector2i(9, 8), "actor023_1": Vector2i(16, 14),
	"leonard": Vector2i(15, 16), "actor024_2": Vector2i(14, 15), "actor024_1": Vector2i(15, 15)}
var OUT := "res://ignored/r7-npc-review/"
var scene: Node
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="): OUT = arg.trim_prefix("--out=").trim_suffix("/") + "/"
	DirAccess.make_dir_recursive_absolute(OUT)
	CampaignProgress.reset_campaign()
	CampaignProgress.pending = {}
	root.size = Vector2i(640, 480)
	root.title = "HSL R7-NPC review"
	create_timer(120).timeout.connect(func(): push_error("review timed out"); quit(2))
	scene = load("res://game/battle/scene/BattleSceneRuntime.tscn").instantiate()
	scene.scenario_path = "res://content/battles/battle_051.json"
	scene.startup_mode = "dev_first_control"
	root.add_child(scene)
	current_scene = scene
	await process_frame
	await process_frame
	scene.start_dev_first_control_harness()
	await create_timer(0.8).timeout
	var slots: Array = scene.play_loop["turn_queue"]["slots"]
	print("R7NPC_QUEUE %s" % str(slots.map(func(slot): return "%s:%d" % [slot["id"], int(slot["live_speed"])])))
	_shot("01-first-control")
	await _station(1, Vector2i(14, 11), "02-r3-24-station-coin1")
	await _station(0, Vector2i(14, 11), "03-r3-24-station-coin0")
	print("R7NPC_REVIEW %s failures=%s" % [OUT, failures])
	quit(0 if failures.is_empty() else 1)


func _station(coin: int, expected: Vector2i, label: String) -> void:
	var board: Dictionary = scene.play_loop.duplicate(true)
	for unit in board["units"]:
		if R3_24.has(unit["id"]): unit["coord"] = R3_24[unit["id"]]
		elif str(unit["id"]) in ["actor021_2", "actor021_4"]:
			unit["hp"] = 0
			unit["defeated"] = true
	Loop._unit(board, "actor021_3")["ai_target_id"] = "actor023_2"
	# rand(2) answers `coin`; every other draw takes its lowest value.
	var step: Dictionary = LoopAI._ai_take_turn(board, "actor021_3", func(bound): return coin if bound == 2 else 0)
	var action: Dictionary = step["action"]
	check(action.get("to") == expected and action.get("target_id") == "actor023_2", "%s: 021_3 strikes 023_2 from %s (got %s, %s)" % [label, str(expected), str(action.get("to")), str(action.get("ai_decision", {}).get("attack_station", {}))])
	var shown: Dictionary = board.duplicate(true)
	Loop._unit(shown, "actor021_3")["coord"] = action.get("to", R3_24["actor021_3"])
	scene.apply_loop(shown, "test")
	await create_timer(0.5).timeout
	_shot(label)


func _shot(label: String) -> void:
	check(root.get_texture().get_image().save_png(OUT + label + ".png") == OK, "capture " + label)


func check(condition: bool, label: String) -> void:
	if not condition:
		failures.append(label)
		push_error(label)
