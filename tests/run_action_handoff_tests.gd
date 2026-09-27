extends SceneTree
const TestSuite = preload("res://tests/support/TestSuite.gd")
const Loop = preload("res://game/battle/scene/BattlePlayLoop.gd")
const Queue = preload("res://game/sim/CoreTurnQueue.gd")
const BattleFixture = preload("res://tests/support/BattleFixture.gd")
const BattleOutcome = preload("res://game/sim/BattleOutcome.gd")
var failures: Array[String] = []
var checks := 0


func _initialize() -> void:
	call_deferred("run")


func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures.append(label)
		push_error(label)


func scene_fixture(next_player: bool = true, wrap: bool = false) -> Node:
	var scene = load("res://game/battle/scene/BattleSceneRuntime.tscn").instantiate()
	scene.scenario_path = BattleFixture.PATH; scene.startup_mode = "dev_first_control"
	root.add_child(scene)
	scene.start_dev_first_control_harness()
	scene.set_process(false)
	TestSuite.stop_audio(scene.get_node("BattleMusic"))
	var actor := Loop._unit(scene.play_loop,"leonard")
	actor["hp"] = 10
	actor["inventory"] = [241,241,241,246,0,0,0,0]
	actor["live_speed"] = 1 if wrap else 30
	var ally := Loop._unit(scene.play_loop,"enemy023_1")
	# Runtime now initializes this NPC's immutable birth layer. Author the fixture
	# in the base source and use the same refresh as equipment/EXP, not stale live
	# values that correctly fail a physical exchange's consistency preflight.
	ally["growth_profile"]["source"]["speed"] += 29 - int(ally["live_speed"])
	ally.merge(Loop.ProgressionRules.refresh_growth_stats(ally,scene.play_loop["equipment_items"]),true)
	ally["coord"] = actor["coord"] + Vector2i.RIGHT
	ally["player_commandable"] = next_player
	ally["battle_actor_role"] = Loop.ROLE_PLAYER if next_player else Loop.ROLE_FRIENDLY
	ally["inventory"] = [0,0,0,0,0,0,0,0]
	scene.play_loop["turn_queue"] = Queue.rebuild(scene.play_loop["units"])
	for index in range(scene.play_loop["turn_queue"]["slots"].size()):
		if scene.play_loop["turn_queue"]["slots"][index]["id"] == "leonard":
			scene.play_loop["turn_queue"]["index"] = index
	scene.apply_loop(Loop.select_player_unit(scene.play_loop,"leonard"), "test")
	scene.interaction_state = "action_menu"
	scene.ai_playback_active = false
	return scene


func run() -> void:
	budget_cases()
	await combined_actions()
	for next_player in [true,false]:
		for wrap in [false,true]:
			for operation in ["wait","use","give"]:
				var scene = scene_fixture(next_player,wrap)
				var before: Dictionary = scene.play_loop.duplicate(true)
				var expected: Dictionary
				if operation == "wait":
					expected = Loop.choose_command(before,"wait")
					scene.menus.choose_command("wait")
				else:
					scene.menus.choose_command("item")
					scene.item_panel.menu._process(0.25)
					if operation == "use":
						expected = Loop.use_item(before,"241","leonard",0)
						scene.item_panel.menu.get_node("UseCommand").pressed.emit()
						scene.item_panel.rows.get_child(0).pressed.emit()
						scene.item_panel.target_buttons["leonard"].pressed.emit()
					else:
						var started := Loop.begin_give(before)
						var accepted := Loop.confirm_give(started,"enemy023_1",0,241,0,0,started["item_revision"])
						expected = Loop.finish_give(accepted,accepted["item_revision"])
						scene.item_panel.menu.get_node("GiveCommand").pressed.emit()
						scene.item_panel.target_buttons["enemy023_1"].pressed.emit()
						scene.item_panel.give_view.source_buttons[0].pressed.emit()
						scene.item_panel.give_view.destination_buttons[0].pressed.emit()
						scene.item_panel.confirm_button.pressed.emit()
						scene.item_panel.give_view.finish_requested.emit()
				var label := "%s player=%s wrap=%s" % [operation,next_player,wrap]
				check(scene.play_loop == expected,"scene uses exactly one settled rules result: " + label)
				check(Queue.current(scene.play_loop["turn_queue"])["id"] == "enemy023_1","immediate next actor is not skipped: " + label)
				check(scene.ai_playback_active == not next_player,"presentation follows actual next actor control: " + label)
				check(scene.interaction_state == expected["interaction"],"scene interaction mirrors final PlayLoop: " + label)
				check(scene.play_loop["turn_queue"]["round"] == (1 if wrap else 0),"one wrap at most: " + label)
				var settled_state: Dictionary = scene.play_loop.duplicate(true)
				scene.resume_turn_presentation()
				scene.resume_turn_presentation()
				check(scene.play_loop == settled_state,"repeated presentation cannot mutate the successor: " + label)
				if operation == "use":
					var settled: Dictionary = scene.play_loop.duplicate(true)
					scene.menus.use_inventory_item("241","leonard")
					check(scene.play_loop == settled,"closed Use callback cannot affect the successor")
				scene.queue_free()
				await process_frame
	for command in ["attack","special"]:
		for next_player in [true,false]:
			for moved in [false,true]:
				for missed in [false,true]:
					await exhausted_presentation(command,next_player,moved,missed)
	await rejected_offense_cases()
	await rejected_use_case()
	failures.append_array(await TestSuite.settle_audio_before_quit(self, 0.3))
	print("ACTION_HANDOFF_TESTS_", "PASS" if failures.is_empty() else "FAIL", " checks=", checks)
	quit(0 if failures.is_empty() else 1)


func budget_cases() -> void:
	var loop := BattleFixture.loop()
	for index in range(loop["turn_queue"]["slots"].size()):
		if loop["turn_queue"]["slots"][index]["id"] == "leonard":
			loop["turn_queue"]["index"] = index
	loop = Loop.select_player_unit(loop,"leonard")
	for moved in [false,true]:
		for attacked in [false,true]:
			var before := loop.duplicate(true)
			before["moved_this_action"] = moved
			before["attacked_this_action"] = attacked
			var expected := Loop.begin_wait_resolution(before) if attacked else before
			var actual := Loop.finish_exhausted_action(before)
			check(actual == expected,"completed offense ends the action with or without preceding movement")
			check(Loop.finish_exhausted_action(actual) == actual,"repeated exhaustion completion is inert for the successor")
	var selecting := Loop.choose_command(loop,"move")
	check(Loop.finish_exhausted_action(selecting) == selecting,"selection alone cannot exhaust an actor")
	var cancelled := Loop.cancel_interaction(selecting)
	check(cancelled["turn_queue"] == loop["turn_queue"] and cancelled["units"] == loop["units"],"Move selection cancellation consumes neither actor nor inventory")
	var give := Loop.begin_give(loop)
	check(Loop.finish_exhausted_action(give) == give,"Give session is not a completed action")
	var terminal := loop.duplicate(true)
	terminal["battle_outcome"] = BattleOutcome.VICTORY_SCRIPT
	terminal["moved_this_action"] = true
	terminal["attacked_this_action"] = true
	check(Loop.finish_exhausted_action(terminal) == terminal,"terminal completion cannot advance any actor")


func exhausted_presentation(command: String, next_player: bool, moved: bool, missed: bool) -> void:
	var scene = scene_fixture(next_player)
	var actor := Loop._unit(scene.play_loop,"leonard")
	# Native default counter/critical rates now execute with the zero-draw fixture.
	# Keep this handoff case nonterminal while retaining the whole counter clip.
	actor["hp"] = 100
	actor["max_hp"] = 500
	actor["stamina"] = 60
	var enemy := Loop._unit(scene.play_loop,"enemy021_1")
	enemy["coord"] = actor["coord"] + Vector2i.UP
	enemy["hp"] = 100
	enemy["max_hp"] = 100
	fixture_defense(enemy,scene.play_loop)
	if missed:
		actor["combat_profile"]["live_hit_ratio"] = 0
		enemy["combat_profile"]["avoid_hit_ratio"] = 100
		TestSuite.own(scene.play_loop, "skill_book")["skills"]["special:magicOTHER:magicCode01"]["fields"]["hit_ratio"] = 0
	scene.play_loop["moved_this_action"] = moved
	scene.apply_loop(scene.play_loop, "test")
	scene.menus.choose_command(command)
	if command == "special": scene.menus._choose_magic("special:magicOTHER:magicCode01")
	scene.apply_loop(Loop.attack_target(scene.play_loop,enemy["id"],func(n): return n - 1 if missed else 0), "test")
	scene.finish_attack_attempt()
	var resolved: Dictionary = scene.play_loop.duplicate(true)
	var expected := Loop.begin_wait_resolution(resolved)
	check(Loop.action_exhausted(resolved),"accepted offensive action exhausts regardless of hit/movement: " + command)
	check(Loop.choose_command(resolved,"move") == resolved,"resolved offense cannot reopen movement selection: " + command)
	var view = scene.get_node("BattlePresentation")
	view.cutin.set_process(false)
	scene._process(0)
	check(scene.play_loop == resolved,"exhaustion waits for the map cue: " + command)
	scene._process(view.attack_cue.duration)
	check(view.cutin.busy() and scene.play_loop == resolved,"exhaustion waits for the entire cut-in: " + command)
	var clip_count := 0
	while view.cutin.busy() and clip_count < 2:
		view.cutin._process(100)
		clip_count += 1
		check(scene.play_loop == resolved,"each primary/counter presentation remains read-only")
	check(clip_count == (2 if not resolved["last_attack"].get("counter",{}).is_empty() else 1),"all committed strike clips finish before handoff")
	scene._process(0)
	if not missed:
		check(view.aftermath.reward_label.visible and scene.play_loop == resolved,"earned map EXP precedes successor dispatch: " + command)
		for _job in range(view.aftermath.jobs.size()):
			if not view.aftermath.busy(): break
			scene._process(0)
			check(scene.play_loop == resolved, "every queued player/NPC reward keeps the same settled action pending")
			scene._process(view.aftermath.REWARD_SECONDS)
	check(scene.play_loop == expected,"completed presentation hands off exactly once: " + command)
	check(Queue.current(scene.play_loop["turn_queue"])["id"] == "enemy023_1","exhaustion preserves the immediate successor: " + command)
	check(scene.ai_playback_active == not next_player,"exhaustion dispatches by the successor's control: " + command)
	var after: Dictionary = scene.play_loop.duplicate(true)
	scene._process(0)
	check(scene.play_loop == after,"next frame does not repeat exhausted handoff: " + command)
	scene.queue_free()
	await process_frame


func rejected_use_case() -> void:
	var scene = scene_fixture()
	var actor := Loop._unit(scene.play_loop,"leonard")
	actor["hp"] = actor["max_hp"]
	scene.menus.choose_command("item")
	scene.item_panel.menu._process(0.25)
	scene.item_panel.menu.get_node("UseCommand").pressed.emit()
	scene.item_panel.rows.get_child(0).pressed.emit()
	var before: Dictionary = scene.play_loop.duplicate(true)
	check(not scene.item_panel.target_buttons["leonard"].disabled,"full-HP Use stays selectable (0x44492a..0x4449b6 has no HP check)")
	scene.menus.use_inventory_item("241","enemy021_1")
	check(scene.play_loop == before and not scene.ai_playback_active,"failed Use (enemy target, no 0x10000) does not start a turn transition")
	scene.item_panel.cancel()
	scene.menus.use_inventory_item("241","leonard")
	check(scene.play_loop == before,"cancelled Use cannot settle via an old callback")
	scene.queue_free()
	await process_frame


func rejected_offense_cases() -> void:
	var scene = scene_fixture()
	var original: Dictionary = scene.play_loop.duplicate(true)
	Loop._unit(original,"leonard")["stamina"] = 60
	Loop._unit(original,"enemy021_1")["coord"] = Loop.unit(original,"leonard")["coord"] + Vector2i.UP
	for command in ["attack","special"]:
		var selected := Loop.choose_command(original,command)
		if command == "special": selected = Loop.choose_special(selected,"special:magicOTHER:magicCode01")
		var cancelled := Loop.cancel_interaction(selected)
		for key in ["units","turn_queue","pending_move","moved_this_action","attacked_this_action"]:
			check(cancelled[key] == original[key],"offense selection cancellation preserves " + key)
		check(not Loop.action_exhausted(cancelled),"cancelled offense does not finish the actor")
		for reason in ["missing","friendly","far","dead_target","dead_actor","wrong_turn","enemy_actor","stamina"]:
			if reason == "stamina" and command != "special": continue
			var invalid := selected.duplicate(true)
			var target := "enemy021_1"
			match reason:
				"missing": target = "absent"
				"friendly": target = "enemy023_1"
				"far": Loop._unit(invalid,target)["coord"] = Vector2i.ZERO
				"dead_target": Loop._unit(invalid,target)["hp"] = 0
				"dead_actor": Loop._unit(invalid,"leonard")["hp"] = 0
				"wrong_turn": invalid["turn_queue"]["index"] += 1
				"enemy_actor": Loop._unit(invalid,"leonard")["player_commandable"] = false
				"stamina": Loop._unit(invalid,"leonard")["stamina"] = 0
			var rejected := Loop.attack_target(invalid,target,func(_n):
				check(false,"rejected offense must not consume random draws")
				return 0)
			check(not rejected["last_attack_reject"].is_empty(),"rejected offense reports reason: " + reason)
			if invalid.has("last_attack_reject"):
				rejected["last_attack_reject"] = invalid["last_attack_reject"]
			else:
				rejected.erase("last_attack_reject")
			check(rejected == invalid,"failed offense changes no gameplay state: " + reason)
			check(not Loop.action_exhausted(rejected),"failed offense does not exhaust action: " + reason)
	scene.queue_free()
	await process_frame


func moved_once(loop: Dictionary) -> Dictionary:
	var origin: Vector2i = Loop.unit(loop,"leonard")["coord"]
	var selected := Loop.choose_command(loop,"move")
	var destinations: Array = Loop.movement_cells(selected,"leonard").filter(func(cell): return absi(cell.x-origin.x)+absi(cell.y-origin.y)==1)
	check(not destinations.is_empty(),"combination fixture has a real legal move")
	if destinations.is_empty(): return loop
	return Loop.move_unit_to(selected,destinations[0])


func combined_actions() -> void:
	var scene = scene_fixture()
	var base: Dictionary = scene.play_loop.duplicate(true)
	Loop._unit(base,"leonard")["stamina"] = 60
	Loop._unit(base,"leonard")["hp"] = 100
	Loop._unit(base,"leonard")["max_hp"] = 500
	base = Loop.select_player_unit(base,"leonard")
	for moved in [false,true]:
		for operation in ["attack","special","use","wait","give","same_give","empty_give","drop","equip"]:
			var before := moved_once(base) if moved else base.duplicate(true)
			var actor := Loop._unit(before,"leonard")
			var ally := Loop._unit(before,"enemy023_1")
			var enemy := Loop._unit(before,"enemy021_1")
			ally["coord"] = actor["coord"] + Vector2i.RIGHT
			ally["inventory"] = [241,246,0,0,0,0,0,0]
			enemy["coord"] = actor["coord"] + Vector2i.UP
			enemy["hp"] = 100
			enemy["max_hp"] = 100
			fixture_defense(enemy,before)
			var initial := before.duplicate(true)
			var after := before.duplicate(true)
			var consumed: bool = operation in ["attack","special","use","wait","give"]
			match operation:
				"attack", "special":
					after = Loop.choose_command(after,operation)
					if operation == "special": after = Loop.choose_special(after,"special:magicOTHER:magicCode01")
					after = Loop.attack_target(after,"enemy021_1",func(_n): return 0)
					check(after["turn_queue"] == before["turn_queue"],"offense holds its owner until presentation is complete")
					check(Loop.cancel_pending_move(after) == after,"resolved offense cannot undo its position")
					after = Loop.finish_exhausted_action(after)
				"use": after = Loop.use_item(after,"241","leonard",0)
				"wait": after = Loop.choose_command(after,"wait")
				"give", "same_give", "empty_give":
					after = Loop.begin_give(after)
					if operation != "empty_give":
						var slot := 0 if operation == "same_give" else 2
						var returned := 241 if slot == 0 else 0
						after = Loop.confirm_give(after,"enemy023_1",0,241,slot,returned,after["item_revision"])
						var accepted := after.duplicate(true)
						check(Loop.confirm_give(after,"enemy023_1",0,241,slot,returned,after["item_revision"]-1) == accepted,"stale Give cannot mutate a compressed duplicate slot")
					check(after["turn_queue"] == before["turn_queue"],"Give never advances before session exit")
					after = Loop.finish_give(after,after["item_revision"])
				"drop": after = Loop.discard_item(after,"241",0)
				"equip": after = Loop.change_equipment(after,"head",-1,0)
			var label := "%s moved=%s" % [operation,moved]
			check(before == initial,"input remains immutable: " + label)
			check(Loop.unit(after,"leonard")["coord"] == actor["coord"],"command retains its settled coordinate: " + label)
			check(after["turn_queue"]["round"] == before["turn_queue"]["round"],"non-tail completion does not create a round: " + label)
			check(after["turn_queue"]["slots"].map(func(s): return [s["id"],s["live_speed"]]) == before["turn_queue"]["slots"].map(func(s): return [s["id"],s["live_speed"]]),"command cannot reorder the current queue: " + label)
			if consumed:
				check(after["selected_unit_id"] == "enemy023_1" and Queue.current(after["turn_queue"])["id"] == "enemy023_1","exact next ally retains control: " + label)
				check(not after["pending_move"] and not after["attacked_this_action"] and not after["moved_this_action"],"successor receives fresh action flags: " + label)
				check(not after["turn_queue"]["slots"][0]["action_ready"] and after["turn_queue"]["slots"][1]["action_ready"],"only the completing owner is marked spent: " + label)
				check(Loop.finish_exhausted_action(after) == after,"repeated completion preserves successor: " + label)
			else:
				check(after["selected_unit_id"] == "leonard" and after["turn_queue"] == before["turn_queue"],"free operation keeps owner and ready slots: " + label)
				check(after["pending_move"] == moved and after["moved_this_action"] == moved,"free operation preserves movement flags: " + label)
				if moved:
					var restored := Loop.cancel_pending_move(after)
					check(restored["interaction"] == "move_select" and Loop.unit(restored,"leonard")["coord"] == Loop.unit(base,"leonard")["coord"],"move cancel restores origin and reopens movement: " + label)
					check(not restored["pending_move"] and not restored["moved_this_action"],"move cancel restores movement eligibility: " + label)
					for id in ["leonard","enemy023_1"]:
						check(Loop.unit(restored,id)["inventory"] == Loop.unit(after,id)["inventory"] and Loop.unit(restored,id)["equipment"] == Loop.unit(after,id)["equipment"],"move cancel preserves confirmed items/equipment: " + label)
					var again := Loop.move_unit_to(restored,actor["coord"])
					check(again["pending_move"] and again["turn_queue"] == before["turn_queue"],"reopened movement accepts another legal move: " + label)
	# Same-code transfers are free; later offense still terminates exactly once.
	var repeated := Loop.begin_give(base)
	Loop._unit(repeated,"enemy023_1")["inventory"] = [241,241,0,0,0,0,0,0]
	for _iteration in range(2):
		repeated = Loop.confirm_give(repeated,"enemy023_1",0,241,0,241,repeated["item_revision"])
	repeated = Loop.finish_give(repeated,repeated["item_revision"])
	repeated = Loop.discard_item(repeated,"246",Loop.unit(repeated,"leonard")["inventory"].find(246))
	var foe := Loop._unit(repeated,"enemy021_1")
	foe["coord"] = Loop.unit(repeated,"leonard")["coord"] + Vector2i.UP
	foe["hp"] = 100
	fixture_defense(foe,repeated)
	repeated = Loop.attack_target(Loop.choose_command(repeated,"attack"),"enemy021_1",func(_n): return 0)
	repeated = Loop.finish_exhausted_action(repeated)
	check(repeated["selected_unit_id"] == "enemy023_1","two same-code gives and Drop can be followed by one Attack handoff")
	# Finishing the last controllable ally selects the next AI slot, not a whole
	# invented team phase. A repeated presentation request cannot skip that slot.
	var next_ai_id: String = repeated["turn_queue"]["slots"][2]["id"]
	repeated = Loop.choose_command(repeated,"wait")
	check(repeated["interaction"] == "ai_resolving" and Queue.current(repeated["turn_queue"])["id"] == next_ai_id,"last ally finishes into exactly the next initiative slot")
	check(Loop.begin_wait_resolution(repeated) == repeated,"player-finish entry cannot skip an AI slot")
	for bad in ["dead","defeated","enemy","wrong_turn","scenario","terminal"]:
		var invalid := base.duplicate(true)
		match bad:
			"dead": Loop._unit(invalid,"leonard")["hp"] = 0
			"defeated": Loop._unit(invalid,"leonard")["defeated"] = true
			"enemy": Loop._unit(invalid,"leonard")["player_commandable"] = false
			"wrong_turn": invalid["turn_queue"]["index"] = 1
			"scenario": invalid["scenario_ok"] = false
			"terminal": invalid["battle_outcome"] = BattleOutcome.VICTORY_SCRIPT
		for command in Loop.IMPLEMENTED_COMMANDS:
			check(Loop.choose_command(invalid,command) == invalid,"invalid actor/state rejects command without mutation: " + bad + "/" + command)
		check(Loop.use_item(invalid,"241","leonard",0) == invalid,"invalid Use is atomic: " + bad)
		check(Loop.discard_item(invalid,"241",0) == invalid,"invalid Drop is atomic: " + bad)
		check(Loop.change_equipment(invalid,"head",-1,0) == invalid,"invalid Equip is atomic: " + bad)
	scene.queue_free()
	await process_frame


func fixture_defense(actor: Dictionary, loop: Dictionary) -> void:
	actor["growth_profile"]["source"]["defense"] += 10000 - int(actor["combat_profile"]["live_defense"])
	actor.merge(Loop.ProgressionRules.refresh_growth_stats(actor,loop["equipment_items"]),true)
	actor["hp"] = 100
	actor["max_hp"] = 100
