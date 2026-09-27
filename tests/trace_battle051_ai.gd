extends SceneTree

## Diagnostic trace of the first battle (level 51) on the pure PlayLoop: the same
## BattlePlayLoop.create／initialize_roster_growth／begin_battle path the product scene
## runs (no opening presentation — the level-51 opening moves no unit but Leonard, whose
## walk is already the scenario coordinate), then Leonard's turns replayed from a plan of
## public commands and every AI action printed one line each (actor, from→to, target,
## kind, HP after). Diagnostic only, not a gate: it answers "where does the remake send
## each AI unit" for docs/evidence_packets/runtime_observations/battle_051_ai_moves/.
##
##   tools/godot.sh --headless --script res://tests/trace_battle051_ai.gd -- [seed] [plan]
##
## `plan`: Leonard's turns separated by `;`, each a comma list of `move:X/Y`,
## `attack:X/Y`, `special:X/Y` (氣刃斬), `item:SLOT` (use on self), `wait`. A turn beyond
## the plan waits. Default plan: Leonard's first three turns in the original recording
## (battle_051_ai_moves README); later turns wait.

const BattlePlayLoop = preload("res://game/sim/loop/BattlePlayLoop.gd")
const BattleScenario = preload("res://game/sim/BattleScenario.gd")
const BattleOutcome = preload("res://game/sim/BattleOutcome.gd")

const SCENARIO := "res://content/battles/battle_051.json"
const MAX_STEPS := 400
const RECORDED_PLAN := "move:15/21,wait;move:15/16,wait;move:15/11,attack:14/11"

var rng := RandomNumberGenerator.new()
var step := 0


func _initialize() -> void:
	var args := Array(OS.get_cmdline_user_args())
	var seed := int(args[0]) if args.size() > 0 else 1
	var plan_text := str(args[1]) if args.size() > 1 else RECORDED_PLAN
	var plan: Array = []
	for turn in plan_text.split(";", false): plan.append(Array(turn.split(",", false)))
	rng.seed = seed
	var scenario := BattleScenario.load_file(SCENARIO)
	var loop := BattlePlayLoop.create([], "", scenario, seed)
	loop = BattlePlayLoop.initialize_roster_growth(loop)
	print("TRACE51 seed=%d" % seed)
	_print_roster(loop)
	loop = BattlePlayLoop._resolve_outcome(loop)
	loop = BattlePlayLoop.begin_battle(loop)
	var turn_index := 0
	while step < MAX_STEPS:
		step += 1
		if BattleOutcome.decided(loop):
			print("TRACE51 outcome=%s round=%s" % [str(loop.get("battle_outcome", "")), str(loop.get("turn", ""))])
			break
		if not bool(loop.get("scenario_ok", false)):
			print("TRACE51 scenario_error=%s" % str(loop.get("scenario_error", "")))
			break
		loop = _settle_rewards(loop)
		var interaction := str(loop.get("interaction", ""))
		if interaction == "ai_resolving":
			var before := loop
			loop = BattlePlayLoop.step_ai_turn(loop, rng)
			_print_ai(before, loop)
			continue
		if interaction == "action_menu":
			var commands: Array = plan[turn_index] if turn_index < plan.size() else ["wait"]
			turn_index += 1
			loop = _player_turn(loop, commands)
			continue
		print("TRACE51 stop interaction=%s" % interaction)
		break
	quit(0)


func _print_roster(loop: Dictionary) -> void:
	for unit in loop["units"]:
		print("TRACE51 unit %s actor=%s role=%s coord=%s hp=%d/%d lv=%s speed=%s move=%s" % [unit["id"], unit["actor_id"], unit["battle_actor_role"], unit["coord"], int(unit["hp"]), int(unit["max_hp"]), str(unit.get("level", "")), str(unit.get("live_speed", "")), str(unit.get("move_point", ""))])
	var order: Array = []
	for slot in loop["turn_queue"].get("slots", []): order.append(str(slot.get("id", "")))
	print("TRACE51 queue %s" % ",".join(order))


func _hp_line(loop: Dictionary) -> String:
	var parts: Array = []
	for unit in loop["units"]:
		parts.append("%s@%d,%d:%d" % [unit["id"], unit["coord"].x, unit["coord"].y, int(unit["hp"])])
	return " ".join(parts)


func _print_ai(before: Dictionary, after: Dictionary) -> void:
	var action: Dictionary = after.get("last_ai_action", {})
	if after.get("last_ai_actions", []).size() == before.get("last_ai_actions", []).size():
		return
	var actor_id := str(action.get("actor_id", ""))
	var start: Vector2i = BattlePlayLoop._unit(before, actor_id).get("coord", Vector2i(-1, -1))
	var decision: Dictionary = action.get("ai_decision", {})
	var selection: Dictionary = decision.get("target_selection", {})
	var damage := ""
	var combat: Dictionary = after.get("last_combat", {})
	if int(combat.get("sequence", 0)) > int(before.get("last_combat", {}).get("sequence", 0)):
		damage = " combat=%s" % JSON.stringify(_combat_summary(combat))
	print("TRACE51 round=%s ai %s %s->%s kind=%s target=%s wait=%s reason=%s skill=%s%s" % [str(before.get("turn", "")), actor_id, start, action.get("to", start), str(action.get("kind", "")), str(action.get("target_id", action.get("toward", ""))), str(action.get("wait_reason", "")), str(selection.get("reason", "")), str(action.get("skill_name", action.get("skill_id", ""))), damage])
	print("TRACE51   board %s" % _hp_line(after))


func _combat_summary(combat: Dictionary) -> Dictionary:
	var out := {}
	for key in ["attacker_id", "defender_id", "damage", "hit", "counter_damage", "defender_hp_after", "attacker_hp_after", "skill_name"]:
		if combat.has(key): out[key] = combat[key]
	return out


func _settle_rewards(loop: Dictionary) -> Dictionary:
	var next := loop
	var guard := 0
	while BattlePlayLoop.loot_waiting(next) and guard < 8:
		guard += 1
		var settlement: Dictionary = next.get("settlement", {})
		next = BattlePlayLoop.finish_rewards(next, int(settlement.get("sequence", 0)), int(settlement.get("revision", 0)), true)
	for unit in next["units"]:
		if int(unit.get("pending_stat_points", 0)) > 0 and bool(unit.get("player_commandable", false)):
			next = BattlePlayLoop.allocate_growth(next, str(unit["id"]), {"con": int(unit["pending_stat_points"])})
	return next


func _player_turn(loop: Dictionary, commands: Array) -> Dictionary:
	var next := loop
	var leonard := BattlePlayLoop._unit(next, "leonard")
	print("TRACE51 round=%s player leonard@%s plan=%s" % [str(next.get("turn", "")), leonard["coord"], ",".join(commands)])
	for command in commands:
		var parts := str(command).split(":")
		var verb := parts[0]
		if verb == "move":
			var xy := parts[1].split("/")
			next = BattlePlayLoop.choose_command(next, "move")
			var moved := BattlePlayLoop.move_unit_to(next, Vector2i(int(xy[0]), int(xy[1])))
			if BattlePlayLoop._unit(moved, "leonard")["coord"] != Vector2i(int(xy[0]), int(xy[1])):
				print("TRACE51   move rejected %s cells=%s" % [parts[1], str(BattlePlayLoop.movement_cells(next, "leonard"))])
				next = BattlePlayLoop.cancel_interaction(next)
			else:
				next = moved
		elif verb in ["attack", "special"]:
			var xy := parts[1].split("/")
			if verb == "special":
				next = BattlePlayLoop.choose_command(next, "special")
				var options := BattlePlayLoop.special_options(next, "leonard")
				next = BattlePlayLoop.choose_special(next, str(options[0]["id"] if options[0] is Dictionary else options[0]))
			else:
				next = BattlePlayLoop.choose_command(next, "attack")
			var hit := BattlePlayLoop.attack_coord(next, Vector2i(int(xy[0]), int(xy[1])), rng)
			print("TRACE51   %s %s reject=%s combat=%s" % [verb, parts[1], str(hit.get("last_attack_reject", {})), JSON.stringify(_combat_summary(hit.get("last_combat", {})))])
			if str(hit.get("interaction", "")) in ["attack_select", "special_select"]:
				# The recorded target is not on this board: back out and Wait instead.
				next = BattlePlayLoop.cancel_interaction(hit)
				break
			next = _settle_rewards(hit)
			if BattlePlayLoop.action_exhausted(next): next = BattlePlayLoop.finish_exhausted_action(next)
			return next
		elif verb == "wait":
			break
	next = BattlePlayLoop.begin_wait_resolution(next)
	return next
