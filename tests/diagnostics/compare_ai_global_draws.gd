extends SceneTree

## Diagnostic, not a gate: the remake's AI draws on the global stream against the original's
## emulated enemy turn (docs/evidence_packets/static_reverse/original_enemy_turn.json turn 0,
## `hsl generate enemy_turn`), action by action.
##
##   tools/godot.sh --headless --script res://tests/diagnostics/compare_ai_global_draws.gd
##
## Board: battle 051 at the recorded first-control board (recorded_round_boards.json
## `first_control`, the board tests/diagnostics/export_enemy_turns.gd `--state first_control` loads:
## template roster, recorded speeds and positions, resume after Leonard). The global words
## start at the oracle turn's [956367880, 2292745173], the damage words at the oracle's.
##
## Two runs:
##   chained   the remake plays the round on its own from the oracle's words (step_ai_turn,
##             its own queue). Once one action draws differently the streams part, so this
##             only reports how many whole actions agree before the first difference.
##   reseated  before each oracle action k the remake is put where the original was: the
##             global／damage words the oracle had at k (replayed from its own draws), the
##             round, and the positions and HP the oracle's earlier actions left; then the
##             oracle's actor takes its turn (`_ai_take_turn`, no queue). Action k's draws
##             are compared on their own: x/11.
##
## Draws are compared as (original site, bound) tokens: a remake draw is named by the
## original site its rule module cites (SITE_OF); the original's direct raw draws at the
## coin sites 0x40bd4f／0x41385d／0x4136ba read the low bit, which is what the remake's
## rand(2) = (r & 0xffff) % 2 reads, so both are the token `bit` (same step, same value).
## A mismatch is classified at its first differing token:
##   modulus     the same original site with another bound
##   draw_count  one side draws at a site the other does not reach in the rest of the
##               action (a skipped／extra draw; includes sites the remake never draws at)
##   branch      both sides still draw at each other's sites, in another order (another path)
##   injection   the original's state could not be reproduced (actor missing／origin differs)
## Output: AIDRAW_ACTION／AIDRAW_SEQ per action, AIDRAW_SITE per original site (draw totals
## over the 11 reseated actions), one AIDRAW_COMPARE summary line.

const Loop = preload("res://game/sim/loop/BattlePlayLoop.gd")
const LoopAI = preload("res://game/sim/loop/BattleLoopAI.gd")
const BattleScenario = preload("res://game/sim/BattleScenario.gd")
const CoreTurnQueue = preload("res://game/sim/CoreTurnQueue.gd")
const GlobalRandom = preload("res://game/sim/GlobalRandomStream.gd")
const DamageRandom = preload("res://game/sim/DamageRandomStream.gd")

const ORACLE := "res://docs/evidence_packets/static_reverse/original_enemy_turn.json"
const BOARDS := "res://docs/evidence_packets/runtime_observations/battle_051_ai_moves/recorded_round_boards.json"
const BOARD_KEY := "first_control"
const SCENARIO := "res://content/battles/battle_051.json"
const RAW := -1
## Original sites whose direct raw draw is read as its low bit.
const COIN_SITES := ["0x40bd4f", "0x41385d", "0x4136ba"]
## Remake draw site → the original site its module cites (rule provenance and comments).
const SITE_OF := {
	"AIDecisionRules.select_target": "0x40bd4f",        # 0x40bb80 scan, retain-old-candidate coin
	"AIPriorityRules.choose_check": "0x440db5",         # 0x440db1..0x440e3d check rolls
	"AIPriorityRules.self_recovery": "0x40c138",        # 0x40c110 self-HP threshold 12+rand(18)
	"AIPriorityRules.low_hp_target": "0x40c061",        # 0x40bf70 dying-foe scan 12+rand(18)
	"AIDecisionRules.select_action": "0x40c58d",        # 0x40c570 action category
	"AINavigationRules._nearest_stoppable": "0x41385d", # 0x413740 refinement tie coin (rand(100) crowd skip: 0x413889)
	"AINavigationRules.attack_station": "0x4136ba",     # 0x413390 station sort coin (rand(99) reposition: 0x440b2c)
}


## The AI source for one action: draws from its own copy of the global words and logs
## every bound, value and the remake frame that asked.
class Recorder:
	var state := {}
	var log: Array = []

	func _init(words: Array) -> void:
		state = {GlobalRandom.LOOP_KEY: words.duplicate()}

	func draw(n: int) -> int:
		var value := GlobalRandom.loop_draw(state, n)
		log.append({"n": RAW if n < 0 else n, "value": value, "site": _site(get_stack())})
		return value

	static func _site(stack: Array) -> String:
		for frame in stack:
			var script := str(frame.get("source", "")).get_file().get_basename()
			var function := str(frame.get("function", ""))
			if script in ["compare_ai_global_draws", "GlobalRandomStream", "DamageRandomStream"]: continue
			if script == "CoreCombatRules" and function in ["_rand_range", "native_draw"]: continue
			if function in ["_draw", "<anonymous lambda>"]: continue
			return "%s.%s:%d" % [script, function, int(frame.get("line", 0))]
		return "?"


var site_totals := {}


func _initialize() -> void:
	var oracle: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(ORACLE))
	var turn: Dictionary = oracle["turns"][0]
	var board: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(BOARDS))[BOARD_KEY]
	var start := _board(board)
	if not str(start.get("error", "")).is_empty():
		print("AIDRAW error %s" % start["error"])
		quit(1)
		return
	var base: Dictionary = start["loop"]
	base[GlobalRandom.LOOP_KEY] = GlobalRandom.from_words(turn["rng"]["global"])
	base[DamageRandom.LOOP_KEY] = DamageRandom.from_words(turn["rng"]["damage"])
	var actions: Array = turn["actions"]
	var metas: Array = turn["meta"]["actions"]
	var chained := _chained(base, actions)
	var matched := 0
	var decisions := 0
	var classes := {}
	var words := GlobalRandom.from_words(turn["rng"]["global"])
	var damage := DamageRandom.from_words(turn["rng"]["damage"])
	for k in range(actions.size()):
		var expected: Dictionary = actions[k]
		var row := _reseated(base, expected, words, damage, actions.slice(0, k), metas.slice(0, k), int(metas[k]["round"]))
		var oracle_tokens := _oracle_tokens(expected)
		var verdict := _classify(oracle_tokens, row["tokens"], row["injection"])
		if verdict["class"] == "match": matched += 1
		if row["decision"] == _decision(expected): decisions += 1
		classes[verdict["class"]] = int(classes.get(verdict["class"], 0)) + 1
		_tally(oracle_tokens, "oracle")
		_tally(row["tokens"], "remake")
		var at := int(verdict["at"])
		print("AIDRAW_ACTION k=%d actor=%s class=%s at=%d oracle_site=%s remake_site=%s draws=%d/%d decision_oracle=%s decision_remake=%s injection=%s" % [
			k, expected["actor"], verdict["class"], at, _token_label(oracle_tokens, at), _remake_label(row, at),
			oracle_tokens.size(), row["tokens"].size(), _decision(expected), row["decision"], ",".join(row["injection"])])
		print("AIDRAW_SEQ k=%d oracle %s" % [k, _compact(oracle_tokens)])
		print("AIDRAW_SEQ k=%d remake %s" % [k, _compact(row["tokens"])])
		# Carry the original's streams forward to the next action.
		for draw in expected["draws"]:
			if str(draw["stream"]) == "global": words = _step(words, draw)
			else: damage = _step(damage, draw)
	var sites := site_totals.keys()
	sites.sort()
	for site in sites:
		print("AIDRAW_SITE site=%s oracle=%d remake=%d remake_from=%s" % [site, int(site_totals[site].get("oracle", 0)), int(site_totals[site].get("remake", 0)), _remake_of(site)])
	print("AIDRAW_COMPARE battle=051 turn=1 board=%s matched=%d/%d classes=%s decisions_matched=%d/%d chained_prefix_actions=%d chained_first_divergence=%s" % [
		BOARD_KEY, matched, actions.size(), JSON.stringify(classes), decisions, actions.size(), int(chained["prefix"]), chained["divergence"]])
	quit(0)


## create → opening growth → recorded board → begin_battle (tests/diagnostics/export_enemy_turns.gd
## `_prepare`／`_inject` for the keys this board uses): "growth": false births with adjust_level
## [0, 0] (the referee's growth false, lane LETHALITY) unless the board sets "speed", which keeps
## the template roster — first_control does, so its roster is unchanged.
func _board(state: Dictionary) -> Dictionary:
	var scenario := BattleScenario.load_file(SCENARIO)
	if not bool(scenario.get("ok", false)): return {"error": "scenario_load"}
	var loop := Loop.create([], "", scenario, 1)
	if not bool(state.get("growth", true)) and not state.has("speed"):
		for unit in loop["units"]:
			if unit.get("growth_profile", {}).get("allocation") == "manual": continue
			var insertion: Dictionary = unit.get("script_insert", {}).duplicate(true)
			insertion["adjust_level"] = [0, 0]
			unit["script_insert"] = insertion
	if bool(state.get("growth", true)) or not state.has("speed"): loop = Loop.initialize_roster_growth(loop)
	var speeds: Dictionary = state.get("speed", {})
	var coords: Dictionary = state.get("units", {})
	for unit in loop["units"]:
		var short := str(unit["id"]).trim_prefix("actor")
		for key in [short, str(unit["id"])]:
			if speeds.has(key): unit["live_speed"] = int(speeds[key])
			if coords.has(key): unit["coord"] = Vector2i(int(coords[key][0]), int(coords[key][1]))
	loop["turn_queue"] = CoreTurnQueue.rebuild(Loop._queue_actors(loop))
	if state.has("resume_after"):
		var slots: Array = loop["turn_queue"]["slots"]
		for i in slots.size():
			if str(slots[i]["id"]) == str(state["resume_after"]): loop["turn_queue"]["index"] = i + 1
	if not bool(loop.get("scenario_ok", false)): return {"error": "scenario:%s" % str(loop.get("scenario_error", ""))}
	loop = Loop._resolve_outcome(loop)
	return {"loop": Loop.begin_battle(loop)}


## The remake plays on alone from the oracle's words: how many whole actions agree.
func _chained(base: Dictionary, actions: Array) -> Dictionary:
	var loop := Loop.copy(base)
	var recorder := Recorder.new(loop[GlobalRandom.LOOP_KEY])
	var source := Callable(recorder, "draw")
	var prefix := 0
	for k in range(actions.size()):
		var expected: Dictionary = actions[k]
		if str(loop.get("interaction", "")) != "ai_resolving": return {"prefix": prefix, "divergence": "k=%d_remake_stopped_at_%s" % [k, str(loop.get("interaction", ""))]}
		var mark := recorder.log.size()
		loop = Loop.step_ai_turn(loop, source)
		var act: Dictionary = loop.get("last_ai_action", {})
		if str(act.get("actor_id", "")) != str(expected["actor"]):
			return {"prefix": prefix, "divergence": "k=%d_actor_remake=%s_oracle=%s" % [k, str(act.get("actor_id", "")), expected["actor"]]}
		var tokens := _remake_tokens(recorder.log.slice(mark))
		var verdict := _classify(_oracle_tokens(expected), tokens, [])
		if verdict["class"] != "match" or _act_decision(act) != _decision(expected):
			return {"prefix": prefix, "divergence": "k=%d_%s_%s_at_draw_%d(oracle=%s,remake=%s)" % [k, act["actor_id"], verdict["class"], int(verdict["at"]), _token_label(_oracle_tokens(expected), int(verdict["at"])), _token_label(tokens, int(verdict["at"]))]}
		prefix += 1
	return {"prefix": prefix, "divergence": "none"}


## Action k with the remake put where the original was before it.
func _reseated(base: Dictionary, expected: Dictionary, words: Array, damage: Array, earlier: Array, metas: Array, round_number: int) -> Dictionary:
	var loop := Loop.copy(base)
	var injection: Array = []
	for j in range(earlier.size()):
		var mover := Loop._unit(loop, str(earlier[j]["actor"]))
		if not mover.is_empty(): mover["coord"] = Vector2i(int(earlier[j]["to"][0]), int(earlier[j]["to"][1]))
		var hp: Dictionary = metas[j].get("hp", {})
		for id in hp:
			var hurt := Loop._unit(loop, str(id))
			if not hurt.is_empty(): hurt["hp"] = int(hurt["hp"]) + int(hp[id])
	loop["turn"] = int(base.get("turn", 1)) + round_number - 1
	loop["turn_queue"]["round"] = int(base["turn_queue"].get("round", 1)) + round_number - 1
	loop[GlobalRandom.LOOP_KEY] = words.duplicate()
	loop[DamageRandom.LOOP_KEY] = damage.duplicate()
	var actor_id := str(expected["actor"])
	var actor := Loop._unit(loop, actor_id)
	if actor.is_empty(): return {"tokens": [], "log": [], "injection": ["missing_actor"], "decision": "-"}
	var origin := Vector2i(int(expected["from"][0]), int(expected["from"][1]))
	if actor["coord"] != origin:
		injection.append("origin_board%s_oracle%s" % [str(actor["coord"]).replace(" ", ""), str(origin).replace(" ", "")])
		actor["coord"] = origin
	var recorder := Recorder.new(words)
	var step: Dictionary = LoopAI._ai_take_turn(loop, actor_id, Callable(recorder, "draw"))
	var after: Dictionary = step.get("loop", loop)
	if after.get(GlobalRandom.LOOP_KEY) != loop[GlobalRandom.LOOP_KEY]: injection.append("draws_outside_source")
	return {"tokens": _remake_tokens(recorder.log), "log": recorder.log, "injection": injection, "decision": _act_decision(step.get("action", {}))}


## (original site, bound) per global draw of an oracle action.
func _oracle_tokens(action: Dictionary) -> Array:
	var out: Array = []
	for draw in action["draws"]:
		if str(draw["stream"]) != "global": continue
		var site := str(draw["site"])
		var bound := RAW if draw["n"] == null else int(draw["n"])
		out.append([site, "bit" if bound == RAW and site in COIN_SITES else _n(bound), site])
	return out


func _remake_tokens(log: Array) -> Array:
	var out: Array = []
	for draw in log:
		var name := str(draw["site"]).get_slice(":", 0)
		var site := str(SITE_OF.get(name, name))
		var bound := int(draw["n"])
		if name == "AINavigationRules._nearest_stoppable" and bound == 100: site = "0x413889"
		if name == "AINavigationRules.attack_station" and bound == 99: site = "0x440b2c"
		out.append([site, "bit" if bound == 2 and site in COIN_SITES else _n(bound), str(draw["site"])])
	return out


func _classify(oracle: Array, remake: Array, injection: Array) -> Dictionary:
	var at := 0
	while at < oracle.size() and at < remake.size() and _same(oracle[at], remake[at]): at += 1
	var ended := at == oracle.size() and at == remake.size()
	if not injection.is_empty(): return {"class": "injection", "at": -1 if ended else at}
	if ended: return {"class": "match", "at": -1}
	if at == oracle.size() or at == remake.size(): return {"class": "draw_count", "at": at}
	var o: Array = oracle[at]
	var r: Array = remake[at]
	if o[0] == r[0]: return {"class": "modulus", "at": at}
	var remake_sites := remake.slice(at).map(func(t): return t[0])
	var oracle_sites := oracle.slice(at).map(func(t): return t[0])
	if not remake_sites.has(o[0]) or not oracle_sites.has(r[0]): return {"class": "draw_count", "at": at}
	return {"class": "branch", "at": at}


func _same(a: Array, b: Array) -> bool:
	return a[0] == b[0] and a[1] == b[1]


func _tally(tokens: Array, side: String) -> void:
	for token in tokens:
		var row: Dictionary = site_totals.get(token[0], {})
		row[side] = int(row.get(side, 0)) + 1
		site_totals[token[0]] = row


func _remake_of(site: String) -> String:
	for name in SITE_OF:
		if SITE_OF[name] == site: return name
	return "-" if site.begins_with("0x") else site


func _token_label(tokens: Array, at: int) -> String:
	return "%s/%s" % [tokens[at][0], tokens[at][1]] if at >= 0 and at < tokens.size() else "end"


func _remake_label(row: Dictionary, at: int) -> String:
	var tokens: Array = row["tokens"]
	return "%s/%s(%s)" % [tokens[at][0], tokens[at][1], tokens[at][2]] if at >= 0 and at < tokens.size() else "end"


func _n(n: int) -> String:
	return "raw" if n == RAW else str(n)


## Destination, whether it struck, and the target: the oracle's `attack`／`wait` against the
## remake's attack／move_then_attack and move／wait kinds.
func _decision(action: Dictionary) -> String:
	var struck := str(action["action"]) in ["attack", "magic", "skill", "item"]
	return "(%d,%d)_%s_%s" % [int(action["to"][0]), int(action["to"][1]), "strike" if struck else "no_strike", str(action.get("target", "")) if struck else "-"]


func _act_decision(act: Dictionary) -> String:
	if act.is_empty(): return "-"
	var to: Variant = act.get("to", act.get("from", Vector2i(-1, -1)))
	if not (to is Vector2i): to = act.get("from", Vector2i(-1, -1))
	var struck := str(act.get("kind", "")) in ["attack", "move_then_attack", "skill", "move_then_skill", "item"]
	return "(%d,%d)_%s_%s" % [int(to.x), int(to.y), "strike" if struck else "no_strike", str(act.get("target_id", "")) if struck else "-"]


func _step(state: Array, draw: Dictionary) -> Array:
	var bound: int = RAW if draw["n"] == null else int(draw["n"])
	return (GlobalRandom.raw(state) if bound < 0 else GlobalRandom.rand(state, bound))["state"]


## Runs of the same token collapsed to `site/bound×count`.
func _compact(tokens: Array) -> String:
	var parts: Array = []
	var i := 0
	while i < tokens.size():
		var j := i
		while j + 1 < tokens.size() and _same(tokens[j + 1], tokens[i]): j += 1
		parts.append("%s/%s%s" % [tokens[i][0], tokens[i][1], ("×%d" % (j - i + 1)) if j > i else ""])
		i = j + 1
	return " ".join(parts)
