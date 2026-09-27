extends RefCounted
## provenance:
##   layout: resource-derived content/imported/hsl/chapter01/map_object_alignment.json
##   layout: static-derived docs/evidence_packets/static_reverse/actor_shp_draw_origin.md
##   layout: runtime-measured docs/evidence_packets/runtime_observations/first_battle_visual_evidence_index.md
##     (historical bridge calibration kept as comparison metadata only)

var alignment_manifest: Dictionary = {}
var calibration_by_record_index: Dictionary = {}


static func from_alignment_manifest(manifest: Dictionary) -> RefCounted:
	var resolver := new()
	resolver.alignment_manifest = manifest.duplicate(true)
	resolver._index_calibrations()
	return resolver


func summary() -> Dictionary:
	return {
		"schema": "hsl_map_object_placement_runtime.v1",
		"alignment_manifest_schema": alignment_manifest.get("schema", ""),
		"alignment_manifest_path": alignment_manifest.get("path", ""),
		"calibration_count": calibration_by_record_index.size(),
		"placement_policy": alignment_manifest.get("placement_policy", ""),
		"source_policy": alignment_manifest.get("source_policy", ""),
	}


func resolve(record: Dictionary) -> Dictionary:
	var candidate_anchor := Vector2(float(record.get("candidate_x", 0)), float(record.get("candidate_y", 0)))
	var calibration := _calibration_for_record(record)
	var shape: Dictionary = alignment_manifest.get("shapes", {}).get(str(record.get("shape_resource_id", "")), {})
	var origin: Array = shape.get("draw_origin", [])
	if origin.size() != 2:
		push_error("Missing native SHP draw origin: %s" % record.get("shape_resource_id", ""))
		return {}
	var render_anchor := candidate_anchor
	var top_left_world := candidate_anchor - Vector2(float(origin[0]), float(origin[1]))
	# Historical bridge measurements remain comparison metadata, never position overrides.
	var anchor_source := "evef_shp_draw_origin"
	var anchor_evidence_ids: Array = calibration.get("anchor_evidence_ids", [])
	var anchor_source_files: Array = calibration.get("anchor_source_files", [])
	var anchor_alignment_note := "Native EVEF position minus SHP draw origin"
	var matched_original_logical_bbox: Dictionary = calibration.get("matched_original_logical_bbox", {})
	var not_proven: Array = alignment_manifest.get("not_proven", [])
	return {
		"candidate_anchor_world": candidate_anchor,
		"render_anchor_world": render_anchor,
		"anchor_delta_from_candidate": render_anchor - candidate_anchor,
		"top_left_world": top_left_world,
		"anchor_source": anchor_source,
		"anchor_evidence_ids": anchor_evidence_ids,
		"anchor_source_files": anchor_source_files,
		"anchor_alignment_note": anchor_alignment_note,
		"matched_original_logical_bbox": matched_original_logical_bbox,
		"anchor_not_proven": not_proven,
	}


func _index_calibrations() -> void:
	calibration_by_record_index.clear()
	for item in alignment_manifest.get("calibrations", []):
		if typeof(item) != TYPE_DICTIONARY:
			continue
		var calibration: Dictionary = item
		calibration_by_record_index[int(calibration.get("record_index", -1))] = calibration


func _calibration_for_record(record: Dictionary) -> Dictionary:
	var record_index := int(record.get("record_index", -1))
	var calibration: Dictionary = calibration_by_record_index.get(record_index, {})
	if calibration.is_empty():
		return {}
	if str(calibration.get("shape_resource_id", "")) != str(record.get("shape_resource_id", "")):
		return {}
	return calibration
