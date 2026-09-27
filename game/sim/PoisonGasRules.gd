extends RefCounted
## 噴人沼氣 (OBS process defProcPoisonGas = PROCESS.DEF 71 → 0x43c7c0): one gas burst at a
## script position (actInsertStoryObjectWaitPos). Writes the loop it is handed: both random
## streams and the hit units' poison; returns the receipt the presentation replays. Also the
## terrain poison of the action end (0x4454a5／0x441eb8): the same 0x409140 with n = 3.
## provenance:
##   rules: static-derived docs/evidence_packets/static_reverse/original_poison_gas.md; runtime-measured docs/evidence_packets/static_reverse/original_poison_gas.md (整镜像裁判 LEVEL032, 43/43 逐值重算)
##   layout: n/a
##   strings: n/a
##   timing: n/a
##   audio: n/a
const DamageRandom = preload("res://game/sim/DamageRandomStream.gd")
const GlobalRandom = preload("res://game/sim/GlobalRandomStream.gd")
const Footprint = preload("res://game/sim/FootprintRules.gd")
const Status = preload("res://game/sim/StatusEffectRules.gd")
const StatusApplication = preload("res://game/sim/StatusApplicationRules.gd")
## 0x43c8f3..0x43c976: the centre cell with 5, then the ring row by row with 3.
const CELLS := [[0, 0, 5], [-1, -1, 3], [0, -1, 3], [1, -1, 3], [-1, 0, 3], [1, 0, 3], [-1, 1, 3], [0, 1, 3], [1, 1, 3]]
## 0x40e240 via 0x446b90: record +0x18c & (avoid_poison 0x800000 | 0x80) skips the unit.
const IMMUNE_MASK := 0x800080
const TURN_CAP := 4
## 0x411c40 map word bit the action end tests (only LEVEL015's WRD carries it, 290 cells).
const TERRAIN_POISON_FLAG := 0x200000


static func spew(loop: Dictionary, position: Array, shape_count: int, cell_size: int) -> Dictionary:
	# State 1 (0x43c84d): two global rand(65) offsets, above 32 folded to 32 - r (−32..32),
	# snapped to the containing cell (& ~31) and its centre (+16).
	var offsets: Array = []
	for _axis in 2:
		var r := GlobalRandom.loop_draw(loop, 65)
		offsets.append(32 - r if r > 32 else r)
	var centre := Vector2i(floori(float(int(position[0]) + int(offsets[0])) / cell_size), floori(float(int(position[1]) + int(offsets[1])) / cell_size))
	# Three obj_Fire_Smoke (706) at the centre, each showing gas frame rand(obj_Shape_Number).
	var frames: Array = []
	for _smoke in 3:
		frames.append(GlobalRandom.loop_draw(loop, shape_count))
	var hits: Array = []
	for entry in CELLS:
		var cell: Vector2i = centre + Vector2i(int(entry[0]), int(entry[1]))
		var unit: Dictionary = Footprint.unit_at(loop.get("units", []), cell)   # 0x407800
		if unit.is_empty() or Status.input_error(unit) != "":
			continue
		var mods := StatusApplication.modifiers(unit, loop.get("skill_book", {}), loop.get("equipment_items", {}))
		if not bool(mods.get("ok", false)) or (int(mods["effects"]) & IMMUNE_MASK) != 0:
			continue
		hits.append(poison(loop, unit, cell, int(entry[2])))
	# Next tick each smoke's first defProcFireSmoke call (0x43c260) draws the global stream:
	# rand(5) hold, rand(77) x and y offsets, rand(0x8000) rise speed — the presentation replays them.
	var smoke_draws: Array = []
	for _smoke in 3:
		smoke_draws.append([GlobalRandom.loop_draw(loop, 5), GlobalRandom.loop_draw(loop, 77), GlobalRandom.loop_draw(loop, 77), GlobalRandom.loop_draw(loop, 0x8000)])
	return {"position": position.duplicate(), "offsets": offsets, "centre": centre, "smoke_frames": frames,
		"smoke_draws": smoke_draws, "hits": hits, "linger_ticks": 90 if not hits.is_empty() else 40}


## Action end, before the treasure test and the status tail (player 0x4454a5..0x4454ef, AI
## 0x441eb8..0x441f00): the actor's own map word 0x411c40 & 0x200000, not flying
## (0x446ad0: record +0xa0 bit 1), not immune (0x446b90) → 0x409140(record, 3). Returns the
## receipt, or {} when nothing applies.
static func terrain(loop: Dictionary, actor: Dictionary, tiles: Dictionary) -> Dictionary:
	var cell: Vector2i = actor.get("coord", Vector2i(-1, -1))
	if not int((tiles.get(cell, {}) as Dictionary).get("tile_id", 0)) & TERRAIN_POISON_FLAG:
		return {}
	if bool((actor.get("traversal", {}) as Dictionary).get("flying", false)) or Status.input_error(actor) != "":
		return {}
	var mods := StatusApplication.modifiers(actor, loop.get("skill_book", {}), loop.get("equipment_items", {}))
	if not bool(mods.get("ok", false)) or (int(mods["effects"]) & IMMUNE_MASK) != 0:
		return {}
	return poison(loop, actor, cell, 3)


## 0x409140(record, n): flag 1; turns = min(4, old + 1 + rand_d(n)) only when that raises
## them; strength 0x406fe0(16, 32) (24 − rand_d(9) + rand_d(9)) merged as max(old, (old+new)/2).
static func poison(loop: Dictionary, unit: Dictionary, cell: Vector2i, n: int) -> Dictionary:
	var words: Dictionary = (unit["status_counters"] as Dictionary).duplicate(true)
	var before := int(words.get("poison", 0))
	var turns := before & 0xffff
	var raised := mini(TURN_CAP, DamageRandom.loop_draw(loop, n) + 1 + turns)
	if raised > turns:
		turns = raised
	var low := DamageRandom.loop_draw(loop, 9)
	var power := DamageRandom.loop_draw(loop, 9) + 24 - low
	var old_power := before >> 16
	if old_power != 0:
		power = maxi(old_power, (power + old_power) / 2)
	words["poison"] = (power << 16) | turns
	unit["status_counters"] = words
	unit["status_flags"] = int(unit["status_flags"]) | Status.POISON
	return {"unit_id": str(unit.get("id", "")), "cell": cell, "n": n, "before_word": before, "after_word": words["poison"]}
