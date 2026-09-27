extends RefCounted
## Original center or eight-cell ring. Every cell derives from the same actor.
## provenance:
##   rules: static-derived docs/evidence_packets/static_reverse/original_large_actor.md
##   layout: n/a
##   strings: n/a
##   timing: n/a
##   audio: n/a
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
