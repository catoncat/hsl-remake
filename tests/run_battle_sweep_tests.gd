extends SceneTree

## Formal-battle sweep: every campaign.json entry that is a battle scenario (no story /
## world_map / game_clear kind) boots from the product opening, plays its opening to
## first control, is force-won through the shared traversal fixture (every living enemy
## defeated, the outcome resolved, script phases replayed) and hands the campaign on
## like the result page's button. A scale guard for levels assembled by
## tools/hsltools/levels/battle.py; per-level rule semantics stay in their own suites and
## nothing here is evidence about original balance or pacing.

const RuntimeScene = preload("res://game/battle/scene/BattleSceneRuntime.tscn")
const CampaignProgress = preload("res://game/common/CampaignProgress.gd")
const BattlePlayLoop = preload("res://game/sim/loop/BattlePlayLoop.gd")
const BattleForceWin = preload("res://tests/support/BattleForceWin.gd")
const TestSuite = preload("res://tests/support/TestSuite.gd")
const BattleOutcome = preload("res://game/sim/BattleOutcome.gd")

var failures: Array[String] = []

## Level 51's victory is the escape after the round-6 objective switch, covered by the
## first-scene runtime and main-path smoke suites; the traversal fixture only plays its
## opening here.
const FORCE_WIN_SKIP := ["51"]


func _initialize() -> void:
	call_deferred("_run")


func _assert_true(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _run() -> void:
	CampaignProgress.pending = {}
	CampaignProgress.resume_prompt_in_headless = false
	var campaign := CampaignProgress.load_campaign()
	var swept: Array[String] = []
	var expected: Array = campaign.get("battles", {}).keys().filter(func(key): return not campaign["battles"][key].has("kind"))
	# Developer filter: HSL_SWEEP_LEVELS="26,34" sweeps only those registered battles
	# (the coverage assertion is skipped); unset means the full registered sweep.
	var only: Array = Array(OS.get_environment("HSL_SWEEP_LEVELS").split(",", false))
	for key in campaign.get("battles", {}):
		var entry: Dictionary = campaign["battles"][key]
		if entry.has("kind"):
			continue
		if not only.is_empty() and not only.has(str(key)):
			continue
		await _sweep_battle(str(key), str(entry.get("scenario", "")), campaign)
		swept.append(str(key))
	if only.is_empty():
		_assert_true(swept == expected, "the sweep covered exactly every registered formal battle: %s vs %s" % [swept, expected])
	await _run_level_6_opening()
	await _run_level_10_opening()
	# Let the audio thread release the last scene's music stream before quitting
	# (otherwise Godot reports the Ogg stream as still in use at exit). Wall-clock: the
	# gate runs this suite under --fixed-fps, where a SceneTreeTimer would elapse in a
	# millisecond.
	await TestSuite.settle_wall_clock(self, 0.3)
	await process_frame
	if failures.is_empty():
		print("BATTLE_SWEEP_TESTS_PASS battles=%d" % swept.size())
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		print("BATTLE_SWEEP_TESTS_FAIL count=%d" % failures.size())
		quit(1)


func _boot(path: String) -> Node:
	CampaignProgress.pending = {}
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


## Plays the opening to first control (tests/support/BattleForceWin.gd).
func _play_opening(scene: Node, label: String) -> void:
	await BattleForceWin.play_opening(self, scene, label, _assert_true)


## The shared force-win fixture (tests/support/BattleForceWin.gd): interprets the level's
## `sweep_fixture` in content/battles/levels/NNN.json (source-timed statuses, rounds, arrival
## or choice branches), otherwise defeats every living enemy, resolves, replays script
## phases, until the result page shows a victory. The explorer walks the campaign through
## the same fixture.
func _force_win(scene: Node, label: String) -> bool:
	return await BattleForceWin.force_win(self, scene, label, _assert_true)


func _sweep_battle(key: String, path: String, campaign: Dictionary) -> void:
	var label := "level %s (%s)" % [key, path.get_file()]
	var scene = await _boot(path)
	_assert_true(bool(scene.play_loop.get("scenario_ok", false)), "%s: the scenario loads (%s)" % [label, str(scene.play_loop.get("scenario_error", ""))])
	if not bool(scene.play_loop.get("scenario_ok", false)):
		await _free(scene)
		return
	if not BattleForceWin.skips_opening(scene):
		# An event-only formal battle (73) opens its event_0/event_1 choice directly from
		# the battle entry, with no first-control phase.
		await _play_opening(scene, label)
		_assert_true(scene.play_loop["units"].any(func(actor): return actor["player_commandable"]), "%s: a controlled unit exists at first control" % label)
		# Every field actor's draw depth follows its unit's flying bit (original_draw_order.md).
		var depth_mismatch: Array = scene.play_loop["units"].filter(func(unit): return scene.actor_node_for_unit(str(unit["id"])) != null and scene.actor_node_for_unit(str(unit["id"])).flying_depth != bool(unit.get("traversal", {}).get("flying", false))).map(func(unit): return unit["id"])
		_assert_true(depth_mismatch.is_empty(), "%s: actor draw depth follows the unit's flying bit: %s" % [label, str(depth_mismatch)])
	if key in FORCE_WIN_SKIP:
		pass
	elif BattleForceWin.arms_own_handoff(scene):
		# A script that ends by event completion (no win section: 73／78): the fixture asserts
		# the hand-off itself, so the result-page next-step assertion does not apply.
		await _force_win(scene, label)
	elif await _force_win(scene, label):
		var destination := CampaignProgress.next_destination(campaign, scene.play_loop, path)
		scene.campaign_progress.start_next_battle()
		await process_frame
		if str(destination.get("kind", "")) == "game_clear":
			# A win section that names the game-clear entry (winfail059／079 and the authored 200:
			# actSetNextPlayLevelEvent N,998) ends the campaign from the result page: no hand-off
			# is armed, the GameClear sequence takes over (CampaignProgress._enter_game_clear).
			_assert_true(str(scene.campaign_progress.last_handoff.get("kind", "")) == "game_clear" and not CampaignProgress.has_pending(), "%s: the result page's next step enters the GameClear sequence" % label)
		else:
			_assert_true(CampaignProgress.has_pending(), "%s: the result page's next step arms a campaign hand-off" % label)
	CampaignProgress.pending = {}
	await _free(scene)


## Level 6 席達鎮 (`python3 tools/hsl.py generate level_battle:6`): STORY006 installs the four
## registered slots and inserts three soldiers and a captain who waits three rounds;
## the twelve villagers are friendly, uncontrollable NPCs; the seven EVEF soldiers are
## enemies; both EVEF chests carry their original contents.
func _run_level_6_opening() -> void:
	var scene = await _boot("res://content/battles/battle_006.json")
	var loop: Dictionary = scene.play_loop
	_assert_true(bool(loop.get("scenario_ok", false)), "level 6: scenario loads (%s)" % str(loop.get("scenario_error", "")))
	if not bool(loop.get("scenario_ok", false)):
		await _free(scene)
		return
	var roles := {}
	for actor in loop["units"]:
		roles[actor["battle_actor_role"]] = int(roles.get(actor["battle_actor_role"], 0)) + 1
	_assert_true(roles == {"player_controlled": 4, "friendly_ai": 12, "enemy_ai": 11}, "level 6: roster is 4 players, 12 villagers, 11 soldiers: %s" % roles)
	_assert_true(BattlePlayLoop.unit(loop, "guard024_1").get("ai_wait_remaining", -1) == 3, "level 6: the inserted captain waits three rounds (actSetPrevInsertObjectWaitRound)")
	_assert_true(BattlePlayLoop.unit(loop, "hanks")["player_commandable"] and BattlePlayLoop.unit(loop, "hanks")["actor_id"] == "004", "level 6: 漢克斯 is the fourth controlled slot")
	_assert_true(loop.get("treasure_source", {}).get("chests", []).size() == 2, "level 6: both EVEF chests are loaded from the per-level treasure source")
	await _play_opening(scene, "level 6")
	_assert_true(str(scene.play_loop.get("interaction", "")) != "", "level 6: the loop is interactive after the opening")
	var leonard := BattlePlayLoop.unit(scene.play_loop, "leonard")
	_assert_true(leonard.get("coord") == Vector2i(23, 8), "level 6: 雷歐納德 stands on the STORY006 endpoint (23,8) at first control: %s" % str(leonard.get("coord")))
	await _free(scene)


## Level 10 帕尼西亞城 廢墟: the EVEF installs 雷歐納德／緹娜, four ruin enemies
## are active at first control, and the formal battle keeps its single EVEF chest.
func _run_level_10_opening() -> void:
	var scene = await _boot("res://content/battles/battle_010.json")
	var loop: Dictionary = scene.play_loop
	_assert_true(bool(loop.get("scenario_ok", false)), "level 10: scenario loads (%s)" % str(loop.get("scenario_error", "")))
	if not bool(loop.get("scenario_ok", false)):
		await _free(scene)
		return
	var roles := {}
	for actor in loop["units"]:
		roles[actor["battle_actor_role"]] = int(roles.get(actor["battle_actor_role"], 0)) + 1
	_assert_true(roles == {"player_controlled": 2, "enemy_ai": 4}, "level 10: roster is 2 players and 4 ruin enemies: %s" % roles)
	_assert_true(loop.get("treasure_source", {}).get("chests", []).size() == 1, "level 10: the EVEF chest is loaded from the per-level treasure source")
	await _play_opening(scene, "level 10")
	var leonard_10 := BattlePlayLoop.unit(scene.play_loop, "leonard")
	_assert_true(leonard_10.get("coord") == Vector2i(13, 6), "level 10: 雷歐納德 stands on the STORY010 endpoint (13,6) at first control: %s" % str(leonard_10.get("coord")))
	await _run_level_10_round5_event(scene)
	await _free(scene)


## WINFAIL010 event_3 (round 5): the party's dialogue and the 琥／漢克斯／雪拉 story
## walk-in play as a script cutscene while the battle is undecided. Its end must resume
## the battle — the win-section default next_level_event (10, big map) is not an
## event-only hand-off (runtime-measured regression from the wave-7 explorer lane).
func _run_level_10_round5_event(scene: Node) -> void:
	_assert_true(not CampaignProgress.has_pending(), "level 10: no campaign hand-off is pending at first control")
	scene.set_process(false)
	var loop: Dictionary = scene.play_loop
	var guard := 0
	while int(loop.get("turn", 0)) < 5 and guard < 512:
		if str(loop.get("interaction", "")) == "action_menu":
			loop = BattlePlayLoop.choose_command(loop, "wait")
		elif str(loop.get("interaction", "")) == "ai_resolving":
			loop = BattlePlayLoop.advance_current_actor(loop)
		else:
			break
		guard += 1
	# Round-N script events fire after round N's first completed action (the original scans
	# before the queue advance bumps the round, original_round_display.md): complete it too.
	if str(loop.get("interaction", "")) == "action_menu":
		loop = BattlePlayLoop.choose_command(loop, "wait")
	elif str(loop.get("interaction", "")) == "ai_resolving":
		loop = BattlePlayLoop.advance_current_actor(loop)
	_assert_true(int(loop.get("turn", 0)) >= 5, "level 10: waiting reaches round 5 (turn %d, interaction %s)" % [int(loop.get("turn", 0)), str(loop.get("interaction", ""))])
	var fired_keys: Array = loop.get("winfail_runtime", {}).get("fired", []).map(func(entry): return str(entry.get("key", "")))
	_assert_true(fired_keys.has("event_3"), "level 10: event_3 fires after round 5's first completed action: %s" % str(fired_keys))
	_assert_true(str(loop.get("next_level_event_status", "?")) == "", "level 10: the dialogue event names no next-level issuing status")
	scene.apply_loop(loop, "test")
	scene.set_process(true)
	var finished := false
	for _frame in range(6000):
		if CampaignProgress.has_pending():
			break
		var coordinator = scene.opening_coordinator
		if coordinator != null and coordinator.active and str(coordinator.summary().get("current_event_kind", "")) == "dialogue_message_id":
			coordinator.handle_input(BattleForceWin.click())
		if coordinator != null and not coordinator.active and coordinator.cutscene_records.any(func(record): return str(record.get("status_key", "")) == "event_3" and bool(record.get("finished", false))):
			finished = true
			break
		await process_frame
	_assert_true(finished, "level 10: the round-5 event cutscene plays to its end (pending=%s)" % str(CampaignProgress.has_pending()))
	_assert_true(not CampaignProgress.has_pending(), "level 10: a dialogue-only event cutscene does not hand the battle off (pending=%s)" % str(CampaignProgress.pending.get("scenario_path", "")))
	_assert_true(not BattleOutcome.decided(scene.play_loop), "level 10: the battle stays undecided after the event cutscene (outcome %s)" % BattleOutcome.of(scene.play_loop))
	_assert_true(str(scene.play_loop.get("interaction", "")) in ["idle", "action_menu", "ai_resolving", "attack_select", "special_select"], "level 10: the battle continues after the cutscene (interaction %s)" % str(scene.play_loop.get("interaction", "")))
