extends SceneTree
const Inventory = preload("res://game/sim/InventoryRules.gd")
const Policy = preload("res://game/sim/ActionBudgetRules.gd")
const Loop = preload("res://game/sim/loop/BattlePlayLoop.gd")
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


func controlled() -> Dictionary:
	var loop := BattleFixture.loop()
	for index in range(loop["turn_queue"]["slots"].size()):
		if loop["turn_queue"]["slots"][index]["id"] == "leonard":
			loop["turn_queue"]["index"] = index
	loop = Loop.select_player_unit(loop, "leonard")
	var actor := Loop._unit(loop, "leonard")
	actor["inventory"] = [241, 241, 246, 281, 0, 0, 0, 0]
	var ally := Loop._unit(loop, "enemy023_1")
	ally["coord"] = actor["coord"] + Vector2i.RIGHT
	ally["inventory"] = [246, 241, 0, 0, 0, 0, 0, 0]
	return loop


func totals(a: Array, b: Array) -> Dictionary:
	var counts := {}
	for value in a + b:
		var code := int(value)
		if code > 0:
			counts[code] = int(counts.get(code, 0)) + 1
	return counts


func gameplay(loop: Dictionary) -> Dictionary:
	var result := loop.duplicate(true)
	# Monotonic stale-request identity is not an inventory or action resource.
	result.erase("item_revision")
	return result


func confirm(loop: Dictionary, index: int, target: int) -> Dictionary:
	return Loop.confirm_give(loop, "enemy023_1", index, int(Loop.unit(loop, "leonard")["inventory"][index]), target, int(Loop.unit(loop, "enemy023_1")["inventory"][target]), int(loop["item_revision"]))


func run() -> void:
	pure_cases()
	session_cases()
	rejection_cases()
	movement_cases()
	await ui_cases()
	print("GIVE_EXCHANGE_TESTS_", "PASS" if failures.is_empty() else "FAIL", " checks=", checks)
	quit(0 if failures.is_empty() else 1)


func pure_cases() -> void:
	var packet: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://docs/evidence_packets/static_reverse/original_give_exchange.json"))
	check(not packet["native_execution"], "static model fixtures are not native execution results")
	for case in packet["examples"]:
		var actual := Inventory.exchange(case["sender"], int(case["index"]), int(case["sender"][int(case["index"])]), case["receiver"], int(case["target"]), int(case["receiver"][int(case["target"])]))
		check(actual["ok"], "reviewed example accepted: " + case["name"])
		for key in case["expected"]:
			var expected: Variant = case["expected"][key]
			if expected is Array:
				expected = expected.map(func(value): return int(value))
			check(actual[key] == expected, case["name"] + ": " + key)
		check(totals(case["sender"], case["receiver"]) == totals(actual["sender"], actual["receiver"]), "example conserves each item code")
	for count_a in range(1, 9):
		for count_b in range(9):
			var a := [0, 0, 0, 0, 0, 0, 0, 0]
			var b := a.duplicate()
			for i in range(count_a): a[i] = 241 if i % 2 == 0 else 246
			for i in range(count_b): b[i] = 246 if i % 3 == 0 else 241
			for index in [0, count_a - 1]:
				for target in [0, 7]:
					var original := [a.duplicate(), b.duplicate()]
					var result := Inventory.exchange(a, index, a[index], b, target, b[target])
					check(result["ok"] and totals(result["sender"], result["receiver"]) == totals(a,b), "all occupancy boundaries conserve duplicate items")
					check(result["sender"].size() == 8 and result["receiver"].size() == 8, "all exchange outputs retain eight slots")
					check(original == [a,b], "pure exchange never mutates either input")
	check(not Inventory.exchange([241,0,0,0,0,0,0,0], 0, 241, [246,246,246,246,246,246,246,246], -1, 0)["ok"], "full bag needs explicit exchange choice")
	for index in [-2, 8]:
		check(not Inventory.exchange([241,0,0,0,0,0,0,0], index, 241, [0,0,0,0,0,0,0,0], 0, 0)["ok"], "invalid source selection rejected")
	check(not Inventory.exchange([241,0,0,0,0,0,0,0], 0, 241, [246,0,0,0,0,0,0,0], 0, 241)["ok"], "stale expected target cannot swap a different item")
	check(not Inventory.exchange([241,0], 0, 241, [0,0,0,0,0,0,0,0], 0, 0)["ok"], "malformed bags rejected before mutation")
	check(Policy.ends_action("use") and not Policy.ends_action("drop") and not Policy.ends_action("equip"), "common ordinary item policy matrix")
	check(not Policy.ends_action("give", false) and Policy.ends_action("give", true), "Give settles at session exit")


func session_cases() -> void:
	var original := controlled()
	var started := Loop.begin_give(original)
	check(started["interaction"] == "give_session" and Loop.begin_give(started) == started, "begin is explicit and cannot reset an existing session")
	var first := confirm(started, 0, 2)
	check(Loop.unit(first, "leonard")["inventory"] == [241,246,281,0,0,0,0,0], "give removes selected duplicate from sender in order")
	check(Loop.unit(first, "enemy023_1")["inventory"] == [246,241,241,0,0,0,0,0], "recipient duplicate occupies a new slot")
	check(first["turn_queue"] == original["turn_queue"] and first["give_session"]["action_used"], "successful give retains current queue and marks the session used")
	check(Loop.confirm_give(first, "enemy023_1", 0, 241, -1, 0, started["item_revision"]) == first, "stale request cannot consume adjacent identical item")
	var second := confirm(first, 0, 3)
	check(Loop.unit(second, "leonard")["inventory"] == [246,281,0,0,0,0,0,0], "second give in same session works")
	var finished := Loop.finish_give(second, second["item_revision"])
	check(finished["turn_queue"] != original["turn_queue"] and finished["give_session"].is_empty(), "close after multiple transfers ends exactly one actor action")
	check(Loop.finish_give(finished, second["item_revision"]) == finished, "duplicate finish does not advance a second actor")
	var cancelled := Loop.finish_give(started, started["item_revision"])
	check(gameplay(cancelled) == gameplay(original), "unconfirmed session cancellation restores all gameplay state")
	var reopened := Loop.begin_give(cancelled)
	check(Loop.confirm_give(reopened, "enemy023_1", 0, 241, -1, 0, started["item_revision"]) == reopened, "cancelled-session request cannot enter a reopened session")
	var same := confirm(started, 0, 1)
	check(not same["give_session"]["action_used"], "same-code exchange does not set native action flag")
	check(Loop.unit(same, "leonard")["inventory"] == [241,246,281,241,0,0,0,0], "same-code exchange still applies original slot ordering")
	var same_finished := Loop.finish_give(same, same["item_revision"])
	check(same_finished["turn_queue"] == original["turn_queue"] and same_finished["selected_unit_id"] == "leonard", "same-code-only session returns player control")
	var charged_then_same := confirm(first, 0, 1)
	check(charged_then_same["give_session"]["action_used"], "same-code later exchange cannot erase prior action charge")
	var full := controlled()
	Loop._unit(full, "leonard")["inventory"] = [241,241,241,241,241,241,241,241]
	Loop._unit(full, "enemy023_1")["inventory"] = [246,241,241,241,241,241,241,241]
	full = Loop.begin_give(full)
	var exchanged := confirm(full, 0, 0)
	check(Loop.unit(exchanged, "leonard")["inventory"] == [241,241,241,241,241,241,241,246], "full sender gets returned item in freed tail")
	check(Loop.unit(exchanged, "enemy023_1")["inventory"] == [241,241,241,241,241,241,241,241], "full target receives incoming after removal and compaction")
	var important := confirm(started, 3, 0)
	check(Loop.unit(important, "enemy023_1")["inventory"].has(281), "important restriction remains discard-only")


func rejection_cases() -> void:
	var started := Loop.begin_give(controlled())
	for id in ["", "missing", "leonard", "enemy021_1"]:
		check(Loop.confirm_give(started, id, 0, 241, 0, 246, started["item_revision"]) == started, "invalid/self/enemy target rejected: " + id)
	for reason in ["dead", "defeated", "far", "malformed"]:
		var invalid := started.duplicate(true)
		var target := Loop._unit(invalid, "enemy023_1")
		match reason:
			"dead": target["hp"] = 0
			"defeated": target["defeated"] = true
			"far": target["coord"] += Vector2i(5,5)
			"malformed": target["inventory"] = [246]
		check(Loop.confirm_give(invalid, "enemy023_1", 0, 241, 0, 246, invalid["item_revision"]) == invalid, "target failure has no partial state: " + reason)
	for reason in ["terminal", "dead", "enemy", "attacked", "wrong_turn", "scenario"]:
		var invalid := started.duplicate(true)
		match reason:
			"terminal": invalid["battle_outcome"] = BattleOutcome.VICTORY_SCRIPT
			"dead": Loop._unit(invalid, "leonard")["hp"] = 0
			"enemy": Loop._unit(invalid, "leonard")["player_commandable"] = false
			"attacked": invalid["attacked_this_action"] = true
			"wrong_turn": invalid["turn_queue"]["index"] = 0
			"scenario": invalid["scenario_ok"] = false
		check(Loop.confirm_give(invalid, "enemy023_1", 0, 241, 0, 246, invalid["item_revision"]) == invalid, "actor failure is atomic: " + reason)
	for command in ["move", "attack", "special", "wait", "item", "status"]:
		check(Loop.choose_command(started, command) == started, "open Give session cannot escape through a different command")
	check(Loop.begin_wait_resolution(started) == started and Loop.select_player_unit(started, "leonard") == started, "direct turn/reselect cannot reset give charge")


func movement_cases() -> void:
	var original := controlled()
	var origin: Vector2i = Loop.unit(original, "leonard")["coord"]
	var moving := Loop.choose_command(original, "move")
	var cells: Array = Loop.movement_cells(moving, "leonard").filter(func(cell): return cell != origin)
	check(not cells.is_empty(), "movement fixture has a legal destination")
	if cells.is_empty(): return
	var moved := Loop.move_unit_to(moving, cells[0])
	Loop._unit(moved, "enemy023_1")["coord"] = cells[0] + Vector2i.RIGHT
	var started := Loop.begin_give(moved)
	check(Loop.cancel_pending_move(started) == started, "movement cannot be rolled back while a give session is open")
	var cancelled := Loop.finish_give(started, started["item_revision"])
	check(gameplay(cancelled) == gameplay(moved), "cancel Give retains pending move and all inventory state")
	check(Loop.unit(Loop.cancel_pending_move(cancelled), "leonard")["coord"] == origin, "no-transfer Give cancellation leaves movement rollback available")
	var received := confirm(started, 0, 2)
	check(received["pending_move"] and received["turn_queue"] == moved["turn_queue"], "move-then-give waits for session exit")
	var finished := Loop.finish_give(received, received["item_revision"])
	check(not finished["pending_move"] and Loop.unit(finished, "leonard")["coord"] == cells[0], "ending changed Give session commits the move")
	check(Loop.cancel_pending_move(finished) == finished, "completed give cannot roll back committed movement")


func ui_cases() -> void:
	var scene = load("res://game/battle/scene/BattleSceneRuntime.tscn").instantiate()
	scene.scenario_path = BattleFixture.PATH; scene.startup_mode = "dev_first_control"
	root.add_child(scene)
	await process_frame
	scene.start_dev_first_control_harness()
	scene.set_process(false)
	var actor := Loop._unit(scene.play_loop, "leonard")
	actor["inventory"] = [241,241,246,281,0,0,0,0]
	var ally := Loop._unit(scene.play_loop, "enemy023_1")
	ally["coord"] = actor["coord"] + Vector2i.RIGHT
	ally["inventory"] = [246,0,0,0,0,0,0,0]
	scene.apply_loop(scene.play_loop, "test")
	scene.menus.choose_command("item")
	scene.item_panel.menu._process(0.25)
	scene.item_panel.menu.get_node("GiveCommand").pressed.emit()
	check(scene.item_panel.page == "give_target", "Give begins with target choice")
	scene.item_panel.target_buttons["enemy023_1"].pressed.emit()
	check(scene.item_panel.page == "give_inventory", "target opens two real inventory views")
	scene.item_panel.give_view.source_buttons[0].pressed.emit()
	scene.item_panel.give_view.destination_buttons[1].pressed.emit()
	var preview: Dictionary = scene.play_loop.duplicate(true)
	var stale = scene.item_panel.confirm_button
	scene.item_panel.cancel()
	check(scene.play_loop == preview and scene.item_panel.page == "give_inventory", "proposal cancellation changes no inventory or action")
	scene.item_panel.give_view.destination_buttons[1].pressed.emit()
	stale.pressed.emit()
	check(scene.play_loop == preview, "cancelled old button cannot confirm a newly identical proposal")
	scene.item_panel.confirm_button.pressed.emit()
	var after: Dictionary = scene.play_loop.duplicate(true)
	check(scene.item_panel.page == "give_inventory" and not scene.ai_playback_active and Loop.unit(after,"leonard")["inventory"].count(241) == 1, "accepted give keeps the updated inventories open")
	stale.pressed.emit()
	check(scene.play_loop == after, "stale signal cannot repeat a transfer")
	scene.item_panel.give_view.source_buttons[0].pressed.emit()
	scene.item_panel.give_view.destination_buttons[2].pressed.emit()
	scene.item_panel.confirm_button.pressed.emit()
	check(Loop.unit(scene.play_loop,"leonard")["inventory"].count(241) == 0, "continuous UI give uses refreshed source and target slots")
	scene.item_panel.give_view.finish_requested.emit()
	check(not scene.item_panel.visible and scene.play_loop["give_session"].is_empty(), "end Give closes and settles once")
	scene.queue_free()
	await process_frame
	await create_timer(0.3).timeout
