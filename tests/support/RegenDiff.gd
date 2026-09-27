extends RefCounted

## Field-level report and verdict for a regen-and-compare suite: tests/run_autoplay_sweep_tests.gd
## rewrites content/generated/hsl/development/autoplay/results.json and compares the rewrite with
## the tracked file. regen_verdict is the sweep's judgement: an entry of the collection (`levels`)
## whose verdict fields changed (the outcome win／fail／dead_end and the dead_end reason), or that
## only one side has, is a failure; any other difference — rounds, action counts, the other row
## fields, header paths, formatting — is drift, reported and never failed. regen_failure is the
## byte-identity report underneath (every difference named, "" exactly when the texts are equal).
## Both name the entries of one collection with a changed field, the header paths outside it, and
## one `path: old -> new` line per differing leaf.
##
## Both sides are compared as parsed JSON, and numbers compare by value, never by Variant type.
## JSON.parse_string turns every number into a float, while the sweep builds its rows with
## ints; Godot's Dictionary equality is type-strict (Variant::hash_compare: {"rounds": 2} !=
## {"rounds": 2.0}), so the comparator this replaced — `tracked_level != rebuilt_level` — named
## every level holding an int field (all of them: rounds, round, actions) whenever any byte
## of the file changed.

const ABSENT := "<absent>"
## Field lines per failure message; the changed-entry list itself is always complete.
const MAX_FIELD_LINES := 200
## results.json row fields whose change fails the sweep: the outcome (win／fail／dead_end) and
## the dead_end reason ("" on every win／fail row). Rounds, action counts and the other fields
## are drift.
const SWEEP_VERDICT_FIELDS := ["outcome", "reason"]


## The failure message for `path` when `rewritten` differs from `tracked`, "" when the texts
## are byte-identical. Names the `collection` entries whose fields changed (added or removed
## entries included) in the rewrite's order then the removed ones, the header paths outside
## the collection, and one `  <path>: <old> -> <new>` line per differing leaf (`<absent>` for
## a side that lacks it). A rewrite equal field for field (formatting or key order only) says
## so; a tracked text that is not a JSON object gets no field list.
static func regen_failure(path: String, tracked: String, rewritten: String, collection: String) -> String:
	if tracked == rewritten:
		return ""
	var previous: Variant = _parse(tracked)
	var current: Variant = _parse(rewritten)
	if not (previous is Dictionary and current is Dictionary):
		return "%s rewritten and differs from the tracked file (the tracked file is missing or not a JSON object, no field list): review and commit the rewrite" % path
	var report := entry_differences(previous, current, collection)
	var head := "%s rewritten and differs from the tracked file (%s changed=%s; header changed=%s): review and commit the rewrite" % [path, collection, str(report["changed"]), str(report["header"])]
	var lines: Array[String] = [head]
	var fields: Array = report["fields"]
	lines.append_array(field_lines(fields))
	if fields.is_empty():
		lines.append("  no field differs: the rewrite changes only formatting or key order")
	return "\n".join(lines)


## Differences between two parsed documents split by `collection`: {"changed": [entry keys
## with a differing field], "header": [paths outside the collection], "fields": [every
## differing leaf, the collection's entries first], "entries": {changed key: [its differing
## leaves]}, "header_fields": [the differing leaves outside the collection]}. When either side's
## collection is not a Dictionary the whole document is header.
static func entry_differences(previous: Dictionary, current: Dictionary, collection: String) -> Dictionary:
	var changed: Array[String] = []
	var fields: Array[Dictionary] = []
	var entries := {}
	var old_entries: Variant = previous.get(collection)
	var new_entries: Variant = current.get(collection)
	var header_old := previous
	var header_new := current
	if old_entries is Dictionary and new_entries is Dictionary:
		var keys: Array = (new_entries as Dictionary).keys()
		for key in old_entries:
			if not (new_entries as Dictionary).has(key):
				keys.append(key)
		for key in keys:
			var before := fields.size()
			_collect(old_entries.get(key), old_entries.has(key), new_entries.get(key), new_entries.has(key), "%s/%s" % [collection, str(key)], fields)
			if fields.size() > before:
				changed.append(str(key))
				entries[str(key)] = fields.slice(before)
		header_old = previous.duplicate()
		header_new = current.duplicate()
		header_old.erase(collection)
		header_new.erase(collection)
	var header: Array[String] = []
	var header_fields := differences(header_old, header_new)
	for entry in header_fields:
		header.append(str(entry["path"]))
	fields.append_array(header_fields)
	return {"changed": changed, "header": header, "fields": fields, "entries": entries, "header_fields": header_fields}


## The sweep's judgement of a rewrite (tests/run_autoplay_sweep_tests.gd): {"identical": bool,
## "changed": [collection keys with a verdict change], "drifted": [keys with only other fields
## changed], "header": [header paths], "failure": String, "drift": String}. An entry whose field
## named in `verdict_fields` differs — or that only one side has (added or removed) — is a verdict
## change; `failure` then names those entries with every differing leaf of theirs. Every other
## difference is drift: `drift` is "<collection>=[keys] header=[paths] fields=N" followed by one
## line per differing leaf of the drifted entries and the header, or by a note that no field
## differs (a formatting-only rewrite). A byte-identical rewrite leaves both ""; a tracked text
## that is not a JSON object is a failure (no verdict to compare against). Field lines stop at
## MAX_FIELD_LINES per message.
static func regen_verdict(path: String, tracked: String, rewritten: String, collection: String, verdict_fields: Array) -> Dictionary:
	var verdict := {"identical": tracked == rewritten, "changed": [], "drifted": [], "header": [], "failure": "", "drift": ""}
	if tracked == rewritten:
		return verdict
	var previous: Variant = _parse(tracked)
	var current: Variant = _parse(rewritten)
	if not (previous is Dictionary and current is Dictionary):
		verdict["failure"] = "%s rewritten and the tracked file is missing or not a JSON object, so no %s verdict can be compared: review and commit the rewrite" % [path, collection]
		return verdict
	var report := entry_differences(previous, current, collection)
	var changed: Array[String] = []
	var drifted: Array[String] = []
	var changed_leaves: Array = []
	var drift_leaves: Array = []
	for key in report["changed"]:
		var leaves: Array = report["entries"][key]
		if _touches_verdict(leaves, "%s/%s" % [collection, key], verdict_fields):
			changed.append(key)
			changed_leaves.append_array(leaves)
		else:
			drifted.append(key)
			drift_leaves.append_array(leaves)
	drift_leaves.append_array(report["header_fields"])
	verdict["changed"] = changed
	verdict["drifted"] = drifted
	verdict["header"] = report["header"]
	if not changed.is_empty():
		var failure: Array[String] = ["%s rewritten with a changed verdict (%s changed=%s; verdict fields %s, or an entry added or removed): review the rewrite, commit it and name the changes in the commit message" % [path, collection, str(changed), "/".join(PackedStringArray(verdict_fields))]]
		failure.append_array(field_lines(changed_leaves))
		verdict["failure"] = "\n".join(failure)
	if not drift_leaves.is_empty() or changed.is_empty():
		var drift: Array[String] = ["%s=%s header=%s fields=%d" % [collection, str(drifted), str(report["header"]), drift_leaves.size()]]
		drift.append_array(field_lines(drift_leaves))
		if drift_leaves.is_empty():
			drift.append("  no field differs: the rewrite changes only formatting or key order")
		verdict["drift"] = "\n".join(drift)
	return verdict


## Whether `leaves` (the differing leaves of the entry at `entry_path`) hold a verdict change:
## the entry itself added or removed, or a leaf under one of `verdict_fields`.
static func _touches_verdict(leaves: Array, entry_path: String, verdict_fields: Array) -> bool:
	for leaf in leaves:
		var leaf_path := str(leaf["path"])
		if leaf_path == entry_path or leaf_path.trim_prefix(entry_path + "/").get_slice("/", 0) in verdict_fields:
			return true
	return false


## One `  <path>: <old> -> <new>` line per leaf, capped at MAX_FIELD_LINES with a count of the rest.
static func field_lines(leaves: Array) -> Array[String]:
	var lines: Array[String] = []
	for entry in leaves.slice(0, MAX_FIELD_LINES):
		lines.append("  %s: %s -> %s" % [str(entry["path"]), render(entry, "old"), render(entry, "new")])
	if leaves.size() > MAX_FIELD_LINES:
		lines.append("  ... %d more field differences (git diff the file for the rest)" % (leaves.size() - MAX_FIELD_LINES))
	return lines


## The parsed text when it is a JSON object, else {} (the chapter suite reads the tracked
## chapter.json and known_dead_ends.json with it).
static func parse_object(text: String) -> Dictionary:
	var parsed: Variant = _parse(text)
	return parsed if parsed is Dictionary else {}


## A chapter.json document's headline — what tests/run_chapter_autoplay_tests.gd prints against
## the tracked file instead of comparing files: game_clear, the stuck and budget-cut battle levels
## ("none" when empty), battles fought／won and retries. {} for an empty document (a tracked file
## that is missing or not an object), so every field then differs from `<absent>`.
static func chapter_headline(document: Dictionary) -> Dictionary:
	if document.is_empty():
		return {}
	return {"game_clear": document.get("game_clear"), "stuck_at": _level_or_none(document.get("stuck_at")), "budget_exhausted_at": _level_or_none(document.get("budget_exhausted")),
		"battles_fought": document.get("battles_fought"), "battles_won": document.get("battles_won"), "retries": document.get("retries")}


static func _level_or_none(row: Variant) -> Variant:
	return (row as Dictionary).get("level", "none") if row is Dictionary and not (row as Dictionary).is_empty() else "none"


## Every leaf where `old` and `new` differ, in `new`'s key order then the keys only `old` has:
## {"path": "levels/6/rounds", "old": 2.0, "new": 3.0}. A key or index only one side has is one
## entry holding that side's whole value (the other side has no "old"／"new" entry).
## Dictionaries recurse by key, arrays by index; numbers compare by value.
static func differences(old: Variant, new: Variant, path: String = "") -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	_collect(old, true, new, true, path, found)
	return found


## Numbers (int or float) equal by value; anything else needs the same Variant type and ==.
static func same_value(a: Variant, b: Variant) -> bool:
	if (a is int or a is float) and (b is int or b is float):
		return float(a) == float(b)
	return typeof(a) == typeof(b) and a == b


## `entry[side]` as compact JSON with integral floats printed as ints ("2", not "2.0" — the
## tracked file's own spelling), or `<absent>`.
static func render(entry: Dictionary, side: String) -> String:
	return JSON.stringify(plain(entry[side])) if entry.has(side) else ABSENT


static func _collect(old: Variant, has_old: bool, new: Variant, has_new: bool, path: String, found: Array[Dictionary]) -> void:
	if has_old and has_new and old is Dictionary and new is Dictionary:
		for key in new:
			_collect(old.get(key), old.has(key), new[key], true, _join(path, key), found)
		for key in old:
			if not new.has(key):
				_collect(old[key], true, null, false, _join(path, key), found)
		return
	if has_old and has_new and old is Array and new is Array:
		for index in range(maxi(old.size(), new.size())):
			_collect(old[index] if index < old.size() else null, index < old.size(), new[index] if index < new.size() else null, index < new.size(), _join(path, index), found)
		return
	if has_old and has_new and same_value(old, new):
		return
	var entry := {"path": path}
	if has_old:
		entry["old"] = old
	if has_new:
		entry["new"] = new
	found.append(entry)


## The parsed text, or null when it is not JSON (JSON.parse_string would also log an engine
## error, which tools/godot.sh counts as a diagnostic failure).
static func _parse(text: String) -> Variant:
	var json := JSON.new()
	return json.data if json.parse(text) == OK else null


static func _join(path: String, key: Variant) -> String:
	return str(key) if path == "" else "%s/%s" % [path, str(key)]


## A deep copy of a parsed JSON value with every integral float (|x| < 2^53) turned back into
## an int — the spelling the sweep's rows are built with.
static func plain(value: Variant) -> Variant:
	if value is float and is_finite(value) and value == floorf(value) and absf(value) < 9007199254740992.0:
		return int(value)
	if value is Dictionary:
		var copy := {}
		for key in value:
			copy[key] = plain(value[key])
		return copy
	if value is Array:
		var items := []
		for item in value:
			items.append(plain(item))
		return items
	return value
