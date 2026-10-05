## Playtest journal. When HSL_JOURNAL_DIR is set, BattleSceneRuntime hands every
## apply_loop(prev, next, reason) to observe(); this writes one JSON line per meaningful
## change of the battle loop (round, player command, combat, AI action, winfail status,
## dialogue, outcome). Pure observer: never reads input, never changes state. Without the
## environment variable nothing is created. Each line is a self-contained JSON object.
##
## provenance:
##   rules: remake-invented
##     (playtest journal behind the HSL_JOURNAL_DIR development switch; it only observes the battle loop, the
##     original has no such log)
extends RefCounted

const SELF_PATH := "res://game/debug/BattleJournal.gd"

const BattlePlayLoop = preload("res://game/sim/loop/BattlePlayLoop.gd")
const BattleOutcome = preload("res://game/sim/BattleOutcome.gd")
const Interaction = preload("res://game/sim/Interaction.gd")

const UNIT_NAME_KEYS := ["display_name", "name", "title", "name_text", "token", "actor"]
const UNIT_MAXHP_KEYS := ["max_hp", "hp_max", "max_hit_point", "hit_point_max"]
const UNIT_EXTRA_KEYS := ["role", "mode", "level", "wait_round", "ai_fixed", "fixed_point", "ai_home_coord", "ai_fixed_radius", "undead", "no_attack", "token"]
const PLAYER_REASONS := ["select_player_unit", "choose_command", "choose_magic", "choose_special", "move_unit_to", "move_unit_to_rejected",
	"attack_coord", "finish_exhausted_action", "use_item", "cancel_interaction", "cancel_pending_move", "cancel_magic", "commit_wait",
	"begin_give", "confirm_give", "finish_give", "change_equipment", "discard_item"]

var _file: FileAccess = null
var _path := ""
var _t0 := 0
var _fp := ""
var _round := -1
var _ended := false
var _ai_count := 0
var _fired_count := 0
var _dialogue_count := 0
var _combat_seq := 0
var _item_seq := -1
var _started := false


static func enabled() -> bool:
	return OS.get_environment("HSL_JOURNAL_DIR") != ""


static func open_for(scenario: Dictionary) -> RefCounted:
	if not enabled():
		return null
	var dir := OS.get_environment("HSL_JOURNAL_DIR")
	if DirAccess.make_dir_recursive_absolute(dir) != OK and not DirAccess.dir_exists_absolute(dir):
		push_warning("BattleJournal: cannot create %s" % dir)
		return null
	var j: RefCounted = load(SELF_PATH).new()
	var id := str(scenario.get("id", "battle"))
	var stamp := Time.get_datetime_string_from_system(false, true).replace(":", "").replace("T", "_").replace("-", "")
	j._path = dir.path_join("%s_%s.jsonl" % [stamp, id])
	j._file = FileAccess.open(j._path, FileAccess.WRITE)
	if j._file == null:
		push_warning("BattleJournal: cannot open %s" % j._path)
		return null
	j._t0 = Time.get_ticks_msec()
	j._write({"kind": "scene", "scenario_id": id, "title": str(scenario.get("title", "")),
		"level_kind": str(scenario.get("level_kind", "")), "wall": Time.get_datetime_string_from_system(), "path": j._path})
	return j


func path() -> String:
	return _path


## Called by the scene after every loop write. prev may be empty on the first write.
func observe(prev: Dictionary, next: Dictionary, reason: String) -> void:
	if _file == null or next.is_empty():
		return
	var summary: Dictionary = BattlePlayLoop.summary(next)
	var round_no := int(summary.get("round", 0))
	var actor := str(summary.get("current_actor_id", ""))
	var inter := str(summary.get("interaction", ""))
	var fp := _fingerprint(next, summary)
	if fp == _fp:
		return
	_fp = fp
	var base := {"round": round_no, "actor": actor, "reason": reason}

	if not _started or reason == "begin_battle":
		_started = true
		_write(_merge(base, {"kind": "battle_start", "map_size": _plain(next.get("map_size")), "units": _plain(next.get("units", []))}))
		_round = round_no

	if round_no != _round:
		_round = round_no
		_write(_merge(base, {"kind": "round", "units": _units_compact(next), "queue": _plain(_queue_ids(next))}))

	var prev_inter := str(prev.get("interaction", "")) if not prev.is_empty() else ""
	if inter in Interaction.PLAYER_CONTROL and not (prev_inter in Interaction.PLAYER_CONTROL):
		_write(_merge(base, {"kind": "control", "interaction": inter}))

	if reason in PLAYER_REASONS:
		var rec := {"kind": "player", "interaction_before": prev_inter, "interaction_after": inter,
			"selected": str(next.get("selected_unit_id", "")), "command_menu": _plain((next.get("command_menu", {}) as Dictionary).get("commands", [])),
			"selected_skill_id": str(next.get("selected_skill_id", ""))}
		var sel := str(next.get("selected_unit_id", ""))
		if sel == "": sel = actor
		if sel != "" and not prev.is_empty():
			var a: Variant = _coord_of(prev, sel)
			var b: Variant = _coord_of(next, sel)
			if a != b:
				rec["from"] = _plain(a); rec["to"] = _plain(b)
		var reject: Dictionary = next.get("last_command_reject", {})
		if not reject.is_empty() and reject != prev.get("last_command_reject", {}): rec["reject"] = _plain(reject)
		var areject: Dictionary = next.get("last_attack_reject", {})
		if not areject.is_empty() and areject != prev.get("last_attack_reject", {}): rec["attack_reject"] = _plain(areject)
		_write(_merge(base, rec))

	var combat: Dictionary = next.get("last_combat", {})
	var seq := int(combat.get("sequence", 0))
	if seq > _combat_seq:
		_combat_seq = seq
		var c := combat.duplicate(true)
		c.erase("strip_known_ids")
		_write(_merge(base, {"kind": "combat", "combat": _plain(c), "hp": _hp_map(next)}))

	var item: Dictionary = next.get("last_item_use", {})
	if not item.is_empty():
		var iseq := int(item.get("sequence", item.get("revision", -2)))
		if iseq != _item_seq and item != prev.get("last_item_use", {}):
			_item_seq = iseq
			_write(_merge(base, {"kind": "item", "item": _plain(item), "hp": _hp_map(next)}))

	var ai_actions: Array = next.get("last_ai_actions", [])
	if ai_actions.size() < _ai_count:
		_ai_count = 0
	for i in range(_ai_count, ai_actions.size()):
		var a: Dictionary = ai_actions[i]
		var ar := a.duplicate(true)
		if ar.has("path") and (ar["path"] as Array).size() > 40: ar["path"] = []
		_write(_merge(base, {"kind": "ai", "action": _plain(ar)}))
	_ai_count = ai_actions.size()

	var runtime: Dictionary = next.get("winfail_runtime", {})
	var fired: Array = runtime.get("fired", [])
	if fired.size() < _fired_count: _fired_count = 0
	for i in range(_fired_count, fired.size()):
		_write(_merge(base, {"kind": "winfail", "fired": _plain(fired[i])}))
	_fired_count = fired.size()
	var dialogue: Array = runtime.get("dialogue", [])
	if dialogue.size() < _dialogue_count: _dialogue_count = 0
	for i in range(_dialogue_count, dialogue.size()):
		_write(_merge(base, {"kind": "message", "message": _plain(dialogue[i])}))
	_dialogue_count = dialogue.size()

	if not _ended and BattleOutcome.decided(next):
		_ended = true
		_write(_merge(base, {"kind": "battle_end", "outcome": _plain(BattleOutcome.of(next)), "units": _units_compact(next)}))
		_file.flush()


func _fingerprint(next: Dictionary, summary: Dictionary) -> String:
	var parts := PackedStringArray()
	parts.append(str(summary.get("round", 0)))
	parts.append(str(summary.get("current_actor_id", "")))
	parts.append(str(summary.get("interaction", "")))
	parts.append(str(next.get("selected_unit_id", "")))
	parts.append(str(bool(next.get("pending_move", false))))
	parts.append(str((next.get("last_combat", {}) as Dictionary).get("sequence", 0)))
	parts.append(str((next.get("last_ai_actions", []) as Array).size()))
	var runtime: Dictionary = next.get("winfail_runtime", {})
	parts.append(str((runtime.get("fired", []) as Array).size()))
	parts.append(str((runtime.get("dialogue", []) as Array).size()))
	parts.append(str(_plain(next.get("last_item_use", {}))))
	parts.append(str(_plain(next.get("last_command_reject", {}))))
	for u in next.get("units", []):
		if typeof(u) != TYPE_DICTIONARY: continue
		parts.append("%s@%s/%s%s%s" % [str(u.get("id", "")), str(u.get("coord", "")), str(u.get("hp", "")),
			"x" if bool(u.get("defeated", false)) else "", "-" if bool(u.get("departed", false)) else ""])
	parts.append(str(BattleOutcome.decided(next)))
	return ",".join(parts)


func _units_compact(loop: Dictionary) -> Array:
	var out := []
	for u in loop.get("units", []):
		if typeof(u) != TYPE_DICTIONARY: continue
		var d := {"id": str(u.get("id", "")), "name": _unit_name(u), "coord": _plain(u.get("coord")), "hp": u.get("hp", null),
			"max_hp": _first(u, UNIT_MAXHP_KEYS), "defeated": bool(u.get("defeated", false)), "departed": bool(u.get("departed", false))}
		for k in UNIT_EXTRA_KEYS:
			if u.has(k): d[k] = _plain(u[k])
		out.append(d)
	return out


func _hp_map(loop: Dictionary) -> Dictionary:
	var out := {}
	for u in loop.get("units", []):
		if typeof(u) != TYPE_DICTIONARY: continue
		out[str(u.get("id", ""))] = [u.get("hp", null), _first(u, UNIT_MAXHP_KEYS), bool(u.get("defeated", false))]
	return out


func _queue_ids(loop: Dictionary) -> Array:
	var q: Dictionary = loop.get("turn_queue", {})
	var out := []
	for k in ["order", "entries", "queue", "actors"]:
		if q.has(k) and typeof(q[k]) == TYPE_ARRAY:
			for e in q[k]:
				out.append(str(e.get("id", e)) if typeof(e) == TYPE_DICTIONARY else str(e))
			break
	return out


func _coord_of(loop: Dictionary, unit_id: String) -> Variant:
	for u in loop.get("units", []):
		if typeof(u) == TYPE_DICTIONARY and str(u.get("id", "")) == unit_id:
			return u.get("coord", null)
	return null


static func _unit_name(u: Dictionary) -> String:
	for k in UNIT_NAME_KEYS:
		if u.has(k) and str(u[k]) != "": return str(u[k])
	return str(u.get("id", ""))


static func _first(u: Dictionary, keys: Array) -> Variant:
	for k in keys:
		if u.has(k): return u[k]
	return null


static func _merge(a: Dictionary, b: Dictionary) -> Dictionary:
	var out := a.duplicate()
	out.merge(b, true)
	return out


func _write(rec: Dictionary) -> void:
	if _file == null: return
	rec["t"] = Time.get_ticks_msec() - _t0
	_file.store_line(JSON.stringify(_plain(rec)))
	if rec.get("kind") in ["battle_start", "round", "winfail", "battle_end", "combat"]:
		_file.flush()


static func _plain(v: Variant) -> Variant:
	match typeof(v):
		TYPE_VECTOR2I: return [v.x, v.y]
		TYPE_VECTOR2: return [v.x, v.y]
		TYPE_DICTIONARY:
			var d := {}
			for k in v.keys(): d[str(k)] = _plain(v[k])
			return d
		TYPE_ARRAY:
			var a := []
			for e in v: a.append(_plain(e))
			return a
		TYPE_PACKED_INT32_ARRAY, TYPE_PACKED_STRING_ARRAY, TYPE_PACKED_FLOAT32_ARRAY, TYPE_PACKED_INT64_ARRAY, TYPE_PACKED_FLOAT64_ARRAY:
			return Array(v)
		TYPE_OBJECT, TYPE_CALLABLE, TYPE_SIGNAL: return str(v)
		_: return v
