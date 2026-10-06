extends RefCounted
## Original center or eight-cell ring. Every cell derives from the same actor.
## provenance:
##   rules: static-derived docs/evidence_packets/static_reverse/original_large_actor.md
const Presence = preload("res://game/sim/BattlePresenceRules.gd")

static func radius(actor: Dictionary) -> int:
	return int(actor["traversal"]["size_type"])

static func cells(actor: Dictionary, origin: Variant = null) -> Array:
	var center: Vector2i = actor["coord"] if origin == null else origin
	var extent := radius(actor)
	var result: Array = []
	for y in range(-extent, extent + 1):
		for x in range(-extent, extent + 1): result.append(center + Vector2i(x,y))
	return result

static func contains(actor: Dictionary, point: Vector2i, origin: Variant = null) -> bool:
	var center: Vector2i = actor["coord"] if origin == null else origin
	var delta := point - center
	var extent := radius(actor)
	return absi(delta.x) <= extent and absi(delta.y) <= extent

static func overlaps(actor: Dictionary, area: Array, origin: Variant = null) -> bool:
	for point in area:
		if contains(actor, point, origin): return true
	return false

static func contact(actor: Dictionary, area: Array) -> Variant:
	if area.has(actor["coord"]): return actor["coord"]
	for point in area:
		if contains(actor, point): return point
	return null

static func distance(first: Dictionary, second: Dictionary, first_origin: Variant = null) -> int:
	var origin: Vector2i = first["coord"] if first_origin == null else first_origin
	var delta: Vector2i = origin - second["coord"]
	var extent := radius(first) + radius(second)
	return maxi(0, absi(delta.x)-extent) + maxi(0, absi(delta.y)-extent)

## `units` in the order 0x4104d0 lists them over the effect cells `area`: it walks the coverage
## window row by row from its top-left cell, x rising within a row, and lists each actor once, at
## the first covered cell of its body. Units sharing that first cell keep their roster order;
## units outside `area` follow, in roster order.
static func scan_order(units: Array, area: Array) -> Array:
	var walk := area.duplicate()
	walk.sort_custom(func(a, b): return a.y < b.y or (a.y == b.y and a.x < b.x))
	var rank := {}
	for index in range(walk.size()): rank[walk[index]] = index
	var ranked: Array = []
	for index in range(units.size()):
		var first := walk.size()
		if units[index] is Dictionary and units[index].get("coord") is Vector2i:
			# cells() runs row by row as well, so its first covered cell is the walk's earliest.
			for cell in cells(units[index]):
				if rank.has(cell):
					first = rank[cell]
					break
		ranked.append([first, index])
	ranked.sort_custom(func(a, b): return a[0] < b[0] or (a[0] == b[0] and a[1] < b[1]))
	return ranked.map(func(entry): return units[entry[1]])

static func unit_at(units: Array, point: Vector2i) -> Dictionary:
	var fallback := {}
	for actor in units:
		if not actor is Dictionary or not Presence.living(actor): continue
		if not contains(actor,point): continue
		if not actor["traversal"]["no_block"]: return actor
		fallback = actor
	return fallback

## `unit_at` for every occupied cell at once (cell → the unit `unit_at` returns there):
## the first blocking unit in roster order wins a cell, else its last no-block unit.
static func occupants(units: Array) -> Dictionary:
	var blocking := {}
	var fallback := {}
	for actor in units:
		if not actor is Dictionary or not Presence.living(actor): continue
		for cell in cells(actor):
			if not actor["traversal"]["no_block"]:
				if not blocking.has(cell): blocking[cell] = actor
			else: fallback[cell] = actor
	for cell in fallback:
		if not blocking.has(cell): blocking[cell] = fallback[cell]
	return blocking
