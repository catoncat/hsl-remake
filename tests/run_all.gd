extends SceneTree

## In-process runner for the rule suites: every tests/run_*.gd whose first line is
## `extends "res://tests/support/TestSuite.gd"` runs in this one Godot process, in file
## order, each printing its own result line (`TAG_PASS checks=N`) exactly as it did as a
## stand-alone SceneTree script, followed by `RULE_SUITE_TIMING suite=<file> seconds=<s>`
## (the suite's wall time; tools/verify_runner.py collects these into
## ignored/rule-suite-timings.json and shards the gate by tests/support/suite_timings.json).
## Scene suites (`extends SceneTree`) are not discovered here; tools/verify_runner.py keeps
## them one per process.
##
##   tools/godot.sh --headless --script res://tests/run_all.gd                        # every rule suite
##   tools/godot.sh --headless --script res://tests/run_all.gd -- run_stamina_tests.gd # only the named suites
##
## Isolation between suites is the process-global state a rule suite does not touch
## (no scene boot, no user:// writes); the runner still fails a suite that leaves nodes
## under the root, or one that wrote into a shared loop configuration block
## (BattleLoopConfig.freeze_enabled is on for the whole batch; TestSuite.assert_config_frozen
## runs after every suite).
##
## Every selected suite is loaded before any runs: a suite that does not parse prints
## `SCRIPT_LOAD_FAIL file=<res path>` and the batch exits 1 at once (a failed `load()`
## returns a GDScript that cannot instantiate; calling `new()` on it aborted this coroutine
## and left the process idling until the gate timeout).

const TestSuite = preload("res://tests/support/TestSuite.gd")
const GlobalRandom = preload("res://game/sim/GlobalRandomStream.gd")
## Seed the batch exports as HSL_RNG_SEED when the caller named none, so every stream a suite
## reaches through the headless seam (the process global stream GlobalRandomStream.session,
## a scene's damage stream) repeats run to run; printed as `RULE_SUITES_RNG_SEED`.
const DEFAULT_RNG_SEED := 1
const SUITE_DIR := "res://tests"
const RULE_SUITE_HEADER := 'extends "res://tests/support/TestSuite.gd"'
## Real-clock cap per suite; only a suite that awaits can be interrupted (a synchronous
## suite never yields to the timer), so this is the one watchdog for the whole batch.
const SUITE_TIMEOUT_SECONDS := 300.0

var _unknown_requests := 0


func _initialize() -> void:
	call_deferred("_run")


static func rule_suites() -> Array[String]:
	var names: Array[String] = []
	for file in DirAccess.get_files_at(SUITE_DIR):
		if not (file.begins_with("run_") and file.ends_with(".gd")):
			continue
		var source := FileAccess.get_file_as_string("%s/%s" % [SUITE_DIR, file])
		if source.get_slice("\n", 0).strip_edges() == RULE_SUITE_HEADER:
			names.append(file)
	names.sort()
	return names


func _selected_suites() -> Array[String]:
	var discovered := rule_suites()
	var requested := OS.get_cmdline_user_args()
	if requested.is_empty():
		return discovered
	var selected: Array[String] = []
	for name in requested:
		if discovered.has(name):
			selected.append(name)
		else:
			_unknown_requests += 1
			push_error("run_all: %s is not a rule suite (expected one of %s)" % [name, str(discovered)])
	return selected


func _load_suites(names: Array[String]) -> Dictionary:
	var scripts := {}
	var load_failed := 0
	for name in names:
		var path := "%s/%s" % [SUITE_DIR, name]
		var script := load(path) as GDScript
		if script == null or not script.can_instantiate():
			print("SCRIPT_LOAD_FAIL file=%s" % path)
			load_failed += 1
			continue
		scripts[name] = script
	if load_failed > 0:
		print("RULE_SUITES_FAIL suites=%d load_failed=%d" % [names.size(), load_failed])
		quit(1)
		return {}
	return scripts


func _run() -> void:
	if not OS.get_environment(GlobalRandom.SEED_ENV).is_valid_int():
		OS.set_environment(GlobalRandom.SEED_ENV, str(DEFAULT_RNG_SEED))
		print("RULE_SUITES_RNG_SEED seed=%d source=harness_default" % DEFAULT_RNG_SEED)
	else:
		print("RULE_SUITES_RNG_SEED seed=%s source=environment" % OS.get_environment(GlobalRandom.SEED_ENV))
	GlobalRandom.reset_session()
	var names := _selected_suites()
	var scripts := _load_suites(names)
	if scripts.is_empty() and not names.is_empty():
		return
	var failed := 0
	var total_checks := 0
	TestSuite.LoopConfig.freeze_enabled = true
	for name in names:
		var script: GDScript = scripts[name]
		var suite = script.new()
		suite.attach(self)
		var children_before := root.get_child_count()
		var started_usec := Time.get_ticks_usec()
		var watchdog := create_timer(SUITE_TIMEOUT_SECONDS)
		var expire := func() -> void:
			push_error("run_all: %s exceeded %d s" % [name, int(SUITE_TIMEOUT_SECONDS)])
			print("RULE_SUITES_FAIL suites=%d timeout=%s" % [names.size(), name])
			quit(2)
		watchdog.timeout.connect(expire)
		await suite.run()
		watchdog.timeout.disconnect(expire)
		await process_frame
		suite.assert_config_frozen()
		if root.get_child_count() != children_before:
			suite.failures.append("%s left %d node(s) under the tree root" % [name, root.get_child_count() - children_before])
		print(suite.result_line())
		print("RULE_SUITE_TIMING suite=%s seconds=%.3f" % [name, float(Time.get_ticks_usec() - started_usec) / 1_000_000.0])
		for failure in suite.failures:
			push_error("%s: %s" % [name, failure])
		total_checks += int(suite.checks)
		if not suite.failures.is_empty():
			failed += 1
	if names.is_empty() or failed > 0 or _unknown_requests > 0:
		print("RULE_SUITES_FAIL suites=%d failed=%d unknown=%d checks=%d" % [names.size(), failed, _unknown_requests, total_checks])
		quit(1)
	else:
		print("RULE_SUITES_PASS suites=%d checks=%d" % [names.size(), total_checks])
		quit(0)
