extends "res://tests/support/TestSuite.gd"
const SkillResolutionRules = preload("res://game/sim/SkillResolutionRules.gd")
const BattlePlayLoop = preload("res://game/sim/loop/BattlePlayLoop.gd")
const BattleLoopCombat = preload("res://game/sim/loop/BattleLoopCombat.gd")
const BattleFixture = preload("res://tests/support/BattleFixture.gd")
const RulesReadback = preload("res://tests/support/RulesReadback.gd")


func _init() -> void:
	tag = "SKILL_RESOLUTION_TESTS"


func controlled() -> Dictionary:
	var loop := BattleFixture.loop()
	BattlePlayLoop.unit_ref(loop,"leonard")["live_speed"] = 100
	var next := BattlePlayLoop.unit_ref(loop,"enemy023_1")
	next["live_speed"] = 99
	next["player_commandable"] = true
	next["battle_actor_role"] = BattlePlayLoop.ROLE_PLAYER
	loop["turn_queue"] = BattlePlayLoop.CoreTurnQueue.rebuild(loop["units"])
	BattlePlayLoop.unit_ref(loop,"leonard")["stamina"] = 20
	return BattlePlayLoop.select_player_unit(loop,"leonard")


func run() -> void:
	var loop := controlled()
	_native_damage_rolls(loop)
	_ownership_and_commit(loop)
	var learned := BattleFixture.loop()
	_learned_damage_magic(learned)
	_learned_damage_magic_upper(learned)
	_weaken_status(learned)
	_special_status(learned)
	_support_heal(learned)
	_stat_buffs_and_drain(learned)
	_turn_effects()
	_steal_gold_player()
	_steal_gold_enemy(learned)
	_steal_item()
	_steal_item_slot_walk()
	_unowned_twin_rows(learned)
	run_skill_footprint_preview()
	run_skill_resource()
	run_skill_target()


func _leonard_actor() -> String:
	return BattlePlayLoop.unit(controlled(),"leonard")["actor_id"]


## Native damage rolls (original_magic_damage, original_skill_resources): Qi Blade and magic check
## hit first, then the triangular (and level) draws; one resource payment; role never picks the formula.
func _native_damage_rolls(loop: Dictionary) -> void:
	var book: Dictionary = loop["skill_book"]
	var targeting: Dictionary = loop["skill_target_data"]
	var items: Dictionary = loop["equipment_items"]
	var cases := [["special:magicOTHER:magicCode01",loop["skill_book"]["skills"]["special:magicOTHER:magicCode01"]["fields"],"leonard","enemy021_1",36,54,20],
		["magic:magicAIR:magicCode01",loop["skill_book"]["skills"]["magic:magicAIR:magicCode01"]["fields"],"enemy026_1","leonard",12,26,8],
		["magic:magicFIRE:magicCode01",loop["skill_book"]["skills"]["magic:magicFIRE:magicCode01"]["fields"],"enemy026_1","leonard",18,32,8]]
	for case in cases:
		for high in [false,true]:
			for hit in [false,true]:
				var actor := BattlePlayLoop.unit(loop,case[2]).duplicate(true)
				var target := BattlePlayLoop.unit(loop,case[3]).duplicate(true)
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
				var result := SkillResolutionRules.resolve(actor,target,case[0],case[1],book,targeting,items,actor["coord"],loop["map_size"],rng)
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
				# The same original character with opposite control roles must use
				# exactly the same effect policy; AI is only a choice/presentation path.
				actor["battle_actor_role"] = BattlePlayLoop.ROLE_ENEMY if actor["battle_actor_role"] == BattlePlayLoop.ROLE_PLAYER else BattlePlayLoop.ROLE_PLAYER
				target["battle_actor_role"] = BattlePlayLoop.ROLE_PLAYER if actor["battle_actor_role"] == BattlePlayLoop.ROLE_ENEMY else BattlePlayLoop.ROLE_ENEMY
				draws.clear()
				var as_player := SkillResolutionRules.resolve(actor,target,case[0],case[1],book,targeting,items,actor["coord"],loop["map_size"],rng)
				check(as_player==result,"role change alone cannot select a different skill formula")


## Initial ownership comes from the PLAYERS source declarations (original_skill_function_bits);
## overkill applies the exact health delta; the player path commits once and hands off once.
func _ownership_and_commit(loop: Dictionary) -> void:
	var book: Dictionary = loop["skill_book"]
	var targeting: Dictionary = loop["skill_target_data"]
	var items: Dictionary = loop["equipment_items"]
	var caster := BattlePlayLoop.unit_ref(loop,"leonard")
	var target := BattlePlayLoop.unit_ref(loop,"enemy021_1")
	target["coord"] = caster["coord"] + Vector2i.UP
	target["hp"] = 100
	target["combat_profile"]["live_defense"] = 10000
	var fields: Dictionary = loop["skill_book"]["skills"]["special:magicOTHER:magicCode01"]["fields"]
	var false_owner := loop.duplicate(true)
	BattlePlayLoop.unit_ref(false_owner,"leonard")["actor_id"] = "023"
	check(not BattlePlayLoop.can_use_special(false_owner,"leonard"),"a stamina field does not grant Leonard's special to another original actor")
	false_owner["interaction"] = "attack_select"
	false_owner["selected_attack"] = "special"
	false_owner["selected_skill_id"] = "special:magicOTHER:magicCode01"
	var rejected := BattlePlayLoop.attack_target(false_owner,"enemy021_1",no_rng)
	check(rejected["last_attack_reject"]["reason"]=="skill_not_owned" and rejected["units"]==false_owner["units"],"forced selection cannot bypass initial ownership")
	var wounded := target.duplicate(true)
	wounded["hp"] = 2
	wounded["combat_profile"]["live_defense"] = 0
	var lethal := SkillResolutionRules.resolve(caster,wounded,"special:magicOTHER:magicCode01",fields,book,targeting,items,caster["coord"],loop["map_size"],func(_n):return 0)
	check(lethal["target_changes"]=={"hp":0,"defeated":true} and lethal["receipt"]["actual_damage"]==2,"overkill has exact applied health delta without negative HP")
	# Public player path must commit once and leave the next actor ready, even
	# when the selected target is killed and resource/experience both change.
	for moved in [false,true]:
		var ready := controlled()
		if moved:
			ready = BattlePlayLoop.choose_command(ready,"move")
			var from: Vector2i = BattlePlayLoop.unit(ready,"leonard")["coord"]
			var candidates: Array = BattlePlayLoop.movement_cells(ready,"leonard").filter(func(p):return p!=from)
			ready = BattlePlayLoop.move_unit_to(ready,candidates[0])
		var enemy := BattlePlayLoop.unit_ref(ready,"enemy021_1")
		enemy["coord"] = BattlePlayLoop.unit(ready,"leonard")["coord"]+Vector2i.UP
		enemy["hp"] = 2
		enemy["combat_profile"]["live_defense"] = 0
		var selected := BattlePlayLoop.choose_special(BattlePlayLoop.choose_command(ready,"special"),"special:magicOTHER:magicCode01")
		var cancelled := BattlePlayLoop.cancel_interaction(selected)
		check(cancelled["units"]==ready["units"] and cancelled["turn_queue"]==ready["turn_queue"] and cancelled["pending_move"]==ready["pending_move"],"move/skill cancel preserves all confirmed state")
		var committed := BattlePlayLoop.attack_target(selected,"enemy021_1",func(_n):return 0)
		check(BattlePlayLoop.unit(committed,"leonard")["stamina"]==0 and BattlePlayLoop.unit(committed,"enemy021_1")["hp"]==0,"shared commit applies resource and effect together")
		check(committed["last_attack"]["experience"]["gained"] == committed["last_attack"]["experience_basis"]["points"] and committed["last_attack"]["experience_basis"]["contribution"] == 2, "common receipt converts actual damage then awards final experience once")
		check(BattlePlayLoop.attack_target(committed,"enemy021_1",no_rng)["units"]==committed["units"],"replayed target cannot repeat damage/resource/experience")
		var finished := BattlePlayLoop.finish_exhausted_action(committed)
		check(finished["selected_unit_id"]=="enemy023_1" and finished["turn_queue"]["index"]==1,"resolved skill hands off once after presentation")
		check(BattlePlayLoop.finish_exhausted_action(finished)==finished,"repeated presentation cannot advance a second actor")
	# A character with another wind skill must not gain Code01 merely because
	# it has MP and a wind declaration (025 owns a different source bit).
	var ai := BattleFixture.loop()
	var mage := BattlePlayLoop.unit_ref(ai,"enemy026_1")
	mage["actor_id"] = "025"
	mage["mp"] = 30
	var enemy := BattlePlayLoop.unit_ref(ai,"leonard")
	mage["coord"] = enemy["coord"] + Vector2i.RIGHT
	var initial := ai.duplicate(true)
	var unowned := SkillResolutionRules.resolve(mage, enemy, "magic:magicAIR:magicCode01", BattlePlayLoop.skill_fields(ai, "magic:magicAIR:magicCode01"), ai["skill_book"], ai["skill_target_data"], ai["equipment_items"], mage["coord"], ai["map_size"], no_rng)
	check(not unowned["ok"] and unowned["reason"] == "skill_not_owned" and ai == initial, "another wind declaration still cannot grant Code01; actual 025 Acid Mist is covered separately")


## Learned source attack magic/specials (original_magic_damage): each element reaches its resistance
## slot through native damage with one MP/ST payment; specials honor their effect range.
func _learned_damage_magic(learned: Dictionary) -> void:
	# A learned source skill uses the same atomic magic transaction as an initial grant.
	var earth_id := "magic:magicEARTH:magicCode01"
	var earth_caster := BattlePlayLoop.unit_ref(learned,"enemy026_1")
	earth_caster["actor_id"] = "026"
	earth_caster["growth_profile"]["job_code"] = 90
	earth_caster["level"] = 1
	earth_caster["mp"] = 20
	earth_caster["learned_skills"] = [{"policy":"source_growth_lifecycle_v1","actor_id":"026","job":90,"level":1,"attributes":{"str":10,"dex":10,"mind":10,"con":10},"trigger":"level_up","id":earth_id,"name":"地裂"}]
	var earth_target := BattlePlayLoop.unit_ref(learned,"leonard")
	earth_caster["coord"] = Vector2i(8,8)
	earth_target["coord"] = Vector2i(8,9)
	earth_target["hp"] = 100
	earth_target["combat_profile"]["resist_by_type"] = {"0":25}
	var earth_fields := BattlePlayLoop.skill_fields(learned,earth_id)
	var learned_result := SkillResolutionRules.resolve(earth_caster,earth_target,earth_id,earth_fields,learned["skill_book"],learned["skill_target_data"],learned["equipment_items"],earth_caster["coord"],learned["map_size"],func(_n): return 0)
	check(learned_result["ok"] and learned_result.get("receipt", {}).get("damage", 0) > 0 and learned_result.get("caster_changes", {}).get("mp", earth_caster["mp"]) < earth_caster["mp"],"learned Earth source skill resolves with HP damage and one MP payment")
	check(learned_result.get("receipt", {}).get("magic_key", "") == "earth" and learned_result.get("target_changes", {}).get("hp", earth_target["hp"]) < earth_target["hp"],"Earth source element reaches the target HP/resistance path")
	var blade_id := "special:magicAIR:magicCode01"
	var blade_caster := BattlePlayLoop.unit_ref(learned,"enemy026_1")
	blade_caster["actor_id"] = "026"
	blade_caster["growth_profile"]["job_code"] = 80
	blade_caster["level"] = 1
	blade_caster["stamina"] = 100
	for key in ["str", "dex", "mind", "con"]: blade_caster["combat_profile"][key] = 30
	blade_caster["learned_skills"] = [{"policy":"source_growth_lifecycle_v1","actor_id":"026","job":80,"level":1,"attributes":{"str":30,"dex":25,"mind":25,"con":30},"trigger":"allocation","id":blade_id,"name":"天雷猛襲劍"}]
	var blade_target := BattlePlayLoop.unit_ref(learned,"leonard")
	blade_caster["coord"] = Vector2i(8,8)
	blade_target["coord"] = Vector2i(8,9)
	blade_target["hp"] = 100
	blade_target["combat_profile"]["resist_by_type"] = {"2":0}  # magicAIR special reads the wind resistance slot
	var blade_result := SkillResolutionRules.resolve_cast(blade_caster,blade_target,[blade_caster,blade_target],blade_id,BattlePlayLoop.skill_fields(learned,blade_id),learned["skill_book"],learned["skill_target_data"],learned["equipment_items"],blade_caster["coord"],learned["map_size"],func(_n): return 0,blade_target["coord"])
	check(blade_result.get("ok", false) and blade_result.get("receipt", {}).get("damage", 0) > 0 and blade_result.get("caster_changes", {}).get("stamina", blade_caster["stamina"]) < blade_caster["stamina"],"learned source special resolves its area target with one ST payment")
	check(blade_result.get("targets", []).size() == 1 and blade_result.get("receipt", {}).get("cast_center", Vector2i(-1,-1)) == blade_target["coord"],"source special effect range is honored by the shared cast transaction")
	var mind_id := "magic:magicMIND:magicCode01"
	var mind_caster := BattlePlayLoop.unit_ref(learned,"enemy026_1")
	mind_caster["actor_id"] = "026"
	mind_caster["growth_profile"]["job_code"] = 98
	mind_caster["level"] = 5
	mind_caster["mp"] = 30
	mind_caster["learned_skills"] = [{"policy":"source_growth_lifecycle_v1","actor_id":"026","job":98,"level":5,"attributes":{"str":1,"dex":1,"mind":1,"con":1},"trigger":"level_up","id":mind_id,"name":"咒殺"}]
	var mind_target := BattlePlayLoop.unit_ref(learned,"leonard")
	mind_caster["coord"] = Vector2i(8,8)
	mind_target["coord"] = Vector2i(8,9)
	mind_target["hp"] = 100
	mind_target["combat_profile"]["resist_by_type"] = {"4":25}
	var mind_result := SkillResolutionRules.resolve(mind_caster,mind_target,mind_id,BattlePlayLoop.skill_fields(learned,mind_id),learned["skill_book"],learned["skill_target_data"],learned["equipment_items"],mind_caster["coord"],learned["map_size"],func(_n): return 0)
	check(mind_result.get("ok", false) and mind_result.get("receipt", {}).get("damage", 0) > 0 and mind_result.get("caster_changes", {}).get("mp", mind_caster["mp"]) < mind_caster["mp"],"learned Mind source magic resolves through native damage with MP payment")
	check(mind_result.get("receipt", {}).get("magic_key", "") == "mind" and mind_result.get("target_changes", {}).get("hp", mind_target["hp"]) < mind_target["hp"],"Mind source element reaches the target resistance path")
	var water_id := "magic:magicWATER:magicCode02"
	var water_caster := BattlePlayLoop.unit_ref(learned,"enemy026_1")
	water_caster["actor_id"] = "026"
	water_caster["growth_profile"]["job_code"] = 90
	water_caster["level"] = 10
	water_caster["mp"] = 30
	water_caster["learned_skills"] = [{"policy":"source_growth_lifecycle_v1","actor_id":"026","job":90,"level":10,"attributes":{"str":1,"dex":1,"mind":1,"con":1},"trigger":"level_up","id":water_id,"name":"水龍波"}]
	var water_target := BattlePlayLoop.unit_ref(learned,"leonard")
	water_caster["coord"] = Vector2i(8,8)
	water_target["coord"] = Vector2i(8,9)
	water_target["hp"] = 100
	water_target["combat_profile"]["resist_by_type"] = {"1":25}
	var water_result := SkillResolutionRules.resolve(water_caster,water_target,water_id,BattlePlayLoop.skill_fields(learned,water_id),learned["skill_book"],learned["skill_target_data"],learned["equipment_items"],water_caster["coord"],learned["map_size"],func(_n): return 0)
	check(water_result.get("ok", false) and water_result.get("receipt", {}).get("damage", 0) > 0 and water_result.get("caster_changes", {}).get("mp", water_caster["mp"]) < water_caster["mp"],"learned Water source magic resolves through native damage with MP payment")
	check(water_result.get("receipt", {}).get("magic_key", "") == "water" and water_result.get("target_changes", {}).get("hp", water_target["hp"]) < water_target["hp"],"Water source element reaches the target resistance path")


## Learned level-two attack magic and attack-plus-paralysis (original_magic_damage).
func _learned_damage_magic_upper(learned: Dictionary) -> void:
	var fire_id := "magic:magicFIRE:magicCode02"
	var fire_caster := BattlePlayLoop.unit_ref(learned,"enemy026_1")
	fire_caster["actor_id"] = "026"
	fire_caster["growth_profile"]["job_code"] = 90
	fire_caster["level"] = 12
	fire_caster["mp"] = 30
	fire_caster["learned_skills"] = [{"policy":"source_growth_lifecycle_v1","actor_id":"026","job":90,"level":12,"attributes":{"str":1,"dex":1,"mind":1,"con":1},"trigger":"level_up","id":fire_id,"name":"熾焰鳥"}]
	var fire_target := BattlePlayLoop.unit_ref(learned,"leonard")
	fire_caster["coord"] = Vector2i(8,8)
	fire_target["coord"] = Vector2i(8,9)
	fire_target["hp"] = 100
	fire_target["combat_profile"]["resist_by_type"] = {"3":25}
	var fire_result := SkillResolutionRules.resolve(fire_caster,fire_target,fire_id,BattlePlayLoop.skill_fields(learned,fire_id),learned["skill_book"],learned["skill_target_data"],learned["equipment_items"],fire_caster["coord"],learned["map_size"],func(_n): return 0)
	check(fire_result.get("ok", false) and fire_result.get("receipt", {}).get("damage", 0) > 0 and fire_result.get("caster_changes", {}).get("mp", fire_caster["mp"]) < fire_caster["mp"],"learned Fire source magic resolves through native damage with MP payment")
	check(fire_result.get("receipt", {}).get("magic_key", "") == "fire" and fire_result.get("target_changes", {}).get("hp", fire_target["hp"]) < fire_target["hp"],"Fire source element reaches the target resistance path")
	var wind_id := "magic:magicAIR:magicCode02"
	var wind_caster := BattlePlayLoop.unit_ref(learned,"enemy026_1")
	wind_caster["actor_id"] = "026"
	wind_caster["growth_profile"]["job_code"] = 92
	wind_caster["level"] = 12
	wind_caster["mp"] = 30
	wind_caster["learned_skills"] = [{"policy":"source_growth_lifecycle_v1","actor_id":"026","job":92,"level":12,"attributes":{"str":1,"dex":1,"mind":1,"con":1},"trigger":"level_up","id":wind_id,"name":"空鳴破"}]
	var wind_target := BattlePlayLoop.unit_ref(learned,"leonard")
	wind_caster["coord"] = Vector2i(8,8)
	wind_target["coord"] = Vector2i(8,9)
	wind_target["hp"] = 100
	wind_target["combat_profile"]["resist_by_type"] = {"2":25}
	var wind_result := SkillResolutionRules.resolve(wind_caster,wind_target,wind_id,BattlePlayLoop.skill_fields(learned,wind_id),learned["skill_book"],learned["skill_target_data"],learned["equipment_items"],wind_caster["coord"],learned["map_size"],func(_n): return 0)
	check(wind_result.get("ok", false) and wind_result.get("receipt", {}).get("damage", 0) > 0 and wind_result.get("caster_changes", {}).get("mp", wind_caster["mp"]) < wind_caster["mp"],"learned Wind source magic resolves through native damage with MP payment")
	check(wind_result.get("receipt", {}).get("magic_key", "") == "wind" and wind_result.get("target_changes", {}).get("hp", wind_target["hp"]) < wind_target["hp"],"Wind source element reaches the target resistance path")
	var earth_two_id := "magic:magicEARTH:magicCode02"
	var earth_two_caster := BattlePlayLoop.unit_ref(learned,"enemy026_1")
	earth_two_caster["actor_id"] = "026"
	earth_two_caster["growth_profile"]["job_code"] = 98
	earth_two_caster["level"] = 12
	earth_two_caster["mp"] = 30
	earth_two_caster["learned_skills"] = [{"policy":"source_growth_lifecycle_v1","actor_id":"026","job":98,"level":12,"attributes":{"str":1,"dex":1,"mind":1,"con":1},"trigger":"level_up","id":earth_two_id,"name":"地龍震"}]
	var earth_two_target := BattlePlayLoop.unit_ref(learned,"leonard")
	earth_two_caster["coord"] = Vector2i(8,8)
	earth_two_target["coord"] = Vector2i(8,9)
	earth_two_target["hp"] = 100
	earth_two_target["combat_profile"]["resist_by_type"] = {"0":25}
	var earth_two_result := SkillResolutionRules.resolve(earth_two_caster,earth_two_target,earth_two_id,BattlePlayLoop.skill_fields(learned,earth_two_id),learned["skill_book"],learned["skill_target_data"],learned["equipment_items"],earth_two_caster["coord"],learned["map_size"],func(_n): return 0)
	check(earth_two_result.get("ok", false) and earth_two_result.get("receipt", {}).get("damage", 0) > 0 and earth_two_result.get("caster_changes", {}).get("mp", earth_two_caster["mp"]) < earth_two_caster["mp"],"learned Earth level-two magic resolves through native damage with MP payment")
	check(earth_two_result.get("receipt", {}).get("magic_key", "") == "earth" and earth_two_result.get("target_changes", {}).get("hp", earth_two_target["hp"]) < earth_two_target["hp"],"Earth level-two source element reaches the target resistance path")
	var bind_id := "magic:magicMIND:magicCode03"
	var bind_caster := BattlePlayLoop.unit_ref(learned,"enemy026_1")
	bind_caster["actor_id"] = "026"
	bind_caster["growth_profile"]["job_code"] = 85
	bind_caster["level"] = 25
	bind_caster["mp"] = 50
	bind_caster["learned_skills"] = [{"policy":"source_growth_lifecycle_v1","actor_id":"026","job":85,"level":25,"attributes":{"str":1,"dex":1,"mind":1,"con":1},"trigger":"level_up","id":bind_id,"name":"咒靈縛剎"}]
	var bind_target := BattlePlayLoop.unit_ref(learned,"leonard")
	bind_caster["coord"] = Vector2i(8,8)
	bind_target["coord"] = Vector2i(8,9)
	bind_target["hp"] = 100
	bind_target["combat_profile"]["resist_by_type"] = {"4":0}
	var bind_result := SkillResolutionRules.resolve(bind_caster,bind_target,bind_id,BattlePlayLoop.skill_fields(learned,bind_id),learned["skill_book"],learned["skill_target_data"],learned["equipment_items"],bind_caster["coord"],learned["map_size"],func(_n): return 0)
	var bind_effects: Array = bind_result.get("receipt", {}).get("status_effects", [])
	check(bind_result.get("ok", false) and bind_result.get("receipt", {}).get("damage", 0) > 0 and bind_result.get("caster_changes", {}).get("mp", bind_caster["mp"]) < bind_caster["mp"],"learned paralysis source magic resolves damage and MP payment")
	check(bind_effects.any(func(effect): return effect.get("status", "") == "paralysis" and effect.get("applied", false)) and bind_result.get("target_changes", {}).get("hp", bind_target["hp"]) < bind_target["hp"],"attack-plus-paralysis source function applies status after damage")


## 魂體衰竭 weaken status: flag 8, packed word, refresh through 0x448840, expiry 0x40b910, live
## attributes read by 0x409a60／0x409be0／0x40a7b0, PLAYERS no_weaken immunity.
func _weaken_status(learned: Dictionary) -> void:
	# Lane A: 魂體衰竭 (magic Weaken) introduces the 衰弱 status: flag 8, packed word, refresh.
	var weaken_id := "magic:magicMIND:magicCode04"
	var weaken_caster := BattlePlayLoop.unit_ref(learned,"enemy026_1")
	weaken_caster["actor_id"] = "026"
	weaken_caster["growth_profile"]["job_code"] = 98
	weaken_caster["level"] = 19
	weaken_caster["mp"] = 30
	weaken_caster["learned_skills"] = [{"policy":"source_growth_lifecycle_v1","actor_id":"026","job":98,"level":19,"attributes":{"str":1,"dex":1,"mind":1,"con":1},"trigger":"level_up","id":weaken_id,"name":"魂體衰竭"}]
	var weaken_target := BattlePlayLoop.unit_ref(learned,"leonard")
	weaken_caster["coord"] = Vector2i(8,8)
	weaken_target["coord"] = Vector2i(8,9)
	weaken_target["hp"] = 100
	weaken_target["combat_profile"]["resist_by_type"] = {"4":0}
	var weaken_before := weaken_target.duplicate(true)
	var weaken_result := SkillResolutionRules.resolve(weaken_caster,weaken_target,weaken_id,BattlePlayLoop.skill_fields(learned,weaken_id),learned["skill_book"],learned["skill_target_data"],learned["equipment_items"],weaken_caster["coord"],learned["map_size"],func(_n): return 0)
	var weaken_changes: Dictionary = weaken_result.get("target_changes", {})
	var weaken_word := int(weaken_changes.get("status_counters", {}).get("weaken", 0))
	check(weaken_result.get("ok", false) and weaken_result.get("receipt", {}).get("damage", -1) == 0 and weaken_result.get("caster_changes", {}).get("mp", 99) == 18,"learned 魂體衰竭 resolves without HP damage for one 12MP payment")
	check((int(weaken_changes.get("status_flags", 0)) & 8) != 0 and (weaken_word & 0xffff) == 2 and (weaken_word >> 16) in range(2, 16),"Weaken sets flag 8 with a 2-turn word and a 2..15 folded power")
	check(weaken_changes.get("combat_profile", {}).get("live_attack_damage", 999) <= weaken_before["combat_profile"]["live_attack_damage"] and weaken_changes.get("max_hp", 9999) <= weaken_before["max_hp"] and weaken_changes.has("live_speed"),"Weaken refreshes derived stats from the reduced attributes (0x448840)")
	var weakened_unit := weaken_target.duplicate(true)
	weakened_unit.merge(weaken_changes, true)
	check(SkillResolutionRules.Status.input_error(weakened_unit) == "" and SkillResolutionRules.Status.weakened(weakened_unit),"weakened unit stays a coherent status state")
	var weaken_tick := SkillResolutionRules.Status.after_action(weakened_unit)
	check(weaken_tick["ok"] and (int(weaken_tick["changes"]["status_counters"]["weaken"]) & 0xffff) == 1 and not weaken_tick["expired"].has("weaken"),"first action end decrements the weaken duration only")
	weakened_unit.merge(weaken_tick["changes"], true)
	weaken_tick = SkillResolutionRules.Status.after_action(weakened_unit)
	check(weaken_tick["ok"] and weaken_tick["expired"].has("weaken") and (int(weaken_tick["changes"]["status_flags"]) & 8) == 0 and not weaken_tick["changes"]["status_counters"].has("weaken"),"weaken expires after its last counted action (0x40b910) and clears flag 8")
	var cured := SkillResolutionRules.Status.cure_weaken(weakened_unit)
	check((int(cured["status_flags"]) & 8) == 0 and not cured["status_counters"].has("weaken"),"cure_weaken clears the whole word and flag 8")
	# Formulas read the live +0x4c..+0x58 attributes (base minus the active weaken power), not the base words.
	var weak_power := int(weakened_unit["status_counters"]["weaken"]) >> 16
	var weak_live := SkillResolutionRules.Combat.combat_profile_from_unit(weakened_unit)
	var weak_base: Dictionary = weakened_unit["combat_profile"]
	check(weak_power >= 2 and weak_live["str"] == maxi(1, int(weak_base["str"]) - weak_power) and weak_live["dex"] == maxi(1, int(weak_base["dex"]) - weak_power) and SkillResolutionRules.Combat.combat_profile_from_unit(weaken_before)["dex"] == int(weak_base["dex"]),"0x409a60／0x409be0 dex／str deltas read the weakened live attributes (0x448840 prologue)")
	var weak_special := SkillResolutionRules.Special.prepare(weakened_unit, weaken_caster, BattlePlayLoop.skill_fields(learned, "special:magicOTHER:magicCode01"), learned["skill_book"], learned["equipment_items"])
	check(weak_special["ok"] and weak_special["input"]["dex"] == maxi(1, int(weak_base["dex"]) - weak_power) and weak_special["input"]["mind"] == maxi(1, int(weak_base["mind"]) - weak_power) and weak_special["input"]["con"] == maxi(1, int(weak_base["con"]) - weak_power),"0x40a7b0 channel1 dex/3＋mind/4＋con/8 read the weakened live attributes")
	var weak_status := SkillResolutionRules.StatusApplication.prepare(weakened_unit, weaken_caster, BattlePlayLoop.skill_fields(learned, "magic:magicAIR:magicCode01"), learned["skill_book"], learned["skill_target_data"], learned["equipment_items"])
	check(weak_status["ok"] and weak_status["roll_input"]["mind"] == maxi(1, int(weak_base["mind"]) - weak_power) and weak_status["roll_input"]["magic_attack"] == int(weak_base["live_magic_attack"]),"0x40a7b0 channel0 mind term reads the weakened live attribute; magic attack stays the refreshed derived value")
	var immune_target := weaken_target.duplicate(true)
	immune_target["actor_id"] = "045"
	var immune_book: Dictionary = learned["skill_book"].duplicate(true)
	immune_book["actors"]["045"]["status_capability_flags"] = int(immune_book["actors"]["045"]["status_capability_flags"]) | 0x2000
	var immune_result := SkillResolutionRules.resolve(weaken_caster,immune_target,weaken_id,BattlePlayLoop.skill_fields(learned,weaken_id),immune_book,learned["skill_target_data"],learned["equipment_items"],weaken_caster["coord"],learned["map_size"],func(_n): return 0)
	check(immune_result.get("ok", false) and immune_result["receipt"]["status_effects"][0]["reason"] == "immune" and (int(immune_result["target_changes"]["status_flags"]) & 8) == 0,"PLAYERS no_weaken (0x2000 -> 0x2000000) makes an equipped target immune")


## Special-channel status skills (original_skill_function_bits): 弱體箭 Attack+Weaken, 影纏 Paralysis.
func _special_status(learned: Dictionary) -> void:
	# 弱體箭: special channel Attack+Weaken shares the status applicator with channel1 rolls.
	var arrow_id := "special:magicMIND:magicCode04"
	var arrow_caster := BattlePlayLoop.unit_ref(learned,"enemy026_1")
	arrow_caster["actor_id"] = "026"
	arrow_caster["growth_profile"]["job_code"] = 83
	arrow_caster["level"] = 10
	arrow_caster["stamina"] = 100
	for key in ["str", "dex", "mind", "con"]: arrow_caster["combat_profile"][key] = 60
	# Tier-2 job 83 records cannot exist yet; grant the source bit through the book copy instead.
	arrow_caster["learned_skills"] = []
	var arrow_book: Dictionary = learned["skill_book"].duplicate(true)
	arrow_book["actors"]["026"]["supported_initial_ids"].append(arrow_id)
	var arrow_target := BattlePlayLoop.unit_ref(learned,"leonard")
	arrow_caster["coord"] = Vector2i(8,8)
	arrow_target["coord"] = Vector2i(8,10)
	arrow_target["hp"] = 1000
	arrow_target["combat_profile"]["resist_by_type"] = {"4":0}
	var arrow_result := SkillResolutionRules.resolve_cast(arrow_caster,arrow_target,[arrow_caster,arrow_target],arrow_id,BattlePlayLoop.skill_fields(learned,arrow_id),arrow_book,learned["skill_target_data"],learned["equipment_items"],arrow_caster["coord"],learned["map_size"],func(_n): return 0,arrow_target["coord"])
	var arrow_effects: Array = arrow_result.get("receipt", {}).get("status_effects", [])
	var arrow_word := int(arrow_result.get("target_changes", {}).get("status_counters", {}).get("weaken", 0))
	check(arrow_result.get("ok", false) and arrow_result.get("receipt", {}).get("damage", 0) > 0 and arrow_result.get("caster_changes", {}).get("stamina", 100) == 80,"learned 弱體箭 deals special damage for one 20ST payment")
	check(arrow_effects.size() == 1 and arrow_effects[0]["status"] == "weaken" and arrow_effects[0]["applied"] and (arrow_word >> 16) in range(2, 16) and arrow_result["receipt"].get("special_key") == "special_status","Attack+Weaken special applies the folded 30% weaken magnitude after damage")
	# 影纏: pure paralysis through the special channel.
	var shadow_id := "special:magicOTHER:magicCode09"
	var shadow_caster := arrow_caster.duplicate(true)
	shadow_caster["growth_profile"]["job_code"] = 83
	shadow_caster["learned_skills"] = [{"policy":"source_growth_lifecycle_v1","actor_id":"026","job":83,"level":1,"attributes":{"str":28,"dex":24,"mind":12,"con":25},"trigger":"allocation","id":shadow_id,"name":"影纏"}]
	var shadow_target := BattlePlayLoop.unit_ref(learned,"leonard")
	shadow_target["coord"] = Vector2i(8,9)
	shadow_target["hp"] = 100
	var shadow_result := SkillResolutionRules.resolve(shadow_caster,shadow_target,shadow_id,BattlePlayLoop.skill_fields(learned,shadow_id),learned["skill_book"],learned["skill_target_data"],learned["equipment_items"],shadow_caster["coord"],learned["map_size"],func(_n): return 0)
	var shadow_effects: Array = shadow_result.get("receipt", {}).get("status_effects", [])
	check(shadow_result.get("ok", false) and shadow_result.get("receipt", {}).get("damage", -1) == 0 and shadow_result.get("caster_changes", {}).get("stamina", 100) == 60,"learned 影纏 costs 40ST and deals no HP damage")
	check(shadow_effects.size() == 1 and shadow_effects[0]["status"] == "paralysis" and shadow_effects[0]["applied"] and (int(shadow_result["target_changes"]["status_flags"]) & 4) != 0,"special Paralysis reuses the shared paralysis applicator")


## Support family: 聖靈祝福 cure bits (0x40aa80), 萬息集氣法／萬息降靈法／萬息臨界法 heal and HealMP
## with the 0x40b49e immediate and 0x40b866 tail experience conversions.
func _support_heal(learned: Dictionary) -> void:
	# Lane A support family: 聖靈祝福 cures four states in one cast (0x40aa80 cure bits).
	var bless_id := "magic:magicMIND:magicCode07"
	var bless_caster := BattlePlayLoop.unit_ref(learned,"enemy026_1")
	bless_caster["actor_id"] = "026"
	bless_caster["growth_profile"]["job_code"] = 85
	bless_caster["level"] = 39
	bless_caster["mp"] = 50
	bless_caster["learned_skills"] = [{"policy":"source_growth_lifecycle_v1","actor_id":"026","job":85,"level":39,"attributes":{"str":1,"dex":1,"mind":1,"con":1},"trigger":"level_up","id":bless_id,"name":"聖靈祝福"}]
	var bless_target := BattlePlayLoop.unit_ref(learned,"enemy021_1")
	bless_caster["coord"] = Vector2i(8,8)
	bless_target["coord"] = Vector2i(8,9)
	bless_target["status_flags"] = 1 | 4 | 8
	bless_target["status_counters"]["poison"] = (10 << 16) | 2
	bless_target["status_counters"]["paralysis"] = 2
	bless_target["status_counters"]["weaken"] = (5 << 16) | 2
	bless_target = SkillResolutionRules.StatMagic.Progression.refresh_growth_stats(bless_target, learned["equipment_items"])
	BattlePlayLoop.unit_ref(learned,"enemy021_1").merge(bless_target, true)
	var bless_before := bless_target.duplicate(true)
	var bless_result := SkillResolutionRules.resolve(bless_caster,bless_target,bless_id,BattlePlayLoop.skill_fields(learned,bless_id),learned["skill_book"],learned["skill_target_data"],learned["equipment_items"],bless_caster["coord"],learned["map_size"],no_rng)
	var bless_changes: Dictionary = bless_result.get("target_changes", {})
	var removed: Array = bless_result.get("receipt", {}).get("support_effects", []).filter(func(effect): return effect["removed"]).map(func(effect): return effect["status"])
	check(bless_result.get("ok", false) and bless_result.get("caster_changes", {}).get("mp", 99) == 30 and bless_result["receipt"].get("healing", -1) == 0,"learned 聖靈祝福 costs 20MP, heals nothing and consumes no RNG")
	check(removed == ["weaken", "paralysis", "poison"] and int(bless_changes.get("status_flags", -1)) == 0 and not bless_changes.get("status_counters", {}).has("weaken"),"the four cure bits clear every present state in native order and leave absent ones reported")
	check(bless_changes.get("combat_profile", {}).get("live_attack_damage", -1) >= bless_before["combat_profile"]["live_attack_damage"] and bless_changes.has("max_hp") and not bless_changes.has("mp"),"curing weaken refreshes derived stats without touching vitals")
	check(bless_result["receipt"]["native_contribution"] == (3 + 3 + 3) * 12,"each removed state contributes (turns+1)*12")
	var healthy := bless_target.duplicate(true)
	healthy.merge(bless_changes, true)
	check(SkillResolutionRules.resolve(bless_caster,healthy,bless_id,BattlePlayLoop.skill_fields(learned,bless_id),learned["skill_book"],learned["skill_target_data"],learned["equipment_items"],bless_caster["coord"],learned["map_size"],no_rng).get("reason", "") == "skill_has_no_effect","a target without any of the four states is refused before payment")
	# 萬息集氣法: special channel Heal, self-centered area, one ST payment for every ally inside.
	var gather_id := "special:magicWATER:magicCode02"
	var gather_caster := BattlePlayLoop.unit_ref(learned,"enemy026_1")
	gather_caster["growth_profile"]["job_code"] = 85
	gather_caster["level"] = 10
	gather_caster["stamina"] = 100
	for key in ["str", "dex", "mind", "con"]: gather_caster["combat_profile"][key] = 30
	gather_caster["learned_skills"] = [{"policy":"source_growth_lifecycle_v1","actor_id":"026","job":85,"level":1,"attributes":{"str":22,"dex":22,"mind":26,"con":16},"trigger":"allocation","id":gather_id,"name":"萬息集氣法"}]
	gather_caster["hp"] = int(gather_caster["max_hp"]) - 30
	var gather_ally := BattlePlayLoop.unit_ref(learned,"enemy021_1")
	gather_ally.merge(healthy, true)
	gather_ally["coord"] = Vector2i(9,8)
	gather_ally["hp"] = int(gather_ally["max_hp"]) - 10
	var gather_result := SkillResolutionRules.resolve_cast(gather_caster,gather_caster,[gather_caster,gather_ally,BattlePlayLoop.unit_ref(learned,"leonard")],gather_id,BattlePlayLoop.skill_fields(learned,gather_id),learned["skill_book"],learned["skill_target_data"],learned["equipment_items"],gather_caster["coord"],learned["map_size"],func(_n): return 0,gather_caster["coord"])
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
	var mana_result := SkillResolutionRules.resolve(mana_caster,mana_caster,mana_id,BattlePlayLoop.skill_fields(learned,mana_id),mana_book,learned["skill_target_data"],learned["equipment_items"],mana_caster["coord"],learned["map_size"],func(_n): return 0)
	check(mana_result.get("ok", false) and int(mana_result.get("receipt", {}).get("restored_mp", 0)) == 10 and int(mana_result["target_changes"]["mp"]) == int(mana_caster["max_mp"]) and mana_result["caster_changes"].get("stamina", 100) == 60,"learned 萬息降靈法 restores missing MP for 40ST")
	var full_mana := mana_caster.duplicate(true)
	full_mana["mp"] = full_mana["max_mp"]
	check(SkillResolutionRules.resolve(mana_caster,full_mana,mana_id,BattlePlayLoop.skill_fields(learned,mana_id),mana_book,learned["skill_target_data"],learned["equipment_items"],mana_caster["coord"],learned["map_size"],no_rng).get("reason", "") == "skill_has_no_effect","HealMP on a full-MP target is refused before RNG")
	# 萬息臨界法 (Heal+HealMP): 0x40b49e converts rand(level)+1 at once, 0x40b866 converts healing/2 at the tail.
	var critical_id := "special:magicWATER:magicCode04"
	var critical_caster := mana_caster.duplicate(true)
	critical_caster["hp"] = int(critical_caster["max_hp"]) - 30
	var critical_book: Dictionary = learned["skill_book"].duplicate(true)
	critical_book["actors"]["026"]["supported_initial_ids"].append(critical_id)
	var critical_result := SkillResolutionRules.resolve_cast(critical_caster,critical_caster,[critical_caster,BattlePlayLoop.unit_ref(learned,"leonard")],critical_id,BattlePlayLoop.skill_fields(learned,critical_id),critical_book,learned["skill_target_data"],learned["equipment_items"],critical_caster["coord"],learned["map_size"],func(_n): return 0,critical_caster["coord"])
	var critical_basis: Dictionary = critical_result.get("receipt", {}).get("experience_basis", {})
	var critical_immediate: Array = critical_basis.get("immediate_experience", [])
	check(critical_result.get("ok", false) and int(critical_result["receipt"]["healing"]) == 30 and int(critical_result["receipt"]["restored_mp"]) == 10,"learned 萬息臨界法 heals HP and MP in one cast")
	check(critical_result["receipt"].get("immediate_contributions") == [1] and int(critical_basis.get("contribution", -1)) == 15 and critical_immediate.size() == 1 and int(critical_immediate[0]["contribution"]) == 1 and int(critical_basis["points"]) == int(critical_basis["tail_points"]) + int(critical_immediate[0]["points"]) and int(critical_immediate[0]["points"]) > 0,"HealMP converts rand(level)+1 through 0x40a5d0 at once and the heal contribution again at the tail (0x40b49e / 0x40b866)")


## Stat family (千羽風靈壁 DefUp, 精神統一 DefUp+AttUp in native order) and 吸血劍 StealHP
## (0x40b7fe immediate, 0x40b866 tail).
func _stat_buffs_and_drain(learned: Dictionary) -> void:
	# Lane A stat family: 千羽風靈壁 (special DefUp on self) and 精神統一 (DefUp+AttUp in native order).
	var wall_id := "special:magicAIR:magicCode05"
	var wall_caster := BattlePlayLoop.unit_ref(learned,"enemy026_1")
	wall_caster["actor_id"] = "026"
	wall_caster["growth_profile"]["job_code"] = 92
	wall_caster["level"] = 10
	wall_caster["stamina"] = 100
	wall_caster["status_flags"] = 0
	wall_caster["status_counters"] = {"poison": 0, "paralysis": 0, "no_magic": 0}
	for key in ["str", "dex", "mind", "con"]: wall_caster["combat_profile"][key] = 30
	wall_caster["learned_skills"] = [{"policy":"source_growth_lifecycle_v1","actor_id":"026","job":92,"level":1,"attributes":{"str":29,"dex":28,"mind":22,"con":24},"trigger":"allocation","id":wall_id,"name":"千羽風靈壁"}]
	wall_caster["coord"] = Vector2i(8,8)
	var refreshed_wall := SkillResolutionRules.StatMagic.Progression.refresh_growth_stats(wall_caster, learned["equipment_items"])
	wall_caster.merge(refreshed_wall, true)
	var wall_before := wall_caster.duplicate(true)
	var wall_result := SkillResolutionRules.resolve_cast(wall_caster,wall_caster,[wall_caster,BattlePlayLoop.unit_ref(learned,"leonard")],wall_id,BattlePlayLoop.skill_fields(learned,wall_id),learned["skill_book"],learned["skill_target_data"],learned["equipment_items"],wall_caster["coord"],learned["map_size"],func(_n): return 0)
	var wall_effects: Array = wall_result.get("receipt", {}).get("stat_effects", [])
	check(wall_result.get("ok", false) and wall_result.get("caster_changes", {}).get("stamina", 100) == 60 and not wall_result["caster_changes"].has("mp"),"learned 千羽風靈壁 targets the caster for one 40ST payment")
	check(wall_effects.size() == 1 and wall_effects[0]["kind"] == "defense_up" and int(wall_result["target_changes"]["combat_profile"]["live_defense"]) > int(wall_before["combat_profile"]["live_defense"]) and wall_result["receipt"].get("special_key") == "special_stat","special DefUp raises live defense through the shared enhancement word")
	check(wall_result["receipt"]["native_stat_rolls"].size() == 2 and wall_result["receipt"]["sampled_durations"] == [2] and SkillResolutionRules.StatMagic.receipt_error(wall_result["receipt"], learned["skill_book"]) == "","special buff receipts replay through the checkpoint validator")
	var focus_id := "special:magicMIND:magicCode01"
	var focus_caster := wall_before.duplicate(true)
	focus_caster["growth_profile"]["job_code"] = 80
	focus_caster["learned_skills"] = []
	focus_caster = SkillResolutionRules.StatMagic.Progression.refresh_growth_stats(focus_caster, learned["equipment_items"])
	var focus_book: Dictionary = learned["skill_book"].duplicate(true)
	focus_book["actors"]["026"]["supported_initial_ids"].append(focus_id)
	var focus_result := SkillResolutionRules.resolve_cast(focus_caster,focus_caster,[focus_caster],focus_id,BattlePlayLoop.skill_fields(learned,focus_id),focus_book,learned["skill_target_data"],learned["equipment_items"],focus_caster["coord"],learned["map_size"],func(_n): return 0)
	var focus_effects: Array = focus_result.get("receipt", {}).get("stat_effects", [])
	check(focus_result.get("ok", false) and focus_effects.map(func(effect): return effect["kind"]) == ["defense_up", "attack_up"] and focus_result["receipt"]["native_stat_rolls"].size() == 4 and focus_result["receipt"]["sampled_durations"].size() == 2,"精神統一 applies DefUp then AttUp with their own rolls and durations")
	check(int(focus_result["target_changes"]["combat_profile"]["live_attack_damage"]) > int(focus_caster["combat_profile"]["live_attack_damage"]) and int(focus_result["target_changes"]["combat_profile"]["live_defense"]) > int(focus_caster["combat_profile"]["live_defense"]) and (int(focus_result["target_changes"]["status_flags"]) & 0x30) == 0x30,"both enhancement flags and derived values land in one refresh")
	# Lane A utility family: 吸血劍 drains the applied damage back to the caster.
	var drain_id := "special:magicOTHER:magicCode24"
	var drain_caster := BattlePlayLoop.unit_ref(learned,"enemy026_1")
	drain_caster["actor_id"] = "026"
	drain_caster["growth_profile"]["job_code"] = 98
	drain_caster["level"] = 10
	drain_caster["stamina"] = 100
	drain_caster["status_flags"] = 0
	drain_caster["status_counters"] = {"poison": 0, "paralysis": 0, "no_magic": 0}
	for key in ["str", "dex", "mind", "con"]: drain_caster["combat_profile"][key] = 40
	drain_caster["learned_skills"] = [{"policy":"source_growth_lifecycle_v1","actor_id":"026","job":98,"level":1,"attributes":{"str":30,"dex":30,"mind":34,"con":32},"trigger":"allocation","id":drain_id,"name":"吸血劍"}]
	drain_caster.merge(SkillResolutionRules.StatMagic.Progression.refresh_growth_stats(drain_caster, learned["equipment_items"]), true)
	drain_caster["hp"] = int(drain_caster["max_hp"]) - 20
	var drain_target := BattlePlayLoop.unit_ref(learned,"leonard")
	drain_caster["coord"] = Vector2i(8,8)
	drain_target["coord"] = Vector2i(8,10)
	drain_target["hp"] = 1000
	var drain_result := SkillResolutionRules.resolve_cast(drain_caster,drain_target,[drain_caster,drain_target],drain_id,BattlePlayLoop.skill_fields(learned,drain_id),learned["skill_book"],learned["skill_target_data"],learned["equipment_items"],drain_caster["coord"],learned["map_size"],func(_n): return 0,drain_target["coord"])
	var drained := int(drain_result.get("receipt", {}).get("damage", 0))
	check(drain_result.get("ok", false) and drained > 0 and drain_result["caster_changes"].get("stamina", 100) == 60,"learned 吸血劍 deals channel1 damage for one 40ST payment")
	check(int(drain_result["caster_changes"].get("hp", 0)) == mini(int(drain_caster["max_hp"]), int(drain_caster["hp"]) + drained) and int(drain_result["receipt"]["stolen_hp"]) == mini(20, drained) and drain_result["receipt"]["native_contribution"] == drained,"StealHP returns the applied damage to the caster, capped at max HP, and keeps the damage as the tail contribution")
	var drain_basis: Dictionary = drain_result.get("receipt", {}).get("experience_basis", {})
	var drain_immediate: Array = drain_basis.get("immediate_experience", [])
	check(drain_result["receipt"].get("immediate_contributions") == [drained * 20 / 100] and drain_immediate.size() == 1 and int(drain_immediate[0]["contribution"]) == drained * 20 / 100 and int(drain_basis.get("contribution", -1)) == drained and int(drain_basis["points"]) == int(drain_basis["tail_points"]) + int(drain_immediate[0]["points"]),"StealHP converts damage*20/100 at once (0x40b7fe) and the damage again at the tail (0x40b866)")


## Turn effects: 獅子吼 CancelActive (0x407550), 天鳴覺醒 reactivate (0x4075a0), 0x4074a0 second pass.
func _turn_effects() -> void:
	# 獅子吼 cancels the target's pending slot through the public player path; 天鳴覺醒 re-enables an acted ally.
	var roar_id := "special:magicOTHER:magicCode20"
	var roar := controlled()
	var roar_actor: String = BattlePlayLoop.unit(roar,"leonard")["actor_id"]
	own(roar, "skill_book")["actors"][roar_actor]["supported_initial_ids"].append(roar_id)
	var roar_target := BattlePlayLoop.unit_ref(roar,"enemy021_1")
	roar_target["coord"] = BattlePlayLoop.unit(roar,"leonard")["coord"] + Vector2i(0,2)
	roar = BattlePlayLoop.choose_command(roar,"special")
	roar = BattlePlayLoop.choose_special(roar, roar_id)
	check(roar["interaction"] == "attack_select" and roar["selected_skill_id"] == roar_id,"a second owned special is selectable from the special list")
	var pending_before: int = roar["turn_queue"]["slots"].filter(func(slot): return slot["id"] == "enemy021_1" and slot["enabled"]).size()
	var roared := BattlePlayLoop.attack_target(roar,"enemy021_1",func(_n): return 0)
	var roar_effects: Array = roared.get("last_attack", {}).get("turn_effects", [])
	check(pending_before == 1 and roar_effects.size() == 1 and roar_effects[0]["kind"] == "cancel_pending" and roar_effects[0]["applied"] and BattlePlayLoop.unit(roared,"leonard")["stamina"] == 0,"獅子吼 pays 20ST and cancels the target's future slot via 0x407550")
	check(roared["turn_queue"]["slots"].filter(func(slot): return slot["id"] == "enemy021_1" and slot["enabled"]).is_empty() and BattlePlayLoop.unit(roared,"enemy021_1")["hp"] == roar_target["hp"],"the cancelled slot stays in the queue as disabled and no damage is dealt")
	check(BattlePlayLoop.attack_target(roar,"enemy023_1",no_rng)["last_attack_reject"].get("reason","") in ["not_enemy","out_of_range"],"a non-enemy is not a CancelActive target")
	var wake_id := "special:magicMIND:magicCode02"
	var wake := controlled()
	BattlePlayLoop.unit_ref(wake,"enemy023_1")["live_speed"] = 101
	wake["turn_queue"] = BattlePlayLoop.CoreTurnQueue.rebuild(wake["units"])
	wake["turn_queue"]["index"] = 1 # enemy023_1 (player-controlled ally) already acted; leonard is current
	wake = BattlePlayLoop.select_player_unit(wake,"leonard")
	BattlePlayLoop.unit_ref(wake,"leonard")["stamina"] = 60
	own(wake, "skill_book")["actors"][roar_actor]["supported_initial_ids"].append(wake_id)
	BattlePlayLoop.unit_ref(wake,"enemy023_1")["coord"] = BattlePlayLoop.unit(wake,"leonard")["coord"] + Vector2i(1,0)
	wake = BattlePlayLoop.choose_special(BattlePlayLoop.choose_command(wake,"special"), wake_id)
	var woken := BattlePlayLoop.attack_coord(wake, BattlePlayLoop.unit(wake,"enemy023_1")["coord"], func(_n): return 0)
	var wake_effects: Array = woken.get("last_attack", {}).get("turn_effects", [])
	check(wake_effects.size() == 1 and wake_effects[0]["kind"] == "reactivate" and wake_effects[0]["applied"] and int(wake_effects[0]["slot_index"]) == 0 and BattlePlayLoop.unit(woken,"leonard")["stamina"] == 0,"天鳴覺醒 re-enables the acted ally's consumed slot via 0x4075a0 for 60ST")
	check(woken["turn_queue"]["slots"][0].get("reactivated", false) and woken["turn_queue"]["index"] == 1,"reactivation marks the earlier slot without moving the current actor")
	var untouched := controlled()
	own(untouched, "skill_book")["actors"][roar_actor]["supported_initial_ids"].append(wake_id)
	BattlePlayLoop.unit_ref(untouched,"leonard")["stamina"] = 60
	BattlePlayLoop.unit_ref(untouched,"enemy023_1")["coord"] = BattlePlayLoop.unit(untouched,"leonard")["coord"] + Vector2i(1,0)
	untouched = BattlePlayLoop.choose_special(BattlePlayLoop.choose_command(untouched,"special"), wake_id)
	check(BattlePlayLoop.attack_coord(untouched, BattlePlayLoop.unit(untouched,"enemy023_1")["coord"], no_rng)["last_attack_reject"].get("reason","") == "skill_has_no_effect","an ally that has not acted yet is refused before payment (0x4075a0 would return 0)")
	# 0x4074a0 second pass: the re-enabled slot is served before the round rebuilds.
	var queue := BattlePlayLoop.CoreTurnQueue.rebuild([{"id":"a","live_speed":3},{"id":"b","live_speed":2},{"id":"c","live_speed":1}])
	queue["index"] = 1
	queue = BattlePlayLoop.CoreTurnQueue.reactivate_consumed(queue,"a")["queue"]
	var passed := BattlePlayLoop.CoreTurnQueue.end_turn(queue)
	check(passed["index"] == 2 and BattlePlayLoop.CoreTurnQueue.current(passed)["id"] == "c","forward slots are still served first")
	var second := BattlePlayLoop.CoreTurnQueue.end_turn(passed)
	check(second["index"] == 0 and second["round"] == 0 and BattlePlayLoop.CoreTurnQueue.current(second)["id"] == "a" and second["slots"][1]["consumed"] and second["slots"][2]["consumed"],"the second pass returns to the re-enabled slot with every other slot consumed")
	var rebuilt := BattlePlayLoop.CoreTurnQueue.end_turn(second)
	check(rebuilt["round"] == 1 and rebuilt["index"] == 0 and BattlePlayLoop.CoreTurnQueue.current(rebuilt)["id"] == "a" and not rebuilt["slots"][0].has("consumed"),"after the re-enabled slot the round rebuilds normally")


## 竊殺 by a registered player: capped by the target record +0x98 (0x40b548, 0x40e390, 0x42bd50,
## 0x442720 state 2).
func _steal_gold_player() -> void:
	var roar_actor := _leonard_actor()
	# 竊殺: Attack+StealGold — party casters add capped carried gold, enemy casters drain party gold.
	var steal_id := "special:magicOTHER:magicCode13"
	var steal := controlled()
	own(steal, "skill_book")["actors"][roar_actor]["supported_initial_ids"].append(steal_id)
	var steal_target := BattlePlayLoop.unit_ref(steal,"enemy021_1")
	steal_target["coord"] = BattlePlayLoop.unit(steal,"leonard")["coord"] + Vector2i(0,2)
	steal_target["hp"] = 1000
	var target_gold: int = int(steal["reward_data"]["actors"][str(steal_target["actor_id"])]["gold"])
	steal = BattlePlayLoop.choose_special(BattlePlayLoop.choose_command(steal,"special"), steal_id)
	var stolen := BattlePlayLoop.attack_target(steal,"enemy021_1",func(_n): return 0)
	var gold_effects: Array = stolen.get("last_attack", {}).get("gold_effects", [])
	check(gold_effects.size() == 1 and gold_effects[0]["from"] == "target_carry" and int(gold_effects[0]["amount"]) == mini(31, target_gold) and int(stolen["gold"]) == int(steal["gold"]) + int(gold_effects[0]["amount"]),"竊殺 by a registered player adds rand-free low+1 gold capped by the target's carried gold")
	check(int(stolen["last_attack"]["damage"]) > 0 and BattlePlayLoop.unit(stolen,"leonard")["stamina"] == 0 and int(stolen["last_attack"]["experience_basis"]["direct_experience"]) == int(gold_effects[0]["amount"]) / 2,"the Attack bit still deals damage, one 20ST payment, and StealGold EXP is added directly")
	# 0x40b548 caps a registered player's steal by the target record +0x98, the same live word kill gold
	# 0x40e390 returns; 0x42bd50 word 0 writes the EVEF instance gold over it after the template copy.
	# A synthetic override below the rand-free amount (31) and the 021 template makes the two readings differ.
	var carried := controlled()
	own(carried, "skill_book")["actors"][roar_actor]["supported_initial_ids"].append(steal_id)
	var carried_target := BattlePlayLoop.unit_ref(carried,"enemy021_1")
	carried_target["coord"] = BattlePlayLoop.unit(carried,"leonard")["coord"] + Vector2i(0,2)
	carried_target["hp"] = 1000
	carried_target["evef_instance"] = {"evidence_tier": "resource-derived", "record_index": 17, "overrides": {"gold": 7}}
	var live_gold: int = BattlePlayLoop.RewardRules.carried_gold(carried_target, target_gold)
	check(target_gold > 7 and live_gold == 7 and live_gold == BattlePlayLoop.RewardRules.kill_gold(carried_target, target_gold),"the live +0x98 word takes the EVEF instance gold over the 021 template")
	carried = BattlePlayLoop.choose_special(BattlePlayLoop.choose_command(carried,"special"), steal_id)
	var carried_effects: Array = BattlePlayLoop.attack_target(carried,"enemy021_1",func(_n): return 0).get("last_attack", {}).get("gold_effects", [])
	check(carried_effects.size() == 1 and carried_effects[0]["from"] == "target_carry" and int(carried_effects[0]["amount"]) == live_gold,"竊殺 caps by the same live +0x98 the kill gold reads (EVEF instance override), not the PLAYERS template: " + str(carried_effects))
	# Enemy A killing controlled B adds B's kill gold to A's record +0x98 (0x442720 state 2,
	# 0x442856..0x442875), so the same cap then reads instance 7 + B's 12 = 19 (< the rand-free 31).
	var grown := controlled()
	own(grown, "skill_book")["actors"][roar_actor]["supported_initial_ids"].append(steal_id)
	var grown_target := BattlePlayLoop.unit_ref(grown,"enemy021_1")
	grown_target["coord"] = BattlePlayLoop.unit(grown,"leonard")["coord"] + Vector2i(0,2)
	grown_target["hp"] = 1000
	grown_target["evef_instance"] = {"evidence_tier": "resource-derived", "record_index": 17, "overrides": {"gold": 7}}
	var fallen := BattlePlayLoop.unit_ref(grown,"enemy023_1")
	fallen["coord"] = grown_target["coord"] + Vector2i(1,0)
	fallen["hp"] = 1
	fallen["combat_profile"]["live_defense"] = 0
	fallen["evef_instance"] = {"evidence_tier": "resource-derived", "record_index": 18, "overrides": {"gold": 12}}
	BattleLoopCombat.resolve_exchange(grown,"enemy021_1","enemy023_1",func(_n): return 0)
	check(BattlePlayLoop.unit(grown,"enemy023_1")["defeated"] and int(BattlePlayLoop.unit(grown,"enemy021_1").get(BattlePlayLoop.RewardRules.CARRIED_GAINED,0)) == 12 and int(grown["gold"]) == 0,"enemy A's kill of controlled B keeps B's kill gold 12 on A, not the party")
	grown = BattlePlayLoop.choose_special(BattlePlayLoop.choose_command(grown,"special"), steal_id)
	var grown_effects: Array = BattlePlayLoop.attack_target(grown,"enemy021_1",func(_n): return 0).get("last_attack", {}).get("gold_effects", [])
	check(grown_effects.size() == 1 and grown_effects[0]["from"] == "target_carry" and int(grown_effects[0]["amount"]) == 7 + 12,"竊殺 against A caps at its instance gold + B's kill gold: " + str(grown_effects))


## Enemy StealGold drains party gold into its own +0x98 (0x40b568, 0x4416bc); 銀之手 initial grant;
## PLAYERS steal_ratio words summed by the 0x4348f0 job-up.
func _steal_gold_enemy(learned: Dictionary) -> void:
	var steal_id := "special:magicOTHER:magicCode13"
	var thief := BattlePlayLoop.unit_ref(learned,"enemy026_1")
	thief["actor_id"] = "026"
	thief["growth_profile"]["job_code"] = 88
	thief["level"] = 10
	thief["stamina"] = 100
	thief["learned_skills"] = []
	thief.merge(SkillResolutionRules.StatMagic.Progression.refresh_growth_stats(thief, learned["equipment_items"]), true)
	var thief_book: Dictionary = learned["skill_book"].duplicate(true)
	thief_book["actors"]["026"]["supported_initial_ids"].append(steal_id)
	var victim := BattlePlayLoop.unit_ref(learned,"leonard")
	thief["coord"] = Vector2i(8,8)
	victim["coord"] = Vector2i(8,10)
	victim["hp"] = 1000
	var party_context := {"turn_queue": learned["turn_queue"], "gold": 12, "reward_data": learned["reward_data"]}
	var party_drain := SkillResolutionRules.resolve_cast(thief,victim,[thief,victim],steal_id,BattlePlayLoop.skill_fields(learned,steal_id),thief_book,learned["skill_target_data"],learned["equipment_items"],thief["coord"],learned["map_size"],func(_n): return 0,victim["coord"],party_context)
	var drain_effects: Array = party_drain.get("gold_effects", [])
	check(party_drain.get("ok", false) and drain_effects.size() == 1 and drain_effects[0]["from"] == "party" and int(drain_effects[0]["amount"]) == 12,"an enemy thief drains the party gold, capped by what the party holds")
	# The drained take also goes into 0x4c2c84 (0x40b568..0x40b572), which 0x4416bc pays the caster
	# through 0x442720 state 2: an enemy caster keeps it on its own record +0x98.
	var robbed := controlled()
	var robber := BattlePlayLoop.unit_ref(robbed,"enemy026_1")
	robber["actor_id"] = "026"
	robber["growth_profile"]["job_code"] = 88
	robber["level"] = 10
	robber["stamina"] = 100
	robber["learned_skills"] = []
	robber.merge(SkillResolutionRules.StatMagic.Progression.refresh_growth_stats(robber, robbed["equipment_items"]), true)
	own(robbed, "skill_book")["actors"]["026"]["supported_initial_ids"].append(steal_id)
	var robbed_leonard := BattlePlayLoop.unit_ref(robbed,"leonard")
	robbed_leonard["hp"] = 1000
	robber["coord"] = robbed_leonard["coord"] + Vector2i(0,2)
	robbed["gold"] = 12
	var robbery := BattleLoopCombat.resolve_skill(robbed,"enemy026_1","leonard",steal_id,BattlePlayLoop.skill_fields(robbed,steal_id),robber["coord"],func(_n): return 0,robbed_leonard["coord"])
	var robbery_effects: Array = robbery.get("gold_effects", [])
	check(robbery_effects.size() == 1 and robbery_effects[0]["from"] == "party" and int(robbed["gold"]) == 0 and int(BattlePlayLoop.unit(robbed,"enemy026_1").get(BattlePlayLoop.RewardRules.CARRIED_GAINED,0)) == 12 and robbery_effects[0].get("carried_by","") == "enemy026_1","an enemy thief keeps the drained 12 on its own record +0x98: " + str(robbery_effects))
	var robber_gold: int = BattlePlayLoop.RewardRules.kill_gold(BattlePlayLoop.unit(robbed,"enemy026_1"), int(robbed["reward_data"]["actors"]["026"]["gold"]))
	BattlePlayLoop.unit_ref(robbed,"enemy026_1")["hp"] = 1
	BattlePlayLoop.unit_ref(robbed,"enemy026_1")["stamina"] = 0 # the synthetic 100ST is outside 026's stamina domain for an exchange
	BattleLoopCombat.resolve_exchange(robbed,"leonard","enemy026_1",func(_n): return 0)
	check(BattlePlayLoop.unit(robbed,"enemy026_1")["defeated"] and int(robbed["gold"]) == robber_gold + 12,"killing the thief pays its template gold + the gold it stole: " + str(robbed["gold"]))
	# 銀之手: 漢克斯 004's PLAYERS special_other declaration grants the pure StealGold row initially.
	var silver_id := "special:magicOTHER:magicCode10"
	check(learned["skill_book"]["actors"]["004"]["supported_initial_ids"].has(silver_id),"004 receives 銀之手 from its source special_other declaration")
	var hanks := thief.duplicate(true)
	victim["coord"] = Vector2i(8,9)
	hanks["actor_id"] = "004"
	hanks["stamina"] = 100
	check(SkillResolutionRules.ownership_error(hanks, silver_id, learned["skill_book"]) == "","004 owns 銀之手 without a learning record")
	var silver := SkillResolutionRules.resolve_cast(hanks,victim,[hanks,victim],silver_id,BattlePlayLoop.skill_fields(learned,silver_id),learned["skill_book"],learned["skill_target_data"],learned["equipment_items"],hanks["coord"],learned["map_size"],func(_n): return 0,victim["coord"],party_context)
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
	var upped_refresh := BattlePlayLoop.ProgressionRules.refresh_growth_stats(upped["actor"], learned["equipment_items"])
	check(BattlePlayLoop.ProgressionRules.refresh_input_error(upped["actor"], learned["equipment_items"]) == "" and int(upped_refresh["combat_profile"]["steal_ratio"]) == 50,"after the job-up the refresh writes +0x196 = 50 (nonzero word, no default)")


## 金之手 StealItem: 0x40b5a8 threshold rand(100)+1 < get_ratio+10+steal_ratio (original_steal_ratio.json),
## 0x436e80 slot shift, 0x40b674 immediate experience, 0x448840 default 12 and add_steal_ratio gear.
func _steal_item() -> void:
	var roar_actor := _leonard_actor()
	# 金之手: StealItem walks the target's slots and moves the first passing item into the shared pending loot.
	var hand_id := "special:magicOTHER:magicCode12"
	var hand := controlled()
	own(hand, "skill_book")["actors"][roar_actor]["supported_initial_ids"].append(hand_id)
	BattlePlayLoop.unit_ref(hand,"leonard")["stamina"] = 60
	var hand_target := BattlePlayLoop.unit_ref(hand,"enemy021_1")
	hand_target["coord"] = BattlePlayLoop.unit(hand,"leonard")["coord"] + Vector2i(1,0)
	var loot_code := int(210)
	hand_target["inventory"] = [loot_code, 0, 0, 0, 0, 0, 0, 0]
	hand = BattlePlayLoop.choose_special(BattlePlayLoop.choose_command(hand,"special"), hand_id)
	var pickpocketed := BattlePlayLoop.attack_target(hand,"enemy021_1",func(_n): return 0)
	var stolen_items: Array = pickpocketed.get("last_attack", {}).get("stolen_items", [])
	check(stolen_items.size() == 1 and int(stolen_items[0]["code"]) == loot_code and int(stolen_items[0]["source_slot"]) == 0 and BattlePlayLoop.unit(pickpocketed,"leonard")["stamina"] == 0,"金之手 pays 60ST and steals the first slot when rand(100)+1 < get_ratio+10")
	check(BattlePlayLoop.unit(pickpocketed,"enemy021_1")["inventory"] == [0, 0, 0, 0, 0, 0, 0, 0] and int(pickpocketed["last_attack"]["damage"]) == 0 and BattlePlayLoop.unit(pickpocketed,"enemy021_1")["hp"] == hand_target["hp"],"the stolen slot shifts out of the target (0x436e80) without damage")
	var hand_basis: Dictionary = pickpocketed.get("last_attack", {}).get("experience_basis", {})
	var hand_immediate: Array = hand_basis.get("immediate_experience", [])
	check(pickpocketed["last_attack"].get("immediate_contributions") == [1] and int(hand_basis.get("contribution", -1)) == int(pickpocketed["last_attack"]["native_damage_roll"]["value"]) and hand_immediate.size() == 1 and int(hand_basis["points"]) == int(hand_basis["tail_points"]) + int(hand_immediate[0]["points"]) and int(pickpocketed["last_attack"]["experience_settlement"]["base"]) == int(hand_basis["points"]),"StealItem converts rand(level)+1 at once (0x40b674) and the proc0 value at the tail (0x40b866); the settlement awards both")
	var pending: Array = pickpocketed.get("settlement", {}).get("pending", [])
	check(BattlePlayLoop.loot_waiting(pickpocketed) and pending.size() == 1 and int(pending[0]["code"]) == loot_code and pending[0]["source_id"] == "enemy021_1" and str(pending[0]["id"]).ends_with(":stolen"),"the stolen item enters the shared claim collection (0x44f2d0 path)")
	# 0x40b5a8 threshold: rand(100)+1 < get_ratio + 10 + caster +0x196, where +0x196 is the PLAYERS steal_ratio
	# word (12 when 0, 0x448840) plus every equipped add_steal_ratio (0x448420). 210 黃金首飾 get_ratio 60.
	var recorded: Array = []
	BattlePlayLoop.attack_target(hand,"enemy021_1",func(bound): recorded.append(int(bound)); return 0)
	var steal_call := recorded.rfind(100)
	check(steal_call > 0 and recorded.count(100) == 2 and int(recorded[steal_call + 1]) == int(BattlePlayLoop.unit(hand,"leonard")["level"]),"the steal draw is the second rand(100) (after the hit check), followed by the rand(level)+1 immediate conversion")
	var at_call := func(index: int, value: int) -> Callable:
		var calls: Array = [0]
		return func(bound):
			var current: int = calls[0]
			calls[0] = current + 1
			return clampi(value, 0, int(bound) - 1) if current == index else 0
	check(int(BattlePlayLoop.unit(hand,"leonard")["combat_profile"]["steal_ratio"]) == 12 and int(BattlePlayLoop.unit(hand,"leonard")["combat_profile"]["base_steal_ratio"]) == 0,"001 declares no steal_ratio, so the +0x196 work value is the 0x448840 default 12")
	var edge := BattlePlayLoop.attack_target(hand,"enemy021_1",at_call.call(steal_call, 80))
	check(edge["last_attack"]["stolen_items"].size() == 1 and int(edge["last_attack"]["stolen_items"][0]["steal_roll"]) == 81,"draw 81 < 60+10+12 still steals")
	var missed := BattlePlayLoop.attack_target(hand,"enemy021_1",at_call.call(steal_call, 81))
	check(missed["last_attack"]["stolen_items"].is_empty() and BattlePlayLoop.unit(missed,"enemy021_1")["inventory"][0] == loot_code and BattlePlayLoop.unit(missed,"leonard")["stamina"] == 0,"draw 82 fails the default threshold: the item stays and the 60ST is still spent")
	var thief_hand := hand.duplicate(true)
	var thief_leonard := BattlePlayLoop.unit_ref(thief_hand,"leonard")
	thief_leonard["combat_profile"]["base_steal_ratio"] = 30  # 004 漢克斯's PLAYERS word
	thief_leonard.merge(BattlePlayLoop.ProgressionRules.refresh_growth_stats(thief_leonard,thief_hand["equipment_items"]),true)
	check(int(thief_leonard["combat_profile"]["steal_ratio"]) == 30,"a nonzero steal_ratio word replaces the default 12 in the refresh")
	var bonus := BattlePlayLoop.attack_target(thief_hand,"enemy021_1",at_call.call(steal_call, 98))
	check(bonus["last_attack"]["stolen_items"].size() == 1 and int(bonus["last_attack"]["stolen_items"][0]["steal_roll"]) == 99,"draw 99 < 60+10+30 steals with the 漢克斯 word")
	check(BattlePlayLoop.attack_target(thief_hand,"enemy021_1",at_call.call(steal_call, 99))["last_attack"]["stolen_items"].is_empty(),"draw 100 fails even the 漢克斯 threshold")
	var cloaked := hand.duplicate(true)
	var cloaked_leonard := BattlePlayLoop.unit_ref(cloaked,"leonard")
	cloaked_leonard["equipment"] = cloaked_leonard["equipment"].filter(func(entry): return entry["slot"] != "armor") + [{"slot":"armor","item_code":131,"name":"隱忍黑衣"}]
	var cloak_delta := BattlePlayLoop.EquipmentRules.effect_delta(cloaked_leonard["equipment"],cloaked["equipment_items"])
	check(cloak_delta["ok"] and int(cloak_delta["delta"]["steal_ratio"]) == 20,"131 隱忍黑衣 add_steal_ratio 20 is a supported equipment effect (item +0x40)")
	cloaked_leonard.merge(BattlePlayLoop.ProgressionRules.refresh_growth_stats(cloaked_leonard,cloaked["equipment_items"]),true)
	check(int(cloaked_leonard["combat_profile"]["steal_ratio"]) == 32,"the work value is the default 12 plus the equipped 20")


## StealItem slot walk (0x40b5e1..0x40b5e5): ends at the first empty slot.
func _steal_item_slot_walk() -> void:
	var roar_actor := _leonard_actor()
	var hand_id := "special:magicOTHER:magicCode12"
	var loot_code := 210
	var empty_handed := controlled()
	own(empty_handed, "skill_book")["actors"][roar_actor]["supported_initial_ids"].append(hand_id)
	BattlePlayLoop.unit_ref(empty_handed,"leonard")["stamina"] = 60
	BattlePlayLoop.unit_ref(empty_handed,"enemy021_1")["coord"] = BattlePlayLoop.unit(empty_handed,"leonard")["coord"] + Vector2i(1,0)
	BattlePlayLoop.unit_ref(empty_handed,"enemy021_1")["inventory"] = [0, 0, 0, 0, 0, 0, 0, 0]
	empty_handed = BattlePlayLoop.choose_special(BattlePlayLoop.choose_command(empty_handed,"special"), hand_id)
	check(BattlePlayLoop.attack_target(empty_handed,"enemy021_1",no_rng)["last_attack_reject"].get("reason","") == "skill_has_no_effect","a target with nothing to steal is refused before payment")
	# 0x40b5e1..0x40b5e5 (native receipt original_steal_ratio.json): the slot walk ends at the first empty slot,
	# so an item behind a hole is never rolled and a target whose first slot is empty has nothing to steal.
	var holed := controlled()
	own(holed, "skill_book")["actors"][roar_actor]["supported_initial_ids"].append(hand_id)
	BattlePlayLoop.unit_ref(holed,"leonard")["stamina"] = 60
	BattlePlayLoop.unit_ref(holed,"enemy021_1")["coord"] = BattlePlayLoop.unit(holed,"leonard")["coord"] + Vector2i(1,0)
	BattlePlayLoop.unit_ref(holed,"enemy021_1")["inventory"] = [0, loot_code, 0, 0, 0, 0, 0, 0]
	holed = BattlePlayLoop.choose_special(BattlePlayLoop.choose_command(holed,"special"), hand_id)
	check(BattlePlayLoop.attack_target(holed,"enemy021_1",no_rng)["last_attack_reject"].get("reason","") == "skill_has_no_effect","an item behind an empty first slot is out of the native walk's reach, so the use is refused like an empty inventory")
	var behind_hole := controlled()
	own(behind_hole, "skill_book")["actors"][roar_actor]["supported_initial_ids"].append(hand_id)
	BattlePlayLoop.unit_ref(behind_hole,"leonard")["stamina"] = 60
	BattlePlayLoop.unit_ref(behind_hole,"enemy021_1")["coord"] = BattlePlayLoop.unit(behind_hole,"leonard")["coord"] + Vector2i(1,0)
	BattlePlayLoop.unit_ref(behind_hole,"enemy021_1")["inventory"] = [loot_code, 0, loot_code, 0, 0, 0, 0, 0]
	behind_hole = BattlePlayLoop.choose_special(BattlePlayLoop.choose_command(behind_hole,"special"), hand_id)
	var hole_recorded: Array = []
	var hole_stop := BattlePlayLoop.attack_target(behind_hole,"enemy021_1",func(n): hole_recorded.append(n); return 81 if n == 100 and hole_recorded.count(100) == 2 else 0)
	check(hole_stop["last_attack"]["stolen_items"].is_empty() and hole_recorded.count(100) == 2 and BattlePlayLoop.unit(hole_stop,"enemy021_1")["inventory"] == [loot_code, 0, loot_code, 0, 0, 0, 0, 0],"a failed first slot followed by an empty slot ends the walk: the item behind the hole gets no roll (one steal rand(100) after the hit check)")


## Unowned source rows 獅子吼2／吸血劍2／金之手LV2 keep their base skill's utility policy (resource-derived).
func _unowned_twin_rows(learned: Dictionary) -> void:
	var roar_actor := _leonard_actor()
	var roar_id := "special:magicOTHER:magicCode20"
	var drain_id := "special:magicOTHER:magicCode24"
	var hand_id := "special:magicOTHER:magicCode12"
	# Wave 9 lane A2: the unowned source rows 獅子吼2／吸血劍2／金之手LV2 keep their base skill's utility
	# policy. No PLAYERS field, learning table or source template references them (resource-derived);
	# they only have to resolve as data through the same transaction. [id, base id]
	for pair in [["special:magicOTHER:magicCode32", roar_id], ["special:magicOTHER2:magicCode03", drain_id], ["special:magicOTHER:magicCode14", hand_id]]:
		var twin_id: String = pair[0]
		var twin: Dictionary = learned["skill_book"]["skills"][twin_id]
		var base: Dictionary = learned["skill_book"]["skills"][pair[1]]
		check(twin["damage_policy"] == base["damage_policy"] and (twin["name"] == base["name"] or twin["name"] == "高級金之手") and twin["fields"]["function"] == base["fields"]["function"],"the 2/LV2 row shares its base skill's function and policy (and name, except 高級金之手 RESOURCE 264): " + twin_id)
		check(learned["skill_book"]["actors"].values().all(func(actor): return not actor["supported_initial_ids"].has(twin_id)) and SkillResolutionRules.descriptor_error(twin_id, twin["fields"], learned["skill_book"], learned["skill_target_data"]) == "","no source actor holds the row, yet its descriptor passes the shared gate: " + twin_id)
		var twin_loop := controlled()
		own(twin_loop, "skill_book")["actors"][roar_actor]["supported_initial_ids"].append(twin_id)
		BattlePlayLoop.unit_ref(twin_loop,"leonard")["stamina"] = 60
		var twin_target := BattlePlayLoop.unit_ref(twin_loop,"enemy021_1")
		twin_target["coord"] = BattlePlayLoop.unit(twin_loop,"leonard")["coord"] + Vector2i(1,0)
		twin_target["hp"] = 1000
		twin_target["inventory"] = [210, 0, 0, 0, 0, 0, 0, 0]
		twin_loop = BattlePlayLoop.choose_special(BattlePlayLoop.choose_command(twin_loop,"special"), twin_id)
		var twin_done := BattlePlayLoop.attack_target(twin_loop,"enemy021_1",func(_n): return 0)
		check(twin_done["attacked_this_action"] and twin_done["last_attack"].get("skill_id") == twin_id and BattlePlayLoop.unit(twin_done,"leonard")["stamina"] < 60,"a fixture grant resolves the row through the player special path with one ST payment: " + twin_id)
		match twin_id:
			"special:magicOTHER:magicCode32": check(twin_done["last_attack"]["turn_effects"].size() == 1 and twin_done["last_attack"]["turn_effects"][0]["kind"] == "cancel_pending","獅子吼2 cancels the pending slot like 獅子吼")
			"special:magicOTHER2:magicCode03": check(int(twin_done["last_attack"]["damage"]) > 0 and int(twin_done["last_attack"]["stolen_hp"]) >= 0 and twin_done["last_attack"].has("stolen_hp"),"吸血劍2 deals damage and drains like 吸血劍")
			"special:magicOTHER:magicCode14": check(twin_done["last_attack"]["stolen_items"].size() == 1 and int(twin_done["last_attack"]["stolen_items"][0]["code"]) == 210,"金之手LV2 steals the first passing slot like 金之手")


# ---- run_skill_resolution_tests.gd ----
## Skill targeting preview = settlement: for every skill in the book, from a caster in the
## middle of an open field, every legal center's preview footprint
## (BattleLoopCombat.skill_cast_footprint — what BattleSceneOverlays.refresh_skill_footprint
## draws) must be exactly the cells whose occupants SkillResolutionRules.prepare_cast takes as
## targets. Every other cell the skill can reach — range reach plus effect reach from the
## caster (SkillTargetRules.cells／effect_cells never place a footprint cell farther) and one
## ring beyond, so a settlement past its own footprint still hits a dummy — holds a
## side-matching unit. Shapes are tallied by (range, effect_range) so the report names each
## class (single cell, cross, Dir line, self-centred area, circles …).
const SkillTargetRules = preload("res://game/sim/SkillTargetRules.gd")
const SCENARIO := "res://content/battles/battle_003.json"
const MAP_SIZE := Vector2i(23, 23)
const ORIGIN := Vector2i(11, 11)
## Per-unit usefulness gates: a utility effect (steal, drain …) skips a unit that yields
## nothing, so its targets are a subset of the footprint's occupants, never outside it.
const SUBSET_POLICIES := ["native_special_utility"]


func run_skill_footprint_preview() -> void:
	var base: Dictionary = BattlePlayLoop.initialize_roster_growth(BattlePlayLoop.create([], "", BattlePlayLoop.BattleScenario.load_file(SCENARIO)))
	check(bool(base.get("scenario_ok", false)), "level 3 initializes")
	var book: Dictionary = base["skill_book"].duplicate(true)
	var targeting: Dictionary = base["skill_target_data"]
	var equipment: Dictionary = base["equipment_items"]
	var caster: Dictionary = BattlePlayLoop.unit(base, "hu").duplicate(true)
	var ally_template: Dictionary = BattlePlayLoop.unit(base, "tina").duplicate(true)
	var foe_template: Dictionary = BattlePlayLoop.unit(base, "actor028_1").duplicate(true)
	# The birth carry is a global-stream roll (0x407c86; RNGC), so whether 028_1 was born holding
	# anything depends on the seed. StealItem's usefulness gate is slot 0 (SpecialUtilityRules,
	# 0x40b4e8 walk): give every foe dummy a stealable bag explicitly.
	if int(foe_template["inventory"][0]) == 0: foe_template["inventory"][0] = 241
	caster["coord"] = ORIGIN
	# Harness ownership and purse: the caster declares every skill and can pay any cost.
	book["actors"][str(caster["actor_id"])]["supported_initial_ids"] = book["skills"].keys()
	caster["max_mp"] = 9999
	caster["mp"] = 9000 # below the maximum: an MP heal on the caster has something to restore
	caster["stamina"] = 100
	_afflict(caster)
	var context := BattlePlayLoop.Combat.skill_context(base)
	var shapes := {}
	var verified := 0
	var unverified: Array[String] = []
	for skill_id in book["skills"]:
		var entry: Dictionary = book["skills"][skill_id]
		var fields: Dictionary = entry["fields"]
		var support := SkillTargetRules.is_support(fields, targeting)
		var units: Array = [caster]
		var radius := _reach(targeting["ranges"][fields["range"]]) + _reach(targeting["ranges"][fields["effect_range"]]) + 1
		for y in range(maxi(0, ORIGIN.y - radius), mini(MAP_SIZE.y, ORIGIN.y + radius + 1)):
			for x in range(maxi(0, ORIGIN.x - radius), mini(MAP_SIZE.x, ORIGIN.x + radius + 1)):
				var cell := Vector2i(x, y)
				if cell == ORIGIN: continue
				var dummy: Dictionary = (ally_template if support else foe_template).duplicate(true)
				dummy["id"] = "dummy_%d_%d" % [x, y]
				dummy["coord"] = cell
				_afflict(dummy)
				units.append(dummy)
		var preview_loop := {"units": [caster], "selected_unit_id": caster["id"], "selected_skill_id": skill_id,
			"interaction": "attack_select", "selected_attack": entry["channel"], "skill_book": book,
			"skill_target_data": targeting, "map_size": MAP_SIZE}
		var shape := "%s→%s" % [fields["range"], fields["effect_range"]]
		shapes[shape] = int(shapes.get(shape, 0)) + 1
		var centers := SkillTargetRules.cells(ORIGIN, fields, targeting, MAP_SIZE)
		check(not centers.is_empty(), "%s has cast centers" % skill_id)
		var skill_context: Dictionary = _utility_context(context, units, str(caster["id"]), str(fields["function"])) if entry["damage_policy"] == "native_special_utility" else context
		var skill_ok := true
		var reason := ""
		for center in centers:
			var preview: Array = BattlePlayLoop.Combat.skill_cast_footprint(preview_loop, center)
			check(not preview.is_empty(), "%s previews a footprint at legal center %s" % [skill_id, center])
			var expected := {}
			for cell in preview:
				if cell != ORIGIN or support: expected[cell] = true
			var primary: Dictionary = {}
			for unit in units:
				if expected.has(unit["coord"]) and (unit["coord"] == center or primary.is_empty()): primary = unit
			if primary.get("id") == caster["id"] and entry["damage_policy"] == "native_special_utility":
				# A queue utility cannot act on its own caster's slot; any other member it
				# reaches is the chosen unit (the center stays the caster's cell).
				for unit in units:
					if unit["id"] != caster["id"] and expected.has(unit["coord"]): primary = unit; break
			if primary.is_empty(): continue
			var prepared := SkillResolutionRules.prepare_cast(caster, primary, units, skill_id, fields, book, targeting, equipment, ORIGIN, MAP_SIZE, center, skill_context)
			if not prepared["ok"]:
				skill_ok = false
				reason = str(prepared["reason"])
				break
			var hit := {}
			for target in prepared["targets"]: hit[target["coord"]] = true
			var outside: Array = hit.keys().filter(func(cell): return not expected.has(cell))
			check(outside.is_empty(), "%s at %s settles no cell outside its preview (%s)" % [skill_id, center, outside])
			if entry["damage_policy"] not in SUBSET_POLICIES:
				var missed: Array = expected.keys().filter(func(cell): return not hit.has(cell))
				check(missed.is_empty(), "%s at %s settles every previewed occupant (missed %s)" % [skill_id, center, missed])
		if skill_ok: verified += 1
		else: unverified.append("%s:%s" % [skill_id, reason])
	var lines: Array[String] = []
	for shape in shapes: lines.append("%s=%d" % [shape, shapes[shape]])
	lines.sort()
	print("SKILL_FOOTPRINT_SHAPES %s" % " ".join(lines))
	print("SKILL_FOOTPRINT_VERIFIED skills=%d verified=%d unverified=%s" % [book["skills"].size(), verified, unverified])
	check(unverified.is_empty(), "every skill settles through prepare_cast on the filled field: %s" % [unverified])


## Chebyshev reach of a targeting pattern from its centre: a Dir line runs size − 1 cells past
## the chosen cell (SkillTargetRules.line_cells), a grid pattern reaches its farthest set cell.
static func _reach(pattern: Dictionary) -> int:
	if SkillTargetRules.is_line(pattern): return int(pattern["size"]) - 1
	var half := int(pattern["size"]) / 2
	var reach := 0
	for y in range(int(pattern["size"])):
		for x in range(int(pattern["size"])):
			if int(pattern["data"][y][x]) > 0: reach = maxi(reach, maxi(absi(x - half), absi(y - half)))
	return reach


## Every unit carries something each support effect can act on: half HP and poison (a
## cure-poison component is in every cure skill). Poison does not stop casting.
static func _afflict(unit: Dictionary) -> void:
	unit["hp"] = maxi(1, int(unit["max_hp"]) / 2)
	unit["status_flags"] = int(unit["status_flags"]) | BattlePlayLoop.StatusEffectRules.POISON
	unit["status_counters"]["poison"] = 3
	# An attack boost for 退魔 (magicFun_ClearAtDfUp) to clear; a further boost still stacks.
	unit["status_flags"] = int(unit["status_flags"]) | BattlePlayLoop.StatusEffectRules.Enhancements.FLAGS["attack_up"]
	unit["status_counters"]["attack_up"] = (5 << 16) | 3


## A queue the queue utilities can act on: 天鳴覺醒 (ActiveAgain) re-activates a member that
## already acted, 獅子吼 (CancelActive) cancels one still to act — every dummy stands on the
## eligible side of the caster's slot.
static func _utility_context(context: Dictionary, units: Array, caster_id: String, function_text: String) -> Dictionary:
	var queue: Dictionary = BattlePlayLoop.CoreTurnQueue.rebuild(units)
	var others: Array = queue["slots"].filter(func(slot): return slot["id"] != caster_id)
	var own: Array = queue["slots"].filter(func(slot): return slot["id"] == caster_id)
	var again := function_text.contains("ActiveAgain")
	queue["slots"] = others + own if again else own + others
	queue["index"] = others.size() if again else 0
	queue["round"] = 1
	var next := context.duplicate()
	next["turn_queue"] = queue
	return next


# ---- run_skill_resolution_tests.gd ----
const SkillResourceRules = preload("res://game/sim/SkillResourceRules.gd")
const BattleLoopAI = preload("res://game/sim/loop/BattleLoopAI.gd")
const EquipmentCatalog = preload("res://game/sim/EquipmentCatalog.gd")
static func stream_rolling(roll: int) -> Array:
	for seed in range(1, 100000):
		if int(DamageRandomStream.rand(DamageRandomStream.seeded(seed), 100)["value"]) == roll: return DamageRandomStream.seeded(seed)
	return []


## Generator steps from one damage-stream state to another (-1 beyond 32).
static func steps_between(start: Array, end: Variant) -> int:
	var state := start.duplicate()
	for count in range(33):
		if state == end: return count
		state = DamageRandomStream.raw(state)["state"]
	return -1


func controlled_skill_resource() -> Dictionary:
	var loop := BattleFixture.loop()
	for index in range(loop["turn_queue"]["slots"].size()):
		if loop["turn_queue"]["slots"][index]["id"] == "leonard":
			loop["turn_queue"]["index"] = index
	return BattlePlayLoop.select_player_unit(loop, "leonard")


func run_skill_resource() -> void:
	var catalog := EquipmentCatalog.items()
	var oracle: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://docs/evidence_packets/static_reverse/original_skill_resources.json"))
	for case in oracle["cases"]:
		var amounts := SkillResourceRules.amounts(case["channel"],case["expend"],case["half_mp"])
		check(amounts["ok"],"native valid cost is accepted")
		var native_available: bool = case["available"] >= amounts["native_required"]
		check(native_available == bool(case["affordable"]),"required threshold matches complete native affordability helper")
		if case["channel"] == "magic":
			check(case["available"]-amounts["amount"] == case["debit_block"]["remaining_mp"],"charge matches native bounded MP debit")
		else:
			check(amounts["amount"] == case["base_cost"],"ST cost matches native complete getter")
		var fixture_items := {"1":{"mp_use_half":case["half_mp"]}}
		var actor := {"mp":int(case["available"]),"stamina":int(case["available"]),"equipment":[{"slot":"weapon","item_code":1}]}
		var before := actor.duplicate(true)
		var quote := SkillResourceRules.quote(actor,{"expend":case["expend"]},case["channel"],fixture_items)
		check(quote["ok"] == (case["available"] >= amounts["amount"]),"product rejects negative-resource corner explicitly")
		check(actor == before,"quote never owns or mutates actor resources")
	for invalid in [null,-1,1.5,"", "1.5","garbage",INF,NAN,true]:
		check(not SkillResourceRules.amounts("special",invalid)["ok"],"invalid or missing source cost cannot become free")
	check(not SkillResourceRules.amounts("special",2147483647)["ok"],"overflowing source cost is refused")
	check(SkillResourceRules.amounts("special","1")["amount"] == 20,"raw source text uses the same recovered cost")
	var loop := controlled_skill_resource()
	var actor := BattlePlayLoop.unit_ref(loop,"leonard")
	actor["stamina"] = 19
	var page := BattlePlayLoop.choose_command(loop,"special")
	check(not BattlePlayLoop.can_use_special(loop,"leonard") and BattlePlayLoop.command_available(loop,"special") and page["interaction"] == "special_select" and page["units"] == loop["units"],"19 ST still opens the skill page (the original opens it with the gauge empty)")
	check(BattlePlayLoop.choose_special(page,"special:magicOTHER:magicCode01") == page,"19 ST cannot start the source cost20 skill from the page")
	check(BattlePlayLoop.cancel_interaction(page)["interaction"] == "action_menu","the page is left by cancelling back to the action menu")
	actor["stamina"] = 20
	var foe := BattlePlayLoop.unit_ref(loop,"enemy021_1")
	foe["coord"] = actor["coord"] + Vector2i.UP
	foe["hp"] = 100
	foe["combat_profile"]["live_defense"] = 10000
	check(BattlePlayLoop.can_use_special(loop,"leonard"),"exact20 ST enables special")
	var selected := BattlePlayLoop.choose_special(BattlePlayLoop.choose_command(loop,"special"),"special:magicOTHER:magicCode01")
	var cancelled := BattlePlayLoop.cancel_interaction(selected)
	check(BattlePlayLoop.unit(cancelled,"leonard")["stamina"] == 20 and cancelled["turn_queue"] == loop["turn_queue"],"target cancel preserves resource and turn")
	for hit in [true,false]:
		var before := selected.duplicate(true)
		var result := BattlePlayLoop.attack_target(selected,"enemy021_1",func(n):return 0 if hit else n-1)
		check(BattlePlayLoop.unit(result,"leonard")["stamina"] == 0,"hit and miss charge exactly20 ST once")
		check(result["last_attack"]["hit"] == hit,"fixture actually exercises requested hit outcome")
		check(result["last_attack"]["resource_payment"]["before"] == 20 and result["last_attack"]["resource_payment"]["amount"] == 20,"receipt records settled authoritative resource cost")
		check(BattlePlayLoop.attack_target(result,"enemy021_1")["units"] == result["units"],"repeat confirmation cannot charge a second time")
		check(selected == before,"special transaction preserves input")
	var no_random := func(_n): check(false,"invalid resource/target must not consume RNG"); return 0
	var wrong_target := BattlePlayLoop.attack_target(selected,"enemy023_1",no_random)
	check(wrong_target["units"] == selected["units"] and wrong_target["turn_queue"] == selected["turn_queue"],"wrong-target special cannot spend any resource")
	var stale := selected.duplicate(true)
	BattlePlayLoop.unit_ref(stale,"leonard")["stamina"] = 19
	var refused := BattlePlayLoop.attack_target(stale,"enemy021_1",no_random)
	check(refused["units"] == stale["units"] and not refused["attacked_this_action"],"cost rechecked after target selection")
	var missing := selected.duplicate(true)
	own(missing, "skill_book")["skills"]["special:magicOTHER:magicCode01"]["fields"].erase("expend")
	check(not BattlePlayLoop.can_use_special(missing,"leonard"),"missing cost disables availability")
	refused = BattlePlayLoop.attack_target(missing,"enemy021_1",no_random)
	check(refused["units"] == missing["units"] and refused["last_attack_reject"]["reason"] == "invalid_skill_cost","missing cost fails explicitly before settlement")
	for bad in [null,"20",-1,1.5,INF,NAN]:
		var invalid := actor.duplicate(true)
		invalid["stamina"] = bad
		check(not SkillResourceRules.quote(invalid,{"expend":"1"},"special",catalog)["ok"],"live resource must be a finite nonnegative integer")
	var halves: Array = catalog.keys().filter(func(code):return catalog[code]["mp_use_half"])
	check(not halves.is_empty(),"source catalog contains actual half-MP items")
	for half in [false,true]:
		var magic_loop := BattleFixture.loop()
		var mage := BattlePlayLoop.unit_ref(magic_loop,"enemy026_1")
		var target := BattlePlayLoop.unit_ref(magic_loop,"leonard")
		mage["coord"] = target["coord"] + Vector2i.RIGHT
		mage["move_point"] = 0 # Isolate cost/hit draws from the independent position tie chooser.
		target["hp"] = 100
		target["max_hp"] = 100
		if half and not halves.is_empty():
			# Only the resource modifier is exercised. This fixture does not unlock
			# otherwise unsupported equipment or claim its other passives work.
			mage["equipment"] = [{"slot":"accessory1","item_code":int(halves[0])}]
		var wind: Dictionary = magic_loop["skill_book"]["skills"]["magic:magicAIR:magicCode01"]
		own(magic_loop, "skill_book")["skills"]["magic:magicFIRE:magicCode01"].erase("fields")
		check(BattlePlayLoop.skill_input_error(magic_loop, mage) == "skill_identity_mismatch", "missing definition for a declared owned spell fails before enumeration")
		# This isolated cost route grants only wind; removing a definition alone
		# must no longer silently hide another source-owned spell.
		own(magic_loop, "skill_book")["actors"]["026"]["supported_initial_ids"] = ["magic:magicAIR:magicCode01"]
		var price: int = SkillResourceRules.amounts("magic",wind["fields"]["expend"],half)["amount"]
		for hit in [true,false]:
			mage["mp"] = price
			var fixture := magic_loop.duplicate(true)
			# Selection draws from the AI decision source; the settlement — native hit, then
			# for a hit the two triangular samples and two EXP values — from the loop's
			# damage stream (0x42c780). A miss stops before both damage and EXP draws.
			set_stream(fixture, "damage", stream_rolling(0 if hit else 99))
			var start: Array = stream_of(fixture, "damage")
			var draws := [0,0,0]
			var bounds: Array = []
			var strike := BattleLoopAI.try_skill_turn(fixture,"enemy026_1",[BattlePlayLoop.unit_ref(fixture,"leonard")],func(n):
				bounds.append(n)
				check(not draws.is_empty(), "cost route received an unexpected random request")
				return draws.pop_front() if not draws.is_empty() else 0)
			check(not strike.is_empty() and strike["hit"] == hit,"AI exercises affordable actual source spell")
			check(draws.is_empty() and bounds == [100, 32, 100],"the decision source serves exactly the native selection draws")
			_assert_eq(steps_between(start, stream_of(fixture, "damage")), 5 if hit else 1, "the damage stream serves the native hit, and only a hit converts a contribution (triangular pair, EXP pair)")
			check(BattlePlayLoop.unit(fixture,"enemy026_1")["mp"] == 0 and strike["resource_payment"]["amount"] == price,"AI availability and debit share exact normal/half cost")
		mage["mp"] = price-1
		var poor := magic_loop.duplicate(true)
		check(BattleLoopAI.try_skill_turn(magic_loop,"enemy026_1",[target],no_random).is_empty() and magic_loop == poor,"unaffordable AI choice cannot move, damage or consume RNG")
		mage["mp"] = price
		own(magic_loop, "skill_book")["skills"]["magic:magicAIR:magicCode01"]["fields"].erase("expend")
		var malformed := magic_loop.duplicate(true)
		check(BattleLoopAI.try_skill_turn(magic_loop,"enemy026_1",[target],no_random).get("reason") == "invalid_skill_cost" and magic_loop == malformed,"malformed AI cost is explicitly rejected before effects or RNG")
		for index in range(magic_loop["turn_queue"]["slots"].size()):
			if magic_loop["turn_queue"]["slots"][index]["id"] == "enemy026_1":
				magic_loop["turn_queue"]["index"] = index
		magic_loop["interaction"] = "ai_resolving"
		var failed := BattlePlayLoop.step_ai_turn(magic_loop,no_random)
		check(not failed["scenario_ok"] and failed["scenario_error"] == "invalid_skill_cost" and failed["interaction"] == "scenario_error","invalid AI source fails explicitly instead of falling back to a physical attack")
		check(failed["units"] == magic_loop["units"] and failed["turn_queue"] == magic_loop["turn_queue"],"invalid AI data cannot partially move, spend or advance")
	var absent := actor.duplicate(true)
	absent["mp"] = 10
	var broken_catalog := catalog.duplicate(true)
	broken_catalog[str(int(absent["equipment"][0]["item_code"]))].erase("mp_use_half")
	check(SkillResourceRules.quote(absent,{"expend":3},"magic",broken_catalog)["reason"] == "missing_magic_cost_modifier","missing modifier metadata fails explicitly")


# ---- run_skill_resolution_tests.gd ----
func controlled_skill_target() -> Dictionary:
	var loop := BattleFixture.loop()
	for index in range(loop["turn_queue"]["slots"].size()):
		if loop["turn_queue"]["slots"][index]["id"] == "leonard":
			loop["turn_queue"]["index"] = index
	BattlePlayLoop.unit_ref(loop,"leonard")["stamina"] = 20
	return BattlePlayLoop.select_player_unit(loop,"leonard")


func run_skill_target() -> void:
	var loop := controlled_skill_target()
	var data: Dictionary = loop["skill_target_data"]
	var fields: Dictionary = loop["skill_book"]["skills"]["special:magicOTHER:magicCode01"]["fields"]
	var native: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://docs/evidence_packets/static_reverse/original_skill_targets.json"))
	for name in native["source_function_modes"]:
		var mask := SkillTargetRules.function_mask(name,data["function_bits"])
		for channel in ["magic","special"]:
			check(RulesReadback.native_target_mode(channel,mask) == int(native["source_function_modes"][name][channel]),"separate native mode mapping: "+name+"/"+channel)
	for code in data["ranges"]:
		if SkillTargetRules.is_line(data["ranges"][code]): continue # line shapes are effect-only; covered below
		var local := fields.duplicate(true)
		local["range"] = code
		for origin in [Vector2i(4,4),Vector2i(0,0),Vector2i(8,8)]:
			var cells := SkillTargetRules.cells(origin,local,data,Vector2i(9,9))
			var pattern: Dictionary = data["ranges"][code]
			var half: int = int(pattern["size"])/2
			for y in range(9):
				for x in range(9):
					var point := Vector2i(x,y)
					var offset: Vector2i = point-origin+Vector2i(half,half)
					var allowed: bool = point!=origin and offset.x>=0 and offset.y>=0 and offset.x<int(pattern["size"]) and offset.y<int(pattern["size"])
					if allowed: allowed = pattern["data"][offset.y][offset.x]>0
					check(cells.has(point)==allowed,"cast coverage follows each original source cell including map clipping")
	var caster := BattlePlayLoop.unit_ref(loop,"leonard")
	var target := BattlePlayLoop.unit_ref(loop,"enemy021_1")
	caster["coord"] = Vector2i(8,8)
	target["coord"] = Vector2i(10,8)
	target["hp"] = 100
	target["max_hp"] = 100
	target["combat_profile"]["live_defense"] = 10000
	var selected := BattlePlayLoop.choose_special(BattlePlayLoop.choose_command(loop,"special"),"special:magicOTHER:magicCode01")
	check(BattlePlayLoop.attack_cells(selected).has(Vector2i(10,8)) and not BattlePlayLoop.attack_cells(selected).has(Vector2i(9,9)),"source special range is a two-cell cross, not a diamond")
	for reason in ["diagonal","same_side","dead","defeated","unknown_role","self"]:
		var denied := selected.duplicate(true)
		var foe := BattlePlayLoop.unit_ref(denied,"enemy021_1")
		var id := "enemy021_1"
		match reason:
			"diagonal": foe["coord"] = Vector2i(9,9)
			"same_side": foe["battle_actor_role"] = BattlePlayLoop.ROLE_FRIENDLY
			"dead": foe["hp"] = 0
			"defeated": foe["defeated"] = true
			"unknown_role": foe["battle_actor_role"] = "unknown"
			"self": id = "leonard"
		var before := denied.duplicate(true)
		var rejected := BattlePlayLoop.attack_target(denied,id,no_rng)
		check(rejected["units"] == before["units"] and rejected["turn_queue"] == before["turn_queue"] and not rejected["attacked_this_action"],"invalid target is atomic: "+reason)
		check(denied == before,"target validation is read-only: "+reason)
	for bad in ["magicFun_Heal","magicFun_Attack,magicFun_Poison","magicFun_ActiveAgain","", "unrecognized"]:
		var denied := selected.duplicate(true)
		own(denied, "skill_book")["skills"]["special:magicOTHER:magicCode01"]["fields"]["function"] = bad
		check(not BattlePlayLoop.can_use_special(denied,"leonard"),"unsupported effect cannot become an available damage action")
		var after := BattlePlayLoop.attack_target(denied,"enemy021_1",no_rng)
		check(after["units"] == denied["units"] and after["turn_queue"] == denied["turn_queue"],"unsupported function cannot spend resource or apply damage")
	for malformed in ["missing_range","row_size","fraction"]:
		var invalid := selected.duplicate(true)
		match malformed:
			"missing_range": own(invalid, "skill_target_data")["ranges"].erase("range2Cell")
			"row_size": own(invalid, "skill_target_data")["ranges"]["range2Cell"]["data"][0] = [1]
			"fraction": own(invalid, "skill_target_data")["ranges"]["range2Cell"]["data"][0][0] = 0.5
		check(not BattlePlayLoop.can_use_special(invalid,"leonard"),"invalid geometry disables skill: "+malformed)
		var after := BattlePlayLoop.attack_target(invalid,"enemy021_1",no_rng)
		check(after["units"] == invalid["units"] and after["turn_queue"] == invalid["turn_queue"],"invalid geometry cannot partially settle")
	# A special whose source effect_range is an area (天雷猛襲劍 range3CellThrust) settles
	# through the same cast transaction as area magic: one payment, every living enemy in
	# the footprint, never the caster standing inside it.
	var area := selected.duplicate(true)
	own(area, "skill_book")["skills"]["special:magicOTHER:magicCode01"]["fields"]["effect_range"] = "range2Cell"
	check(BattlePlayLoop.can_use_special(area,"leonard"),"an area effect_range keeps the special available")
	var swept := BattlePlayLoop.attack_target(area,"enemy021_1",func(_n): return 0)
	var affected: Array = swept.get("last_attack", {}).get("affected_targets", [])
	check(swept["attacked_this_action"] and BattlePlayLoop.unit(swept,"leonard")["stamina"] == 0 and swept["last_attack"].get("cast_center") == Vector2i(10,8),"area special pays once and settles at the chosen center")
	check(affected.any(func(receipt): return receipt["defender_id"] == "enemy021_1" and int(receipt["damage"]) > 0) and not affected.any(func(receipt): return receipt["defender_id"] == "leonard"),"area special damages the footprint enemy and skips the caster inside the footprint")
	check(BattlePlayLoop.unit(swept,"enemy021_1")["hp"] < 100 and BattlePlayLoop.unit(swept,"leonard")["hp"] == BattlePlayLoop.unit(area,"leonard")["hp"],"only footprint enemies lose HP")
	var hit := BattlePlayLoop.attack_target(selected,"enemy021_1",func(_n): return 0)
	check(BattlePlayLoop.unit(hit,"leonard")["stamina"]==0 and hit["attacked_this_action"],"valid source target pays and completes once")
	check(BattlePlayLoop.strike_range_cells(hit,hit["last_attack"]) == BattlePlayLoop.attack_cells(selected),"attack preview and settled special range share the same mask")
	# Two different source ranges must constrain which spell the AI can choose.
	var ai := BattleFixture.loop()
	var mage := BattlePlayLoop.unit_ref(ai,"enemy026_1")
	mage["coord"] = Vector2i(6,6)
	mage["mp"] = 30
	var foe := BattlePlayLoop.unit_ref(ai,"leonard")
	foe["coord"] = Vector2i(8,7)
	foe["hp"] = 100
	foe["max_hp"] = 100
	own(ai, "skill_book")["skills"]["magic:magicAIR:magicCode01"]["fields"]["range"] = "range2Cell"
	var before := ai.duplicate(true)
	var result := BattleLoopAI.try_skill_turn(ai,"enemy026_1",[foe],func(_n): return 0)
	check(result.get("magic_key")=="fire" and result["path"]==BattlePlayLoop.movement_path(before,"enemy026_1",result["to"]),"AI chooses source-prepended fire and its own legal casting route, including staying put")
	check(BattlePlayLoop.strike_range_cells(ai,result).has(foe["coord"]) and BattlePlayLoop.unit(ai,"enemy026_1")["mp"]==22,"AI range cue and charged spell match its eligible target")
	for corruption in ["friendly","unknown_id","stale_dead"]:
		var invalid := before.duplicate(true)
		var proposed: Dictionary = BattlePlayLoop.unit(invalid,"leonard").duplicate(true)
		match corruption:
			"friendly": BattlePlayLoop.unit_ref(invalid,"leonard")["battle_actor_role"] = BattlePlayLoop.ROLE_ENEMY
			"unknown_id": proposed["id"] = "not_in_roster"
			"stale_dead": BattlePlayLoop.unit_ref(invalid,"leonard")["hp"] = 0
		var initial := invalid.duplicate(true)
		check(BattleLoopAI.try_skill_turn(invalid,"enemy026_1",[proposed],no_rng).is_empty() and invalid==initial,"AI rereads real target identity/state before choosing or spending: "+corruption)
	for bad in ["magicFun_Heal", "magicFun_Attack,magicFun_Poison"]:
		var invalid := before.duplicate(true)
		own(invalid, "skill_book")["skills"]["magic:magicAIR:magicCode01"]["fields"]["function"] = bad
		for index in range(invalid["turn_queue"]["slots"].size()):
			if invalid["turn_queue"]["slots"][index]["id"]=="enemy026_1": invalid["turn_queue"]["index"]=index
		invalid["interaction"] = "ai_resolving"
		var after := BattlePlayLoop.step_ai_turn(invalid,no_rng)
		check(after["interaction"]=="scenario_error" and after["scenario_error"]=="unsupported_skill_function","invalid effect fails AI input rather than falling back to damaging attack")
		check(after["units"]==invalid["units"] and after["turn_queue"]==invalid["turn_queue"],"bad skill definition cannot move or advance")
	# Line (Dir) effect footprints: 0x4100e0 indices 21..23 write a straight size-cell line
	# from the chosen cell away from the caster (column difference first, then row).
	var line_fields := fields.duplicate(true)
	line_fields["range"] = "range1Cell"
	line_fields["effect_range"] = "range3CellDir"
	var map := Vector2i(16, 16)
	check(SkillTargetRules.definition_error(line_fields, data) == "", "range3CellDir is an accepted effect range")
	var cast_line := line_fields.duplicate(true)
	cast_line["range"] = "range3CellDir"
	check(SkillTargetRules.definition_error(cast_line, data) == "unsupported_line_cast_range", "a line is refused as a cast range instead of guessing a direction")
	check(SkillTargetRules.effect_cells(Vector2i(9, 8), line_fields, data, map, Vector2i(8, 8)) == [Vector2i(9, 8), Vector2i(10, 8), Vector2i(11, 8)], "east target extends the line east from the target cell")
	check(SkillTargetRules.effect_cells(Vector2i(7, 8), line_fields, data, map, Vector2i(8, 8)) == [Vector2i(7, 8), Vector2i(6, 8), Vector2i(5, 8)], "west target extends west")
	check(SkillTargetRules.effect_cells(Vector2i(8, 7), line_fields, data, map, Vector2i(8, 8)) == [Vector2i(8, 7), Vector2i(8, 6), Vector2i(8, 5)], "north target extends north")
	check(SkillTargetRules.effect_cells(Vector2i(8, 9), line_fields, data, map, Vector2i(8, 8)) == [Vector2i(8, 9), Vector2i(8, 10), Vector2i(8, 11)], "south target extends south")
	check(SkillTargetRules.effect_cells(Vector2i(9, 9), line_fields, data, map, Vector2i(8, 8)) == [Vector2i(9, 9), Vector2i(10, 9), Vector2i(11, 9)], "a diagonal center takes the horizontal axis first, as the original branch order does")
	check(SkillTargetRules.effect_cells(Vector2i(8, 8), line_fields, data, map, Vector2i(8, 8)) == [Vector2i(8, 8)], "the caster's own cell yields only that cell")
	check(SkillTargetRules.effect_cells(Vector2i(15, 8), line_fields, data, map, Vector2i(14, 8)) == [Vector2i(15, 8)], "the map edge stops the line")
	check(SkillTargetRules.effect_cells(Vector2i(9, 8), line_fields, data, map).is_empty(), "a line footprint without the caster position is refused, not defaulted")
	var line_caster := BattlePlayLoop.unit(loop, "leonard").duplicate(true)
	line_caster["coord"] = Vector2i(8, 8)
	var far_foe := BattlePlayLoop.unit(loop, "enemy021_1").duplicate(true)
	far_foe["coord"] = Vector2i(11, 8)
	var line_centers := SkillTargetRules.candidate_centers(line_caster, [line_caster, far_foe], line_fields, data, map, Vector2i(8, 8))
	check(line_centers == [Vector2i(9, 8), Vector2i(10, 8), Vector2i(11, 8)], "inverse line centers are exactly the cells whose line reaches the foe; the caster side yields none")
	for center in line_centers:
		check(SkillTargetRules.effect_cells(center, line_fields, data, map, Vector2i(8, 8)).has(far_foe["coord"]), "each candidate center projects onto the foe")
	# Player path: 皇龍閃 (range1Cell cast, range3CellDir effect) hits the adjacent enemy and the
	# one two cells behind it, skips the enemy beside the caster, pays once.
	var dragon := controlled_skill_target()
	var dragon_id := "special:magicOTHER:magicCode02"
	own(dragon, "skill_book")["actors"]["001"]["supported_initial_ids"].append(dragon_id)
	BattlePlayLoop.unit_ref(dragon, "leonard")["stamina"] = 80
	BattlePlayLoop.unit_ref(dragon, "leonard")["coord"] = Vector2i(8, 8)
	var near := BattlePlayLoop.unit_ref(dragon, "enemy021_1")
	near["coord"] = Vector2i(9, 8)
	near["hp"] = 400
	near["max_hp"] = 400
	var behind := BattlePlayLoop.unit_ref(dragon, "enemy021_2")
	behind["coord"] = Vector2i(11, 8)
	behind["hp"] = 400
	behind["max_hp"] = 400
	var beside := BattlePlayLoop.unit_ref(dragon, "enemy021_3")
	beside["coord"] = Vector2i(8, 9)
	beside["hp"] = 400
	beside["max_hp"] = 400
	var picked := BattlePlayLoop.choose_special(BattlePlayLoop.choose_command(dragon, "special"), dragon_id)
	check(picked["interaction"] == "attack_select" and picked["selected_skill_id"] == dragon_id, "a learned line special is selectable from the special menu")
	check(BattlePlayLoop.magic_target_id_at_coord(picked, Vector2i(9, 8)) == "enemy021_1", "the adjacent cell resolves to the adjacent enemy as center")
	var slashed := BattlePlayLoop.attack_target(picked, "enemy021_1", func(_n): return 0)
	var slashed_ids: Array = slashed.get("last_attack", {}).get("affected_targets", []).map(func(receipt): return receipt["defender_id"])
	check(slashed["attacked_this_action"] and BattlePlayLoop.unit(slashed, "leonard")["stamina"] == 20 and slashed["last_attack"].get("cast_center") == Vector2i(9, 8), "line special pays its source cost once and settles on the adjacent cell")
	check(slashed_ids == ["enemy021_1", "enemy021_2"] and BattlePlayLoop.unit(slashed, "enemy021_1")["hp"] < 400 and BattlePlayLoop.unit(slashed, "enemy021_2")["hp"] < 400, "both enemies on the line lose HP")
	check(BattlePlayLoop.unit(slashed, "enemy021_3")["hp"] == 400 and BattlePlayLoop.unit(slashed, "leonard")["hp"] == BattlePlayLoop.unit(dragon, "leonard")["hp"], "the enemy beside the caster and the caster are untouched")
	check(BattlePlayLoop.strike_range_cells(slashed, slashed["last_attack"]) == [Vector2i(9, 8), Vector2i(10, 8), Vector2i(11, 8)], "the settled cue shows the actual line footprint")
	# Self-centered pure specials (range0Cell cast, area effect): 慌雨斬 range1CellFull hits the
	# eight surrounding enemies from the caster's own cell, never the caster, one ST payment.
	var rain := controlled_skill_target()
	var rain_id := "special:magicWATER:magicCode01"
	own(rain, "skill_book")["actors"]["001"]["supported_initial_ids"].append(rain_id)
	var rain_caster := BattlePlayLoop.unit_ref(rain, "leonard")
	rain_caster["stamina"] = 40
	rain_caster["coord"] = Vector2i(8, 8)
	var ring := BattlePlayLoop.unit_ref(rain, "enemy021_1")
	ring["coord"] = Vector2i(9, 9)
	ring["hp"] = 400
	ring["max_hp"] = 400
	ring["combat_profile"]["resist_by_type"] = {"1": 0}
	var ring_two := BattlePlayLoop.unit_ref(rain, "enemy021_2")
	ring_two["coord"] = Vector2i(7, 8)
	ring_two["hp"] = 400
	ring_two["max_hp"] = 400
	ring_two["combat_profile"]["resist_by_type"] = {"1": 80}
	var outside := BattlePlayLoop.unit_ref(rain, "enemy021_3")
	outside["coord"] = Vector2i(10, 8)
	outside["hp"] = 400
	outside["max_hp"] = 400
	var rain_picked := BattlePlayLoop.choose_special(BattlePlayLoop.choose_command(rain, "special"), rain_id)
	check(rain_picked["interaction"] == "attack_select" and BattlePlayLoop.attack_cells(rain_picked) == [Vector2i(8, 8)], "a self-centered special offers only the caster's own cell")
	check(BattlePlayLoop.magic_target_id_at_coord(rain_picked, Vector2i(8, 8)) != "", "choosing the caster's cell resolves to a surrounding enemy")
	var rained := BattlePlayLoop.attack_target(rain_picked, "enemy021_1", func(_n): return 0)
	var rained_ids: Array = rained.get("last_attack", {}).get("affected_targets", []).map(func(receipt): return receipt["defender_id"])
	check(rained["attacked_this_action"] and BattlePlayLoop.unit(rained, "leonard")["stamina"] == 20 and rained["last_attack"].get("cast_center") == Vector2i(8, 8), "self-centered special pays its source cost once from the caster's cell")
	check(rained_ids == ["enemy021_1", "enemy021_2"] and BattlePlayLoop.unit(rained, "enemy021_3")["hp"] == 400 and BattlePlayLoop.unit(rained, "leonard")["hp"] == rain_caster["hp"], "only the ring enemies are affected; the caster inside the footprint is skipped")
	var ring_damage: int = 400 - BattlePlayLoop.unit(rained, "enemy021_1")["hp"]
	var ring_two_damage: int = 400 - BattlePlayLoop.unit(rained, "enemy021_2")["hp"]
	check(ring_damage > 0 and ring_two_damage == ring_damage * 20 / 100, "each footprint target applies its own water resistance to the same special roll")
	# magicOTHER damage magic (滅): the 0x40a7b0 type switch has no case 5, so no resistance
	# slot is read; MP, hit equipment and the level/mind/magic-attack terms follow the magic path.
	var Resolution := BattlePlayLoop.SkillResolutionRules
	var other_loop := controlled_skill_target()
	var other_id := "magic:magicOTHER:magicCode01"
	var other_caster := BattlePlayLoop.unit_ref(other_loop, "enemy026_1")
	other_caster["actor_id"] = "052"
	other_caster["mp"] = 40
	other_caster["coord"] = Vector2i(8, 8)
	var other_target := BattlePlayLoop.unit_ref(other_loop, "leonard")
	other_target["coord"] = Vector2i(8, 10)
	other_target["hp"] = 300
	other_target["combat_profile"]["resist_by_type"] = {}
	var other_fields := BattlePlayLoop.skill_fields(other_loop, other_id)
	var other_result := Resolution.resolve(other_caster, other_target, other_id, other_fields, other_loop["skill_book"], other_loop["skill_target_data"], other_loop["equipment_items"], other_caster["coord"], other_loop["map_size"], func(_n): return 0)
	check(other_result.get("ok", false) and other_result.get("receipt", {}).get("magic_key", "") == "other" and int(other_result.get("receipt", {}).get("damage", 0)) > 0 and other_result.get("caster_changes", {}).get("mp", 40) == 21, "滅 resolves as native magic damage without any resistance slot and pays 19 MP")
	var shielded := other_target.duplicate(true)
	shielded["combat_profile"]["resist_by_type"] = {"0": 80, "1": 80, "2": 80, "3": 80, "4": 80}
	var shielded_result := Resolution.resolve(other_caster, shielded, other_id, other_fields, other_loop["skill_book"], other_loop["skill_target_data"], other_loop["equipment_items"], other_caster["coord"], other_loop["map_size"], func(_n): return 0)
	check(shielded_result.get("ok", false) and shielded_result["receipt"]["damage"] == other_result["receipt"]["damage"], "elemental resistances do not scale magicOTHER magic")
	# eff_proc_Global wind magic (逆風裂空): same native wind policy as 風刃 with a wide footprint.
	var gale_id := "magic:magicAIR:magicCode03"
	var gale_caster := BattlePlayLoop.unit_ref(other_loop, "enemy026_1")
	gale_caster["actor_id"] = "056"
	gale_caster["mp"] = 40
	var gale_center := BattlePlayLoop.unit_ref(other_loop, "leonard")
	gale_center["coord"] = Vector2i(8, 12)
	gale_center["hp"] = 300
	gale_center["combat_profile"]["resist_by_type"] = {"2": 0}
	var gale_second := BattlePlayLoop.unit_ref(other_loop, "enemy023_1")
	gale_second["coord"] = Vector2i(8, 13)
	gale_second["hp"] = 300
	gale_second["combat_profile"]["resist_by_type"] = {"2": 0}
	var gale_fields := BattlePlayLoop.skill_fields(other_loop, gale_id)
	var gale_result := Resolution.resolve_cast(gale_caster, gale_center, [gale_caster, gale_center, gale_second], gale_id, gale_fields, other_loop["skill_book"], other_loop["skill_target_data"], other_loop["equipment_items"], gale_caster["coord"], other_loop["map_size"], func(_n): return 0, gale_center["coord"])
	var gale_ids: Array = gale_result.get("receipt", {}).get("affected_targets", []).map(func(receipt): return receipt["defender_id"])
	check(gale_result.get("ok", false) and gale_result.get("receipt", {}).get("magic_key", "") == "wind" and gale_ids == ["leonard", "enemy023_1"] and gale_result.get("caster_changes", {}).get("mp", 40) == 7, "逆風裂空 reaches a range5CellCircle center four cells away, hits both units in its range3CellCircle footprint and pays 33 MP once")
	# Elemental specials (SPECIAL type 0..4) read the target's resist_by_type slot on the
	# same 0x40a7b0 proc0 switch as magic; magicOTHER (type 5) still multiplies nothing.
	var Special := BattlePlayLoop.SkillResolutionRules.Special
	var wind_fields := fields.duplicate(true)
	wind_fields["type"] = "magicAIR"
	var resistant := BattlePlayLoop.unit(loop,"enemy021_1").duplicate(true)
	resistant["combat_profile"]["resist_by_type"] = {"2": 80, "3": 40}
	var caster_now := BattlePlayLoop.unit(loop,"leonard")
	var other_input: Dictionary = Special.prepare(caster_now, resistant, fields, loop["skill_book"], loop["equipment_items"])["input"]
	var wind_prepared := Special.prepare(caster_now, resistant, wind_fields, loop["skill_book"], loop["equipment_items"])
	check(other_input["element"] == "5" and other_input["resistance"] == 0 and wind_prepared["ok"] and wind_prepared["input"]["element"] == "2" and wind_prepared["input"]["resistance"] == 80, "special element index follows the SPECIAL type; magicOTHER reads no resistance slot")
	var fixed := func(_n): return 0
	var other_value: int = Special.roll(other_input, fixed)["value"]
	var wind_value: int = Special.roll(wind_prepared["input"], fixed)["value"]
	check(other_value > 0 and wind_value == (100 - 80) * other_value / 100, "wind special is scaled by the target's wind resistance while magicOTHER is not")
	var unresisted := resistant.duplicate(true)
	unresisted["combat_profile"]["resist_by_type"] = {"3": 40}
	check(Special.prepare(caster_now, unresisted, wind_fields, loop["skill_book"], loop["equipment_items"]).get("reason") == "missing_skill_resistance", "a missing resistance slot fails the elemental special instead of assuming zero")
	# Party members' initial specials come from their own PLAYERS declaration field (the
	# book now extracts all 13 magic_*/special_* fields): 雷特 006 連續突刺 (special_other,
	# range2Cell→range1Cell, magicOTHER), 嚎 007 碎岩擊 (special_earth, range2CellCircle→
	# range1Cell, reads earth resistance), 克羅蒂 009 魔晃斬 (special_mind, range2Cell→range1Cell).
	for row in [["006", "special:magicOTHER:magicCode16", Vector2i(10, 8), Vector2i(9, 9), ""], ["007", "special:magicEARTH:magicCode01", Vector2i(9, 9), Vector2i(11, 8), "0"], ["009", "special:magicMIND:magicCode05", Vector2i(10, 8), Vector2i(9, 9), "4"]]:
		var party := controlled_skill_target()
		var member := BattlePlayLoop.unit_ref(party, "leonard")
		member["actor_id"] = row[0]
		member["stamina"] = 40
		member["coord"] = Vector2i(8, 8)
		check(party["skill_book"]["actors"][row[0]]["supported_initial_ids"].has(row[1]), "the PLAYERS declaration grants the member's initial special: " + row[0])
		var victim := BattlePlayLoop.unit_ref(party, "enemy021_1")
		victim["coord"] = row[2]
		victim["hp"] = 400
		victim["max_hp"] = 400
		victim["combat_profile"]["resist_by_type"] = {"0": 40, "4": 40}
		var off_cell := BattlePlayLoop.unit_ref(party, "enemy021_2")
		off_cell["coord"] = row[3]
		off_cell["hp"] = 400
		off_cell["max_hp"] = 400
		BattlePlayLoop.unit_ref(party, "enemy021_4")["coord"] = Vector2i(1, 1)
		var chosen := BattlePlayLoop.choose_special(BattlePlayLoop.choose_command(party, "special"), row[1])
		check(chosen["interaction"] == "attack_select" and chosen["selected_skill_id"] == row[1], "the granted special is selectable from the member's special menu: " + row[1])
		check(BattlePlayLoop.attack_cells(chosen).has(row[2]) and not BattlePlayLoop.attack_cells(chosen).has(row[3]), "cast range follows the source range symbol (cross vs circle): " + row[1])
		var struck := BattlePlayLoop.attack_target(chosen, "enemy021_1", func(_n): return 0)
		var struck_ids: Array = struck.get("last_attack", {}).get("affected_targets", []).map(func(receipt): return receipt["defender_id"])
		check(struck["attacked_this_action"] and BattlePlayLoop.unit(struck, "leonard")["stamina"] == 20 and struck["last_attack"].get("skill_id") == row[1], "the special pays its 1-expend ST cost once and records its own id: " + row[1])
		check(struck_ids == ["enemy021_1"] and BattlePlayLoop.unit(struck, "enemy021_1")["hp"] < 400 and BattlePlayLoop.unit(struck, "enemy021_2")["hp"] == 400, "only the range1Cell footprint enemy loses HP: " + row[1])
		var member_fields := BattlePlayLoop.skill_fields(party, row[1])
		var member_input: Dictionary = BattlePlayLoop.SkillResolutionRules.Special.prepare(member, victim, member_fields, party["skill_book"], party["equipment_items"])["input"]
		check(member_input["element"] == ("5" if row[4] == "" else row[4]) and member_input["resistance"] == (0 if row[4] == "" else 40), "the special reads the resistance slot of its own SPECIAL type: " + row[1])
	# Enemy "2" variants are separate source rows with their own mag-spc.h bit (alias name+'2'):
	# same RESOURCE name, different id. 056 連續突刺2 (magicOTHER code30) vs 006 連續突刺 (code16);
	# 030/049 氣刃斬2 is type magicOTHER2 (TYPE.H 6) which lies above the 0x40a7b0 resist
	# switch bound exactly like magicOTHER, so no resistance slot scales it.
	var book_actors: Dictionary = loop["skill_book"]["actors"]
	check(book_actors["056"]["supported_initial_ids"].has("special:magicOTHER:magicCode30") and not book_actors["056"]["supported_initial_ids"].has("special:magicOTHER:magicCode16") and not book_actors["006"]["supported_initial_ids"].has("special:magicOTHER:magicCode30"), "連續突刺2 and 連續突刺 are distinct grants")
	check(loop["skill_book"]["skills"]["special:magicOTHER:magicCode30"]["name"] == loop["skill_book"]["skills"]["special:magicOTHER:magicCode16"]["name"] and loop["skill_book"]["skills"]["special:magicOTHER:magicCode30"]["fields"]["damage"] == "12,20", "the 2 variant shares the display name but keeps its own source row")
	for pair in [["030", "special:magicOTHER2:magicCode01"], ["049", "special:magicOTHER2:magicCode01"], ["051", "special:magicOTHER2:magicCode02"], ["032", "special:magicEARTH:magicCode04"], ["033", "special:magicEARTH:magicCode05"], ["055", "special:magicEARTH:magicCode04"], ["055", "special:magicEARTH:magicCode05"], ["045", "special:magicAIR:magicCode06"], ["048", "special:magicWATER:magicCode05"], ["054", "special:magicOTHER:magicCode31"]]:
		check(book_actors[pair[0]]["supported_initial_ids"].has(pair[1]), "special_earth/wind/water/other2 declarations grant the 2 variant: " + pair[0] + " " + pair[1])
	var two_loop := controlled_skill_target()
	var two_caster := BattlePlayLoop.unit_ref(two_loop, "enemy021_1")
	two_caster["actor_id"] = "049"
	two_caster["stamina"] = 20
	two_caster["coord"] = Vector2i(8, 8)
	var two_target := BattlePlayLoop.unit_ref(two_loop, "leonard")
	two_target["coord"] = Vector2i(10, 8)
	two_target["hp"] = 400
	two_target["combat_profile"]["resist_by_type"] = {"0": 80, "1": 80, "2": 80, "3": 80, "4": 80}
	var two_id := "special:magicOTHER2:magicCode01"
	var two_fields := BattlePlayLoop.skill_fields(two_loop, two_id)
	var two_prepared := Special.prepare(two_caster, two_target, two_fields, two_loop["skill_book"], two_loop["equipment_items"])
	check(two_prepared["ok"] and two_prepared["input"]["element"] == "6" and two_prepared["input"]["resistance"] == 0, "magicOTHER2 is the resist switch default: element 6, no slot read")
	var two_result := Resolution.resolve(two_caster, two_target, two_id, two_fields, two_loop["skill_book"], two_loop["skill_target_data"], two_loop["equipment_items"], two_caster["coord"], two_loop["map_size"], func(_n): return 0)
	var bare := two_target.duplicate(true)
	bare["combat_profile"]["resist_by_type"] = {"0": 0, "1": 0, "2": 0, "3": 0, "4": 0}
	var bare_result := Resolution.resolve(two_caster, bare, two_id, two_fields, two_loop["skill_book"], two_loop["skill_target_data"], two_loop["equipment_items"], two_caster["coord"], two_loop["map_size"], func(_n): return 0)
	check(two_result.get("ok", false) and int(two_result["receipt"]["damage"]) > 0 and two_result["receipt"]["damage"] == bare_result["receipt"]["damage"] and two_result["caster_changes"]["stamina"] == 0, "氣刃斬2 resolves as native special damage unaffected by every elemental resistance and pays 20 ST")
	var dragon_two := BattlePlayLoop.skill_fields(two_loop, "special:magicOTHER2:magicCode02")
	check(SkillTargetRules.effect_cells(Vector2i(9, 8), dragon_two, data, map, Vector2i(8, 8)) == [Vector2i(9, 8), Vector2i(10, 8), Vector2i(11, 8), Vector2i(12, 8)], "龍嘯天驅2 keeps the four-cell line footprint of its source row")
	# Boss initial specials. 017 神罰: range1Cell cast, range4CellDir line footprint from the chosen
	# cell. 057 咕噜最終型態 虛空無轉: range4CellCircle cast (Manhattan 4), range2CellCircle footprint.
	check(book_actors["017"]["supported_initial_ids"].has("special:magicOTHER:magicCode22") and book_actors["057"]["supported_initial_ids"].has("special:magicOTHER:magicCode28"), "017 神罰 and 057 虛空無轉 are granted from special_other")
	var wrath := BattlePlayLoop.skill_fields(loop, "special:magicOTHER:magicCode22")
	check(SkillTargetRules.effect_cells(Vector2i(8, 7), wrath, data, map, Vector2i(8, 8)) == [Vector2i(8, 7), Vector2i(8, 6), Vector2i(8, 5), Vector2i(8, 4)], "神罰 projects a four-cell line north from the adjacent target cell")
	var void_loop := controlled_skill_target()
	var void_id := "special:magicOTHER:magicCode28"
	var void_caster := BattlePlayLoop.unit_ref(void_loop, "enemy021_1")
	void_caster["actor_id"] = "057"
	void_caster["stamina"] = 80
	void_caster["coord"] = Vector2i(8, 8)
	var void_fields := BattlePlayLoop.skill_fields(void_loop, void_id)
	var void_cells := SkillTargetRules.cells(Vector2i(8, 8), void_fields, data, map)
	check(void_cells.has(Vector2i(12, 8)) and void_cells.has(Vector2i(10, 10)) and not void_cells.has(Vector2i(11, 10)) and not void_cells.has(Vector2i(8, 8)), "虛空無轉 casts anywhere within Manhattan distance 4 except the caster's cell")
	var void_footprint := SkillTargetRules.effect_cells(Vector2i(12, 8), void_fields, data, map, Vector2i(8, 8))
	check(void_footprint.has(Vector2i(13, 9)) and void_footprint.has(Vector2i(14, 8)) and not void_footprint.has(Vector2i(15, 8)), "its footprint is the range2CellCircle around the chosen cell")
	var void_center := BattlePlayLoop.unit_ref(void_loop, "leonard")
	void_center["coord"] = Vector2i(12, 8)
	void_center["hp"] = 900
	void_center["max_hp"] = 900
	var void_second := BattlePlayLoop.unit_ref(void_loop, "enemy023_1")
	void_second["coord"] = Vector2i(13, 9)
	void_second["hp"] = 900
	void_second["max_hp"] = 900
	var void_outside := BattlePlayLoop.unit_ref(void_loop, "enemy023_2")
	void_outside["coord"] = Vector2i(15, 8)
	void_outside["hp"] = 900
	void_outside["max_hp"] = 900
	var void_result := Resolution.resolve_cast(void_caster, void_center, [void_caster, void_center, void_second, void_outside], void_id, void_fields, void_loop["skill_book"], void_loop["skill_target_data"], void_loop["equipment_items"], void_caster["coord"], void_loop["map_size"], func(_n): return 0, void_center["coord"])
	var void_ids: Array = void_result.get("receipt", {}).get("affected_targets", []).map(func(receipt): return receipt["defender_id"])
	check(void_result.get("ok", false) and void_ids == ["leonard", "enemy023_1"] and void_result["caster_changes"]["stamina"] == 20 and void_result["targets"].all(func(change): return int(change["changes"]["hp"]) < 900), "虛空無轉 hits both units in the footprint, skips the one outside and pays its 3-expend ST once")
	# 極 (magic:magicOTHER:magicCode03, 059／060 initial): the third magicOTHER damage magic walks the
	# same OtherMagicRules path as 滅／裁 — 120 MP, range5CellCircle cast, range3CellCircle footprint,
	# no resistance slot.
	var apex_id := "magic:magicOTHER:magicCode03"
	check(book_actors["059"]["supported_initial_ids"].has(apex_id) and book_actors["060"]["supported_initial_ids"].has(apex_id), "059 and 060 hold 極 from magic_other")
	var apex_loop := controlled_skill_target()
	var apex_caster := BattlePlayLoop.unit_ref(apex_loop, "enemy026_1")
	apex_caster["actor_id"] = "059"
	apex_caster["mp"] = 130
	apex_caster["coord"] = Vector2i(8, 8)
	var apex_center := BattlePlayLoop.unit_ref(apex_loop, "leonard")
	apex_center["coord"] = Vector2i(13, 8)
	apex_center["hp"] = 900
	apex_center["max_hp"] = 900
	apex_center["combat_profile"]["resist_by_type"] = {"0": 80, "1": 80, "2": 80, "3": 80, "4": 80}
	var apex_second := BattlePlayLoop.unit_ref(apex_loop, "enemy023_1")
	apex_second["coord"] = Vector2i(15, 9)
	apex_second["hp"] = 900
	apex_second["max_hp"] = 900
	apex_second["combat_profile"]["resist_by_type"] = {"0": 0, "1": 0, "2": 0, "3": 0, "4": 0}
	var apex_outside := BattlePlayLoop.unit_ref(apex_loop, "enemy023_2")
	apex_outside["coord"] = Vector2i(17, 8)
	apex_outside["hp"] = 900
	apex_outside["max_hp"] = 900
	var apex_fields := BattlePlayLoop.skill_fields(apex_loop, apex_id)
	var apex_result := Resolution.resolve_cast(apex_caster, apex_center, [apex_caster, apex_center, apex_second, apex_outside], apex_id, apex_fields, apex_loop["skill_book"], apex_loop["skill_target_data"], apex_loop["equipment_items"], apex_caster["coord"], apex_loop["map_size"], func(_n): return 0, apex_center["coord"])
	var apex_receipts: Array = apex_result.get("receipt", {}).get("affected_targets", [])
	check(apex_result.get("ok", false) and apex_result["receipt"].get("magic_key") == "other" and apex_receipts.map(func(receipt): return receipt["defender_id"]) == ["leonard", "enemy023_1"] and apex_result["caster_changes"]["mp"] == 10, "極 reaches a center five cells away, hits both footprint units and pays 120 MP once")
	check(apex_receipts.size() == 2 and int(apex_receipts[0]["damage"]) > 0 and apex_receipts[0]["damage"] == apex_receipts[1]["damage"], "the fully resistant and the unresisting target take the same 極 damage: no slot is read")
	# High-tier eff_proc_Global damage magic (wave 9 lane A2): each row keeps its element's
	# native_magic_damage policy (0x40a7b0 channel0/proc0, resist_by_type slot), a wide cast range
	# and a multi-cell footprint, one MP payment. [id, holder, key, element, cost, center, inside, outside]
	for row in [
		["magic:magicEARTH:magicCode03", "057", "earth", "0", 33, Vector2i(8, 12), Vector2i(8, 13), Vector2i(8, 16)],
		["magic:magicEARTH:magicCode04", "060", "earth", "0", 84, Vector2i(8, 13), Vector2i(10, 14), Vector2i(8, 18)],
		["magic:magicFIRE:magicCode03", "051", "fire", "3", 33, Vector2i(8, 12), Vector2i(8, 13), Vector2i(8, 16)],
		["magic:magicFIRE:magicCode04", "057", "fire", "3", 84, Vector2i(8, 12), Vector2i(10, 14), Vector2i(8, 17)],
		["magic:magicWATER:magicCode03", "058", "water", "1", 33, Vector2i(8, 12), Vector2i(8, 13), Vector2i(8, 15)],
		["magic:magicWATER:magicCode04", "059", "water", "1", 84, Vector2i(8, 12), Vector2i(10, 14), Vector2i(8, 17)],
	]:
		var tier_id: String = row[0]
		check(book_actors[row[1]]["supported_initial_ids"].has(tier_id), "the PLAYERS declaration grants the high-tier magic to its source holder: " + tier_id)
		var tier_loop := controlled_skill_target()
		var tier_caster := BattlePlayLoop.unit_ref(tier_loop, "enemy026_1")
		tier_caster["actor_id"] = row[1]
		tier_caster["mp"] = 200
		tier_caster["coord"] = Vector2i(8, 8)
		var tier_center := BattlePlayLoop.unit_ref(tier_loop, "leonard")
		tier_center["coord"] = row[5]
		tier_center["hp"] = 900
		tier_center["max_hp"] = 900
		tier_center["combat_profile"]["resist_by_type"] = {"0": 0, "1": 0, "2": 0, "3": 0, "4": 0}
		var tier_inside := BattlePlayLoop.unit_ref(tier_loop, "enemy023_1")
		tier_inside["coord"] = row[6]
		tier_inside["hp"] = 900
		tier_inside["max_hp"] = 900
		tier_inside["combat_profile"]["resist_by_type"] = {"0": 80, "1": 80, "2": 80, "3": 80, "4": 80}
		var tier_outside := BattlePlayLoop.unit_ref(tier_loop, "enemy023_2")
		tier_outside["coord"] = row[7]
		tier_outside["hp"] = 900
		tier_outside["max_hp"] = 900
		var tier_fields := BattlePlayLoop.skill_fields(tier_loop, tier_id)
		var tier_result := Resolution.resolve_cast(tier_caster, tier_center, [tier_caster, tier_center, tier_inside, tier_outside], tier_id, tier_fields, tier_loop["skill_book"], tier_loop["skill_target_data"], tier_loop["equipment_items"], tier_caster["coord"], tier_loop["map_size"], func(_n): return 0, tier_center["coord"])
		var tier_receipts: Array = tier_result.get("receipt", {}).get("affected_targets", [])
		check(tier_result.get("ok", false) and tier_result["receipt"].get("magic_key") == row[2] and tier_receipts.map(func(receipt): return receipt["defender_id"]) == ["leonard", "enemy023_1"] and tier_result["caster_changes"]["mp"] == 200 - int(row[4]), "%s reaches its far center, hits both footprint units, skips the one outside and pays %d MP once" % [tier_id, row[4]])
		check(tier_receipts.size() == 2 and int(tier_receipts[0]["damage"]) > 0 and int(tier_receipts[1]["damage"]) == int(tier_receipts[0]["damage"]) * 20 / 100, "each footprint target applies its own %s resistance to the same roll: " % row[2] + tier_id)
		# Player path: a member who learned the row picks it from the magic menu and settles at a chosen cell.
		var learned := controlled_skill_target()
		own(learned, "skill_book")["actors"]["001"]["supported_initial_ids"].append(tier_id)
		var learner := BattlePlayLoop.unit_ref(learned, "leonard")
		learner["mp"] = 200
		learner["max_mp"] = 200
		learner["coord"] = Vector2i(8, 8)
		var learned_foe := BattlePlayLoop.unit_ref(learned, "enemy021_1")
		learned_foe["coord"] = row[5]
		learned_foe["hp"] = 900
		learned_foe["max_hp"] = 900
		var menu := BattlePlayLoop.choose_command(learned, "magic")
		check(BattlePlayLoop.magic_options(menu, "leonard").any(func(option): return option["id"] == tier_id and option["quote"]["ok"]), "the learned high-tier magic is listed and affordable in the magic menu: " + tier_id)
		var chosen_tier := BattlePlayLoop.choose_magic(menu, tier_id)
		check(chosen_tier["interaction"] == "attack_select" and chosen_tier["selected_skill_id"] == tier_id and BattlePlayLoop.attack_cells(chosen_tier).has(row[5]), "choosing it opens target selection with the source cast range: " + tier_id)
		var cast_tier := BattlePlayLoop.attack_target(chosen_tier, "enemy021_1", func(_n): return 0)
		check(cast_tier["attacked_this_action"] and BattlePlayLoop.unit(cast_tier, "leonard")["mp"] == 200 - int(row[4]) and BattlePlayLoop.unit(cast_tier, "enemy021_1")["hp"] < 900 and cast_tier["last_attack"].get("skill_id") == tier_id, "the player cast pays once, damages the center and records the skill id: " + tier_id)
	# Wave 9 lane A2 specials: 神怒 (OTHER 23, job 97 tier-2 learner) is a magicFun_Attack row on the
	# same channel1/proc0 roll as 神罰 (magicOTHER: no resistance slot); the unowned source rows
	# 百裂突刺2／獅子吼2／吸血劍2／金之手LV2 are registered under their base skill's policy.
	# [id, cost ST, target cell, off cell]
	for row in [
		["special:magicOTHER:magicCode23", 40, Vector2i(12, 8), Vector2i(11, 10)],
		["special:magicOTHER:magicCode29", 40, Vector2i(10, 8), Vector2i(8, 11)],
	]:
		var late_id: String = row[0]
		var late := controlled_skill_target()
		own(late, "skill_book")["actors"]["001"]["supported_initial_ids"].append(late_id)
		var late_caster := BattlePlayLoop.unit_ref(late, "leonard")
		late_caster["stamina"] = 60
		late_caster["coord"] = Vector2i(8, 8)
		var late_target := BattlePlayLoop.unit_ref(late, "enemy021_1")
		late_target["coord"] = row[2]
		late_target["hp"] = 900
		late_target["max_hp"] = 900
		late_target["combat_profile"]["resist_by_type"] = {"0": 80, "1": 80, "2": 80, "3": 80, "4": 80}
		var late_off := BattlePlayLoop.unit_ref(late, "enemy021_2")
		late_off["coord"] = row[3]
		late_off["hp"] = 900
		late_off["max_hp"] = 900
		var late_picked := BattlePlayLoop.choose_special(BattlePlayLoop.choose_command(late, "special"), late_id)
		check(late_picked["interaction"] == "attack_select" and late_picked["selected_skill_id"] == late_id, "the special is selectable from the special menu: " + late_id)
		check(BattlePlayLoop.attack_cells(late_picked).has(row[2]) and not BattlePlayLoop.attack_cells(late_picked).has(row[3]), "cast range follows the source range symbol: " + late_id)
		var late_hit := BattlePlayLoop.attack_target(late_picked, "enemy021_1", func(_n): return 0)
		check(late_hit["attacked_this_action"] and BattlePlayLoop.unit(late_hit, "leonard")["stamina"] == 60 - int(row[1]) and late_hit["last_attack"].get("skill_id") == late_id, "the special pays its source ST once and records its id: " + late_id)
		check(BattlePlayLoop.unit(late_hit, "enemy021_1")["hp"] < 900 and BattlePlayLoop.unit(late_hit, "enemy021_2")["hp"] == 900, "only the footprint target loses HP, fully resistant or not: " + late_id)
