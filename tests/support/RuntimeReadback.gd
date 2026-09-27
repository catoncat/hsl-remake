extends RefCounted

## Read-only test/capture face of BattleSceneRuntime: the `*_summary` contracts and their
## helpers, as static functions over a booted runtime. Reads runtime, PlayLoop and node
## state; owns and mutates nothing. Lives under tests/support so the product exposes no
## player-invisible summary surface (AGENTS: no long-lived test-only surface in game/).

const BattlePlayLoop = preload("res://game/sim/loop/BattlePlayLoop.gd")
const Interaction = preload("res://game/sim/Interaction.gd")


static func runtime_contract_summary(runtime: Node) -> Dictionary:
	var world_size := Vector2i.ZERO
	var viewport_size: Vector2i = runtime.logical_viewport_size
	if runtime.map_config != null:
		world_size = runtime.map_config.world_size
		viewport_size = runtime.map_config.logical_viewport_size
	var map_object_contract := map_object_summary(runtime)
	return {
		"schema": "hsl_first_scene_runtime.v1",
		"scenario_schema": str(runtime.first_battle_scenario.get("schema", "")),
		"scenario_path": str(runtime.first_battle_scenario.get("path", runtime.scenario_path)),
		"conditional_party": runtime.conditional_party_receipt,
		"startup_mode": runtime.startup_mode,
		"runtime_entrypoint": runtime.runtime_entrypoint,
		"product_main_path_state": "opening_timeline" if runtime.runtime_entrypoint == runtime.ENTRYPOINT_PRODUCT_OPENING else "dev_harness",
		"map_texture_path": runtime.map_texture_path,
		"map_world_size": world_size,
		"logical_viewport_size": viewport_size,
		"camera_node": runtime.camera.name if runtime.camera != null else "",
		"camera_position": runtime.camera.position if runtime.camera != null else Vector2.ZERO,
		"grid_projection_evidence_id": str(runtime.map_config.grid_projection.get("evidence_id", "")) if runtime.map_config != null else "",
		"actor_walk_manifest_schema": runtime.actor_walk_manifest.get("schema", ""),
		"actor_walk_manifest_actor_count": runtime.actor_walk_manifest.get("actors", {}).size(),
		"shared_actor_walk_manifest_actor_count": runtime.shared_actor_walk_manifest.get("actors", {}).size(),
		"actor_runtime_count": runtime.actors_root.get_child_count() if runtime.actors_root != null else 0,
		"actor_unit_ids": _actor_unit_ids(runtime),
		"actor_frame_source_statuses": _actor_frame_source_statuses(runtime),
		"actor_frame_actor_ids": _actor_frame_actor_ids(runtime),
		"map_object_manifest_schema": map_object_contract.get("manifest_schema", ""),
		"map_object_alignment_manifest_schema": map_object_contract.get("alignment_manifest_schema", ""),
		"map_object_source_count": map_object_contract.get("source_map_object_count", 0),
		"map_object_spawn_count": map_object_contract.get("spawned_count", 0),
		"map_object_foreground_count": map_object_contract.get("foreground_count", 0),
		"map_object_visual_blocking_candidate_count": map_object_contract.get("visual_blocking_candidate_count", 0),
		"map_object_bridge_runtime_aligned_count": map_object_contract.get("bridge_runtime_aligned_count", 0),
		"map_object_layer_policy": map_object_contract.get("layer_policy", ""),
		"map_object_coordinate_claim": map_object_contract.get("coordinate_claim", ""),
		"unit_grid_coords": runtime.unit_grid_coords.duplicate(true),
		"unit_position_source_status": "native_level_placement_npc_opening_moves_unresolved",
		"scene_timeline_schema": runtime.scene_timeline.summary().get("schema", "") if runtime.scene_timeline != null else "",
		"scene_timeline_current_event_id": runtime.scene_timeline.summary().get("current_event_id", "") if runtime.scene_timeline != null else "",
		"scene_timeline_event_count": runtime.scene_timeline.summary().get("event_count", 0) if runtime.scene_timeline != null else 0,
		"opening_timeline_manifest_schema": runtime.opening_timeline_manifest.get("schema", ""),
		"opening_timeline_event_count": runtime.opening_timeline_manifest.get("event_count", 0),
		"opening_timeline_mode": runtime.opening_timeline_mode,
		"message_text_evidence_schema": runtime.message_text_evidence.get("schema", ""),
		"message_text_status": runtime.message_text_evidence.get("message_text_status", ""),
		"leonard_frame_source_status": _actor_summary(runtime, "ActorRuntimeLeonard").get("frame_source_status", ""),
		"leonard_animation_frame_count": _actor_summary(runtime, "ActorRuntimeLeonard").get("animation_frame_count", 0),
		"battle_state_owner": "BattlePlayLoop",
		"provisional": true,
	}


static func map_object_summary(runtime: Node) -> Dictionary:
	var shape_counts := {}
	var layer_counts := {"back": 0, "foreground": 0, "backdrop": 0}
	var visual_blocking_candidates: Array[String] = []
	var bridge_overlay_candidates: Array[String] = []
	var bridge_runtime_aligned_candidates: Array[String] = []
	for record in runtime.map_object_records:
		var shape_id := str(record.get("shape_resource_id", ""))
		shape_counts[shape_id] = int(shape_counts.get(shape_id, 0)) + 1
		var layer := str(record.get("runtime_layer", ""))
		layer_counts[layer] = int(layer_counts.get(layer, 0)) + 1
		if str(record.get("role_claim", "")) == "visual_blocking_candidate":
			visual_blocking_candidates.append("%s:%s" % [str(record.get("record_index", "")), shape_id])
		if str(record.get("role_claim", "")).contains("bridge_overlay_candidate"):
			bridge_overlay_candidates.append("%s:%s" % [str(record.get("record_index", "")), shape_id])
		if shape_id in ["bar004a.SHP", "bar004b.SHP"] and str(record.get("anchor_source", "")) == "evef_shp_draw_origin":
			bridge_runtime_aligned_candidates.append("%s:%s" % [str(record.get("record_index", "")), shape_id])
	return {
		"schema": "hsl_first_scene_map_objects_runtime.v1",
		"manifest_path": runtime.map_objects_path,
		"manifest_schema": runtime.map_objects_manifest.get("schema", ""),
		"alignment_manifest_path": runtime.map_object_alignment_path,
		"alignment_manifest_schema": runtime.map_object_alignment_manifest.get("schema", ""),
		"placement_resolver_schema": runtime.map_object_placement.summary().get("schema", "") if runtime.map_object_placement != null else "",
		"shape_preview_root": preload("res://game/sim/ContentPaths.gd").MAP_OBJECT_PREVIEWS,
		"source_map_object_count": _map_object_source_count(runtime),
		"spawned_count": runtime.map_object_records.size(),
		"background_sound_records": runtime.background_sound_records.duplicate(true),
		"foreground_count": int(layer_counts.get("foreground", 0)),
		"back_count": int(layer_counts.get("back", 0)),
		"backdrop_count": int(layer_counts.get("backdrop", 0)),
		"shape_counts": shape_counts,
		"records": runtime.map_object_records.duplicate(true),
		"visual_blocking_candidate_count": visual_blocking_candidates.size(),
		"visual_blocking_candidates": visual_blocking_candidates,
		"bridge_overlay_candidates": bridge_overlay_candidates,
		"bridge_runtime_aligned_count": bridge_runtime_aligned_candidates.size(),
		"bridge_runtime_aligned_candidates": bridge_runtime_aligned_candidates,
		"bridge_alignment_evidence_ids": ["p1_route_upper_formation_11", "p1_route_upper_formation_12"],
		"coordinate_claim": "EVEF candidate_x/candidate_y stays recorded; stand objects use native SHP draw origins; bridge positions match curated measurements",
		"anchor_claim": "stand-object render_anchor_world is the unchanged EVEF position; texture top-left subtracts native SHP origin",
		"layer_policy": "remake_notes:map_object_layer_policy",
		"evidence_tier": "mixed-resource-derived-runtime-measured",
		"provisional": true,
		"not_proven": [
			"exact original stand-object anchor",
			"exact original planeObject draw order",
			"exact original clipping/crop interaction",
			"tree07 gameplay blocking/cost semantics",
			"complete stand-object placement transform",
			"bridge/fire animation frame timing",
		],
	}


static func interaction_summary(runtime: Node) -> Dictionary:
	var loop_summary: Dictionary = BattlePlayLoop.summary(runtime.play_loop) if not runtime.play_loop.is_empty() else {}
	return {
		"schema": "hsl_first_scene_interaction.v1",
		"interaction_state": runtime.interaction_state,
		"conditional_party": runtime.conditional_party_receipt,
		"selected_unit_id": runtime.selected_unit_id,
		"selected_grid_coord": runtime.unit_grid_coord(runtime.selected_unit_id),
		"action_menu_visible": runtime.action_menu.visible if runtime.action_menu != null else false,
		"action_menu_command_count": runtime.action_menu.get_child_count() if runtime.action_menu != null else 0,
		"move_overlay_visible": runtime.move_overlay.visible if runtime.move_overlay != null else false,
		"move_overlay_cell_count": runtime.move_overlay.get_child_count() if runtime.move_overlay != null else 0,
		"move_overlay_provisional": false,
		"move_overlay_move_point": move_point_for_selected_unit(runtime),
		"move_overlay_generation_status": "wrd_bfs_core_turn_queue",
		"menu_evidence_id": "bcmd_core_turn_queue" if runtime.action_menu != null and runtime.action_menu.visible else "",
		"move_overlay_evidence_id": str(runtime.map_config.grid_projection.get("evidence_id", "")) if runtime.map_config != null and runtime.move_overlay != null and runtime.move_overlay.visible else "",
		"cancel_evidence_id": runtime.cancel_evidence_id,
		"pending_move_revert": runtime.pending_move_revert,
		"pending_move_original_grid": runtime.pending_move_original_grid,
		"last_move_frame_source_status": runtime.last_move_result.get("frame_source_status", ""),
		"last_move_duration_seconds": runtime.last_move_result.get("duration_seconds", 0.0),
		"last_move_uses_frame_sequence": runtime.last_move_result.get("uses_frame_sequence", false),
		"last_move_animation_frame_count": runtime.last_move_result.get("animation_frame_count", 0),
		"last_move_frame_advance_steps": runtime.last_move_result.get("frame_advance_steps", 0),
		"attack_overlay_cell_count": runtime.attack_overlay_cells.size(),
		"last_attack": runtime.last_attack_result,
		"last_attack_reject": runtime.last_attack_reject,
		"ai_playback_active": runtime.ai_playback_active,
		"play_loop": loop_summary,
		"loop_write_reason": runtime.loop_write_reason,
		"mechanics_priority": "playable_over_visual_parity",
		"evidence_tier": "static-derived",
		"unresolved_semantics": [
			"exact original click hitbox",
			"exact original menu icon placement",
			"exact original cancel input timing",
			"AI action/target selection full parity",
		],
	}


static func opening_timeline_summary(runtime: Node) -> Dictionary:
	var timeline_summary: Dictionary = runtime.scene_timeline.summary() if runtime.scene_timeline != null else {}
	var contract: Dictionary = runtime.opening_timeline_manifest.get("contract", {})
	return {
		"schema": "hsl_first_scene_opening_runtime.v1",
		"manifest_path": runtime.opening_timeline_path,
		"manifest_schema": runtime.opening_timeline_manifest.get("schema", ""),
		"manifest_evidence_tier": runtime.opening_timeline_manifest.get("evidence_tier", ""),
		"mode": runtime.opening_timeline_mode,
		"event_count": timeline_summary.get("event_count", 0),
		"current_index": timeline_summary.get("current_index", 0),
		"current_event_id": timeline_summary.get("current_event_id", ""),
		"current_event_kind": timeline_summary.get("current_event_kind", ""),
		"current_event_display_line": timeline_summary.get("current_event_display_line", ""),
		"current_event_source_token": timeline_summary.get("current_event_source_token", ""),
		"current_event_message_id": timeline_summary.get("current_event_message_id", ""),
		"current_event_actor_token": timeline_summary.get("current_event_actor_token", ""),
		"current_event_presentation_status": timeline_summary.get("current_event_presentation_status", ""),
		"contract_not_proven": contract.get("not_proven", []),
		"first_control_playable": runtime.interaction_state != Interaction.OPENING_TIMELINE,
		"provisional": true,
	}


static func input_summary(runtime: Node) -> Dictionary:
	return {
		"schema": "hsl_first_scene_input_hit_test.v1",
		"pointer_logical_position": runtime.pointer_logical_position,
		"pointer_world_position": runtime.pointer_world_position,
		"hovered_grid_cell": runtime.hovered_grid_cell,
		"hovered_unit_id": runtime.hovered_unit_id,
		"hovered_command_id": runtime.hovered_command_id,
		"held_command_id": runtime.held_command_id,
		"grid_projection_evidence_id": str(runtime.map_config.grid_projection.get("evidence_id", "")) if runtime.map_config != null else "",
		"evidence_tier": "runtime-measured",
		"provisional": true,
		"unresolved_semantics": [
			"exact original actor clickable rect",
			"exact original command release behavior",
			"exact original camera settle timing",
		],
	}


static func play_loop_summary(runtime: Node) -> Dictionary:
	return BattlePlayLoop.summary(runtime.play_loop) if not runtime.play_loop.is_empty() else {}


static func _actor_unit_ids(runtime: Node) -> Array[String]:
	var unit_ids: Array[String] = []
	if runtime.actors_root == null:
		return unit_ids
	for child in runtime.actors_root.get_children():
		if child.has_method("runtime_summary"):
			var summary: Dictionary = child.call("runtime_summary")
			unit_ids.append(str(summary.get("unit_id", "")))
	return unit_ids


static func _actor_frame_source_statuses(runtime: Node) -> Dictionary:
	var statuses := {}
	if runtime.actors_root == null:
		return statuses
	for child in runtime.actors_root.get_children():
		if child.has_method("runtime_summary"):
			var summary: Dictionary = child.call("runtime_summary")
			statuses[str(summary.get("unit_id", ""))] = str(summary.get("frame_source_status", ""))
	return statuses


## unit_id -> PLAYERS row whose walk frames the node currently shows (ActorRuntime.actor_id).
static func _actor_frame_actor_ids(runtime: Node) -> Dictionary:
	var rows := {}
	if runtime.actors_root == null:
		return rows
	for child in runtime.actors_root.get_children():
		if child.has_method("runtime_summary"):
			var summary: Dictionary = child.call("runtime_summary")
			rows[str(summary.get("unit_id", ""))] = str(summary.get("actor_id", ""))
	return rows


static func _map_object_source_count(runtime: Node) -> int:
	return runtime.stage.map_object_stand_records().size()


## Move budget the overlay reports for the selected unit (the scenario's player unit
## while nothing is selected); readback-only, not a rule input.
static func move_point_for_selected_unit(runtime: Node) -> int:
	var unit_id: String = runtime.selected_unit_id
	if unit_id == "":
		unit_id = str(runtime.first_battle_scenario.get("player_unit_id", ""))
	if runtime.play_loop.is_empty():
		return 0
	var unit: Dictionary = BattlePlayLoop.unit(runtime.play_loop, unit_id)
	return int(unit.get("move_point", 0))


static func _actor_summary(runtime: Node, node_name: String) -> Dictionary:
	if runtime.actors_root == null:
		return {}
	var actor: Node = runtime.actors_root.get_node_or_null(node_name)
	if actor != null and actor.has_method("runtime_summary"):
		return actor.call("runtime_summary")
	return {}


## ---------------------------------------------------------------------------
## Node reads the suites and captures ask of scene children (no product path asks them).

## The loot／treasure panel's first empty bag slot of the unit on show, or -1.
static func first_empty_slot(panel: Node) -> int:
	var actor: Dictionary = panel._actor()
	if actor.is_empty(): return -1
	for index in range(actor["inventory"].size()):
		if int(actor["inventory"][index]) == 0: return index # JSON-origin bags hold 0.0
	return -1


## The highlight an ActorRuntime shows: "", "actor", "target" or "speaker".
static func highlight_kind(actor: Node) -> String:
	return actor._highlight_kind


## The dialogue board's rows in view on the current page (the name row as its label text).
static func window_rows(dialogue: Node) -> PackedStringArray:
	var rows := PackedStringArray()
	if dialogue._name_row:
		rows.append(dialogue.speaker_label.text)
	rows.append_array(dialogue.body_label.text.split("\n"))
	return rows.slice(dialogue.top_row, dialogue.top_row + dialogue.WINDOW_ROWS)


## What a cut-in's result shows: the numbers' texts (spawn order, " · "), then the caption line.
static func result_text(cutin: Node) -> String:
	var numbers: Array[String] = []
	if cutin.result_number.visible:
		for number in cutin.result_number.get_children():
			if number.showing(): numbers.append(number.text)
	var lines: Array[String] = []
	if not numbers.is_empty(): lines.append(" · ".join(numbers))
	if cutin.result.visible and cutin.result.text != "": lines.append(cutin.result.text)
	return "\n".join(lines)


## A logical (640×480) point in viewport pixels under the runtime's camera (input events).
static func logical_to_viewport_position(runtime: Node, logical_position: Vector2) -> Vector2:
	var camera: Object = runtime.camera_controller
	if camera == null:
		return logical_position
	var viewport_size: Vector2 = runtime.get_viewport_rect().size
	if viewport_size.x <= 0.0 or viewport_size.y <= 0.0:
		return logical_position
	return Vector2(
		logical_position.x * viewport_size.x / float(camera.logical_viewport_size.x),
		logical_position.y * viewport_size.y / float(camera.logical_viewport_size.y)
	)


## The logical centre of a command button (a click point), or ZERO when it is not laid out.
static func command_center_logical_position(scene_input: Object, command_id: String) -> Vector2:
	var rect := command_logical_rect(scene_input, command_id)
	if rect.size == Vector2.ZERO:
		return Vector2.ZERO
	return rect.position + rect.size * 0.5


## A command button's rect in logical pixels, or an empty rect when the menu lacks it.
static func command_logical_rect(scene_input: Object, command_id: String) -> Rect2:
	var runtime: Node = scene_input.runtime
	if runtime.action_menu == null:
		return Rect2()
	for child in runtime.action_menu.get_children():
		if child is Control and scene_input.command_id_for_control(child) == command_id:
			return Rect2(runtime.action_menu.position + child.position, child.size)
	return Rect2()

static func save_notice_visible(menu: Node) -> bool:
	return menu._save_notice != null and menu._save_notice.visible


## The shade a closing panel leaves in its place (null when none is fading).
static func shade_ghost(motion: Object) -> ColorRect:
	return motion._shade_ghost
