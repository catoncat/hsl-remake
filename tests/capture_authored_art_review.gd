extends SceneTree
## Windowed review of the authored looks (content/authored/actors/102 and 103, placeholder
## recolours of 003／004): level 200 at first control with 蕾雅 and 托蘭 on the map in their own
## walk frames, then one ordinary cut-in shot of each drawn from their own cutin/ frames.
## Output: ignored/authored-art-review/*.png + manifest.json (visual review input, not parity proof).
const CampaignProgress = preload("res://game/battle/runtime/CampaignProgress.gd")
const Loop = preload("res://game/sim/loop/BattlePlayLoop.gd")
const OUT := "res://ignored/authored-art-review/"
const SCENARIO_PATH := "res://content/battles/battle_200.json"
var failures: Array[String] = []
var records: Array = []


func _initialize() -> void:
	call_deferred("run")


func check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)


func run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Authored art review requires a rendering window")
		quit(2)
		return
	CampaignProgress.reset_campaign()
	root.title = "HSL Authored Art Review"
	root.size = Vector2i(640, 480)
	create_timer(90).timeout.connect(func(): push_error("Authored art review timed out"); quit(2))
	DirAccess.make_dir_recursive_absolute(OUT)
	var runtime = load("res://game/battle/scene/BattleSceneRuntime.tscn").instantiate()
	runtime.scenario_path = SCENARIO_PATH
	runtime.startup_mode = "dev_first_control"
	root.add_child(runtime)
	current_scene = runtime
	await create_timer(1.0).timeout
	runtime.center_camera_on_grid(Loop.unit(runtime.play_loop, "reia")["coord"])
	await create_timer(0.6).timeout
	await _shot("map_reia_toran_walk_frames", {"units": ["reia", "toran"], "walk_frame": str(runtime.actor_node_for_unit("reia").get_node("Sprite2D").texture.resource_path)})
	var cutin = runtime.get_node("BattlePresentation").cutin
	for pair in [["reia", "wolf_1"], ["toran", "wolf_2"]]:
		var attacker := Loop.unit(runtime.play_loop, pair[0])
		var defender := Loop.unit(runtime.play_loop, pair[1])
		cutin.play({"hit": true, "damage": 5, "defender_hp_before": int(defender["hp"]), "defender_hp_after": int(defender["hp"]) - 5}, attacker, defender, false)
		var schedule: Dictionary = cutin.Timing.ordinary(cutin.manifest["actors"][str(attacker["actor_id"])], cutin.clips[0]["strike"])
		await create_timer(float(schedule["opening"]) / cutin.Timing.PLAYBACK_SPEED + 0.45).timeout
		var frame := str(cutin.attacker_sprite.texture.resource_path) if cutin.attacker_sprite.texture != null else ""
		check(cutin.attacker_sprite.visible and frame.begins_with("res://content/authored/actors/%s/cutin/" % attacker["actor_id"]), "%s cut-in draws its own frame: %s" % [pair[0], frame])
		await _shot("cutin_" + pair[0], {"attacker": pair[0], "cutin_frame": frame})
		while cutin.busy():
			await process_frame
	var file := FileAccess.open(OUT + "manifest.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"schema": "hsl_authored_art_review.v1", "scenario": SCENARIO_PATH, "shots": records, "failures": failures}, "  "))
	file.close()
	for failure in failures:
		push_error(failure)
	print("AUTHORED_ART_REVIEW_%s shots=%d output=%s" % ["PASS" if failures.is_empty() else "FAIL", records.size(), OUT])
	quit(0 if failures.is_empty() else 1)


func _shot(label: String, detail: Dictionary) -> void:
	await process_frame
	await process_frame
	check(root.get_texture().get_image().save_png(OUT + label + ".png") == OK, "capture " + label)
	var record := detail.duplicate()
	record["label"] = label
	records.append(record)
