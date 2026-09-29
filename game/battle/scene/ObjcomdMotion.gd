extends RefCounted
## The native motion of the SPECIAL-script objects: every defProcObjectMove object (process
## slot 37 → 0x4051d0) runs its objcomd.txt command program, executed per tick on the original
## instructions (hsltools/probes/objcomd_motion.py → objcomd_motion.json) with every object it
## throws. Same instance columns as EffectObjectMotion; positions are relative to the object's
## creation point. Random programs carry up to four seed variants; `variant(order)` spreads
## repeated insertions over them. Nothing here owns combat truth, a clock or a random stream.
## provenance:
##   layout: static-derived content/generated/hsl/skills/objcomd_motion.json
##   layout: static-derived docs/evidence_packets/static_reverse/original_objcomd_programs.md
##   layout: provisional
##     (seed variants stand in for the one shared RNG stream; off-screen waits end where the first script insertion
##     point would)
##   timing: static-derived content/generated/hsl/skills/objcomd_motion.json
const ContentPaths = preload("res://game/sim/ContentPaths.gd")
const EffectObjectMotion = preload("res://game/battle/scene/EffectObjectMotion.gd")
const PATH := "res://content/generated/hsl/skills/objcomd_motion.json"

static var _packet: Dictionary = {}
static var _decoded: Dictionary = {}


static func packet() -> Dictionary:
	if _packet.is_empty():
		_packet = ContentPaths.read_json(PATH)
	return _packet


## `object_name` is an object symbol or a patterned insert's key (`pattern_key`), whose
## variants are its instances in the inserter's creation order.
static func tracked(object_name: String) -> bool:
	return packet()["objects"].has(object_name) or packet().get("patterns", {}).has(object_name)


## The packet key of a patterned insert as the script writes it (`op:code,x,y,…`); tracked only
## for the rows the probe runs natively (objcomd_motion.py PATTERN_ROWS).
static func pattern_key(op: String, args: Array) -> String:
	return op + ":" + ",".join(args.map(func(word): return str(word)))


static func _row(object_name: String) -> Dictionary:
	var row: Dictionary = packet()["objects"].get(object_name, {})
	return row if not row.is_empty() else packet().get("patterns", {}).get(object_name, {})


## Frames until the last instance is gone; open-ended programs (objmOver holds, endless loops)
## report the probe's frame limit and `open_ended`. `hit` picks the hit run where it differs.
static func frames(object_name: String, hit: bool = false) -> int:
	var row: Dictionary = _row(object_name)
	return int(row["hit_frames"]) if hit and row.has("hit_frames") else int(row["frames"])


static func open_ended(object_name: String) -> bool:
	return bool(_row(object_name)["open_ended"])


static func variants(object_name: String) -> int:
	return (_row(object_name)["variants"] as Array).size()


## [frame, WAV, hit_only] the variant's program played in the probe's hit run (objmPlaySound
## 0x4059b7; objmPlayHitSound 0x4059cf only on a hit).
static func sounds(object_name: String, variant: int = 0) -> Array:
	var row: Dictionary = _row(object_name)
	if row.has("variant_sounds"):
		return row["variant_sounds"][variant % (row["variant_sounds"] as Array).size()]
	return row["sounds"]


## The frame the variant's program reads the hit word [0x4c1418]: its first objmPlayHitSound
## (0x4059cf), the hit-only throws (0x405434／0x405495) running on the same frame just before
## it; -1 for a program that plays no hit-only sound.
static func hit_read_frame(object_name: String, variant: int = 0) -> int:
	var read := -1
	for sound in sounds(object_name, variant):
		if bool(sound[2]) and (read < 0 or int(sound[0]) < read):
			read = int(sound[0])
	return read


## The decoded tree of one variant, in EffectObjectMotion.track's shape plus its `members`
## table, for EffectObjectMotion.sprites_at. `hit`: the hit run (hit roll [0x4c1418] under the
## hit rate [0x4c6f58]), whose hit-only throws (0x405434／0x405495) the miss run lacks; objects
## without `hit_variants` run the same either way.
static func track(object_name: String, variant: int = 0, hit: bool = false) -> Dictionary:
	var row: Dictionary = _row(object_name)
	var runs_key := "hit_variants" if hit and row.has("hit_variants") else "variants"
	var key := "%s#%d#%s" % [object_name, variant, runs_key]
	if _decoded.has(key):
		return _decoded[key]
	var instances: Array = []
	for instance in row[runs_key][variant % (row[runs_key] as Array).size()]:
		if int(instance["start"]) < 0:
			continue
		instances.append({"code": int(instance["code"]), "start": int(instance["start"]),
			"x": PackedInt32Array(instance["x"]), "y": PackedInt32Array(instance["y"]),
			"member": EffectObjectMotion._expand(instance["member"]), "mode": EffectObjectMotion._expand(instance["mode"]),
			"level": EffectObjectMotion._expand(instance["level"]),
			"zoom_x": EffectObjectMotion._expand(instance["zoom_x"]), "zoom_y": EffectObjectMotion._expand(instance["zoom_y"])})
	var decoded := {"motion": "translates", "frames": frames(object_name, hit), "instances": instances, "members": packet()["members"]}
	_decoded[key] = decoded
	return decoded


static func sprites_at(object_name: String, variant: int, frame: int, hit: bool = false) -> Array:
	return EffectObjectMotion.sprites_at(track(object_name, variant, hit), frame)


## [frame, op] of the variant's objmInitMultiHitData (71, 0x4c6f6a++) and objmSetMultiHitData
## (72, 0x4c6f6a--, 0x4c6f68++) in the probe's hit run; [] for a program that runs neither.
static func multi_hits(object_name: String, variant: int = 0) -> Array:
	var row: Dictionary = _row(object_name)
	if row.has("variant_multi_hit"):
		return row["variant_multi_hit"][variant % (row["variant_multi_hit"] as Array).size()]
	return row.get("multi_hit", [])
