extends "res://tests/support/TestSuite.gd"
const TargetRules = preload("res://game/sim/SkillTargetRules.gd")
const Loop = preload("res://game/battle/scene/BattlePlayLoop.gd")
const LoopAI = preload("res://game/battle/scene/BattleLoopAI.gd")
const BattleFixture = preload("res://tests/support/BattleFixture.gd")


func _init() -> void:
	tag = "SKILL_TARGET_TESTS"


func controlled() -> Dictionary:
	var loop := BattleFixture.loop()
	for index in range(loop["turn_queue"]["slots"].size()):
		if loop["turn_queue"]["slots"][index]["id"] == "leonard":
			loop["turn_queue"]["index"] = index
	Loop._unit(loop,"leonard")["stamina"] = 20
	return Loop.select_player_unit(loop,"leonard")


func run() -> void:
	var loop := controlled()
	var data: Dictionary = loop["skill_target_data"]
	var fields: Dictionary = loop["skill_book"]["skills"]["special:magicOTHER:magicCode01"]["fields"]
	var native: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://docs/evidence_packets/static_reverse/original_skill_targets.json"))
	for name in native["source_function_modes"]:
		var mask := TargetRules.function_mask(name,data["function_bits"])
		for channel in ["magic","special"]:
			check(TargetRules.native_target_mode(channel,mask) == int(native["source_function_modes"][name][channel]),"separate native mode mapping: "+name+"/"+channel)
	for code in data["ranges"]:
		if TargetRules.is_line(data["ranges"][code]): continue # line shapes are effect-only; covered below
		var local := fields.duplicate(true)
		local["range"] = code
		for origin in [Vector2i(4,4),Vector2i(0,0),Vector2i(8,8)]:
			var cells := TargetRules.cells(origin,local,data,Vector2i(9,9))
			var pattern: Dictionary = data["ranges"][code]
			var half: int = int(pattern["size"])/2
			for y in range(9):
				for x in range(9):
					var point := Vector2i(x,y)
					var offset: Vector2i = point-origin+Vector2i(half,half)
					var allowed: bool = point!=origin and offset.x>=0 and offset.y>=0 and offset.x<int(pattern["size"]) and offset.y<int(pattern["size"])
					if allowed: allowed = pattern["data"][offset.y][offset.x]>0
					check(cells.has(point)==allowed,"cast coverage follows each original source cell including map clipping")
	var caster := Loop._unit(loop,"leonard")
	var target := Loop._unit(loop,"enemy021_1")
	caster["coord"] = Vector2i(8,8)
	target["coord"] = Vector2i(10,8)
	target["hp"] = 100
	target["max_hp"] = 100
	target["combat_profile"]["live_defense"] = 10000
	var selected := Loop.choose_special(Loop.choose_command(loop,"special"),"special:magicOTHER:magicCode01")
	check(Loop.attack_cells(selected).has(Vector2i(10,8)) and not Loop.attack_cells(selected).has(Vector2i(9,9)),"source special range is a two-cell cross, not a diamond")
	for reason in ["diagonal","same_side","dead","defeated","unknown_role","self"]:
		var denied := selected.duplicate(true)
		var foe := Loop._unit(denied,"enemy021_1")
		var id := "enemy021_1"
		match reason:
			"diagonal": foe["coord"] = Vector2i(9,9)
			"same_side": foe["battle_actor_role"] = Loop.ROLE_FRIENDLY
			"dead": foe["hp"] = 0
			"defeated": foe["defeated"] = true
			"unknown_role": foe["battle_actor_role"] = "unknown"
			"self": id = "leonard"
		var before := denied.duplicate(true)
		var rejected := Loop.attack_target(denied,id,no_rng)
		check(rejected["units"] == before["units"] and rejected["turn_queue"] == before["turn_queue"] and not rejected["attacked_this_action"],"invalid target is atomic: "+reason)
		check(denied == before,"target validation is read-only: "+reason)
	for bad in ["magicFun_Heal","magicFun_Attack,magicFun_Poison","magicFun_ActiveAgain","", "unrecognized"]:
		var denied := selected.duplicate(true)
		own(denied, "skill_book")["skills"]["special:magicOTHER:magicCode01"]["fields"]["function"] = bad
		check(not Loop.can_use_special(denied,"leonard"),"unsupported effect cannot become an available damage action")
		var after := Loop.attack_target(denied,"enemy021_1",no_rng)
		check(after["units"] == denied["units"] and after["turn_queue"] == denied["turn_queue"],"unsupported function cannot spend resource or apply damage")
	for malformed in ["missing_range","row_size","fraction"]:
		var invalid := selected.duplicate(true)
		match malformed:
			"missing_range": own(invalid, "skill_target_data")["ranges"].erase("range2Cell")
			"row_size": own(invalid, "skill_target_data")["ranges"]["range2Cell"]["data"][0] = [1]
			"fraction": own(invalid, "skill_target_data")["ranges"]["range2Cell"]["data"][0][0] = 0.5
		check(not Loop.can_use_special(invalid,"leonard"),"invalid geometry disables skill: "+malformed)
		var after := Loop.attack_target(invalid,"enemy021_1",no_rng)
		check(after["units"] == invalid["units"] and after["turn_queue"] == invalid["turn_queue"],"invalid geometry cannot partially settle")
	# A special whose source effect_range is an area (天雷猛襲劍 range3CellThrust) settles
	# through the same cast transaction as area magic: one payment, every living enemy in
	# the footprint, never the caster standing inside it.
	var area := selected.duplicate(true)
	own(area, "skill_book")["skills"]["special:magicOTHER:magicCode01"]["fields"]["effect_range"] = "range2Cell"
	check(Loop.can_use_special(area,"leonard"),"an area effect_range keeps the special available")
	var swept := Loop.attack_target(area,"enemy021_1",func(_n): return 0)
	var affected: Array = swept.get("last_attack", {}).get("affected_targets", [])
	check(swept["attacked_this_action"] and Loop.unit(swept,"leonard")["stamina"] == 0 and swept["last_attack"].get("cast_center") == Vector2i(10,8),"area special pays once and settles at the chosen center")
	check(affected.any(func(receipt): return receipt["defender_id"] == "enemy021_1" and int(receipt["damage"]) > 0) and not affected.any(func(receipt): return receipt["defender_id"] == "leonard"),"area special damages the footprint enemy and skips the caster inside the footprint")
	check(Loop.unit(swept,"enemy021_1")["hp"] < 100 and Loop.unit(swept,"leonard")["hp"] == Loop.unit(area,"leonard")["hp"],"only footprint enemies lose HP")
	var hit := Loop.attack_target(selected,"enemy021_1",func(_n): return 0)
	check(Loop.unit(hit,"leonard")["stamina"]==0 and hit["attacked_this_action"],"valid source target pays and completes once")
	check(Loop.strike_range_cells(hit,hit["last_attack"]) == Loop.attack_cells(selected),"attack preview and settled special range share the same mask")
	# Two different source ranges must constrain which spell the AI can choose.
	var ai := BattleFixture.loop()
	var mage := Loop._unit(ai,"enemy026_1")
	mage["coord"] = Vector2i(6,6)
	mage["mp"] = 30
	var foe := Loop._unit(ai,"leonard")
	foe["coord"] = Vector2i(8,7)
	foe["hp"] = 100
	foe["max_hp"] = 100
	own(ai, "skill_book")["skills"]["magic:magicAIR:magicCode01"]["fields"]["range"] = "range2Cell"
	var before := ai.duplicate(true)
	var result := LoopAI._try_skill_turn(ai,"enemy026_1",[foe],func(_n): return 0)
	check(result.get("magic_key")=="fire" and result["path"]==Loop.movement_path(before,"enemy026_1",result["to"]),"AI chooses source-prepended fire and its own legal casting route, including staying put")
	check(Loop.strike_range_cells(ai,result).has(foe["coord"]) and Loop.unit(ai,"enemy026_1")["mp"]==22,"AI range cue and charged spell match its eligible target")
	for corruption in ["friendly","unknown_id","stale_dead"]:
		var invalid := before.duplicate(true)
		var proposed: Dictionary = Loop.unit(invalid,"leonard").duplicate(true)
		match corruption:
			"friendly": Loop._unit(invalid,"leonard")["battle_actor_role"] = Loop.ROLE_ENEMY
			"unknown_id": proposed["id"] = "not_in_roster"
			"stale_dead": Loop._unit(invalid,"leonard")["hp"] = 0
		var initial := invalid.duplicate(true)
		check(LoopAI._try_skill_turn(invalid,"enemy026_1",[proposed],no_rng).is_empty() and invalid==initial,"AI rereads real target identity/state before choosing or spending: "+corruption)
	for bad in ["magicFun_Heal", "magicFun_Attack,magicFun_Poison"]:
		var invalid := before.duplicate(true)
		own(invalid, "skill_book")["skills"]["magic:magicAIR:magicCode01"]["fields"]["function"] = bad
		for index in range(invalid["turn_queue"]["slots"].size()):
			if invalid["turn_queue"]["slots"][index]["id"]=="enemy026_1": invalid["turn_queue"]["index"]=index
		invalid["interaction"] = "ai_resolving"
		var after := Loop.step_ai_turn(invalid,no_rng)
		check(after["interaction"]=="scenario_error" and after["scenario_error"]=="unsupported_skill_function","invalid effect fails AI input rather than falling back to damaging attack")
		check(after["units"]==invalid["units"] and after["turn_queue"]==invalid["turn_queue"],"bad skill definition cannot move or advance")
	# Line (Dir) effect footprints: 0x4100e0 indices 21..23 write a straight size-cell line
	# from the chosen cell away from the caster (column difference first, then row).
	var line_fields := fields.duplicate(true)
	line_fields["range"] = "range1Cell"
	line_fields["effect_range"] = "range3CellDir"
	var map := Vector2i(16, 16)
	check(TargetRules.definition_error(line_fields, data) == "", "range3CellDir is an accepted effect range")
	var cast_line := line_fields.duplicate(true)
	cast_line["range"] = "range3CellDir"
	check(TargetRules.definition_error(cast_line, data) == "unsupported_line_cast_range", "a line is refused as a cast range instead of guessing a direction")
	check(TargetRules.effect_cells(Vector2i(9, 8), line_fields, data, map, Vector2i(8, 8)) == [Vector2i(9, 8), Vector2i(10, 8), Vector2i(11, 8)], "east target extends the line east from the target cell")
	check(TargetRules.effect_cells(Vector2i(7, 8), line_fields, data, map, Vector2i(8, 8)) == [Vector2i(7, 8), Vector2i(6, 8), Vector2i(5, 8)], "west target extends west")
	check(TargetRules.effect_cells(Vector2i(8, 7), line_fields, data, map, Vector2i(8, 8)) == [Vector2i(8, 7), Vector2i(8, 6), Vector2i(8, 5)], "north target extends north")
	check(TargetRules.effect_cells(Vector2i(8, 9), line_fields, data, map, Vector2i(8, 8)) == [Vector2i(8, 9), Vector2i(8, 10), Vector2i(8, 11)], "south target extends south")
	check(TargetRules.effect_cells(Vector2i(9, 9), line_fields, data, map, Vector2i(8, 8)) == [Vector2i(9, 9), Vector2i(10, 9), Vector2i(11, 9)], "a diagonal center takes the horizontal axis first, as the original branch order does")
	check(TargetRules.effect_cells(Vector2i(8, 8), line_fields, data, map, Vector2i(8, 8)) == [Vector2i(8, 8)], "the caster's own cell yields only that cell")
	check(TargetRules.effect_cells(Vector2i(15, 8), line_fields, data, map, Vector2i(14, 8)) == [Vector2i(15, 8)], "the map edge stops the line")
	check(TargetRules.effect_cells(Vector2i(9, 8), line_fields, data, map).is_empty(), "a line footprint without the caster position is refused, not defaulted")
	var line_caster := Loop.unit(loop, "leonard").duplicate(true)
	line_caster["coord"] = Vector2i(8, 8)
	var far_foe := Loop.unit(loop, "enemy021_1").duplicate(true)
	far_foe["coord"] = Vector2i(11, 8)
	var line_centers := TargetRules.candidate_centers(line_caster, [line_caster, far_foe], line_fields, data, map, Vector2i(8, 8))
	check(line_centers == [Vector2i(9, 8), Vector2i(10, 8), Vector2i(11, 8)], "inverse line centers are exactly the cells whose line reaches the foe; the caster side yields none")
	for center in line_centers:
		check(TargetRules.effect_cells(center, line_fields, data, map, Vector2i(8, 8)).has(far_foe["coord"]), "each candidate center projects onto the foe")
	# Player path: 皇龍閃 (range1Cell cast, range3CellDir effect) hits the adjacent enemy and the
	# one two cells behind it, skips the enemy beside the caster, pays once.
	var dragon := controlled()
	var dragon_id := "special:magicOTHER:magicCode02"
	own(dragon, "skill_book")["actors"]["001"]["supported_initial_ids"].append(dragon_id)
	Loop._unit(dragon, "leonard")["stamina"] = 80
	Loop._unit(dragon, "leonard")["coord"] = Vector2i(8, 8)
	var near := Loop._unit(dragon, "enemy021_1")
	near["coord"] = Vector2i(9, 8)
	near["hp"] = 400
	near["max_hp"] = 400
	var behind := Loop._unit(dragon, "enemy021_2")
	behind["coord"] = Vector2i(11, 8)
	behind["hp"] = 400
	behind["max_hp"] = 400
	var beside := Loop._unit(dragon, "enemy021_3")
	beside["coord"] = Vector2i(8, 9)
	beside["hp"] = 400
	beside["max_hp"] = 400
	var picked := Loop.choose_special(Loop.choose_command(dragon, "special"), dragon_id)
	check(picked["interaction"] == "attack_select" and picked["selected_skill_id"] == dragon_id, "a learned line special is selectable from the special menu")
	check(Loop.magic_target_id_at_coord(picked, Vector2i(9, 8)) == "enemy021_1", "the adjacent cell resolves to the adjacent enemy as center")
	var slashed := Loop.attack_target(picked, "enemy021_1", func(_n): return 0)
	var slashed_ids: Array = slashed.get("last_attack", {}).get("affected_targets", []).map(func(receipt): return receipt["defender_id"])
	check(slashed["attacked_this_action"] and Loop.unit(slashed, "leonard")["stamina"] == 20 and slashed["last_attack"].get("cast_center") == Vector2i(9, 8), "line special pays its source cost once and settles on the adjacent cell")
	check(slashed_ids == ["enemy021_1", "enemy021_2"] and Loop.unit(slashed, "enemy021_1")["hp"] < 400 and Loop.unit(slashed, "enemy021_2")["hp"] < 400, "both enemies on the line lose HP")
	check(Loop.unit(slashed, "enemy021_3")["hp"] == 400 and Loop.unit(slashed, "leonard")["hp"] == Loop.unit(dragon, "leonard")["hp"], "the enemy beside the caster and the caster are untouched")
	check(Loop.strike_range_cells(slashed, slashed["last_attack"]) == [Vector2i(9, 8), Vector2i(10, 8), Vector2i(11, 8)], "the settled cue shows the actual line footprint")
	# Self-centered pure specials (range0Cell cast, area effect): 慌雨斬 range1CellFull hits the
	# eight surrounding enemies from the caster's own cell, never the caster, one ST payment.
	var rain := controlled()
	var rain_id := "special:magicWATER:magicCode01"
	own(rain, "skill_book")["actors"]["001"]["supported_initial_ids"].append(rain_id)
	var rain_caster := Loop._unit(rain, "leonard")
	rain_caster["stamina"] = 40
	rain_caster["coord"] = Vector2i(8, 8)
	var ring := Loop._unit(rain, "enemy021_1")
	ring["coord"] = Vector2i(9, 9)
	ring["hp"] = 400
	ring["max_hp"] = 400
	ring["combat_profile"]["resist_by_type"] = {"1": 0}
	var ring_two := Loop._unit(rain, "enemy021_2")
	ring_two["coord"] = Vector2i(7, 8)
	ring_two["hp"] = 400
	ring_two["max_hp"] = 400
	ring_two["combat_profile"]["resist_by_type"] = {"1": 80}
	var outside := Loop._unit(rain, "enemy021_3")
	outside["coord"] = Vector2i(10, 8)
	outside["hp"] = 400
	outside["max_hp"] = 400
	var rain_picked := Loop.choose_special(Loop.choose_command(rain, "special"), rain_id)
	check(rain_picked["interaction"] == "attack_select" and Loop.attack_cells(rain_picked) == [Vector2i(8, 8)], "a self-centered special offers only the caster's own cell")
	check(Loop.magic_target_id_at_coord(rain_picked, Vector2i(8, 8)) != "", "choosing the caster's cell resolves to a surrounding enemy")
	var rained := Loop.attack_target(rain_picked, "enemy021_1", func(_n): return 0)
	var rained_ids: Array = rained.get("last_attack", {}).get("affected_targets", []).map(func(receipt): return receipt["defender_id"])
	check(rained["attacked_this_action"] and Loop.unit(rained, "leonard")["stamina"] == 20 and rained["last_attack"].get("cast_center") == Vector2i(8, 8), "self-centered special pays its source cost once from the caster's cell")
	check(rained_ids == ["enemy021_1", "enemy021_2"] and Loop.unit(rained, "enemy021_3")["hp"] == 400 and Loop.unit(rained, "leonard")["hp"] == rain_caster["hp"], "only the ring enemies are affected; the caster inside the footprint is skipped")
	var ring_damage: int = 400 - Loop.unit(rained, "enemy021_1")["hp"]
	var ring_two_damage: int = 400 - Loop.unit(rained, "enemy021_2")["hp"]
	check(ring_damage > 0 and ring_two_damage == ring_damage * 20 / 100, "each footprint target applies its own water resistance to the same special roll")
	# magicOTHER damage magic (滅): the 0x40a7b0 type switch has no case 5, so no resistance
	# slot is read; MP, hit equipment and the level/mind/magic-attack terms follow the magic path.
	var Resolution := Loop.SkillResolutionRules
	var other_loop := controlled()
	var other_id := "magic:magicOTHER:magicCode01"
	var other_caster := Loop._unit(other_loop, "enemy026_1")
	other_caster["actor_id"] = "052"
	other_caster["mp"] = 40
	other_caster["coord"] = Vector2i(8, 8)
	var other_target := Loop._unit(other_loop, "leonard")
	other_target["coord"] = Vector2i(8, 10)
	other_target["hp"] = 300
	other_target["combat_profile"]["resist_by_type"] = {}
	var other_fields := Loop.skill_fields(other_loop, other_id)
	var other_result := Resolution.resolve(other_caster, other_target, other_id, other_fields, other_loop["skill_book"], other_loop["skill_target_data"], other_loop["equipment_items"], other_caster["coord"], other_loop["map_size"], func(_n): return 0)
	check(other_result.get("ok", false) and other_result.get("receipt", {}).get("magic_key", "") == "other" and int(other_result.get("receipt", {}).get("damage", 0)) > 0 and other_result.get("caster_changes", {}).get("mp", 40) == 21, "滅 resolves as native magic damage without any resistance slot and pays 19 MP")
	var shielded := other_target.duplicate(true)
	shielded["combat_profile"]["resist_by_type"] = {"0": 80, "1": 80, "2": 80, "3": 80, "4": 80}
	var shielded_result := Resolution.resolve(other_caster, shielded, other_id, other_fields, other_loop["skill_book"], other_loop["skill_target_data"], other_loop["equipment_items"], other_caster["coord"], other_loop["map_size"], func(_n): return 0)
	check(shielded_result.get("ok", false) and shielded_result["receipt"]["damage"] == other_result["receipt"]["damage"], "elemental resistances do not scale magicOTHER magic")
	# eff_proc_Global wind magic (逆風裂空): same native wind policy as 風刃 with a wide footprint.
	var gale_id := "magic:magicAIR:magicCode03"
	var gale_caster := Loop._unit(other_loop, "enemy026_1")
	gale_caster["actor_id"] = "056"
	gale_caster["mp"] = 40
	var gale_center := Loop._unit(other_loop, "leonard")
	gale_center["coord"] = Vector2i(8, 12)
	gale_center["hp"] = 300
	gale_center["combat_profile"]["resist_by_type"] = {"2": 0}
	var gale_second := Loop._unit(other_loop, "enemy023_1")
	gale_second["coord"] = Vector2i(8, 13)
	gale_second["hp"] = 300
	gale_second["combat_profile"]["resist_by_type"] = {"2": 0}
	var gale_fields := Loop.skill_fields(other_loop, gale_id)
	var gale_result := Resolution.resolve_cast(gale_caster, gale_center, [gale_caster, gale_center, gale_second], gale_id, gale_fields, other_loop["skill_book"], other_loop["skill_target_data"], other_loop["equipment_items"], gale_caster["coord"], other_loop["map_size"], func(_n): return 0, gale_center["coord"])
	var gale_ids: Array = gale_result.get("receipt", {}).get("affected_targets", []).map(func(receipt): return receipt["defender_id"])
	check(gale_result.get("ok", false) and gale_result.get("receipt", {}).get("magic_key", "") == "wind" and gale_ids == ["leonard", "enemy023_1"] and gale_result.get("caster_changes", {}).get("mp", 40) == 7, "逆風裂空 reaches a range5CellCircle center four cells away, hits both units in its range3CellCircle footprint and pays 33 MP once")
	# Elemental specials (SPECIAL type 0..4) read the target's resist_by_type slot on the
	# same 0x40a7b0 proc0 switch as magic; magicOTHER (type 5) still multiplies nothing.
	var Special := Loop.SkillResolutionRules.Special
	var wind_fields := fields.duplicate(true)
	wind_fields["type"] = "magicAIR"
	var resistant := Loop.unit(loop,"enemy021_1").duplicate(true)
	resistant["combat_profile"]["resist_by_type"] = {"2": 80, "3": 40}
	var caster_now := Loop.unit(loop,"leonard")
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
		var party := controlled()
		var member := Loop._unit(party, "leonard")
		member["actor_id"] = row[0]
		member["stamina"] = 40
		member["coord"] = Vector2i(8, 8)
		check(party["skill_book"]["actors"][row[0]]["supported_initial_ids"].has(row[1]), "the PLAYERS declaration grants the member's initial special: " + row[0])
		var victim := Loop._unit(party, "enemy021_1")
		victim["coord"] = row[2]
		victim["hp"] = 400
		victim["max_hp"] = 400
		victim["combat_profile"]["resist_by_type"] = {"0": 40, "4": 40}
		var off_cell := Loop._unit(party, "enemy021_2")
		off_cell["coord"] = row[3]
		off_cell["hp"] = 400
		off_cell["max_hp"] = 400
		Loop._unit(party, "enemy021_4")["coord"] = Vector2i(1, 1)
		var chosen := Loop.choose_special(Loop.choose_command(party, "special"), row[1])
		check(chosen["interaction"] == "attack_select" and chosen["selected_skill_id"] == row[1], "the granted special is selectable from the member's special menu: " + row[1])
		check(Loop.attack_cells(chosen).has(row[2]) and not Loop.attack_cells(chosen).has(row[3]), "cast range follows the source range symbol (cross vs circle): " + row[1])
		var struck := Loop.attack_target(chosen, "enemy021_1", func(_n): return 0)
		var struck_ids: Array = struck.get("last_attack", {}).get("affected_targets", []).map(func(receipt): return receipt["defender_id"])
		check(struck["attacked_this_action"] and Loop.unit(struck, "leonard")["stamina"] == 20 and struck["last_attack"].get("skill_id") == row[1], "the special pays its 1-expend ST cost once and records its own id: " + row[1])
		check(struck_ids == ["enemy021_1"] and Loop.unit(struck, "enemy021_1")["hp"] < 400 and Loop.unit(struck, "enemy021_2")["hp"] == 400, "only the range1Cell footprint enemy loses HP: " + row[1])
		var member_fields := Loop.skill_fields(party, row[1])
		var member_input: Dictionary = Loop.SkillResolutionRules.Special.prepare(member, victim, member_fields, party["skill_book"], party["equipment_items"])["input"]
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
	var two_loop := controlled()
	var two_caster := Loop._unit(two_loop, "enemy021_1")
	two_caster["actor_id"] = "049"
	two_caster["stamina"] = 20
	two_caster["coord"] = Vector2i(8, 8)
	var two_target := Loop._unit(two_loop, "leonard")
	two_target["coord"] = Vector2i(10, 8)
	two_target["hp"] = 400
	two_target["combat_profile"]["resist_by_type"] = {"0": 80, "1": 80, "2": 80, "3": 80, "4": 80}
	var two_id := "special:magicOTHER2:magicCode01"
	var two_fields := Loop.skill_fields(two_loop, two_id)
	var two_prepared := Special.prepare(two_caster, two_target, two_fields, two_loop["skill_book"], two_loop["equipment_items"])
	check(two_prepared["ok"] and two_prepared["input"]["element"] == "6" and two_prepared["input"]["resistance"] == 0, "magicOTHER2 is the resist switch default: element 6, no slot read")
	var two_result := Resolution.resolve(two_caster, two_target, two_id, two_fields, two_loop["skill_book"], two_loop["skill_target_data"], two_loop["equipment_items"], two_caster["coord"], two_loop["map_size"], func(_n): return 0)
	var bare := two_target.duplicate(true)
	bare["combat_profile"]["resist_by_type"] = {"0": 0, "1": 0, "2": 0, "3": 0, "4": 0}
	var bare_result := Resolution.resolve(two_caster, bare, two_id, two_fields, two_loop["skill_book"], two_loop["skill_target_data"], two_loop["equipment_items"], two_caster["coord"], two_loop["map_size"], func(_n): return 0)
	check(two_result.get("ok", false) and int(two_result["receipt"]["damage"]) > 0 and two_result["receipt"]["damage"] == bare_result["receipt"]["damage"] and two_result["caster_changes"]["stamina"] == 0, "氣刃斬2 resolves as native special damage unaffected by every elemental resistance and pays 20 ST")
	var dragon_two := Loop.skill_fields(two_loop, "special:magicOTHER2:magicCode02")
	check(TargetRules.effect_cells(Vector2i(9, 8), dragon_two, data, map, Vector2i(8, 8)) == [Vector2i(9, 8), Vector2i(10, 8), Vector2i(11, 8), Vector2i(12, 8)], "龍嘯天驅2 keeps the four-cell line footprint of its source row")
	# Boss initial specials. 017 神罰: range1Cell cast, range4CellDir line footprint from the chosen
	# cell. 057 咕噜最終型態 虛空無轉: range4CellCircle cast (Manhattan 4), range2CellCircle footprint.
	check(book_actors["017"]["supported_initial_ids"].has("special:magicOTHER:magicCode22") and book_actors["057"]["supported_initial_ids"].has("special:magicOTHER:magicCode28"), "017 神罰 and 057 虛空無轉 are granted from special_other")
	var wrath := Loop.skill_fields(loop, "special:magicOTHER:magicCode22")
	check(TargetRules.effect_cells(Vector2i(8, 7), wrath, data, map, Vector2i(8, 8)) == [Vector2i(8, 7), Vector2i(8, 6), Vector2i(8, 5), Vector2i(8, 4)], "神罰 projects a four-cell line north from the adjacent target cell")
	var void_loop := controlled()
	var void_id := "special:magicOTHER:magicCode28"
	var void_caster := Loop._unit(void_loop, "enemy021_1")
	void_caster["actor_id"] = "057"
	void_caster["stamina"] = 80
	void_caster["coord"] = Vector2i(8, 8)
	var void_fields := Loop.skill_fields(void_loop, void_id)
	var void_cells := TargetRules.cells(Vector2i(8, 8), void_fields, data, map)
	check(void_cells.has(Vector2i(12, 8)) and void_cells.has(Vector2i(10, 10)) and not void_cells.has(Vector2i(11, 10)) and not void_cells.has(Vector2i(8, 8)), "虛空無轉 casts anywhere within Manhattan distance 4 except the caster's cell")
	var void_footprint := TargetRules.effect_cells(Vector2i(12, 8), void_fields, data, map, Vector2i(8, 8))
	check(void_footprint.has(Vector2i(13, 9)) and void_footprint.has(Vector2i(14, 8)) and not void_footprint.has(Vector2i(15, 8)), "its footprint is the range2CellCircle around the chosen cell")
	var void_center := Loop._unit(void_loop, "leonard")
	void_center["coord"] = Vector2i(12, 8)
	void_center["hp"] = 900
	void_center["max_hp"] = 900
	var void_second := Loop._unit(void_loop, "enemy023_1")
	void_second["coord"] = Vector2i(13, 9)
	void_second["hp"] = 900
	void_second["max_hp"] = 900
	var void_outside := Loop._unit(void_loop, "enemy023_2")
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
	var apex_loop := controlled()
	var apex_caster := Loop._unit(apex_loop, "enemy026_1")
	apex_caster["actor_id"] = "059"
	apex_caster["mp"] = 130
	apex_caster["coord"] = Vector2i(8, 8)
	var apex_center := Loop._unit(apex_loop, "leonard")
	apex_center["coord"] = Vector2i(13, 8)
	apex_center["hp"] = 900
	apex_center["max_hp"] = 900
	apex_center["combat_profile"]["resist_by_type"] = {"0": 80, "1": 80, "2": 80, "3": 80, "4": 80}
	var apex_second := Loop._unit(apex_loop, "enemy023_1")
	apex_second["coord"] = Vector2i(15, 9)
	apex_second["hp"] = 900
	apex_second["max_hp"] = 900
	apex_second["combat_profile"]["resist_by_type"] = {"0": 0, "1": 0, "2": 0, "3": 0, "4": 0}
	var apex_outside := Loop._unit(apex_loop, "enemy023_2")
	apex_outside["coord"] = Vector2i(17, 8)
	apex_outside["hp"] = 900
	apex_outside["max_hp"] = 900
	var apex_fields := Loop.skill_fields(apex_loop, apex_id)
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
		var tier_loop := controlled()
		var tier_caster := Loop._unit(tier_loop, "enemy026_1")
		tier_caster["actor_id"] = row[1]
		tier_caster["mp"] = 200
		tier_caster["coord"] = Vector2i(8, 8)
		var tier_center := Loop._unit(tier_loop, "leonard")
		tier_center["coord"] = row[5]
		tier_center["hp"] = 900
		tier_center["max_hp"] = 900
		tier_center["combat_profile"]["resist_by_type"] = {"0": 0, "1": 0, "2": 0, "3": 0, "4": 0}
		var tier_inside := Loop._unit(tier_loop, "enemy023_1")
		tier_inside["coord"] = row[6]
		tier_inside["hp"] = 900
		tier_inside["max_hp"] = 900
		tier_inside["combat_profile"]["resist_by_type"] = {"0": 80, "1": 80, "2": 80, "3": 80, "4": 80}
		var tier_outside := Loop._unit(tier_loop, "enemy023_2")
		tier_outside["coord"] = row[7]
		tier_outside["hp"] = 900
		tier_outside["max_hp"] = 900
		var tier_fields := Loop.skill_fields(tier_loop, tier_id)
		var tier_result := Resolution.resolve_cast(tier_caster, tier_center, [tier_caster, tier_center, tier_inside, tier_outside], tier_id, tier_fields, tier_loop["skill_book"], tier_loop["skill_target_data"], tier_loop["equipment_items"], tier_caster["coord"], tier_loop["map_size"], func(_n): return 0, tier_center["coord"])
		var tier_receipts: Array = tier_result.get("receipt", {}).get("affected_targets", [])
		check(tier_result.get("ok", false) and tier_result["receipt"].get("magic_key") == row[2] and tier_receipts.map(func(receipt): return receipt["defender_id"]) == ["leonard", "enemy023_1"] and tier_result["caster_changes"]["mp"] == 200 - int(row[4]), "%s reaches its far center, hits both footprint units, skips the one outside and pays %d MP once" % [tier_id, row[4]])
		check(tier_receipts.size() == 2 and int(tier_receipts[0]["damage"]) > 0 and int(tier_receipts[1]["damage"]) == int(tier_receipts[0]["damage"]) * 20 / 100, "each footprint target applies its own %s resistance to the same roll: " % row[2] + tier_id)
		# Player path: a member who learned the row picks it from the magic menu and settles at a chosen cell.
		var learned := controlled()
		own(learned, "skill_book")["actors"]["001"]["supported_initial_ids"].append(tier_id)
		var learner := Loop._unit(learned, "leonard")
		learner["mp"] = 200
		learner["max_mp"] = 200
		learner["coord"] = Vector2i(8, 8)
		var learned_foe := Loop._unit(learned, "enemy021_1")
		learned_foe["coord"] = row[5]
		learned_foe["hp"] = 900
		learned_foe["max_hp"] = 900
		var menu := Loop.choose_command(learned, "magic")
		check(Loop.magic_options(menu, "leonard").any(func(option): return option["id"] == tier_id and option["quote"]["ok"]), "the learned high-tier magic is listed and affordable in the magic menu: " + tier_id)
		var chosen_tier := Loop.choose_magic(menu, tier_id)
		check(chosen_tier["interaction"] == "attack_select" and chosen_tier["selected_skill_id"] == tier_id and Loop.attack_cells(chosen_tier).has(row[5]), "choosing it opens target selection with the source cast range: " + tier_id)
		var cast_tier := Loop.attack_target(chosen_tier, "enemy021_1", func(_n): return 0)
		check(cast_tier["attacked_this_action"] and Loop.unit(cast_tier, "leonard")["mp"] == 200 - int(row[4]) and Loop.unit(cast_tier, "enemy021_1")["hp"] < 900 and cast_tier["last_attack"].get("skill_id") == tier_id, "the player cast pays once, damages the center and records the skill id: " + tier_id)
	# Wave 9 lane A2 specials: 神怒 (OTHER 23, job 97 tier-2 learner) is a magicFun_Attack row on the
	# same channel1/proc0 roll as 神罰 (magicOTHER: no resistance slot); the unowned source rows
	# 百裂突刺2／獅子吼2／吸血劍2／金之手LV2 are registered under their base skill's policy.
	# [id, cost ST, target cell, off cell]
	for row in [
		["special:magicOTHER:magicCode23", 40, Vector2i(12, 8), Vector2i(11, 10)],
		["special:magicOTHER:magicCode29", 40, Vector2i(10, 8), Vector2i(8, 11)],
	]:
		var late_id: String = row[0]
		var late := controlled()
		own(late, "skill_book")["actors"]["001"]["supported_initial_ids"].append(late_id)
		var late_caster := Loop._unit(late, "leonard")
		late_caster["stamina"] = 60
		late_caster["coord"] = Vector2i(8, 8)
		var late_target := Loop._unit(late, "enemy021_1")
		late_target["coord"] = row[2]
		late_target["hp"] = 900
		late_target["max_hp"] = 900
		late_target["combat_profile"]["resist_by_type"] = {"0": 80, "1": 80, "2": 80, "3": 80, "4": 80}
		var late_off := Loop._unit(late, "enemy021_2")
		late_off["coord"] = row[3]
		late_off["hp"] = 900
		late_off["max_hp"] = 900
		var late_picked := Loop.choose_special(Loop.choose_command(late, "special"), late_id)
		check(late_picked["interaction"] == "attack_select" and late_picked["selected_skill_id"] == late_id, "the special is selectable from the special menu: " + late_id)
		check(Loop.attack_cells(late_picked).has(row[2]) and not Loop.attack_cells(late_picked).has(row[3]), "cast range follows the source range symbol: " + late_id)
		var late_hit := Loop.attack_target(late_picked, "enemy021_1", func(_n): return 0)
		check(late_hit["attacked_this_action"] and Loop.unit(late_hit, "leonard")["stamina"] == 60 - int(row[1]) and late_hit["last_attack"].get("skill_id") == late_id, "the special pays its source ST once and records its id: " + late_id)
		check(Loop.unit(late_hit, "enemy021_1")["hp"] < 900 and Loop.unit(late_hit, "enemy021_2")["hp"] == 900, "only the footprint target loses HP, fully resistant or not: " + late_id)
