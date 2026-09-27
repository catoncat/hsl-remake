extends "res://tests/capture_story_scene_review.gd"
## Reuse real story controls at normal speed after rebuilding maps through OBS.
## No story, camera, actor or campaign rules are replaced by this review.
var checked_maps: Dictionary = {}

func _initialize() -> void:
	ProjectSettings.set_setting("application/config/use_custom_user_dir", true)
	ProjectSettings.set_setting("application/config/custom_user_dir_name", "HSL-Review-MapBinding-" + str(OS.get_process_id()))
	DirAccess.make_dir_recursive_absolute(OS.get_user_data_dir())
	call_deferred("run")

func shot(label: String) -> void:
	OUT = "res://ignored/map-binding-review/%03d/" % level
	DirAccess.make_dir_recursive_absolute(OUT)
	root.position = DisplayServer.screen_get_position(root.current_screen) + Vector2i(60, 80)
	if is_instance_valid(scene):
		var current_level := int(scene.first_battle_scenario.get("level", 0))
		if current_level > 0 and not checked_maps.has(current_level):
			var packet: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://docs/evidence_packets/static_reverse/original_map_binding.json"))
			var matches: Array = packet["sources"]["bindings"].filter(func(row): return int(row["level"]) == current_level)
			check(matches.size() == 1, "current rendered level has one reviewed original binding")
			if matches.size() == 1:
				var binding: Dictionary = matches[0]
				var seed: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://content/generated/hsl/chapter01/battle%03d_seed.json" % current_level))
				check(str(seed["sources"]["map"]["member"]).to_lower() == str(binding["shape_member"]).to_lower(), "actual scene uses the full source map member")
				check(seed["sources"]["map"]["sha256"] == binding["shape_sha256"], "scene seed names the original map bytes, not the similar camp")
				check(scene.map_texture_path == seed["map"]["decoded_png"] and scene.map_backdrop.texture.resource_path == scene.map_texture_path, "Runtime binds the generated map to the visible backdrop")
				var original := Image.load_from_file(scene.map_texture_path)
				var displayed: Image = scene.map_backdrop.texture.get_image()
				original.convert(Image.FORMAT_RGBA8)
				displayed.convert(Image.FORMAT_RGBA8)
				check(displayed.get_size() == Vector2i(int(binding["shape_size"][0]), int(binding["shape_size"][1])), "rendered map has the source dimensions")
				check(displayed.get_data() == original.get_data(), "visible texture pixels equal the source-derived PNG")
				var hash := HashingContext.new()
				hash.start(HashingContext.HASH_SHA256)
				hash.update(displayed.get_data())
				checked_maps[current_level] = {"level": current_level, "scene": scene.scenario_path, "map_member": binding["shape_member"], "source_sha256": binding["shape_sha256"], "png_sha256": FileAccess.get_sha256(scene.map_texture_path), "rgba_sha256": hash.finish().hex_encode(), "size": binding["shape_size"]}
	await super.shot(label)

func finish() -> void:
	check(checked_maps.has(level), "the requested scene was actually drawn and audited before handoff")
	check(Engine.time_scale == 1.0, "review uses real-time story pacing")
	FileAccess.open(OUT + "binding-receipt.json", FileAccess.WRITE).store_string(JSON.stringify({"schema":"hsl_map_binding_render.v1", "requested_level":level, "native_execution":false, "real_control_events":true, "time_scale":Engine.time_scale, "pid":OS.get_process_id(), "screen":root.current_screen, "isolated_user_directory":OS.get_user_data_dir().contains("HSL-Review-MapBinding-"), "maps":checked_maps.values(), "failures":failures}, "  "))
	await super.finish()
