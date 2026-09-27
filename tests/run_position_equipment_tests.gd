extends "res://tests/support/TestSuite.gd"
## Equipment that changes what a turn can do, each against its original returns: attack-range
## and move-then-cast accessories (original_position_equipment.json), casting equipment —
## protection／hit and the blood-robe transfer (original_casting_equipment.json) — and
## equipped movement (original_equipment_mobility.json). The real-scene movement readback is
## in run_battle_scene_runtime_tests.gd.
const Loop = preload("res://game/battle/scene/BattlePlayLoop.gd")
const LoopAI = preload("res://game/battle/scene/BattleLoopAI.gd")
const LoopCombat = preload("res://game/battle/scene/BattleLoopCombat.gd")
const Position = preload("res://game/sim/PositionCapabilityRules.gd")
const Roles = preload("res://tests/run_job_stats_tests.gd")
const Resources = preload("res://tests/run_resource_recovery_tests.gd")
const Areas = preload("res://tests/run_ai_skill_tests.gd")
const Ordinary = preload("res://tests/run_ordinary_special_tests.gd")
const Modifiers = preload("res://game/sim/StatusApplicationRules.gd")
const Recovery = preload("res://game/sim/ResourceRecoveryRules.gd")
const Mobility = preload("res://game/sim/MobilityRules.gd")
const DamageRandom = preload("res://game/sim/DamageRandomStream.gd")
const Checkpoint = preload("res://game/battle/runtime/BattleCheckpoint.gd")
const BattleFixture = preload("res://tests/support/BattleFixture.gd")
const BattleOutcome = preload("res://game/sim/BattleOutcome.gd")
const VIEW := {"camera":Vector2(320,240),"shown_story_events":[],"story_complete":true,"growth_notified_level":1}
const WIND := "magic:magicAIR:magicCode01"
const HEAL := "magic:magicWATER:magicCode06"
const CURE := "magic:magicWATER:magicCode05"
const POISON := "magic:magicAIR:magicCode05"


func _init() -> void:
	tag = "POSITION_EQUIPMENT_TESTS"


static func fixture(role: String = "026", ai: bool = false) -> Dictionary:
	var loop := Roles.fixture(role, not ai)
	var actor := Loop._unit(loop,"leonard")
	Loop._unit(loop,"enemy023_1")["battle_actor_role"] = Loop.ROLE_PLAYER
	actor["inventory"] = [232,233,236,227,218,241,0,0]
	actor["hp"] = actor["max_hp"];actor["mp"] = actor["max_mp"]
	Loop._unit(loop,"enemy021_1")["no_attack"] = true
	Loop._unit(loop,"enemy021_1")["inventory"] = [0,0,0,0,0,0,0,0]
	return loop


static func equip(loop: Dictionary, slot: String, code: int) -> Dictionary:
	return Loop.change_equipment(loop,slot,Loop.unit(loop,"leonard")["inventory"].find(code) if code else -1,code)


static func selected(loop: Dictionary, id: String = WIND) -> Dictionary:
	return Loop.choose_magic(Loop.choose_command(loop,"magic"),id)


static func moved(loop: Dictionary, at: Vector2i = Vector2i(9,8)) -> Dictionary:
	return Loop.move_unit_to(Loop.choose_command(loop,"move"),at)


static func casting_fixture(code: String = "026") -> Dictionary:
	var loop := Roles.fixture(code)
	Loop._unit(loop,"leonard")["inventory"] = [145,128,217,219,215,226,218,227]
	Loop._unit(loop,"enemy021_1")["inventory"] = [0,0,0,0,0,0,0,0]
	return loop


static func mobility_fixture() -> Dictionary:
	var loop := Ordinary.fixture()
	Loop._unit(loop,"leonard")["coord"] = Vector2i(4,8)
	Loop._unit(loop,"enemy021_1")["coord"] = Vector2i(18,8)
	Loop._unit(loop,"enemy023_1")["coord"] = Vector2i(2,2)
	Loop._unit(loop,"leonard")["inventory"] = [193,138,231,231,0,0,0,0]
	return loop


func run() -> void:
	native_cases()
	permission_cases()
	range_and_growth()
	ai_cases()
	stale_ai_choices()
	terminal_cases()
	casting_native_cases()
	equipment_cases()
	transfer_lifecycle()
	protected_spells()
	casting_ai_cases()
	casting_terminal_cases()
	await presentation_cases()
	mobility_native_cases()
	equipment_growth_cases()
	movement_cases()
	mobility_ai_cases()
	save_and_invalid_cases()


func native_cases() -> void:
	var packet: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://docs/evidence_packets/static_reverse/original_position_equipment.json"))
	for row in packet["cases"]:
		var input: Dictionary = row["input"]
		var loop := fixture()
		var actor := Loop._unit(loop,"leonard")
		actor["equipment"].append({"slot":"accessory1","item_code":232})
		own(loop, "equipment_items")["232"]["move_magic_use"] = (int(input["effects"]) & 0x1000) != 0
		own(loop, "equipment_items")["232"]["add_attack_range"] = (int(input["effects"]) & 1) != 0
		if input["kind"] in ["ai","getter"]:
			var result := Position.effects(actor,loop["skill_book"],loop["equipment_items"])
			check(result["ok"] and result["effects"]["move_magic_use"] == (bool(row["native"]["moving_search"]) if input["kind"] == "ai" else bool(row["native"]["value"])),"native source getter and AI branch agree")
		elif input["kind"] == "menu":
			var permitted := Position.cast_error(actor,loop["skill_book"],loop["equipment_items"],"magic",bool(input["moved"])) == ""
			check(row["native"]["commands"].contains("v") == (permitted and bool(input["magic"]) and not bool(input["silence"])),"original moved menu magic eligibility matches source capability")
			check(row["native"]["commands"].contains("w") == bool(input["special"]),"moving magic restriction does not suppress a special")
		elif input["kind"] == "range" and int(input["size"]) == 0 and int(input["weapon"]) == 1 and int(input["base"]) in [1,2]:
			actor["weapon_code"] = int(input["base"])
			var result := Position.attack_pattern(actor,loop["equipment_items"],loop["attack_patterns"],{"1":"range1Cell","2":"range2Cell"})
			check(result["ok"] and result["index"] == int(row["native"]["value"]),"native weapon range index advances exactly one source record")
	for row in packet["gear"]:
		var loop := fixture();var actor := Loop._unit(loop,"leonard")
		actor["equipment"] = []
		for code in row["input"]["codes"]: actor["equipment"].append({"item_code":int(code)})
		own(loop, "skill_book")["actors"]["026"]["move_magic_use"] = bool(int(row["input"]["capability"]) & 0x400)
		var result := Position.effects(actor,loop["skill_book"],loop["equipment_items"])
		var mask := (0x1000 if result["effects"]["move_magic_use"] else 0) | (1 if result["effects"]["add_attack_range"] else 0)
		for native in row["native"]:check(mask == int(native["values"]["effects"]),"full source gear refresh maps innate/current capabilities without accumulating")
	var stock := BattleFixture.loop()
	check(stock["units"].all(func(a):return not Position.effects(a,stock["skill_book"],stock["equipment_items"])["effects"]["move_magic_use"]),"default actors retain source stationary casting")
	check(stock["skill_book"]["actors"]["020"]["move_magic_use"] and stock["skill_book"]["actors"]["059"]["move_magic_use"],"later innate permissions are preserved as source data without granting a new party")


func permission_cases() -> void:
	var base := fixture();var before := base.duplicate(true)
	var walk := moved(base)
	check(Loop.unit(walk,"leonard")["coord"] == Vector2i(9,8) and not Loop.command_available(walk,"magic"),"ordinary movement accepts its position but removes magic command")
	check(not walk["command_menu"]["commands"].any(func(c):return c["command"] == "magic"),"post-move menu reflects original qualification")
	check(Loop.magic_options(walk,"leonard").all(func(o):return o["quote"]["reason"] == "magic_unavailable_after_movement"),"unavailable quotes explain the actual movement restriction")
	var forged := walk.duplicate(true);forged.merge({"interaction":"attack_select","selected_attack":"magic","selected_skill_id":WIND},true)
	var rejected := Loop.attack_target(forged,"enemy021_1",no_rng)
	check(rejected["units"] == walk["units"] and rejected["last_attack_reject"]["reason"] == "magic_unavailable_after_movement", "stale magic selection fails before payment, RNG or EXP")
	check(LoopCombat._resolve_skill(walk,"leonard","enemy021_1",WIND,Loop.skill_fields(walk,WIND),Vector2i(9,8),no_rng).is_empty(),"shared commit cannot bypass pending player movement")
	var cancel := Loop.cancel_interaction(Loop.cancel_pending_move(walk))
	check(Loop.unit(cancel,"leonard")["coord"] == Vector2i(8,8) and Loop.command_available(cancel,"magic") and base == before,"cancelling the walk restores stationary casting without mutating original state")
	var grant := equip(walk,"accessory1",232)
	check(Loop.command_available(grant,"magic") and grant["pending_move"] and grant["turn_queue"] == walk["turn_queue"],"equipping after the walk immediately enables magic without another move or turn")
	var loaded := Checkpoint.encode(grant,VIEW)
	check(loaded["ok"],"equipped pending movement is a valid checkpoint")
	if loaded["ok"]:
		var restored := Checkpoint.decode(loaded["bytes"], grant)
		check(restored["ok"] and restored["snapshot"]["loop"] == grant,"restore keeps exact moved state and current capability")
	var cast := Loop.attack_target(selected(grant),"enemy021_1",zero)
	check(not cast["last_attack"].is_empty() and Loop.unit(cast,"leonard")["mp"] == Loop.unit(grant,"leonard")["mp"] - 8,"accepted post-move spell pays once and creates one actual receipt")
	var removed := equip(grant,"accessory1",0)
	check(not Loop.command_available(removed,"magic") and removed["pending_move"],"removing the last permission revokes casting but preserves the accepted location")
	var wings := equip(fixture(),"accessory2",227)
	var again := Loop.choose_command(moved(wings),"wait")
	check(again["extra_action"]["pending"] and Loop.command_available(again,"magic") and not again["moved_this_action"],"fresh second action permits stationary casting at the new origin without movement gear")
	check(not Loop.command_available(moved(again,Vector2i(10,8)),"magic"),"movement in second action requires its own current permission")
	for condition in ["mp","silence"]:
		var limited := equip(fixture(),"accessory1",232)
		var actor := Loop._unit(limited,"leonard")
		if condition == "mp": actor["mp"] = 0
		else: actor.merge(Loop.StatusEffectRules.apply(actor,"no_magic",2)["changes"],true)
		limited = moved(limited)
		check(Loop.command_available(limited,"magic") and Loop.magic_options(limited,"leonard").all(func(o):return not o["quote"]["ok"]),"movement permission never bypasses resources or silence: "+condition)
		check(Loop.choose_magic(Loop.choose_command(limited,"magic"),WIND)["units"] == limited["units"],"unavailable post-move spell keeps resources unchanged")


func range_and_growth() -> void:
	for code in [232,233,236]:
		var before := fixture("001")
		var old_range := Loop.attack_cells(before)
		var equipped := equip(before,"accessory1",code)
		check(equipped != before,"source item can be equipped by source job: "+str(code))
		var actor := Loop.unit(equipped,"leonard")
		check(actor["move_point"] == 5 + (1 if code == 236 else 0),"combined item adds source movement once")
		check(Loop.attack_cells(equipped).size() == (old_range.size() if code == 232 else 8),"one-cell weapon gains source two-cell cross only with range ability")
		actor["exp"] = 99
		var grew := Loop.ProgressionRules.resolve_experience(actor,1,equipped["equipment_items"])
		check(Loop.weapon_pattern(equipped,grew)["index"] == Loop.weapon_pattern(equipped,actor)["index"] and grew["move_point"] == actor["move_point"],"level refresh preserves current capability and range without stacking")
		var removed := equip(equipped,"accessory1",0)
		check(Loop.attack_cells(removed) == old_range and Loop.unit(removed,"leonard")["move_point"] == 5,"removal restores base range and movement")
	var both := equip(equip(fixture("001"),"accessory1",233),"accessory2",236)
	check(Loop.weapon_pattern(both,Loop.unit(both,"leonard"))["index"] == 2,"two range sources OR instead of adding two records")
	var range := Loop.weapon_pattern(both,Loop.unit(both,"leonard"))
	check(range["offsets"].any(func(o):return Vector2i(int(o[0]),int(o[1])) == Vector2i(2,0)) and not range["offsets"].any(func(o):return Vector2i(int(o[0]),int(o[1])) == Vector2i(1,1)),"source cross is not an invented Manhattan diamond")
	var heavy := equip(fixture("024"),"accessory1",233)
	check(Loop.weapon_pattern(heavy,Loop.unit(heavy,"leonard"))["index"]==3 and Loop.attack_cells(heavy).has(Vector2i(11,8)),"source two-cell weapon gains the original three-cell cross")
	var heavy_hit := Loop.attack_target(Loop.choose_command(heavy,"attack"),"enemy021_1",zero)
	check(heavy_hit["last_attack"].get("defender_id")=="enemy021_1" and heavy_hit["last_attack"]["defender_hp_after"]>0,"extended heavy attack commits a real nonlethal exchange")
	var bare_magic := Loop.attack_cells(selected(fixture()))
	var enhanced_magic := Loop.attack_cells(selected(equip(fixture(),"accessory1",233)))
	check(bare_magic==enhanced_magic,"weapon range bonus leaves actual player magic selection cells unchanged")
	var hit := equip(fixture("001"),"accessory1",233)
	Loop._unit(hit,"enemy021_1")["coord"] = Vector2i(10,8)
	Loop._unit(hit,"enemy021_1")["hp"] = 1
	Loop._unit(hit,"leonard")["hit_bonus_accum"] = 1000
	Loop._unit(hit,"leonard")["exp"] = 99
	var resolved := Loop.attack_target(Loop.choose_command(hit,"attack"),"enemy021_1",zero)
	check(Loop.unit(resolved,"enemy021_1")["defeated"] and Loop.unit(resolved,"leonard")["level"] == 2,"extended ordinary attack reaches lethal settlement and final EXP growth")
	for bad in ["effect","source","range"]:
		var broken := both.duplicate(true)
		if bad == "effect": own(broken, "equipment_items")["236"]["move_magic_use"] = 1
		elif bad == "source": own(broken, "skill_book")["actors"]["001"].erase("move_magic_use")
		else: own(broken, "attack_patterns").erase("range2Cell")
		check(not Checkpoint.encode(broken,VIEW)["ok"],"invalid source/equipment/range checkpoint is rejected: "+bad)


func ai_cases() -> void:
	for grant in [false,true]:
		var loop := fixture("026",true);var actor := Loop._unit(loop,"leonard")
		actor["no_attack"] = true
		actor["equipment"] = actor["equipment"].filter(func(s):return not s["slot"].begins_with("accessory"))
		actor["equipment"].append({"slot":"accessory1","item_code":227})
		if grant: actor["equipment"].append({"slot":"accessory2","item_code":232})
		Loop._unit(loop,"enemy021_1")["coord"] = Vector2i(14,8)
		own(loop, "ai_profiles")["actors"]["026"]["profile"].merge({"find_range":20,"ai_att_magic":100,"ai_check_dying":0,"ai_help_otherhp":0,"ai_help_status":0},true)
		own(loop, "skill_book")["skills"]["magic:magicAIR:magicCode01"]["fields"]["use_ratio"] = "100"
		own(loop, "skill_book")["skills"]["magic:magicFIRE:magicCode01"]["fields"]["use_ratio"] = "0"
		var before := loop.duplicate(true)
		var first := Loop.step_ai_turn(loop,zero)
		check(first["scenario_ok"] and first["extra_action"]["pending"] and loop == before,"AI position decision commits one independent action: "+str(first.get("scenario_error")))
		if not first["scenario_ok"]: continue
		check(first["last_ai_action"]["kind"] == ("move_then_attack" if grant else "move"),"source permission distinguishes moved casting from preparing a future position")
		if not grant: check(Loop.unit(first,"leonard")["mp"] == actor["mp"],"pursuit without casting cannot debit magic")
		var second := Loop.step_ai_turn(first,zero)
		check(second["scenario_ok"] and second["last_ai_action"].get("skill_id") == WIND and second["selected_unit_id"] == "enemy023_1", "AI reconsiders the new origin and casts on its second action")
		check(second["last_ai_actions"].size() == 2 and second["action_end_sequence"] == 1,"two independent AI decisions share one final tail and successor")
	var support := fixture("026",true);var caster := Loop._unit(support,"leonard")
	caster["equipment"] = caster["equipment"].filter(func(s):return not s["slot"].begins_with("accessory"))
	Loop._unit(support,"enemy023_1")["coord"] = Vector2i(14,8)
	Loop._unit(support,"enemy023_1")["hp"] = 1
	Loop._unit(support,"enemy021_1")["coord"] = Vector2i(17,10) # Leave the only three-step casting square accessible.
	own(support, "skill_book")["actors"]["026"]["supported_initial_ids"] = [HEAL]
	own(support, "skill_book")["skills"][HEAL]["fields"]["use_ratio"] = "100"
	own(support, "ai_profiles")["actors"]["026"]["profile"].merge({"ai_help_otherhp":100,"ai_help_status":100,"ai_att_magic":100},true)
	var stationary := LoopAI._prepare_ai_turn(support,"leonard")
	check(stationary["ok"] and stationary["ally_support"]["heal"].is_empty(),"stationary healer cannot manufacture a moved allied cast")
	caster["equipment"].append({"slot":"accessory1","item_code":232})
	var mobile := LoopAI._prepare_ai_turn(support,"leonard")
	check(mobile["ok"] and not mobile["ally_support"]["heal"].is_empty(),"current permission adds legal allied healing positions")
	var accepted := Loop.step_ai_turn(support,zero)
	check(accepted["last_ai_action"].get("skill_id") == HEAL and accepted["last_ai_action"]["healing"] > 0,"AI commits its exact moved support proposal")


func stale_ai_choices() -> void:
	var loop := fixture("026",true)
	var actor := Loop._unit(loop,"leonard")
	actor["no_attack"]=true
	actor["equipment"]=actor["equipment"].filter(func(s):return not s["slot"].begins_with("accessory"))
	actor["equipment"].append({"slot":"accessory2","item_code":232})
	Loop._unit(loop,"enemy021_1")["coord"]=Vector2i(14,8)
	var plan := LoopAI._ai_skill_candidates(loop,"leonard",[Loop.unit(loop,"enemy021_1")],"magic")
	check(plan["ok"] and plan["targets"].has("enemy021_1"),"mobile AI generates a real stored candidate before world changes")
	if not plan["ok"] or not plan["targets"].has("enemy021_1"):return
	var choice: Dictionary = Loop.AISkillPlanning.choose(plan["targets"]["enemy021_1"],zero)["intent"]
	check(choice["destination"]!=actor["coord"],"stored candidate actually needs movement")
	for change in ["removed_permission","occupied","dead_target","no_mp","silenced"]:
		var changed := loop.duplicate(true)
		var caster := Loop._unit(changed,"leonard")
		match change:
			"removed_permission":caster["equipment"]=caster["equipment"].filter(func(s):return s["slot"]!="accessory2")
			"occupied":Loop._unit(changed,"enemy023_1")["coord"]=choice["destination"]
			"dead_target":
				# A distant bystander keeps the development fixture undecided (enemy clear
				# would otherwise end the battle before the hand-off under test).
				var bystander: Dictionary = Loop._unit(changed,"enemy021_1").duplicate(true)
				bystander.merge({"id":"enemy021_far","coord":Vector2i(0,0),"live_speed":1,"no_attack":true,"move_point":0,"base_move_point":0},true)
				changed["units"].append(bystander)
				changed["turn_queue"]=Loop.CoreTurnQueue.rebuild(changed["units"])
				Loop._unit(changed,"enemy021_1")["hp"]=0
				Loop._set_unit_defeated(changed,"enemy021_1",true)
			"no_mp":caster["mp"]=0
			"silenced":caster.merge(Loop.StatusEffectRules.apply(caster,"no_magic",2)["changes"],true)
		var before := changed.duplicate(true)
		check(LoopAI._execute_ai_skill_choice(changed,"leonard",choice,no_rng).is_empty() and changed==before,"stale candidate rejects before movement/payment/EXP: "+change)
		var fresh := Loop.step_ai_turn(changed,zero)
		check(fresh["scenario_ok"] and fresh["last_ai_actions"].size()==1 and fresh["selected_unit_id"]=="enemy023_1","normal AI entry recomputes one legitimate action and hands off: "+change)
		if change=="occupied":check(fresh["last_ai_action"].get("to")!=choice["destination"],"fresh AI cannot stand on the newly occupied target cell")


func terminal_cases() -> void:
	for outcome in ["victory","defeat","escape"]:
		var loop := equip(equip(fixture("001"),"accessory1",236),"accessory2",227)
		loop = Loop.choose_command(loop,"wait")
		var actor := Loop._unit(loop,"leonard");var target := Loop._unit(loop,"enemy021_1")
		if outcome == "escape":
			actor["coord"] = loop["escape_zone"][0];loop = Loop.choose_command(loop,"wait")
		else:
			target["coord"] = Vector2i(9,8);actor["hit_bonus_accum"] = 1000
			if outcome == "victory": target["hp"] = 1;actor["exp"] = 99
			else:
				actor["hp"] = 1;target["no_attack"] = false;target["hit_bonus_accum"] = 1000
				target["combat_profile"]["attack_back"] = 100;target["combat_profile"]["live_attack_damage"] = 1000
			loop = Loop.attack_target(Loop.choose_command(loop,"attack"),"enemy021_1",zero)
		check(loop["battle_outcome"] == {"victory":BattleOutcome.VICTORY_ENEMIES_CLEARED,"defeat":BattleOutcome.DEFEAT_FALLEN,"escape":BattleOutcome.VICTORY_ESCAPE}[outcome] and not loop["extra_action"]["pending"],"position equipment leaves terminal transaction frozen: "+outcome)
		check(Checkpoint.encode(loop,VIEW)["ok"] and Loop.finish_exhausted_action(loop) == loop,"terminal checkpoint and repeated finish cannot regrant effects")


func casting_native_cases() -> void:
	var packet: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://docs/evidence_packets/static_reverse/original_casting_equipment.json"))
	for row in packet["transfers"]:
		var c: Dictionary = row["input"]
		var loss := 0; var gain := 0
		if c["enabled"]:
			var bounds := Recovery.transfer_bounds(int(c["max_hp"]))
			check(row["draws"].size() == 2 and row["draws"].all(func(d):return int(d["bound"]) == bounds["bound"]),"original triangular transfer draw shape")
			var result := Recovery.transfer_values(int(c["max_hp"]),int(c["hp"]),int(c["max_mp"]),int(c["mp"]),int(row["draws"][0]["value"]),int(row["draws"][1]["value"]))
			loss = result["hp_loss"]; gain = result["mp_gain"]
		check(loss == row["native"]["hp_loss"] and gain == row["native"]["mp_gain"] and int(c["hp"]) - loss == row["native"]["hp"] and int(c["mp"]) + gain == row["native"]["mp"],"native actual HP loss and independently capped MP")
	for row in packet["gear"]:
		var loop := casting_fixture("001" if row["input"]["job"] == 80 else "026")
		var actor := Loop._unit(loop,"leonard")
		actor["equipment"] = []
		var accessory := 1
		for value in row["input"]["codes"]:
			var code := int(value)
			var slot := "armor" if loop["equipment_items"][str(code)]["type_code"] == 4 else "accessory" + str(accessory)
			if slot != "armor": accessory += 1
			actor["equipment"].append({"slot":slot,"item_code":code})
		var result := Modifiers.equipment_modifiers(actor,loop["equipment_items"])
		var capabilities := Recovery.effects(actor,loop["equipment_items"])
		for native in row["native"]:
			check(result["ok"] and result["effects"] == int(native["values"]["effects"]) and result["magic_hit_bonus"] == int(native["values"]["magic_hit"]),"source OR protection and additive hit agree with native refresh")
			check(capabilities["ok"] and capabilities["effects"]["hp_transfer_mp"] == (int(native["values"]["other_effects"]) == 1),"transfer uses independent equipment capability")


func equipment_cases() -> void:
	for role in ["001","024","026"]:
		for code in [128,145,217,219,215,226]:
			var before := casting_fixture(role)
			var slot := "armor" if code in [128,145] else "accessory1"
			var after := equip(before,slot,code)
			var permitted: bool = code in [217,219] or role == "026" or (role == "001" and code != 128)
			check((Loop.EquipmentRules.equipped_code(Loop.unit(after,"leonard")["equipment"],slot) == code) == permitted,"real job eligibility retained: %s/%s" % [role,code])
			if not permitted: check(after == before,"wrong-job new gear is an atomic rejection"); continue
			check(after["turn_queue"] == before["turn_queue"] and after["action_end_sequence"] == 0,"equip is free and preserves source queue snapshot")
			var actor := Loop.unit(after,"leonard")
			var twice := Loop.ProgressionRules.refresh_growth_stats(Loop.ProgressionRules.refresh_growth_stats(actor,after["equipment_items"]),after["equipment_items"])
			check(twice == actor and Checkpoint.encode(after,Resources.VIEW)["ok"],"equipped job refresh and save do not stack or lose capabilities")
	var stacked := equip(equip(casting_fixture(),"accessory1",215),"accessory2",226)
	var actor := Loop._unit(stacked,"leonard")
	check(Modifiers.modifiers(actor,stacked["skill_book"],stacked["equipment_items"])["magic_hit_bonus"] == 20,"both real accessories add magic hit once")
	actor["pending_stat_points"] = 5
	var grown := Loop.allocate_growth(stacked,"leonard",{"str":1,"dex":1,"mind":2,"con":1})
	check(Modifiers.modifiers(Loop.unit(grown,"leonard"),grown["skill_book"],grown["equipment_items"])["magic_hit_bonus"] == 20,"manual job growth retains equipped casting modifiers")
	var removed := equip(grown,"accessory2",0)
	check(Modifiers.modifiers(Loop.unit(removed,"leonard"),removed["skill_book"],removed["equipment_items"])["magic_hit_bonus"] == 10,"unequip removes only its own magic hit contribution")
	var afflicted := casting_fixture()
	var target := Loop._unit(afflicted,"leonard")
	target.merge(Loop.StatusEffectRules.apply(target,"poison",3,7)["changes"],true)
	target.merge(Loop.StatusEffectRules.apply(target,"no_magic",2)["changes"],true)
	var protected := equip(equip(afflicted,"accessory1",217),"accessory2",219)
	check(Loop.unit(protected,"leonard")["status_counters"] == target["status_counters"],"protective equip is not an antidote or silence cure")
	var unavailable := Loop.SkillResolutionRules.available(Loop.unit(protected,"leonard"),WIND,Loop.skill_fields(protected,WIND),protected["skill_book"],protected["skill_target_data"],protected["equipment_items"])
	check(not unavailable["ok"] and unavailable["reason"] == "magic_disabled_by_status","existing silence remains a real casting restriction after equip")
	for field in ["hp_transfer_mp","status_effect_flags","magic_hit_bonus"]:
		var bad := casting_fixture()
		own(bad, "equipment_items")["145"][field] = "invalid"
		check(equip(bad,"armor",145) == bad,"new invalid casting equipment must reject before exchange: "+field)


func transfer_lifecycle() -> void:
	var loop := casting_fixture()
	Loop._unit(loop,"leonard")["inventory"] = [145,223,224,227,218,0,0,0]
	loop = equip(equip(equip(loop,"armor",145),"accessory1",223),"accessory2",224)
	var actor := Loop._unit(loop,"leonard")
	actor["growth_profile"]["source"]["hit_point"] += 100
	actor.merge(Loop.ProgressionRules.refresh_growth_stats(actor,loop["equipment_items"]),true)
	actor["hp"] = 20; actor["mp"] = 0
	actor.merge(Loop.StatusEffectRules.apply(actor,"poison",3,7)["changes"],true)
	actor.merge(Loop.StatusEffectRules.apply(actor,"no_magic",2)["changes"],true)
	var before := loop.duplicate(true)
	var done := Loop.choose_command(loop,"wait")
	var tail: Dictionary = done["last_action_end"]
	check(tail["events"].map(func(e):return e["kind"]) == ["poison","auto_hp","auto_mp","transfer_hp","transfer_mp"],"one final boundary preserves full poison/restore/transfer order")
	check(tail["draws"].size() == 4 and tail["events"][3]["before"] == tail["events"][1]["after"],"conversion samples after actual HP recovery, never from stale original HP")
	check(done["selected_unit_id"] == "enemy023_1" and done["gold"] == before["gold"] and Loop.unit(done,"leonard")["exp"] == actor["exp"] and Loop.unit(done,"leonard")["status_counters"]["no_magic"] == 1,"one handoff and one status tick; conversion grants no XP or gold")
	var saved := Checkpoint.encode(done,Resources.VIEW)
	check(saved["ok"],"complete five-part tail can be saved")
	if saved["ok"]:
		var restored := Checkpoint.decode(saved["bytes"], done)
		check(restored["ok"] and restored["snapshot"]["loop"] == done and Loop.finish_exhausted_action(done) == done,"restoration cannot repeat blood loss, MP, RNG or growth")
	for hp in [1,2,30]:
		for max_mp in [0,30]:
			var target: Dictionary = actor.duplicate(true)
			target.merge({"max_hp":30,"hp":hp,"max_mp":max_mp,"mp":max_mp},true)
			var flags := {"mp_use_half":false,"hp_auto_restore":false,"mp_auto_restore":false,"hp_transfer_mp":true}
			var result := Recovery.prepare(target,flags,DamageRandom.seeded(19))
			check(result["ok"] and result["changes"]["mp"] == max_mp and result["changes"]["hp"] >= 1 and (result["changes"]["hp"] < hp) == (hp > 1),"full or nonexistent MP still costs HP but cannot kill")
			check(result["draws"].size() == 2 and result["state"] == DamageRandom.advance(DamageRandom.seeded(19),2),"1HP still consumes the two original transfer samples")
	var wings := equip(equip(casting_fixture(),"armor",145),"accessory2",227)
	Loop._unit(wings,"leonard")["mp"] = 0
	var first := Loop.choose_command(wings,"wait")
	check(first["extra_action"]["pending"] and no_draw(first, wings, "damage") and first["action_end_sequence"] == 0,"blood conversion is deferred across independent first action")
	var second_removed := equip(first,"armor",0)
	var second := Loop.choose_command(second_removed,"wait")
	check(second["selected_unit_id"] == "enemy023_1" and second["last_action_end"]["events"].is_empty() and no_draw(second, wings, "damage"),"removing blood armor on second action cancels only conversion, not the existing action latch")


func protected_spells() -> void:
	var fitted := equip(casting_fixture("001"),"accessory1",217)
	var area := Areas.area_fixture()
	Loop._unit(area,"leonard")["equipment"] = Loop.unit(fitted,"leonard")["equipment"].duplicate(true)
	var cast := LoopCombat._resolve_skill(area,"enemy026_1","leonard",POISON,Loop.skill_fields(area,POISON),Vector2i(4,6),zero)
	check(not cast.is_empty() and cast["affected_targets"].size() >= 2,"original owned poison still commits a mixed protected/unprotected area")
	if cast.is_empty(): return
	check(not Loop.StatusEffectRules.poisoned(Loop.unit(area,"leonard")) and Loop.StatusEffectRules.poisoned(Loop.unit(area,"area-center")),"equipment immunity is applied per living target, not to the whole cast")
	var primary: Dictionary = cast["affected_targets"].filter(func(t):return t["defender_id"] == "leonard")[0]
	check(primary["status_effects"][0]["reason"] == "immune" and primary["native_contribution"] == 0,"immune status grants no invented contribution but remains visible")
	var source := casting_fixture()
	var caster := Loop.unit(source,"leonard")
	var target := Loop.unit(source,"enemy021_1")
	var fields := Loop.skill_fields(source,WIND).duplicate(true)
	fields["hit_ratio"] = "70" # Explicit synthetic boundary; original formula is independently replayed.
	var plain := Modifiers.prepare(caster,target,fields,source["skill_book"],source["skill_target_data"],source["equipment_items"])
	var accurate := equip(equip(source,"accessory1",215),"accessory2",226)
	var boosted := Modifiers.prepare(Loop.unit(accurate,"leonard"),target,fields,accurate["skill_book"],accurate["skill_target_data"],accurate["equipment_items"])
	check(plain["ok"] and boosted["ok"] and boosted["roll_input"]["magic_hit_bonus"] == plain["roll_input"]["magic_hit_bonus"] + 20,"one shared magic proposal reads current equipment hit bonus")
	var rolled_plain := Modifiers.Rolls.roll(plain["roll_input"],func(bound):return 79 if bound == 100 else 0)
	var rolled_boosted := Modifiers.Rolls.roll(boosted["roll_input"],func(bound):return 79 if bound == 100 else 0)
	check(not rolled_plain["hit_check_passed"] and rolled_boosted["hit_check_passed"],"equipped accuracy changes the actual damage hit check")
	var status_input: Dictionary = boosted["roll_input"].duplicate(true)
	status_input.merge({"proc":6,"status_hit_ratio":65},true)
	var status_roll := Modifiers.Rolls.roll(status_input,func(bound):return 69 if bound == 100 else 0)
	check(not status_roll["hit_check_passed"] and status_roll["hit_rate"] == 65,"magic accuracy cannot silently raise the independent status success rate")


func casting_ai_cases() -> void:
	var area := Areas.area_fixture()
	for actor in area["units"]:
		if actor["id"] != "enemy026_1": actor["equipment"].append({"slot":"accessory2","item_code":217})
	var before := area.duplicate(true)
	var plan := LoopAI._ai_skill_candidates(area,"enemy026_1",[Loop.unit(area,"leonard")],"magic")
	check(plan["ok"] and plan["targets"]["leonard"]["skills"].all(func(s):return s["skill_id"]=="magic:magicWATER:magicCode01") and area == before,"current equipment removes useless poison proposals while preserving source025's effective water spell")
	var water := LoopAI._try_skill_turn(area,"enemy026_1",[Loop.unit(area,"leonard")],zero)
	check(water.get("magic_key")=="water" and Loop.unit(area,"enemy026_1")["mp"]==Loop.unit(before,"enemy026_1")["mp"]-8,"equipment-protected poison targets still permit one paid source-owned water fallback")
	check(area["units"].all(func(u):return not Loop.StatusEffectRules.poisoned(u)),"water fallback never applies the excluded poison effect")
	var unavailable := before.duplicate(true)
	Loop._unit(unavailable,"enemy026_1")["mp"]=7
	var unchanged := unavailable.duplicate(true)
	check(LoopAI._try_skill_turn(unavailable,"enemy026_1",[Loop.unit(unavailable,"leonard")],no_rng).is_empty() and unavailable==unchanged,"no affordable effective skill preserves equipment protection, payment and random state")
	var loop := equip(equip(casting_fixture(),"armor",145),"accessory1",218)
	var actor := Loop._unit(loop,"leonard")
	actor["growth_profile"]["source"]["hit_point"] += 100
	actor.merge(Loop.ProgressionRules.refresh_growth_stats(actor,loop["equipment_items"]),true)
	actor.merge({"hp":actor["max_hp"],"mp":0,"live_speed":120,"player_commandable":false,"battle_actor_role":Loop.ROLE_FRIENDLY,"no_attack":true,"inventory":[0,0,0,0,0,0,0,0]},true)
	actor["growth_profile"]["allocation"] = "fixed_template"
	Loop._unit(loop,"enemy021_1")["no_attack"] = true
	own(loop, "ai_profiles")["actors"]["026"]["profile"].merge({"ai_att_magic":100,"ai_check_dying":0,"ai_help_selfhp":0,"ai_help_otherhp":0,"ai_help_status":0,"find_range":20},true)
	own(loop, "skill_book")["skills"]["magic:magicAIR:magicCode01"]["fields"]["use_ratio"] = "100"
	own(loop, "skill_book")["skills"]["magic:magicFIRE:magicCode01"]["fields"]["use_ratio"] = "0"
	loop["turn_queue"] = Loop.CoreTurnQueue.rebuild(loop["units"])
	var first := Loop.step_ai_turn(Roles.ai_start(loop),zero)
	check(first["scenario_ok"] and not first["last_ai_action"].has("skill_id") and Loop.unit(first,"leonard")["mp"] >= 4,"zero-MP AI falls back before conversion enables a later cast")
	var following := Loop.choose_command(first,"wait")
	for _step in range(8):
		if Loop.CoreTurnQueue.current(following["turn_queue"])["id"] == "leonard": break
		following = Loop.step_ai_turn(following,zero)
	var mp_before := int(Loop.unit(following,"leonard")["mp"])
	var second := Loop.step_ai_turn(following,zero)
	check(second["scenario_ok"] and second["last_ai_action"].get("skill_id") == WIND and second["last_action_end"]["before"]["mp"] == mp_before - 4,"next actual queue cycle redecides a reduced-cost spell using converted MP")


func casting_terminal_cases() -> void:
	for ending in [BattleOutcome.VICTORY_ENEMIES_CLEARED,BattleOutcome.DEFEAT_FALLEN,BattleOutcome.VICTORY_ESCAPE]:
		var loop := equip(equip(casting_fixture("001"),"armor",145),"accessory2",227)
		loop = Loop.choose_command(loop,"wait")
		var actor := Loop._unit(loop,"leonard")
		actor["coord"] = Vector2i(10,8); actor["hit_bonus_accum"] = 1000; actor["exp"] = 99
		if ending == BattleOutcome.VICTORY_ENEMIES_CLEARED: Loop._unit(loop,"enemy021_1")["hp"] = 1
		elif ending == BattleOutcome.DEFEAT_FALLEN:
			actor["hp"] = 1
			Loop._unit(loop,"enemy021_1")["combat_profile"].merge({"attack_back":100,"live_attack_damage":1000},true)
		else: actor["coord"] = loop["escape_zone"][0]
		var done := Loop.choose_command(loop,"wait") if ending == BattleOutcome.VICTORY_ESCAPE else Loop.attack_target(Loop.choose_command(loop,"attack"),"enemy021_1",zero)
		check(done["battle_outcome"] == ending and done["action_end_sequence"] == 0 and no_draw(done, loop, "damage") and not done["extra_action"]["pending"],"real terminal action cancels blood transfer and leftover extra action: "+BattleOutcome.describe(ending))
		check(Checkpoint.encode(done,Resources.VIEW)["ok"] and Loop.choose_command(done,"wait") == done,"terminal persistence remains frozen")
		if ending == BattleOutcome.VICTORY_ENEMIES_CLEARED: check(Loop.unit(done,"leonard")["level"] == 2,"terminal killing blow retains final EXP before freeze")


func presentation_cases() -> void:
	var cue = preload("res://game/battle/scene/BattleTurnEndCue.gd").new()
	root.add_child(cue)
	var loop := equip(casting_fixture(),"armor",145)
	Loop._unit(loop,"leonard")["mp"] = 0
	loop = Loop.choose_command(loop,"wait")
	var before := loop.duplicate(true)
	for index in range(2):
		cue.refresh(loop,Vector2(320,240),true,0 if index == 0 else cue.EVENT_SECONDS)
		# The number alone (UI6: no 轉化 caption, no HP／MP suffix, no sign glyph): the loss beat in the red kind-0 glyphs, the gain in the blue MP glyphs.
		var number = cue.numbers[cue.cursor]
		check(number != null and number.text.is_valid_int() and number.kind == ("damage" if index == 0 else "mp") and not cue.label.visible and cue.busy(loop),"blood loss and MP gain have distinct ordered visible beats")
	cue.refresh(loop,Vector2(320,240),true,cue.NUMBER_SECONDS)  # last number lives 46 ticks
	check(not cue.busy(loop) and loop == before,"both conversion beats release without another resource transaction")
	cue.queue_free();await process_frame


func mobility_native_cases() -> void:
	var packet: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://docs/evidence_packets/static_reverse/original_equipment_mobility.json"))
	var loop := BattleFixture.loop()
	check(loop["scenario_ok"] and loop["units"].all(func(unit):return Mobility.saved_error(unit,loop["equipment_items"]) == ""),"source first-battle initialization produces consistent base/equipped movement")
	var scenario := Loop.BattleScenario.load_file("res://content/battles/battle_052.json")
	var second := Loop.create([],"",scenario)
	check(second["scenario_ok"] and second["units"].all(func(unit):return Mobility.saved_error(unit,second["equipment_items"]) == ""),"shared second-battle scenario uses the same source mobility")
	for row in packet["cases"]:
		var data: Dictionary = row["input"]
		var actor := {"base_move_point":int(data["base"]),"equipment":[]}
		var bonus := 0
		for index in range(6):
			var code := int(data["equipment"][index])
			if code:
				actor["equipment"].append({"slot":Mobility.SLOTS[index],"item_code":code})
				bonus += int(loop["equipment_items"][str(code)]["effects"]["move_point"])
		for result in row["native"]:
			check(Mobility.value(int(data["base"]),bonus) == int(result["move_point"]),"source signed sum and final0..12 equal the full original refresh")
		if int(data["base"]) >= 0:
			var prepared := Mobility.prepare(actor,loop["equipment_items"])
			check(prepared["ok"] and prepared["value"] == row["native"][0]["move_point"],"live source/equipment adapter agrees with native mobility")
	for code in [138,193,231,236]: check(loop["equipment_items"][str(code)]["supported"],"source mobility equipment is enabled: " + str(code))
	check(not loop["equipment_items"]["194"]["supported"],"unresolved source add_defnese spelling remains rejected")


func equipment_growth_cases() -> void:
	var loop := mobility_fixture()
	var original := loop.duplicate(true)
	var actor := Loop.unit(loop,"leonard")
	var original_foot: int = Loop.EquipmentRules.equipped_code(actor["equipment"],"foot")
	for row in [["foot",193,6],["armor",138,7],["accessory1",231,8],["accessory2",231,9]]:
		loop = equip(loop,row[0],row[1])
		actor = Loop.unit(loop,"leonard")
		check(actor["move_point"] == row[2] and actor["base_move_point"] == 5,"each confirmed piece contributes once to the same live movement")
		check(loop["turn_queue"] == original["turn_queue"] and actor["stamina"] == Loop.unit(original,"leonard")["stamina"],"free mobility exchange preserves queue and stamina")
		for _repeat in range(3): actor = Loop.ProgressionRules.refresh_growth_stats(actor,loop["equipment_items"])
		check(actor["move_point"] == row[2],"repeated refresh cannot compound equipped movement")
	actor = Loop._unit(loop,"leonard")
	actor["hp"] = 17; actor["exp"] = 99
	var levelled := Loop.ProgressionRules.resolve_experience(actor,1,loop["equipment_items"])
	check(levelled["level"] == 2 and levelled["move_point"] == 9 and levelled["hp"] == 17,"native level refresh preserves mobility equipment without healing")
	var grown := Loop.ProgressionRules.apply_allocation(levelled,{"str":2,"dex":1,"mind":1,"con":1},loop["equipment_items"])
	check(grown["move_point"] == 9 and grown["base_move_point"] == 5 and grown["pending_stat_points"] == 0,"four-stat growth never substitutes dexterity/speed for movement")
	var restored := equip(loop,"foot",original_foot)
	check(Loop.unit(restored,"leonard")["move_point"] == 8,"replacing boots removes just that item's movement")
	var removed := equip(restored,"accessory2",0)
	check(Loop.unit(removed,"leonard")["move_point"] == 7,"removing one duplicate accessory preserves the other slot's bonus")
	var cap := Loop.unit(loop,"leonard")
	cap["base_move_point"] = 11
	cap = Loop.ProgressionRules.refresh_growth_stats(cap,loop["equipment_items"])
	check(cap["move_point"] == 12,"final cap applies after all additive equipment, not before each piece")
	check(Loop.unit(original,"leonard")["move_point"] == 5 and Loop.unit(original,"leonard")["inventory"] == [193,138,231,231,0,0,0,0],"pure exchange and refresh do not mutate the source battle")


func movement_cases() -> void:
	var loop := mobility_fixture()
	var origin: Vector2i = Loop.unit(loop,"leonard")["coord"]
	var target := origin + Vector2i(6,0)
	var before_cells := Loop.movement_cells(loop)
	check(not before_cells.has(target),"source base5 excludes the six-cost destination")
	loop = equip(loop,"foot",193)
	var path := Loop.movement_path(loop,"leonard",target)
	check(Loop.movement_cells(loop).has(target) and path.size() == 7 and path.front() == origin and path.back() == target,"equipped range and world path share the new6 budget")
	var moved := Loop.move_unit_to(Loop.choose_command(loop,"move"),target)
	check(moved["pending_move"] and Loop.unit(moved,"leonard")["coord"] == target,"newly reached cell commits through ordinary Move")
	var old_foot: int = Loop.unit(moved,"leonard")["inventory"].filter(func(code):return code >= 181 and code < 193)[0]
	var reduced := equip(moved,"foot",old_foot)
	check(Loop.unit(reduced,"leonard")["move_point"] == 5 and reduced["pending_move"] and Loop.unit(reduced,"leonard")["coord"] == target,"decreased budget does not teleport or undo the accepted pending walk")
	var saved := reduced.duplicate(true)
	var cancelled := Loop.cancel_pending_move(reduced)
	check(cancelled["interaction"] == "move_select" and Loop.unit(cancelled,"leonard")["coord"] == origin and not Loop.movement_cells(cancelled).has(target),"cancelling returns to the origin and recomputes with current equipment")
	check(Loop.unit(cancelled,"leonard")["inventory"] == Loop.unit(reduced,"leonard")["inventory"] and reduced == saved,"movement cancellation cannot resurrect old boots or change confirmed inventory")
	check(Loop.move_unit_to(cancelled,target)["units"] == cancelled["units"],"a stale highlighted farther cell is rejected after movement shrink")
	var wait := Loop.begin_wait_resolution(reduced)
	check(wait["selected_unit_id"] == "enemy023_1" and wait["turn_queue"]["index"] == 1 and Loop.unit(wait,"leonard")["coord"] == target,"Wait commits the accepted position and hands off exactly once")
	var blocked := equip(mobility_fixture(),"foot",193)
	own(blocked, "tiles")[origin + Vector2i(1,0)] = {"blocks_movement":true,"move_cost":1,"movement_flags":0}
	check(Loop.movement_path(blocked,"leonard",target).is_empty(),"one mobility bonus does not bypass a blocked detour whose full cost is8")
	var stacked := equip(equip(blocked,"armor",138),"accessory1",231)
	check(not Loop.movement_path(stacked,"leonard",target).is_empty(),"stacked bonuses legitimately pay the longer shared route")


static func mobility_ai_fixture(with_boots: bool) -> Dictionary:
	var loop := mobility_fixture()
	var ai := Loop._unit(loop,"enemy021_1")
	ai["coord"] = Vector2i(4,8); ai["live_speed"] = 120; ai["hp"] = 100; ai["max_hp"] = 100
	Loop._unit(loop,"leonard")["coord"] = Vector2i(11,8)
	ai["equipment"] = ai["equipment"].filter(func(slot):return slot["slot"] != "foot")
	if with_boots: ai["equipment"].append({"slot":"foot","item_code":193,"name":"舞空之靴"})
	ai["move_point"] = Mobility.prepare(ai,loop["equipment_items"])["value"]
	own(loop, "ai_profiles")["actors"]["021"]["profile"].merge({"find_range":30,"ai_check_dying":0,"ai_help_selfhp":0,"ai_help_otherhp":0,"ai_help_status":0,"ai_att_magic":0},true)
	loop["turn_queue"] = Loop.CoreTurnQueue.rebuild(loop["units"])
	loop["interaction"] = "ai_resolving"
	return loop


func mobility_ai_cases() -> void:
	for with_boots in [false,true]:
		var loop := mobility_ai_fixture(with_boots)
		var before := loop.duplicate(true)
		var after := Loop.step_ai_turn(loop,func(_n):return 0)
		var action: Dictionary = after["last_ai_action"]
		check(after["scenario_ok"] and action["kind"] == ("move_then_attack" if with_boots else "move"),"AI plans with the same current equipped movement as players")
		check(loop == before and after["last_ai_actions"].size() == 1,"changing mobility cannot duplicate AI movement or actions")
		if not with_boots: check(Loop.unit(after,"leonard")["hp"] == Loop.unit(loop,"leonard")["hp"],"unreachable attack remains pursuit without early damage")
	var invalid := mobility_ai_fixture(true)
	Loop._unit(invalid,"enemy021_1").erase("base_move_point")
	var denied := Loop.step_ai_turn(invalid,no_rng)
	check(not denied["scenario_ok"] and denied["units"] == invalid["units"] and denied["turn_queue"] == invalid["turn_queue"],"invalid source mobility stops AI preflight before RNG or movement")


func save_and_invalid_cases() -> void:
	var loop := equip(mobility_fixture(),"foot",193)
	loop = Loop.move_unit_to(Loop.choose_command(loop,"move"),Vector2i(10,8))
	var view := {"camera":Vector2(320,240),"shown_story_events":[],"story_complete":false,"growth_notified_level":1}
	var encoded := Checkpoint.encode(loop,view)
	check(encoded["ok"],"quiet pending movement with equipped budget can be saved")
	if encoded["ok"]:
		var restored := Checkpoint.decode(encoded["bytes"], loop)
		check(restored["ok"] and restored["snapshot"]["loop"] == loop,"base, current movement, equipment and pending origin survive exact restore")
		var cancel := Loop.cancel_pending_move(restored["snapshot"]["loop"])
		check(Loop.unit(cancel,"leonard")["move_point"] == 6 and Loop.movement_cells(cancel).has(Vector2i(10,8)),"restored pending walk can be cancelled and selected again with the same budget")
	for field in ["base_move_point","move_point"]:
		var bad := loop.duplicate(true)
		Loop._unit(bad,"leonard")[field] += 1
		check(not Checkpoint.encode(bad,view)["ok"],"save rejects inconsistent base/equipped movement: " + field)
	for value in [null,true,1.5,NAN,INF,10001]:
		var bad := mobility_fixture()
		own(bad, "equipment_items")["193"]["effects"]["move_point"] = value
		var refused := equip(bad,"foot",193)
		check(refused["units"] == bad["units"] and refused["turn_queue"] == bad["turn_queue"] and refused["interaction"] == bad["interaction"],"malformed candidate bonus cannot partially exchange or refresh: " + str(value))
	var bad_source := mobility_fixture()
	Loop._unit(bad_source,"leonard").erase("base_move_point")
	check(equip(bad_source,"foot",193) == bad_source,"missing source never infers a new base from the currently equipped movement")
	var capped := mobility_fixture()
	Loop._unit(capped,"leonard")["inventory"] = [194,236,0,0,0,0,0,0]
	check(equip(capped,"foot",194) == capped,"unknown companion fields remain rejected through the actual equipment API")
	var necklace := equip(capped,"accessory1",236)
	check(Loop.unit(necklace,"leonard")["move_point"] == 6 and Loop.weapon_pattern(necklace,Loop.unit(necklace,"leonard"))["index"] == 2,"proven necklace combines movement and source weapon range without a second refresh")
