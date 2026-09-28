extends SceneTree
## State-transition tests; saved original growth outputs remain a separate oracle.
const TestSuite = preload("res://tests/support/TestSuite.gd")
const InventoryRules = preload("res://game/sim/InventoryRules.gd")
const EquipmentRules = preload("res://game/sim/EquipmentRules.gd")
const ProgressionRules = preload("res://game/sim/ProgressionRules.gd")
const EquipmentCatalog = preload("res://game/sim/EquipmentCatalog.gd")
const BattlePlayLoop = preload("res://game/sim/loop/BattlePlayLoop.gd")
const CoreTurnQueue = preload("res://game/sim/CoreTurnQueue.gd")
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
	return BattlePlayLoop.select_player_unit(loop, "leonard")


func run() -> void:
	inventory_cases()
	equipment_cases()
	saved_native_growth_cases()
	transfer_cases()
	important_item_cases()
	discard_action_cases()
	await run_give_exchange()
	print("INVENTORY_EQUIPMENT_TESTS_", "PASS" if failures.is_empty() else "FAIL", " checks=", checks)
	quit(0 if failures.is_empty() else 1)


func inventory_cases() -> void:
	var bag := [241, 246, 241, 0, 0, 0, 0, 0]
	check(InventoryRules.insert(bag, 241)["inventory"] == [241, 246, 241, 241, 0, 0, 0, 0], "duplicate items use distinct slots")
	check(InventoryRules.remove(bag, 2, 241)["inventory"] == [241, 246, 0, 0, 0, 0, 0, 0], "selected duplicate removal preserves earlier order")
	check(InventoryRules.remove(bag, 0, 241)["inventory"] == [246, 241, 0, 0, 0, 0, 0, 0], "first removal compacts left")
	check(InventoryRules.insert([241, 0, 246, 0, 0, 0, 0, 0], 3)["inventory"] == [241, 3, 246, 0, 0, 0, 0, 0], "insertion fills first hole without sorting")
	check(not InventoryRules.insert([1, 2, 3, 4, 5, 6, 7, 8], 241)["ok"], "full backpack rejects insertion")
	check(InventoryRules.remove([1, 2, 3, 4, 5, 6, 7, 8], 7, 8)["inventory"] == [1, 2, 3, 4, 5, 6, 7, 0], "last-slot removal clears tail")
	for index in [-2, -1, 8, 100]:
		check(not InventoryRules.remove(bag, index, 241)["ok"], "invalid removal index is inert: " + str(index))
	check(not InventoryRules.remove(bag, 1, 241)["ok"], "stale item selection rejects before mutation")
	var decoded: Array = JSON.parse_string("[241,246,241,0,0,0,0,0]")
	check(InventoryRules.find_item(decoded, 241) == 0 and InventoryRules.insert(decoded, 1)["inventory"][3] == 1, "JSON numeric slots work before canonicalization")
	check(bag == [241, 246, 241, 0, 0, 0, 0, 0], "pure inventory calls preserve input")
	check(BattlePlayLoop.unit(BattleFixture.loop(), "leonard")["inventory"] == [241, 241, 241, 246, 0, 0, 0, 0], "normal bootstrap creates ordered integer slots")


func equipment_cases() -> void:
	var loop := controlled()
	var actor := BattlePlayLoop.unit_ref(loop, "leonard")
	actor["inventory"] = [241, 3, 241, 246, 0, 0, 0, 0]
	actor["hp"] = 17
	loop["pending_move"] = true
	loop["pending_move_from"] = actor["coord"] - Vector2i.DOWN
	loop["moved_this_action"] = true
	var original := loop.duplicate(true)
	var changed := BattlePlayLoop.change_equipment(loop, "weapon", 1, 3)
	var after := BattlePlayLoop.unit(changed, "leonard")
	check(after["weapon_code"] == 3, "weapon code changes through PlayLoop")
	check(after["inventory"] == [241, 241, 246, 2, 0, 0, 0, 0], "old weapon returns after ordered removal")
	check(after["combat_profile"]["live_attack_damage"] == 59 and after["combat_profile"]["live_magic_attack"] == 22, "weapon 3 applies original attack and add_magic_power")
	check(after["combat_profile"]["live_defense"] == 43 and after["live_speed"] == 16, "all other equipped pieces are reapplied once")
	check(after["hp"] == 17 and after["max_hp"] == 30 and after["mp"] == 0, "swap does not heal")
	for key in ["pending_move", "pending_move_from", "moved_this_action", "attacked_this_action", "turn_queue", "interaction"]:
		check(changed[key] == original[key], "exchange preserves action/queue policy: " + key)
	check(loop == original, "equipment operation leaves its input untouched")
	check(BattlePlayLoop.change_equipment(changed, "weapon", 1, 3) == changed, "repeated swap request is inert")
	var returned := BattlePlayLoop.change_equipment(changed, "weapon", 3, 2)
	compare_numbers(BattlePlayLoop.unit(returned, "leonard")["combat_profile"], actor["combat_profile"], "swap-back restores original combat values")
	var levelled := after.duplicate(true)
	levelled["exp"] = 99
	levelled = ProgressionRules.resolve_experience(levelled, 1, changed["equipment_items"])
	check(levelled["combat_profile"]["live_attack_damage"] == 60 and levelled["combat_profile"]["live_magic_attack"] == 23, "level-up refresh keeps current equipment")
	var queue: Dictionary = changed["turn_queue"].duplicate(true)
	queue["index"] = queue["slots"].size() - 1
	var rebuilt := CoreTurnQueue.advance(queue, changed["units"])
	var player_slot: Dictionary = rebuilt["slots"].filter(func(entry): return entry["id"] == "leonard")[0]
	check(player_slot["live_speed"] == 16, "next-round rebuild consumes equipped speed")
	var full := original.duplicate(true)
	BattlePlayLoop.unit_ref(full, "leonard")["inventory"] = [241, 241, 241, 241, 241, 241, 241, 3]
	var full_swap := BattlePlayLoop.change_equipment(full, "weapon", 7, 3)
	check(BattlePlayLoop.unit(full_swap, "leonard")["inventory"] == [241, 241, 241, 241, 241, 241, 241, 2], "full bag exchange uses selected item's freed slot")
	check(BattlePlayLoop.change_equipment(full, "head", -1, 0) == full, "full bag cannot lose an unequipped helmet")
	var unarmed := BattlePlayLoop.change_equipment(original, "weapon", -1, 0)
	check(BattlePlayLoop.unit(unarmed,"leonard")["weapon_code"]==0 and BattlePlayLoop.unit(unarmed,"leonard")["inventory"]==[241,3,241,246,2,0,0,0], "native range0 permits a real unequip and returns the old weapon to its first free slot")
	check(not BattlePlayLoop.command_available(unarmed,"attack") and BattlePlayLoop.attack_cells(unarmed).is_empty(), "empty source weapon range disables ordinary selection instead of granting a fake adjacent strike")
	check(BattlePlayLoop.change_equipment(full,"weapon",-1,0)==full, "unarmed support must not bypass full-bag protection")
	# Full bag: the Equip／Drop window's hand keeps the piece in the loop (0x437020, 0x438c84, 0x436f30, 0x43aacb, 0x438868).
	var in_hand := BattlePlayLoop.unequip_to_hand(full, "head", 153)
	check(BattlePlayLoop.held_item_code(in_hand) == 153 and BattlePlayLoop.EquipmentRules.equipped_code(BattlePlayLoop.unit(in_hand, "leonard")["equipment"], "head") == 0 and BattlePlayLoop.unit(in_hand, "leonard")["inventory"] == BattlePlayLoop.unit(full, "leonard")["inventory"], "full bag takes the helmet off into the hand")
	check(BattlePlayLoop.unequip_to_hand(original, "head", 153) == original, "with room the take-off stays on the bag path")
	check(BattlePlayLoop.change_equipment(in_hand, "weapon", 7, 3) == in_hand and BattlePlayLoop.return_hand(in_hand, 153) == in_hand, "a held piece blocks other commands and a full bag keeps it in the hand")
	var swapped := BattlePlayLoop.swap_hand_with_bag(in_hand, 7, 3, 153)
	check(BattlePlayLoop.held_item_code(swapped) == 3 and BattlePlayLoop.unit(swapped, "leonard")["inventory"] == [241, 241, 241, 241, 241, 241, 241, 153], "full-bag row pick: the row's item to the hand, the held piece into slot 8")
	var hand_worn := BattlePlayLoop.equip_from_hand(swapped, "weapon", 3)
	check(BattlePlayLoop.unit(hand_worn, "leonard")["weapon_code"] == 3 and BattlePlayLoop.held_item_code(hand_worn) == 2 and BattlePlayLoop.unit(hand_worn, "leonard")["inventory"] == [241, 241, 241, 241, 241, 241, 241, 153], "held weapon goes on and the old weapon comes into the hand")
	check(BattlePlayLoop.equip_from_hand(hand_worn, "head", 2) == hand_worn, "a wrong slot keeps the hand")
	var hand_dropped := BattlePlayLoop.discard_hand(hand_worn, 2)
	check(not hand_dropped.has("held_item") and BattlePlayLoop.unit(hand_dropped, "leonard")["inventory"] == [241, 241, 241, 241, 241, 241, 241, 153] and BattlePlayLoop.change_equipment(hand_dropped, "head", 7, 153) != hand_dropped, "丟棄 clears a non-important hand and frees the other commands")
	var roomy := in_hand.duplicate(true)
	BattlePlayLoop.unit_ref(roomy, "leonard")["inventory"][7] = 0
	var hand_back := BattlePlayLoop.return_hand(roomy, 153)
	check(not hand_back.has("held_item") and BattlePlayLoop.unit(hand_back, "leonard")["inventory"] == [241, 241, 241, 241, 241, 241, 241, 153], "with room the held piece goes back first-empty")
	var keepsake := full.duplicate(true)
	BattlePlayLoop.unit_ref(keepsake, "leonard")["inventory"][7] = 281
	var important_hand := BattlePlayLoop.swap_hand_with_bag(BattlePlayLoop.unequip_to_hand(keepsake, "head", 153), 7, 281, 153)
	check(BattlePlayLoop.held_item_code(important_hand) == 281 and BattlePlayLoop.discard_hand(important_hand, 281) == important_hand, "丟棄 keeps an important item in the hand")
	for request in [["head", 1, 3], ["weapon", 0, 3], ["unknown", 1, 3]]:
		check(BattlePlayLoop.change_equipment(original, request[0], request[1], request[2]) == original, "wrong slot/stale selection fails atomically")
	for key in ["battle_outcome", "attacked_this_action", "interaction"]:
		var invalid := original.duplicate(true)
		invalid[key] = BattleOutcome.VICTORY_SCRIPT if key == "battle_outcome" else (true if key == "attacked_this_action" else "ai_resolving")
		check(BattlePlayLoop.change_equipment(invalid, "weapon", 1, 3) == invalid, "invalid phase rejects: " + key)
	var locked := original.duplicate(true)
	TestSuite.own(locked, "equipment_items")["2"]["unequip_blocked"] = true
	check(BattlePlayLoop.change_equipment(locked, "weapon", 1, 3) == locked, "old equipment lock rejects complete transaction")
	for field in ["attack_power", "has_magic", "base_resist_by_type"]:
		var incomplete := original.duplicate(true)
		var incomplete_unit := BattlePlayLoop.unit_ref(incomplete, "leonard")
		incomplete_unit["growth_profile"]["source"].erase(field)
		incomplete_unit["pending_stat_points"] = 5
		incomplete_unit["exp"] = 99
		check(BattlePlayLoop.change_equipment(incomplete, "weapon", 1, 3) == incomplete, "incomplete source preserves inventory/equipment/stats: " + field)
		check(ProgressionRules.apply_allocation(incomplete_unit, {"str": 1}, incomplete["equipment_items"]) == incomplete_unit, "incomplete source does not spend growth points")
		check(ProgressionRules.resolve_experience(incomplete_unit, 1, incomplete["equipment_items"]) == incomplete_unit, "incomplete source does not partially level up")
	var absent_effect := original.duplicate(true)
	TestSuite.own(absent_effect, "equipment_items")["3"]["effects"].erase("attack")
	check(BattlePlayLoop.change_equipment(absent_effect, "weapon", 1, 3) == absent_effect, "missing new-item effects reject before inventory commit")
	var invalid_roster: Array = BattleFixture.loop()["units"].duplicate(true)
	for entry in invalid_roster:
		if entry["id"] == "leonard":
			entry["growth_profile"]["source"].erase("speed")
	var invalid_scene := BattleFixture.loop(invalid_roster)
	check(not invalid_scene["scenario_ok"] and invalid_scene["scenario_error"] == "invalid_growth_source_speed", "invalid initial growth source fails the scenario explicitly")
	var wrong_job := actor.duplicate(true)
	wrong_job["growth_profile"]["job_code"] = 83
	check(EquipmentRules.replace(wrong_job, "weapon", 1, 3, original["equipment_items"])["reason"] == "wrong_job", "class eligibility is checked before replacement")
	var enemy := original.duplicate(true)
	BattlePlayLoop.unit_ref(enemy, "leonard")["player_commandable"] = false
	check(BattlePlayLoop.change_equipment(enemy, "weapon", 1, 3) == enemy, "non-commandable actor rejects equipment mutation")
	var dead := original.duplicate(true)
	BattlePlayLoop.unit_ref(dead, "leonard")["hp"] = 0
	check(BattlePlayLoop.change_equipment(dead, "weapon", 1, 3) == dead, "dead actor rejects equipment mutation")
	var helmet_off := BattlePlayLoop.change_equipment(original, "head", -1, 0)
	check(BattlePlayLoop.unit(helmet_off, "leonard")["combat_profile"]["live_defense"] == 37, "head slot contributes defense, not attack")
	var helmet_slot: int = BattlePlayLoop.unit(helmet_off, "leonard")["inventory"].find(153)
	var helmet_on := BattlePlayLoop.change_equipment(helmet_off, "head", helmet_slot, 153)
	check(BattlePlayLoop.unit(helmet_on, "leonard")["combat_profile"]["live_defense"] == 43, "re-equipping helmet restores only its contribution")
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
			BattlePlayLoop.unit_ref(ready, "leonard")["inventory"] = [accessory, 0, 0, 0, 0, 0, 0, 0]
			var equipped := BattlePlayLoop.change_equipment(ready, slot, 0, accessory)
			check(EquipmentRules.equipped_code(BattlePlayLoop.unit(equipped, "leonard")["equipment"], slot) == accessory, "accessory enters selected slot: " + slot)
			var removed := BattlePlayLoop.change_equipment(equipped, slot, -1, 0)
			check(BattlePlayLoop.unit(removed, "leonard")["inventory"] == [accessory, 0, 0, 0, 0, 0, 0, 0], "accessory removal returns exact item: " + slot)


func saved_native_growth_cases() -> void:
	var packet: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://docs/evidence_packets/static_reverse/original_growth_refresh.json"))
	var source := BattlePlayLoop.unit(BattleFixture.loop(), "leonard")
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
			var result := ProgressionRules.refresh_growth_stats(unit, EquipmentCatalog.items())
			var expected: Dictionary = fixture["native_equipped" if equipped else "native_unequipped"]
			for field in mapping:
				check(result[mapping[field]] == expected[field], "saved native fixture " + fixture["case"] + ": " + field)
			for field in profile_mapping:
				if field == "resist_by_type":
					compare_numbers(result["combat_profile"][field], expected[field], "saved native fixture " + fixture["case"])
				else:
					check(result["combat_profile"][profile_mapping[field]] == expected[field], "saved native fixture " + fixture["case"] + ": " + field)
	# Synthetic catalog case verifies clamping and no healing, not original execution.
	var catalog := EquipmentCatalog.items()
	catalog["153"]["effects"]["max_hp"] = 100
	catalog["153"]["effects"]["resist_by_type"]["0"] = 100
	source["hp"] = 17
	var boosted := ProgressionRules.refresh_growth_stats(source, catalog)
	check(boosted["max_hp"] == 130 and boosted["hp"] == 17 and boosted["combat_profile"]["resist_by_type"]["0"] == 80, "equipment refresh clamps resistance and preserves wounded HP")
	boosted["hp"] = 100
	var restored := ProgressionRules.refresh_growth_stats(boosted, EquipmentCatalog.items())
	check(restored["hp"] == 30, "lowering max HP clamps current HP once")


func transfer_cases() -> void:
	var loop := controlled()
	var actor := BattlePlayLoop.unit_ref(loop, "leonard")
	var ally := BattlePlayLoop.unit_ref(loop, "enemy023_1")
	ally["coord"] = actor["coord"] + Vector2i.RIGHT
	ally["inventory"] = [241, 241, 241, 241, 241, 241, 241, 241]
	var session := BattlePlayLoop.begin_give(loop)
	check(BattlePlayLoop.confirm_give(session, ally["id"], 1, 241, -1, 0, session["item_revision"]) == session, "giving without choosing an exchange to a full recipient preserves inventories and action")
	actor["inventory"] = [241, 246, 241, 0, 0, 0, 0, 0]
	actor["hp"] = 10
	var used := BattlePlayLoop.use_item(loop, "241", "leonard", 2)
	check(BattlePlayLoop.unit(used, "leonard")["inventory"] == [241, 246, 0, 0, 0, 0, 0, 0], "use consumes the selected duplicate slot")
	check(BattlePlayLoop.use_item(loop, "241", "leonard", 1) == loop, "stale use index cannot consume another item")


func important_item_cases() -> void:
	var loop := controlled()
	var actor := BattlePlayLoop.unit_ref(loop, "leonard")
	loop["pending_move"] = true
	loop["pending_move_from"] = actor["coord"] - Vector2i.DOWN
	loop["moved_this_action"] = true
	var catalog: Dictionary = loop["equipment_items"]
	for code in [281, 282, 283, 284, 285]:
		actor["inventory"] = [241, code, 246, 0, 0, 0, 0, 0]
		var before := loop.duplicate(true)
		check(BattlePlayLoop.discard_item(loop, str(code), 1) == before, "important rejection preserves all state including queue and pending move")
	actor["inventory"] = [281, 241, 246, 0, 0, 0, 0, 0]
	var ordinary := BattlePlayLoop.discard_item(loop, "241", 1)
	check(BattlePlayLoop.unit(ordinary, "leonard")["inventory"] == [281, 246, 0, 0, 0, 0, 0, 0], "normal discard removes only the requested non-important slot")
	check(ordinary["pending_move"] and ordinary["turn_queue"] == loop["turn_queue"], "ordinary discard preserves pending movement and the current action")
	check(BattlePlayLoop.discard_item(ordinary, "241", 1) == ordinary, "completed discard cannot repeat")
	check(not InventoryRules.discard(actor["inventory"], 1, 9999, catalog)["ok"], "missing catalog entry cannot silently authorize discard")
	var missing := catalog.duplicate(true)
	missing["241"].erase("important")
	check(InventoryRules.discard_error(241, missing) == "missing_item_discard_rule", "missing important flag rejects explicitly")
	var unrelated_lock := catalog.duplicate(true)
	unrelated_lock["241"]["unequip_blocked"] = true
	check(InventoryRules.discard(actor["inventory"], 1, 241, unrelated_lock)["ok"], "unequip lock is not confused with the discard restriction")
	var ally := BattlePlayLoop.unit_ref(loop, "enemy023_1")
	ally["coord"] = actor["coord"] + Vector2i.RIGHT
	var session := BattlePlayLoop.begin_give(loop)
	var given := BattlePlayLoop.confirm_give(session, ally["id"], 0, 281, -1, 0, session["item_revision"])
	check(BattlePlayLoop.unit(given, ally["id"])["inventory"].has(281), "discard-only restriction does not invent an important-item transfer ban")


func discard_action_cases() -> void:
	for moved in [false, true]:
		var loop := controlled()
		BattlePlayLoop.unit_ref(loop, "leonard")["inventory"] = [241, 241, 246, 0, 0, 0, 0, 0]
		var origin: Vector2i = BattlePlayLoop.unit(loop, "leonard")["coord"]
		if moved:
			var destinations: Array = BattlePlayLoop.movement_cells(loop, "leonard").filter(func(cell): return cell != origin)
			check(not destinations.is_empty(), "discard fixture has a legal move")
			if destinations.is_empty():
				continue
			loop = BattlePlayLoop.move_unit_to(BattlePlayLoop.choose_command(loop, "move"), destinations[0])
		var original := loop.duplicate(true)
		var expected := loop.duplicate(true)
		BattlePlayLoop.unit_ref(expected, "leonard")["inventory"] = [241, 246, 0, 0, 0, 0, 0, 0]
		var discarded := BattlePlayLoop.discard_item(loop, "241", 0)
		check(discarded == expected, "discard only changes the requested inventory, including after a move")
		check(loop == original, "discard does not mutate its input snapshot")
		check(BattlePlayLoop.choose_command(discarded, "attack")["interaction"] == "attack_select", "attack remains available after discard")
		if moved:
			var cancelled := BattlePlayLoop.cancel_pending_move(discarded)
			check(BattlePlayLoop.unit(cancelled, "leonard")["coord"] == origin and not cancelled["moved_this_action"], "discard does not prevent cancelling an uncommitted move")
			check(BattlePlayLoop.unit(cancelled, "leonard")["inventory"] == BattlePlayLoop.unit(discarded, "leonard")["inventory"], "movement cancellation cannot restore a discarded item")
		else:
			check(BattlePlayLoop.choose_command(discarded, "move")["interaction"] == "move_select", "move remains available after discard")
		for field in ["interaction", "battle_outcome", "attacked_this_action"]:
			var invalid := original.duplicate(true)
			invalid[field] = "ai_resolving" if field == "interaction" else (BattleOutcome.VICTORY_SCRIPT if field == "battle_outcome" else true)
			check(BattlePlayLoop.discard_item(invalid, "241", 0) == invalid, "free discard still rejects invalid action state: " + field)


# ---- run_inventory_equipment_tests.gd ----
const ActionBudgetRules = preload("res://game/sim/ActionBudgetRules.gd")
func controlled_give_exchange() -> Dictionary:
	var loop := BattleFixture.loop()
	for index in range(loop["turn_queue"]["slots"].size()):
		if loop["turn_queue"]["slots"][index]["id"] == "leonard":
			loop["turn_queue"]["index"] = index
	loop = BattlePlayLoop.select_player_unit(loop, "leonard")
	var actor := BattlePlayLoop.unit_ref(loop, "leonard")
	actor["inventory"] = [241, 241, 246, 281, 0, 0, 0, 0]
	var ally := BattlePlayLoop.unit_ref(loop, "enemy023_1")
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
	return BattlePlayLoop.confirm_give(loop, "enemy023_1", index, int(BattlePlayLoop.unit(loop, "leonard")["inventory"][index]), target, int(BattlePlayLoop.unit(loop, "enemy023_1")["inventory"][target]), int(loop["item_revision"]))


func run_give_exchange() -> void:
	pure_cases()
	session_cases()
	movement_cases()
func pure_cases() -> void:
	var packet: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://docs/evidence_packets/static_reverse/original_give_exchange.json"))
	for case in packet["examples"]:
		var actual := InventoryRules.exchange(case["sender"], int(case["index"]), int(case["sender"][int(case["index"])]), case["receiver"], int(case["target"]), int(case["receiver"][int(case["target"])]))
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
					var result := InventoryRules.exchange(a, index, a[index], b, target, b[target])
					check(result["ok"] and totals(result["sender"], result["receiver"]) == totals(a,b), "all occupancy boundaries conserve duplicate items")
					check(result["sender"].size() == 8 and result["receiver"].size() == 8, "all exchange outputs retain eight slots")
					check(original == [a,b], "pure exchange never mutates either input")
	check(not InventoryRules.exchange([241,0,0,0,0,0,0,0], 0, 241, [246,246,246,246,246,246,246,246], -1, 0)["ok"], "full bag needs explicit exchange choice")
	for index in [-2, 8]:
		check(not InventoryRules.exchange([241,0,0,0,0,0,0,0], index, 241, [0,0,0,0,0,0,0,0], 0, 0)["ok"], "invalid source selection rejected")
	check(not InventoryRules.exchange([241,0,0,0,0,0,0,0], 0, 241, [246,0,0,0,0,0,0,0], 0, 241)["ok"], "stale expected target cannot swap a different item")
	check(not InventoryRules.exchange([241,0], 0, 241, [0,0,0,0,0,0,0,0], 0, 0)["ok"], "malformed bags rejected before mutation")
	check(ActionBudgetRules.ends_action("use") and not ActionBudgetRules.ends_action("drop") and not ActionBudgetRules.ends_action("equip"), "common ordinary item policy matrix")
	check(not ActionBudgetRules.ends_action("give", false) and ActionBudgetRules.ends_action("give", true), "Give settles at session exit")


func session_cases() -> void:
	var original := controlled_give_exchange()
	var started := BattlePlayLoop.begin_give(original)
	check(started["interaction"] == "give_session" and BattlePlayLoop.begin_give(started) == started, "begin is explicit and cannot reset an existing session")
	var first := confirm(started, 0, 2)
	check(BattlePlayLoop.unit(first, "leonard")["inventory"] == [241,246,281,0,0,0,0,0], "give removes selected duplicate from sender in order")
	check(BattlePlayLoop.unit(first, "enemy023_1")["inventory"] == [246,241,241,0,0,0,0,0], "recipient duplicate occupies a new slot")
	check(first["turn_queue"] == original["turn_queue"] and first["give_session"]["action_used"], "successful give retains current queue and marks the session used")
	check(BattlePlayLoop.confirm_give(first, "enemy023_1", 0, 241, -1, 0, started["item_revision"]) == first, "stale request cannot consume adjacent identical item")
	var second := confirm(first, 0, 3)
	check(BattlePlayLoop.unit(second, "leonard")["inventory"] == [246,281,0,0,0,0,0,0], "second give in same session works")
	var finished := BattlePlayLoop.finish_give(second, second["item_revision"])
	check(finished["turn_queue"] != original["turn_queue"] and finished["give_session"].is_empty(), "close after multiple transfers ends exactly one actor action")
	check(BattlePlayLoop.finish_give(finished, second["item_revision"]) == finished, "duplicate finish does not advance a second actor")
	var cancelled := BattlePlayLoop.finish_give(started, started["item_revision"])
	check(gameplay(cancelled) == gameplay(original), "unconfirmed session cancellation restores all gameplay state")
	var reopened := BattlePlayLoop.begin_give(cancelled)
	check(BattlePlayLoop.confirm_give(reopened, "enemy023_1", 0, 241, -1, 0, started["item_revision"]) == reopened, "cancelled-session request cannot enter a reopened session")
	var same := confirm(started, 0, 1)
	check(not same["give_session"]["action_used"], "same-code exchange does not set native action flag")
	check(BattlePlayLoop.unit(same, "leonard")["inventory"] == [241,246,281,241,0,0,0,0], "same-code exchange still applies original slot ordering")
	var same_finished := BattlePlayLoop.finish_give(same, same["item_revision"])
	check(same_finished["turn_queue"] == original["turn_queue"] and same_finished["selected_unit_id"] == "leonard", "same-code-only session returns player control")
	var charged_then_same := confirm(first, 0, 1)
	check(charged_then_same["give_session"]["action_used"], "same-code later exchange cannot erase prior action charge")
	var full := controlled_give_exchange()
	BattlePlayLoop.unit_ref(full, "leonard")["inventory"] = [241,241,241,241,241,241,241,241]
	BattlePlayLoop.unit_ref(full, "enemy023_1")["inventory"] = [246,241,241,241,241,241,241,241]
	full = BattlePlayLoop.begin_give(full)
	var exchanged := confirm(full, 0, 0)
	check(BattlePlayLoop.unit(exchanged, "leonard")["inventory"] == [241,241,241,241,241,241,241,246], "full sender gets returned item in freed tail")
	check(BattlePlayLoop.unit(exchanged, "enemy023_1")["inventory"] == [241,241,241,241,241,241,241,241], "full target receives incoming after removal and compaction")
	var important := confirm(started, 3, 0)
	check(BattlePlayLoop.unit(important, "enemy023_1")["inventory"].has(281), "important restriction remains discard-only")


func movement_cases() -> void:
	var original := controlled_give_exchange()
	var origin: Vector2i = BattlePlayLoop.unit(original, "leonard")["coord"]
	var moving := BattlePlayLoop.choose_command(original, "move")
	var cells: Array = BattlePlayLoop.movement_cells(moving, "leonard").filter(func(cell): return cell != origin)
	check(not cells.is_empty(), "movement fixture has a legal destination")
	if cells.is_empty(): return
	var moved := BattlePlayLoop.move_unit_to(moving, cells[0])
	BattlePlayLoop.unit_ref(moved, "enemy023_1")["coord"] = cells[0] + Vector2i.RIGHT
	var started := BattlePlayLoop.begin_give(moved)
	check(BattlePlayLoop.cancel_pending_move(started) == started, "movement cannot be rolled back while a give session is open")
	var cancelled := BattlePlayLoop.finish_give(started, started["item_revision"])
	check(gameplay(cancelled) == gameplay(moved), "cancel Give retains pending move and all inventory state")
	check(BattlePlayLoop.unit(BattlePlayLoop.cancel_pending_move(cancelled), "leonard")["coord"] == origin, "no-transfer Give cancellation leaves movement rollback available")
	var received := confirm(started, 0, 2)
	check(received["pending_move"] and received["turn_queue"] == moved["turn_queue"], "move-then-give waits for session exit")
	var finished := BattlePlayLoop.finish_give(received, received["item_revision"])
	check(not finished["pending_move"] and BattlePlayLoop.unit(finished, "leonard")["coord"] == cells[0], "ending changed Give session commits the move")
	check(BattlePlayLoop.cancel_pending_move(finished) == finished, "completed give cannot roll back committed movement")
