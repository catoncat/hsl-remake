extends SceneTree
## State-transition tests; saved original growth outputs remain a separate oracle.
const TestSuite = preload("res://tests/support/TestSuite.gd")
const Inventory = preload("res://game/sim/InventoryRules.gd")
const Equipment = preload("res://game/sim/EquipmentRules.gd")
const Growth = preload("res://game/sim/ProgressionRules.gd")
const Catalog = preload("res://game/sim/EquipmentCatalog.gd")
const Loop = preload("res://game/sim/loop/BattlePlayLoop.gd")
const Queue = preload("res://game/sim/CoreTurnQueue.gd")
const BattleFixture = preload("res://tests/support/BattleFixture.gd")
const BattleOutcome = preload("res://game/sim/BattleOutcome.gd")
var failures: Array[String] = []
var checks := 0


func _initialize() -> void:
	call_deferred("run")


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		push_error(message)


func compare_numbers(actual: Dictionary, expected: Dictionary, label: String) -> void:
	for key in expected:
		if expected[key] is Dictionary:
			compare_numbers(actual.get(key, {}), expected[key], label + ": " + key)
		elif typeof(expected[key]) in [TYPE_INT, TYPE_FLOAT]:
			check(actual.has(key) and actual[key] == expected[key], "%s: %s actual=%s expected=%s" % [label, key, actual.get(key), expected[key]])


func controlled() -> Dictionary:
	var loop := BattleFixture.loop()
	# Select a genuine queue entry without inventing a second battle state.
	for index in range(loop["turn_queue"]["slots"].size()):
		if loop["turn_queue"]["slots"][index]["id"] == "leonard":
			loop["turn_queue"]["index"] = index
	return Loop.select_player_unit(loop, "leonard")


func run() -> void:
	inventory_cases()
	equipment_cases()
	saved_native_growth_cases()
	transfer_cases()
	important_item_cases()
	discard_action_cases()
	await ui_cases()
	print("INVENTORY_EQUIPMENT_TESTS_", "PASS" if failures.is_empty() else "FAIL", " checks=", checks)
	quit(0 if failures.is_empty() else 1)


func inventory_cases() -> void:
	var bag := [241, 246, 241, 0, 0, 0, 0, 0]
	check(Inventory.insert(bag, 241)["inventory"] == [241, 246, 241, 241, 0, 0, 0, 0], "duplicate items use distinct slots")
	check(Inventory.remove(bag, 2, 241)["inventory"] == [241, 246, 0, 0, 0, 0, 0, 0], "selected duplicate removal preserves earlier order")
	check(Inventory.remove(bag, 0, 241)["inventory"] == [246, 241, 0, 0, 0, 0, 0, 0], "first removal compacts left")
	check(Inventory.insert([241, 0, 246, 0, 0, 0, 0, 0], 3)["inventory"] == [241, 3, 246, 0, 0, 0, 0, 0], "insertion fills first hole without sorting")
	check(not Inventory.insert([1, 2, 3, 4, 5, 6, 7, 8], 241)["ok"], "full backpack rejects insertion")
	check(Inventory.remove([1, 2, 3, 4, 5, 6, 7, 8], 7, 8)["inventory"] == [1, 2, 3, 4, 5, 6, 7, 0], "last-slot removal clears tail")
	for index in [-2, -1, 8, 100]:
		check(not Inventory.remove(bag, index, 241)["ok"], "invalid removal index is inert: " + str(index))
	check(not Inventory.remove(bag, 1, 241)["ok"], "stale item selection rejects before mutation")
	var decoded: Array = JSON.parse_string("[241,246,241,0,0,0,0,0]")
	check(Inventory.find_item(decoded, 241) == 0 and Inventory.insert(decoded, 1)["inventory"][3] == 1, "JSON numeric slots work before canonicalization")
	check(bag == [241, 246, 241, 0, 0, 0, 0, 0], "pure inventory calls preserve input")
	check(Loop.unit(BattleFixture.loop(), "leonard")["inventory"] == [241, 241, 241, 246, 0, 0, 0, 0], "normal bootstrap creates ordered integer slots")


func equipment_cases() -> void:
	var loop := controlled()
	var actor := Loop._unit(loop, "leonard")
	actor["inventory"] = [241, 3, 241, 246, 0, 0, 0, 0]
	actor["hp"] = 17
	loop["pending_move"] = true
	loop["pending_move_from"] = actor["coord"] - Vector2i.DOWN
	loop["moved_this_action"] = true
	var original := loop.duplicate(true)
	var changed := Loop.change_equipment(loop, "weapon", 1, 3)
	var after := Loop.unit(changed, "leonard")
	check(after["weapon_code"] == 3, "weapon code changes through PlayLoop")
	check(after["inventory"] == [241, 241, 246, 2, 0, 0, 0, 0], "old weapon returns after ordered removal")
	check(after["combat_profile"]["live_attack_damage"] == 59 and after["combat_profile"]["live_magic_attack"] == 22, "weapon 3 applies original attack and add_magic_power")
	check(after["combat_profile"]["live_defense"] == 43 and after["live_speed"] == 16, "all other equipped pieces are reapplied once")
	check(after["hp"] == 17 and after["max_hp"] == 30 and after["mp"] == 0, "swap does not heal")
	for key in ["pending_move", "pending_move_from", "moved_this_action", "attacked_this_action", "turn_queue", "interaction"]:
		check(changed[key] == original[key], "exchange preserves action/queue policy: " + key)
	check(loop == original, "equipment operation leaves its input untouched")
	check(Loop.change_equipment(changed, "weapon", 1, 3) == changed, "repeated swap request is inert")
	var returned := Loop.change_equipment(changed, "weapon", 3, 2)
	compare_numbers(Loop.unit(returned, "leonard")["combat_profile"], actor["combat_profile"], "swap-back restores original combat values")
	var levelled := after.duplicate(true)
	levelled["exp"] = 99
	levelled = Growth.resolve_experience(levelled, 1, changed["equipment_items"])
	check(levelled["combat_profile"]["live_attack_damage"] == 60 and levelled["combat_profile"]["live_magic_attack"] == 23, "level-up refresh keeps current equipment")
	var queue: Dictionary = changed["turn_queue"].duplicate(true)
	queue["index"] = queue["slots"].size() - 1
	var rebuilt := Queue.advance(queue, changed["units"])
	var player_slot: Dictionary = rebuilt["slots"].filter(func(entry): return entry["id"] == "leonard")[0]
	check(player_slot["live_speed"] == 16, "next-round rebuild consumes equipped speed")
	var full := original.duplicate(true)
	Loop._unit(full, "leonard")["inventory"] = [241, 241, 241, 241, 241, 241, 241, 3]
	var full_swap := Loop.change_equipment(full, "weapon", 7, 3)
	check(Loop.unit(full_swap, "leonard")["inventory"] == [241, 241, 241, 241, 241, 241, 241, 2], "full bag exchange uses selected item's freed slot")
	check(Loop.change_equipment(full, "head", -1, 0) == full, "full bag cannot lose an unequipped helmet")
	var unarmed := Loop.change_equipment(original, "weapon", -1, 0)
	check(Loop.unit(unarmed,"leonard")["weapon_code"]==0 and Loop.unit(unarmed,"leonard")["inventory"]==[241,3,241,246,2,0,0,0], "native range0 permits a real unequip and returns the old weapon to its first free slot")
	check(not Loop.command_available(unarmed,"attack") and Loop.attack_cells(unarmed).is_empty(), "empty source weapon range disables ordinary selection instead of granting a fake adjacent strike")
	check(Loop.change_equipment(full,"weapon",-1,0)==full, "unarmed support must not bypass full-bag protection")
	for request in [["head", 1, 3], ["weapon", 0, 3], ["unknown", 1, 3]]:
		check(Loop.change_equipment(original, request[0], request[1], request[2]) == original, "wrong slot/stale selection fails atomically")
	for key in ["battle_outcome", "attacked_this_action", "interaction"]:
		var invalid := original.duplicate(true)
		invalid[key] = BattleOutcome.VICTORY_SCRIPT if key == "battle_outcome" else (true if key == "attacked_this_action" else "ai_resolving")
		check(Loop.change_equipment(invalid, "weapon", 1, 3) == invalid, "invalid phase rejects: " + key)
	var locked := original.duplicate(true)
	TestSuite.own(locked, "equipment_items")["2"]["unequip_blocked"] = true
	check(Loop.change_equipment(locked, "weapon", 1, 3) == locked, "old equipment lock rejects complete transaction")
	for field in ["attack_power", "has_magic", "base_resist_by_type"]:
		var incomplete := original.duplicate(true)
		var incomplete_unit := Loop._unit(incomplete, "leonard")
		incomplete_unit["growth_profile"]["source"].erase(field)
		incomplete_unit["pending_stat_points"] = 5
		incomplete_unit["exp"] = 99
		check(Growth.refresh_input_error(incomplete_unit, incomplete["equipment_items"]) != "", "incomplete source reports a precise rejection")
		check(Loop.change_equipment(incomplete, "weapon", 1, 3) == incomplete, "incomplete source preserves inventory/equipment/stats: " + field)
		check(Growth.apply_allocation(incomplete_unit, {"str": 1}, incomplete["equipment_items"]) == incomplete_unit, "incomplete source does not spend growth points")
		check(Growth.resolve_experience(incomplete_unit, 1, incomplete["equipment_items"]) == incomplete_unit, "incomplete source does not partially level up")
	var absent_effect := original.duplicate(true)
	TestSuite.own(absent_effect, "equipment_items")["3"]["effects"].erase("attack")
	check(Loop.change_equipment(absent_effect, "weapon", 1, 3) == absent_effect, "missing new-item effects reject before inventory commit")
	var invalid_roster: Array = BattleFixture.loop()["units"].duplicate(true)
	for entry in invalid_roster:
		if entry["id"] == "leonard":
			entry["growth_profile"]["source"].erase("speed")
	var invalid_scene := BattleFixture.loop(invalid_roster)
	check(not invalid_scene["scenario_ok"] and invalid_scene["scenario_error"] == "invalid_growth_source_speed", "invalid initial growth source fails the scenario explicitly")
	var wrong_job := actor.duplicate(true)
	wrong_job["growth_profile"]["job_code"] = 83
	check(Equipment.replace(wrong_job, "weapon", 1, 3, original["equipment_items"])["reason"] == "wrong_job", "class eligibility is checked before replacement")
	var enemy := original.duplicate(true)
	Loop._unit(enemy, "leonard")["player_commandable"] = false
	check(Loop.change_equipment(enemy, "weapon", 1, 3) == enemy, "non-commandable actor rejects equipment mutation")
	var dead := original.duplicate(true)
	Loop._unit(dead, "leonard")["hp"] = 0
	check(Loop.change_equipment(dead, "weapon", 1, 3) == dead, "dead actor rejects equipment mutation")
	var helmet_off := Loop.change_equipment(original, "head", -1, 0)
	check(Loop.unit(helmet_off, "leonard")["combat_profile"]["live_defense"] == 37, "head slot contributes defense, not attack")
	var helmet_slot: int = Loop.unit(helmet_off, "leonard")["inventory"].find(153)
	var helmet_on := Loop.change_equipment(helmet_off, "head", helmet_slot, 153)
	check(Loop.unit(helmet_on, "leonard")["combat_profile"]["live_defense"] == 43, "re-equipping helmet restores only its contribution")
	var untouched := Catalog.items()
	untouched["2"]["effects"]["attack"] = 999
	check(Catalog.items()["2"]["effects"]["attack"] == 23, "catalog callers cannot mutate the cached source")
	# Check both accessory destinations using an actual supported source item.
	var accessory := 0
	for code in original["equipment_items"]:
		var item: Dictionary = original["equipment_items"][code]
		if int(item["type_code"]) == 6 and item["supported"] and (int(item["job_mask"]) & 1) != 0:
			accessory = int(code)
			break
	check(accessory > 0, "source catalog contains a supported SwordMan accessory")
	if accessory > 0:
		for slot in ["accessory1", "accessory2"]:
			var ready := original.duplicate(true)
			Loop._unit(ready, "leonard")["inventory"] = [accessory, 0, 0, 0, 0, 0, 0, 0]
			var equipped := Loop.change_equipment(ready, slot, 0, accessory)
			check(Equipment.equipped_code(Loop.unit(equipped, "leonard")["equipment"], slot) == accessory, "accessory enters selected slot: " + slot)
			var removed := Loop.change_equipment(equipped, slot, -1, 0)
			check(Loop.unit(removed, "leonard")["inventory"] == [accessory, 0, 0, 0, 0, 0, 0, 0], "accessory removal returns exact item: " + slot)


func saved_native_growth_cases() -> void:
	var packet: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://docs/evidence_packets/static_reverse/original_growth_refresh.json"))
	var source := Loop.unit(BattleFixture.loop(), "leonard")
	var mapping := {"current_hp": "hp", "max_hp": "max_hp", "current_mp": "mp", "max_mp": "max_mp", "speed": "live_speed"}
	var profile_mapping := {"attack": "live_attack_damage", "defense": "live_defense", "magic_attack": "live_magic_attack", "hit_rate": "live_hit_ratio", "resist_by_type": "resist_by_type"}
	for fixture in packet["cases"]:
		for equipped in [true, false]:
			var unit := source.duplicate(true)
			unit["combat_profile"].merge(fixture["attributes"], true)
			unit["level"] = int(fixture["level"])
			unit["hp"] = int(fixture["input_current_hp"])
			unit["mp"] = int(fixture["input_current_mp"])
			if not equipped:
				unit["equipment"] = []
			var result := Growth.refresh_growth_stats(unit, Catalog.items())
			var expected: Dictionary = fixture["native_equipped" if equipped else "native_unequipped"]
			for field in mapping:
				check(result[mapping[field]] == expected[field], "saved native fixture " + fixture["case"] + ": " + field)
			for field in profile_mapping:
				if field == "resist_by_type":
					compare_numbers(result["combat_profile"][field], expected[field], "saved native fixture " + fixture["case"])
				else:
					check(result["combat_profile"][profile_mapping[field]] == expected[field], "saved native fixture " + fixture["case"] + ": " + field)
	# Synthetic catalog case verifies clamping and no healing, not original execution.
	var catalog := Catalog.items()
	catalog["153"]["effects"]["max_hp"] = 100
	catalog["153"]["effects"]["resist_by_type"]["0"] = 100
	source["hp"] = 17
	var boosted := Growth.refresh_growth_stats(source, catalog)
	check(boosted["max_hp"] == 130 and boosted["hp"] == 17 and boosted["combat_profile"]["resist_by_type"]["0"] == 80, "equipment refresh clamps resistance and preserves wounded HP")
	boosted["hp"] = 100
	var restored := Growth.refresh_growth_stats(boosted, Catalog.items())
	check(restored["hp"] == 30, "lowering max HP clamps current HP once")


func transfer_cases() -> void:
	var loop := controlled()
	var actor := Loop._unit(loop, "leonard")
	var ally := Loop._unit(loop, "enemy023_1")
	ally["coord"] = actor["coord"] + Vector2i.RIGHT
	ally["inventory"] = [241, 241, 241, 241, 241, 241, 241, 241]
	var session := Loop.begin_give(loop)
	check(Loop.confirm_give(session, ally["id"], 1, 241, -1, 0, session["item_revision"]) == session, "giving without choosing an exchange to a full recipient preserves inventories and action")
	actor["inventory"] = [241, 246, 241, 0, 0, 0, 0, 0]
	actor["hp"] = 10
	var used := Loop.use_item(loop, "241", "leonard", 2)
	check(Loop.unit(used, "leonard")["inventory"] == [241, 246, 0, 0, 0, 0, 0, 0], "use consumes the selected duplicate slot")
	check(Loop.use_item(loop, "241", "leonard", 1) == loop, "stale use index cannot consume another item")


func important_item_cases() -> void:
	var loop := controlled()
	var actor := Loop._unit(loop, "leonard")
	loop["pending_move"] = true
	loop["pending_move_from"] = actor["coord"] - Vector2i.DOWN
	loop["moved_this_action"] = true
	var catalog: Dictionary = loop["equipment_items"]
	for code in [281, 282, 283, 284, 285]:
		actor["inventory"] = [241, code, 246, 0, 0, 0, 0, 0]
		var before := loop.duplicate(true)
		check(Inventory.discard_error(code, catalog) == "important_item", "source-important item rejects discard: " + str(code))
		check(Loop.discard_item(loop, str(code), 1) == before, "important rejection preserves all state including queue and pending move")
		check(Loop.discard_item(loop, str(code), 1) == before, "repeated important-item request is inert")
	actor["inventory"] = [281, 241, 246, 0, 0, 0, 0, 0]
	var ordinary := Loop.discard_item(loop, "241", 1)
	check(Loop.unit(ordinary, "leonard")["inventory"] == [281, 246, 0, 0, 0, 0, 0, 0], "normal discard removes only the requested non-important slot")
	check(ordinary["pending_move"] and ordinary["turn_queue"] == loop["turn_queue"], "ordinary discard preserves pending movement and the current action")
	check(Loop.discard_item(ordinary, "241", 1) == ordinary, "completed discard cannot repeat")
	check(not Inventory.discard(actor["inventory"], 1, 9999, catalog)["ok"], "missing catalog entry cannot silently authorize discard")
	var missing := catalog.duplicate(true)
	missing["241"].erase("important")
	check(Inventory.discard_error(241, missing) == "missing_item_discard_rule", "missing important flag rejects explicitly")
	var unrelated_lock := catalog.duplicate(true)
	unrelated_lock["241"]["unequip_blocked"] = true
	check(Inventory.discard(actor["inventory"], 1, 241, unrelated_lock)["ok"], "unequip lock is not confused with the discard restriction")
	var ally := Loop._unit(loop, "enemy023_1")
	ally["coord"] = actor["coord"] + Vector2i.RIGHT
	var session := Loop.begin_give(loop)
	var given := Loop.confirm_give(session, ally["id"], 0, 281, -1, 0, session["item_revision"])
	check(Loop.unit(given, ally["id"])["inventory"].has(281), "discard-only restriction does not invent an important-item transfer ban")


func discard_action_cases() -> void:
	for moved in [false, true]:
		var loop := controlled()
		Loop._unit(loop, "leonard")["inventory"] = [241, 241, 246, 0, 0, 0, 0, 0]
		var origin: Vector2i = Loop.unit(loop, "leonard")["coord"]
		if moved:
			var destinations: Array = Loop.movement_cells(loop, "leonard").filter(func(cell): return cell != origin)
			check(not destinations.is_empty(), "discard fixture has a legal move")
			if destinations.is_empty():
				continue
			loop = Loop.move_unit_to(Loop.choose_command(loop, "move"), destinations[0])
		var original := loop.duplicate(true)
		var expected := loop.duplicate(true)
		Loop._unit(expected, "leonard")["inventory"] = [241, 246, 0, 0, 0, 0, 0, 0]
		var discarded := Loop.discard_item(loop, "241", 0)
		check(discarded == expected, "discard only changes the requested inventory, including after a move")
		check(loop == original, "discard does not mutate its input snapshot")
		check(Loop.choose_command(discarded, "attack")["interaction"] == "attack_select", "attack remains available after discard")
		if moved:
			var cancelled := Loop.cancel_pending_move(discarded)
			check(Loop.unit(cancelled, "leonard")["coord"] == origin and not cancelled["moved_this_action"], "discard does not prevent cancelling an uncommitted move")
			check(Loop.unit(cancelled, "leonard")["inventory"] == Loop.unit(discarded, "leonard")["inventory"], "movement cancellation cannot restore a discarded item")
		else:
			check(Loop.choose_command(discarded, "move")["interaction"] == "move_select", "move remains available after discard")
		for field in ["interaction", "battle_outcome", "attacked_this_action"]:
			var invalid := original.duplicate(true)
			invalid[field] = "ai_resolving" if field == "interaction" else (BattleOutcome.VICTORY_SCRIPT if field == "battle_outcome" else true)
			check(Loop.discard_item(invalid, "241", 0) == invalid, "free discard still rejects invalid action state: " + field)


func ui_cases() -> void:
	var scene = load("res://game/battle/scene/BattleSceneRuntime.tscn").instantiate()
	scene.scenario_path = BattleFixture.PATH; scene.startup_mode = "dev_first_control"
	root.add_child(scene)
	await process_frame
	scene.start_dev_first_control_harness()
	scene.set_process(false)
	Loop._unit(scene.play_loop, "leonard")["inventory"] = [241, 3, 241, 246, 0, 0, 0, 0]
	var before: Dictionary = scene.play_loop.duplicate(true)
	scene.menus.choose_command("item")
	scene.item_panel.menu._process(0.25)
	scene.item_panel.menu.get_node("EquipCommand").pressed.emit()
	scene.item_panel.rows.get_child(0).pressed.emit()
	check(scene.item_panel.page == "equip_confirm" and scene.play_loop == before, "equipment preview cannot mutate live state")
	scene.item_panel.cancel()
	scene.menus.change_equipment("weapon", 1, 3)
	check(scene.play_loop == before, "cancelled equipment callback is inert")
	scene.item_panel.rows.get_child(0).pressed.emit()
	scene.item_panel.confirm_button.pressed.emit()
	check(not scene.item_panel.visible and Loop.unit(scene.play_loop, "leonard")["weapon_code"] == 3, "UI confirmation commits through the runtime and PlayLoop")
	var after: Dictionary = scene.play_loop.duplicate(true)
	scene.menus.change_equipment("weapon", 1, 3)
	check(scene.play_loop == after and not scene.ai_playback_active, "closed-panel duplicate cannot repeat a free exchange")
	Loop._unit(scene.play_loop, "leonard")["inventory"] = [281, 241, 241, 246, 0, 0, 0, 0]
	scene.menus.choose_command("item")
	scene.item_panel.menu._process(0.25)
	scene.item_panel.menu.get_node("DropCommand").pressed.emit()
	check(scene.item_panel.rows.get_child(0).disabled and not scene.item_panel.rows.get_child(1).disabled, "UI blocks important items while keeping ordinary discard available")
	var protected: Dictionary = scene.play_loop.duplicate(true)
	scene.item_panel._select_item("281", 0)
	check(scene.item_panel.confirm_button.disabled, "stale/programmatic important-item selection cannot enable confirm")
	scene.menus.discard_inventory_item("281")
	check(scene.play_loop == protected and scene.item_panel.visible, "runtime rejects important discard without closing the panel or consuming action")
	scene.item_panel.cancel()
	check(scene.play_loop == protected and scene.item_panel.page == "inventory", "blocked discard remains cancellable")
	scene.item_panel.rows.get_child(1).pressed.emit()
	scene.item_panel.confirm_button.pressed.emit()
	var discarded: Dictionary = scene.play_loop.duplicate(true)
	check(Loop.unit(discarded, "leonard")["inventory"] == [281, 241, 246, 0, 0, 0, 0, 0], "confirmation removes only one of two adjacent duplicate items")
	check(discarded["turn_queue"] == protected["turn_queue"] and not scene.ai_playback_active and scene.interaction_state == "action_menu", "runtime does not hand off the turn after free discard")
	scene.menus.discard_inventory_item("241")
	check(scene.play_loop == discarded, "closed-panel stale callback cannot discard the identical item now in the same slot")
	scene.menus.choose_command("move")
	check(scene.interaction_state == "move_select", "runtime accepts movement after discard")
	scene.queue_free()
	await process_frame
	await create_timer(0.3).timeout
