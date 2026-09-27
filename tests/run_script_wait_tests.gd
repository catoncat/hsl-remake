extends SceneTree
const TestSuite = preload("res://tests/support/TestSuite.gd")
const BattlePlayLoop = preload("res://game/sim/loop/BattlePlayLoop.gd")
const BattleLoopScript = preload("res://game/sim/loop/BattleLoopScript.gd")
const WinfailScenarioRules = preload("res://game/sim/WinfailScenarioRules.gd")
const WinfailActions = preload("res://game/sim/WinfailActions.gd")
const ScriptWaitRules = preload("res://game/sim/ScriptWaitRules.gd")
const BattleCheckpoint = preload("res://game/battle/runtime/BattleCheckpoint.gd")
const run_mobile_jobs_tests = preload("res://tests/run_mobile_jobs_tests.gd")
const run_ai_navigation_tests = preload("res://tests/run_ai_navigation_tests.gd")
const ScriptDepartureFixture = preload("res://tests/ScriptDepartureFixture.gd")
const run_departure_tests = preload("res://tests/run_departure_tests.gd")
const run_weapon_effect_tests = preload("res://tests/run_weapon_effect_tests.gd")
const ScriptWaitFixture = preload("res://tests/ScriptWaitFixture.gd")
const BattleFixture = preload("res://tests/support/BattleFixture.gd")
const BattleOutcome = preload("res://game/sim/BattleOutcome.gd")
const VIEW := {"camera": Vector2(320,240), "shown_story_events": [], "story_complete": true, "growth_notified_level": 1}
var checks := 0
var failures: Array[String] = []

func _initialize() -> void: call_deferred("run")

static func fixture() -> Dictionary:
	var loop := run_mobile_jobs_tests.fixture("004", true)
	var foe := BattlePlayLoop.unit_ref(loop, "enemy026_1")
	var second := foe.duplicate(true)
	second.merge({"id":"enemy026_2", "coord":Vector2i(15,18), "ai_home_coord":Vector2i(15,18)}, true)
	loop["units"].append(second)
	loop["winfail_runtime"] = {"fired": [], "wait_requests": [], "inserts": [], "spawn_target": {}, "departed_unit_ids": [], "departure_requests": [],
		"actor_bindings": {"SID_PLAYER0/1":"thief", "SID_PLAYER1/1":"tina", "SID_ENEMY026/1":"enemy026_1", "SID_ENEMY026/2":"enemy026_2"}}
	loop["winfail_script_rules"] = {"source_level":999}
	return loop

static func assign(loop: Dictionary, serial: int, value: int, token: String = "SID_ENEMY026") -> Dictionary:
	var next := loop.duplicate(true)
	WinfailActions.apply_actions(next, {"key":"event_wait", "actions":[{"name":"actSetWaitRound", "args":[token,str(serial),str(value)]}]}, "test")
	BattleLoopScript.consume_script_waits(next)
	return next

func run() -> void:
	create_timer(120).timeout.connect(func(): push_error("SCRIPT_WAIT_TIMEOUT"); quit(2))
	native_setters()
	source_initialization()
	insertion_order()
	wake_and_actions()
	await object_synchronization()
	print("SCRIPT_WAIT_TESTS_", "PASS" if failures.is_empty() else "FAIL", " checks=", checks)
	quit(0 if failures.is_empty() else 1)

func native_setters() -> void:
	var packet: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://docs/evidence_packets/static_reverse/original_script_wait.json"))
	for row in packet["vm"]:
		var c: Dictionary = row["input"]
		if int(c["opcode"]) != 34 or int(c["value"]) < 0: continue
		var initial := fixture()
		var actor_order: Array = ["enemy026_1", "enemy026_2", "tina"]
		# The original synthetic third actor uses code23. Bind that code explicitly.
		BattlePlayLoop.unit_ref(initial,"tina")["actor_id"] = "023"
		for id in actor_order: BattlePlayLoop.unit_ref(initial,id)["ai_wait_remaining"] = int(c["old"])
		var before := initial.duplicate(true)
		var next := assign(initial,int(c["serial"]),int(c["value"]),"SID_ENEMY%03d" % int(c["code"]))
		check(initial == before and next["scenario_ok"], "source setter is an immutable outer transaction")
		for i in range(actor_order.size()):
			check(BattlePlayLoop.unit(next,actor_order[i])["ai_wait_remaining"] == int(row["native"]["wait_values"][i]), "native code/serial write matches exact actor")
		for key in ["turn_queue","extra_action","gold",TestSuite.STREAM_KEYS["damage"],TestSuite.STREAM_KEYS["reward"],"action_end_sequence","item_use_sequence"]:
			check(next[key] == initial[key], "assignment does not change " + key)
	var missing := assign(fixture(),1,3,"SID_ENEMY999")
	check(missing["script_wait_cursor"] == 1 and missing["units"] == fixture()["units"], "missing target advances its request without actor mutation")
	check(ScriptWaitRules.select(["a","b"],0) == ["a"] and ScriptWaitRules.select(["a","b"],200) == ["b"], "source serial zero/oversize select first/last registered instance")

func source_initialization() -> void:
	var config := BattlePlayLoop.BattleScenario.load_file("res://content/battles/battle_052.json")
	var battle := BattlePlayLoop.create([],"",config)
	check(battle["scenario_ok"], "source second battle starts: " + str(battle.get("scenario_error")))
	if not battle["scenario_ok"]: return
	var assignments: Array = battle["script_wait_source"]["initial"]
	check(assignments.size() == 4, "STORY052 supplies four wait2 insertions, not eight")
	for row in assignments:
		check(row["rounds"] == 2 and BattlePlayLoop.unit(battle,row["unit_id"])["ai_wait_remaining"] == 2, "source wait is live before first control")
	var first := BattlePlayLoop.begin_battle(battle)
	var carry := BattlePlayLoop.CampaignCarryRules.capture(run_mobile_jobs_tests.fixture())
	var carried := BattlePlayLoop.apply_campaign_carry(battle, carry)
	for row in assignments:
		check(BattlePlayLoop.unit(first,row["unit_id"])["ai_wait_remaining"] == 2 and BattlePlayLoop.unit(carried,row["unit_id"])["ai_wait_remaining"] == 2, "first control and campaign data do not replace enemy script waits")
	check(BattleFixture.loop()["script_wait_source"]["initial"].is_empty(), "first battle retains its source defaults")
	var third := BattlePlayLoop.create([],"",BattlePlayLoop.BattleScenario.load_file("res://content/battles/battle_053.json"))
	check(third["scenario_ok"] and third["script_wait_source"]["initial"].is_empty(), "third battle inserts without wait token do not acquire a wait")
	# STORY006 inserts three Enemy23 and then one Enemy24 whose actSetPrevInsertObjectWaitRound(3)
	# follows: insert bindings are numbered per symbol, so the captain (Enemy24/insert1) waits.
	var sixth := BattlePlayLoop.create([],"",BattlePlayLoop.BattleScenario.load_file("res://content/battles/battle_006.json"))
	check(sixth["scenario_ok"], "level 6 battle starts: " + str(sixth.get("scenario_error")))
	if sixth["scenario_ok"]:
		var sixth_rows: Array = sixth["script_wait_source"]["initial"]
		check(sixth_rows.size() == 1 and sixth_rows[0]["unit_id"] == "guard024_1" and sixth_rows[0]["rounds"] == 3 and BattlePlayLoop.unit(sixth,"guard024_1")["ai_wait_remaining"] == 3, "STORY006 mixed-symbol inserts bind the wait round to the captain: " + str(sixth_rows))
		check(BattlePlayLoop.unit(sixth,"guard023_3")["ai_wait_remaining"] == 0, "the third soldier keeps its default wait")

func insertion_order() -> void:
	var loop := fixture()
	var actions: Array = [{"name":"actInsertObject","args":["obj_guard","0","0"]},
		{"name":"actSetPrevInsertObjectWaitRound","args":["2"]},
		{"name":"actSetWaitRound","args":["SID_ENEMY026","3","7"]},
		{"name":"actSetPrevInsertObjectWaitRound","args":["1"]}]
	WinfailActions.apply_actions(loop,{"key":"event_insert","actions":actions,"inserts":[{"class_id":"Enemy026","object_symbol":"obj_guard","wait_round":1}]},"test")
	BattleLoopScript.consume_script_waits(loop)
	check(loop["scenario_ok"] and loop["winfail_runtime"]["inserts"][0]["wait_round"] == 1, "previous/explicit/previous writes keep original action order")
	check(loop["winfail_runtime"]["wait_requests"][1]["insert_index"] == 0, "code/serial query can address an inserted actor awaiting materialization")
	loop["rule_adapter"] = "winfail"
	loop["winfail_runtime"]["initial_class_unit_ids"] = {"Enemy026":["enemy026_1","enemy026_2"]}
	loop["reinforcement_templates"] = [BattlePlayLoop.unit(loop,"enemy026_1")]
	loop["reinforcement_spawn_cells"] = [Vector2i(17,16)]
	BattleLoopScript.maintain_script_pressure(loop)
	var id := str(loop["winfail_runtime"]["inserts"][0].get("unit_id",""))
	check(id != "" and BattlePlayLoop.unit(loop,id)["ai_wait_remaining"] == 1, "only the new recruit receives its final wait assignment")
	if id == "": return
	BattlePlayLoop.unit_ref(loop,id)["ai_wait_remaining"] = 0
	BattleLoopScript.maintain_script_pressure(loop)
	check(BattlePlayLoop.unit(loop,id)["ai_wait_remaining"] == 0 and loop["units"].size() == 5, "recruit pressure cannot repeat a consumed initialization")
	WinfailActions.apply_actions(loop,{"key":"event_previous","actions":[{"name":"actSetPrevInsertObjectWaitRound","args":["3"]}]},"test")
	BattleLoopScript.consume_script_waits(loop)
	check(BattlePlayLoop.unit(loop,id)["ai_wait_remaining"] == 3, "previous insertion setter also addresses a previously materialized recruit")

func wake_and_actions() -> void:
	var chain: Dictionary = ScriptWaitFixture.build("ai_chain")["loop"]
	chain = BattlePlayLoop.choose_command(chain,"wait")
	chain = BattlePlayLoop.choose_command(chain,"wait")
	var before_tail: int = chain["action_end_sequence"]
	chain = BattlePlayLoop.step_ai_turn(chain,zero)
	check(chain["scenario_ok"] and chain["extra_action"]["pending"] and chain["last_ai_action"].get("skill_id")==run_mobile_jobs_tests.WIND, "woken caster executes its owned spell before a second independent action")
	chain = BattlePlayLoop.step_ai_turn(chain,zero)
	check(chain["scenario_ok"] and BattlePlayLoop.unit(chain,"enemy026_1")["mp"]==0 and chain["last_ai_action"].get("kind") in ["attack","move_then_attack"] and chain["last_ai_action"].get("formula_source")=="core_logic" and chain["action_end_sequence"]==before_tail+1, "exhausted AI reselects a legal physical position and attack, then commits only one final tail")
	for mode in ["wait","injured","poison","silence","buff","near","dead_target","twice","paralyzed"]:
		var loop := run_ai_navigation_tests.fixture("wait")
		var actor: Dictionary = loop["units"][0]
		actor["ai_wait_remaining"] = 2
		actor["hp"] = actor["max_hp"]
		if mode == "injured": actor["hp"] -= 1
		if mode in ["poison","silence","paralyzed"]:
			actor.merge(BattlePlayLoop.StatusEffectRules.apply(actor,{"poison":"poison","silence":"no_magic","paralyzed":"paralysis"}[mode],2,7 if mode == "poison" else 0)["changes"],true)
		if mode == "buff":
			actor["status_flags"] |= 16; actor["status_counters"]["attack_up"] = 10 << 16 | 2
			actor.merge(BattlePlayLoop.ProgressionRules.refresh_growth_stats(actor,loop["equipment_items"]),true)
		if mode == "near": loop["units"][1]["coord"] = Vector2i(5,5)
		if mode == "dead_target": BattlePlayLoop.set_unit_defeated(loop,loop["units"][1]["id"],true)
		if mode == "twice": run_weapon_effect_tests.set_gear(actor,loop["equipment_items"],"accessory2",227)
		var next := BattlePlayLoop.step_ai_turn(loop,zero)
		check(next["scenario_ok"], "wait/wake branch valid: " + mode + " " + str(next.get("scenario_error")))
		if not next["scenario_ok"]: continue
		var result := BattlePlayLoop.unit(next,actor["id"])
		if mode in ["wait","dead_target","twice"]:
			check(next["last_ai_action"].get("wait_reason") == "wait_round" and result["ai_wait_remaining"] == 1, "undisturbed guard consumes one wait evaluation: " + mode)
		elif mode == "paralyzed":
			check(next["last_ai_action"]["kind"] == "paralysis_skip" and result["ai_wait_remaining"] == 2, "paralysis entry bypasses AI evaluation but uses the normal status tail")
		else: check(result["ai_wait_remaining"] == 0, "health, any status or near target releases guard: " + mode)
		if mode == "twice":
			check(next["extra_action"]["pending"] and next["action_end_sequence"] == 0, "first wait action has no duplicate status/resource tail")
			var second := BattlePlayLoop.step_ai_turn(next,zero)
			check(second["scenario_ok"] and BattlePlayLoop.unit(second,actor["id"])["ai_wait_remaining"] == 0 and second["action_end_sequence"] == 1, "second independent action reevaluates wait, tail runs once")

func object_synchronization() -> void:
	var scene = load("res://game/battle/development/MobileJobsTrial.tscn").instantiate()
	root.add_child(scene); current_scene = scene; scene.set_process(false)
	if scene.opening_coordinator == null:
		scene.opening_coordinator = scene.BattleOpeningCoordinator.new()
		scene.opening_coordinator.runtime = scene; scene.add_child(scene.opening_coordinator)
	var coordinator = scene.opening_coordinator
	coordinator.bindings = {"SID_PLAYER0/1":{"unit_id":"thief"},"SID_PLAYER1/1":{"unit_id":"tina"}}
	var owner = scene.actor_node_for_unit("thief")
	var other = scene.actor_node_for_unit("tina")
	check(owner != null and other != null, "real actor nodes available for bounded script synchronization")
	if owner != null and other != null:
		var before: Dictionary = scene.play_loop.duplicate(true)
		other.move_along([other.position,other.position+Vector2(200,0)],10)
		coordinator._wait_bound_actor({"id":"wait_idle","args":["SID_PLAYER0","1"]})
		check(other.is_moving() and not coordinator._target_busy(), "an unrelated moving actor does not hold an idle target's wait")
		owner.move_along([owner.position,owner.position+Vector2(40,0)],10)
		coordinator._wait_bound_actor({"id":"wait_busy","args":["SID_PLAYER0","1"]})
		check(coordinator._target_busy() and scene.play_loop == before, "busy target blocks without ticking or modifying the battle")
		owner.move_along([owner.position],0)
		check(not coordinator._target_busy() and other.is_moving(), "completion follows the target rather than the global motion set")
		other.move_along([other.position],0)
	var voices: Array[WeakRef] = []
	for audio in scene.find_children("*", "AudioStreamPlayer", true, false):
		var deadline := Time.get_ticks_msec() + 1000
		while audio.playing and audio.get_playback_position() <= 0 and Time.get_ticks_msec() < deadline: await create_timer(0.01).timeout
		if audio.playing: voices.append(weakref(audio.get_stream_playback()))
		audio.stop(); audio.stream = null
	root.remove_child(scene); scene.queue_free(); await process_frame
	var deadline := Time.get_ticks_msec() + 2000
	while voices.any(func(voice): return voice.get_ref() != null) and Time.get_ticks_msec() < deadline: await create_timer(0.02).timeout
	check(voices.all(func(voice): return voice.get_ref() == null), "real synchronization scene releases its audio playback")

func zero(_bound: int) -> int: return 0
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message); push_error(message)
