extends "res://tests/support/TestSuite.gd"

## Winnability census (lane R6-L8): every registered battle of content/battles/campaign.json
## must have a script path to victory that the remake can actually take — independent of how
## well any bot plays. Read from the scenario's own compiled winfail program
## (WinfailCompiler) and the same condition reader the interpreter uses (WinfailConditions),
## over the battle's "cast": the units fielded at first control plus every actor its script
## can create (script_actor_source templates).
##
## A status is *fireable* when each leading condition can hold for some play: attack
## conditions name a unit that exists, an HPLow target reaches the threshold at the lowest
## HP it can stand at (an undead unit revives at 1 HP, BattleLoopCombat._undead_revives), a
## count of listed ids has enough countable ids, an arrival zone is reachable on foot with
## every mid-battle ClearWall open, round numbers are finite, static enemy objects the remake
## never destroys stay counted. From the statuses the STORY arms (plus STORY select events)
## the census follows the insert actions of fireable statuses; the battle is winnable in
## principle when a fireable win status, or a fireable event that hands off the campaign
## (actSetNextPlayLevelEvent: 73／78／900), is reached.
##
## Defect classes it guards, each over all battles:
## 1. HPLow threshold (static-derived, 0x450840 case 0x41): `ratio 0` holds at HP ≤ 1, so the
##    undead bosses of 41／59／75–79 and the undead-gated events of 30–37 can fire.
##    Ablation: the pre-R6-L8 reading (ratio 0 ⇒ HP ≤ 0) leaves 41／59／75／76／77／79 without a
##    win path and fails `_hp_low_undead_targets`.
## 2. Condition ids the remake cannot resolve (an unresolved token never counts): STORY029
##    renames 梅爾／凱文 to 1000／1001 with actChangePlayerID. Ablation: without the binding
##    the level-29 death events name nobody.
## 3. Missing script actors: a win path gated on a unit neither fielded nor creatable.
##    KNOWN_BLOCKED lists what is still open, with its reason; a battle leaving or entering
##    the list fails the suite. Lane R6-L10 fielded STORY037's guardians (066／067, the
##    pillar-5 chain to Enemy052) and level 80's 怨念體 068. Ablation: without those units
##    level 37 has no win path and level 80's wall event holds at first control.
## 4. Conditions on static enemy objects (drawn, never destroyed): KNOWN_STATIC_CONDITIONS.
## 5. Referenced-but-unbuilt actors: every SID_ENEMYnnn token a battle's WINFAIL statuses or
##    STORY actions name resolves to a unit of the cast (fielded, script template, or an
##    opening-only actor the STORY deletes) except KNOWN_UNBUILT.

const Loop = preload("res://game/sim/loop/BattlePlayLoop.gd")
const BattleScenario = preload("res://game/sim/BattleScenario.gd")
const CampaignProgress = preload("res://game/battle/runtime/CampaignProgress.gd")
const WinfailCompiler = preload("res://game/sim/WinfailCompiler.gd")
const WinfailConditions = preload("res://game/sim/WinfailConditions.gd")
const Grid = preload("res://game/sim/TacticalGridRules.gd")
const TerrainEdits = preload("res://game/sim/TerrainEditRules.gd")
const CoreTurnQueue = preload("res://game/sim/CoreTurnQueue.gd")
const BattleOutcome = preload("res://game/sim/BattleOutcome.gd")

## Round conditions beyond this never fire in play (WINFAIL030 events 7／8 wait for round 30000).
const ROUND_REACHABLE := 999
const HANDOFF_ACTION := "actSetNextPlayLevelEvent"
## Battles whose win path is still blocked in the remake, with the missing piece.
const KNOWN_BLOCKED := {}
## Conditions naming a static enemy object the remake draws without a unit (provisional
## boundary: static_enemy_counts in the scenario) — token per battle.
const KNOWN_STATIC_CONDITIONS := {}  # ACTORS100 (2026-09-27): Enemy101 hulls／Enemy100 doors are registered actors like the original's; no static conditions remain.
## Tokens a battle's scripts name that no unit of the cast answers to, with the reason.
const KNOWN_UNBUILT := {
	# Enemy101 船殼 hulls (12／26) and STORY018's 門 (Enemy100) became PLAYERS 100／101 actors in ACTORS100
	# (2026-09-27): pmALL door 0x40bb80, hull 0x850000 enemy target, no_attack 0x43f413, no_showshape 0x4420ef.
	# WINFAIL533's actCheckEnemy lists 024／027, classes its EVEF never places (counted as fallen,
	# 0x450840 case 0x26 — docs/evidence_packets/static_reverse/original_check_targets.md).
	"533": ["SID_ENEMY024", "SID_ENEMY027"],
}

var verbose := OS.get_environment("HSL_WINNABILITY_VERBOSE") != ""
## HPLow threshold the census reads (max_hp, ratio) -> HP; the ablation swaps in the old one.
var hp_low_threshold: Callable = WinfailConditions.hp_low_threshold
## Battle key -> [loop, scenario, arrival floods] of the first pass, reused by the ablations.
var boards := {}


func _init() -> void:
	tag = "WINNABILITY_CENSUS_TESTS"
	report_checks = true


func run() -> void:
	var campaign := CampaignProgress.load_campaign()
	var blocked := {}
	var static_conditions := {}
	var unbuilt := {}
	var battles := 0
	for key in campaign.get("battles", {}):
		var entry: Dictionary = campaign["battles"][key]
		if entry.has("kind"):
			continue
		battles += 1
		var scenario := BattleScenario.load_file(str(entry.get("scenario", "")))
		var loop := Loop.create([], "", scenario, 1)
		_assert_true(bool(loop.get("scenario_ok", false)), "battle %s creates a PlayLoop (%s)" % [key, str(loop.get("scenario_error", ""))])
		if not bool(loop.get("scenario_ok", false)):
			continue
		var cast := cast_battle(loop)
		boards[str(key)] = [loop, scenario, arrival_floods(cast, loop["winfail_script_rules"])]
		var report := census(loop, scenario, boards[str(key)][2])
		for problem in report["unresolved"]:
			check(false, "battle %s: %s" % [key, problem])
		for problem in report["hp_low"]:
			check(false, "battle %s: %s" % [key, problem])
		if report["path"].is_empty():
			blocked[str(key)] = true
		if not report["static_tokens"].is_empty():
			static_conditions[str(key)] = report["static_tokens"]
		var missing := unbuilt_tokens(loop, scenario)
		if not missing.is_empty():
			unbuilt[str(key)] = missing
		if verbose:
			print("WINNABILITY level=%s path=%s blocked_by=%s" % [key, ",".join(report["path"]), JSON.stringify(report["blocked_by"])])
	_assert_eq(battles, 128, "the census covers every registered battle")
	var known_blocked := KNOWN_BLOCKED.keys()
	known_blocked.sort()
	var found_blocked := blocked.keys()
	found_blocked.sort()
	_assert_eq(found_blocked, known_blocked, "battles with no remake path to victory are exactly KNOWN_BLOCKED")
	_assert_eq(static_conditions, KNOWN_STATIC_CONDITIONS, "conditions on static enemy objects are exactly KNOWN_STATIC_CONDITIONS")
	_assert_eq(unbuilt, KNOWN_UNBUILT, "script tokens without a unit of the cast are exactly KNOWN_UNBUILT")
	_hp_low_threshold_reading()
	_ablations(campaign)


## One battle: {path: status keys from an armed status to the win (empty = blocked),
## blocked_by: unfireable statuses and why, unresolved: condition tokens naming nobody,
## hp_low: undead HPLow targets the condition misses at 1 HP, static_tokens}.
func census(loop: Dictionary, scenario: Dictionary, arrivals: Variant = null) -> Dictionary:
	var cast := cast_battle(loop)
	var rules: Dictionary = loop["winfail_script_rules"]
	var undead := undead_ids(cast, rules)
	if arrivals == null:
		arrivals = arrival_floods(cast, rules)
	var report := {"path": [], "blocked_by": {}, "unresolved": [], "hp_low": [], "static_tokens": []}
	var statics: Dictionary = loop["winfail_runtime"].get("static_enemy_counts", {})
	var fireable := {}
	for status in WinfailCompiler.all_statuses(rules):
		var why := unfireable_reason(cast, status, undead, arrivals)
		fireable[str(status["key"])] = why == ""
		if why != "":
			report["blocked_by"][str(status["key"])] = why
		for token in WinfailConditions.condition_tokens(status):
			if WinfailConditions.token_source(cast, str(token)) == "unresolved":
				report["unresolved"].append("%s condition token %s names no unit" % [status["key"], token])
			if statics.has(str(token)) and WinfailConditions.units_for_token(cast, str(token)).is_empty() and not report["static_tokens"].has(str(token)):
				report["static_tokens"].append(str(token))
		for condition in status.get("conditions", []):
			if str(condition["name"]) != "actCheckPlayerHPLow":
				continue
			for unit_id in WinfailConditions.units_for_token(cast, WinfailConditions._arg(condition["args"], 0), WinfailConditions._int_arg(condition["args"], 1)):
				if undead.has(unit_id) and not _holds_at(cast, unit_id, 1, false, condition):
					report["hp_low"].append("%s %s misses undead %s at its revive HP 1" % [status["key"], str(condition["args"]), unit_id])
	var armed: Array = []
	var parent := {}
	for kind in WinfailCompiler.STATUS_KINDS:
		for code in loop.get("%s_statuses" % kind, []):
			armed.append("%s_%d" % [kind, int(code)])
	for key in (scenario.get("opening", {}) as Dictionary).get("select_event_timelines", {}).keys():
		if not armed.has(str(key)):
			armed.append(str(key))
	var frontier := armed.duplicate()
	while not frontier.is_empty():
		var key: String = frontier.pop_front()
		var status := WinfailCompiler.status_by_key(rules, key)
		if status.is_empty() or not bool(fireable.get(key, false)):
			continue
		if key.begins_with("win_") or (key.begins_with("event_") and _hands_off(status)):
			var path := [key]
			while parent.has(path[0]):
				path.push_front(parent[path[0]])
			report["path"] = path
			break
		for next_key in armed_by(status, armed, fireable):
			if not armed.has(next_key):
				armed.append(next_key)
				parent[next_key] = key
				frontier.append(next_key)
	report["unresolved"].sort()
	report["static_tokens"].sort()
	return report


## The loop with every creatable script actor added (template id `template:<symbol>`), its
## registered-player tokens bound: what the conditions can ever name.
func cast_battle(loop: Dictionary) -> Dictionary:
	var cast: Dictionary = Loop.copy(loop)
	cast["units"] = (loop["units"] as Array).duplicate(true)
	var bindings: Dictionary = cast["winfail_runtime"]["actor_bindings"]
	var templates: Dictionary = (loop.get("script_actor_source", {}) as Dictionary).get("templates", {})
	for symbol in templates:
		var spec: Dictionary = templates[symbol]
		if spec.has("insert_skip"):
			continue
		var actor: Dictionary = (spec["actor"] as Dictionary).duplicate(true)
		if not WinfailConditions.unit(cast, str(actor["id"])).is_empty():
			continue
		actor["census_template"] = str(symbol)
		cast["units"].append(actor)
		for token in [spec["token"]] + spec["aliases"]:
			if not bindings.has(str(token) + "/1"):
				bindings[str(token) + "/1"] = str(actor["id"])
	return cast


## SID_ENEMYnnn tokens the battle's WINFAIL statuses and STORY actions name that resolve to
## no unit of the cast (fielded units, one instance per script template, the opening-only
## actors the STORY deletes before first control), sorted.
func unbuilt_tokens(loop: Dictionary, scenario: Dictionary) -> Array:
	var cast := cast_battle(loop)
	var tokens := {}
	for status in WinfailCompiler.all_statuses(loop["winfail_script_rules"]):
		for item in status.get("conditions", []) + status.get("actions", []):
			for arg in item["args"]:
				if str(arg).begins_with("SID_ENEMY"):
					tokens[str(arg)] = true
	var seed_path := str((scenario.get("resources", {}) as Dictionary).get("battle_seed", ""))
	if seed_path != "" and FileAccess.file_exists(seed_path):
		var seed: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(seed_path))
		for section in seed.get("scripts", {}).get("story", {}).get("sections", []):
			for action in section.get("actions", []):
				for command in action.get("chain", []):
					for arg in command.get("args", []):
						if str(arg).begins_with("SID_ENEMY"):
							tokens[str(arg)] = true
	var opening_only := {}
	for actor in scenario.get("story_actors", []):
		opening_only[str(actor.get("token", ""))] = true
	var missing: Array = []
	for token in tokens:
		if WinfailConditions.units_for_token(cast, str(token)).is_empty() and not opening_only.has(token):
			missing.append(str(token))
	missing.sort()
	return missing


## Units that are (or the script ever makes) undead: they revive at 1 HP instead of dying.
func undead_ids(cast: Dictionary, rules: Dictionary) -> Dictionary:
	var ids := {}
	for unit in cast["units"]:
		if bool(unit.get("undead", false)):
			ids[str(unit["id"])] = true
	for status in WinfailCompiler.all_statuses(rules):
		for action in status.get("actions", []):
			if str(action["name"]) == "actSetPlayerUndead" and WinfailConditions._int_arg(action["args"], 2) != 0:
				for unit_id in WinfailConditions.units_for_token(cast, WinfailConditions._arg(action["args"], 0), WinfailConditions._int_arg(action["args"], 1)):
					ids[str(unit_id)] = true
	return ids


func unfireable_reason(cast: Dictionary, status: Dictionary, undead: Dictionary, arrivals: Dictionary) -> String:
	var conditions: Array = status.get("conditions", [])
	if conditions.is_empty():
		return "no condition"
	for condition in conditions:
		var name := str(condition["name"])
		var args: Array = condition["args"]
		if not bool(condition.get("supported", false)):
			return "unsupported %s" % name
		match name:
			"actFALSE":
				return "actFALSE"
			"actCheckRoundNumber", "actCheckRoundDisp", "actDetectRoundDispDisp":
				if WinfailConditions._int_arg(args, 0) > ROUND_REACHABLE:
					return "%s %s never comes" % [name, str(args)]
			"actCheckPlayerAttacked":
				if WinfailConditions.units_for_token(cast, WinfailConditions._arg(args, 1)).is_empty():
					return "%s: nobody to attack as %s" % [name, WinfailConditions._arg(args, 1)]
				if WinfailConditions._arg(args, 0) != "-1" and WinfailConditions.units_for_token(cast, WinfailConditions._arg(args, 0)).is_empty():
					return "%s: no attacker %s" % [name, WinfailConditions._arg(args, 0)]
			"actCheckSerialPlayerAttacked":
				if WinfailConditions.units_for_token(cast, WinfailConditions._arg(args, 0), WinfailConditions._int_arg(args, 1)).is_empty():
					return "%s: no %s serial %s" % [name, WinfailConditions._arg(args, 0), WinfailConditions._arg(args, 1)]
			"actCheckPlayerHPLow":
				var reached := false
				for unit_id in WinfailConditions.units_for_token(cast, WinfailConditions._arg(args, 0), WinfailConditions._int_arg(args, 1)):
					var lowest := 1 if undead.has(unit_id) else 0
					if _holds_at(cast, unit_id, lowest, lowest == 0, condition):
						reached = true
				if not reached:
					return "%s %s: no target reaches the threshold" % [name, str(args)]
			"actCheckEnemyNumber":
				var token := WinfailConditions._arg(args, 0)
				if WinfailConditions.token_source(cast, token) == "unresolved":
					return "%s: unresolved %s" % [name, token]
				if int(cast["winfail_runtime"].get("static_enemy_counts", {}).get(token, 0)) >= WinfailConditions._int_arg(args, 1):
					return "%s: static objects %s are never destroyed" % [name, token]
			"actCheckPlayer", "actCheckEnemy":
				var needed := mini(WinfailConditions._int_arg(args, 0), args.size() - 1)
				var countable := 0
				for index in range(1, args.size()):
					var token := WinfailConditions._arg(args, index)
					var source := WinfailConditions.token_source(cast, token)
					if source == "unresolved" or (source == "binding" and WinfailConditions.units_for_token(cast, token).is_empty()):
						continue
					countable += 1
				if needed <= 0 or countable < needed:
					return "%s %s: only %d countable ids" % [name, str(args), countable]
			"actCheckPlayerArrivePos", "actCheckAnyPlayerArrivePos":
				if not bool(arrivals.get(JSON.stringify([name, args]), false)):
					return "%s %s: zone unreachable" % [name, str(args)]
	return ""


func _holds_at(cast: Dictionary, unit_id: String, hp: int, defeated: bool, condition: Dictionary) -> bool:
	var probe: Dictionary = cast.duplicate()
	probe["units"] = (cast["units"] as Array).duplicate(true)
	var unit := WinfailConditions.unit(probe, unit_id)
	unit["hp"] = hp
	unit["defeated"] = defeated
	if str(condition["name"]) == "actCheckPlayerHPLow":
		# WinfailConditions' own reading, with the threshold routed through hp_low_threshold.
		_assert_eq(WinfailConditions.condition_holds(probe, "actCheckPlayerHPLow", condition["args"], "round"), hp <= WinfailConditions.hp_low_threshold(int(unit.get("max_hp", 0)), WinfailConditions._int_arg(condition["args"], 2)), "census HPLow agrees with WinfailConditions for %s" % unit_id)
		return hp <= int(hp_low_threshold.call(int(unit.get("max_hp", 0)), WinfailConditions._int_arg(condition["args"], 2)))
	return WinfailConditions.condition_holds(probe, str(condition["name"]), condition["args"], "round")


func _hands_off(status: Dictionary) -> bool:
	for action in status.get("actions", []):
		if str(action["name"]) == HANDOFF_ACTION:
			return true
	return false


## Statuses the chain arms. A chain gate (actCheckEventNotExist, WinfailCompiler.CHAIN_GATE_CONDITIONS)
## ends the chain while a listed event is still armed: the inserts behind it count only when
## every listed event already armed can fire (and so leave the slot table) — WINFAIL037's pillar
## 5 arms event 6 only after pillars 1–4, WINFAIL080's treasures arm win 0 only as the second.
func armed_by(status: Dictionary, armed: Array = [], fireable: Dictionary = {}) -> Array:
	var keys: Array = []
	for action in status.get("actions", []):
		var name := str(action["name"])
		var args: Array = action["args"]
		if bool(action.get("chain_gate", false)):
			for index in range(1, 1 + mini(WinfailConditions._int_arg(args, 0), args.size() - 1)):
				var listed := "event_%d" % WinfailConditions._int_arg(args, index)
				if armed.has(listed) and not bool(fireable.get(listed, false)):
					return keys
			continue
		if name.begins_with("actInsert") and WinfailCompiler.status_kind_of(name) != "" and args.size() >= 1:
			keys.append("%s_%d" % [WinfailCompiler.status_kind_of(name), int(args[0])])
		elif name == "actSelectInsertEvent":
			# [id][serial][num][msg 1][event 1][msg 2][event 2]...
			for index in range(4, args.size(), 2):
				keys.append("event_%d" % int(args[index]))
	return keys


## {JSON [name, args]: reachable} for every arrival condition: some unit it names (any
## player-side unit for actCheckAnyPlayerArrivePos, the party for a unit the script creates)
## can walk into the zone on the map with every mid-battle ClearWall open, ignoring units.
func arrival_floods(cast: Dictionary, rules: Dictionary) -> Dictionary:
	var result := {}
	var board: Dictionary = Loop.copy(cast)
	board["terrain_edits"] = []
	var cell_size := WinfailConditions.cell_size(cast)
	for status in WinfailCompiler.all_statuses(rules):
		for action in status.get("actions", []):
			var args: Array = action["args"]
			var edit: Dictionary = rules.get("story_object_terrain", {}).get(WinfailConditions._arg(args, 0), {})
			if str(action["name"]) == "actInsertStoryObject" and edit.has("clear_flags") and args.size() >= 3:
				TerrainEdits.record(board, WinfailConditions._arg(args, 0), [Vector2i(floori(float(args[1]) / cell_size), floori(float(args[2]) / cell_size))], "winnability census")
	var tiles := TerrainEdits.tiles(board)
	var size: Vector2i = cast["map_size"]
	var reach_cache := {}
	for status in WinfailCompiler.all_statuses(rules):
		for condition in status.get("conditions", []):
			var name := str(condition["name"])
			var args: Array = condition["args"]
			if name != "actCheckPlayerArrivePos" and name != "actCheckAnyPlayerArrivePos":
				continue
			var zone: Array = [args.slice(2, 6), args.slice(0, 4)][int(name == "actCheckAnyPlayerArrivePos")]
			var cells := {}
			for cell in WinfailCompiler.zone_cells(zone.map(func(value): return int(value)), cell_size):
				cells[Vector2i(int(cell[0]), int(cell[1]))] = true
			var walkers: Array = []
			if name == "actCheckPlayerArrivePos":
				for unit_id in WinfailConditions.units_for_token(cast, WinfailConditions._arg(args, 0), WinfailConditions._int_arg(args, 1)):
					var unit := WinfailConditions.unit(cast, unit_id)
					walkers.append(unit if not unit.has("census_template") else {})
			if walkers.is_empty() or walkers.has({}):
				for unit in cast["units"]:
					if not unit.has("census_template") and WinfailConditions.player_side(unit):
						walkers.append(unit)
			var reached := false
			for unit in walkers:
				if unit.is_empty():
					continue
				var id := str(unit["id"])
				if not reach_cache.has(id):
					var mover: Dictionary = unit.duplicate(true)
					var envelope := Grid.movement_reachability_envelope(mover, [], tiles, size, size.x * size.y * 16)
					var reach := {mover["coord"]: true}
					for coord in envelope.get("reachable_coords", []):
						reach[coord] = true
					reach_cache[id] = reach
				for cell in cells:
					if (reach_cache[id] as Dictionary).has(cell):
						reached = true
				if reached:
					break
			result[JSON.stringify([name, args])] = reached
	return result


## The static-derived reading itself: threshold max_hp × ratio / 100, at least 1.
func _hp_low_threshold_reading() -> void:
	_assert_eq(WinfailConditions.hp_low_threshold(6313, 0), 1, "ratio 0 holds at HP 1 (clamp)")
	_assert_eq(WinfailConditions.hp_low_threshold(35, 30), 10, "35 × 30 / 100 truncates to 10")
	_assert_eq(WinfailConditions.hp_low_threshold(3, 20), 1, "a threshold below 1 is clamped to 1")
	var battle := {"units": [{"id": "boss", "class_id": "Enemy060", "actor_id": "060", "hp": 2, "max_hp": 6313}], "winfail_runtime": {"actor_bindings": {}}}
	_assert_true(not WinfailConditions.condition_holds(battle, "actCheckPlayerHPLow", ["SID_ENEMY060", "1", "0"], "round"), "HP 2 of 6313 is above the ratio-0 threshold")
	battle["units"][0]["hp"] = 1
	_assert_true(WinfailConditions.condition_holds(battle, "actCheckPlayerHPLow", ["SID_ENEMY060", "1", "0"], "round"), "an undead boss revived at HP 1 satisfies ratio 0")


## The census must fail without each fix: the pre-R6-L8 HPLow reading, and level 29 without
## its actChangePlayerID bindings.
func _ablations(campaign: Dictionary) -> void:
	var loop_59: Dictionary = boards["59"][0]
	var scenario_59: Dictionary = boards["59"][1]
	var cast := cast_battle(loop_59)
	var win: Dictionary = WinfailCompiler.status_by_key(loop_59["winfail_script_rules"], "win_0")
	var condition: Dictionary = win["conditions"][0]
	_assert_true(_holds_at(cast, "actor060_1", 1, false, condition), "level 59 win 0 holds on the undead boss at HP 1")
	var report := census(loop_59, scenario_59, boards["59"][2])
	_assert_eq(report["path"], ["win_0"], "level 59 is winnable through win 0")
	# Ablation: the pre-R6-L8 reading (hp × 100 <= ratio × max_hp, so ratio 0 needs HP <= 0,
	# no clamp) over every battle: the undead bosses lose their win path.
	hp_low_threshold = func(max_hp: int, ratio: int) -> int: return max_hp * ratio / 100
	var blocked: Array = []
	var misses := 0
	for key in boards:
		var ablated := census(boards[key][0], boards[key][1], boards[key][2])
		misses += ablated["hp_low"].size()
		if ablated["path"].is_empty():
			blocked.append(str(key))
	hp_low_threshold = WinfailConditions.hp_low_threshold
	for key in ["41", "59", "75", "76", "77", "79"]:
		_assert_true(blocked.has(key), "ablation: the old HPLow reading leaves battle %s without a win path (blocked=%s)" % [key, str(blocked)])
	_assert_true(misses > 0, "ablation: the old HPLow reading misses undead targets at 1 HP")
	if verbose:
		print("WINNABILITY_ABLATION hp_low_old blocked=%s misses=%d" % [",".join(blocked), misses])
	var loop_29: Dictionary = boards["29"][0]
	var scenario_29: Dictionary = boards["29"][1]
	_assert_eq(WinfailConditions.units_for_token(loop_29, "1000", 1), ["actor023_1"], "STORY029 actChangePlayerID binds 1000 to 梅爾 (SID_ENEMY023 serial 1)")
	_assert_eq(WinfailConditions.units_for_token(loop_29, "1001", 1), ["actor023_2"], "STORY029 actChangePlayerID binds 1001 to 凱文 (SID_ENEMY023 serial 2)")
	var unbound: Dictionary = Loop.copy(loop_29)
	unbound["winfail_runtime"] = (loop_29["winfail_runtime"] as Dictionary).duplicate(true)
	unbound["winfail_runtime"]["actor_bindings"].erase("1000/1")
	unbound["winfail_runtime"]["actor_bindings"].erase("1001/1")
	_assert_true(not census(unbound, scenario_29, boards["29"][2])["unresolved"].is_empty(), "ablation: without the bindings the level-29 death events name nobody")
	_missing_actor_ablations()


## Lane R6-L10: level 37's win path runs through the guardians and level 80's wall waits for
## the 怨念體; take the units out again and the census must see the old defects.
func _missing_actor_ablations() -> void:
	var loop_37: Dictionary = boards["37"][0]
	var scenario_37: Dictionary = boards["37"][1]
	var report := census(loop_37, scenario_37, boards["37"][2])
	_assert_eq(report["path"].slice(0, 2), ["event_5", "event_6"], "level 37 wins through pillar 5 (SID_ENEMY067 serial 5) and event 6 (Enemy052)")
	_assert_eq(WinfailConditions.units_for_token(loop_37, "SID_ENEMY067", 5), ["guard067_5"], "SID_ENEMY067 serial 5 is the fifth inserted gem")
	var gems := 0
	for unit in loop_37["units"]:
		if str(unit["actor_id"]) == "067":
			gems += 1
			_assert_true(bool(unit.get("undead", false)) and int(unit["max_hp"]) == 1, "gem %s is undead at max HP 1 (hit_point -10000)" % unit["id"])
	_assert_eq(gems, 5, "STORY037 fields five gems")
	var stripped := _without_actors(loop_37, ["066", "067"])
	_assert_true(census(stripped, scenario_37, boards["37"][2])["path"].is_empty(), "ablation: without the guardian units level 37 has no win path")
	_assert_eq(unbuilt_tokens(stripped, scenario_37), ["SID_ENEMY066", "SID_ENEMY067"], "ablation: without the guardian units their tokens are unbuilt")
	var loop_80: Dictionary = boards["80"][0]
	var wall := ["1", "SID_ENEMY068"]
	_assert_true(not WinfailConditions.condition_holds(loop_80, "actCheckEnemy", wall, "round"), "level 80's wall event waits while the 怨念體 stands")
	var fallen: Dictionary = Loop.copy(loop_80)
	fallen["units"] = (loop_80["units"] as Array).duplicate(true)
	WinfailConditions.unit(fallen, "actor068_1")["defeated"] = true
	_assert_true(WinfailConditions.condition_holds(fallen, "actCheckEnemy", wall, "round"), "level 80's wall event holds once the 怨念體 falls")
	_assert_true(WinfailConditions.condition_holds(_without_actors(loop_80, ["068"]), "actCheckEnemy", wall, "round"), "ablation: without the 怨念體 unit the wall event holds at first control")
	_level37_gem_chain(loop_37)
	_level80_treasure_order(loop_80)


## The pillar puzzle through the public commands: a gem refuses an ordinary attack (weapon range,
## 0x800000), takes a spell and revives at 1 HP (undead) switched to pmPlayerEnemy. Its event
## chain ends at the actCheckEventNotExist gate while another pillar event is still armed
## (0x450840 case 0x72): gem 5 struck first only goes dark; struck last (pillars 1–4 already
## struck, their events consumed) it deletes the guardians and fields Enemy052 (events 5 → 6);
## another gem struck last resets the pillars (event 7 re-arms 8–12).
func _level37_gem_chain(first: Dictionary) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var loop: Dictionary = Loop._resolve_outcome(Loop.BattleScenarioRuleAdapter.run_event_hooks(Loop.copy(first)))
	var caster := ""
	var skill := ""
	for step in range(200):
		var id := str(CoreTurnQueue.current(loop["turn_queue"]).get("id", ""))
		if not bool(Loop._unit(loop, id).get("player_commandable", false)):
			loop = Loop.step_ai_turn(loop, rng)
			continue
		var ready := Loop.select_player_unit(loop, id)
		for option in Loop.magic_options(ready, id):
			if option["quote"]["ok"] and not Loop.SkillTargetRules.is_support(option["fields"], ready["skill_target_data"]):
				caster = id
				skill = str(option["id"])
				break
		if caster != "":
			loop = ready
			break
		loop = Loop.commit_wait(ready, rng)
	_assert_true(caster != "", "level 37 fields a caster with an offensive spell")
	if caster == "":
		return
	var adjacent := _gem_beside(loop, caster, "guard067_5")
	var struck := Loop.attack_target(Loop.choose_command(adjacent, "attack"), "guard067_5", rng)
	_assert_eq(str(struck.get("last_attack_reject", {}).get("reason", "")), "not_enemy", "an ordinary attack cannot select a pmMagicAttack gem")
	var early := _cast_on_gem(loop, caster, skill, "guard067_5", rng)
	var after := Loop._unit(early, "guard067_5")
	_assert_true(int(after["hp"]) == 1 and not bool(after.get("defeated", false)), "the undead gem revives at 1 HP after a lethal spell")
	_assert_eq(int(after.get("player_mode", 0)), 0x30000, "a struck gem goes dark (pmPlayerEnemy)")
	var fired: Array = early["winfail_runtime"]["fired"]
	_assert_eq(fired.map(func(entry): return entry["key"]), ["event_5"], "gem 5 struck first fires event 5 only")
	_assert_eq(int(fired[0].get("chain_stop_index", -1)), 3, "event 5 stops at its actCheckEventNotExist gate while pillars 1–4 are armed")
	_assert_true(not (early["event_statuses"] as Array).has(6) and _alive_of(early, ["052"]).is_empty() and _alive_of(early, ["066", "067"]).size() == 10, "gem 5 struck first leaves the guardians standing and Enemy052 absent")
	# Pillars 1–4 already struck: their events have left the slot table.
	var primed: Dictionary = Loop.copy(loop)
	primed["event_statuses"] = (loop["event_statuses"] as Array).filter(func(code): return not [1, 2, 3, 4].has(int(code)))
	var last := _cast_on_gem(primed, caster, skill, "guard067_5", rng)
	_assert_eq(last["winfail_runtime"]["fired"].map(func(entry): return entry["key"]), ["event_5", "event_6"], "gem 5 struck last fires WINFAIL037 events 5 and 6")
	_assert_true(_alive_of(last, ["066", "067"]).is_empty() and _alive_of(last, ["052"]).size() == 1 and (last["event_statuses"] as Array).has(47), "event 6 removes the ten guardians, fields Enemy052 and arms event 47")
	# Gem 4 struck last (1, 2, 3 and 5 already struck): the pillars reset.
	var wrong: Dictionary = Loop.copy(loop)
	wrong["event_statuses"] = (loop["event_statuses"] as Array).filter(func(code): return not [1, 2, 3, 5].has(int(code)))
	var reset := _cast_on_gem(wrong, caster, skill, "guard067_4", rng)
	_assert_eq(reset["winfail_runtime"]["fired"].map(func(entry): return entry["key"]), ["event_4", "event_7"], "another gem struck last fires its event and the event-7 reset")
	var rearmed := true
	for code in [8, 9, 10, 11, 12]:
		rearmed = rearmed and (reset["event_statuses"] as Array).has(code)
	_assert_true(rearmed and not (reset["event_statuses"] as Array).has(6) and int(Loop._unit(reset, "guard067_4").get("player_mode", 0)) == 0x870000, "event 7 relights the gems (pmMagicAttack) and arms events 8–12")


## WINFAIL080 events 0／1 (the two treasures) end at `actCheckEventNotExist 1,<other>` while the
## other treasure event is armed: the first one reached only hands out its item, the second arms
## win 0. The southern treasure lies behind the wall event 3 opens when the 怨念體 falls
## (run_story_object_terrain_tests), so the win needs the boss down and both treasures.
func _level80_treasure_order(first: Dictionary) -> void:
	var runner := ""
	for unit in first["units"]:
		if bool(unit.get("player_commandable", false)):
			runner = str(unit["id"])
			break
	var north := _arrive(Loop.copy(first), runner, Vector2i(19, 4))
	var north_fired: Array = north["winfail_runtime"]["fired"]
	_assert_eq(north_fired.map(func(entry): return entry["key"]), ["event_0"], "level 80: the northern treasure fires event 0")
	_assert_true(int(north_fired[0].get("chain_stop_index", -1)) == 11 and not (north["win_statuses"] as Array).has(0) and not BattleOutcome.decided(north), "level 80: the first treasure stops at its gate (event 1 armed) — no win while the 怨念體 guards the second")
	var south_only: Dictionary = Loop.copy(first)
	WinfailConditions.unit(south_only, "actor068_1")["defeated"] = true
	south_only = _arrive(south_only, runner, Vector2i(19, 13))
	_assert_true(south_only["winfail_runtime"]["fired"].map(func(entry): return entry["key"]).has("event_1") and not (south_only["win_statuses"] as Array).has(0) and not BattleOutcome.decided(south_only), "level 80: the southern treasure alone does not arm win 0 either")
	var both: Dictionary = Loop.copy(north)
	WinfailConditions.unit(both, "actor068_1")["defeated"] = true
	both = _arrive(both, runner, Vector2i(19, 13))
	var both_fired: Array = both["winfail_runtime"]["fired"].map(func(entry): return entry["key"])
	_assert_true(both_fired.has("event_1") and both_fired.has("event_3"), "level 80: the second treasure fires event 1, the fallen 怨念體 event 3 (%s)" % str(both_fired))
	_assert_eq(BattleOutcome.of(both), BattleOutcome.VICTORY_SCRIPT, "level 80: both treasures arm win 0 and the battle is won")


func _arrive(loop: Dictionary, unit_id: String, cell: Vector2i) -> Dictionary:
	var unit := WinfailConditions.unit(loop, unit_id)
	unit["coord"] = cell
	unit["grid_coord"] = cell
	return Loop._resolve_outcome(Loop.BattleScenarioRuleAdapter.run_event_hooks(loop))


## `loop` with gem `gem_id` moved beside the caster (a copy).
func _gem_beside(loop: Dictionary, caster: String, gem_id: String) -> Dictionary:
	var next: Dictionary = Loop.copy(loop)
	var gem := Loop._unit(next, gem_id)
	for delta in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		if Loop.unit_id_at_coord(next, Loop._unit(next, caster)["coord"] + delta) == "":
			gem["coord"] = Loop._unit(next, caster)["coord"] + delta
			break
	return next


func _cast_on_gem(loop: Dictionary, caster: String, skill: String, gem_id: String, rng: RandomNumberGenerator) -> Dictionary:
	var ready := _gem_beside(loop, caster, gem_id)
	var cast := Loop.attack_target(Loop.choose_magic(Loop.choose_command(ready, "magic"), skill), gem_id, rng, Loop._unit(ready, gem_id)["coord"])
	return Loop.finish_exhausted_action(cast)


func _alive_of(loop: Dictionary, actor_ids: Array) -> Array:
	return loop["units"].filter(func(unit): return str(unit["actor_id"]) in actor_ids and WinfailConditions.unit_alive(loop, str(unit["id"])))


func _without_actors(loop: Dictionary, actor_ids: Array) -> Dictionary:
	var stripped: Dictionary = Loop.copy(loop)
	stripped["units"] = (loop["units"] as Array).filter(func(unit): return not actor_ids.has(str(unit["actor_id"])))
	stripped["winfail_runtime"] = (loop["winfail_runtime"] as Dictionary).duplicate(true)
	var bindings: Dictionary = stripped["winfail_runtime"]["actor_bindings"]
	for key in bindings.keys():
		if WinfailConditions.unit(stripped, str(bindings[key])).is_empty():
			bindings.erase(key)
	return stripped
