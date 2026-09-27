extends SceneTree

## Measures what copying a battle loop costs on the largest formal battles: bytes of the
## whole loop versus its read-only configuration (BattlePlayLoop.CONFIG_SHARED) versus
## the state that remains, the ten largest top-level keys after create(), the `units`
## bytes and the unit keys that hold them, the wall time of `loop.duplicate(true)` against
## `BattlePlayLoop.copy`, and the wall time of one complete headless round (every AI step
## plus the greedy autoplay policy for player turns) with the number of whole-loop copies
## it made (BattleLoopConfig.copy_count) and the share of the round they cost. It then
## times what the round really spends its time on: BattleLoopAI.prepare_ai_turn (the
## read-only preflight of every living AI unit, per phase) and, at the round's first player
## menu, one lookahead decision of tests/support/AutoplayBrain.gd (copies, simulations,
## milliseconds). Diagnostic only — nothing here is a rule, a gate or evidence about the
## original. Numbers: docs/architecture/BATTLE_CONFIG_STATE.md §量化.
##
##   tools/godot.sh --headless --script res://tests/measure_loop_copy.gd            # levels 44 and 45
##   tools/godot.sh --headless --script res://tests/measure_loop_copy.gd -- 44 38   # chosen levels

const BattlePlayLoop = preload("res://game/sim/loop/BattlePlayLoop.gd")
const BattleLoopConfig = preload("res://game/sim/BattleLoopConfig.gd")
const BattleLoopAI = preload("res://game/sim/loop/BattleLoopAI.gd")
const BattleScenario = preload("res://game/sim/BattleScenario.gd")
const Autoplay = preload("res://tests/support/Autoplay.gd")
const AutoplayBrain = preload("res://tests/support/AutoplayBrain.gd")
const BattleOutcome = preload("res://game/sim/BattleOutcome.gd")

const DEFAULT_LEVELS := ["44", "45"]
const COPY_REPEATS := 20
const TOP_UNIT_KEYS := 8
## `_prepare_ai_turn`'s phases in its own order; timed one by one on a shared `work` dict.
static var PREPARE_PHASES := {"preflight": BattleLoopAI._ai_preflight_actor, "target_rows": BattleLoopAI._ai_target_rows, "approach_routes": BattleLoopAI._ai_approach_routes, "call_state": BattleLoopAI._ai_call_state, "action_candidates": BattleLoopAI._ai_action_candidates}


func _initialize() -> void:
	var levels: Array = Array(OS.get_cmdline_user_args())
	if levels.is_empty():
		levels = DEFAULT_LEVELS
	for level in levels:
		_measure(str(level))
	quit(0)


func _measure(level: String) -> void:
	var path := "res://content/battles/battle_%03d.json" % int(level)
	var loop := BattlePlayLoop.begin_battle(BattlePlayLoop.initialize_roster_growth(BattlePlayLoop.create([], "", BattleScenario.load_file(path))))
	if not bool(loop.get("scenario_ok", false)):
		print("LOOP_COPY_MEASURE level=%s error=%s" % [level, str(loop.get("scenario_error", ""))])
		return
	var total := var_to_bytes(loop).size()
	var config := 0
	var sizes: Array = []
	for key in loop:
		var bytes := var_to_bytes(loop[key]).size()
		sizes.append([bytes, str(key)])
		if BattlePlayLoop.CONFIG_SHARED.has(key):
			config += bytes
	sizes.sort_custom(func(a, b): return a[0] > b[0])
	var top: Array = []
	for row in sizes.slice(0, 10):
		top.append("%s=%d%s" % [row[1], row[0], "*" if BattlePlayLoop.CONFIG_SHARED.has(row[1]) else ""])
	var units: Array = loop["units"]
	print("LOOP_COPY_MEASURE level=%s units=%d keys=%d total_bytes=%d config_bytes=%d state_bytes=%d" % [level, units.size(), loop.size(), total, config, total - config])
	print("LOOP_COPY_MEASURE level=%s top_keys(*=shared)=%s" % [level, " ".join(top)])
	var units_bytes := var_to_bytes(units).size()
	print("LOOP_COPY_MEASURE level=%s units_bytes=%d per_unit=%d top_unit_keys=%s" % [level, units_bytes, units_bytes / maxi(units.size(), 1), " ".join(_unit_key_sizes(units))])
	var started := Time.get_ticks_usec()
	for _index in range(COPY_REPEATS):
		var _deep := loop.duplicate(true)
	var deep_usec := (Time.get_ticks_usec() - started) / COPY_REPEATS
	started = Time.get_ticks_usec()
	for _index in range(COPY_REPEATS):
		var _shared := BattlePlayLoop.copy(loop)
	var copy_usec := (Time.get_ticks_usec() - started) / COPY_REPEATS
	print("LOOP_COPY_MEASURE level=%s duplicate_true_usec=%d copy_usec=%d" % [level, deep_usec, copy_usec])
	var prepare := _time_ai_prepare(loop)
	BattleLoopConfig.copy_count = 0
	var round_result := _play_one_round(loop)
	var copies: int = BattleLoopConfig.copy_count
	var copy_msec := copies * copy_usec / 1000
	var round_msec := int(round_result["msec"])
	print("LOOP_COPY_MEASURE level=%s round_steps=%d round_msec=%d copies=%d copy_msec=%d copy_share=%.1f%% interaction=%s" % [level, int(round_result["steps"]), round_msec, copies, copy_msec, 100.0 * copy_msec / maxf(round_msec, 1.0), str(round_result["interaction"])])
	print("LOOP_COPY_MEASURE level=%s ai_prepare_units=%d ai_prepare_msec=%d ai_prepare_share=%.1f%% phases_msec=%s" % [level, int(prepare["units"]), int(prepare["msec"]), 100.0 * int(prepare["msec"]) / maxf(round_msec, 1.0), str(prepare["phases"])])
	var lookahead := _time_lookahead_decision(loop)
	print("LOOP_COPY_MEASURE level=%s lookahead_actor=%s lookahead_copies=%d lookahead_simulations=%d lookahead_msec=%d" % [level, str(lookahead["actor"]), int(lookahead["copies"]), int(lookahead["simulations"]), int(lookahead["msec"])])


## Bytes of each unit key summed over the roster, largest first ("key=bytes").
static func _unit_key_sizes(units: Array) -> Array:
	var totals := {}
	for unit in units:
		for key in unit:
			totals[key] = int(totals.get(key, 0)) + var_to_bytes(unit[key]).size()
	var rows: Array = []
	for key in totals:
		rows.append([int(totals[key]), str(key)])
	rows.sort_custom(func(a, b): return a[0] > b[0])
	var out: Array = []
	for row in rows.slice(0, TOP_UNIT_KEYS):
		out.append("%s=%d" % [row[1], row[0]])
	return out


## Runs BattleLoopAI.prepare_ai_turn's phases for every living AI unit on a copy and
## sums their wall time per phase (the preflight is read-only; the copy keeps `loop`
## pristine for the round that follows).
static func _time_ai_prepare(loop: Dictionary) -> Dictionary:
	var probe := BattlePlayLoop.copy(loop)
	var phases := {}
	for name in PREPARE_PHASES:
		phases[name] = 0
	var units := 0
	var started := Time.get_ticks_usec()
	for unit in probe["units"]:
		if bool(unit.get("player_commandable", false)) or not BattlePlayLoop.Presence.living(unit):
			continue
		var work := {}
		var failed := false
		for name in PREPARE_PHASES:
			var phase_started := Time.get_ticks_usec()
			var failure: Dictionary = (PREPARE_PHASES[name] as Callable).call(probe, str(unit["id"]), work)
			phases[name] = int(phases[name]) + (Time.get_ticks_usec() - phase_started) / 1000
			if not failure.is_empty():
				failed = true
				break
		if not failed:
			units += 1
	return {"units": units, "msec": (Time.get_ticks_usec() - started) / 1000, "phases": phases}


## Advances the round to its first player menu and lets a lookahead AutoplayBrain take one
## decision there: whole-loop copies, simulated rounds and wall time of that decision.
static func _time_lookahead_decision(loop: Dictionary) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	var current := loop
	var steps := 0
	while str(current.get("interaction", "")) == "ai_resolving" and steps < Autoplay.STEP_LIMIT_PER_ROUND:
		steps += 1
		var stepped := BattlePlayLoop.step_ai_turn(current, rng)
		if stepped == current:
			break
		current = stepped
	if str(current.get("interaction", "")) != "action_menu":
		return {"actor": "", "copies": 0, "simulations": 0, "msec": 0}
	var brain := AutoplayBrain.create(AutoplayBrain.MODE_LOOKAHEAD)
	BattleLoopConfig.copy_count = 0
	var started := Time.get_ticks_usec()
	AutoplayBrain.take_player_action(brain, current, rng)
	return {"actor": str(current.get("selected_unit_id", "")), "copies": BattleLoopConfig.copy_count, "simulations": int(brain["simulations"]), "msec": (Time.get_ticks_usec() - started) / 1000}


## Runs rule steps until the round counter advances (or the battle decides / stalls).
static func _play_one_round(loop: Dictionary) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	var first_round := int(loop.get("turn", 1))
	var steps := 0
	var started := Time.get_ticks_msec()
	var current := loop
	while int(current.get("turn", 1)) == first_round and not BattleOutcome.decided(current) and steps < Autoplay.STEP_LIMIT_PER_ROUND:
		steps += 1
		if BattlePlayLoop.loot_waiting(current):
			var settlement: Dictionary = current["settlement"]
			current = BattlePlayLoop.finish_rewards(current, int(settlement["sequence"]), int(settlement["revision"]), false, true)
			continue
		match str(current.get("interaction", "")):
			"action_menu":
				var step := Autoplay.take_player_action(current, rng)
				if str(step["action"]) == "":
					break
				current = step["loop"]
			"ai_resolving":
				var stepped := BattlePlayLoop.step_ai_turn(current, rng)
				if stepped == current:
					break
				current = stepped
			_:
				break
	return {"steps": steps, "msec": Time.get_ticks_msec() - started, "interaction": str(current.get("interaction", ""))}
