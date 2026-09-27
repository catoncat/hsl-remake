extends SceneTree

## Autoplay sweep: every campaign.json battle entry (no story / world_map / game_clear
## kind) boots from the product opening, plays its opening to first control, then
## tests/support/Autoplay.gd plays it to a natural outcome with no fixture — player units
## through the loop's public command entry points, AI units through step_ai_turn. One
## `AUTOPLAY level=… outcome=win|fail|dead_end …` line per battle; the run is written to
## content/generated/hsl/development/autoplay/results.json (guarded by
## `hsl check autoplay_results`). The loop RNG is seeded through
## BattleSceneRuntime.LOOP_SEED_ENV (Autoplay.ensure_loop_seed, headless only) so a full run
## is reproducible: the suite is regen-and-compare — it rewrites results.json in place and
## compares the rewrite with the tracked file (tests/support/RegenDiff.gd regen_verdict). A
## level whose outcome (win／fail／dead_end) or dead_end reason changed, or a level added or
## removed, fails the suite and is listed with its fields (review the rewrite, commit it and
## name the flips); any other change — rounds, action counts, the other row fields, the header —
## is drift: one `AUTOPLAY_SWEEP_DRIFT levels=[…] header=[…] fields=N` line plus one
## `levels/<key>/<field>: old -> new` line per field, never a failure, and the rewrite stays in
## the worktree for the merger to commit. The PASS line ends `results=identical|drift`.
## A SCRIPT ERROR fails the run through tools/godot.sh. The other oracle is "no battle ends
## in a dead_end" unless known_dead_ends.json lists it; win or fail is recorded, not asserted
## beyond the comparison with the tracked file. Not a gate suite
## (docs/PLAYABILITY.md R1): run it alone with
## `tools/godot.sh --headless --fixed-fps 60 --script res://tests/run_autoplay_sweep_tests.gd`.
## Developer filters: HSL_AUTOPLAY_LEVELS="51,501" (or HSL_SWEEP_LEVELS) plays only those
## battles and skips the results file; HSL_RNG_SEED=N plays another seed (also skips it) — it seeds
## both the loop and the autoplayer's roll stream, as the chapter walk's attempt seed does;
## HSL_AUTOPLAY_PARTY="hu,tina,hanks,shera" boots each battle with a campaign carry holding
## only those members (an encounter fielded without 雷歐納德, as at levels 30-34; also skips it).
## HSL_AUTOPLAY_HANDOFF=/abs/path/campaign_progress.json boots only the battle a saved campaign
## position (CampaignProgress.save_progress, the product's own hand-off record) points at, with
## its carried party — the chapter walk's stuck battle replayed alone (also skips it); with
## HSL_RNG_SEED=N it replays that walk's CHAPTER_AUTOPLAY_TRY seed=N.
## HSL_AUTOPLAY_STAT_SCALE=1.5 scales the controlled units' attributes at first control
## (Autoplay.apply_stat_scale, a harness diagnostic; also skips it; recorded in `knobs`).
## HSL_AUTOPLAY_BRAIN=scored|lookahead commands player turns with tests/support/AutoplayBrain.gd
## (candidate plans + code scoring; lookahead adds the simulated enemy round) instead of the
## greedy policy, appends `brain=…` to each line and never writes the results file. HSL_AUTOPLAY_COMPARE=1 runs the brain comparison
## instead: the first COMPARE_BATTLES main-line battles the greedy run lost in results.json,
## each played COMPARE_REPEATS times per mode (HSL_AUTOPLAY_BRAIN_MODES, default
## greedy,scored; HSL_AUTOPLAY_BRAIN_REPEATS), written to brain_comparison.json (guarded by
## `hsl check autoplay_brain`) with one `AUTOPLAY_BRAIN_COMPARE mode=…` line per mode. With
## the loop seeded the repeats are a residual-variance check, not a necessity.

const RuntimeScene = preload("res://game/battle/scene/BattleSceneRuntime.tscn")
const CampaignProgress = preload("res://game/battle/runtime/CampaignProgress.gd")
const BattleScenario = preload("res://game/battle/runtime/BattleScenario.gd")
const Autoplay = preload("res://tests/support/Autoplay.gd")
const Brain = preload("res://tests/support/AutoplayBrain.gd")
const TestSuite = preload("res://tests/support/TestSuite.gd")
const RegenDiff = preload("res://tests/support/RegenDiff.gd")
const GlobalRandom = preload("res://game/sim/GlobalRandomStream.gd")

const RESULTS_PATH := "res://content/generated/hsl/development/autoplay/results.json"
const COMPARISON_PATH := "res://content/generated/hsl/development/autoplay/brain_comparison.json"
const COMPARE_BATTLES := 20
const COMPARE_REPEATS := 3
const KNOWN_DEAD_ENDS_PATH := "res://content/generated/hsl/development/autoplay/known_dead_ends.json"

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _assert_true(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _run() -> void:
	CampaignProgress.pending = {}
	CampaignProgress.resume_prompt_in_headless = false
	var campaign := CampaignProgress.load_campaign()
	if OS.get_environment("HSL_AUTOPLAY_COMPARE") != "":
		await _run_compare(campaign)
		return
	var only: Array = Array(OS.get_environment("HSL_AUTOPLAY_LEVELS").split(",", false))
	if only.is_empty():
		only = Array(OS.get_environment("HSL_SWEEP_LEVELS").split(",", false))
	var mode := Brain.mode_from_environment()
	var known := _load_known_dead_ends()
	var loop_seed := Autoplay.ensure_loop_seed()
	var party: Array = Array(OS.get_environment("HSL_AUTOPLAY_PARTY").split(",", false))
	var handoff := _saved_handoff(OS.get_environment("HSL_AUTOPLAY_HANDOFF"))
	var results := {}
	var tally := {Autoplay.OUTCOME_WIN: 0, Autoplay.OUTCOME_FAIL: 0, Autoplay.OUTCOME_DEAD_END: 0}
	var unknown_dead_ends: Array[String] = []
	var known_dead_ends: Array[String] = []
	var started := Time.get_ticks_msec()
	for key in campaign.get("battles", {}):
		var entry: Dictionary = campaign["battles"][key]
		if entry.has("kind"):
			continue
		if not only.is_empty() and not only.has(str(key)):
			continue
		if not handoff.is_empty() and str(handoff["scenario_path"]) != str(entry.get("scenario", "")):
			continue
		var result := await _autoplay_battle(str(key), str(entry.get("scenario", "")), party, mode, handoff)
		var line := Autoplay.format_line(str(key), result)
		if mode != Brain.MODE_GREEDY:
			line += " brain=%s plans=%d kinds=%s allocations=%d actions=%s" % [mode, int(result["brain"]["plans"]), JSON.stringify(result["brain"]["plan_kinds"]), int(result["brain"]["allocations"]), JSON.stringify(result["actions"])]
			if result["brain"].has("lookahead"):
				line += " lookahead=%s" % JSON.stringify(result["brain"]["lookahead"])
		print(line)
		results[str(key)] = result
		tally[str(result["outcome"])] += 1
		if str(result["outcome"]) == Autoplay.OUTCOME_DEAD_END:
			if known.has(str(key)):
				known_dead_ends.append(str(key))
			else:
				unknown_dead_ends.append(str(key))
	var seconds := float(Time.get_ticks_msec() - started) / 1000.0
	_assert_true(unknown_dead_ends.is_empty(), "every dead_end is listed in %s: unknown=%s" % [KNOWN_DEAD_ENDS_PATH, str(unknown_dead_ends)])
	var compared := ""
	if only.is_empty() and party.is_empty() and handoff.is_empty() and mode == Brain.MODE_GREEDY and loop_seed == Autoplay.DEFAULT_LOOP_SEED and is_equal_approx(Autoplay.stat_scale_from_environment(), 1.0):
		compared = _write_and_compare_results(results, loop_seed)
	await TestSuite.settle_wall_clock(self, 0.3)
	await process_frame
	var summary := "battles=%d win=%d fail=%d dead_end=%d seconds=%.1f" % [results.size(), tally[Autoplay.OUTCOME_WIN], tally[Autoplay.OUTCOME_FAIL], tally[Autoplay.OUTCOME_DEAD_END], seconds]
	if mode != Brain.MODE_GREEDY:
		summary += " brain=%s" % mode
	if not known_dead_ends.is_empty():
		summary += " known_dead_ends=%s" % ",".join(known_dead_ends)
	if compared != "":
		summary += " results=%s" % compared
	if failures.is_empty():
		print("AUTOPLAY_SWEEP_PASS %s" % summary)
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		print("AUTOPLAY_SWEEP_FAIL count=%d %s" % [failures.size(), summary])
		quit(1)


## Brain comparison over the greedy-lost main-line battles; see the file header.
func _run_compare(campaign: Dictionary) -> void:
	Autoplay.ensure_loop_seed()
	var modes: Array = Array(OS.get_environment("HSL_AUTOPLAY_BRAIN_MODES").split(",", false))
	if modes.is_empty():
		modes = [Brain.MODE_GREEDY, Brain.MODE_SCORED]
	for mode in modes:
		_assert_true(mode in Brain.MODES, "HSL_AUTOPLAY_BRAIN_MODES entry %s is a known brain mode %s" % [str(mode), str(Brain.MODES)])
	var repeats := COMPARE_REPEATS
	if OS.get_environment("HSL_AUTOPLAY_BRAIN_REPEATS").is_valid_int():
		repeats = maxi(1, int(OS.get_environment("HSL_AUTOPLAY_BRAIN_REPEATS")))
	var only: Array = Array(OS.get_environment("HSL_AUTOPLAY_LEVELS").split(",", false))
	var levels := _greedy_lost_main_line(campaign)
	if not only.is_empty():
		levels = levels.filter(func(level): return only.has(str(level)))
	var battles := {}
	var summary := {}
	for mode in modes:
		summary[mode] = {"runs": 0, Autoplay.OUTCOME_WIN: 0, Autoplay.OUTCOME_FAIL: 0, Autoplay.OUTCOME_DEAD_END: 0, "seconds": 0.0}
	var started := Time.get_ticks_msec()
	if failures.is_empty():
		for level in levels:
			var entry: Dictionary = campaign["battles"][level]
			battles[level] = {}
			for mode in modes:
				var row := {"runs": [], Autoplay.OUTCOME_WIN: 0, Autoplay.OUTCOME_FAIL: 0, Autoplay.OUTCOME_DEAD_END: 0, "plan_kinds": {}}
				for _repeat in range(repeats):
					var result := await _autoplay_battle(str(level), str(entry.get("scenario", "")), [], str(mode))
					var line := Autoplay.format_line(str(level), result) + " mode=%s" % str(mode)
					var run := {"outcome": str(result["outcome"]), "battle_outcome": result["battle_outcome"], "rounds": int(result["rounds"]), "seconds": snappedf(float(result["seconds"]), 0.1)}
					if str(result["outcome"]) == Autoplay.OUTCOME_DEAD_END:
						run["reason"] = str(result["reason"])
					if result.has("brain"):
						line += " plans=%d kinds=%s" % [int(result["brain"]["plans"]), JSON.stringify(result["brain"]["plan_kinds"])]
						run["plans"] = int(result["brain"]["plans"])
						if result["brain"].has("lookahead"):
							line += " lookahead=%s" % JSON.stringify(result["brain"]["lookahead"])
							run["lookahead"] = result["brain"]["lookahead"]
						for kind in result["brain"]["plan_kinds"]:
							row["plan_kinds"][kind] = int(row["plan_kinds"].get(kind, 0)) + int(result["brain"]["plan_kinds"][kind])
					print(line)
					row["runs"].append(run)
					row[str(result["outcome"])] += 1
					summary[mode]["runs"] += 1
					summary[mode][str(result["outcome"])] += 1
					summary[mode]["seconds"] += float(result["seconds"])
				battles[level][mode] = row
	var seconds := float(Time.get_ticks_msec() - started) / 1000.0
	for mode in modes:
		summary[mode]["seconds"] = snappedf(float(summary[mode]["seconds"]), 0.1)
		print("AUTOPLAY_BRAIN_COMPARE mode=%s battles=%d repeats=%d runs=%d win=%d fail=%d dead_end=%d seconds=%.1f" % [str(mode), levels.size(), repeats, int(summary[mode]["runs"]), int(summary[mode][Autoplay.OUTCOME_WIN]), int(summary[mode][Autoplay.OUTCOME_FAIL]), int(summary[mode][Autoplay.OUTCOME_DEAD_END]), float(summary[mode]["seconds"])])
	if only.is_empty() and failures.is_empty():
		var policies := {}
		for mode in modes:
			policies[mode] = Brain.POLICIES[mode]
		var payload := {"schema": "hsl_autoplay_brain_comparison.v1", "policies": policies,
			"selection": "first %d main-line battles (key < 500) whose greedy outcome in results.json is fail, in campaign order" % COMPARE_BATTLES,
			"round_limit": Autoplay.DEFAULT_ROUND_LIMIT, "seed": Autoplay.ensure_loop_seed(), "repeats": repeats, "modes": modes, "levels": levels, "evidence_tier": "current-godot",
			"knobs": {"stat_scale": Autoplay.stat_scale_from_environment()},
			"note": "Natural outcomes of the remake rules under the listed autoplay policies (tests/support/Autoplay.gd, tests/support/AutoplayBrain.gd) with the loop RNG seeded; wins are counted over repeats as a residual-variance check; not evidence about original balance.",
			"seconds": snappedf(seconds, 0.1), "summary": summary, "battles": battles}
		var file := FileAccess.open(COMPARISON_PATH, FileAccess.WRITE)
		_assert_true(file != null, "%s is writable" % COMPARISON_PATH)
		if file != null:
			file.store_string(JSON.stringify(payload, "  ", false) + "\n")
			file.close()
	await TestSuite.settle_wall_clock(self, 0.3)
	await process_frame
	if failures.is_empty():
		print("AUTOPLAY_BRAIN_COMPARE_PASS battles=%d modes=%s repeats=%d seconds=%.1f" % [levels.size(), ",".join(modes), repeats, seconds])
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		print("AUTOPLAY_BRAIN_COMPARE_FAIL count=%d" % failures.size())
		quit(1)


## The first COMPARE_BATTLES main-line battles (key < 500) the tracked greedy run lost, in campaign order.
func _greedy_lost_main_line(campaign: Dictionary) -> Array:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(RESULTS_PATH))
	_assert_true(parsed is Dictionary and parsed.get("schema") == "hsl_autoplay_results.v1", "%s parses with its schema" % RESULTS_PATH)
	var levels: Array = []
	if not parsed is Dictionary:
		return levels
	for key in campaign.get("battles", {}):
		if levels.size() >= COMPARE_BATTLES:
			break
		var entry: Dictionary = campaign["battles"][key]
		if entry.has("kind") or not str(key).is_valid_int() or int(str(key)) >= 500:
			continue
		if str((parsed["levels"].get(str(key), {}) as Dictionary).get("outcome", "")) == Autoplay.OUTCOME_FAIL:
			levels.append(str(key))
	return levels


## The pending hand-off a saved campaign position arms (CampaignProgress.queue_resume's shape);
## {} when `path` is empty. A path that does not hold a progress record is a suite failure.
func _saved_handoff(path: String) -> Dictionary:
	if path == "":
		return {}
	var saved := CampaignProgress.load_progress(path)
	_assert_true(not saved.is_empty(), "HSL_AUTOPLAY_HANDOFF %s holds a campaign progress record" % path)
	if saved.is_empty():
		return {}
	var handoff := CampaignProgress.queue_resume(saved)
	CampaignProgress.pending = {}
	return handoff


func _boot(path: String, party: Array, handoff: Dictionary = {}) -> Node:
	# Each battle starts the process's global stream afresh from the seed, so a battle's AI
	# and opening levels do not depend on which battles a shard played before it.
	GlobalRandom.reset_session()
	CampaignProgress.pending = {}
	if not handoff.is_empty():
		CampaignProgress.pending = handoff.duplicate(true)
	elif not party.is_empty():
		CampaignProgress.pending = {"schema": CampaignProgress.SCHEMA, "scenario_path": path, "carry": _party_carry(path, party), "from_scenario_id": "autoplay_party_filter", "world": {}}
	var scene = RuntimeScene.instantiate()
	scene.scenario_path = path
	scene.startup_mode = "product_opening"
	root.add_child(scene)
	await process_frame
	await process_frame
	return scene


func _free(scene: Node) -> void:
	if is_instance_valid(scene):
		scene.queue_free()
	await process_frame
	await process_frame


## A carry holding only `party` (unit ids of the scenario's player roster), the way the
## campaign hands a battle a party that lacks members; the units keep their scenario
## templates (CampaignCarryRules.apply restores vitals from the record's actor id).
func _party_carry(path: String, party: Array) -> Dictionary:
	var scenario: Dictionary = BattleScenario.load_file(path)
	var units := {}
	for unit_value in scenario.get("playable_units", []):
		var unit: Dictionary = unit_value
		if str(unit.get("battle_actor_role", "")) == "player_controlled" and party.has(str(unit.get("id", ""))):
			units[str(unit["id"])] = {"actor_id": str(unit.get("actor_id", "")), "attributes": {}}
	_assert_true(units.size() == party.size(), "HSL_AUTOPLAY_PARTY names player units of %s: %s" % [path.get_file(), str(party)])
	return {"schema": "hsl_campaign_carry.v1", "units": units, "loop": {}, "restore_vitals": true}


func _autoplay_battle(key: String, path: String, party: Array, mode: String = Brain.MODE_GREEDY, handoff: Dictionary = {}) -> Dictionary:
	var label := "level %s (%s)" % [key, path.get_file()]
	var scene = await _boot(path, party, handoff)
	var result: Dictionary
	if not bool(scene.play_loop.get("scenario_ok", false)):
		result = {"outcome": Autoplay.OUTCOME_DEAD_END, "battle_outcome": {}, "rounds": 0, "seconds": 0.0, "reason": Autoplay.REASON_EXCEPTION, "unit": "", "round": 0, "detail": "scenario_error=%s" % str(scene.play_loop.get("scenario_error", "")), "actions": {}, "result_page": false}
	else:
		await Autoplay.reach_first_control(self, scene, label, _assert_true)
		var scaled := Autoplay.apply_stat_scale(scene.play_loop, Autoplay.stat_scale_from_environment())
		if not (scaled["scaled"] as Array).is_empty():
			scene.apply_loop(scaled["loop"], "test")
		result = await Autoplay.play_battle(self, scene, Autoplay.DEFAULT_ROUND_LIMIT, Autoplay.ensure_loop_seed(), Brain.create(mode))
	CampaignProgress.pending = {}
	await _free(scene)
	return result


func _load_known_dead_ends() -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(KNOWN_DEAD_ENDS_PATH))
	_assert_true(parsed is Dictionary and parsed.get("schema") == "hsl_autoplay_known_dead_ends.v1", "%s parses with its schema" % KNOWN_DEAD_ENDS_PATH)
	if not parsed is Dictionary:
		return {}
	return parsed.get("levels", {})


## Regen-and-compare: the file holds only seed-determined content (no wall clock) and is
## rewritten in place, then judged by tests/support/RegenDiff.gd regen_verdict (both sides as
## parsed JSON, numbers by value): a level whose RegenDiff.SWEEP_VERDICT_FIELDS (outcome, dead_end
## reason) changed, or that one side lacks,
## fails once — listed with its fields and split into main-line and 5xx encounter levels (an
## encounter's outcome also moves with the random stream); everything else prints one
## AUTOPLAY_SWEEP_DRIFT line with its field lines and passes. Returns the PASS line's
## `results=` word: identical, drift or outcome_changed.
func _write_and_compare_results(results: Dictionary, loop_seed: int) -> String:
	var levels := {}
	for key in results:
		var result: Dictionary = results[key]
		levels[key] = {"outcome": str(result["outcome"]), "battle_outcome": result["battle_outcome"], "rounds": int(result["rounds"]),
			"reason": str(result["reason"]), "unit": str(result["unit"]), "round": int(result["round"]), "detail": str(result["detail"]), "actions": result["actions"], "result_page": bool(result["result_page"])}
	var payload := {"schema": "hsl_autoplay_results.v1", "policy": "greedy_public_commands_v1",
		"round_limit": Autoplay.DEFAULT_ROUND_LIMIT, "seed": 1, "loop_seed": loop_seed, "evidence_tier": "current-godot",
		"note": "Natural outcomes of the remake rules under a greedy autoplayer (tests/support/Autoplay.gd) with the loop RNG seeded (BattleSceneRuntime.LOOP_SEED_ENV); not evidence about original balance.",
		"battles": results.size(), "levels": levels}
	var text := JSON.stringify(payload, "  ", false) + "\n"
	var tracked := FileAccess.get_file_as_string(RESULTS_PATH) if FileAccess.file_exists(RESULTS_PATH) else ""
	var file := FileAccess.open(RESULTS_PATH, FileAccess.WRITE)
	_assert_true(file != null, "%s is writable" % RESULTS_PATH)
	if file != null:
		file.store_string(text)
		file.close()
	var verdict := RegenDiff.regen_verdict(RESULTS_PATH, tracked, text, "levels", RegenDiff.SWEEP_VERDICT_FIELDS)
	if str(verdict["drift"]) != "":
		print("AUTOPLAY_SWEEP_DRIFT %s" % str(verdict["drift"]))
	if str(verdict["failure"]) != "":
		var encounters: Array = (verdict["changed"] as Array).filter(func(key): return str(key).is_valid_int() and int(str(key)) >= 500 and int(str(key)) < 600)
		var main_line: Array = (verdict["changed"] as Array).filter(func(key): return not encounters.has(key))
		_assert_true(false, "%s\n  split: main_line=%s encounter_5xx=%s" % [str(verdict["failure"]), str(main_line), str(encounters)])
		return "outcome_changed"
	return "identical" if bool(verdict["identical"]) else "drift"
