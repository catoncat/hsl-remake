extends SceneTree
## The level-up window offer (BattleSceneMenus.offer_pending_growth／open_growth,
## BattleSceneRuntime.growth_offered_levels, BattleLoopRewards.allocate_growth): the window
## opens for any player member whose current level has not been offered — after the
## EXP／LEVEL UP floats, before the next hand-off (0x442720 phase 8) — regardless of who was
## offered before, whether the member is the current actor, or whose turn it is. Level 3
## (雷歐納德／緹娜／琥, 琥 acts first) is the three-member formation.
const TestSuite = preload("res://tests/support/TestSuite.gd")
const Loop = preload("res://game/battle/scene/BattlePlayLoop.gd")
const LoopCombat = preload("res://game/battle/scene/BattleLoopCombat.gd")
const Checkpoint = preload("res://game/battle/runtime/BattleCheckpoint.gd")
const CampaignProgress = preload("res://game/battle/runtime/CampaignProgress.gd")
const BattleOutcome = preload("res://game/sim/BattleOutcome.gd")
const Interaction = preload("res://game/sim/Interaction.gd")
const ForceWin = preload("res://tests/support/BattleForceWin.gd")
const GlobalRandom = preload("res://game/sim/GlobalRandomStream.gd")
const SCENARIO := "res://content/battles/battle_003.json"
var checks := 0
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("run")


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		push_error(message)


func run() -> void:
	# Reproducible formation and rolls (the headless loop-seed seam the autoplay sweep uses).
	OS.set_environment("HSL_RNG_SEED", "1")
	CampaignProgress.reset_campaign()
	CampaignProgress.pending = {}
	await _test_second_member_at_lower_level()
	await _test_status_reaches_any_member()
	await _test_enemy_turn_counter_level_up()
	await _test_enemy_turn_counter_level_up(true)
	for skip in [false, true]:
		await _test_terminal_victory_offers_before_story(skip)
	await _test_terminal_defeat_offers_nothing()
	_test_checkpoint_offers()
	await TestSuite.settle_wall_clock(self, 0.2)
	if failures.is_empty():
		print("GROWTH_OFFER_TESTS_PASS checks=%d" % checks)
		quit(0)
	else:
		print("GROWTH_OFFER_TESTS_FAIL count=%d" % failures.size())
		quit(1)


func _start() -> Node:
	# Every case boots from the seeded global stream, not from where the previous case's
	# opening and enemy turns left the process stream (the formation must be the same).
	GlobalRandom.reset_session()
	var scene = load("res://game/battle/scene/BattleSceneRuntime.tscn").instantiate()
	scene.scenario_path = SCENARIO
	scene.startup_mode = "dev_first_control"
	root.add_child(scene)
	await process_frame
	await process_frame
	scene.start_dev_first_control_harness()
	await process_frame
	return scene


func _close(scene: Node) -> void:
	scene.queue_free()
	await process_frame


## Levels the member up once in place (as a settled EXP award would) and mirrors the loop.
func _level_up(scene: Node, id: String) -> void:
	var unit: Dictionary = Loop._unit(scene.play_loop, id)
	unit["exp"] = Loop.ProgressionRules.exp_to_next(int(unit["level"])) - 1
	unit.merge(Loop.ProgressionRules.resolve_experience(unit, 1, scene.play_loop["equipment_items"]), true)
	scene.apply_loop(scene.play_loop, "test")


func _state(scene: Node) -> String:
	var view = scene.get_node("BattlePresentation")
	return "inter=%s sel=%s busy=%s dlg=%s loot=%s motion=%s modal=%s script=%s" % [scene.interaction_state, scene.selected_unit_id, view.combat_busy(scene.play_loop), view.dialogue_active(), Loop.loot_waiting(scene.play_loop), scene.has_actor_motion(), scene.modal_open(), scene.ScriptPresentation.pending(scene)]


func _offered_to(scene: Node) -> String:
	return str(scene.growth_panel.source_unit.get("id", "")) if scene.growth_panel.visible else ""


func _spend_all(scene: Node) -> void:
	var points := int(scene.growth_panel.source_unit["pending_stat_points"])
	for i in range(points):
		scene.growth_panel.choices["con"]["plus"].pressed.emit()
	scene.growth_panel.confirm_button.pressed.emit()


## The recorded bug: 雷歐納德 8→9 was offered, then 琥 7→8 never was (one battle-wide level).
func _test_second_member_at_lower_level() -> void:
	var scene = await _start()
	scene.set_process(false)
	check(scene.selected_unit_id == "hu" and scene.interaction_state == Interaction.ACTION_MENU, "level 3 opens on 琥's action menu")
	_level_up(scene, "hu")
	_level_up(scene, "hu") # 琥 now stands two levels above 緹娜's next level
	scene._process(0.0)
	check(_offered_to(scene) == "hu", "the acting member's level-up opens the window")
	scene.growth_panel.hide() # harness skip seam: points stay, the same level is not offered again
	scene._process(0.0)
	check(not scene.growth_panel.visible, "a skipped level is not offered every frame")
	var hu_level := int(Loop.unit(scene.play_loop, "hu")["level"])
	_level_up(scene, "tina")
	check(int(Loop.unit(scene.play_loop, "tina")["level"]) < hu_level, "緹娜 levels up to a level below the one already offered to 琥")
	scene._process(0.0)
	check(_offered_to(scene) == "tina", "another member's lower level-up still opens its own window (per-member offer)")
	_spend_all(scene)
	check(not scene.growth_panel.visible and int(Loop.unit(scene.play_loop, "tina")["pending_stat_points"]) == 0, "a non-current member's allocation commits through allocate_growth")
	check(scene.selected_unit_id == "hu" and scene.interaction_state == Interaction.ACTION_MENU, "allocating for 緹娜 leaves 琥's turn untouched")
	scene._process(0.0)
	check(not scene.growth_panel.visible, "琥's skipped level is not reoffered")
	await _close(scene)


## Status 成長點 reopens points left unallocated (old save／harness skip) for any member, not only the current actor.
func _test_status_reaches_any_member() -> void:
	var scene = await _start()
	scene.set_process(false)
	_level_up(scene, "leonard")
	scene._process(0.0)
	check(_offered_to(scene) == "leonard", "雷歐納德's level-up is offered while 琥 acts " + _state(scene))
	scene.growth_panel.hide()
	scene.status_panel.show_unit(Loop.unit(scene.play_loop, "leonard"))
	check(scene.status_panel.growth_button.visible, "雷歐納德's status page shows his unspent points")
	scene.status_panel.growth_button.pressed.emit()
	check(_offered_to(scene) == "leonard" and not scene.status_panel.visible, "成長點 reopens the window for the inspected non-current member")
	_spend_all(scene)
	check(int(Loop.unit(scene.play_loop, "leonard")["pending_stat_points"]) == 0, "the reopened window commits 雷歐納德's points")
	await _close(scene)


## Enemy turn: a foe strikes 緹娜, her counter kills it and levels her; the window opens
## after the aftermath floats and holds the next AI step until it closes. `final_blow`: the
## foe is the last enemy, so the foe's completed-action scan wins the battle inside the enemy
## step — the window still opens first and the victory cutscene／result follow it.
func _test_enemy_turn_counter_level_up(final_blow: bool = false) -> void:
	var scene = await _start()
	scene.set_process(false)
	var loop: Dictionary = scene.play_loop
	if final_blow:
		for unit in loop["units"]:
			if unit["battle_actor_role"] == Loop.ROLE_ENEMY and unit["id"] != "actor028_2" and Loop.Presence.living(unit):
				Loop._set_unit_defeated(loop, unit["id"], true)
	var tina: Dictionary = Loop._unit(loop, "tina")
	var foe: Dictionary = Loop._unit(loop, "actor028_2")
	for step in [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.UP, Vector2i.DOWN]:
		if foe["coord"] == tina["coord"] + step: break
		var at: Vector2i = tina["coord"] + step
		if Loop.unit_id_at_coord(loop, at) == "" and Loop.TraversalRules.placement_error(foe.merged({"coord": at}, true), loop["units"], loop["tiles"], loop["map_size"]) == "":
			foe["coord"] = at
			break
	check(Loop.Footprint.overlaps(foe, Loop.attack_cells(loop, "tina")), "028_2 stands in 緹娜's counter reach")
	tina["exp"] = Loop.ProgressionRules.exp_to_next(int(tina["level"])) - 1
	tina["hit_bonus_accum"] = 1000
	foe["hp"] = 1
	loop["interaction"] = Interaction.AI_RESOLVING
	loop["selected_unit_id"] = ""
	var level_before := int(tina["level"])
	# The counter gate (CoreCombatRules.attack_back_triggered) rolls; take the first seed
	# whose exchange draws a lethal counter.
	var strike := {}
	var fought := {}
	for seed in range(1, 200):
		fought = loop.duplicate(true)
		var rng := RandomNumberGenerator.new()
		rng.seed = seed
		strike = LoopCombat._resolve_exchange(fought, "actor028_2", "tina", rng)
		if not strike.get("counter", {}).is_empty() and int(Loop.unit(fought, "actor028_2")["hp"]) == 0: break
	loop = fought
	if final_blow:
		# The foe's action completes in its own death sequence (0x407510 → win scan).
		loop = Loop._resolve_outcome(Loop.BattleScenarioRuleAdapter.run_event_hooks(loop, true))
		check(BattleOutcome.won(loop), "the counter on the last foe wins inside the enemy step")
	check(not strike.is_empty() and not strike.get("counter", {}).is_empty(), "the foe's strike draws 緹娜's counter")
	check(int(Loop.unit(loop, "tina")["level"]) > level_before and int(Loop.unit(loop, "actor028_2")["hp"]) == 0, "the counter kills the foe and levels 緹娜")
	scene.apply_loop(loop, "test")
	scene.resume_turn_presentation()
	check(scene.ai_playback_active or final_blow, "the enemy turn is playing back")
	var saw_float := false
	var saw_level_up := false
	var opened_after_float := false
	var queue_while_open: Variant = null
	for frame in range(1800):
		var view = scene.get_node("BattlePresentation")
		var aftermath = view.aftermath
		if aftermath.stage == "experience": saw_float = true
		if aftermath.stage == "level_up" and saw_float: saw_level_up = true
		if view.dialogue_active(): view.advance_dialogue()
		if Loop.loot_waiting(scene.play_loop):
			# The get-item window (0x442720 phase 4) precedes the level-up window; 稍後.
			var settlement: Dictionary = scene.play_loop["settlement"]
			scene.apply_loop(Loop.finish_rewards(scene.play_loop, int(settlement["sequence"]), int(settlement["revision"]), false, true), "test")
		scene._process(1.0 / 60.0)
		if scene.growth_panel.visible:
			opened_after_float = saw_float and not aftermath.busy()
			queue_while_open = scene.play_loop["turn_queue"].duplicate(true)
			break
		await process_frame
	check(_offered_to(scene) == "tina", "the counter's level-up opens 緹娜's window during the enemy turn")
	check(opened_after_float, "the window follows the EXP／LEVEL UP float (0x442720 phase 8 after phase 6)")
	check(saw_level_up, "the counter's level-up shows its own LEVEL UP float after the EXP float (0x442720 phase 6)")
	for i in range(30):
		scene._process(1.0 / 60.0)
	check(scene.growth_panel.visible and scene.play_loop["turn_queue"] == queue_while_open, "no AI step runs while the window is open")
	if final_blow:
		var view = scene.get_node("BattlePresentation")
		check(not view.battle_finished and not scene.opening_coordinator.active, "the enemy-turn final blow holds the victory cutscene and result behind the window")
	_spend_all(scene)
	check(not scene.growth_panel.visible and int(Loop.unit(scene.play_loop, "tina")["pending_stat_points"]) == 0, "緹娜's points commit during the enemy turn")
	if final_blow:
		var view = scene.get_node("BattlePresentation")
		var coordinator = scene.opening_coordinator
		coordinator.walk_pixels_per_second = 6400.0
		coordinator.delay_token_seconds = 0.001
		coordinator.default_step_seconds = 0.005
		scene.set_process(true)
		for _frame in range(1200):
			if view.battle_finished: break
			if coordinator.active and str(coordinator.summary().get("current_event_kind", "")) in ForceWin.CLICK_THROUGH_KINDS: coordinator.handle_input(ForceWin.click())
			elif view.dialogue_active(): view.advance_dialogue()
			await process_frame
		check(view.battle_finished and BattleOutcome.won(scene.play_loop) and not scene.ai_playback_active, "the victory result follows the enemy-turn window (%s)" % _state(scene))
	await _close(scene)


## The final blow of a won battle (user decision 2026-09-24, as the original: 0x442720 phase 8
## runs in the attacker's completion, before the action ends and the win scan 0x44ee20 runs):
## level 3's clear fires win_0, whose closing cutscene and the result page wait for the level-up
## window of a member other than the actor. Allocating commits on the won loop; the harness skip
## seam (hide) lets the victory script and the result follow, the points stay for the carry and
## the next battle's first quiet moment offers them.
func _test_terminal_victory_offers_before_story(skip: bool) -> void:
	var label := " (skip seam)" if skip else ""
	var scene = await _start()
	scene.set_process(false)
	_level_up(scene, "tina")
	var loop: Dictionary = scene.play_loop.duplicate(true)
	for unit in loop["units"]:
		if unit["battle_actor_role"] == Loop.ROLE_ENEMY and Loop.Presence.living(unit):
			Loop._set_unit_defeated(loop, unit["id"], true)
	loop = Loop._resolve_outcome(Loop.BattleScenarioRuleAdapter.run_event_hooks(loop))
	check(BattleOutcome.won(loop) and scene.ScriptPresentation.timeline(scene, "win_0").get("playable_event_count", 0) > 0, "level 3's clear wins through win_0's closing cutscene" + label)
	scene.apply_loop(loop, "test")
	scene.mirror_interaction()
	var coordinator = scene.opening_coordinator
	coordinator.walk_pixels_per_second = 6400.0
	coordinator.delay_token_seconds = 0.001
	coordinator.default_step_seconds = 0.005
	var view = scene.get_node("BattlePresentation")
	scene.set_process(true)
	for _frame in range(120):
		if scene.growth_panel.visible or coordinator.active or view.battle_finished: break
		await process_frame
	check(_offered_to(scene) == "tina", "the final blow's window opens for 緹娜 (%s)%s" % [_state(scene), label])
	check(not coordinator.active and not view.dialogue_active() and not view.battle_finished, "the victory cutscene and the result page wait for the window" + label)
	for _frame in range(10): await process_frame
	check(scene.growth_panel.visible and not coordinator.active and not view.battle_finished, "the window holds the victory flow while open" + label)
	if skip:
		scene.growth_panel.hide() # the harness skip seam; a player cannot close before OK
	else:
		_spend_all(scene)
	var tina: Dictionary = Loop.unit(scene.play_loop, "tina")
	check(not scene.growth_panel.visible and int(tina["pending_stat_points"]) == (5 if skip else 0), "the window closes; the points %s%s" % ["stay" if skip else "commit on the won loop", label])
	var cutscene_played := false
	for _frame in range(1200):
		if view.battle_finished: break
		if coordinator.active:
			cutscene_played = true
			if str(coordinator.summary().get("current_event_kind", "")) in ForceWin.CLICK_THROUGH_KINDS: coordinator.handle_input(ForceWin.click())
		elif view.dialogue_active():
			view.advance_dialogue()
		await process_frame
	check(cutscene_played and view.battle_finished and BattleOutcome.won(scene.play_loop), "the victory cutscene, then the result page, follow the window (%s)%s" % [_state(scene), label])
	check(not scene.growth_panel.visible, "the window does not reopen over the result" + label)
	var carried := int(Loop.CampaignCarryRules.capture(scene.play_loop)["units"]["tina"]["pending_stat_points"])
	check(carried == (5 if skip else 0), "the carry keeps exactly the unspent points" + label)
	await _close(scene)
	if not skip: return
	var next = await _start()
	next.set_process(false)
	# The carried member (CampaignCarryRules keeps pending_stat_points) is not the first actor.
	Loop._unit(next.play_loop, "tina")["pending_stat_points"] = carried
	next.apply_loop(next.play_loop, "test")
	next._process(0.0)
	check(next.selected_unit_id == "hu" and _offered_to(next) == "tina", "carried points open the member's window at the next battle's first control")
	await _close(next)


## A lost battle offers no window (provisional, the conservative reading: a defeat restarts the
## battle, so points won on its last exchange cannot be kept) and the loop rejects allocation.
func _test_terminal_defeat_offers_nothing() -> void:
	var scene = await _start()
	scene.set_process(false)
	_level_up(scene, "hu")
	var loop: Dictionary = scene.play_loop.duplicate(true)
	Loop._set_unit_defeated(loop, "leonard", true)
	loop = Loop._resolve_outcome(loop)
	check(BattleOutcome.lost(loop), "雷歐納德's fall loses level 3")
	scene.apply_loop(loop, "test")
	scene.mirror_interaction()
	var view = scene.get_node("BattlePresentation")
	scene.set_process(true)
	for _frame in range(120):
		if scene.growth_panel.visible or view.battle_finished: break
		if view.dialogue_active(): view.advance_dialogue()
		await process_frame
	check(not scene.growth_panel.visible and view.battle_finished and not scene.menus.terminal_growth_pending(), "a defeat shows its result without a level-up window (%s)" % _state(scene))
	check(Loop.allocate_growth(scene.play_loop, "hu", {"con": 1}) == scene.play_loop, "a lost loop rejects allocation")
	await _close(scene)


func _test_checkpoint_offers() -> void:
	var loop: Dictionary = Loop.create([], "", Loop.BattleScenario.load_file(SCENARIO))
	var legacy := Checkpoint.growth_offered_levels({"growth_notified_level": 9}, loop)
	check(legacy.size() == loop["units"].size() and int(legacy["hu"]) == int(Loop.unit(loop, "hu")["level"]), "a pre-per-member save restores every member as offered at its current level")
	var saved := Checkpoint.growth_offered_levels({"growth_offered_levels": {"hu": 5}}, loop)
	check(saved == {"hu": 5}, "a per-member save restores its own offers")
