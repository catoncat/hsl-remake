extends SceneTree
const TestSuite = preload("res://tests/support/TestSuite.gd")
const Loop = preload("res://game/sim/loop/BattlePlayLoop.gd")
const LoopAI = preload("res://game/sim/loop/BattleLoopAI.gd")
const Status = preload("res://game/sim/StatusEffectRules.gd")
const Item = preload("res://game/sim/ItemUseRules.gd")
const Resolution = preload("res://game/sim/SkillResolutionRules.gd")
const BattleFixture = preload("res://tests/support/BattleFixture.gd")
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
	var player := Loop._unit(loop, "leonard")
	player["live_speed"] = 100
	var ally := Loop._unit(loop, "enemy023_1")
	ally["live_speed"] = 99
	ally["player_commandable"] = true
	ally["battle_actor_role"] = Loop.ROLE_PLAYER
	ally["coord"] = player["coord"] + Vector2i.RIGHT
	loop["turn_queue"] = Loop.CoreTurnQueue.rebuild(loop["units"])
	return Loop.select_player_unit(loop, "leonard")


func afflict(actor: Dictionary, turns: int, power: int, silence: int = 0) -> void:
	actor["status_flags"] = (1 if turns > 0 else 0) | (2 if silence > 0 else 0)
	actor["status_counters"] = {"poison": (power << 16) | turns if turns > 0 else 0, "paralysis": 0, "no_magic": silence}


func run() -> void:
	check(BattleFixture.loop()["scenario_ok"], "normal bootstrap has explicit healthy status data")
	for hp in [1, 3, 30]:
		for power in [0, 2, 20, 65535]:
			for turns in [1, 2, 9]:
				var actor := Loop.unit(controlled(), "leonard").duplicate(true)
				actor["hp"] = hp
				afflict(actor, turns, power, 2)
				var before := actor.duplicate(true)
				var result := Status.after_action(actor)
				check(result["ok"], "supported packed status words accepted")
				var next: Dictionary = result["changes"]
				check(next["hp"] == maxi(1, hp - power), "poison damage clamps at one HP without healing")
				check(next["status_counters"]["poison"] == (0 if turns == 1 else (power << 16) | (turns - 1)), "duration decays without corrupting potency; expiry clears entire word")
				check(next["status_flags"] == (2 if turns == 1 else 3) and next["status_counters"]["no_magic"] == 1, "independent no-magic duration survives poison expiry")
				check(actor == before, "pure status proposal preserves input")
	item_cases()
	action_cases()
	skill_cases()
	await ui_cases()
	print("STATUS_EFFECT_TESTS_", "PASS" if failures.is_empty() else "FAIL", " checks=", checks)
	quit(0 if failures.is_empty() else 1)


func item_cases() -> void:
	var loop := controlled()
	var actor := Loop._unit(loop, "leonard")
	afflict(actor, 3, 7, 2)
	var initial := loop.duplicate(true)
	var used := Loop.use_item(loop, "246", "leonard", 3)
	var cured := Loop.unit(used, "leonard")
	check(cured["hp"] == actor["hp"] and not Status.poisoned(cured), "full-health antidote clears poison before post-action damage")
	check(cured["status_counters"] == {"poison": 0, "paralysis": 0, "no_magic": 1} and cured["status_flags"] == 2, "antidote preserves unrelated silence then owner duration ticks once")
	check(cured["inventory"] == [241, 241, 241, 0, 0, 0, 0, 0] and used["selected_unit_id"] == "enemy023_1", "consume exactly one antidote and reach the next ally")
	check(Loop.use_item(used, "246", "leonard", 3) == used and loop == initial, "repeat after handoff is inert and original input remains intact")
	var ally := Loop._unit(loop, "enemy023_1")
	afflict(ally, 1, 9)
	var given := Loop.use_item(loop, "246", ally["id"], 3)
	check(not Status.poisoned(Loop.unit(given, ally["id"])), "antidote can cure an adjacent full-health ally")
	check(Loop.unit(given, "leonard")["hp"] == actor["hp"] - 7 and Loop.unit(given, "leonard")["status_counters"]["poison"] == (7 << 16) | 2, "only the acting user's own poison ticks after ally cure")
	for hp in [10, 30]:
		var healthy := controlled()
		Loop._unit(healthy, "leonard")["hp"] = hp
		var spent := Loop.use_item(healthy, "246", "leonard", 3)
		check(spent["item_use_sequence"] == healthy["item_use_sequence"] + 1 and Loop.unit(spent, "leonard")["inventory"].count(246) == Loop.unit(healthy, "leonard")["inventory"].count(246) - 1 and not spent["last_item_use"]["cured_poison"], "healthy antidote use still spends one 246 without a cure (0x444aba)")
	for target in ["missing", "enemy021_1"]:
		check(Loop.use_item(loop, "246", target, 3) == loop, "invalid target cannot mutate items, health, status or action")
	for value in [-1, 1.5, "2", null]:
		var invalid := loop.duplicate(true)
		Loop._unit(invalid, "leonard")["status_counters"]["poison"] = value
		check(Loop.use_item(invalid, "246", "leonard", 3) == invalid, "invalid counter refuses the complete transaction")
	var missing := loop.duplicate(true)
	TestSuite.own(missing, "consumables")["246"].erase("cure_poison")
	check(Loop.use_item(missing, "246", "leonard", 3) == missing, "missing cure rule cannot silently consume the item")
	var raw: Array = BattleFixture.loop()["units"].duplicate(true)
	raw[0].erase("status_counters")
	check(not BattleFixture.loop(raw)["scenario_ok"], "missing initial status state fails explicitly")


func action_cases() -> void:
	var loop := controlled()
	var actor := Loop._unit(loop, "leonard")
	afflict(actor, 2, 5, 1)
	var original := loop.duplicate(true)
	var dropped := Loop.discard_item(loop, "241", 0)
	check(Loop.unit(dropped, "leonard")["status_counters"] == actor["status_counters"] and dropped["turn_queue"] == loop["turn_queue"], "free Drop does not tick poison or no-magic")
	var equipped := Loop.change_equipment(dropped, "head", -1, 0)
	check(Loop.unit(equipped, "leonard")["status_counters"] == actor["status_counters"] and Loop.unit(equipped, "leonard")["hp"] == actor["hp"], "free equipment refresh preserves status without ticking")
	var moved := Loop.choose_command(equipped, "move")
	var destinations := Loop.movement_cells(moved, "leonard")
	for cell in destinations:
		if cell != actor["coord"]:
			moved = Loop.move_unit_to(moved, cell)
			break
	var cancelled := Loop.cancel_pending_move(moved)
	check(Loop.unit(cancelled, "leonard")["coord"] == actor["coord"] and Loop.unit(cancelled, "leonard")["status_counters"] == actor["status_counters"], "movement cancellation restores location but does not advance status time")
	cancelled = Loop.cancel_interaction(cancelled)
	var ended := Loop.choose_command(cancelled, "wait")
	check(ended["selected_unit_id"] == "enemy023_1" and Loop.unit(ended, "leonard")["hp"] == actor["hp"] - 5, "Wait applies poison once and reaches exactly the next actor")
	check(Loop.unit(ended, "leonard")["status_counters"] == {"poison": (5 << 16) | 1, "paralysis": 0, "no_magic": 0}, "expiry clears no-magic while preserving poison potency")
	check(loop == original, "all combined operations preserve the supplied input state")
	for command in ["attack", "special"]:
		var ready := controlled()
		var player := Loop._unit(ready, "leonard")
		player["hp"] = 100
		player["max_hp"] = 100
		afflict(player, 2, 5)
		player["stamina"] = 20
		var foe := Loop._unit(ready, "enemy021_1")
		foe["coord"] = player["coord"] + Vector2i.UP
		foe["hp"] = 100
		var selected := Loop.choose_command(ready, command)
		if command == "special": selected = Loop.choose_special(selected, "special:magicOTHER:magicCode01")
		var attack := Loop.attack_target(selected, foe["id"], func(_n): return 0)
		check(Loop.unit(attack, "leonard")["status_counters"] == player["status_counters"], "offense does not tick status while presentation is pending")
		var finished := Loop.finish_exhausted_action(attack)
		check(finished["selected_unit_id"] == "enemy023_1" and Loop.unit(finished, "leonard")["hp"] == Loop.unit(attack,"leonard")["hp"] - 5, "offense completion adds one poison tick after all committed primary/counter HP loss: " + command)
		check(Loop.finish_exhausted_action(finished) == finished, "duplicate offense completion cannot tick another actor")


func skill_cases() -> void:
	var loop := controlled()
	var mage := Loop._unit(loop, "enemy026_1")
	afflict(mage, 0, 0, 1)
	var target := Loop._unit(loop, "leonard")
	mage["coord"] = target["coord"] + Vector2i.UP
	var before := loop.duplicate(true)
	var draws: Array = []
	var blocked := Resolution.resolve(mage, target, "magic:magicAIR:magicCode01", loop["skill_book"]["skills"]["magic:magicAIR:magicCode01"]["fields"], loop["skill_book"], loop["skill_target_data"], loop["equipment_items"], mage["coord"], loop["map_size"], func(n): draws.append(n); return 0)
	check(not blocked["ok"] and blocked["reason"] == "magic_disabled_by_status" and draws.is_empty() and loop == before, "shared spell rejection precedes RNG, MP, HP and movement")
	check(LoopAI._try_skill_turn(loop, mage["id"], [target], func(_n): return 0).is_empty() and loop == before, "AI uses the same no-magic restriction before planning a spell")
	afflict(target, 0, 0, 2)
	target["stamina"] = 20
	check(Loop.can_use_special(loop, "leonard"), "no-magic does not prohibit a supported special")
	mage.merge(Status.after_action(mage)["changes"], true)
	check(Resolution.available(mage, "magic:magicAIR:magicCode01", loop["skill_book"]["skills"]["magic:magicAIR:magicCode01"]["fields"], loop["skill_book"], loop["skill_target_data"], loop["equipment_items"])["ok"], "spell becomes eligible after the owner's silence expires")
	var ai := controlled()
	var ai_mage := Loop._unit(ai, "enemy026_1")
	# This case isolates the post-counter status tail. A source-stocked antidote
	# now correctly selects self-cure first; that route has dedicated item tests.
	ai_mage["inventory"] = [0,0,0,0,0,0,0,0]
	ai_mage["hp"] = 1000
	ai_mage["max_hp"] = 1000
	ai_mage["coord"] = Loop.unit(ai, "leonard")["coord"] + Vector2i.UP
	ai_mage["live_speed"] = 101
	afflict(ai_mage, 2, 5, 1)
	ai["turn_queue"] = Loop.CoreTurnQueue.rebuild(ai["units"])
	ai["selected_unit_id"] = ""
	ai["interaction"] = "ai_resolving"
	var ai_done := Loop.step_ai_turn(ai, func(_n): return 0)
	var after := Loop.unit(ai_done, ai_mage["id"])
	check(after["mp"] == ai_mage["mp"] and ai_done["last_ai_action"].get("kind") != "magic", "silenced AI completes a non-magic action without spending MP")
	var counter_damage := int(ai_done["last_ai_action"].get("counter",{}).get("actual_damage",0))
	check(after["hp"] == ai_mage["hp"] - counter_damage - 5 and after["status_flags"] == 1 and after["status_counters"] == {"poison": (5 << 16) | 1, "paralysis": 0, "no_magic": 0}, "AI without a cure uses one post-action status step after the actual counter receipt")
	check(ai_done["selected_unit_id"] == "leonard" and ai_done["turn_queue"]["round"] == ai["turn_queue"]["round"], "AI status step preserves queue order and does not rebuild mid-round")


func ui_cases() -> void:
	var scene = load("res://game/battle/scene/BattleSceneRuntime.tscn").instantiate()
	scene.scenario_path = BattleFixture.PATH; scene.startup_mode = "dev_first_control"
	root.add_child(scene)
	await process_frame
	scene.start_dev_first_control_harness()
	scene.set_process(false)
	scene.apply_loop(controlled(), "test")
	var actor := Loop._unit(scene.play_loop, "leonard")
	afflict(actor, 2, 7, 2)
	scene.apply_loop(scene.play_loop, "test")
	scene.menus.choose_command("item")
	scene.item_panel.menu._process(0.25)
	scene.item_panel.menu.get_node("UseCommand").pressed.emit()
	scene.item_panel._select_item("246", 3)
	check(not scene.item_panel.target_buttons["leonard"].disabled, "full-health poisoned target stays selectable for antidote")
	check(not scene.item_panel.target_buttons["enemy023_1"].disabled and scene.item_panel.target_buttons["enemy023_1"].tooltip_text.ends_with("沒有需要解除的中毒；使用仍會消耗"), "healthy adjacent ally stays selectable and the preview warns the antidote is still spent (0x44492a..0x4449b6 has no need check)")
	var before: Dictionary = scene.play_loop.duplicate(true)
	scene.item_panel.cancel()
	scene.menus.use_inventory_item("246", "leonard")
	check(scene.play_loop == before, "cancelled antidote callback is inert")
	scene.item_panel._select_item("246", 3)
	scene.item_panel.target_buttons["leonard"].pressed.emit()
	check(not scene.item_panel.visible and scene.selected_unit_id == "enemy023_1" and not scene.ai_playback_active, "status-only item success closes UI and hands off without skipping next ally")
	var used: Dictionary = scene.play_loop.duplicate(true)
	scene.menus.use_inventory_item("246", "leonard")
	check(scene.play_loop == used and not Status.poisoned(Loop.unit(used, "leonard")), "duplicate signal cannot apply or hand off twice")
	scene.queue_free()
	await process_frame
	await create_timer(0.3).timeout
