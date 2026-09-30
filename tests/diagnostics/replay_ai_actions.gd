extends "res://tests/diagnostics/export_enemy_turns.gd"

## Replay judge, remake side (lane BATCH3; diagnostic only, no rule changes): the referee's
## round played again in the remake with the original's own AI draws fed in, decision point by
## decision point, and each queue slot's decision compared (hsltools.probes.ai_replay reads it).
##
##   tools/godot.sh --headless --script res://tests/diagnostics/replay_ai_actions.gd -- \
##       --jobs FILE --state ignored/ai_action_frequency/board_growth_false.json --turns 1 --out FILE
##
## --jobs FILE: a JSON list of {"battle", "level", "seed", "original", "meta", "select_event"?}:
## the `_enemy_level.py batch` lines (draws named by enemy_turn.SITE_MAP) and meta (opening_board,
## action_after, handoff_after) of one (level, seed). Each job is the export run the batch compares
## (`_prepare` with --seed s --global-seed s --state FILE) with three differences:
##
## - AI source = Feeder: a draw asked by an AI rule (innermost AI-rule frame `Script.function`,
##   as the exporter names it) at bound n takes the next value the original drew at the same
##   `site/n` in the same queue slot (one FIFO per site/n: the original's values by call site,
##   not by position, so a draw-order difference is no mismatch). A site/n with no value left is
##   `exhausted` (the remake draws there more often than the original, or at a site with no
##   original counterpart) and takes a fallback PCG value; non-AI draws (the exchange's hit and
##   damage) always take the fallback.
## - the board follows the original: at the opening every unit's hp and held target (+0x88) take
##   the original's opening_board values; before a slot the actor stands on the original's
##   `from`; after it on the original's `to`, with the original's held target (action_after
##   chase) and every unit's hp as the original's deltas leave it (player turn-ends: handoff_after).
##   A unit the original killed and the remake did not is marked defeated (`death`); the reverse
##   (`revive`) cannot be undone — both stay as context flags on every later slot.
## - the queue is the remake's: a remake slot whose actor is not the original's next one is run
##   uncompared when the actor never acts in the rest of the original round (ship hulls
##   actor101_x, paralysed players, units the probe does not see), else the job stops (`order`).
##
## Output FILE: one line per job {"level", "seed", "error", "stop", "opening_diff", "rows",
## "uncompared", "unreached"}; a row: k (original action index), round, actor, original／remake
## {from, to, action, target, skill} (the remake's action_twice pair merged as the batch merges
## it), same, drawn (site/n in the remake's order), exhausted, leftover {site/n: count} (original
## values the remake never asked for), context, decision (TURNDUMP_DECISION summary per step).
## stdout: REPLAY_RUN per job, REPLAY_DONE at the end.

const BattlePresenceRules = preload("res://game/sim/BattlePresenceRules.gd")
## The original's chain call sites (priority／support chain rolls, HP tests, action class, MAGIC／SPECIAL lists,
## area order, side walk, buff aid) and the remake draw points of the same phase.
const CHAIN_SITES := ["0x440db5", "0x440ddf", "0x440e1b", "0x440e57", "0x440e93", "0x440ecf", "0x40c138", "0x40c061", "0x40d500",
	"0x40c58d", "0x40c5b3", "0x40c5f8", "0x40c7f8", "0x40c842", "0x40de0c", "0x40de56", "0x43ff32", "0x440a86"]
const CHAIN_NAMES := ["AIPriorityRules.choose_check", "AIPriorityRules.self_recovery", "AIPriorityRules.low_hp_target", "AISupportRules.next_check",
	"AISkillDecisionRules.area_order", "AIDecisionRules.select_action", "AISkillDecisionRules.select_index", "AIDecisionRules.side_walk_roll",
	"BattleLoopAI._ai_lock_check", "AISupportPlanning.choose"]


class Feeder:
	var fallback := RandomNumberGenerator.new()
	var queues := {}
	var log: Array = []
	var drawn: Array = []
	var exhausted: Array = []

	var mode := "first"
	var in_chain := false

	## `sites`: the call address of each draw (1:1). mode first: every draw; final／low／high: the
	## draws of the priority chain's passes that looped back (from the first 0x440db5 roll up to the
	## last one) are dropped — the original re-rolls the whole chain when a chosen category finds no
	## object, the remake skips such categories beforehand (AI-PRIO-2, distribution-equal) — and
	## low／high answer an exhausted site/n with 0／n - 1 instead of the fallback PCG.
	## The remake's fresh lock roll (BattleLoopAI._ai_lock_check, drawn when no chain roll is
	## carried) takes the original's carried roll: its last chain roll (choose_check／next_check).
	func prime(draws: Array, sites: Array = []) -> void:
		queues = {}
		drawn = []
		exhausted = []
		in_chain = false
		# phase: draws before the original's first chain draw (target acquisition: the 0x40bb80 scan coins and its
		# approach cells) feed the remake's draws before its first chain draw; the rest feed the rest (the move's
		# 0x413740 coins come after the chain on both sides)
		var chain_at := draws.size()
		for i in sites.size():
			if str(sites[i]) in CHAIN_SITES:
				chain_at = i
				break
		var keep := range(draws.size())
		if mode != "first" and sites.size() == draws.size():
			var starts: Array = []
			for i in sites.size():
				if str(sites[i]) == "0x440db5": starts.append(i)
			if starts.size() >= 2: keep = keep.filter(func(i): return i < int(starts[0]) or i >= int(starts[-1]))
		var carried := -1
		for i in keep:
			var d: Dictionary = draws[i]
			var key := "%s/%s" % [str(d["site"]), "null" if d["n"] == null else str(int(d["n"]))]
			var value := int(d["value"])
			# 0x440a86..0x440ad3 buff aid: one raw draw, its low bit orders magic／special — the remake's
			# AISupportPlanning.choose special_first coin (not in enemy_turn.SITE_MAP)
			if str(d["site"]) == "0x440a86":
				key = "AISupportPlanning.choose/2"
				value = value & 1
			if key in ["AIPriorityRules.choose_check/99", "AISupportRules.next_check/99"]: carried = int(d["value"])
			key = ("pre|" if i < chain_at else "post|") + key
			if not queues.has(key): queues[key] = []
			queues[key].append(value)
		if carried >= 0: queues["post|BattleLoopAI._ai_lock_check/99"] = [carried]

	func draw(n: int) -> int:
		var stack := get_stack()
		var site := _ai_site(stack)
		var value := -1
		if site != "":
			var key := "%s/%d" % [site, n]
			drawn.append(key)
			if site in CHAIN_NAMES: in_chain = true
			var queue: Array = queues.get(("post|" if in_chain else "pre|") + key, [])
			if queue.is_empty():
				exhausted.append(key)
				if mode == "low": value = 0
				elif mode == "high": value = maxi(n - 1, 0)
			else: value = int(queue.pop_front())
		if value < 0: value = fallback.randi_range(0, n - 1) if n > 0 else int(fallback.randi())
		log.append({"n": n, "value": value, "stack": stack})
		return value

	func remaining() -> Dictionary:
		var out := {}
		for key in queues:
			if not queues[key].is_empty(): out[str(key).get_slice("|", 1)] = int(out.get(str(key).get_slice("|", 1), 0)) + queues[key].size()
		return out

	static func _ai_site(stack: Array) -> String:
		for frame in stack:
			var script := str(frame.get("source", "")).get_file().get_basename()
			var function := str(frame.get("function", ""))
			if script in ["replay_ai_actions", "export_enemy_turns"]: continue
			if script == "CoreCombatRules" and function in ["rand_range", "native_draw"]: continue
			if function == "recorded_draw": continue
			return "%s.%s" % [script, function] if script in AI_SOURCES else ""
		return ""


func _initialize() -> void:
	var args := Array(OS.get_cmdline_user_args())
	var opts := {"turns": "1", "jobs": "", "state": "", "out": ""}
	var i := 0
	while i + 1 < args.size():
		opts[str(args[i]).trim_prefix("--")] = str(args[i + 1])
		i += 2
	var jobs: Variant = JSON.parse_string(FileAccess.get_file_as_string(str(opts["jobs"])))
	var file := FileAccess.open(str(opts["out"]), FileAccess.WRITE)
	if not jobs is Array or file == null:
		printerr("REPLAY usage: --jobs FILE --state FILE --turns N --out FILE")
		quit(2)
		return
	var done := 0
	for job in jobs:
		var run_opts := {"battle": str(job["battle"]), "turns": int(opts["turns"]), "seed": int(job["seed"]), "global-seed": int(job["seed"])}
		if not str(opts["state"]).is_empty(): run_opts["state"] = str(opts["state"])
		if job.get("select_event") != null: run_opts["select-event"] = int(job["select_event"])
		var result := _fresh(job)
		var prep := _prepare(run_opts)
		if not str(prep["error"]).is_empty(): result["error"] = str(prep["error"])
		else:
			var rounds := _load_lines(str(job["original"]))
			var meta: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(str(job["meta"])))
			result = _replay(prep, run_opts, rounds, meta, result, "first")
			# the other variants only up to the last row variant first decides differently
			var last_diff := -1
			for row in result["rows"]:
				if not bool(row["same"]): last_diff = int(row["k"])
			for mode in (["final", "low", "high"] if last_diff >= 0 else []):
				var other := _replay(prep, run_opts, rounds, meta, _fresh(job), mode, last_diff)
				var by_k := {}
				for row in other["rows"]: by_k[int(row["k"])] = row
				for row in result["rows"]:
					var alt: Dictionary = by_k.get(int(row["k"]), {})
					if not row.has("variants"): row["variants"] = {}
					row["variants"][mode] = {} if alt.is_empty() else {"same": alt["same"], "exhausted": alt["exhausted"], "remake": alt["remake"], "context": alt["context"]}
		file.store_line(JSON.stringify(result))
		done += 1
		print("REPLAY_RUN level=%d seed=%d rows=%d stop=%s error=%s" % [int(job["level"]), int(job["seed"]), result["rows"].size(), result["stop"], result["error"]])
	file.close()
	print("REPLAY_DONE jobs=%d" % done)
	quit(0)


func _fresh(job: Dictionary) -> Dictionary:
	return {"level": int(job["level"]), "seed": int(job["seed"]), "error": "", "stop": "", "opening_diff": [], "rows": [], "uncompared": [], "unreached": []}


func _replay(prep: Dictionary, opts: Dictionary, rounds: Array, meta: Dictionary, result: Dictionary, mode: String, stop_after: int = 1 << 30) -> Dictionary:
	var loop: Dictionary = BattlePlayLoop.copy(prep["loop"])
	var first_turn := int(prep["first_turn"])
	var last_turn := first_turn + int(opts["turns"]) - 1
	var flat: Array = []
	for turn in rounds:
		for action in turn.get("actions", []): flat.append(dict_with(action, "round", int(turn.get("turn", 1))))
	var after: Array = meta.get("action_after", [])
	var handoffs: Array = meta.get("handoff_after", [])
	var tracked := {}
	var opening: Dictionary = meta.get("opening_board", {})
	for unit in loop["units"]:
		var id := str(unit["id"])
		if not opening.has(id): continue
		var o: Dictionary = opening[id]
		tracked[id] = int(o["hp"])
		if int(unit.get("hp", 0)) != int(o["hp"]):
			result["opening_diff"].append("%s.hp %d->%d" % [id, int(unit.get("hp", 0)), int(o["hp"])])
			unit["hp"] = mini(int(o["hp"]), int(unit.get("max_hp", o["hp"])))
		var held := "" if o.get("target") == null else _id(str(o["target"]))
		if str(unit.get("ai_target_id", "")) != held and not bool(unit.get("player_commandable", false)):
			result["opening_diff"].append("%s.target %s->%s" % [id, str(unit.get("ai_target_id", "")), held])
			unit["ai_target_id"] = held
		if o.get("cell") is Array and unit.get("coord") is Vector2i and unit["coord"] != Vector2i(int(o["cell"][0]), int(o["cell"][1])):
			result["opening_diff"].append("%s.cell" % id)
	var feeder := Feeder.new()
	feeder.fallback.seed = int(opts["seed"])
	feeder.mode = mode
	var source := Callable(feeder, "draw")
	var k := 0
	var pending := {}
	var sticky: Array = []
	var handoff_index := 0
	var step := 0
	while step < MAX_STEPS:
		step += 1
		if BattleOutcome.decided(loop): break
		if not bool(loop.get("scenario_ok", false)):
			result["error"] = "scenario:%s" % str(loop.get("scenario_error", ""))
			break
		loop = _settle_rewards(loop)
		var round_number := int(loop.get("turn", 1))
		if round_number > last_turn: break
		if k > stop_after: break
		var interaction := str(loop.get("interaction", ""))
		if interaction == "ai_resolving":
			var cur_id := str(CoreTurnQueue.current(loop.get("turn_queue", {})).get("id", ""))
			if not pending.is_empty() and cur_id != pending["actor"]:
				loop = _finish(loop, pending, flat[k], after[k] if k < after.size() else {}, k, tracked, sticky, feeder, result)
				pending = {}
				k += 1
			if pending.is_empty():
				var expected: Dictionary = flat[k] if k < flat.size() else {}
				var comparable := not expected.is_empty() and str(expected["actor"]) == cur_id and int(expected["round"]) == round_number
				if not comparable:
					var later := false
					for j in range(k, flat.size()):
						if int(flat[j]["round"]) == round_number and str(flat[j]["actor"]) == cur_id: later = true
					if later:
						result["stop"] = "order k=%d remake=%s original=%s" % [k, cur_id, str(expected.get("actor", "-"))]
						break
					feeder.prime([])
					var before_skip := loop
					var mark_skip := feeder.log.size()
					loop = BattlePlayLoop.step_ai_turn(loop, source)
					if loop.get("last_ai_actions", []).size() != before_skip.get("last_ai_actions", []).size():
						var skipped := _action_entry(before_skip, loop, feeder.log.slice(mark_skip))
						skipped.erase("draws")
						result["uncompared"].append(skipped)
					continue
				var actor := BattlePlayLoop.unit_ref(loop, cur_id)
				var context: Array = sticky.duplicate()
				var origin := Vector2i(int(expected["from"][0]), int(expected["from"][1]))
				if actor.get("coord") != origin:
					context.append("from")
					actor["coord"] = origin
				feeder.prime(expected.get("draws", []), after[k].get("sites", []) if k < after.size() else [])
				pending = {"actor": cur_id, "entries": [], "decisions": [], "context": context}
			var before := loop
			var mark := feeder.log.size()
			loop = BattlePlayLoop.step_ai_turn(loop, source)
			if loop.get("last_ai_actions", []).size() == before.get("last_ai_actions", []).size(): continue
			var entry := _action_entry(before, loop, feeder.log.slice(mark))
			pending["entries"].append(entry)
			pending["decisions"].append(_decision_summary(loop, entry))
			continue
		if interaction == "action_menu":
			if not pending.is_empty():
				loop = _finish(loop, pending, flat[k], after[k] if k < after.size() else {}, k, tracked, sticky, feeder, result)
				pending = {}
				k += 1
			loop = _player_turn(loop, ["wait"], feeder.fallback)
			if handoff_index < handoffs.size():
				var deltas: Dictionary = handoffs[handoff_index].get("hp", {})
				for id in deltas: tracked[id] = int(tracked.get(id, 0)) + int(deltas[id])
				handoff_index += 1
				_sync_hp(loop, tracked, sticky)
			continue
		result["error"] = "stopped_at_interaction:%s" % interaction
		break
	if not pending.is_empty() and k < flat.size():
		loop = _finish(loop, pending, flat[k], after[k] if k < after.size() else {}, k, tracked, sticky, feeder, result)
		k += 1
	for j in range(k, flat.size()):
		if int(flat[j]["round"]) <= last_turn: result["unreached"].append({"k": j, "actor": flat[j]["actor"]})
	return result


static func dict_with(source: Dictionary, key: String, value: Variant) -> Dictionary:
	var copy := source.duplicate(true)
	copy[key] = value
	return copy


## Compare one queue slot, then move the board to where the original left it.
func _finish(loop: Dictionary, pending: Dictionary, expected: Dictionary, after: Dictionary, k: int, tracked: Dictionary, sticky: Array, feeder: Feeder, result: Dictionary) -> Dictionary:
	var entries: Array = pending["entries"]
	var merged: Dictionary = entries[0].duplicate(true)
	# The compared row is {actor, from, to, action, target, skill} whether one entry or an
	# action_twice pair was merged: draws and the per-step hp are dropped (the board follows the
	# original's action_after hp below, not the remake's).
	merged.erase("draws")
	merged.erase("hp")
	for i in range(1, entries.size()):
		var last: Dictionary = entries[i]
		var keep: Dictionary = last if str(last["action"]) != "wait" else (merged if str(merged["action"]) != "wait" else last)
		merged = {"actor": merged["actor"], "from": merged["from"], "to": last["to"], "action": keep["action"], "target": keep["target"], "skill": keep["skill"]}
	if str(merged["action"]) == "other": merged = dict_with(dict_with(merged, "action", "wait"), "to", merged["from"])
	var original := {"from": expected["from"], "to": expected["to"], "action": expected["action"], "target": expected["target"], "skill": expected.get("skill")}
	var same := true
	for field in ["from", "to", "action", "target"]:
		if str(original[field]) != str(merged.get(field)): same = false
	result["rows"].append({"k": k, "round": int(expected["round"]), "actor": str(expected["actor"]), "original": original, "remake": merged, "same": same,
		"drawn": feeder.drawn.duplicate(), "exhausted": feeder.exhausted.duplicate(), "leftover": feeder.remaining(),
		"context": pending["context"], "decision": pending["decisions"]})
	var actor := BattlePlayLoop.unit_ref(loop, str(expected["actor"]))
	if not actor.is_empty():
		if expected.get("to") is Array: actor["coord"] = Vector2i(int(expected["to"][0]), int(expected["to"][1]))
		if after.has("chase"): actor["ai_target_id"] = "" if after["chase"] == null else _id(str(after["chase"]))
	var deltas: Dictionary = after.get("hp", {})
	for id in deltas: tracked[id] = int(tracked.get(id, 0)) + int(deltas[id])
	_sync_hp(loop, tracked, sticky)
	return loop


func _sync_hp(loop: Dictionary, tracked: Dictionary, sticky: Array) -> void:
	for unit in loop["units"]:
		var id := str(unit["id"])
		if not tracked.has(id): continue
		var want := int(tracked[id])
		var alive := BattlePresenceRules.living(unit)
		if want <= 0 and alive:
			unit["hp"] = 0
			unit["defeated"] = true
			if not ("death:" + id) in sticky: sticky.append("death:" + id)
		elif want > 0 and not alive:
			if not ("revive:" + id) in sticky: sticky.append("revive:" + id)
		elif want > 0:
			unit["hp"] = mini(want, int(unit.get("max_hp", want)))
