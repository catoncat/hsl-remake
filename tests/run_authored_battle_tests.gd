extends SceneTree
## The battle-scenario contract (content/schema/battle.schema.json) end to end on a
## minimal hand-written battle (tests/support/authored_minimal_battle.json — the text
## docs/MODDING_LEVELS.md shows an author): only the required keys and the shared tables,
## no evidence ledgers. BattleScenario.load_file validates it and fills the defaults,
## BattlePlayLoop.create accepts it, the runtime boots it at first control and the
## fixture-free Autoplay driver plays rounds of it; a scenario missing a required key
## and a hand-built dictionary that skipped load_file fail with the contract's own text.
const BattleScenario = preload("res://game/battle/runtime/BattleScenario.gd")
const UnitSchema = preload("res://game/sim/UnitSchema.gd")
const Loop = preload("res://game/battle/scene/BattlePlayLoop.gd")
const Autoplay = preload("res://tests/support/Autoplay.gd")
const TestSuite = preload("res://tests/support/TestSuite.gd")
const RuntimeScene = preload("res://game/battle/scene/BattleSceneRuntime.tscn")
const PATH := "res://tests/support/authored_minimal_battle.json"

var checks := 0
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("run")


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)


func run() -> void:
	_contract_cases()
	await _autoplay_case()
	await TestSuite.settle_wall_clock(self, 0.3)
	for failure in failures:
		push_error(failure)
	print("AUTHORED_BATTLE_TESTS_", "PASS" if failures.is_empty() else "FAIL", " checks=", checks)
	quit(0 if failures.is_empty() else 1)


func _contract_cases() -> void:
	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	for key in ["commands", "skill_rules", "level"]:
		check(not raw.has(key), "the minimal battle omits the defaulted key " + key)
	check(not raw["scenario_rules"].has("events"), "the minimal battle omits scenario_rules.events")
	var scenario := BattleScenario.load_file(PATH)
	check(bool(scenario.get("ok", false)), "the minimal battle loads: " + str(scenario.get("error", "")))
	check(scenario.get("contract") == BattleScenario.BATTLE_CONTRACT, "load_file marks the validated contract")
	check(scenario["skill_rules"] == {} and scenario["commands"] == {"has_magic": false, "has_special": false} and scenario["level"] == 0, "load_file fills the top-level defaults")
	check(scenario["scenario_rules"]["events"] == {} and scenario["scenario_rules"]["reinforcements"] == [] and scenario["scenario_rules"]["script_fallback"]["escape_zone"] == [] and scenario["scenario_rules"]["allow_optional_clear_after_switch"] == false, "load_file fills the scenario_rules defaults")
	var units := BattleScenario.units(scenario)
	check(units.size() == 3 and units.all(func(unit): return UnitSchema.evidence_tier(unit, "vitals") == UnitSchema.AUTHORED_TIER), "units without evidence ledgers are labelled authored")
	check(UnitSchema.roster_error(units) == "", "the authored roster meets the unit contract: " + UnitSchema.roster_error(units))
	var loop := Loop.create([], "", scenario)
	check(bool(loop["scenario_ok"]), "create() accepts the minimal battle: " + str(loop.get("scenario_error", "")))
	check(loop["skill_rules"] == {} and loop["escape_zone"] == [] and loop["objective_phase"] == "clear" and loop["allow_optional_clear_after_switch"] == false and loop["reinforcement_templates"] == [], "the loop reads the defaulted keys")
	check(loop["win_statuses"] == [0] and loop["fail_statuses"] == [0], "the reused seed's win and fail statuses are armed")
	var missing := raw.duplicate(true)
	missing["scenario_rules"].erase("initial_objective_phase")
	var refused := Loop.create([], "", missing)
	check(not bool(refused["scenario_ok"]) and refused["interaction"] == "scenario_error", "an in-memory scenario missing a required key fails create()")
	check(str(refused.get("scenario_error", "")) == "battle_schema:$.scenario_rules: missing required key 'initial_objective_phase'", "the failure names the contract violation: " + str(refused.get("scenario_error", "")))
	var wrong := raw.duplicate(true)
	wrong["resources"].erase("terrain")
	check(BattleScenario.battle_error(wrong) == "$.resources: missing required key 'terrain'", "a battle without a terrain resource is a contract violation, not a terrain-load fallback")
	var typed := raw.duplicate(true)
	typed["skill_rules"] = {"initial_stamina": "40"}
	check(BattleScenario.battle_error(typed) == "$.skill_rules.initial_stamina: expected integer, got string", "typed optional keys are checked when present")
	check(BattleScenario.battle_error({"schema": "hsl_story_scene.v1", "rule_adapter": "story_scene"}) == "", "a story scene is not a battle and is not held to the battle contract")
	var story := BattleScenario.load_file("res://content/battles/story_058.json")
	check(bool(story.get("ok", false)) and not story.has("contract"), "story scenes still load untouched")


func _autoplay_case() -> void:
	# Seed the scene's streams (headless seam) before it boots: without it a direct run seeds
	# the damage stream from the clock and the few rounds below are not repeatable.
	Autoplay.ensure_loop_seed()
	var scene = RuntimeScene.instantiate()
	scene.scenario_path = PATH
	scene.startup_mode = "dev_first_control"
	root.add_child(scene)
	await process_frame
	await process_frame
	check(bool(scene.play_loop.get("scenario_ok", false)), "the runtime boots the minimal battle: " + str(scene.play_loop.get("scenario_error", "")))
	check(str(scene.interaction_state) != "opening_timeline", "dev_first_control starts the minimal battle at first control")
	var result := await Autoplay.play_battle(self, scene, 3, 1)
	check(int(result["rounds"]) >= 2 or str(result["outcome"]) != Autoplay.OUTCOME_DEAD_END, "autoplay plays at least one full round: " + Autoplay.format_line("authored", result))
	# Luck-free on any seed (probed 1..20): the fixture hero's 120 HP outlasts the levelled
	# wolves' opening strikes, so the player always gets control; a quick win can leave the
	# AI a single step, so both sides acting is one step each.
	check(int(result["actions"]["ai_steps"]) >= 1 and int(result["actions"]["attack"]) + int(result["actions"]["move_then_attack"]) + int(result["actions"]["move"]) + int(result["actions"]["wait"]) >= 1, "both sides acted: " + str(result["actions"]))
	check(str(result["reason"]) != Autoplay.REASON_EXCEPTION, "no scenario_error while playing: " + str(result.get("detail", "")))
	print(Autoplay.format_line("authored_minimal", result))
	scene.queue_free()
	await process_frame
	await process_frame
