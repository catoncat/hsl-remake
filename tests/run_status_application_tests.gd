extends SceneTree
const TestSuite = preload("res://tests/support/TestSuite.gd")
const BattlePlayLoop = preload("res://game/sim/loop/BattlePlayLoop.gd")
const BattleLoopAI = preload("res://game/sim/loop/BattleLoopAI.gd")
const StatusEffectRules = preload("res://game/sim/StatusEffectRules.gd")
const StatusApplicationRules = preload("res://game/sim/StatusApplicationRules.gd")
const NativeMagicRollRules = preload("res://game/sim/NativeMagicRollRules.gd")
const SkillResolutionRules = preload("res://game/sim/SkillResolutionRules.gd")
const BattleFixture = preload("res://tests/support/BattleFixture.gd")
const BattleOutcome = preload("res://game/sim/BattleOutcome.gd")
const POISON := "magic:magicAIR:magicCode05"
const SEAL := "magic:magicMIND:magicCode02"
var failures: Array[String] = []
var checks := 0


func _initialize() -> void: call_deferred("run")


func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error(message)


static func fixture() -> Dictionary:
	var units: Array = BattleFixture.loop()["units"].duplicate(true)
	var source := BattlePlayLoop.BattleScenario.load_file("res://content/battles/battle_052.json")
	var boss: Dictionary = BattlePlayLoop.BattleScenario.units(source).filter(func(unit): return unit["actor_id"] == "025")[0]
	boss["coord"] = Vector2i(8, 8)
	boss["battle_actor_role"] = BattlePlayLoop.ROLE_PLAYER
	boss["player_commandable"] = true
	boss.erase("player_mode") # the fixture flips his side by battle_actor_role below; without an installed word the side is role-implied
	units.append(boss)
	var loop := BattleFixture.loop(units)
	# The shared initializer now refreshes every source job. Install the bounded
	# cast fixture after that refresh, just as the rendered encounter fixtures do.
	BattlePlayLoop._unit(loop, str(boss["id"])).merge({"live_speed": 100, "mp": 100, "max_mp": 100}, true)
	BattlePlayLoop._unit(loop, "leonard")["live_speed"] = 99
	BattlePlayLoop._unit(loop, "leonard")["coord"] = Vector2i(8, 7)
	BattlePlayLoop._unit(loop, "enemy021_1")["coord"] = Vector2i(9, 8)
	BattlePlayLoop._unit(loop, "enemy021_2")["coord"] = Vector2i(10, 8)
	BattlePlayLoop._unit(loop, "enemy023_1")["coord"] = Vector2i(9, 9)
	loop["turn_queue"] = BattlePlayLoop.CoreTurnQueue.rebuild(loop["units"])
	return BattlePlayLoop.select_player_unit(loop, str(boss["id"]))


func select_poison(loop: Dictionary) -> Dictionary:
	return BattlePlayLoop.choose_magic(BattlePlayLoop.choose_command(loop, "magic"), POISON)


func run() -> void:
	native_roll_cases()
	native_lifecycle_cases()
	merge_cases()
	cast_cases()
	seal_cases()
	decay_cases()
	lifecycle_cases()
	await run_status_effect()
	print("STATUS_APPLICATION_TESTS_", "PASS" if failures.is_empty() else "FAIL", " checks=", checks)
	quit(0 if failures.is_empty() else 1)


func native_roll_cases() -> void:
	var packet: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://docs/evidence_packets/static_reverse/original_status_rolls.json"))
	for case in packet["cases"]:
		var cursor := [0]
		var random := func(bound):
			check(cursor[0] < case["draws"].size(), "pure replay cannot consume unobserved random values")
			if cursor[0] >= case["draws"].size(): return 0
			var draw: Dictionary = case["draws"][cursor[0]]
			check(bound == int(draw["bound"]), "random bound matches original executed helper")
			cursor[0] += 1
			return int(draw["value"])
		var output := NativeMagicRollRules.roll(case["input"], random)
		check(output["value"] == case["native"]["value"] and output["hit_bonus_after"] == case["native"]["hit_bonus_after"], "Godot numerical output matches actual native return")
		check(cursor[0] == case["draws"].size(), "all native random draws replayed once")


func merge_cases() -> void:
	for old_power in [0, 5, 20, 50]:
		for new_power in [5, 25, 50]:
			for duration in [2, 8, 9]:
				var old: int = (old_power << 16) | duration
				var actor := {"hp": 100, "status_flags": 1, "status_counters": {"poison": old, "paralysis": 0, "no_magic": 0}}
				var proposal := StatusEffectRules.apply(actor, "poison", 3, new_power)
				var next: int = proposal["after_word"]
				check((next & 0xffff) == mini(9, duration + 3), "reapplication extends duration and caps at nine")
				check((next >> 16) == (new_power if old_power == 0 else maxi(old_power, (old_power + new_power) / 2)), "poison strength combines without weakening existing power")
	for pair in [[0, 5], [1, 6], [3, 8], [4, 9], [50, 50], [51, 41], [60, 50], [100, 50]]:
		check(StatusApplicationRules.poison_strength(pair[0]) == pair[1], "native potency folding is not a min/max clamp")


func cast_cases() -> void:
	var loop := fixture()
	check(loop["scenario_ok"], "source-owned caster fixture loads")
	var owner: String = loop["selected_unit_id"]
	check(BattlePlayLoop.magic_options(loop, "leonard").is_empty(), "normal Leonard has not gained a magic skill")
	var selected := select_poison(loop)
	check(selected["interaction"] == "attack_select", "source-owned spell selected through Magic command")
	var before := selected.duplicate(true)
	var preparation := SkillResolutionRules.prepare_cast(BattlePlayLoop.unit(selected, owner), BattlePlayLoop.unit(selected, "enemy021_1"), selected["units"], POISON, BattlePlayLoop.skill_fields(selected, POISON), selected["skill_book"], selected["skill_target_data"], selected["equipment_items"], BattlePlayLoop.unit(selected, owner)["coord"], selected["map_size"])
	check(preparation["ok"], "source fixture prepares all status targets: " + str(preparation.get("reason", "")))
	var cast := BattlePlayLoop.attack_target(selected, "enemy021_1", func(_n): return 0)
	check(StatusEffectRules.poisoned(BattlePlayLoop.unit(cast, "enemy021_1")) and StatusEffectRules.poisoned(BattlePlayLoop.unit(cast, "enemy021_2")), "source cross footprint applies poison to both opponents")
	check(not StatusEffectRules.poisoned(BattlePlayLoop.unit(cast, "enemy023_1")), "allied unit in area is not affected by hostile target adapter")
	check(BattlePlayLoop.unit(cast, owner)["mp"] == 90 and cast["turn_queue"] == before["turn_queue"], "area cast charges one fee and waits for presentation")
	check(BattlePlayLoop.unit(cast, "enemy021_1")["hp"] == BattlePlayLoop.unit(before, "enemy021_1")["hp"], "pure poison infliction does not deal immediate HP damage")
	check(selected == before, "cast proposal does not mutate caller input")
	var replay := BattlePlayLoop.attack_target(cast, "enemy021_1", func(_n): check(false, "repeat cast must not draw"); return 0)
	check(replay["units"] == cast["units"] and replay["turn_queue"] == cast["turn_queue"] and replay["last_combat"] == cast["last_combat"], "repeat cast cannot charge, afflict or enqueue presentation twice")
	var other_center := SkillResolutionRules.resolve_cast(BattlePlayLoop.unit(before, owner), BattlePlayLoop.unit(before, "enemy021_2"), before["units"], POISON, BattlePlayLoop.skill_fields(before, POISON), before["skill_book"], before["skill_target_data"], before["equipment_items"], BattlePlayLoop.unit(before, owner)["coord"], before["map_size"], func(_n): return 0)
	check(other_center["receipt"]["defender_id"] == "enemy021_2" and other_center["target_changes"] == other_center["targets"][1]["changes"], "primary receipt and primary changes agree even when center is later in roster order")
	var end := BattlePlayLoop.finish_exhausted_action(cast)
	check(end["selected_unit_id"] == "leonard" and end["turn_queue"]["round"] == cast["turn_queue"]["round"], "one completion reaches next ally without mid-round rebuild")
	check(BattlePlayLoop.finish_exhausted_action(end) == end, "duplicate completion is inert")
	var immune := before.duplicate(true)
	TestSuite.own(immune, "skill_book")["actors"]["021"]["status_capability_flags"] = 0x40
	var draws := [0]
	var protected := BattlePlayLoop.attack_target(immune, "enemy021_1", func(_n): draws[0] += 1; return 0)
	check(draws[0] == 0 and not StatusEffectRules.poisoned(BattlePlayLoop.unit(protected, "enemy021_1")), "all-immune cast skips effect RNG but still settles a valid spell")
	check(BattlePlayLoop.unit(protected, owner)["mp"] == 90 and protected["attacked_this_action"], "immune outcome consumes exactly one cast")
	var repeated := loop.duplicate(true)
	for id in ["enemy021_1", "enemy021_2"]:
		BattlePlayLoop._unit(repeated, id)["status_flags"] = 1
		BattlePlayLoop._unit(repeated, id)["status_counters"]["poison"] = (50 << 16) | 8
	var renewed := BattlePlayLoop.attack_target(select_poison(repeated), "enemy021_1", func(_n): return 0)
	check(BattlePlayLoop.unit(renewed, "enemy021_1")["status_counters"]["poison"] == (50 << 16) | 9, "whole-cast reapplication caps duration and preserves stronger old potency")
	for error in ["secondary_missing", "out_of_range", "dead", "terminal", "poor", "silenced"]:
		var invalid := before.duplicate(true)
		match error:
			"secondary_missing": BattlePlayLoop._unit(invalid, "enemy021_2").erase("status_counters")
			"out_of_range": BattlePlayLoop._unit(invalid, "enemy021_1")["coord"] = Vector2i(20, 20)
			"dead": BattlePlayLoop._unit(invalid, owner)["hp"] = 0
			"terminal": invalid["battle_outcome"] = BattleOutcome.VICTORY_SCRIPT
			"poor": BattlePlayLoop._unit(invalid, owner)["mp"] = 9
			"silenced":
				BattlePlayLoop._unit(invalid, owner)["status_flags"] = 2
				BattlePlayLoop._unit(invalid, owner)["status_counters"]["no_magic"] = 2
		var untouched := invalid.duplicate(true)
		var result := BattlePlayLoop.attack_target(invalid, "enemy021_1", func(_n): check(false, "invalid casts must consume no RNG"); return 0)
		check(result["units"] == untouched["units"] and result["turn_queue"] == untouched["turn_queue"] and not result["attacked_this_action"], "all targets/resource/action fail atomically: " + error)
	var cancelled := BattlePlayLoop.cancel_interaction(before)
	var stale := BattlePlayLoop.attack_target(cancelled, "enemy021_1", func(_n): check(false, "cancel must not draw"); return 0)
	check(stale["units"] == cancelled["units"] and stale["turn_queue"] == cancelled["turn_queue"], "stale target after cancel cannot cast")


func seal_cases() -> void:
	var loop := fixture()
	var actor := BattlePlayLoop._unit(loop, loop["selected_unit_id"])
	actor["actor_id"] = "045" # Numerical fixture with an actual source owner, not a new starting grant.
	var target := BattlePlayLoop._unit(loop, "enemy021_1")
	var fields := BattlePlayLoop.skill_fields(loop, SEAL)
	var result := SkillResolutionRules.resolve(actor, target, SEAL, fields, loop["skill_book"], loop["skill_target_data"], loop["equipment_items"], actor["coord"], loop["map_size"], func(_n): return 0)
	check(result["ok"], "source Seal fixture prepares: " + str(result.get("reason", "")))
	if not result["ok"]: return
	check(result["ok"] and (int(result["target_changes"]["status_flags"]) & 2) != 0 and int(result["target_changes"]["hp"]) < int(target["hp"]), "Seal applies damage then no-magic via shared resolver")
	check(result["caster_changes"]["mp"] == 77, "mixed effect spell charges one fee")
	target["hp"] = 1
	var draws := [0]
	var lethal := SkillResolutionRules.resolve(actor, target, SEAL, fields, loop["skill_book"], loop["skill_target_data"], loop["equipment_items"], actor["coord"], loop["map_size"], func(_n): draws[0] += 1; return 0)
	check(lethal["target_changes"]["defeated"] and lethal["target_changes"]["status_flags"] == 0 and draws[0] == 3, "lethal primary damage skips later status and its random draws")


## 死骸腐靈獄 (magic:magicMIND:magicCode05, wave 9 lane A2): the only MAGIC row with every status bit.
## 0x40aa80 visits Attack, then Paralysis／Poison／NoMagic／Weaken in that order; each status has its
## own proc6 check on status_hit_ratio 30 and (poison／weaken) a 30%-scaled magnitude; 100 MP once.
func decay_cases() -> void:
	const DECAY := "magic:magicMIND:magicCode05"
	var loop := fixture()
	check(loop["skill_book"]["actors"]["059"]["supported_initial_ids"].has(DECAY) and loop["skill_book"]["actors"]["068"]["supported_initial_ids"].has(DECAY), "059／068 declare 死骸腐靈獄 in magic_mind")
	var actor := BattlePlayLoop._unit(loop, loop["selected_unit_id"])
	actor["actor_id"] = "059"
	actor["mp"] = 120
	actor["max_mp"] = 120
	TestSuite.own(loop, "skill_book")["actors"]["025"]["supported_initial_ids"].append(DECAY)
	actor["actor_id"] = "025"
	check(BattlePlayLoop.magic_options(BattlePlayLoop.choose_command(loop, "magic"), actor["id"]).any(func(option): return option["id"] == DECAY and option["quote"]["ok"]), "the learned spell is listed and affordable in the magic menu")
	var picked := BattlePlayLoop.choose_magic(BattlePlayLoop.choose_command(loop, "magic"), DECAY)
	check(picked["interaction"] == "attack_select" and BattlePlayLoop.attack_cells(picked).has(Vector2i(10, 8)), "range5CellCircle target selection opens")
	var target := BattlePlayLoop._unit(picked, "enemy021_2")
	target["hp"] = 900
	target["max_hp"] = 900
	target["combat_profile"]["resist_by_type"]["4"] = 0
	var neighbour := BattlePlayLoop._unit(picked, "enemy021_1")
	neighbour["hp"] = 900
	neighbour["max_hp"] = 900
	var settled := BattlePlayLoop.attack_target(picked, "enemy021_2", func(_n): return 0)
	var receipts: Array = settled.get("last_attack", {}).get("affected_targets", [])
	check(settled["attacked_this_action"] and settled["last_attack"].get("skill_id") == DECAY and BattlePlayLoop.unit(settled, actor["id"])["mp"] == 20, "one 100 MP payment settles the cast")
	var struck_ids: Array = receipts.map(func(receipt): return receipt["defender_id"])
	check(struck_ids.has("enemy021_1") and struck_ids.has("enemy021_2") and not struck_ids.has("leonard"), "the range3CellCircle footprint reaches the neighbour and the center, never the ally")
	for receipt in receipts.filter(func(receipt): return receipt["defender_id"] in ["enemy021_1", "enemy021_2"]):
		var applied: Array = receipt["status_effects"].filter(func(effect): return effect["applied"]).map(func(effect): return effect["status"])
		check(int(receipt["damage"]) > 0 and applied == ["paralysis", "poison", "no_magic", "weaken"], "damage first, then every status in native visit order on a zero roll: " + receipt["defender_id"])
		var unit := BattlePlayLoop.unit(settled, receipt["defender_id"])
		check((int(unit["status_flags"]) & 15) == 15 and StatusEffectRules.weaken_power(unit) >= 2 and (int(unit["status_counters"]["poison"]) >> 16) >= 5, "the target carries paralysis, poison, no-magic and a weaken power after the cast: " + receipt["defender_id"])
		check(int(unit["combat_profile"]["str"]) <= int(BattlePlayLoop.unit(picked, receipt["defender_id"])["combat_profile"]["str"]), "weaken refreshes the live attributes downward: " + receipt["defender_id"])
	var lethal := fixture()
	var caster := BattlePlayLoop._unit(lethal, lethal["selected_unit_id"])
	caster["mp"] = 120
	TestSuite.own(lethal, "skill_book")["actors"]["025"]["supported_initial_ids"].append(DECAY)
	var victim := BattlePlayLoop._unit(lethal, "enemy021_1")
	victim["hp"] = 1
	var draws := [0]
	var killed := SkillResolutionRules.resolve(caster, victim, DECAY, BattlePlayLoop.skill_fields(lethal, DECAY), lethal["skill_book"], lethal["skill_target_data"], lethal["equipment_items"], caster["coord"], lethal["map_size"], func(_n): draws[0] += 1; return 0)
	check(killed["ok"] and killed["target_changes"]["defeated"] and killed["target_changes"]["status_flags"] == 0 and draws[0] == 3 and killed["receipt"]["status_effects"].all(func(effect): return not effect["applied"] and effect["reason"] == "target_defeated"), "a lethal primary hit skips all four status checks and their draws")

func native_lifecycle_cases() -> void:
	var packet: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://docs/evidence_packets/static_reverse/original_status_application.json"))
	for row in packet["application_cases"]:
		var input: Dictionary = row["input"]
		var cursor := [0]
		var draws: Array = row["draws"]
		var target := {"hp": input["hp"], "defeated": input["hp"] == 0, "status_flags": (1 if input["words"]["poison"] else 0) | (2 if input["words"]["no_magic"] else 0), "status_counters": input["words"].duplicate(true)}
		target["status_counters"]["paralysis"] = 0 # The older native packet only authored poison/silence.
		var result := StatusApplicationRules.resolve({"function_mask": 8 if input["status"] == "poison" else 16, "immunities": input["effects"], "roll_input": input}, target, func(bound):
			check(cursor[0] < draws.size() and bound == int(draws[cursor[0]]["bound"]), "application follows native random-call bounds")
			var value := int(draws[cursor[0]]["value"])
			cursor[0] += 1
			return value)
		for key in ["hp", "status_flags"]:
			check(result["target_changes"][key] == row["native"][key], "application proposal matches original executed branch: " + key)
		for key in row["native"]["status_counters"]:
			check(int(result["target_changes"]["status_counters"][key]) == int(row["native"]["status_counters"][key]), "application counter matches original branch: %s actual=%s expected=%s" % [key, result["target_changes"]["status_counters"][key], row["native"]["status_counters"][key]])
		check(result["hit_bonus_after"] == row["native"]["hit_bonus_after"] and cursor[0] == draws.size(), "application matches original bonus and full random sequence")
		check(not row["normal_return"] and row["stop_address"] == "0x40b831", "application evidence remains a prefix, not a whole spell return")
	for row in packet["tick_cases"]:
		var words: Dictionary = row["input"].duplicate(true)
		words["paralysis"] = 0
		var actor := {"hp": 100, "status_flags": (1 if words["poison"] else 0) | (2 if words["no_magic"] else 0), "status_counters": words}
		var tick := StatusEffectRules.after_action(actor)
		check(int(tick["changes"]["status_flags"]) == int(row["native"]["status_flags"]), "status flags match normally-returned original tick helper")
		for key in row["native"]["status_counters"]:
			check(int(tick["changes"]["status_counters"][key]) == int(row["native"]["status_counters"][key]), "counter update matches normally-returned original tick helper: " + key)


func lifecycle_cases() -> void:
	var loop := fixture()
	var actor := BattlePlayLoop._unit(loop, loop["selected_unit_id"])
	actor["status_flags"] = 3
	actor["status_counters"] = {"poison": (7 << 16) | 2, "paralysis": 0, "no_magic": 1}
	var sealed := BattlePlayLoop.choose_command(loop, "magic")
	check(BattlePlayLoop.choose_magic(sealed, POISON) == sealed, "silence blocks selected magic without spending the action")
	loop = BattlePlayLoop.cancel_interaction(sealed)
	var first := BattlePlayLoop.choose_command(loop, "wait")
	var after := BattlePlayLoop.unit(first, actor["id"])
	check(after["hp"] == actor["hp"] - 7 and after["status_flags"] == 1 and after["status_counters"] == {"poison": (7 << 16) | 1, "paralysis": 0, "no_magic": 0}, "owner completion damages before independently expiring silence")
	check(first["turn_queue"]["index"] == 1 and first["interaction"] == "action_menu" and first["selected_unit_id"] == "leonard", "status completion preserves current actor, phase and within-round order")
	check(SkillResolutionRules.available(after, POISON, BattlePlayLoop.skill_fields(first, POISON), first["skill_book"], first["skill_target_data"], first["equipment_items"])["ok"], "expired silence restores the same source-owned spell")
	var healed := StatusEffectRules.cure_poison(after)
	check(healed["status_flags"] == 0 and healed["status_counters"] == {"poison": 0, "paralysis": 0, "no_magic": 0}, "cure clears full poison word including potency")
	var last := StatusEffectRules.after_action(after)
	check(last["changes"]["hp"] == actor["hp"] - 14 and last["changes"]["status_flags"] == 0 and last["changes"]["status_counters"] == {"poison": 0, "paralysis": 0, "no_magic": 0}, "last poison action damages once then clears potency and duration")
	var dead := after.duplicate(true)
	dead["hp"] = 0
	dead["defeated"] = true
	check(not StatusEffectRules.after_action(dead)["ok"] and not StatusEffectRules.apply(dead, "poison", 2, 8)["ok"], "dead recipients cannot tick, be revived by poison flooring or accept new status")
	var ending := loop.duplicate(true)
	ending["battle_outcome"] = BattleOutcome.VICTORY_SCRIPT
	ending["interaction"] = "battle_result"
	check(BattlePlayLoop.begin_wait_resolution(ending) == ending and BattlePlayLoop.finish_exhausted_action(ending) == ending, "terminal battle snapshot stays frozen without another damage or duration step")
	var ai := fixture()
	var dead_actor := BattlePlayLoop._unit(ai, ai["selected_unit_id"])
	dead_actor["hp"] = 0
	dead_actor["defeated"] = true
	dead_actor["status_flags"] = 1
	dead_actor["status_counters"]["poison"] = (8 << 16) | 2
	ai["interaction"] = "ai_resolving"
	ai["selected_unit_id"] = ""
	var skipped := BattlePlayLoop.step_ai_turn(ai, func(_n): check(false, "dead slot must not attack"); return 0)
	check(BattlePlayLoop.unit(skipped, dead_actor["id"]) == dead_actor and skipped["selected_unit_id"] == "leonard", "dead slot is skipped without ticking or clearing frozen status")


func feedback_rect(node: Node) -> Rect2:
	if node is Node2D:
		var rect: Rect2 = node.bounds()
		return rect if node.number == null else Rect2(rect.position + node.number.position, rect.size)
	return node.get_rect()


# ---- run_status_application_tests.gd ----
const ItemUseRules = preload("res://game/sim/ItemUseRules.gd")
func controlled() -> Dictionary:
	var loop := BattleFixture.loop()
	var player := BattlePlayLoop._unit(loop, "leonard")
	player["live_speed"] = 100
	var ally := BattlePlayLoop._unit(loop, "enemy023_1")
	ally["live_speed"] = 99
	ally["player_commandable"] = true
	ally["battle_actor_role"] = BattlePlayLoop.ROLE_PLAYER
	ally["coord"] = player["coord"] + Vector2i.RIGHT
	loop["turn_queue"] = BattlePlayLoop.CoreTurnQueue.rebuild(loop["units"])
	return BattlePlayLoop.select_player_unit(loop, "leonard")


func afflict(actor: Dictionary, turns: int, power: int, silence: int = 0) -> void:
	actor["status_flags"] = (1 if turns > 0 else 0) | (2 if silence > 0 else 0)
	actor["status_counters"] = {"poison": (power << 16) | turns if turns > 0 else 0, "paralysis": 0, "no_magic": silence}


func run_status_effect() -> void:
	check(BattleFixture.loop()["scenario_ok"], "normal bootstrap has explicit healthy status data")
	for hp in [1, 3, 30]:
		for power in [0, 2, 20, 65535]:
			for turns in [1, 2, 9]:
				var actor := BattlePlayLoop.unit(controlled(), "leonard").duplicate(true)
				actor["hp"] = hp
				afflict(actor, turns, power, 2)
				var before := actor.duplicate(true)
				var result := StatusEffectRules.after_action(actor)
				check(result["ok"], "supported packed status words accepted")
				var next: Dictionary = result["changes"]
				check(next["hp"] == maxi(1, hp - power), "poison damage clamps at one HP without healing")
				check(next["status_counters"]["poison"] == (0 if turns == 1 else (power << 16) | (turns - 1)), "duration decays without corrupting potency; expiry clears entire word")
				check(next["status_flags"] == (2 if turns == 1 else 3) and next["status_counters"]["no_magic"] == 1, "independent no-magic duration survives poison expiry")
				check(actor == before, "pure status proposal preserves input")
	item_cases()
	action_cases()
	skill_cases()
func item_cases() -> void:
	var loop := controlled()
	var actor := BattlePlayLoop._unit(loop, "leonard")
	afflict(actor, 3, 7, 2)
	var initial := loop.duplicate(true)
	var used := BattlePlayLoop.use_item(loop, "246", "leonard", 3)
	var cured := BattlePlayLoop.unit(used, "leonard")
	check(cured["hp"] == actor["hp"] and not StatusEffectRules.poisoned(cured), "full-health antidote clears poison before post-action damage")
	check(cured["status_counters"] == {"poison": 0, "paralysis": 0, "no_magic": 1} and cured["status_flags"] == 2, "antidote preserves unrelated silence then owner duration ticks once")
	check(cured["inventory"] == [241, 241, 241, 0, 0, 0, 0, 0] and used["selected_unit_id"] == "enemy023_1", "consume exactly one antidote and reach the next ally")
	check(BattlePlayLoop.use_item(used, "246", "leonard", 3) == used and loop == initial, "repeat after handoff is inert and original input remains intact")
	var ally := BattlePlayLoop._unit(loop, "enemy023_1")
	afflict(ally, 1, 9)
	var given := BattlePlayLoop.use_item(loop, "246", ally["id"], 3)
	check(not StatusEffectRules.poisoned(BattlePlayLoop.unit(given, ally["id"])), "antidote can cure an adjacent full-health ally")
	check(BattlePlayLoop.unit(given, "leonard")["hp"] == actor["hp"] - 7 and BattlePlayLoop.unit(given, "leonard")["status_counters"]["poison"] == (7 << 16) | 2, "only the acting user's own poison ticks after ally cure")
	for hp in [10, 30]:
		var healthy := controlled()
		BattlePlayLoop._unit(healthy, "leonard")["hp"] = hp
		var spent := BattlePlayLoop.use_item(healthy, "246", "leonard", 3)
		check(spent["item_use_sequence"] == healthy["item_use_sequence"] + 1 and BattlePlayLoop.unit(spent, "leonard")["inventory"].count(246) == BattlePlayLoop.unit(healthy, "leonard")["inventory"].count(246) - 1 and not spent["last_item_use"]["cured_poison"], "healthy antidote use still spends one 246 without a cure (0x444aba)")
	for target in ["missing", "enemy021_1"]:
		check(BattlePlayLoop.use_item(loop, "246", target, 3) == loop, "invalid target cannot mutate items, health, status or action")
	for value in [-1, 1.5, "2", null]:
		var invalid := loop.duplicate(true)
		BattlePlayLoop._unit(invalid, "leonard")["status_counters"]["poison"] = value
		check(BattlePlayLoop.use_item(invalid, "246", "leonard", 3) == invalid, "invalid counter refuses the complete transaction")
	var missing := loop.duplicate(true)
	TestSuite.own(missing, "consumables")["246"].erase("cure_poison")
	check(BattlePlayLoop.use_item(missing, "246", "leonard", 3) == missing, "missing cure rule cannot silently consume the item")
	var raw: Array = BattleFixture.loop()["units"].duplicate(true)
	raw[0].erase("status_counters")
	check(not BattleFixture.loop(raw)["scenario_ok"], "missing initial status state fails explicitly")


func action_cases() -> void:
	var loop := controlled()
	var actor := BattlePlayLoop._unit(loop, "leonard")
	afflict(actor, 2, 5, 1)
	var original := loop.duplicate(true)
	var dropped := BattlePlayLoop.discard_item(loop, "241", 0)
	check(BattlePlayLoop.unit(dropped, "leonard")["status_counters"] == actor["status_counters"] and dropped["turn_queue"] == loop["turn_queue"], "free Drop does not tick poison or no-magic")
	var equipped := BattlePlayLoop.change_equipment(dropped, "head", -1, 0)
	check(BattlePlayLoop.unit(equipped, "leonard")["status_counters"] == actor["status_counters"] and BattlePlayLoop.unit(equipped, "leonard")["hp"] == actor["hp"], "free equipment refresh preserves status without ticking")
	var moved := BattlePlayLoop.choose_command(equipped, "move")
	var destinations := BattlePlayLoop.movement_cells(moved, "leonard")
	for cell in destinations:
		if cell != actor["coord"]:
			moved = BattlePlayLoop.move_unit_to(moved, cell)
			break
	var cancelled := BattlePlayLoop.cancel_pending_move(moved)
	check(BattlePlayLoop.unit(cancelled, "leonard")["coord"] == actor["coord"] and BattlePlayLoop.unit(cancelled, "leonard")["status_counters"] == actor["status_counters"], "movement cancellation restores location but does not advance status time")
	cancelled = BattlePlayLoop.cancel_interaction(cancelled)
	var ended := BattlePlayLoop.choose_command(cancelled, "wait")
	check(ended["selected_unit_id"] == "enemy023_1" and BattlePlayLoop.unit(ended, "leonard")["hp"] == actor["hp"] - 5, "Wait applies poison once and reaches exactly the next actor")
	check(BattlePlayLoop.unit(ended, "leonard")["status_counters"] == {"poison": (5 << 16) | 1, "paralysis": 0, "no_magic": 0}, "expiry clears no-magic while preserving poison potency")
	check(loop == original, "all combined operations preserve the supplied input state")
	for command in ["attack", "special"]:
		var ready := controlled()
		var player := BattlePlayLoop._unit(ready, "leonard")
		player["hp"] = 100
		player["max_hp"] = 100
		afflict(player, 2, 5)
		player["stamina"] = 20
		var foe := BattlePlayLoop._unit(ready, "enemy021_1")
		foe["coord"] = player["coord"] + Vector2i.UP
		foe["hp"] = 100
		var selected := BattlePlayLoop.choose_command(ready, command)
		if command == "special": selected = BattlePlayLoop.choose_special(selected, "special:magicOTHER:magicCode01")
		var attack := BattlePlayLoop.attack_target(selected, foe["id"], func(_n): return 0)
		check(BattlePlayLoop.unit(attack, "leonard")["status_counters"] == player["status_counters"], "offense does not tick status while presentation is pending")
		var finished := BattlePlayLoop.finish_exhausted_action(attack)
		check(finished["selected_unit_id"] == "enemy023_1" and BattlePlayLoop.unit(finished, "leonard")["hp"] == BattlePlayLoop.unit(attack,"leonard")["hp"] - 5, "offense completion adds one poison tick after all committed primary/counter HP loss: " + command)
		check(BattlePlayLoop.finish_exhausted_action(finished) == finished, "duplicate offense completion cannot tick another actor")


func skill_cases() -> void:
	var loop := controlled()
	var mage := BattlePlayLoop._unit(loop, "enemy026_1")
	afflict(mage, 0, 0, 1)
	var target := BattlePlayLoop._unit(loop, "leonard")
	mage["coord"] = target["coord"] + Vector2i.UP
	var before := loop.duplicate(true)
	var draws: Array = []
	var blocked := SkillResolutionRules.resolve(mage, target, "magic:magicAIR:magicCode01", loop["skill_book"]["skills"]["magic:magicAIR:magicCode01"]["fields"], loop["skill_book"], loop["skill_target_data"], loop["equipment_items"], mage["coord"], loop["map_size"], func(n): draws.append(n); return 0)
	check(not blocked["ok"] and blocked["reason"] == "magic_disabled_by_status" and draws.is_empty() and loop == before, "shared spell rejection precedes RNG, MP, HP and movement")
	check(BattleLoopAI._try_skill_turn(loop, mage["id"], [target], func(_n): return 0).is_empty() and loop == before, "AI uses the same no-magic restriction before planning a spell")
	afflict(target, 0, 0, 2)
	target["stamina"] = 20
	check(BattlePlayLoop.can_use_special(loop, "leonard"), "no-magic does not prohibit a supported special")
	mage.merge(StatusEffectRules.after_action(mage)["changes"], true)
	check(SkillResolutionRules.available(mage, "magic:magicAIR:magicCode01", loop["skill_book"]["skills"]["magic:magicAIR:magicCode01"]["fields"], loop["skill_book"], loop["skill_target_data"], loop["equipment_items"])["ok"], "spell becomes eligible after the owner's silence expires")
	var ai := controlled()
	var ai_mage := BattlePlayLoop._unit(ai, "enemy026_1")
	# This case isolates the post-counter status tail. A source-stocked antidote
	# now correctly selects self-cure first; that route has dedicated item tests.
	ai_mage["inventory"] = [0,0,0,0,0,0,0,0]
	ai_mage["hp"] = 1000
	ai_mage["max_hp"] = 1000
	ai_mage["coord"] = BattlePlayLoop.unit(ai, "leonard")["coord"] + Vector2i.UP
	ai_mage["live_speed"] = 101
	afflict(ai_mage, 2, 5, 1)
	ai["turn_queue"] = BattlePlayLoop.CoreTurnQueue.rebuild(ai["units"])
	ai["selected_unit_id"] = ""
	ai["interaction"] = "ai_resolving"
	var ai_done := BattlePlayLoop.step_ai_turn(ai, func(_n): return 0)
	var after := BattlePlayLoop.unit(ai_done, ai_mage["id"])
	check(after["mp"] == ai_mage["mp"] and ai_done["last_ai_action"].get("kind") != "magic", "silenced AI completes a non-magic action without spending MP")
	var counter_damage := int(ai_done["last_ai_action"].get("counter",{}).get("actual_damage",0))
	check(after["hp"] == ai_mage["hp"] - counter_damage - 5 and after["status_flags"] == 1 and after["status_counters"] == {"poison": (5 << 16) | 1, "paralysis": 0, "no_magic": 0}, "AI without a cure uses one post-action status step after the actual counter receipt")
	check(ai_done["selected_unit_id"] == "leonard" and ai_done["turn_queue"]["round"] == ai["turn_queue"]["round"], "AI status step preserves queue order and does not rebuild mid-round")
