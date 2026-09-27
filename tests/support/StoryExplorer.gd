extends RefCounted

## Story-mode walk shared by tests/run_story_mode_explorer_tests.gd (formal battles through
## the force-win fixture) and tests/run_chapter_autoplay_tests.gd (formal battles really
## fought by the scored autoplay commander). From a campaign hand-off it walks the game the
## way a player in story mode would, without a hand-authored route — travels to every
## reachable big-map point, exhausts every town menu (dialogue confirmed, prompts answered
## with their first row, shops closed), plays every story scene it is handed (the first row
## of any prompt) and hands each formal battle to `play_formal_battle` — until the GameClear
## sequence appears or nothing new can be reached. Encounter dice are the runtime's own. The
## walk proves the registered scenes, map reveals and town chains connect through the
## product's own hand-offs; what a battle proves is the battle player's business.
##
## `play_formal_battle(explorer, scene) -> String` is awaited on a booted formal battle and
## answers "handoff" (the campaign's next scene is pending), "stuck", or "retry" (boot the
## same hand-off again: the explorer restores the pending hand-off it booted from and plays
## the scene once more without counting it twice). A formal battle whose result page enters
## the game-clear entry directly (CampaignProgress._enter_game_clear: no pending hand-off,
## last_handoff kind "game_clear") counts as GameClear, not as stuck.
##
## Coverage passes (tests/run_story_mode_explorer_tests.gd) reuse the walk with three knobs:
## `goal` ends a walk early, `prompt_last_row` takes the other row of every town prompt on its
## first sighting, `ending` overrides STORY057's over-score dispatch; `handoffs` records every
## hand-off the walk booted so a later pass can resume from a real walked state.

const RuntimeScene = preload("res://game/battle/scene/BattleSceneRuntime.tscn")
const CampaignProgress = preload("res://game/battle/runtime/CampaignProgress.gd")
const WorldMapRules = preload("res://game/world/WorldMapRules.gd")
const WorldScriptActions = preload("res://game/world/WorldScriptActions.gd")
const TownEventRules = preload("res://game/sim/TownEventRules.gd")
const EndingDispatchRules = preload("res://game/sim/EndingDispatchRules.gd")
const BattleForceWin = preload("res://tests/support/BattleForceWin.gd")

const WORLD_MAP_PATH := "res://content/imported/hsl/global/world_map/world_map.json"
const MAP_SCENE := "res://content/world/world_map_scene.json"
const GAME_CLEAR_PATH := "res://game/title/GameClearScreen.tscn"
const TOWNDEF_PATH := "res://content/imported/hsl/global/world_map/towndef.json"
const STORY_057 := "res://content/battles/story_057.json"
const STEP_BUDGET := 900
## Frame cap for a map travel / route reveal in flight (a script walk runs at the map's own
## 96 px/s; the explorer's own travels are near-instant).
const MAP_SETTLE_FRAMES := 900

const OUTCOME_HANDOFF := "handoff"
const OUTCOME_STUCK := "stuck"
const OUTCOME_RETRY := "retry"
const OUTCOME_GAME_CLEAR := "game_clear"
const OUTCOME_EXHAUSTED := "exhausted"
## The walk's `goal` held before the next hand-off was booted.
const OUTCOME_GOAL := "goal"
const ENDINGS := ["76", "77", "78"]

var tree: SceneTree
var play_formal_battle: Callable
var world_map: Dictionary = {}
var log_lines: Array[String] = []
var scenes_played: Array[String] = []
var towns_explored: Dictionary = {}
var game_clear_reached := false
var steps := 0
var outcome := ""
var requested_ending := ""
## Formal-battle replays the battle player asked for (OUTCOME_RETRY).
var retries := 0
## Prompts already answered once (option lists as keys): a repeat takes the last row
## (usually the "no" of a yes / no captain prompt) so transport loops end, and a
## repeated member prompt (the ceremony room) is declined.
var prompts_seen: Dictionary = {}
## Points arrived on, keyed by point and the event armed there at the time.
var arrived_keys: Dictionary = {}
## Optional shopper (town: Node, town_id: int) run on every shop the walk opens before it
## is closed (the chapter autoplay's tests/support/AutoplayShopping.gd); unset, shops just close.
var shopper: Callable = Callable()
var town_in_focus := 0
## Optional `goal(explorer, next_scenario_path) -> bool`, asked before each pending hand-off
## is booted; true ends the walk with OUTCOME_GOAL (the hand-off stays pending, unbooted).
var goal: Callable = Callable()
## True: a town prompt seen for the first time takes its last row instead of the first (the
## branch a first-row walk never takes); a repeat is answered as before.
var prompt_last_row := false
## "76" / "77" / "78" forces that finale at STORY057 (see inject_requested_ending);
## defaults to HSL_EXPLORER_ENDING.
var ending := OS.get_environment("HSL_EXPLORER_ENDING").strip_edges()
## Every hand-off booted, in order: {"after": file name of the scene played before it ("" at
## the start), "path": its scenario path, "handoff": a deep copy of the pending hand-off}.
var handoffs: Array[Dictionary] = []


func _init(scene_tree: SceneTree, battle_player: Callable) -> void:
	tree = scene_tree
	play_formal_battle = battle_player
	world_map = WorldMapRules.load_world_map(WORLD_MAP_PATH)


func note(line: String) -> void:
	log_lines.append(line)
	steps += 1


static func click() -> InputEventMouseButton:
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	return click


## The explorer's default start: the big map after the 歐姆村 battle with a fresh party
## (the battle's own world write, 歐姆村 exec event 9, applied by hand). HSL_EXPLORER_ENDING
## 76 / 77 / 78 starts at the STORY057 hand-off instead for finale QA.
static func start_after_ohm_village(gold: int = 5000) -> void:
	CampaignProgress.reset_campaign()
	var seeded: Dictionary = WorldScriptActions.ensure_state({}, CampaignProgress.load_campaign())
	var world: Dictionary = seeded["state"]
	world = TownEventRules.apply_script_town_actions(world, [{"name": "actSetTownExecEvent", "args": ["town_歐姆村", "9"]}], TownEventRules.load_towndef(TOWNDEF_PATH))["state"]
	var ending_mode := OS.get_environment("HSL_EXPLORER_ENDING").strip_edges()
	var initial_path := STORY_057 if ending_mode in ["76", "77", "78"] else MAP_SCENE
	CampaignProgress.pending = {"schema": CampaignProgress.SCHEMA, "scenario_path": initial_path, "carry": {"schema": "hsl_campaign_carry.v1", "units": {}, "loop": {"gold": gold}}, "from_scenario_id": "ohm_village_battle", "world": world}
	CampaignProgress.last_entry = {}


## The product's own start: the campaign's start_level (the prologue battle) with no carry,
## every later scene reached through the runtime's hand-offs.
static func start_at_campaign_start() -> void:
	CampaignProgress.reset_campaign()
	var campaign := CampaignProgress.load_campaign()
	CampaignProgress.pending = {"schema": CampaignProgress.SCHEMA, "scenario_path": CampaignProgress.first_scenario_path(campaign), "carry": {}, "from_scenario_id": "campaign_start", "world": {}}
	CampaignProgress.last_entry = {}


## Resumes from a hand-off an earlier walk recorded (`handoffs` / `handoff_into`): a fresh
## campaign whose pending hand-off is that walked state.
static func start_from_handoff(handoff: Dictionary) -> void:
	CampaignProgress.reset_campaign()
	CampaignProgress.pending = handoff.duplicate(true)
	CampaignProgress.last_entry = {}


## Walks from the pending hand-off until GameClear, exhaustion, a stuck scene or the step
## budget; returns the final outcome ("game_clear", "exhausted", "stuck", "goal" when `goal`
## held, "handoff" when the budget ran out). Sets `outcome`, `requested_ending`, `scenes_played`, `retries`.
func run() -> String:
	outcome = ""
	while steps < STEP_BUDGET and not game_clear_reached and CampaignProgress.has_pending():
		var path := str(CampaignProgress.pending.get("scenario_path", ""))
		if goal.is_valid() and goal.call(self, path):
			outcome = OUTCOME_GOAL
			break
		if path == GAME_CLEAR_PATH:
			scenes_played.append(path.get_file())
			note("scene: " + path.get_file())
			game_clear_reached = true
			outcome = OUTCOME_GAME_CLEAR
			CampaignProgress.pending = {}
			break
		if path == STORY_057:
			requested_ending = inject_requested_ending()
			if not requested_ending.is_empty():
				note("ending: " + requested_ending)
		var handoff: Dictionary = CampaignProgress.pending.duplicate(true)
		handoffs.append({"after": scenes_played.back() if not scenes_played.is_empty() else "", "path": path, "handoff": handoff})
		var scene = await boot_pending()
		if path == MAP_SCENE:
			outcome = await explore_map(scene)
		else:
			scenes_played.append(path.get_file())
			note("scene: " + path.get_file())
			outcome = await play_scene(scene)
			if outcome == OUTCOME_GAME_CLEAR:
				game_clear_reached = true
				await tree.process_frame
				await tree.process_frame
				var ending = tree.current_scene
				if ending != null and ending.has_method("summary") and str(ending.summary().get("schema", "")) == "hsl_game_clear_screen.v1":
					ending.queue_free()
				await tree.process_frame
		if is_instance_valid(scene):
			await free_scene(scene)
		if outcome == OUTCOME_RETRY:
			# The same battle boots again from the hand-off it came from; one scene entry.
			scenes_played.pop_back()
			retries += 1
			CampaignProgress.pending = handoff
			continue
		if outcome == OUTCOME_EXHAUSTED or outcome == OUTCOME_STUCK:
			break
	return outcome


## The first recorded hand-off into `path` booted right after the scene `after` ("" for any),
## {} when the walk never booted one.
func handoff_into(path: String, after: String = "") -> Dictionary:
	for record in handoffs:
		if str(record["path"]) == path and (after == "" or str(record["after"]) == after):
			return (record["handoff"] as Dictionary).duplicate(true)
	return {}


func inject_requested_ending() -> String:
	var requested := ending
	if requested not in ENDINGS:
		return ""
	var world_value: Variant = CampaignProgress.pending.get("world", {})
	if typeof(world_value) != TYPE_DICTIONARY:
		return ""
	var world: Dictionary = (world_value as Dictionary).duplicate(true)
	match requested:
		"76":
			world["over_score"] = {"1": 100000, "2": 0, "3": 0}
			world["over_flag"] = 0
		"77":
			world["over_score"] = {"1": 0, "2": 100000, "3": 0}
			world["over_flag"] = EndingDispatchRules.FLAG_FREE_ENEMY
		"78":
			world["over_score"] = {"1": 0, "2": 0, "3": 100000}
			world["over_flag"] = EndingDispatchRules.FLAG_ENEMY_JOB_UP
	CampaignProgress.pending["world"] = world
	return requested


func boot_pending() -> Node:
	var path := str(CampaignProgress.pending.get("scenario_path", ""))
	var scene = RuntimeScene.instantiate()
	scene.scenario_path = path
	scene.startup_mode = "product_opening"
	tree.root.add_child(scene)
	await tree.process_frame
	await tree.process_frame
	return scene


func free_scene(scene: Node) -> void:
	scene.queue_free()
	await tree.process_frame
	await tree.process_frame


## Plays a scene to its end; returns "handoff", "game_clear", "stuck" or (a formal battle's
## player's) "retry".
func play_scene(scene: Node) -> String:
	var coordinator = scene.opening_coordinator
	# A battle without a script coordinator (the prologue's own scene timeline) is formal too.
	if coordinator == null or not coordinator.story_mode:
		var battle_outcome: String = await play_formal_battle.call(self, scene)
		if battle_outcome == OUTCOME_STUCK and str(scene.campaign_progress.last_handoff.get("kind", "")) == "game_clear":
			return OUTCOME_GAME_CLEAR
		return battle_outcome
	coordinator.walk_pixels_per_second = 6400.0
	var frames := 0
	while coordinator.active and not coordinator.story_finished and frames < 9000 and not CampaignProgress.has_pending():
		if not (coordinator.summary().get("select_options", []) as Array).is_empty():
			coordinator.choose_select_option(0)
		elif scene.party_equipment_screen != null and scene.party_equipment_screen.active:
			scene.party_equipment_screen.close()  # actEnterStorageWindow: leave the party as it is
		elif str(coordinator.summary().get("current_event_kind", "")) in BattleForceWin.CLICK_THROUGH_KINDS:
			coordinator.handle_input(click())
		await tree.process_frame
		frames += 1
	for record in coordinator.summary().get("story_records", []):
		if str((record as Dictionary).get("kind", "")) == "game_clear":
			return OUTCOME_GAME_CLEAR
	if not CampaignProgress.has_pending() and coordinator.story_finished:
		var options: Array = coordinator.summary().get("end_card_options", [])
		if not options.is_empty():
			coordinator.select_end_card_option(0)
			coordinator.confirm_end_card_option()
		else:
			coordinator.handle_input(click())
		await tree.process_frame
		# A skipped finale's win section may play the ending film first (story_059):
		# a click skips it so the hand-off / GameClear follows.
		for _frame in range(60):
			if scene.get_node_or_null("StoryMovie") == null:
				break
			coordinator.handle_input(click())
			await tree.process_frame
		for record in coordinator.summary().get("story_records", []):
			if str((record as Dictionary).get("kind", "")) == "game_clear":
				return OUTCOME_GAME_CLEAR
	return OUTCOME_HANDOFF if CampaignProgress.has_pending() else OUTCOME_STUCK


## Confirms dialogue, answers prompts with their first row and closes shops until the
## town is back on a menu (or closed / handing off).
func drain(town: Node) -> void:
	var guard := 0
	while is_instance_valid(town) and guard < 200 and not CampaignProgress.has_pending():
		match str(town.mode):
			"dialogue":
				town.confirm()
			"select":
				var pending: Dictionary = town.run.get("pending", {})
				var options: Array = pending.get("options", [])
				var key := JSON.stringify(options)
				if prompts_seen.has(key):
					if str(pending.get("kind", "")) == "player_select":
						town.cancel_select()
					else:
						town.choose(options.size() - 1)
				else:
					prompts_seen[key] = true
					town.choose(options.size() - 1 if prompt_last_row else 0)
			"shop":
				if shopper.is_valid():
					shopper.call(town, town_in_focus)
				town.shop_close()
			_:
				return
		guard += 1


func entries(town: Node) -> Array:
	var codes: Array = []
	if typeof(town.run.get("pending")) == TYPE_DICTIONARY:
		for entry in (town.run["pending"] as Dictionary).get("entries", []):
			codes.append(int(entry["code"]))
	return codes


## Exhausts a town's menu tree once per (town, tree signature): every root entry, every
## sub-menu child, re-listing after each pick because events rewrite the tree.
func explore_town(town: Node, town_id: int) -> void:
	town_in_focus = town_id
	drain(town)
	var visited: Dictionary = {}
	var rounds := 0
	while is_instance_valid(town) and str(town.mode) == "menu" and rounds < 40 and not CampaignProgress.has_pending():
		rounds += 1
		var picked := false
		for code in town.menu_codes():
			if visited.has(code):
				continue
			visited[code] = true
			picked = true
			note("town %d: root %d" % [town_id, code])
			town.select_entry(code)
			drain(town)
			if CampaignProgress.has_pending() or not is_instance_valid(town):
				return
			if str(town.mode) == "sub_menu":
				var sub_visited: Dictionary = {}
				var sub_rounds := 0
				while str(town.mode) == "sub_menu" and sub_rounds < 40 and not CampaignProgress.has_pending():
					sub_rounds += 1
					var child_picked := false
					for child in entries(town):
						if sub_visited.has(child):
							continue
						sub_visited[child] = true
						child_picked = true
						note("town %d: sub %d" % [town_id, child])
						town.menu_pick(child)
						drain(town)
						if CampaignProgress.has_pending() or not is_instance_valid(town):
							return
						break
					if not child_picked:
						break
				if str(town.mode) == "sub_menu":
					town.menu_exit()
				drain(town)
			break
		if not picked:
			break
	if is_instance_valid(town) and str(town.mode) == "menu" and not CampaignProgress.has_pending():
		town.leave()
		await tree.process_frame
		if is_instance_valid(town):
			drain(town)


## Waits for the map's travel and route reveals in flight to finish (condition-driven,
## frame-capped), then one frame for the arrival's hand-off / town / card to settle.
func settle_map(map: Node) -> void:
	var frames := 0
	while map.traveling and frames < MAP_SETTLE_FRAMES:
		await tree.process_frame
		frames += 1
	await tree.process_frame
	frames = 0
	while bool(map.summary().get("reveal_busy", false)) and frames < MAP_SETTLE_FRAMES:
		await tree.process_frame
		frames += 1
	await tree.process_frame


## One travel step; returns the arrival kind.
func travel(map: Node, point_id: int) -> String:
	map.travel_pixels_per_second = 100000.0
	map.track_reveal_tick_seconds = 0.0001
	var record: Dictionary = map.select_point(point_id, "explorer")
	if str(record.get("status", "")) == "unreachable":
		return "unreachable"
	await settle_map(map)
	var arrivals: Array = map.summary().get("arrival_records", [])
	return str((arrivals[arrivals.size() - 1] as Dictionary).get("kind", "")) if not arrivals.is_empty() else ""


func dismiss_card(map: Node) -> void:
	if bool(map.summary().get("card_visible", false)):
		var key := InputEventKey.new()
		key.keycode = KEY_SPACE
		key.pressed = true
		map.handle_input(key)
		await tree.process_frame


func town_signature(state: Dictionary, point_id: int) -> String:
	var town_id := WorldMapRules.town_id_for_point(world_map, point_id)
	var town: Dictionary = (state.get("towns", {}) as Dictionary).get(str(town_id), {})
	return "%d:%s:%d" % [town_id, JSON.stringify(town.get("tree", {})), int(town.get("exec_event", 0))]


## What makes a point worth visiting now: a town whose menu tree / armed event we have
## not exhausted, or a point whose current event we have not yet arrived on.
func interesting(state: Dictionary, point_id: int) -> bool:
	if WorldMapRules.point_type(state, world_map, point_id) == "bmpmTown":
		return not towns_explored.has(town_signature(state, point_id))
	return not arrived_keys.has("%d:%d" % [point_id, WorldMapRules.point_event(state, world_map, point_id)])


## Shortest revealed path from here to the nearest interesting point ([] when none).
func path_to_interesting(state: Dictionary, here: int) -> Array:
	var previous: Dictionary = {here: 0}
	var queue: Array = [here]
	while not queue.is_empty():
		var point: int = queue.pop_front()
		if point != here and interesting(state, point):
			var path: Array = []
			var cursor := point
			while cursor != here:
				path.push_front(cursor)
				cursor = int(previous[cursor])
			return path
		for next in WorldMapRules.reachable_points(state, world_map, point):
			if not previous.has(next):
				previous[next] = point
				queue.append(next)
	return []


## Explores the map from the current point until a hand-off happens or nothing new is
## reachable; returns "handoff" or "exhausted".
func explore_map(scene: Node) -> String:
	var map = scene.world_map_runtime
	while steps < STEP_BUDGET:
		# A hand-off the map armed by itself — a script's actSetBMWalkToPoint arrival on
		# entering the map (STORY071 → 33 → 32 → 34 chain), a town's level request — is
		# taken before the explorer picks its own target. In the product the scene reloads
		# at once; here another hop's random encounter would overwrite the armed hand-off
		# and the visited point would never open its level again (`exhausted`, ~35%). A
		# script walk still travelling (96 px/s) gets to arrive first; selecting a point
		# meanwhile would kill its tween and the arrival would never fire.
		if map.traveling or bool(map.summary().get("reveal_busy", false)):
			await settle_map(map)
		if CampaignProgress.has_pending():
			return OUTCOME_HANDOFF
		var here: int = map.current_point()
		# The town we stand on, when its tree / armed event changed since we exhausted it.
		if WorldMapRules.point_type(map.state, world_map, here) == "bmpmTown" and map.town_runtime == null and interesting(map.state, here):
			var sig := town_signature(map.state, here)
			towns_explored[sig] = true
			note("map: reopen town at %d" % here)
			await travel(map, here)
			if CampaignProgress.has_pending():
				return OUTCOME_HANDOFF
			if map.town_runtime != null:
				await explore_town(map.town_runtime, WorldMapRules.town_id_for_point(world_map, here))
				if CampaignProgress.has_pending():
					return OUTCOME_HANDOFF
			continue
		var path: Array = path_to_interesting(map.state, here)
		if path.is_empty():
			return OUTCOME_EXHAUSTED
		var target: int = int(path[0])
		var event_key := "%d:%d" % [target, WorldMapRules.point_event(map.state, world_map, target)]
		var town_sig := town_signature(map.state, target) if WorldMapRules.point_type(map.state, world_map, target) == "bmpmTown" else ""
		note("map: %d -> %d" % [here, target])
		await travel(map, target)
		arrived_keys[event_key] = true
		if CampaignProgress.has_pending():
			return OUTCOME_HANDOFF
		if map.town_runtime != null:
			towns_explored[town_sig] = true
			await explore_town(map.town_runtime, WorldMapRules.town_id_for_point(world_map, target))
			if CampaignProgress.has_pending():
				return OUTCOME_HANDOFF
		await dismiss_card(map)
	return OUTCOME_EXHAUSTED


## Registered story scenes (campaign.json kind=story) whose file names were not played.
func unreached_story_scenes() -> Array:
	var registered: Array = []
	var campaign := CampaignProgress.load_campaign()
	for key in campaign.get("battles", {}):
		if str(campaign["battles"][key].get("kind", "")) == "story":
			registered.append(str(campaign["battles"][key].get("scenario", "")).get_file())
	return registered.filter(func(name): return not scenes_played.has(name))
