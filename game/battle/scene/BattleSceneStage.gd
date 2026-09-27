extends RefCounted
## Stage assembly for BattleSceneRuntime: ActorRuntime nodes for the PlayLoop roster
## (walk frames／walk audio from the scenario's actor manifests) and the EVEF stand
## objects／background sounds of map_objects.json, placed under the runtime's World
## layers. Records land on the runtime (`map_object_records`, `background_sound_records`)
## for the readback; nothing here is battle state — positions come from the PlayLoop
## through the runtime's coordinate chain.
## provenance:
##   rules: n/a
##   layout: resource-derived content/imported/hsl/chapter01/actor_walk_frames; resource-derived content/imported/hsl/chapter01/map_objects.json; resource-derived content/imported/hsl/chapter01/map_object_alignment.json; provisional (combined-placement child offsets, layer hints)
##   strings: n/a
##   timing: static-derived docs/evidence_packets/static_reverse/original_map_object_drift.md (mapobjCloud drift and mapobjMoveBG parallax, run by MapObjectDrift)
##   audio: resource-derived content/imported/hsl/chapter01/actor_audio.json; resource-derived content/imported/hsl/chapter01/scripts; provisional (background sounds play map-wide at −8 dB; native attenuation not located)

const ActorRuntime = preload("res://game/battle/runtime/ActorRuntime.gd")
const ActorSpriteKey = preload("res://game/battle/runtime/ActorSpriteKey.gd")
const BattleScenario = preload("res://game/battle/runtime/BattleScenario.gd")
const MapObjectAnimation = preload("res://game/battle/runtime/MapObjectAnimation.gd")
const MapObjectDrift = preload("res://game/battle/runtime/MapObjectDrift.gd")
const MapObjectFlash = preload("res://game/battle/runtime/MapObjectFlash.gd")
const ScriptPresentation = preload("res://game/battle/scene/BattleScriptPresentation.gd")
const ScriptActorsPresentation = preload("res://game/battle/scene/BattleScriptActorPresentation.gd")

const ContentPaths = preload("res://game/sim/ContentPaths.gd")
## map_objects.json placement roles drawn as stand sprites (tools/hsl_level_map_objects.py).
const STAND_OBJECT_ROLES := ["map_object", "static_enemy_object", "treasure_box"]

var runtime: Node


static func create(scene_runtime: Node) -> RefCounted:
	var stage := new()
	stage.runtime = scene_runtime
	return stage


func spawn_scene_actors() -> void:
	for unit_value in runtime.play_loop.get("units", []):
		if typeof(unit_value) != TYPE_DICTIONARY:
			continue
		var unit: Dictionary = unit_value
		var unit_id := str(unit.get("id", ""))
		if runtime.actor_node_for_unit(unit_id) != null:
			continue
		if not ScriptPresentation.retain_actor(runtime, unit): continue
		if ScriptActorsPresentation.defer_spawn(runtime, unit): continue
		var grid_coord: Vector2i = unit.get("grid_coord", unit.get("coord", Vector2i.ZERO))
		var actor: Node = spawn_actor_node(unit_id, str(unit.get("actor_id", "")), runtime.actor_world_position_for_grid(grid_coord), unit)
		if bool(unit.get("defeated", false)):
			actor.visible = runtime.get_node("BattlePresentation").retain_defeated_actor(runtime.play_loop, unit_id)


## Presentation actor for one roster or story-cast entry; walk frames and walk
## audio come from the scenario's actor manifests. Holds no battle state.
## `unit` is the presentation view (a PlayLoop unit, or a carried member's view from
## `carried_unit_view`): its job-up target row selects the walk frames
## (ActorSpriteKey.frame_key) and the walk sound (ActorSpriteKey.audio_binding);
## without one the base `actor_id` row is drawn and heard.
func spawn_actor_node(unit_id: String, actor_id: String, world_position: Vector2, unit: Dictionary = {}) -> Node:
	var view := unit if not unit.is_empty() else {"id": unit_id, "actor_id": actor_id}
	var actor := ActorRuntime.new()
	actor.name = runtime.actor_node_name(unit_id)
	actor.configure_from_manifest(unit_id, actor_manifest_entry(frame_key_for_unit(view)))
	_configure_walk_audio(actor, view)
	actor.position = world_position
	sync_actor_depth(actor, view)
	actor.play_state("idle", "0")
	if bool(view.get("no_showshape", false)): actor.hide_shape()
	runtime.actors_root.add_child(actor)
	return actor


## PLAYERS rows may carry no walk sound (and the shared encounter pool may not yet
## have one for every reviewed monster); such actors walk silently.
func _configure_walk_audio(actor: Node, unit: Dictionary) -> void:
	var sound_path := ActorSpriteKey.audio_binding(unit, "walk", [runtime.actor_audio_manifest, runtime.shared_actor_audio_manifest])
	if sound_path != "":
		actor.configure_walk_audio(sound_path)


## Walk-frame row for a PlayLoop unit: job-up target when imported, else its actor id.
func frame_key_for_unit(unit: Dictionary) -> String:
	return ActorSpriteKey.frame_key(unit, [runtime.actor_walk_manifest, runtime.shared_actor_walk_manifest])


## Presentation view of a cast member that has no PlayLoop unit (story-scene cast,
## big-map marker): the hand-off carry's record for `unit_id` supplies the job-up
## target row when it holds this member on the same base row, so cutscenes and the
## map draw the title the battles do. Otherwise just the base row.
func carried_unit_view(unit_id: String, actor_id: String) -> Dictionary:
	var view := {"id": unit_id, "actor_id": actor_id}
	var carry: Variant = runtime.campaign_handoff.get("carry", {})
	if typeof(carry) != TYPE_DICTIONARY:
		return view
	var record: Variant = ((carry as Dictionary).get("units", {}) as Dictionary).get(unit_id, {})
	if typeof(record) == TYPE_DICTIONARY and str((record as Dictionary).get("actor_id", "")) == actor_id and str((record as Dictionary).get("job_up_target_actor_id", "")) != "":
		view["job_up_target_actor_id"] = str((record as Dictionary)["job_up_target_actor_id"])
	return view


## An in-battle job-up (actPlayerJobUpProcess: 咕嚕 008 → 017) or a replayed carry
## changes the unit's row after its node exists; reload the frames and the walk sound
## from the row now keyed, keeping position/motion. ActorRuntime.actor_id mirrors the
## loaded frame set.
func sync_actor_row(actor: Node, unit: Dictionary) -> void:
	sync_actor_depth(actor, unit)
	actor.set_additive(str(unit.get("draw_mode", "")).begins_with("engADDCOLOR"))
	var frame_key := frame_key_for_unit(unit)
	if frame_key == "" or str(actor.actor_id) == frame_key:
		return
	actor.configure_from_manifest(str(unit.get("id", "")), actor_manifest_entry(frame_key))
	_configure_walk_audio(actor, unit)
	if not actor.is_moving():
		actor.play_state("idle", "0")


## A flying unit draws 10 rows deeper (ActorRuntime.FLYING_DEPTH_ROWS); the flag is the
## PlayLoop unit's traversal, which actSetPlayerFly can change mid-battle.
func sync_actor_depth(actor: Node, unit: Dictionary) -> void:
	actor.flying_depth = bool((unit.get("traversal", {}) as Dictionary).get("flying", false))


## Lookup order: the scenario's own manifest, then the shared up-title manifest. An
## actor in neither is a data error: it is reported and drawn frameless
## (ActorRuntime `missing_frame_manifest`), never as another actor's sprite.
func actor_manifest_entry(actor_id: String) -> Dictionary:
	var entry := ActorSpriteKey.manifest_entry(actor_id, [runtime.actor_walk_manifest, runtime.shared_actor_walk_manifest])
	if not entry.is_empty():
		return entry
	push_error("Actor walk manifest has no entry for actor " + actor_id)
	return {"actor_id": actor_id, "animations": {}, "unresolved": ["actor_walk_manifest_missing_entry"]}


func spawn_map_objects() -> void:
	_clear_map_object_layer(runtime.map_objects_back)
	_clear_map_object_layer(runtime.map_objects_foreground)
	runtime.map_object_records.clear()
	var drift := _map_object_drift()
	_start_background_sounds()
	var animation_manifest: Dictionary = runtime.load_optional_json(BattleScenario.resource_path(runtime.first_battle_scenario, "fire_animation"))
	for item in map_object_stand_records():
		var record: Dictionary = item
		# Stand objects, plus enemy-process objects whose shape has no walk groups
		# (level 12's Enemy101 船殼 hull pieces, role static_enemy_object) and EVEF 寶藏
		# chests (defProcTreasureBox, role treasure_box). The source-owned treasure
		# view hides collected instances; story-only previews retain the closed art.
		if str(record.get("process", "")) != "defProcStandObject" and str(record.get("role", "")) not in STAND_OBJECT_ROLES:
			continue
		var shape_id := str(record.get("shape_resource_id", ""))
		var texture: Texture2D = load(_map_object_preview_path(shape_id))
		if texture == null:
			push_error("Missing map object texture for %s" % shape_id)
			continue
		var placement: Dictionary = runtime.map_object_placement.resolve(record) if runtime.map_object_placement != null else {}
		var candidate_anchor_world: Vector2 = placement.get("candidate_anchor_world", Vector2(float(record.get("candidate_x", 0)), float(record.get("candidate_y", 0))))
		var anchor_world: Vector2 = placement.get("render_anchor_world", candidate_anchor_world)
		if placement.is_empty():
			continue
		var top_left_world: Vector2 = placement["top_left_world"]
		var runtime_layer := _map_object_runtime_layer(record)
		var animated := map_object_field_value(record, "obj_Data9") == "mapobjNextShape"
		var flashing := map_object_field_value(record, "obj_Data9") == "mapobjFlash"
		var additive := map_object_field_value(record, "obj_Mode").begins_with("engADDCOLOR")
		var glass := map_object_field_value(record, "obj_Mode").begins_with("engGLASS")
		var sprite: Sprite2D
		if animated:
			sprite = MapObjectAnimation.new()
		elif flashing:
			sprite = MapObjectFlash.new()
		else:
			sprite = Sprite2D.new()
		sprite.name = map_object_node_name(record)
		sprite.texture = texture
		sprite.centered = false
		sprite.position = top_left_world
		if animated:
			sprite.configure(animation_manifest, anchor_world)
		elif flashing:
			sprite.configure(top_left_world, additive)
		elif additive:
			var blend := CanvasItemMaterial.new()
			blend.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
			sprite.material = blend
		if map_object_field_value(record, "obj_Data9") == "mapobjShadow":
			# Source shadow token; the alpha is a remake presentation value.
			sprite.modulate = Color(1, 1, 1, 0.55)
		elif glass:
			# engGLASS (level-1 cloud shadows, opaque black silhouettes in the SHP):
			# read as a translucent overlay; the alpha is a remake presentation value.
			sprite.modulate = Color(1, 1, 1, 0.4)
		sprite.z_index = int(anchor_world.y)
		sprite.set_meta("record_index", record.get("record_index", -1))
		sprite.set_meta("shape_resource_id", shape_id)
		sprite.set_meta("candidate_anchor_world", candidate_anchor_world)
		sprite.set_meta("render_anchor_world", anchor_world)
		sprite.set_meta("process_code", str(record.get("process", "")))
		sprite.set_meta("runtime_layer", runtime_layer)
		_map_object_layer_node(runtime_layer).add_child(sprite)
		if runtime_layer == "backdrop":
			# mapobjMoveBG (level 2's 移動背景01): the picture shows through the map's
			# transparent sky, so it draws under the map backdrop.
			runtime.world_root.move_child(sprite, runtime.map_backdrop.get_index())
			sprite.z_index = runtime.map_backdrop.z_index
		# The "移動" of both kinds (original_map_object_drift.md): a cloud (雲影 included —
		# same template angle／speed, no link) drifts and wraps around the map every tick;
		# a moving background follows the camera by obj_Score/640, obj_HitPoint/480.
		var origin := Vector2i(anchor_world - top_left_world)
		match map_object_field_value(record, "obj_Data9"):
			"mapobjCloud":
				drift.add_cloud(sprite, anchor_world, MapObjectDrift.field_int(map_object_field_value(record, "obj_Data7")),
					MapObjectDrift.field_int(map_object_field_value(record, "obj_Data8")), Vector2i(texture.get_size()), origin)
			"mapobjMoveBG":
				drift.add_background(sprite, anchor_world, MapObjectDrift.field_int(map_object_field_value(record, "obj_Score")),
					MapObjectDrift.field_int(map_object_field_value(record, "obj_HitPoint")), origin)
		runtime.map_object_records.append({
			"record_index": int(record.get("record_index", -1)),
			"object_code": int(record.get("object_code", -1)),
			"object_name": str(record.get("object_name", "")),
			"shape_resource_id": shape_id,
			"shape_resource": str(record.get("shape_resource", "")),
			"preview_res_path": _map_object_preview_path(shape_id),
			"candidate_anchor_world": candidate_anchor_world,
			"render_anchor_world": anchor_world,
			"anchor_delta_from_candidate": placement.get("anchor_delta_from_candidate", anchor_world - candidate_anchor_world),
			"anchor_source": str(placement.get("anchor_source", "evef_candidate_xy_provisional")),
			"anchor_evidence_ids": placement.get("anchor_evidence_ids", []),
			"anchor_source_files": placement.get("anchor_source_files", []),
			"anchor_alignment_note": str(placement.get("anchor_alignment_note", "")),
			"matched_original_logical_bbox": placement.get("matched_original_logical_bbox", {}),
			"anchor_not_proven": placement.get("anchor_not_proven", []),
			"top_left_world": top_left_world,
			"texture_size": Vector2i(texture.get_width(), texture.get_height()),
			"object_plane": map_object_field_value(record, "obj_plane"),
			"process": str(record.get("process", "")),
			"runtime_layer": runtime_layer,
			"role_claim": _map_object_role_claim(record),
			"coordinate_interpretation": record.get("coordinate_interpretation", {}).duplicate(true),
			"provisional": true,
		})


## The runtime's one MapObjectDrift, emptied for a fresh placement. A child of the runtime,
## so it runs after the runtime's own _process has moved the camera this frame.
func _map_object_drift() -> MapObjectDrift:
	var drift: MapObjectDrift = runtime.get_node_or_null("MapObjectDrift")
	if drift == null:
		drift = MapObjectDrift.new()
		drift.name = "MapObjectDrift"
		runtime.add_child(drift)
	drift.clear()
	drift.map_size = runtime.map_config.world_size if runtime.map_config != null else Vector2i.ZERO
	drift.camera_top_left = func() -> Vector2: return runtime.camera_controller.logical_to_world(Vector2.ZERO) if runtime.camera_controller != null else Vector2.ZERO
	return drift


func _clear_map_object_layer(layer: Node2D) -> void:
	if layer == null:
		return
	for child in layer.get_children():
		layer.remove_child(child)
		child.free()


## EVEF background-sound objects (mapobjPlayBGSound; tools/hsl_level_map_objects.py
## exports them as role background_sound instead of drawing their I_RECT01 marker):
## the obj_Data2 WAV, decoded by tools/hsl_level_sounds.py into the scenario's
## script_sounds manifest, loops for the whole scene at a remake -8 dB. Placement
## position is not used (the original plays it map-wide as far as is known).
func _start_background_sounds() -> void:
	for record in runtime.background_sound_records:
		var node_path := str(record.get("node_path", ""))
		var player: Node = runtime.get_node_or_null(node_path) if node_path != "" else null
		if player != null:
			player.queue_free()
	runtime.background_sound_records.clear()
	var sounds: Dictionary = runtime.load_optional_json(BattleScenario.resource_path(runtime.first_battle_scenario, "script_sounds")).get("sounds", {})
	for item in runtime.map_objects_manifest.get("placements", []):
		if typeof(item) != TYPE_DICTIONARY or str((item as Dictionary).get("role", "")) != "background_sound":
			continue
		var record: Dictionary = item
		var resource_token := map_object_field_value(record, "obj_Data2")
		var row: Dictionary = sounds.get(resource_token, {})
		var res_path := str(row.get("res_path", ""))
		var entry := {"record_index": int(record.get("record_index", -1)), "object_name": str(record.get("object_name", "")), "resource": resource_token, "status": "not_imported_skipped", "node_path": ""}
		if res_path != "" and ResourceLoader.exists(res_path):
			var stream: AudioStream = load(res_path)
			if stream != null:
				var player := AudioStreamPlayer.new()
				player.name = "MapBackgroundSound_%d" % int(record.get("record_index", 0))
				player.stream = stream
				player.volume_db = -8.0
				runtime.add_child(player)
				player.finished.connect(player.play)
				player.play()
				entry["status"] = "looping"
				entry["node_path"] = str(runtime.get_path_to(player))
			else:
				entry["status"] = "load_failed_skipped"
		runtime.background_sound_records.append(entry)


func map_object_stand_records() -> Array:
	## Stand-object records to place: the manifest's plain placements plus the
	## children of combined placements (EVEF anchor + child offset already resolved
	## to candidate_x/candidate_y by tools/hsl_level_map_objects.py; e.g. level 1's
	## tree/house + shadow pairs). Children take the group's record_index and a
	## child index so node names stay unique (the first child stands on the EVEF point,
	## static-derived from the original installer 0x46bd67).
	var records: Array = []
	for item in runtime.map_objects_manifest.get("placements", []):
		if typeof(item) == TYPE_DICTIONARY and str((item as Dictionary).get("role", "")) in STAND_OBJECT_ROLES:
			records.append(item)
	for group_value in runtime.map_objects_manifest.get("combined_placements", []):
		if typeof(group_value) != TYPE_DICTIONARY:
			continue
		var group: Dictionary = group_value
		for child_value in group.get("children", []):
			if typeof(child_value) != TYPE_DICTIONARY:
				continue
			var child: Dictionary = (child_value as Dictionary).duplicate(true)
			child["role"] = "map_object"
			child["record_index"] = int(group.get("record_index", -1))
			child["combined_symbol"] = str(group.get("symbol", ""))
			records.append(child)
	return records


func _map_object_preview_path(shape_id: String) -> String:
	return "%s/%s.png" % [ContentPaths.MAP_OBJECT_PREVIEWS, shape_id]


func _map_object_runtime_layer(record: Dictionary) -> String:
	## The level manifest's hint (hsltools.levels.map_objects LAYER_HINTS plus the level
	## profile's layer_overrides) decides the layer; a manifest without hints falls back
	## to the obj_plane token.
	var hint := str(record.get("runtime_layer_hint", ""))
	if hint == "foreground" or hint == "back" or hint == "backdrop":
		return hint
	if map_object_field_value(record, "obj_plane") == "planeObject20":
		return "foreground"
	return "back"


func _map_object_layer_node(runtime_layer: String) -> Node2D:
	if runtime_layer == "backdrop":
		return runtime.world_root
	if runtime_layer == "back" and runtime.map_objects_back != null:
		return runtime.map_objects_back
	if runtime.map_objects_foreground != null:
		return runtime.map_objects_foreground
	return runtime.world_root


func _map_object_role_claim(record: Dictionary) -> String:
	var shape_id := str(record.get("shape_resource_id", ""))
	if shape_id == "tree07.SHP":
		return "visual_blocking_candidate"
	if shape_id == "FIRE01-01.SHP":
		return "animated_foreground_candidate"
	if shape_id == "bar004a.SHP" or shape_id == "bar004b.SHP":
		return "runtime_measured_bridge_overlay_candidate"
	return "stand_object_visual_candidate"


func map_object_field_value(record: Dictionary, field_name: String) -> String:
	var fields: Dictionary = record.get("object_fields", {})
	var field: Dictionary = fields.get(field_name, {})
	return str(field.get("value", ""))


func map_object_node_name(record: Dictionary) -> String:
	var name := "MapObject_%02d_%s" % [
		int(record.get("record_index", 0)),
		_map_object_safe_suffix(str(record.get("shape_resource_id", "unknown"))),
	]
	if record.has("child_index"):
		name += "_c%d" % int(record.get("child_index", 0))
	return name


func _map_object_safe_suffix(value: String) -> String:
	return value.replace(".", "_").replace("-", "_").replace("/", "_").replace("\\", "_")
