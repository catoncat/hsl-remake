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
## The ANIMAL random, distance and round inserts place and time their objects as the
## interpreter 0x4038a0 does (spawners 0x401390／0x401480／0x401560, 0x403ddb).
## The tick clock (60/s), the other object lifetimes (shape_number × (shape_delay + 1) ticks;
## untracked effect objects at least EFFECT_MIN_LIFETIME_TICKS then an EFFECT_FADE_TICKS alpha
## tail), flights of the special objects without a track inserted outside the 640×320 stage towards
## the target centre, the ANIMAL angle／tornado geometry and the magic impact mark (the
## script's last insertion or sound cue) are provisional remake readings recorded in
## skill_effects/manifest.json (`policy`, `replacement_evidence`); the effProc* programs listed
## unrestored are not restored; an object's own sounds are — a
## special object's objcomd.txt command sounds and an effect object's obj_X1／obj_Y1／obj_X2 WAVs.
## provenance:
##   layout: static-derived content/generated/hsl/skills/effect_motion.json
##   layout: static-derived content/generated/hsl/skills/objcomd_motion.json
##   layout: static-derived docs/evidence_packets/static_reverse/original_objcomd_programs.md
##   layout: resource-derived content/imported/hsl/shared/skill_effects/manifest.json
##   layout: resource-derived content/imported/hsl/global/tables/ANIMAL.H
##   layout: resource-derived content/imported/hsl/global/tables/effects.h
##   layout: resource-derived content/imported/hsl/shared/mage_magic/manifest.json
##   layout: static-derived docs/evidence_packets/static_reverse/animal_program_execution.md#8-施法引导程序m_actions_action的解释
##   layout: static-derived docs/evidence_packets/static_reverse/original_cast_overlays.md#施法引导的合成
##   layout: provisional
##     (ANIMAL angle／tornado geometry, off-stage flights, static hold of the objects effect_motion.json
##     lists unrestored, eff_proc_Global at screen centre — manifest policy)
##   layout: static-derived docs/evidence_packets/runtime_observations/cutin_floaters/README.md
##   strings: resource-derived content/generated/hsl/skills/special_effect_scripts.json
##   strings: remake-invented content/generated/hsl/skills/authored_effect_scripts.json
##     (the authored skills' names and scripts, sequel content from content/authored/roles/skills.json)
##   timing: resource-derived content/generated/hsl/skills/special_effect_scripts.json
##   timing: static-derived content/generated/hsl/skills/effect_motion.json
##   timing: static-derived docs/evidence_packets/static_reverse/original_effect_motion.md
##   timing: static-derived docs/evidence_packets/static_reverse/original_caster_effect.md
##   timing: static-derived docs/evidence_packets/runtime_observations/original_tick_rate/README.md
##   timing: resource-derived content/imported/hsl/chapter01/combat_animation/manifest.json
##   timing: static-derived docs/evidence_packets/static_reverse/original_effect_object_sounds.md
##   timing: static-derived docs/evidence_packets/static_reverse/original_objcomd_programs.md
##   timing: provisional
##     (lifetime = shape_number × (shape_delay＋1); untracked objects' lifetime／fade; impact at the last cue;
##     EMPTY_ATTACK_LEAD_TICKS stands in; effProc* motion not restored)
##   audio: resource-derived content/imported/hsl/shared/skill_effects/manifest.json
##   audio: static-derived docs/evidence_packets/static_reverse/original_effect_object_sounds.md
##   audio: static-derived content/generated/hsl/skills/objcomd_motion.json
##   audio: static-derived content/generated/hsl/skills/effect_motion.json
##   audio: provisional
##     (objects without a native track keep the static command_sounds／program_sounds)
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
const BattleCameraController = preload("res://game/common/BattleCameraController.gd")
const TICKS_PER_SECOND := OriginalTick.TICKS_PER_SECOND
## Object 154's sub-state 5 (0x403089): the one call after the posing call; it hands the flow
## back to the effect VM (0x40309e), whose states 4／7／0x17／0x19 set the effect phase and then
## wait only on the caster's pose bit — in parallel with the pose, not after it.
const SUB_STATE_5_TICKS := 1
## effect_caster (docs/evidence_packets/static_reverse/original_caster_effect.md): Local's start state
## 0x14 sets 0x15 and returns (0x442f35), and 0x15's 0x43bf30(caster, 0x80000000) finds the camera
## already there since state 0, so its lead comes a call later than the no-caster lead (0x442f26,
## same call); Global's 1 → 2 → lead takes the calls its no-caster 1 → 5 → lead does.
const CASTER_LOCAL_START_TICKS := 1
## The call that builds the caster object (0x442f77) and the one that finds +0x9e at 0 and sets
## 7／0x19 (0x442cd0／0x442fe2), around the +0x9e calls that count it down; 7／0x19 run on the next.
const CASTER_HANDOFF_TICKS := 2
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
## Phase 18 of aniProcessHitMissMulti: a strike's check tick to the next check (sub-states
## 0 → 1 → 3 → 0: 0x4047d5, 0x4045d5, 0x4045c7) when the strike's numbers do not hold the
## defender (every strike but the last, and a last strike that spawns no number).
const MULTI_HIT_STRIKE_TICKS := 3
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
## The mixer's channels: 0x42f164 opens 9 (0x459b60(9, 20, …) → [0x4c23d4]) and every sound
## the object programs play (0x42c180 → 0x45a390, flags 0) takes the first channel that is empty
## or has stopped (0x4593a0); with all 9 sounding the new sound is dropped — no cut, no
## same-WAV merge, so each object instance sounds its own cue (百裂突刺's 26 thrusts).
const SOUND_VOICES := 9
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


func compile_row(skill_id: String, hit: bool, seed: int, strike_hits: Array = [], last_strike: Dictionary = {}) -> Dictionary:
	var row: Dictionary = scripts[skill_id]
	if str(row["channel"]) == "magic":
		return compile_effect(row["actions"][row["effect_code"]], seed, manifest, row)
	return compile(row["actions"][row["attack_code"]], row["actions"][row["defense_code"]], hit, seed, manifest, strike_hits, last_strike)


## The tick timeline of one attack script followed by one defense script. Pure: the same
## inputs and seed give the same events; nothing is drawn or played here. `strike_hits`: the
## per-strike hits of a multi-hit receipt (MultiHitSpecialRules `hit_segments`), in settlement
## order; an object's hit run and hit-only sounds follow the strike [0x4c1418] holds when its
## program reads the word (strike_word_hit). `last_strike`: {"damage", "experience"} of the
## receipt — the last strike's HP change and the shot's summed experience — which decide
## whether the last strike's number holds the defender (_last_strike_ticks); empty keeps the
## three-tick cadence.
static func compile(attack_lines: Array, defense_lines: Array, hit: bool, seed: int, data: Dictionary, strike_hits: Array = [], last_strike: Dictionary = {}) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var timeline := {"kind": "special", "events": [], "release_tick": 0, "impact_tick": -1, "result_tick": -1, "darken_tick": 0, "complete_tick": 0,
		"hit": hit, "strike_hits": strike_hits, "last_strike": last_strike, "strike_ticks": [], "sound_cues": [],
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
				_insert_spawner(timeline, data, rng, phase, str(args[0]), Vector2(number(args[1]), number(args[2])), Vector2i(number(args[3]), number(args[4])), 0, number(args[5]), false, number(args[6]), cursor)
		"aniInsertHitRandomObjectDisp":
			if hit:
				# 0x403be2: the base is the defender object's own x／y — the neutral shot anchor
				# here, moved onto the defender's drawn point at this tick by _place_on_defender.
				var base: Vector2 = CutinLayout.SHOT_ANCHOR + timeline["xy_disp"]
				var first: int = timeline["events"].size()
				_insert_spawner(timeline, data, rng, phase, str(args[0]), base + Vector2(number(args[1]), number(args[2])), Vector2i(number(args[3]), number(args[4])), 0, number(args[5]), false, number(args[6]), cursor)
				for index in range(first, timeline["events"].size()):
					if timeline["events"][index]["kind"] == "object":
						timeline["events"][index]["defender_base"] = base
						timeline["events"][index]["defender_tick"] = cursor
		"aniInsertRandomObjectDelay", "aniInsertRandomObjectFixDelay", "aniInsertHitRandomObjectFixDelay":
			if hit or op != "aniInsertHitRandomObjectFixDelay":
				_insert_spawner(timeline, data, rng, phase, str(args[0]), Vector2(number(args[1]), number(args[2])), Vector2i(number(args[3]), number(args[4])), number(args[5]), number(args[6]), op != "aniInsertRandomObjectDelay", number(args[7]), cursor)
		"aniInsertRoundRandomObject":
			_insert_round(timeline, data, phase, args, cursor)
			# 0x403e90 stores the pointer and leaves the interpreter (0x404ba6): the next
			# instruction runs on the next tick.
			cursor += 1
		"aniInsertSpecialBG":
			timeline[phase + "_background"] = str(args[0])
		"aniProcessHitMiss":
			timeline["hit_ticks"].append(cursor)
		"aniProcessHitMissMulti":
			cursor = _multi_hit_wait(timeline, cursor)
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


## aniProcessHitMissMulti (op 6 of 0x404ee8 → 0x403e9e) at `cursor` puts the defender in
## phase 18 (0x4045a4) and yields; from the next tick its sub-state 0 (0x4047af) reads the dword
## 0x4c6f68 — the settle counter 0x4c6f68 and the pending counter 0x4c6f6a. Zero: back to the
## script (0x4047b8 clears phase and sub-state). Settle counter non-zero: one strike settles
## (0x4047d5: 0x4c6f68--, then the single-strike body 0x4047e9) and the next tick (sub-state 1,
## 0x4045d5) spawns its numbers (0x4084e0), sub-state 3 resets to 0 a tick later, so the next
## check comes three ticks after a strike. The last strike (settle counter 0 at 0x4045fb)
## spawns its number with the defender as waiter and skips the sub-state increment while the
## number lives (0x404795／0x40473a); the number bumps it (0x4088fa) — _last_strike_ticks.
## The counters count from the defender insert (0x406ecc clears them): each defense object's
## objmInitMultiHitData (op 71, 0x4c6f6a++; a program's first word, counted at creation by
## 0x40524d before any insertion delay) and objmSetMultiHitData (op 72, 0x4c6f6a--,
## 0x4c6f68++) at the tick its native run executed it (`multi_hit_ops`, _insert_sounds). Each
## strike appends a hit mark and a result mark (its numbers); the next cursor is the check that
## reads both counters zero. Without an op 72 among the objects the strike settles at the
## cursor. A counter no program brings back to zero ends the wait once no op is left (the
## original would hold until the teardown). The frame loop 0x45f5f7 runs the planes in order,
## each list in creation order (0x45e307 appends): the defender (object 155, planeEffect3 =
## 46) runs before its script's objects (planeEffect4 = 47, or later on plane 46), so an op
## executed on tick t counts at the check of t + 1.
static func _multi_hit_wait(timeline: Dictionary, cursor: int) -> int:
	var ops: Array = timeline.get("multi_hit_ops", []).duplicate()
	if not ops.any(func(op): return int(op[1]) == 72):
		timeline["hit_ticks"].append(cursor)
		return cursor
	ops.sort_custom(func(a, b): return int(a[0]) < int(b[0]))
	var settle := 0
	var pending := 0
	var index := 0
	var tick := cursor + 1
	while true:
		while index < ops.size() and int(ops[index][0]) < tick:
			if int(ops[index][1]) == 71:
				pending += 1
			else:
				pending -= 1
				settle += 1
			index += 1
		if settle > 0:
			timeline["hit_ticks"].append(tick)
			timeline["strike_ticks"].append(tick)
			timeline["result_ticks"].append(tick + 1)
			settle -= 1
			var last := settle == 0 and not ops.slice(index).any(func(op): return int(op[1]) == 72)
			tick += _last_strike_ticks(timeline["last_strike"]) if last else MULTI_HIT_STRIKE_TICKS
			continue
		if pending == 0 or index >= ops.size():
			break
		tick += 1
	return tick


## Ticks from the last strike's check to the check that returns to the script. Sub-state 1
## (0x4045d5) spawns the number the tick after the strike; with both change words zero and
## the shot's experience [0x4c13f0] (0x40485d, cleared at the page open 0x40438c) non-zero it
## spawns none and steps on (0x404772): the three-tick cadence. Otherwise the number — red
## kind 0 for an HP loss, green kind 2 for a gain, MISS kind 5 when nothing changed and no
## experience was gained — takes the defender as waiter and bumps its sub-state at release
## (0x4088f4: +0x28 < 9 for kind 0, Timing.damage_number_release_ticks; 0x4086ea for the
## other kinds, 32 ticks after the hold); the number (planeMenu2 = 51) runs after the
## defender, which sees sub-state 3 a tick later, resets it (0x4045c7) and checks the next
## tick. The MP number (kind 3) of an MP change is not in the receipt and keeps the cadence.
static func _last_strike_ticks(last_strike: Dictionary) -> int:
	if last_strike.is_empty():
		return MULTI_HIT_STRIKE_TICKS
	var damage := int(last_strike.get("damage", 0))
	if damage == 0 and int(last_strike.get("experience", 0)) != 0:
		return MULTI_HIT_STRIKE_TICKS
	var release := Timing.damage_number_release_ticks(damage) if damage > 0 else ResultNumberFloater.hidden_ticks(0) + Timing.SHOW_NUMBER_RELEASE_TICKS
	return 1 + release + 2


## Whether [0x4c1418] reads as a hit on `tick`: every multi-hit strike rewrites it as it settles
## (0x404803 clears it, 0x4048d6 writes 200 when the strike changed nothing), in the defender's
## run, before the objects of that tick (0x45f5f7 plane order), so a read on tick t sees the
## last strike settled on or before t; before the first strike, or on a shot without one, the
## word keeps the shot's roll (`hit`).
static func strike_word_hit(timeline: Dictionary, tick: int) -> bool:
	var strikes: Array = timeline.get("strike_ticks", [])
	var hits: Array = timeline.get("strike_hits", [])
	var index := -1
	for rank in range(mini(strikes.size(), hits.size())):
		if int(strikes[rank]) <= tick:
			index = rank
	return bool(hits[index]) if index >= 0 else bool(timeline["hit"])


## The patterned multi-object inserts (line, ring, tornado); false for any other op.
## aniInsertDistanceObjectFixDelay [code][x][y][x disp][y disp][base delay][delay][number]
## (op 25 → 0x403ad7 → 0x401560): object k at the point + k × disp, created at once with
## insertion delay base + k × delay (_insert_delay); no random draw.
static func _insert_pattern(timeline: Dictionary, data: Dictionary, phase: String, op: String, args: Array, cursor: int) -> bool:
	match op:
		"aniInsertDistanceObjectFixDelay":
			var step := Vector2(number(args[3]), number(args[4]))
			for index in range(number(args[7])):
				_insert(timeline, data, phase, str(args[0]), Vector2(number(args[1]), number(args[2])) + step * index, cursor + _insert_delay(number(args[5]) + number(args[6]) * index), cursor)
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
		# The hit-only throws (0x405434／0x405495) and objmPlayHitSound (0x4059f3) read
		# [0x4c1418] < [0x4c6f58] on the frame the program plays its first hit-only sound
		# (the throws run just before it, e.g. objcomd code 79: op 72, objmDelay 1, throws,
		# sounds); the word then holds the strike settled last (strike_word_hit).
		var read := ObjcomdMotion.hit_read_frame(name, int(event["variant"]))
		event["hit"] = strike_word_hit(timeline, int(event["tick"]) + maxi(read, 0))
	timeline["events"] = timeline["events"].filter(func(event): return not event.get("hit_only", false) or strike_word_hit(timeline, int(event["tick"])))
	for event in timeline["events"]:
		event.erase("hit_only")
	for event in timeline["events"]:
		if event.get("source", "") == "objcomd":
			event["expire"] = int(event["tick"]) + ObjcomdMotion.frames(str(event["object"]), bool(event["hit"]))
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
	# hold it. The defense script's aniOver (0x403d3d) goes straight to phase 101 (0x403d7a):
	# sub 0 requests the 16-tick darken (0x404b23), sub 1 then sets the teardown bit
	# 0x4c1404 |= 1 and deletes the 0x4c1400 objects (0x401370, 0x404ada); every cutin effect
	# object (slots 36–38: 0x404ffa, 0x4050a0, 0x4051d0) deletes itself on that bit — no
	# liveness check. The attack script's phase 101 (0x40298a) sets the same bit as soon as its
	# hit flash is gone, so the attack page's objects end at the page change (the defense page
	# clears the bit, 0x40435e). An object — a random-delay insert (0x401390) whose accumulated
	# delay overtakes its page's teardown — never appears, and neither do the command sounds
	# of an object past its deletion. `darken_tick` starts the shade (the remake keeps the
	# RESULT_HOLD_TICKS stand-in for the unread aniShowHitResult block); `complete_tick` is the
	# teardown.
	var darken := maxi(cursor, int(timeline["result_tick"]) + RESULT_HOLD_TICKS)
	var complete := darken + Timing.RECOVERY_TICKS
	var cuts := {"attack": int(timeline["release_tick"]), "defense": complete}
	var kept: Array = []
	for event in timeline["events"]:
		var cut: int = cuts.get(event["phase"], complete)
		if int(event["tick"]) >= cut or int(event.get("source_tick", -1)) >= cut:
			continue
		if event["kind"] == "object" and (event.get("open_ended", false) or int(event["expire"]) > cut):
			event["expire"] = cut
		kept.append(event)
	timeline["events"] = kept
	timeline.erase("multi_hit_ops")
	timeline.erase("last_strike_tick")
	timeline.erase("last_strike")
	timeline["darken_tick"] = darken
	timeline["complete_tick"] = complete
	timeline.erase("sound_cues")


## The tick timeline of one MAGIC effCode script. Object positions are displacements from
## the effect origin (the drawer adds the target position); the impact mark is the script's
## last cue — its last object insertion or sound — every object holds for
## clamp(lifetime, EFFECT_MIN_LIFETIME_TICKS, the script's remaining waits) then fades, and
## the clip completes when the script's waits and every fade are over. `script_end_tick` is the
## sum of the waits: the tick the effect interpreter reaches op 0 and steps the cast routine on
## (0x4239ac `inc word [ctx+0x8c]`). Pure like `compile`.
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
	timeline["script_end_tick"] = cursor
	var complete := cursor
	var seed_order := {}
	for event in timeline["events"]:
		if event["kind"] == "object":
			if EffectObjectMotion.tracked(str(event["object"])):
				# The native tree: frame f of the track shows at insertion tick + f, until its
				# last instance is gone; an anchored program drives itself from the origin.
				# Repeated insertions of one object cycle its seed variants.
				var order: int = seed_order.get(str(event["object"]), 0)
				seed_order[str(event["object"])] = order + 1
				event["variant"] = order % EffectObjectMotion.variants(str(event["object"]))
				var native: Dictionary = EffectObjectMotion.track(str(event["object"]), int(event["variant"]))
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
	var caster: Dictionary = row.get("caster", {})
	if not caster.is_empty():
		timeline["caster"] = compile_caster(str(caster["object"]), int(caster["ticks"]), data)
	return timeline


## The effect_caster object (MAGIC record +0x34／+0x38): built once at the caster's cell by
## 0x45e307(x, y, code, 0) on the first call the pose bit is clear (0x442f77), then the cast waits
## `ticks` calls. Its own tick 0 is that call; a tracked object follows its native run.
static func compile_caster(object_name: String, ticks: int, data: Dictionary) -> Dictionary:
	var caster := {"object": object_name, "ticks": ticks, "events": [], "sound_cues": [], "skipped_objects": []}
	var event := _insert(caster, data, "effect", object_name, Vector2.ZERO, 0, 0)
	if not event.is_empty() and EffectObjectMotion.tracked(object_name):
		var native: Dictionary = EffectObjectMotion.track(object_name, 0)
		event["variant"] = 0
		event["motion"] = "native"
		event["anchored"] = str(native["motion"]) == "anchored"
		event["expire"] = int(native["frames"])
	elif not event.is_empty():
		event["fade_tick"] = clampi(int(event["lifetime"]), EFFECT_MIN_LIFETIME_TICKS, maxi(EFFECT_MIN_LIFETIME_TICKS, ticks))
		event["expire"] = int(event["fade_tick"]) + EFFECT_FADE_TICKS
	caster.erase("sound_cues")
	return caster


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


## The ANIMAL random inserts as the interpreter runs them, all creating their objects at once
## with an insertion delay (+0xae): aniInsertRandomObject／aniInsertHitRandomObject／
## aniInsertHitRandomObjectDisp [code][x][y][x range][y range][delay][number] (ops 19／27／28 →
## 0x403c2b → spawner 0x401390, base delay 0), aniInsertRandomObjectDelay [code][x][y]
## [x range][y range][base delay][delay][number] (op 23, 0x403b25 → 0x401390) and
## aniInsertRandomObjectFixDelay／aniInsertHitRandomObjectFixDelay with the same words (ops
## 24／29, 0x403b73／0x403c3b → 0x401480; 29 and 27／28 only on a hit, [0x4c1418] < +0xa6, no
## draw on a miss). Each object at the point plus rand(range) folded into (−range/2, range/2]
## (x then y); the first gets the base delay, every next one rand(delay) + 1 more (0x401455;
## 3 draws an object) or, for 0x401480, a fixed `delay` more (2 draws an object); each starts
## as _insert_delay reads its delay. 月花圓舞's 64 petals fall over about 220 ticks, not in one
## burst. The draws come from the clip's presentation RNG.
static func _insert_spawner(timeline: Dictionary, data: Dictionary, rng: RandomNumberGenerator, phase: String, code: String, centre: Vector2, span: Vector2i, base_delay: int, delay: int, fixed_step: bool, count: int, cursor: int) -> void:
	var first: int = timeline["events"].size()
	var wait := base_delay
	for _index in range(count):
		var offset := Vector2(_fold(rng, span.x), _fold(rng, span.y))
		_insert(timeline, data, phase, code, centre + offset, cursor + _insert_delay(wait), cursor)
		wait += delay if fixed_step else _rand(rng, delay) + 1
	_mark_random(timeline, first)


## aniInsertRoundRandomObject [code][x][y][radius][x shr][y shr][delay][start angle][number]
## (op 26, 0x403ddb; no random draw despite the name): number objects (0 counts as 1) round
## the point, the angle (16.16, 256 a turn) from the start angle in steps of 0x1000000 ／
## number; 0x45ea2b takes each offset as trunc(|cos／sin table| × radius ／ 2^32) with the
## table's sign (radius 16.16), then shifts it right by x shr／y shr (arithmetic). Object k
## is created at once with insertion delay k × delay (_insert_delay).
static func _insert_round(timeline: Dictionary, data: Dictionary, phase: String, args: Array, cursor: int) -> void:
	var count := number(args[8])
	if count == 0:
		count = 1
	var radius := number(args[3])
	var step: int = 0x1000000 / count
	var angle := number(args[7]) << 16
	var shifts := Vector2i(number(args[4]) & 31, number(args[5]) & 31)
	for index in range(count):
		var turn := TAU * float((angle >> 16) & 0xff) / 256.0
		var offset := Vector2i(_polar(roundi(65536.0 * cos(turn)), radius), _polar(roundi(65536.0 * sin(turn)), radius))
		offset = Vector2i(offset.x >> shifts.x, offset.y >> shifts.y)
		_insert(timeline, data, phase, str(args[0]), Vector2(number(args[1]), number(args[2])) + Vector2(offset), cursor + _insert_delay(number(args[6]) * index), cursor)
		angle += step


## The tick after its creation an object inserted with delay `delay` (+0xae) starts its
## program: defProcObjectMove's first call (0x405294..0x4052a2) decrements +0xae before
## testing it against 0, so delays 0 and 1 both run on the creation call and d ≥ 1 runs d − 1
## ticks later. A program opening with objmRandomDelay adds its draw to +0xae first
## (0x40525b..0x405287); its native track already holds that wait, not merged here (no object
## the ANIMAL inserts place opens so).
static func _insert_delay(delay: int) -> int:
	return maxi(delay - 1, 0)


## 0x45ea2b's product: |table| × radius >> 16 >> 16, negated for a negative table entry.
static func _polar(entry: int, radius: int) -> int:
	var magnitude := ((absi(entry) * radius) >> 16) >> 16
	return -magnitude if entry < 0 else magnitude


## Tags the events a random insert (0x401390) appended from `first` on: which of them the
## scene teardown overtakes depends on the drawn delays.
static func _mark_random(timeline: Dictionary, first: int) -> void:
	for index in range(first, timeline["events"].size()):
		timeline["events"][index]["random"] = true


## One object insertion; {} (and a `skipped_objects` entry) for an object the manifest cannot
## draw — obj_Special51_05 has no OBJ-ALL.H definition (scope `unresolved_objects`). In the
## `effect` phase the position is a displacement and the object's hold and fade are settled by
## compile_effect once the script's length is known. The object's own sounds are scheduled
## first (`_insert_sounds`), so an object whose frames cannot be drawn still sounds.
static func _insert(timeline: Dictionary, data: Dictionary, phase: String, object_name: String, position: Vector2, tick: int, sound_tick: int = -1) -> Dictionary:
	var object: Dictionary = data["objects"].get(object_name, {})
	var first_sound: int = timeline["events"].size()
	_insert_sounds(timeline, data, phase, object_name, object, tick, sound_tick)
	for index in range(first_sound, timeline["events"].size()):
		timeline["events"][index]["source_tick"] = tick
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
	if timeline.has("last_strike_tick"):
		event["strike_tick"] = int(timeline["last_strike_tick"])
	timeline.erase("last_strike_tick")
	timeline["events"].append(event)
	return event


## The sounds an inserted object makes by itself, from the native runs when the object has a
## track (each cue at the instance's tick plus the frame the run played it, the variant counted
## per object over the timeline's insertions):
## - an effect object (effect_motion.json `sounds`): obj_X1 as it starts (0x415e1a) and the
##   obj_Y1／obj_X2 its effProc* program plays at its own events (0x415d40／0x415d70／0x415d90),
##   with every child it throws — 烈蝕水彈's WaterBig1 throws six balls (SHOOT002 each, WATER002
##   as they land) and bursts WATER008;
## - a special object (objcomd_motion.json `sounds`, hit run): objmPlaySound (0x4059b7) always
##   and objmPlayHitSound (0x4059cf, `hit_only`) only on a hit — 氣刃斬's impact bursts
##   obj_Special01_03 play WAV\BOMB0017.WAV as they appear.
## The patterned inserts (angle rings, tornado columns) keep their geometry instead of the
## track but take its sounds and multi-hit ops the same way: every instance runs the program
## (無想冥殺's ring obj_Special06_06 plays SHOOT008／BOMB0025 and sets the multi-hit counter,
## which the aniProcessHitMissMulti wait follows). A defense object's op 71／72 ticks go to
## `multi_hit_ops` (_multi_hit_wait). Objects without a track keep the static tables: obj_X1
## once per instruction at `sound_tick`, `program_sounds` and `command_sounds` at the
## insertion plus the read delay.
static func _insert_sounds(timeline: Dictionary, data: Dictionary, phase: String, object_name: String, object: Dictionary, tick: int, sound_tick: int) -> void:
	var cues: Array = []
	if not timeline.has("sound_order"):
		timeline["sound_order"] = {}
	var order: int = timeline["sound_order"].get(object_name, 0)
	if phase == "effect" and EffectObjectMotion.tracked(object_name):
		timeline["sound_order"][object_name] = order + 1
		for sound in EffectObjectMotion.sounds(object_name, order):
			cues.append({"member": str(sound[1]), "tick": tick + int(sound[0])})
	elif phase != "effect" and ObjcomdMotion.tracked(object_name):
		timeline["sound_order"][object_name] = order + 1
		for sound in ObjcomdMotion.sounds(object_name, order):
			cues.append({"member": str(sound[1]), "tick": tick + int(sound[0]), "hit_only": bool(sound[2])})
		if phase == "defense":
			for op in ObjcomdMotion.multi_hits(object_name, order):
				if not timeline.has("multi_hit_ops"):
					timeline["multi_hit_ops"] = []
				var created := sound_tick if sound_tick >= 0 and int(op[0]) == 0 and int(op[1]) == 71 else tick
				timeline["multi_hit_ops"].append([created + int(op[0]), int(op[1])])
				if int(op[1]) == 72: timeline["last_strike_tick"] = created + int(op[0])
	else:
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
			cues.append({"member": str(sound["member"]), "tick": tick + int(sound["delay_ticks"]), "hit_only": bool(sound["hit_only"])})
	for cue in cues:
		if not data["sounds"].has(cue["member"]):
			push_error("skill_effects manifest has no sound " + str(cue["member"]))
			continue
		var event := {"tick": int(cue["tick"]), "kind": "sound", "member": str(cue["member"]), "phase": phase}
		if cue.get("hit_only", false): event["hit_only"] = true
		timeline["events"].append(event)


## Presenter entry: compiles the row's timeline once per clip (seeded from the receipt, never
## the play loop's RNG), then drives the special cut-in or the map effect.
func present(host: CanvasLayer, clip: Dictionary, elapsed: float) -> bool:
	if not clip.has("effect_timeline"):
		var strike: Dictionary = clip["strike"]
		var skill_id := str(strike.get("skill_id", ""))
		var seed := hash(skill_id + str(strike.get("attacker_id", "")) + str(strike.get("defender_id", "")) + str(strike.get("hit_roll", strike.get("native_damage_roll", ""))))
		var parts: Array = strike.get("hit_segments", [])
		var strike_hits: Array = parts.map(func(part): return bool(part["hit"]))
		var last_strike := {} if parts.is_empty() else {"damage": int(parts.back()["actual_damage"]),
			"experience": parts.reduce(func(sum, part): return sum + int(part.get("experience_points", 0)), 0)}
		clip["effect_timeline"] = compile_row(skill_id, bool(strike["hit"]), seed, strike_hits, last_strike)
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
	var spawns := strike_spawns(clip["strike"], timeline, host.result_spawns(clip["strike"]))
	var closing := clip_closing_tick(timeline, spawns)
	if script_tick >= float(closing + Timing.CLOSING_LIGHTEN_TICKS):
		clear()
		return true
	if script_tick >= float(closing):
		# 0x404ada: teardown, 0x42c3f0(0) leaves the cut-in, 0x42dca0(1) lightens the map.
		clear()
		host.show_closing_lighten_ticks(script_tick - float(closing))
		return false
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
		host.defender_sprite.position = _defender_point(host, clip, script_tick)
		host.defender_sprite.modulate = Color.WHITE
		if double_page and _stand(host, host.attacker_sprite, clip["attacker"], 0, clip["attacker_unit"]):
			host.attacker_sprite.position = Vector2(160, CutinLayout.SHOT_ANCHOR.y)
			host.attacker_sprite.show()
	_place_on_defender(host, clip)
	draw(clip, script_tick / TICKS_PER_SECOND, [Vector2.ZERO])
	var shown := script_tick >= float(timeline["result_tick"])
	host.result.visible = shown
	if shown:
		host.show_result(clip["strike"], script_tick - float(timeline["result_tick"]), host.SCRIPT_NUMBER_POINT, spawns)
	# 0x404b23: the defense page's phase 101 darkens 16 ticks over the running shot.
	if script_tick >= float(timeline["darken_tick"]):
		host._show_closing_darken(script_tick - float(timeline["darken_tick"]))
	return false


## The defender object 0x4038a0's drawn point at script tick `tick`: its shot anchor (x 480
## from aniDoublePageMode) plus aniSetXYDisp, knock-back on a hit and the dodge slide on a
## miss from the impact on.
func _defender_point(host: CanvasLayer, clip: Dictionary, tick: float) -> Vector2:
	var timeline: Dictionary = clip["effect_timeline"]
	var double_page := int(timeline["double_page_tick"]) >= 0 and tick >= float(timeline["double_page_tick"])
	var point: Vector2 = (Vector2(480, CutinLayout.SHOT_ANCHOR.y) if double_page else host.defender_anchor(clip)) + timeline["xy_disp"]
	var row: Dictionary = host.manifest.get("actors", {}).get(clip["defender"], {})
	if tick >= float(timeline["impact_tick"]) and not row.is_empty():
		point.x += CutinLayout.reaction_x(row, bool(clip["strike"]["hit"]), tick - float(timeline["impact_tick"]), CutinLayout.side_swapped(clip["defender_unit"]))
	return point


## aniInsertHitRandomObjectDisp (0x403be2) reads the defender object's own x／y when it runs:
## its objects move from the neutral anchor they were compiled at onto the defender's drawn
## point at the insert tick, once per clip.
func _place_on_defender(host: CanvasLayer, clip: Dictionary) -> void:
	if clip.get("defender_placed", false):
		return
	clip["defender_placed"] = true
	for event in clip["effect_timeline"]["events"]:
		if event.has("defender_base"):
			event["position"] += _defender_point(host, clip, float(event["defender_tick"])) - (event["defender_base"] as Vector2)
			event.erase("defender_base")


## The numbers of a special shot, timed from its first result mark. A multi-hit receipt's
## strikes each spawn their own (0x4045d5 → 0x4084e0 the tick after the strike settles: the
## strike's HP loss — 0x4047eb clears the change words per strike), held back to their own
## result mark; any other receipt keeps `whole`. A strike that changed nothing — both change
## words, HP [0x4c6f74] and MP [0x4c6f78], zero (0x404611–0x404622; the hit flag is not read)
## — spawns no number unless it is the last (0x404626: [esp+0x14] is set only when the dword
## 0x4c6f68 reads zero at 0x4045fb); 0x404630 steps straight to sub-state 3. The last one
## spawns MISS (kind 5, 0x404664) unless the shot's experience [0x4c13f0] is non-zero
## (0x404656 → 0x404772, no number), as _last_strike_ticks times it.
static func strike_spawns(strike: Dictionary, timeline: Dictionary, whole: Array[Dictionary]) -> Array[Dictionary]:
	var parts: Array = strike.get("hit_segments", [])
	var marks: Array = timeline.get("result_ticks", [])
	if parts.is_empty() or marks.is_empty(): return whole
	var experience: int = parts.reduce(func(sum, part): return sum + int(part.get("experience_points", 0)), 0)
	var result: Array[Dictionary] = []
	for index in range(mini(parts.size(), marks.size())):
		var damage := int(parts[index]["actual_damage"])
		var offset := int(marks[index]) - int(marks[0])
		var miss := damage == 0 and index == parts.size() - 1 and experience == 0
		for entry in ResultNumberFloater.spawns(damage, 0, 0, miss):
			entry["hold"] = int(entry["hold"]) + offset
			result.append(entry)
	return result


## The tick the special shot ends: the lighten after `clip_closing_tick`.
static func clip_complete_tick(timeline: Dictionary, spawns: Array) -> int:
	return clip_closing_tick(timeline, spawns) + Timing.CLOSING_LIGHTEN_TICKS


## The tick the cut-in gives way to the map lighten: the compiled teardown, and not before
## the numbers aniShowHitResult spawned are deleted. 0x404643 (opcode 30, [esp+0x14] = 1) spawns the last
## number with the defender object as waiter and leaves its phase at 0x62 (0x403ecc) until that
## number releases it (+0x28 < 9, 0x408580) — for a red kind-0 number 27 ＋ 10×digits ticks —
## and the number lives on to 34 ＋ 10×digits (two digits: 47 and 54) while the shot closes. The
## remake keeps the darkened shot up until the last number's deletion
## (ResultNumberFloater.life_of) when that outlasts the teardown.
## `spawns` are the shot's result numbers (BattleCombatCutin.result_spawns).
static func clip_closing_tick(timeline: Dictionary, spawns: Array) -> int:
	var complete := int(timeline["complete_tick"])
	for entry in spawns:
		var digits := 1 if str(entry["kind"]) == "miss" else str(absi(int(entry["value"]))).length()
		complete = maxi(complete, int(timeline["result_tick"]) + ResultNumberFloater.life_of(str(entry["kind"]), digits, int(entry.get("hold", 0))))
	return complete


## A MAGIC script on the tactical map (MAGIC.TXT eff_proc_Local): no backdrop or close-up
## actors; the cast lead's shadow darkens the map (level 8／16 through the effect). First the camera glides to the
## caster (state 0, _caster_glide), then the caster's ANIMAL m_action cast
## lead (AnimalCastLead through the host, `cast_lead(clip, "magic")` — banner, insets and
## portrait from the m_shape strip over the shadowed map, tick-driven) when the caster has an
## imported strip, else the 預備動作-off lead (AnimalCastLead.skipped, 8 shadow calls); as it ends
## the caster poses (`released`), Cast_Star bursts over it and sfx 0x193 sounds, and the
## script waits out the pose (`caster_pose_ticks`, 8n + 40), then plays at every affected
## position (once at the cursor cell centre `map_target` for eff_proc_Global: 0x442b58 sets
## 0x4c2c70／0x4c2c74 to (column×32+16, row×32+16) and 0x442d81 builds one interpreter there once the camera
## has glided to that centre, _effect_centre_glide) with `impact` at its last cue; the
## effect carries no name caption. Real seconds, 62.5 ticks/s, after the lead.
func _present_effect(host: CanvasLayer, clip: Dictionary, elapsed: float) -> bool:
	var timeline: Dictionary = clip["effect_timeline"]
	var strike: Dictionary = clip["strike"]
	hide_actors(host)
	host.stage.size = Vector2(640, 480)
	host.scenery.visible = false
	host.vitals.visible = false
	# The whole effect plays over the live map: the cut-in's close-up backdrop and result stay
	# off from the first frame, so state 0's glide shows the map sliding and the AI's name
	# caption (BattleAttackCue, a lower CanvasLayer) stays visible under this layer.
	host.background.visible = false
	host.result.visible = false
	# State 0 (0x442ad1), every spell: the camera glides to the caster first (_caster_glide), the
	# AI's name caption still up while it glides; a spell with an effect_caster (0x4098e0
	# non-zero) then spends one more Local call (0x14 → 0x15, whose 0x43bf30 arrives at once and
	# builds the lead, 0x442f18). The clip's clock below starts after both.
	var caster: Dictionary = timeline.get("caster", {})
	if not clip.has("caster_glide"):
		clip["camera_glide"] = _caster_glide(host, clip)
		clip["caster_glide"] = float(clip["camera_glide"]) + (Timing.scaled(OriginalTick.seconds(CASTER_LOCAL_START_TICKS)) if not caster.is_empty() and not bool(timeline["global"]) else 0.0)
	# The arrival call still draws the caption before the VM leaves state 0: K + 1 calls.
	_hold_caption(host, clip, elapsed < float(clip["camera_glide"]) + Timing.scaled(OriginalTick.seconds(1)))
	if elapsed < float(clip["caster_glide"]):
		clear()
		return false
	elapsed -= float(clip["caster_glide"])
	# Every map spell builds the cast lead object 154 kind 1 (0x442a90 → 0x406d20 on each branch:
	# 0x442f26, 0x442c6c, 0x442cea); a caster with no lead frames takes the 預備動作-off jump
	# (0x401d6f → 0x401ec4) into sub-state 7 with the shadow bit set (0x401ed4), so the map is
	# shadowed whether or not the spell deals damage: level min(call + 1, 8) while +0x90 counts
	# (0x4030f7); from sub-state 5's call the effect phase holds it at 8 (host.begin_spell_phase).
	var lead_call := int(elapsed / Timing.PLAYBACK_SPEED * TICKS_PER_SECOND)
	# The spell's name captions the AI lead-in's range (BattleAttackCue.caption), not the effect:
	# the original's effect states (0x7a, 0x4419f8) draw no text (result hidden above).
	show()
	# A caster without an imported strip plays the 預備動作-off lead (the same 0x401ec4 jump);
	# with 預備動作 off the host hands out that lead for a caster with a strip too (0x401e74
	# tests only [0x477c14] & 2), so both take the skipped timing: posing on the 9th call,
	# shadow fade 8..0.
	var lead: Dictionary = host.cast_lead(clip, "magic")
	var skipped := lead.is_empty() or bool(lead.get("skipped", false))
	if skipped:
		lead = AnimalCastLead.skipped(true)
	var lead_end: float = Timing.scaled(OriginalTick.seconds(float(lead["complete_tick"])))
	# The call that enters sub-state 5 poses the caster (0x4071e0 sets +0x80 |= 0x1000 at
	# 0x40721b), bursts Cast_Star and sounds 0x193: a strip lead's last tail call (0x402fd1,
	# counted in TAIL_CALLS), the 預備動作-off lead's 9th call after its 8 states (0x403128).
	# Sub-state 5 (0x403089) runs on the next call, handing the flow back (parent +0x8c++,
	# 0x40309e): the effect VM states 4／7／0x17／0x19 set the effect phase from there and wait
	# only while the pose bit is set (0x442c89, 0x442d07, 0x442f65, 0x443009), 8n + 40 ticks
	# from the posing call. So the effect starts at the posing call's end + max(sub-state 5's
	# call, the pose).
	var posing_end := float(lead["complete_tick"]) + (1.0 if skipped else 0.0)
	var phase_at: float = Timing.scaled(OriginalTick.seconds(posing_end))
	var lead_in: float = Timing.scaled(OriginalTick.seconds(posing_end + maxf(SUB_STATE_5_TICKS, float(clip.get("caster_pose_ticks", 0)))))
	if elapsed < lead_end:
		host.shade_map(mini(lead_call + 1, AnimalCastLead.SHADOW_MAX_LEVEL))
		host.show_cast_lead(clip, lead, elapsed / Timing.PLAYBACK_SPEED * TICKS_PER_SECOND)
		clear()
		return false
	if not clip.get("cast_started", false):
		clip["cast_started"] = true
		host.ability_sound.stream = load(host.cue_manifest["sounds"]["cast_magic"]["res_path"])
		host.ability_sound.play()
		clip["cast_stars"] = cast_stars(hash(str(clip["strike"])))
		var controller: RefCounted = host.battle_camera()
		if controller != null and controller.camera != null and not clip.has("cast_camera"):
			clip["cast_camera"] = controller.camera.position
	if elapsed < phase_at:
		# The 預備動作-off lead's posing call: sub-state 7 still draws its shadow.
		host.shade_map(mini(lead_call + 1, AnimalCastLead.SHADOW_MAX_LEVEL))
	elif not clip.get("spell_phase_begun", false):
		# After the lead the attacker object stays: sub-state 5 drops the close-up bit and hides
		# it, sub-state 6 (0x4030b7) keeps its shadow while the effect phase [0x4c1b00] &
		# 0x1000000 holds — the one bit the shadow, the spell's lift and the shadows' hold read;
		# the script's op 0 (Global) or the relay after it (Local) clears it and the host fades
		# the shadow from +0x90: 7..0 after a strip lead, 8..0 after the 預備動作-off one (its
		# sub-state 7 leaves at +0x90 = 9, 0x4030fe).
		clip["spell_phase_begun"] = true
		host.begin_spell_phase(clip["strike"], AnimalCastLead.SHADOW_MAX_LEVEL if skipped else AnimalCastLead.SHADOW_MAX_LEVEL - 1)
	var star_origin: Vector2 = clip["map_caster"] - Vector2(0, float(clip.get("caster_height", CAST_STAR_DEFAULT_HEIGHT)))
	var star_tick: float = (elapsed - lead_end) / Timing.PLAYBACK_SPEED * TICKS_PER_SECOND
	if elapsed < lead_in:
		mark(host, clip, elapsed, {"release": lead_end, "impact": INF, "complete": INF})
		_draw_cast_stars(clip["cast_stars"], star_tick, star_origin - _view_shift(host, clip), 0)
		return false
	# effect_caster: states 4／0x17 build the caster object on the first pose-clear call
	# (0x442f77, lead_in), count +0x9e down one a call, then on the call that finds it at 0 set
	# 0x19 (Local) or glide Global to the effect centre 0x4c3860 and set 7 when it arrives
	# (0x442cba); 7／0x19 then run as they do without a caster, on the next call (wait_end).
	var wait_end := lead_in
	if not caster.is_empty():
		wait_end = lead_in + Timing.scaled(OriginalTick.seconds(int(caster["ticks"]) + CASTER_HANDOFF_TICKS))
		var glide_at: float = wait_end - (Timing.scaled(OriginalTick.seconds(1)) if bool(timeline["global"]) else 0.0)
		if elapsed < glide_at:
			mark(host, clip, elapsed, {"release": lead_end, "impact": INF, "complete": INF})
			var held := _view_shift(host, clip)
			_draw_cast_stars(clip["cast_stars"], star_tick, star_origin - held, _draw_caster(clip, elapsed - lead_in, held, 0))
			return false
	# eff_proc_Local's state 0x19 glides the camera to each receiver before it builds the effect
	# there, the first included (0x44301e: 0x43bf30 every tick, returning until it reports
	# arrival; a receiver inside the tolerance does not move it). eff_proc_Global glides to the
	# effect centre first (_effect_centre_glide, from wait_end, or from glide_at after an
	# effect_caster); its receivers' glides follow its effect (state 9, MagicImpactPresentation).
	if not clip.has("first_glide"):
		if bool(timeline["global"]):
			clip["first_glide"] = _effect_centre_glide(host, clip)
		else:
			clip["first_glide"] = _first_receiver_glide(host, clip)
	var effect_start: float = wait_end + float(clip["first_glide"])
	if elapsed < effect_start:
		mark(host, clip, elapsed, {"release": lead_end, "impact": INF, "complete": INF})
		var held := _view_shift(host, clip)
		_draw_cast_stars(clip["cast_stars"], star_tick, star_origin - held, _draw_caster(clip, elapsed - lead_in, held, 0))
		return false
	var seconds: float = (elapsed - effect_start) / Timing.PLAYBACK_SPEED
	var scale: float = Timing.PLAYBACK_SPEED / TICKS_PER_SECOND
	var complete := mark(host, clip, elapsed, {"release": lead_end,
		"impact": effect_start + float(timeline["impact_tick"]) * scale,
		"complete": effect_start + float(timeline["complete_tick"]) * scale})
	# The script's op 0 (script_end_tick) steps the cast routine on: eff_proc_Global's state 9
	# clears the effect phase at its entry (0x442da3); eff_proc_Local's relay holds it past its
	# last receiver's bars (host.release_spell_phase), clearing it here if those went first.
	if not clip.get("script_ended", false) and elapsed >= effect_start + float(timeline.get("script_end_tick", timeline["complete_tick"])) * scale:
		clip["script_ended"] = true
		if not host.spell_phase_held:
			host.end_spell_phase()
	_effect_view(host, clip, seconds * TICKS_PER_SECOND, complete)
	# The effect sits on the map: drawn back by every camera move since the release.
	var shift := _view_shift(host, clip)
	var origins: Array = []
	# Every map spell relays (MagicImpactPresentation.is_relayed, not preloaded: that script
	# preloads this one): its Local effect goes on the first receiver here, and the relay rebuilds
	# it on each later one after the camera reaches it (0x443087).
	var local_origins: Array = clip["affected_positions"].slice(0, 1) if clip["strike"].has("magic_key") else clip["affected_positions"]
	for origin in ([clip["map_target"]] if bool(timeline["global"]) else local_origins):
		origins.append(origin - shift)
	var used := _draw_caster(clip, elapsed - lead_in, shift, draw(clip, seconds, origins))
	_draw_cast_stars(clip["cast_stars"], star_tick, star_origin - shift, used)
	if complete:
		clear()
		return true
	return false


## eff_proc_Local's glide to the first receiver (state 0x19, 0x44301e) at the battle step,
## started now; its scaled seconds, 0 when the receiver is already within the tolerance.
func _first_receiver_glide(host: CanvasLayer, clip: Dictionary) -> float:
	var controller: RefCounted = host.battle_camera()
	if controller == null or controller.camera == null or not clip.has("cast_camera") or not clip["strike"].has("magic_key"):
		return 0.0
	var world: Vector2 = controller.logical_to_world(clip["affected_positions"][0] - _view_shift(host, clip))
	return Timing.scaled(controller.scroll_to(BattleCameraController.focus_centre(world), BattleCameraController.BATTLE_SCROLL_STEP))


## State 0's glide to the caster, every spell (0x442ad1: 0x43bf30(caster, 0) at 0x442ae7 each call,
## returning at 0x442af3 until it reports arrival; the arrival call sets Global 1 (0x44316f) or
## Local 0x14 (0x442bf1), which run on the next call) at the battle step, started now. The camera
## position is kept first, since the clip's logical positions were laid before it moves. Its
## scaled seconds are the calls that return 0 — the arrival call is the clip's tick 0, as the AI
## lead-in's camera stage counts it — so a camera already on the caster (the unit the player
## just picked, the AI's own camera stage) adds nothing.
func _caster_glide(host: CanvasLayer, clip: Dictionary) -> float:
	var controller: RefCounted = host.battle_camera()
	if controller == null or controller.camera == null:
		return 0.0
	clip["cast_camera"] = controller.camera.position
	var world: Vector2 = controller.logical_to_world(clip["map_caster"])
	return _unarrived_seconds(controller.scroll_to(BattleCameraController.focus_centre(world), BattleCameraController.BATTLE_SCROLL_STEP))


## eff_proc_Global's glide to the effect centre state 0 noted (the pseudo-object 0x4c3860, whose
## +4／+8 = 0x4c3864／0x4c3868 hold the target cell's centre, 0x442b5d／0x442b6d), started now:
## state 7 calls 0x43bf30 on it (0x442d10) after the pose and builds the effect on the arrival
## call (0x442d81); after an effect_caster wait the call that finds +0x9e at 0 glides first
## (0x442cba) and state 7, a call after the arrival, finds the camera there. Scaled seconds of
## the calls that return 0.
func _effect_centre_glide(host: CanvasLayer, clip: Dictionary) -> float:
	var controller: RefCounted = host.battle_camera()
	if controller == null or controller.camera == null or not clip.has("cast_camera"):
		return 0.0
	var world: Vector2 = controller.logical_to_world(clip["map_target"] - _view_shift(host, clip))
	return _unarrived_seconds(controller.scroll_to(BattleCameraController.focus_centre(world), BattleCameraController.BATTLE_SCROLL_STEP))


## A 0x43bf30 glide of `seconds` (BattleCameraController.scroll_to: its ticks with the arrival one,
## 0 for a target within the tolerance) as the scaled seconds of its calls that return 0.
static func _unarrived_seconds(seconds: float) -> float:
	return Timing.scaled(OriginalTick.seconds(maxi(roundi(OriginalTick.ticks(seconds)) - 1, 0)))


## The AI's name caption (BattleAttackCue.caption) stays up while state 0 glides: the AI target
## state 0x441947 draws it every call before it runs the cast VM, until the VM leaves state 0
## (then 0x4419f8 runs the VM alone). The player's cast state 0x7a draws none (the cue holds no
## caption for a player's strike).
func _hold_caption(host: CanvasLayer, clip: Dictionary, held: bool) -> void:
	if held != bool(clip.get("caption_held", false)) and host.has_signal("cast_caption_held"):
		clip["caption_held"] = held
		host.cast_caption_held.emit(held)


## The effect_caster object at the caster's cell, `since` scaled seconds after it was built
## (lead_in); sprites from `used` on, returning the next free one. Its sounds play once each.
func _draw_caster(clip: Dictionary, since: float, shift: Vector2, used: int) -> int:
	var caster: Dictionary = clip["effect_timeline"].get("caster", {})
	if caster.is_empty() or since < 0.0:
		return used
	return _draw_timeline(clip, caster, since / Timing.PLAYBACK_SPEED * TICKS_PER_SECOND, [clip["map_caster"] - shift], used, "caster_sounds_played")


## How far the battle camera has moved since the release (the first receiver's glide, the relay's
## glide, OtherBBall1's track): the logical positions laid at play time move back by it.
func _view_shift(host: CanvasLayer, clip: Dictionary) -> Vector2:
	var controller: RefCounted = host.battle_camera()
	if controller == null or controller.camera == null or not clip.has("cast_camera"):
		return Vector2.ZERO
	return controller.camera.position - clip["cast_camera"]


## The two effect objects that act on the whole view. effProcOtherBig (OtherBBall1) moves the
## battle camera by its 0x43bf30 track (EffectObjectMotion.camera_at), clamped to the map as
## 0x46bede does; the effect sprites, fixed on the map in the original, are drawn shifted
## back by the camera's actual move (_view_shift). At the script's op 0 the effect hands the
## camera back: it glides toward where the effect found it at the battle step, and
## eff_proc_Global's glide to its first receiver (state 9, 0x442dbd, MagicImpactPresentation)
## replaces that glide as it starts; the fading objects keep drawing without moving it.
## effProcIconBGSet (IconBGSet1／FireBGSet) lays its 0x461687 row offsets over the map and
## units (host.show_effect_ripple) from its first call until the effect phase ends: the object
## only deletes itself — and clears the ripple bit 0x400000 of [0x4c1cc0] (0x41d761) — once
## [0x4c1b00] & 0x1000000 is clear (host.spell_phase: Global's state 9 entry, as the script
## reaches op 0).
func _effect_view(host: CanvasLayer, clip: Dictionary, tick: float, complete: bool) -> void:
	var timeline: Dictionary = clip["effect_timeline"]
	var offset := Vector2.ZERO
	var ripple := {}
	for event in timeline["events"]:
		if event["kind"] != "object" or event.get("motion", "") != "native" or event.get("source", "") == "objcomd" or tick < float(event["tick"]):
			continue
		var frame := int(tick - float(event["tick"]))
		offset += EffectObjectMotion.camera_at(str(event["object"]), frame)
		var params := EffectObjectMotion.ripple_at(str(event["object"]), frame)
		if not params.is_empty():
			ripple = params
	host.show_effect_ripple({} if complete or not host.spell_phase else ripple)
	var camera: RefCounted = host.battle_camera()
	if camera == null or camera.camera == null or clip.get("camera_returned", false) or (offset == Vector2.ZERO and not clip.has("effect_camera_base")):
		return
	if not clip.has("effect_camera_base"):
		clip["effect_camera_base"] = camera.camera.position
	var base: Vector2 = clip["effect_camera_base"]
	if complete or clip.get("script_ended", false):
		# The camera is handed back once, at the script's op 0: the relay's glide to the first
		# receiver (state 9, 0x442dbd) then takes it over.
		clip["camera_returned"] = true
		camera.scroll_to(base)
		return
	camera.stop_scroll()
	camera.camera.position = camera.clamped_position(base + offset)


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
	var used := _draw_timeline(clip, clip["effect_timeline"], seconds * TICKS_PER_SECOND, origins, 0, "effect_sounds_played")
	for index in range(used, sprites.size()):
		sprites[index].hide()
	return used


func _draw_timeline(clip: Dictionary, timeline: Dictionary, tick: float, origins: Array, used: int, played_key: String) -> int:
	if not clip.has(played_key):
		clip[played_key] = []
	for index in range(timeline["events"].size()):
		var event: Dictionary = timeline["events"][index]
		if event["kind"] == "sound":
			if tick >= float(event["tick"]) and not clip[played_key].has(index):
				clip[played_key].append(index)
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
	var entries: Array = ObjcomdMotion.sprites_at(str(event["object"]), int(event["variant"]), frame, bool(event.get("hit", false))) if event.get("source", "") == "objcomd" \
		else EffectObjectMotion.sprites_at(EffectObjectMotion.track(str(event["object"]), int(event.get("variant", 0))), frame)
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
			sprite.rotation = float(entry.get("rotation", 0.0))
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


## 0x4593a0: the first channel that is empty or has stopped takes the sound; none free → dropped.
func _play(member: String) -> void:
	for player in sounds:
		if not player.playing:
			player.stream = load(manifest["sounds"][member]["res_path"])
			player.play()
			return


func clear() -> void:
	for sprite in sprites:
		sprite.hide()
	hide()
