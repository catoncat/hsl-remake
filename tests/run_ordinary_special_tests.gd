extends "res://tests/support/TestSuite.gd"
const BattlePlayLoop = preload("res://game/sim/loop/BattlePlayLoop.gd")
const BattleLoopCombat = preload("res://game/sim/loop/BattleLoopCombat.gd")
const CoreCombatRules = preload("res://game/sim/CoreCombatRules.gd")
const SpecialDamageRules = preload("res://game/sim/SpecialDamageRules.gd")
const BattleCombatCutin = preload("res://game/battle/scene/BattleCombatCutin.gd")
const BattleFixture = preload("res://tests/support/BattleFixture.gd")
const RuntimeReadback = preload("res://tests/support/RuntimeReadback.gd")
const RulesReadback = preload("res://tests/support/RulesReadback.gd")


func _init() -> void:
	tag = "ORDINARY_SPECIAL_TESTS"


func run() -> void:
	native_physical()
	native_special()
	transactions()
	hit_bonus_process()
	equipment()
	await presentation()
	await run_stamina()


func random_from(draws: Array) -> Callable:
	return func(bound):
		check(not draws.is_empty(), "native random replay has an expected call")
		if draws.is_empty(): return 0
		var sample: Dictionary = draws.pop_front()
		check(int(sample["bound"]) == bound, "native random bound/order, including zero and raw draws")
		return int(sample["value"])


func native_physical() -> void:
	var packet: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://docs/evidence_packets/static_reverse/original_physical_combat.json"))
	for row in packet["cases"]:
		var input: Dictionary = row["input"]
		var draws: Array = row["draws"].duplicate(true)
		var random := random_from(draws)
		var actual := {}
		match input["kind"]:
			"damage", "weapon":
				var attacker := {"live_attack_damage": input["attack"], "str": input["strength"], "weapon_magic_attack_type": input["element"], "weapon_damage_variance_lo": input["low"], "weapon_damage_variance_hi": input["high"]}
				var defender := {"live_defense": input["defense"], "str": input["target_strength"], "resist_by_type": {}}
				for index in range(5): defender["resist_by_type"][str(index)] = input["resistance"]
				actual["damage"] = CoreCombatRules.preview_damage(attacker, defender, random)["damage"] if input["kind"] == "damage" else CoreCombatRules.variance_bonus(attacker, defender, random)
			"hit":
				actual["hit_rate"] = CoreCombatRules.hit_chance({"live_hit_ratio": input["hit_rate"], "dex": input["dex"]}, {"dex": input["target_dex"], "avoid_hit_ratio": input["avoid"]})["hit_chance"]
			"impact":
				var hit: bool = input["hit_roll"] < input["hit_rate"]
				var impact := CoreCombatRules.critical_impact(int(input["damage"]), hit, int(input["critical_rate"]), random)
				actual = {"hit": hit, "critical": impact["critical"], "damage": impact["damage"], "queued_damage": input["damage"]}
			"fallback": actual["damage"] = CoreCombatRules.damage_floor(random)
			"chances":
				var loop := BattleFixture.loop()
				var actor := BattlePlayLoop.unit(loop, "leonard")
				actor["equipment"] = []
				var source: Dictionary = actor["growth_profile"]["source"]
				source["avoid_hit_ratio"] = int(input["avoid"])
				source["attack_back"] = int(input["counter"])
				source["attack_damagex2"] = int(input["critical"])
				var after := BattlePlayLoop.ProgressionRules.refresh_growth_stats(actor, loop["equipment_items"])
				actual = {"avoid": after["combat_profile"]["avoid_hit_ratio"], "counter": after["combat_profile"]["attack_back"], "critical": after["combat_profile"]["attack_damagex2"]}
		check(actual.size() == row["native"].size() and row["native"].keys().all(func(key): return actual.has(key) and actual[key] == row["native"][key]) and draws.is_empty(), "Godot agrees with original physical result and consumes every draw: " + input["kind"])


func native_special() -> void:
	var packet: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://docs/evidence_packets/static_reverse/original_special_damage.json"))
	for row in packet["rolls"]:
		var draws: Array = row["draws"].duplicate(true)
		var actual := SpecialDamageRules.roll(row["input"], random_from(draws))
		check(actual["value"] == row["native"]["value"] and actual["hit_bonus_after"] == row["native"]["hit_bonus_after"] and draws.is_empty(), "Qi Blade matches native channel1 including level cap, ignored armor and magic-hit equipment")
	for row in packet["applications"]:
		var loop := fixture()
		var actor := BattlePlayLoop.unit_ref(loop, "leonard")
		var target := BattlePlayLoop.unit_ref(loop, "enemy021_1")
		var input: Dictionary = row["input"]
		for key in ["dex", "mind", "con"]: actor["combat_profile"][key] = int(input[key])
		actor["level"] = int(input["level"])
		actor["hit_bonus_accum"] = int(input["hit_bonus"])
		target["hp"] = int(input["hp"])
		target["combat_profile"]["live_defense"] = int(input["defense"])
		own(loop, "skill_book")["actors"][target["actor_id"]]["status_capability_flags"] = 2 if input["no_attack"] else 0
		var fields := BattlePlayLoop.skill_fields(loop, "special:magicOTHER:magicCode01")
		for key in ["hit_ratio", "attackpow_ratio"]: fields[key] = str(int(input[key]))
		var before := loop.duplicate(true)
		var draws: Array = row["draws"].duplicate(true)
		var result := BattlePlayLoop.SkillResolutionRules.resolve(actor, target, "special:magicOTHER:magicCode01", fields, loop["skill_book"], loop["skill_target_data"], loop["equipment_items"], actor["coord"], loop["map_size"], random_from(draws))
		check(result["ok"], "native special application is accepted through shared skill resolver")
		if not result["ok"]: continue
		check(result["target_changes"]["hp"] == row["native"]["hp"] and result["receipt"]["actual_damage"] == row["native"]["damage"], "native capped HP loss matches shared proposal")
		check(result["receipt"]["native_contribution"] == row["native"]["contribution"] and result["caster_changes"]["hit_bonus_accum"] == row["native"]["hit_bonus_local"] and draws.is_empty(), "special contribution/bonus and random order agree")
		check(loop == before and result["caster_changes"]["stamina"] == 0, "proposal pays source20 once without mutating its inputs")


static func fixture() -> Dictionary:
	var loop := BattleFixture.loop()
	loop["units"] = loop["units"].filter(func(unit): return unit["id"] in ["leonard", "enemy021_1", "enemy023_1"])
	loop["tiles"] = {}
	loop["reinforcement_templates"] = []
	for index in range(loop["units"].size()):
		var unit: Dictionary = loop["units"][index]
		unit["coord"] = {"leonard":Vector2i(8,8), "enemy021_1":Vector2i(9,8), "enemy023_1":Vector2i(8,10)}[unit["id"]]
		unit["hp"] = 100
		unit["max_hp"] = 100
		unit["inventory"] = [0,0,0,0,0,0,0,0]
		unit["combat_profile"].merge({"live_hit_ratio": 100, "str":20, "dex":20, "live_attack_damage":20, "live_defense":0, "attack_back":0, "attack_damagex2":0}, true)
	BattlePlayLoop.unit_ref(loop, "leonard")["live_speed"] = 110
	BattlePlayLoop.unit_ref(loop, "leonard")["stamina"] = 20
	var ally := BattlePlayLoop.unit_ref(loop, "enemy023_1")
	ally["live_speed"] = 100
	ally["player_commandable"] = true
	ally["battle_actor_role"] = BattlePlayLoop.ROLE_PLAYER
	# A second, distant enemy keeps the development fixture undecided when the first one
	# falls (its objectives end the battle on enemy clear), so hand-offs stay observable.
	var bystander: Dictionary = BattlePlayLoop.unit_ref(loop, "enemy021_1").duplicate(true)
	bystander.merge({"id": "enemy021_far", "coord": Vector2i(0, 0), "live_speed": 1, "no_attack": true, "move_point": 0, "base_move_point": 0}, true)
	loop["units"].append(bystander)
	loop["turn_queue"] = BattlePlayLoop.CoreTurnQueue.rebuild(loop["units"])
	return BattlePlayLoop.select_player_unit(loop, "leonard")


func transactions() -> void:
	for kill in [false, true]:
		var loop := fixture()
		BattlePlayLoop.unit_ref(loop, "leonard")["combat_profile"]["attack_damagex2"] = 100
		var target := BattlePlayLoop.unit_ref(loop, "enemy021_1")
		target["max_hp"] = 60
		target["hp"] = 1 if kill else 60
		var selected := BattlePlayLoop.choose_command(loop, "attack")
		var before := selected.duplicate(true)
		var after := BattlePlayLoop.attack_target(selected, target["id"], func(_n): return 0)
		var receipt: Dictionary = after["last_attack"]
		check(receipt["critical"] and receipt["queued_damage"] == 20 and receipt["damage"] == 31, "critical actual strike remains distinct from original queued20")
		check(receipt["actual_damage"] == (1 if kill else 31) and receipt["experience_basis"]["contribution"] == receipt["actual_damage"], "EXP is based on actual capped critical HP loss")
		check(not receipt["stamina_gain"]["heavy_hit"] and receipt["stamina_gain"]["base_gain"] == (4 if kill else 3), "critical cannot turn a light queued strike into a heavy ST gain")
		check(BattlePlayLoop.unit(after,target["id"])["hp"] == (0 if kill else 29) and selected == before, "one player transaction commits the exact HP and preserves input")
		var repeated := BattlePlayLoop.attack_target(after,target["id"],no_rng)
		check(repeated["units"] == after["units"] and repeated["last_combat"] == after["last_combat"] and repeated["turn_queue"] == after["turn_queue"], "repeated strike cannot pay/award or hit again")
		check(BattlePlayLoop.finish_exhausted_action(after)["selected_unit_id"] == "enemy023_1", "complete attack hands off once to the next ally")
	var loop := fixture()
	BattlePlayLoop.unit_ref(loop,"enemy021_1")["combat_profile"].merge({"attack_back":100,"attack_damagex2":100},true)
	var exchange := BattleLoopCombat.resolve_exchange(loop,"leonard","enemy021_1",func(_n):return 0)
	check(exchange["counter"]["critical"] and exchange["counter"]["queued_damage"] == 16 and exchange["counter"]["damage"] == 25, "counter scaling precedes its independent critical calculation")
	check(not exchange["counter"].has("counter") and exchange["counter"]["experience_basis"]["contribution"] == 25, "counter has its own contribution and cannot recurse")
	for mode in ["special", "silenced", "miss"]:
		var ready := fixture()
		var caster := BattlePlayLoop.unit_ref(ready,"leonard")
		if mode == "silenced": caster.merge(BattlePlayLoop.StatusEffectRules.apply(caster,"no_magic",2)["changes"],true)
		BattlePlayLoop.unit_ref(ready,"enemy021_1")["combat_profile"]["live_defense"] = 10000
		var started := BattlePlayLoop.choose_special(BattlePlayLoop.choose_command(ready,"special"),"special:magicOTHER:magicCode01")
		check(BattlePlayLoop.cancel_interaction(started)["units"] == ready["units"], "special cancel preserves ST and statuses")
		var after := BattlePlayLoop.attack_target(started,"enemy021_1",func(n):return 99 if mode == "miss" and n == 100 else 0)
		var receipt: Dictionary = after["last_attack"]
		check(receipt["hit"] == (mode != "miss") and BattlePlayLoop.unit(after,"leonard")["stamina"] == 0, "silence permits the special; miss still pays exactly once")
		check(receipt["actual_damage"] > 30 if mode != "miss" else receipt["actual_damage"] == 0, "physical armor does not reduce Qi Blade")
		check(not receipt.has("stamina_gain") and not receipt.has("counter"), "special cannot return ordinary ST or trigger physical counter")
		check(BattlePlayLoop.unit(after,"leonard")["hit_bonus_accum"] == (10 if mode == "miss" else 0), "special miss accumulates native one-based compensation")


## Hit-bonus write-back (+0xb0) is the player process's: 0x442405 `test byte [mode], 2` skips
## 0x44240d..0x44244c for the NPC process's exchanges (0x4414a0 mode 2 primary, 0x4414d3 mode 3
## counter), so an enemy-initiated exchange leaves both sides' bonus as it was — a miss adds
## nothing, damage clears nothing, the player's counter neither — while the hit roll still reads
## it (0x442591). Measured on the original: 250 level-53 damage seeds, 34 enemy／counter misses,
## +0xb0 stays 0 (original_damage_random.md, whole-exchange comparison).
func hit_bonus_process() -> void:
	var rng := func(bound): return 50 if bound == 100 else 0
	for initiator in ["leonard", "enemy021_1"]:
		var player: bool = initiator == "leonard"
		var other := "enemy021_1" if player else "leonard"
		for outcome in ["miss", "hit"]:
			var loop := fixture()
			check(bool(BattlePlayLoop.unit_ref(loop, "leonard").get("player_commandable", false)) and not bool(BattlePlayLoop.unit_ref(loop, "enemy021_1").get("player_commandable", false)), "fixture sides: leonard player-commandable, enemy021_1 not")
			for id in [initiator, other]:
				var unit := BattlePlayLoop.unit_ref(loop, id)
				unit["hit_bonus_accum"] = 7 if id == initiator else 5
				unit["no_attack"] = false
				unit["combat_profile"].merge({"attack_back": 100, "live_hit_ratio": 20 if outcome == "miss" else 100}, true)
			var exchange := BattleLoopCombat.resolve_exchange(loop, initiator, other, rng)
			var counter: Dictionary = exchange.get("counter", {})
			check(not counter.is_empty() and exchange["hit"] == (outcome == "hit") and counter["hit"] == (outcome == "hit"), "%s %s: both series strike once with the planned result" % [initiator, outcome])
			check(exchange["hit_rate"] == (27 if outcome == "miss" else 100) and counter["hit_rate"] == (25 if outcome == "miss" else 100), "%s %s: the hit roll reads the bonus in either process (0x442591)" % [initiator, outcome])
			var expect := {initiator: 7, other: 5}
			if player: expect = {initiator: 9, other: 7} if outcome == "miss" else {initiator: 0, other: 0}
			for id in expect:
				check(int(BattlePlayLoop.unit_ref(loop, id)["hit_bonus_accum"]) == expect[id], "%s %s: %s hit bonus %d (%s process, 0x442405 test mode,2)" % [initiator, outcome, id, expect[id], "player" if player else "NPC"])
			check(int(exchange["hit_bonus_after"]) == expect[initiator] and int(counter["hit_bonus_after"]) == expect[other], "%s %s: receipts carry the live bonus after each strike" % [initiator, outcome])


func equipment() -> void:
	var loop := fixture()
	BattlePlayLoop.unit_ref(loop,"leonard")["inventory"] = [6,7,216,0,0,0,0,0]
	var elemental := BattlePlayLoop.change_equipment(loop,"weapon",0,6)
	var owner := BattlePlayLoop.unit(elemental,"leonard")
	check(owner["combat_profile"]["weapon_magic_attack_type"] == 2 and owner["combat_profile"]["weapon_damage_variance_lo"] == 5, "real source sword enables wind bonus through equipment transaction")
	check(elemental["turn_queue"] == loop["turn_queue"] and owner["stamina"] == 20 and BattlePlayLoop.unit(loop,"leonard")["weapon_code"] != 6, "equipment is atomic/free and never changes charge or input")
	var target := BattlePlayLoop.unit(elemental,"enemy021_1")
	target["combat_profile"]["resist_by_type"]["2"] = 0
	var low := RulesReadback.preview_attack(owner,target,func(_n):return 0)
	target["combat_profile"]["resist_by_type"]["2"] = 80
	var high_wind := RulesReadback.preview_attack(owner,target,func(_n):return 0)
	check(low["damage"] - high_wind["damage"] == 4, "same weapon and RNG apply target wind resistance only to its bonus")
	var critical := BattlePlayLoop.change_equipment(elemental,"weapon",owner["inventory"].find(7),7)
	owner = BattlePlayLoop.unit(critical,"leonard")
	check(owner["combat_profile"]["weapon_magic_attack_type"] == -1 and owner["combat_profile"]["attack_damagex2"] == 24 and owner["combat_profile"]["attack_back"] == 12, "replacement clears old weapon element and adds10 to Leonard's declared critical14")
	critical = BattlePlayLoop.change_equipment(critical,"accessory1",owner["inventory"].find(216),216)
	owner = BattlePlayLoop.unit(critical,"leonard")
	check(owner["combat_profile"]["attack_damagex2"] == 40, "critical modifiers from weapon and accessory add to Leonard's source base14")
	owner["exp"] = 99
	var grown := BattlePlayLoop.ProgressionRules.resolve_experience(owner,1,critical["equipment_items"])
	check(grown["level"] == 2 and grown["combat_profile"]["attack_damagex2"] == 40 and grown["combat_profile"]["attack_back"] == 12, "level refresh retains current equipment probabilities")
	var malformed := loop.duplicate(true)
	own(malformed, "equipment_items")["6"]["weapon_magic"]["low"] = "broken"
	check(BattlePlayLoop.change_equipment(malformed,"weapon",0,6) == malformed, "bad weapon magnitude cannot exchange equipment or silently omit its effect")


func presentation() -> void:
	var loop := fixture()
	BattlePlayLoop.unit_ref(loop,"leonard")["combat_profile"]["attack_damagex2"] = 100
	BattlePlayLoop.unit_ref(loop,"enemy021_1")["hp"] = 1
	var receipt := BattleLoopCombat.resolve_exchange(loop,"leonard","enemy021_1",func(_n):return 0)
	var before := loop.duplicate(true)
	var view := BattleCombatCutin.new()
	root.add_child(view)
	view.configure("res://content/imported/hsl/chapter01/combat_animation/manifest.json")
	view.set_process(false)
	var impacts := [0]
	view.impact.connect(func(_s,_a,_d,_c): impacts[0] += 1)
	view.play(receipt,BattlePlayLoop.unit(loop,"leonard"),BattlePlayLoop.unit(loop,"enemy021_1"),false)
	view._process(0.01)
	check(not view.result.text.contains("暴擊"), "wind-up never reveals precomputed critical result")
	var timing := view.Timing.ordinary(view.manifest["actors"]["001"], receipt)
	# 0x404290 spawns the red number 40 ticks after the hit; read it two ticks later.
	view._process((float(timing["impact"]) + view.Timing.scaled(view.OriginalTick.seconds(view.Timing.HIT_TO_NUMBER_TICKS + 2)) - view.elapsed)/view.Timing.PLAYBACK_SPEED)
	check(RuntimeReadback.result_text(view) == "1" and not RuntimeReadback.result_text(view).contains(str(receipt["damage"])), "critical feedback shows the actual 1 HP loss alone (unsigned, no 暴擊 caption — UI6) rather than uncapped impact (%s)" % RuntimeReadback.result_text(view))
	view._process(0.01)
	check(impacts[0] == 1 and loop == before, "repeated display cannot replay critical impact or mutate reward/resource state")
	view.queue_free()
	await process_frame
	var special_loop := fixture()
	var special_receipt: Dictionary = BattlePlayLoop.attack_target(BattlePlayLoop.choose_special(BattlePlayLoop.choose_command(special_loop,"special"),"special:magicOTHER:magicCode01"),"enemy021_1",func(_n):return 0)["last_attack"]
	var special_view := BattleCombatCutin.new()
	root.add_child(special_view)
	special_view.configure("res://content/imported/hsl/chapter01/combat_animation/manifest.json")
	special_view.set_process(false)
	var events: Array = []
	special_view.released.connect(func(_s,_a,_d,_c):events.append("release"))
	special_view.impact.connect(func(_s,_a,_d,_c):events.append("impact"))
	special_view.play(special_receipt,BattlePlayLoop.unit(special_loop,"leonard"),BattlePlayLoop.unit(special_loop,"enemy021_1"),false)
	# 雷歐納德's ANIMAL s_action cast lead (140 ticks, AnimalCastLead) precedes the script.
	var lead_seconds: float = special_view.OriginalTick.seconds(float(special_view.cast_lead(special_view.clips[0])["complete_tick"]))
	special_view._process(lead_seconds + 2.0)
	# 氣刃斬 plays its specCode01／02 script (SkillEffectScriptPlayer): its WAV\SP01-001.WAV is
	# fired by the player's own sound pool, release at script tick 60 and impact at tick 90.
	# The hit sparks obj_Special01_03 add their objcomd.txt landing sound WAV\BOMB0017.WAV (R5-L2).
	var sounding: Array = special_view.skill_effects.sounds.filter(func(player): return player.playing)
	var files: Array = sounding.map(func(player): return str(player.stream.resource_path).get_file())
	var voices: Array = sounding.filter(func(player): return str(player.stream.resource_path).get_file() == "sp01-001.wav")
	check(events == ["release","impact"] and voices.size() == 1 and files.has("bomb0017.wav") and files.all(func(file): return file in ["sp01-001.wav", "bomb0017.wav"]),"a long presentation frame still emits the special source sound, the landing sound and release before one impact (%s)" % str(files))
	special_view._process(0.01)
	check(events == ["release","impact"],"special repeat frame cannot repeat either event")
	var ability_sound: AudioStreamPlayer = voices[0] if not voices.is_empty() else special_view.ability_sound
	var deadline := Time.get_ticks_msec() + 1000
	while ability_sound.playing and ability_sound.get_playback_position() <= 0 and Time.get_ticks_msec() < deadline: await tree.create_timer(0.01).timeout
	var voice: WeakRef = weakref(ability_sound.get_stream_playback())
	ability_sound.stop()
	ability_sound.stream = null
	special_view.queue_free()
	await process_frame
	deadline = Time.get_ticks_msec() + 1500
	while voice.get_ref() != null and Time.get_ticks_msec() < deadline: await tree.create_timer(0.02).timeout
	check(voice.get_ref() == null,"completed special review releases its actual audio playback")


# ---- run_ordinary_special_tests.gd ----
const StaminaRules = preload("res://game/sim/StaminaRules.gd")
const BattleLoopAI = preload("res://game/sim/loop/BattleLoopAI.gd")
const run_ai_decision_tests = preload("res://tests/run_ai_decision_tests.gd")
func run_stamina() -> void:
	native_cases()
	combat_cases()
	equipment_cases()


func native_cases() -> void:
	var packet: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://docs/evidence_packets/static_reverse/original_stamina.json"))
	for row in packet["cases"]:
		var c: Dictionary = row["input"]
		var before := c.duplicate(true)
		var amount := StaminaRules.amounts(int(c["max_hp"]), int(c["hp_after"]), int(c["damage"]), int(c["attacker_level"]), int(c["defender_level"]), int(c["attacker_st"]), int(c["defender_st"]), int(c["attacker_flags"]), int(c["defender_flags"]))
		check(amount["attacker"]["after"] == row["native"]["attacker"] and amount["defender"]["after"] == row["native"]["defender"], "both gains equal complete original x86 return")
		check(row["normal_return"] and row["rng_calls"] == 0 and c == before, "native stamina case has complete return, zero RNG and no input mutation")
	check(StaminaRules.amounts(11, 1, 5, 1, 1, 0, 0, 0, 0)["base_gain"] == 4, "odd maxHP half threshold uses integer floor")
	check(StaminaRules.amounts(1, 1, 4, 1, 1, 0, 0, 0, 0)["base_gain"] == 3, "maxHP below10 retains original minimum denominator")


static func fixture_stamina() -> Dictionary:
	var loop := BattleFixture.loop()
	var player := BattlePlayLoop.unit_ref(loop, "leonard")
	var enemy := BattlePlayLoop.unit_ref(loop, "enemy021_1")
	player["live_speed"] = 100
	for unit in loop["units"]:
		unit["combat_profile"]["attack_back"] = 0
	for unit in [player, enemy]:
		unit["hp"] = 500
		unit["max_hp"] = 500
		unit["level"] = 1
		unit["combat_profile"]["live_hit_ratio"] = 200
		unit["combat_profile"]["live_defense"] = 0
		unit["combat_profile"]["live_attack_damage"] = 10
		enemy["coord"] = player["coord"] + Vector2i.UP
	loop["turn_queue"] = BattlePlayLoop.CoreTurnQueue.rebuild(loop["units"])
	return BattlePlayLoop.select_player_unit(loop, "leonard")


func combat_cases() -> void:
	var loop := fixture_stamina()
	check(loop["units"].all(func(unit): return unit["stamina"] == 0), "every roster actor starts at explicit zero ST")
	for unit in loop["units"]:
		if unit["id"] == "leonard": continue
		check(not BattlePlayLoop.menu_for_unit(loop, unit["id"])["commands"].any(func(command): return command["command"] == "special"), "having ST never grants another actor Leonard's ability")
	var player := BattlePlayLoop.unit_ref(loop, "leonard")
	var enemy := BattlePlayLoop.unit_ref(loop, "enemy021_1")
	for index in range(5):
		var attacking: String = "leonard" if index % 2 == 0 else "enemy021_1"
		var defending: String = "enemy021_1" if index % 2 == 0 else "leonard"
		var before := [player["stamina"], enemy["stamina"]]
		var strike := BattleLoopCombat.apply_strike(loop, attacking, defending, func(_bound): return 0)
		check(strike["stamina_gain"]["attacker"]["delta"] == 3 and strike["stamina_gain"]["defender"]["delta"] == 6, "ordinary light damage has asymmetric native gain")
		check(player["stamina"] == before[0] + (3 if attacking == "leonard" else 6), "committed player ST matches role")
	check(player["stamina"] == 21 and BattlePlayLoop.can_use_special(loop, "leonard"), "earned charge unlocks the real20-cost skill")
	var canceled := BattlePlayLoop.cancel_interaction(BattlePlayLoop.choose_command(loop, "special"))
	check(canceled["units"] == loop["units"], "canceling earned special preserves exact charges")
	var selected := BattlePlayLoop.choose_special(BattlePlayLoop.choose_command(loop, "special"), "special:magicOTHER:magicCode01")
	for hit in [true, false]:
		var cast := BattlePlayLoop.attack_coord(selected, enemy["coord"], func(bound): return 0 if hit or bound != 100 else 99)
		check(BattlePlayLoop.unit(cast, "leonard")["stamina"] == 1 and BattlePlayLoop.unit(cast, enemy["id"])["stamina"] == enemy["stamina"], "special pays20 once on hit or miss, with no invented normal-attack gain")
	var counter_loop := fixture_stamina()
	BattlePlayLoop.unit_ref(counter_loop, "enemy021_1")["combat_profile"]["attack_back"] = 200
	var exchange := BattleLoopCombat.resolve_exchange(counter_loop, "leonard", "enemy021_1", func(_n): return 0)
	check(not exchange["counter"].is_empty() and BattlePlayLoop.unit(counter_loop, "leonard")["stamina"] == 9 and BattlePlayLoop.unit(counter_loop, "enemy021_1")["stamina"] == 9, "counter exchanges gain independently with reversed roles")
	var missed := fixture_stamina()
	BattlePlayLoop.unit_ref(missed, "leonard")["combat_profile"]["live_hit_ratio"] = 0
	var miss := BattleLoopCombat.apply_strike(missed, "leonard", "enemy021_1", func(_n): return 99)
	check(not miss["hit"] and not miss.has("stamina_gain") and BattlePlayLoop.unit(missed, "leonard")["stamina"] == 0 and BattlePlayLoop.unit(missed, "enemy021_1")["stamina"] == 0, "miss grants neither participant stamina")
	var mage_loop := run_ai_decision_tests.live_fixture()
	var magic := BattleLoopAI.try_skill_turn(mage_loop, "enemy026_1", [BattlePlayLoop.unit(mage_loop, "leonard")], func(_n): return 0)
	check(not magic.is_empty() and BattlePlayLoop.unit(mage_loop, "leonard")["stamina"] == 0 and BattlePlayLoop.unit(mage_loop, "enemy026_1")["stamina"] == 0, "magic damage retains the separate original no-ST-gain channel")
	var killed := fixture_stamina()
	BattlePlayLoop.unit_ref(killed, "enemy021_1")["hp"] = 1
	var death := BattleLoopCombat.apply_strike(killed, "leonard", "enemy021_1", func(_n): return 0)
	check(death["stamina_gain"]["base_gain"] == 4 and death["stamina_gain"]["defeated"] and BattlePlayLoop.unit(killed, "leonard")["stamina"] == 4, "lethal strike includes the source kill increment once")
	var capped := fixture_stamina()
	BattlePlayLoop.unit_ref(capped, "leonard")["stamina"] = 59
	BattleLoopCombat.apply_strike(capped, "leonard", "enemy021_1", func(_n): return 0)
	check(BattlePlayLoop.unit(capped, "leonard")["stamina"] == 60, "earned charges never exceed source cap60")


func equipment_cases() -> void:
	var loop := fixture_stamina()
	BattlePlayLoop.unit_ref(loop, "leonard")["inventory"] = [225, 225, 169, 0, 0, 0, 0, 0]
	var before := loop.duplicate(true)
	var equipped := BattlePlayLoop.change_equipment(loop, "accessory1", 0, 225)
	check(BattlePlayLoop.EquipmentRules.equipped_code(BattlePlayLoop.unit(equipped, "leonard")["equipment"], "accessory1") == 225 and loop == before, "source ring equips through actual immutable player transaction")
	check(equipped["turn_queue"] == loop["turn_queue"] and BattlePlayLoop.unit(equipped, "leonard")["stamina"] == 0, "equipping grants no free ST and preserves current turn")
	equipped = BattlePlayLoop.change_equipment(equipped, "accessory2", BattlePlayLoop.unit(equipped, "leonard")["inventory"].find(225), 225)
	var old_st: int = BattlePlayLoop.unit(equipped, "leonard")["stamina"]
	var strike := BattleLoopCombat.apply_strike(equipped, "leonard", "enemy021_1", func(_n): return 0)
	check(strike["stamina_gain"]["attacker"]["doubled"] and BattlePlayLoop.unit(equipped, "leonard")["stamina"] == old_st + 6, "two source rings set one native bit; gains double, never quadruple")
	equipped = BattlePlayLoop.change_equipment(equipped, "head", BattlePlayLoop.unit(equipped, "leonard")["inventory"].find(169), 169)
	check(BattlePlayLoop.EquipmentRules.equipped_code(BattlePlayLoop.unit(equipped, "leonard")["equipment"], "head") == 169, "Ghost Mask is actually equipable with supported effects")
	old_st = BattlePlayLoop.unit(equipped, "leonard")["stamina"]
	var locked := BattleLoopCombat.apply_strike(equipped, "leonard", "enemy021_1", func(_n): return 0)
	check(locked["stamina_gain"]["attacker"]["blocked"] and BattlePlayLoop.unit(equipped, "leonard")["stamina"] == old_st, "source no_addst takes precedence over double gain")
	var mask_removed := BattlePlayLoop.change_equipment(equipped, "head", -1, 0)
	check((int(StaminaRules.effects(BattlePlayLoop.unit(mask_removed, "leonard"), mask_removed["equipment_items"])["flags"]) & StaminaRules.BLOCK) == 0, "unequip removes effective block immediately without resetting earned ST")
	var resumed := BattleLoopCombat.apply_strike(mask_removed, "leonard", "enemy021_1", func(_n): return 0)
	check(resumed["stamina_gain"]["attacker"]["delta"] == 6, "normal progression refresh preserves passive gain behavior")
