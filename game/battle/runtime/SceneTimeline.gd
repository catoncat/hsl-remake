extends RefCounted
## provenance:
##   rules: resource-derived content/imported/hsl/chapter01/source_texts/STORY051.TXT; static-derived docs/evidence_packets/static_reverse/original_select_insert_event.md
##   layout: n/a
##   strings: n/a
##   timing: n/a
##   audio: n/a

const SUMMARY_SCHEMA := "hsl_scene_timeline.v1"
const TRANSITION_SCHEMA := "hsl_scene_timeline_transition.v1"

var events: Array[Dictionary] = []
var current_index: int = 0


static func from_events(source_events: Array, start_event_id: String = "") -> RefCounted:
	var timeline := new()
	for item in source_events:
		if typeof(item) == TYPE_DICTIONARY:
			timeline.events.append(item.duplicate(true))
	if start_event_id != "":
		timeline.seek_to_event_id(start_event_id)
	return timeline


func current_event() -> Dictionary:
	if current_index < 0 or current_index >= events.size():
		return {}
	return events[current_index].duplicate(true)


func advance(trigger: String = "") -> Dictionary:
	if is_finished():
		return {
			"schema": TRANSITION_SCHEMA,
			"trigger": trigger,
			"from_index": current_index,
			"to_index": current_index,
			"from_event_id": "",
			"to_event_id": "",
			"finished": true,
		}
	var from_event := current_event()
	var from_event_id := str(from_event.get("id", ""))
	current_index += 1
	var to_event := current_event()
	return {
		"schema": TRANSITION_SCHEMA,
		"trigger": trigger,
		"from_index": current_index - 1,
		"to_index": current_index,
		"from_event_id": from_event_id,
		"to_event_id": str(to_event.get("id", "")),
		"finished": is_finished(),
	}


func reset() -> void:
	current_index = 0


## Splices events right after the current one (a chosen actSelectInsertEvent branch:
## the winfail event chain the choice inserts); returns how many were inserted.
func insert_after_current(source_events: Array) -> int:
	var inserted: Array[Dictionary] = []
	for item in source_events:
		if typeof(item) == TYPE_DICTIONARY:
			inserted.append((item as Dictionary).duplicate(true))
	if inserted.is_empty():
		return 0
	var at := mini(current_index + 1, events.size())
	var merged: Array[Dictionary] = []
	merged.append_array(events.slice(0, at))
	merged.append_array(inserted)
	merged.append_array(events.slice(at))
	events = merged
	return inserted.size()


func seek_to_event_id(event_id: String) -> bool:
	for index in range(events.size()):
		if str(events[index].get("id", "")) == event_id:
			current_index = index
			return true
	return false


func is_finished() -> bool:
	return current_index >= events.size()


func summary() -> Dictionary:
	var event := current_event()
	return {
		"schema": SUMMARY_SCHEMA,
		"event_count": events.size(),
		"current_index": current_index,
		"current_event_id": str(event.get("id", "")),
		"current_event_kind": str(event.get("kind", "")),
		"current_event_display_line": str(event.get("display_line", "")),
		"current_event_source_token": str(event.get("source_token", "")),
		"current_event_message_id": str(event.get("message_id", "")),
		"current_event_actor_token": str(event.get("actor_token", "")),
		"current_event_presentation_status": str(event.get("presentation_status", "")),
		"finished": is_finished(),
	}
