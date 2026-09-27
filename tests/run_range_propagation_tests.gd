extends "res://tests/support/TestSuite.gd"
## Original range propagation (RangePropagationRules, original_weapon_ranges.md):
## every native 0x40f8b0／0x4100e0 return of original_range_terrain.json byte for byte, and
## real battlefield cells through the player's weapon range, cast range and cast check.

const RangePropagationRules = preload("res://game/sim/RangePropagationRules.gd")
const BattlePlayLoop = preload("res://game/sim/loop/BattlePlayLoop.gd")
const SkillResolutionRules = preload("res://game/sim/SkillResolutionRules.gd")
const TerrainEditRules = preload("res://game/sim/TerrainEditRules.gd")
const Autoplay = preload("res://tests/support/Autoplay.gd")
const PACKET := "res://docs/evidence_packets/static_reverse/original_range_terrain.json"
const LINE_SIZES := {"range3CellDir": 3, "range4CellDir": 4, "range5CellDir": 5}
const POISON_ARROW := "special:magicMIND:magicCode03"
const QUAKE := "magic:magicEARTH:magicCode02"
const DRAGON := "special:magicOTHER:magicCode02"


func _init() -> void:
	tag = "RANGE_PROPAGATION_TESTS"


func run() -> void:
	_native_returns()
	_wall_stop_battle_003()
	_h255_and_ally_battle_005()
	_open_ground_first_battle()
	_walled_pocket_battle_504()
	_cast_range_battle_003()
	_area_wall_battle_003()
	_area_matrix_battle_504()
	_line_wall_battle_504()
	_autoplay_destination()


func _native_returns() -> void:
	var packet: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(PACKET))
	var rows := {}
	var weapons: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://content/generated/hsl/chapter01/attack_ranges.json"))["patterns"]
	var skills: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://content/generated/hsl/skills/targeting.json"))["ranges"]
	for table in [weapons, skills]:
		for code in table:
			if table[code].get("data") is Array: rows[code] = table[code]["data"]
	var grids := {}
	for name in packet["grids"]:
		var words := {}
		for entry in packet["grids"][name]["words"]:
			words[Vector2i(int(entry[0]), int(entry[1]))] = int(entry[2])
		grids[name] = {"words": words, "size": Vector2i(int(packet["grids"][name]["size"]), int(packet["grids"][name]["size"]))}
	var counts := {"weapon": 0, "area": 0, "line": 0}
	for case in packet["cases"]:
		var input: Dictionary = case["input"]
		var grid: Dictionary = grids[input["grid"]]
		var code := str(input["code"])
		var got: Dictionary
		var kind := str(input["builder"])
		if kind == "weapon":
			got = RangePropagationRules.weapon_coverage(rows[code], _cell(input["origin"]), grid["words"], grid["size"], int(input["mode"]), int(input["flag5"]) != 0)
		elif LINE_SIZES.has(code):
			kind = "line"
			got = RangePropagationRules.line_coverage(LINE_SIZES[code], _cell(input["caster"]), _cell(input["target"]), grid["words"], grid["size"], int(input["mode"]))
		else:
			got = RangePropagationRules.area_coverage(rows[code], _cell(input["target"]), grid["words"], grid["size"], int(input["mode"]))
		counts[kind] += 1
		check(got == _native(case), "native %s %s %s %s mode %d: expected %s got %s" % [kind, input["grid"], code, str(input.get("origin", input.get("target"))), int(input["mode"]), str(_native(case)), str(got)])
	check(counts["weapon"] == 124 and counts["area"] + counts["line"] == 230, "all 354 native returns compared: %s" % str(counts))


## battle_003 opening: 胡 (4,9) with range3CellShoot. (4,7) carries the WRD 0x4000 flag; the
## flat record covers it and (4,6) behind it, the original flood stops at it. (3,10)／(5,10)
## hold allies (mode 2 leaves pmPLAYER occupants unwritten).
func _wall_stop_battle_003() -> void:
	var loop := _loop("battle_003")
	var hu := BattlePlayLoop.unit(loop, "hu")
	var tiles: Dictionary = TerrainEditRules.tiles(loop)
	check(hu["coord"] == Vector2i(4, 9) and str(BattlePlayLoop.weapon_pattern(loop, hu)["name"]) == "range3CellShoot", "battle_003 胡 opens at (4,9) with range3CellShoot")
	check(int(tiles[Vector2i(4, 7)]["movement_flags"]) & 0x4000 != 0 and int(tiles[Vector2i(4, 6)]["movement_flags"]) & 0x4000 != 0, "battle_003 (4,7) and (4,6) are 0x4000 walls")
	var flat: Array = BattlePlayLoop.TacticalGridRules.attack_pattern_cells(hu["coord"], BattlePlayLoop.weapon_pattern(loop, hu)["offsets"], loop["map_size"])
	var cells := BattlePlayLoop.attack_cells(loop, "hu")
	check(flat.has(Vector2i(4, 7)) and not cells.has(Vector2i(4, 7)), "battle_003 胡: the 0x4000 cell (4,7) is in the flat record but not attackable")
	check(flat.has(Vector2i(2, 10)) and not cells.has(Vector2i(2, 10)), "battle_003 胡: (2,10) next to the (2,9)／(3,9) walls loses its power at the onward check")
	check(cells.has(Vector2i(5, 8)) and cells.has(Vector2i(4, 12)), "battle_003 胡: (5,8) beside the wall and (4,12) on open ground stay attackable")
	_assert_eq(cells, [Vector2i(5, 8), Vector2i(6, 8), Vector2i(6, 9), Vector2i(7, 9), Vector2i(6, 10), Vector2i(3, 11), Vector2i(4, 11), Vector2i(5, 11), Vector2i(4, 12)], "battle_003 胡 weapon cells")


## battle_005 opening: 胡 (10,11) with range3CellShoot. (8,11) and (7,11) are height 255
## without 0x4000: the range builders never read heights, so both stay covered. (9,10)
## holds an ally: left out, and the flood carries on to (8,10) behind it.
func _h255_and_ally_battle_005() -> void:
	var loop := _loop("battle_005")
	var hu := BattlePlayLoop.unit(loop, "hu")
	var tiles: Dictionary = TerrainEditRules.tiles(loop)
	check(hu["coord"] == Vector2i(10, 11), "battle_005 胡 opens at (10,11)")
	for cell in [Vector2i(8, 11), Vector2i(7, 11)]:
		check(int(tiles[cell]["elevation"]) == 255 and int(tiles[cell]["movement_flags"]) & 0x4000 == 0, "battle_005 %s is h255 without 0x4000" % str(cell))
	var cells := BattlePlayLoop.attack_cells(loop, "hu")
	check(cells.has(Vector2i(8, 11)) and cells.has(Vector2i(7, 11)), "battle_005 胡: the range passes over the h255 cells (8,11) and (7,11)")
	check(RangePropagationRules.side_word(_at(loop, Vector2i(9, 10))) & RangePropagationRules.P != 0 and not cells.has(Vector2i(9, 10)) and cells.has(Vector2i(8, 10)), "battle_005 胡: the ally at (9,10) is left out, (8,10) behind it stays")
	_assert_eq(cells.size(), 19, "battle_005 胡 weapon cell count (20 flat minus the ally)")


## first_battle opening: 萊納德 (15,17) with range1Cell on open ground — the flood equals
## the flat record.
func _open_ground_first_battle() -> void:
	var loop := _loop("first_battle")
	var leonard := BattlePlayLoop.unit(loop, "leonard")
	var flat: Array = BattlePlayLoop.TacticalGridRules.attack_pattern_cells(leonard["coord"], BattlePlayLoop.weapon_pattern(loop, leonard)["offsets"], loop["map_size"])
	check(leonard["coord"] == Vector2i(15, 17), "first_battle 萊納德 opens at (15,17)")
	_assert_eq(BattlePlayLoop.attack_cells(loop, "leonard"), [Vector2i(15, 16), Vector2i(14, 17), Vector2i(16, 17), Vector2i(15, 18)], "first_battle 萊納德 open-ground weapon cells")
	_assert_eq(BattlePlayLoop.attack_cells(loop, "leonard"), flat, "first_battle 萊納德: flood equals the flat record on open ground")


## battle_504 opening: 咕嚕 (7,15) range3CellCircle inside a walled pocket.
func _walled_pocket_battle_504() -> void:
	var loop := _loop("battle_504")
	check(BattlePlayLoop.unit(loop, "gulu")["coord"] == Vector2i(7, 15), "battle_504 咕嚕 opens at (7,15)")
	_assert_eq(BattlePlayLoop.attack_cells(loop, "gulu"), [Vector2i(7, 12), Vector2i(6, 13), Vector2i(7, 13), Vector2i(5, 14), Vector2i(6, 14), Vector2i(7, 14), Vector2i(8, 14), Vector2i(6, 15), Vector2i(6, 16), Vector2i(7, 16), Vector2i(8, 16), Vector2i(7, 17)], "battle_504 咕嚕 weapon cells (24 flat)")


## battle_003 opening: 胡's 毒魔箭 cast range range3CellThrust through the player's
## selection (mode -1, flag 0: walls stop, no side exclusion) and the settled cast check.
func _cast_range_battle_003() -> void:
	var loop := _loop("battle_003")
	var hu := BattlePlayLoop.unit(loop, "hu")
	var fields := BattlePlayLoop.skill_fields(loop, POISON_ARROW)
	check(str(fields.get("range", "")) == "range3CellThrust", "毒魔箭 cast range is range3CellThrust")
	var flat: Array = BattlePlayLoop.SkillTargetRules.cells(hu["coord"], fields, loop["skill_target_data"], loop["map_size"])
	var selecting := loop.duplicate()
	selecting.merge({"selected_attack": "special", "interaction": "attack_select", "selected_unit_id": "hu", "selected_skill_id": POISON_ARROW}, true)
	var cells := BattlePlayLoop.attack_cells(selecting, "hu")
	check(flat.has(Vector2i(4, 7)) and flat.has(Vector2i(4, 6)) and not cells.has(Vector2i(4, 7)) and not cells.has(Vector2i(4, 6)), "毒魔箭 from (4,9): the 0x4000 cell (4,7) and (4,6) behind it are not castable")
	check(cells.has(Vector2i(4, 8)) and cells.has(Vector2i(3, 10)), "毒魔箭 from (4,9): (4,8) before the wall and the ally cell (3,10) stay castable")
	_assert_eq(cells, [Vector2i(4, 8), Vector2i(5, 8), Vector2i(5, 9), Vector2i(6, 9), Vector2i(7, 9), Vector2i(3, 10), Vector2i(4, 10), Vector2i(5, 10), Vector2i(4, 11), Vector2i(4, 12)], "毒魔箭 cast cells from (4,9)")
	var caster: Dictionary = hu.duplicate(true)
	caster["stamina"] = 60
	var walled := SkillResolutionRules.prepare_cast(caster, caster, loop["units"], POISON_ARROW, fields, loop["skill_book"], loop["skill_target_data"], loop["equipment_items"], caster["coord"], loop["map_size"], Vector2i(4, 7), {"range_terrain": BattlePlayLoop.skill_terrain(loop)})
	var bare := SkillResolutionRules.prepare_cast(caster, caster, loop["units"], POISON_ARROW, fields, loop["skill_book"], loop["skill_target_data"], loop["equipment_items"], caster["coord"], loop["map_size"], Vector2i(4, 7))
	check(walled.get("reason") == "out_of_range" and bare.get("reason") != "out_of_range", "毒魔箭 aimed at the wall (4,7): out_of_range with the terrain (got %s), in range without (got %s)" % [str(walled.get("reason")), str(bare.get("reason"))])


## battle_003 opening: 胡's 毒魔箭 area (range1Cell) through the player's effect area
## (0x444f08／0x4450e0 → 0x4100e0 mode 2): the 0x4000 cells and the P occupants are left
## out, the centre is written unless a P occupant stands on it (0x410498[2]).
func _area_wall_battle_003() -> void:
	var loop := _loop("battle_003")
	var selecting := loop.duplicate()
	selecting.merge({"selected_attack": "special", "interaction": "attack_select", "selected_unit_id": "hu", "selected_skill_id": POISON_ARROW}, true)
	var fields := BattlePlayLoop.skill_fields(loop, POISON_ARROW)
	var hu := BattlePlayLoop.unit(loop, "hu")
	var flat: Array = BattlePlayLoop.SkillTargetRules.cast_footprint(hu["coord"], Vector2i(4, 8), fields, loop["skill_target_data"], loop["map_size"])
	_assert_eq(flat, [Vector2i(4, 7), Vector2i(3, 8), Vector2i(4, 8), Vector2i(5, 8), Vector2i(4, 9)], "毒魔箭 at (4,8): the flat cross")
	_assert_eq(BattlePlayLoop.Combat.skill_cast_footprint(selecting, Vector2i(4, 8)), [Vector2i(4, 8), Vector2i(5, 8)], "毒魔箭 at (4,8) against the (4,7)／(3,8) walls, 胡 at (4,9) left out")
	_assert_eq(BattlePlayLoop.Combat.skill_cast_footprint(selecting, Vector2i(4, 10)), [Vector2i(4, 10), Vector2i(4, 11)], "毒魔箭 at (4,10) between 胡, 緹娜 and 雷歐納德: only the open cells")
	_assert_eq(BattlePlayLoop.Combat.skill_cast_footprint(selecting, Vector2i(3, 10)), [Vector2i(2, 10), Vector2i(4, 10), Vector2i(3, 11)], "毒魔箭 on 緹娜's cell (3,10): the P centre and the (3,9) wall left out")
	_assert_eq(BattlePlayLoop.Combat.skill_cast_footprint(selecting, Vector2i(4, 11)), [Vector2i(4, 10), Vector2i(3, 11), Vector2i(4, 11), Vector2i(5, 11), Vector2i(4, 12)], "毒魔箭 at (4,11) on open ground: the whole cross")
	# The settled context carries the same terrain only in the player's command cast.
	check(BattlePlayLoop.Combat._skill_context(selecting).get("range_terrain") == BattlePlayLoop.skill_terrain(selecting), "the player's command cast settles with the player's skill terrain")
	check(not BattlePlayLoop.Combat._skill_context(loop).has("range_terrain"), "outside the player's skill targeting the settled context carries no terrain")
	var ai_casting := selecting.duplicate()
	ai_casting["interaction"] = "ai_resolving"
	check(not BattlePlayLoop.Combat._skill_context(ai_casting).has("range_terrain"), "an AI cast (ai_resolving) settles flat")
	# The area modes 2／3 are the P side's: a commandable caster of another side keeps the flat area.
	var hu_e: Dictionary = BattlePlayLoop.unit(selecting, "hu").merged({"player_mode": RangePropagationRules.E}, true)
	check(BattlePlayLoop.skill_terrain(selecting).has("area_modes") and not BattlePlayLoop.skill_terrain(selecting, hu_e).has("area_modes") and BattlePlayLoop.skill_terrain(selecting, hu_e).has("cast_mode"), "the area half needs a P-side caster; the mode -1 cast range applies to any")


## battle_504 opening: 克勞蒂 (7,11) casts 地龍震 (range3CellCircle → range2CellCircle) on a
## foe at (7,14). 胡 (8,13), 漢克斯 (9,14) and 咕嚕 (7,15) are P and left out, (8,15) is
## 0x4000; at (7,15) the onward check sees the (8,15) wall and ends the flood, so the foe
## at (7,16) is outside the area the flat record would reach. Preview, target line and
## the settled strike read that one area.
func _area_matrix_battle_504() -> void:
	var loop := _loop("battle_504")
	BattlePlayLoop._unit(loop, "actor036_1")["coord"] = Vector2i(7, 14)
	BattlePlayLoop._unit(loop, "actor036_2")["coord"] = Vector2i(7, 16)
	BattlePlayLoop._unit(loop, "actor036_3")["coord"] = Vector2i(6, 14)
	var casting := BattlePlayLoop.choose_magic(BattlePlayLoop.choose_command(_turn(loop, "claudie"), "magic"), QUAKE)
	check(casting["interaction"] == "attack_select" and casting["selected_skill_id"] == QUAKE, "克勞蒂 selects 地龍震")
	var fields := BattlePlayLoop.skill_fields(casting, QUAKE)
	var flat: Array = BattlePlayLoop.SkillTargetRules.cast_footprint(Vector2i(7, 11), Vector2i(7, 14), fields, casting["skill_target_data"], casting["map_size"])
	var area: Array = BattlePlayLoop.Combat.skill_cast_footprint(casting, Vector2i(7, 14))
	check(flat.has(Vector2i(7, 16)) and flat.has(Vector2i(8, 15)), "地龍震 at (7,14): the flat record reaches (7,16) and the (8,15) wall")
	_assert_eq(area, [Vector2i(7, 12), Vector2i(6, 13), Vector2i(7, 13), Vector2i(5, 14), Vector2i(6, 14), Vector2i(7, 14), Vector2i(8, 14), Vector2i(6, 15)], "地龍震 at (7,14) beside the (8,15) wall")
	check(BattlePlayLoop.magic_target_id_at_coord(casting, Vector2i(7, 14)) == "actor036_1", "the target line at (7,14) names the centre foe")
	var before := int(BattlePlayLoop.unit(casting, "actor036_2")["hp"])
	var cast := BattlePlayLoop.attack_target(casting, "actor036_1", func(_n): return 0, Vector2i(7, 14))
	var hit: Array = cast.get("last_attack", {}).get("affected_targets", []).map(func(receipt): return receipt["defender_id"])
	check(cast.get("last_attack_reject", {}).is_empty() and hit == ["actor036_1", "actor036_3"], "地龍震 settles on the two foes inside the area (got %s)" % [hit])
	check(int(BattlePlayLoop.unit(cast, "actor036_2")["hp"]) == before, "the foe at (7,16) past the wall-side stop keeps its HP")
	_assert_eq(hit, _foes_on(casting, area), "地龍震: the settled targets are the foes on the previewed area")


## battle_504: 咕嚕 (moved to (7,16)) slashes 皇龍閃 (range1Cell → range3CellDir) at the foe
## on (8,16). (9,16) is 0x4000: the 0x4100e0 line ends there as a whole, so the foe on
## (10,16) — on the flat line — is not struck, and the settled cue shows the one cell.
func _line_wall_battle_504() -> void:
	var loop := _loop("battle_504")
	var gulu := BattlePlayLoop._unit(loop, "gulu")
	own(loop, "skill_book")["actors"][str(gulu["actor_id"])]["supported_initial_ids"].append(DRAGON)
	gulu["coord"] = Vector2i(7, 16)
	gulu["stamina"] = 80
	BattlePlayLoop._unit(loop, "actor036_1")["coord"] = Vector2i(8, 16)
	BattlePlayLoop._unit(loop, "actor036_2")["coord"] = Vector2i(10, 16)
	var tiles: Dictionary = TerrainEditRules.tiles(loop)
	check(int(tiles[Vector2i(9, 16)]["movement_flags"]) & 0x4000 != 0 and int(tiles[Vector2i(10, 16)]["movement_flags"]) & 0x4000 == 0, "battle_504 (9,16) is a 0x4000 wall, (10,16) open")
	var casting := BattlePlayLoop.choose_special(BattlePlayLoop.choose_command(_turn(loop, "gulu"), "special"), DRAGON)
	check(casting["interaction"] == "attack_select" and casting["selected_skill_id"] == DRAGON, "咕嚕 selects 皇龍閃")
	var fields := BattlePlayLoop.skill_fields(casting, DRAGON)
	_assert_eq(BattlePlayLoop.SkillTargetRules.cast_footprint(Vector2i(7, 16), Vector2i(8, 16), fields, casting["skill_target_data"], casting["map_size"]), [Vector2i(8, 16), Vector2i(9, 16), Vector2i(10, 16)], "皇龍閃 from (7,16) at (8,16): the flat line")
	_assert_eq(BattlePlayLoop.Combat.skill_cast_footprint(casting, Vector2i(8, 16)), [Vector2i(8, 16)], "皇龍閃 at (8,16): the line ends at the (9,16) wall")
	var before := int(BattlePlayLoop.unit(casting, "actor036_2")["hp"])
	var slashed := BattlePlayLoop.attack_target(casting, "actor036_1", func(_n): return 0)
	var hit: Array = slashed.get("last_attack", {}).get("affected_targets", []).map(func(receipt): return receipt["defender_id"])
	check(slashed.get("last_attack_reject", {}).is_empty() and hit == ["actor036_1"], "皇龍閃 settles on the foe before the wall only (got %s)" % [hit])
	check(int(BattlePlayLoop.unit(slashed, "actor036_2")["hp"]) == before, "the foe on (10,16) behind the wall keeps its HP")
	_assert_eq(BattlePlayLoop.strike_range_cells(slashed, slashed.get("last_attack", {})), [Vector2i(8, 16)], "the settled cue shows the cut line")


## The autoplay driver's destination (tests/support/Autoplay.gd `_destination`): the flat
## pattern proposes the cheapest cell, the weapon's flood from it decides. 胡 (range3CellShoot)
## on real walls: battle_003 foe (6,6) — from (6,9) the flat record covers it but (6,7)／(6,8)
## sit beside the walls; foe (1,10) — from (4,10) the flood dies at (2,10) beside (2,9)／(3,9);
## battle_504 foe (7,16) — from (8,14) the (8,15) wall is in the way. Each time the driver
## lands on another cell and strikes from it in the same action.
func _autoplay_destination() -> void:
	for case in [["battle_003", "actor028_1", Vector2i(6, 6), Vector2i(6, 9)], ["battle_003", "actor028_1", Vector2i(1, 10), Vector2i(4, 10)], ["battle_504", "actor036_1", Vector2i(7, 16), Vector2i(8, 14)]]:
		var loop := _loop(case[0])
		var foe := BattlePlayLoop._unit(loop, case[1])
		foe["coord"] = case[2]
		var turn := _turn(loop, "hu")
		var hu := BattlePlayLoop.unit(turn, "hu")
		var pattern := BattlePlayLoop.weapon_pattern(turn, hu)
		var flat_cell: Vector2i = case[3]
		var label := "%s 胡 %s → foe %s" % [case[0], str(hu["coord"]), str(case[2])]
		check(BattlePlayLoop.Footprint.contact(foe, BattlePlayLoop.attack_cells(turn, "hu")) == null, "%s: not in reach before the move" % label)
		var from_flat: Array = Autoplay._weapon_cells_from(turn, hu, pattern, flat_cell)
		check(BattlePlayLoop.movement_cells(turn, "hu").has(flat_cell) and BattlePlayLoop.TacticalGridRules.attack_pattern_cells(flat_cell, pattern["offsets"], turn["map_size"]).has(case[2]) and not from_flat.has(case[2]), "%s: the flat record covers the foe from %s, the flood does not" % [label, str(flat_cell)])
		var destination: Variant = Autoplay._destination(turn, "hu")
		check(destination is Vector2i and destination != flat_cell and BattlePlayLoop.movement_path(turn, "hu", flat_cell).size() <= BattlePlayLoop.movement_path(turn, "hu", destination).size(), "%s: the driver passes over the cheaper flat cell %s (chose %s)" % [label, str(flat_cell), str(destination)])
		var step := Autoplay._take_player_action(turn, RandomNumberGenerator.new())
		check(step["action"] == "move_then_attack" and BattlePlayLoop.unit(step["loop"], "hu")["coord"] == destination, "%s: lands on %s and strikes (got %s)" % [label, str(destination), str(step["action"])])


## The living foes standing on `cells`, in roster order.
func _foes_on(loop: Dictionary, cells: Array) -> Array:
	var result: Array = []
	for unit in loop["units"]:
		if int(unit["hp"]) > 0 and cells.has(unit["coord"]) and unit.get("battle_actor_role") == "enemy_ai": result.append(unit["id"])
	return result


## Hands the action to `id` (its slot becomes current) and opens its action menu.
func _turn(loop: Dictionary, id: String) -> Dictionary:
	for index in range(loop["turn_queue"]["slots"].size()):
		if loop["turn_queue"]["slots"][index]["id"] == id: loop["turn_queue"]["index"] = index
	return BattlePlayLoop.select_player_unit(loop, id)


func _loop(level: String) -> Dictionary:
	return BattlePlayLoop.create([], "", BattlePlayLoop.BattleScenario.load_file("res://content/battles/%s.json" % level), 1)


func _at(loop: Dictionary, cell: Vector2i) -> Dictionary:
	for unit in loop["units"]:
		if unit.get("coord") == cell: return unit
	return {}


func _cell(pair: Array) -> Vector2i:
	return Vector2i(int(pair[0]), int(pair[1]))


func _native(case: Dictionary) -> Dictionary:
	var frame: Array = case["frame"]
	var bytes: PackedByteArray = str(case["coverage"]).hex_decode()
	var result := {}
	for y in range(int(frame[1])):
		for x in range(int(frame[0])):
			var value := int(bytes[y * int(frame[0]) + x])
			if value != 0: result[Vector2i(int(frame[2]) + x, int(frame[3]) + y)] = value
	return result
