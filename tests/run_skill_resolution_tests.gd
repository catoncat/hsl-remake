extends "res://tests/support/TestSuite.gd"
const Resolution = preload("res://game/sim/SkillResolutionRules.gd")
const Loop = preload("res://game/battle/scene/BattlePlayLoop.gd")
const LoopCombat = preload("res://game/battle/scene/BattleLoopCombat.gd")
const BattleFixture = preload("res://tests/support/BattleFixture.gd")


func _init() -> void:
	tag = "SKILL_RESOLUTION_TESTS"


func controlled() -> Dictionary:
	var loop := BattleFixture.loop()
	Loop._unit(loop,"leonard")["live_speed"] = 100
	var next := Loop._unit(loop,"enemy023_1")
	next["live_speed"] = 99
	next["player_commandable"] = true
	next["battle_actor_role"] = Loop.ROLE_PLAYER
	loop["turn_queue"] = Loop.CoreTurnQueue.rebuild(loop["units"])
	Loop._unit(loop,"leonard")["stamina"] = 20
	return Loop.select_player_unit(loop,"leonard")


func run() -> void:
	var loop := controlled()
	var book: Dictionary = loop["skill_book"]
	var targeting: Dictionary = loop["skill_target_data"]
	var items: Dictionary = loop["equipment_items"]
	var cases := [["special:magicOTHER:magicCode01",loop["skill_book"]["skills"]["special:magicOTHER:magicCode01"]["fields"],"leonard","enemy021_1",36,54,20],
		["magic:magicAIR:magicCode01",loop["skill_book"]["skills"]["magic:magicAIR:magicCode01"]["fields"],"enemy026_1","leonard",12,26,8],
		["magic:magicFIRE:magicCode01",loop["skill_book"]["skills"]["magic:magicFIRE:magicCode01"]["fields"],"enemy026_1","leonard",18,32,8]]
	for case in cases:
		for high in [false,true]:
			for hit in [false,true]:
				var actor := Loop.unit(loop,case[2]).duplicate(true)
				var target := Loop.unit(loop,case[3]).duplicate(true)
				actor["coord"] = Vector2i(8,8)
				target["coord"] = Vector2i(8,9)
				target["hp"] = 100
				target["combat_profile"]["live_defense"] = 10
				target["combat_profile"]["resist_by_type"] = {"2":25,"3":25}
				var resource := "stamina" if case[2] == "leonard" else "mp"
				actor[resource] = case[6]+1
				var initial := [actor.duplicate(true),target.duplicate(true)]
				var draws: Array = []
				var rng := func(n):
					draws.append(n)
					if draws.size() == 1: return 0 if hit else 99
					return (0 if high else n - 1) if draws.size() == 2 else (n - 1 if high else 0)
				var result := Resolution.resolve(actor,target,case[0],case[1],book,targeting,items,actor["coord"],loop["map_size"],rng)
				check(result["ok"],"supported skill resolves through the same pure entry")
				if not result["ok"]: continue
				var receipt: Dictionary = result["receipt"]
				var raw: int = case[5] if high else case[4]
				var dealt: int = raw + int(actor["combat_profile"]["con"]) / 8 + int(actor["combat_profile"]["mind"]) / 4 + int(actor["combat_profile"]["dex"]) / 3
				if resource == "mp":
					var mind: int = int(actor["combat_profile"]["mind"]) / 2
					dealt = (int(actor["level"]) + mind + raw) * int(actor["combat_profile"]["live_magic_attack"]) / 100
					if dealt < 3: dealt += 3 * ((5 - dealt) / 3)
					dealt = dealt * 75 / 100
				if not hit: dealt = 0
				if resource == "stamina":
					check(draws == ([100,10,10,1,1] if hit else [100]), "native Qi Blade checks hit before triangular and level draws")
					if hit: check(receipt["native_damage_roll"]["sampled"] == raw, "native special triangular endpoints are preserved")
				else:
					check(draws == ([100, 8, 8] if hit else [100]), "native magic checks hit first and consumes two triangular draws only on success")
					if hit: check(receipt["native_damage_roll"]["sampled"] == raw, "native triangular lower/upper values reach the shared effect")
				check(receipt["hit"] == hit and receipt["damage"] == dealt, "selected policy result for lower/upper/miss/hit")
				check(receipt["defender_hp_after"]==100-dealt and result["caster_changes"][resource]==1,"resource and health proposals are computed together")
				check(actor==initial[0] and target==initial[1],"pure resolver mutates neither actor nor target")
				check(receipt["skill_id"] == case[0], "all registered attack abilities now carry independently checked native numeric evidence")
				# The same original character with opposite control roles must use
				# exactly the same effect policy; AI is only a choice/presentation path.
				actor["battle_actor_role"] = Loop.ROLE_ENEMY if actor["battle_actor_role"] == Loop.ROLE_PLAYER else Loop.ROLE_PLAYER
				target["battle_actor_role"] = Loop.ROLE_PLAYER if actor["battle_actor_role"] == Loop.ROLE_ENEMY else Loop.ROLE_ENEMY
				draws.clear()
				var as_player := Resolution.resolve(actor,target,case[0],case[1],book,targeting,items,actor["coord"],loop["map_size"],rng)
				check(as_player==result,"role change alone cannot select a different skill formula")
	var caster := Loop._unit(loop,"leonard")
	var target := Loop._unit(loop,"enemy021_1")
	target["coord"] = caster["coord"] + Vector2i.UP
	target["hp"] = 100
	target["combat_profile"]["live_defense"] = 10000
	var fields: Dictionary = loop["skill_book"]["skills"]["special:magicOTHER:magicCode01"]["fields"]
	for key in ["damage","hit_ratio","type","code","expend","attackpow_ratio"]:
		var invalid := loop.duplicate(true)
		own(invalid, "skill_book")["skills"]["special:magicOTHER:magicCode01"]["fields"].erase(key)
		check(not Loop.can_use_special(invalid,"leonard"),"missing required field disables actual skill command: "+key)
		invalid["interaction"] = "attack_select"
		invalid["selected_attack"] = "special"
		invalid["selected_skill_id"] = "special:magicOTHER:magicCode01"
		var rejected := Loop.attack_target(invalid,"enemy021_1",no_rng)
		check(rejected["units"]==invalid["units"] and rejected["turn_queue"]==invalid["turn_queue"] and not rejected["attacked_this_action"],"missing field cannot half-charge or half-complete: "+key)
	for pair in [["damage","54,36"],["damage","-1,2"],["damage","1.5,2"],["damage","1,2,3"],["damage","0,2147483647"],["hit_ratio","101"],["hit_ratio","-1"],["hit_ratio",NAN],["code","magicCode02"],["type","magicFIRE"]]:
		var invalid := fields.duplicate(true)
		invalid[pair[0]] = pair[1]
		check(not Resolution.resolve(caster,target,"special:magicOTHER:magicCode01",invalid,book,targeting,items,caster["coord"],loop["map_size"],no_rng)["ok"],"invalid source value rejects before RNG")
	check(Resolution.resolve(caster,target,"missing-skill",fields,book,targeting,items,caster["coord"],loop["map_size"],no_rng)["reason"]=="unknown_skill","unknown requested skill ID is refused")
	var false_owner := loop.duplicate(true)
	Loop._unit(false_owner,"leonard")["actor_id"] = "023"
	check(not Loop.can_use_special(false_owner,"leonard"),"a stamina field does not grant Leonard's special to another original actor")
	false_owner["interaction"] = "attack_select"
	false_owner["selected_attack"] = "special"
	false_owner["selected_skill_id"] = "special:magicOTHER:magicCode01"
	var rejected := Loop.attack_target(false_owner,"enemy021_1",no_rng)
	check(rejected["last_attack_reject"]["reason"]=="skill_not_owned" and rejected["units"]==false_owner["units"],"forced selection cannot bypass initial ownership")
	var wounded := target.duplicate(true)
	wounded["hp"] = 2
	wounded["combat_profile"]["live_defense"] = 0
	var lethal := Resolution.resolve(caster,wounded,"special:magicOTHER:magicCode01",fields,book,targeting,items,caster["coord"],loop["map_size"],func(_n):return 0)
	check(lethal["target_changes"]=={"hp":0,"defeated":true} and lethal["receipt"]["actual_damage"]==2,"overkill has exact applied health delta without negative HP")
	var missing_attribute := caster.duplicate(true)
	missing_attribute["combat_profile"].erase("con")
	check(Resolution.resolve(missing_attribute,target,"special:magicOTHER:magicCode01",fields,book,targeting,items,caster["coord"],loop["map_size"],no_rng)["reason"]=="invalid_special_con","missing required special attribute rejects before RNG")
	# Public player path must commit once and leave the next actor ready, even
	# when the selected target is killed and resource/experience both change.
	for moved in [false,true]:
		var ready := controlled()
		if moved:
			ready = Loop.choose_command(ready,"move")
			var from: Vector2i = Loop.unit(ready,"leonard")["coord"]
			var candidates: Array = Loop.movement_cells(ready,"leonard").filter(func(p):return p!=from)
			ready = Loop.move_unit_to(ready,candidates[0])
		var enemy := Loop._unit(ready,"enemy021_1")
		enemy["coord"] = Loop.unit(ready,"leonard")["coord"]+Vector2i.UP
		enemy["hp"] = 2
		enemy["combat_profile"]["live_defense"] = 0
		var selected := Loop.choose_special(Loop.choose_command(ready,"special"),"special:magicOTHER:magicCode01")
		var cancelled := Loop.cancel_interaction(selected)
		check(cancelled["units"]==ready["units"] and cancelled["turn_queue"]==ready["turn_queue"] and cancelled["pending_move"]==ready["pending_move"],"move/skill cancel preserves all confirmed state")
		var committed := Loop.attack_target(selected,"enemy021_1",func(_n):return 0)
		check(Loop.unit(committed,"leonard")["stamina"]==0 and Loop.unit(committed,"enemy021_1")["hp"]==0,"shared commit applies resource and effect together")
		check(committed["last_attack"]["experience"]["gained"] == committed["last_attack"]["experience_basis"]["points"] and committed["last_attack"]["experience_basis"]["contribution"] == 2, "common receipt converts actual damage then awards final experience once")
		check(Loop.attack_target(committed,"enemy021_1",no_rng)["units"]==committed["units"],"replayed target cannot repeat damage/resource/experience")
		var finished := Loop.finish_exhausted_action(committed)
		check(finished["selected_unit_id"]=="enemy023_1" and finished["turn_queue"]["index"]==1,"resolved skill hands off once after presentation")
		check(Loop.finish_exhausted_action(finished)==finished,"repeated presentation cannot advance a second actor")
	# A character with another wind skill must not gain Code01 merely because
	# it has MP and a wind declaration (025 owns a different source bit).
	var ai := BattleFixture.loop()
	var mage := Loop._unit(ai,"enemy026_1")
	mage["actor_id"] = "025"
	mage["mp"] = 30
	var enemy := Loop._unit(ai,"leonard")
	mage["coord"] = enemy["coord"] + Vector2i.RIGHT
	var initial := ai.duplicate(true)
	var unowned := Resolution.resolve(mage, enemy, "magic:magicAIR:magicCode01", Loop.skill_fields(ai, "magic:magicAIR:magicCode01"), ai["skill_book"], ai["skill_target_data"], ai["equipment_items"], mage["coord"], ai["map_size"], no_rng)
	check(not unowned["ok"] and unowned["reason"] == "skill_not_owned" and ai == initial, "another wind declaration still cannot grant Code01; actual 025 Acid Mist is covered separately")
	for missing in ["damage","hit_ratio","resistance","skill_id"]:
		var invalid := BattleFixture.loop()
		var real_mage := Loop._unit(invalid,"enemy026_1")
		var real_target := Loop._unit(invalid,"leonard")
		real_mage["coord"] = real_target["coord"]+Vector2i.RIGHT
		# Isolate the invalid target: choosing another valid nearby ally is a
		# legitimate plan, not evidence that the invalid target was accepted.
		invalid["units"] = invalid["units"].filter(func(u): return u["id"] in ["leonard","enemy026_1"])
		invalid["turn_queue"] = Loop.CoreTurnQueue.rebuild(invalid["units"])
		for index in range(invalid["turn_queue"]["slots"].size()):
			if invalid["turn_queue"]["slots"][index]["id"] == "enemy026_1": invalid["turn_queue"]["index"] = index
		invalid["interaction"] = "ai_resolving"
		if missing == "resistance":
			real_target["combat_profile"].erase("resist_by_type")
		elif missing == "skill_id":
			own(invalid, "skill_book")["skills"]["other_spell"] = invalid["skill_book"]["skills"]["magic:magicAIR:magicCode01"].duplicate(true)
			own(invalid, "skill_book")["actors"]["026"]["supported_initial_ids"].append("other_spell")
		else:
			own(invalid, "skill_book")["skills"]["magic:magicAIR:magicCode01"]["fields"].erase(missing)
		var before := invalid.duplicate(true)
		var rejected_ai := Loop.step_ai_turn(invalid,no_rng)
		check(rejected_ai["interaction"]=="scenario_error" and not rejected_ai["scenario_ok"],"invalid necessary input fails public AI skill settlement: "+missing)
		check(rejected_ai["units"]==before["units"] and rejected_ai["turn_queue"]==before["turn_queue"] and rejected_ai["last_ai_actions"]==before["last_ai_actions"],"bad data cannot silently attack physically or advance: "+missing)
		check(invalid==before,"public AI failure preserves caller input")
	# A learned source skill uses the same atomic magic transaction as an initial grant.
	var learned := BattleFixture.loop()
	var earth_id := "magic:magicEARTH:magicCode01"
	var earth_caster := Loop._unit(learned,"enemy026_1")
	earth_caster["actor_id"] = "026"
	earth_caster["growth_profile"]["job_code"] = 90
	earth_caster["level"] = 1
	earth_caster["mp"] = 20
	earth_caster["learned_skills"] = [{"policy":"source_growth_lifecycle_v1","actor_id":"026","job":90,"level":1,"attributes":{"str":10,"dex":10,"mind":10,"con":10},"trigger":"level_up","id":earth_id,"name":"地裂"}]
	var earth_target := Loop._unit(learned,"leonard")
	earth_caster["coord"] = Vector2i(8,8)
	earth_target["coord"] = Vector2i(8,9)
	earth_target["hp"] = 100
	earth_target["combat_profile"]["resist_by_type"] = {"0":25}
	var earth_fields := Loop.skill_fields(learned,earth_id)
	var learned_result := Resolution.resolve(earth_caster,earth_target,earth_id,earth_fields,learned["skill_book"],learned["skill_target_data"],learned["equipment_items"],earth_caster["coord"],learned["map_size"],func(_n): return 0)
	check(learned_result["ok"] and learned_result.get("receipt", {}).get("damage", 0) > 0 and learned_result.get("caster_changes", {}).get("mp", earth_caster["mp"]) < earth_caster["mp"],"learned Earth source skill resolves with HP damage and one MP payment")
	check(learned_result.get("receipt", {}).get("magic_key", "") == "earth" and learned_result.get("target_changes", {}).get("hp", earth_target["hp"]) < earth_target["hp"],"Earth source element reaches the target HP/resistance path")
	var blade_id := "special:magicAIR:magicCode01"
	var blade_caster := Loop._unit(learned,"enemy026_1")
	blade_caster["actor_id"] = "026"
	blade_caster["growth_profile"]["job_code"] = 80
	blade_caster["level"] = 1
	blade_caster["stamina"] = 100
	for key in ["str", "dex", "mind", "con"]: blade_caster["combat_profile"][key] = 30
	blade_caster["learned_skills"] = [{"policy":"source_growth_lifecycle_v1","actor_id":"026","job":80,"level":1,"attributes":{"str":30,"dex":25,"mind":25,"con":30},"trigger":"allocation","id":blade_id,"name":"天雷猛襲劍"}]
	var blade_target := Loop._unit(learned,"leonard")
	blade_caster["coord"] = Vector2i(8,8)
	blade_target["coord"] = Vector2i(8,9)
	blade_target["hp"] = 100
	blade_target["combat_profile"]["resist_by_type"] = {"2":0}  # magicAIR special reads the wind resistance slot
	var blade_result := Resolution.resolve_cast(blade_caster,blade_target,[blade_caster,blade_target],blade_id,Loop.skill_fields(learned,blade_id),learned["skill_book"],learned["skill_target_data"],learned["equipment_items"],blade_caster["coord"],learned["map_size"],func(_n): return 0,blade_target["coord"])
	check(blade_result.get("ok", false) and blade_result.get("receipt", {}).get("damage", 0) > 0 and blade_result.get("caster_changes", {}).get("stamina", blade_caster["stamina"]) < blade_caster["stamina"],"learned source special resolves its area target with one ST payment")
	check(blade_result.get("targets", []).size() == 1 and blade_result.get("receipt", {}).get("cast_center", Vector2i(-1,-1)) == blade_target["coord"],"source special effect range is honored by the shared cast transaction")
	var mind_id := "magic:magicMIND:magicCode01"
	var mind_caster := Loop._unit(learned,"enemy026_1")
	mind_caster["actor_id"] = "026"
	mind_caster["growth_profile"]["job_code"] = 98
	mind_caster["level"] = 5
	mind_caster["mp"] = 30
	mind_caster["learned_skills"] = [{"policy":"source_growth_lifecycle_v1","actor_id":"026","job":98,"level":5,"attributes":{"str":1,"dex":1,"mind":1,"con":1},"trigger":"level_up","id":mind_id,"name":"咒殺"}]
	var mind_target := Loop._unit(learned,"leonard")
	mind_caster["coord"] = Vector2i(8,8)
	mind_target["coord"] = Vector2i(8,9)
	mind_target["hp"] = 100
	mind_target["combat_profile"]["resist_by_type"] = {"4":25}
	var mind_result := Resolution.resolve(mind_caster,mind_target,mind_id,Loop.skill_fields(learned,mind_id),learned["skill_book"],learned["skill_target_data"],learned["equipment_items"],mind_caster["coord"],learned["map_size"],func(_n): return 0)
	check(mind_result.get("ok", false) and mind_result.get("receipt", {}).get("damage", 0) > 0 and mind_result.get("caster_changes", {}).get("mp", mind_caster["mp"]) < mind_caster["mp"],"learned Mind source magic resolves through native damage with MP payment")
	check(mind_result.get("receipt", {}).get("magic_key", "") == "mind" and mind_result.get("target_changes", {}).get("hp", mind_target["hp"]) < mind_target["hp"],"Mind source element reaches the target resistance path")
	var water_id := "magic:magicWATER:magicCode02"
	var water_caster := Loop._unit(learned,"enemy026_1")
	water_caster["actor_id"] = "026"
	water_caster["growth_profile"]["job_code"] = 90
	water_caster["level"] = 10
	water_caster["mp"] = 30
	water_caster["learned_skills"] = [{"policy":"source_growth_lifecycle_v1","actor_id":"026","job":90,"level":10,"attributes":{"str":1,"dex":1,"mind":1,"con":1},"trigger":"level_up","id":water_id,"name":"水龍波"}]
	var water_target := Loop._unit(learned,"leonard")
	water_caster["coord"] = Vector2i(8,8)
	water_target["coord"] = Vector2i(8,9)
	water_target["hp"] = 100
	water_target["combat_profile"]["resist_by_type"] = {"1":25}
	var water_result := Resolution.resolve(water_caster,water_target,water_id,Loop.skill_fields(learned,water_id),learned["skill_book"],learned["skill_target_data"],learned["equipment_items"],water_caster["coord"],learned["map_size"],func(_n): return 0)
	check(water_result.get("ok", false) and water_result.get("receipt", {}).get("damage", 0) > 0 and water_result.get("caster_changes", {}).get("mp", water_caster["mp"]) < water_caster["mp"],"learned Water source magic resolves through native damage with MP payment")
	check(water_result.get("receipt", {}).get("magic_key", "") == "water" and water_result.get("target_changes", {}).get("hp", water_target["hp"]) < water_target["hp"],"Water source element reaches the target resistance path")
	var fire_id := "magic:magicFIRE:magicCode02"
	var fire_caster := Loop._unit(learned,"enemy026_1")
	fire_caster["actor_id"] = "026"
	fire_caster["growth_profile"]["job_code"] = 90
	fire_caster["level"] = 12
	fire_caster["mp"] = 30
	fire_caster["learned_skills"] = [{"policy":"source_growth_lifecycle_v1","actor_id":"026","job":90,"level":12,"attributes":{"str":1,"dex":1,"mind":1,"con":1},"trigger":"level_up","id":fire_id,"name":"熾焰鳥"}]
	var fire_target := Loop._unit(learned,"leonard")
	fire_caster["coord"] = Vector2i(8,8)
	fire_target["coord"] = Vector2i(8,9)
	fire_target["hp"] = 100
	fire_target["combat_profile"]["resist_by_type"] = {"3":25}
	var fire_result := Resolution.resolve(fire_caster,fire_target,fire_id,Loop.skill_fields(learned,fire_id),learned["skill_book"],learned["skill_target_data"],learned["equipment_items"],fire_caster["coord"],learned["map_size"],func(_n): return 0)
	check(fire_result.get("ok", false) and fire_result.get("receipt", {}).get("damage", 0) > 0 and fire_result.get("caster_changes", {}).get("mp", fire_caster["mp"]) < fire_caster["mp"],"learned Fire source magic resolves through native damage with MP payment")
	check(fire_result.get("receipt", {}).get("magic_key", "") == "fire" and fire_result.get("target_changes", {}).get("hp", fire_target["hp"]) < fire_target["hp"],"Fire source element reaches the target resistance path")
	var wind_id := "magic:magicAIR:magicCode02"
	var wind_caster := Loop._unit(learned,"enemy026_1")
	wind_caster["actor_id"] = "026"
	wind_caster["growth_profile"]["job_code"] = 92
	wind_caster["level"] = 12
	wind_caster["mp"] = 30
	wind_caster["learned_skills"] = [{"policy":"source_growth_lifecycle_v1","actor_id":"026","job":92,"level":12,"attributes":{"str":1,"dex":1,"mind":1,"con":1},"trigger":"level_up","id":wind_id,"name":"空鳴破"}]
	var wind_target := Loop._unit(learned,"leonard")
	wind_caster["coord"] = Vector2i(8,8)
	wind_target["coord"] = Vector2i(8,9)
	wind_target["hp"] = 100
	wind_target["combat_profile"]["resist_by_type"] = {"2":25}
	var wind_result := Resolution.resolve(wind_caster,wind_target,wind_id,Loop.skill_fields(learned,wind_id),learned["skill_book"],learned["skill_target_data"],learned["equipment_items"],wind_caster["coord"],learned["map_size"],func(_n): return 0)
	check(wind_result.get("ok", false) and wind_result.get("receipt", {}).get("damage", 0) > 0 and wind_result.get("caster_changes", {}).get("mp", wind_caster["mp"]) < wind_caster["mp"],"learned Wind source magic resolves through native damage with MP payment")
	check(wind_result.get("receipt", {}).get("magic_key", "") == "wind" and wind_result.get("target_changes", {}).get("hp", wind_target["hp"]) < wind_target["hp"],"Wind source element reaches the target resistance path")
	var earth_two_id := "magic:magicEARTH:magicCode02"
	var earth_two_caster := Loop._unit(learned,"enemy026_1")
	earth_two_caster["actor_id"] = "026"
	earth_two_caster["growth_profile"]["job_code"] = 98
	earth_two_caster["level"] = 12
	earth_two_caster["mp"] = 30
	earth_two_caster["learned_skills"] = [{"policy":"source_growth_lifecycle_v1","actor_id":"026","job":98,"level":12,"attributes":{"str":1,"dex":1,"mind":1,"con":1},"trigger":"level_up","id":earth_two_id,"name":"地龍震"}]
	var earth_two_target := Loop._unit(learned,"leonard")
	earth_two_caster["coord"] = Vector2i(8,8)
	earth_two_target["coord"] = Vector2i(8,9)
	earth_two_target["hp"] = 100
	earth_two_target["combat_profile"]["resist_by_type"] = {"0":25}
	var earth_two_result := Resolution.resolve(earth_two_caster,earth_two_target,earth_two_id,Loop.skill_fields(learned,earth_two_id),learned["skill_book"],learned["skill_target_data"],learned["equipment_items"],earth_two_caster["coord"],learned["map_size"],func(_n): return 0)
	check(earth_two_result.get("ok", false) and earth_two_result.get("receipt", {}).get("damage", 0) > 0 and earth_two_result.get("caster_changes", {}).get("mp", earth_two_caster["mp"]) < earth_two_caster["mp"],"learned Earth level-two magic resolves through native damage with MP payment")
	check(earth_two_result.get("receipt", {}).get("magic_key", "") == "earth" and earth_two_result.get("target_changes", {}).get("hp", earth_two_target["hp"]) < earth_two_target["hp"],"Earth level-two source element reaches the target resistance path")
	var bind_id := "magic:magicMIND:magicCode03"
	var bind_caster := Loop._unit(learned,"enemy026_1")
	bind_caster["actor_id"] = "026"
	bind_caster["growth_profile"]["job_code"] = 85
	bind_caster["level"] = 25
	bind_caster["mp"] = 50
	bind_caster["learned_skills"] = [{"policy":"source_growth_lifecycle_v1","actor_id":"026","job":85,"level":25,"attributes":{"str":1,"dex":1,"mind":1,"con":1},"trigger":"level_up","id":bind_id,"name":"咒靈縛剎"}]
	var bind_target := Loop._unit(learned,"leonard")
	bind_caster["coord"] = Vector2i(8,8)
	bind_target["coord"] = Vector2i(8,9)
	bind_target["hp"] = 100
	bind_target["combat_profile"]["resist_by_type"] = {"4":0}
	var bind_result := Resolution.resolve(bind_caster,bind_target,bind_id,Loop.skill_fields(learned,bind_id),learned["skill_book"],learned["skill_target_data"],learned["equipment_items"],bind_caster["coord"],learned["map_size"],func(_n): return 0)
	var bind_effects: Array = bind_result.get("receipt", {}).get("status_effects", [])
	check(bind_result.get("ok", false) and bind_result.get("receipt", {}).get("damage", 0) > 0 and bind_result.get("caster_changes", {}).get("mp", bind_caster["mp"]) < bind_caster["mp"],"learned paralysis source magic resolves damage and MP payment")
	check(bind_effects.any(func(effect): return effect.get("status", "") == "paralysis" and effect.get("applied", false)) and bind_result.get("target_changes", {}).get("hp", bind_target["hp"]) < bind_target["hp"],"attack-plus-paralysis source function applies status after damage")
	# Lane A: 魂體衰竭 (magic Weaken) introduces the 衰弱 status: flag 8, packed word, refresh.
	var weaken_id := "magic:magicMIND:magicCode04"
	var weaken_caster := Loop._unit(learned,"enemy026_1")
	weaken_caster["actor_id"] = "026"
	weaken_caster["growth_profile"]["job_code"] = 98
	weaken_caster["level"] = 19
	weaken_caster["mp"] = 30
	weaken_caster["learned_skills"] = [{"policy":"source_growth_lifecycle_v1","actor_id":"026","job":98,"level":19,"attributes":{"str":1,"dex":1,"mind":1,"con":1},"trigger":"level_up","id":weaken_id,"name":"魂體衰竭"}]
	var weaken_target := Loop._unit(learned,"leonard")
	weaken_caster["coord"] = Vector2i(8,8)
	weaken_target["coord"] = Vector2i(8,9)
	weaken_target["hp"] = 100
	weaken_target["combat_profile"]["resist_by_type"] = {"4":0}
	var weaken_before := weaken_target.duplicate(true)
	var weaken_result := Resolution.resolve(weaken_caster,weaken_target,weaken_id,Loop.skill_fields(learned,weaken_id),learned["skill_book"],learned["skill_target_data"],learned["equipment_items"],weaken_caster["coord"],learned["map_size"],func(_n): return 0)
	var weaken_changes: Dictionary = weaken_result.get("target_changes", {})
	var weaken_word := int(weaken_changes.get("status_counters", {}).get("weaken", 0))
	check(weaken_result.get("ok", false) and weaken_result.get("receipt", {}).get("damage", -1) == 0 and weaken_result.get("caster_changes", {}).get("mp", 99) == 18,"learned 魂體衰竭 resolves without HP damage for one 12MP payment")
	check((int(weaken_changes.get("status_flags", 0)) & 8) != 0 and (weaken_word & 0xffff) == 2 and (weaken_word >> 16) in range(2, 16),"Weaken sets flag 8 with a 2-turn word and a 2..15 folded power")
	check(weaken_changes.get("combat_profile", {}).get("live_attack_damage", 999) <= weaken_before["combat_profile"]["live_attack_damage"] and weaken_changes.get("max_hp", 9999) <= weaken_before["max_hp"] and weaken_changes.has("live_speed"),"Weaken refreshes derived stats from the reduced attributes (0x448840)")
	check(weaken_target == weaken_before,"weaken resolver mutates neither caller unit")
	var weakened_unit := weaken_target.duplicate(true)
	weakened_unit.merge(weaken_changes, true)
	check(Resolution.Status.input_error(weakened_unit) == "" and Resolution.Status.weakened(weakened_unit),"weakened unit stays a coherent status state")
	var weaken_tick := Resolution.Status.after_action(weakened_unit)
	check(weaken_tick["ok"] and (int(weaken_tick["changes"]["status_counters"]["weaken"]) & 0xffff) == 1 and not weaken_tick["expired"].has("weaken"),"first action end decrements the weaken duration only")
	weakened_unit.merge(weaken_tick["changes"], true)
	weaken_tick = Resolution.Status.after_action(weakened_unit)
	check(weaken_tick["ok"] and weaken_tick["expired"].has("weaken") and (int(weaken_tick["changes"]["status_flags"]) & 8) == 0 and not weaken_tick["changes"]["status_counters"].has("weaken"),"weaken expires after its last counted action (0x40b910) and clears flag 8")
	var cured := Resolution.Status.cure_weaken(weakened_unit)
	check((int(cured["status_flags"]) & 8) == 0 and not cured["status_counters"].has("weaken"),"cure_weaken clears the whole word and flag 8")
	# Formulas read the live +0x4c..+0x58 attributes (base minus the active weaken power), not the base words.
	var weak_power := int(weakened_unit["status_counters"]["weaken"]) >> 16
	var weak_live := Resolution.Combat.combat_profile_from_unit(weakened_unit)
	var weak_base: Dictionary = weakened_unit["combat_profile"]
	check(weak_power >= 2 and weak_live["str"] == maxi(1, int(weak_base["str"]) - weak_power) and weak_live["dex"] == maxi(1, int(weak_base["dex"]) - weak_power) and Resolution.Combat.combat_profile_from_unit(weaken_before)["dex"] == int(weak_base["dex"]),"0x409a60／0x409be0 dex／str deltas read the weakened live attributes (0x448840 prologue)")
	var weak_special := Resolution.Special.prepare(weakened_unit, weaken_caster, Loop.skill_fields(learned, "special:magicOTHER:magicCode01"), learned["skill_book"], learned["equipment_items"])
	check(weak_special["ok"] and weak_special["input"]["dex"] == maxi(1, int(weak_base["dex"]) - weak_power) and weak_special["input"]["mind"] == maxi(1, int(weak_base["mind"]) - weak_power) and weak_special["input"]["con"] == maxi(1, int(weak_base["con"]) - weak_power),"0x40a7b0 channel1 dex/3＋mind/4＋con/8 read the weakened live attributes")
	var weak_status := Resolution.StatusApplication.prepare(weakened_unit, weaken_caster, Loop.skill_fields(learned, "magic:magicAIR:magicCode01"), learned["skill_book"], learned["skill_target_data"], learned["equipment_items"])
	check(weak_status["ok"] and weak_status["roll_input"]["mind"] == maxi(1, int(weak_base["mind"]) - weak_power) and weak_status["roll_input"]["magic_attack"] == int(weak_base["live_magic_attack"]),"0x40a7b0 channel0 mind term reads the weakened live attribute; magic attack stays the refreshed derived value")
	var immune_target := weaken_target.duplicate(true)
	immune_target["actor_id"] = "045"
	var immune_book: Dictionary = learned["skill_book"].duplicate(true)
	immune_book["actors"]["045"]["status_capability_flags"] = int(immune_book["actors"]["045"]["status_capability_flags"]) | 0x2000
	var immune_result := Resolution.resolve(weaken_caster,immune_target,weaken_id,Loop.skill_fields(learned,weaken_id),immune_book,learned["skill_target_data"],learned["equipment_items"],weaken_caster["coord"],learned["map_size"],func(_n): return 0)
	check(immune_result.get("ok", false) and immune_result["receipt"]["status_effects"][0]["reason"] == "immune" and (int(immune_result["target_changes"]["status_flags"]) & 8) == 0,"PLAYERS no_weaken (0x2000 -> 0x2000000) makes an equipped target immune")
	# 弱體箭: special channel Attack+Weaken shares the status applicator with channel1 rolls.
	var arrow_id := "special:magicMIND:magicCode04"
	var arrow_caster := Loop._unit(learned,"enemy026_1")
	arrow_caster["actor_id"] = "026"
	arrow_caster["growth_profile"]["job_code"] = 83
	arrow_caster["level"] = 10
	arrow_caster["stamina"] = 100
	for key in ["str", "dex", "mind", "con"]: arrow_caster["combat_profile"][key] = 60
	# Tier-2 job 83 records cannot exist yet; grant the source bit through the book copy instead.
	arrow_caster["learned_skills"] = []
	var arrow_book: Dictionary = learned["skill_book"].duplicate(true)
	arrow_book["actors"]["026"]["supported_initial_ids"].append(arrow_id)
	var arrow_target := Loop._unit(learned,"leonard")
	arrow_caster["coord"] = Vector2i(8,8)
	arrow_target["coord"] = Vector2i(8,10)
	arrow_target["hp"] = 1000
	arrow_target["combat_profile"]["resist_by_type"] = {"4":0}
	var arrow_result := Resolution.resolve_cast(arrow_caster,arrow_target,[arrow_caster,arrow_target],arrow_id,Loop.skill_fields(learned,arrow_id),arrow_book,learned["skill_target_data"],learned["equipment_items"],arrow_caster["coord"],learned["map_size"],func(_n): return 0,arrow_target["coord"])
	var arrow_effects: Array = arrow_result.get("receipt", {}).get("status_effects", [])
	var arrow_word := int(arrow_result.get("target_changes", {}).get("status_counters", {}).get("weaken", 0))
	check(arrow_result.get("ok", false) and arrow_result.get("receipt", {}).get("damage", 0) > 0 and arrow_result.get("caster_changes", {}).get("stamina", 100) == 80,"learned 弱體箭 deals special damage for one 20ST payment")
	check(arrow_effects.size() == 1 and arrow_effects[0]["status"] == "weaken" and arrow_effects[0]["applied"] and (arrow_word >> 16) in range(2, 16) and arrow_result["receipt"].get("special_key") == "special_status","Attack+Weaken special applies the folded 30% weaken magnitude after damage")
	# 影纏: pure paralysis through the special channel.
	var shadow_id := "special:magicOTHER:magicCode09"
	var shadow_caster := arrow_caster.duplicate(true)
	shadow_caster["growth_profile"]["job_code"] = 83
	shadow_caster["learned_skills"] = [{"policy":"source_growth_lifecycle_v1","actor_id":"026","job":83,"level":1,"attributes":{"str":28,"dex":24,"mind":12,"con":25},"trigger":"allocation","id":shadow_id,"name":"影纏"}]
	var shadow_target := Loop._unit(learned,"leonard")
	shadow_target["coord"] = Vector2i(8,9)
	shadow_target["hp"] = 100
	var shadow_result := Resolution.resolve(shadow_caster,shadow_target,shadow_id,Loop.skill_fields(learned,shadow_id),learned["skill_book"],learned["skill_target_data"],learned["equipment_items"],shadow_caster["coord"],learned["map_size"],func(_n): return 0)
	var shadow_effects: Array = shadow_result.get("receipt", {}).get("status_effects", [])
	check(shadow_result.get("ok", false) and shadow_result.get("receipt", {}).get("damage", -1) == 0 and shadow_result.get("caster_changes", {}).get("stamina", 100) == 60,"learned 影纏 costs 40ST and deals no HP damage")
	check(shadow_effects.size() == 1 and shadow_effects[0]["status"] == "paralysis" and shadow_effects[0]["applied"] and (int(shadow_result["target_changes"]["status_flags"]) & 4) != 0,"special Paralysis reuses the shared paralysis applicator")
	# Lane A support family: 聖靈祝福 cures four states in one cast (0x40aa80 cure bits).
	var bless_id := "magic:magicMIND:magicCode07"
	var bless_caster := Loop._unit(learned,"enemy026_1")
	bless_caster["actor_id"] = "026"
	bless_caster["growth_profile"]["job_code"] = 85
	bless_caster["level"] = 39
	bless_caster["mp"] = 50
	bless_caster["learned_skills"] = [{"policy":"source_growth_lifecycle_v1","actor_id":"026","job":85,"level":39,"attributes":{"str":1,"dex":1,"mind":1,"con":1},"trigger":"level_up","id":bless_id,"name":"聖靈祝福"}]
	var bless_target := Loop._unit(learned,"enemy021_1")
	bless_caster["coord"] = Vector2i(8,8)
	bless_target["coord"] = Vector2i(8,9)
	bless_target["status_flags"] = 1 | 4 | 8
	bless_target["status_counters"]["poison"] = (10 << 16) | 2
	bless_target["status_counters"]["paralysis"] = 2
	bless_target["status_counters"]["weaken"] = (5 << 16) | 2
	bless_target = Resolution.StatMagic.Progression.refresh_growth_stats(bless_target, learned["equipment_items"])
	Loop._unit(learned,"enemy021_1").merge(bless_target, true)
	var bless_before := bless_target.duplicate(true)
	var bless_result := Resolution.resolve(bless_caster,bless_target,bless_id,Loop.skill_fields(learned,bless_id),learned["skill_book"],learned["skill_target_data"],learned["equipment_items"],bless_caster["coord"],learned["map_size"],no_rng)
	var bless_changes: Dictionary = bless_result.get("target_changes", {})
	var removed: Array = bless_result.get("receipt", {}).get("support_effects", []).filter(func(effect): return effect["removed"]).map(func(effect): return effect["status"])
	check(bless_result.get("ok", false) and bless_result.get("caster_changes", {}).get("mp", 99) == 30 and bless_result["receipt"].get("healing", -1) == 0,"learned 聖靈祝福 costs 20MP, heals nothing and consumes no RNG")
	check(removed == ["weaken", "paralysis", "poison"] and int(bless_changes.get("status_flags", -1)) == 0 and not bless_changes.get("status_counters", {}).has("weaken"),"the four cure bits clear every present state in native order and leave absent ones reported")
	check(bless_changes.get("combat_profile", {}).get("live_attack_damage", -1) >= bless_before["combat_profile"]["live_attack_damage"] and bless_changes.has("max_hp") and not bless_changes.has("mp"),"curing weaken refreshes derived stats without touching vitals")
	check(bless_result["receipt"]["native_contribution"] == (3 + 3 + 3) * 12,"each removed state contributes (turns+1)*12")
	var healthy := bless_target.duplicate(true)
	healthy.merge(bless_changes, true)
	check(Resolution.resolve(bless_caster,healthy,bless_id,Loop.skill_fields(learned,bless_id),learned["skill_book"],learned["skill_target_data"],learned["equipment_items"],bless_caster["coord"],learned["map_size"],no_rng).get("reason", "") == "skill_has_no_effect","a target without any of the four states is refused before payment")
	# 萬息集氣法: special channel Heal, self-centered area, one ST payment for every ally inside.
	var gather_id := "special:magicWATER:magicCode02"
	var gather_caster := Loop._unit(learned,"enemy026_1")
	gather_caster["growth_profile"]["job_code"] = 85
	gather_caster["level"] = 10
	gather_caster["stamina"] = 100
	for key in ["str", "dex", "mind", "con"]: gather_caster["combat_profile"][key] = 30
	gather_caster["learned_skills"] = [{"policy":"source_growth_lifecycle_v1","actor_id":"026","job":85,"level":1,"attributes":{"str":22,"dex":22,"mind":26,"con":16},"trigger":"allocation","id":gather_id,"name":"萬息集氣法"}]
	gather_caster["hp"] = int(gather_caster["max_hp"]) - 30
	var gather_ally := Loop._unit(learned,"enemy021_1")
	gather_ally.merge(healthy, true)
	gather_ally["coord"] = Vector2i(9,8)
	gather_ally["hp"] = int(gather_ally["max_hp"]) - 10
	var gather_result := Resolution.resolve_cast(gather_caster,gather_caster,[gather_caster,gather_ally,Loop._unit(learned,"leonard")],gather_id,Loop.skill_fields(learned,gather_id),learned["skill_book"],learned["skill_target_data"],learned["equipment_items"],gather_caster["coord"],learned["map_size"],func(_n): return 0,gather_caster["coord"])
	var gathered: Array = gather_result.get("targets", [])
	check(gather_result.get("ok", false) and gather_result.get("caster_changes", {}).get("stamina", 100) == 60 and not gather_result["caster_changes"].has("hp"),"learned 萬息集氣法 pays 40ST once and keeps the caster's HP proposal with the targets")
	check(gathered.size() == 2 and gathered.all(func(row): return int(row["changes"]["hp"]) > 0) and gather_result["receipt"].get("special_key") == "special_support" and int(gather_result["receipt"]["healing"]) == 30,"self-centered special heal reaches the caster and the adjacent ally, capped at missing HP")
	# 萬息降靈法: HealMP restores MP up to the maximum and refuses a full target.
	var mana_id := "special:magicOTHER:magicCode08"
	var mana_caster := gather_caster.duplicate(true)
	mana_caster["hp"] = mana_caster["max_hp"]
	mana_caster["mp"] = int(mana_caster["max_mp"]) - 10
	mana_caster["learned_skills"] = []
	var mana_book: Dictionary = learned["skill_book"].duplicate(true)
	mana_book["actors"]["026"]["supported_initial_ids"].append(mana_id)
	var mana_result := Resolution.resolve(mana_caster,mana_caster,mana_id,Loop.skill_fields(learned,mana_id),mana_book,learned["skill_target_data"],learned["equipment_items"],mana_caster["coord"],learned["map_size"],func(_n): return 0)
	check(mana_result.get("ok", false) and int(mana_result.get("receipt", {}).get("restored_mp", 0)) == 10 and int(mana_result["target_changes"]["mp"]) == int(mana_caster["max_mp"]) and mana_result["caster_changes"].get("stamina", 100) == 60,"learned 萬息降靈法 restores missing MP for 40ST")
	var full_mana := mana_caster.duplicate(true)
	full_mana["mp"] = full_mana["max_mp"]
	check(Resolution.resolve(mana_caster,full_mana,mana_id,Loop.skill_fields(learned,mana_id),mana_book,learned["skill_target_data"],learned["equipment_items"],mana_caster["coord"],learned["map_size"],no_rng).get("reason", "") == "skill_has_no_effect","HealMP on a full-MP target is refused before RNG")
	# 萬息臨界法 (Heal+HealMP): 0x40b49e converts rand(level)+1 at once, 0x40b866 converts healing/2 at the tail.
	var critical_id := "special:magicWATER:magicCode04"
	var critical_caster := mana_caster.duplicate(true)
	critical_caster["hp"] = int(critical_caster["max_hp"]) - 30
	var critical_book: Dictionary = learned["skill_book"].duplicate(true)
	critical_book["actors"]["026"]["supported_initial_ids"].append(critical_id)
	var critical_result := Resolution.resolve_cast(critical_caster,critical_caster,[critical_caster,Loop._unit(learned,"leonard")],critical_id,Loop.skill_fields(learned,critical_id),critical_book,learned["skill_target_data"],learned["equipment_items"],critical_caster["coord"],learned["map_size"],func(_n): return 0,critical_caster["coord"])
	var critical_basis: Dictionary = critical_result.get("receipt", {}).get("experience_basis", {})
	var critical_immediate: Array = critical_basis.get("immediate_experience", [])
	check(critical_result.get("ok", false) and int(critical_result["receipt"]["healing"]) == 30 and int(critical_result["receipt"]["restored_mp"]) == 10,"learned 萬息臨界法 heals HP and MP in one cast")
	check(critical_result["receipt"].get("immediate_contributions") == [1] and int(critical_basis.get("contribution", -1)) == 15 and critical_immediate.size() == 1 and int(critical_immediate[0]["contribution"]) == 1 and int(critical_basis["points"]) == int(critical_basis["tail_points"]) + int(critical_immediate[0]["points"]) and int(critical_immediate[0]["points"]) > 0,"HealMP converts rand(level)+1 through 0x40a5d0 at once and the heal contribution again at the tail (0x40b49e / 0x40b866)")
	# Lane A stat family: 千羽風靈壁 (special DefUp on self) and 精神統一 (DefUp+AttUp in native order).
	var wall_id := "special:magicAIR:magicCode05"
	var wall_caster := Loop._unit(learned,"enemy026_1")
	wall_caster["actor_id"] = "026"
	wall_caster["growth_profile"]["job_code"] = 92
	wall_caster["level"] = 10
	wall_caster["stamina"] = 100
	wall_caster["status_flags"] = 0
	wall_caster["status_counters"] = {"poison": 0, "paralysis": 0, "no_magic": 0}
	for key in ["str", "dex", "mind", "con"]: wall_caster["combat_profile"][key] = 30
	wall_caster["learned_skills"] = [{"policy":"source_growth_lifecycle_v1","actor_id":"026","job":92,"level":1,"attributes":{"str":29,"dex":28,"mind":22,"con":24},"trigger":"allocation","id":wall_id,"name":"千羽風靈壁"}]
	wall_caster["coord"] = Vector2i(8,8)
	var refreshed_wall := Resolution.StatMagic.Progression.refresh_growth_stats(wall_caster, learned["equipment_items"])
	wall_caster.merge(refreshed_wall, true)
	var wall_before := wall_caster.duplicate(true)
	var wall_result := Resolution.resolve_cast(wall_caster,wall_caster,[wall_caster,Loop._unit(learned,"leonard")],wall_id,Loop.skill_fields(learned,wall_id),learned["skill_book"],learned["skill_target_data"],learned["equipment_items"],wall_caster["coord"],learned["map_size"],func(_n): return 0)
	var wall_effects: Array = wall_result.get("receipt", {}).get("stat_effects", [])
	check(wall_result.get("ok", false) and wall_result.get("caster_changes", {}).get("stamina", 100) == 60 and not wall_result["caster_changes"].has("mp"),"learned 千羽風靈壁 targets the caster for one 40ST payment")
	check(wall_effects.size() == 1 and wall_effects[0]["kind"] == "defense_up" and int(wall_result["target_changes"]["combat_profile"]["live_defense"]) > int(wall_before["combat_profile"]["live_defense"]) and wall_result["receipt"].get("special_key") == "special_stat","special DefUp raises live defense through the shared enhancement word")
	check(wall_result["receipt"]["native_stat_rolls"].size() == 2 and wall_result["receipt"]["sampled_durations"] == [2] and Resolution.StatMagic.receipt_error(wall_result["receipt"], learned["skill_book"]) == "","special buff receipts replay through the checkpoint validator")
	var focus_id := "special:magicMIND:magicCode01"
	var focus_caster := wall_before.duplicate(true)
	focus_caster["growth_profile"]["job_code"] = 80
	focus_caster["learned_skills"] = []
	focus_caster = Resolution.StatMagic.Progression.refresh_growth_stats(focus_caster, learned["equipment_items"])
	var focus_book: Dictionary = learned["skill_book"].duplicate(true)
	focus_book["actors"]["026"]["supported_initial_ids"].append(focus_id)
	var focus_result := Resolution.resolve_cast(focus_caster,focus_caster,[focus_caster],focus_id,Loop.skill_fields(learned,focus_id),focus_book,learned["skill_target_data"],learned["equipment_items"],focus_caster["coord"],learned["map_size"],func(_n): return 0)
	var focus_effects: Array = focus_result.get("receipt", {}).get("stat_effects", [])
	check(focus_result.get("ok", false) and focus_effects.map(func(effect): return effect["kind"]) == ["defense_up", "attack_up"] and focus_result["receipt"]["native_stat_rolls"].size() == 4 and focus_result["receipt"]["sampled_durations"].size() == 2,"精神統一 applies DefUp then AttUp with their own rolls and durations")
	check(int(focus_result["target_changes"]["combat_profile"]["live_attack_damage"]) > int(focus_caster["combat_profile"]["live_attack_damage"]) and int(focus_result["target_changes"]["combat_profile"]["live_defense"]) > int(focus_caster["combat_profile"]["live_defense"]) and (int(focus_result["target_changes"]["status_flags"]) & 0x30) == 0x30,"both enhancement flags and derived values land in one refresh")
	check(Resolution.StatMagic.receipt_error(focus_result["receipt"], focus_book) == "","two-kind special buff receipts replay through the checkpoint validator")
	# Lane A utility family: 吸血劍 drains the applied damage back to the caster.
	var drain_id := "special:magicOTHER:magicCode24"
	var drain_caster := Loop._unit(learned,"enemy026_1")
	drain_caster["actor_id"] = "026"
	drain_caster["growth_profile"]["job_code"] = 98
	drain_caster["level"] = 10
	drain_caster["stamina"] = 100
	drain_caster["status_flags"] = 0
	drain_caster["status_counters"] = {"poison": 0, "paralysis": 0, "no_magic": 0}
	for key in ["str", "dex", "mind", "con"]: drain_caster["combat_profile"][key] = 40
	drain_caster["learned_skills"] = [{"policy":"source_growth_lifecycle_v1","actor_id":"026","job":98,"level":1,"attributes":{"str":30,"dex":30,"mind":34,"con":32},"trigger":"allocation","id":drain_id,"name":"吸血劍"}]
	drain_caster.merge(Resolution.StatMagic.Progression.refresh_growth_stats(drain_caster, learned["equipment_items"]), true)
	drain_caster["hp"] = int(drain_caster["max_hp"]) - 20
	var drain_target := Loop._unit(learned,"leonard")
	drain_caster["coord"] = Vector2i(8,8)
	drain_target["coord"] = Vector2i(8,10)
	drain_target["hp"] = 1000
	var drain_result := Resolution.resolve_cast(drain_caster,drain_target,[drain_caster,drain_target],drain_id,Loop.skill_fields(learned,drain_id),learned["skill_book"],learned["skill_target_data"],learned["equipment_items"],drain_caster["coord"],learned["map_size"],func(_n): return 0,drain_target["coord"])
	var drained := int(drain_result.get("receipt", {}).get("damage", 0))
	check(drain_result.get("ok", false) and drained > 0 and drain_result["caster_changes"].get("stamina", 100) == 60,"learned 吸血劍 deals channel1 damage for one 40ST payment")
	check(int(drain_result["caster_changes"].get("hp", 0)) == mini(int(drain_caster["max_hp"]), int(drain_caster["hp"]) + drained) and int(drain_result["receipt"]["stolen_hp"]) == mini(20, drained) and drain_result["receipt"]["native_contribution"] == drained,"StealHP returns the applied damage to the caster, capped at max HP, and keeps the damage as the tail contribution")
	var drain_basis: Dictionary = drain_result.get("receipt", {}).get("experience_basis", {})
	var drain_immediate: Array = drain_basis.get("immediate_experience", [])
	check(drain_result["receipt"].get("immediate_contributions") == [drained * 20 / 100] and drain_immediate.size() == 1 and int(drain_immediate[0]["contribution"]) == drained * 20 / 100 and int(drain_basis.get("contribution", -1)) == drained and int(drain_basis["points"]) == int(drain_basis["tail_points"]) + int(drain_immediate[0]["points"]),"StealHP converts damage*20/100 at once (0x40b7fe) and the damage again at the tail (0x40b866)")
	# 獅子吼 cancels the target's pending slot through the public player path; 天鳴覺醒 re-enables an acted ally.
	var roar_id := "special:magicOTHER:magicCode20"
	var roar := controlled()
	var roar_actor: String = Loop.unit(roar,"leonard")["actor_id"]
	own(roar, "skill_book")["actors"][roar_actor]["supported_initial_ids"].append(roar_id)
	var roar_target := Loop._unit(roar,"enemy021_1")
	roar_target["coord"] = Loop.unit(roar,"leonard")["coord"] + Vector2i(0,2)
	roar = Loop.choose_command(roar,"special")
	roar = Loop.choose_special(roar, roar_id)
	check(roar["interaction"] == "attack_select" and roar["selected_skill_id"] == roar_id,"a second owned special is selectable from the special list")
	var pending_before: int = roar["turn_queue"]["slots"].filter(func(slot): return slot["id"] == "enemy021_1" and slot["enabled"]).size()
	var roared := Loop.attack_target(roar,"enemy021_1",func(_n): return 0)
	var roar_effects: Array = roared.get("last_attack", {}).get("turn_effects", [])
	check(pending_before == 1 and roar_effects.size() == 1 and roar_effects[0]["kind"] == "cancel_pending" and roar_effects[0]["applied"] and Loop.unit(roared,"leonard")["stamina"] == 0,"獅子吼 pays 20ST and cancels the target's future slot via 0x407550")
	check(roared["turn_queue"]["slots"].filter(func(slot): return slot["id"] == "enemy021_1" and slot["enabled"]).is_empty() and Loop.unit(roared,"enemy021_1")["hp"] == roar_target["hp"],"the cancelled slot stays in the queue as disabled and no damage is dealt")
	check(Loop.attack_target(roar,"enemy023_1",no_rng)["last_attack_reject"].get("reason","") in ["not_enemy","out_of_range"],"a non-enemy is not a CancelActive target")
	var wake_id := "special:magicMIND:magicCode02"
	var wake := controlled()
	Loop._unit(wake,"enemy023_1")["live_speed"] = 101
	wake["turn_queue"] = Loop.CoreTurnQueue.rebuild(wake["units"])
	wake["turn_queue"]["index"] = 1 # enemy023_1 (player-controlled ally) already acted; leonard is current
	wake = Loop.select_player_unit(wake,"leonard")
	Loop._unit(wake,"leonard")["stamina"] = 60
	own(wake, "skill_book")["actors"][roar_actor]["supported_initial_ids"].append(wake_id)
	Loop._unit(wake,"enemy023_1")["coord"] = Loop.unit(wake,"leonard")["coord"] + Vector2i(1,0)
	wake = Loop.choose_special(Loop.choose_command(wake,"special"), wake_id)
	var woken := Loop.attack_coord(wake, Loop.unit(wake,"enemy023_1")["coord"], func(_n): return 0)
	var wake_effects: Array = woken.get("last_attack", {}).get("turn_effects", [])
	check(wake_effects.size() == 1 and wake_effects[0]["kind"] == "reactivate" and wake_effects[0]["applied"] and int(wake_effects[0]["slot_index"]) == 0 and Loop.unit(woken,"leonard")["stamina"] == 0,"天鳴覺醒 re-enables the acted ally's consumed slot via 0x4075a0 for 60ST")
	check(woken["turn_queue"]["slots"][0].get("reactivated", false) and woken["turn_queue"]["index"] == 1,"reactivation marks the earlier slot without moving the current actor")
	var untouched := controlled()
	own(untouched, "skill_book")["actors"][roar_actor]["supported_initial_ids"].append(wake_id)
	Loop._unit(untouched,"leonard")["stamina"] = 60
	Loop._unit(untouched,"enemy023_1")["coord"] = Loop.unit(untouched,"leonard")["coord"] + Vector2i(1,0)
	untouched = Loop.choose_special(Loop.choose_command(untouched,"special"), wake_id)
	check(Loop.attack_coord(untouched, Loop.unit(untouched,"enemy023_1")["coord"], no_rng)["last_attack_reject"].get("reason","") == "skill_has_no_effect","an ally that has not acted yet is refused before payment (0x4075a0 would return 0)")
	# 0x4074a0 second pass: the re-enabled slot is served before the round rebuilds.
	var queue := Loop.CoreTurnQueue.rebuild([{"id":"a","live_speed":3},{"id":"b","live_speed":2},{"id":"c","live_speed":1}])
	queue["index"] = 1
	queue = Loop.CoreTurnQueue.reactivate_consumed(queue,"a")["queue"]
	var passed := Loop.CoreTurnQueue.end_turn(queue)
	check(passed["index"] == 2 and Loop.CoreTurnQueue.current(passed)["id"] == "c","forward slots are still served first")
	var second := Loop.CoreTurnQueue.end_turn(passed)
	check(second["index"] == 0 and second["round"] == 0 and Loop.CoreTurnQueue.current(second)["id"] == "a" and second["slots"][1]["consumed"] and second["slots"][2]["consumed"],"the second pass returns to the re-enabled slot with every other slot consumed")
	var rebuilt := Loop.CoreTurnQueue.end_turn(second)
	check(rebuilt["round"] == 1 and rebuilt["index"] == 0 and Loop.CoreTurnQueue.current(rebuilt)["id"] == "a" and not rebuilt["slots"][0].has("consumed"),"after the re-enabled slot the round rebuilds normally")
	# 竊殺: Attack+StealGold — party casters add capped carried gold, enemy casters drain party gold.
	var steal_id := "special:magicOTHER:magicCode13"
	var steal := controlled()
	own(steal, "skill_book")["actors"][roar_actor]["supported_initial_ids"].append(steal_id)
	var steal_target := Loop._unit(steal,"enemy021_1")
	steal_target["coord"] = Loop.unit(steal,"leonard")["coord"] + Vector2i(0,2)
	steal_target["hp"] = 1000
	var target_gold: int = int(steal["reward_data"]["actors"][str(steal_target["actor_id"])]["gold"])
	steal = Loop.choose_special(Loop.choose_command(steal,"special"), steal_id)
	var stolen := Loop.attack_target(steal,"enemy021_1",func(_n): return 0)
	var gold_effects: Array = stolen.get("last_attack", {}).get("gold_effects", [])
	check(gold_effects.size() == 1 and gold_effects[0]["from"] == "target_carry" and int(gold_effects[0]["amount"]) == mini(31, target_gold) and int(stolen["gold"]) == int(steal["gold"]) + int(gold_effects[0]["amount"]),"竊殺 by a registered player adds rand-free low+1 gold capped by the target's carried gold")
	check(int(stolen["last_attack"]["damage"]) > 0 and Loop.unit(stolen,"leonard")["stamina"] == 0 and int(stolen["last_attack"]["experience_basis"]["direct_experience"]) == int(gold_effects[0]["amount"]) / 2,"the Attack bit still deals damage, one 20ST payment, and StealGold EXP is added directly")
	# 0x40b548 caps a registered player's steal by the target record +0x98, the same live word kill gold
	# 0x40e390 returns; 0x42bd50 word 0 writes the EVEF instance gold over it after the template copy.
	# A synthetic override below the rand-free amount (31) and the 021 template makes the two readings differ.
	var carried := controlled()
	own(carried, "skill_book")["actors"][roar_actor]["supported_initial_ids"].append(steal_id)
	var carried_target := Loop._unit(carried,"enemy021_1")
	carried_target["coord"] = Loop.unit(carried,"leonard")["coord"] + Vector2i(0,2)
	carried_target["hp"] = 1000
	carried_target["evef_instance"] = {"evidence_tier": "resource-derived", "record_index": 17, "overrides": {"gold": 7}}
	var live_gold: int = Loop.RewardRules.carried_gold(carried_target, target_gold)
	check(target_gold > 7 and live_gold == 7 and live_gold == Loop.RewardRules.kill_gold(carried_target, target_gold),"the live +0x98 word takes the EVEF instance gold over the 021 template")
	carried = Loop.choose_special(Loop.choose_command(carried,"special"), steal_id)
	var carried_effects: Array = Loop.attack_target(carried,"enemy021_1",func(_n): return 0).get("last_attack", {}).get("gold_effects", [])
	check(carried_effects.size() == 1 and carried_effects[0]["from"] == "target_carry" and int(carried_effects[0]["amount"]) == live_gold,"竊殺 caps by the same live +0x98 the kill gold reads (EVEF instance override), not the PLAYERS template: " + str(carried_effects))
	# Enemy A killing controlled B adds B's kill gold to A's record +0x98 (0x442720 state 2,
	# 0x442856..0x442875), so the same cap then reads instance 7 + B's 12 = 19 (< the rand-free 31).
	var grown := controlled()
	own(grown, "skill_book")["actors"][roar_actor]["supported_initial_ids"].append(steal_id)
	var grown_target := Loop._unit(grown,"enemy021_1")
	grown_target["coord"] = Loop.unit(grown,"leonard")["coord"] + Vector2i(0,2)
	grown_target["hp"] = 1000
	grown_target["evef_instance"] = {"evidence_tier": "resource-derived", "record_index": 17, "overrides": {"gold": 7}}
	var fallen := Loop._unit(grown,"enemy023_1")
	fallen["coord"] = grown_target["coord"] + Vector2i(1,0)
	fallen["hp"] = 1
	fallen["combat_profile"]["live_defense"] = 0
	fallen["evef_instance"] = {"evidence_tier": "resource-derived", "record_index": 18, "overrides": {"gold": 12}}
	LoopCombat._resolve_exchange(grown,"enemy021_1","enemy023_1",func(_n): return 0)
	check(Loop.unit(grown,"enemy023_1")["defeated"] and int(Loop.unit(grown,"enemy021_1").get(Loop.RewardRules.CARRIED_GAINED,0)) == 12 and int(grown["gold"]) == 0,"enemy A's kill of controlled B keeps B's kill gold 12 on A, not the party")
	grown = Loop.choose_special(Loop.choose_command(grown,"special"), steal_id)
	var grown_effects: Array = Loop.attack_target(grown,"enemy021_1",func(_n): return 0).get("last_attack", {}).get("gold_effects", [])
	check(grown_effects.size() == 1 and grown_effects[0]["from"] == "target_carry" and int(grown_effects[0]["amount"]) == 7 + 12,"竊殺 against A caps at its instance gold + B's kill gold: " + str(grown_effects))
	var thief := Loop._unit(learned,"enemy026_1")
	thief["actor_id"] = "026"
	thief["growth_profile"]["job_code"] = 88
	thief["level"] = 10
	thief["stamina"] = 100
	thief["learned_skills"] = []
	thief.merge(Resolution.StatMagic.Progression.refresh_growth_stats(thief, learned["equipment_items"]), true)
	var thief_book: Dictionary = learned["skill_book"].duplicate(true)
	thief_book["actors"]["026"]["supported_initial_ids"].append(steal_id)
	var victim := Loop._unit(learned,"leonard")
	thief["coord"] = Vector2i(8,8)
	victim["coord"] = Vector2i(8,10)
	victim["hp"] = 1000
	var party_context := {"turn_queue": learned["turn_queue"], "gold": 12, "reward_data": learned["reward_data"]}
	var party_drain := Resolution.resolve_cast(thief,victim,[thief,victim],steal_id,Loop.skill_fields(learned,steal_id),thief_book,learned["skill_target_data"],learned["equipment_items"],thief["coord"],learned["map_size"],func(_n): return 0,victim["coord"],party_context)
	var drain_effects: Array = party_drain.get("gold_effects", [])
	check(party_drain.get("ok", false) and drain_effects.size() == 1 and drain_effects[0]["from"] == "party" and int(drain_effects[0]["amount"]) == 12,"an enemy thief drains the party gold, capped by what the party holds")
	# The drained take also goes into 0x4c2c84 (0x40b568..0x40b572), which 0x4416bc pays the caster
	# through 0x442720 state 2: an enemy caster keeps it on its own record +0x98.
	var robbed := controlled()
	var robber := Loop._unit(robbed,"enemy026_1")
	robber["actor_id"] = "026"
	robber["growth_profile"]["job_code"] = 88
	robber["level"] = 10
	robber["stamina"] = 100
	robber["learned_skills"] = []
	robber.merge(Resolution.StatMagic.Progression.refresh_growth_stats(robber, robbed["equipment_items"]), true)
	own(robbed, "skill_book")["actors"]["026"]["supported_initial_ids"].append(steal_id)
	var robbed_leonard := Loop._unit(robbed,"leonard")
	robbed_leonard["hp"] = 1000
	robber["coord"] = robbed_leonard["coord"] + Vector2i(0,2)
	robbed["gold"] = 12
	var robbery := LoopCombat._resolve_skill(robbed,"enemy026_1","leonard",steal_id,Loop.skill_fields(robbed,steal_id),robber["coord"],func(_n): return 0,robbed_leonard["coord"])
	var robbery_effects: Array = robbery.get("gold_effects", [])
	check(robbery_effects.size() == 1 and robbery_effects[0]["from"] == "party" and int(robbed["gold"]) == 0 and int(Loop.unit(robbed,"enemy026_1").get(Loop.RewardRules.CARRIED_GAINED,0)) == 12 and robbery_effects[0].get("carried_by","") == "enemy026_1","an enemy thief keeps the drained 12 on its own record +0x98: " + str(robbery_effects))
	var robber_gold: int = Loop.RewardRules.kill_gold(Loop.unit(robbed,"enemy026_1"), int(robbed["reward_data"]["actors"]["026"]["gold"]))
	Loop._unit(robbed,"enemy026_1")["hp"] = 1
	Loop._unit(robbed,"enemy026_1")["stamina"] = 0 # the synthetic 100ST is outside 026's stamina domain for an exchange
	LoopCombat._resolve_exchange(robbed,"leonard","enemy026_1",func(_n): return 0)
	check(Loop.unit(robbed,"enemy026_1")["defeated"] and int(robbed["gold"]) == robber_gold + 12,"killing the thief pays its template gold + the gold it stole: " + str(robbed["gold"]))
	check(Resolution.resolve_cast(thief,victim,[thief,victim],steal_id,Loop.skill_fields(learned,steal_id),thief_book,learned["skill_target_data"],learned["equipment_items"],thief["coord"],learned["map_size"],no_rng,victim["coord"]).get("reason","") == "missing_reward_context","StealGold without the reward context fails before RNG")
	# 金之手: StealItem walks the target's slots and moves the first passing item into the shared pending loot.
	var hand_id := "special:magicOTHER:magicCode12"
	var hand := controlled()
	own(hand, "skill_book")["actors"][roar_actor]["supported_initial_ids"].append(hand_id)
	Loop._unit(hand,"leonard")["stamina"] = 60
	var hand_target := Loop._unit(hand,"enemy021_1")
	hand_target["coord"] = Loop.unit(hand,"leonard")["coord"] + Vector2i(1,0)
	var loot_code := int(210)
	hand_target["inventory"] = [loot_code, 0, 0, 0, 0, 0, 0, 0]
	hand = Loop.choose_special(Loop.choose_command(hand,"special"), hand_id)
	var pickpocketed := Loop.attack_target(hand,"enemy021_1",func(_n): return 0)
	var stolen_items: Array = pickpocketed.get("last_attack", {}).get("stolen_items", [])
	check(stolen_items.size() == 1 and int(stolen_items[0]["code"]) == loot_code and int(stolen_items[0]["source_slot"]) == 0 and Loop.unit(pickpocketed,"leonard")["stamina"] == 0,"金之手 pays 60ST and steals the first slot when rand(100)+1 < get_ratio+10")
	check(Loop.unit(pickpocketed,"enemy021_1")["inventory"] == [0, 0, 0, 0, 0, 0, 0, 0] and int(pickpocketed["last_attack"]["damage"]) == 0 and Loop.unit(pickpocketed,"enemy021_1")["hp"] == hand_target["hp"],"the stolen slot shifts out of the target (0x436e80) without damage")
	var hand_basis: Dictionary = pickpocketed.get("last_attack", {}).get("experience_basis", {})
	var hand_immediate: Array = hand_basis.get("immediate_experience", [])
	check(pickpocketed["last_attack"].get("immediate_contributions") == [1] and int(hand_basis.get("contribution", -1)) == int(pickpocketed["last_attack"]["native_damage_roll"]["value"]) and hand_immediate.size() == 1 and int(hand_basis["points"]) == int(hand_basis["tail_points"]) + int(hand_immediate[0]["points"]) and int(pickpocketed["last_attack"]["experience_settlement"]["base"]) == int(hand_basis["points"]),"StealItem converts rand(level)+1 at once (0x40b674) and the proc0 value at the tail (0x40b866); the settlement awards both")
	var pending: Array = pickpocketed.get("settlement", {}).get("pending", [])
	check(Loop.loot_waiting(pickpocketed) and pending.size() == 1 and int(pending[0]["code"]) == loot_code and pending[0]["source_id"] == "enemy021_1" and str(pending[0]["id"]).ends_with(":stolen"),"the stolen item enters the shared claim collection (0x44f2d0 path)")
	# 0x40b5a8 threshold: rand(100)+1 < get_ratio + 10 + caster +0x196, where +0x196 is the PLAYERS steal_ratio
	# word (12 when 0, 0x448840) plus every equipped add_steal_ratio (0x448420). 210 黃金首飾 get_ratio 60.
	var recorded: Array = []
	Loop.attack_target(hand,"enemy021_1",func(bound): recorded.append(int(bound)); return 0)
	var steal_call := recorded.rfind(100)
	check(steal_call > 0 and recorded.count(100) == 2 and int(recorded[steal_call + 1]) == int(Loop.unit(hand,"leonard")["level"]),"the steal draw is the second rand(100) (after the hit check), followed by the rand(level)+1 immediate conversion")
	var at_call := func(index: int, value: int) -> Callable:
		var calls: Array = [0]
		return func(bound):
			var current: int = calls[0]
			calls[0] = current + 1
			return clampi(value, 0, int(bound) - 1) if current == index else 0
	check(int(Loop.unit(hand,"leonard")["combat_profile"]["steal_ratio"]) == 12 and int(Loop.unit(hand,"leonard")["combat_profile"]["base_steal_ratio"]) == 0,"001 declares no steal_ratio, so the +0x196 work value is the 0x448840 default 12")
	var edge := Loop.attack_target(hand,"enemy021_1",at_call.call(steal_call, 80))
	check(edge["last_attack"]["stolen_items"].size() == 1 and int(edge["last_attack"]["stolen_items"][0]["steal_roll"]) == 81,"draw 81 < 60+10+12 still steals")
	var missed := Loop.attack_target(hand,"enemy021_1",at_call.call(steal_call, 81))
	check(missed["last_attack"]["stolen_items"].is_empty() and Loop.unit(missed,"enemy021_1")["inventory"][0] == loot_code and Loop.unit(missed,"leonard")["stamina"] == 0,"draw 82 fails the default threshold: the item stays and the 60ST is still spent")
	var thief_hand := hand.duplicate(true)
	var thief_leonard := Loop._unit(thief_hand,"leonard")
	thief_leonard["combat_profile"]["base_steal_ratio"] = 30  # 004 漢克斯's PLAYERS word
	thief_leonard.merge(Loop.ProgressionRules.refresh_growth_stats(thief_leonard,thief_hand["equipment_items"]),true)
	check(int(thief_leonard["combat_profile"]["steal_ratio"]) == 30,"a nonzero steal_ratio word replaces the default 12 in the refresh")
	var bonus := Loop.attack_target(thief_hand,"enemy021_1",at_call.call(steal_call, 98))
	check(bonus["last_attack"]["stolen_items"].size() == 1 and int(bonus["last_attack"]["stolen_items"][0]["steal_roll"]) == 99,"draw 99 < 60+10+30 steals with the 漢克斯 word")
	check(Loop.attack_target(thief_hand,"enemy021_1",at_call.call(steal_call, 99))["last_attack"]["stolen_items"].is_empty(),"draw 100 fails even the 漢克斯 threshold")
	var cloaked := hand.duplicate(true)
	var cloaked_leonard := Loop._unit(cloaked,"leonard")
	cloaked_leonard["equipment"] = cloaked_leonard["equipment"].filter(func(entry): return entry["slot"] != "armor") + [{"slot":"armor","item_code":131,"name":"隱忍黑衣"}]
	var cloak_delta := Loop.EquipmentRules.effect_delta(cloaked_leonard["equipment"],cloaked["equipment_items"])
	check(cloak_delta["ok"] and int(cloak_delta["delta"]["steal_ratio"]) == 20,"131 隱忍黑衣 add_steal_ratio 20 is a supported equipment effect (item +0x40)")
	cloaked_leonard.merge(Loop.ProgressionRules.refresh_growth_stats(cloaked_leonard,cloaked["equipment_items"]),true)
	check(int(cloaked_leonard["combat_profile"]["steal_ratio"]) == 32,"the work value is the default 12 plus the equipped 20")
	var unrefreshed := hand.duplicate(true)
	Loop._unit(unrefreshed,"leonard")["combat_profile"].erase("steal_ratio")
	check(Loop.attack_target(unrefreshed,"enemy021_1",no_rng)["last_attack_reject"].get("reason","") == "missing_steal_ratio","a caster without the +0x196 work value is refused instead of stealing at an assumed 0")
	var empty_handed := controlled()
	own(empty_handed, "skill_book")["actors"][roar_actor]["supported_initial_ids"].append(hand_id)
	Loop._unit(empty_handed,"leonard")["stamina"] = 60
	Loop._unit(empty_handed,"enemy021_1")["coord"] = Loop.unit(empty_handed,"leonard")["coord"] + Vector2i(1,0)
	Loop._unit(empty_handed,"enemy021_1")["inventory"] = [0, 0, 0, 0, 0, 0, 0, 0]
	empty_handed = Loop.choose_special(Loop.choose_command(empty_handed,"special"), hand_id)
	check(Loop.attack_target(empty_handed,"enemy021_1",no_rng)["last_attack_reject"].get("reason","") == "skill_has_no_effect","a target with nothing to steal is refused before payment")
	# 0x40b5e1..0x40b5e5 (native receipt original_steal_ratio.json): the slot walk ends at the first empty slot,
	# so an item behind a hole is never rolled and a target whose first slot is empty has nothing to steal.
	var holed := controlled()
	own(holed, "skill_book")["actors"][roar_actor]["supported_initial_ids"].append(hand_id)
	Loop._unit(holed,"leonard")["stamina"] = 60
	Loop._unit(holed,"enemy021_1")["coord"] = Loop.unit(holed,"leonard")["coord"] + Vector2i(1,0)
	Loop._unit(holed,"enemy021_1")["inventory"] = [0, loot_code, 0, 0, 0, 0, 0, 0]
	holed = Loop.choose_special(Loop.choose_command(holed,"special"), hand_id)
	check(Loop.attack_target(holed,"enemy021_1",no_rng)["last_attack_reject"].get("reason","") == "skill_has_no_effect","an item behind an empty first slot is out of the native walk's reach, so the use is refused like an empty inventory")
	var behind_hole := controlled()
	own(behind_hole, "skill_book")["actors"][roar_actor]["supported_initial_ids"].append(hand_id)
	Loop._unit(behind_hole,"leonard")["stamina"] = 60
	Loop._unit(behind_hole,"enemy021_1")["coord"] = Loop.unit(behind_hole,"leonard")["coord"] + Vector2i(1,0)
	Loop._unit(behind_hole,"enemy021_1")["inventory"] = [loot_code, 0, loot_code, 0, 0, 0, 0, 0]
	behind_hole = Loop.choose_special(Loop.choose_command(behind_hole,"special"), hand_id)
	var hole_recorded: Array = []
	var hole_stop := Loop.attack_target(behind_hole,"enemy021_1",func(n): hole_recorded.append(n); return 81 if n == 100 and hole_recorded.count(100) == 2 else 0)
	check(hole_stop["last_attack"]["stolen_items"].is_empty() and hole_recorded.count(100) == 2 and Loop.unit(hole_stop,"enemy021_1")["inventory"] == [loot_code, 0, loot_code, 0, 0, 0, 0, 0],"a failed first slot followed by an empty slot ends the walk: the item behind the hole gets no roll (one steal rand(100) after the hit check)")
	# 銀之手: 漢克斯 004's PLAYERS special_other declaration grants the pure StealGold row initially.
	var silver_id := "special:magicOTHER:magicCode10"
	check(learned["skill_book"]["actors"]["004"]["supported_initial_ids"].has(silver_id),"004 receives 銀之手 from its source special_other declaration")
	var hanks := thief.duplicate(true)
	victim["coord"] = Vector2i(8,9)
	hanks["actor_id"] = "004"
	hanks["stamina"] = 100
	check(Resolution.ownership_error(hanks, silver_id, learned["skill_book"]) == "","004 owns 銀之手 without a learning record")
	var silver := Resolution.resolve_cast(hanks,victim,[hanks,victim],silver_id,Loop.skill_fields(learned,silver_id),learned["skill_book"],learned["skill_target_data"],learned["equipment_items"],hanks["coord"],learned["map_size"],func(_n): return 0,victim["coord"],party_context)
	var silver_effects: Array = silver.get("gold_effects", [])
	check(silver.get("ok", false) and int(silver["receipt"]["damage"]) == 0 and int(victim["hp"]) == int(silver["target_changes"].get("hp", victim["hp"])) and silver_effects.size() == 1 and int(silver_effects[0]["amount"]) == 11 and silver["caster_changes"].get("stamina", 100) == 80,"pure StealGold deals no damage, pays 20ST and takes low+1 gold (rand 0) within the party cap")
	# PLAYERS steal_ratio: 004 漢克斯 30 and 013 20 are the only nonzero rows; the 0x4348f0 job-up adds the
	# +0x194 words (0x434aa6) and the next refresh rebuilds the +0x196 work value from the sum.
	var JobUp = preload("res://game/sim/JobUpRules.gd")
	var hanks_template := JobUp.load_source_template("004")
	check(int(hanks_template["combat_profile"]["base_steal_ratio"]) == 30 and int(hanks_template["combat_profile"]["steal_ratio"]) == 30,"004's template carries its PLAYERS word 30 as both the base and the work value (no add_steal_ratio gear)")
	var live_hanks := hanks.duplicate(true)
	live_hanks["combat_profile"]["base_steal_ratio"] = int(hanks_template["combat_profile"]["base_steal_ratio"])
	var upped := JobUp.merge_source_template(live_hanks, JobUp.load_source_template("013"), JobUp.NATIVE_JOB_UP_FLAG)
	check(upped["ok"] and int(upped["actor"]["combat_profile"]["base_steal_ratio"]) == 50,"the 013 job-up sums the +0x194 words: 30 + 20")
	var upped_refresh := Loop.ProgressionRules.refresh_growth_stats(upped["actor"], learned["equipment_items"])
	check(Loop.ProgressionRules.refresh_input_error(upped["actor"], learned["equipment_items"]) == "" and int(upped_refresh["combat_profile"]["steal_ratio"]) == 50,"after the job-up the refresh writes +0x196 = 50 (nonzero word, no default)")
	# Wave 9 lane A2: the unowned source rows 獅子吼2／吸血劍2／金之手LV2 keep their base skill's utility
	# policy. No PLAYERS field, learning table or source template references them (resource-derived);
	# they only have to resolve as data through the same transaction. [id, base id]
	for pair in [["special:magicOTHER:magicCode32", roar_id], ["special:magicOTHER2:magicCode03", drain_id], ["special:magicOTHER:magicCode14", hand_id]]:
		var twin_id: String = pair[0]
		var twin: Dictionary = learned["skill_book"]["skills"][twin_id]
		var base: Dictionary = learned["skill_book"]["skills"][pair[1]]
		check(twin["damage_policy"] == base["damage_policy"] and (twin["name"] == base["name"] or twin["name"] == "高級金之手") and twin["fields"]["function"] == base["fields"]["function"],"the 2/LV2 row shares its base skill's function and policy (and name, except 高級金之手 RESOURCE 264): " + twin_id)
		check(learned["skill_book"]["actors"].values().all(func(actor): return not actor["supported_initial_ids"].has(twin_id)) and Resolution.descriptor_error(twin_id, twin["fields"], learned["skill_book"], learned["skill_target_data"]) == "","no source actor holds the row, yet its descriptor passes the shared gate: " + twin_id)
		var twin_loop := controlled()
		own(twin_loop, "skill_book")["actors"][roar_actor]["supported_initial_ids"].append(twin_id)
		Loop._unit(twin_loop,"leonard")["stamina"] = 60
		var twin_target := Loop._unit(twin_loop,"enemy021_1")
		twin_target["coord"] = Loop.unit(twin_loop,"leonard")["coord"] + Vector2i(1,0)
		twin_target["hp"] = 1000
		twin_target["inventory"] = [210, 0, 0, 0, 0, 0, 0, 0]
		twin_loop = Loop.choose_special(Loop.choose_command(twin_loop,"special"), twin_id)
		var twin_done := Loop.attack_target(twin_loop,"enemy021_1",func(_n): return 0)
		check(twin_done["attacked_this_action"] and twin_done["last_attack"].get("skill_id") == twin_id and Loop.unit(twin_done,"leonard")["stamina"] < 60,"a fixture grant resolves the row through the player special path with one ST payment: " + twin_id)
		match twin_id:
			"special:magicOTHER:magicCode32": check(twin_done["last_attack"]["turn_effects"].size() == 1 and twin_done["last_attack"]["turn_effects"][0]["kind"] == "cancel_pending","獅子吼2 cancels the pending slot like 獅子吼")
			"special:magicOTHER2:magicCode03": check(int(twin_done["last_attack"]["damage"]) > 0 and int(twin_done["last_attack"]["stolen_hp"]) >= 0 and twin_done["last_attack"].has("stolen_hp"),"吸血劍2 deals damage and drains like 吸血劍")
			"special:magicOTHER:magicCode14": check(twin_done["last_attack"]["stolen_items"].size() == 1 and int(twin_done["last_attack"]["stolen_items"][0]["code"]) == 210,"金之手LV2 steals the first passing slot like 金之手")
