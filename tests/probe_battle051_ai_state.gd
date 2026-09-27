extends SceneTree

## Diagnostic state-injection probe for the first battle (level 51): puts the pure
## PlayLoop into a board recorded from the original run (unit coords, HP, deaths, held
## targets) and asks the remake AI for one unit's action on that board, so each original
## AI action can be compared without the cascade of earlier divergences. Diagnostic only,
## not a gate: it feeds docs/evidence_packets/runtime_observations/battle_051_ai_moves/.
##
##   tools/godot.sh --headless --script res://tests/probe_battle051_ai_state.gd -- CASES.json [seeds]
##
## CASES.json: an array of {"name", "actor", "units": {id: [x, y]}, "hp": {id: n},
## "dead": [id], "targets": {id: target_id}}; ids drop the "actor" prefix ("021_3").
## Each case runs once per seed (default 1..8) and prints the destination/target tally.

const BattlePlayLoop = preload("res://game/sim/loop/BattlePlayLoop.gd")
const BattleLoopAI = preload("res://game/sim/loop/BattleLoopAI.gd")
const BattleScenario = preload("res://game/sim/BattleScenario.gd")

const SCENARIO := "res://content/battles/battle_051.json"


func _initialize() -> void:
	var args := Array(OS.get_cmdline_user_args())
	var cases: Array = JSON.parse_string(FileAccess.get_file_as_string(str(args[0])))
	var seeds := int(args[1]) if args.size() > 1 else 8
	var scenario := BattleScenario.load_file(SCENARIO)
	var base := BattlePlayLoop.initialize_roster_growth(BattlePlayLoop.create([], "", scenario, 1))
	for case in cases:
		var tally := {}
		for seed in range(1, seeds + 1):
			var loop := _inject(base, case)
			var rng := RandomNumberGenerator.new()
			rng.seed = seed
			var actor_id := _id(str(case["actor"]))
			var step: Dictionary = BattleLoopAI.ai_take_turn(loop, actor_id, rng)
			var action: Dictionary = step.get("action", {})
			var key := "%s->%s %s %s" % [str(action.get("from", "")), str(action.get("to", action.get("from", ""))), str(action.get("kind", "")), str(action.get("target_id", action.get("toward", ""))).trim_prefix("actor")]
			if not bool(step.get("loop", {}).get("scenario_ok", true)): key = "error " + str(step["loop"].get("scenario_error", ""))
			tally[key] = int(tally.get(key, 0)) + 1
		print("PROBE51 %s | %s" % [str(case["name"]), JSON.stringify(tally)])
	quit(0)


func _id(short: String) -> String:
	return short if short == "leonard" else "actor" + short


func _inject(base: Dictionary, case: Dictionary) -> Dictionary:
	var loop := BattlePlayLoop.copy(base)
	var coords: Dictionary = case.get("units", {})
	var hps: Dictionary = case.get("hp", {})
	var dead: Array = case.get("dead", [])
	var targets: Dictionary = case.get("targets", {})
	for unit in loop["units"]:
		var short := str(unit["id"]).trim_prefix("actor")
		if coords.has(short): unit["coord"] = Vector2i(int(coords[short][0]), int(coords[short][1]))
		if hps.has(short): unit["hp"] = int(hps[short])
		if short in dead:
			unit["hp"] = 0
			unit["defeated"] = true
		if targets.has(short): unit["ai_target_id"] = _id(str(targets[short]))
	return loop
