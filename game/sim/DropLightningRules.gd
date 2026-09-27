extends RefCounted
## 打人閃電 (OBS process defProcDropLightn = PROCESS.DEF 67 → 0x43ca70): one bolt somewhere in
## the view (WINFAIL010 event 6 actInsertStoryObjectWait). Writes the loop it is handed: the
## global stream and the struck units' HP; returns the receipt the presentation replays.
## provenance:
##   rules: static-derived docs/evidence_packets/static_reverse/original_drop_lightning.md (the view: the live camera 0x4c091c／0x4c0920, via presentation_view); runtime-measured docs/evidence_packets/static_reverse/original_drop_lightning.md (整镜像裁判 LEVEL010, 落点与伤害按抽前随机字逐值重算); remake-invented (headless: the ending actor centred as by 0x43bf30; the camera is read at commit, not at the hand-off scan)
##   layout: n/a
##   strings: n/a
##   timing: n/a
##   audio: n/a
const GlobalRandom = preload("res://game/sim/GlobalRandomStream.gd")
const Footprint = preload("res://game/sim/FootprintRules.gd")
## 640×480 screen; 0x43bf30 centres an object at (x − 320, y − 192), clamped to the map.
const SCREEN := Vector2i(640, 480)
const HALF := Vector2i(320, 240)
const FOCUS := Vector2i(320, 192)
## 0x43cbe1..0x43cc7f: 0x43c9d0(x + dx·32, y + dy·32, lo, hi), the centre first, then the ring row by row.
const CELLS := [[0, 0, 16, 32], [-1, -1, 4, 16], [0, -1, 4, 16], [1, -1, 4, 16], [-1, 0, 4, 16], [1, 0, 4, 16], [-1, 1, 4, 16], [0, 1, 4, 16], [1, 1, 4, 16]]


## `view`: the presentation's camera top-left in map pixels (0x4c091c／0x4c0920) when a scene
## runs the battle; otherwise null and the view centres `focus` (0x43bf30: x − 320, y − 192).
static func strike(loop: Dictionary, focus: Vector2i, shape_count: int, cell_size: int, view: Variant = null) -> Dictionary:
	var map_px: Vector2i = (loop.get("map_size", Vector2i.ZERO) as Vector2i) * cell_size
	var source := "presentation" if view is Vector2i else "actor_centre"
	var top_left: Vector2i = view if view is Vector2i else focus - FOCUS
	var camera := Vector2i(clampi(top_left.x, 0, maxi(map_px.x - SCREEN.x, 0)), clampi(top_left.y, 0, maxi(map_px.y - SCREEN.y, 0)))
	# Creation message (0x43ca8a): global rand(640) above 320 folded to r − 640, rand(480)
	# above 240 to r − 480, around the view centre (camera + 320, camera + 240).
	var rx := GlobalRandom.loop_draw(loop, SCREEN.x)
	var ry := GlobalRandom.loop_draw(loop, SCREEN.y)
	var pixel := Vector2i(camera.x + HALF.x + (rx - SCREEN.x if rx > HALF.x else rx), camera.y + HALF.y + (ry - SCREEN.y if ry > HALF.y else ry))
	# State 0 (0x43cb3d), once the camera has scrolled onto it: frame rand(obj_Shape_Number).
	var frame := GlobalRandom.loop_draw(loop, shape_count)
	var hits: Array = []
	for entry in CELLS:
		var cell := Vector2i(floori(float(pixel.x + 32 * int(entry[0])) / cell_size), floori(float(pixel.y + 32 * int(entry[1])) / cell_size))
		var unit: Dictionary = Footprint.unit_at(loop.get("units", []), cell)   # 0x407800
		if unit.is_empty():
			continue
		# 0x43c9d0: damage lo + rand(hi − lo + 1) on the global stream, any side, no hit roll,
		# never below 1 HP (+0xd8); a unit already at 1 takes and shows nothing.
		var lo := int(entry[2])
		var damage := GlobalRandom.loop_draw(loop, int(entry[3]) - lo + 1) + lo
		var before := int(unit.get("hp", 0))
		var left := before - damage
		if left < 1:
			damage += left - 1
			left = 1
		unit["hp"] = left
		if damage != 0:
			hits.append({"unit_id": str(unit.get("id", "")), "cell": cell, "damage": damage, "hp_before": before, "hp_after": left})
	return {"camera": camera, "view_source": source, "pixel": pixel, "frame": frame, "hits": hits, "linger_ticks": 80 if not hits.is_empty() else 20}
