extends "res://tests/capture_support_magic_review.gd"
## Actual Wait -> AI move -> owned support spell -> EXP -> player handoff.
## Uses inherited input events/cleanup; no result assignment or clock acceleration.
const run_ai_support_tests = preload("res://tests/run_ai_support_tests.gd")
const DEST := "res://ignored/ally-support-review/"
var observations: Dictionary = {}
var exp_events: Array = []
var cues: Dictionary = {}
var sounds: Dictionary = {}
var supported_skill := ""


func run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Ally support review requires a rendered built-in-display window")
		quit(2)
		return
	root.title = "HSL Ally Support Review"
	root.size = Vector2i(640,480)
	root.position = DisplayServer.screen_get_position(root.current_screen) + Vector2i(60,80)
	DirAccess.make_dir_recursive_absolute(DEST)
	create_timer(210).timeout.connect(func(): push_error("ALLY_SUPPORT_REVIEW_TIMEOUT"); quit(2))
	var names: Array = ["heal_move", "greater_move", "life_move", "cure_move", "next_patient", "enemy_heal", "no_mp", "silence", "item_move", "item_no_mp"]
	if not OS.get_cmdline_user_args().is_empty(): names = Array(OS.get_cmdline_user_args())
	for name in names:
		mode = name
		await prepare_case()
		await play_case()
		await close_scene()
		if not failures.is_empty(): break
	FileAccess.open(DEST + "receipt.json",FileAccess.WRITE).store_string(JSON.stringify({
		"fixture":true,"native_execution":false,"real_control_events":true,"normal_clock":Engine.time_scale,
		"input":"Inherited Viewport mouse/key/scroll events; normal Runtime movement, skill and aftermath clocks",
		"overrides":"Four source-rendered participants plus a controllable initial sentinel; explicit source water grants on 001, synthetic supported growth/100MP, fixed coordinates/speeds and matching three-cell move_point/move_range, low-HP patients and no reinforcements. Actual scene WRD retained. Aid/use ratios100 for reproducible visible success; cure includes two poisoned friends and preserves recipient silence. Next-patient puts the first friend beyond movement+heal reach. Enemy route changes adapted side. Item routes author exactly one medicine241. No combat RNG replacement, result assignment, time acceleration, or default first-battle grants/stock changes.",
		"screen":root.current_screen,"window_position":root.position,"window_size":root.size,"routes":routes,"failures":failures},"  "))
	print("ALLY_SUPPORT_RENDER_", "PASS" if failures.is_empty() else "FAIL", " routes=",routes.size())
	quit(0 if failures.is_empty() else 1)


func prepare_case() -> void:
	observations = {}
	exp_events = []
	cues = {"release":0,"impact":0}
	sounds = {}
	supported_skill = {"greater_move":run_ai_support_tests.GREATER,"life_move":run_ai_support_tests.LIFE,"cure_move":run_ai_support_tests.CURE}.get(mode,run_ai_support_tests.HEAL)
	scene = load("res://game/battle/scene/BattleSceneRuntime.tscn").instantiate()
	scene.scenario_path = BattleFixture.PATH; scene.startup_mode = "dev_first_control"
	root.add_child(scene)
	current_scene = scene
	scene.start_dev_first_control_harness()
	scene.set_process(false)
	await create_timer(0.2).timeout
	scene.get_node("BattleMusic").stop()
	var loop := run_ai_support_tests.fixture(supported_skill)
	loop["tiles"] = scene.play_loop["tiles"]
	loop["map_size"] = scene.play_loop["map_size"]
	var owner := BattlePlayLoop.unit_ref(loop,"leonard")
	owner["exp"] = 99
	var patient := BattlePlayLoop.unit_ref(loop,"enemy023_1")
	var other := BattlePlayLoop.unit_ref(loop,"enemy021_2")
	other["live_speed"] = 80
	other["player_commandable"] = true
	other["battle_actor_role"] = BattlePlayLoop.ROLE_PLAYER
	if mode == "cure_move":
		for unit in [patient,other]: unit.merge(BattlePlayLoop.StatusEffectRules.apply(unit,"poison",2,10)["changes"],true)
		patient.merge(BattlePlayLoop.StatusEffectRules.apply(patient,"no_magic",2)["changes"],true)
	if mode == "next_patient":
		patient["coord"] = Vector2i(16,8)
		other["coord"] = Vector2i(10,11)
	if mode == "enemy_heal":
		owner["battle_actor_role"] = BattlePlayLoop.ROLE_ENEMY
		BattlePlayLoop.unit_ref(loop,"enemy021_1").merge({"hp":4,"coord":Vector2i(13,8)},true)
	if mode == "no_mp": owner["mp"] = 0
	if mode == "silence": owner.merge(BattlePlayLoop.StatusEffectRules.apply(owner,"no_magic",2)["changes"],true)
	if mode.begins_with("item_"):
		patient["coord"] = Vector2i(12,8)
		owner["inventory"][0] = 241
		if mode == "item_no_mp": owner["mp"] = 0
		else: TestSuite.own(loop, "skill_book")["actors"]["001"]["supported_initial_ids"] = []
	if mode == "heal_move":
		patient["growth_profile"] = owner["growth_profile"].duplicate(true)
		patient["growth_profile"]["source"]["hit_point"] = 100
		patient["combat_profile"].merge({"mind":20,"live_magic_attack":100},true)
		patient["mp"] = 100
		patient["max_mp"] = 100
		patient["exp"] = 99
		TestSuite.own(loop, "skill_book")["actors"][patient["actor_id"]]["supported_initial_ids"] = [run_ai_support_tests.HEAL]
	var initial := BattlePlayLoop.unit(scene.play_loop,"enemy024_1")
	initial.merge({"id":"review-initial","coord":Vector2i(7,8),"hp":100,"max_hp":100,"player_commandable":true,"battle_actor_role":BattlePlayLoop.ROLE_PLAYER,"live_speed":110,"inventory":[0,0,0,0,0,0,0,0]},true)
	loop["units"].append(initial)
	loop["turn_queue"] = BattlePlayLoop.CoreTurnQueue.rebuild(loop["units"])
	scene.apply_loop(BattlePlayLoop.return_to_player(loop,"review-initial"), "test")
	for actor in scene.actors_root.get_children(): scene.actors_root.remove_child(actor); actor.queue_free()
	scene.unit_grid_coords.clear()
	for unit in loop["units"]: unit["grid_coord"] = unit["coord"]
	scene.resume_turn_presentation()
	scene.center_camera_on_grid(Vector2i(11,8))
	var view = scene.get_node("BattlePresentation")
	view.experience_presented.connect(func(growth):exp_events.append(growth.duplicate(true)))
	view.cutin.released.connect(func(_s,_a,_d,_c):cues["release"]+=1)
	view.cutin.impact.connect(func(_s,_a,_d,_c):cues["impact"]+=1)
	scene.set_process(true)
	await create_timer(0.3).timeout


func play_case() -> void:
	var before: Dictionary = scene.play_loop.duplicate(true)
	var target_id: String = "enemy021_2" if mode == "next_patient" else "enemy021_1" if mode == "enemy_heal" else "enemy023_1"
	await shot("before")
	await click(scene.action_menu.get_node("WaitCommand"))
	await wait_for("enemy023_1")
	var action: Dictionary = scene.play_loop.get("last_ai_action",{}).duplicate(true)
	var owner := BattlePlayLoop.unit(scene.play_loop,"leonard")
	if mode in ["no_mp","silence"]:
		check(not action.has("skill_id") and exp_events.is_empty() and cues["impact"] == 0, "unavailable magic cannot fabricate a support transaction or EXP")
		check(owner["mp"] == BattlePlayLoop.unit(before,"leonard")["mp"] and owner["exp"] == 99, "support rejection preserves resources and prior EXP")
	elif mode.begins_with("item_"):
		check(action.get("kind") == "move_then_item" and action.get("target_id") == target_id, "actual Wait produces moving assistance with the carried medicine")
		check(observations.has("moving") and observations.has("item") and cues["impact"] == 0 and exp_events.is_empty(), "item feedback follows arrival and uses its own transaction")
		check(owner["inventory"][0] == 0 and owner["mp"] == BattlePlayLoop.unit(before,"leonard")["mp"] and owner["exp"] == 99, "one medicine consumed with no phantom MP or EXP")
		check(BattlePlayLoop.unit(scene.play_loop,target_id)["hp"] == 44, "actual item feedback agrees with the healed patient")
		check(sounds.has(scene.ui_sounds["use_item"]["res_path"]), "use-item sound mixer playback advances once after arrival")
	else:
		check(action.get("skill_id") == supported_skill and action.get("kind") == "move_then_attack", "Wait commits exactly the intended moved support spell")
		check(action.get("ai_skill_decision",{}).get("source") == "original_ai_support", "actual action uses the ally planner")
		check(action.get("ai_skill_decision",{}).get("attempts",[{}]).back().get("primary_target_id") == target_id, "original scan selects the expected reachable patient")
		check(observations.has("moving") and observations.has("casting") and observations.has("impact") and observations.has("experience"), "normal clock exposes movement, cast, impact and final EXP")
		check(cues == {"release":1,"impact":1} and exp_events.size() == 1 and exp_events[0] == action.get("experience"), "one release, one impact and one final support award")
		check(action["resource_payment"]["after"] == 100 - int(BattlePlayLoop.skill_fields(before,supported_skill)["expend"]), "exactly one source MP fee")
		check(not sounds.is_empty(), "source audio mixer playback advances during the actual cast")
		if mode == "cure_move":
			check(action["affected_targets"].size() == 2 and BattlePlayLoop.unit(scene.play_loop,"enemy023_1")["status_counters"] == {"poison":0,"paralysis":0,"no_magic":2}, "moving area cure clears both friends but leaves silence and recipient turn intact")
		else:
			check(BattlePlayLoop.unit(scene.play_loop,target_id)["hp"] > BattlePlayLoop.unit(before,target_id)["hp"], "the selected ally's actual health improves")
		check(scene.play_loop["last_combat"]["sequence"] == action["sequence"], "playback never repeats the committed action")
	check(scene.play_loop["turn_queue"]["index"] == 2 and scene.play_loop["last_ai_actions"].size() == 1, "initial Wait plus one AI action reaches the precise next player")
	await shot("handoff")
	var first_award := {"level":owner["level"],"exp":owner["exp"],"pending_points":owner["pending_stat_points"]}
	var second_receipt := {}
	if mode == "heal_move":
		await click(scene.action_menu.get_node("MagicCommand"))
		await click(scene.magic_panel.choices[run_ai_support_tests.HEAL])
		await point(scene.grid_cell_center_to_logical_position(BattlePlayLoop.unit(scene.play_loop,"enemy021_2")["coord"]))
		second_receipt = scene.play_loop["last_attack"].duplicate(true)
		await wait_for("enemy021_2")
		var patient := BattlePlayLoop.unit(scene.play_loop,"enemy023_1")
		check(second_receipt.get("attacker_id") == "enemy023_1" and second_receipt.has("experience") and exp_events.size() == 2, "next participant's real cast earns a separate final EXP award")
		check(patient["level"] > 1 and patient["pending_stat_points"] > 0, "second healer retains its own unspent growth")
		owner = BattlePlayLoop.unit(scene.play_loop,"leonard")
		check(first_award == {"level":owner["level"],"exp":owner["exp"],"pending_points":owner["pending_stat_points"]}, "later support neither reallocates nor repeats the prior healer's EXP")
		await shot("second-handoff")
	var inspected := "enemy021_2" if mode == "heal_move" else target_id
	if inspected == scene.selected_unit_id: await click(scene.action_menu.get_node("StatusCommand"))
	else: await point(scene.grid_cell_center_to_logical_position(BattlePlayLoop.unit(scene.play_loop,inspected)["coord"]))
	check(scene.status_panel.visible, "support recipient can be inspected through normal controls")
	await shot("status")
	routes.append({"mode":mode,"action":action,"owner":compact(owner),"growth":first_award,"second_receipt":second_receipt,
		"observations":observations,"cues":cues.duplicate(true),"sounds":sounds.duplicate(true),"experience_events":exp_events.duplicate(true),
		"next_actor":scene.selected_unit_id,"turn_index":scene.play_loop["turn_queue"]["index"]})


func wait_for(id: String) -> void:
	for _attempt in range(1000):
		var view = scene.get_node("BattlePresentation")
		var actor = scene.actor_node_for_unit("leonard")
		if actor != null and actor.is_moving() and not observations.has("moving"):
			observations["moving"] = true
			check(not scene.action_menu.visible and not view.cutin.busy() and not view.item_feedback_busy(), "AI movement finishes before the effect or successor controls")
			await shot("moving")
		if view.item_feedback_busy():
			check(not scene.has_actor_motion() and not scene.action_menu.visible, "item feedback holds successor controls after movement")
			if scene.ui_audio.playing and scene.ui_audio.get_playback_position() > 0: sounds[scene.ui_audio.stream.resource_path] = true
			if not observations.has("item"):
				observations["item"] = true
				await shot("item")
		if view.cutin.busy():
			if not observations.has("casting"):
				observations["casting"] = true
				check(not scene.has_actor_motion() and not scene.action_menu.visible, "cast starts from settled actor position")
				await shot("casting")
			for player in view.cutin.skill_effects.sounds:
				if player.playing and player.get_playback_position() > 0: sounds[player.stream.resource_path] = true
			if view.cutin.clips[0]["impact_emitted"] and not observations.has("impact"):
				observations["impact"] = true
				check(view.status_feedback.get_child_count() > 0 and not view.aftermath.reward_label.visible, "actual support feedback precedes EXP")
				await shot("impact")
		if view.aftermath.reward_label.visible and not observations.has("experience"):
			observations["experience"] = true
			check(not view.cutin.busy() and not scene.action_menu.visible, "final support EXP waits for all particles")
			await shot("experience")
		if scene.growth_panel.visible:
			await shot("growth")
			scene.growth_panel.hide() # harness skip seam
		if scene.selected_unit_id == id and scene.action_menu.is_visible_in_tree() and not scene.ai_playback_active and not view.combat_busy(scene.play_loop) and not scene.action_menu.is_expanding(): return
		await create_timer(0.025).timeout
	check(false,"bounded AI support playback reaches " + id)


func shot(label: String) -> void:
	await process_frame
	RenderingServer.force_draw(false)
	check(root.get_texture().get_image().save_png(DEST + mode + "-" + label + ".png") == OK,"capture " + label)
