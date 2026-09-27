extends RefCounted
## The native motion of the MAGIC effect objects: every effProc* program of
## defProcEffectProcess1 (0x415dc0) that runs through reviewed code was executed per tick on
## the original instructions (hsltools/probes/effect_motion.py → effect_motion.json), with
## every object it spawns — sparks, bullets, afterimages. A root object's track is a tree of
## instances; each instance holds, for every frame since the root was created, its position
## relative to the effect origin, its SHP member (−1 = not drawn that frame), its PROCESS.DEF
## eng* draw mode, its mix level (0..16) and its 16.16 zoom. The script player places a
## tracked object at its insertion tick and reads the frame the clip has reached; nothing here
## owns combat truth, a clock or a random stream.
## provenance:
##   layout: static-derived content/generated/hsl/skills/effect_motion.json
##   layout: static-derived docs/evidence_packets/static_reverse/original_effect_motion.md
##   layout: static-derived docs/evidence_packets/static_reverse/original_tick_counts.md
##   layout: provisional
##     (one RNG seed per root: random spark angles and spawn offsets replay identically for every instance; a member
##     hsl.pak lacks cycles the series' existing members like the untracked player)
##   timing: static-derived content/generated/hsl/skills/effect_motion.json
##   timing: provisional (±1 frame where the original plane-list order differs from the probe's)
const ContentPaths = preload("res://game/sim/ContentPaths.gd")
const PATH := "res://content/generated/hsl/skills/effect_motion.json"
## PROCESS.DEF eng* bits the tracks carry (resource-derived names; the effect process ORs
## engADDCOLOR into every object's mode at 0x415e52).
const ENG_MIX := 0x20000000
const ENG_ZOOM := 0x08000000
const ENG_ADDCOLOR := 0x04000000
const ENG_SUBCOLOR := 0x02000000
const LEVELS := 16.0
const FIXED_ONE := 65536.0

static var _packet: Dictionary = {}
static var _decoded: Dictionary = {}


static func packet() -> Dictionary:
	if _packet.is_empty():
		_packet = ContentPaths.read_json(PATH)
	return _packet


## True when `object_name` (an effCode object) has a native track.
static func tracked(object_name: String) -> bool:
	return packet()["objects"].has(object_name)


## The decoded tree of one tracked object: `motion` (translates／anchored／mixed／reshaped —
## how the probe's displaced run related to the plain one), `frames` (frames until the last
## instance is gone) and `instances` (start frame plus per-frame arrays).
static func track(object_name: String) -> Dictionary:
	if _decoded.has(object_name):
		return _decoded[object_name]
	var row: Dictionary = packet()["objects"][object_name]
	var instances: Array = []
	for instance in row["instances"]:
		if int(instance["start"]) < 0:
			continue
		instances.append({"code": int(instance["code"]), "start": int(instance["start"]),
			"x": PackedInt32Array(instance["x"]), "y": PackedInt32Array(instance["y"]),
			"member": _expand(instance["member"]), "mode": _expand(instance["mode"]), "level": _expand(instance["level"]),
			"zoom_x": _expand(instance["zoom_x"]), "zoom_y": _expand(instance["zoom_y"])})
	var decoded := {"motion": str(row["motion"]), "frames": int(row["frames"]), "instances": instances}
	_decoded[object_name] = decoded
	return decoded


## Run-length pairs [value, count] → one value per frame.
static func _expand(runs: Array) -> PackedInt32Array:
	var values := PackedInt32Array()
	for run in runs:
		for _index in range(int(run[1])):
			values.append(int(run[0]))
	return values


## The sprites the tree draws at `frame` (frames since the root's creation): one entry per
## drawn instance — `member` (SHP name), `offset` (from the effect origin), `scale`, `alpha`
## and `blend` (`add`／`sub`／`mix`). engZOOM scales by the 16.16 zoom (a negative one
## mirrors); engMIX weights the source by level／16; engADDCOLOR／engSUBCOLOR pick the
## saturating add／subtract kinds, otherwise a plain draw.
static func sprites_at(decoded: Dictionary, frame: int) -> Array:
	var members: Array = packet()["members"]
	var sprites: Array = []
	for instance in decoded["instances"]:
		var index: int = frame - int(instance["start"])
		if index < 0 or index >= (instance["x"] as PackedInt32Array).size():
			continue
		var member: int = instance["member"][index]
		if member < 0:
			continue
		var mode: int = instance["mode"][index]
		var scale := Vector2.ONE
		if mode & ENG_ZOOM:
			scale = Vector2(float(instance["zoom_x"][index]) / FIXED_ONE, float(instance["zoom_y"][index]) / FIXED_ONE)
		var alpha := 1.0
		if mode & ENG_MIX:
			alpha = clampf(float(instance["level"][index]) / LEVELS, 0.0, 1.0)
		var blend := "add" if mode & ENG_ADDCOLOR else ("sub" if mode & ENG_SUBCOLOR else "mix")
		sprites.append({"member": str(members[member]), "offset": Vector2(instance["x"][index], instance["y"][index]),
			"scale": scale, "alpha": alpha, "blend": blend})
	return sprites
