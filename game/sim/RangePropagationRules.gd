extends RefCounted
## Original range propagation over the map words: which cells of a RANGE record a weapon,
## a cast range or a skill area actually covers once the 0x4000 wall flag and the
## occupants' side bits are read. Pure; callers pass the rows, the anchor, the cell words
## (`cell_words`) and the builder mode, and keep their own origin／side policy.
##
##   weapon 0x40f8b0 → 0x40f5d0: player weapon 0x444156 (mode 2, flag 1), counters and AI
##          weapons (0x40bab0 mode, flag 1), player magic／special cast range 0x444eb7／
##          0x445075／0x44508f (mode -1, flag 0)
##   area   0x4100e0 → 0x40fdc0 flood for a matrix record, a straight line for RANGE 21..23
##          (player effect areas 0x444f08／0x4450e0: mode 2 offensive, 3 support)
##
## Every step (hsl01.exe, static-derived, 354 native returns in original_range_terrain.json):
## off-map stop; a 0x4000 word stops; a zero RANGE value stops; coverage already >= power
## stops; a positive value writes the power unless the step table's side mask excludes the
## occupant (pmALL kept, except a pmMagicAttack pmALL occupant for flag 1), then an onward
## check (0x40eb80 over the three cells ahead) zeroes the power next to a wall; power-1,
## stop at 0; up／down／left／right continue in the native DFS order. A negative value
## carries the flood without writing and without the onward check. Heights are not read.
## provenance:
##   rules: static-derived docs/evidence_packets/static_reverse/original_weapon_ranges.md
##   rules: static-derived docs/evidence_packets/static_reverse/original_range_terrain.json
##   rules: remake-invented
##     (map words from WRD movement_flags and FootprintRules.occupants; ACTOR marker for 0x40fc90's hit; local frame
##     unclamped — every battlefield ≥ 20x15, largest record 13x13)

const Footprint = preload("res://game/sim/FootprintRules.gd")
const ActorRoleRules = preload("res://game/sim/ActorRoleRules.gd")
const TerrainEditRules = preload("res://game/sim/TerrainEditRules.gd")

const WALL := 0x4000
const P := 0x10000
const E := 0x20000
const N := 0x40000
const ALL := 0x70000
const MAGIC := 0x800000
const NO_MAGIC_NPC := 0x850000
## Remake-only marker (no original bit): a living actor stands on the cell, so 0x40fc90
## returns it and 0x40fdc0／0x4100e0 test 0 instead of the word against 0x850000.
const ACTOR := 0x1000000
## Origin／line side exclusion: tables 0x40fa48 (0x40f8b0) and 0x410498 (0x4100e0), identical.
const ORIGIN_EXCLUSION := {0: P, 1: P, 2: P, 3: E, 4: P, 5: E, 7: N, 8: 0x60000, 9: 0x50000, 10: 0x30000}
## 0x40f5d0 step table 0x40f874: mode -> [side mask, onward check]; default [0, false].
const WEAPON_STEP := {2: [P, true], 3: [E, true], 4: [P, false], 5: [E, false], 6: [0, false], 7: [N, true],
	8: [0x60000, true], 9: [0x50000, true], 10: [0x30000, true]}
## 0x40fdc0 step table 0x4100a0: mode -> [side mask, onward check]; default [0, true].
const AREA_STEP := {0: [0, false], 1: [0, false], 2: [P, true], 3: [E, true], 4: [P, false], 5: [E, false], 6: [0, true],
	7: [N, true], 8: [0x60000, true], 9: [0x50000, true], 10: [0x30000, true]}
## Player cast range mode (0x444eb7／0x445075／0x44508f push -1, flag 0).
const PLAYER_CAST_MODE := -1
## Player effect area modes (0x4c2c78 = 2 offensive, 3 support before 0x444f08／0x4450e0).
const PLAYER_AREA_MODES := {"offensive": 2, "support": 3}

static var _walls := {"tiles": null, "words": {}}


## The occupant word a unit leaves on its cells: the installed player_mode's side and
## pmMagicAttack bits, else the side its role implies.
static func side_word(unit: Dictionary) -> int:
	if unit.has("player_mode"): return int(unit["player_mode"]) & (ActorRoleRules.SIDE_MASK | ActorRoleRules.MAGIC_ONLY_BIT)
	return ActorRoleRules.side_mask(unit)


## Map words the range builders read (0x4c0928): the WRD 0x4000 flag and every living
## occupant's side word plus the ACTOR marker. Heights (h 255) are not part of it.
static func cell_words(tiles: Dictionary, units: Array) -> Dictionary:
	if not is_same(_walls["tiles"], tiles):
		var walls := {}
		for cell in tiles:
			if int(tiles[cell].get("movement_flags", 0)) & WALL: walls[cell] = WALL
		_walls = {"tiles": tiles, "words": walls}
	var words: Dictionary = _walls["words"].duplicate()
	var occupants := Footprint.occupants(units)
	for cell in occupants:
		words[cell] = int(words.get(cell, 0)) | side_word(occupants[cell]) | ACTOR
	return words


static func loop_words(loop: Dictionary) -> Dictionary:
	return cell_words(TerrainEditRules.tiles(loop), loop["units"])


## 0x40bab0: the offensive builder mode from the actor's player_mode (P 2, else E 3, else
## N 7); a sideless actor gets the value 0x10000, which no table lists.
static func offensive_mode(actor: Dictionary) -> int:
	var side := side_word(actor)
	if side & P: return 2
	if side & E: return 3
	if side & N: return 7
	return 0x10000


## The player's skill terrain: cast range always, effect area only when `area` is set.
static func player_skill_terrain(loop: Dictionary, area: bool = false) -> Dictionary:
	var terrain := {"words": loop_words(loop), "cast_mode": PLAYER_CAST_MODE}
	if area: terrain["area_modes"] = PLAYER_AREA_MODES
	return terrain


## 0x40f8b0(px, py, range, mode, flag5): written coverage {cell: power} of a matrix record.
static func weapon_coverage(rows: Array, origin: Vector2i, words: Dictionary, map_size: Vector2i, mode: int, flag5: bool) -> Dictionary:
	var state := _state(rows, origin, words, map_size, WEAPON_STEP.get(mode, [0, false]), flag5, false)
	if not int(words.get(origin, 0)) & int(ORIGIN_EXCLUSION.get(mode, 0)):
		state["cov"][origin] = state["half"] + 1
	return _flood(state)


## 0x4100e0 matrix branch: the centre is written unless its side is excluded (pmALL kept)
## or it is an actorless 0x850000 word; no 0x4000 or RANGE check on the centre itself.
static func area_coverage(rows: Array, center: Vector2i, words: Dictionary, map_size: Vector2i, mode: int) -> Dictionary:
	var state := _state(rows, center, words, map_size, AREA_STEP.get(mode, [0, true]), false, true)
	var word := int(words.get(center, 0))
	if (not word & int(ORIGIN_EXCLUSION.get(mode, 0)) or word & ALL == ALL) and not _no_magic_npc(word):
		state["cov"][center] = state["half"] + 1
	return _flood(state)


## 0x4100e0 line branch (RANGE 21..23): from the chosen cell away from the caster, a
## differing column first; the caster's own cell gives length 1. Off-map or a 0x4000 word
## ends the line; an excluded occupant is skipped and the line runs on. {cell: remaining+1}.
static func line_coverage(size: int, caster: Vector2i, target: Vector2i, words: Dictionary, map_size: Vector2i, mode: int) -> Dictionary:
	var step := Vector2i.ZERO
	if target.x != caster.x: step = Vector2i(signi(target.x - caster.x), 0)
	elif target.y != caster.y: step = Vector2i(0, signi(target.y - caster.y))
	var excl := int(ORIGIN_EXCLUSION.get(mode, 0))
	var cov := {}
	var cell := target
	var length := 1 if step == Vector2i.ZERO else size
	for remaining in range(length - 1, -1, -1):
		if not inside(cell, map_size): break
		var word := int(words.get(cell, 0))
		if word & WALL: break
		if not (word & excl and word & ALL != ALL) and not _no_magic_npc(word): cov[cell] = remaining + 1
		cell += step
	return cov


## Written cells of a coverage in row-major order, optionally without `skip`.
static func cells(coverage: Dictionary, skip: Variant = null) -> Array:
	var result: Array = []
	for cell in coverage:
		if int(coverage[cell]) > 0 and cell != skip: result.append(cell)
	result.sort_custom(func(a, b): return a.y < b.y or (a.y == b.y and a.x < b.x))
	return result


static func _state(rows: Array, anchor: Vector2i, words: Dictionary, map_size: Vector2i, step: Array, flag5: bool, area: bool) -> Dictionary:
	return {"rows": rows, "anchor": anchor, "half": rows.size() >> 1, "words": words, "map_size": map_size,
		"excl": int(step[0]), "check": bool(step[1]), "flag5": flag5, "area": area, "cov": {}}


static func _flood(state: Dictionary) -> Dictionary:
	var anchor: Vector2i = state["anchor"]
	var half: int = state["half"]
	_visit(state, anchor + Vector2i.UP, half, 0)
	_visit(state, anchor + Vector2i.DOWN, half, 1)
	_visit(state, anchor + Vector2i.LEFT, half, 2)
	_visit(state, anchor + Vector2i.RIGHT, half, 3)
	return state["cov"]


## One 0x40f5d0／0x40fdc0 call. Direction 0 up, 1 down, 2 left, 3 right.
static func _visit(state: Dictionary, cell: Vector2i, power: int, direction: int) -> void:
	var cov: Dictionary = state["cov"]
	var words: Dictionary = state["words"]
	var rows: Array = state["rows"]
	var offset: Vector2i = Vector2i(state["half"], state["half"]) - state["anchor"]
	while power > 0:
		if not inside(cell, state["map_size"]): return
		var word := int(words.get(cell, 0))
		if word & WALL: return
		var local: Vector2i = cell + offset
		var value := int(rows[local.y][local.x])
		if value == 0 or int(cov.get(cell, 0)) >= power: return
		if value > 0:
			if not _skip(state, word): cov[cell] = power
			if state["check"] and not _onward_clear(cell, direction, words, state["map_size"]): power = 0
		power -= 1
		if power <= 0: return
		match direction:
			0:
				_visit(state, cell + Vector2i.UP, power, 0)
				_visit(state, cell + Vector2i.LEFT, power, 2)
				cell += Vector2i.RIGHT
				direction = 3
			1:
				_visit(state, cell + Vector2i.DOWN, power, 1)
				_visit(state, cell + Vector2i.LEFT, power, 2)
				cell += Vector2i.RIGHT
				direction = 3
			2:
				_visit(state, cell + Vector2i.UP, power, 0)
				_visit(state, cell + Vector2i.DOWN, power, 1)
				cell += Vector2i.LEFT
			_:
				_visit(state, cell + Vector2i.UP, power, 0)
				_visit(state, cell + Vector2i.DOWN, power, 1)
				cell += Vector2i.RIGHT


static func _skip(state: Dictionary, word: int) -> bool:
	var excluded := bool(word & int(state["excl"]))
	if state["area"]:
		return (excluded and word & ALL != ALL) or _no_magic_npc(word)
	return excluded and (word & ALL != ALL or (bool(state["flag5"]) and bool(word & MAGIC)))


static func _no_magic_npc(word: int) -> bool:
	return not word & ACTOR and word & 0x870000 == NO_MAGIC_NPC


## 0x40eb80(x, y, dir, 0x4000): clear when none of the three cells ahead／sideways of the
## step carries 0x4000; off-map cells read 0.
static func _onward_clear(cell: Vector2i, direction: int, words: Dictionary, map_size: Vector2i) -> bool:
	var ahead: Array
	match direction:
		0: ahead = [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1)]
		1: ahead = [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, 1)]
		2: ahead = [Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0)]
		_: ahead = [Vector2i(0, -1), Vector2i(0, 1), Vector2i(1, 0)]
	for delta in ahead:
		var point: Vector2i = cell + delta
		if inside(point, map_size) and int(words.get(point, 0)) & WALL: return false
	return true


static func inside(point: Vector2i, map_size: Vector2i) -> bool:
	return point.x >= 0 and point.y >= 0 and point.x < map_size.x and point.y < map_size.y
