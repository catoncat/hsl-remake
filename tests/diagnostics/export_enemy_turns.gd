extends SceneTree

## Enemy-turn export (`enemy_turn_v1`): load a level's opening on the pure PlayLoop, fix
## every random stream's starting point, run N rounds and print one JSON object per round
## listing each NPC action in order (actor, from→to, action, target, skill, and every AI
## decision draw with its site). The remake counterpart of the emulator run of the
## original program on the same board, for cell-by-cell comparison and batch sweeps of
## level openings. Diagnostic only, not a gate: no rule changes — draws are recorded by
## wrapping the AI source RNG in a Callable (CoreCombatRules accepts either; same values).
##
##   tools/godot.sh --headless --script res://tests/diagnostics/export_enemy_turns.gd -- [options]
##
##   --battle 051        level id (content/battles/battle_<id>.json) or res:// path
##   --turns N           rounds to export (default 3)
##   --seed N            product-style HSL_RNG_SEED: create() reward seed and AI source seed (default 1)
##   --ai-seed N         AI source seed (overrides --seed; in the remake this source also rolls
##                       the combat hits/damage of the acting unit's exchange)
##   --ai-state N        RandomNumberGenerator.state of the AI source after seeding
##   --reward-seed N     create() reward_seed: seeds the damage stream (items, recovery) (overrides --seed)
##   --global-seed N     the global stream's clock value t (0x458c10 lazy seed [t, t ^ 0xe54a231c]),
##                       drawn by the NPC opening level-ups 0x40e870; default: the process
##                       stream (HSL_RNG_SEED headless). The AI draws stay on the AI source
##   --state FILE        board overrides after opening growth: {"growth": false (births without
##                       level dispersion, the referee's growth false; with "speed" the template
##                       roster, no births), "turn": n, "speed": {id: n},
##                       "units": {id: [x, y]}, "hp": {id: n}, "dead": [id], "targets": {id: id},
##                       "resume_after": id (start mid-round after that unit's slot)};
##                       ids with or without the "actor" prefix; the queue is rebuilt
##   --state-key KEY     take the board from FILE[KEY] (one file holding several boards)
##   --select-event N    after the board, the opening actSelectInsertEvent choice of winfail event
##                       N (WinfailScenarioRules.select_event_status, as the opening prompt does);
##                       its chain's walks commit at the outcome check (level 900: event 1)
##   --plan TEXT         player turns `;`-separated, each `move:X/Y`,`attack:X/Y`,`special:X/Y`,
##                       `wait` (comma list, like trace_battle051_ai.gd); default: every player waits
##   --out FILE          also write the JSON lines to FILE
##   --check             rerun without the draw recorder and fail unless actions match
##   --expect FILE       enemy_turn_v1 lines to compare with (actor/from/to/action/target, and
##                       skill／draws when the expectation gives them; a Wait's null target and
##                       the actors of an optional "skip": [id] are not compared); prints
##                       TURNDUMP_MATCH lines
##   --search A-B[,C,..] with --expect: try these AI seeds, stop each run at its first mismatch,
##                       print the best seeds (longest matched prefix) instead of the export
##   --decisions         also print one `TURNDUMP_DECISION {json}` line per AI action: the target
##                       selection (index, reason, retained, previous target), the candidate
##                       filters and the lock check — stdout only, the export lines are unchanged
##
## Output: stdout lines starting with `{"format":"enemy_turn_v1"` are the export; other
## lines are Godot/tool chatter. `rng` holds each stream's live value when the round
## starts (`ai_seed`／`ai_state` for the AI source, every `*_rng` loop stream).

const Loop = preload("res://game/sim/loop/BattlePlayLoop.gd")
const BattleScenario = preload("res://game/sim/BattleScenario.gd")
const BattleOutcome = preload("res://game/sim/BattleOutcome.gd")
const WinfailScenarioRules = preload("res://game/sim/WinfailScenarioRules.gd")
const GlobalRandom = preload("res://game/sim/GlobalRandomStream.gd")
const CoreTurnQueue = preload("res://game/sim/CoreTurnQueue.gd")
const TargetRules = preload("res://game/sim/SkillTargetRules.gd")
const Footprint = preload("res://game/sim/FootprintRules.gd")

const FORMAT := "enemy_turn_v1"
const MAX_STEPS := 2000
## Scripts whose frames are AI decision points. A draw whose innermost non-helper frame
## lies elsewhere (combat hit/damage, experience) is not an AI decision draw.
const AI_SOURCES := ["AIDecisionRules", "AIPriorityRules", "AISupportRules", "AINavigationRules",
	"AISkillDecisionRules", "AISkillPlanning", "AISupportPlanning", "BattleLoopAI"]


## The AI source: a seeded RandomNumberGenerator, drawn exactly as CoreCombatRules draws
## from a RandomNumberGenerator (`randi_range(0, n - 1)`; `randi()` for n <= 0), with each
## draw logged together with the call stack that asked for it.
class DrawRecorder:
	var rng := RandomNumberGenerator.new()
	var log: Array = []

	func draw(n: int) -> int:
		var value: int = rng.randi_range(0, n - 1) if n > 0 else int(rng.randi())
		log.append({"n": n, "value": value, "stack": get_stack()})
		return value


func _initialize() -> void:
	var opts := _parse(Array(OS.get_cmdline_user_args()))
	if opts.has("error"):
		printerr("TURNDUMP usage error: %s" % opts["error"])
		quit(2)
		return
	var prep := _prepare(opts)
	if not str(prep["error"]).is_empty():
		print("TURNDUMP error %s" % prep["error"])
		quit(1)
		return
	# Compare only the rounds this run exports.
	var expect: Array = []
	if opts.has("expect"):
		for turn in _load_lines(str(opts["expect"])):
			var round_number := int(turn.get("turn", 0))
			if round_number < int(prep["first_turn"]) or round_number >= int(prep["first_turn"]) + int(opts["turns"]): continue
			if round_number == int(prep["first_turn"]):
				# A mid-round board ("resume_after"): units that already acted are not expected.
				turn["actions"] = turn.get("actions", []).filter(func(a): return not str(a.get("actor", "")) in prep["acted"])
			expect.append(turn)
	if opts.has("search"):
		_search(prep, opts, expect)
		quit(0)
		return
	var run := _play(prep, opts, true)
	if not str(run["error"]).is_empty():
		print("TURNDUMP error %s" % run["error"])
		quit(1)
		return
	var lines: Array = []
	for turn in run["turns"]: lines.append(JSON.stringify(turn, "", false))
	for line in lines: print(line)
	if opts.has("out"):
		var file := FileAccess.open(str(opts["out"]), FileAccess.WRITE)
		file.store_string("\n".join(lines) + "\n")
		file.close()
	var code := 0
	if opts.has("check"):
		var raw := _play(prep, opts, false)
		var same: bool = _strip_draws(run["turns"]) == _strip_draws(raw["turns"]) and str(raw["error"]).is_empty()
		print("TURNDUMP_CHECK recorder_vs_raw_rng same=%s rounds=%d" % [str(same), run["turns"].size()])
		if not same: code = 1
	if opts.has("expect"):
		for line in _compare(run["turns"], expect): print(line)
	quit(code)


func _parse(args: Array) -> Dictionary:
	var opts := {"battle": "051", "turns": 3, "seed": 1}
	var i := 0
	while i < args.size():
		var key := str(args[i]).trim_prefix("--")
		if key == "check" or key == "decisions":
			opts[key] = true
			i += 1
			continue
		if i + 1 >= args.size(): return {"error": "missing value for --%s" % key}
		var value := str(args[i + 1])
		match key:
			"battle", "state", "state-key", "plan", "out", "expect", "search": opts[key] = value
			"turns", "seed", "ai-seed", "ai-state", "reward-seed", "global-seed", "select-event":
				if not value.lstrip("-").is_valid_int(): return {"error": "--%s wants an integer" % key}
				opts[key] = int(value)
			_: return {"error": "unknown option --%s" % key}
		i += 2
	if opts.has("search") and not opts.has("expect"): return {"error": "--search needs --expect"}
	return opts


func _scenario_path(battle: String) -> String:
	if battle.begins_with("res://"): return battle
	return "res://content/battles/battle_%s.json" % battle


func _battle_id(battle: String) -> String:
	return battle.get_file().get_basename().trim_prefix("battle_") if battle.begins_with("res://") else battle


func _id(short: String) -> String:
	return short if short.begins_with("actor") or short == "leonard" or not short.substr(0, 1).is_valid_int() else "actor" + short


## The opening every run shares: create → optional global stream start → opening
## growth → optional board overrides → outcome check → begin_battle. None of it draws
## from the AI source, so a seed search prepares it once.
func _prepare(opts: Dictionary) -> Dictionary:
	var prep := {"loop": {}, "error": "", "battle": _battle_id(str(opts["battle"])), "first_turn": 1, "acted": []}
	var scenario := BattleScenario.load_file(_scenario_path(str(opts["battle"])))
	if not bool(scenario.get("ok", false)):
		prep["error"] = "scenario_load:%s" % str(scenario.get("error", scenario.get("reason", "")))
		return prep
	var loop := Loop.create([], "", scenario, int(opts.get("reward-seed", opts["seed"])))
	if opts.has("global-seed"): loop[GlobalRandom.LOOP_KEY] = GlobalRandom.seeded(int(opts["global-seed"]))
	var state: Variant = {}
	if opts.has("state"):
		state = JSON.parse_string(FileAccess.get_file_as_string(str(opts["state"])))
		if state is Dictionary and opts.has("state-key"): state = state.get(str(opts["state-key"]))
		if not state is Dictionary:
			prep["error"] = "state_unreadable:%s %s" % [str(opts["state"]), str(opts.get("state-key", ""))]
			return prep
	# "growth": false is the referee's growth false (_enemy_level.py): the original only zeroes
	# the level-adjust words +0x1f8／+0x1fa (0x43eefb／0x44345d) and still runs every opening
	# birth 0x40e870, so NPCs reach their instance level (level 10 034: attack 59 → 68) and
	# players their inferred level. The remake births with adjust_level [0, 0], as the opening
	# snapshot's g0 does (export_opening_snapshot.gd; 127 levels field-equal to the original).
	# The template roster without births hit weaker than the referee's units (lane LETHALITY).
	# A "speed" override keeps the template roster (no births): a born unit's live speed must
	# match its growth receipt (ProgressionRules inconsistent_permanent_speed) — the recorded
	# level-51 boards (ORACLE2) stay on the template roster they were compared on.
	if not bool(state.get("growth", true)) and not state.has("speed"):
		for unit in loop["units"]:
			if unit.get("growth_profile", {}).get("allocation") == "manual": continue
			var insertion: Dictionary = unit.get("script_insert", {}).duplicate(true)
			insertion["adjust_level"] = [0, 0]
			unit["script_insert"] = insertion
	if bool(state.get("growth", true)) or not state.has("speed"): loop = Loop.initialize_roster_growth(loop)
	if not state.is_empty(): loop = _inject(loop, state)
	if opts.has("select-event"): loop = WinfailScenarioRules.select_event_status(loop, int(opts["select-event"]))
	if not bool(loop.get("scenario_ok", false)):
		prep["error"] = "scenario:%s" % str(loop.get("scenario_error", ""))
		return prep
	prep["first_turn"] = int(loop.get("turn", 1))
	var queue: Dictionary = loop["turn_queue"]
	for i in mini(int(queue.get("index", 0)), queue["slots"].size()): prep["acted"].append(str(queue["slots"][i]["id"]))
	if int(queue.get("index", 0)) > 0:
		# Mid-round, a unit already down acted (or fell) earlier in the round.
		for unit in loop["units"]:
			if bool(unit.get("defeated", false)) or int(unit.get("hp", 1)) <= 0: prep["acted"].append(str(unit["id"]))
	loop = Loop._resolve_outcome(loop)
	prep["loop"] = Loop.begin_battle(loop)
	return prep


## One export run from a prepared opening. `record`: route AI draws through the recorder
## (else the bare RNG). `expect`: stop at the first action that differs (search mode);
## `matched` counts the agreeing prefix.
func _play(prep: Dictionary, opts: Dictionary, record: bool, expect: Array = []) -> Dictionary:
	var result := {"turns": [], "error": str(prep["error"]), "matched": 0, "mismatch": ""}
	if not str(prep["error"]).is_empty(): return result
	var loop: Dictionary = Loop.copy(prep["loop"])
	var recorder := DrawRecorder.new()
	var ai_seed := int(opts.get("ai-seed", opts["seed"]))
	recorder.rng.seed = ai_seed
	if opts.has("ai-state"): recorder.rng.state = int(opts["ai-state"])
	var source: Variant = Callable(recorder, "draw") if record else recorder.rng
	var plan: Array = []
	for turn_text in str(opts.get("plan", "")).split(";", false): plan.append(Array(turn_text.split(",", false)))
	var first_turn := int(prep["first_turn"])
	var last_turn := first_turn + int(opts["turns"]) - 1
	var by_turn := {}
	var order: Array = []
	var player_turn := 0
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
		if not by_turn.has(round_number):
			by_turn[round_number] = {"format": FORMAT, "battle": prep["battle"], "turn": round_number,
				"rng": _streams(loop, ai_seed, recorder.rng), "actions": []}
			order.append(round_number)
		var interaction := str(loop.get("interaction", ""))
		if interaction == "ai_resolving":
			var before := loop
			var mark := recorder.log.size()
			loop = Loop.step_ai_turn(loop, source)
			if loop.get("last_ai_actions", []).size() == before.get("last_ai_actions", []).size(): continue
			var entry := _action_entry(before, loop, recorder.log.slice(mark))
			by_turn[round_number]["actions"].append(entry)
			if opts.has("decisions"): print("TURNDUMP_DECISION " + JSON.stringify(_decision_summary(loop, entry)))
			var skip := _skipped(expect, round_number)
			if not expect.is_empty() and not str(entry["actor"]) in skip:
				var compared: Array = by_turn[round_number]["actions"].filter(func(a): return not str(a["actor"]) in skip)
				var verdict := _expect_step(expect, round_number, compared.size() - 1, entry)
				if verdict == "done": break
				if verdict != "":
					result["mismatch"] = verdict
					break
				result["matched"] = int(result["matched"]) + 1
			continue
		if interaction == "action_menu":
			var commands: Array = plan[player_turn] if player_turn < plan.size() else ["wait"]
			player_turn += 1
			loop = _player_turn(loop, commands, source)
			continue
		result["error"] = "stopped_at_interaction:%s" % interaction
		break
	for round_number in order: result["turns"].append(by_turn[round_number])
	return result


## The target-selection part of an AI action's decision receipt (--decisions).
func _decision_summary(loop: Dictionary, entry: Dictionary) -> Dictionary:
	var decision: Dictionary = loop.get("last_ai_action", {}).get("ai_decision", {})
	var selected: Dictionary = decision.get("target_selection", {})
	var index := int(selected.get("index", -1))
	var units: Array = loop.get("units", [])
	return {"turn": int(loop.get("turn", 0)), "actor": entry["actor"], "target": entry["target"],
		"selected": str(units[index]["id"]) if index >= 0 and index < units.size() else null,
		"reason": selected.get("reason"), "retained": selected.get("retained"), "previous": selected.get("previous_target_id"),
		"candidate_filters": decision.get("candidate_filters", {}), "lock_check": decision.get("lock_check", {}),
		"adoption": decision.get("call_target", {}).get("adoption", {})}


func _inject(base: Dictionary, state: Dictionary) -> Dictionary:
	var loop := Loop.copy(base)
	var speeds: Dictionary = state.get("speed", {})
	var coords: Dictionary = state.get("units", {})
	var hps: Dictionary = state.get("hp", {})
	var dead: Array = state.get("dead", [])
	var targets: Dictionary = state.get("targets", {})
	for unit in loop["units"]:
		var short := str(unit["id"]).trim_prefix("actor")
		for key in [short, str(unit["id"])]:
			if speeds.has(key): unit["live_speed"] = int(speeds[key])
			if coords.has(key): unit["coord"] = Vector2i(int(coords[key][0]), int(coords[key][1]))
			if hps.has(key): unit["hp"] = mini(int(hps[key]), int(unit["max_hp"]))
			if key in dead:
				unit["hp"] = 0
				unit["defeated"] = true
			if targets.has(key): unit["ai_target_id"] = _id(str(targets[key]))
	loop["turn_queue"] = CoreTurnQueue.rebuild(Loop._queue_actors(loop))
	if state.has("turn"):
		# The loop counts rounds from 1, the queue from 0; keep them paired so the wrap
		# still advances the counter.
		loop["turn"] = int(state["turn"])
		loop["turn_queue"]["round"] = int(state["turn"]) - 1
	if state.has("resume_after"):
		# Start mid-round: every slot up to and including this unit has already acted.
		var slots: Array = loop["turn_queue"]["slots"]
		var after := _id(str(state["resume_after"]))
		for i in slots.size():
			if str(slots[i]["id"]) == after: loop["turn_queue"]["index"] = i + 1
	return loop


func _streams(loop: Dictionary, ai_seed: int, rng: RandomNumberGenerator) -> Dictionary:
	var streams := {"ai_seed": ai_seed, "ai_state": rng.state}
	var keys: Array = []
	for key in loop.keys():
		if str(key).ends_with("_rng") and typeof(loop[key]) == TYPE_INT: keys.append(str(key))
	keys.sort()
	for key in keys: streams[key] = int(loop[key])
	return streams


func _action_entry(before: Dictionary, after: Dictionary, draws: Array) -> Dictionary:
	var action: Dictionary = after.get("last_ai_action", {})
	var actor_id := str(action.get("actor_id", ""))
	var start: Vector2i = action.get("from", Loop._unit(before, actor_id).get("coord", Vector2i(-1, -1)))
	var to: Vector2i = action.get("to", start)
	var kind := str(action.get("kind", ""))
	var skill_id := str(action.get("skill_id", ""))
	var verb := "other"
	var target: Variant = null
	var skill: Variant = null
	if kind in ["attack", "move_then_attack"]:
		verb = "magic" if skill_id.begins_with("magic:") else ("skill" if skill_id != "" else "attack")
		target = _area_first(after, action, skill_id) if skill_id != "" else str(action.get("target_id", ""))
		if skill_id != "": skill = skill_id
	elif kind in ["use_item", "move_then_item"]:
		verb = "item"
		target = str(action.get("target_id", ""))
		var use: Dictionary = action.get("item_use", {})
		var code := str(use.get("item_code", use.get("item_id", action.get("item_code", ""))))
		if code != "": skill = "item:" + code
	elif kind in ["wait", "move"]:
		verb = "wait"
		# The unit's held pursuit target (ai_target_id; the original's object +0x88), null if none.
		var held := str(Loop._unit(after, actor_id).get("ai_target_id", ""))
		if held != "": target = held
	var ai_draws: Array = []
	for draw in draws:
		var site := _site(draw["stack"])
		if site != "": ai_draws.append({"site": site, "n": int(draw["n"]), "value": int(draw["value"])})
	return {"actor": actor_id, "from": [start.x, start.y], "to": [to.x, to.y], "action": verb,
		"target": target, "skill": skill, "draws": ai_draws}


## The original's recorded AI magic/special target: the cast state writes [0x4c1cec] = 0x4104d0(0) right after
## 0x4100e0 fills the effect area around the cast centre (0x4417a6..0x4417b5; enemy_turn.py AI_TARGET reads it at
## the caption 0x43e110) — the first object of the area in row order (0x4104d0: y outer, x inner), not the centre
## unit the remake's action names. Same convention here: the first affected unit meeting a footprint cell in row order.
static func _area_first(after: Dictionary, action: Dictionary, skill_id: String) -> String:
	var receipts: Array = action.get("affected_targets", [])
	if receipts.size() < 2 or not action.get("cast_center") is Vector2i: return str(action.get("target_id", ""))
	var ids := {}
	for receipt in receipts: ids[str(receipt.get("defender_id", ""))] = true
	var footprint: Array = TargetRules.cast_footprint(action["to"], action["cast_center"], Loop.skill_fields(after, skill_id), after["skill_target_data"], after["map_size"])
	footprint.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.y < b.y or (a.y == b.y and a.x < b.x))
	for cell in footprint:
		for unit in after["units"]:
			if unit is Dictionary and ids.has(str(unit.get("id", ""))) and unit.get("coord") is Vector2i and Footprint.contains(unit, cell): return str(unit["id"])
	return str(action.get("target_id", ""))


## `Script.function` of the AI rule that asked for the draw, or "" for a non-AI draw.
func _site(stack: Array) -> String:
	for frame in stack:
		var script := str(frame.get("source", "")).get_file().get_basename()
		var function := str(frame.get("function", ""))
		if script == "export_enemy_turns": continue
		if script == "CoreCombatRules" and function in ["_rand_range", "native_draw"]: continue
		if function == "_draw": continue
		return "%s.%s" % [script, function] if script in AI_SOURCES else ""
	return ""


func _strip_draws(turns: Array) -> Array:
	var out: Array = []
	for turn in turns:
		var copy: Dictionary = turn.duplicate(true)
		for action in copy["actions"]: action.erase("draws")
		copy.erase("rng")
		out.append(copy)
	return out


func _settle_rewards(loop: Dictionary) -> Dictionary:
	var next := loop
	var guard := 0
	while Loop.loot_waiting(next) and guard < 8:
		guard += 1
		var settlement: Dictionary = next.get("settlement", {})
		next = Loop.finish_rewards(next, int(settlement.get("sequence", 0)), int(settlement.get("revision", 0)), true)
	for unit in next["units"]:
		if int(unit.get("pending_stat_points", 0)) > 0 and bool(unit.get("player_commandable", false)):
			next = Loop.allocate_growth(next, str(unit["id"]), {"con": int(unit["pending_stat_points"])})
	return next


## One player turn from the plan (the selected unit; see trace_battle051_ai.gd). A rejected
## move or an absent attack target falls back to Wait.
func _player_turn(loop: Dictionary, commands: Array, source: Variant) -> Dictionary:
	var next := loop
	var unit_id := str(next.get("selected_unit_id", ""))
	for command in commands:
		var parts := str(command).split(":")
		var verb := parts[0]
		if verb == "move" and parts.size() > 1:
			var xy := parts[1].split("/")
			var cell := Vector2i(int(xy[0]), int(xy[1]))
			next = Loop.choose_command(next, "move")
			var moved := Loop.move_unit_to(next, cell)
			next = moved if Loop._unit(moved, unit_id)["coord"] == cell else Loop.cancel_interaction(next)
		elif verb in ["attack", "special"] and parts.size() > 1:
			var xy := parts[1].split("/")
			if verb == "special":
				next = Loop.choose_command(next, "special")
				var options := Loop.special_options(next, unit_id)
				if options.is_empty():
					next = Loop.cancel_interaction(next)
					break
				next = Loop.choose_special(next, str(options[0]["id"] if options[0] is Dictionary else options[0]))
			else:
				next = Loop.choose_command(next, "attack")
			var hit := Loop.attack_coord(next, Vector2i(int(xy[0]), int(xy[1])), source)
			if str(hit.get("interaction", "")) in ["attack_select", "special_select"]:
				next = Loop.cancel_interaction(hit)
				break
			next = _settle_rewards(hit)
			if Loop.action_exhausted(next): next = Loop.finish_exhausted_action(next)
			return next
		elif verb == "wait":
			break
	return Loop.begin_wait_resolution(next)


func _load_lines(path: String) -> Array:
	var out: Array = []
	for line in FileAccess.get_file_as_string(path).split("\n", false):
		var parsed: Variant = JSON.parse_string(line)
		if parsed is Dictionary and str(parsed.get("format", "")) == FORMAT: out.append(_integers(parsed))
	return out


## JSON.parse_string reads every number as a float; the format's numbers are integers.
func _integers(value: Variant) -> Variant:
	if value is float: return int(value)
	if value is Array: return value.map(func(item): return _integers(item))
	if value is Dictionary:
		var out := {}
		for key in value: out[key] = _integers(value[key])
		return out
	return value


func _expected_actions(expect: Array, round_number: int) -> Array:
	for turn in expect:
		if int(turn.get("turn", -1)) == round_number: return turn.get("actions", [])
	return []


## Actors an expectation round leaves out on purpose (optional "skip": [id] beside the
## format keys, e.g. a unit the other side did not report); their actions are not compared.
func _skipped(expect: Array, round_number: int) -> Array:
	for turn in expect:
		if int(turn.get("turn", -1)) == round_number: return turn.get("skip", [])
	return []


## "" when the action agrees with the expectation, "done" once past the expected rounds,
## else a description of the first difference.
func _expect_step(expect: Array, round_number: int, index: int, actual: Dictionary) -> String:
	var last := 0
	for turn in expect: last = maxi(last, int(turn.get("turn", 0)))
	if round_number > last: return "done"
	var wanted := _expected_actions(expect, round_number)
	# Every expected round but the last lists all its NPC actions; the last may be a prefix.
	if index >= wanted.size(): return "done" if round_number == last else "extra action %s" % str(actual.get("actor", ""))
	return _difference(wanted[index], actual)


func _difference(wanted: Dictionary, actual: Dictionary) -> String:
	for key in ["actor", "from", "to", "action", "target"]:
		# A recorded Wait cannot show the held pursuit target: null there means "not observed".
		if key == "target" and wanted.get("action") == "wait" and wanted.get("target") == null: continue
		if JSON.stringify(wanted.get(key)) != JSON.stringify(actual.get(key)):
			return "%s want=%s got=%s" % [key, JSON.stringify(wanted.get(key)), JSON.stringify(actual.get(key))]
	if wanted.get("skill") != null and JSON.stringify(wanted.get("skill")) != JSON.stringify(actual.get("skill")):
		return "skill want=%s got=%s" % [JSON.stringify(wanted.get("skill")), JSON.stringify(actual.get("skill"))]
	if not (wanted.get("draws", []) as Array).is_empty() and JSON.stringify(wanted["draws"]) != JSON.stringify(actual.get("draws")):
		return "draws differ"
	return ""


func _compare(turns: Array, expect: Array) -> Array:
	var lines: Array = []
	var agree := 0
	var total := 0
	for wanted_turn in expect:
		var round_number := int(wanted_turn.get("turn", 0))
		var actual: Array = []
		for turn in turns:
			if int(turn["turn"]) == round_number:
				actual = turn["actions"].filter(func(a): return not str(a["actor"]) in wanted_turn.get("skip", []))
		var wanted: Array = wanted_turn.get("actions", [])
		for i in wanted.size():
			total += 1
			var want: Dictionary = wanted[i]
			var got: Dictionary = actual[i] if i < actual.size() else {}
			var diff := _difference(want, got) if not got.is_empty() else "missing"
			if diff == "": agree += 1
			lines.append("TURNDUMP_MATCH turn=%d #%d %s %s %s->%s %s | %s" % [round_number, i + 1, "OK  " if diff == "" else "DIFF",
				str(want.get("actor", "")).trim_prefix("actor"), JSON.stringify(want.get("from")), JSON.stringify(want.get("to")),
				"%s %s" % [str(want.get("action", "")), str(want.get("target", "")).trim_prefix("actor") if want.get("target") != null else "-"],
				"same" if diff == "" else diff])
	lines.append("TURNDUMP_MATCH total agree=%d/%d" % [agree, total])
	return lines


func _search(prep: Dictionary, opts: Dictionary, expect: Array) -> void:
	var seeds: Array = []
	for part in str(opts["search"]).split(",", false):
		var span := part.split("-")
		for seed in range(int(span[0]), int(span[1] if span.size() > 1 else span[0]) + 1): seeds.append(seed)
	var total := 0
	var record := false
	for turn in expect:
		total += (turn.get("actions", []) as Array).size()
		for action in turn.get("actions", []):
			if not (action.get("draws", []) as Array).is_empty(): record = true
	var best := -1
	var best_seeds: Array = []
	var histogram := {}
	var full: Array = []
	for seed in seeds:
		var trial := opts.duplicate()
		trial["ai-seed"] = seed
		trial.erase("ai-state")
		var run := _play(prep, trial, record, expect)
		if not str(run["error"]).is_empty():
			print("TURNDUMP error seed=%d %s" % [seed, run["error"]])
			return
		var matched := int(run["matched"])
		histogram[matched] = int(histogram.get(matched, 0)) + 1
		if matched > best:
			best = matched
			best_seeds = [seed]
		elif matched == best and best_seeds.size() < 16:
			best_seeds.append(seed)
		if matched == total: full.append(seed)
	var keys := histogram.keys()
	keys.sort()
	var parts: Array = []
	for key in keys: parts.append("%d:%d" % [key, histogram[key]])
	print("TURNDUMP_SEARCH seeds=%s tried=%d expected=%d best_prefix=%d best_seeds=%s full_match=%d prefix_histogram=%s" % [str(opts["search"]), seeds.size(), total, best, JSON.stringify(best_seeds), full.size(), " ".join(parts)])
