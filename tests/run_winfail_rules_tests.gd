extends "res://tests/support/TestSuite.gd"

## Pure-dictionary coverage for WinfailScenarioRules, the data-driven winfail
## interpreter: (1) the WINFAIL053 state sequence against golden values recorded
## from the retired hand-written level-53 module, (2) the live level-52 scenario
## through PlayLoop.create against the retired level-52 module's golden values,
## (3) original script semantics on synthetic seeds: 0x450840 count cases, status
## arming/chains, native action tokens, board labels and the next-level token, player-side totals.
## No PlayLoop mutation, no adapter dispatch.

const WinfailScenarioRules = preload("res://game/sim/WinfailScenarioRules.gd")
const WinfailConditions = preload("res://game/sim/WinfailConditions.gd")
const BattlePlayLoop = preload("res://game/sim/loop/BattlePlayLoop.gd")
const BattleScenarioRuleAdapter = preload("res://game/sim/BattleScenarioRuleAdapter.gd")
const BattleScenario = preload("res://game/sim/BattleScenario.gd")
const ConditionalPartyRules = preload("res://game/sim/ConditionalPartyRules.gd")
const BattleOutcome = preload("res://game/sim/BattleOutcome.gd")
const RulesReadback = preload("res://tests/support/RulesReadback.gd")


func _init() -> void:
	tag = "WINFAIL_RULES_TESTS"
	report_checks = false


func _unit(id: String, class_id: String, coord: Vector2i, hp: int = 10, role: String = "") -> Dictionary:
	var unit := {"id": id, "class_id": class_id, "coord": coord, "hp": hp, "max_hp": 10, "defeated": hp <= 0}
	if role != "":
		unit["battle_actor_role"] = role
	return unit


func _kill(loop: Dictionary, unit_id: String) -> void:
	for unit in loop["units"]:
		if str(unit["id"]) == unit_id:
			unit["hp"] = 0
			unit["defeated"] = true


func _projected(messages: Array) -> Array:
	var out: Array = []
	for message in messages:
		out.append([str(message.get("speaker_id", "")), str(message.get("message_id", ""))])
	return out


func _command(name: String, args: Array = []) -> Dictionary:
	var strings: Array = []
	for arg in args:
		strings.append(str(arg))
	return {"primary": name, "chain": [{"name": name, "args": strings}]}


func _section(name: String, code: int, actions: Array, message: String = "") -> Dictionary:
	return {"index": 0, "name": name, "codes": [str(code)], "messages": [message] if message != "" else [], "actions": actions}


func _seed(sections: Array, story_actions: Array, script_objects: Array = []) -> Dictionary:
	return {
		"schema": "hsl_battle_seed.v1",
		"level": 999,
		"evidence_tier": "test-fixture",
		"script_objects": script_objects,
		"scripts": {
			"story": {"sections": [{"index": 0, "name": "story", "codes": [], "messages": [], "actions": story_actions}]},
			"winfail": {"sections": sections},
		},
	}


func run() -> void:
	_third_battle_sequence()
	_second_battle_sequence()
	_encounter_fail_resolves_player_name_token()
	_level37_token_set()
	_level_three_mode_and_undead_transition()
	_level_twelve_opcode_actions()
	_lane_k_token_actions()
	_script_dead_message_words()
	_random_position_family()
	_select_event_status_branches()
	_exec_mode_and_system_arrival()
	_enemy_count_checks_0x450840()
	_status_arming_and_chains()
	_native_action_tokens()
	_win_fail_board_and_next_level()
	_player_side_totals()
	_round_and_x_range_tokens()
	_adapter_dispatch()
	run_event_cadence()
	run_winnability_census()


func _select_event_status_branches() -> void:
	## The formal battle choice inserts exactly the selected unconditional event
	## status and marks its fired presentation as inlined for the open prompt.
	var sections := [
		_section("event", 2, [_command("actTRUE"), _command("actSelectInsertEvent", ["SID_PLAYER0", 1, 2, 1810, 3, 1811, 4])]),
		_section("event", 3, [_command("actTRUE"), _command("actMessage", ["SID_PLAYER0", 1, 1812])]),
		_section("event", 4, [_command("actTRUE"), _command("actMessage", ["SID_PLAYER0", 1, 1813])]),
	]
	for selected_code in [3, 4]:
		var seed := _seed(sections, [_command("actInsertEventStatus", [2])])
		var scenario := {"scenario_rules": {}, "opening": {"actor_bindings": {"SID_PLAYER0/1": {"unit_id": "p0", "actor_id": "001"}}}}
		var battle := {"player_unit_id": "p0", "turn": 1, "units": [_unit("p0", "Player001", Vector2i(1, 1), 10, "player_controlled")]}
		var loop: Dictionary = WinfailScenarioRules.initialize_script_state(battle, scenario, seed)
		loop = WinfailScenarioRules.run_event_hooks(loop)
		loop = WinfailScenarioRules.select_event_status(loop, selected_code)
		_assert_eq(loop.get("event_statuses", []), [], "selected event %d is consumed after its actTRUE chain" % selected_code)
		_assert_eq(loop.get("winfail_runtime", {}).get("select_requests", []).size(), 1, "selected event %d records one request" % selected_code)
		var fired: Array = loop.get("winfail_runtime", {}).get("fired", [])
		_assert_eq(fired.size(), 2, "selected event %d fires event 2 then selected branch" % selected_code)
		_assert_eq(str(fired[1].get("key", "")), "event_%d" % selected_code, "selected event %d is the inserted branch" % selected_code)
		_assert_true(bool(fired[1].get("presentation_inlined", false)), "selected event %d presentation is inlined" % selected_code)


## ---------------------------------------------------------------------------
## (1) level 53: one state sequence through WINFAIL053. The expected values are
## the golden outputs recorded from the retired hand-written level module
## (ThirdBattleScenarioRules, presentation-line 2026-09-18) at the moment the
## interpreter replaced it; the board labels 695/696 and result ids never change
## along the sequence, the deficits/statuses/messages do.

const BOARD_WIN_53 := [{"actor_token": "SID_PLAYER1", "key": "win", "message_id": "695", "speaker_id": "1"}]
const BOARD_FAIL_53 := [{"actor_token": "SID_PLAYER1", "key": "fail", "message_id": "696", "speaker_id": "1"}]


func _expect_53(wf: Dictionary, label: String, deficits: Dictionary, victory: Dictionary, event_statuses: Array, win_statuses: Array, spawned: int, messages: Array = [], compare_board: bool = true) -> void:
	_assert_eq(WinfailScenarioRules.reinforcement_deficits(wf), deficits, label + ": reinforcement_deficits")
	_assert_eq(WinfailScenarioRules.victory_state(wf), victory, label + ": victory_state")
	_assert_eq(wf.get("event_statuses", []), event_statuses, label + ": event_statuses")
	_assert_eq(wf.get("win_statuses", []), win_statuses, label + ": win_statuses")
	if compare_board:
		var board: Dictionary = WinfailScenarioRules.objective_board(wf)
		_assert_eq(board.get("win", []), BOARD_WIN_53, label + ": objective_board win")
		_assert_eq(board.get("fail", []), BOARD_FAIL_53, label + ": objective_board fail")
		_assert_eq(board.get("event", []), [], label + ": no event labels in winfail053")
	_assert_eq(WinfailScenarioRules.story_dialogue_messages(wf), messages, label + ": story_dialogue_messages")
	_assert_eq(WinfailScenarioRules.spawned_reinforcement_count(wf, "Enemy023"), spawned, label + ": spawned count")
	_assert_eq(WinfailScenarioRules.result_message_id(wf, BattleOutcome.VICTORY_ESCAPE), "695", label + ": result_message_id victory_escape")
	_assert_eq(WinfailScenarioRules.result_message_id(wf, BattleOutcome.DEFEAT_FALLEN), "696", label + ": result_message_id defeat_leonard")


func _hooks_53(wf: Dictionary, turn: int) -> Dictionary:
	wf["turn"] = turn
	return WinfailScenarioRules.run_event_hooks(wf)


func _third_battle_sequence() -> void:
	var seed: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://content/generated/hsl/chapter01/battle053_seed.json"))
	var rules: Dictionary = WinfailScenarioRules.rules_from_seed(seed)
	_assert_eq(int(rules.get("source_level", 0)), 53, "53 source level")
	_assert_true(bool(rules.get("fully_supported", false)), "winfail053 uses only supported tokens: " + str(rules.get("unsupported_tokens", [])))
	_assert_eq((rules["statuses"]["win"] as Array).size(), 1, "one win status")
	_assert_eq((rules["statuses"]["fail"] as Array).size(), 1, "one fail status")
	_assert_eq((rules["statuses"]["event"] as Array).size(), 3, "three event statuses")
	_assert_eq(rules["initial_statuses"], {"win": [0], "fail": [0], "event": [0, 1, 2]}, "STORY053 arms win 0 / fail 0 / events 0-2")
	_assert_eq(rules["dead_messages"], {"SID_PLAYER1": "694"}, "STORY053 dead message 694")
	var win: Dictionary = rules["statuses"]["win"][0]
	_assert_eq(win["result_message"], {"actor_token": "SID_PLAYER1", "message_id": "695"}, "win board label 695")
	_assert_eq((win["conditions"] as Array).size(), 1, "win has one condition")
	_assert_eq(win["conditions"][0]["name"], "actCheckPlayerArrivePos", "win condition is the arrival check")
	_assert_eq((win["actions"] as Array).size(), 3, "win has three result actions")
	var event2: Dictionary = rules["statuses"]["event"][2]
	_assert_eq(event2["inserts"][0]["class_id"], "Enemy023", "insert class joined through script_objects obj_Data7")
	_assert_eq(event2["inserts"][0]["walk_cell"], [1, 30], "event2 lands at (32,960) = cell (1,30)")
	_assert_eq(rules["statuses"]["event"][0]["inserts"][0]["adjust_level"], [0, 0], "actSetPrevInsertObjectAdjustLevel is folded into the insert record")
	_assert_eq(WinfailScenarioRules.insert_walk_cells(rules), [Vector2i(5, 18), Vector2i(1, 30)], "landing cells (160,576)->(5,18) and (32,960)->(1,30), de-duplicated")

	var scenario := {"scenario_rules": {"reinforcement_class_id": "Enemy023"}, "opening": {"speaker_resource_ids": {"SID_PLAYER1": "1", "SID_ENEMY023": "376"}}}
	var battle := {
		"player_unit_id": "tina", "turn": 1, "units": [
			_unit("tina", "Player029", Vector2i(20, 23)),
			_unit("guard023_1", "Enemy023", Vector2i(29, 24)),
			_unit("guard023_2", "Enemy023", Vector2i(27, 23)),
			_unit("gate023_1", "Enemy023", Vector2i(30, 36)),
		],
	}
	var wf: Dictionary = WinfailScenarioRules.initialize_script_state(battle, scenario, seed)
	_assert_eq(wf.get("next_level_event", []), [1, 1], "next level event [1,1]")
	_assert_eq(wf.get("objective_phase", ""), "escape", "escape objective from the start")
	_assert_eq(wf.get("escape_zone_cells", []), [[30, 35], [31, 35], [30, 36], [31, 36]], "gate cells")
	_assert_eq(wf.get("fail_statuses", []), [0], "fail statuses")
	_assert_eq(wf["winfail_runtime"]["initial_class_unit_ids"], {"Enemy023": ["guard023_1", "guard023_2", "gate023_1"]}, "initial soldiers remembered per class")
	_assert_eq(wf["winfail_runtime"]["token_resolution"].get("SID_PLAYER1", {}), {"source": "player_unit_id_default", "unit_ids": ["tina"]}, "SID_PLAYER1 falls back to the controlled unit and says so")
	_expect_53(wf, "init", {}, {}, [0, 1, 2], [0], 0)

	wf = _hooks_53(wf, 4)
	_expect_53(wf, "round 4", {}, {}, [0, 1, 2], [0], 0)
	wf = _hooks_53(wf, 5)
	_assert_eq(wf["winfail_runtime"]["spawn_target"], {"Enemy023": 1}, "spawn target raised by the fired insert")
	_assert_true((wf.get("event_log", []) as Array).has("event_0"), "event_0 logged")
	_expect_53(wf, "round 5", {"Enemy023": 1}, {}, [1, 2], [0], 0)
	wf = _hooks_53(wf, 5)
	_expect_53(wf, "round 5 re-run does not double", {"Enemy023": 1}, {}, [1, 2], [0], 0)
	wf["units"].append(_unit("Enemy023_reinforcement_4", "Enemy023", Vector2i(5, 18)))
	_expect_53(wf, "recruit satisfies round 5", {}, {}, [1, 2], [0], 1)
	wf = _hooks_53(wf, 7)
	_expect_53(wf, "round 7", {"Enemy023": 1}, {}, [2], [0], 1)
	wf["units"].append(_unit("Enemy023_reinforcement_5", "Enemy023", Vector2i(1, 30)))
	_expect_53(wf, "second recruit", {}, {}, [2], [0], 2)
	for id in ["guard023_1", "guard023_2", "gate023_1"]:
		_kill(wf, id)
	wf = _hooks_53(wf, 7)
	_expect_53(wf, "two soldiers left: actCheckEnemyNumber 2 is a strict compare and stays quiet", {}, {}, [2], [0], 2)
	_kill(wf, "Enemy023_reinforcement_5")
	wf = _hooks_53(wf, 7)
	_expect_53(wf, "count event fires (one soldier left)", {"Enemy023": 1}, {}, [2], [0], 2)
	wf["units"].append(_unit("Enemy023_reinforcement_6", "Enemy023", Vector2i(1, 30)))
	_expect_53(wf, "third recruit", {}, {}, [2], [0], 3)
	_kill(wf, "Enemy023_reinforcement_4")
	wf["event_statuses"] = []
	wf = _hooks_53(wf, 7)
	_expect_53(wf, "disarmed event2 stays silent", {}, {}, [], [0], 3)
	wf["event_statuses"] = [2]
	wf = _hooks_53(wf, 7)
	_expect_53(wf, "re-armed event2 repeats", {"Enemy023": 1}, {}, [2], [0], 3)
	wf["units"].append(_unit("Enemy023_reinforcement_7", "Enemy023", Vector2i(1, 30)))
	_expect_53(wf, "fourth recruit", {}, {}, [2], [0], 4)

	wf["units"][0]["coord"] = Vector2i(31, 36)
	_expect_53(wf, "arrival: 緹娜 on a gate cell escapes", {}, BattleOutcome.VICTORY_ESCAPE, [2], [0], 4)
	wf["win_statuses"] = []
	_expect_53(wf, "arrival needs win status 0", {}, {}, [2], [], 4, [], false)
	_assert_eq(WinfailScenarioRules.objective_board(wf)["win"], [], "a disarmed win status leaves the board (the retired level module kept the label; the interpreter lists armed statuses only)")
	wf["win_statuses"] = [0]
	wf["battle_outcome"] = BattleOutcome.VICTORY_ESCAPE
	var win_message := [{"key": WinfailScenarioRules.TERMINAL_DIALOGUE_KEY, "speaker_id": "1", "message_id": "704", "actor_token": "SID_PLAYER1"}]
	_expect_53(wf, "victory messages", {}, BattleOutcome.VICTORY_ESCAPE, [2], [0], 4, win_message)
	var committed: Dictionary = WinfailScenarioRules.commit_outcome(wf)
	_assert_eq(committed["winfail_runtime"]["resolved"], {"key": "win_0", "kind": "win", "code": 0, "outcome": BattleOutcome.VICTORY_ESCAPE}, "commit records the deciding status")
	_assert_eq((committed["winfail_runtime"]["deleted_player_codes"] as Array).size(), 1, "actDeletePlayerCode recorded on commit")
	_assert_eq(committed.get("next_level_event", []), [1, 1], "next level event from the fired win")
	_assert_eq(WinfailScenarioRules.story_dialogue_messages(committed), win_message, "committed win message is not duplicated")
	_assert_eq(WinfailScenarioRules.commit_outcome(committed)["winfail_runtime"]["fired"], committed["winfail_runtime"]["fired"], "commit is idempotent")
	wf["units"][0]["coord"] = Vector2i(10, 10)
	_kill(wf, "tina")
	wf["battle_outcome"] = BattleOutcome.DEFEAT_FALLEN
	# 694 is 蒂娜's death word (STORY053 actSetDeadMessage → unit dead_message): spoken at death by
	# BattleAftermath, not repeated as a result-page line (the original has no such reader).
	_expect_53(wf, "defeat: the controlled player falling is the shared defeat key", {}, BattleOutcome.DEFEAT_FALLEN, [2], [0], 4, [])
	_assert_eq(WinfailScenarioRules.story_dialogue_messages({}), [], "no rules: no messages")
	_assert_eq(WinfailScenarioRules.objective_board({}), {"win": [], "fail": [], "event": []}, "no rules: empty board")


## ---------------------------------------------------------------------------
## (2) level 52 through the live scenario (PlayLoop.create + adapter). Expected
## values are the golden outputs of the retired SecondBattleScenarioRules where
## the two agreed; the documented divergence (event1 fires once) is asserted as
## the interpreter's reading.

func _second_battle_sequence() -> void:
	var scenario: Dictionary = BattleScenario.load_file("res://content/battles/battle_052.json")
	var seed: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://content/generated/hsl/chapter01/battle052_seed.json"))
	_assert_eq(str(scenario.get("rule_adapter", "")), "winfail", "level 52 declares the interpreter")
	var wf := BattlePlayLoop.create([], "", scenario, 3)
	_assert_eq(bool(wf.get("scenario_ok", false)), true, "second battle loop valid under the interpreter")
	_assert_eq(str(wf.get("rule_adapter", "")), "winfail", "PlayLoop.create dispatches through the winfail adapter")
	var rules: Dictionary = wf.get("winfail_script_rules", {})
	_assert_eq(rules.get("unsupported_tokens", []), [], "winfail052 is fully supported (actSetUseShapeWait is a recorded presentation token)")
	_assert_eq(rules.get("initial_statuses", {}), {"win": [0], "fail": [0], "event": [0, 1]}, "STORY052 arms win 0 / fail 0 / events 0-1")
	_assert_eq(WinfailScenarioRules.insert_walk_cells(rules), [Vector2i(7, 38), Vector2i(12, 38), Vector2i(4, 30), Vector2i(14, 30)], "event1 landing cells (227,1228)/(403,1228)/(134,987)/(463,987) by integer division")
	_assert_eq(wf.get("next_level_event", []), [58, 58], "next level event [58,58]")
	_assert_eq(wf.get("objective_phase", ""), "defeat_boss", "actCheckPlayer on the boss is a defeat_boss objective")
	_assert_eq(wf["winfail_runtime"]["token_resolution"].get("SID_ENEMY025", {}), {"source": "binding", "unit_ids": ["emperor025"]}, "opening actor_bindings resolve SID_ENEMY025")
	_assert_eq(wf["winfail_runtime"]["token_resolution"].get("SID_PLAYER0", {}), {"source": "binding", "unit_ids": ["leonard"]}, "opening actor_bindings resolve SID_PLAYER0")
	_assert_eq(wf["winfail_runtime"]["unresolved_tokens"], [], "every WINFAIL052 token resolves")
	_assert_eq(WinfailScenarioRules.objective_board(wf)["win"], [{"key": "win", "speaker_id": "382", "message_id": "122", "actor_token": "SID_ENEMY025"}], "win board label: 法蘭克 + 122 (死亡)")
	_assert_eq(WinfailScenarioRules.objective_board(wf)["fail"], [{"key": "fail", "speaker_id": "0", "message_id": "122", "actor_token": "SID_PLAYER0"}], "fail board label: 雷歐納德 + 122")
	_assert_eq(WinfailScenarioRules.story_dialogue_messages(wf), [], "no dialogue before events or outcome")
	_assert_eq(WinfailScenarioRules.victory_state(wf), {}, "fresh battle ongoing")
	_assert_eq(WinfailScenarioRules.reinforcement_deficits(wf), {}, "fresh deficits")
	_assert_eq(WinfailScenarioRules.rules_from_seed(seed).get("initial_statuses", {}), rules.get("initial_statuses", {}), "the loop carries the seed-derived rules")

	var attack := {"attacker_id": "leonard", "defender_id": "emperor025"}
	var wf_hit := wf.duplicate(true)
	wf_hit["last_attack"] = attack
	wf_hit = WinfailScenarioRules.run_event_hooks(wf_hit, true)
	_assert_eq(wf_hit.get("event_log", []), ["event_0"], "Winfail logs event_0 (the retired module called it boss_engaged)")
	_assert_eq(_projected(WinfailScenarioRules.story_dialogue_messages(wf_hit)), [["382", "392"], ["0", "393"]], "event0 lines 392/393 in order: the emperor, then Leonard")
	_assert_eq(WinfailScenarioRules.story_dialogue_messages(wf_hit)[0]["key"], "event_0", "event dialogue keyed by status")
	var wf_again := WinfailScenarioRules.run_event_hooks(wf_hit, true)
	_assert_eq(_projected(WinfailScenarioRules.story_dialogue_messages(wf_again)), [["382", "392"], ["0", "393"]], "event0 fires once")
	_assert_eq(wf_again.get("event_statuses", []), [1], "event0 consumed")
	var round_only := wf.duplicate(true)
	round_only["last_attack"] = attack
	round_only = WinfailScenarioRules.run_event_hooks(round_only)
	_assert_eq(round_only.get("event_statuses", []), [0, 1], "a stale last_attack does not fire the attacked event at a round transition")
	var other := wf.duplicate(true)
	other["last_attack"] = {"attacker_id": "ally023_1", "defender_id": "emperor025"}
	other = WinfailScenarioRules.run_event_hooks(other, true)
	_assert_eq(WinfailScenarioRules.story_dialogue_messages(other), [], "ally attacks do not trigger event0")

	var wf_won := wf_hit.duplicate(true)
	_kill(wf_won, "emperor025")
	_assert_eq(WinfailScenarioRules.victory_state(wf_won), BattleOutcome.VICTORY_BOSS, "boss down wins: actCheckPlayer on an enemy token maps to victory_boss")
	wf_won["battle_outcome"] = BattleOutcome.VICTORY_BOSS
	_assert_eq(_projected(WinfailScenarioRules.story_dialogue_messages(wf_won)), [["382", "392"], ["0", "393"], ["0", "378"]], "victory appends 378 after the event lines")
	_assert_eq(WinfailScenarioRules.result_message_id(wf_won, BattleOutcome.VICTORY_BOSS), "122", "win board label")
	var wf_lost := wf.duplicate(true)
	_kill(wf_lost, "leonard")
	_kill(wf_lost, "emperor025")
	_assert_eq(WinfailScenarioRules.victory_state(wf_lost), BattleOutcome.DEFEAT_FALLEN, "player defeat takes precedence over the boss")
	wf_lost["battle_outcome"] = BattleOutcome.DEFEAT_FALLEN
	# 394 (STORY052 actSetDeadMessage for 雷歐納德) lives on the unit as dead_message and is spoken
	# once at death; the defeat result page adds no line of its own.
	_assert_eq(_projected(WinfailScenarioRules.story_dialogue_messages(wf_lost)), [], "defeat appends no result-page line (394 is the death word, spoken at death)")
	var unknown := wf.duplicate(true)
	unknown["event_log"] = ["round_4_warning"]
	_assert_eq(WinfailScenarioRules.story_dialogue_messages(unknown), [], "first-battle events do not leak into level 52")

	var pressure := wf.duplicate(true)
	var alive_021 := 0
	for unit in pressure["units"]:
		if str(unit.get("class_id", "")) == "Enemy021" and int(unit.get("hp", 0)) > 0:
			alive_021 += 1
	var killed := 0
	for unit in pressure["units"]:
		if str(unit.get("class_id", "")) == "Enemy021" and alive_021 - killed > 1:
			_kill(pressure, str(unit["id"]))
			killed += 1
	pressure["turn"] = 2
	pressure = WinfailScenarioRules.run_event_hooks(pressure)
	_assert_eq(WinfailScenarioRules.reinforcement_deficits(pressure), {"Enemy021": 4}, "fewer than two 021 alive (strict compare): four inserts owed")
	_assert_eq(pressure.get("event_statuses", []), [0], "event1 (no self re-arm) is consumed: one wave, unlike the retired module's continuous pressure")
	_assert_eq((pressure["winfail_runtime"]["inserts"] as Array).size(), 4, "four insert records with walk cells")
	_assert_eq(pressure["winfail_runtime"]["inserts"][2]["walk_cell"], [4, 30], "third insert walks to (134,987) = cell (4,30)")
	for index in range(4):
		pressure["units"].append(_unit("Enemy021_reinforcement_%d" % index, "Enemy021", Vector2i(7, 38)))
	_assert_eq(WinfailScenarioRules.reinforcement_deficits(pressure), {}, "the wave is satisfied by four spawned 021 units")
	for unit in pressure["units"]:
		if str(unit.get("class_id", "")) == "Enemy021":
			_kill(pressure, str(unit["id"]))
	pressure = WinfailScenarioRules.run_event_hooks(pressure)
	_assert_eq(WinfailScenarioRules.reinforcement_deficits(pressure), {}, "with event1 consumed, wiping the 021 class asks for nothing more")


func _encounter_fail_resolves_player_name_token() -> void:
	# Every WINFAIL5NN fail section is `actCheckPlayer 1 SID_雷歐納德` (EXTRAS.H slot 0).
	# The encounter assembler binds the fielded EVEF 有才產生 slots to their party tokens
	# the way trace_opening does for the main line, so the name token resolves to leonard
	# and the encounter is lost when he falls (R1 autoplay dead_end party_wiped_no_defeat).
	var scenario: Dictionary = BattleScenario.load_file("res://content/battles/battle_571.json")
	var wf := BattlePlayLoop.create([], "", scenario, 5)
	_assert_eq(bool(wf.get("scenario_ok", false)), true, "encounter 571 loop valid under the interpreter")
	_assert_eq(wf["winfail_runtime"]["token_resolution"].get("SID_雷歐納德", {}), {"source": "binding", "unit_ids": ["leonard"]}, "the EVEF slot-0 binding resolves SID_雷歐納德 to leonard")
	_assert_eq(wf["winfail_runtime"]["unresolved_tokens"], [], "every WINFAIL571 token resolves")
	_assert_eq(WinfailScenarioRules.objective_board(wf)["fail"], [{"key": "fail", "speaker_id": "0", "message_id": "122", "actor_token": "SID_雷歐納德"}], "fail board label: 雷歐納德 + 122")
	_assert_eq(WinfailScenarioRules.victory_state(wf), {}, "fresh encounter ongoing")
	var others_lost := wf.duplicate(true)
	for unit in others_lost["units"]:
		if str(unit.get("battle_actor_role", "")) == "player_controlled" and str(unit["id"]) != "leonard":
			_kill(others_lost, str(unit["id"]))
	_assert_eq(WinfailScenarioRules.victory_state(others_lost), {}, "the fail section names only 雷歐納德: the rest of the party falling does not end the encounter")
	var lost := wf.duplicate(true)
	_kill(lost, "leonard")
	_assert_eq(WinfailScenarioRules.victory_state(lost), BattleOutcome.DEFEAT_FALLEN, "actCheckPlayer 1 SID_雷歐納德 holds once leonard falls")
	for unit in wf["units"]:
		if str(unit.get("battle_actor_role", "")) == "player_controlled":
			var token_key := ""
			for key in wf["winfail_runtime"]["actor_bindings"]:
				if str(wf["winfail_runtime"]["actor_bindings"][key]) == str(unit["id"]):
					token_key = str(key)
			_assert_true(token_key.begins_with("SID_") and token_key.ends_with("/1") and not token_key.begins_with("SID_PLAYER"), "fielded slot %s is bound to its EXTRAS.H name token (%s)" % [str(unit["id"]), token_key])
	_assert_eq(WinfailScenarioRules.commit_outcome(lost)["winfail_runtime"]["resolved"]["key"], "fail_0", "the script fail section is the recorded resolution when 雷歐納德 falls")
	# The party carried without 雷歐納德 (levels 30-34): the bound slot is not fielded.
	# A bound-but-unfielded member is not fallen (provisional remake reading), and the
	# remake party-wipe rule decides once every fielded member is down and no script
	# status holds.
	var carry := {"schema": "hsl_campaign_carry.v1", "units": {"hu": {"actor_id": "003"}, "tina": {"actor_id": "002"}, "hanks": {"actor_id": "004"}, "shera": {"actor_id": "005"}}, "loop": {}}
	var filtered: Dictionary = ConditionalPartyRules.apply(scenario, carry)
	_assert_eq(filtered["receipt"]["skipped"].has("leonard"), true, "the carry without 雷歐納德 skips his conditional install")
	var absent := BattlePlayLoop.create([], "", filtered["scenario"], 5)
	_assert_eq(absent["winfail_runtime"]["token_resolution"].get("SID_雷歐納德", {}), {"source": "binding", "unit_ids": []}, "the slot-0 binding stays a binding with no fielded unit")
	_assert_eq(WinfailScenarioRules.victory_state(absent), {}, "actCheckPlayer 1 SID_雷歐納德 does not hold for a member this battle never fielded")
	var fielded: Array = []
	for unit in absent["units"]:
		if str(unit.get("battle_actor_role", "")) == "player_controlled":
			fielded.append(str(unit["id"]))
	_assert_eq(fielded.size(), 4, "four members fielded without 雷歐納德")
	var wiped := absent.duplicate(true)
	for id in fielded:
		_kill(wiped, str(id))
	_assert_eq(WinfailScenarioRules.party_wiped(wiped), true, "every fielded member defeated = party wiped")
	_assert_eq(WinfailScenarioRules.victory_state(wiped), BattleOutcome.DEFEAT_FALLEN, "the remake party-wipe rule decides the defeat when no script status holds")
	var committed := WinfailScenarioRules.commit_outcome(wiped)
	_assert_eq(committed["winfail_runtime"]["resolved"], {"key": WinfailScenarioRules.PARTY_WIPE_KEY, "kind": "fail", "code": -1, "outcome": BattleOutcome.DEFEAT_FALLEN, "policy": WinfailScenarioRules.PARTY_WIPE_POLICY}, "the party wipe is recorded as its own resolution (no script fail chain)")
	_assert_eq(committed["winfail_runtime"]["dialogue"], [], "no script fail message runs for the party wipe")
	committed["battle_outcome"] = BattleOutcome.DEFEAT_FALLEN
	_assert_eq(WinfailScenarioRules.story_dialogue_messages(committed), [], "the absent member's dead message is not spoken for the party wipe")
	_assert_eq(WinfailScenarioRules.result_message_id(committed, BattleOutcome.DEFEAT_FALLEN), "", "no script board label for the party wipe (the presentation shows its own defeat label)")
	_assert_eq(WinfailScenarioRules.victory_state(committed), BattleOutcome.DEFEAT_FALLEN, "the recorded party wipe keeps the defeat")
	var three_down := absent.duplicate(true)
	for id in fielded.slice(0, 3):
		_kill(three_down, str(id))
	_assert_eq(WinfailScenarioRules.victory_state(three_down), {}, "one fielded member standing keeps the battle going")
	var departed := three_down.duplicate(true)
	(departed["winfail_runtime"]["departed_unit_ids"] as Array).append(str(fielded[3]))
	_assert_eq(WinfailScenarioRules.victory_state(departed), BattleOutcome.DEFEAT_FALLEN, "a script-departed member is not counted: the remaining fielded members are all down")
	var all_departed := absent.duplicate(true)
	for id in fielded:
		(all_departed["winfail_runtime"]["departed_unit_ids"] as Array).append(str(id))
	_assert_eq(WinfailScenarioRules.victory_state(all_departed), {}, "a party that departed by script is not a wiped party")
	var cleared := wiped.duplicate(true)
	for unit in cleared["units"]:
		if str(unit.get("battle_actor_role", "")) == "enemy_ai":
			_kill(cleared, str(unit["id"]))
	_assert_eq(WinfailScenarioRules.victory_state(cleared), BattleOutcome.VICTORY_ENEMIES_CLEARED, "a script win status that holds outranks the party wipe")


## ---------------------------------------------------------------------------
## (3) failure paths and edges

func _level37_token_set() -> void:
	# 0x4348f0 resolves 008's job_up_code obj_Player8Up1 (816) through global.obs obj_Data7 to
	# PLAYERS row 017 邪獸 — the same row the town chain names (static-derived, original_level37_tokens.md).
	var target: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://content/generated/hsl/actors/017.json"))["actor"]
	var source: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://content/generated/hsl/actors/008.json"))["actor"]
	source["id"] = "gulu"
	source["coord"] = Vector2i(2, 2)
	var scenario := {"scenario_rules": {"job_up_targets": {"008": "017"}}, "job_up_templates": {"017": target}, "opening": {"actor_bindings": {"SID_GULU/1": {"unit_id": "gulu"}}}}
	var attack_seed := _seed([_section("event", 0, [_command("actCheckSerialPlayerAttacked", ["SID_GULU", 1]), _command("actMessage", ["SID_GULU", 1, "371"] )])], [_command("actInsertEventStatus", [0])])
	var attacked := WinfailScenarioRules.initialize_script_state({"player_unit_id": "gulu", "turn": 1, "units": [source]}, scenario, attack_seed)
	attacked["last_attack"] = {"attacker_id": "foe", "defender_id": "gulu"}
	attacked = WinfailScenarioRules.run_event_hooks(attacked, true)
	_assert_eq(attacked["winfail_runtime"]["fired"].size(), 1, "actCheckSerialPlayerAttacked matches the exact attacked serial")
	var not_attacker_seed := _seed([_section("event", 0, [_command("actCheckNotPlayerAttacker", ["SID_GULU"]), _command("actMessage", ["SID_GULU", 1, "372"] )])], [_command("actInsertEventStatus", [0])])
	var not_attacker := WinfailScenarioRules.initialize_script_state({"player_unit_id": "gulu", "turn": 1, "units": [source]}, scenario, not_attacker_seed)
	not_attacker["last_attack"] = {"attacker_id": "foe", "defender_id": "target"}
	not_attacker = WinfailScenarioRules.run_event_hooks(not_attacker, true)
	_assert_eq(not_attacker["winfail_runtime"]["fired"].size(), 1, "actCheckNotPlayerAttacker accepts another attacker")
	not_attacker["event_statuses"] = [0]
	not_attacker["last_attack"] = {"attacker_id": "gulu", "defender_id": "target"}
	not_attacker = WinfailScenarioRules.run_event_hooks(not_attacker, true)
	_assert_eq(not_attacker["winfail_runtime"]["fired"].size(), 1, "actCheckNotPlayerAttacker rejects the named player")
	var idle := WinfailScenarioRules.initialize_script_state({"player_unit_id": "gulu", "turn": 1, "units": [source]}, scenario, not_attacker_seed)
	idle = WinfailScenarioRules.run_event_hooks(idle)
	_assert_eq(idle["winfail_runtime"]["fired"].size(), 1, "actCheckNotPlayerAttacker holds at a completion without an attack (case 0x74: 0x4c1ce8 is 0)")
	var any_seed := _seed([_section("event", 0, [_command("actCheckPlayerAttacked", ["-1", "SID_GULU"]), _command("actMessage", ["SID_GULU", 1, "374"] )])], [_command("actInsertEventStatus", [0])])
	var any_attacker := WinfailScenarioRules.initialize_script_state({"player_unit_id": "gulu", "turn": 1, "units": [source]}, scenario, any_seed)
	any_attacker["last_attack"] = {"attacker_id": "foe", "defender_id": "gulu"}
	_assert_eq(WinfailScenarioRules.run_event_hooks(any_attacker)["winfail_runtime"]["fired"].size(), 0, "actCheckPlayerAttacked needs the attack action's own completion scan")
	any_attacker = WinfailScenarioRules.run_event_hooks(any_attacker, true)
	_assert_eq(any_attacker["winfail_runtime"]["fired"].size(), 1, "actCheckPlayerAttacked -1 accepts any attacker (case 0x2a skips the 0x4c1ce8 check)")
	var area := WinfailScenarioRules.initialize_script_state({"player_unit_id": "gulu", "turn": 1, "units": [source]}, scenario, attack_seed)
	area["last_attack"] = {"attacker_id": "foe", "defender_id": "other", "affected_targets": [{"defender_id": "other"}, {"defender_id": "gulu"}]}
	area = WinfailScenarioRules.run_event_hooks(area, true)
	_assert_eq(area["winfail_runtime"]["fired"].size(), 1, "the attacked list holds every target of an area skill, not only its first")
	var false_seed := _seed([_section("event", 0, [_command("actFALSE"), _command("actMessage", ["SID_GULU", 1, "373"] )])], [_command("actInsertEventStatus", [0])])
	var always_false := WinfailScenarioRules.initialize_script_state({"player_unit_id": "gulu", "turn": 1, "units": [source]}, scenario, false_seed)
	always_false = WinfailScenarioRules.run_event_hooks(always_false)
	_assert_eq(always_false["winfail_runtime"]["fired"].size(), 0, "actFALSE never satisfies a status")
	var shape_seed := _seed([_section("event", 0, [_command("actTRUE"), _command("actSetPlayerWalkShape", ["SID_GULU", 1])])], [_command("actInsertEventStatus", [0])])
	var shaped := WinfailScenarioRules.initialize_script_state({"player_unit_id": "gulu", "turn": 1, "units": [source]}, scenario, shape_seed)
	shaped = WinfailScenarioRules.run_event_hooks(shaped)
	_assert_eq(shaped["winfail_runtime"]["walk_shape_changes"][0]["unit_ids"], ["gulu"], "actSetPlayerWalkShape resolves the player serial")
	# The job-up runs on a prepared level-37 unit (learning / permanent layers and the
	# equipment catalog the shared refresh needs), with the tables where the assembler
	# writes them: scenario_rules.job_up_targets / job_up_templates.
	var job_seed := _seed([_section("event", 0, [_command("actTRUE"), _command("actPlayerJobUpProcess", ["SID_GULU", 0]), _command("actSetOverFlag", ["gameoverflagEnemyJobUp"])])], [_command("actInsertEventStatus", [0])])
	var level37 := BattlePlayLoop.create([], "", BattleScenario.load_file("res://content/battles/battle_037.json"), 7)
	var prepared: Dictionary = BattlePlayLoop.unit_ref(level37, "gulu").duplicate(true)
	_assert_eq([str(prepared.get("actor_id", "")), bool(prepared.get("install_if_carried", false))], ["008", true], "battle_037 fields the conditional 咕嚕 slot (all slots without a hand-off)")
	var assembled := {"scenario_rules": {"job_up_targets": {"008": "017"}, "job_up_templates": {"017": target}}, "opening": {"actor_bindings": {"SID_GULU/1": {"unit_id": "gulu"}}}}
	prepared["hp"] = 3  # wounded before the exchange: 0x4348f0 / 0x407ec0 / 0x448840 write no vitals
	var upgraded := WinfailScenarioRules.initialize_script_state({"player_unit_id": "gulu", "turn": 1, "units": [prepared], "equipment_items": level37["equipment_items"]}, assembled, job_seed)
	upgraded = WinfailScenarioRules.run_event_hooks(upgraded)
	var actor: Dictionary = upgraded["units"][0]
	_assert_eq(upgraded["winfail_runtime"]["unsupported_encountered"], [], "level 37 token set has no unsupported runtime actions")
	_assert_eq([str(actor["actor_id"]), str(actor.get("job_up_target_actor_id", "")), int(actor.get("job_up_flags", 0))], ["008", "017", 0x80000000], "actPlayerJobUpProcess keeps actor 008 as the rules key, stands the member on 017 and records the native flag (same contract as the town job-up)")
	_assert_eq(actor["job_up_history"], [{"from_actor_id": "008", "to_actor_id": "017", "flag": 0x80000000, "from_job_code": 96, "job_code": 97}], "the job-up history the campaign carry replays")
	_assert_eq(int(actor["growth_profile"]["job_code"]), int(target["growth_profile"]["job_code"]), "job-up changes the job code to 97 jobEvilMonster")
	_assert_eq(actor["combat_profile"]["str"], prepared["combat_profile"]["str"], "0x4348f0 leaves the member's attributes untouched")
	_assert_eq(int(actor["level"]), int(prepared["level"]), "level is kept")
	_assert_eq(int(actor["growth_profile"]["source"]["attack_power"]), int(prepared["growth_profile"]["source"]["attack_power"]) + int(target["growth_profile"]["source"]["attack_power"]), "additive PLAYERS layer: 017 attack_power is summed onto 008's")
	_assert_eq([int(actor["weapon_code"]), actor["equipment"]], [53, [{"slot": "weapon", "item_code": 53, "name": "???"}]], "the declared 017 weapon 53 replaces the weapon slot in the six-slot list")
	_assert_true(int(actor["max_hp"]) != int(prepared["max_hp"]) and int(actor["hp"]) == 3, "the shared refresh derives the 017 form (max %d→%d) while the member keeps its current HP 3 (0x4348f0 writes no vitals, 0x448840 only clamps downward)" % [int(prepared["max_hp"]), int(actor["max_hp"])])
	_assert_eq(upgraded["winfail_runtime"]["job_up_changes"][0]["to_actor_id"], "017", "the receipt names the target row")
	_assert_eq(upgraded["winfail_runtime"]["pending_world_flags"][0]["args"][0], "gameoverflagEnemyJobUp", "job-up event records the EnemyJobUp flag")
	# A member already standing on 017 (job_up 0): 0x4348f0 returns before any exchange — a no-op, not a failure.
	var moved := prepared.duplicate(true)
	moved["job_up_target_actor_id"] = "017"
	var settled := WinfailScenarioRules.initialize_script_state({"player_unit_id": "gulu", "turn": 1, "units": [moved], "equipment_items": level37["equipment_items"]}, assembled, job_seed)
	settled = WinfailScenarioRules.run_event_hooks(settled)
	_assert_eq([settled["winfail_runtime"]["unsupported_encountered"], settled["winfail_runtime"]["job_up_changes"][0]["policy"], str(settled["units"][0].get("job_up_target_actor_id", ""))], [[], "job_up_code_zero_noop", "017"], "a member whose row declares job_up 0 is left untouched with a no-op receipt (no stacking, no error)")


func _level_three_mode_and_undead_transition() -> void:
	var seed := _seed([
		_section("win", 0, [_command("actTRUE"), _command("actSetPlayerMode", ["SID_漢克斯", "1", "pmPlayer", "1"]), _command("actSetPlayerUndead", ["SID_漢克斯", "1", "0"])]),
	], [
		_command("actInsertWinStatus", ["0"]),
		_command("actSetPlayerMode", ["SID_漢克斯", "1", "pmEnemy", "1"]),
		_command("actSetPlayerUndead", ["SID_漢克斯", "1", "1"]),
	])
	var scenario := {"opening": {"actor_bindings": {"SID_漢克斯/1": {"unit_id": "hanks"}}}}
	var battle := {"player_unit_id": "leonard", "turn": 1, "units": [
		_unit("leonard", "Player001", Vector2i(1, 1), 10, "player_controlled"),
		_unit("hanks", "Enemy004", Vector2i(2, 1), 10, "enemy_ai"),
	]}
	var wf: Dictionary = WinfailScenarioRules.initialize_script_state(battle, scenario, seed)
	_assert_eq(wf["units"][1].get("battle_actor_role", ""), "enemy_ai", "level 3 opening mode is enemy")
	_assert_eq(bool(wf["units"][1].get("undead", false)), true, "level 3 opening undead marker is set")
	wf["battle_outcome"] = BattleOutcome.VICTORY_SCRIPT
	wf = WinfailScenarioRules.commit_outcome(wf)
	_assert_eq(wf["units"][1].get("battle_actor_role", ""), "player_controlled", "WINFAIL003 victory mode joins player side")
	_assert_eq(bool(wf["units"][1].get("player_commandable", false)), true, "mode transition makes hanks commandable")
	_assert_eq(bool(wf["units"][1].get("undead", true)), false, "WINFAIL003 victory clears undead marker")
	_assert_eq(wf["winfail_runtime"]["mode_changes"].back()["mode"], 0x10000, "pmPlayer symbolic mode resolves to native value")


func _level_twelve_opcode_actions() -> void:
	var seed := _seed([
		_section("event", 0, [
			_command("actTRUE"),
			_command("actInsertObject", ["obj_Story_Level12_Unknown", 0, 0]),
			_command("actChangePrevInsertObjectID", [10000]),
			_command("actSetPlayerFixPos", ["SID_ENEMY038", 1, 32, 64, 1]),
			_command("actSetPlayerFly", ["SID_ENEMY038", 1, 1]),
		]),
		_section("event", 1, [
			_command("actTRUE"),
			_command("actSetPlayerFixPos", ["SID_ENEMY038", 2, -160, 1824, 1]),
		]),
	], [
		_command("actInsertEventStatus", [0]),
		_command("actInsertEventStatus", [1]),
	])
	var scenario := {"scenario_rules": {"cell_size": 32}, "opening": {"actor_bindings": {
		"SID_ENEMY038/1": {"unit_id": "enemy038_1"},
		"SID_ENEMY038/2": {"unit_id": "enemy038_2"},
	}}}
	var battle := {"map_size": Vector2i(45, 60), "turn": 1, "units": [
		_unit("enemy038_1", "Enemy038", Vector2i(4, 4), 10, "enemy_ai"),
		_unit("enemy038_2", "Enemy038", Vector2i(5, 5), 10, "enemy_ai"),
	]}
	var wf: Dictionary = WinfailScenarioRules.initialize_script_state(battle, scenario, seed)
	_assert_true(bool(wf["winfail_script_rules"]["fully_supported"]), "level 12 opcodes are supported by the interpreter")
	wf = WinfailScenarioRules.run_event_hooks(wf)
	_assert_eq(wf.get("event_statuses", []), [1], "one scan starts only the first holding event (0x44ee20 returns after it)")
	wf = WinfailScenarioRules.run_event_hooks(wf)
	_assert_eq(wf["winfail_runtime"]["previous_insert_id_changes"], [{"key": "event_0", "object_id": 10000, "previous_object_id": null, "insert_index": 0}], "previous insert id is applied to the latest insert receipt")
	_assert_eq(wf["winfail_runtime"]["fixed_position_changes"][0]["coord"], Vector2i(1, 2), "fixed position quantizes source pixels by 32px")
	# 0x450840 case 0x54 writes the guard anchor (+0x46/+0x44) and, for a nonzero distance,
	# the live ai_fixed (+0x1d0); the object itself stays where it stands.
	_assert_eq(wf["units"][0]["ai_home_coord"], Vector2i(1, 2), "fixed position resolves code plus serial into that unit's guard anchor")
	_assert_eq(wf["units"][0]["coord"], Vector2i(4, 4), "fixed position does not move the unit")
	_assert_eq(wf["units"][0].get("ai_fixed_radius"), 1, "a nonzero distance is the unit's live guard radius")
	_assert_true(bool(wf["units"][0]["traversal"]["flying"]), "fly opcode reuses traversal.flying")
	_assert_eq(wf["winfail_runtime"]["fixed_position_changes"][1]["off_map"], true, "an anchor beyond the map edge is recorded as such in the receipt")
	_assert_eq(wf["units"][1]["ai_home_coord"], Vector2i(-5, 57), "negative source pixels use floor quantization for the anchor (WINFAIL012 retreat point)")
	_assert_eq(wf["units"][1]["coord"], Vector2i(5, 5), "an off-map anchor leaves the unit on the field")
	_assert_eq(WinfailConditions.alive_units_for_token(wf, "SID_ENEMY038", 2), ["enemy038_2"], "a unit retreating toward an off-map anchor still counts until actWalkAndDelete removes it")
	_assert_eq(wf["winfail_runtime"]["unsupported_encountered"], [], "level 12 opcode actions do not fall through to unsupported")


func _lane_k_token_actions() -> void:
	var scenario: Dictionary = BattleScenario.load_file("res://content/battles/battle_040.json")
	var base: Dictionary = BattlePlayLoop.create([], "", scenario, 3)
	_assert_true(bool(base.get("scenario_ok", false)), "lane K fixture: source battle loop is valid")
	var boss := BattlePlayLoop.unit_ref(base, "actor055_1")
	_assert_eq(boss.get("inventory", [])[0], 252, "source actor 055 carries item 252")
	boss["hp"] = 100
	boss["status_counters"]["poison"] = 3
	boss["status_flags"] = 1
	var item_seed := _seed([
		_section("event", 0, [_command("actTRUE"), _command("actUseItem", ["SID_ENEMY055", 1, 252])]),
	], [_command("actInsertEventStatus", [0])])
	var item_scenario := {"opening": {"actor_bindings": {"SID_ENEMY055/1": {"unit_id": "actor055_1"}}}}
	var item_loop: Dictionary = WinfailScenarioRules.initialize_script_state(base, item_scenario, item_seed)
	item_loop = WinfailScenarioRules.run_event_hooks(item_loop)
	var item_actor := WinfailConditions.unit(item_loop, "actor055_1")
	_assert_eq(item_loop["winfail_runtime"]["item_requests"][0]["status"], "applied", "actUseItem commits through ItemResolutionRules")
	_assert_eq(item_actor.get("hp"), item_actor.get("max_hp"), "actUseItem restores HP through the existing consumable rule")
	_assert_eq(item_actor["inventory"].has(252), false, "actUseItem consumes the source inventory item")
	_assert_eq(item_actor["status_counters"]["poison"], 0, "actUseItem cures poison through the existing consumable rule")

	var no_attack_seed := _seed([
		_section("event", 0, [_command("actTRUE"), _command("actSetPlayerNoAttack", ["SID_PLAYER0", 1, 1])]),
	], [_command("actInsertEventStatus", [0])])
	var no_attack_scenario := {"opening": {"actor_bindings": {"SID_PLAYER0/1": {"unit_id": "leonard"}}}}
	var no_attack_loop: Dictionary = WinfailScenarioRules.initialize_script_state(base, no_attack_scenario, no_attack_seed)
	no_attack_loop = WinfailScenarioRules.run_event_hooks(no_attack_loop)
	_assert_true(bool(WinfailConditions.unit(no_attack_loop, "leonard").get("no_attack", false)), "actSetPlayerNoAttack sets the actor marker")
	no_attack_loop = BattlePlayLoop.return_to_player(no_attack_loop, "leonard")
	_assert_eq(BattlePlayLoop.command_available(no_attack_loop, "attack"), false, "no_attack removes the player attack command")

	var serial_seed := _seed([
		_section("event", 0, [_command("actCheckNextSerialNumber", [3]), _command("actInsertEventStatus", [0]), _command("actInsertStoryObjectWaitPos", ["obj_Story_Level_PoisonGas", 9, 672, 128, 288, 288, 64, 384, 480, 544, 640, 576, 576, 800, 288, 800, 96, 896, 224, 1056]), _command("actExecWinFailProcess")]),
	], [_command("actInsertEventStatus", [0])])
	var serial_loop: Dictionary = WinfailScenarioRules.initialize_script_state(base, {"opening": {}}, serial_seed)
	# 0x4525e0: a timer on the handoff counter 0x4c1ad4 — armed to counter + 3 at the first scan,
	# holds at the fourth handoff; the chain's rescan (counter already bumped) re-arms it to 4 + 3.
	var installs: Array = []
	for _handoff in 8:
		serial_loop = WinfailScenarioRules.run_event_hooks(serial_loop)
		installs.append(serial_loop["winfail_runtime"]["story_object_wait_requests"].size())
	_assert_eq(installs, [0, 0, 0, 1, 1, 1, 1, 2], "actCheckNextSerialNumber 3 fires every fourth handoff")
	_assert_eq([serial_loop["winfail_runtime"]["handoff_counter"], serial_loop["winfail_runtime"]["serial_deadline"]], [8, 11], "each handoff bumps the counter once; the rescan re-arms the deadline")
	_assert_eq(serial_loop.get("event_statuses", []), [0], "the self re-arming serial event stays armed")
	# 0x451ecf: each installation draws one rand(count) on the global stream for its pair.
	var requests: Array = serial_loop["winfail_runtime"]["story_object_wait_requests"]
	for index in range(requests.size()):
		var request: Dictionary = requests[index]
		var replay := GlobalRandomStream.rand(request["rng_before"], 9)
		_assert_eq([request["selected_index"], request["selected_position"], request["rng_after"]], [replay["value"], request["positions"][replay["value"]], replay["state"]], "story-object wait position %d is the global stream's rand(9) pick" % index)
		if index > 0:
			check(continues(requests[index - 1], request), "story-object wait positions draw back to back on the global stream")
	_assert_eq(requests.back()["rng_after"], stream_of(serial_loop, "global"), "the last wait-position draw leaves the loop's global words")


## actSetDeadMessage (0x452197) writes the addressed unit's live +0x14 word: the serial picks
## among the token's living units, the installed 稱號 stays the speaker, the fail page's
## dead_messages record is unchanged; with script inserts the same-chain insert is the target
## (WINFAIL006 event 5: the reinforcement 隊長 speaks 969, not its object word 957).
func _script_dead_message_words() -> void:
	var seed := _seed([
		_section("event", 0, [_command("actTRUE"), _command("actSetDeadMessage", ["SID_ENEMY024", 1, 969, 0]), _command("actSetDeadMessage", ["SID_ENEMY023", 2, 374, 375])]),
	], [_command("actInsertEventStatus", [0])])
	var scenario := {"opening": {"actor_bindings": {"SID_ENEMY024/1": {"unit_id": "captain_1"}, "SID_ENEMY024/2": {"unit_id": "captain_2"}, "SID_ENEMY023/1": {"unit_id": "soldier_1"}, "SID_ENEMY023/2": {"unit_id": "soldier_2"}}, "speaker_resource_ids": {"SID_ENEMY023": "376"}}}
	var battle := {"turn": 1, "units": [
		_unit("captain_1", "Enemy024", Vector2i(1, 1), 0, "enemy_ai"),
		_unit("captain_2", "Enemy024", Vector2i(2, 1), 10, "enemy_ai"),
		_unit("soldier_1", "Enemy023", Vector2i(3, 1), 10, "enemy_ai"),
		_unit("soldier_2", "Enemy023", Vector2i(4, 1), 10, "enemy_ai"),
	]}
	battle["units"][1]["title"] = "兵隊長"
	battle["units"][1]["dead_message"] = {"speaker": "兵隊長", "messages": [{"id": "957", "text": "啊"}]}
	var wf: Dictionary = WinfailScenarioRules.run_event_hooks(WinfailScenarioRules.initialize_script_state(battle, scenario, seed))
	_assert_eq(wf["units"][0].get("dead_message", {}), {}, "the fallen first 024 is not the serial-1 target (0x44fad0 counts living objects)")
	_assert_eq(wf["units"][1]["dead_message"], {"speaker": "兵隊長", "messages": [{"id": "969"}]}, "the living 024 takes 969 (msg1 << 16, the zero half copies) under its installed 稱號")
	_assert_eq(wf["units"][3]["dead_message"], {"speaker": "", "speaker_id": "376", "messages": [{"id": "374"}, {"id": "375"}]}, "serial 2 of 023 takes the packed pair first 374, second 375 and names its speaker by the token's resource id")
	_assert_true(not wf["units"][2].has("dead_message"), "serial 1 of 023 is untouched")
	_assert_eq(wf["winfail_runtime"]["dead_messages"], {"SID_ENEMY024": "969", "SID_ENEMY023": "374"}, "the fail page record keeps its token → msg1 shape")
	var sixth := BattlePlayLoop.initialize_roster_growth(BattlePlayLoop.create([], "", BattleScenario.load_file("res://content/battles/battle_006.json")))
	_assert_true(bool(sixth.get("scenario_ok", false)), "battle_006 loop is valid")
	_assert_eq(BattlePlayLoop.unit_ref(sixth, "guard024_1")["dead_message"]["messages"][0]["id"], "957", "the placed 隊長 keeps its object word 957 (WINFAIL006 never addresses it alive)")
	BattlePlayLoop.set_unit_defeated(sixth, "guard024_1", true)
	# Event code 1 (section 5) is armed by the level's earlier chain; arm it directly and
	# drop the phase-one win so the reinforcement event is what fires on the 隊長's fall.
	sixth["event_statuses"] = [1]
	sixth["win_statuses"] = []
	var fired: Dictionary = BattlePlayLoop.resolve_outcome(WinfailScenarioRules.run_event_hooks(sixth))
	_assert_true(bool(fired.get("scenario_ok", false)), "WINFAIL006 event 5 installs its reinforcements: " + str(fired.get("scenario_error", "")))
	var captains: Array = fired["units"].filter(func(row): return str(row["actor_id"]) == "024" and not bool(row.get("defeated", false)))
	_assert_eq(captains.size(), 1, "one living 隊長 after the event")
	if captains.size() == 1:
		_assert_eq(captains[0]["dead_message"], {"speaker": "兵隊長", "messages": [{"id": "969"}]}, "the inserted 隊長 speaks 969 (actSetDeadMessage after its insert in the same chain), not its object word 957")
	_assert_eq(fired["winfail_runtime"]["dead_messages"].get("SID_ENEMY024", ""), "969", "the fail page record follows the same line")


func _exec_mode_and_system_arrival() -> void:
	var seed := _seed([
		_section("event", 0, [
			_command("actTRUE"),
			_command("actRandomSetSysArrivePos", [2, 32, 64, 64, 96]),
			_command("actSetPlayerExecMode", ["SID_HOU", 1, 1]),
		]),
		_section("event", 1, [
			_command("actCheckPlayerArriveSysPos", ["SID_HOU", 1]),
			_command("actMessage", ["SID_HOU", 1, "777"]),
		]),
	], [_command("actInsertEventStatus", [0]), _command("actInsertEventStatus", [1])])
	var scenario := {"scenario_rules": {"cell_size": 32}, "opening": {"actor_bindings": {"SID_HOU/1": {"unit_id": "hou"}}, "speaker_resource_ids": {"SID_HOU": "7"}}}
	var battle := {STREAM_KEYS["global"]: GlobalRandomStream.seeded(1), "turn": 1, "units": [
		_unit("hou", "Player007", Vector2i(2, 3), 10, "enemy_ai"),
	]}
	var wf: Dictionary = WinfailScenarioRules.initialize_script_state(battle, scenario, seed)
	wf = WinfailScenarioRules.run_event_hooks(wf)
	_assert_eq(wf.get("event_statuses", []), [1], "the arrival check waits for the scan after the one that chose the point")
	var chosen: Array = wf["winfail_runtime"]["system_arrival_position"]["position"]
	wf["units"][0]["coord"] = Vector2i(int(chosen[0]) / 32, int(chosen[1]) / 32)
	wf = WinfailScenarioRules.run_event_hooks(wf)
	var arrival: Dictionary = wf["winfail_runtime"]["system_arrival_position"]
	_assert_true((arrival["candidates"] as Array).has(arrival["position"]), "random system arrival selects a listed candidate")
	var arrival_draw := GlobalRandomStream.rand(GlobalRandomStream.seeded(1), 2)
	_assert_eq(arrival["position"], arrival["candidates"][arrival_draw["value"]], "random system arrival picks with one rand(2) on the loop's global stream (0x451787)")
	_assert_eq([arrival["rng_before"], arrival["rng_after"]], [GlobalRandomStream.seeded(1), arrival_draw["state"]], "random system arrival records the global words before and after")
	_assert_eq(wf["units"][0]["player_exec_mode"], 1, "exec mode writes the source mode")
	_assert_eq(wf["units"][0]["player_exec_mode_native"], 5, "exec mode maps argument 1 to native state 5")
	_assert_eq(wf["units"][0]["battle_actor_role"], "enemy_ai", "exec mode does not change faction role")
	_assert_eq(_projected(WinfailScenarioRules.story_dialogue_messages(wf)), [["7", "777"]], "system arrival condition fires at the selected point")
	wf["units"][0]["coord"] = Vector2i(0, 0)
	_assert_true(not WinfailConditions.condition_holds(wf, "actCheckPlayerArriveSysPos", ["SID_HOU", "1"], "event"), "system arrival condition rejects another point")


func _edge_battle() -> Dictionary:
	var battle := {
		"player_unit_id": "hero", "turn": 1, "equipment_items": {"14": {}}, "units": [
			_unit("hero", "Player001", Vector2i(1, 1), 10, "player_controlled"),
			_unit("foe_1", "Enemy023", Vector2i(5, 5), 10, "enemy_ai"),
			_unit("foe_2", "Enemy023", Vector2i(6, 5), 10, "enemy_ai"),
			_unit("friend_1", "Enemy023", Vector2i(2, 2), 10, "friendly_ai"),
		],
	}
	battle["units"][0]["inventory"] = [0, 0, 0, 0, 0, 0, 0, 0]
	return battle


func _edge_scenario() -> Dictionary:
	return {"scenario_rules": {}, "opening": {"speaker_resource_ids": {"SID_ENEMY023": "376", "SID_PLAYER0": "0"}}}


func _edge_objects() -> Array:
	return [{"symbol": "obj_Story_Test_Enemy23", "object_code": 99, "object_data_fields": {"obj_Data6": "SID_ENEMY023", "obj_Data7": "23"}}]


## hsl01.exe 0x450840 enemy-count cases (original_check_targets): case 0x24 strict compare,
## class tokens ignore serial bindings, static hull pieces stay counted; cases 0x23/0x26
## count a never-placed listed class as fallen, an unresolvable token never as fallen.
func _enemy_count_checks_0x450840() -> void:
	var scenario := _edge_scenario()
	var battle := _edge_battle()
	# A serial binding (SID_ENEMY023/1 -> a speaker) must not shrink the class:
	# actCheckEnemyNumber(SID_ENEMY023, 2) counts every living Enemy023 unit.
	var seed53_bound: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://content/generated/hsl/chapter01/battle053_seed.json"))
	var bound_scenario := {"scenario_rules": {}, "opening": {"speaker_resource_ids": {"SID_PLAYER1": "1"}, "actor_bindings": {"SID_PLAYER1/1": {"unit_id": "tina"}, "SID_ENEMY023/1": {"unit_id": "g2"}}}}
	var bound := WinfailScenarioRules.initialize_script_state({"player_unit_id": "tina", "turn": 1, "units": [_unit("tina", "Player002", Vector2i(20, 23)), _unit("g1", "Enemy023", Vector2i(29, 24)), _unit("g2", "Enemy023", Vector2i(27, 23)), _unit("g3", "Enemy023", Vector2i(30, 36))]}, bound_scenario, seed53_bound)
	_assert_eq(bound["winfail_runtime"]["token_resolution"]["SID_ENEMY023"]["unit_ids"], ["g1", "g2", "g3"], "serial-less SID_ENEMY023 is the whole class even with a /1 binding")
	_assert_eq(bound["winfail_runtime"]["token_resolution"]["SID_PLAYER1"], {"source": "binding", "unit_ids": ["tina"]}, "SID_PLAYER1 resolves through its binding")
	_assert_eq(WinfailConditions.units_for_token(bound, "SID_ENEMY023", 1), ["g2"], "SID_ENEMY023,1 selects the bound instance")
	bound = WinfailScenarioRules.run_event_hooks(bound)
	_assert_eq(WinfailScenarioRules.reinforcement_deficits(bound), {}, "three guards alive: the count event (< 2) stays quiet despite the binding")
	_kill(bound, "g1")
	bound = WinfailScenarioRules.run_event_hooks(bound)
	_assert_eq(WinfailScenarioRules.reinforcement_deficits(bound), {}, "two guards alive: 2 < 2 is false (0x450840 case 0x24 is a strict compare)")
	_kill(bound, "g3")
	bound = WinfailScenarioRules.run_event_hooks(bound)
	_assert_eq(WinfailScenarioRules.reinforcement_deficits(bound), {"Enemy023": 1}, "one guard alive: the count event fires once")
	# Static enemy objects (hull pieces) stay registered: 26 drawn pieces never satisfy < 26.
	var hull_seed := _seed([
		_section("fail", 0, [_command("actCheckEnemyNumber", ["SID_ENEMY101", 26])]),
	], [_command("actInsertFailStatus", [0])])
	var hull_loop: Dictionary = WinfailScenarioRules.initialize_script_state({"player_unit_id": "tina", "turn": 1, "units": [_unit("tina", "Player002", Vector2i(20, 23))], "last_attack": {}}, {"scenario_rules": {"static_enemy_counts": {"SID_ENEMY101": 26}}, "opening": {}}, hull_seed)
	_assert_eq(WinfailScenarioRules.victory_state(hull_loop), {}, "26 static Enemy101 hull pieces keep the < 26 fail check quiet")
	hull_loop["winfail_runtime"]["static_enemy_counts"] = {"SID_ENEMY101": 25}
	_assert_eq(WinfailScenarioRules.victory_state(hull_loop), WinfailScenarioRules.DEFEAT_OUTCOME, "one hull piece fewer than the threshold fails the battle")

	# hsl01.exe 0x450840 case 0x23/0x26 only counts ids 0x44fad0 still finds: a listed class
	# with no unit at all is fallen (WINFAIL533 lists 024/027 its EVEF never places), while a
	# token the remake cannot resolve never satisfies a check.
	var absent := _seed([
		_section("fail", 0, [_command("actCheckPlayer", [2, "SID_PLAYER0", "SID_不明"])], "-1,748"),
		_section("win", 0, [_command("actCheckEnemy", [3, "SID_ENEMY024", "SID_ENEMY023", "SID_ENEMY027"]), _command("actSetNextPlayLevelEvent", [7, 7])], "-1,121"),
	], [_command("actInsertFailStatus", [0]), _command("actInsertWinStatus", [0])])
	var absent_loop: Dictionary = WinfailScenarioRules.initialize_script_state(battle, scenario, absent)
	_assert_eq(WinfailScenarioRules.victory_state(absent_loop), {}, "a living Enemy023 keeps the win open although 024/027 were never placed")
	_kill(absent_loop, "hero")
	_assert_eq(WinfailScenarioRules.commit_outcome(absent_loop)["winfail_runtime"]["resolved"]["key"], WinfailScenarioRules.PARTY_WIPE_KEY, "an unresolved token never counts as fallen: fail 0 still needs two (the party wipe is the recorded resolution)")
	absent_loop["units"][0]["hp"] = 10
	absent_loop["units"][0]["defeated"] = false
	_kill(absent_loop, "foe_1")
	_kill(absent_loop, "foe_2")
	_kill(absent_loop, "friend_1")
	_assert_eq(WinfailScenarioRules.victory_state(absent_loop), BattleOutcome.VICTORY_BOSS, "never-placed 024/027 count as fallen once every 023 is down")


## Status arming semantics of the original winfail scan (0x453b30 status-object tick):
## deleted statuses never fire, commit-on-fire, actExecWinFailProcess chains, actCheckEventNotExist
## as a head condition and as a mid-chain gate (0x450840 case 0x72).
func _status_arming_and_chains() -> void:
	var scenario := _edge_scenario()
	var battle := _edge_battle()
	# Deleted statuses never fire; a fired insert stays owed even after disarming.
	var seed53: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://content/generated/hsl/chapter01/battle053_seed.json"))
	var tina := {"player_unit_id": "tina", "turn": 1, "units": [_unit("tina", "Player029", Vector2i(20, 23)), _unit("g1", "Enemy023", Vector2i(29, 24)), _unit("g2", "Enemy023", Vector2i(27, 23)), _unit("g3", "Enemy023", Vector2i(30, 36))]}
	var deleted: Dictionary = WinfailScenarioRules.initialize_script_state(tina, {"scenario_rules": {}, "opening": {"speaker_resource_ids": {"SID_PLAYER1": "1"}}}, seed53)
	deleted["event_statuses"] = [1, 2]
	deleted["turn"] = 5
	deleted = WinfailScenarioRules.run_event_hooks(deleted)
	_assert_eq(WinfailScenarioRules.reinforcement_deficits(deleted), {}, "deleted event0 does not fire at round 5")
	_assert_true(not (deleted.get("event_log", []) as Array).has("event_0"), "deleted event0 not logged")
	deleted["turn"] = 7
	deleted = WinfailScenarioRules.run_event_hooks(deleted)
	_assert_eq(WinfailScenarioRules.reinforcement_deficits(deleted), {"Enemy023": 1}, "event1 still fires at round 7")
	deleted["event_statuses"] = []
	deleted = WinfailScenarioRules.run_event_hooks(deleted)
	_assert_eq(WinfailScenarioRules.reinforcement_deficits(deleted), {"Enemy023": 1}, "a committed insert stays owed after the event list is cleared (commit-on-fire)")
	_assert_eq((deleted["winfail_runtime"]["fired"] as Array).size(), 1, "one status fired")

	# actExecWinFailProcess chains a newly armed status in the same call; dialogue de-duplicates.
	var chain := _seed([
		_section("event", 0, [_command("actTRUE"), _command("actMessage", ["SID_ENEMY023", 1, "500"]), _command("actInsertEventStatus", [1]), _command("actExecWinFailProcess")]),
		_section("event", 1, [_command("actTRUE"), _command("actMessage", ["SID_PLAYER0", 1, "501"]), _command("actDelay", [20])]),
		_section("event", 2, [_command("actTRUE"), _command("actMessage", ["SID_PLAYER0", 1, "502"])]),
		_section("fail", 0, [_command("actCheckPlayer", [1, "SID_PLAYER0"])], "SID_PLAYER0,122"),
	], [_command("actInsertEventStatus", [0]), _command("actInsertFailStatus", [0])])
	var chained: Dictionary = WinfailScenarioRules.initialize_script_state(battle, scenario, chain)
	_assert_eq(chained.get("event_statuses", []), [0], "only event0 armed by the story")
	chained = WinfailScenarioRules.run_event_hooks(chained)
	_assert_eq(chained.get("event_statuses", []), [], "event0 and the chained event1 both consumed in one call")
	_assert_eq(_projected(WinfailScenarioRules.story_dialogue_messages(chained)), [["376", "500"], ["0", "501"]], "messages in fire order; event2 never armed")
	_assert_eq(chained["winfail_runtime"]["presentation_requests"], [{"key": "event_1", "name": "actDelay", "args": ["20"]}], "actDelay is recorded only")
	var twice: Dictionary = WinfailScenarioRules.run_event_hooks(chained)
	_assert_eq(WinfailScenarioRules.story_dialogue_messages(twice), WinfailScenarioRules.story_dialogue_messages(chained), "re-running hooks does not repeat dialogue")
	_assert_eq(WinfailScenarioRules.victory_state(chained), {}, "alive player: ongoing")
	_kill(chained, "hero")
	_assert_eq(WinfailScenarioRules.victory_state(chained), BattleOutcome.DEFEAT_FALLEN, "fail status decides the shared defeat key")
	_assert_eq(WinfailScenarioRules.result_message_id(chained, BattleOutcome.DEFEAT_FALLEN), "122", "fail board label")

	# AND-chain with actCheckEventNotExist; unresolved count tokens never satisfy <=.
	var and_seed := _seed([
		_section("event", 0, [_command("actCheckRoundNumber", [1]), _command("actCheckEventNotExist", [1, 1]), _command("actMessage", ["SID_PLAYER0", 1, "700"])]),
		_section("event", 1, [_command("actCheckRoundNumber", [3])]),
		_section("event", 2, [_command("actCheckEnemyNumber", ["SID_雷歐納德", 5]), _command("actMessage", ["SID_PLAYER0", 1, "701"])]),
		_section("event", 3, [_command("actCheckEnemyNumber", ["SID_ENEMY099", 5]), _command("actMessage", ["SID_PLAYER0", 1, "702"])]),
	], [_command("actInsertEventStatus", [0]), _command("actInsertEventStatus", [1]), _command("actInsertEventStatus", [2]), _command("actInsertEventStatus", [3])])
	var and_loop: Dictionary = WinfailScenarioRules.initialize_script_state(battle, scenario, and_seed)
	and_loop = WinfailScenarioRules.run_event_hooks(and_loop)
	_assert_eq(and_loop.get("event_statuses", []), [0, 1, 2], "event0 waits while event1 exists; unresolved 雷歐納德 count never fires; absent SID_ENEMY099 (0 < 5) fires")
	_assert_eq(_projected(WinfailScenarioRules.story_dialogue_messages(and_loop)), [["0", "702"]], "only the resolvable class count fired")
	and_loop["turn"] = 3
	and_loop = WinfailScenarioRules.run_event_hooks(and_loop)
	_assert_eq(and_loop.get("event_statuses", []), [0, 2], "event1 consumed at round 3; event0 needs another pass")
	and_loop = WinfailScenarioRules.run_event_hooks(and_loop)
	_assert_eq(and_loop.get("event_statuses", []), [2], "event0 fires once event1 no longer exists")

	# Mid-chain actCheckEventNotExist (0x450840 case 0x72 in the status-object tick 0x453b30):
	# a listed event still armed ends the chain there; none armed lets it continue.
	var gate_sections := [
		_section("event", 0, [_command("actCheckRoundNumber", [1]), _command("actMessage", ["SID_PLAYER0", 1, "710"]), _command("actCheckEventNotExist", [2, 1, 2]), _command("actMessage", ["SID_PLAYER0", 1, "711"]), _command("actInsertWinStatus", [0])]),
		_section("event", 1, [_command("actCheckRoundNumber", [3])]),
		_section("win", 0, [_command("actTRUE")], "-1,121"),
	]
	var gated: Dictionary = WinfailScenarioRules.run_event_hooks(WinfailScenarioRules.initialize_script_state(battle, scenario, _seed(gate_sections, [_command("actInsertEventStatus", [0]), _command("actInsertEventStatus", [1])])))
	_assert_eq(_projected(WinfailScenarioRules.story_dialogue_messages(gated)), [["0", "710"]], "the chain runs up to the gate and stops while a listed event is armed")
	_assert_eq([gated.get("event_statuses", []), gated.get("win_statuses", []), int(gated["winfail_runtime"]["fired"][0].get("chain_stop_index", -1)), gated["winfail_runtime"]["unsupported_encountered"]], [[1], [], 2, []], "the gated status is consumed, win 0 stays unarmed, the stop index is recorded")
	var open_gate: Dictionary = WinfailScenarioRules.run_event_hooks(WinfailScenarioRules.initialize_script_state(battle, scenario, _seed(gate_sections, [_command("actInsertEventStatus", [0])])))
	_assert_eq(_projected(WinfailScenarioRules.story_dialogue_messages(open_gate)), [["0", "710"], ["0", "711"]], "with no listed event armed the chain continues past the gate")
	_assert_eq([open_gate.get("win_statuses", []), open_gate["winfail_runtime"]["fired"][0].has("chain_stop_index")], [[0], false], "the passed gate arms win 0 and records no stop")


## Native action tokens as the original scripts use them: actGetItem into the party
## inventory, actCheckPlayerHPLow ratio, actMessageIfExist branches, actDeleteObject serials,
## actInsertObject class joins and landing cells (obj_Data7, 32-px cells).
func _native_action_tokens() -> void:
	var scenario := _edge_scenario()
	var battle := _edge_battle()
	var objects := _edge_objects()
	# Native get-item and position-object deletion remain explicit coordinator requests.
	var item_position := _seed([
		_section("event", 0, [_command("actTRUE"), _command("actGetItem", [14, 1]), _command("actDeletePosObject", [640, 488, 2, "defProcStandObject"]), _command("actMessage", ["SID_PLAYER0", 1, "599"])]),
	], [_command("actInsertEventStatus", [0])])
	var item_position_loop: Dictionary = WinfailScenarioRules.initialize_script_state(battle, scenario, item_position)
	item_position_loop = WinfailScenarioRules.run_event_hooks(item_position_loop)
	_assert_eq(item_position_loop["winfail_runtime"]["item_requests"][0].get("status"), "applied", "actGetItem applies to the party inventory")
	_assert_eq(item_position_loop["units"][0].get("inventory", [])[0], 14, "actGetItem uses the controlled party inventory")
	_assert_eq(item_position_loop["winfail_runtime"]["departed_unit_ids"], [], "position deletion does not guess a unit departure")
	_assert_eq(_projected(WinfailScenarioRules.story_dialogue_messages(item_position_loop)), [["0", "599"]], "following action still runs")

	# HP ratio, actMessageIfExist branches, actDeleteObject departures, dedupe within one status.
	var hp_seed := _seed([
		_section("event", 0, [_command("actCheckPlayerHPLow", ["SID_ENEMY023", 1, 30]), _command("actMessageIfExist", ["SID_PLAYER0", 1, "800", "801", 1, "SID_ENEMY023"]), _command("actDeleteObject", ["SID_ENEMY023", 2]), _command("actSetPlayerUndead", ["SID_ENEMY023", 1, 0]), _command("actWaitPlayer", ["SID_PLAYER0", 1]), _command("actSetWaitRound", ["SID_ENEMY023", 1, 3])]),
		_section("event", 1, [_command("actCheckEnemyTotalNumber", [1]), _command("actMessageIfExist", ["SID_PLAYER0", 1, "802", "803", 1, "SID_ENEMY099"]), _command("actMessage", ["SID_PLAYER0", 1, "803"])]),
	], [_command("actInsertEventStatus", [0]), _command("actInsertEventStatus", [1])])
	var hp_loop: Dictionary = WinfailScenarioRules.initialize_script_state(battle, scenario, hp_seed)
	hp_loop = WinfailScenarioRules.run_event_hooks(hp_loop)
	_assert_eq(hp_loop.get("event_statuses", []), [0, 1], "full HP: nothing fires")
	hp_loop["units"][1]["hp"] = 4
	hp_loop = WinfailScenarioRules.run_event_hooks(hp_loop)
	_assert_eq(hp_loop.get("event_statuses", []), [0, 1], "4/10 is above 30%")
	hp_loop["units"][1]["hp"] = 3
	hp_loop = WinfailScenarioRules.run_event_hooks(hp_loop)
	_assert_eq(hp_loop.get("event_statuses", []), [1], "3/10 <= 30% fires event0 and that scan ends there")
	hp_loop = WinfailScenarioRules.run_event_hooks(hp_loop)
	_assert_eq(hp_loop.get("event_statuses", []), [], "the departed second soldier leaves one enemy so the next scan fires event1")
	_assert_eq(_projected(WinfailScenarioRules.story_dialogue_messages(hp_loop)), [["0", "800"], ["0", "803"]], "true branch 800 (023 alive), false branch 803 (no 099), duplicate 803 collapsed")
	_assert_eq(hp_loop["winfail_runtime"]["departed_unit_ids"], ["foe_2"], "actDeleteObject serial 2 departs the second living unit of the class")

	# Inserts: class join, wait round on the insert record, per-class accounting, self re-arm guard.
	var insert_seed := _seed([
		_section("event", 0, [_command("actCheckRoundNumber", [2]), _command("actInsertObject", ["obj_Story_Test_Enemy23", -32, 480]), _command("actSetPrevInsertObjectWaitRound", [2]), _command("actWalkPrevInsertObjectWait", [160, 576, 8]), _command("actInsertObject", ["obj_Unknown_Symbol", 0, 0]), _command("actWalkPrevInsertObject", [64, 64, 0]), _command("actInsertEventStatus", [0])]),
	], [_command("actInsertEventStatus", [0])], objects)
	var insert_rules: Dictionary = WinfailScenarioRules.rules_from_seed(insert_seed)
	_assert_eq(WinfailScenarioRules.insert_walk_cells(insert_rules), [Vector2i(5, 18), Vector2i(2, 2)], "two landing cells")
	var insert_loop: Dictionary = WinfailScenarioRules.initialize_script_state(battle, scenario, insert_seed)
	insert_loop["turn"] = 2
	insert_loop = WinfailScenarioRules.run_event_hooks(insert_loop)
	_assert_eq(WinfailScenarioRules.reinforcement_deficits(insert_loop), {"Enemy023": 1}, "only the joined class is owed")
	_assert_eq(insert_loop.get("event_statuses", []), [0], "self re-arming insert event re-armed")
	insert_loop = WinfailScenarioRules.run_event_hooks(insert_loop)
	_assert_eq(WinfailScenarioRules.reinforcement_deficits(insert_loop), {"Enemy023": 1}, "re-armed insert event waits for its recruit before asking again")
	insert_loop["units"].append(_unit("Enemy023_reinforcement_9", "Enemy023", Vector2i(5, 18), 10, "enemy_ai"))
	_assert_eq(WinfailScenarioRules.reinforcement_deficits(insert_loop), {}, "recruit settles the deficit")
	insert_loop = WinfailScenarioRules.run_event_hooks(insert_loop)
	_assert_eq(WinfailScenarioRules.reinforcement_deficits(insert_loop), {"Enemy023": 1}, "then it asks for the next one")


## Win/fail checks, objective-board labels and the next-level token (original_check_targets:
## actCheckPlayer/actCheckEnemy all-listed reading, arrival rectangles, actSetNextPlayLevelEvent
## default vs issuing status — WINFAIL010 event_6).
func _win_fail_board_and_next_level() -> void:
	var scenario := _edge_scenario()
	var battle := _edge_battle()
	# Armed win/event labels show on the objective board; actCheckEnemyTotalNumber counts enemy_ai only.
	var labels := _seed([
		_section("event", 0, [_command("actTRUE"), _command("actMessage", ["SID_PLAYER0", 1, "600"]), _command("actBMSetPointEvent", [3, 504, "bmpmVisit"]), _command("actAddTE", ["town_x", 169, 0])], "-1,361"),
		_section("event", 1, [_command("actCheckSerialPlayerAttacked", ["SID_ENEMY067", 1]), _command("actMessage", ["SID_PLAYER0", 1, "601"])]),
		_section("win", 0, [_command("actCheckEnemyTotalNumber", [0]), _command("actSetTownExecEvent", ["town_x", 9])], "-1,121"),
	], [_command("actInsertEventStatus", [0]), _command("actInsertEventStatus", [1]), _command("actInsertWinStatus", [0])])
	var labels_loop: Dictionary = WinfailScenarioRules.initialize_script_state(battle, scenario, labels)
	_assert_eq(WinfailScenarioRules.objective_board(labels_loop)["event"], [{"key": "event", "speaker_id": "", "message_id": "361", "actor_token": "-1"}], "an armed event label shows on the board")
	labels_loop = WinfailScenarioRules.run_event_hooks(labels_loop)
	_assert_eq(WinfailScenarioRules.objective_board(labels_loop)["event"], [], "the consumed event label leaves the board")
	_assert_eq((labels_loop["winfail_runtime"]["pending_world_flags"] as Array).size(), 2, "town/big-map flags recorded, not executed")
	_assert_eq(WinfailScenarioRules.objective_board(labels_loop)["win"], [{"key": "win", "speaker_id": "", "message_id": "121", "actor_token": "-1"}], "-1 board label keeps its message id without a speaker")
	_assert_eq(WinfailScenarioRules.victory_state(labels_loop), {}, "two enemies alive: no clear")
	_kill(labels_loop, "foe_1")
	_kill(labels_loop, "foe_2")
	_assert_eq(WinfailScenarioRules.victory_state(labels_loop), BattleOutcome.VICTORY_ENEMIES_CLEARED, "friendly Enemy023 does not count; enemy_ai clear wins")
	var cleared: Dictionary = WinfailScenarioRules.commit_outcome(labels_loop)
	_assert_eq((cleared["winfail_runtime"]["pending_world_flags"] as Array).size(), 3, "win result actSetTownExecEvent recorded on commit")
	_assert_eq(WinfailScenarioRules.result_message_id(cleared, BattleOutcome.VICTORY_ENEMIES_CLEARED), "121", "clear board label 121")

	# actCheckPlayer with several tokens needs all of them down; actCheckEnemy shares the reading.
	var multi := _seed([
		_section("fail", 0, [_command("actCheckPlayer", [2, "SID_PLAYER0", "SID_ENEMY023"])], "-1,748"),
		_section("win", 0, [_command("actCheckEnemy", [1, "SID_ENEMY023"]), _command("actMessage", ["SID_PLAYER0", 1, "900"]), _command("actSetNextPlayLevelEvent", [7, 7])], "-1,121"),
		_section("win", 1, [_command("actCheckPlayerArrivePos", ["SID_PLAYER0", 1, 64, 64, 95, 95]), _command("actSetNextPlayLevelEvent", [8, 8])], "SID_PLAYER0,362"),
	], [_command("actInsertFailStatus", [0]), _command("actInsertWinStatus", [0]), _command("actInsertWinStatus", [1])])
	var multi_loop: Dictionary = WinfailScenarioRules.initialize_script_state(battle, scenario, multi)
	_assert_eq(multi_loop.get("next_level_event", []), [7, 7], "default next level from the first win status")
	_assert_eq(multi_loop.get("next_level_event_status", "?"), "", "the win-section default names no issuing status")
	_assert_eq(multi_loop.get("objective_phase", ""), "escape", "an armed arrival win makes the objective an escape")
	_assert_eq(multi_loop.get("escape_zone", []), [Vector2i(2, 2)], "escape zone from the arrival rectangle")
	_assert_eq((WinfailScenarioRules.objective_board(multi_loop)["win"] as Array).size(), 2, "both armed win labels listed")
	_kill(multi_loop, "hero")
	# hero is the only fielded player: the remake party-wipe rule (not fail 0) decides here.
	_assert_eq(WinfailScenarioRules.commit_outcome(multi_loop)["winfail_runtime"]["resolved"]["key"], WinfailScenarioRules.PARTY_WIPE_KEY, "one of two listed units down: fail 0 does not hold (the party wipe is the recorded resolution)")
	multi_loop["units"][0]["hp"] = 10
	multi_loop["units"][0]["defeated"] = false
	multi_loop["units"][0]["coord"] = Vector2i(2, 2)
	_assert_eq(WinfailScenarioRules.victory_state(multi_loop), BattleOutcome.VICTORY_ESCAPE, "arrival wins")
	var escaped: Dictionary = WinfailScenarioRules.commit_outcome(multi_loop)
	_assert_eq(escaped.get("next_level_event", []), [8, 8], "the fired win overrides the default next level")
	_assert_eq(escaped.get("next_level_event_status", ""), "win_1", "the fired status that wrote the token is recorded")
	_assert_eq(WinfailScenarioRules.result_message_id(escaped, BattleOutcome.VICTORY_ESCAPE), "362", "arrival board label")
	# A fired dialogue-only event leaves the default token and no issuing status:
	# the runtime must not end the battle from its cutscene (WINFAIL010 event_6).
	var chatter := _seed([
		_section("win", 0, [_command("actCheckEnemy", [1, "SID_ENEMY023"]), _command("actSetNextPlayLevelEvent", [7, 7])], "-1,121"),
		_section("event", 0, [_command("actCheckRoundNumber", [2]), _command("actMessage", ["SID_PLAYER0", 1, "901"])]),
		_section("event", 1, [_command("actCheckRoundNumber", [3]), _command("actMessage", ["SID_PLAYER0", 1, "902"]), _command("actSetNextPlayLevelEvent", [41, 49])]),
	], [_command("actInsertWinStatus", [0]), _command("actInsertEventStatus", [0]), _command("actInsertEventStatus", [1])])
	var chatter_loop: Dictionary = WinfailScenarioRules.initialize_script_state(battle, scenario, chatter)
	chatter_loop["turn"] = 2
	chatter_loop = WinfailScenarioRules.run_event_hooks(chatter_loop)
	_assert_eq(chatter_loop.get("event_log", []), ["event_0"], "the round-2 dialogue event fires")
	_assert_eq(chatter_loop.get("next_level_event", []), [7, 7], "a dialogue-only event keeps the win-section default")
	_assert_eq(chatter_loop.get("next_level_event_status", "?"), "", "and names no issuing status")
	chatter_loop["turn"] = 3
	chatter_loop = WinfailScenarioRules.run_event_hooks(chatter_loop)
	_assert_eq(chatter_loop.get("next_level_event", []), [41, 49], "an event carrying actSetNextPlayLevelEvent rewrites the token")
	_assert_eq(chatter_loop.get("next_level_event_status", ""), "event_1", "and is recorded as the issuing status for the runtime's event-only handoff")
	multi_loop["units"][0]["coord"] = Vector2i(1, 1)
	_kill(multi_loop, "foe_1")
	_kill(multi_loop, "foe_2")
	_kill(multi_loop, "friend_1")
	_assert_eq(WinfailScenarioRules.victory_state(multi_loop), BattleOutcome.VICTORY_BOSS, "all Enemy023 down satisfies actCheckEnemy")
	multi_loop["battle_outcome"] = BattleOutcome.VICTORY_BOSS
	_assert_eq(_projected(WinfailScenarioRules.story_dialogue_messages(multi_loop)), [["0", "900"]], "win message without commit")
	_assert_eq(WinfailScenarioRules.result_message_id(multi_loop, BattleOutcome.VICTORY_BOSS), "121", "board label of the deciding win")

	var frozen := multi_loop.duplicate(true)
	frozen["battle_outcome"] = BattleOutcome.VICTORY_BOSS
	_assert_eq(WinfailScenarioRules.run_event_hooks(frozen)["winfail_runtime"]["fired"], frozen["winfail_runtime"]["fired"], "hooks are inert once the outcome is frozen")


## Player-side totals and any-player arrival (actCheckPlayerTotalNumber, actCheckAnyPlayerArrivePos),
## walk-and-delete departures, actKeepPlayerST carry.
func _player_side_totals() -> void:
	var scenario := _edge_scenario()
	var battle := _edge_battle()
	var objects := _edge_objects()
	var side_seed := _seed([
		_section("fail", 0, [_command("actCheckPlayerTotalNumber", [0])], "-1,748"),
		_section("win", 0, [_command("actCheckAnyPlayerArrivePos", [128, 128, 128, 128]), _command("actKeepPlayerST"), _command("actScrollBGToPos", [64, 64]), _command("actBMClearTrackFlag", [3, "bmpmHidden"])], "-1,121"),
		_section("event", 0, [_command("actCheckRoundNumber", [2]), _command("actWalkAndDeleteWait", ["SID_ENEMY023", 1, 608, 1280, 8]), _command("actInsertObject", ["obj_Story_Test_Enemy23", 0, 0]), _command("actSetPrevInsertObjectFly", [1]), _command("actSetPrevInsertObjectST", [20]), _command("actSetPrevInsertObjectEquip", [5, 0]), _command("actWalkPrevInsertObject", [96, 96, 0])]),
	], [_command("actInsertFailStatus", [0]), _command("actInsertWinStatus", [0]), _command("actInsertEventStatus", [0])], objects)
	var side_loop: Dictionary = WinfailScenarioRules.initialize_script_state(battle, scenario, side_seed)
	_assert_eq(side_loop.get("objective_phase", ""), "escape", "any-player arrival is an escape objective")
	_assert_eq(side_loop.get("escape_zone_cells", []), [[4, 4]], "any-player arrival cell (4,4); friend_1 at (2,2) is not on it")
	_assert_eq(WinfailScenarioRules.victory_state(side_loop), {}, "nobody arrived, two player-side units alive")
	side_loop["turn"] = 2
	side_loop = WinfailScenarioRules.run_event_hooks(side_loop)
	_assert_eq(side_loop["winfail_runtime"]["departed_unit_ids"], ["foe_1"], "actWalkAndDeleteWait departs the first living 023")
	_assert_eq(side_loop["winfail_runtime"]["presentation_requests"][0]["name"], "actWalkAndDeleteWait", "the walk-out is also a presentation request")
	_assert_eq(WinfailScenarioRules.reinforcement_deficits(side_loop), {"Enemy023": 1}, "the flying recruit is owed")
	side_loop["units"][3]["coord"] = Vector2i(4, 4)
	_assert_eq(WinfailScenarioRules.victory_state(side_loop), BattleOutcome.VICTORY_ESCAPE, "a friendly unit on the cell satisfies actCheckAnyPlayerArrivePos")
	var side_won: Dictionary = WinfailScenarioRules.commit_outcome(side_loop)
	_assert_eq(side_won["winfail_runtime"]["carry_requests"], [{"key": "win_0", "kind": "keep_stamina"}], "actKeepPlayerST recorded as a carry request")
	_assert_eq((side_won["winfail_runtime"]["pending_world_flags"] as Array).size(), 1, "actBMClearTrackFlag recorded as a world flag")
	_assert_eq(side_won["winfail_runtime"]["presentation_requests"][1], {"key": "win_0", "name": "actScrollBGToPos", "args": ["64", "64"]}, "win scroll recorded for a coordinator")
	side_loop["units"][3]["coord"] = Vector2i(9, 9)
	_kill(side_loop, "hero")
	_assert_eq(WinfailScenarioRules.commit_outcome(side_loop)["winfail_runtime"]["resolved"]["key"], WinfailScenarioRules.PARTY_WIPE_KEY, "one friendly still alive: player total 1 > 0 (actCheckPlayerTotalNumber does not hold; the wipe of the only controlled unit is the recorded resolution)")
	_kill(side_loop, "friend_1")
	_assert_eq(WinfailScenarioRules.victory_state(side_loop), BattleOutcome.DEFEAT_FALLEN, "no player-side unit alive: actCheckPlayerTotalNumber 0 fails the battle")


func _round_and_x_range_tokens() -> void:
	var round_seed := _seed([
		_section("event", 0, [_command("actCheckRoundDisp", [5]), _command("actMessage", ["SID_PLAYER0", 1, 900])]),
	], [_command("actInsertEventStatus", [0])])
	var scenario := {"scenario_rules": {}, "opening": {"actor_bindings": {"SID_PLAYER0/1": {"unit_id": "p0", "actor_id": "001"}}}}
	var round_loop: Dictionary = WinfailScenarioRules.initialize_script_state({"player_unit_id": "p0", "turn": 1, "units": [_unit("p0", "Player001", Vector2i(1, 1), 10, "player_controlled")]}, scenario, round_seed)
	round_loop["turn"] = 4
	round_loop = WinfailScenarioRules.run_event_hooks(round_loop)
	_assert_eq(round_loop["winfail_runtime"]["fired"].size(), 0, "actCheckRoundDisp is false before round 5")
	round_loop["turn"] = 5
	round_loop = WinfailScenarioRules.run_event_hooks(round_loop)
	_assert_eq(round_loop["winfail_runtime"]["fired"].size(), 1, "actCheckRoundDisp is true at round 5")

	var detect_seed := _seed([
		_section("event", 0, [_command("actDetectRoundDispDisp", [-2]), _command("actMessage", ["SID_PLAYER0", 1, 901])]),
	], [_command("actInsertEventStatus", [0])])
	var detect_loop: Dictionary = WinfailScenarioRules.initialize_script_state({"player_unit_id": "p0", "turn": 1, "units": [_unit("p0", "Player001", Vector2i(1, 1), 10, "player_controlled")]}, scenario, detect_seed)
	detect_loop["winfail_runtime"]["round_display_baseline"] = 5
	detect_loop["turn"] = 2
	detect_loop = WinfailScenarioRules.run_event_hooks(detect_loop)
	_assert_eq(detect_loop["winfail_runtime"]["fired"].size(), 0, "actDetectRoundDispDisp is false before baseline plus offset")
	detect_loop["turn"] = 3
	detect_loop = WinfailScenarioRules.run_event_hooks(detect_loop)
	_assert_eq(detect_loop["winfail_runtime"]["fired"].size(), 1, "actDetectRoundDispDisp is true at baseline plus offset")

	var x_seed := _seed([
		_section("event", 0, [
			_command("actTRUE"),
			_command("actDeletePosPlayerXRange", [32, 128, 3, "defProcPlayer"]),
			_command("actInsertStoryObjectXRange", ["obj_Story_Block", 480, 640, 3]),
			_command("actInsertLevelUpStar", ["WAV\\EFF0010.WAV"]),
			_command("actPlayMovie", [140]),
		]),
	], [_command("actInsertEventStatus", [0])])
	var x_units := [
		_unit("player_in", "Player001", Vector2i(1, 4), 10, "player_controlled"),
		_unit("player_in_2", "Player002", Vector2i(3, 4), 10, "friendly_ai"),
		_unit("enemy_in", "Enemy023", Vector2i(2, 4), 10, "enemy_ai"),
		_unit("player_out", "Player003", Vector2i(2, 5), 10, "player_controlled"),
	]
	var x_loop: Dictionary = WinfailScenarioRules.initialize_script_state({"player_unit_id": "player_in", "turn": 1, "units": x_units}, scenario, x_seed)
	x_loop = WinfailScenarioRules.run_event_hooks(x_loop)
	var runtime: Dictionary = x_loop["winfail_runtime"]
	_assert_true(bool(WinfailScenarioRules.rules_from_seed(x_seed)["fully_supported"]), "round display and X-range tokens are supported")
	_assert_eq(runtime["player_x_range_delete_requests"][0]["unit_ids"], ["player_in", "player_in_2"], "X-range deletion selects only player-side units in the three-cell pixel span")
	_assert_eq(runtime["departed_unit_ids"], ["player_in", "player_in_2"], "X-range deletion uses the existing departure ledger")
	_assert_eq(runtime["story_object_x_range_requests"][0]["positions"].map(func(value): return value["cell"]), [Vector2i(15, 20), Vector2i(16, 20), Vector2i(17, 20)], "X-range insertion quantizes pixels and includes exactly x_number cells")
	_assert_eq(runtime["movie_requests"][0]["movie"], "end", "actPlayMovie 140 records the ending film request")


## ---------------------------------------------------------------------------
## (4) adapter dispatch: rule_adapter "winfail" routes every seam to the interpreter

func _random_position_family() -> void:
	var object_record := {"symbol": "obj_Story_Test_Enemy23", "object_data_fields": {"obj_Data6": "SID_ENEMY023", "obj_Data7": "23"}}
	var random_seed := _seed([
		_section("event", 0, [_command("actTRUE"), _command("actSetPlayerPosToRandom0", ["SID_ENEMY023", 1]), _command("actInsertObjectRandomPos", ["obj_Story_Test_Enemy23", 0, 0, 0]), _command("actInsertRandomObject", ["obj_Effect_Test", 0, 32, 32, 4, 4]), _command("actDeleteRandomPosObject", [0, 16, "defProcEnemy"])]),
	], [_command("actInsertEventStatus", [0])], [object_record])
	var tiles := {}
	for y in range(6):
		for x in range(6):
			tiles[Vector2i(x, y)] = {"blocks_movement": false, "movement_flags": 0}
	var battle := {STREAM_KEYS["global"]: GlobalRandomStream.seeded(1), "map_size": Vector2i(6, 6), "tiles": tiles, "turn": 1, "player_unit_id": "hero", "units": [_unit("hero", "Player001", Vector2i(1, 1), 10, "player_controlled"), _unit("foe", "Enemy023", Vector2i(2, 2), 10, "enemy_ai")]}
	var first: Dictionary = WinfailScenarioRules.initialize_script_state(battle, {"rule_adapter": "winfail"}, random_seed)
	var second: Dictionary = WinfailScenarioRules.initialize_script_state(battle, {"rule_adapter": "winfail"}, random_seed)
	first = WinfailScenarioRules.run_event_hooks(first)
	second = WinfailScenarioRules.run_event_hooks(second)
	var first_runtime: Dictionary = first["winfail_runtime"]
	var second_runtime: Dictionary = second["winfail_runtime"]
	var effect: Dictionary = first_runtime["presentation_requests"].filter(func(item): return item.get("name") == "actInsertRandomObject")[0]
	_assert_eq([effect["objects"].size(), effect["rng_after"]], [4, GlobalRandomStream.advance(GlobalRandomStream.seeded(1), 12)], "actInsertRandomObject draws width, height and delay on the global stream for each of its 4 objects (0x450f99)")
	_assert_eq(first_runtime["inserts"][0]["position_xy"], second_runtime["inserts"][0]["position_xy"], "fixed seed produces the same random insertion pixel")
	var coord: Vector2i = Vector2i(first_runtime["inserts"][0]["position_xy"][0] / 32, first_runtime["inserts"][0]["position_xy"][1] / 32)
	_assert_true(coord.x >= 0 and coord.y >= 0 and coord.x < 6 and coord.y < 6, "random insertion stays inside the map")
	_assert_true(not first["tiles"][coord].get("blocks_movement", false), "random insertion avoids blocked terrain")
	_assert_eq(coord, Vector2i(2, 2), "actInsertObjectRandomPos inserts at slot 0 plus its displacement, drawing nothing (0x450f2c)")
	_assert_eq(first_runtime["departed_unit_ids"], ["foe"], "random-position delete uses slot zero and records the existing object departure")
	_assert_eq(first_runtime["presentation_requests"].filter(func(item): return item.get("name") == "actSetDoublePageMode").size(), 0, "random fixture has no double-page request")


func _adapter_dispatch() -> void:
	var seed: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://content/generated/hsl/chapter01/battle053_seed.json"))
	var scenario := {"rule_adapter": "winfail", "scenario_rules": {"reinforcement_class_id": "Enemy023"}, "opening": {"speaker_resource_ids": {"SID_PLAYER1": "1", "SID_ENEMY023": "376"}, "actor_bindings": {"SID_PLAYER1/1": {"unit_id": "tina"}}}}
	var battle := {
		"player_unit_id": "tina", "turn": 1, "units": [
			_unit("tina", "Player002", Vector2i(20, 23)),
			_unit("guard023_1", "Enemy023", Vector2i(29, 24)),
			_unit("guard023_2", "Enemy023", Vector2i(27, 23)),
			_unit("gate023_1", "Enemy023", Vector2i(30, 36)),
		],
	}
	_assert_true(BattleScenarioRuleAdapter.script_payload_valid(scenario, seed), "battle053 seed is a valid payload")
	_assert_true(not BattleScenarioRuleAdapter.script_payload_valid(scenario, {"schema": "hsl_battle_seed.v1", "scripts": {}}), "a seed without a winfail script is rejected before initialization")
	_assert_true(not BattleScenarioRuleAdapter.script_payload_valid(scenario, {"schema": "other"}), "foreign payload rejected")
	var dispatched: Dictionary = BattleScenarioRuleAdapter.initialize_script_state(battle.merged({"rule_adapter": "winfail"}), scenario, seed)
	_assert_eq(dispatched.get("objective_phase", ""), "escape", "adapter initialize reaches WinfailScenarioRules")
	_assert_eq(dispatched.get("event_statuses", []), [0, 1, 2], "adapter initialize arms the three events")
	_assert_eq(dispatched.get("next_level_event", []), [1, 1], "adapter initialize arms the campaign hand-off")
	dispatched["turn"] = 5
	dispatched = BattleScenarioRuleAdapter.run_event_hooks(dispatched)
	_assert_eq(BattleScenarioRuleAdapter.reinforcement_deficits(dispatched), {"Enemy023": 1}, "adapter round hook + deficit dispatch")
	var attack_scan: Dictionary = BattleScenarioRuleAdapter.run_event_hooks(dispatched, true)
	_assert_eq(BattleScenarioRuleAdapter.reinforcement_deficits(attack_scan), {"Enemy023": 1}, "an attack-context completion scan re-evaluates without doubling the owed insert")
	_assert_eq(attack_scan.get("event_statuses", []), [1, 2], "an attack-context completion scan leaves the round events alone")
	_assert_eq(BattleScenarioRuleAdapter.victory_state(dispatched), {}, "adapter victory dispatch")
	(dispatched["units"][0] as Dictionary)["coord"] = Vector2i(30, 35)
	_assert_eq(BattleScenarioRuleAdapter.victory_state(dispatched), BattleOutcome.VICTORY_ESCAPE, "adapter sees the gate cell arrival")
	dispatched["battle_outcome"] = BattleOutcome.VICTORY_ESCAPE
	_assert_eq(BattleScenarioRuleAdapter.story_dialogue_messages(dispatched), [{"key": WinfailScenarioRules.TERMINAL_DIALOGUE_KEY, "speaker_id": "1", "message_id": "704", "actor_token": "SID_PLAYER1"}], "adapter dialogue dispatch")
	_assert_eq(BattleScenarioRuleAdapter.result_message_id(dispatched, BattleOutcome.VICTORY_ESCAPE), "695", "adapter result label dispatch")
	_assert_eq(BattleScenarioRuleAdapter.objective_board({"rule_adapter": "development_battle"}), {"win": [], "fail": [], "event": []}, "development battles keep an empty board")


# ---- run_winfail_rules_tests.gd ----
## Winfail scan cadence through the PlayLoop (static-derived,
## docs/evidence_packets/static_reverse/original_round_display.md «Evaluation cadence»):
## every completed action runs its status tail (0x40b910), then 0x407510 scans
## win／fail／event statuses (0x408370 → 0x44ee20) before 0x4074a0 advances the
## queue and bumps the round counter at wrap. So (1) a round-N event of the live
## level 51 fires after round N's first completed action, not at the boundary;
## (2) a Wait re-reads statuses after its poison tick; (3) an item use re-reads
## statuses, and a win armed by the event it fires decides in that same action.
## Scan shape (same packet «Scan shape»): (4) the event walk of 0x44ee20 returns after
## the first status that fires, so level 51's two reinforcement events that one kill
## satisfies together start on two consecutive completed actions; (5) only a chain
## that ran actExecWinFailProcess rescans at once (0x453b7c), so a second holding event
## joins the same action only behind such a chain. Attack context (packet «Attack
## context»): (6) actCheckPlayerAttacked is read by the attack action's completion scan
## (0x450840 case 0x2a reads the attacker global 0x4c1ce8) — not right after the strike —
## and the next action's scan no longer sees that attack (0x4c1ce8 is cleared when an
## action starts).

const StatusEffectRules = preload("res://game/sim/StatusEffectRules.gd")

const SCENARIO_PATH := "res://content/battles/battle_051.json"


func run_event_cadence() -> void:
	_round_event_after_first_completed_action()
	_wait_rereads_after_poison_tail()
	_item_use_rereads_and_decides()
	_one_event_per_scan()
	_exec_winfail_process_rescans()
	_attack_read_by_completion_scan()


func _battle() -> Dictionary:
	var loop := BattlePlayLoop.create([], "", BattleScenario.load_file(SCENARIO_PATH), 7)
	_assert_true(bool(loop.get("scenario_ok", false)), "battle_051 PlayLoop creates (%s)" % str(loop.get("scenario_error", "")))
	return BattlePlayLoop.begin_battle(loop)


func _complete_action(loop: Dictionary) -> Dictionary:
	## One completed action: the player's Wait, or an AI slot ended without a decision
	## (deterministic; no RNG, no strike, so no attack-context scan interferes).
	match str(loop.get("interaction", "")):
		"action_menu":
			return BattlePlayLoop.begin_wait_resolution(loop)
		"ai_resolving":
			return BattlePlayLoop.advance_current_actor(loop)
	_assert_true(false, "no completable action in %s (%s)" % [str(loop.get("interaction", "")), str(loop.get("scenario_error", ""))])
	return loop


func _fired(loop: Dictionary) -> Array:
	return (loop.get("winfail_runtime", {}) as Dictionary).get("fired", [])


func _fired_entry(loop: Dictionary, key: String) -> Dictionary:
	for entry in _fired(loop):
		if str((entry as Dictionary).get("key", "")) == key:
			return entry
	return {}


func _reach_player(loop: Dictionary) -> Dictionary:
	var next := loop
	for _step in range(64):
		if str(next.get("interaction", "")) == "action_menu":
			return next
		next = _complete_action(next)
	_assert_true(false, "the player's action menu is reached")
	return next


func _round_event_after_first_completed_action() -> void:
	## WINFAIL051 event 2 = actCheckRoundNumber 4 (waiting lines), event 3 =
	## actCheckRoundNumber 6 (objective switch arming both win statuses).
	var loop := _battle()
	for spec in [[4, "event_2"], [6, "event_3"]]:
		var round_number: int = spec[0]
		var key: String = spec[1]
		var guard := 0
		while int(loop.get("turn", 1)) < round_number and guard < 256:
			_assert_true(_fired_entry(loop, key).is_empty(), "%s has not fired during round %d" % [key, int(loop.get("turn", 1))])
			loop = _complete_action(loop)
			guard += 1
		_assert_eq(int(loop.get("turn", 1)), round_number, "the queue wrapped into round %d" % round_number)
		_assert_true(_fired_entry(loop, key).is_empty(), "%s does not fire at the round-%d boundary (the boundary scan still reads %d)" % [key, round_number, round_number - 1])
		if key == "event_3":
			_assert_eq(loop.get("win_statuses", []), [], "the round-6 win statuses are not armed before round 6's first action")
		var fired_before := _fired(loop).size()
		loop = _complete_action(loop)
		var entry := _fired_entry(loop, key)
		_assert_true(not entry.is_empty(), "%s fires after round %d's first completed action" % [key, round_number])
		_assert_eq(int(entry.get("turn", 0)), round_number, "%s records round %d" % [key, round_number])
		_assert_eq(_fired(loop).size(), fired_before + 1, "%s is the only status that first action fires" % key)
		if key == "event_3":
			_assert_eq((loop.get("win_statuses", []) as Array).size(), 2, "round 6's first action arms both win statuses")


func _fired_keys(loop: Dictionary, from: int = 0) -> Array:
	var keys: Array = []
	for entry in _fired(loop).slice(from):
		keys.append(str((entry as Dictionary).get("key", "")))
	return keys


func _one_event_per_scan() -> void:
	## WINFAIL051 event 0 (actCheckEnemyNumber SID_ENEMY021 3) and event 1
	## (actCheckEnemyNumber SID_ENEMY026 2) both hold once three of the five 021 and one
	## of the two 026 are down. The original's scan starts event 0 only (first armed slot);
	## its recruit refills 021 to three, so the next completed action starts event 1.
	var loop := _reach_player(_battle())
	var downed := {"Enemy021": 3, "Enemy026": 1}
	for unit in loop["units"]:
		var class_id := str(unit.get("class_id", ""))
		if int(downed.get(class_id, 0)) > 0:
			BattlePlayLoop.set_unit_defeated(loop, str(unit["id"]), true)
			downed[class_id] = int(downed[class_id]) - 1
	_assert_eq(downed, {"Enemy021": 0, "Enemy026": 0}, "three 021 and one 026 are down")
	_assert_eq(loop.get("event_statuses", []), [0, 1, 2, 3], "both reinforcement events are armed")
	var before := _fired(loop).size()
	loop = _complete_action(loop)
	_assert_eq(_fired_keys(loop, before), ["event_0"], "one completed action starts only the first holding event (0x44ee20 returns after it)")
	_assert_eq(WinfailScenarioRules.spawned_reinforcement_count(loop, "Enemy026"), 0, "the 026 recruit is not asked for in the same scan")
	_assert_eq(WinfailScenarioRules.spawned_reinforcement_count(loop, "Enemy021"), 1, "event 0's recruit landed")
	before = _fired(loop).size()
	loop = _complete_action(loop)
	_assert_eq(_fired_keys(loop, before), ["event_1"], "the next completed action starts event 1")
	_assert_eq(WinfailScenarioRules.spawned_reinforcement_count(loop, "Enemy026"), 1, "event 1's recruit landed one action later")


func _exec_winfail_process_rescans() -> void:
	## Four unconditional events on one completion. Event 50 ends in
	## actExecWinFailProcess (case 0x44 → 0x4c1d44), so its chain's end rescans and
	## starts event 51; event 51 does not, so events 52 and 53 wait for the next two
	## completed actions.
	var loop := _custom_rules(_reach_player(_battle()), [
		_section_event_cadence("event", 50, [["actTRUE"], ["actExecWinFailProcess"]]),
		_section_event_cadence("event", 51, [["actTRUE"], ["actMessage", "SID_PLAYER0", 1, 777]]),
		_section_event_cadence("event", 52, [["actTRUE"], ["actMessage", "SID_PLAYER0", 1, 778]]),
		_section_event_cadence("event", 53, [["actTRUE"], ["actMessage", "SID_PLAYER0", 1, 779]]),
	])
	loop = _complete_action(loop)
	_assert_eq(_fired_keys(loop), ["event_50", "event_51"], "actExecWinFailProcess rescans once after its chain; the plain chain stops the scan")
	_assert_eq(loop.get("event_statuses", []), [52, 53], "the other holding events stay armed")
	var before := _fired(loop).size()
	loop = _complete_action(loop)
	_assert_eq(_fired_keys(loop, before), ["event_52"], "the next completed action starts the next armed event only")
	before = _fired(loop).size()
	loop = _complete_action(loop)
	_assert_eq(_fired_keys(loop, before), ["event_53"], "and the one after starts the last")


func _attack_read_by_completion_scan() -> void:
	var loop := _custom_rules(_reach_player(_battle()), [
		_section_event_cadence("event", 60, [["actCheckPlayerAttacked", "SID_PLAYER0", "SID_ENEMY021"], ["actMessage", "SID_PLAYER0", 1, 780]]),
	])
	var armed := BattlePlayLoop.choose_command(loop, "attack")
	var target_id := ""
	for cell in BattlePlayLoop.attack_cells(armed, "leonard"):
		if BattlePlayLoop.unit_id_at_coord(armed, cell) == "":
			for unit in armed["units"]:
				if str(unit.get("class_id", "")) == "Enemy021" and not bool(unit.get("defeated", false)):
					target_id = str(unit["id"])
					BattlePlayLoop.set_unit_coord(armed, target_id, cell)
					unit["max_hp"] = 9999  # survives the strike: no loot settlement to close first
					unit["hp"] = 9999
					break
			break
	_assert_true(target_id != "", "a 021 stands in Leonard's attack range")
	var turn_before := int(armed.get("turn", 1))
	var struck := BattlePlayLoop.attack_target(armed, target_id, zero)
	_assert_true(not (struck.get("last_attack", {}) as Dictionary).is_empty(), "Leonard's strike settled")
	_assert_true(_fired_entry(struck, "event_60").is_empty(), "the strike itself scans nothing (the original has no per-strike scan)")
	var done := BattlePlayLoop.finish_exhausted_action(struck)
	var entry := _fired_entry(done, "event_60")
	_assert_true(not entry.is_empty(), "the attack action's completion scan reads the attacker and fires the attacked event")
	_assert_eq(str(entry.get("context", "")), "attack", "the completion scan of an attack action runs in the attack context")
	_assert_eq(int(entry.get("turn", 0)), turn_before, "it precedes the queue advance")
	_assert_eq(_fired_keys(done).count("event_60"), 1, "an attack action is scanned once")
	var rearmed := BattlePlayLoop.copy(done)
	(rearmed["event_statuses"] as Array).append(60)
	var before := _fired(rearmed).size()
	rearmed = _complete_action(rearmed)
	_assert_eq(_fired_keys(rearmed, before), [], "the next action's completion scan no longer sees Leonard's attack (0x4c1ce8 is cleared when an action starts)")


func _custom_rules(loop: Dictionary, sections: Array) -> Dictionary:
	## Replace the level's script with a fixture program on the same PlayLoop (the
	## opening bindings keep SID_PLAYER0/1 → leonard).
	var seed := {"schema": "hsl_battle_seed.v1", "level": 999, "evidence_tier": "test-fixture", "script_objects": [],
		"scripts": {"story": {"sections": []}, "winfail": {"sections": sections}}}
	var next := BattlePlayLoop.copy(loop)
	var rules := WinfailScenarioRules.rules_from_seed(seed)
	next["winfail_script_rules"] = rules
	for kind in ["win", "fail", "event"]:
		next["%s_statuses" % kind] = []
	for status in rules["statuses"]["event"]:
		(next["event_statuses"] as Array).append(int(status["code"]))
	return next


func _section_event_cadence(name: String, code: int, commands: Array) -> Dictionary:
	var actions: Array = []
	for command in commands:
		var args: Array = []
		for arg in command.slice(1):
			args.append(str(arg))
		actions.append({"primary": str(command[0]), "chain": [{"name": str(command[0]), "args": args}]})
	return {"index": 0, "name": name, "codes": [str(code)], "messages": [], "actions": actions}


func _wait_rereads_after_poison_tail() -> void:
	## Leonard at 60 % HP carries poison worth a fifth of his max HP. His Wait's tail
	## ticks him to 40 %; the completion scan that follows reads the new HP and fires
	## the HP-low event in the same action, before the queue advances.
	var loop := _custom_rules(_reach_player(_battle()), [_section_event_cadence("event", 40, [["actCheckPlayerHPLow", "SID_PLAYER0", 1, 50], ["actMessage", "SID_PLAYER0", 1, 777]])])
	_assert_eq(str(loop.get("selected_unit_id", "")), "leonard", "Leonard holds the action menu")
	var leonard := BattlePlayLoop.unit_ref(loop, "leonard")
	var max_hp := int(leonard["max_hp"])
	leonard["hp"] = max_hp * 6 / 10
	var poisoned := StatusEffectRules.apply(leonard, "poison", 2, max_hp / 5)
	_assert_true(bool(poisoned.get("ok", false)), "Leonard is poisoned (%s)" % str(poisoned.get("reason", "")))
	leonard.merge(poisoned.get("changes", {}), true)
	var turn_before := int(loop.get("turn", 1))
	var after := BattlePlayLoop.choose_command(loop, "wait")
	_assert_true(int(BattlePlayLoop.unit(after, "leonard")["hp"]) * 100 <= 50 * max_hp, "the Wait's poison tick drops Leonard to half HP or below")
	var entry := _fired_entry(after, "event_40")
	_assert_true(not entry.is_empty(), "the HP-low event fires after the poisoned Wait completes")
	_assert_eq(int(entry.get("turn", 0)), turn_before, "the scan precedes the queue advance (fired in round %d)" % turn_before)
	_assert_eq(str(entry.get("context", "")), "round", "a non-attack completion scans in the non-attack context")


func _item_use_rereads_and_decides() -> void:
	## Leonard moves onto a cell and drinks a potion. The item completion scans the
	## arrival event, whose chain arms an unconditional win: the battle is decided in
	## that action, in the same round, without waiting for a strike or a boundary.
	var loop := _reach_player(_battle())
	var leonard := BattlePlayLoop.unit_ref(loop, "leonard")
	var cells: Array = BattlePlayLoop.movement_cells(BattlePlayLoop.choose_command(loop, "move"), "leonard")
	var destination: Vector2i = leonard["coord"]
	for cell in cells:
		if cell != leonard["coord"]:
			destination = cell
			break
	_assert_true(destination != leonard["coord"], "Leonard has a cell to move to")
	var px := destination.x * 32
	var py := destination.y * 32
	loop = _custom_rules(loop, [
		_section_event_cadence("event", 41, [["actCheckPlayerArrivePos", "SID_PLAYER0", 1, px, py, px + 31, py + 31], ["actInsertWinStatus", 0]]),
		_section_event_cadence("win", 0, [["actTRUE"]]),
	])
	leonard = BattlePlayLoop.unit_ref(loop, "leonard")
	leonard["hp"] = maxi(1, int(leonard["max_hp"]) / 2)
	var inventory: Array = leonard["inventory"]
	if not inventory.has(241):
		inventory[inventory.find(0)] = 241
	loop = BattlePlayLoop.move_unit_to(BattlePlayLoop.choose_command(loop, "move"), destination)
	_assert_eq(BattlePlayLoop.unit(loop, "leonard")["coord"], destination, "Leonard moved onto the arrival cell")
	_assert_true(_fired_entry(loop, "event_41").is_empty(), "moving alone completes no action and scans nothing")
	var turn_before := int(loop.get("turn", 1))
	loop = BattlePlayLoop.use_item(loop, "241")
	_assert_true(int(loop.get("item_use_sequence", 0)) > 0, "the potion was used")
	var entry := _fired_entry(loop, "event_41")
	_assert_true(not entry.is_empty(), "the arrival event fires after the item use completes")
	_assert_eq(int(entry.get("turn", 0)), turn_before, "the item completion scan precedes the queue advance")
	_assert_true(BattleOutcome.won(loop), "the win status the event armed decides in the same action")
	_assert_eq(int(loop.get("turn", 1)), turn_before, "the decided battle freezes before the queue advance")


# ---- run_winfail_rules_tests.gd ----
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
## 2. Condition ids the remake cannot resolve (an unresolved token never counts): STORY029
##    renames 梅爾／凱文 to 1000／1001 with actChangePlayerID.
## 3. Missing script actors: a win path gated on a unit neither fielded nor creatable.
##    KNOWN_BLOCKED lists what is still open, with its reason; a battle leaving or entering
##    the list fails the suite. Lane R6-L10 fielded STORY037's guardians (066／067, the
##    pillar-5 chain to Enemy052) and level 80's 怨念體 068.
## 4. Conditions on static enemy objects (drawn, never destroyed): KNOWN_STATIC_CONDITIONS.
## 5. Referenced-but-unbuilt actors: every SID_ENEMYnnn token a battle's WINFAIL statuses or
##    STORY actions name resolves to a unit of the cast (fielded, script template, or an
##    opening-only actor the STORY deletes) except KNOWN_UNBUILT.

const CampaignProgress = preload("res://game/common/CampaignProgress.gd")
const WinfailCompiler = preload("res://game/sim/WinfailCompiler.gd")
const TacticalGridRules = preload("res://game/sim/TacticalGridRules.gd")
const TerrainEditRules = preload("res://game/sim/TerrainEditRules.gd")
const CoreTurnQueue = preload("res://game/sim/CoreTurnQueue.gd")
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
## Battle key -> [loop, scenario, arrival floods] of the first pass, reused by the spot checks.
var boards := {}


func run_winnability_census() -> void:
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
		var loop := BattlePlayLoop.create([], "", scenario, 1)
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
		for token in RulesReadback.condition_tokens(status):
			if WinfailConditions.token_source(cast, str(token)) == "unresolved":
				report["unresolved"].append("%s condition token %s names no unit" % [status["key"], token])
			if statics.has(str(token)) and WinfailConditions.units_for_token(cast, str(token)).is_empty() and not report["static_tokens"].has(str(token)):
				report["static_tokens"].append(str(token))
		for condition in status.get("conditions", []):
			if str(condition["name"]) != "actCheckPlayerHPLow":
				continue
			for unit_id in WinfailConditions.units_for_token(cast, WinfailConditions.arg(condition["args"], 0), WinfailConditions.int_arg(condition["args"], 1)):
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
	var cast: Dictionary = BattlePlayLoop.copy(loop)
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
			if str(action["name"]) == "actSetPlayerUndead" and WinfailConditions.int_arg(action["args"], 2) != 0:
				for unit_id in WinfailConditions.units_for_token(cast, WinfailConditions.arg(action["args"], 0), WinfailConditions.int_arg(action["args"], 1)):
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
				if WinfailConditions.int_arg(args, 0) > ROUND_REACHABLE:
					return "%s %s never comes" % [name, str(args)]
			"actCheckPlayerAttacked":
				if WinfailConditions.units_for_token(cast, WinfailConditions.arg(args, 1)).is_empty():
					return "%s: nobody to attack as %s" % [name, WinfailConditions.arg(args, 1)]
				if WinfailConditions.arg(args, 0) != "-1" and WinfailConditions.units_for_token(cast, WinfailConditions.arg(args, 0)).is_empty():
					return "%s: no attacker %s" % [name, WinfailConditions.arg(args, 0)]
			"actCheckSerialPlayerAttacked":
				if WinfailConditions.units_for_token(cast, WinfailConditions.arg(args, 0), WinfailConditions.int_arg(args, 1)).is_empty():
					return "%s: no %s serial %s" % [name, WinfailConditions.arg(args, 0), WinfailConditions.arg(args, 1)]
			"actCheckPlayerHPLow":
				var reached := false
				for unit_id in WinfailConditions.units_for_token(cast, WinfailConditions.arg(args, 0), WinfailConditions.int_arg(args, 1)):
					var lowest := 1 if undead.has(unit_id) else 0
					if _holds_at(cast, unit_id, lowest, lowest == 0, condition):
						reached = true
				if not reached:
					return "%s %s: no target reaches the threshold" % [name, str(args)]
			"actCheckEnemyNumber":
				var token := WinfailConditions.arg(args, 0)
				if WinfailConditions.token_source(cast, token) == "unresolved":
					return "%s: unresolved %s" % [name, token]
				if int(cast["winfail_runtime"].get("static_enemy_counts", {}).get(token, 0)) >= WinfailConditions.int_arg(args, 1):
					return "%s: static objects %s are never destroyed" % [name, token]
			"actCheckPlayer", "actCheckEnemy":
				var needed := mini(WinfailConditions.int_arg(args, 0), args.size() - 1)
				var countable := 0
				for index in range(1, args.size()):
					var token := WinfailConditions.arg(args, index)
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
		return hp <= int(WinfailConditions.hp_low_threshold(int(unit.get("max_hp", 0)), WinfailConditions.int_arg(condition["args"], 2)))
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
			for index in range(1, 1 + mini(WinfailConditions.int_arg(args, 0), args.size() - 1)):
				var listed := "event_%d" % WinfailConditions.int_arg(args, index)
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
	var board: Dictionary = BattlePlayLoop.copy(cast)
	board["terrain_edits"] = []
	var cell_size := WinfailConditions.cell_size(cast)
	for status in WinfailCompiler.all_statuses(rules):
		for action in status.get("actions", []):
			var args: Array = action["args"]
			var edit: Dictionary = rules.get("story_object_terrain", {}).get(WinfailConditions.arg(args, 0), {})
			if str(action["name"]) == "actInsertStoryObject" and edit.has("clear_flags") and args.size() >= 3:
				TerrainEditRules.record(board, WinfailConditions.arg(args, 0), [Vector2i(floori(float(args[1]) / cell_size), floori(float(args[2]) / cell_size))], "winnability census")
	var tiles := TerrainEditRules.tiles(board)
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
				for unit_id in WinfailConditions.units_for_token(cast, WinfailConditions.arg(args, 0), WinfailConditions.int_arg(args, 1)):
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
					var envelope := TacticalGridRules.movement_reachability_envelope(mover, [], tiles, size, size.x * size.y * 16)
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


## Spot checks on the census: level 59's undead boss and level 29's actChangePlayerID bindings.
func _ablations(campaign: Dictionary) -> void:
	var loop_59: Dictionary = boards["59"][0]
	var scenario_59: Dictionary = boards["59"][1]
	var cast := cast_battle(loop_59)
	var win: Dictionary = WinfailCompiler.status_by_key(loop_59["winfail_script_rules"], "win_0")
	var condition: Dictionary = win["conditions"][0]
	_assert_true(_holds_at(cast, "actor060_1", 1, false, condition), "level 59 win 0 holds on the undead boss at HP 1")
	var report := census(loop_59, scenario_59, boards["59"][2])
	_assert_eq(report["path"], ["win_0"], "level 59 is winnable through win 0")
	var loop_29: Dictionary = boards["29"][0]
	var scenario_29: Dictionary = boards["29"][1]
	_assert_eq(WinfailConditions.units_for_token(loop_29, "1000", 1), ["actor023_1"], "STORY029 actChangePlayerID binds 1000 to 梅爾 (SID_ENEMY023 serial 1)")
	_assert_eq(WinfailConditions.units_for_token(loop_29, "1001", 1), ["actor023_2"], "STORY029 actChangePlayerID binds 1001 to 凱文 (SID_ENEMY023 serial 2)")
	_missing_actor_ablations()


## Lane R6-L10: level 37's win path runs through the guardians and level 80's wall waits for
## the 怨念體.
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
	var loop_80: Dictionary = boards["80"][0]
	var wall := ["1", "SID_ENEMY068"]
	_assert_true(not WinfailConditions.condition_holds(loop_80, "actCheckEnemy", wall, "round"), "level 80's wall event waits while the 怨念體 stands")
	var fallen: Dictionary = BattlePlayLoop.copy(loop_80)
	fallen["units"] = (loop_80["units"] as Array).duplicate(true)
	WinfailConditions.unit(fallen, "actor068_1")["defeated"] = true
	_assert_true(WinfailConditions.condition_holds(fallen, "actCheckEnemy", wall, "round"), "level 80's wall event holds once the 怨念體 falls")
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
	var loop: Dictionary = BattlePlayLoop.resolve_outcome(BattlePlayLoop.BattleScenarioRuleAdapter.run_event_hooks(BattlePlayLoop.copy(first)))
	var caster := ""
	var skill := ""
	for step in range(200):
		var id := str(CoreTurnQueue.current(loop["turn_queue"]).get("id", ""))
		if not bool(BattlePlayLoop.unit_ref(loop, id).get("player_commandable", false)):
			loop = BattlePlayLoop.step_ai_turn(loop, rng)
			continue
		var ready := BattlePlayLoop.select_player_unit(loop, id)
		for option in BattlePlayLoop.magic_options(ready, id):
			if option["quote"]["ok"] and not BattlePlayLoop.SkillTargetRules.is_support(option["fields"], ready["skill_target_data"]):
				caster = id
				skill = str(option["id"])
				break
		if caster != "":
			loop = ready
			break
		loop = BattlePlayLoop.commit_wait(ready, rng)
	_assert_true(caster != "", "level 37 fields a caster with an offensive spell")
	if caster == "":
		return
	var adjacent := _gem_beside(loop, caster, "guard067_5")
	var struck := BattlePlayLoop.attack_target(BattlePlayLoop.choose_command(adjacent, "attack"), "guard067_5", rng)
	_assert_eq(str(struck.get("last_attack_reject", {}).get("reason", "")), "not_enemy", "an ordinary attack cannot select a pmMagicAttack gem")
	var early := _cast_on_gem(loop, caster, skill, "guard067_5", rng)
	var after := BattlePlayLoop.unit_ref(early, "guard067_5")
	_assert_true(int(after["hp"]) == 1 and not bool(after.get("defeated", false)), "the undead gem revives at 1 HP after a lethal spell")
	_assert_eq(int(after.get("player_mode", 0)), 0x30000, "a struck gem goes dark (pmPlayerEnemy)")
	var fired: Array = early["winfail_runtime"]["fired"]
	_assert_eq(fired.map(func(entry): return entry["key"]), ["event_5"], "gem 5 struck first fires event 5 only")
	_assert_eq(int(fired[0].get("chain_stop_index", -1)), 3, "event 5 stops at its actCheckEventNotExist gate while pillars 1–4 are armed")
	_assert_true(not (early["event_statuses"] as Array).has(6) and _alive_of(early, ["052"]).is_empty() and _alive_of(early, ["066", "067"]).size() == 10, "gem 5 struck first leaves the guardians standing and Enemy052 absent")
	# Pillars 1–4 already struck: their events have left the slot table.
	var primed: Dictionary = BattlePlayLoop.copy(loop)
	primed["event_statuses"] = (loop["event_statuses"] as Array).filter(func(code): return not [1, 2, 3, 4].has(int(code)))
	var last := _cast_on_gem(primed, caster, skill, "guard067_5", rng)
	_assert_eq(last["winfail_runtime"]["fired"].map(func(entry): return entry["key"]), ["event_5", "event_6"], "gem 5 struck last fires WINFAIL037 events 5 and 6")
	_assert_true(_alive_of(last, ["066", "067"]).is_empty() and _alive_of(last, ["052"]).size() == 1 and (last["event_statuses"] as Array).has(47), "event 6 removes the ten guardians, fields Enemy052 and arms event 47")
	# Gem 4 struck last (1, 2, 3 and 5 already struck): the pillars reset.
	var wrong: Dictionary = BattlePlayLoop.copy(loop)
	wrong["event_statuses"] = (loop["event_statuses"] as Array).filter(func(code): return not [1, 2, 3, 5].has(int(code)))
	var reset := _cast_on_gem(wrong, caster, skill, "guard067_4", rng)
	_assert_eq(reset["winfail_runtime"]["fired"].map(func(entry): return entry["key"]), ["event_4", "event_7"], "another gem struck last fires its event and the event-7 reset")
	var rearmed := true
	for code in [8, 9, 10, 11, 12]:
		rearmed = rearmed and (reset["event_statuses"] as Array).has(code)
	_assert_true(rearmed and not (reset["event_statuses"] as Array).has(6) and int(BattlePlayLoop.unit_ref(reset, "guard067_4").get("player_mode", 0)) == 0x870000, "event 7 relights the gems (pmMagicAttack) and arms events 8–12")


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
	var north := _arrive(BattlePlayLoop.copy(first), runner, Vector2i(19, 4))
	var north_fired: Array = north["winfail_runtime"]["fired"]
	_assert_eq(north_fired.map(func(entry): return entry["key"]), ["event_0"], "level 80: the northern treasure fires event 0")
	_assert_true(int(north_fired[0].get("chain_stop_index", -1)) == 11 and not (north["win_statuses"] as Array).has(0) and not BattleOutcome.decided(north), "level 80: the first treasure stops at its gate (event 1 armed) — no win while the 怨念體 guards the second")
	var south_only: Dictionary = BattlePlayLoop.copy(first)
	WinfailConditions.unit(south_only, "actor068_1")["defeated"] = true
	south_only = _arrive(south_only, runner, Vector2i(19, 13))
	_assert_true(south_only["winfail_runtime"]["fired"].map(func(entry): return entry["key"]).has("event_1") and not (south_only["win_statuses"] as Array).has(0) and not BattleOutcome.decided(south_only), "level 80: the southern treasure alone does not arm win 0 either")
	var both: Dictionary = BattlePlayLoop.copy(north)
	WinfailConditions.unit(both, "actor068_1")["defeated"] = true
	both = _arrive(both, runner, Vector2i(19, 13))
	var both_fired: Array = both["winfail_runtime"]["fired"].map(func(entry): return entry["key"])
	_assert_true(both_fired.has("event_1") and both_fired.has("event_3"), "level 80: the second treasure fires event 1, the fallen 怨念體 event 3 (%s)" % str(both_fired))
	_assert_eq(BattleOutcome.of(both), BattleOutcome.VICTORY_SCRIPT, "level 80: both treasures arm win 0 and the battle is won")


func _arrive(loop: Dictionary, unit_id: String, cell: Vector2i) -> Dictionary:
	var unit := WinfailConditions.unit(loop, unit_id)
	unit["coord"] = cell
	unit["grid_coord"] = cell
	return BattlePlayLoop.resolve_outcome(BattlePlayLoop.BattleScenarioRuleAdapter.run_event_hooks(loop))


## `loop` with gem `gem_id` moved beside the caster (a copy).
func _gem_beside(loop: Dictionary, caster: String, gem_id: String) -> Dictionary:
	var next: Dictionary = BattlePlayLoop.copy(loop)
	var gem := BattlePlayLoop.unit_ref(next, gem_id)
	for delta in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		if BattlePlayLoop.unit_id_at_coord(next, BattlePlayLoop.unit_ref(next, caster)["coord"] + delta) == "":
			gem["coord"] = BattlePlayLoop.unit_ref(next, caster)["coord"] + delta
			break
	return next


func _cast_on_gem(loop: Dictionary, caster: String, skill: String, gem_id: String, rng: RandomNumberGenerator) -> Dictionary:
	var ready := _gem_beside(loop, caster, gem_id)
	var cast := BattlePlayLoop.attack_target(BattlePlayLoop.choose_magic(BattlePlayLoop.choose_command(ready, "magic"), skill), gem_id, rng, BattlePlayLoop.unit_ref(ready, gem_id)["coord"])
	return BattlePlayLoop.finish_exhausted_action(cast)


func _alive_of(loop: Dictionary, actor_ids: Array) -> Array:
	return loop["units"].filter(func(unit): return str(unit["actor_id"]) in actor_ids and WinfailConditions.unit_alive(loop, str(unit["id"])))
