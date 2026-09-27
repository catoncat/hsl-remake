extends SceneTree

## Whole-exchange replay (`hsl_exchange_replay.v1`): every exchange a
## tools/hsltools/probes/_exchange_check.py `record` file caught on the original program is
## replayed through the remake's one exchange seam `BattleLoopCombat.resolve_exchange`, from
## the same exchange-start state — board cells／HP from the case, both participants' HP,
## EXP, level, hit bonus (+0xb0) and kill chain (+0xa8) from their live records, the loop
## damage stream `damage_rng` set to the original's words 0x4c3044／0x4c3040. The rng handed
## in is a Callable over DamageRandomStream.loop_draw on the same loop (the AI's null source
## draws the same values, DamageRandomStream.loop_source), with each draw logged beside the
## script frame that asked for it. Diagnostic only, not a gate: no rule changes.
##
##   tools/godot.sh --headless --script res://tests/export_exchanges.gd -- --cases FILE --out FILE
##
## Output: {"schema", "level", "cases": [{run, index, striker, defender, receipt, draws:
## [[n, value, site]], profiles, overrides, end, error}]}; `end` holds both participants' hp／
## exp／level／hit_bonus_accum／kill_chain_word and the damage words after the exchange. The
## level's template roster is used, as the record's `growth` false board: that board only zeroes
## the growth words, and every player birth still runs 0x44346e → 0x40e870, whose kind3 path
## re-infers the level from base attributes (0x40e800) and refreshes (0x40eb18), so manual
## players take InitialRosterGrowthRules.prepare_player (level 53: 緹娜 L1 35/37 → L2 36/38).
## A participant whose level／max HP／combat words still differ from the original's live record
## takes the original's, each listed in `overrides` as [remake, original].

const BattlePlayLoop = preload("res://game/sim/loop/BattlePlayLoop.gd")
const BattleLoopCombat = preload("res://game/sim/loop/BattleLoopCombat.gd")
const BattleScenario = preload("res://game/sim/BattleScenario.gd")
const CoreTurnQueue = preload("res://game/sim/CoreTurnQueue.gd")
const CoreCombatRules = preload("res://game/sim/CoreCombatRules.gd")
const DamageRandomStream = preload("res://game/sim/DamageRandomStream.gd")
const InitialRosterGrowthRules = preload("res://game/sim/InitialRosterGrowthRules.gd")

const SCHEMA := "hsl_exchange_replay.v1"
## Frames that only forward a draw; the logged site is the first frame outside them.
const FORWARDERS := ["draw", "rand_range", "native_draw", "recorded_draw", "loop_draw"]
## Record field (_exchange_check.py LIVE: +0xc0 attack, +0xb4 defense, +0xbc hit, +0x4c str,
## +0x50 dex, +0x19a avoid, +0x19e counter, +0x1a2 critical) → combat_profile key.
const PROFILE_FIELDS := {"attack": "live_attack_damage", "defense": "live_defense", "hit": "live_hit_ratio",
	"str": "str", "dex": "dex", "avoid": "avoid_hit_ratio", "counter": "attack_back", "crit": "attack_damagex2"}


class DamageRecorder:
	var loop: Dictionary
	var log: Array = []

	func draw(bound: int) -> int:
		var value := DamageRandomStream.loop_draw(loop, bound)
		var site := "?"
		for frame in get_stack():
			if str(frame["function"]) in FORWARDERS: continue
			site = "%s.%s:%d" % [str(frame["source"]).get_file().get_basename(), str(frame["function"]), int(frame["line"])]
			break
		log.append([bound, value, site])
		return value


func _initialize() -> void:
	var args := Array(OS.get_cmdline_user_args())
	var opts := {}
	for i in range(0, args.size() - 1, 2): opts[str(args[i]).trim_prefix("--")] = str(args[i + 1])
	if not opts.has("cases") or not opts.has("out"):
		printerr("EXCHANGE_REPLAY usage: --cases FILE --out FILE")
		quit(2)
		return
	var cases: Variant = JSON.parse_string(FileAccess.get_file_as_string(str(opts["cases"])))
	if not cases is Dictionary:
		printerr("EXCHANGE_REPLAY unreadable cases %s" % opts["cases"])
		quit(2)
		return
	var scenario := BattleScenario.load_file("res://content/battles/battle_%s.json" % str(cases["battle"]))
	if not bool(scenario.get("ok", false)):
		printerr("EXCHANGE_REPLAY scenario_load %s" % str(scenario.get("error", scenario.get("reason", ""))))
		quit(1)
		return
	var base := BattlePlayLoop.create([], "", scenario, 1)
	for index in range(base["units"].size()):
		if base["units"][index]["growth_profile"]["allocation"] != "manual": continue
		var born := InitialRosterGrowthRules.prepare_player(base["units"][index], base["equipment_items"])
		if not bool(born["ok"]):
			printerr("EXCHANGE_REPLAY player_birth %s %s" % [str(base["units"][index]["id"]), str(born["reason"])])
			quit(1)
			return
		base["units"][index] = born["actor"]
	var out :={"schema": SCHEMA, "level": int(cases["level"]), "cases": []}
	var started := Time.get_ticks_msec()
	var errors := 0
	for run_index in cases["runs"].size():
		for exchange in cases["runs"][run_index].get("exchanges", []):
			var row := _replay(base, exchange)
			row["run"] = run_index
			row["index"] = int(exchange["index"])
			row["striker"] = str(exchange["striker"])
			row["defender"] = str(exchange["defender"])
			if row.has("error"): errors += 1
			out["cases"].append(row)
	var file := FileAccess.open(str(opts["out"]), FileAccess.WRITE)
	file.store_string(JSON.stringify(out, " ", false) + "\n")
	file.close()
	print("EXCHANGE_REPLAY level=%d cases=%d errors=%d wall=%.1fs out=%s" % [int(cases["level"]), out["cases"].size(), errors, (Time.get_ticks_msec() - started) / 1000.0, opts["out"]])
	quit(0)


func _replay(base: Dictionary, exchange: Dictionary) -> Dictionary:
	var loop := BattlePlayLoop.copy(base)
	var start: Dictionary = exchange["start"]
	var board: Dictionary = start.get("board", {})
	var units: Dictionary = start["units"]
	for unit in loop["units"]:
		var id := str(unit["id"])
		if board.has(id):
			if board[id]["cell"] == null:
				unit["hp"] = 0
				unit["defeated"] = true
			else:
				unit["coord"] = Vector2i(int(board[id]["cell"][0]), int(board[id]["cell"][1]))
				unit["hp"] = mini(int(board[id]["hp"]), int(unit["max_hp"]))
		if units.has(id):
			var live: Dictionary = units[id]
			unit["coord"] = Vector2i(int(live["cell"][0]), int(live["cell"][1]))
			unit["hp"] = int(live["hp"])
			unit["defeated"] = false
			unit["exp"] = int(live["exp"])
			unit["hit_bonus_accum"] = int(live["hit_bonus"])
			unit["kill_chain_word"] = int(live["kill_chain"])
	var overrides := {}
	for id in [str(exchange["striker"]), str(exchange["defender"])]:
		var unit := BattlePlayLoop.unit_ref(loop, id)
		if unit.is_empty(): return {"error": "no_remake_unit:%s" % id}
		# A participant that still differs from the original's live record at this start takes
		# the original's level and live combat words, listed under `overrides`; the exchange
		# rules are what is compared, not the roster.
		var profile := CoreCombatRules.combat_profile_from_unit(unit)
		var live: Dictionary = units[id]
		var mine := {"level": int(unit["level"]), "max_hp": int(unit["max_hp"])}
		for field in PROFILE_FIELDS: mine[field] = int(profile[PROFILE_FIELDS[field]])
		for field in mine:
			if mine[field] == int(live[field]): continue
			overrides[id] = overrides.get(id, {})
			overrides[id][field] = [mine[field], int(live[field])]
			if field in ["level", "max_hp"]: unit[field] = int(live[field])
			else: unit["combat_profile"][PROFILE_FIELDS[field]] = int(live[field])
	loop["turn_queue"] = CoreTurnQueue.rebuild(BattlePlayLoop.queue_actors(loop))
	loop = BattlePlayLoop.resolve_outcome(loop)
	loop = BattlePlayLoop.begin_battle(loop)
	var profiles := {}
	for id in [str(exchange["striker"]), str(exchange["defender"])]:
		var unit := BattlePlayLoop.unit_ref(loop, id)
		var profile := CoreCombatRules.combat_profile_from_unit(unit)
		profiles[id] = {"hp": int(unit["hp"]), "max_hp": int(unit["max_hp"]), "level": int(unit["level"]), "exp": int(unit["exp"]),
			"attack": profile["live_attack_damage"], "defense": profile["live_defense"], "hit": profile["live_hit_ratio"],
			"str": profile["str"], "dex": profile["dex"], "avoid": profile["avoid_hit_ratio"], "counter": profile["attack_back"],
			"crit": profile["attack_damagex2"], "status": int(unit.get("status_flags", 0)), "cell": [unit["coord"].x, unit["coord"].y],
			"player": bool(unit.get("player_commandable", false))}
	loop[DamageRandomStream.LOOP_KEY] = [int(start["damage"][0]), int(start["damage"][1])]
	var recorder := DamageRecorder.new()
	recorder.loop = loop
	var receipt := BattleLoopCombat.resolve_exchange(loop, str(exchange["striker"]), str(exchange["defender"]), Callable(recorder, "draw"))
	var end := {"damage": loop[DamageRandomStream.LOOP_KEY], "units": {}}
	for id in [str(exchange["striker"]), str(exchange["defender"])]:
		var unit := BattlePlayLoop.unit_ref(loop, id)
		end["units"][id] = {"hp": int(unit["hp"]), "exp": int(unit["exp"]), "level": int(unit["level"]),
			"hit_bonus": int(unit.get("hit_bonus_accum", 0)), "kill_chain": int(unit.get("kill_chain_word", 0))}
	var row := {"receipt": receipt, "draws": recorder.log, "profiles": profiles, "overrides": overrides, "end": end}
	if receipt.is_empty(): row["error"] = "empty_receipt (an input or outcome gate of _resolve_exchange refused)"
	return row
