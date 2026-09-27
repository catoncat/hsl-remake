extends "res://tests/support/TestSuite.gd"
## Equipment that changes what a turn can do, each against its original returns: attack-range
## and move-then-cast accessories (original_position_equipment.json), casting equipment —
## protection／hit and the blood-robe transfer (original_casting_equipment.json) — and
## equipped movement (original_equipment_mobility.json). The real-scene movement readback is
## in run_battle_scene_runtime_tests.gd.
const BattlePlayLoop = preload("res://game/sim/loop/BattlePlayLoop.gd")
const BattleLoopAI = preload("res://game/sim/loop/BattleLoopAI.gd")
const BattleLoopCombat = preload("res://game/sim/loop/BattleLoopCombat.gd")
const PositionCapabilityRules = preload("res://game/sim/PositionCapabilityRules.gd")
const run_job_stats_tests = preload("res://tests/run_job_stats_tests.gd")
const run_resource_recovery_tests = preload("res://tests/run_resource_recovery_tests.gd")
const run_ai_skill_tests = preload("res://tests/run_ai_skill_tests.gd")
const run_ordinary_special_tests = preload("res://tests/run_ordinary_special_tests.gd")
const StatusApplicationRules = preload("res://game/sim/StatusApplicationRules.gd")
const ResourceRecoveryRules = preload("res://game/sim/ResourceRecoveryRules.gd")
const MobilityRules = preload("res://game/sim/MobilityRules.gd")
const BattleCheckpoint = preload("res://game/battle/runtime/BattleCheckpoint.gd")
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
	var loop := run_job_stats_tests.fixture(role, not ai)
	var actor := BattlePlayLoop._unit(loop,"leonard")
	BattlePlayLoop._unit(loop,"enemy023_1")["battle_actor_role"] = BattlePlayLoop.ROLE_PLAYER
	actor["inventory"] = [232,233,236,227,218,241,0,0]
	actor["hp"] = actor["max_hp"];actor["mp"] = actor["max_mp"]
	BattlePlayLoop._unit(loop,"enemy021_1")["no_attack"] = true
	BattlePlayLoop._unit(loop,"enemy021_1")["inventory"] = [0,0,0,0,0,0,0,0]
	return loop


static func equip(loop: Dictionary, slot: String, code: int) -> Dictionary:
	return BattlePlayLoop.change_equipment(loop,slot,BattlePlayLoop.unit(loop,"leonard")["inventory"].find(code) if code else -1,code)


static func selected(loop: Dictionary, id: String = WIND) -> Dictionary:
	return BattlePlayLoop.choose_magic(BattlePlayLoop.choose_command(loop,"magic"),id)


static func moved(loop: Dictionary, at: Vector2i = Vector2i(9,8)) -> Dictionary:
	return BattlePlayLoop.move_unit_to(BattlePlayLoop.choose_command(loop,"move"),at)


static func casting_fixture(code: String = "026") -> Dictionary:
	var loop := run_job_stats_tests.fixture(code)
	BattlePlayLoop._unit(loop,"leonard")["inventory"] = [145,128,217,219,215,226,218,227]
	BattlePlayLoop._unit(loop,"enemy021_1")["inventory"] = [0,0,0,0,0,0,0,0]
	return loop


static func mobility_fixture() -> Dictionary:
	var loop := run_ordinary_special_tests.fixture()
	BattlePlayLoop._unit(loop,"leonard")["coord"] = Vector2i(4,8)
	BattlePlayLoop._unit(loop,"enemy021_1")["coord"] = Vector2i(18,8)
	BattlePlayLoop._unit(loop,"enemy023_1")["coord"] = Vector2i(2,2)
	BattlePlayLoop._unit(loop,"leonard")["inventory"] = [193,138,231,231,0,0,0,0]
	return loop


func run() -> void:
	native_cases()
	permission_cases()
	range_and_growth()
	casting_native_cases()
	equipment_cases()
	transfer_lifecycle()
	protected_spells()
	mobility_native_cases()
	equipment_growth_cases()
	movement_cases()


func native_cases() -> void:
	var packet: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://docs/evidence_packets/static_reverse/original_position_equipment.json"))
	for row in packet["cases"]:
		var input: Dictionary = row["input"]
		var loop := fixture()
		var actor := BattlePlayLoop._unit(loop,"leonard")
		actor["equipment"].append({"slot":"accessory1","item_code":232})
		own(loop, "equipment_items")["232"]["move_magic_use"] = (int(input["effects"]) & 0x1000) != 0
		own(loop, "equipment_items")["232"]["add_attack_range"] = (int(input["effects"]) & 1) != 0
		if input["kind"] in ["ai","getter"]:
			var result := PositionCapabilityRules.effects(actor,loop["skill_book"],loop["equipment_items"])
			check(result["ok"] and result["effects"]["move_magic_use"] == (bool(row["native"]["moving_search"]) if input["kind"] == "ai" else bool(row["native"]["value"])),"native source getter and AI branch agree")
		elif input["kind"] == "menu":
			var permitted := PositionCapabilityRules.cast_error(actor,loop["skill_book"],loop["equipment_items"],"magic",bool(input["moved"])) == ""
			check(row["native"]["commands"].contains("v") == (permitted and bool(input["magic"]) and not bool(input["silence"])),"original moved menu magic eligibility matches source capability")
			check(row["native"]["commands"].contains("w") == bool(input["special"]),"moving magic restriction does not suppress a special")
		elif input["kind"] == "range" and int(input["size"]) == 0 and int(input["weapon"]) == 1 and int(input["base"]) in [1,2]:
			actor["weapon_code"] = int(input["base"])
			var result := PositionCapabilityRules.attack_pattern(actor,loop["equipment_items"],loop["attack_patterns"],{"1":"range1Cell","2":"range2Cell"})
			check(result["ok"] and result["index"] == int(row["native"]["value"]),"native weapon range index advances exactly one source record")
	for row in packet["gear"]:
		var loop := fixture();var actor := BattlePlayLoop._unit(loop,"leonard")
		actor["equipment"] = []
		for code in row["input"]["codes"]: actor["equipment"].append({"item_code":int(code)})
		own(loop, "skill_book")["actors"]["026"]["move_magic_use"] = bool(int(row["input"]["capability"]) & 0x400)
		var result := PositionCapabilityRules.effects(actor,loop["skill_book"],loop["equipment_items"])
		var mask := (0x1000 if result["effects"]["move_magic_use"] else 0) | (1 if result["effects"]["add_attack_range"] else 0)
		for native in row["native"]:check(mask == int(native["values"]["effects"]),"full source gear refresh maps innate/current capabilities without accumulating")
	var stock := BattleFixture.loop()
	check(stock["units"].all(func(a):return not PositionCapabilityRules.effects(a,stock["skill_book"],stock["equipment_items"])["effects"]["move_magic_use"]),"default actors retain source stationary casting")
	check(stock["skill_book"]["actors"]["020"]["move_magic_use"] and stock["skill_book"]["actors"]["059"]["move_magic_use"],"later innate permissions are preserved as source data without granting a new party")


func permission_cases() -> void:
	var base := fixture();var before := base.duplicate(true)
	var walk := moved(base)
	check(BattlePlayLoop.unit(walk,"leonard")["coord"] == Vector2i(9,8) and not BattlePlayLoop.command_available(walk,"magic"),"ordinary movement accepts its position but removes magic command")
	check(not walk["command_menu"]["commands"].any(func(c):return c["command"] == "magic"),"post-move menu reflects original qualification")
	check(BattlePlayLoop.magic_options(walk,"leonard").all(func(o):return o["quote"]["reason"] == "magic_unavailable_after_movement"),"unavailable quotes explain the actual movement restriction")
	var forged := walk.duplicate(true);forged.merge({"interaction":"attack_select","selected_attack":"magic","selected_skill_id":WIND},true)
	var rejected := BattlePlayLoop.attack_target(forged,"enemy021_1",no_rng)
	check(rejected["units"] == walk["units"] and rejected["last_attack_reject"]["reason"] == "magic_unavailable_after_movement", "stale magic selection fails before payment, RNG or EXP")
	check(BattleLoopCombat._resolve_skill(walk,"leonard","enemy021_1",WIND,BattlePlayLoop.skill_fields(walk,WIND),Vector2i(9,8),no_rng).is_empty(),"shared commit cannot bypass pending player movement")
	var cancel := BattlePlayLoop.cancel_interaction(BattlePlayLoop.cancel_pending_move(walk))
	check(BattlePlayLoop.unit(cancel,"leonard")["coord"] == Vector2i(8,8) and BattlePlayLoop.command_available(cancel,"magic") and base == before,"cancelling the walk restores stationary casting without mutating original state")
	var grant := equip(walk,"accessory1",232)
	check(BattlePlayLoop.command_available(grant,"magic") and grant["pending_move"] and grant["turn_queue"] == walk["turn_queue"],"equipping after the walk immediately enables magic without another move or turn")
	var loaded := BattleCheckpoint.encode(grant,VIEW)
	check(loaded["ok"],"equipped pending movement is a valid checkpoint")
	if loaded["ok"]:
		var restored := BattleCheckpoint.decode(loaded["bytes"], grant)
		check(restored["ok"] and restored["snapshot"]["loop"] == grant,"restore keeps exact moved state and current capability")
	var cast := BattlePlayLoop.attack_target(selected(grant),"enemy021_1",zero)
	check(not cast["last_attack"].is_empty() and BattlePlayLoop.unit(cast,"leonard")["mp"] == BattlePlayLoop.unit(grant,"leonard")["mp"] - 8,"accepted post-move spell pays once and creates one actual receipt")
	var removed := equip(grant,"accessory1",0)
	check(not BattlePlayLoop.command_available(removed,"magic") and removed["pending_move"],"removing the last permission revokes casting but preserves the accepted location")
	var wings := equip(fixture(),"accessory2",227)
	var again := BattlePlayLoop.choose_command(moved(wings),"wait")
	check(again["extra_action"]["pending"] and BattlePlayLoop.command_available(again,"magic") and not again["moved_this_action"],"fresh second action permits stationary casting at the new origin without movement gear")
	check(not BattlePlayLoop.command_available(moved(again,Vector2i(10,8)),"magic"),"movement in second action requires its own current permission")
	for condition in ["mp","silence"]:
		var limited := equip(fixture(),"accessory1",232)
		var actor := BattlePlayLoop._unit(limited,"leonard")
		if condition == "mp": actor["mp"] = 0
		else: actor.merge(BattlePlayLoop.StatusEffectRules.apply(actor,"no_magic",2)["changes"],true)
		limited = moved(limited)
		check(BattlePlayLoop.command_available(limited,"magic") and BattlePlayLoop.magic_options(limited,"leonard").all(func(o):return not o["quote"]["ok"]),"movement permission never bypasses resources or silence: "+condition)
		check(BattlePlayLoop.choose_magic(BattlePlayLoop.choose_command(limited,"magic"),WIND)["units"] == limited["units"],"unavailable post-move spell keeps resources unchanged")


func range_and_growth() -> void:
	for code in [232,233,236]:
		var before := fixture("001")
		var old_range := BattlePlayLoop.attack_cells(before)
		var equipped := equip(before,"accessory1",code)
		check(equipped != before,"source item can be equipped by source job: "+str(code))
		var actor := BattlePlayLoop.unit(equipped,"leonard")
		check(actor["move_point"] == 5 + (1 if code == 236 else 0),"combined item adds source movement once")
		check(BattlePlayLoop.attack_cells(equipped).size() == (old_range.size() if code == 232 else 8),"one-cell weapon gains source two-cell cross only with range ability")
		actor["exp"] = 99
		var grew := BattlePlayLoop.ProgressionRules.resolve_experience(actor,1,equipped["equipment_items"])
		check(BattlePlayLoop.weapon_pattern(equipped,grew)["index"] == BattlePlayLoop.weapon_pattern(equipped,actor)["index"] and grew["move_point"] == actor["move_point"],"level refresh preserves current capability and range without stacking")
		var removed := equip(equipped,"accessory1",0)
		check(BattlePlayLoop.attack_cells(removed) == old_range and BattlePlayLoop.unit(removed,"leonard")["move_point"] == 5,"removal restores base range and movement")
	var both := equip(equip(fixture("001"),"accessory1",233),"accessory2",236)
	check(BattlePlayLoop.weapon_pattern(both,BattlePlayLoop.unit(both,"leonard"))["index"] == 2,"two range sources OR instead of adding two records")
	var range := BattlePlayLoop.weapon_pattern(both,BattlePlayLoop.unit(both,"leonard"))
	check(range["offsets"].any(func(o):return Vector2i(int(o[0]),int(o[1])) == Vector2i(2,0)) and not range["offsets"].any(func(o):return Vector2i(int(o[0]),int(o[1])) == Vector2i(1,1)),"source cross is not an invented Manhattan diamond")
	var heavy := equip(fixture("024"),"accessory1",233)
	check(BattlePlayLoop.weapon_pattern(heavy,BattlePlayLoop.unit(heavy,"leonard"))["index"]==3 and BattlePlayLoop.attack_cells(heavy).has(Vector2i(11,8)),"source two-cell weapon gains the original three-cell cross")
	var heavy_hit := BattlePlayLoop.attack_target(BattlePlayLoop.choose_command(heavy,"attack"),"enemy021_1",zero)
	check(heavy_hit["last_attack"].get("defender_id")=="enemy021_1" and heavy_hit["last_attack"]["defender_hp_after"]>0,"extended heavy attack commits a real nonlethal exchange")
	var bare_magic := BattlePlayLoop.attack_cells(selected(fixture()))
	var enhanced_magic := BattlePlayLoop.attack_cells(selected(equip(fixture(),"accessory1",233)))
	check(bare_magic==enhanced_magic,"weapon range bonus leaves actual player magic selection cells unchanged")
	var hit := equip(fixture("001"),"accessory1",233)
	BattlePlayLoop._unit(hit,"enemy021_1")["coord"] = Vector2i(10,8)
	BattlePlayLoop._unit(hit,"enemy021_1")["hp"] = 1
	BattlePlayLoop._unit(hit,"leonard")["hit_bonus_accum"] = 1000
	BattlePlayLoop._unit(hit,"leonard")["exp"] = 99
	var resolved := BattlePlayLoop.attack_target(BattlePlayLoop.choose_command(hit,"attack"),"enemy021_1",zero)
	check(BattlePlayLoop.unit(resolved,"enemy021_1")["defeated"] and BattlePlayLoop.unit(resolved,"leonard")["level"] == 2,"extended ordinary attack reaches lethal settlement and final EXP growth")
	for bad in ["effect","source","range"]:
		var broken := both.duplicate(true)
		if bad == "effect": own(broken, "equipment_items")["236"]["move_magic_use"] = 1
		elif bad == "source": own(broken, "skill_book")["actors"]["001"].erase("move_magic_use")
		else: own(broken, "attack_patterns").erase("range2Cell")
		check(not BattleCheckpoint.encode(broken,VIEW)["ok"],"invalid source/equipment/range checkpoint is rejected: "+bad)


func casting_native_cases() -> void:
	var packet: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://docs/evidence_packets/static_reverse/original_casting_equipment.json"))
	for row in packet["transfers"]:
		var c: Dictionary = row["input"]
		var loss := 0; var gain := 0
		if c["enabled"]:
			var bounds := ResourceRecoveryRules.transfer_bounds(int(c["max_hp"]))
			check(row["draws"].size() == 2 and row["draws"].all(func(d):return int(d["bound"]) == bounds["bound"]),"original triangular transfer draw shape")
			var result := ResourceRecoveryRules.transfer_values(int(c["max_hp"]),int(c["hp"]),int(c["max_mp"]),int(c["mp"]),int(row["draws"][0]["value"]),int(row["draws"][1]["value"]))
			loss = result["hp_loss"]; gain = result["mp_gain"]
		check(loss == row["native"]["hp_loss"] and gain == row["native"]["mp_gain"] and int(c["hp"]) - loss == row["native"]["hp"] and int(c["mp"]) + gain == row["native"]["mp"],"native actual HP loss and independently capped MP")
	for row in packet["gear"]:
		var loop := casting_fixture("001" if row["input"]["job"] == 80 else "026")
		var actor := BattlePlayLoop._unit(loop,"leonard")
		actor["equipment"] = []
		var accessory := 1
		for value in row["input"]["codes"]:
			var code := int(value)
			var slot := "armor" if loop["equipment_items"][str(code)]["type_code"] == 4 else "accessory" + str(accessory)
			if slot != "armor": accessory += 1
			actor["equipment"].append({"slot":slot,"item_code":code})
		var result := StatusApplicationRules.equipment_modifiers(actor,loop["equipment_items"])
		var capabilities := ResourceRecoveryRules.effects(actor,loop["equipment_items"])
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
			check((BattlePlayLoop.EquipmentRules.equipped_code(BattlePlayLoop.unit(after,"leonard")["equipment"],slot) == code) == permitted,"real job eligibility retained: %s/%s" % [role,code])
			if not permitted: check(after == before,"wrong-job new gear is an atomic rejection"); continue
			check(after["turn_queue"] == before["turn_queue"] and after["action_end_sequence"] == 0,"equip is free and preserves source queue snapshot")
			var actor := BattlePlayLoop.unit(after,"leonard")
			var twice := BattlePlayLoop.ProgressionRules.refresh_growth_stats(BattlePlayLoop.ProgressionRules.refresh_growth_stats(actor,after["equipment_items"]),after["equipment_items"])
			check(twice == actor and BattleCheckpoint.encode(after,run_resource_recovery_tests.VIEW)["ok"],"equipped job refresh and save do not stack or lose capabilities")
	var stacked := equip(equip(casting_fixture(),"accessory1",215),"accessory2",226)
	var actor := BattlePlayLoop._unit(stacked,"leonard")
	check(StatusApplicationRules.modifiers(actor,stacked["skill_book"],stacked["equipment_items"])["magic_hit_bonus"] == 20,"both real accessories add magic hit once")
	actor["pending_stat_points"] = 5
	var grown := BattlePlayLoop.allocate_growth(stacked,"leonard",{"str":1,"dex":1,"mind":2,"con":1})
	check(StatusApplicationRules.modifiers(BattlePlayLoop.unit(grown,"leonard"),grown["skill_book"],grown["equipment_items"])["magic_hit_bonus"] == 20,"manual job growth retains equipped casting modifiers")
	var removed := equip(grown,"accessory2",0)
	check(StatusApplicationRules.modifiers(BattlePlayLoop.unit(removed,"leonard"),removed["skill_book"],removed["equipment_items"])["magic_hit_bonus"] == 10,"unequip removes only its own magic hit contribution")
	var afflicted := casting_fixture()
	var target := BattlePlayLoop._unit(afflicted,"leonard")
	target.merge(BattlePlayLoop.StatusEffectRules.apply(target,"poison",3,7)["changes"],true)
	target.merge(BattlePlayLoop.StatusEffectRules.apply(target,"no_magic",2)["changes"],true)
	var protected := equip(equip(afflicted,"accessory1",217),"accessory2",219)
	check(BattlePlayLoop.unit(protected,"leonard")["status_counters"] == target["status_counters"],"protective equip is not an antidote or silence cure")
	var unavailable := BattlePlayLoop.SkillResolutionRules.available(BattlePlayLoop.unit(protected,"leonard"),WIND,BattlePlayLoop.skill_fields(protected,WIND),protected["skill_book"],protected["skill_target_data"],protected["equipment_items"])
	check(not unavailable["ok"] and unavailable["reason"] == "magic_disabled_by_status","existing silence remains a real casting restriction after equip")
	for field in ["hp_transfer_mp","status_effect_flags","magic_hit_bonus"]:
		var bad := casting_fixture()
		own(bad, "equipment_items")["145"][field] = "invalid"
		check(equip(bad,"armor",145) == bad,"new invalid casting equipment must reject before exchange: "+field)


func transfer_lifecycle() -> void:
	var loop := casting_fixture()
	BattlePlayLoop._unit(loop,"leonard")["inventory"] = [145,223,224,227,218,0,0,0]
	loop = equip(equip(equip(loop,"armor",145),"accessory1",223),"accessory2",224)
	var actor := BattlePlayLoop._unit(loop,"leonard")
	actor["growth_profile"]["source"]["hit_point"] += 100
	actor.merge(BattlePlayLoop.ProgressionRules.refresh_growth_stats(actor,loop["equipment_items"]),true)
	actor["hp"] = 20; actor["mp"] = 0
	actor.merge(BattlePlayLoop.StatusEffectRules.apply(actor,"poison",3,7)["changes"],true)
	actor.merge(BattlePlayLoop.StatusEffectRules.apply(actor,"no_magic",2)["changes"],true)
	var before := loop.duplicate(true)
	var done := BattlePlayLoop.choose_command(loop,"wait")
	var tail: Dictionary = done["last_action_end"]
	check(tail["events"].map(func(e):return e["kind"]) == ["poison","auto_hp","auto_mp","transfer_hp","transfer_mp"],"one final boundary preserves full poison/restore/transfer order")
	check(tail["draws"].size() == 4 and tail["events"][3]["before"] == tail["events"][1]["after"],"conversion samples after actual HP recovery, never from stale original HP")
	check(done["selected_unit_id"] == "enemy023_1" and done["gold"] == before["gold"] and BattlePlayLoop.unit(done,"leonard")["exp"] == actor["exp"] and BattlePlayLoop.unit(done,"leonard")["status_counters"]["no_magic"] == 1,"one handoff and one status tick; conversion grants no XP or gold")
	var saved := BattleCheckpoint.encode(done,run_resource_recovery_tests.VIEW)
	check(saved["ok"],"complete five-part tail can be saved")
	if saved["ok"]:
		var restored := BattleCheckpoint.decode(saved["bytes"], done)
		check(restored["ok"] and restored["snapshot"]["loop"] == done and BattlePlayLoop.finish_exhausted_action(done) == done,"restoration cannot repeat blood loss, MP, RNG or growth")
	for hp in [1,2,30]:
		for max_mp in [0,30]:
			var target: Dictionary = actor.duplicate(true)
			target.merge({"max_hp":30,"hp":hp,"max_mp":max_mp,"mp":max_mp},true)
			var flags := {"mp_use_half":false,"hp_auto_restore":false,"mp_auto_restore":false,"hp_transfer_mp":true}
			var result := ResourceRecoveryRules.prepare(target,flags,DamageRandomStream.seeded(19))
			check(result["ok"] and result["changes"]["mp"] == max_mp and result["changes"]["hp"] >= 1 and (result["changes"]["hp"] < hp) == (hp > 1),"full or nonexistent MP still costs HP but cannot kill")
			check(result["draws"].size() == 2 and result["state"] == DamageRandomStream.advance(DamageRandomStream.seeded(19),2),"1HP still consumes the two original transfer samples")
	var wings := equip(equip(casting_fixture(),"armor",145),"accessory2",227)
	BattlePlayLoop._unit(wings,"leonard")["mp"] = 0
	var first := BattlePlayLoop.choose_command(wings,"wait")
	check(first["extra_action"]["pending"] and no_draw(first, wings, "damage") and first["action_end_sequence"] == 0,"blood conversion is deferred across independent first action")
	var second_removed := equip(first,"armor",0)
	var second := BattlePlayLoop.choose_command(second_removed,"wait")
	check(second["selected_unit_id"] == "enemy023_1" and second["last_action_end"]["events"].is_empty() and no_draw(second, wings, "damage"),"removing blood armor on second action cancels only conversion, not the existing action latch")


func protected_spells() -> void:
	var fitted := equip(casting_fixture("001"),"accessory1",217)
	var area := run_ai_skill_tests.area_fixture()
	BattlePlayLoop._unit(area,"leonard")["equipment"] = BattlePlayLoop.unit(fitted,"leonard")["equipment"].duplicate(true)
	var cast := BattleLoopCombat._resolve_skill(area,"enemy026_1","leonard",POISON,BattlePlayLoop.skill_fields(area,POISON),Vector2i(4,6),zero)
	check(not cast.is_empty() and cast["affected_targets"].size() >= 2,"original owned poison still commits a mixed protected/unprotected area")
	if cast.is_empty(): return
	check(not BattlePlayLoop.StatusEffectRules.poisoned(BattlePlayLoop.unit(area,"leonard")) and BattlePlayLoop.StatusEffectRules.poisoned(BattlePlayLoop.unit(area,"area-center")),"equipment immunity is applied per living target, not to the whole cast")
	var primary: Dictionary = cast["affected_targets"].filter(func(t):return t["defender_id"] == "leonard")[0]
	check(primary["status_effects"][0]["reason"] == "immune" and primary["native_contribution"] == 0,"immune status grants no invented contribution but remains visible")
	var source := casting_fixture()
	var caster := BattlePlayLoop.unit(source,"leonard")
	var target := BattlePlayLoop.unit(source,"enemy021_1")
	var fields := BattlePlayLoop.skill_fields(source,WIND).duplicate(true)
	fields["hit_ratio"] = "70" # Explicit synthetic boundary; original formula is independently replayed.
	var plain := StatusApplicationRules.prepare(caster,target,fields,source["skill_book"],source["skill_target_data"],source["equipment_items"])
	var accurate := equip(equip(source,"accessory1",215),"accessory2",226)
	var boosted := StatusApplicationRules.prepare(BattlePlayLoop.unit(accurate,"leonard"),target,fields,accurate["skill_book"],accurate["skill_target_data"],accurate["equipment_items"])
	check(plain["ok"] and boosted["ok"] and boosted["roll_input"]["magic_hit_bonus"] == plain["roll_input"]["magic_hit_bonus"] + 20,"one shared magic proposal reads current equipment hit bonus")
	var rolled_plain := StatusApplicationRules.Rolls.roll(plain["roll_input"],func(bound):return 79 if bound == 100 else 0)
	var rolled_boosted := StatusApplicationRules.Rolls.roll(boosted["roll_input"],func(bound):return 79 if bound == 100 else 0)
	check(not rolled_plain["hit_check_passed"] and rolled_boosted["hit_check_passed"],"equipped accuracy changes the actual damage hit check")
	var status_input: Dictionary = boosted["roll_input"].duplicate(true)
	status_input.merge({"proc":6,"status_hit_ratio":65},true)
	var status_roll := StatusApplicationRules.Rolls.roll(status_input,func(bound):return 69 if bound == 100 else 0)
	check(not status_roll["hit_check_passed"] and status_roll["hit_rate"] == 65,"magic accuracy cannot silently raise the independent status success rate")


func mobility_native_cases() -> void:
	var packet: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://docs/evidence_packets/static_reverse/original_equipment_mobility.json"))
	var loop := BattleFixture.loop()
	check(loop["scenario_ok"] and loop["units"].all(func(unit):return MobilityRules.saved_error(unit,loop["equipment_items"]) == ""),"source first-battle initialization produces consistent base/equipped movement")
	var scenario := BattlePlayLoop.BattleScenario.load_file("res://content/battles/battle_052.json")
	var second := BattlePlayLoop.create([],"",scenario)
	check(second["scenario_ok"] and second["units"].all(func(unit):return MobilityRules.saved_error(unit,second["equipment_items"]) == ""),"shared second-battle scenario uses the same source mobility")
	for row in packet["cases"]:
		var data: Dictionary = row["input"]
		var actor := {"base_move_point":int(data["base"]),"equipment":[]}
		var bonus := 0
		for index in range(6):
			var code := int(data["equipment"][index])
			if code:
				actor["equipment"].append({"slot":MobilityRules.SLOTS[index],"item_code":code})
				bonus += int(loop["equipment_items"][str(code)]["effects"]["move_point"])
		for result in row["native"]:
			check(MobilityRules.value(int(data["base"]),bonus) == int(result["move_point"]),"source signed sum and final0..12 equal the full original refresh")
		if int(data["base"]) >= 0:
			var prepared := MobilityRules.prepare(actor,loop["equipment_items"])
			check(prepared["ok"] and prepared["value"] == row["native"][0]["move_point"],"live source/equipment adapter agrees with native mobility")
	for code in [138,193,231,236]: check(loop["equipment_items"][str(code)]["supported"],"source mobility equipment is enabled: " + str(code))
	check(not loop["equipment_items"]["194"]["supported"],"unresolved source add_defnese spelling remains rejected")


func equipment_growth_cases() -> void:
	var loop := mobility_fixture()
	var original := loop.duplicate(true)
	var actor := BattlePlayLoop.unit(loop,"leonard")
	var original_foot: int = BattlePlayLoop.EquipmentRules.equipped_code(actor["equipment"],"foot")
	for row in [["foot",193,6],["armor",138,7],["accessory1",231,8],["accessory2",231,9]]:
		loop = equip(loop,row[0],row[1])
		actor = BattlePlayLoop.unit(loop,"leonard")
		check(actor["move_point"] == row[2] and actor["base_move_point"] == 5,"each confirmed piece contributes once to the same live movement")
		check(loop["turn_queue"] == original["turn_queue"] and actor["stamina"] == BattlePlayLoop.unit(original,"leonard")["stamina"],"free mobility exchange preserves queue and stamina")
		for _repeat in range(3): actor = BattlePlayLoop.ProgressionRules.refresh_growth_stats(actor,loop["equipment_items"])
		check(actor["move_point"] == row[2],"repeated refresh cannot compound equipped movement")
	actor = BattlePlayLoop._unit(loop,"leonard")
	actor["hp"] = 17; actor["exp"] = 99
	var levelled := BattlePlayLoop.ProgressionRules.resolve_experience(actor,1,loop["equipment_items"])
	check(levelled["level"] == 2 and levelled["move_point"] == 9 and levelled["hp"] == 17,"native level refresh preserves mobility equipment without healing")
	var grown := BattlePlayLoop.ProgressionRules.apply_allocation(levelled,{"str":2,"dex":1,"mind":1,"con":1},loop["equipment_items"])
	check(grown["move_point"] == 9 and grown["base_move_point"] == 5 and grown["pending_stat_points"] == 0,"four-stat growth never substitutes dexterity/speed for movement")
	var restored := equip(loop,"foot",original_foot)
	check(BattlePlayLoop.unit(restored,"leonard")["move_point"] == 8,"replacing boots removes just that item's movement")
	var removed := equip(restored,"accessory2",0)
	check(BattlePlayLoop.unit(removed,"leonard")["move_point"] == 7,"removing one duplicate accessory preserves the other slot's bonus")
	var cap := BattlePlayLoop.unit(loop,"leonard")
	cap["base_move_point"] = 11
	cap = BattlePlayLoop.ProgressionRules.refresh_growth_stats(cap,loop["equipment_items"])
	check(cap["move_point"] == 12,"final cap applies after all additive equipment, not before each piece")
	check(BattlePlayLoop.unit(original,"leonard")["move_point"] == 5 and BattlePlayLoop.unit(original,"leonard")["inventory"] == [193,138,231,231,0,0,0,0],"pure exchange and refresh do not mutate the source battle")


func movement_cases() -> void:
	var loop := mobility_fixture()
	var origin: Vector2i = BattlePlayLoop.unit(loop,"leonard")["coord"]
	var target := origin + Vector2i(6,0)
	var before_cells := BattlePlayLoop.movement_cells(loop)
	check(not before_cells.has(target),"source base5 excludes the six-cost destination")
	loop = equip(loop,"foot",193)
	var path := BattlePlayLoop.movement_path(loop,"leonard",target)
	check(BattlePlayLoop.movement_cells(loop).has(target) and path.size() == 7 and path.front() == origin and path.back() == target,"equipped range and world path share the new6 budget")
	var moved := BattlePlayLoop.move_unit_to(BattlePlayLoop.choose_command(loop,"move"),target)
	check(moved["pending_move"] and BattlePlayLoop.unit(moved,"leonard")["coord"] == target,"newly reached cell commits through ordinary Move")
	var old_foot: int = BattlePlayLoop.unit(moved,"leonard")["inventory"].filter(func(code):return code >= 181 and code < 193)[0]
	var reduced := equip(moved,"foot",old_foot)
	check(BattlePlayLoop.unit(reduced,"leonard")["move_point"] == 5 and reduced["pending_move"] and BattlePlayLoop.unit(reduced,"leonard")["coord"] == target,"decreased budget does not teleport or undo the accepted pending walk")
	var saved := reduced.duplicate(true)
	var cancelled := BattlePlayLoop.cancel_pending_move(reduced)
	check(cancelled["interaction"] == "move_select" and BattlePlayLoop.unit(cancelled,"leonard")["coord"] == origin and not BattlePlayLoop.movement_cells(cancelled).has(target),"cancelling returns to the origin and recomputes with current equipment")
	check(BattlePlayLoop.unit(cancelled,"leonard")["inventory"] == BattlePlayLoop.unit(reduced,"leonard")["inventory"] and reduced == saved,"movement cancellation cannot resurrect old boots or change confirmed inventory")
	check(BattlePlayLoop.move_unit_to(cancelled,target)["units"] == cancelled["units"],"a stale highlighted farther cell is rejected after movement shrink")
	var wait := BattlePlayLoop.begin_wait_resolution(reduced)
	check(wait["selected_unit_id"] == "enemy023_1" and wait["turn_queue"]["index"] == 1 and BattlePlayLoop.unit(wait,"leonard")["coord"] == target,"Wait commits the accepted position and hands off exactly once")
	var blocked := equip(mobility_fixture(),"foot",193)
	own(blocked, "tiles")[origin + Vector2i(1,0)] = {"blocks_movement":true,"move_cost":1,"movement_flags":0}
	check(BattlePlayLoop.movement_path(blocked,"leonard",target).is_empty(),"one mobility bonus does not bypass a blocked detour whose full cost is8")
	var stacked := equip(equip(blocked,"armor",138),"accessory1",231)
	check(not BattlePlayLoop.movement_path(stacked,"leonard",target).is_empty(),"stacked bonuses legitimately pay the longer shared route")
