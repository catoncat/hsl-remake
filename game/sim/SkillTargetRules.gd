extends RefCounted
const Footprint = preload("res://game/sim/FootprintRules.gd")
const Propagation = preload("res://game/sim/RangePropagationRules.gd")
## Pure source-backed skill targeting. Native mode selection is separate from
## the current battle-role adapter and the subset of effects actually implemented.
## `terrain` (optional, RangePropagationRules.player_skill_terrain) switches the cast range
## (`cast_mode`) and the effect area (`area_modes`) from the flat RANGE projection to the
## original 0x4000／occupant propagation; without it the projection stays flat.
## provenance:
##   rules: static-derived docs/evidence_packets/static_reverse/original_skill_targets.md; static-derived docs/evidence_packets/static_reverse/original_line_ranges.md; static-derived docs/evidence_packets/static_reverse/original_weapon_ranges.md; resource-derived content/generated/hsl/skills/targeting.json; static-derived docs/evidence_packets/static_reverse/original_player_mode_sides.md; provisional (battle-role adapter, support same-side as overlap, unsupported effects refused)
##   layout: n/a
##   strings: n/a
##   timing: n/a
##   audio: n/a
const MAGIC_SUPPORT_MASK := 0x0f62
const SPECIAL_SUPPORT_MASK := 0x18f62
const ROLES := ["player_controlled", "friendly_ai", "enemy_ai"]
const Sides = preload("res://game/sim/ActorRoleRules.gd")


static func function_mask(expression: Variant, symbols: Dictionary) -> int:
	if not expression is String or expression.is_empty():
		return -1
	var mask := 0
	for raw in expression.split(","):
		var symbol: String = raw.strip_edges()
		if not symbols.has(symbol):
			return -1
		var bit: Variant = symbols[symbol]
		if typeof(bit) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(bit)) or bit <= 0 or bit != int(bit) or bit > 0x7fffffff:
			return -1
		mask |= int(bit)
	return mask


static func native_target_mode(channel: String, mask: int) -> int:
	if mask <= 0 or channel not in ["magic", "special"]:
		return -1
	var support := MAGIC_SUPPORT_MASK if channel == "magic" else SPECIAL_SUPPORT_MASK
	return 3 if (mask & support) != 0 else 2


static func is_line(pattern: Variant) -> bool:
	## RANGE.H "N Line"/"E Line" (range3CellDir/range4CellDir): hsl_skill_target_data marks
	## them shape=line; 0x4100e0 indices 21..23 never read the rows, only the size.
	return pattern is Dictionary and pattern.get("shape") == "line"


static func _line_error(pattern: Dictionary) -> String:
	var size_value: Variant = pattern.get("size")
	if typeof(size_value) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(size_value)) or size_value != int(size_value) or size_value < 1 or size_value > 25:
		return "invalid_skill_range"
	var rows: Variant = pattern.get("data")
	if not rows is Array or rows.size() != int(size_value):
		return "invalid_skill_range"
	for row in rows:
		if not row is Array or row.size() != 1:
			return "invalid_skill_range"
		var value: Variant = row[0]
		if typeof(value) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(value)) or value != int(value) or value < 0 or value > 127:
			return "invalid_skill_range"
	return ""


static func _pattern_error(pattern: Variant) -> String:
	if is_line(pattern): return _line_error(pattern)
	if not pattern is Dictionary or typeof(pattern.get("size")) not in [TYPE_INT, TYPE_FLOAT]:
		return "invalid_skill_range"
	var size_value: Variant = pattern["size"]
	if not is_finite(float(size_value)) or size_value != int(size_value) or size_value < 1 or size_value > 25 or int(size_value) % 2 == 0:
		return "invalid_skill_range"
	var rows: Variant = pattern.get("data")
	if not rows is Array or rows.size() != int(size_value):
		return "invalid_skill_range"
	for row in rows:
		if not row is Array or row.size() != int(size_value):
			return "invalid_skill_range"
		for value in row:
			if typeof(value) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(value)) or value != int(value) or value < 0 or value > 127:
				return "invalid_skill_range"
	return ""


static func definition_error(fields: Dictionary, data: Dictionary) -> String:
	if data.get("schema") != "hsl_skill_target_data.v1" or not data.get("function_bits") is Dictionary or not data.get("ranges") is Dictionary:
		return "missing_skill_target_data"
	var mask := function_mask(fields.get("function"), data["function_bits"])
	if mask < 0:
		return "invalid_skill_function"
	if mask not in [1, 2, 4, 5, 8, 9, 17, 0x20, 0x40, 0x400, 0x4000, 0x60, 0x100, 0x1000, 0x1001, 0x101d, 0x2e00, 0x8000, 0x8002, 0x10000, 0x80000, 0x100001, 0x20001, 0x20000, 0x40000] or int(data["function_bits"].get("magicFun_Attack", 0)) != 1:
		return "unsupported_skill_function"
	for key in ["range", "effect_range"]:
		if not fields.get(key) is String or not data["ranges"].has(fields[key]):
			return "missing_skill_range"
		var error := _pattern_error(data["ranges"][fields[key]])
		if error != "":
			return error
	# A line is only a source effect_range (皇龍閃/龍嘯天驅/翔天刃風擊 cast with range1Cell);
	# no source row casts with one, and 0x4100e0's line branch needs a caster direction.
	if is_line(data["ranges"][fields["range"]]):
		return "unsupported_line_cast_range"
	# Effect-area support belongs to the selected resolver: every AREA_POLICIES
	# resolver (native magic, native special damage/poison) prepares each living
	# target inside the effect footprint through the shared cast transaction.
	return ""


## 0x4100e0 line branch (range index 21..23): the line starts on the chosen cell and
## runs size cells away from the caster. A differing column picks the horizontal
## axis first; the same column picks the vertical axis; the caster's own cell yields
## only that cell. Map edges stop the line; with `terrain` a 0x4000 word stops it too and an
## excluded occupant is skipped (RangePropagationRules.line_coverage).
static func line_direction(origin: Vector2i, center: Vector2i) -> Vector2i:
	if center.x != origin.x: return Vector2i(signi(center.x - origin.x), 0)
	if center.y != origin.y: return Vector2i(0, signi(center.y - origin.y))
	return Vector2i.ZERO


static func line_cells(center: Vector2i, size: int, origin: Vector2i, map_size: Vector2i, terrain: Dictionary = {}, mode: int = 2) -> Array:
	var step := line_direction(origin, center)
	var coverage := Propagation.line_coverage(size, origin, center, terrain["words"], map_size, mode) if terrain.has("words") else {}
	var result: Array = []
	for index in range(1 if step == Vector2i.ZERO else size):
		var cell: Vector2i = center + step * index
		if not _inside(cell, map_size): break
		if terrain.has("words") and not coverage.has(cell): continue
		result.append(cell)
	return result


static func effect_cells(center: Vector2i, fields: Dictionary, data: Dictionary, map_size: Vector2i, origin: Variant = null, terrain: Dictionary = {}) -> Array:
	if definition_error(fields, data) != "": return []
	var pattern: Dictionary = data["ranges"][fields["effect_range"]]
	var area := terrain.has("words") and terrain.get("area_modes") is Dictionary
	var mode := int(terrain["area_modes"]["support" if is_support(fields, data) else "offensive"]) if area else 2
	if is_line(pattern):
		# The caster position is a necessary input for a line footprint; no default direction.
		if not origin is Vector2i: return []
		return line_cells(center, int(pattern["size"]), origin, map_size, terrain if area else {}, mode)
	if area:
		if not _inside(center, map_size): return []
		return Propagation.cells(Propagation.area_coverage(pattern["data"], center, terrain["words"], map_size, mode))
	var result: Array = []
	var half := int(pattern["size"]) / 2
	for y in range(int(pattern["size"])):
		for x in range(int(pattern["size"])):
			var cell := center + Vector2i(x - half, y - half)
			if int(pattern["data"][y][x]) > 0 and _inside(cell, map_size): result.append(cell)
	return result


## The cells a cast from `origin` centred on `center` settles over: the effect footprint
## of a legal center, [] for a center outside the cast range. SkillResolutionRules
## prepare_cast／RepeatedSpecialRules read their targets from it and the player's
## targeting preview draws it (BattleSceneOverlays.refresh_skill_footprint) — one set.
static func cast_footprint(origin: Vector2i, center: Vector2i, fields: Dictionary, data: Dictionary, map_size: Vector2i, terrain: Dictionary = {}) -> Array:
	if not cells(origin, fields, data, map_size, terrain).has(center): return []
	return effect_cells(center, fields, data, map_size, origin, terrain)


static func candidate_centers(caster: Dictionary, units: Array, fields: Dictionary, data: Dictionary, map_size: Vector2i, origin: Vector2i) -> Array:
	# Inverse footprint: this is exactly every map cell whose effect can reach a
	# living eligible target, including empty ground. No actor is invented there.
	var result: Array = []
	var seen := {}
	var pattern: Dictionary = data["ranges"][fields["effect_range"]]
	var half := int(pattern["size"]) / 2
	for unit in units:
		if not _living(unit) or unit.get("battle_actor_role") not in ROLES or not side_matches(caster, unit, fields, data): continue
		for coord in Footprint.cells(unit, origin if unit["id"] == caster["id"] else null):
			if is_line(pattern):
				# Inverse line: a center reaches this cell only along the four axes; test
				# each candidate through the same forward projection.
				for step in [Vector2i.ZERO, Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
					for index in range(1 if step == Vector2i.ZERO else int(pattern["size"])):
						var center: Vector2i = coord - step * index
						if _inside(center, map_size) and not seen.has(center) and line_cells(center, int(pattern["size"]), origin, map_size).has(coord):
							seen[center] = true
							result.append(center)
				continue
			for y in range(int(pattern["size"])):
				for x in range(int(pattern["size"])):
					if int(pattern["data"][y][x]) <= 0: continue
					var center: Vector2i = coord - Vector2i(x - half, y - half)
					if _inside(center, map_size) and not seen.has(center):
						seen[center] = true
						result.append(center)
	result.sort_custom(func(a, b): return a.y < b.y or (a.y == b.y and a.x < b.x))
	return result


## The cast range. With `terrain` the cells are the 0x40f8b0 coverage (mode `cast_mode`,
## flag 0): walls stop it, occupants never do; the origin keeps the remake rule below.
static func cells(origin: Vector2i, fields: Dictionary, data: Dictionary, map_size: Vector2i, terrain: Dictionary = {}) -> Array:
	if definition_error(fields, data) != "" or not _inside(origin, map_size):
		return []
	var pattern: Dictionary = data["ranges"][fields["range"]]
	var support := is_support(fields, data)
	var half := int(pattern["size"]) / 2
	var reached := Propagation.weapon_coverage(pattern["data"], origin, terrain["words"], map_size, int(terrain.get("cast_mode", Propagation.PLAYER_CAST_MODE)), false) if terrain.has("words") else {}
	var result: Array = []
	for y in range(int(pattern["size"])):
		for x in range(int(pattern["size"])):
			var point := origin + Vector2i(x - half, y - half)
			if int(pattern["data"][y][x]) > 0 and (point != origin or support or self_centered(fields)) and _inside(point, map_size) and (not terrain.has("words") or reached.has(point)):
				result.append(point)
	return result


static func _inside(point: Vector2i, map_size: Vector2i) -> bool:
	return point.x >= 0 and point.y >= 0 and point.x < map_size.x and point.y < map_size.y


static func _living(unit: Dictionary) -> bool:
	return Footprint.Presence.living(unit)


static func is_support(fields: Dictionary, data: Dictionary) -> bool:
	# Native mode3 classification (0x18f62): any support bit selects allies; dispel/steal/cancel stay mode2.
	var mask := function_mask(fields.get("function"), data.get("function_bits", {}))
	return mask > 0 and (mask & SPECIAL_SUPPORT_MASK) != 0


static func self_centered(fields: Dictionary) -> bool:
	return fields.get("range") == "range0Cell" and fields.get("effect_range") != "range0Cell"


static func side_matches(caster: Dictionary, target: Dictionary, fields: Dictionary, data: Dictionary) -> bool:
	# Side bits of the installed player_mode: offensive skills need disjoint sides
	# (0x40bb80 / 0x40f8b0), support skills an overlapping side. The player's magic and
	# special ranges also keep a pmALL occupant (the level-37 gems, pmMagicAttack):
	# ActorRoleRules.player_range_selectable; AI casters keep the target scan's disjoint sides.
	if is_support(fields, data):
		return Sides.same_side(caster, target)
	if str(caster.get("battle_actor_role", "")) == "player_controlled":
		return Sides.player_range_selectable(caster, target, true)
	return Sides.hostile(caster, target) and caster["id"] != target["id"]


static func area_side_matches(caster: Dictionary, target: Dictionary, fields: Dictionary, data: Dictionary) -> bool:
	# Who a cast's area takes in once its centre is chosen. static-derived (hsl01.exe
	# 0x40fdc0, the area mask 0x4104d0 walks for the targets): a cell whose occupant
	# shares the caster mode's excluded side is dropped unless its side is pmALL, so a pmALL
	# occupant (the level-37 gems) is in every caster's offensive area, the AI's too.
	# (The same builder also drops pmNPCPlayerNoMagic 0x850000 occupants; no remake unit has it.)
	if side_matches(caster, target, fields, data):
		return true
	return not is_support(fields, data) and Sides.side_mask(target) == Sides.SIDE_MASK and caster["id"] != target["id"]


static func target_error(caster: Dictionary, target: Dictionary, origin: Vector2i, fields: Dictionary, data: Dictionary, map_size: Vector2i, terrain: Dictionary = {}) -> String:
	var error := definition_error(fields, data)
	if error != "":
		return error
	if caster.get("battle_actor_role") not in ROLES or target.get("battle_actor_role") not in ROLES:
		return "unsupported_target_role"
	if not _living(caster) or not _living(target):
		return "target_unavailable"
	if str(caster.get("id", "")) == "" or str(target.get("id", "")) == "":
		return "invalid_target_identity"
	if not side_matches(caster, target, fields, data):
		return "not_ally" if is_support(fields, data) else "not_enemy"
	var covered := effect_cells(origin, fields, data, map_size, origin, terrain) if self_centered(fields) else cells(origin, fields, data, map_size, terrain)
	if not target.get("coord") is Vector2i or not Footprint.overlaps(target, covered):
		return "out_of_range"
	return ""
