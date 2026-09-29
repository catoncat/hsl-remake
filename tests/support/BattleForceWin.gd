extends RefCounted

## Shared force-win fixture for registered formal battles, used by both
## tests/run_battle_sweep_tests.gd (asserts the result page / hand-off per level) and
## tests/run_story_mode_explorer_tests.gd (only needs the hand-off to continue the walk).
## The per-level knowledge lives in content/battles/levels/NNN.json `sweep_fixture`
## (docs/architecture/LEVEL_PROFILES.md): this file only interprets the five modes
## (`clear`, `status`, `rounds`, `play_to_round`, `choice_branch`) and keeps no branch on a
## scenario path. Every entry point takes the calling SceneTree (for frame awaits), the
## booted BattleSceneRuntime scene, a label for messages and an assert callback
## `Callable(condition: bool, message: String)` — the sweep passes its failure collector,
## the explorer a logger. Nothing here is evidence about original balance or pacing: the
## fixtures defeat every living enemy / arm the source-timed status and resolve the
## outcome so the campaign hand-off can be followed.

const CampaignProgress = preload("res://game/common/CampaignProgress.gd")
const BattleOutcome = preload("res://game/sim/BattleOutcome.gd")
const PROFILE_DIRECTORY := "res://content/battles/levels"
const RESULT_FRAMES := 9000
const HANDOFF_FRAMES := 12000


## Opening tokens a player clicks through: dialogue pages, and the section title's 320-tick
## hold (a click during its entry ramps is ignored by the coordinator, as in the original).
const CLICK_THROUGH_KINDS := ["dialogue_message_id", "section_title_resource"]


static func click() -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	return event


## The level profile of the booted scenario (content/battles/levels/NNN.json), {} when the
## scenario names no level or the level has no profile (encounters, hand-written scenarios).
static func level_profile(scene: Node) -> Dictionary:
	var level := int(scene.first_battle_scenario.get("level", 0))
	if level <= 0:
		return {}
	var path := "%s/%03d.json" % [PROFILE_DIRECTORY, level]
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if typeof(parsed) == TYPE_DICTIONARY else {}


static func sweep_fixture(scene: Node) -> Dictionary:
	var fixture: Variant = level_profile(scene).get("sweep_fixture", {})
	return fixture if typeof(fixture) == TYPE_DICTIONARY else {}


## True when the level's script opens its event chain straight from the battle entry (no
## first-control phase): callers do not play the opening before force_win.
static func skips_opening(scene: Node) -> bool:
	return bool(sweep_fixture(scene).get("skip_opening", false))


## True when the level ends by event completion (no win section): force_win asserts the
## campaign hand-off itself, so the result page's next step does not apply.
static func arms_own_handoff(scene: Node) -> bool:
	return str(sweep_fixture(scene).get("finish", "result")) != "result"


## The row a STORY actSelectInsertEvent takes while the opening plays (default the first).
static func opening_select_option(scene: Node) -> int:
	return int(sweep_fixture(scene).get("opening_select_option", 0))


static func _ints(values: Variant) -> Array:
	var result: Array = []
	for value in (values as Array):
		result.append(int(value))
	return result


## Plays the opening to first control: dialogue is clicked through, walks accelerated. A
## STORY actSelectInsertEvent takes the fixture's `opening_select_option` row (default 0).
static func play_opening(tree: SceneTree, scene: Node, label: String, assert_cb: Callable) -> void:
	var coordinator = scene.opening_coordinator
	var select_option := opening_select_option(scene)
	if coordinator != null:
		coordinator.walk_pixels_per_second = 6400.0
	for _frame in range(RESULT_FRAMES):
		if coordinator == null or not coordinator.active:
			break
		if scene.party_equipment_screen != null and scene.party_equipment_screen.active:
			scene.party_equipment_screen.close()
		if coordinator != null and not (coordinator.summary().get("select_options", []) as Array).is_empty():
			coordinator.choose_select_option(select_option)
		elif str(coordinator.summary().get("current_event_kind", "")) in CLICK_THROUGH_KINDS:
			coordinator.handle_input(click())
		await tree.process_frame
	assert_cb.call(coordinator == null or not coordinator.active, "%s: the opening reaches first control" % label)


## The shared traversal fixture: interprets the level's `sweep_fixture` (mode `clear` when
## absent) until the result page shows a victory or the fixture's hand-off is armed.
static func force_win(tree: SceneTree, scene: Node, label: String, assert_cb: Callable) -> bool:
	var fixture := sweep_fixture(scene)
	var mode := str(fixture.get("mode", "clear"))
	match mode:
		"clear":
			return await _force_clear(tree, scene, label, assert_cb, fixture)
		"status":
			return await _force_status(tree, scene, label, assert_cb, fixture)
		"rounds":
			return await _force_rounds(tree, scene, label, assert_cb, fixture)
		"play_to_round":
			return await _force_play_to_round(tree, scene, label, assert_cb, fixture)
		"choice_branch":
			return await _force_choice_branch(tree, scene, label, assert_cb, fixture)
	assert_cb.call(false, "%s: unknown sweep_fixture mode %s" % [label, mode])
	return false


static func _protect_players(loop: Dictionary, rules) -> void:
	for actor in loop.get("units", []):
		if actor["battle_actor_role"] == rules.ROLE_PLAYER:
			actor["defeated"] = false
			actor["hp"] = actor["max_hp"]


static func _defeat_living_enemies(loop: Dictionary, rules) -> int:
	var count := 0
	for actor in loop.get("units", []):
		if actor["battle_actor_role"] == rules.ROLE_ENEMY and rules.Presence.living(actor):
			rules.set_unit_defeated(loop, actor["id"], true)
			count += 1
	return count


static func _escape_zone(scene: Node) -> Array:
	return scene.first_battle_scenario.get("scenario_rules", {}).get("script_fallback", {}).get("escape_zone", [])


## Waits for the result page, advancing result dialogue and clicking coordinator cutscenes.
static func _await_result(tree: SceneTree, scene: Node, presentation) -> void:
	for _frame in range(RESULT_FRAMES):
		if presentation.battle_finished:
			break
		if presentation.dialogue_active():
			presentation.advance_dialogue()
		elif scene.opening_coordinator != null and scene.opening_coordinator.active:
			if str(scene.opening_coordinator.summary().get("current_event_kind", "")) in CLICK_THROUGH_KINDS:
				scene.opening_coordinator.handle_input(click())
		await tree.process_frame


static func _victory_shown(scene: Node, presentation, label: String, assert_cb: Callable, what: String) -> bool:
	var shown: bool = presentation.battle_finished and BattleOutcome.won(scene.play_loop)
	assert_cb.call(shown, "%s: %s reaches a victory result page (outcome %s)" % [label, what, BattleOutcome.describe(BattleOutcome.of(scene.play_loop))])
	return shown


## Mode `clear`: protect the controlled roster, hold the fail statuses out, defeat every
## living enemy phase by phase (replaying script phases) until the result page shows a
## victory; an escape objective falls back to standing the controlled unit on the first
## escape cell. `arm_win_statuses` / `advance_turn` run first when no win status is armed at
## first control (a scripted progression without a clear win, or a win status armed by a
## later round event).
static func _force_clear(tree: SceneTree, scene: Node, label: String, assert_cb: Callable, fixture: Dictionary) -> bool:
	var coordinator = scene.opening_coordinator
	var rules = scene.BattlePlayLoop
	var presentation = scene.get_node("BattlePresentation")
	# This fixture validates the victory path after an artificial clear; keep the
	# controlled roster alive so enemy AI cannot turn it into a defeat while a
	# scripted result dialogue settles.
	_protect_players(scene.play_loop, rules)
	# The artificial clear is a victory-path probe; do not let a source fail
	# status race the protected roster while the result actions settle.
	scene.play_loop["fail_statuses"] = []
	var win_unarmed: bool = (scene.play_loop.get("win_statuses", []) as Array).is_empty()
	if fixture.has("arm_win_statuses") and win_unarmed:
		scene.set_process(false)
		var armed: Dictionary = rules.copy(scene.play_loop)
		armed["win_statuses"] = _ints(fixture["arm_win_statuses"])
		armed["event_statuses"] = []
		armed = rules.resolve_outcome(armed)
		scene.apply_loop(armed, "test")
		scene.set_process(true)
	elif fixture.has("advance_turn") and win_unarmed:
		var scripted: Dictionary = rules.copy(scene.play_loop)
		scripted["turn"] = int(fixture["advance_turn"])
		# One completed-action scan starts at most one event (original_round_display.md
		# «Scan shape»): WINFAIL051 needs one for event 2 and the next for event 3. Scan
		# until the round's event has armed a win status, before the artificial clear.
		for _scan in range(8):
			var fired_before: int = (scripted.get("winfail_runtime", {}).get("fired", []) as Array).size()
			scripted = rules.resolve_outcome(rules.BattleScenarioRuleAdapter.run_event_hooks(scripted))
			if not (scripted.get("win_statuses", []) as Array).is_empty() or BattleOutcome.decided(scripted):
				break
			if (scripted.get("winfail_runtime", {}).get("fired", []) as Array).size() == fired_before:
				break
		scene.apply_loop(scripted, "test")
	for _phase in range(6):
		if presentation.battle_finished:
			break
		scene.set_process(false)
		var living := _defeat_living_enemies(scene.play_loop, rules)
		if living == 0:
			scene.set_process(true)
			scene.apply_loop(rules.resolve_outcome(rules.BattleScenarioRuleAdapter.run_event_hooks(scene.play_loop)), "test")
			if BattleOutcome.decided(scene.play_loop):
				break
			continue
		scene.apply_loop(rules.resolve_outcome(rules.BattleScenarioRuleAdapter.run_event_hooks(scene.play_loop)), "test")
		scene.set_process(true)
		var settled := 0
		for _frame in range(RESULT_FRAMES):
			if presentation.battle_finished:
				break
			if scene.party_equipment_screen != null and scene.party_equipment_screen.active:
				scene.party_equipment_screen.close()
			elif coordinator != null and coordinator.active:
				settled = 0
				if str(coordinator.summary().get("current_event_kind", "")) in CLICK_THROUGH_KINDS:
					coordinator.handle_input(click())
			elif scene.has_actor_motion():
				settled = 0
			else:
				settled += 1
				if settled > 90:
					break
			await tree.process_frame
	if not presentation.battle_finished:
		# An escape objective: stand the controlled unit on the first escape cell and
		# resolve, the way the arrival check would see a player who walked there.
		var zone: Array = _escape_zone(scene)
		var player_id := str(scene.first_battle_scenario.get("player_unit_id", ""))
		if not zone.is_empty() and player_id != "":
			scene.set_process(false)
			rules.unit_ref(scene.play_loop, player_id)["coord"] = Vector2i(int(zone[0][0]), int(zone[0][1]))
			scene.apply_loop(rules.resolve_outcome(rules.BattleScenarioRuleAdapter.run_event_hooks(scene.play_loop)), "test")
			scene.set_process(true)
			for _frame in range(RESULT_FRAMES):
				if presentation.battle_finished:
					break
				if coordinator != null and coordinator.active and str(coordinator.summary().get("current_event_kind", "")) in CLICK_THROUGH_KINDS:
					coordinator.handle_input(click())
				await tree.process_frame
	var outcome := BattleOutcome.describe(BattleOutcome.of(scene.play_loop))
	var diagnostics := "interaction=%s coordinator_active=%s event=%s cutscene=%s motion=%s loot_waiting=%s combat_busy=%s settlement=%s win=%s event=%s inserts=%s fired=%s living=%s script_units=%s transactions=%s" % [str(scene.play_loop.get("interaction", "")), str(coordinator != null and coordinator.active), str(coordinator.summary().get("current_event_kind", "")) if coordinator != null else "", str(scene.script_cutscene_consumed), str(scene.has_actor_motion()), str(rules.loot_waiting(scene.play_loop)), str(presentation.combat_busy(scene.play_loop)), str(scene.play_loop.get("settlement", {})), str(scene.play_loop.get("win_statuses", [])), str(scene.play_loop.get("event_statuses", [])), str((scene.play_loop.get("winfail_runtime", {}) as Dictionary).get("inserts", []).size()), str((scene.play_loop.get("winfail_runtime", {}) as Dictionary).get("fired", []).size()), str(scene.play_loop["units"].filter(func(u): return u["battle_actor_role"] == rules.ROLE_ENEMY and rules.Presence.living(u)).map(func(u): return "%s hp=%s undead=%s" % [u["id"], str(u.get("hp")), str(u.get("undead", false))])), str(scene.play_loop["units"].filter(func(u): return str(u["id"]).begins_with("level")).map(func(u): return "%s hp=%s defeated=%s" % [u["id"], str(u.get("hp")), str(u.get("defeated"))])), str(scene.play_loop.get("script_actor_transactions", []))]
	assert_cb.call(presentation.battle_finished and BattleOutcome.won(scene.play_loop), "%s: force-win reaches a victory result page (outcome %s; %s)" % [label, outcome, diagnostics])
	return presentation.battle_finished and BattleOutcome.won(scene.play_loop)


## Mode `status`: a source-timed objective that an artificial clear would misrepresent
## (arrival, evacuation, event-only chains, actTRUE terminal statuses). Edits the frozen loop
## as the fixture says — `players` (`defeat` / `depart`), `arrive {unit, cell, restore}`,
## `turn`, `event_statuses`, `win_statuses` — runs the round hooks unless `run_hooks` is
## false, resolves, applies the `expect_*` / `commit_outcome`
## post-conditions, then waits for the result page or (`finish`) the campaign hand-off.
static func _force_status(tree: SceneTree, scene: Node, label: String, assert_cb: Callable, fixture: Dictionary) -> bool:
	var rules = scene.BattlePlayLoop
	var presentation = scene.get_node("BattlePresentation")
	scene.set_process(false)
	var loop: Dictionary = rules.copy(scene.play_loop)
	loop["fail_statuses"] = []
	if bool(fixture.get("expect_no_outcome", false)):
		assert_cb.call(not BattleOutcome.decided(loop), "%s: first control has no outcome before the fixture acts" % label)
	match str(fixture.get("players", "")):
		"defeat":
			for actor_value in loop.get("units", []):
				var actor: Dictionary = actor_value
				if actor.get("battle_actor_role") == rules.ROLE_PLAYER:
					actor["defeated"] = true
		"depart":
			var runtime: Dictionary = loop["winfail_runtime"]
			for actor_value in loop.get("units", []):
				var actor: Dictionary = actor_value
				if actor.get("battle_actor_role") == rules.ROLE_PLAYER:
					var departed: Array = runtime["departed_unit_ids"]
					if departed.find(actor["id"]) == -1:
						departed.append(actor["id"])
	var arrive: Dictionary = fixture.get("arrive", {})
	var restore_unit := ""
	var restore_coord := Vector2i.ZERO
	if not arrive.is_empty():
		var destination := Vector2i.ZERO
		if typeof(arrive.get("cell")) == TYPE_ARRAY:
			destination = Vector2i(int(arrive["cell"][0]), int(arrive["cell"][1]))
		else:
			var zone: Array = _escape_zone(scene)
			assert_cb.call(not zone.is_empty(), "%s has an escape zone for its arrival fixture" % label)
			if zone.is_empty():
				scene.set_process(true)
				return false
			destination = Vector2i(int(zone[0][0]), int(zone[0][1]))
		var unit_id := str(arrive.get("unit", ""))
		if unit_id == "players":
			for actor_value in loop.get("units", []):
				var actor: Dictionary = actor_value
				if actor.get("battle_actor_role") == rules.ROLE_PLAYER:
					actor["coord"] = destination
		elif bool(arrive.get("restore", false)):
			# Preserve the logical victory while leaving the presentation mirror at its
			# valid pre-arrival footprint (a large actor's source endpoint may not be a valid stop).
			restore_unit = unit_id
			restore_coord = rules.unit_ref(loop, unit_id).get("coord", Vector2i.ZERO)
			rules.set_unit_coord(loop, unit_id, destination)
		else:
			rules.unit_ref(loop, unit_id)["coord"] = destination
	if fixture.has("turn"):
		loop["turn"] = int(fixture["turn"])
	if fixture.has("event_statuses"):
		loop["event_statuses"] = _ints(fixture["event_statuses"])
	if fixture.has("win_statuses"):
		loop["win_statuses"] = _ints(fixture["win_statuses"])
	if bool(fixture.get("run_hooks", true)):
		loop = rules.BattleScenarioRuleAdapter.run_event_hooks(loop)
		loop["fail_statuses"] = []
	loop = rules.resolve_outcome(loop)
	if fixture.has("expect_win_status"):
		assert_cb.call((loop.get("win_statuses", []) as Array).has(int(fixture["expect_win_status"])), "%s: the source chain arms win_%d" % [label, int(fixture["expect_win_status"])])
		loop["fail_statuses"] = []
		loop = rules.resolve_outcome(loop)
	if bool(fixture.get("expect_victory_resolved", false)):
		assert_cb.call(BattleOutcome.won(loop), "%s resolves its arrival victory" % label)
	if fixture.has("commit_outcome"):
		# An event-only battle without a win section: the fixture commits the result
		# explicitly ({result, reason}, a BattleOutcome structure).
		assert_cb.call(BattleOutcome.error(fixture["commit_outcome"]) == "" and not (fixture["commit_outcome"] as Dictionary).is_empty(), "%s: commit_outcome is a decided BattleOutcome" % label)
		loop["battle_outcome"] = (fixture["commit_outcome"] as Dictionary).duplicate()
		loop["interaction"] = "battle_result"
	if restore_unit != "":
		rules.set_unit_coord(loop, restore_unit, restore_coord)
	scene.apply_loop(loop, "test")
	scene.set_process(true)
	var finish := str(fixture.get("finish", "result"))
	if finish == "result":
		await _await_result(tree, scene, presentation)
		return _victory_shown(scene, presentation, label, assert_cb, "source-timed %s fixture" % str(fixture.get("mode", "status")))
	return await _await_handoff(tree, scene, label, assert_cb, fixture, finish)


## `finish: "pending_handoff"` waits for the campaign hand-off the cutscene arms (pressing
## the result page's next step when none came); `finish: "handoff_or_result"` stops at the
## result page or the hand-off. `expect_handoff` names the destination: "world_map" or
## {"battle": "79"} (campaign.json entries).
static func _await_handoff(tree: SceneTree, scene: Node, label: String, assert_cb: Callable, fixture: Dictionary, finish: String) -> bool:
	var presentation = scene.get_node("BattlePresentation")
	var coordinator = scene.opening_coordinator
	for _frame in range(HANDOFF_FRAMES):
		if CampaignProgress.has_pending():
			break
		if finish == "handoff_or_result" and presentation.battle_finished:
			break
		if scene.party_equipment_screen != null and scene.party_equipment_screen.active:
			scene.party_equipment_screen.close()
		elif coordinator != null and coordinator.active and str(coordinator.summary().get("current_event_kind", "")) in CLICK_THROUGH_KINDS:
			coordinator.handle_input(click())
		await tree.process_frame
	if finish == "pending_handoff" and not CampaignProgress.has_pending():
		scene.campaign_progress.start_next_battle()
		await tree.process_frame
	var handoff := CampaignProgress.pending if CampaignProgress.has_pending() else CampaignProgress.last_entry
	var campaign := CampaignProgress.load_campaign()
	var expected := ""
	var target: Variant = fixture.get("expect_handoff", "")
	if typeof(target) == TYPE_DICTIONARY:
		expected = str(campaign.get("battles", {}).get(str((target as Dictionary).get("battle", "")), {}).get("scenario", ""))
	elif str(target) == "world_map":
		expected = str(campaign.get("world_map", {}).get("scenario", ""))
	var reached: bool = expected != "" and str(handoff.get("scenario_path", "")) == expected
	assert_cb.call(reached, "%s: the event chain hands off to %s (%s), actual=%s" % [label, str(target), expected, str(handoff)])
	return reached


## Mode `rounds`: set the turn to each source round in order (running the round hooks and
## resolving, fail statuses held out), then defeat the living enemies phase by phase
## (`clear_phases`) and wait for the result page.
static func _force_rounds(tree: SceneTree, scene: Node, label: String, assert_cb: Callable, fixture: Dictionary) -> bool:
	var rules = scene.BattlePlayLoop
	var presentation = scene.get_node("BattlePresentation")
	scene.set_process(false)
	var loop: Dictionary = scene.play_loop
	_protect_players(loop, rules)
	loop["fail_statuses"] = []
	if bool(fixture.get("expect_win_unarmed_before", false)):
		assert_cb.call((loop.get("win_statuses", []) as Array).is_empty(), "%s: no win status is armed before the source rounds" % label)
	for target_round in _ints(fixture.get("rounds", [])):
		# Evaluate each source round before resolving so a provisional fail status cannot
		# terminate the timing probe.
		loop["turn"] = target_round
		loop["fail_statuses"] = []
		loop = rules.BattleScenarioRuleAdapter.run_event_hooks(loop)
		loop["fail_statuses"] = []
		loop = rules.resolve_outcome(loop)
		loop["fail_statuses"] = []
		assert_cb.call(int(loop.get("turn", 0)) >= target_round or BattleOutcome.decided(loop), "%s reaches scripted round %d before force-win" % [label, target_round])
	if bool(fixture.get("expect_undecided_after_rounds", false)):
		assert_cb.call(not BattleOutcome.decided(loop), "%s: reaching the source rounds does not decide the battle" % label)
	for _phase in range(int(fixture.get("clear_phases", 0))):
		var converted := _defeat_living_enemies(loop, rules)
		loop = rules.resolve_outcome(rules.BattleScenarioRuleAdapter.run_event_hooks(loop))
		loop["fail_statuses"] = []
		if BattleOutcome.decided(loop) or converted == 0:
			break
	if fixture.has("expect_win_status"):
		assert_cb.call((loop.get("win_statuses", []) as Array).has(int(fixture["expect_win_status"])), "%s: the source chain arms win_%d after the clear" % [label, int(fixture["expect_win_status"])])
	scene.apply_loop(loop, "test")
	scene.set_process(true)
	await _await_result(tree, scene, presentation)
	return _victory_shown(scene, presentation, label, assert_cb, "source-timed rounds fixture")


## Mode `play_to_round`: play the battle with wait commands / AI steps up to each source
## round (so the script's own insertions and installs commit), assert `expect_units`, then
## defeat the living enemies, resolve, settle the rewards and wait for the result page.
static func _force_play_to_round(tree: SceneTree, scene: Node, label: String, assert_cb: Callable, fixture: Dictionary) -> bool:
	var rules = scene.BattlePlayLoop
	var presentation = scene.get_node("BattlePresentation")
	scene.set_process(false)
	var loop: Dictionary = scene.play_loop
	for target_round in _ints(fixture.get("rounds", [])):
		var guard := 0
		while int(loop.get("turn", 0)) < target_round and guard < 256:
			loop = _defer_loot(loop, rules)
			if str(loop.get("interaction", "")) == "action_menu":
				loop = rules.choose_command(loop, "wait")
			elif str(loop.get("interaction", "")) == "ai_resolving":
				loop = rules.advance_current_actor(loop)
			else:
				break
			guard += 1
		# Round-N script events fire after round N's first completed action (the original scans
		# before the queue advance bumps the round, original_round_display.md): complete it too.
		loop = _defer_loot(loop, rules)
		if str(loop.get("interaction", "")) == "action_menu":
			loop = rules.choose_command(loop, "wait")
		elif str(loop.get("interaction", "")) == "ai_resolving":
			loop = rules.advance_current_actor(loop)
		assert_cb.call(int(loop.get("turn", 0)) >= target_round, "%s reaches scripted round %d before forced victory" % [label, target_round])
	for expected_value in fixture.get("expect_units", []):
		var expected: Dictionary = expected_value
		var unit: Dictionary = rules.unit(loop, str(expected["id"]))
		assert_cb.call(str(unit.get("actor_id", "")) == str(expected["actor_id"]) and str(unit.get("battle_actor_role", "")) == str(expected["role"]), "%s installs %s (%s, %s) before forced victory" % [label, str(expected["id"]), str(expected["actor_id"]), str(expected["role"])])
	_defeat_living_enemies(loop, rules)
	loop = rules.resolve_outcome(loop)
	var settlement: Dictionary = loop.get("settlement", {})
	if not settlement.is_empty() and not bool(settlement.get("closed", true)):
		loop = rules.finish_rewards(loop, int(settlement.get("sequence", 0)), int(settlement.get("revision", 0)), false, true)
	scene.apply_loop(loop, "test")
	scene.set_process(true)
	await _await_result(tree, scene, presentation)
	return _victory_shown(scene, presentation, label, assert_cb, "played-rounds fixture")


## An open collection panel refuses every command: take its "later" as the commander does
## (Autoplay.play_battle), keeping the pending items.
static func _defer_loot(loop: Dictionary, rules) -> Dictionary:
	if not rules.loot_waiting(loop):
		return loop
	var settlement: Dictionary = loop["settlement"]
	return rules.finish_rewards(loop, int(settlement["sequence"]), int(settlement["revision"]), false, true)


## Mode `choice_branch`: advance to each source round, letting the coordinator play the
## armed event cutscene; a round with `expect_event_status` asserts the choice event is
## armed, a round with `select_option` waits for the actSelectInsertEvent prompt and takes
## that row. `expect_install_unit` asserts the branch's script install created the unit.
static func _force_choice_branch(tree: SceneTree, scene: Node, label: String, assert_cb: Callable, fixture: Dictionary) -> bool:
	var rules = scene.BattlePlayLoop
	var presentation = scene.get_node("BattlePresentation")
	var coordinator = scene.opening_coordinator
	scene.set_process(false)
	var loop: Dictionary = scene.play_loop
	loop["fail_statuses"] = []
	for step_value in fixture.get("rounds", []):
		var step: Dictionary = step_value
		var target_round := int(step["turn"])
		loop["turn"] = target_round
		loop = rules.BattleScenarioRuleAdapter.run_event_hooks(loop)
		loop["fail_statuses"] = []
		loop = rules.resolve_outcome(loop)
		loop["fail_statuses"] = []
		scene.apply_loop(loop, "test")
		scene.set_process(true)
		for _frame in range(RESULT_FRAMES):
			if coordinator == null or not coordinator.active: break
			if not (coordinator.summary().get("select_options", []) as Array).is_empty(): break
			if str(coordinator.summary().get("current_event_kind", "")) in CLICK_THROUGH_KINDS: coordinator.handle_input(click())
			await tree.process_frame
		scene.set_process(false)
		loop = scene.play_loop
		if step.has("expect_event_status"):
			assert_cb.call(loop.get("event_statuses", []).has(int(step["expect_event_status"])), "%s: round %d arms event %d" % [label, target_round, int(step["expect_event_status"])])
		if step.has("select_option"):
			# The event cutscene starts from _process on a later frame; wait for the
			# coordinator to come up and reach the actSelectInsertEvent prompt.
			scene.set_process(true)
			var opened := false
			var idle := 0
			for _frame in range(RESULT_FRAMES):
				await tree.process_frame
				coordinator = scene.opening_coordinator
				if coordinator != null and coordinator.active:
					idle = 0
					if (coordinator.summary().get("select_options", []) as Array).size() == 2:
						opened = true
						break
					if str(coordinator.summary().get("current_event_kind", "")) in CLICK_THROUGH_KINDS:
						coordinator.handle_input(click())
				else:
					idle += 1
					if idle > 120:
						break
			assert_cb.call(opened, "%s: round %d opens both choices" % [label, target_round])
			if opened:
				coordinator.choose_select_option(int(step["select_option"]))
				for _frame in range(RESULT_FRAMES):
					if presentation.battle_finished: break
					if coordinator.active and str(coordinator.summary().get("current_event_kind", "")) in CLICK_THROUGH_KINDS: coordinator.handle_input(click())
					await tree.process_frame
	var shown := _victory_shown(scene, presentation, label, assert_cb, "choice branch")
	if fixture.has("expect_install_unit"):
		var installed := false
		for transaction in scene.play_loop.get("script_actor_transactions", []):
			for row in (transaction as Dictionary).get("actions", []):
				if str(((row as Dictionary).get("install", {}) as Dictionary).get("unit_id", "")) == str(fixture["expect_install_unit"]):
					installed = true
		assert_cb.call(installed, "%s: the branch installs %s through its script template" % [label, str(fixture["expect_install_unit"])])
	return shown
