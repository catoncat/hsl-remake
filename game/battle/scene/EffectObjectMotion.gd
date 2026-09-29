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
##     (up to four RNG seed variants stand in for the one shared stream; a member hsl.pak lacks cycles the series'
##     existing members like the untracked player)
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
## Random programs carry seed variants (`variants`); `variant` picks one, wrapping.
static func track(object_name: String, variant: int = 0) -> Dictionary:
	var key := "%s#%d" % [object_name, variant % variants(object_name)]
	if _decoded.has(key):
		return _decoded[key]
	var row: Dictionary = packet()["objects"][object_name]
	var chosen: Dictionary = row if variant % variants(object_name) == 0 else row["variants"][variant % variants(object_name) - 1]
	var instances: Array = []
	for instance in chosen["instances"]:
		if int(instance["start"]) < 0:
			continue
		instances.append({"code": int(instance["code"]), "start": int(instance["start"]),
			"x": PackedInt32Array(instance["x"]), "y": PackedInt32Array(instance["y"]),
			"member": _expand(instance["member"]), "mode": _expand(instance["mode"]), "level": _expand(instance["level"]),
			"zoom_x": _expand(instance["zoom_x"]), "zoom_y": _expand(instance["zoom_y"]),
			"angle": _expand(instance.get("angle", []))})
	var decoded := {"motion": str(row["motion"]), "frames": int(chosen["frames"]), "instances": instances}
	_decoded[key] = decoded
	return decoded


## Seed variants of a tracked object (1 when its program draws no random numbers that matter).
static func variants(object_name: String) -> int:
	return 1 + (packet()["objects"][object_name].get("variants", []) as Array).size()


## [frame, WAV] the variant's tree played (obj_X1 at 0x415e1a, obj_Y1／obj_X2 via 0x415d40／0x415d70／0x415d90).
static func sounds(object_name: String, variant: int = 0) -> Array:
	var row: Dictionary = packet()["objects"][object_name]
	var index := variant % variants(object_name)
	return row["sounds"] if index == 0 else row["variants"][index - 1].get("sounds", row["sounds"])


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
## saturating add／subtract kinds, otherwise a plain draw. `rotation` (radians) is the turn of a
## shape the program synthesised at run time (0x460541 slots written by 0x45f141: the SHP
## rotated by angle/256 turn about its origin).
static func sprites_at(decoded: Dictionary, frame: int) -> Array:
	var members: Array = decoded.get("members", packet()["members"])
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
		var angles: PackedInt32Array = instance.get("angle", PackedInt32Array())
		var rotation := TAU * float(angles[index]) / 256.0 if index < angles.size() else 0.0
		sprites.append({"member": str(members[member]), "offset": Vector2(instance["x"][index], instance["y"][index]),
			"scale": scale, "alpha": alpha, "blend": blend, "rotation": rotation})
	return sprites


## effProcOtherBig's 0x43bf30 camera follow as the probe ran it: the battle camera relative
## to where it stood at the object's creation, at `frame` (0x46bede adds the frame's scroll
## accumulator after 0x45f5f7). Before the first row it has not moved; after the last row it
## stays — the object restores nothing. Zero for an object without `camera` rows.
static func camera_at(object_name: String, frame: int) -> Vector2:
	var offset := Vector2.ZERO
	for row in packet()["objects"].get(object_name, {}).get("camera", []):
		if int(row[0]) > frame:
			break
		offset = Vector2(int(row[1]), int(row[2]))
	return offset


## effProcIconBGSet's 0x46164b parameters at `frame`. The probe's `ripple` row is the first
## call (it deleted the object right after: [0x4c1b00] & 0x1000000 was clear). Every call passes
## phase −1 (ebp of 0x415dc0, so 0x461687 keeps accumulating the frame step) and the amplitude
## counter +0x92 before its increment, capped per change-X mode (obj_Data5 1 → 4 at 0x41d716,
## 2 → 24 at 0x41d6c4); the row step stays (0x41d708 writes +0x9e back unchanged).
## {} before the first call or for an object without `ripple` rows.
const RIPPLE_AMPLITUDE_CAP := {"obj_Effect_IconBGSet1": 4, "obj_Effect_FireBGSet": 24}


static func ripple_at(object_name: String, frame: int) -> Dictionary:
	var rows: Array = packet()["objects"].get(object_name, {}).get("ripple", [])
	if rows.is_empty() or frame < int(rows[0][0]):
		return {}
	var row: Array = rows[0]
	var calls := frame - int(row[0])
	return {"phase": (int(row[1]) + int(row[4]) * calls) & 0xff, "row_phase_step": int(row[2]), "rows_per_step": maxi(1, int(row[3])),
		"amplitude": mini(int(row[5]) + calls, int(RIPPLE_AMPLITUDE_CAP.get(object_name, int(row[5]))))}


## effProcIconBGSet's colour change (obj_Data6, change color mode: 1 → red +0xa1 = 0xff,
## 2 → blue +0xa3 = 0xff; global.obs: IconBGSet1 1, FireBGSet 1, WaterBGSet 2) as the map draws
## it at `frame`. The creation call (0x41d77c) writes [0x4c1cc0] = 0x10000000 and colour
## [0x4c1cc4] = 0 and zeroes the +0x95..+0x97 components; every later call (0x41d5b8) raises
## each by 12 capped at its +0xa1..+0xa3 target and packs them RGB565 into [0x4c1cc4]. The map
## (0x430370 → 0x46bf6f) and the stand objects (0x43d853) read both in the process pass, on
## lower planes than planeEffect2, so frame f shows call f − 1's colour: none at the creation
## frame, black the frame after. Returns the RGB565 channels (0..31, 0..63, 0..31) with alpha 1,
## or a zero Color when the object has no colour change or has not been created.
const TINT_TARGET := {"obj_Effect_IconBGSet1": [0xff, 0, 0], "obj_Effect_FireBGSet": [0xff, 0, 0], "obj_Effect_WaterBGSet": [0, 0, 0xff]}
const TINT_STEP := 12


static func tint_at(object_name: String, frame: int) -> Color:
	if not TINT_TARGET.has(object_name) or frame < 1:
		return Color(0, 0, 0, 0)
	var target: Array = TINT_TARGET[object_name]
	var calls := frame - 1
	var r := mini(TINT_STEP * calls, int(target[0]))
	var g := mini(TINT_STEP * calls, int(target[1]))
	var b := mini(TINT_STEP * calls, int(target[2]))
	return Color(float(r >> 3), float(g >> 2), float(b >> 3), 1.0)


## 0x461687's per-row x offsets for one frame (`phase` already advanced by the frame step):
## every `rows_per_step` rows the running phase adds `row_phase_step`; offset =
## sin[phase] × amplitude >> 16 (table 0x4a39fc = 65536·sin(2π i/256)); a running phase of
## exactly 64 becomes 66 (0x4616bb／0x4616e7).
static func ripple_rows(params: Dictionary, rows: int = 480) -> PackedFloat32Array:
	var offsets := PackedFloat32Array()
	offsets.resize(rows)
	var amplitude: int = params["amplitude"]
	var phase: int = int(params["phase"]) & 0xff
	if phase == 64:
		phase = 66
	var value := _ripple_offset(phase, amplitude)
	var count: int = params["rows_per_step"]
	for index in range(rows):
		count -= 1
		if count <= 0:
			count = params["rows_per_step"]
			phase = (phase + int(params["row_phase_step"])) & 0xff
			if phase == 64:
				phase = 66
			value = _ripple_offset(phase, amplitude)
		offsets[index] = value
	return offsets


static func _ripple_offset(phase: int, amplitude: int) -> int:
	return (int(roundf(FIXED_ONE * sin(TAU * float(phase) / 256.0))) * amplitude) >> 16
