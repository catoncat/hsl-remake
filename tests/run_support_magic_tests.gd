extends "res://tests/support/TestSuite.gd"
## Support magic against the original: healing and cure (original_support_magic.json), the
## attack／defense enhancements and dispel with their final-action timers
## (original_stat_magic.json, on stat_magic_trial.json), and the slot-1 priest 002 with its
## initial skills and MP items (original_priest.json, on priest_trial.json). The two dev trial
## scenes boot in run_battle_scene_runtime_tests.gd.
const Loop = preload("res://game/battle/scene/BattlePlayLoop.gd")
const Support = preload("res://game/sim/SupportMagicRules.gd")
const Rolls = preload("res://game/sim/NativeMagicRollRules.gd")
const BattleFixture = preload("res://tests/support/BattleFixture.gd")
const Save = preload("res://game/battle/runtime/BattleCheckpoint.gd")
const Stats = preload("res://game/sim/StatEnhancementRules.gd")
const Magic = preload("res://game/sim/StatMagicRules.gd")
const Aid = preload("res://game/sim/AISupportRules.gd")
const BattleOutcome = preload("res://game/sim/BattleOutcome.gd")
const HEAL := "magic:magicWATER:magicCode06"
const GREATER := "magic:magicWATER:magicCode07"
const LIFE := "magic:magicWATER:magicCode08"
const CURE := "magic:magicWATER:magicCode05"
const ATT := "magic:magicFIRE:magicCode05"
const DEF := "magic:magicEARTH:magicCode06"
const DISPEL := "magic:magicMIND:magicCode06"
const VIEW := {"camera": Vector2(320,240), "shown_story_events": [], "story_complete": true, "growth_notified_level": 1}


func _init() -> void:
	tag = "SUPPORT_MAGIC_TESTS"


func run() -> void:
	native_cases()
	player_cases()
	earth_heals()
	ai_cases()
	await presentation_tail_cases()
	stat_magic_cases()
	priest_cases()


static func fixture(ai: bool = false) -> Dictionary:
	var loop := BattleFixture.loop()
	var caster := Loop.unit(loop, "enemy026_1" if ai else "leonard")
	var ally := Loop.unit(loop, "enemy023_1")
	var foe := Loop.unit(loop, "leonard" if ai else "enemy026_1")
	caster.merge({"coord": Vector2i(8, 8), "live_speed": 100, "hp": 20, "max_hp": 100, "mp": 100, "max_mp": 100, "inventory": [241, 0, 0, 0, 0, 0, 0, 0], "equipment": [], "player_commandable": not ai, "battle_actor_role": Loop.ROLE_ENEMY if ai else Loop.ROLE_PLAYER}, true)
	caster["combat_profile"].merge({"mind": 20, "live_magic_attack": 100}, true)
	if ai: caster["hp"] = 4
	ally.merge({"coord": Vector2i(9, 8), "live_speed": 90, "hp": 20, "max_hp": 100, "player_commandable": true, "battle_actor_role": Loop.ROLE_PLAYER}, true)
	foe.merge({"coord": Vector2i(10, 8), "live_speed": 10, "hp": 100, "max_hp": 100}, true)
	loop["units"] = [caster, ally, foe]
	own(loop, "skill_book")["actors"][caster["actor_id"]]["supported_initial_ids"] = [HEAL, GREATER, LIFE, CURE]
	loop["tiles"] = {}
	loop["map_size"] = Vector2i(24, 20)
	loop["reinforcement_templates"] = []
	loop["turn_queue"] = Loop.CoreTurnQueue.rebuild(loop["units"])
	loop["interaction"] = "ai_resolving" if ai else "idle"
	return loop if ai else Loop.select_player_unit(loop, caster["id"])


func native_cases() -> void:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://docs/evidence_packets/static_reverse/original_support_magic.json"))
	for row in data["rolls"]:
		var draws: Array = row["draws"].duplicate(true)
		var result := Rolls.roll(row["input"], func(bound): check(not draws.is_empty() and bound == draws[0]["bound"], "native heal random-call order"); return int(draws.pop_front()["value"]))
		check(result["value"] == int(row["native"]["value"]) and result["hit_bonus_after"] == int(row["native"]["hit_bonus_after"]) and draws.is_empty(), "heal helper equals the normal original return, including ignored resistance")
	for row in data["applications"]:
		var loop := fixture()
		var caster: Dictionary = loop["units"][0]
		var target: Dictionary = loop["units"][1]
		var input: Dictionary = row["input"]
		caster["level"] = int(input["level"])
		caster["hit_bonus_accum"] = int(input["hit_bonus"])
		caster["combat_profile"]["mind"] = int(input["mind"])
		caster["combat_profile"]["live_magic_attack"] = int(input["magic_attack"])
		target.merge({"hp": int(input["hp"]), "max_hp": int(input["max_hp"]), "equipment": [],
			"status_flags": (1 if input["poison"] else 0) | (2 if input["no_magic"] else 0),
			"status_counters": {"poison": int(input["poison"]), "paralysis": 0, "no_magic": int(input["no_magic"])}}, true)
		var prepared := Support.prepare(caster, target, Loop.skill_fields(loop, HEAL if input["kind"] == "heal" else CURE), loop["skill_book"], loop["skill_target_data"], loop["equipment_items"])
		check(prepared["ok"], "native application fixture is valid")
		if not prepared["ok"]: continue
		var before := target.duplicate(true)
		var draws: Array = row["draws"].duplicate(true)
		var resolved := Support.resolve(prepared, target, int(caster["hit_bonus_accum"]), func(bound): check(not draws.is_empty() and draws[0]["bound"] == bound, "native application random-call order"); return int(draws.pop_front()["value"]))
		var after := target.duplicate(true)
		after.merge(resolved["target_changes"], true)
		check(target == before and after["hp"] == row["native"]["hp"] and after["status_flags"] == row["native"]["status_flags"], "bounded original application agrees without mutating its target")
		check(after["status_counters"] == {"poison": int(row["native"]["poison"]), "paralysis": 0, "no_magic": int(row["native"]["no_magic"])}, "cure clears both packed halves and preserves silence")
		check(draws.is_empty() and resolved["hit_bonus_after"] == row["native"]["hit_bonus_local"] and resolved["native_contribution"] == row["native"]["contribution"], "native numeric contribution and bonus are recorded without claiming full XP distribution")


func selected(loop: Dictionary, skill_id: String) -> Dictionary:
	return Loop.choose_magic(Loop.choose_command(loop, "magic"), skill_id)


func player_cases() -> void:
	var stock := BattleFixture.loop()
	check(Loop.magic_options(stock, "leonard").is_empty() and Loop.magic_options(stock, "enemy026_1").size() == 2, "registration preserves first-battle source grants")
	check(stock["skill_book"]["actors"]["027"]["supported_initial_ids"].has(HEAL), "source-declared later healer receives the supported real skill")
	for id in [HEAL, GREATER, LIFE]:
		for target_id in ["leonard", "enemy023_1"]:
			var loop := fixture()
			var started := selected(loop, id)
			var before := started.duplicate(true)
			check(Loop.attack_cells(started).has(loop["units"][0]["coord"]), "support cast range includes self")
			var after := Loop.attack_target(started, target_id, func(_bound): return 0)
			var receipt: Dictionary = after["last_attack"]
			check(receipt.get("skill_id") == id and receipt.get("healing", 0) > 0, "owned heal resolves through the player command path for " + target_id + " " + id + " " + str(after.get("last_attack_reject", after.get("scenario_error", ""))))
			if receipt.get("skill_id") != id: continue
			check(Loop.unit(after, target_id)["hp"] <= 100 and receipt["healing"] == receipt["defender_hp_after"] - receipt["defender_hp_before"], "healing is capped and reported as actual HP recovered")
			check(Loop.unit(after, "leonard")["mp"] == 100 - int(loop["skill_book"]["skills"][id]["fields"]["expend"]) and not receipt.has("stamina_gain"), "self HP update cannot overwrite one MP payment or award hit stamina")
			check(started == before and Loop.attack_target(after, target_id, no_rng)["units"] == after["units"], "repeated input cannot repeat a finished skill")
	var loop := fixture()
	for target in [loop["units"][0], loop["units"][1]]:
		target.merge(Loop.StatusEffectRules.apply(target, "poison", 2, 10)["changes"], true)
	loop["units"][1].merge(Loop.StatusEffectRules.apply(loop["units"][1], "no_magic", 2)["changes"], true)
	# Cure itself draws nothing; its newly integrated native EXP conversion does.
	var cured := Loop.attack_target(selected(loop, CURE), "enemy023_1", func(_bound): return 0)
	check(cured["last_attack"].get("affected_targets", []).size() == 2 and Loop.unit(cured, "leonard")["mp"] == 96, "cross-area cure prepares both friends and charges once")
	check(not Loop.StatusEffectRules.poisoned(Loop.unit(cured, "leonard")) and Loop.unit(cured, "leonard")["hp"] == 20, "self cure prevents the owner's subsequent poison tick")
	check(Loop.unit(cured, "enemy023_1")["status_counters"] == {"poison": 0, "paralysis": 0, "no_magic": 2}, "ally cure preserves other state and its unspent turn")
	for bad in ["enemy", "range", "full", "dead", "silence", "cost", "max_hp", "area_state"]:
		var invalid := fixture()
		var id := HEAL
		var target_id := "enemy023_1"
		match bad:
			"enemy": target_id = "enemy026_1"
			"range": invalid["units"][1]["coord"] = Vector2i(20, 18)
			"full": invalid["units"][1]["hp"] = 100
			"dead": invalid["units"][1]["hp"] = 0
			"silence": invalid["units"][0].merge(Loop.StatusEffectRules.apply(invalid["units"][0], "no_magic", 2)["changes"], true)
			"cost": invalid["units"][0]["mp"] = 5
			"max_hp": invalid["units"][1]["max_hp"] = 0
			"area_state":
				id = CURE
				invalid["units"][1].merge(Loop.StatusEffectRules.apply(invalid["units"][1], "poison", 2, 10)["changes"], true)
				invalid["units"][0]["status_counters"]["poison"] = 1
		var started := selected(invalid, id)
		var before := started.duplicate(true)
		var after := Loop.attack_target(started, target_id, no_rng)
		check(after["units"] == before["units"] and after["turn_queue"] == before["turn_queue"] and started == before, "support rejection is atomic before RNG: " + bad)
	var no_effect := fixture()
	var empty_cure := Loop.attack_target(selected(no_effect, CURE), "leonard", no_rng)
	check(empty_cure.get("last_attack_reject", {}).get("reason") == "skill_has_no_effect" and empty_cure["units"] == no_effect["units"], "clean area cannot silently consume cure MP")


func ai_cases() -> void:
	for mode in ["magic", "empty_mp", "silenced", "failed_use_ratio", "cure", "no_foe"]:
		var loop := fixture(true)
		var actor: Dictionary = loop["units"][0]
		own(loop, "skill_book")["actors"][actor["actor_id"]]["supported_initial_ids"] = [HEAL, CURE]
		own(loop, "ai_profiles")["actors"][actor["actor_id"]]["profile"]["ai_att_magic"] = 100
		match mode:
			"empty_mp": actor["mp"] = 0
			"silenced": actor.merge(Loop.StatusEffectRules.apply(actor, "no_magic", 2)["changes"], true)
			"failed_use_ratio": own(loop, "skill_book")["skills"][HEAL]["fields"]["use_ratio"] = "0"
			"cure":
				actor["hp"] = 100
				actor.merge(Loop.StatusEffectRules.apply(actor, "poison", 2, 10)["changes"], true)
			"no_foe":
				loop["units"][1]["coord"] = Vector2i(22, 18)
				loop["units"][2]["coord"] = Vector2i(23, 18)
		var before := loop.duplicate(true)
		var after := Loop.step_ai_turn(loop, func(_bound): return 0)
		check(after["scenario_ok"], "AI support preflight: " + mode + " " + str(after.get("scenario_error", "")))
		if not after["scenario_ok"]: continue
		var action: Dictionary = after["last_ai_action"]
		if mode in ["magic", "no_foe", "cure"]:
			check(action.get("skill_id") == (CURE if mode == "cure" else HEAL) and action.get("defender_id") == actor["id"], "AI chooses one owned self-preservation spell: " + mode)
			check(Loop.unit(after, actor["id"])["inventory"] == actor["inventory"] and Loop.unit(after, actor["id"])["mp"] == 100 - (4 if mode == "cure" else 6), "successful self spell preserves medicine and pays one fee")
		else:
			check(action.get("kind") == "use_item" and not action.has("skill_id") and Loop.unit(after, actor["id"])["mp"] == actor["mp"], "unavailable/failed spell retains one medicine fallback: " + mode)
		check(after["selected_unit_id"] == "enemy023_1" and after["turn_queue"]["index"] == 1 and after["last_ai_actions"].size() == 1, "AI self action hands off exactly once")
		check(loop == before and Loop.unit(after, "leonard")["hp"] == Loop.unit(before, "leonard")["hp"], "self action cannot also attack or mutate its caller")
	var corrupted := fixture(true)
	corrupted["units"][0]["max_hp"] = 0
	var refused := Loop.step_ai_turn(corrupted, no_rng)
	check(not refused["scenario_ok"] and refused["units"] == corrupted["units"] and refused["turn_queue"] == corrupted["turn_queue"], "malformed support cannot fall through into another attack")


## Wave 9 lane A2: 大地之癒 (EARTH 08) and 大地之惠 (EARTH 09) are magicFun_Heal rows with an area
## footprint: same 0x40aa80 bit 2 branch / proc1 roll as the water heals, every wounded ally inside
## the footprint is healed for one MP payment; the 治癒之水 effect art is reused (provisional).
## [id, cost, initial holders]
func earth_heals() -> void:
	for row in [["magic:magicEARTH:magicCode08", 25, ["056", "065"]], ["magic:magicEARTH:magicCode09", 45, ["059"]]]:
		var id: String = row[0]
		var loop := fixture()
		for holder in row[2]: check(loop["skill_book"]["actors"][holder]["supported_initial_ids"].has(id), "source holder declares the earth heal: " + holder + " " + id)
		own(loop, "skill_book")["actors"]["001"]["supported_initial_ids"].append(id)
		check(Loop.magic_options(Loop.choose_command(loop, "magic"), "leonard").any(func(option): return option["id"] == id and option["quote"]["ok"]), "the earth heal is listed and affordable in the magic menu: " + id)
		var started := selected(loop, id)
		check(started["interaction"] == "attack_select" and Loop.attack_cells(started).has(Vector2i(9, 8)), "choosing it opens ally target selection: " + id)
		var after := Loop.attack_target(started, "enemy023_1", func(_bound): return 0)
		var receipts: Array = after.get("last_attack", {}).get("affected_targets", [])
		check(after["last_attack"].get("skill_id") == id and receipts.map(func(receipt): return receipt["defender_id"]) == ["leonard", "enemy023_1"], "the footprint heals the ally center and the caster inside it, never the foe: " + id)
		check(receipts.all(func(receipt): return int(receipt["healing"]) > 0 and receipt["healing"] == receipt["defender_hp_after"] - receipt["defender_hp_before"]) and Loop.unit(after, "leonard")["hp"] > 20 and Loop.unit(after, "enemy023_1")["hp"] > 20, "both wounded allies recover actual HP: " + id)
		check(Loop.unit(after, "leonard")["mp"] == 100 - int(row[1]) and Loop.unit(after, "enemy026_1")["hp"] == 100, "one MP payment; the enemy is untouched: " + id)

## The four water support spells play their effCode scripts (驅毒 12, 治癒之水 13, 生命之水 14,
## 女神之淚 15) through SkillEffectScriptPlayer: source WATER shapes visible one tick after the
## impact mark (an object is not drawn on its creation tick — the 0x10000000 skip bit of the
## 0x45f5f7 draw walk; 生命之水's last cue creates its star ball at tick 0), every sprite gone at
## the clip's complete mark (the last fade is inside the busy interval).
func presentation_tail_cases() -> void:
	var view := preload("res://game/battle/scene/SkillEffectScriptPlayer.gd").new()
	root.add_child(view)
	for skill_id in ["magic:magicWATER:magicCode06", "magic:magicWATER:magicCode07", "magic:magicWATER:magicCode08", "magic:magicWATER:magicCode05"]:
		# Sound dispatch is already covered by real playback. This fixture isolates
		# whether the advertised busy interval actually contains all source sprites.
		var clip := {"effect_timeline": view.compile_row(skill_id, true, 3), "effect_sounds_played": [0, 1, 2, 3, 4, 5]}
		var timeline: Dictionary = clip["effect_timeline"]
		view.draw(clip, float(timeline["impact_tick"] + 1) / view.TICKS_PER_SECOND, [Vector2(300, 200)])
		check(view.sprites.any(func(sprite): return sprite.visible and sprite.modulate.a > 0.001 and str(sprite.texture.resource_path).contains("/wat")), "impact retains visible source WATER effect (first drawable tick after the impact mark): " + skill_id)
		view.draw(clip, float(timeline["complete_tick"]) / view.TICKS_PER_SECOND, [Vector2(300, 200)])
		check(view.sprites.all(func(sprite): return not sprite.visible or sprite.modulate.a <= 0.001), "cast completion cannot truncate a remaining particle fade: " + skill_id)
	# The creation tick draws nothing: 生命之水 creates its only object at tick 0.
	var life := {"effect_timeline": view.compile_row("magic:magicWATER:magicCode07", true, 3), "effect_sounds_played": [0, 1, 2, 3, 4, 5]}
	view.draw(life, 0.0, [Vector2(300, 200)])
	check(view.sprites.all(func(sprite): return not sprite.visible), "an effect object is not drawn on its creation tick (0x45f5f7 skip bit)")
	view.queue_free()
	await process_frame


static func stat_initial() -> Dictionary:
	return Loop.create([], "", Loop.BattleScenario.load_file("res://content/battles/stat_magic_trial.json"))

static func stat_fixture() -> Dictionary:
	var loop := stat_initial()
	for actor in loop["units"]:
		actor["coord"] = {"tina": Vector2i(14,16), "companion": Vector2i(14,15), "enemy026_1": Vector2i(16,16)}[actor["id"]]
		actor["grid_coord"] = actor["coord"]; actor["ai_home_coord"] = actor["coord"]
		actor["growth_profile"]["source"]["speed"] = {"tina":200, "companion":100, "enemy026_1":10}[actor["id"]]
		actor["growth_profile"]["source"]["hit_point"] += 800
		actor.merge(Loop.ProgressionRules.refresh_growth_stats(actor, loop["equipment_items"]), true)
		actor["hp"] = actor["max_hp"]
	loop["turn_queue"] = Loop.CoreTurnQueue.rebuild(loop["units"])
	return Loop._return_to_player(loop, "tina")

static func gear(loop: Dictionary, code: int, slot: String) -> Dictionary:
	return Loop.change_equipment(loop, slot, Loop.unit(loop,"tina")["inventory"].find(code) if code else -1, code)

static func cast(loop: Dictionary, id: String, target: String, rng: Variant = null) -> Dictionary:
	return Loop.attack_target(Loop.choose_magic(Loop.choose_command(loop,"magic"),id),target,rng)

static func set_words(actor: Dictionary, words: Dictionary) -> void:
	actor["status_flags"] = 0
	actor["status_counters"] = {"poison":0, "no_magic":0, "paralysis":0}
	for key in words:
		var value := int(words[key])
		if value == 0 and Stats.FLAGS.has(key): continue
		actor["status_counters"][key] = value
		if value: actor["status_flags"] |= {"poison":1,"no_magic":2,"paralysis":4,"attack_up":16,"defense_up":32}[key]

static func buff(loop: Dictionary, id: String, kind: String, duration: int = 3, power: int = 20) -> void:
	var actor := Loop._unit(loop,id)
	actor.merge(Stats.apply(actor,kind,duration,power)["actor"],true)
	actor.merge(Loop.ProgressionRules.refresh_growth_stats(actor,loop["equipment_items"]),true)

func stat_magic_cases() -> void:
	var boot := stat_initial()
	check(boot["scenario_ok"],"published stat trial initializes: "+str(boot.get("scenario_error","")))
	if not boot["scenario_ok"]: return
	native_applications()
	native_refresh_and_ticks()
	native_ai()
	ownership_and_actions()
	aid_and_fallback()
	dispel_decisions_and_combat()
	high_tier_area_buffs()
	resist_barrier()
	save_and_terminal()

func native_applications() -> void:
	var source := priest_initial()
	var book: Dictionary = stat_initial()["skill_book"]
	var packet: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://docs/evidence_packets/static_reverse/original_stat_magic.json"))
	for row in packet["applications"]:
		var c: Dictionary = row["input"]
		var target := Loop.unit(source,"tina").duplicate(true)
		target["level"]=int(c["level"]); target["hp"]=int(c["hp"]); target["mp"]=int(c["mp"])
		set_words(target,c["words"])
		target=Loop.ProgressionRules.refresh_growth_stats(target,source["equipment_items"])
		var caster := target.duplicate(true)
		caster["level"]=3; caster["hit_bonus_accum"]=int(c["hit_bonus"])
		caster["combat_profile"]["mind"]=15; caster["combat_profile"]["live_magic_attack"]=40
		var id: String = {"attack_up":ATT,"defense_up":DEF,"dispel":DISPEL}[c["kind"]]
		var fields: Dictionary = book["skills"][id]["fields"].duplicate(true)
		fields["hit_ratio"]=str(int(c["hit"]))
		if c["low"] != null: fields["damage"]="%d,%d" % [c["low"],c["high"]]
		var prepared := Magic.prepare(caster,target,fields,book,source["skill_target_data"],source["equipment_items"])
		check(prepared["ok"],"bounded stat fixture has valid source refresh input")
		var draws: Array = row["draws"].duplicate(true)
		var random := func(bound):
			check(not draws.is_empty() and bound==int(draws[0]["bound"]),"stat original draw order/bound")
			return int(draws.pop_front()["value"]) if not draws.is_empty() else 0
		var before := target.duplicate(true)
		var result := Magic.resolve(prepared,target,int(c["hit_bonus"]),source["equipment_items"],random)
		check(draws.is_empty() and target==before,"native proposal consumes exactly its tape, never modifies target")
		check(result["native_contribution"]==row["native"]["contribution"] and result["hit_bonus_after"]==row["native"]["hit_bonus"],"original contribution/compensation before final EXP")
		var after := target.duplicate(true); after.merge(result["target_changes"],true)
		check(after["status_flags"]==int(row["native"]["flags"]),"original positive/negative flags retained")
		for key in row["native"]["words"]:
			check(int(after["status_counters"].get(key,0))==int(row["native"]["words"][key]),"original packed application: "+key)
		for pair in [["attack","live_attack_damage"],["defense","live_defense"]]:
			check(after["combat_profile"][pair[1]]==row["derived"][pair[0]],"full native post-effect refresh: "+pair[0])
		check(not result["target_changes"].has("mp") and not result["target_changes"].has("stamina"),"target proposal cannot refund self-cast MP or consume an extra ST")

func native_refresh_and_ticks() -> void:
	var first := BattleFixture.loop(); var priest := priest_initial()
	var packet: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://docs/evidence_packets/static_reverse/original_stat_magic.json"))
	for row in packet["refresh"]:
		var c: Dictionary = row["input"]
		var actor: Dictionary = Loop.unit(priest,"tina") if c["actor"]=="002" else first["units"].filter(func(a):return a["actor_id"]==c["actor"])[0].duplicate(true)
		actor["level"]=int(c["level"]);actor["hp"]=1;actor["mp"]=0
		if not c["equipped"]:actor["equipment"]=[]
		set_words(actor,{"attack_up":c["attack_up"],"defense_up":c["defense_up"]})
		for r in row["native"]:
			actor["combat_profile"]["live_attack_damage"]=999;actor["combat_profile"]["live_defense"]=999;actor["move_point"]=999
			actor=Loop.ProgressionRules.refresh_growth_stats(actor,first["equipment_items"])
			for pair in [["attack","live_attack_damage"],["defense","live_defense"],["magic_attack","live_magic_attack"]]:
				check(actor["combat_profile"][pair[1]]==r["values"][pair[0]],"four-job native idempotent derived stat "+str(c)+pair[0])
			for key in ["max_hp","max_mp","move_point"]:check(actor[key]==r["values"][key],"four-job native refresh "+key)
			check(actor["live_speed"]==r["values"]["speed"] and actor["hp"]==1 and actor["mp"]==0,"buff does not increase resources or borrow another class speed")
	for row in packet["ticks"]:
		var actor := Loop.unit(priest,"tina").duplicate(true)
		actor["level"]=3; actor["hp"]=10; actor["mp"]=5
		set_words(actor,row["input"])
		actor=Loop.ProgressionRules.refresh_growth_stats(actor,first["equipment_items"])
		var tick := Loop.StatusEffectRules.after_action(actor)
		check(tick["ok"],"native expiry fixture valid")
		actor.merge(tick["changes"],true)
		actor=Loop.ProgressionRules.refresh_growth_stats(actor,first["equipment_items"])
		for key in row["native"]:check(Stats.word(actor,key)==int(row["native"][key]),"full native duration return "+key)
		check(actor["combat_profile"]["live_attack_damage"]==row["derived"]["attack"] and actor["combat_profile"]["live_defense"]==row["derived"]["defense"],"expiry invokes same source recomputation")

func native_ai() -> void:
	var packet: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://docs/evidence_packets/static_reverse/original_ai_stat.json"))
	for row in packet["cases"]:
		var c: Dictionary=row["input"];var draws:Array=row["draws"].duplicate(true)
		var random:=func(n):
			check(not draws.is_empty() and int(draws[0]["bound"])==n,"original positive-aid RNG")
			return int(draws.pop_front()["value"]) if not draws.is_empty() else 0
		if c["kind"]=="priority":
			var result:=Aid.next_check({"ai_help_otherhp":c["rates"][0],"ai_help_status":c["rates"][1],"ai_help_attack":c["rates"][2]},int(c["attempted"]),int(c["roll"]),random,true)
			for key in ["mode","attempted","next_roll"]:check(result[key]==row["result"][key],"three-gate native priority "+key)
		elif c["kind"]=="useful":check(Aid.buff_useful(c["masks"],int(c["flags"]))==bool(row["result"]),"full original buff-usefulness predicate")
		else:
			var rows:Array=c["units"].duplicate(true)
			for u in rows:
				if u!=null:u["coord"]=Vector2i(u["coord"][0],u["coord"][1]);u["status_flags"]=u["flags"]
			var cursor:=0;var indices:Array=[];var masks:Array=[]
			for attempt in range(rows.size()+1):
				var result:=Aid.scan(rows,0,"buff",cursor,int(c["radius"]),random,c["masks"])
				indices.append(result["index"]+1)
				if result["index"]<0:break
				masks.append(result["mask"]);cursor=result["next_cursor"]
			check(indices==row["result"]["indices"].map(func(v):return int(v)) and masks==row["result"]["masks"].map(func(v):return int(v)),"full native ally scan/continuation skips matching present buffs")
		check(draws.is_empty(),"AI consumes no unexplained draws")

func ownership_and_actions() -> void:
	var formal := priest_initial()
	check(Loop.magic_options(formal,"tina").size()==1,"default priest not silently granted training buffs")
	check(formal["skill_book"]["actors"]["045"]["supported_initial_ids"].has(ATT) and formal["skill_book"]["actors"]["045"]["supported_initial_ids"].has(DEF),"source045 actually declares both buffs")
	check(formal["skill_book"]["actors"]["027"]["supported_initial_ids"].has(DISPEL) and formal["skill_book"]["actors"]["029"]["supported_initial_ids"].is_empty(),"source027 owns dispel, cinematic029 remains empty")
	var loop:=gear(stat_fixture(),227,"accessory2");var before:=loop.duplicate(true)
	var self_cast:=cast(loop,ATT,"tina",zero)
	check(not self_cast["last_attack"].is_empty(),"self-target buff resolves")
	if self_cast["last_attack"].is_empty():return
	check(Loop.unit(self_cast,"tina")["mp"]==Loop.unit(before,"tina")["mp"]-19,"self-cast target cannot refund the independent payment")
	check(Loop.unit(self_cast,"tina")["stamina"]==40 and loop==before,"buff consumes no stamina or proposal input")
	self_cast=Loop.finish_exhausted_action(self_cast)
	check(self_cast["extra_action"]["pending"] and self_cast["action_end_sequence"]==0 and (Stats.word(Loop.unit(self_cast,"tina"),"attack_up")&65535)==2,"first action does not tick source duration")
	var repeated:=cast(self_cast,ATT,"tina",zero)
	check(repeated["last_attack"]["stat_effects"][0]["duration"]==4,"same-caster second action merges duration, not a second additive stat")
	repeated=Loop.finish_exhausted_action(repeated)
	var actor:=Loop.unit(repeated,"tina")
	check(not repeated["extra_action"]["pending"] and repeated["action_end_sequence"]==1 and (Stats.word(actor,"attack_up")&65535)==3,"two actions close one duration/recovery tail")
	check(actor["combat_profile"]["live_attack_damage"]==Loop.unit(before,"tina")["combat_profile"]["live_attack_damage"]+Stats.power(actor,"attack_up"),"repeat does not add the same source buff twice")
	var grown:=Loop.ProgressionRules.resolve_experience(actor,1000,loop["equipment_items"])
	check(grown["level"]>actor["level"] and Stats.word(grown,"attack_up")==Stats.word(actor,"attack_up") and grown["mp"]==actor["mp"],"level refresh preserves one buff and spent MP")
	var mobile:=gear(gear(stat_fixture(),227,"accessory2"),232,"accessory1")
	var moved:=Loop.move_unit_to(Loop.choose_command(mobile,"move"),Vector2i(15,16))
	var moved_cast:=cast(moved,DEF,"companion",zero)
	check(moved_cast["last_attack"].get("skill_id")==DEF and moved_cast["pending_move"]==false,"current ring permits moved allied buff")
	moved_cast=Loop.finish_exhausted_action(moved_cast)
	var removed:=gear(moved_cast,0,"accessory1")
	var walk:=Loop.move_unit_to(Loop.choose_command(removed,"move"),Vector2i(14,16))
	check(not Loop.command_available(walk,"magic"),"second-action unequip revokes movement casting immediately")
	for condition in ["mp","no_magic","paralysis"]:
		var invalid:=stat_fixture();var caster:=Loop._unit(invalid,"tina")
		if condition=="mp":caster["mp"]=0
		else:caster.merge(Loop.StatusEffectRules.apply(caster,condition,2)["changes"],true)
		var ready:=Loop.SkillResolutionRules.available(caster,ATT,invalid["skill_book"]["skills"][ATT]["fields"],invalid["skill_book"],invalid["skill_target_data"],invalid["equipment_items"])
		check(not ready["ok"],"blocked resource/status quote "+condition)
		var rejected:=cast(invalid,ATT,"tina",no_rng)
		check(rejected["units"]==invalid["units"] and rejected["turn_queue"]==invalid["turn_queue"],"blocked cast cannot spend/advance "+condition)
	var empty:=stat_fixture();var rejected:=cast(empty,DISPEL,"enemy026_1",no_rng)
	check(rejected["units"]==empty["units"] and rejected["last_attack"].is_empty(),"dispel on unenhanced enemy refuses without payment or RNG")

## Wave 9 lane A2: 地靈聖護 (EARTH 07, DefUp) and 赤炎波動 (FIRE 06, AttUp) are the area editions of
## 地精守護／灼熱波動 — same 0x40aa80 0x20／0x40 branches and packed words, range2CellCircle footprint,
## one MP payment for every ally inside. [id, kind, cost, initial holders]
func high_tier_area_buffs() -> void:
	for row in [["magic:magicEARTH:magicCode07", "defense_up", 30, ["058", "065"]], ["magic:magicFIRE:magicCode06", "attack_up", 38, ["058", "065"]]]:
		var id: String = row[0]
		var kind: String = row[1]
		var loop := stat_fixture()
		for holder in row[3]: check(loop["skill_book"]["actors"][holder]["supported_initial_ids"].has(id), "source holder declares the area buff: " + holder + " " + id)
		own(loop, "skill_book")["actors"]["002"]["supported_initial_ids"].append(id)
		Loop._unit(loop, "tina")["mp"] = 200
		Loop._unit(loop, "tina")["max_mp"] = 200
		var menu := Loop.choose_command(loop, "magic")
		check(Loop.magic_options(menu, "tina").any(func(option): return option["id"] == id and option["quote"]["ok"]), "the area buff is listed and affordable in the magic menu: " + id)
		var picked := Loop.choose_magic(menu, id)
		check(picked["interaction"] == "attack_select" and picked["selected_skill_id"] == id and Loop.attack_cells(picked).has(Vector2i(14, 15)), "choosing it opens ally target selection with the range4CellCircle cast range: " + id)
		var settled := Loop.attack_target(picked, "companion", zero)
		var ids: Array = settled.get("last_attack", {}).get("affected_targets", []).map(func(receipt): return receipt["defender_id"])
		check(settled["attacked_this_action"] and Loop.unit(settled, "tina")["mp"] == 200 - int(row[2]) and settled["last_attack"].get("skill_id") == id, "the area buff pays its source MP once: " + id)
		check(ids.has("companion") and ids.has("tina") and not ids.has("enemy026_1"), "every ally inside the range2CellCircle footprint (caster included) is buffed, the enemy is not: " + id)
		for ally in ["companion", "tina"]:
			var unit := Loop.unit(settled, ally)
			check(Stats.word(unit, kind) != 0 and (int(unit["status_flags"]) & int(Stats.FLAGS[kind])) != 0, "%s carries the packed %s word after the cast: %s" % [ally, kind, id])
			var field := "live_defense" if kind == "defense_up" else "live_attack_damage"
			check(int(unit["combat_profile"][field]) == int(Loop.unit(loop, ally)["combat_profile"][field]) + Stats.power(unit, kind), "%s derived %s includes exactly one buff power: %s" % [ally, field, id])
		check(Loop.unit(settled, "enemy026_1")["status_flags"] == Loop.unit(loop, "enemy026_1")["status_flags"], "the enemy outside the ally footprint keeps its state: " + id)

## 魔障壁 (magic:magicOTHER:magicCode04, magicFun_AllUp 0x100, wave 9 lane A2): 0x40aa80 0x40b1ee
## branch — proc1 helper (value discarded), flag 0x40, rand(4)+2 turns into +0x48 (cap 9), then
## rand(14)+7 added to the +0x4a strength (cap 20, cumulative, no averaging), contribution 3／turn,
## 0x448840 adds the strength to all five resistances (cap 80); 退魔 never clears it (static-derived).
func resist_barrier() -> void:
	const BARRIER := "magic:magicOTHER:magicCode04"
	var loop := stat_fixture()
	check(loop["skill_book"]["actors"].values().all(func(actor): return not actor["supported_initial_ids"].has(BARRIER)), "no PLAYERS row declares 魔障壁; only 賢者 87@48 learns it")
	own(loop, "skill_book")["actors"]["002"]["supported_initial_ids"].append(BARRIER)
	Loop._unit(loop, "tina")["mp"] = 200
	Loop._unit(loop, "tina")["max_mp"] = 200
	var before := Loop.unit(loop, "companion").duplicate(true)
	check(Loop.magic_options(Loop.choose_command(loop, "magic"), "tina").any(func(option): return option["id"] == BARRIER and option["quote"]["ok"]), "魔障壁 is listed and affordable in the magic menu")
	var casted := cast(loop, BARRIER, "companion", zero)
	var receipt: Dictionary = casted.get("last_attack", {})
	check(receipt.get("skill_id") == BARRIER and Loop.unit(casted, "tina")["mp"] == 200 - 31 and receipt.get("magic_key") == "resist_up", "one 31 MP payment settles the barrier")
	var ally := Loop.unit(casted, "companion")
	check((int(ally["status_flags"]) & 0x40) != 0 and Stats.word(ally, "resist_up") == ((7 << 16) | 2), "zero draws give flag 0x40 with 2 turns and strength rand(14)+7 = 7")
	check(receipt["stat_effects"].size() == 1 and receipt["stat_effects"][0]["kind"] == "resist_up" and int(receipt["native_contribution"]) == 6 and receipt["native_stat_rolls"].size() == 2 and receipt["sampled_durations"] == [2], "the receipt carries one resist_up effect, 3 contribution per added turn and the proc1 roll plus the strength sample")
	for index in range(5):
		var key := str(index)
		check(int(ally["combat_profile"]["resist_by_type"][key]) == mini(80, int(before["combat_profile"]["resist_by_type"][key]) + 7), "resistance %s rises by the barrier strength (cap 80)" % key)
	check(ally["combat_profile"]["live_attack_damage"] == before["combat_profile"]["live_attack_damage"] and ally["combat_profile"]["live_defense"] == before["combat_profile"]["live_defense"] and ally["hp"] == before["hp"], "attack, defense and vitals are untouched")
	check(Magic.receipt_error(receipt, casted["skill_book"]) == "" and Save.encode(casted, VIEW)["ok"], "the barrier receipt replays through the checkpoint validator and saves")
	var again := cast(Loop._return_to_player(casted.duplicate(true), "tina"), BARRIER, "companion", zero)
	var stacked := Loop.unit(again, "companion")
	check(Stats.word(stacked, "resist_up") == ((14 << 16) | 4) and int(stacked["combat_profile"]["resist_by_type"]["0"]) == mini(80, int(before["combat_profile"]["resist_by_type"]["0"]) + 14), "a second cast adds strength and turns instead of averaging")
	var capped := Stats.apply(stacked, "resist_up", 5, 20)
	check(Stats.word(capped["actor"], "resist_up") == ((20 << 16) | 9) and int(capped["contribution"]) == 15, "strength caps at 20 and turns at 9; contribution counts only the added turns")
	var dispelled := Stats.dispel(stacked)
	check(dispelled["effects"].is_empty() and Stats.word(dispelled["actor"], "resist_up") == Stats.word(stacked, "resist_up"), "退魔 clears only attack／defense words, never the barrier")
	var enemy_barrier := again.duplicate(true)
	var foe := Loop._unit(enemy_barrier, "enemy026_1")
	foe.merge(Stats.apply(foe, "resist_up", 3, 10)["actor"], true)
	var dispel_quote := Magic.prepare(Loop.unit(enemy_barrier, "tina"), foe, enemy_barrier["skill_book"]["skills"][DISPEL]["fields"], enemy_barrier["skill_book"], enemy_barrier["skill_target_data"], enemy_barrier["equipment_items"])
	check(dispel_quote["ok"] and not dispel_quote["useful"], "a barrier-only enemy is not a useful 退魔 target")
	var ticking := stacked.duplicate(true)
	ticking["status_counters"]["resist_up"] = (14 << 16) | 1
	var tick := Loop.StatusEffectRules.after_action(ticking)
	check(tick["ok"] and tick["expired"].has("resist_up") and (int(tick["changes"]["status_flags"]) & 0x40) == 0 and not tick["changes"]["status_counters"].has("resist_up"), "the last turn expires the barrier and clears flag 0x40")
	ticking.merge(tick["changes"], true)
	var restored := Loop.ProgressionRules.refresh_growth_stats(ticking, again["equipment_items"])
	check(restored["combat_profile"]["resist_by_type"] == before["combat_profile"]["resist_by_type"], "the expiry refresh returns the five resistances to their unbuffed values")
	check(Aid.buff_useful([0x100], 0) and not Aid.buff_useful([0x100], 0x40) and Aid.buff_useful([0x100], 0x30), "the AI buff scan (0x40dcf0) maps AllUp to live flag 0x40")

func aid_and_fallback() -> void:
	var loop:=stat_fixture();var actor:=Loop._unit(loop,"tina")
	actor["player_commandable"]=false;actor["battle_actor_role"]=Loop.ROLE_FRIENDLY
	actor["inventory"]=[0,0,0,0,0,0,0,0];actor["equipment"].append({"slot":"accessory2","item_code":227})
	own(loop, "skill_book")["actors"]["002"]["supported_initial_ids"]=[ATT,DEF]
	own(loop, "ai_profiles")["actors"]["002"]["profile"].merge({"ai_check_dying":0,"ai_check_hp":0,"ai_help_otherhp":0,"ai_help_status":0,"ai_help_attack":100,"ai_att_magic":100},true)
	loop["selected_unit_id"]="";loop["interaction"]="ai_resolving"
	var first:=Loop.step_ai_turn(loop,zero)
	check(first["scenario_ok"] and first["last_ai_action"].get("skill_id")==ATT and first["last_ai_action"]["ai_decision"]["priority"]["kind"]=="ally_skill","AI chooses a legal owned buff before ordinary offense")
	if not first["scenario_ok"]:return
	check(first["extra_action"]["pending"] and first["action_end_sequence"]==0,"AI first buff preserves second action without owner tail")
	var second:=Loop.step_ai_turn(first,zero)
	check(second["scenario_ok"] and second["last_ai_action"].get("skill_id")!=first["last_ai_action"].get("skill_id"),"AI recomputes missing positive state, never refreshes its first buff")
	var ally:=Loop.unit(second,"companion")
	check((int(ally["status_flags"])&0x30)==0x30 and second["action_end_sequence"]==1,"both buff states committed through one AI action pair")
	for condition in ["mp","no_magic","paralysis","full"]:
		var blocked:=loop.duplicate(true);var caster:=Loop._unit(blocked,"tina")
		if condition=="mp":caster["mp"]=0
		elif condition=="full":buff(blocked,"companion","attack_up");buff(blocked,"companion","defense_up")
		else:caster.merge(Loop.StatusEffectRules.apply(caster,condition,2)["changes"],true)
		var done:=Loop.step_ai_turn(blocked,zero)
		if condition=="full":
			# 0x43fce1..0x43fd46: no ally still needs a buff, so the caster's own mask decides and tina buffs herself.
			check(done["scenario_ok"] and done["last_ai_action"].get("skill_id") in [ATT,DEF] and (int(Loop.unit(done,"tina")["status_flags"])&0x30)!=0,"AI with every ally already enhanced buffs itself (0x43fce1..0x43fd46)"+str(done.get("scenario_error","")))
			continue
		check(done["scenario_ok"] and not done["last_ai_action"].has("skill_id"),"AI no-resource/status/already-enhanced fallback: "+condition+str(done.get("scenario_error","")))
		if condition=="paralysis":check(done["last_ai_action"]["kind"]=="paralysis_skip" and not done["extra_action"]["pending"],"paralysis skips one queue slot, not two fabricated actions")
	var dispel:=stat_fixture();buff(dispel,"enemy026_1","attack_up");buff(dispel,"enemy026_1","defense_up")
	var victim:=Loop._unit(dispel,"enemy026_1")
	for key in ["poison","no_magic","paralysis"]:victim.merge(Loop.StatusEffectRules.apply(victim,key,3,7 if key=="poison" else 0)["changes"],true)
	var gone:=cast(dispel,DISPEL,"enemy026_1",zero)
	check(gone["last_attack"].get("skill_id")==DISPEL and int(Loop.unit(gone,"enemy026_1")["status_flags"])==7,"dispel clears exactly two buffs and retains three afflictions")
	check(gone["last_attack"]["native_contribution"]==96 and Loop.unit(gone,"tina")["mp"]==Loop.unit(dispel,"tina")["mp"]-18,"dispel contribution and one cost reach shared final settlement")
	check(Loop.unit(gone,"enemy026_1")["hp"]==victim["hp"] and gone["last_attack"]["actual_damage"]==0,"dispel is not fake HP damage")

func dispel_decisions_and_combat() -> void:
	var loop := stat_fixture()
	var actor := Loop._unit(loop,"tina")
	actor["player_commandable"] = false; actor["battle_actor_role"] = Loop.ROLE_FRIENDLY
	actor["no_attack"] = true; actor["inventory"] = [0,0,0,0,0,0,0,0]
	actor["equipment"].append({"slot":"accessory2","item_code":227})
	own(loop, "skill_book")["actors"]["002"]["supported_initial_ids"] = [DISPEL]
	own(loop, "skill_book")["skills"][DISPEL]["fields"]["use_ratio"] = "100"
	own(loop, "ai_profiles")["actors"]["002"]["profile"].merge({"ai_check_hp":0,"ai_check_dying":0,"ai_help_otherhp":0,"ai_help_status":0,"ai_help_attack":0,"ai_att_magic":100},true)
	buff(loop,"enemy026_1","attack_up"); buff(loop,"enemy026_1","defense_up")
	loop["selected_unit_id"] = ""; loop["interaction"] = "ai_resolving"
	var first := Loop.step_ai_turn(loop,zero)
	check(first["scenario_ok"] and first["last_ai_action"].get("skill_id") == DISPEL,"offensive AI uses the actual source bucket for enemy dispel")
	check((int(Loop.unit(first,"enemy026_1")["status_flags"]) & 0x30) == 0,"AI dispel submits both removals before the independent next decision")
	var second := Loop.step_ai_turn(first,zero)
	check(second["scenario_ok"] and not second["last_ai_action"].has("skill_id") and Loop.unit(second,"tina")["mp"] == actor["mp"] - 18,"second AI action rejects the now-useless dispel without another debit")
	var baseline := stat_fixture()
	Loop._unit(baseline,"enemy026_1")["coord"] = Vector2i(15,16)
	Loop._unit(baseline,"enemy026_1")["no_attack"] = true
	var stronger := baseline.duplicate(true); buff(stronger,"tina","attack_up",3,24)
	var guarded := baseline.duplicate(true); buff(guarded,"enemy026_1","defense_up",3,30)
	var ordinary := Loop.attack_target(Loop.choose_command(baseline,"attack"),"enemy026_1",zero)
	var attack_up := Loop.attack_target(Loop.choose_command(stronger,"attack"),"enemy026_1",zero)
	var defense_up := Loop.attack_target(Loop.choose_command(guarded,"attack"),"enemy026_1",zero)
	check(attack_up["last_attack"]["damage"] > ordinary["last_attack"]["damage"] and defense_up["last_attack"]["damage"] < ordinary["last_attack"]["damage"],"actual ordinary damage reads current flat attack and defense enhancement")
	var wind := "magic:magicAIR:magicCode01"
	own(baseline, "skill_book")["actors"]["002"]["supported_initial_ids"].append(wind)
	var fields: Dictionary = baseline["skill_book"]["skills"][wind]["fields"]
	var caster := Loop.unit(baseline,"tina")
	var target := Loop.unit(baseline,"enemy026_1")
	var original := Loop.SkillResolutionRules.resolve(caster,target,wind,fields,baseline["skill_book"],baseline["skill_target_data"],baseline["equipment_items"],caster["coord"],baseline["map_size"],zero)
	var enhanced := Loop.SkillResolutionRules.resolve(Loop.unit(stronger,"tina"),Loop.unit(guarded,"enemy026_1"),wind,fields,baseline["skill_book"],baseline["skill_target_data"],baseline["equipment_items"],caster["coord"],baseline["map_size"],zero)
	check(original["ok"] and enhanced["ok"] and original["receipt"]["damage"] == enhanced["receipt"]["damage"],"physical enhancements do not become an invented multiplier on wind magic")
	var receiver := Loop.unit(baseline,"companion").duplicate(true); receiver["hp"] = 1
	var heal := HEAL
	var heal_fields: Dictionary = baseline["skill_book"]["skills"][heal]["fields"]
	var a := Loop.SkillResolutionRules.resolve(caster,receiver,heal,heal_fields,baseline["skill_book"],baseline["skill_target_data"],baseline["equipment_items"],caster["coord"],baseline["map_size"],zero)
	var b := Loop.SkillResolutionRules.resolve(Loop.unit(stronger,"tina"),receiver,heal,heal_fields,baseline["skill_book"],baseline["skill_target_data"],baseline["equipment_items"],caster["coord"],baseline["map_size"],zero)
	check(a["ok"] and b["ok"] and a["receipt"]["healing"] == b["receipt"]["healing"],"attack enhancement leaves actual support healing and MP formula unchanged")

func save_and_terminal() -> void:
	var loop:=gear(stat_fixture(),227,"accessory2")
	buff(loop,"tina","attack_up",1)
	var first:=Loop.begin_wait_resolution(loop)
	check(first["extra_action"]["pending"] and Stats.word(Loop.unit(first,"tina"),"attack_up")>0,"buff1 survives first independent action")
	var saved:=Save.encode(first,VIEW)
	var tampered:=first.duplicate(true)
	Loop._unit(tampered,"tina")["combat_profile"]["live_attack_damage"]+=20
	check(not Save.encode(tampered,VIEW)["ok"] and Loop.begin_wait_resolution(tampered)==tampered,"stale/double-added buff values reject save and final-action advancement")
	check(saved["ok"],"active buff/second-action checkpoint accepted: "+str(saved.get("error","")))
	if not saved["ok"]:return
	var restored:=Save.decode(saved["bytes"], first)
	check(restored["ok"] and restored["snapshot"]["loop"]==first,"load does not reapply buff or replay first action")
	var finish:=Loop.begin_wait_resolution(first);var again:=Loop.begin_wait_resolution(restored["snapshot"]["loop"])
	check(finish==again and finish["action_end_sequence"]==1 and Stats.word(Loop.unit(finish,"tina"),"attack_up")==0,"restored final action has identical expiry and RNG order")
	check(finish["last_action_end"]["events"].any(func(e):return e["kind"]=="attack_up_expired"),"expiry carries explicit presentation receipt")
	var clean:=Loop.ProgressionRules.refresh_growth_stats(Loop.unit(finish,"tina"),finish["equipment_items"])
	check(clean["combat_profile"]==Loop.unit(finish,"tina")["combat_profile"],"final owner tail removes derived buff immediately")
	var casted:=cast(gear(stat_fixture(),227,"accessory2"),ATT,"tina",zero)
	check(Save.encode(casted,VIEW)["ok"],"settled original stat receipt saves without replay")
	var bad:=casted.duplicate(true);bad["last_attack"]["stat_effects"][0]["after_power"]+=1
	check(not Save.encode(bad,VIEW)["ok"],"saved receipt cannot silently reorder or alter stat effects")
	for outcome in [BattleOutcome.VICTORY_ENEMIES_CLEARED,BattleOutcome.DEFEAT_FALLEN,BattleOutcome.VICTORY_ESCAPE]:
		var terminal:=stat_fixture();buff(terminal,"tina","attack_up");buff(terminal,"enemy026_1","defense_up")
		if outcome==BattleOutcome.VICTORY_ENEMIES_CLEARED:Loop._set_unit_defeated(terminal,"enemy026_1",true)
		elif outcome==BattleOutcome.DEFEAT_FALLEN:Loop._set_unit_defeated(terminal,"tina",true)
		else:Loop._set_unit_coord(terminal,"tina",terminal["escape_zone"][0])
		terminal=Loop._resolve_outcome(terminal)
		check(terminal["battle_outcome"]==outcome and Save.encode(terminal,VIEW)["ok"],"enhanced terminal is coherent and saveable "+BattleOutcome.describe(outcome))
		check(Loop.step_ai_turn(terminal,no_rng)==terminal and Loop.finish_exhausted_action(terminal)==terminal and Loop._advance_current_actor(terminal)==terminal,"terminal freezes every subsequent status/resource/extra-action tail "+BattleOutcome.describe(outcome))
		var restarted:=stat_initial();check(not BattleOutcome.decided(restarted) and Stats.word(Loop.unit(restarted,"tina"),"attack_up")==0,"new scenario carries no expired/terminal enhancement")


static func priest_initial() -> Dictionary:
	return Loop.create([],"",Loop.BattleScenario.load_file("res://content/battles/priest_trial.json"))

static func priest_fixture() -> Dictionary:
	var loop := priest_initial()
	for actor in loop["units"]:
		actor["coord"]={"tina":Vector2i(10,16),"companion":Vector2i(10,15),"enemy021_1":Vector2i(12,16)}[actor["id"]]
		actor["grid_coord"]=actor["coord"];actor["ai_home_coord"]=actor["coord"]
		actor["live_speed"]={"tina":200,"companion":100,"enemy021_1":50}[actor["id"]]
		actor["player_commandable"]=actor["id"]!="enemy021_1"
		actor["battle_actor_role"]=Loop.ROLE_PLAYER if actor["player_commandable"] else Loop.ROLE_ENEMY
	loop["turn_queue"]=Loop.CoreTurnQueue.rebuild(loop["units"])
	return Loop._return_to_player(loop,"tina")

static func equip(loop:Dictionary,slot:String,code:int)->Dictionary:
	var actor:=Loop.unit(loop,"tina")
	return Loop.change_equipment(loop,slot,actor["inventory"].find(code) if code else -1,code)

static func healing(loop:Dictionary)->Dictionary:
	return Loop.choose_magic(Loop.choose_command(loop,"magic"),HEAL)

func priest_cases()->void:
	var boot:=priest_initial()
	check(boot["scenario_ok"],"priest scenario initialization: "+str(boot.get("scenario_error","")))
	if not boot["scenario_ok"]:return
	native_stats()
	actions_and_growth()
	mana_items()
	ai_and_terminal()

func native_stats()->void:
	var loop:=priest_initial();check(loop["scenario_ok"],"source priest initializes in the real loop")
	var source:=Loop.unit(loop,"tina")
	check(source["actor_id"]=="002" and source["growth_profile"]["job_code"]==85 and source["weapon_code"]==82,"player slot source002 is priest85 with its actual staff, not story029")
	check(Loop.magic_options(loop,"tina").size()==1 and Loop.magic_options(loop,"tina")[0]["id"]==HEAL,"initial healing ownership comes from source002 alone")
	check(not Loop.can_use_special(loop,"tina"),"zero initial stamina cannot pay the priest's source special")
	var packet:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://docs/evidence_packets/static_reverse/original_priest.json"))
	for row in packet["stats"]:
		var c:Dictionary=row["input"];var actor:=source.duplicate(true)
		actor["level"]=int(c["level"]);actor["hp"]=int(c["hp"]);actor["mp"]=int(c["mp"])
		actor["combat_profile"].merge(c["attributes"],true);actor["growth_profile"]["source"]["mode"]=int(c["mode"]);actor["player_mode"]=int(c["mode"]) # live +0x28 of the native run
		actor["equipment"]=[]
		for i in range(6):
			if int(c["equipment"][i])>0:actor["equipment"].append({"slot":Loop.EquipmentRules.SLOTS[i],"item_code":int(c["equipment"][i])})
		for native in row["native"]:
			actor=Loop.ProgressionRules.refresh_growth_stats(actor,loop["equipment_items"])
			var v:Dictionary=native["values"]
			for k in ["max_hp","max_mp","move_point"]:check(actor[k]==int(v[k]),"native priest "+str(c["name"])+" "+k)
			check(actor["hp"]==int(v["current_hp"]) and actor["mp"]==int(v["current_mp"]),"refresh clamps but never refills current resources")
			for pair in [["attack","live_attack_damage"],["defense","live_defense"],["magic_attack","live_magic_attack"],["hit_rate","live_hit_ratio"],["attack_back","attack_back"],["attack_damagex2","attack_damagex2"]]:
				check(actor["combat_profile"][pair[1]]==int(v[pair[0]]),"native priest "+str(c["name"])+" "+pair[0])
			check(actor["live_speed"]==int(v["speed"]),"native priest speed matches")
			for element in v["resist_by_type"]:
				check(int(actor["combat_profile"]["resist_by_type"][element])==int(v["resist_by_type"][element]),"native priest resistance matches: "+element)

func actions_and_growth()->void:
	var loop:=priest_fixture();var actor:=Loop._unit(loop,"tina")
	actor["exp"]=99
	var before:=loop.duplicate(true)
	var payment:Dictionary=Loop.magic_options(loop,"tina")[0]["quote"]
	var healed:=Loop.attack_target(healing(loop),"companion",zero)
	check(healed["last_attack"]["healing"]>0 and Loop.unit(healed,"tina")["mp"]==actor["mp"]-int(payment["amount"]),"source healing commits actual HP and one source payment")
	check(Loop.unit(healed,"tina")["level"]>1 and healed["last_attack"]["experience"]["gained"]>0,"healing contribution reaches final EXP and priest level refresh")
	check(loop==before and not healed["extra_action"]["pending"],"resolution keeps its input and waits for presentation before handing off")
	var after:=Loop.finish_exhausted_action(healed)
	check(Save.encode(after,VIEW)["ok"],"non-Leonard support transaction has a valid quiet checkpoint")
	var grown:=Loop.unit(healed,"tina")
	var allocated:=Loop.ProgressionRules.apply_allocation(grown,{"mind":1},loop["equipment_items"])
	check(allocated["combat_profile"]["mind"]==grown["combat_profile"]["mind"]+1 and allocated["mp"]==grown["mp"],"priest growth uses its job while preserving spent MP")
	var mobile:=equip(equip(priest_fixture(),"accessory1",232),"accessory2",227)
	Loop._unit(mobile,"tina")["mp"]=int(Loop.magic_options(mobile,"tina")[0]["quote"]["amount"])
	var move:=Loop.move_unit_to(Loop.choose_command(mobile,"move"),Vector2i(11,16))
	check(move["pending_move"] and Loop.command_available(move,"magic"),"current movement ring permits a moved priest heal")
	var first:=Loop.attack_target(healing(move),"companion",zero)
	first=Loop.finish_exhausted_action(first)
	check(first["extra_action"]["pending"] and first["selected_unit_id"]=="tina","support animation closes into the same priest's independent second action")
	check(Loop.magic_options(first,"tina").all(func(o):return not o["quote"]["ok"]),"remaining MP cannot pay a second full-cost heal")
	var removed:=equip(first,"accessory1",0)
	var walk:=Loop.move_unit_to(Loop.choose_command(removed,"move"),Vector2i(10,16))
	check(walk["pending_move"] and not Loop.command_available(walk,"magic"),"removal immediately restores the ordinary moved-cast restriction")
	var back:=Loop.cancel_interaction(Loop.cancel_pending_move(walk))
	check(back["extra_action"]["pending"] and not back["moved_this_action"] and back["units"]==removed["units"],"cancel restores position, not spent first-action resources")
	var encoded:=Save.encode(back,VIEW)
	check(encoded["ok"] and Save.decode(encoded["bytes"], back)["snapshot"]["loop"]==back,"second-action state and equipment roundtrip without duplication")
	var tampered:=back.duplicate(true);tampered["player_unit_id"]="companion"
	check(Save.configuration(tampered)!=Save.configuration(back),"primary actor is part of save compatibility")
	var melee:=equip(priest_fixture(),"weapon",87)
	Loop._unit(melee,"tina")["hit_bonus_accum"]=1000
	Loop._unit(melee,"enemy021_1")["hp"]=1
	var killed:=Loop.attack_target(Loop.choose_command(melee,"attack"),"enemy021_1",zero)
	check(killed["battle_outcome"]==BattleOutcome.VICTORY_ENEMIES_CLEARED and killed["rewarded_unit_ids"].count("enemy021_1")==1,"long staff reaches its source range and lethal outcome once")
	check(Loop.attack_target(killed,"enemy021_1",no_rng)==killed,"terminal priest cannot repeat the accepted kill")

func mana_items()->void:
	var packet:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://docs/evidence_packets/static_reverse/original_mana_item.json"))
	var loop:=priest_fixture();var source:=Loop.unit(loop,"tina");var item:Dictionary=loop["consumables"]["244"]
	for row in packet["cases"]:
		var target:=source.duplicate(true);var c:Dictionary=row["input"]
		target["mp"]=int(c["mp"]);target["max_mp"]=int(c["max_mp"])
		for status in ["poison","no_magic","paralysis"]:
			var bit:int={"poison":1,"no_magic":2,"paralysis":4}[status]
			if int(c["flags"])&bit:target.merge(Loop.StatusEffectRules.apply(target,status,2,16 if status=="poison" else 0)["changes"],true)
		var effect:=Loop.ItemUseRules.prepare(target,item)
		if int(row["native"]["restored_mp"])==0:
			check(not effect["ok"] and effect["reason"]=="item_has_no_effect","default planning quote refuses a full-MP use")
		else:
			check(effect["ok"] and effect["restored_mp"]==int(row["native"]["restored_mp"]) and effect["changes"]["mp"]==int(row["native"]["mp"]),"actual original mana restoration and cap agree")
			check(not effect["changes"].has("status_flags"),"mana restoration does not cure or reapply statuses")
	var full:=loop.duplicate(true)
	var drunk:=Loop.use_item(full,"244","tina",1)
	check(drunk["item_use_sequence"]==full["item_use_sequence"]+1 and drunk["last_item_use"]["restored_mp"]==0 and drunk["last_item_use"]["heal_numbers"]["mp"]==0 and Loop.unit(drunk,"tina")["inventory"].count(244)==Loop.unit(full,"tina")["inventory"].count(244)-1,"full-MP use still spends one 244 and floats 0 MP (0x409e40, 0x444aba, 0x444ac9)")
	loop= equip(loop,"accessory2",227)
	Loop._unit(loop,"tina")["mp"]=0
	var used:=Loop.use_item(loop,"244","tina",Loop.unit(loop,"tina")["inventory"].find(244))
	check(used["last_item_use"]["restored_mp"]==19 and used["last_item_use"]["restored_hp"]==0 and used["extra_action"]["pending"],"mana potion commits one use and leaves an independent second action")
	var spent:=Loop.attack_target(healing(used),"companion",zero)
	check(spent["last_attack"]["healing"]>0 and Loop.unit(spent,"tina")["mp"]==13,"restored resource immediately supports the next legitimate cast")
	spent=Loop.finish_exhausted_action(spent)
	check(Save.encode(spent,VIEW)["ok"] and not Loop.unit(spent,"tina")["inventory"].has(244),"post-item/spent save preserves exactly one consumed mana item")

func ai_and_terminal()->void:
	var loop:=priest_fixture();var actor:=Loop._unit(loop,"tina")
	actor["player_commandable"]=false;actor["battle_actor_role"]=Loop.ROLE_FRIENDLY
	loop["selected_unit_id"]="";loop["interaction"]="ai_resolving"
	var done:=Loop.step_ai_turn(loop,zero)
	check(done["scenario_ok"] and done.get("last_ai_action",{}).get("skill_id")==HEAL,"source priest AI selects its actual ally support skill: "+str(done.get("scenario_error",done.get("last_ai_action",{}))))
	for condition in ["mp","silence","paralysis"]:
		var blocked:=loop.duplicate(true);var caster:=Loop._unit(blocked,"tina")
		if condition=="mp":caster["mp"]=0
		else:caster.merge(Loop.StatusEffectRules.apply(caster,"no_magic" if condition=="silence" else "paralysis",2)["changes"],true)
		var result:=Loop.step_ai_turn(blocked,zero)
		check(result["scenario_ok"] and not result.get("last_ai_action",{}).has("skill_id"),"priest AI respects resource/status fallback: "+condition+" "+str(result.get("scenario_error","")))
		if condition=="paralysis":check(result["last_ai_action"]["kind"]=="paralysis_skip","priest paralysis consumes the shared single entry tail")
	for outcome in [BattleOutcome.DEFEAT_FALLEN,BattleOutcome.VICTORY_ESCAPE,BattleOutcome.VICTORY_ENEMIES_CLEARED]:
		var terminal:=priest_fixture()
		if outcome==BattleOutcome.DEFEAT_FALLEN:Loop._set_unit_defeated(terminal,"tina",true)
		elif outcome==BattleOutcome.VICTORY_ESCAPE:Loop._set_unit_coord(terminal,"tina",terminal["escape_zone"][0])
		else:Loop._set_unit_defeated(terminal,"enemy021_1",true)
		terminal=Loop._resolve_outcome(terminal)
		check(terminal["battle_outcome"]==outcome and Save.encode(terminal,VIEW)["ok"],"configured priest controls terminal/save boundary: "+BattleOutcome.describe(outcome))
		check(Loop.step_ai_turn(terminal,no_rng)==terminal,"no actor executes after priest terminal: "+BattleOutcome.describe(outcome))
