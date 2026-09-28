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


static func tracked(object_name: String) -> bool:
	return packet()["objects"].has(object_name)


## Frames until the last instance is gone; open-ended programs (objmOver holds, endless loops)
## report the probe's frame limit and `open_ended`.
static func frames(object_name: String) -> int:
	return int(packet()["objects"][object_name]["frames"])


static func open_ended(object_name: String) -> bool:
	return bool(packet()["objects"][object_name]["open_ended"])


static func variants(object_name: String) -> int:
	return (packet()["objects"][object_name]["variants"] as Array).size()


## [frame, WAV, hit_only] the variant's program played in the probe's hit run (objmPlaySound
## 0x4059b7; objmPlayHitSound 0x4059cf only on a hit).
static func sounds(object_name: String, variant: int = 0) -> Array:
	var row: Dictionary = packet()["objects"][object_name]
	if row.has("variant_sounds"):
		return row["variant_sounds"][variant % (row["variant_sounds"] as Array).size()]
	return row["sounds"]


## The decoded tree of one variant, in EffectObjectMotion.track's shape plus its `members`
## table, for EffectObjectMotion.sprites_at.
static func track(object_name: String, variant: int = 0) -> Dictionary:
	var key := "%s#%d" % [object_name, variant]
	if _decoded.has(key):
		return _decoded[key]
	var row: Dictionary = packet()["objects"][object_name]
	var instances: Array = []
	for instance in row["variants"][variant % (row["variants"] as Array).size()]:
		if int(instance["start"]) < 0:
			continue
		instances.append({"code": int(instance["code"]), "start": int(instance["start"]),
			"x": PackedInt32Array(instance["x"]), "y": PackedInt32Array(instance["y"]),
			"member": EffectObjectMotion._expand(instance["member"]), "mode": EffectObjectMotion._expand(instance["mode"]),
			"level": EffectObjectMotion._expand(instance["level"]),
			"zoom_x": EffectObjectMotion._expand(instance["zoom_x"]), "zoom_y": EffectObjectMotion._expand(instance["zoom_y"])})
	var decoded := {"motion": "translates", "frames": int(row["frames"]), "instances": instances, "members": packet()["members"]}
	_decoded[key] = decoded
	return decoded


static func sprites_at(object_name: String, variant: int, frame: int) -> Array:
	return EffectObjectMotion.sprites_at(track(object_name, variant), frame)
