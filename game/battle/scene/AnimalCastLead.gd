extends RefCounted
## The ANIMAL.TXT cast lead: the caster's own `s_action` program that stages the 絶技 cut-in
## before the EFFECTS attack script — the eye banner (strip panel 0) slides in over the
## shadowed map, the pose insets (panels from the cast object's start panel) step through
## at the upper corner, the portrait frames (panels 1 .. start−1) slide into the lower
## corner, the composition fades and holds. `compile` turns the program plus the strip's
## panel sizes into one state per original tick (one dispatcher call of the object process
## 0x401c20, slot 22 of 0x477c2c); BattleCombatCutin draws the state at the clip's tick.
## Every opcode the 37 live m_action／s_action programs use is in CAST_OPCODES (checked by
## field_coverage); a program with another opcode is refused by the importer, not skipped.
## The m_action programs share this shape over the m_shape strips (`magic_frames`／
## `magic_cast_program`): the map magic presenter plays them the same way. The lead leaves
## the original's afterimages (0x401220: an object 179 copy of the shape at level 6, faded by
## defProcShadowLeft 0x4010c0) and mirrors for an actor installed side-swapped (0x446be0).
## Nothing here owns combat truth.
## provenance:
##   layout: static-derived docs/evidence_packets/static_reverse/animal_program_execution.md#8-施法引导程序m_actions_action的解释
##   layout: resource-derived content/generated/hsl/animation/animal_programs.json
##   layout: static-derived docs/evidence_packets/static_reverse/original_effect_motion.md
##   layout: static-derived docs/evidence_packets/static_reverse/original_cast_overlays.md#施法引导的合成
##     (shadow in bucket 0x17 over map and units < 0x17; lifted units over it, BattleCombatCutin.shade_map)
##   layout: provisional (planeEffect2 < 0x32 by PROCESS.DEF order)
##   timing: static-derived docs/evidence_packets/static_reverse/animal_program_execution.md#8-施法引导程序m_actions_action的解释
##   timing: static-derived docs/evidence_packets/runtime_observations/system_menu/README.md (預備動作 off)
##   timing: resource-derived content/generated/hsl/animation/animal_programs.json
##   timing: static-derived docs/evidence_packets/static_reverse/original_effect_motion.md
##   timing: provisional (±1 call where the afterimage order differs)
const CommandPresentationRules = preload("res://game/battle/runtime/CommandPresentationRules.gd")
## The same spelling as the importer's cast-program validation (combat_animation.CAST_OPCODES).
const CAST_OPCODES := ["aniSetXYDisp", "aniShadowBG", "aniMoveToCenter", "aniInsertCastObject"]
## 0x401ce1／0x402771: the caster object starts at and slides to base + (0x140, 0xf0).
const CENTRE := Vector2i(320, 240)
## 0x402752: phase 12 counts +0x90 up to 8 after the call that set it.
const SHADOW_BG_CALLS := 8
## 0x4035ef: while the message word carries 0x1000 the object draws the all-black screen
## shape [0x4bbb4e] in bucket 0x17 with mode 0x20000000 (crossfade, 0x4699fd) at level
## min(+0x90, 8) — the map and units below keep (16 − level)／16 of each component.
const SHADOW_MAX_LEVEL := 8
## 0x402771／0x402ac9／0x402d27 call 0x45e80d with tolerance 16 and maximum step 32.
const SLIDE_TOLERANCE := 16
const SLIDE_STEP := 32
## 0x4025c0／0x402c58 (+0x64): the near corner's edge; 0x4025ff／0x402c0b (+0x21c／+0x1e0):
## the far corner's right and bottom edges; 0x402c19: a portrait wider than 440 is centred.
const NEAR_EDGE := 100
const FAR_RIGHT_EDGE := 540
const PORTRAIT_BOTTOM := 480
const PORTRAIT_CENTRED_WIDTH := 440
const SCREEN_WIDTH := 640
## 0x402517／0x402e30: the last portrait frame holds delay2 + 20.
const LAST_PORTRAIT_BONUS := 20
## 0x402e49 (+0x84 counts to 16; mode 0, the panels stay opaque — 0x402e55) and
## 0x402d3a／0x402ef5 (+0xa0 = 10 calls counted down, then the 11th call reads 0x4c1408 at
## 0x402f0b: a 絶技 leaves for phase 103 after it, a spell steps +0x84 to 17).
const FADE_CALLS := 16
const HOLD_CALLS := 11
## A spell's crossfade tail (0x402f5e): mode 0x20000000 at level +0x28 (16 from 0x402d44);
## 0x4c6f70 = 0x20002 (0x402d4b) takes one level and steps +0x84 every 2 calls, so +0x84
## 17..31 hold 2 calls each at level 33 − +0x84 (16 → 2) and +0x84 = 32 draws level 1 in
## the one call that enters sub-state 5 (0x402fac: pose 0x4071e0, Cast_Star 0x408b20, sfx
## 0x193) — the lead ends there and the spell is released.
const TAIL_CALLS := 31
## 0x403052: every sub-state-4 call also draws the object's own shape +0x86 (BALL001) at the
## screen centre, bucket 0x33, mode 0x2c000000 (level-scaled saturating add, zoom — 0x46b6b1
## kind 9, T[level] on the source at 0x4623e1), zoom 0x48000 on both axes, level = +0x84
## (0..16) — 32 − +0x84 in the tail (15 → 0).
const GLOW_ZOOM := 4.5
## 0x401220 → object 179 at level 6 (+0x28); defProcShadowLeft (0x4010c0) takes one level
## every 4 calls (+0x90 = 0x40004) and destroys the copy at level 0.
const AFTERIMAGE_LEVEL := 6
const AFTERIMAGE_STEP_CALLS := 4
const AFTERIMAGE_CALLS := AFTERIMAGE_LEVEL * AFTERIMAGE_STEP_CALLS
const LEVELS := 16.0
## 預備動作 off ([0x477c14] bit1 clear, 0x401e74 → 0x401ec4, the same jump as a caster with no
## lead frames): the program never runs and the object is hidden (+0x30 = 0xffff). A spell
## (kind 1) sets the shadow bit and counts +0x90 to 9 in sub-state 7 (0x4030f7), posing and
## bursting Cast_Star on the 9th call; a 絶技 (kind 2) waits sub-states 8／9 (0x403199／
## 0x4031c7): the setup call, the 16-count and the 10-call hold, then releases phase 103.
const SKIPPED_MAGIC_CALLS := 8
## Sub-state 9 draws the same centred glow (0x403245／0x403484) and reads 0x4c1408 on its
## 11th call at +0x84 = 16 (0x403201).
const SKIPPED_SPECIAL_CALLS := 1 + FADE_CALLS + HOLD_CALLS


## The strip panel metrics the lead needs: `[{"size": Vector2i, "origin": Vector2i}]` from the
## combat manifest's `special_frames` (`draw_origin`) and their textures.
static func panel_metrics(frames: Array, textures: Array) -> Array:
	var panels: Array = []
	for index in range(frames.size()):
		var frame: Dictionary = frames[index]
		panels.append({"size": Vector2i((textures[index] as Texture2D).get_size()), "origin": Vector2i(int(frame["draw_origin"][0]), int(frame["draw_origin"][1]))})
	return panels


## The lead a caster plays with 預備動作 off: SKIPPED_* calls with the caster object hidden
## (`hidden`), no inset, portrait or afterimage, the map shadowed only for a spell.
static func skipped(magic: bool) -> Dictionary:
	var states: Array = []
	for call in range(SKIPPED_MAGIC_CALLS if magic else SKIPPED_SPECIAL_CALLS):
		# A spell's first call sets 0x1000 and the sub-state 7 count (+0x90 = 1, 0x401ee1 then
		# 0x4030f7); the dispatcher passes the word read before the call, so the shadow shows
		# from the next call at level min(call + 1, 8).
		var shadow := mini(call + 1, SHADOW_MAX_LEVEL) if magic and call > 0 else 0
		var glow := 0 if magic or call == 0 else mini(call - 1, FADE_CALLS)
		states.append({"banner": CENTRE, "hidden": true, "mirrored": false, "shadow": shadow, "inset": -1, "inset_anchor": Vector2i.ZERO, "portrait": -1, "portrait_anchor": Vector2i.ZERO, "fade": 0.0, "glow": glow, "afterimages": []})
	return {"states": states, "complete_tick": states.size(), "strip": []}


## True when `program` is a cast lead this module can play against `panel_count` strip
## panels: only CAST_OPCODES, one aniInsertCastObject whose start panel leaves at least one
## inset and one portrait frame (panels 1 .. start−1 and start .. count−1).
static func playable(program: Array, panel_count: int) -> bool:
	var cast_objects := 0
	for instruction in program:
		var op := str(instruction["op"])
		if not CAST_OPCODES.has(op):
			return false
		if op == "aniInsertCastObject":
			cast_objects += 1
			var start := int(instruction["args"][2])
			if start < 2 or start >= panel_count:
				return false
	return cast_objects == 1 and not program.is_empty()


## One state per dispatcher call. Keys: `banner` (anchor of panel 0, the caster object),
## `mirrored` (the caster object's x zoom is −1), `shadow` (the shadow level 0..8 of 16 over
## the map from aniShadowBG on), `inset`／`portrait` (panel index or −1) with
## `inset_anchor`／`portrait_anchor`, `fade` (1 − level／16 of the panels' crossfade: 0 through
## sub-state 4's opaque calls, rising in a spell's tail), `glow` (the centred BALL001 add
## level 0..16, sub-state 4 only) and `afterimages`
## ([{panel, anchor, level, mirrored}], level 6 → 1). Anchors are the screen positions of each
## panel's SHP draw origin. `complete_tick` is the number of states; the attack script follows.
## `mirrored` is the caster's side-swap flag (unit `side_swapped`): 0x401ddf sets the object's
## x zoom to −1 and aniSetXYDisp (0x4021b8) negates its x displacement. `magic` (kind 1, an
## m_action lead) adds the crossfade tail after the hold; a 絶技 (kind 2) ends on the 11th.
static func compile(program: Array, panels: Array, mirrored: bool = false, magic: bool = false) -> Dictionary:
	var states: Array = []
	var state := {"banner": CENTRE, "mirrored": mirrored, "shadow": 0, "inset": -1, "inset_anchor": Vector2i.ZERO, "portrait": -1, "portrait_anchor": Vector2i.ZERO, "fade": 0.0, "glow": 0, "ghosts": []}
	var offset := Vector2i.ZERO
	for instruction in program:
		var args: Array = instruction["args"]
		match str(instruction["op"]):
			"aniSetXYDisp":
				# 0x402180: as the first opcode of a call it leaves an afterimage of the caster
				# object where it stands (0x402187), then adds the displacement — x negated for a
				# side-swapped actor — and keeps decoding in the same call.
				_leave_afterimage(states, state, 0, state["banner"], mirrored)
				offset += Vector2i(-int(args[0]) if mirrored else int(args[0]), int(args[1]))
				state["banner"] = CENTRE + offset
			"aniShadowBG":
				# 0x402499 sets the shadow flag and phase 12 (one call); 0x402752 counts 8 more.
				# The flag reaches the message word on the next call, drawn at +0x90 = 1..8.
				_emit(states, state, 1)
				for level in range(1, SHADOW_BG_CALLS + 1):
					state["shadow"] = mini(level, SHADOW_MAX_LEVEL)
					_emit(states, state, 1)
			"aniMoveToCenter":
				# 0x4024c1 enters phase 13 (one call); 0x402771 steps toward the centre per call.
				_emit(states, state, 1)
				while state["banner"] != CENTRE:
					state["banner"] = CommandPresentationRules.opening_step(state["banner"], CENTRE, SLIDE_TOLERANCE, SLIDE_STEP)
					_emit(states, state, 1)
			"aniInsertCastObject":
				_cast_object(states, state, panels, int(args[0]) < 0, int(args[2]), int(args[3]), int(args[4]), magic)
	return {"states": states, "complete_tick": states.size()}


## aniInsertCastObject [xdisp][ydisp][shp1 disp][delay1][delay2] → phase 102 (0x4024d3): only
## the sign of xdisp is read (0x4025bc, the near corner's side); the start panel, delay1 and
## delay2 drive the sub-states below.
static func _cast_object(states: Array, state: Dictionary, panels: Array, from_left: bool, first_inset: int, inset_delay: int, portrait_delay: int, magic: bool) -> void:
	# The setup call.
	_emit(states, state, 1)
	# Sub-state 0 (0x402a5c): the first inset slides from off-screen to the near corner's
	# top edge — drawn at the pre-step position each call, one 0x45e80d(16,32) step per call.
	var inset: Dictionary = panels[first_inset]
	state["inset"] = first_inset
	state["inset_anchor"] = _near_start(inset, from_left)
	_slide(states, state, "inset_anchor", Vector2i(_near_edge_x(inset, from_left), inset["origin"].y))
	# Sub-state 1 (0x402afe): every panel from the start panel holds delay1 calls (+0x7c
	# counts down, reloads from +0x7e, the remaining count +0xa0 = panels − start); on the
	# call a panel expires with panels still to come, 0x402b68 leaves its afterimage (layer
	# 0x33, at the inset anchor) before the next panel shows.
	for panel in range(first_inset, panels.size()):
		state["inset"] = panel
		if panel == panels.size() - 1 or inset_delay <= 0:
			_emit(states, state, inset_delay)
			continue
		_emit(states, state, inset_delay - 1)
		_leave_afterimage(states, state, panel, state["inset_anchor"], false)
		_emit(states, state, 1)
	# Sub-state 2 (0x402c87): the portrait (panel 0 + 1) slides from the far side to the far
	# corner's bottom edge; a portrait wider than 440 is centred (0x402c19).
	var portrait: Dictionary = panels[1]
	var portrait_target := Vector2i(_far_edge_x(portrait, from_left), PORTRAIT_BOTTOM - portrait["size"].y + portrait["origin"].y)
	state["portrait"] = 1
	state["portrait_anchor"] = Vector2i(_far_start_x(portrait, from_left), portrait_target.y)
	_slide(states, state, "portrait_anchor", portrait_target)
	# Sub-state 3 (0x402d79): the portrait frames 1 .. start−1 hold delay2 calls each
	# (0x4c6fa8 counts down, 0x4c6f5c the frames left); the last one holds delay2 + 20.
	for panel in range(1, first_inset):
		state["portrait"] = panel
		_emit(states, state, portrait_delay + (LAST_PORTRAIT_BONUS if first_inset - panel <= 1 else 0))
	# Sub-state 4 (0x402e47): 16 calls at mode 0 (both panels opaque, 0x402e55) with the
	# centred glow at level +0x84, then 10 calls and the 11th that reads 0x4c1408 at 16.
	for call in range(FADE_CALLS):
		state["glow"] = call
		_emit(states, state, 1)
	state["glow"] = FADE_CALLS
	_emit(states, state, HOLD_CALLS)
	if not magic:
		return
	# A spell's tail: the panels crossfade out (level 16 → 1) as the glow fades (15 → 0).
	for call in range(TAIL_CALLS):
		var step := 17 + int(call / 2)
		state["fade"] = 1.0 - float(33 - step) / LEVELS
		state["glow"] = 32 - step
		_emit(states, state, 1)


static func _slide(states: Array, state: Dictionary, key: String, target: Vector2i) -> void:
	while true:
		_emit(states, state, 1)
		state[key] = CommandPresentationRules.opening_step(state[key], target, SLIDE_TOLERANCE, SLIDE_STEP)
		if state[key] == target:
			return


## The near corner: the left edge at x 100 for a program entering from the left
## (0x4025c0), the right edge at 540 from the right (0x4025ff).
static func _near_edge_x(panel: Dictionary, from_left: bool) -> int:
	return NEAR_EDGE + panel["origin"].x if from_left else FAR_RIGHT_EDGE - panel["size"].x + panel["origin"].x


## One panel width outside the near side: 0x4025c0 (base − width + origin) or 0x4025ff
## (base + 640 + origin).
static func _near_start(panel: Dictionary, from_left: bool) -> Vector2i:
	return Vector2i(panel["origin"].x - panel["size"].x if from_left else SCREEN_WIDTH + panel["origin"].x, panel["origin"].y)


## The far corner for the portrait: the right edge at 540 (centred when wider than 440)
## for a program entering from the left (0x402c0b), the left edge at 100 from the right
## (0x402c58).
static func _far_edge_x(panel: Dictionary, from_left: bool) -> int:
	if from_left:
		return CENTRE.x if panel["size"].x > PORTRAIT_CENTRED_WIDTH else FAR_RIGHT_EDGE - panel["size"].x + panel["origin"].x
	return NEAR_EDGE + panel["origin"].x


static func _far_start_x(panel: Dictionary, from_left: bool) -> int:
	return SCREEN_WIDTH + panel["origin"].x if from_left else panel["origin"].x - panel["size"].x


## 0x401220 during the call about to be emitted: the copy is drawn from that call on (the
## creator clears its skip bit, 0x401269) at AFTERIMAGE_LEVEL.
static func _leave_afterimage(states: Array, state: Dictionary, panel: int, anchor: Vector2i, mirrored: bool) -> void:
	state["ghosts"].append({"panel": panel, "anchor": anchor, "born": states.size(), "mirrored": mirrored})


static func _emit(states: Array, state: Dictionary, calls: int) -> void:
	for _call in range(calls):
		var snapshot := state.duplicate()
		snapshot.erase("ghosts")
		var shown: Array = []
		for ghost in state["ghosts"]:
			var age: int = states.size() - int(ghost["born"])
			if age >= 0 and age < AFTERIMAGE_CALLS:
				shown.append({"panel": ghost["panel"], "anchor": ghost["anchor"], "level": AFTERIMAGE_LEVEL - int(age / AFTERIMAGE_STEP_CALLS), "mirrored": ghost["mirrored"]})
		snapshot["afterimages"] = shown
		states.append(snapshot)
