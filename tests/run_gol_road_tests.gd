extends SceneTree
const TestSuite = preload("res://tests/support/TestSuite.gd")
const Loop = preload("res://game/battle/scene/BattlePlayLoop.gd")
const Save = preload("res://game/battle/runtime/BattleCheckpoint.gd")
const Rules = preload("res://game/sim/WinfailScenarioRules.gd")
const BattleOutcome = preload("res://game/sim/BattleOutcome.gd")
const GlobalRandom = preload("res://game/sim/GlobalRandomStream.gd")
const VIEW := {"camera": Vector2(320, 400), "shown_story_events": [], "story_complete": true, "growth_notified_level": 4}
var checks := 0
var failures: Array[String] = []

func _initialize() -> void: call_deferred("run")

static func initial() -> Dictionary:
	return Loop.initialize_roster_growth(Loop.create([], "", Loop.BattleScenario.load_file("res://content/battles/gol_road_battle.json")))

static func ready_event(loop: Dictionary) -> Dictionary:
	var next := loop.duplicate(true)
	# A bounded condition fixture, not a rewrite of the formal encounter: four
	# raiders have already fallen. The real script, generation and RNG still run.
	for actor in next["units"]:
		if actor["actor_id"] == "028" and actor["id"] != "actor028_1":
			Loop._set_unit_defeated(next, actor["id"], true)
	return next


static func attack_fixture() -> Dictionary:
	var loop := initial()
	for id in ["actor028_3", "actor028_4", "actor028_5"]: Loop._set_unit_defeated(loop, id, true)
	var hu := Loop._unit(loop, "hu")
	hu["growth_profile"]["source"]["speed"] += 200
	hu["equipment"].append({"slot": "accessory2", "item_code": 227})
	hu.merge(Loop.ProgressionRules.refresh_growth_stats(hu, loop["equipment_items"]), true)
	hu["hit_bonus_accum"] = 1000
	var victim := Loop._unit(loop, "actor028_2")
	victim["hp"] = 1
	for offset in Loop.weapon_pattern(loop, hu)["offsets"]:
		victim["coord"] = hu["coord"] + Vector2i(int(offset[0]), int(offset[1]))
		if Loop.TraversalRules.placement_error(victim, loop["units"], loop["tiles"], loop["map_size"]) == "": break
	victim["ai_home_coord"] = victim["coord"]
	loop["turn_queue"] = Loop.CoreTurnQueue.rebuild(Loop._queue_actors(loop))
	return Loop.begin_battle(loop)


static func owned_turn(loop: Dictionary, id: String) -> Dictionary:
	var next := loop.duplicate(true)
	# Numerical ability fixtures explicitly enter another actor's fresh turn;
	# retaining Hu's pending second-action lease would be an illegal owner swap.
	Loop._clear_extra_action(next)
	next["turn_queue"] = Loop.CoreTurnQueue.rebuild(Loop._queue_actors(next))
	for index in range(next["turn_queue"]["slots"].size()):
		if next["turn_queue"]["slots"][index]["id"] == id: next["turn_queue"]["index"] = index;break
	return Loop._return_to_player(next, id)

func run() -> void:
	var loop := initial()
	check(loop["scenario_ok"], "source Gol configuration initializes: " + str(loop.get("scenario_error", "")))
	check(loop["units"].size() == 7 and Loop.unit(loop, "tina").is_empty(), "Tina and guards are not pre-created or eligible in phase one")
	check(loop["win_statuses"].is_empty() and loop["event_statuses"] == [0], "first phase has an event, not an early victory")
	check(loop["winfail_script_rules"]["unsupported_tokens"].is_empty(), "source actMEssage spelling uses the canonical opcode instead of being dropped")
	var before := ready_event(loop)
	var fired := Rules.run_event_hooks(before)
	fired = Loop._resolve_outcome(fired)
	check(fired["scenario_ok"], "event generation succeeds: " + str(fired.get("scenario_error", "")))
	check(not Loop.unit(fired, "tina").is_empty(), "actual event installs registered Player2 in the sole battle roster")
	check(fired["units"].filter(func(a): return a["actor_id"] == "023").size() == 4, "all four original pursuit inserts materialize")
	check(not BattleOutcome.decided(fired) and fired["win_statuses"] == [0], "second-phase result sees the newly generated roster, not an obsolete clear")
	check(fired["winfail_runtime"]["fired"].size() == 1, "the source event fires once")
	check(before["units"].size() == 7, "script proposal preserves its input")
	if not Loop.unit(fired, "tina").is_empty():
		birth_and_persistence(loop, fired)
		atomic_proposals(before)
		combat_and_terminals(fired)
	actual_action_transition()
	await rendering_boundary()
	print("GOL_ROAD_TESTS_", "PASS" if failures.is_empty() else "FAIL", " checks=", checks)
	call_deferred("quit", 0 if failures.is_empty() else 1)

func birth_and_persistence(initial_state: Dictionary, fired: Dictionary) -> void:
	var tina := Loop.unit(fired, "tina")
	check(tina["actor_id"] == "002" and tina["weapon_code"] == 82 and tina["player_commandable"] and tina["growth_profile"]["allocation"] == "manual", "event Player2 retains the real priest identity/equipment/manual control")
	check(tina["hp"] == tina["max_hp"] and tina["learned_skills"].is_empty(), "new registered player initializes once without random allocation or fictional learning")
	check(Loop.SkillResolutionRules.ownership_error(tina, "magic:magicWATER:magicCode06", fired["skill_book"]) == "", "new Tina owns her source healing immediately, not a mage's skills")
	var levels: Array = fired["units"].filter(func(a): return a["growth_profile"]["allocation"] == "manual").map(func(a): return a["level"])
	for guard in fired["units"].filter(func(a): return a["actor_id"] == "023"):
		check(guard["entry_growth"]["input"]["party_levels"] == levels, "each guard uses the already-registered three-member party and ordered birth stream")
		check(guard["battle_actor_role"] == Loop.ROLE_ENEMY and not guard["player_commandable"], "pursuers retain enemy AI and their own job")
	check(Loop.ReinforcementGrowth.state_error(fired) == "", "whole event draws the births back to back on the global stream, each receipt independently validated")
	check(Loop.unit(fired, "actor028_1")["departed"] and not fired["rewarded_unit_ids"].has("actor028_1"), "remaining raider departs without a fabricated kill/reward")
	check(Loop.ScriptActors.state_error(fired) == "", "script creation ledger validates independently")
	var quiet := Loop.begin_battle(fired)
	var view := VIEW.duplicate(true)
	view["script_cutscene_consumed"] = 1
	var saved := Save.encode(quiet, view)
	check(saved["ok"], "event-complete F9 boundary: " + str(saved.get("reason", "")))
	check(not Save.encode(quiet, VIEW)["ok"], "unplayed installation/cutscene cannot be falsely saved as already seen")
	if saved["ok"]:
		var restored := Save.decode(saved["bytes"], quiet)
		check(restored["ok"] and restored["snapshot"]["loop"] == quiet, "F9 restores actors, birth draws, actual stage and receipts byte-equivalently")
		# The scan's handoff also bumps the counter word 0x4c1ad4 (original_poison_gas.md); nothing else may change.
		var rescanned: Dictionary = Loop._resolve_outcome(Rules.run_event_hooks(restored["snapshot"]["loop"]))
		rescanned["winfail_runtime"]["handoff_counter"] = int(quiet["winfail_runtime"]["handoff_counter"])
		check(rescanned == quiet, "post-restore event check cannot recreate, reroll, replay the grant or move units again")
	for variant in ["program", "duplicate", "birth"]:
		var bad := quiet.duplicate(true)
		match variant:
			"program": bad["script_actor_transactions"][0]["actions"][0]["name"] = "actWait"
			"duplicate": bad["script_actor_transactions"][0]["created_ids"].append("tina")
			"birth": Loop._unit(bad, "tina")["script_creation"]["player_growth"]["level"] += 1
		check(not Save.encode(bad, view)["ok"], "F9 rejects a contradictory script actor ledger: " + variant)
	var carry: Dictionary = JSON.parse_string(JSON.stringify(Loop.CampaignCarryRules.capture(quiet)))
	check(carry["units"].has("tina") and carry["units"]["tina"]["actor_id"] == "002" and TestSuite.carries_no_stream(carry), "actual campaign JSON includes the joined priest and no global stream")
	var replay := fired.duplicate(true)
	Loop._unit(replay, "tina")["hp"] = 1
	var existing := replay.duplicate(true)
	var outcome := Loop.ScriptActors._install(replay, replay["script_actor_source"]["templates"]["obj_Story_Player2"], "obj_Story_Player2", 1, 0, {})
	check(outcome["ok"] and not outcome["created"] and replay == existing, "repeat installation of the existing slot never resets health, equipment, progress or RNG")


func atomic_proposals(before: Dictionary) -> void:
	var pending := Rules.run_event_hooks(before)
	var broken := pending.duplicate(true)
	TestSuite.own(broken, "script_actor_source")["templates"]["obj_Story_Level2_Enemy23"]["source_actor_id"] = "026"
	var untouched := broken.duplicate(true)
	var result := Loop.ScriptActors.prepare(broken)
	check(not result["ok"] and broken == untouched, "bad later guard source rejects the whole proposal without partial Tina or RNG commit")
	var actor: Dictionary = before["units"][0].duplicate(true)
	var landing := Loop.ScriptActors._landing(actor, Vector2i(-100000, -100000), before["units"], before)
	check(landing["ok"] and landing["coord"].x >= 0 and landing["coord"].y >= 0, "outside cinematic insertion is bounded by the real map, not by the magnitude of a script coordinate")
	var blocked := pending.duplicate(true)
	var last: Dictionary = blocked["script_actor_source"]["templates"]["obj_Story_Level2_Enemy23"]
	last["actor"]["growth_profile"]["job_code"] = 999
	untouched = blocked.duplicate(true)
	result = Loop.ScriptActors.prepare(blocked)
	check(not result["ok"] and blocked == untouched, "later growth failure cannot leak an earlier newly installed player or advanced random stream")


func combat_and_terminals(fired: Dictionary) -> void:
	for dead_id in ["leonard", "hu", "tina"]:
		var state := fired.duplicate(true)
		Loop._set_unit_defeated(state, dead_id, true)
		state = Loop._resolve_outcome(state)
		check(BattleOutcome.lost(state), "second phase checks actual registered member death: " + dead_id)
		check(Loop.step_ai_turn(state) == state and Loop.finish_exhausted_action(state) == state, "terminal freezes further installation/growth/actions: " + dead_id)
	var won := fired.duplicate(true)
	var guards: Array = won["units"].filter(func(a): return a["actor_id"] == "023")
	for index in range(guards.size() - 1): Loop._set_unit_defeated(won, guards[index]["id"], true)
	won = Loop._resolve_outcome(won)
	check(BattleOutcome.won(won) and won["next_level_event"] == [2, 55], "source second phase leaves one retreating pursuer and leads to the camp, not an invented escape")
	check(won["script_actor_transactions"].size() == 2 and Loop.ScriptActors.state_error(won) == "", "terminal script movement has one committed receipt, no second installation")
	var view := VIEW.duplicate(true);view["script_cutscene_consumed"] = 2
	check(Save.encode(won, view)["ok"], "completed victory movement/camp destination are checkpointable")
	var restarted := initial()
	check(restarted["units"].size() == 7 and restarted["script_actor_transactions"].is_empty() and Loop.unit(restarted, "tina").is_empty(), "fresh restart returns to original first phase without retaining the completed grant")


func actual_action_transition() -> void:
	var before := attack_fixture()
	var attacked := Loop.attack_target(Loop.choose_command(before, "attack"), "actor028_2", func(_n): return 0)
	check(attacked["scenario_ok"] and attacked["units"].size() == before["units"].size() and Loop.unit(attacked, "actor028_2")["defeated"], "the lethal strike itself scans nothing: the arrival waits for a completion scan")
	check(attacked["last_combat"]["attacker_id"] == "hu" and attacked["last_combat"]["defender_id"] == "actor028_2", "the completed attack receipt keeps its participants")
	check(Loop.loot_waiting(attacked) and Loop.finish_exhausted_action(attacked) == attacked, "the lethal action's pending loot blocks its completion and the White Wings second action")
	var settled := Loop.finish_rewards(attacked, attacked["settlement"]["sequence"], attacked["settlement"]["revision"], false, true)
	check(not Loop.loot_waiting(settled), "explicit defer closes the current reward interaction without dropping the item")
	var repeat := Loop.finish_exhausted_action(settled)
	check(repeat["selected_unit_id"] == "hu" and repeat["extra_action"]["pending"] and not repeat["moved_this_action"], "the lethal first half completes into an independent White Wings second action")
	check(TestSuite.no_draw(repeat, attacked, "global") and repeat["units"].size() == before["units"].size(), "the first half of the extra action is not scanned (its repeat skips 0x407510): no arrival yet")
	var second := Loop.choose_command(repeat, "wait")
	check(second["scenario_ok"] and second["units"].size() == 12 and not Loop.unit(second, "tina").is_empty(), "the second half's completion scan triggers the original arrival event, not a direct spawner call")
	var later := Loop.choose_command(owned_turn(second, "tina"), "wait")
	check(later["script_actor_transactions"] == second["script_actor_transactions"] and later["units"].size() == 12, "a later completion cannot sample the completed arrival again")
	var resumed := owned_turn(second, "tina")
	var target := Loop._unit(resumed, "leonard")
	target["hp"] = maxi(1, int(target["hp"]) - 8)
	var before_heal := resumed.duplicate(true)
	var heal := Loop.attack_target(Loop.choose_magic(Loop.choose_command(resumed, "magic"), "magic:magicWATER:magicCode06"), "leonard", func(_n): return 0)
	check(heal["last_attack"].get("magic_key") == "heal" and Loop.unit(heal, "leonard")["hp"] > Loop.unit(before_heal, "leonard")["hp"], "joined priest's real source healing settles through the common player transaction")
	check(Loop.unit(heal, "tina")["mp"] == Loop.unit(before_heal, "tina")["mp"] - 6, "joined ability pays its actual cost once")
	for condition in ["no_magic", "paralysis", "empty_mp"]:
		var state := owned_turn(second, "tina")
		var actor := Loop._unit(state, "tina")
		if condition == "empty_mp": actor["mp"] = 0
		else: actor.merge(Loop.StatusEffectRules.apply(actor, condition, 2)["changes"], true)
		var unchanged := state.duplicate(true)
		var draws := [0]
		var denied := Loop.attack_target(Loop.choose_magic(Loop.choose_command(state, "magic"), "magic:magicWATER:magicCode06"), "leonard", func(_n): draws[0] += 1;return 0)
		check(draws[0] == 0 and denied["units"] == unchanged["units"] and TestSuite.no_draw(denied, unchanged, "global"), "joined priest rejects stale/resource/status-invalid casting atomically: " + condition)
	var current := owned_turn(second, "tina")
	var unit := Loop._unit(current, "tina")
	unit["permanent_gains"]["attack_power"] = 3
	unit.merge(Loop.ProgressionRules.refresh_growth_stats(unit, current["equipment_items"]), true)
	var birth: Dictionary = unit["script_creation"].duplicate(true)
	var grown := Loop.ProgressionRules.resolve_experience(unit, 1000, current["equipment_items"])
	check(grown["level"] > unit["level"] and grown["script_creation"] == birth and grown["permanent_gains"] == unit["permanent_gains"], "subsequent multi-level growth preserves committed installation and permanent gain sources")


func rendering_boundary() -> void:
	var runtime = load("res://game/battle/development/GolRoad.tscn").instantiate()
	runtime.startup_mode = "dev_first_control"
	root.add_child(runtime);runtime.set_process(false)
	# Let the audio mixer consume the scene's queued startup before stopping it.
	# This test drives the visual event synchronously, not at audio wall-clock pace.
	await create_timer(0.15).timeout
	var input := Loop.begin_battle(ready_event(initial()))
	runtime.apply_loop(input, "test")
	var actor_node: Node = runtime.actor_node_for_unit("leonard")
	var position: Vector2 = actor_node.position
	runtime.apply_loop(Loop._resolve_outcome(Rules.run_event_hooks(input)), "test")
	check(runtime.actor_node_for_unit("tina") == null and runtime.actor_node_for_unit("leonard").position == position, "post-hit state commit does not preview an unplayed installation or future scripted position")
	var source: Dictionary = runtime.first_battle_scenario["scenario_rules"]["status_timelines"]["event_0"]
	var events: Array = runtime.ScriptActorsPresentation.attach(runtime, source["events"], 0)
	runtime.script_cutscene_consumed = 1
	if runtime.opening_coordinator == null:
		runtime.opening_coordinator = runtime.BattleOpeningCoordinator.new()
		runtime.opening_coordinator.runtime = runtime
		runtime.add_child(runtime.opening_coordinator)
	runtime.opening_coordinator.start_cutscene("event_0", events)
	check(runtime.actor_node_for_unit("tina") != null and runtime.actor_node_for_unit("tina").visible, "first actual installation token reveals only the already-committed priest")
	check(runtime.play_loop["units"].size() == 12, "renderer never creates a second gameplay actor")
	for node in runtime.find_children("*", "AudioStreamPlayer", true, false): node.stop();node.stream = null
	await create_timer(0.15).timeout
	root.remove_child(runtime);runtime.queue_free()
	await process_frame
	await create_timer(0.3).timeout


func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)
		push_error(message)
