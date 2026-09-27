extends SceneTree

## Opening snapshot, remake side: every unit of a level's pure PlayLoop at the moment the
## original referee halts (tools/hsltools/probes/_opening_snapshot.py: the first round-queue
## sort, after the opening scripts and every opening birth) — create → global stream start →
## opening births (InitialRosterGrowthRules) → outcome check → begin_battle, the same opening
## export_enemy_turns.gd prepares. One JSON per level; hsltools.probes.opening_snapshot pairs it
## with the original's live records field by field. Diagnostic only, no rule changes.
##
##   tools/godot.sh --headless --script res://tests/diagnostics/export_opening_snapshot.gd -- [options]
##
##   --levels 3,51       levels (campaign.json battles keys; default: the autoplay results.json levels)
##   --modes g0,g1       g0: growth false — every non-player birth gets adjust_level [0, 0] (the
##                       original side zeroes the growth words +0x1f8／+0x1fa at 0x43eefb／0x44345d),
##                       so no level is drawn; the carry roll still draws. Global seed 1.
##                       g1: the real opening births, one run per --seeds value
##   --seeds 1-32        g1 global seeds: GlobalRandomStream.seeded(t) (the original side writes the
##                       same words [t, t ^ 0xe54a231c] before the level); also the create() reward seed
##   --out DIR           default ignored/opening_snapshot/remake (L051.json per level)
##
## Per unit: the loop dictionary (evidence prose keys dropped, Vector2i as [x, y]) plus `extra`:
## registry slot (CoreTurnQueue.registry_layout position), living, carried gold
## (BattleRewardRules.carried_gold), exp threshold (ProgressionRules.exp_to_next), the effective
## source words (entry growth and permanent gains on the template source), the skill ids
## (skill book supported_initial_ids + learned), the effective AI profile
## (AINavigationRules.instance_profile), the template carry list, the bag before the births (the
## carry roll 0x407c40 inserts into it), the side mask, the death-line ids (own word or PLAYERS
## pair), the growth halves a birth reads, the placement source (STORY actions, the assembler's
## blocked-cell move, off-grid endpoint) and, per birth, its lowest／highest outcome (bounds).

const BattlePlayLoop = preload("res://game/sim/loop/BattlePlayLoop.gd")
const BattleScenario = preload("res://game/sim/BattleScenario.gd")
const GlobalRandomStream = preload("res://game/sim/GlobalRandomStream.gd")
const CoreTurnQueue = preload("res://game/sim/CoreTurnQueue.gd")
const BattlePresenceRules = preload("res://game/sim/BattlePresenceRules.gd")
const BattleRewardRules = preload("res://game/sim/BattleRewardRules.gd")
const ProgressionRules = preload("res://game/sim/ProgressionRules.gd")
const EntryGrowthRules = preload("res://game/sim/EntryGrowthRules.gd")
const PermanentCapabilityRules = preload("res://game/sim/PermanentCapabilityRules.gd")
const AINavigationRules = preload("res://game/sim/AINavigationRules.gd")
const ActorRoleRules = preload("res://game/sim/ActorRoleRules.gd")

const SCHEMA := "hsl_opening_snapshot_remake.v1"
const DROP_SUFFIXES := ["_source", "_evidence_tier", "_note", "_evidence"]
const DROP_KEYS := ["position_source", "entry_growth", "entry_readjust", "evef_instance"]
## The keys a birth's bound proposal rewrites (the rest of the unit is the birth's own).
const BOUND_KEYS := ["level", "exp", "stamina", "kill_exp", "hp", "max_hp", "mp", "max_mp", "live_speed", "move_point", "combat_profile"]

var death_templates: Dictionary = {}


func _initialize() -> void:
	var opts := _parse(Array(OS.get_cmdline_user_args()))
	if opts.has("error"):
		printerr("OPENING_SNAPSHOT usage error: %s" % opts["error"])
		quit(2)
		return
	var campaign: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://content/battles/campaign.json"))
	death_templates = JSON.parse_string(FileAccess.get_file_as_string("res://content/generated/hsl/combat/aftermath.json"))["actors"]
	DirAccess.make_dir_recursive_absolute(str(opts["out"]))
	var failed := 0
	for level in opts["levels"]:
		var entry: Dictionary = campaign["battles"].get(str(level), {})
		var path := str(entry.get("scenario", "res://content/battles/battle_%03d.json" % int(level)))
		var data := {"schema": SCHEMA, "level": int(level), "scenario": path, "runs": {}}
		for mode in opts["modes"]:
			var seeds: Array = [1] if mode == "g0" else opts["seeds"]
			for seed in seeds:
				var run := _run(path, str(mode), int(seed), mode == "g1" and seed == seeds[0])
				data["runs"]["%s_s%d" % [mode, int(seed)]] = run
				if run.has("error"): failed += 1
		var file := FileAccess.open(str(opts["out"]).path_join("L%03d.json" % int(level)), FileAccess.WRITE)
		file.store_string(JSON.stringify(data, "", false) + "\n")
		file.close()
		print("OPENING_SNAPSHOT_REMAKE level=%d runs=%d" % [int(level), data["runs"].size()])
	print("OPENING_SNAPSHOT_REMAKE_DONE levels=%d failed_runs=%d" % [opts["levels"].size(), failed])
	quit(0)


func _parse(args: Array) -> Dictionary:
	var opts := {"modes": ["g0", "g1"], "seeds": _range("1-32"), "levels": [],
		"out": ProjectSettings.globalize_path("res://ignored/opening_snapshot/remake")}
	var i := 0
	while i < args.size():
		var key := str(args[i]).trim_prefix("--")
		if i + 1 >= args.size(): return {"error": "missing value for --%s" % key}
		var value := str(args[i + 1])
		match key:
			"levels": opts["levels"] = _range(value)
			"modes": opts["modes"] = Array(value.split(",", false))
			"seeds": opts["seeds"] = _range(value)
			"out": opts["out"] = value
			_: return {"error": "unknown option --%s" % key}
		i += 2
	if opts["levels"].is_empty():
		var results: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://content/generated/hsl/development/autoplay/results.json"))
		for key in results["levels"]: opts["levels"].append(int(key))
		opts["levels"].sort()
	return opts


## "1,3,5-8" → [1, 3, 5, 6, 7, 8]
func _range(text: String) -> Array:
	var out: Array = []
	for part in text.split(",", false):
		if "-" in part:
			var ends := part.split("-")
			for n in range(int(ends[0]), int(ends[1]) + 1): out.append(n)
		else: out.append(int(part))
	return out


func _run(path: String, mode: String, seed: int, with_bounds: bool) -> Dictionary:
	var scenario := BattleScenario.load_file(path)
	if not bool(scenario.get("ok", false)): return {"error": "scenario_load:%s" % str(scenario.get("error", scenario.get("reason", "")))}
	var loop := BattlePlayLoop.create([], "", scenario, seed)
	if not bool(loop.get("scenario_ok", false)): return {"error": "scenario:%s" % str(loop.get("scenario_error", ""))}
	loop[GlobalRandomStream.LOOP_KEY] = GlobalRandomStream.seeded(seed)
	if mode == "g0":
		for unit in loop["units"]:
			if unit.get("growth_profile", {}).get("allocation") == "manual": continue
			var insertion: Dictionary = unit.get("script_insert", {}).duplicate(true)
			insertion["adjust_level"] = [0, 0]
			unit["script_insert"] = insertion
	var templates := {}
	for unit in loop["units"]: templates[str(unit["id"])] = _plain(unit.get("inventory", []))
	loop = BattlePlayLoop.initialize_roster_growth(loop)
	if not bool(loop.get("scenario_ok", false)): return {"error": "births:%s" % str(loop.get("scenario_error", ""))}
	loop = BattlePlayLoop._resolve_outcome(loop)
	loop = BattlePlayLoop.begin_battle(loop)
	var layout := CoreTurnQueue.registry_layout(loop["units"])
	var units: Array = []
	for index in range(loop["units"].size()):
		var unit: Dictionary = _unit(loop, loop["units"][index], layout.find(index), with_bounds)
		unit["extra"]["inventory_template"] = templates.get(str(unit["id"]), [])
		units.append(unit)
	return {"global_after": loop[GlobalRandomStream.LOOP_KEY], "interaction": str(loop.get("interaction", "")),
		"turn": int(loop.get("turn", 0)), "units": units}


func _unit(loop: Dictionary, unit: Dictionary, slot: int, with_bounds: bool) -> Dictionary:
	var out := {}
	for key in unit:
		if key in DROP_KEYS or DROP_SUFFIXES.any(func(suffix): return str(key).ends_with(suffix)): continue
		out[key] = _plain(unit[key])
	var code := str(unit.get("actor_id", ""))
	var book: Dictionary = loop.get("skill_book", {}).get("actors", {}).get(code, {})
	var skills: Array = book.get("supported_initial_ids", []).duplicate()
	for record in unit.get("learned_skills", []): skills.append(str(record["id"]))
	var reward: Dictionary = loop.get("reward_data", {}).get("actors", {}).get(code, {})
	var extra := {"registry_slot": slot, "living": BattlePresenceRules.living(unit),
		"exp_threshold": ProgressionRules.exp_to_next(int(unit.get("level", 1))), "skill_ids": skills,
		"status_capability_flags": int(book.get("status_capability_flags", 0)), "double_attack": bool(book.get("double_attack", false)),
		"move_magic_use": bool(book.get("move_magic_use", false)), "carry_items": _plain(reward.get("carry_items", []))}
	if unit.has("growth_profile") and unit.has("permanent_gains"):
		extra["source"] = _plain(EntryGrowthRules.effective_profile(unit, PermanentCapabilityRules.effective_profile(unit))["source"])
	if not reward.is_empty(): extra["carried_gold"] = BattleRewardRules.carried_gold(unit, int(reward.get("gold", 0)))
	var declared: Dictionary = loop.get("ai_profiles", {}).get("actors", {}).get(code, {}).get("profile", {})
	if not declared.is_empty(): extra["ai_profile"] = _plain(AINavigationRules.instance_profile(unit, declared))
	extra["side_mask"] = ActorRoleRules.side_mask(unit)
	var placed: Dictionary = unit.get("position_source", {})
	extra["position"] = {"actions": placed.get("story_movements", []).map(func(m): return str(m.get("action", ""))),
		"insert": str(placed.get("opening_insert", {}).get("kind", "")), "story_endpoint": _plain(placed.get("story_endpoint")),
		"blocked_source_cell": _plain(placed.get("blocked_source_cell")), "unaligned": placed.has("unaligned_story_endpoint")}
	var death: Dictionary = unit["dead_message"] if unit.get("dead_message") is Dictionary else death_templates.get(code, {})
	extra["dead_message_ids"] = death.get("messages", []).map(func(m): return int(m["id"]))
	extra["growth_parameters"] = _growth_parameters(loop, unit)
	var birth: Variant = unit.get("entry_growth")
	if birth is Dictionary:
		extra["birth"] = {"parameters": _plain(birth.get("input", {}).get("parameters", [])),
			"source_level": int(birth.get("result", {}).get("source_level", 0)), "sampled_level": int(birth.get("result", {}).get("sampled_level", 0)),
			"draws": birth.get("draws", []).size()}
		if with_bounds: extra["bounds"] = _bounds(loop, unit, reward)
	out["extra"] = extra
	return out


## The +0x1fa／+0x1f8 halves a birth reads, resolved as ReinforcementGrowthRules.prepare does: a
## pre-baked insert's adjust_level, else the PLAYERS template pair with the EVEF words 16／17 over it.
func _growth_parameters(loop: Dictionary, unit: Dictionary) -> Variant:
	var insertion: Variant = unit.get("script_insert", {}).get("adjust_level", [])
	if insertion is Array and not insertion.is_empty(): return _plain(insertion)
	var source: Variant = loop.get("entry_growth_data", {}).get("actors", {}).get(str(unit.get("actor_id", "")), {}).get("parameters")
	if not source is Array or source.size() != 2: return null
	var overrides: Dictionary = unit.get("evef_instance", {}).get("overrides", {})
	return [int(overrides.get("level_adjust_range", source[0])), int(overrides.get("level_adjust_disp_range", source[1]))]


## The support of a birth's outcome: EntryGrowthRules.propose on the birth's own input for every
## pair of target draws (0x40e870's 1 + rand((w+1)/2+1) + rand(w/2) level pick, enumerated) with
## every later draw at its lowest (0) or highest (bound − 1) — for a fixed target level the gains,
## stamina, gold and kill EXP rise with their own draws — refreshed like
## ReinforcementGrowthRules._apply; an opcode 73 re-adjust (level 6) is chained on each variant with
## all its draws low or high. Field-wise minimum and maximum over the variants. Computed once per
## unit (the births' inputs do not depend on the seed).
func _bounds(loop: Dictionary, unit: Dictionary, reward: Dictionary) -> Dictionary:
	var birth: Dictionary = unit["entry_growth"]
	var targets: Array = [[]]
	var picks: Array = birth["draws"].slice(0, 2) if birth["draws"].size() >= 2 else []
	if not picks.is_empty():
		targets = []
		for a in range(int(picks[0]["bound"])):
			for b in range(maxi(1, int(picks[1]["bound"]))): targets.append([a, b])
	var low := {}
	var high := {}
	for target in targets:
		for top in [false, true]:
			var variant := _variant(loop, unit, reward, target, top)
			if variant.is_empty(): return {}
			low = _fold(low, variant, false)
			high = _fold(high, variant, true)
	return {"min": low, "max": high}


func _variant(loop: Dictionary, unit: Dictionary, reward: Dictionary, target: Array, top: bool) -> Dictionary:
	var birth: Dictionary = unit["entry_growth"]
	var calls := [0]
	var rng := func(bound: int) -> int:
		var index: int = calls[0]
		calls[0] += 1
		if index < target.size(): return mini(int(target[index]), bound - 1)
		return bound - 1 if top else 0
	var proposal := EntryGrowthRules.propose(birth["input"], rng)
	if not proposal["ok"]: return {}
	var next := unit.duplicate(true)
	var record := birth.duplicate(true)
	record["draws"] = proposal["draws"]
	record["result"] = proposal["result"]
	next["entry_growth"] = record
	var result: Dictionary = proposal["result"]
	if unit.has("entry_readjust"):
		var again: Dictionary = unit["entry_readjust"].duplicate(true)
		for key in ["level", "exp", "stamina", "kill_exp", "gold", "attributes"]: again["input"][key] = result[key]
		var second := EntryGrowthRules.propose(again["input"], func(bound: int) -> int: return bound - 1 if top else 0)
		if not second["ok"]: return {}
		again["draws"] = second["draws"]
		again["result"] = second["result"]
		next["entry_readjust"] = again
		result = second["result"]
	for key in ["level", "exp", "stamina", "kill_exp"]: next[key] = result[key]
	for key in EntryGrowthRules.KEYS: next["combat_profile"][key] = result["attributes"][key]
	if ProgressionRules.refresh_input_error(next, loop["equipment_items"]) != "": return {}
	next = ProgressionRules._refreshed_growth_stats(next, loop["equipment_items"])
	next["hp"] = next["max_hp"]
	next["mp"] = next["max_mp"]
	var bound := {}
	for key in BOUND_KEYS: bound[key] = _plain(next[key])
	bound["source"] = _plain(EntryGrowthRules.effective_profile(next, PermanentCapabilityRules.effective_profile(next))["source"])
	bound["exp_threshold"] = ProgressionRules.exp_to_next(int(next["level"]))
	if not reward.is_empty(): bound["carried_gold"] = BattleRewardRules.carried_gold(next, int(reward.get("gold", 0)))
	return bound


## Field-wise min (top false) or max of two plain values of the same shape; numbers fold, the rest keeps `into`.
func _fold(into: Variant, value: Variant, top: bool) -> Variant:
	if typeof(into) == TYPE_DICTIONARY and typeof(value) == TYPE_DICTIONARY:
		if into.is_empty(): return value.duplicate(true)
		var out: Dictionary = into.duplicate(true)
		for key in value: out[key] = _fold(into.get(key), value[key], top) if into.has(key) else value[key]
		return out
	if typeof(into) in [TYPE_INT, TYPE_FLOAT] and typeof(value) in [TYPE_INT, TYPE_FLOAT]:
		return maxi(int(into), int(value)) if top else mini(int(into), int(value))
	return into if into != null else value


## JSON-exact values: Vector2i → [x, y], integral floats → int, containers recursively.
func _plain(value: Variant) -> Variant:
	match typeof(value):
		TYPE_VECTOR2I: return [value.x, value.y]
		TYPE_VECTOR2: return [value.x, value.y]
		TYPE_FLOAT: return int(value) if is_finite(value) and value == floor(value) else value
		TYPE_DICTIONARY:
			var out := {}
			for key in value: out[str(key)] = _plain(value[key])
			return out
		TYPE_ARRAY:
			var out: Array = []
			for item in value: out.append(_plain(item))
			return out
	return value
