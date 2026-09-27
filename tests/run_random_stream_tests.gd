extends "res://tests/support/TestSuite.gd"
## The two original random streams against the original. The damage／hit stream:
## DamageRandomStream replays original_damage_random.json (0x458c10 raw and 0x458c80 rand(n),
## executed on hsl01.exe by `hsl generate damage_random`) value for value from every recorded
## state, one exchange draws in the original order, and the save carries it. The global stream
## (0x4795d4／0x4795d8): the same generator, the static initial words, the clock seed of
## 0x458c10, and the emulated enemy turn of original_enemy_turn.json (`hsl generate
## enemy_turn`), whose every global draw GlobalRandomStream replays value for value from the
## turn's words; the save leaves it out.
const Global = preload("res://game/sim/GlobalRandomStream.gd")
const Damage = preload("res://game/sim/DamageRandomStream.gd")
const Loop = preload("res://game/sim/loop/BattlePlayLoop.gd")
const Checkpoint = preload("res://game/battle/runtime/BattleCheckpoint.gd")
const BattleFixture = preload("res://tests/support/BattleFixture.gd")
const PACKET := "res://docs/evidence_packets/static_reverse/original_damage_random.json"
const ORACLE := "res://docs/evidence_packets/static_reverse/original_enemy_turn.json"
const FIRST_BATTLE := "res://content/battles/battle_051.json"
const VIEW := {"camera": Vector2(320, 240), "shown_story_events": [], "story_complete": true, "growth_notified_level": 1}
## The AI's decision stream is the global one; the damage-stream replay pins it so only the
## damage stream carried by the save decides whether the results repeat.
const DECISION_SEED := 11


func _init() -> void:
	tag = "RANDOM_STREAM_TESTS"


func run() -> void:
	damage_native_cases()
	damage_order_cases()
	damage_save_load_cases()
	global_native_cases()
	oracle_cases()
	session_cases()
	global_save_load_cases()
	new_campaign_cases()


static func words(text: String) -> Array:
	var out: Array = []
	for index in range(0, text.length(), 8):
		out.append(text.substr(index, 8).hex_to_int())
	return out


static func state_of(value: Variant) -> Array:
	return Damage.from_words(value)


func damage_native_cases() -> void:
	var packet: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(PACKET))
	var bounds: Array = packet["bounds"].map(func(b): return int(b))
	var draws := int(packet["draws"])
	check(packet["states"].size() >= 3 and draws == 1000, "native packet covers at least 3 states × 1000 draws")
	for row in packet["states"]:
		var start := state_of(row["state"])
		check(Damage.valid(start), "native start state is two u32 words")
		var native_raw := words(row["raw_hex"])
		var state := start.duplicate()
		var raw_ok := native_raw.size() == draws
		for index in range(draws):
			var step := Damage.raw(state)
			state = step["state"]
			if not raw_ok or int(step["value"]) != int(native_raw[index]):
				raw_ok = false
				break
		check(raw_ok and state == state_of(row["raw_end"]), "0x458c10 raw draws match the original value for value from %s" % str(start))
		var native_rand := words(row["rand_hex"])
		state = start.duplicate()
		var rand_ok := native_rand.size() == draws
		for index in range(draws):
			var step := Damage.rand(state, int(bounds[index % bounds.size()]))
			state = step["state"]
			if not rand_ok or int(step["value"]) != int(native_rand[index]):
				rand_ok = false
				break
		check(rand_ok and state == state_of(row["rand_end"]), "0x458c80 rand(n) matches the original for every cycled bound from %s" % str(start))
		var drawn := Damage.rand(start, 0)
		check(drawn["value"] == 0 and drawn["state"] == start and row["rand_zero"]["state_unchanged"] == true, "rand(0) returns 0 without advancing, as 0x458c80 does")
		check(state_of(row["damage_wrapper"]["rand_end"]) == state_of(row["rand_end"]) and row["damage_wrapper"]["global_state_kept"] == true,
			"0x42c780 advances only the damage words, exactly like the generator on them")
	check(Damage.seeded(0x12d687) == [0x12d687, 0xffed2978] and Damage.seeded(-1) == [0xffffffff, 0], "new-game seed is [t, ~t] on 32-bit words")
	var loop := {Damage.LOOP_KEY: Damage.seeded(7)}
	var source := Damage.loop_source(loop)
	var expected := Damage.rand(Damage.seeded(7), 100)
	check(int(source.call(100)) == int(expected["value"]) and loop[Damage.LOOP_KEY] == expected["state"], "the loop source draws rand(n) and writes the state back at once")
	check(int(source.call(0)) == 0 and loop[Damage.LOOP_KEY] == expected["state"], "the loop source's rand(0) leaves the stream where it was")
	var raw := Damage.raw(expected["state"])
	check(int(source.call(-1)) == int(raw["value"]) and loop[Damage.LOOP_KEY] == raw["state"], "a negative bound is the raw 0x42c720 draw")
	check(Damage.advance(Damage.seeded(7), 2) == raw["state"], "advance(n) walks the same chain")
	check(Damage.from_words([1.0, 4294967295.0]) == [1, 0xffffffff] and Damage.from_words([1.5, 2]).is_empty() and Damage.from_words([-1, 2]).is_empty(), "carried JSON words are accepted only as exact u32 pairs")


## Leonard next to enemy021_1 (who always counters), Leonard to act. He carries one 會心
## (262: first use draws its 5–10 strength) and wears an HP auto-restore accessory (223:
## every final action below full HP draws rand(6)), so items and the turn-end tail share
## the stream with the exchanges.
static func duel(seed: int) -> Dictionary:
	var loop := BattleFixture.loop([], "", seed)
	var player := Loop._unit(loop, "leonard")
	player["inventory"] = [262, 0, 0, 0, 0, 0, 0, 0]
	player["equipment"] = player["equipment"].filter(func(slot): return not str(slot["slot"]).begins_with("accessory"))
	player["equipment"].append({"slot": "accessory2", "item_code": 223})
	player.merge(Loop.ProgressionRules.refresh_growth_stats(player, loop["equipment_items"]), true)
	player["hp"] = int(player["max_hp"]) - 5
	player["live_speed"] = 100
	player["coord"] = Vector2i(15, 15)
	var target := Loop._unit(loop, "enemy021_1")
	target["coord"] = player["coord"] + Vector2i.RIGHT
	target["combat_profile"]["attack_back"] = 100
	target["max_hp"] = 400
	target["hp"] = 400
	loop["turn_queue"] = Loop.CoreTurnQueue.rebuild(loop["units"])
	return Loop.select_player_unit(loop, "leonard")


## What a player sees of one step: every actor's HP／EXP／status, the last exchange's rolls
## and the stream.
static func observed(loop: Dictionary) -> Dictionary:
	var vitals := {}
	for actor in loop["units"]:
		vitals[actor["id"]] = [actor["hp"], actor["exp"], actor["status_flags"]]
	var combat: Dictionary = loop.get("last_combat", {})
	var strikes: Array = []
	for receipt in [combat, combat.get("counter", {})]:
		if receipt.is_empty(): continue
		for strike in [receipt] + receipt.get("followups", []):
			strikes.append([strike["attacker_id"], strike["hit_roll"], strike["hit"], strike["damage"], strike["critical"], strike["critical_roll"], strike["damage_detail"]["noise"]])
	return {"vitals": vitals, "strikes": strikes, "sequence": combat.get("sequence", 0), "stream": loop[Damage.LOOP_KEY],
		"item": loop.get("last_item_use", {}).get("draws", []), "tail": loop.get("last_action_end", {}).get("draws", [])}


## Leonard drinks 會心 first, then three rounds of Leonard attacking and the AI side
## answering: the observed trace.
static func damage_play(loop: Dictionary) -> Array:
	var trace: Array = []
	var decisions := RandomNumberGenerator.new()
	decisions.seed = DECISION_SEED
	var next := loop
	for round in range(3):
		if str(next.get("interaction", "")) != "action_menu" or next.get("selected_unit_id") != "leonard": break
		if round == 0:
			next = Loop.use_item(next, "262")
			trace.append(observed(next))
		next = Loop.attack_target(Loop.choose_command(next, "attack"), "enemy021_1")
		trace.append(observed(next))
		if Loop.action_exhausted(next):
			next = Loop.finish_exhausted_action(next)
		for _step in range(60):
			if str(next.get("interaction", "")) != "ai_resolving": break
			next = Loop.step_ai_turn(next, decisions)
			trace.append(observed(next))
	trace.append(next.get("interaction", ""))
	return trace


## One exchange draws in the original order (0x4423c0 → 0x409be0 → 0x403860): counter gate
## rand(100), then the damage draws, then hit rand(100), then the critical rand(100).
func damage_order_cases() -> void:
	var loop := duel(5)
	var shadow := {Damage.LOOP_KEY: loop[Damage.LOOP_KEY]}
	var bounds: Array = []
	var logging := func(bound: int) -> int:
		bounds.append(bound)
		return Damage.loop_draw(shadow, bound)
	var done := Loop.attack_target(Loop.choose_command(loop, "attack"), "enemy021_1", logging)
	var strike: Dictionary = done.get("last_combat", {})
	check(not strike.is_empty(), "the duel fixture settles one exchange")
	if strike.is_empty(): return
	var detail: Dictionary = strike["damage_detail"]
	var expected: Array = [100]
	if detail["path"] == "base_non_positive_floor": expected.append(5)
	elif detail["path"] == "base_weak_band": expected.append(int(detail["base_attack_minus_defense"]) + 4)
	var half := absi(int(detail["str_term"])) / 2
	expected.append_array([int(detail["effective_before_noise"]) * 30 / 100, half, half])
	if detail["used_nonpositive_fallback"]: expected.append(-1)
	check(int(detail["variance_bonus"]) == 0, "the fixture weapon has no element variance draws")
	expected.append(100)
	if strike["hit"]: expected.append(100)
	_assert_eq(bounds.slice(0, expected.size()), expected, "one exchange draws gate → damage → hit → critical in the original order")
	var live := Loop.attack_target(Loop.choose_command(loop, "attack"), "enemy021_1")
	check(observed(live)["strikes"] == observed(done)["strikes"] and live[Damage.LOOP_KEY] == shadow[Damage.LOOP_KEY],
		"the product exchange draws exactly those values from the loop's own stream and keeps where it stopped")


## Save → act and record → load → repeat → identical, as the original's reload (0x42e980
## restores the damage words) makes it. A different saved stream changes the results.
func damage_save_load_cases() -> void:
	var loop := duel(20260925)
	var saved := Checkpoint.encode(loop, VIEW)
	check(saved["ok"], "the duel fixture is a savable boundary: " + str(saved.get("reason", "")))
	if not saved["ok"]: return
	var first := damage_play(loop)
	var decoded := Checkpoint.decode(saved["bytes"], loop)
	check(decoded["ok"], "the save loads back")
	if not decoded["ok"]: return
	var restored: Dictionary = decoded["snapshot"]["loop"]
	check(restored[Damage.LOOP_KEY] == loop[Damage.LOOP_KEY], "the save keeps the damage stream words exactly")
	var again := damage_play(restored)
	var strikes := 0
	for step in first:
		if step is Dictionary: strikes += step["strikes"].size()
	check(strikes >= 3, "the replayed stretch settles at least three strikes (%d)" % strikes)
	var item_draws := 0
	var tail_draws := 0
	for step in first:
		if step is Dictionary:
			item_draws = maxi(item_draws, step["item"].size())
			tail_draws = maxi(tail_draws, step["tail"].size())
	check(item_draws == 1 and tail_draws >= 1, "the stretch also draws an item strength and a turn-end recovery from the same stream (item %d, tail %d)" % [item_draws, tail_draws])
	_assert_eq(again, first, "after loading, the same actions repeat the same HP, hits, damage, criticals and stream")
	check(first[first.size() - 2]["stream"] != loop[Damage.LOOP_KEY], "the stretch advanced the saved stream")
	var other := Loop.copy(restored)
	other[Damage.LOOP_KEY] = Damage.advance(restored[Damage.LOOP_KEY], 1)
	check(damage_play(other) != first, "a different saved stream gives different results: the save, not luck, repeats them")


func global_native_cases() -> void:
	var state: Array = Global.STATIC_STATE.duplicate()
	var values: Array = []
	for _index in range(5):
		var step := Global.raw(state)
		state = step["state"]
		values.append(int(step["value"]))
	_assert_eq(values, [0x75308ecb, 0x10a9752a, 0xc6c87601, 0xa18611ff, 0xb50b4dc4], "the static words 0x12345678／0x87654321 give the original's first five raw values")
	var probe := Global.seeded(0x2a)
	check(Global.raw(probe) == Damage.raw(probe) and Global.rand(probe, 99) == Damage.rand(probe, 99) and Global.advance(probe, 7) == Damage.advance(probe, 7),
		"the global stream runs the damage stream's generator 0x458c10／0x458c80, not a second implementation")
	check(Global.seeded(12) == [12, 12 ^ 0xe54a231c] and Global.seeded(-1) == [0xffffffff, 0x1ab5dce3], "0x458c10's lazy seed stores [t, t ^ 0xe54a231c] on 32-bit words")
	check(Global.seeded(12) != Damage.seeded(12), "the same clock value seeds the two streams to different words")
	var loop := {Global.LOOP_KEY: Global.seeded(9)}
	var source := Global.loop_source(loop)
	var expected := Global.rand(Global.seeded(9), 100)
	check(int(source.call(100)) == int(expected["value"]) and loop[Global.LOOP_KEY] == expected["state"], "the loop source draws rand(n) and writes the state back at once")
	check(int(source.call(0)) == 0 and loop[Global.LOOP_KEY] == expected["state"], "rand(0) leaves the stream where it was")
	var raw := Global.raw(expected["state"])
	check(int(source.call(-1)) == int(raw["value"]) and loop[Global.LOOP_KEY] == raw["state"], "a negative bound is the raw 0x458c10 draw")


## Every global draw of the emulated turn, in order, from the turn's starting words: the
## recorded values follow from rand(n)／raw alone, so nothing else drew from the stream
## between them (the damage draws of the one attack sit on the damage words).
func oracle_cases() -> void:
	var packet: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(ORACLE))
	var turn: Dictionary = packet["turns"][0]
	var streams := {"global": Global.from_words(turn["rng"]["global"]), "damage": Damage.from_words(turn["rng"]["damage"])}
	check(Global.valid(streams["global"]) and Damage.valid(streams["damage"]), "the oracle turn starts from two word pairs")
	var counts := {"global": 0, "damage": 0}
	var first_miss := ""
	for action in turn["actions"]:
		for draw in action["draws"]:
			var stream := str(draw["stream"])
			var bound := -1 if draw["n"] == null else int(draw["n"])
			var step := Global.raw(streams[stream]) if bound < 0 else Global.rand(streams[stream], bound)
			streams[stream] = step["state"]
			counts[stream] += 1
			if first_miss == "" and int(step["value"]) != int(draw["value"]):
				first_miss = "%s %s draw %d at %s" % [action["actor"], stream, counts[stream], draw["site"]]
	check(counts["global"] >= 500 and counts["damage"] >= 1, "the oracle turn records hundreds of global draws and the attack's damage draws (%s)" % str(counts))
	check(first_miss == "", "every oracle draw replays from the turn's words value for value (first miss: %s)" % first_miss)


## The process stream: seeded once on first use, by HSL_RNG_SEED when a headless run names
## one; the running battle hands its words back.
func session_cases() -> void:
	var saved := OS.get_environment(Global.SEED_ENV)
	OS.set_environment(Global.SEED_ENV, "77")
	Global.reset_session()
	check(Global.session() == Global.seeded(77), "headless with HSL_RNG_SEED, the first use seeds the process stream from it")
	var first := Global.session_draw(100)
	check(first == int(Global.rand(Global.seeded(77), 100)["value"]) and Global.session() == Global.rand(Global.seeded(77), 100)["state"], "a session draw advances the process stream")
	OS.set_environment(Global.SEED_ENV, "78")
	check(Global.session() == Global.rand(Global.seeded(77), 100)["state"], "the process stream is seeded once; a later seed does not re-seed it")
	var loop := {Global.LOOP_KEY: Global.session()}
	Global.loop_draw(loop, 99)
	Global.loop_draw(loop, -1)
	Global.remember(loop)
	check(Global.session() == loop[Global.LOOP_KEY], "remember adopts the battle loop's words as the process stream")
	Global.reset_session()
	check(Global.session() == Global.seeded(78), "reset forgets the stream and the next use seeds it again")
	if saved == "": OS.unset_environment(Global.SEED_ENV)
	else: OS.set_environment(Global.SEED_ENV, saved)
	Global.reset_session()


## The duel above with the product AI: every AI step draws from the
## loop's own global words (no decision source handed in). Per step: what a player sees,
## the AI's decision, and the global words.
static func global_play(loop: Dictionary) -> Array:
	var trace: Array = []
	var next := loop
	for round in range(3):
		if str(next.get("interaction", "")) != "action_menu" or next.get("selected_unit_id") != "leonard": break
		next = Loop.attack_target(Loop.choose_command(next, "attack"), "enemy021_1")
		trace.append({"seen": observed(next), "ai": {}, "global": next[Global.LOOP_KEY]})
		if Loop.action_exhausted(next):
			next = Loop.finish_exhausted_action(next)
		for _step in range(60):
			if str(next.get("interaction", "")) != "ai_resolving": break
			next = Loop.step_ai_turn(next)
			var act: Dictionary = next.get("last_ai_action", {})
			trace.append({"seen": observed(next), "global": next[Global.LOOP_KEY],
				"ai": {"actor": act.get("actor_id", ""), "kind": act.get("kind", ""), "to": act.get("to", act.get("from")), "target": act.get("target_id", "")}})
	return trace


static func first_ai(trace: Array) -> int:
	for index in range(trace.size()):
		if not trace[index]["ai"].is_empty(): return index
	return -1


## Save → play → load into a battle whose global stream has moved on → play again: the
## save holds the damage words, not the global ones (the original keeps 0x4795d4／0x4795d8
## out of its save and seeds them from the clock), so everything up to the first AI step
## repeats exactly and the AI may then choose differently — the first live advance of the
## global words that turns its first choice is searched, not pinned; the same global words
## replay the whole stretch.
## The target stands left of Leonard: 0x413390 ranks the station right of him first, and
## with a foe beside it the actor walks round there only on rand(99) + 1 above 92
## (0x440b2c state 0xb sub 0), so the global words can change its first choice. (Right of
## him, that station is its own cell and both outcomes are the same attack in place.)
func global_save_load_cases() -> void:
	var loop := duel(20260925)
	Loop._unit(loop, "enemy021_1")["coord"] = Loop._unit(loop, "leonard")["coord"] + Vector2i.LEFT
	loop["turn_queue"] = Loop.CoreTurnQueue.rebuild(loop["units"])
	loop = Loop.select_player_unit(loop, "leonard")
	check(not Checkpoint.state(loop).has(Global.LOOP_KEY) and Checkpoint.state(loop).has(Damage.LOOP_KEY), "the saved half of the loop holds the damage stream and not the global stream")
	var saved := Checkpoint.encode(loop, VIEW)
	check(saved["ok"], "the duel fixture is a savable boundary: " + str(saved.get("reason", "")))
	if not saved["ok"]: return
	var first := global_play(loop)
	var ai_at := first_ai(first)
	check(ai_at >= 1, "the stretch reaches an AI step after the player's strike (%d)" % ai_at)
	if ai_at < 1: return
	var live := {}
	var restored := {}
	var again: Array = []
	for advance in range(1, 65):
		live = Loop.copy(loop)
		live[Global.LOOP_KEY] = Global.advance(loop[Global.LOOP_KEY], advance)
		var decoded := Checkpoint.decode(saved["bytes"], live)
		check(decoded["ok"], "the save loads back into the running battle: " + str(decoded.get("reason", "")))
		if not decoded["ok"]: return
		restored = decoded["snapshot"]["loop"]
		again = global_play(restored)
		if first_ai(again) == ai_at and again[ai_at]["ai"] != first[ai_at]["ai"]: break
	check(restored[Damage.LOOP_KEY] == loop[Damage.LOOP_KEY] and restored[Global.LOOP_KEY] == live[Global.LOOP_KEY], "the load restores the saved damage words and keeps the running battle's global words")
	check(first_ai(again) == ai_at, "the loaded stretch reaches its AI step at the same point (%d)" % first_ai(again))
	_assert_eq(again.slice(0, ai_at).map(func(step): return step["seen"]), first.slice(0, ai_at).map(func(step): return step["seen"]), "after loading, the player's strike repeats the same hits, damage, criticals and damage stream")
	check(again.size() > ai_at and again[ai_at]["ai"] != first[ai_at]["ai"], "some live global words within 64 advances change the AI's first choice after the load (%s)" % str(first[ai_at]["ai"]))
	var pinned := Loop.copy(restored)
	pinned[Global.LOOP_KEY] = (loop[Global.LOOP_KEY] as Array).duplicate()
	_assert_eq(global_play(pinned), first, "the loaded battle with the save-time global words replays the whole stretch, AI included")


## A new battle's NPC opening levels (InitialRosterGrowthRules, 0x40e870 rand draws) come
## from the process stream: the same HSL_RNG_SEED gives the same levels, other seeds other
## levels.
static func opening_levels(scenario: Dictionary, seed: int) -> Array:
	OS.set_environment(Global.SEED_ENV, str(seed))
	Global.reset_session()
	var loop := Loop.initialize_roster_growth(Loop.create([], "", scenario, 1, Global.session()))
	var levels: Array = []
	for unit in loop["units"]:
		if unit.has("entry_growth"): levels.append([unit["id"], unit["level"], unit["max_hp"]])
	return levels


func new_campaign_cases() -> void:
	var saved := OS.get_environment(Global.SEED_ENV)
	var scenario := Loop.BattleScenario.load_file(FIRST_BATTLE)
	check(bool(scenario.get("ok", false)), "battle 051 loads")
	if not bool(scenario.get("ok", false)): return
	var rosters := {}
	for seed in [1, 2, 3, 4]:
		var levels := opening_levels(scenario, seed)
		check(not levels.is_empty(), "battle 051 has NPCs with an opening level adjustment (seed %d)" % seed)
		_assert_eq(opening_levels(scenario, seed), levels, "the same HSL_RNG_SEED gives the same opening levels (seed %d)" % seed)
		rosters[str(levels)] = seed
	check(opening_levels(scenario, 1) != opening_levels(scenario, 2) and rosters.size() >= 3, "different seeds give different opening levels (%d distinct rosters of 4)" % rosters.size())
	if saved == "": OS.unset_environment(Global.SEED_ENV)
	else: OS.set_environment(Global.SEED_ENV, saved)
	Global.reset_session()
