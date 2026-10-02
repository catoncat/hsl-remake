extends SceneTree
## Windowed capture for the level atlas (tools/hsl_level_atlas.py capture). One process takes a list
## of campaign entries in turn (`-- --levels=51,1,501 --out=DIR [--mode=clean] [--choice=900:1]`),
## so its window opens, and takes the keyboard focus, once per run. Renders go through a SubViewport
## sharing the battle's World2D at zoom 1, so the UI CanvasLayers (cursor, menus, boards) never enter
## the picture. Moving backgrounds and waterfalls (MapObjectDrift) sit where the camera puts them:
## on such a map the render is put together from view-sized tiles, each with the drift placed for a
## camera looking at that tile, so the sky behind a transparent map is the one a player sees there.
##
## Default mode: the opening plays at remake pacing with every line clicked through (the
## tests/capture_battle_review.gd opening loop; a scripted choice takes the --choice row, and without
## one the scene is taken at the choice). The moment it hands over (every actor snapped to its cell,
## round 1 set up but nobody started) the scene is frozen, so an AI that would act first never moves:
##   DIR/LEVELnnn/map.png      map backdrop + map objects; actors and battle presentation hidden
##   DIR/LEVELnnn/opening.png  the same render with the actors shown: the designed deployment
##   DIR/LEVELnnn/units.json   every PlayLoop unit (side, name, title, level, cell, commandable,
##                             drawn), the armed win／fail／event statuses, who acts before the party
## A story scene (campaign kind story) gets map.png only, once its stage is built.
##
## --mode=clean: as soon as the stage is built, the backdrop and the static EVEF stand objects only,
## on a transparent background: DIR/LEVELnnn/clean.png + clean.json (which objects were hidden).
## Hidden as effects: moving backgrounds (mapobjMoveBG／mapobjMoveBGFlash), clouds, cloud shadows and
## fog (mapobjCloud), flashing lights (mapobjFlash), additive frame animations (fire: mapobjNextShape*
## with engADDCOLOR); hidden chests and anything else the game does not draw at the start;
## everything outside the two map-object layers (actors, story-inserted effects such as rain, smoke
## and fire, overlays). Reads runtime state and toggles visibility／processing
## for the render only; reference material, not parity proof.
const CampaignProgress = preload("res://game/common/CampaignProgress.gd")
const Presence = preload("res://game/sim/BattlePresenceRules.gd")
const UISkin = preload("res://game/common/BattleUISkin.gd")
const ActorSpriteKey = preload("res://game/battle/runtime/ActorSpriteKey.gd")
const OPENING_BUDGET_MS := 240000
## Opening events a player clicks through or skips (a line, the win／fail board, a section title, a movie).
const CLICK_THROUGH := ["dialogue_message_id", "winfail_board_refresh", "section_title_resource", "movie_play"]
const EFFECT_KINDS := ["mapobjMoveBG", "mapobjMoveBGFlash", "mapobjCloud", "mapobjFlash"]
var levels: Array[int] = []
var mode := "levels"
var slot := 0
var choices := {}
var out_root := ""
var level := 0
var out_dir := ""
var scene: Node
var failures: Array[String] = []
var report := {}


func _init() -> void:
	preload("res://game/battle/scene/BattleSceneRuntime.gd").hold_finished_battle = true


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	# reset_campaign() deletes the campaign save in user://: never in the real user directory.
	if not OS.get_user_data_dir().begins_with(ProjectSettings.globalize_path("res://ignored/")):
		push_error("Level atlas capture clears the campaign save in user://: run it through tools/hsl_level_atlas.py (HOME under ignored/)")
		quit(2)
		return
	if DisplayServer.get_name() == "headless":
		push_error("Level atlas capture requires a rendering window")
		quit(2)
		return
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--levels="):
			for part in arg.trim_prefix("--levels=").split(",", false):
				levels.append(int(part))
		elif arg.begins_with("--out="):
			out_root = arg.trim_prefix("--out=")
		elif arg.begins_with("--mode="):
			mode = arg.trim_prefix("--mode=")
		elif arg.begins_with("--slot="):
			slot = int(arg.trim_prefix("--slot="))
		elif arg.begins_with("--choice="):
			for pair in arg.trim_prefix("--choice=").split(",", false):
				var parts := pair.split(":")
				if parts.size() == 2:
					choices[int(parts[0])] = int(parts[1])
	if out_root == "":
		out_root = "res://ignored/level-atlas"
	if out_root.begins_with("res://") or out_root.begins_with("user://"):
		out_root = ProjectSettings.globalize_path(out_root)
	root.title = "HSL Level Atlas"
	root.size = Vector2i(640, 480)
	# Parallel runs (--slot) stagger their windows: a fully covered window stops drawing.
	root.position = DisplayServer.screen_get_position(DisplayServer.window_get_current_screen()) + Vector2i(40 + slot * 620, 40 + slot * 300)
	await process_frame
	print("LEVEL_ATLAS_WINDOW_READY pid=%d levels=%d" % [OS.get_process_id(), levels.size()])
	var failed: Array[int] = []
	for entry_level in levels:
		var ok: bool = await capture_level(entry_level)
		if not ok:
			failed.append(entry_level)
	print("LEVEL_ATLAS_DONE levels=%d failed=%s" % [levels.size(), str(failed)])
	await create_timer(0.3).timeout
	quit(0 if failed.is_empty() else 1)


func capture_level(entry_level: int) -> bool:
	level = entry_level
	failures = []
	out_dir = out_root.path_join("LEVEL%03d" % level)
	DirAccess.make_dir_recursive_absolute(out_dir)
	print("LEVEL_ATLAS_BEGIN level=%d" % level)
	var entry: Dictionary = CampaignProgress.load_campaign().get("battles", {}).get(str(level), {})
	var scenario_path := str(entry.get("scenario", ""))
	report = {"schema": "hsl_level_atlas_capture.v3", "level": level, "mode": mode, "scenario": scenario_path, "kind": str(entry.get("kind", "battle"))}
	if not scenario_path.ends_with(".json"):
		check(false, "campaign.json has no battle scenario for level %d" % level)
		return await finish_level()
	CampaignProgress.reset_campaign()
	CampaignProgress.pending = {}
	root.title = "HSL Level Atlas %03d" % level
	scene = load("res://game/battle/scene/BattleSceneRuntime.tscn").instantiate()
	scene.scenario_path = scenario_path
	scene.startup_mode = "product_opening"
	root.add_child(scene)
	current_scene = scene
	await process_frame
	await process_frame
	var texture: Texture2D = scene.map_backdrop.texture
	check(texture != null, "map texture loads for " + scenario_path)
	if texture == null:
		return await finish_level()
	report["map_px"] = [texture.get_width(), texture.get_height()]
	var presentation: Node = scene.get_node("BattlePresentation")
	if mode == "clean":
		scene.set_process(false)
		report["clean"] = await render("clean.png", clean_hidden(presentation), true)
		return await finish_level()
	if scene.is_story_scene():
		report["kind"] = "story"
		await create_timer(0.3).timeout
		scene.set_process(false)
		report["map"] = await render("map.png", [presentation, scene.move_overlay, scene.actors_root])
		return await finish_level()
	check(bool(scene.play_loop.get("scenario_ok", false)), "battle scenario loads: " + str(scene.play_loop.get("scenario_error", "")))
	var coordinator = scene.opening_coordinator
	var started := Time.get_ticks_msec()
	while coordinator != null and coordinator.active and Time.get_ticks_msec() - started < OPENING_BUDGET_MS:
		if CampaignProgress.has_pending() or not is_instance_valid(scene):
			break
		if scene.party_equipment_screen != null and scene.party_equipment_screen.active:
			scene.party_equipment_screen.close()
		if not coordinator.select_options.is_empty():
			report["opening_choice"] = {"options": coordinator.select_options.size()}
			if not choices.has(level):
				break  # no --choice row: the scene is taken at the choice (a pick may hand off without a battle)
			report["opening_choice"]["row"] = clampi(int(choices[level]), 0, coordinator.select_options.size() - 1)
			coordinator.choose_select_option(report["opening_choice"]["row"])
		elif str(coordinator.summary().get("current_event_kind", "")) in CLICK_THROUGH:
			coordinator.handle_input(click())
		await process_frame
	# The opening hands over inside the scene's _process (or the click above): BattleOpeningCoordinator
	# snaps every actor to its cell and enter_first_control_state sets up round 1, whose first AI step
	# waits for a later _process. This frame's _process has not run yet: freezing now keeps the deployment.
	if is_instance_valid(scene):
		scene.set_process(false)
	report["opening_done"] = coordinator == null or not coordinator.active
	report["opening_seconds"] = snappedf((Time.get_ticks_msec() - started) / 1000.0, 0.1)
	if not report["opening_done"] and coordinator != null:
		report["stopped_at"] = coordinator.summary()
	if not is_instance_valid(scene):
		check(false, "the battle scene left before it could be rendered")
		return await finish_level()
	var settle_start := Time.get_ticks_msec()
	while scene.has_actor_motion() and Time.get_ticks_msec() - settle_start < 3000:
		await process_frame
	var loop: Dictionary = scene.play_loop
	report["turn"] = int(loop.get("turn", 0))
	report["interaction"] = str(loop.get("interaction", ""))
	for key in ["win_statuses", "fail_statuses", "event_statuses"]:
		report[key] = loop.get(key, [])
	report.merge(round_order(loop))
	report["map"] = await render("map.png", [presentation, scene.move_overlay, scene.actors_root])
	report["opening"] = await render("opening.png", [presentation, scene.move_overlay])
	report["units"] = unit_rows()
	var living: Array = report["units"].filter(func(u): return u["living"])
	report["living_units"] = living.size()
	report["drawn_units"] = report["units"].filter(func(u): return u["drawn"]).size()
	check(report["opening"].get("sha", "") != report["map"].get("sha", "") or living.is_empty(), "opening.png differs from map.png (a fresh frame with the actors shown)")
	return await finish_level()


## The clean map keeps the backdrop and the two map-object layers, minus their effect objects
## (EFFECT_KINDS, additive frame animations); clean.json lists what was hidden and what was kept.
func clean_hidden(presentation: Node) -> Array:
	var hidden: Array = [presentation]
	for child in scene.world_root.get_children():
		if child != scene.map_backdrop and child != scene.map_objects_back and child != scene.map_objects_foreground and child is CanvasItem:
			hidden.append(child)
	var records := {}
	for record in scene.stage.map_object_stand_records():
		records[int(record.get("record_index", -1))] = record
	var kept: Array = []
	var dropped: Array = []
	for layer in [scene.map_objects_back, scene.map_objects_foreground]:
		for sprite in layer.get_children():
			var record: Dictionary = records.get(int(sprite.get_meta("record_index", -1)), {})
			var kind := str(scene.stage.map_object_field_value(record, "obj_Data9"))
			var additive := str(scene.stage.map_object_field_value(record, "obj_Mode")).begins_with("engADDCOLOR")
			var row := {"name": str(record.get("object_name", sprite.name)), "kind": kind, "additive": additive, "role": str(record.get("role", "")),
				"shown": sprite is CanvasItem and sprite.is_visible_in_tree()}
			# A hidden chest (template obj_Attribute without objattrATTACKFLAG, BattleTreasurePresentation)
			# is not drawn for a player at the start, whatever the 寶箱 option says.
			var hidden_chest: bool = row["role"] == "treasure_box" and not str(scene.stage.map_object_field_value(record, "obj_Attribute")).contains("objattrATTACKFLAG")
			if kind in EFFECT_KINDS or (kind.begins_with("mapobjNextShape") and additive) or hidden_chest or not row["shown"]:
				hidden.append(sprite)
				dropped.append(row)
			else:
				kept.append(row)
	for child in hidden:
		if child.get_meta("record_index", -1) != -1 and child.get_parent() == scene.world_root:
			dropped.append({"name": str(records.get(int(child.get_meta("record_index")), {}).get("object_name", child.name)), "kind": "backdrop layer", "additive": false, "role": ""})
	report["hidden_objects"] = dropped
	report["kept_objects"] = kept
	return hidden


## Round 1 in queue order from the current slot up to the first player-commandable actor:
## everyone listed acts before the party can.
func round_order(loop: Dictionary) -> Dictionary:
	var queue: Dictionary = loop.get("turn_queue", {})
	var slots: Array = queue.get("slots", [])
	var commandable := {}
	for unit in loop.get("units", []):
		commandable[str(unit["id"])] = bool(unit.get("player_commandable", false))
	var ahead: Array = []
	for index in range(maxi(0, int(queue.get("index", 0))), slots.size()):
		var slot_entry: Dictionary = slots[index]
		if not bool(slot_entry.get("enabled", true)) or bool(slot_entry.get("consumed", false)):
			continue
		if commandable.get(str(slot_entry.get("id", "")), false):
			return {"acts_before_player": ahead, "player_in_queue": true}
		ahead.append(str(slot_entry.get("id", "")))
	return {"acts_before_player": ahead, "player_in_queue": false}


## Renders the battle's World2D at zoom 1 into an image the size of the map texture (the scene is
## frozen by the caller), `hidden` nodes hidden. The frame counter must advance and most sampled
## pixels must match the backdrop texture, so a stale or blank render (an occluded window that
## stopped drawing) fails instead of saving.
func render(file_name: String, hidden: Array, transparent := false) -> Dictionary:
	var texture: Texture2D = scene.map_backdrop.texture
	var size := Vector2i(texture.get_width(), texture.get_height())
	var restore := {}
	for node in hidden:
		restore[node] = node.visible
		node.visible = false
	var viewport := SubViewport.new()
	viewport.size = size
	viewport.world_2d = scene.get_world_2d()
	viewport.transparent_bg = transparent
	viewport.disable_3d = true
	viewport.canvas_item_default_texture_filter = root.canvas_item_default_texture_filter
	viewport.snap_2d_transforms_to_pixel = root.snap_2d_transforms_to_pixel
	viewport.snap_2d_vertices_to_pixel = root.snap_2d_vertices_to_pixel
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	viewport.canvas_transform = Transform2D.IDENTITY
	var frames_before := Engine.get_frames_drawn()
	var image: Image = await compose(viewport, size, hidden)
	var frames_drawn := Engine.get_frames_drawn() - frames_before
	root.remove_child(viewport)
	viewport.free()
	for node in restore:
		node.visible = restore[node]
	image.convert(Image.FORMAT_RGBA8 if transparent else Image.FORMAT_RGB8)
	var backdrop: Image = texture.get_image()
	backdrop.convert(image.get_format())
	var matched := 0
	var samples := 0
	for y in range(16, size.y, 64):
		for x in range(16, size.x, 64):
			samples += 1
			if image.get_pixel(x, y).is_equal_approx(backdrop.get_pixel(x, y)):
				matched += 1
	var match_ratio := float(matched) / maxf(1.0, float(samples))
	check(frames_drawn > 0, "%s: the window drew new frames for the render" % file_name)
	# 0.1, not more: map objects can cover most of a map (龍之息's lava field leaves about a quarter).
	check(match_ratio >= 0.1, "%s: the render shows the map backdrop (%.2f of samples match)" % [file_name, match_ratio])
	var path := out_dir.path_join(file_name)
	check(image.save_png(path) == OK, "save " + path)
	var digest := HashingContext.new()
	digest.start(HashingContext.HASH_MD5)
	digest.update(image.get_data())
	return {"file": file_name, "size": [image.get_width(), image.get_height()], "frames_drawn": frames_drawn,
		"backdrop_match": snappedf(match_ratio, 0.01), "sha": digest.finish().hex_encode()}


## One pass, or (moving backgrounds／waterfalls on the map) one pass per view-sized tile with the
## drift placed for a camera whose top-left is that tile, each pass contributing its tile.
func compose(viewport: SubViewport, size: Vector2i, hidden: Array) -> Image:
	var drift: Node = scene.get_node_or_null("MapObjectDrift")
	var moving: bool = drift != null and (not drift.backgrounds.is_empty() or not drift.waterfalls.is_empty())
	var view: Vector2i = scene.logical_viewport_size
	var tiles: Array = [Vector2i.ZERO]
	var saved_camera := Callable()
	var drift_processing := false
	if moving:
		tiles = []
		for y in tile_starts(size.y, view.y):
			for x in tile_starts(size.x, view.x):
				tiles.append(Vector2i(x, y))
		saved_camera = drift.camera_top_left
		drift_processing = drift.is_processing()
		drift.set_process(false)
		report["drift_tiles"] = tiles.size()
	var composed: Image = null
	for tile in tiles:
		if moving:
			drift.camera_top_left = func() -> Vector2: return Vector2(tile)
			for background in drift.backgrounds:
				drift._place_background(background)
			for waterfall in drift.waterfalls:
				drift.step_waterfall(waterfall, tile, true)
				drift._draw_waterfall(waterfall)
		for _frame in range(3):
			await process_frame
			for node in hidden:
				node.visible = false
		RenderingServer.force_draw(false)
		var pass_image: Image = viewport.get_texture().get_image()
		if not moving:
			return pass_image
		if composed == null:
			composed = Image.create(size.x, size.y, false, pass_image.get_format())
		var area := Rect2i(tile, view).intersection(Rect2i(Vector2i.ZERO, size))
		composed.blit_rect(pass_image, area, area.position)
	drift.camera_top_left = saved_camera
	for background in drift.backgrounds:
		drift._place_background(background)
	drift.set_process(drift_processing)
	return composed


## Top-left offsets of view-sized tiles covering `total` pixels, the last one clamped to the map edge
## (the camera's own range).
func tile_starts(total: int, span: int) -> Array:
	var starts: Array = []
	var at := 0
	while true:
		starts.append(mini(at, maxi(0, total - span)))
		if at + span >= total:
			break
		at += span
	return starts


func unit_rows() -> Array:
	var actors: Dictionary = UISkin.data()["actors"]
	var rows: Array = []
	for unit in scene.play_loop.get("units", []):
		var row: Dictionary = actors.get(ActorSpriteKey.row_key(unit, actors), {})
		var coord: Variant = unit.get("coord", Vector2i.ZERO)
		var node: Node = scene.actor_node_for_unit(str(unit["id"]))
		rows.append({
			"id": str(unit["id"]), "actor_id": str(unit.get("actor_id", "")),
			"role": str(unit.get("battle_actor_role", "")),
			"name": str(unit.get("display_name", row.get("name", ""))),
			"title": str(unit.get("title", row.get("title", ""))),
			"race": str(actors.get(str(unit.get("actor_id", "")), {}).get("race", "")),
			"level": int(unit.get("level", 0)), "hp": int(unit.get("hp", 0)), "max_hp": int(unit.get("max_hp", 0)),
			"cell": [coord.x, coord.y] if coord is Vector2i else [int(coord[0]), int(coord[1])],
			"commandable": bool(unit.get("player_commandable", false)),
			"living": Presence.living(unit), "departed": bool(unit.get("departed", false)),
			"drawn": node != null and node is CanvasItem and node.is_visible_in_tree() and not bool(unit.get("no_showshape", false)),
		})
	return rows


func finish_level() -> bool:
	report["failures"] = failures
	var manifest := FileAccess.open(out_dir.path_join("clean.json" if mode == "clean" else "units.json"), FileAccess.WRITE)
	if manifest != null:
		manifest.store_string(JSON.stringify(report, "  "))
		manifest.close()
	if is_instance_valid(scene):
		scene.queue_free()
	scene = null
	current_scene = null
	await process_frame
	await process_frame
	await create_timer(0.3).timeout
	if failures.is_empty():
		print("LEVEL_ATLAS_PASS level=%d mode=%s opening_done=%s living=%s drawn=%s" % [level, mode, str(report.get("opening_done", "-")), str(report.get("living_units", "-")), str(report.get("drawn_units", "-"))])
	else:
		print("LEVEL_ATLAS_FAIL level=%d count=%d first=%s" % [level, failures.size(), failures[0]])
	return failures.is_empty()


func click() -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	return event


func check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)
		push_error(label)
