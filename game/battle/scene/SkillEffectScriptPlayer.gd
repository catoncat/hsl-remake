extends "res://game/battle/scene/SkillPresenter.gd"
## Presentation-only interpreter for the EFFECTS.TXT scripts, and the default presenter of the
## combat cut-in (every skill_effects/manifest.json row declared `script`). A SPECIAL row's
## attack script (the caster's shot) then its defense script (the target's shot) becomes a
## tick timeline of sounds, inserted objects, backdrop panels and the hit／result marks the
## cut-in anchors its `released`／`impact` signals and result text to. A MAGIC row's effCode
## script becomes a timeline of objects displaced from the effect origin — drawn on the map at
## every affected position (eff_proc_Local) or once at the screen centre (eff_proc_Global) —
## after the caster's cast lead, pose and Cast_Star burst. It reads the settled strike receipt (hit, damage) and never
## decides anything: hit-only opcodes are dropped at compile time, random placements come from
## a presentation RNG seeded per clip, not the play loop's.
##
## Source of the verbs and parameter names: ANIMAL.H (`aniInsertRandomObject [code][x][y]
## [x range][y range][delay][number]`…) and effects.h (`effInsertObject [code][x disp][y disp]`,
## `effInsertRandomObject [code][x disp][y disp][x range][y range][delay range][number]`,
## `effWait`, `effPlaySound`), resource-derived. An effCode object whose effProc* program the
## native probe ran (EffectObjectMotion, effect_motion.json) plays that track — its own motion,
## shapes, blend, level and zoom and every object it spawns — from its insertion tick; the
## effInsertRandomObject placement and accumulating delays follow the interpreter 0x423873.
## A special object (defProcObjectMove) plays its objcomd.txt program's native track
## (ObjcomdMotion, objcomd_motion.json) the same way, displaced from its insertion point.
## The tick clock (60/s), the other object lifetimes (shape_number × (shape_delay + 1) ticks;
## untracked effect objects at least EFFECT_MIN_LIFETIME_TICKS then an EFFECT_FADE_TICKS alpha
## tail), flights of the special objects without a track inserted outside the 640×320 stage towards
## the target centre, the ANIMAL random／angle／round／tornado geometry and the magic impact mark (the
## script's last insertion or sound cue) are provisional remake readings recorded in
## skill_effects/manifest.json (`policy`, `replacement_evidence`); the effProc* programs listed
## unrestored are not restored; an object's own sounds are — a
## special object's objcomd.txt command sounds and an effect object's obj_X1／obj_Y1／obj_X2 WAVs.
## provenance:
##   layout: static-derived content/generated/hsl/skills/effect_motion.json
##   layout: static-derived content/generated/hsl/skills/objcomd_motion.json
##   layout: resource-derived content/imported/hsl/shared/skill_effects/manifest.json
##   layout: resource-derived content/imported/hsl/global/tables/ANIMAL.H
##   layout: resource-derived content/imported/hsl/global/tables/effects.h
##   layout: resource-derived content/imported/hsl/shared/mage_magic/manifest.json
##   layout: static-derived docs/evidence_packets/static_reverse/animal_program_execution.md#8-施法引导程序m_actions_action的解释
##   layout: static-derived docs/evidence_packets/static_reverse/original_cast_overlays.md#施法引导的合成
##   layout: provisional
##     (ANIMAL random／angle／round／tornado geometry, off-stage flights, static hold of the objects effect_motion.json
##     lists unrestored, eff_proc_Global at screen centre — manifest policy)
##   layout: static-derived docs/evidence_packets/runtime_observations/cutin_floaters/README.md
##   strings: resource-derived content/generated/hsl/skills/special_effect_scripts.json
##   strings: remake-invented content/generated/hsl/skills/authored_effect_scripts.json
##     (the authored skills' names and scripts, sequel content from content/authored/roles/skills.json)
##   timing: resource-derived content/generated/hsl/skills/special_effect_scripts.json
##   timing: static-derived content/generated/hsl/skills/effect_motion.json
##   timing: static-derived docs/evidence_packets/static_reverse/original_effect_motion.md
##   timing: static-derived docs/evidence_packets/runtime_observations/original_tick_rate/README.md
##   timing: resource-derived content/imported/hsl/chapter01/combat_animation/manifest.json
##   timing: provisional
##     (lifetime = shape_number × (shape_delay＋1); untracked objects' lifetime／fade; impact at the last cue;
##     EMPTY_ATTACK_LEAD_TICKS stands in; effProc* motion not restored)
##   audio: resource-derived content/imported/hsl/shared/skill_effects/manifest.json
##   audio: static-derived docs/evidence_packets/static_reverse/original_effect_object_sounds.md
##   audio: provisional
##     (a command sound behind a motion wait counted at zero wait; effect-program cues behind unrun motion —
##     program_sounds timing provisional; SOUND_VOICES)
##   audio: resource-derived content/imported/hsl/shared/interface_audio/manifest.json
const Timing = preload("res://game/battle/runtime/CombatPresentationTiming.gd")
const ResultNumberFloater = preload("res://game/battle/scene/ResultNumberFloater.gd")
const ContentPaths = preload("res://game/sim/ContentPaths.gd")
const MANIFEST_PATH := ContentPaths.SKILL_EFFECTS
const SCRIPTS_PATH := "res://content/generated/hsl/skills/special_effect_scripts.json"
## The authored skills' rows (content/authored/roles/skills.json via hsltools/data/authored_skills.py):
## same row shape, each declaring its own `presentation` — the imported manifest has no row for them.
const AUTHORED_SCRIPTS_PATH := "res://content/generated/hsl/skills/authored_effect_scripts.json"
const CASTING_PATH := ContentPaths.MAGE_MAGIC
const OriginalTick = preload("res://game/common/OriginalTick.gd")
const AnimalCastLead = preload("res://game/battle/scene/AnimalCastLead.gd")
const CutinLayout = preload("res://game/battle/runtime/CutinLayout.gd")
const EffectObjectMotion = preload("res://game/battle/scene/EffectObjectMotion.gd")
const ObjcomdMotion = preload("res://game/battle/scene/ObjcomdMotion.gd")
const TICKS_PER_SECOND := OriginalTick.TICKS_PER_SECOND
const STAGE_SIZE := Vector2(640, 320)
const TARGET_CENTRE := Vector2(320, 160)
## A row whose attack script is empty still shows the caster's cast panels for this lead.
const EMPTY_ATTACK_LEAD_TICKS := 30
## Ticks the result stays up after aniShowHitResult at the least (a remake floor that keeps a
## caption-only receipt readable); the clip itself runs until the result numbers are deleted
## (clip_complete_tick).
const RESULT_HOLD_TICKS := 40
## Flight time of an off-stage object when no aniProcessHitMiss follows in its phase.
const FLIGHT_TICKS := 30
## An untracked effCode object (its effProc* program stopped at an unreviewed callee in the
## native probe — effect_motion.json `unrestored`) stays at least this long and no longer than
## the script's remaining waits, then fades over EFFECT_FADE_TICKS.
const EFFECT_MIN_LIFETIME_TICKS := 48
const EFFECT_FADE_TICKS := 24
const ANGLE_SPEED := 6.0
const ANGLE_LIFETIME_TICKS := 30
const TORNADO_LIFETIME_TICKS := 60
## Tornado spin per tick in turns (4/256 of a circle, the angle unit the scripts use).
const TORNADO_SPIN := 4.0 / 256.0
## The same spelling as skill_effects/manifest.json `implemented_opcodes` (checked in tests).
const IMPLEMENTED_OPCODES := ["aniDelay", "aniPlaySound", "aniInsertObject", "aniInsertRandomObject", "aniInsertRandomObjectFixDelay",
	"aniProcessHitMiss", "aniShowHitResult", "aniInsertRandomObjectDelay", "aniPlayHitSound",
	"aniInsertHitRandomObject", "aniInsertSpecialBG", "aniDoublePageMode", "aniInsertHitRandomObjectFixDelay",
	"aniProcessHitMissMulti", "aniInsertAngleObject", "aniInsertDistanceObjectFixDelay",
	"aniInsertHitRandomObjectDisp", "aniShowHitResultNoWait", "aniNoSpecialDarkBG", "aniInsertRoundRandomObject",
	"aniInsertTornadoObject", "aniShowAttacker", "aniInsertAngleObjectMakeShape", "aniSetXYDisp",
	"effWait", "effInsertObject", "effInsertRandomObject", "effPlaySound"]
const PLANE_Z := {"planeEffect2": 0, "planeEffect3": 1, "planeEffect4": 2}
var manifest: Dictionary
var scripts: Dictionary
var casting: Array
var sprites: Array[Sprite2D] = []
var sounds: Array[AudioStreamPlayer] = []
## Voices the timeline's cues rotate through, the oldest cut first (remake mixing: every
## object instance sounds its own command cue — 百裂突刺's 26 thrusts — and the native
## mixer's channel count is not read).
const SOUND_VOICES := 8
var next_sound := 0
var textures: Dictionary = {}
var materials: Dictionary = {}
## Track members hsl.pak lacks → the series member drawn instead (`_native_member`).
var series_members: Dictionary = {}


func _ready() -> void:
	manifest = ContentPaths.read_json(MANIFEST_PATH)
	scripts = ContentPaths.read_json(SCRIPTS_PATH)["rows"]
	scripts.merge(ContentPaths.read_json(AUTHORED_SCRIPTS_PATH)["rows"])
	casting = ContentPaths.read_json(CASTING_PATH)["casting"]["frames"]
	for _index in range(SOUND_VOICES):
		var player := AudioStreamPlayer.new()
		add_child(player)
		sounds.append(player)
	# Remake compositing: the SP*.SHP light effects carry black RGB padding, so additive
	# blending is the default; global.obs obj_Mode names the exceptions.
	for mode in ["", "engADDCOLOR_MIX", "engSUBCOLOR_MIX", "engMIX", "0", "engZOOM"]:
		var material := CanvasItemMaterial.new()
		material.blend_mode = CanvasItemMaterial.BLEND_MODE_SUB if mode == "engSUBCOLOR_MIX" else (CanvasItemMaterial.BLEND_MODE_MIX if mode == "engMIX" else CanvasItemMaterial.BLEND_MODE_ADD)
		materials[mode] = material
	# The native tracks' blend kinds (EffectObjectMotion.sprites_at).
	for blend in ["add", "sub", "mix"]:
		var material := CanvasItemMaterial.new()
		material.blend_mode = {"add": CanvasItemMaterial.BLEND_MODE_ADD, "sub": CanvasItemMaterial.BLEND_MODE_SUB, "mix": CanvasItemMaterial.BLEND_MODE_MIX}[blend]
		materials[blend] = material
	hide()


## `script` when the row plays through this interpreter, `dedicated_module` for rows with
## their own restored presentation, `borrowed_qi_blade` when an opcode is not implemented,
## "" for an id neither the manifest nor an authored row declares (synthetic clips without a
## skill_id). An authored row carries its own `presentation` (always `script`).
func presentation(skill_id: String) -> String:
	return str(manifest["rows"].get(skill_id, scripts.get(skill_id, {})).get("presentation", ""))


## `special` (specCode attack／defense cut-in) or `magic` (effCode map effect); "" when unknown.
func channel(skill_id: String) -> String:
	return str(scripts.get(skill_id, {}).get("channel", ""))


func matches(strike: Dictionary) -> bool:
	return presentation(str(strike.get("skill_id", ""))) == "script"


## Neither channel needs the actors' combat art: magic scripts draw on the map, and a special
## cut-in whose caster or target is outside the scene's combat-animation packet (029; authored
## 102／103 under a chapter-01 table) still plays its backdrop, objects and sounds with that
## actor's close-up left out (`_stand`), instead of the text-only missing-art clip.
func needs_actor_art(_strike: Dictionary) -> bool:
	return false


## Stands `row`'s combat frame on `sprite` (mirrored for a side-swapped actor: the special's
## attacker 0x401c20 and defender 0x4038a0 objects read 0x446be0 at init like the ordinary
## shot's); hides the sprite and returns false when the combat manifest has no such row.
static func _stand(host: CanvasLayer, sprite: Sprite2D, row: String, frame: int, unit: Dictionary) -> bool:
	if not host.manifest["actors"].has(row):
		sprite.hide()
		return false
	host._set_frame(sprite, row, frame, CutinLayout.side_swapped(unit))
	return true


func texture(member: String) -> Texture2D:
	if not textures.has(member):
		textures[member] = load(manifest["frames"][member]["res_path"])
	return textures[member]


## Comma-separated action lines → instructions in order; an `ani*`／`eff*` verb token opens
## an instruction, the tokens up to the next one are its arguments.
static func parse(lines: Array) -> Array[Dictionary]:
	var instructions: Array[Dictionary] = []
	for line in lines:
		for token in str(line).split(","):
			var text := str(token).strip_edges()
			if text.begins_with("ani") or text.begins_with("eff"):
				instructions.append({"op": text, "args": []})
			elif not instructions.is_empty():
				instructions.back()["args"].append(text)
	return instructions


static func number(token: String) -> int:
	var text := token.strip_edges()
	var sign := 1
	if text.begins_with("-"):
		sign = -1
		text = text.substr(1)
	if text.begins_with("0x") or text.begins_with("0X"):
		return sign * text.hex_to_int()
	return sign * int(text)


static func fixed16(token: String) -> float:
	return float(number(token)) / 65536.0


func compile_row(skill_id: String, hit: bool, seed: int) -> Dictionary:
	var row: Dictionary = scripts[skill_id]
	if str(row["channel"]) == "magic":
		return compile_effect(row["actions"][row["effect_code"]], seed, manifest, row)
	return compile(row["actions"][row["attack_code"]], row["actions"][row["defense_code"]], hit, seed, manifest)


## The tick timeline of one attack script followed by one defense script. Pure: the same
## inputs and seed give the same events; nothing is drawn or played here.
static func compile(attack_lines: Array, defense_lines: Array, hit: bool, seed: int, data: Dictionary) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var timeline := {"kind": "special", "events": [], "release_tick": 0, "impact_tick": -1, "result_tick": -1, "complete_tick": 0,
		"hit": hit, "sound_cues": [],
		"hit_ticks": [], "result_ticks": [], "attack_background": "", "defense_background": "",
		"double_page_tick": -1, "no_dark_bg": false, "show_attacker": false, "xy_disp": Vector2.ZERO, "empty_attack": false,
		"unimplemented": [], "skipped_objects": [], "instructions": 0}
	var cursor := 0
	for phase in ["attack", "defense"]:
		var instructions := parse(attack_lines if phase == "attack" else defense_lines)
		timeline["instructions"] += instructions.size()
		if phase == "attack" and instructions.is_empty():
			cursor = EMPTY_ATTACK_LEAD_TICKS
			timeline["release_tick"] = cursor
			timeline["empty_attack"] = true
			continue
		for instruction in instructions:
			var op: String = instruction["op"]
			var args: Array = instruction["args"]
			cursor = _compile_instruction(timeline, data, rng, phase, hit, cursor, op, args)
		if phase == "attack":
			timeline["release_tick"] = cursor
	_finish_timeline(timeline, cursor)
	return timeline


## One special-script instruction at tick `cursor` into `timeline`; returns the next cursor.
static func _compile_instruction(timeline: Dictionary, data: Dictionary, rng: RandomNumberGenerator, phase: String, hit: bool, cursor: int, op: String, args: Array) -> int:
	if _insert_pattern(timeline, data, phase, op, args, cursor): return cursor
	match op:
		"aniDelay":
			cursor += number(args[0])
		"aniPlaySound", "aniPlayHitSound":
			if hit or op == "aniPlaySound":
				timeline["events"].append({"tick": cursor, "kind": "sound", "member": str(args[0]), "phase": phase})
		"aniInsertObject":
			_insert(timeline, data, phase, str(args[0]), Vector2(number(args[1]), number(args[2])), cursor)
		"aniInsertRandomObject", "aniInsertHitRandomObject":
			if hit or op == "aniInsertRandomObject":
				_insert_spawner(timeline, data, rng, phase, args, Vector2(number(args[1]), number(args[2])), cursor)
		"aniInsertHitRandomObjectDisp":
			if hit:
				_insert_spawner(timeline, data, rng, phase, args, TARGET_CENTRE + Vector2(number(args[1]), number(args[2])), cursor)
		"aniInsertRandomObjectDelay":
			_insert_random(timeline, data, rng, phase, args, Vector2(number(args[1]), number(args[2])), cursor, number(args[5]), number(args[6]), false, number(args[7]))
		"aniInsertRandomObjectFixDelay", "aniInsertHitRandomObjectFixDelay":
			if hit or op == "aniInsertRandomObjectFixDelay":
				_insert_random(timeline, data, rng, phase, args, Vector2(number(args[1]), number(args[2])), cursor, number(args[5]), number(args[6]), true, number(args[7]))
		"aniInsertSpecialBG":
			timeline[phase + "_background"] = str(args[0])
		"aniProcessHitMiss", "aniProcessHitMissMulti":
			timeline["hit_ticks"].append(cursor)
		"aniShowHitResult", "aniShowHitResultNoWait":
			timeline["result_ticks"].append(cursor)
		"aniDoublePageMode":
			if int(timeline["double_page_tick"]) < 0:
				timeline["double_page_tick"] = cursor
		"aniNoSpecialDarkBG":
			timeline["no_dark_bg"] = true
		"aniShowAttacker":
			timeline["show_attacker"] = true
		"aniSetXYDisp":
			timeline["xy_disp"] = Vector2(number(args[0]), number(args[1]))
		_:
			if not timeline["unimplemented"].has(op):
				timeline["unimplemented"].append(op)
	return cursor


## The patterned multi-object inserts (line, ring, oval, tornado); false for any other op.
static func _insert_pattern(timeline: Dictionary, data: Dictionary, phase: String, op: String, args: Array, cursor: int) -> bool:
	match op:
		"aniInsertDistanceObjectFixDelay":
			var step := Vector2(number(args[3]), number(args[4]))
			for index in range(number(args[7])):
				_insert(timeline, data, phase, str(args[0]), Vector2(number(args[1]), number(args[2])) + step * index, cursor + number(args[5]) + number(args[6]) * index)
		"aniInsertAngleObject", "aniInsertAngleObjectMakeShape":
			var count := number(args[3])
			for index in range(count):
				var angle := TAU * index / float(maxi(count, 1))
				var event := _insert(timeline, data, phase, str(args[0]), Vector2(number(args[1]), number(args[2])), cursor + number(args[4]) + number(args[5]) * index)
				if event.is_empty(): continue
				event["motion"] = "radial"
				event["direction"] = Vector2(cos(angle), sin(angle))
				event["expire"] = event["tick"] + maxi(event["expire"] - event["tick"], ANGLE_LIFETIME_TICKS)
				if op == "aniInsertAngleObject" and event["frames"].size() >= count:
					event["fixed_frame"] = index
				else:
					event["rotation"] = angle
		"aniInsertRoundRandomObject":
			var radius := fixed16(args[3])
			var radii := Vector2(radius / float(1 << number(args[4])), radius / float(1 << number(args[5])))
			var count := number(args[8])
			for index in range(count):
				var angle := TAU * (number(args[7]) / 256.0 + index / float(maxi(count, 1)))
				_insert(timeline, data, phase, str(args[0]), Vector2(number(args[1]), number(args[2])) + Vector2(cos(angle) * radii.x, sin(angle) * radii.y), cursor + number(args[6]) * index)
		"aniInsertTornadoObject":
			for index in range(number(args[10])):
				var centre := Vector2(number(args[1]), number(args[2]) + number(args[3]) * index)
				var event := _insert(timeline, data, phase, str(args[0]), centre, cursor)
				if event.is_empty(): continue
				event["motion"] = "spin"
				event["centre"] = centre
				event["radius"] = fixed16(args[4]) + fixed16(args[5]) * index
				event["angle"] = (number(args[6]) + number(args[7]) * index) / 256.0
				event["zoom"] = maxf(0.05, fixed16(args[8]) + fixed16(args[9]) * index)
				event["expire"] = event["tick"] + maxi(event["expire"] - event["tick"], TORNADO_LIFETIME_TICKS)
		_:
			return false
	return true


## Impact／result marks, flight arrivals and the completion tick of a compiled special timeline.
static func _finish_timeline(timeline: Dictionary, cursor: int) -> void:
	timeline["impact_tick"] = int(timeline["hit_ticks"][0]) if not timeline["hit_ticks"].is_empty() else int(timeline["release_tick"])
	timeline["result_tick"] = int(timeline["result_ticks"][0]) if not timeline["result_ticks"].is_empty() else int(timeline["impact_tick"])
	# A defProcObjectMove object with a native track (objcomd_motion.json) runs its objcomd.txt
	# program: frame f of the track shows at insertion tick + f, displaced from the insertion
	# point; repeated insertions of one object cycle its seed variants. Open-ended programs
	# (objmOver holds, endless loops) last until the clip ends, the scene teardown that
	# 0x4051d0 obeys (0x4c1404 bit 0). The patterned inserts (angle rings, tornado columns)
	# write per-instance angle／radius fields the track does not carry and keep their geometry.
	var native_order := {}
	for event in timeline["events"]:
		if event["kind"] != "object" or not ObjcomdMotion.tracked(str(event["object"])): continue
		if str(event["motion"]) in ["radial", "spin"]: continue
		var name := str(event["object"])
		var order: int = native_order.get(name, 0)
		native_order[name] = order + 1
		event["motion"] = "native"
		event["source"] = "objcomd"
		event["variant"] = order % ObjcomdMotion.variants(name)
		event["anchored"] = false
		event["open_ended"] = ObjcomdMotion.open_ended(name)
		event["expire"] = int(event["tick"]) + ObjcomdMotion.frames(name)
	# Remaining off-stage objects fly to the target centre, arriving at the phase's next hit mark
	# or after FLIGHT_TICKS (remake composition).
	for event in timeline["events"]:
		if event.get("motion", "") != "fly": continue
		var arrive: int = event["tick"] + FLIGHT_TICKS
		if event["phase"] == "defense":
			for mark in timeline["hit_ticks"]:
				if int(mark) > int(event["tick"]):
					arrive = int(mark)
					break
		event["arrive"] = arrive
		event["expire"] = arrive + event["frames"].size() * int(event["frame_ticks"])
	# The clip ends when the script and the readable result are done; object lifetimes do not
	# hold it. The defense script's aniOver (0x403d3d) goes straight to phase 101 (0x403d7a),
	# whose close (0x404ada) sets the teardown bit 0x4c1404 |= 1, and every cutin effect object
	# (slots 36–38: 0x404ffa, 0x4050a0, 0x4051d0) deletes itself on that bit — no liveness
	# check. Objects still running then are cut at the end. Remake reading: a random-delay
	# insert (0x401390) landing after the script's end still appears and sounds its insertion
	# cues, so a seed never changes which objects and cues play.
	var complete := maxi(cursor, int(timeline["result_tick"]) + RESULT_HOLD_TICKS)
	for event in timeline["events"]:
		complete = maxi(complete, int(event["tick"]) + (1 if event["kind"] == "object" else 0))
	for event in timeline["events"]:
		if event["kind"] == "object" and (event.get("open_ended", false) or int(event["expire"]) > complete):
			event["expire"] = complete
	timeline["complete_tick"] = complete
	timeline.erase("sound_cues")


## The tick timeline of one MAGIC effCode script. Object positions are displacements from
## the effect origin (the drawer adds the target position); the impact mark is the script's
## last cue — its last object insertion or sound — every object holds for
## clamp(lifetime, EFFECT_MIN_LIFETIME_TICKS, the script's remaining waits) then fades, and
## the clip completes when the script's waits and every fade are over. Pure like `compile`.
static func compile_effect(lines: Array, seed: int, data: Dictionary, row: Dictionary) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var timeline := {"kind": "effect", "events": [], "impact_tick": 0, "complete_tick": 0, "hit": true, "sound_cues": [],
		"global": str(row.get("effect_proc", "")) == "eff_proc_Global", "dim": str(row.get("damage_policy", "")) == "native_magic_damage",
		"unimplemented": [], "skipped_objects": [], "instructions": 0}
	var instructions := parse(lines)
	timeline["instructions"] = instructions.size()
	var cursor := 0
	var last_cue := 0
	for instruction in instructions:
		var op: String = instruction["op"]
		var args: Array = instruction["args"]
		match op:
			"effWait":
				cursor += number(args[0])
			"effPlaySound":
				timeline["events"].append({"tick": cursor, "kind": "sound", "member": str(args[0]), "phase": "effect"})
				last_cue = cursor
			"effInsertObject":
				_insert(timeline, data, "effect", str(args[0]), Vector2(number(args[1]), number(args[2])), cursor, cursor)
				last_cue = cursor
			"effInsertRandomObject":
				_insert_effect_random(timeline, data, rng, args, cursor)
				last_cue = cursor
			_:
				if not timeline["unimplemented"].has(op):
					timeline["unimplemented"].append(op)
	timeline["impact_tick"] = last_cue
	var complete := cursor
	for event in timeline["events"]:
		if event["kind"] == "object":
			if EffectObjectMotion.tracked(str(event["object"])):
				# The native tree: frame f of the track shows at insertion tick + f, until its
				# last instance is gone; an anchored program drives itself from the origin.
				var native: Dictionary = EffectObjectMotion.track(str(event["object"]))
				event["motion"] = "native"
				event["anchored"] = str(native["motion"]) == "anchored"
				event["expire"] = int(event["tick"]) + int(native["frames"])
			else:
				var hold: int = clampi(int(event["lifetime"]), EFFECT_MIN_LIFETIME_TICKS, maxi(EFFECT_MIN_LIFETIME_TICKS, cursor - int(event["tick"])))
				event["fade_tick"] = int(event["tick"]) + hold
				event["expire"] = int(event["fade_tick"]) + EFFECT_FADE_TICKS
		complete = maxi(complete, int(event.get("expire", event["tick"])))
	timeline["complete_tick"] = complete
	timeline.erase("sound_cues")
	return timeline


## effInsertRandomObject [code][x disp][y disp][x range][y range][delay range][number] as the
## effect interpreter reads it (0x423873..0x42397a): each object at the displacement plus
## rand(range) folded into (−range/2, range/2] (a zero range reads as 1, 0x4238b5／0x4238e1);
## the first at once, every next one rand(delay range) ticks after the previous — the +0xae
## delay accumulates (0x423951). The draws come from the clip's presentation RNG.
static func _insert_effect_random(timeline: Dictionary, data: Dictionary, rng: RandomNumberGenerator, args: Array, cursor: int) -> void:
	var centre := Vector2(number(args[1]), number(args[2]))
	var wait := 0
	for _index in range(number(args[6])):
		var offset := Vector2(_fold(rng, number(args[3])), _fold(rng, number(args[4])))
		_insert(timeline, data, "effect", str(args[0]), centre + offset, cursor + wait, cursor)
		wait += _rand(rng, number(args[5]))


## 0x458c80 rand(n): 0..n−1, 0 for n ≤ 0.
static func _rand(rng: RandomNumberGenerator, n: int) -> int:
	return 0 if n <= 0 else rng.randi_range(0, n - 1)


## A rand(range) offset folded the interpreter's way: values above range/2 map to
## range/2 − value.
static func _fold(rng: RandomNumberGenerator, span: int) -> int:
	var width := maxi(span, 1)
	var value := _rand(rng, width)
	var half := int(width / 2)
	return half - value if value > half else value


## aniInsertRandomObject／aniInsertHitRandomObject／aniInsertHitRandomObjectDisp [code][x][y]
## [x range][y range][delay][number] as the ANIMAL interpreter runs them (ops 19／27／28 →
## 0x403c2b → spawner 0x401390 with base delay 0): each object at the point plus rand(range)
## folded into (−range/2, range/2] (x then y), the first at once and every next one
## rand(delay) + 1 ticks after the previous (+0xae accumulates, 0x401455) — 月花圓舞's 64 petals
## fall over about 220 ticks, not in one burst. The draws come from the clip's presentation RNG.
static func _insert_spawner(timeline: Dictionary, data: Dictionary, rng: RandomNumberGenerator, phase: String, args: Array, centre: Vector2, cursor: int) -> void:
	var wait := 0
	for _index in range(number(args[6])):
		var offset := Vector2(_fold(rng, number(args[3])), _fold(rng, number(args[4])))
		_insert(timeline, data, phase, str(args[0]), centre + offset, cursor + wait, cursor)
		wait += _rand(rng, number(args[5])) + 1


static func _insert_random(timeline: Dictionary, data: Dictionary, rng: RandomNumberGenerator, phase: String, args: Array, centre: Vector2, cursor: int, base_delay: int, delay: int, fixed_delay: bool, count: int) -> void:
	var spread := Vector2(number(args[3]), number(args[4]))
	for index in range(count):
		var offset := Vector2(rng.randf_range(-spread.x / 2.0, spread.x / 2.0), rng.randf_range(-spread.y / 2.0, spread.y / 2.0)).round()
		var wait := base_delay + (delay * index if fixed_delay else rng.randi_range(0, maxi(delay, 0)))
		_insert(timeline, data, phase, str(args[0]), centre + offset, cursor + wait, cursor)


## One object insertion; {} (and a `skipped_objects` entry) for an object the manifest cannot
## draw — obj_Special51_05 has no OBJ-ALL.H definition (scope `unresolved_objects`). In the
## `effect` phase the position is a displacement and the object's hold and fade are settled by
## compile_effect once the script's length is known. The object's own sounds are scheduled
## first (`_insert_sounds`), so an object whose frames cannot be drawn still sounds.
static func _insert(timeline: Dictionary, data: Dictionary, phase: String, object_name: String, position: Vector2, tick: int, sound_tick: int = -1) -> Dictionary:
	var object: Dictionary = data["objects"].get(object_name, {})
	_insert_sounds(timeline, data, phase, object, tick, sound_tick)
	var frames: Array = []
	for member in object.get("shape_members", []):
		if data["frames"].has(member):
			frames.append(member)
	if frames.is_empty():
		if not timeline["skipped_objects"].has(object_name):
			timeline["skipped_objects"].append(object_name)
		return {}
	var frame_ticks := int(object["frame_ticks"])
	var on_stage := phase == "effect" or (position.x >= 0 and position.x <= STAGE_SIZE.x and position.y >= 0 and position.y <= STAGE_SIZE.y)
	var lifetime := frames.size() * frame_ticks
	var zoom: Array = object.get("zoom", [1.0, 1.0])
	var event := {"tick": tick, "kind": "object", "phase": phase, "object": object_name, "frames": frames, "frame_ticks": frame_ticks,
		"lifetime": lifetime, "position": position, "expire": tick + lifetime, "motion": "static" if on_stage else "fly",
		"fixed_frame": -1, "rotation": 0.0, "zoom": 1.0, "scale": Vector2(float(zoom[0]), float(zoom[1])),
		"z": int(PLANE_Z.get(str(object["plane"]), 2)), "mode": str(object.get("mode", "")),
		"order": timeline["events"].size()}
	timeline["events"].append(event)
	return event


## The sounds an inserted object makes by itself:
## - an effect object's obj_X1 WAV (defProcEffectProcess1 plays template +0x10 as the object
##   starts, 0x415e1a) once per instruction, at `sound_tick` (the instruction's cursor), and its
##   obj_Y1／obj_X2 WAVs (manifest `program_sounds`: its effProc* program plays +0x44／+0x46 at
##   its own events — 0x415d40／0x415d70／0x415d90) at its start plus the statically read delay,
##   one cue per WAV and tick — 烈蝕水彈's water ball fires SHOOT002 then bursts WATER008;
## - a special object's objcomd.txt command sounds (manifest `command_sounds`; its obj_Data7
##   program runs from the object's insertion): objmPlaySound (0x4059b7) always and
##   objmPlayHitSound (0x4059cf, hit roll under the hit rate) only on a hit, once per
##   instance at its own tick plus the objmDelay ticks ahead of it, as each object's program
##   calls the sound wrapper itself — 氣刃斬's impact bursts obj_Special01_03 (command 2) play
##   WAV\BOMB0017.WAV as they appear, 百裂突刺's thrusts one ATTACK17 swish each.
static func _insert_sounds(timeline: Dictionary, data: Dictionary, phase: String, object: Dictionary, tick: int, sound_tick: int) -> void:
	var cues: Array = []
	if phase == "effect" and str(object.get("insert_sound", "")) != "":
		var key := str(object["insert_sound"]) + "@" + str(sound_tick)
		if not timeline["sound_cues"].has(key):
			timeline["sound_cues"].append(key)
			cues.append({"member": str(object["insert_sound"]), "tick": sound_tick})
	if phase == "effect":
		for sound in object.get("program_sounds", []):
			var at := tick + int(sound["delay_ticks"])
			var key := str(sound["member"]) + "@" + str(at)
			if not timeline["sound_cues"].has(key):
				timeline["sound_cues"].append(key)
				cues.append({"member": str(sound["member"]), "tick": at})
	for sound in object.get("command_sounds", []):
		if bool(sound["hit_only"]) and not bool(timeline["hit"]):
			continue
		cues.append({"member": str(sound["member"]), "tick": tick + int(sound["delay_ticks"])})
	for cue in cues:
		if not data["sounds"].has(cue["member"]):
			push_error("skill_effects manifest has no sound " + str(cue["member"]))
			continue
		timeline["events"].append({"tick": int(cue["tick"]), "kind": "sound", "member": str(cue["member"]), "phase": phase})


## Presenter entry: compiles the row's timeline once per clip (seeded from the receipt, never
## the play loop's RNG), then drives the special cut-in or the map effect.
func present(host: CanvasLayer, clip: Dictionary, elapsed: float) -> bool:
	if not clip.has("effect_timeline"):
		var strike: Dictionary = clip["strike"]
		var skill_id := str(strike.get("skill_id", ""))
		var seed := hash(skill_id + str(strike.get("attacker_id", "")) + str(strike.get("defender_id", "")) + str(strike.get("hit_roll", strike.get("native_damage_roll", ""))))
		clip["effect_timeline"] = compile_row(skill_id, bool(strike["hit"]), seed)
	if str(clip["effect_timeline"]["kind"]) == "effect":
		return _present_effect(host, clip, elapsed)
	return _present_special(host, clip, elapsed)


## The special timeline drives the shot. First the caster's ANIMAL s_action cast lead
## (AnimalCastLead through the host — the banner, insets and portrait over the shadowed map)
## when the caster has an imported strip; then the attack phase (the standing caster on
## aniShowAttacker or when there is no lead, over the aniInsertSpecialBG panel or the
## backdrop), then the defense phase (target over the darkened backdrop unless
## aniNoSpecialDarkBG; both actors side by side from aniDoublePageMode). `released` fires
## at the phase change, `impact` at the first aniProcessHitMiss, the result text at
## aniShowHitResult; the clip completes when the script ends and the result has been
## readable for RESULT_HOLD_TICKS. A lead replaces the EMPTY_ATTACK_LEAD_TICKS stand-in of
## an empty attack script. The script clock runs in real seconds (the host's
## Timing.PLAYBACK_SPEED is undone), 62.5 ticks/s.
func _present_special(host: CanvasLayer, clip: Dictionary, elapsed: float) -> bool:
	var timeline: Dictionary = clip["effect_timeline"]
	var seconds: float = elapsed / Timing.PLAYBACK_SPEED
	var tick := seconds * TICKS_PER_SECOND
	var hit: bool = clip["strike"]["hit"]
	host.blade.hide()
	host.flash_sprite.hide()
	var lead: Dictionary = host.cast_lead(clip)
	var lead_ticks := int(lead.get("complete_tick", 0))
	# No name caption over the lead or the script: the original captions a skill only while
	# its range is drawn (BattleAttackCue.caption). The result line appears at aniShowHitResult.
	host.result.visible = false
	host.result.position.y = 264
	host.result.text = ""
	if tick < float(lead_ticks):
		host.show_cast_lead(clip, lead, tick)
		clear()
		return false
	# The script's own clock: after the lead; an empty attack script yields at once.
	var script_tick := tick - float(lead_ticks) + (float(EMPTY_ATTACK_LEAD_TICKS) if lead_ticks > 0 and bool(timeline["empty_attack"]) else 0.0)
	var attack_phase := script_tick < float(timeline["release_tick"])
	if not attack_phase and not clip["release_emitted"]:
		clip["release_emitted"] = true
		host.released.emit(clip["strike"], clip["attacker_unit"], clip["defender_unit"], false)
	if script_tick >= float(timeline["impact_tick"]) and not clip["impact_emitted"]:
		clip["impact_emitted"] = true
		host.impact.emit(clip["strike"], clip["attacker_unit"], clip["defender_unit"], false)
	host._show_shot(clip, not attack_phase)
	var backdrop := str(timeline["attack_background" if attack_phase else "defense_background"])
	if backdrop != "":
		host.scenery.texture = texture(backdrop)
	else:
		host.scenery.texture = load(host.manifest["background"]["res_path"])
		if not attack_phase and not bool(timeline["no_dark_bg"]):
			host.scenery.modulate = Color(0.45, 0.45, 0.5)
	if attack_phase:
		if lead_ticks == 0 or bool(timeline["show_attacker"]):
			_stand(host, host.attacker_sprite, clip["attacker"], 0, clip["attacker_unit"])
			host.attacker_sprite.position = CutinLayout.attacker_anchor()
		else:
			# The cast object has ended (phase 101); the attack script owns the shot.
			host.attacker_sprite.hide()
		host.defender_sprite.hide()
	else:
		var double_page := int(timeline["double_page_tick"]) >= 0 and script_tick >= float(timeline["double_page_tick"])
		# 0x4038a0 has no return to neutral: the hurt pose holds until the shot ends.
		var hurt: bool = hit and bool(clip["impact_emitted"])
		var hurt_frame: int = int(host.manifest["actors"].get(clip["defender"], {}).get("hurt_frame", 0))
		_stand(host, host.defender_sprite, clip["defender"], hurt_frame if hurt else 0, clip["defender_unit"])
		host.defender_sprite.position = (Vector2(480, CutinLayout.SHOT_ANCHOR.y) if double_page else host.defender_anchor(clip)) + timeline["xy_disp"]
		# The same defender object 0x4038a0: knock-back on a hit, dodge slide on a miss, from the roll.
		var defender_row: Dictionary = host.manifest.get("actors", {}).get(clip["defender"], {})
		if clip["impact_emitted"] and not defender_row.is_empty():
			host.defender_sprite.position.x += CutinLayout.reaction_x(defender_row, hit, script_tick - float(timeline["impact_tick"]), CutinLayout.side_swapped(clip["defender_unit"]))
		host.defender_sprite.modulate = Color.WHITE
		if double_page and _stand(host, host.attacker_sprite, clip["attacker"], 0, clip["attacker_unit"]):
			host.attacker_sprite.position = Vector2(160, CutinLayout.SHOT_ANCHOR.y)
			host.attacker_sprite.show()
	draw(clip, script_tick / TICKS_PER_SECOND, [Vector2.ZERO])
	var shown := script_tick >= float(timeline["result_tick"])
	host.result.visible = shown
	if shown:
		host.show_result(clip["strike"], script_tick - float(timeline["result_tick"]))
	if script_tick >= float(clip_complete_tick(timeline, host.result_spawns(clip["strike"]))):
		clear()
		return true
	return false


## The tick the special shot ends: the compiled timeline's end, and not before the numbers
## aniShowHitResult spawned are deleted. 0x404643 (opcode 30, [esp+0x14] = 1) spawns the last
## number with the defender object as waiter and leaves its phase at 0x62 (0x403ecc) until that
## number releases it (+0x28 < 9, 0x408580) — for a red kind-0 number 27 ＋ 10×digits ticks —
## and the number lives on to 34 ＋ 10×digits (two digits: 47 and 54) while the shot closes. The
## remake has no closing transition on this path, so it keeps the shot up until the last
## number's deletion (ResultNumberFloater.life_of) instead of cutting the fade at
## RESULT_HOLD_TICKS.
## `spawns` are the shot's result numbers (BattleCombatCutin.result_spawns).
static func clip_complete_tick(timeline: Dictionary, spawns: Array) -> int:
	var complete := int(timeline["complete_tick"])
	for entry in spawns:
		var digits := 1 if str(entry["kind"]) == "miss" else str(absi(int(entry["value"]))).length()
		complete = maxi(complete, int(timeline["result_tick"]) + ResultNumberFloater.life_of(str(entry["kind"]), digits, int(entry.get("hold", 0))))
	return complete


## A MAGIC script on the tactical map (MAGIC.TXT eff_proc_Local): no backdrop or close-up
## actors; the cast lead's shadow darkens the map (level 8／16 through the effect). First the caster's ANIMAL m_action cast
## lead (AnimalCastLead through the host, `cast_lead(clip, "magic")` — banner, insets and
## portrait from the m_shape strip over the shadowed map, tick-driven) when the caster has an
## imported strip, else the 預備動作-off lead (AnimalCastLead.skipped, 8 shadow calls); as it ends
## the caster poses (`released`), Cast_Star bursts over it and sfx 0x193 sounds, and the
## script waits out the pose (`caster_pose_ticks`, 8n + 40), then plays at every affected
## position (once at the cursor cell centre `map_target` for eff_proc_Global: 0x442b58 sets
## 0x4c2c70／0x4c2c74 to (column×32+16, row×32+16) and 0x442d81 builds one interpreter there) with `impact` at its last cue; the
## effect carries no name caption. Real seconds, 62.5 ticks/s, after the lead.
func _present_effect(host: CanvasLayer, clip: Dictionary, elapsed: float) -> bool:
	var timeline: Dictionary = clip["effect_timeline"]
	var strike: Dictionary = clip["strike"]
	hide_actors(host)
	host.stage.size = Vector2(640, 480)
	host.scenery.visible = false
	host.vitals.visible = false
	# Every map spell builds the cast lead object 154 kind 1 (0x442a90 → 0x406d20 on each branch:
	# 0x442f26, 0x442c6c, 0x442cea); a caster with no lead frames takes the 預備動作-off jump
	# (0x401d6f → 0x401ec4) into sub-state 7 with the shadow bit set (0x401ed4), so the map is
	# shadowed whether or not the spell deals damage: level min(call + 1, 8) while +0x90 counts
	# (0x4030f7), then 8 through sub-states 5 and 6 (0x4030b7).
	host.background.visible = true
	var lead_call := int(elapsed / Timing.PLAYBACK_SPEED * TICKS_PER_SECOND)
	host.background.color = Color(0, 0, 0, float(mini(lead_call + 1, AnimalCastLead.SHADOW_MAX_LEVEL)) / AnimalCastLead.LEVELS)
	# The spell's name captions the AI lead-in's range (BattleAttackCue.caption), not the effect:
	# the original's effect states (0x7a, 0x4419f8) draw no text.
	host.result.visible = false
	show()
	# A caster without an imported strip plays the 預備動作-off lead (the same 0x401ec4 jump).
	var lead: Dictionary = host.cast_lead(clip, "magic")
	if lead.is_empty():
		lead = AnimalCastLead.skipped(true)
	var lead_end: float = Timing.scaled(OriginalTick.seconds(float(lead["complete_tick"])))
	# The call after the lead poses the caster (0x4071e0), bursts Cast_Star and sounds 0x193
	# (0x402fd1／0x403128); the effect VM states 4／7／0x17／0x19 wait while the caster's pose bit
	# 0x1000 is set (0x442c89, 0x442d07, 0x442f65, 0x443009), 8n + 40 ticks.
	var lead_in: float = Timing.scaled(OriginalTick.seconds(float(lead["complete_tick"]) + float(clip.get("caster_pose_ticks", 0))))
	if elapsed < lead_end:
		host.show_cast_lead(clip, lead, elapsed / Timing.PLAYBACK_SPEED * TICKS_PER_SECOND)
		clear()
		return false
	if not clip.get("cast_started", false):
		clip["cast_started"] = true
		host.ability_sound.stream = load(host.cue_manifest["sounds"]["cast_magic"]["res_path"])
		host.ability_sound.play()
		clip["cast_stars"] = cast_stars(hash(str(clip["strike"])))
	# After the lead the attacker object stays: sub-state 5 (0x403089) hands the flow back
	# (parent +0x8c++) and hides itself, sub-state 6 (0x4030b7) keeps its shadow at +0x90 = 8
	# while the effect phase holds [0x4c1b00] & 0x1000000, so the map stays at level 8／16.
	host.background.color = Color(0, 0, 0, float(AnimalCastLead.SHADOW_MAX_LEVEL) / AnimalCastLead.LEVELS)
	var star_origin: Vector2 = clip["map_caster"] - Vector2(0, float(clip.get("caster_height", CAST_STAR_DEFAULT_HEIGHT)))
	var star_tick: float = (elapsed - lead_end) / Timing.PLAYBACK_SPEED * TICKS_PER_SECOND
	if elapsed < lead_in:
		mark(host, clip, elapsed, {"release": lead_end, "impact": INF, "complete": INF})
		_draw_cast_stars(clip["cast_stars"], star_tick, star_origin, 0)
		return false
	var seconds: float = (elapsed - lead_in) / Timing.PLAYBACK_SPEED
	var scale: float = Timing.PLAYBACK_SPEED / TICKS_PER_SECOND
	var complete := mark(host, clip, elapsed, {"release": lead_end,
		"impact": lead_in + float(timeline["impact_tick"]) * scale,
		"complete": lead_in + float(timeline["complete_tick"]) * scale})
	var used := draw(clip, seconds, [clip["map_target"]] if bool(timeline["global"]) else clip["affected_positions"])
	_draw_cast_stars(clip["cast_stars"], star_tick, star_origin, used)
	if complete:
		clear()
		return true
	return false


## 0x408b20 case 4 (0x408bb4): two 0x401390 calls of object 399 Cast_Star at the burst point,
## (w 2, h 2, delay 0, jitter 0, 28) then (…, delay 24, …, 20) — dx, dy ∈ {0, 1}, one tick
## apart. Each runs effProcCollectFadeShape (0x41f4e5): a held shape rand(6), angle rand & 0xff,
## radius obj_Data5 128 + rand(64) px closing at obj_Data3 3.5 px a tick to 1 px, level + 1
## every 2 ticks to 16, then − 1 a tick; additive (0x415dc0). Presentation RNG, seeded per clip.
const CAST_STAR_BATCHES := [[0, 28], [24, 20]]
const CAST_STAR_RADIUS := 128
const CAST_STAR_RADIUS_RANGE := 64
const CAST_STAR_SPEED := 3.5
const CAST_STAR_LEVELS := 16
## 0x43d990 for a caster without a shape (0xffff): 40 + 2.
const CAST_STAR_DEFAULT_HEIGHT := 42


static func cast_stars(seed: int) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var stars: Array = []
	for batch in CAST_STAR_BATCHES:
		for index in range(int(batch[1])):
			var angle := TAU * float(rng.randi() & 0xff) / 256.0
			var radius := float(CAST_STAR_RADIUS + _rand(rng, CAST_STAR_RADIUS_RANGE))
			var arrive := int(ceilf((radius - 1.0) / CAST_STAR_SPEED))
			stars.append({"start": int(batch[0]) + index, "at": Vector2(_rand(rng, 2), _rand(rng, 2)), "frame": _rand(rng, 6),
				"direction": Vector2(cos(angle), sin(angle)), "radius": radius, "arrive": arrive, "arrive_level": mini(arrive / 2, CAST_STAR_LEVELS)})
	return stars


## Draws the Cast_Star objects alive `tick` ticks after the burst from sprite `first` on.
func _draw_cast_stars(stars: Array, tick: float, origin: Vector2, first: int) -> void:
	var used := first
	for star in stars:
		var age := int(tick) - int(star["start"])
		if age < 0:
			continue
		var level := mini(age / 2, CAST_STAR_LEVELS) if age <= int(star["arrive"]) else int(star["arrive_level"]) - (age - int(star["arrive"]))
		if level <= 0:
			continue
		var frame: Dictionary = casting[int(star["frame"]) % casting.size()]
		var sprite := _sprite(used)
		used += 1
		sprite.texture = load(frame["res_path"])
		sprite.centered = false
		sprite.offset = -Vector2(frame["draw_origin"][0], frame["draw_origin"][1])
		sprite.position = origin + Vector2(star["at"]) + (Vector2(star["direction"]) * maxf(float(star["radius"]) - CAST_STAR_SPEED * age, 1.0)).floor()
		sprite.scale = Vector2.ONE
		sprite.rotation = 0.0
		sprite.z_index = 0
		sprite.material = materials[""]
		sprite.modulate = Color(1, 1, 1, float(level) / CAST_STAR_LEVELS)
		sprite.show()
	for index in range(used, sprites.size()):
		sprites[index].hide()


## Draws the objects alive at `seconds` once per origin and fires the sounds reached since
## the last call (the clip remembers which). Special sprites follow the stage — (0,0) top-left,
## the target centre at (320,160), feet at y=320 — with the single origin (0,0); effect sprites
## are displaced from each affected position.
func draw(clip: Dictionary, seconds: float, origins: Array) -> int:
	show()
	var timeline: Dictionary = clip["effect_timeline"]
	var tick := seconds * TICKS_PER_SECOND
	if not clip.has("effect_sounds_played"):
		clip["effect_sounds_played"] = []
	var used := 0
	for index in range(timeline["events"].size()):
		var event: Dictionary = timeline["events"][index]
		if event["kind"] == "sound":
			if tick >= float(event["tick"]) and not clip["effect_sounds_played"].has(index):
				clip["effect_sounds_played"].append(index)
				_play(str(event["member"]))
			continue
		if tick < float(event["tick"]) or tick >= float(event["expire"]):
			continue
		if event["motion"] == "native":
			used = _draw_native(event, tick, origins, used)
			continue
		for origin in origins:
			var sprite := _sprite(used)
			used += 1
			_draw_object(sprite, event, tick, origin)
	for index in range(used, sprites.size()):
		sprites[index].hide()
	return used


func _draw_object(sprite: Sprite2D, event: Dictionary, tick: float, origin: Vector2) -> void:
	var age := tick - float(event["tick"])
	var frames: Array = event["frames"]
	var frame_index := int(event["fixed_frame"])
	if frame_index < 0:
		frame_index = int(age / float(event["frame_ticks"]))
		frame_index = frame_index % frames.size() if event["motion"] != "static" else mini(frame_index, frames.size() - 1)
	var record: Dictionary = manifest["frames"][frames[frame_index]]
	sprite.texture = texture(frames[frame_index])
	sprite.centered = false
	sprite.offset = -Vector2(record["draw_origin"][0], record["draw_origin"][1])
	sprite.rotation = float(event["rotation"])
	sprite.scale = event["scale"] * float(event["zoom"])
	sprite.z_index = int(event["z"])
	sprite.material = materials.get(event["mode"], materials[""])
	sprite.modulate = Color.WHITE
	if event.has("fade_tick"):
		sprite.modulate.a = clampf(1.0 - (tick - float(event["fade_tick"])) / float(EFFECT_FADE_TICKS), 0.0, 1.0)
	var position: Vector2 = event["position"]
	match str(event["motion"]):
		"fly":
			var progress := clampf(age / maxf(1.0, float(event["arrive"]) - float(event["tick"])), 0.0, 1.0)
			position = position.lerp(TARGET_CENTRE, progress)
		"radial":
			position += event["direction"] * ANGLE_SPEED * age
		"spin":
			var angle := TAU * (float(event["angle"]) + TORNADO_SPIN * age)
			position = event["centre"] + Vector2(cos(angle) * float(event["radius"]), sin(angle) * float(event["radius"]) * 0.25)
	sprite.position = origin + position
	sprite.show()


## A natively tracked effect object: every instance of its tree drawn at the track frame the
## clip has reached, displaced like the insertion (an anchored program ignores it), in the
## track's blend, level alpha and zoom.
func _draw_native(event: Dictionary, tick: float, origins: Array, used: int) -> int:
	var frame := int(tick - float(event["tick"]))
	var displacement: Vector2 = Vector2.ZERO if bool(event["anchored"]) else event["position"]
	var entries: Array = ObjcomdMotion.sprites_at(str(event["object"]), int(event["variant"]), frame) if event.get("source", "") == "objcomd" \
		else EffectObjectMotion.sprites_at(EffectObjectMotion.track(str(event["object"])), frame)
	for entry in entries:
		var member := _native_member(str(entry["member"]))
		if member == "":
			continue
		var record: Dictionary = manifest["frames"][member]
		for origin in origins:
			var sprite := _sprite(used)
			used += 1
			sprite.texture = texture(member)
			sprite.centered = false
			sprite.offset = -Vector2(record["draw_origin"][0], record["draw_origin"][1])
			sprite.rotation = 0.0
			sprite.scale = entry["scale"]
			sprite.z_index = int(event["z"])
			sprite.material = materials[str(entry["blend"])]
			sprite.modulate = Color(1, 1, 1, float(entry["alpha"]))
			sprite.position = origin + displacement + (entry["offset"] as Vector2)
			sprite.show()
	return used


## The imported frame for a track member; a member hsl.pak lacks (the skill_effects
## missing_members, negative-evidence) cycles the series' existing members like the untracked
## player does (provisional: the original registry's neighbour is unread); "" when the series
## has none.
func _native_member(member: String) -> String:
	if manifest["frames"].has(member):
		return member
	if not series_members.has(member):
		var found := RegEx.create_from_string("^(.*?)(\\d+)(\\.SHP)$").search(member)
		var existing: Array = []
		if found != null:
			for index in range(1, int(found.get_string(2))):
				var candidate := found.get_string(1) + str(index).pad_zeros(found.get_string(2).length()) + found.get_string(3)
				if manifest["frames"].has(candidate):
					existing.append(candidate)
		series_members[member] = "" if existing.is_empty() else existing[(int(found.get_string(2)) - 1) % existing.size()]
	return series_members[member]


func _sprite(index: int) -> Sprite2D:
	while sprites.size() <= index:
		var sprite := Sprite2D.new()
		sprite.hide()
		add_child(sprite)
		sprites.append(sprite)
	return sprites[index]


func _play(member: String) -> void:
	var player := sounds[next_sound]
	next_sound = (next_sound + 1) % sounds.size()
	# A voice still sounding is cut before its stream changes: swapping the stream of a
	# playing AudioStreamPlayer leaves the old playback referenced until exit.
	player.stop()
	player.stream = load(manifest["sounds"][member]["res_path"])
	player.play()


func clear() -> void:
	for sprite in sprites:
		sprite.hide()
	hide()
