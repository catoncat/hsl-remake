extends SceneTree

## Story-mode walkthrough of chapter 1 as the product plays it after the 歐姆村 battle
## (level 1, SR-074): the big map from 歐姆村, the towns and every registered scene in
## the order the original scripts chain them, with each not-yet-remade battle taken
## through its 略過戰鬥（視為勝利） row. Proves the map / town / scene hand-offs connect
## end to end — from 歐姆村 to the ship at 薛維斯港 — not that any battle plays. Travel,
## walk and dialogue pacing are forced fast; nothing here proves original behaviour.

const RuntimeScene = preload("res://game/battle/scene/BattleSceneRuntime.tscn")
const CampaignProgress = preload("res://game/battle/runtime/CampaignProgress.gd")
const MapRules = preload("res://game/world/WorldMapRules.gd")
const WorldActions = preload("res://game/world/WorldScriptActions.gd")
const TownRules = preload("res://game/sim/TownEventRules.gd")
const TestSuite = preload("res://tests/support/TestSuite.gd")
const BattleOutcome = preload("res://game/sim/BattleOutcome.gd")

const WORLD_MAP_PATH := "res://content/imported/hsl/global/world_map/world_map.json"
const MAP_SCENE := "res://content/world/world_map_scene.json"

var failures: Array[String] = []
var world_map: Dictionary = {}
var steps: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _assert_eq(actual: Variant, expected: Variant, message: String) -> void:
	if actual != expected:
		failures.append("%s expected=%s actual=%s" % [message, str(expected), str(actual)])


func _assert_true(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _click() -> InputEventMouseButton:
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	return click


## Boots whatever the campaign hand-off points at (the product reloads the scene the
## same way); returns the runtime scene.
func _boot_pending() -> Node:
	_assert_true(CampaignProgress.has_pending(), "a campaign hand-off is pending (%s)" % (steps[steps.size() - 1] if not steps.is_empty() else "start"))
	var path := str(CampaignProgress.pending.get("scenario_path", ""))
	var scene = RuntimeScene.instantiate()
	scene.scenario_path = path
	scene.startup_mode = "product_opening"
	root.add_child(scene)
	await process_frame
	await process_frame
	steps.append(path.get_file())
	return scene


func _free(scene: Node) -> void:
	scene.queue_free()
	await process_frame
	await process_frame


## Plays a story scene to its end: pages dialogue, takes the first row of any
## actSelectInsertEvent prompt, and on a not-remade card takes the victory row
## (略過戰鬥（視為勝利）) so the win section's writes reach the world. Returns when a
## hand-off is pending.
func _play_scene(scene: Node) -> void:
	if str(scene.scenario_path) == "res://content/battles/gol_road_battle.json":
		await _play_formal_gol_handoff(scene)
		return
	var coordinator = scene.opening_coordinator
	if coordinator != null and not coordinator.story_mode:
		await _play_formal_handoff(scene)
		return
	_assert_true(coordinator != null and coordinator.active and coordinator.story_mode, "%s runs as a story scene" % scene.scenario_path)
	if coordinator == null:
		return
	coordinator.walk_pixels_per_second = 6400.0
	var frames := 0
	while coordinator.active and not coordinator.story_finished and frames < 8000 and not CampaignProgress.has_pending():
		if not (coordinator.summary().get("select_options", []) as Array).is_empty():
			coordinator.choose_select_option(0)
		elif scene.party_equipment_screen != null and scene.party_equipment_screen.active:
			scene.party_equipment_screen.close()  # actEnterStorageWindow: leave the party as it is
		elif str(coordinator.summary().get("current_event_kind", "")) == "dialogue_message_id":
			coordinator.handle_input(_click())
		await process_frame
		frames += 1
	if not CampaignProgress.has_pending() and coordinator.story_finished:
		var options: Array = coordinator.summary().get("end_card_options", [])
		_assert_true(not options.is_empty(), "%s: the not-remade card offers the victory row" % scene.scenario_path)
		coordinator.select_end_card_option(0)
		coordinator.confirm_end_card_option()
		await process_frame
	_assert_true(CampaignProgress.has_pending(), "%s hands off through the campaign" % scene.scenario_path)


func _play_formal_gol_handoff(scene: Node) -> void:
	# This map/story traversal test uses explicit defeated-enemy preconditions,
	# not the removed preview skip card. Actual combat/input is independently
	# verified by capture_gol_road_review, including the exact victory save→camps.
	var coordinator = scene.opening_coordinator
	_assert_true(coordinator != null and not coordinator.story_mode, "registered Gol is a battle, not a silently skipped preview")
	if coordinator == null: return
	coordinator.walk_pixels_per_second = 6400.0
	for _frame in range(8000):
		if not coordinator.active: break
		if str(coordinator.summary().get("current_event_kind", "")) == "dialogue_message_id": coordinator.handle_input(_click())
		await process_frame
	_assert_true(not coordinator.active, "formal Gol opening reaches its first control")
	var rules = scene.BattlePlayLoop
	scene.set_process(false)
	for actor in scene.play_loop["units"]:
		if actor["actor_id"] == "028" and actor["id"] != "actor028_1": rules._set_unit_defeated(scene.play_loop, actor["id"], true)
	scene.apply_loop(rules._resolve_outcome(rules.BattleScenarioRuleAdapter.run_event_hooks(scene.play_loop)), "test")
	_assert_true(rules.unit(scene.play_loop, "tina").get("actor_id") == "002" and scene.play_loop["units"].size() == 12, "source event really creates the priest and four pursuers before the second phase")
	scene.apply_loop(scene.play_loop, "test")
	scene.set_process(true)
	for _frame in range(8000):
		if scene.script_cutscene_consumed == 1 and not coordinator.active: break
		if coordinator.active and str(coordinator.summary().get("current_event_kind", "")) == "dialogue_message_id": coordinator.handle_input(_click())
		await process_frame
	_assert_true(scene.script_cutscene_consumed == 1 and not coordinator.active, "source arrival dialogue/motion completes before the next precondition")
	scene.set_process(false)
	for actor in scene.play_loop["units"]:
		if actor["battle_actor_role"] == rules.ROLE_ENEMY and rules.Presence.living(actor): rules._set_unit_defeated(scene.play_loop, actor["id"], true)
	scene.apply_loop(rules._resolve_outcome(scene.play_loop), "test")
	scene.set_process(true)
	for _frame in range(8000):
		if scene.get_node("BattlePresentation").battle_finished: break
		if coordinator.active and str(coordinator.summary().get("current_event_kind", "")) == "dialogue_message_id": coordinator.handle_input(_click())
		await process_frame
	_assert_true(scene.play_loop["winfail_runtime"]["resolved"]["key"] == "win_0", "real second-phase result drives the camp destination")
	scene.campaign_progress.start_next_battle()
	_assert_eq(str(CampaignProgress.pending.get("scenario_path", "")), "res://content/battles/story_055.json", "formal Gol victory enters the registered camp chain")
	_assert_true(CampaignProgress.pending.get("carry", {}).get("units", {}).has("tina"), "story traversal carries the real event-created priest")


## Any other registered formal battle (levels assembled by tools/hsl_level_battle.py):
## the shared traversal fixture — opening to first control, every living enemy defeated
## and the outcome resolved, script phases replayed, then the result page's next step.
## Map / story traversal only; the battle itself is verified by run_battle_sweep_tests
## and the level's own evidence.
func _play_formal_handoff(scene: Node) -> void:
	var coordinator = scene.opening_coordinator
	var rules = scene.BattlePlayLoop
	var presentation = scene.get_node("BattlePresentation")
	coordinator.walk_pixels_per_second = 6400.0
	for _frame in range(8000):
		if not coordinator.active: break
		if not (coordinator.summary().get("select_options", []) as Array).is_empty():
			coordinator.choose_select_option(0)
		elif str(coordinator.summary().get("current_event_kind", "")) == "dialogue_message_id":
			coordinator.handle_input(_click())
		await process_frame
	# Formal 900's first choice is the non-battle branch: the selected status
	# writes the town/map hand-off and the opening ends without first control.
	if str(scene.scenario_path) == "res://content/battles/battle_900.json" and CampaignProgress.has_pending():
		_assert_eq(str(CampaignProgress.pending.get("scenario_path", "")), MAP_SCENE, "level 900 choice one returns to the map")
		return
	_assert_true(not coordinator.active, "%s: the formal opening reaches its first control" % scene.scenario_path)
	if str(scene.scenario_path) == "res://content/battles/battle_007.json":
		await _play_level7_formal_handoff(scene, rules, presentation)
		return
	# WINFAIL010 arms its first win status from event 3 at round 5; advance that
	# source-timed phase before the generic traversal clear fixture.
	if (scene.play_loop.get("win_statuses", []) as Array).is_empty() and scene.play_loop.get("event_statuses", []).has(3):
		var scripted: Dictionary = scene.play_loop.duplicate(true)
		scripted["turn"] = 5
		scripted = rules.BattleScenarioRuleAdapter.run_event_hooks(scripted)
		scripted = rules._resolve_outcome(scripted)
		scene.apply_loop(scripted, "test")
	for _phase in range(6):
		if presentation.battle_finished: break
		var living := 0
		scene.set_process(false)
		for actor in scene.play_loop["units"]:
			if actor["battle_actor_role"] == rules.ROLE_ENEMY and rules.Presence.living(actor):
				rules._set_unit_defeated(scene.play_loop, actor["id"], true)
				living += 1
		if living == 0:
			scene.set_process(true)
			break
		scene.apply_loop(rules._resolve_outcome(rules.BattleScenarioRuleAdapter.run_event_hooks(scene.play_loop)), "test")
		scene.set_process(true)
		var settled := 0
		for _frame in range(8000):
			if presentation.battle_finished: break
			if coordinator.active:
				settled = 0
				if str(coordinator.summary().get("current_event_kind", "")) == "dialogue_message_id": coordinator.handle_input(_click())
			elif scene.has_actor_motion():
				settled = 0
			else:
				settled += 1
				if settled > 90: break
			await process_frame
	_assert_true(presentation.battle_finished and BattleOutcome.won(scene.play_loop), "%s: the forced victory reaches the result page" % scene.scenario_path)
	scene.campaign_progress.start_next_battle()
	await process_frame
	_assert_true(CampaignProgress.has_pending(), "%s hands off through the campaign" % scene.scenario_path)


func _play_level7_formal_handoff(scene: Node, rules, presentation) -> void:
	# Level 7's round-5/6 script actors must be committed before the forced clear;
	# otherwise this traversal would only prove the result page, not the event path.
	scene.set_process(false)
	var loop: Dictionary = scene.play_loop
	for target_round in [5, 6]:
		var guard := 0
		while int(loop.get("turn", 0)) < target_round and guard < 256:
			if str(loop.get("interaction", "")) == "action_menu":
				loop = rules.choose_command(loop, "wait")
			elif str(loop.get("interaction", "")) == "ai_resolving":
				loop = rules._advance_current_actor(loop)
			else:
				break
			guard += 1
		# Round-N script events fire after round N's first completed action (the original scans
		# before the queue advance bumps the round, original_round_display.md): complete it too.
		if str(loop.get("interaction", "")) == "action_menu":
			loop = rules.choose_command(loop, "wait")
		elif str(loop.get("interaction", "")) == "ai_resolving":
			loop = rules._advance_current_actor(loop)
		_assert_true(int(loop.get("turn", 0)) >= target_round, "level 7 reaches scripted round %d before forced victory" % target_round)
	var shera: Dictionary = rules.unit(loop, "shera")
	_assert_true(str(shera.get("actor_id", "")) == "005" and str(shera.get("battle_actor_role", "")) == rules.ROLE_PLAYER, "level 7 installs player-controlled Shera before forced victory")
	for actor in loop.get("units", []):
		if actor["battle_actor_role"] == rules.ROLE_ENEMY and rules.Presence.living(actor):
			rules._set_unit_defeated(loop, actor["id"], true)
	loop = rules._resolve_outcome(loop)
	var settlement: Dictionary = loop.get("settlement", {})
	if not settlement.is_empty() and not bool(settlement.get("closed", true)):
		loop = rules.finish_rewards(loop, int(settlement.get("sequence", 0)), int(settlement.get("revision", 0)), false, true)
	scene.apply_loop(loop, "test")
	scene.set_process(true)
	for _frame in range(8000):
		if presentation.battle_finished: break
		if presentation.dialogue_active():
			presentation.advance_dialogue()
		elif scene.opening_coordinator != null and scene.opening_coordinator.active:
			if str(scene.opening_coordinator.summary().get("current_event_kind", "")) == "dialogue_message_id":
				scene.opening_coordinator.handle_input(_click())
		await process_frame
	_assert_true(presentation.battle_finished and BattleOutcome.won(scene.play_loop), "level 7 reaches the result after scripted handoffs")
	scene.campaign_progress.start_next_battle()
	await process_frame
	_assert_true(CampaignProgress.has_pending(), "level 7 hands off through the campaign")


## Travels one track on the big map and lets the arrival resolve (town open, hand-off
## or plain stop). Returns the arrival outcome kind.
func _travel(scene: Node, point_id: int) -> String:
	var map = scene.world_map_runtime
	_assert_true(map != null, "the big map is open before travelling to point %d" % point_id)
	if map == null:
		return ""
	map.travel_pixels_per_second = 100000.0
	map.track_reveal_tick_seconds = 0.0001
	# Fixed dice: sample 100 rolls an encounter only on ratio-100 points, so the cleared
	# points on the route (2 / 7 / 8, ratios 20 / 14 / 20) never divert the walkthrough
	# into a registered encounter battle.
	map.encounter_sample = 100
	var record: Dictionary = map.select_point(point_id, "walkthrough")
	_assert_true(str(record.get("status", "")) != "unreachable", "point %d is reachable from point %d (track known / revealed)" % [point_id, map.current_point()])
	var frames := 0
	while map.traveling and frames < 240:
		await process_frame
		frames += 1
	await process_frame
	frames = 0
	while bool(map.summary().get("reveal_busy", false)) and frames < 2400:
		await process_frame
		frames += 1
	await process_frame
	await process_frame
	var arrivals: Array = map.summary().get("arrival_records", [])
	steps.append("map→%d" % point_id)
	return str((arrivals[arrivals.size() - 1] as Dictionary).get("kind", "")) if not arrivals.is_empty() else ""


func _confirm_through(town: Node, limit: int = 80) -> int:
	var guard := 0
	while town.mode in ["dialogue", "delay"] and guard < limit:
		town.confirm()
		guard += 1
	return guard


func _menu_entries(town: Node) -> Array:
	var entries: Array = []
	for entry in (town.run["pending"] as Dictionary).get("entries", []):
		entries.append(int(entry["code"]))
	return entries


func _run() -> void:
	world_map = MapRules.load_world_map(WORLD_MAP_PATH)
	CampaignProgress.reset_campaign()
	# After the 歐姆村 battle the campaign hands the party to the big map standing at
	# point 1 with winfail001's victory write applied (actSetTownExecEvent town_歐姆村,9).
	var seeded: Dictionary = WorldActions.ensure_state({}, CampaignProgress.load_campaign())
	var world: Dictionary = seeded["state"]
	world = TownRules.apply_script_town_actions(world, [{"name": "actSetTownExecEvent", "args": ["town_歐姆村", "9"]}], TownRules.load_towndef("res://content/imported/hsl/global/world_map/towndef.json"))["state"]
	CampaignProgress.pending = {"schema": CampaignProgress.SCHEMA, "scenario_path": MAP_SCENE, "carry": {"schema": "hsl_campaign_carry.v1", "units": {}, "loop": {"gold": 1200}}, "from_scenario_id": "ohm_village_battle", "world": world}
	CampaignProgress.last_entry = {}
	await _chapter_one()
	await process_frame
	# Audio-release settle on the wall clock: the gate runs this suite under --fixed-fps.
	await TestSuite.settle_wall_clock(self, 0.2)
	if failures.is_empty():
		print("STORY_MODE_WALKTHROUGH_PASS steps=%d" % steps.size())
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		print("STORY_MODE_WALKTHROUGH_FAIL count=%d after %s" % [failures.size(), " > ".join(steps)])
		quit(1)


## Plays a chain of scenes starting from the pending hand-off until the big map is
## the pending destination; asserts the scene files seen in order.
func _play_chain(expected: Array) -> void:
	var seen: Array = []
	while CampaignProgress.has_pending() and str(CampaignProgress.pending.get("scenario_path", "")) != MAP_SCENE and seen.size() < 8:
		seen.append(str(CampaignProgress.pending.get("scenario_path", "")).get_file())
		var scene = await _boot_pending()
		await _play_scene(scene)
		await _free(scene)
	_assert_eq(seen, expected, "the scenes chain in script order")
	_assert_eq(str(CampaignProgress.pending.get("scenario_path", "")), MAP_SCENE, "the chain returns to the big map")


func _chapter_one() -> void:
	# 歐姆村: on the big map after the battle, exec event 9 armed for the village.
	var map_scene = await _boot_pending()
	var map = map_scene.world_map_runtime
	_assert_eq(int(map.current_point()), 1, "the party stands at 歐姆村")
	_assert_eq(int(((map.state.get("towns", {}) as Dictionary).get("1", {}) as Dictionary).get("exec_event", 0)), 9, "winfail001's victory arms 歐姆村 event 9")
	# 戈爾山道 (2): formal two-phase battle (explicit terminal fixture) → camps.
	_assert_eq(await _travel(map_scene, 2), "level", "戈爾山道 opens level 2")
	await _free(map_scene)
	await _play_chain(["gol_road_battle.json", "story_055.json", "story_056.json"])
	map_scene = await _boot_pending()
	map = map_scene.world_map_runtime
	_assert_eq(int(map.current_point()), 2, "back at 戈爾山道")
	_assert_true(MapRules.track_hidden(map.state, world_map, 3), "track 3 (2–4) is still hidden before the cave")
	# 盜賊洞窟 (3): formal battle → camp 61 (reveals track 3 to 米蘭多, 歐姆村 event 10) → map at 3.
	_assert_eq(await _travel(map_scene, 3), "level", "盜賊洞窟 opens level 3")
	await _free(map_scene)
	await _play_chain(["battle_003.json", "story_061.json"])
	map_scene = await _boot_pending()
	map = map_scene.world_map_runtime
	_assert_eq(int(map.current_point()), 3, "back at 盜賊洞窟")
	_assert_true(not MapRules.track_hidden(map.state, world_map, 3), "STORY061 revealed track 3 (2–4)")
	# Back through 戈爾山道 (an encounter point now: no stop expected in the test's fixed
	# arrival) to 米蘭多 (4, town) and on to 呼嘯平原 (5).
	await _travel(map_scene, 2)
	_assert_eq(int(map.current_point()), 2, "passing back through 戈爾山道")
	if CampaignProgress.has_pending():
		# A rolled encounter (event 501) would leave the map; the test does not model
		# encounter dice — record it and stop here.
		failures.append("unexpected hand-off at point 2: %s" % str(CampaignProgress.pending.get("scenario_path", "")))
		return
	var arrival := await _travel(map_scene, 4)
	_assert_eq(arrival, "town", "米蘭多 opens its town")
	if map.town_runtime != null:
		_confirm_through(map.town_runtime)
		map.town_runtime.leave()
		await process_frame
	_assert_eq(await _travel(map_scene, 5), "level", "呼嘯平原 opens level 5")
	await _free(map_scene)
	# 呼嘯平原 (5): formal battle → victory (席達鎮 exec 19, tracks 6 / 15 hidden) → map at 5.
	await _play_chain(["battle_005.json"])
	map_scene = await _boot_pending()
	map = map_scene.world_map_runtime
	_assert_eq(int(map.current_point()), 5, "back at 呼嘯平原")
	_assert_eq(int(((map.state.get("towns", {}) as Dictionary).get("6", {}) as Dictionary).get("exec_event", 0)), 19, "winfail005's victory arms 席達鎮 event 19")
	_assert_true(MapRules.track_hidden(map.state, world_map, 6), "winfail005 hides track 6 (6–7) until the town battle")
	# 席達鎮 (6): exec event 19, then the tavern's Wosfita soldiers (23) start level 6.
	_assert_eq(await _travel(map_scene, 6), "town", "席達鎮 opens its town")
	var town = map.town_runtime
	_assert_true(town != null, "席達鎮 has a town runtime")
	if town == null:
		return
	_assert_eq(str(town.mode), "dialogue", "exec event 19 talks first")
	_confirm_through(town)
	_assert_eq(str(town.mode), "menu", "back on the root menu")
	town.select_entry(20)
	_confirm_through(town)
	_assert_eq(str(town.mode), "sub_menu", "the tavern menu opens")
	_assert_true(_menu_entries(town).has(23), "the Wosfita soldiers (23) sit in the tavern")
	town.menu_pick(23)
	_confirm_through(town)
	await process_frame
	await process_frame
	_assert_true(CampaignProgress.has_pending() and str(CampaignProgress.pending.get("scenario_path", "")) == "res://content/battles/battle_006.json", "the soldiers' teSetNextPlayLevelEvent 6,6 enters the level-6 battle")
	await _free(map_scene)
	# 席達鎮 battle (6): formal battle (forced victory) → camp 62 → hall 63 (reveals track 6) → map at 6.
	await _play_chain(["battle_006.json", "story_062.json", "story_063.json"])
	map_scene = await _boot_pending()
	map = map_scene.world_map_runtime
	_assert_eq(int(map.current_point()), 6, "back at 席達鎮")
	_assert_true(not MapRules.track_hidden(map.state, world_map, 6), "STORY063 reveals track 6 (6–7)")
	# 寧靜之森 (7) → camp 64 → map at 7; 菲納斯河畔 (8) → 廢都 (9, now a battle point) → 65 → 66 → map at 9.
	_assert_eq(await _travel(map_scene, 7), "level", "寧靜之森 opens level 7")
	await _free(map_scene)
	await _play_chain(["battle_007.json", "story_064.json"])
	map_scene = await _boot_pending()
	map = map_scene.world_map_runtime
	_assert_eq(await _travel(map_scene, 8), "level", "菲納斯河畔 opens its story scene")
	await _free(map_scene)
	await _play_chain(["story_008.json"])
	map_scene = await _boot_pending()
	map = map_scene.world_map_runtime
	_assert_eq(MapRules.point_type(map.state, world_map, 9), "bmpmBattle", "STORY008 turned 廢都 into a battle point")
	_assert_eq(await _travel(map_scene, 9), "level", "廢都 opens level 9")
	await _free(map_scene)
	await _play_chain(["story_009.json", "story_065.json", "story_066.json"])
	map_scene = await _boot_pending()
	map = map_scene.world_map_runtime
	_assert_eq(int(map.current_point()), 9, "back at 廢都 (a town again)")
	_assert_eq(MapRules.point_type(map.state, world_map, 9), "bmpmTown", "STORY009 restored 廢都 as a town")
	# 帕尼西亞城 廢墟 (10): formal battle → victory (point 8 → event 901) → map at 10.
	_assert_eq(await _travel(map_scene, 10), "level", "廢墟 opens level 10")
	await _free(map_scene)
	await _play_chain(["battle_010.json"])
	map_scene = await _boot_pending()
	map = map_scene.world_map_runtime
	_assert_eq(MapRules.point_event(map.state, world_map, 8), 901, "winfail010's victory arms 菲納斯河畔 with the ambush 901")
	# Back to 菲納斯河畔 through 廢都 (a town: passing by, no stop) for the ambush.
	await _travel(map_scene, 9)
	if map.town_runtime != null:
		_confirm_through(map.town_runtime)
		map.town_runtime.leave()
		await process_frame
	_assert_eq(await _travel(map_scene, 8), "level", "菲納斯河畔 now opens the ambush 901")
	await _free(map_scene)
	await _play_chain(["battle_901.json"])
	map_scene = await _boot_pending()
	map = map_scene.world_map_runtime
	_assert_eq(int(((map.state.get("towns", {}) as Dictionary).get("6", {}) as Dictionary).get("exec_event", 0)), 25, "winfail901's victory arms 席達鎮 event 25")
	# 席達鎮 again: 25 → tavern 27 → 28 → 30 reveals 薛維斯港 (11) and track 10 (9–11).
	await _travel(map_scene, 7)
	await _travel(map_scene, 6)
	town = map.town_runtime
	_assert_true(town != null, "席達鎮 opens again")
	if town == null:
		return
	_confirm_through(town)
	town.select_entry(20)
	_confirm_through(town)
	_assert_true(_menu_entries(town).has(27), "the woman guest (27) sits in the tavern after the ambush")
	town.menu_pick(27)
	_confirm_through(town)
	town.menu_pick(28)
	_confirm_through(town)
	_assert_true(_menu_entries(town).has(30), "the fairy's talk (28) brings 女客人二 (30)")
	town.menu_pick(30)
	_confirm_through(town)
	town.menu_exit()
	town.leave()
	await process_frame
	await process_frame
	_assert_true(not MapRules.point_hidden(map.state, world_map, 11), "薛維斯港 (11) is revealed on the map")
	_assert_true(not MapRules.track_hidden(map.state, world_map, 10), "track 10 (9–11) is revealed")
	# Towards 薛維斯港: 6 → 7 → 8 (an encounter point now; the fixed dice roll none) → 9,
	# where event 30 armed 曼多力亞 with event 900: the confrontation (formal battle_900) opens.
	for point in [7, 8]:
		await _travel(map_scene, point)
		if CampaignProgress.has_pending():
			failures.append("unexpected hand-off on the way to the port at point %d: %s" % [point, str(CampaignProgress.pending.get("scenario_path", ""))])
			return
	_assert_eq(await _travel(map_scene, 9), "level", "曼多力亞 now opens the confrontation 900")
	await _free(map_scene)
	# 選擇一 (the first prompt row): 雷歐納德 kicks the soldier, the party leaves, no battle;
	# 曼多力亞 is a town again and the map stands at point 9.
	await _play_chain(["battle_900.json"])
	map_scene = await _boot_pending()
	map = map_scene.world_map_runtime
	_assert_eq(int(map.current_point()), 9, "back at 曼多力亞 after the confrontation")
	_assert_eq(MapRules.point_type(map.state, world_map, 9), "bmpmTown", "選擇一 restores 曼多力亞 as a town")
	_assert_eq(await _travel(map_scene, 11), "town", "薛維斯港 opens its town")
	town = map.town_runtime
	_assert_true(town != null, "薛維斯港 has a town runtime")
	if town == null:
		return
	_assert_eq(str(town.mode), "dialogue", "第一次到薛維斯港 (32) talks first")
	_confirm_through(town)
	_assert_true(town.menu_codes().has(41), "the harbour (41) is on the root menu")
	town.select_entry(41)
	_confirm_through(town)
	_assert_eq(str(town.mode), "sub_menu", "the harbour menu opens")
	_assert_true(_menu_entries(town).has(42), "the captain (42) waits at the harbour")
	town.menu_pick(42)
	_confirm_through(town)
	_assert_true(_menu_entries(town).has(48), "the captain's second talk (48) replaces the first")
	town.menu_pick(48)
	_confirm_through(town)
	_assert_eq(str(town.mode), "select", "the captain asks for a choice (teSelectInsertEvent)")
	town.choose(0)
	var guard := 0
	while is_instance_valid(town) and town.mode in ["dialogue", "delay"] and guard < 80:
		town.confirm()
		guard += 1
	await process_frame
	await process_frame
	# town_命運神殿 is big-map point 16 (towndef symbols); the captain's choice 51 charges
	# 500 gold, reveals the temple and sends the party there (teSetNextPlayLevelEvent
	# town_命運神殿,gameBigMapLevel — a move on the map, not a scene change).
	_assert_true(not MapRules.point_hidden(map.state, world_map, 16), "the ship reveals 命運神殿 (point 16)")
	_assert_eq(int(map.current_point()), 16, "the ship carries the party to 命運神殿 (point 16)")
	_assert_eq(int(map_scene.campaign_handoff["carry"]["loop"]["gold"]), 700, "the passage costs 500 gold (teCheckMoney)")
	steps.append("ship")
	await _free(map_scene)
