extends "res://tests/support/TestSuite.gd"
## The cut-in plays each actor's own ANIMAL.TXT program. The expectations here are computed
## from content/generated/hsl/animation/animal_programs.json (the source programs) with the
## documented dispatcher call model (animal_program_execution.md §5／§8), never from the
## manifest's compiled dispatch — so a stale binding or a hand-authored pose fails.
const Cutin = preload("res://game/battle/scene/BattleCombatCutin.gd")
const CastLead = preload("res://game/battle/scene/AnimalCastLead.gd")
const PresentationRules = preload("res://game/battle/runtime/CommandPresentationRules.gd")
const Timing = preload("res://game/battle/runtime/CombatPresentationTiming.gd")
const OriginalTick = preload("res://game/battle/runtime/OriginalTick.gd")
const BattleFixture = preload("res://tests/support/BattleFixture.gd")
const PROGRAMS_PATH := "res://content/generated/hsl/animation/animal_programs.json"
## One dispatcher call per step, a hair over a tick so accumulated float error never lands a
## sample just before the boundary it is meant to have crossed.
const STEP := OriginalTick.TICK_SECONDS * (1.0 + 1e-4)
var programs: Dictionary


func _init() -> void:
	tag = "ANIMAL_PROGRAM_TESTS"


func unit(actor_id: String) -> Dictionary:
	for actor in BattleFixture.loop()["units"]:
		if str(actor["actor_id"]) == actor_id:
			return actor.duplicate(true)
	assert(false, "missing actor fixture " + actor_id)
	return {}


func record(code: String) -> Dictionary:
	for row in programs["records"]:
		if str(row["code"]) == code:
			return row
	assert(false, "missing ANIMAL record " + code)
	return {}


## The frame visible after each dispatcher call of an ordinary `action` program, from the
## probe-measured call model: aniDelay D occupies the setup call plus max(D,1) waiting calls
## (its successor is first visible at index max(D,1)+2), aniSetShape yields after its call,
## aniInsertAttackFlash and the speed setters continue／yield as compile_action reads them.
func expected_action_frames(program: Array) -> Dictionary:
	var frames: Array[int] = []
	var frame := 0
	var release_call := -1
	for instruction in program:
		var args: Array = instruction["args"]
		match str(instruction["op"]):
			"aniDelay":
				for _call in range(1 + maxi(1, int(args[0]))):
					frames.append(frame)
			"aniSetShape":
				frame = int(args[0])
				frames.append(frame)
			"aniInsertAttackFlash":
				release_call = frames.size() + 1
			"aniSetSubSpeed", "aniSetAddSpeed", "aniSetStopSpeed":
				frames.append(frame)
			_:
				assert(false, "unexpected ordinary opcode " + str(instruction["op"]))
	return {"frames": frames, "release_call": release_call}


func ordinary_program_drives_the_cutin(actor_id: String, code: String, defender_id: String) -> void:
	var expected := expected_action_frames(record(code)["programs"]["action"])
	var cutin := Cutin.new()
	root.add_child(cutin)
	cutin.configure("res://content/imported/hsl/chapter01/combat_animation/manifest.json")
	cutin.set_process(false)
	var release_marks: Array[int] = []
	cutin.released.connect(func(_s, _a, _d, _c): release_marks.append(int(round(OriginalTick.ticks(cutin.elapsed)))))
	var attacker := unit(actor_id)
	var defender := unit(defender_id)
	cutin.play({"hit": true, "damage": 5, "defender_hp_before": 22, "defender_hp_after": 17}, attacker, defender, false)
	var seen: Array[int] = []
	var schedule := Timing.ordinary(cutin.manifest["actors"][actor_id], cutin.clips[0]["strike"])
	var calls: int = expected["frames"].size()
	# The first shot's phase-100 opening (56 ticks) precedes the program's first call.
	cutin._process(float(schedule["opening"]) * 0.25 / Timing.PLAYBACK_SPEED)
	_assert_true(cutin.opening_ball.visible and not cutin.attacker_sprite.visible and not cutin.defender_sprite.visible, "%s: the opening's zoom draws fill the screen before the program, attacker hidden" % code)
	cutin._process(float(schedule["opening"]) * 0.75 / Timing.PLAYBACK_SPEED)
	_assert_true(not cutin.opening_ball.visible and cutin.attacker_sprite.visible and absf(cutin.elapsed - float(schedule["opening"])) < 1e-6, "%s: the program starts as the opening ends" % code)
	release_marks.clear()
	# Call k (1-based) is visible once elapsed reaches k ticks; sample the frame just after
	# each call but the last (the last wait's end hands over to the target shot).
	for call in range(1, calls):
		cutin._process(STEP)
		var path: String = cutin.attacker_sprite.texture.resource_path
		seen.append(int(path.get_file().get_basename()))
	_assert_eq(seen, expected["frames"].slice(0, calls - 1), "%s: the cut-in's attacker frames follow the ANIMAL action program call by call" % code)
	_assert_true(cutin.attacker_sprite.visible and not cutin.defender_sprite.visible and cutin.elapsed < float(schedule["target"]), "%s: the attacker's shot lasts through call %d" % [code, calls - 1])
	cutin._process(STEP * 2)
	_assert_true(cutin.defender_sprite.visible and not cutin.attacker_sprite.visible, "%s: the target shot follows the program's %d calls" % [code, calls])
	_assert_eq(release_marks, [int(expected["release_call"]) + Timing.OPENING_TICKS], "%s: `released` fires once, at the aniInsertAttackFlash call after the opening" % code)
	var poses: Array[int] = []
	for frame in seen:
		if poses.is_empty() or poses.back() != frame:
			poses.append(frame)
	var source_poses: Array[int] = [0]
	for instruction in record(code)["programs"]["action"]:
		if str(instruction["op"]) == "aniSetShape" and int(instruction["args"][0]) != source_poses.back():
			source_poses.append(int(instruction["args"][0]))
	_assert_eq(poses, source_poses, "%s: the pose order is the source aniSetShape order" % code)
	while cutin.busy():
		cutin._process(0.1)
	cutin.queue_free()
	await process_frame


## 雷歐納德 (SID_PLAYER0: 12／8／3 waits, poses 1／2／3, flash before the last pose, 30-tick
## tail) and the 帝國一般兵 021 (SID_ENEMY021: 12／3／12／30) play their own programs.
func ordinary_programs() -> void:
	await ordinary_program_drives_the_cutin("001", "SID_PLAYER0", "021")
	await ordinary_program_drives_the_cutin("021", "SID_ENEMY021", "001")
	var leonard := expected_action_frames(record("SID_PLAYER0")["programs"]["action"])
	_assert_eq(leonard["frames"].size(), 60, "雷歐納德's action program is 60 dispatcher calls")
	_assert_eq(leonard["release_call"], 29, "雷歐納德's flash is the 29th call")
	var soldier := expected_action_frames(record("SID_ENEMY021")["programs"]["action"])
	_assert_true(soldier["frames"] != leonard["frames"], "the soldier's program differs from 雷歐納德's — the cut-in does not share one hand-written sequence")


## The 0x45e80d slide as the cast lead calls it (tolerance 16, step 32), independent of the
## menu's (2, 8) defaults: 640 px take 21 calls (19 × 32, one 16, then the snap).
func slide_calls(from: Vector2i, to: Vector2i) -> int:
	var calls := 0
	var at := from
	while at != to:
		at = PresentationRules.opening_step(at, to, CastLead.SLIDE_TOLERANCE, CastLead.SLIDE_STEP)
		calls += 1
		assert(calls < 1000)
	return calls


## The 氣刃斬 cast lead of 雷歐納德: ANIMAL.TXT lines 14–15 (aniSetXYDisp −640,0 · aniShadowBG ·
## aniMoveToCenter · aniInsertCastObject −160,−150,2,6,6) against the 7-panel P001_201 strip.
func cast_lead_program() -> void:
	var row := record("SID_PLAYER0")
	var program: Array = row["programs"]["s_action"]
	var cutin := Cutin.new()
	root.add_child(cutin)
	cutin.configure("res://content/imported/hsl/chapter01/combat_animation/manifest.json")
	cutin.set_process(false)
	var actor: Dictionary = cutin.manifest["actors"]["001"]
	_assert_eq(actor["cast_program"].map(func(i): return [str(i["op"]), i["args"]]), program.map(func(i): return [str(i["op"]), i["args"]]), "the combat manifest carries 001's s_action verbatim")
	_assert_eq(int(row["fields"]["s_number"]["value"]), actor["special_frames"].size(), "the strip has the source s_number panels")
	var cast_object: Dictionary = program.filter(func(i): return str(i["op"]) == "aniInsertCastObject")[0]
	var first_inset := int(cast_object["args"][2])
	var inset_delay := int(cast_object["args"][3])
	var portrait_delay := int(cast_object["args"][4])
	var displacement := Vector2i(int(program[0]["args"][0]), int(program[0]["args"][1]))
	_assert_eq(str(program[0]["op"]), "aniSetXYDisp", "the program opens with the displacement")
	var strike := {"skill_id": "special:magicOTHER:magicCode01", "skill_name": "氣刃斬", "attacker_id": "leonard", "defender_id": "enemy021_1", "hit": true, "damage": 9, "defender_hp_before": 22, "defender_hp_after": 13, "attacker_before": {}, "defender_before": {}}
	cutin.play(strike, unit("001"), unit("021"), false)
	var lead: Dictionary = cutin.cast_lead(cutin.clips[0])
	var states: Array = lead["states"]
	var panels: Array = CastLead.panel_metrics(actor["special_frames"], actor["special_frames"].map(func(frame): return load(frame["res_path"])))
	# Expected call counts from the program's numbers and the handler constants.
	var banner_start: Vector2i = CastLead.CENTRE + displacement
	var move_calls := slide_calls(banner_start, CastLead.CENTRE)
	_assert_eq(move_calls, 21, "aniMoveToCenter from −640 takes 21 steps of 0x45e80d(16,32)")
	var inset: Dictionary = panels[first_inset]
	var inset_target := Vector2i(CastLead.NEAR_EDGE + inset["origin"].x, inset["origin"].y)
	var inset_calls := slide_calls(Vector2i(inset["origin"].x - inset["size"].x, inset["origin"].y), inset_target)
	var portrait: Dictionary = panels[1]
	var portrait_target := Vector2i(CastLead.FAR_RIGHT_EDGE - portrait["size"].x + portrait["origin"].x, CastLead.PORTRAIT_BOTTOM - portrait["size"].y + portrait["origin"].y)
	var portrait_calls := slide_calls(Vector2i(CastLead.SCREEN_WIDTH + portrait["origin"].x, portrait_target.y), portrait_target)
	var inset_count := panels.size() - first_inset
	var portrait_hold := 0
	for panel in range(1, first_inset):
		portrait_hold += portrait_delay + (CastLead.LAST_PORTRAIT_BONUS if first_inset - panel <= 1 else 0)
	var expected_total := (1 + CastLead.SHADOW_BG_CALLS) + (1 + move_calls) + 1 + inset_calls + inset_count * inset_delay + portrait_calls + portrait_hold + CastLead.FADE_CALLS + CastLead.HOLD_CALLS
	_assert_eq(int(lead["complete_tick"]), expected_total, "the lead's call count is the sum the program's numbers give (%d)" % expected_total)
	_assert_eq(int(lead["complete_tick"]), 139, "雷歐納德's 氣刃斬 lead is 139 ticks")
	# Phase by phase.
	for call in range(1 + CastLead.SHADOW_BG_CALLS):
		_assert_true(states[call]["shadow"] and states[call]["banner"] == banner_start and int(states[call]["inset"]) < 0, "call %d: shadow background, banner still displaced, no inset" % call)
	var at := 1 + CastLead.SHADOW_BG_CALLS
	_assert_eq(states[at]["banner"], banner_start, "the aniMoveToCenter call itself does not move")
	_assert_eq(states[at + 1]["banner"], banner_start + Vector2i(CastLead.SLIDE_STEP, 0), "the first slide call steps 32 px")
	_assert_eq(states[at + move_calls]["banner"], CastLead.CENTRE, "the banner arrives at (320,240)")
	at += 1 + move_calls + 1
	_assert_eq(int(states[at]["inset"]), first_inset, "the cast object's first inset is the program's start panel (%d)" % first_inset)
	_assert_true(states[at]["inset_anchor"].x < 0, "the inset starts off-screen on the displacement's side")
	at += inset_calls
	_assert_true(states[at - 1]["inset_anchor"] != inset_target and states[at]["inset_anchor"] == inset_target, "each slide call draws before it steps; the inset stands with its left edge at x 100 and top at 0 from the next call")
	for index in range(inset_count):
		for call in range(inset_delay):
			_assert_eq(int(states[at + index * inset_delay + call]["inset"]), first_inset + index, "inset panel %d holds delay1 = %d calls" % [first_inset + index, inset_delay])
	at += inset_count * inset_delay
	_assert_eq(int(states[at]["portrait"]), 1, "the portrait (panel 1) enters after the insets")
	_assert_true(states[at]["portrait_anchor"].x >= CastLead.SCREEN_WIDTH, "the portrait starts off-screen on the far side")
	at += portrait_calls
	_assert_true(states[at - 1]["portrait_anchor"] != portrait_target and states[at]["portrait_anchor"] == portrait_target, "the portrait stands with its right edge at 540 and bottom at 480 from the call after its slide")
	_assert_eq(states[at + portrait_hold - 1]["fade"], 0.0, "the portrait holds delay2 + 20 = %d calls before the fade" % portrait_hold)
	_assert_eq(states[at + portrait_hold + CastLead.FADE_CALLS - 1]["fade"], 1.0, "the fade completes over 16 calls")
	_assert_eq(states.size() - (at + portrait_hold + CastLead.FADE_CALLS), CastLead.HOLD_CALLS, "then the 10-call hold ends the lead")
	# The special presenter plays the lead first, then the attack script: 氣刃斬's 60-tick
	# attack script releases at lead + 60.
	var release_marks: Array[int] = []
	cutin.released.connect(func(_s, _a, _d, _c): release_marks.append(int(round(OriginalTick.ticks(cutin.elapsed)))))
	var banner_seen := false
	var inset_seen := false
	var portrait_seen := false
	var frames := 0
	while cutin.busy() and frames < 1000:
		frames += 1
		cutin._process(STEP)
		if frames < int(lead["complete_tick"]):
			banner_seen = banner_seen or (cutin.attacker_sprite.visible and cutin.attacker_sprite.texture.resource_path.ends_with("001/special-0.png") and cutin.attacker_sprite.position == Vector2(320, 240))
			inset_seen = inset_seen or (cutin.cast_inset.visible and cutin.cast_inset.texture.resource_path.ends_with("001/special-%d.png" % first_inset) and cutin.cast_inset.position == Vector2(inset_target))
			portrait_seen = portrait_seen or (cutin.cast_portrait.visible and cutin.cast_portrait.texture.resource_path.ends_with("001/special-1.png") and cutin.cast_portrait.position == Vector2(portrait_target))
			_assert_true(not cutin.scenery.visible and not cutin.vitals.visible and cutin.stage.size == Vector2(640, 480), "during the lead the map shows through a 640×480 stage without backdrop or vitals")
		elif frames == int(lead["complete_tick"]) + 1:
			_assert_true(cutin.scenery.visible and not cutin.cast_inset.visible and not cutin.cast_portrait.visible and not cutin.attacker_sprite.visible, "after the lead the attack script owns the shot: special backdrop, no cast panels, no standing caster")
	_assert_true(banner_seen and inset_seen and portrait_seen, "the banner, an inset and the portrait were drawn at their anchors (%s %s %s)" % [str(banner_seen), str(inset_seen), str(portrait_seen)])
	_assert_eq(release_marks, [int(lead["complete_tick"]) + 60], "氣刃斬 releases once, after the lead plus its 60-tick attack script")
	cutin.queue_free()
	await process_frame


## The expected call count of a cast lead from the program's numbers and the handler
## constants (the same sum cast_lead_program checks phase by phase for 雷歐納德).
func expected_lead_calls(program: Array, panels: Array) -> int:
	var cast_object: Dictionary = program.filter(func(i): return str(i["op"]) == "aniInsertCastObject")[0]
	var first_inset := int(cast_object["args"][2])
	var displacement := Vector2i(int(program[0]["args"][0]), int(program[0]["args"][1]))
	var move_calls := slide_calls(CastLead.CENTRE + displacement, CastLead.CENTRE)
	var inset: Dictionary = panels[first_inset]
	var inset_calls := slide_calls(Vector2i(inset["origin"].x - inset["size"].x, inset["origin"].y), Vector2i(CastLead.NEAR_EDGE + inset["origin"].x, inset["origin"].y))
	var portrait: Dictionary = panels[1]
	var portrait_target := Vector2i(CastLead.FAR_RIGHT_EDGE - portrait["size"].x + portrait["origin"].x, CastLead.PORTRAIT_BOTTOM - portrait["size"].y + portrait["origin"].y)
	var portrait_calls := slide_calls(Vector2i(CastLead.SCREEN_WIDTH + portrait["origin"].x, portrait_target.y), portrait_target)
	var portrait_hold := 0
	for panel in range(1, first_inset):
		portrait_hold += int(cast_object["args"][4]) + (CastLead.LAST_PORTRAIT_BONUS if first_inset - panel <= 1 else 0)
	return (1 + CastLead.SHADOW_BG_CALLS) + (1 + move_calls) + 1 + inset_calls + (panels.size() - first_inset) * int(cast_object["args"][3]) + portrait_calls + portrait_hold + CastLead.FADE_CALLS + CastLead.HOLD_CALLS


## The magic cast lead: 緹娜's m_action (SID_PLAYER1: aniSetXYDisp −640,0 · aniShadowBG ·
## aniMoveToCenter · aniInsertCastObject −160,−150,2,4,4 over the 7-panel P002_101 strip) plays
## through the map magic presenter before the effCode script — the same AnimalCastLead as the
## 絕技 lead; `released` fires at its end and the script clock starts there. A caster without
## an imported m_shape strip (026, whose m_shape is commented out) keeps the Cast_Star ring.
func magic_cast_lead_program() -> void:
	var row := record("SID_PLAYER1")
	var program: Array = row["programs"]["m_action"]
	var cutin := Cutin.new()
	root.add_child(cutin)
	cutin.configure("res://content/imported/hsl/chapter01/combat_animation/manifest.json")
	cutin.set_process(false)
	var actor: Dictionary = cutin.manifest["actors"]["002"]
	_assert_eq(actor["magic_cast_program"].map(func(i): return [str(i["op"]), i["args"]]), program.map(func(i): return [str(i["op"]), i["args"]]), "the combat manifest carries 002's m_action verbatim")
	_assert_eq(int(row["fields"]["m_number"]["value"]), actor["magic_frames"].size(), "the magic strip has the source m_number panels")
	_assert_eq(actor["magic_frames"][0]["source_member"], str(row["fields"]["m_shape"]["token"]), "panel 0 is the m_shape member")
	var strike := {"skill_id": "magic:magicAIR:magicCode01", "magic_key": "wind", "magic_name": "風刃", "attacker_id": "tina", "defender_id": "enemy021_1", "hit": true, "damage": 5, "defender_hp_before": 30, "defender_hp_after": 25, "attacker_before": {}, "defender_before": {}}
	var tina := unit("001")
	tina["actor_id"] = "002"
	cutin.play(strike, tina, unit("021"), false, Vector2(470, 320), Vector2(190, 210), [Vector2(470, 320)])
	var lead: Dictionary = cutin.cast_lead(cutin.clips[0], "magic")
	_assert_true(not lead.is_empty() and cutin.cast_lead(cutin.clips[0]).is_empty(), "002 has a magic lead and no special lead (its s_shape strip is not imported)")
	var panels: Array = CastLead.panel_metrics(actor["magic_frames"], actor["magic_frames"].map(func(frame): return load(frame["res_path"])))
	var expected_total := expected_lead_calls(program, panels)
	_assert_eq(int(lead["complete_tick"]), expected_total, "the magic lead's call count is the sum the program's numbers give (%d)" % expected_total)
	_assert_eq(expected_lead_calls(record("SID_PLAYER0")["programs"]["s_action"], CastLead.panel_metrics(cutin.manifest["actors"]["001"]["special_frames"], cutin.manifest["actors"]["001"]["special_frames"].map(func(frame): return load(frame["res_path"])))), 139, "the same sum gives 雷歐納德's 139")
	var cast_object: Dictionary = program.filter(func(i): return str(i["op"]) == "aniInsertCastObject")[0]
	var first_inset := int(cast_object["args"][2])
	var release_marks: Array[int] = []
	var impact_marks: Array[int] = []
	cutin.released.connect(func(_s, _a, _d, _c): release_marks.append(int(round(OriginalTick.ticks(cutin.elapsed)))))
	cutin.impact.connect(func(_s, _a, _d, _c): impact_marks.append(int(round(OriginalTick.ticks(cutin.elapsed)))))
	var banner_seen := false
	var inset_seen := false
	var portrait_seen := false
	var star_seen := false
	var objects_seen := false
	var frames := 0
	while cutin.busy() and frames < 3000:
		frames += 1
		cutin._process(STEP)
		if frames < int(lead["complete_tick"]):
			banner_seen = banner_seen or (cutin.attacker_sprite.visible and cutin.attacker_sprite.texture.resource_path.ends_with("002/magic-0.png") and cutin.attacker_sprite.position == Vector2(320, 240))
			inset_seen = inset_seen or (cutin.cast_inset.visible and cutin.cast_inset.texture.resource_path.ends_with("002/magic-%d.png" % first_inset))
			portrait_seen = portrait_seen or (cutin.cast_portrait.visible and cutin.cast_portrait.texture.resource_path.ends_with("002/magic-1.png"))
			star_seen = star_seen or cutin.skill_effects.sprites.any(func(sprite): return sprite.visible and str(sprite.texture.resource_path).contains("cast_star"))
			_assert_true(not cutin.scenery.visible and not cutin.vitals.visible and cutin.stage.size == Vector2(640, 480) and not cutin.result.visible, "during the magic lead the map shows through a 640×480 stage, with no name caption (the spell's name captions only the AI lead-in range)")
		elif frames == int(lead["complete_tick"]) + 1:
			_assert_true(not cutin.cast_inset.visible and not cutin.cast_portrait.visible and not cutin.attacker_sprite.visible, "after the lead the effCode script owns the map shot")
		else:
			objects_seen = objects_seen or cutin.skill_effects.sprites.any(func(sprite): return sprite.visible and str(sprite.texture.resource_path).contains("skill_effects/frames/"))
	var timeline: Dictionary = cutin.clips[0]["effect_timeline"] if cutin.busy() else {}
	_assert_true(banner_seen and inset_seen and portrait_seen and not star_seen and objects_seen, "the m_shape banner, an inset and the portrait were drawn, no Cast_Star ring, then the script's objects (%s %s %s %s %s)" % [str(banner_seen), str(inset_seen), str(portrait_seen), str(star_seen), str(objects_seen)])
	_assert_eq(release_marks, [int(lead["complete_tick"])], "the spell releases once, when its m_action lead ends")
	_assert_true(impact_marks.size() == 1 and impact_marks[0] > int(lead["complete_tick"]), "impact follows the lead (%s)" % str(impact_marks))
	_assert_true(not cutin.busy() and timeline.is_empty(), "the magic clip completes")
	cutin.play(strike, unit("026"), unit("021"), false, Vector2(470, 320), Vector2(190, 210), [Vector2(470, 320)])
	_assert_true(cutin.cast_lead(cutin.clips[0], "magic").is_empty() and cutin.manifest["actors"]["026"]["magic_frames"].is_empty() and cutin.manifest["actors"]["026"]["magic_cast_program"].is_empty(), "026 declares no m_action (commented out in ANIMAL.TXT) and no strip")
	cutin._process(STEP * 5)
	_assert_true(cutin.skill_effects.sprites.any(func(sprite): return sprite.visible and str(sprite.texture.resource_path).contains("cast_star")), "a caster without a magic strip keeps the Cast_Star stand-in lead")
	while cutin.busy():
		cutin._process(0.1)
	for actor_id in cutin.manifest["actors"]:
		var manifest_row: Dictionary = cutin.manifest["actors"][actor_id]
		if not manifest_row["magic_frames"].is_empty():
			_assert_true(CastLead.playable(manifest_row["magic_cast_program"], manifest_row["magic_frames"].size()), "%s: imported magic strip with a playable m_action" % actor_id)
	cutin.queue_free()
	await process_frame


## A caster whose s_action program exists but whose strip is not in the combat manifest (002:
## its P002_201 strip is the moon-dance import) keeps the standing caster — the manifest's
## declared per-actor gap, not a silent global fallback. 004 漢克斯, whose P004_201…203 strip is
## imported, compiles its s_action lead over it.
func caster_without_strip() -> void:
	var cutin := Cutin.new()
	root.add_child(cutin)
	cutin.configure("res://content/imported/hsl/chapter01/combat_animation/manifest.json")
	cutin.set_process(false)
	var actor: Dictionary = cutin.manifest["actors"]["002"]
	_assert_true(not actor["cast_program"].is_empty() and actor["special_frames"].is_empty(), "002 declares an s_action but no strip in the combat manifest")
	var tina := unit("001")
	tina["actor_id"] = "002"
	var strike := {"skill_id": "special:magicOTHER:magicCode02", "skill_name": "連續突刺", "attacker_id": "a", "defender_id": "b", "hit": true, "damage": 6, "defender_hp_before": 22, "defender_hp_after": 16, "attacker_before": {}, "defender_before": {}}
	cutin.play(strike, tina, unit("021"), false)
	_assert_true(cutin.cast_lead(cutin.clips[0]).is_empty(), "no lead is compiled for a caster without a strip")
	cutin._process(STEP * 5)
	_assert_true(cutin.attacker_sprite.visible and cutin.attacker_sprite.texture.resource_path.ends_with("002/0.png") and cutin.scenery.visible, "the attack phase shows the standing caster over the backdrop")
	while cutin.busy():
		cutin._process(0.1)
	var hanks := unit("001")
	hanks["actor_id"] = "004"
	cutin.play(strike, hanks, unit("021"), false)
	var lead: Dictionary = cutin.cast_lead(cutin.clips[0])
	_assert_true(not lead.is_empty() and str(lead["row"]) == "004" and lead["strip"] == cutin.manifest["actors"]["004"]["special_frames"], "004 compiles its s_action lead over the imported P004 strip")
	while cutin.busy():
		cutin._process(0.1)
	# Every actor with an imported strip has a playable lead; every program in ANIMAL.TXT's
	# m_action／s_action channels uses only the four cast opcodes.
	var manifest_actors: Dictionary = cutin.manifest["actors"]
	for actor_id in manifest_actors:
		var row: Dictionary = manifest_actors[actor_id]
		if not row["special_frames"].is_empty():
			_assert_true(CastLead.playable(row["cast_program"], row["special_frames"].size()), "%s: imported strip with a playable cast program" % actor_id)
	cutin.queue_free()
	await process_frame
	var cast_ops := {}
	for row in programs["records"]:
		for channel in ["m_action", "s_action"]:
			for instruction in row["programs"].get(channel, []):
				cast_ops[str(instruction["op"])] = true
	_assert_eq(cast_ops.keys().size(), CastLead.CAST_OPCODES.size(), "the live cast programs use exactly the interpreted opcodes (%s)" % str(cast_ops.keys()))
	for op in cast_ops:
		_assert_true(CastLead.CAST_OPCODES.has(op), "cast opcode interpreted: " + op)


## The cast lead's afterimages and the side mirror, from the handler constants: 0x401220
## copies the object's shape at level 6 (0x40124e) and defProcShadowLeft (0x4010c0) takes one
## level every 4 calls (+0x90 = 0x40004, 0x40126f) — 24 calls; aniSetXYDisp leaves one of the
## banner where it stands as the call's first opcode (0x402187), every inset panel that
## expires with panels to come leaves one at the inset anchor (0x402b68). A side-swapped actor
## (obj_Data9 ≠ 0: 0x407ec0 sets live +0xa0 bit 8, 0x446be0 reads it) draws the banner with x
## zoom −1 (0x401ddf) and enters from the other side (x displacement negated, 0x4021b8).
func cast_lead_afterimages_and_mirror() -> void:
	var row := record("SID_PLAYER0")
	var program: Array = row["programs"]["s_action"]
	var cutin := Cutin.new()
	root.add_child(cutin)
	cutin.configure("res://content/imported/hsl/chapter01/combat_animation/manifest.json")
	cutin.set_process(false)
	var actor: Dictionary = cutin.manifest["actors"]["001"]
	var panels: Array = CastLead.panel_metrics(actor["special_frames"], actor["special_frames"].map(func(frame): return load(frame["res_path"])))
	var cast_object: Dictionary = program.filter(func(i): return str(i["op"]) == "aniInsertCastObject")[0]
	var first_inset := int(cast_object["args"][2])
	var inset_delay := int(cast_object["args"][3])
	var displacement := Vector2i(int(program[0]["args"][0]), int(program[0]["args"][1]))
	var plain: Dictionary = CastLead.compile(program, panels)
	var states: Array = plain["states"]
	# The banner's afterimage: at (320,240) from call 0, level 6 for 4 calls, then one less
	# every 4, gone at call 24.
	for call in range(26):
		var banner_ghosts: Array = states[call]["afterimages"].filter(func(ghost): return int(ghost["panel"]) == 0)
		if call < 24:
			_assert_true(banner_ghosts.size() == 1 and banner_ghosts[0]["anchor"] == CastLead.CENTRE and int(banner_ghosts[0]["level"]) == 6 - int(call / 4) and not bool(banner_ghosts[0]["mirrored"]), "call %d: the banner's afterimage stands at (320,240) at level %d" % [call, 6 - int(call / 4)])
		else:
			_assert_true(banner_ghosts.is_empty(), "call %d: the banner's afterimage is gone after 24 calls" % call)
	# Each inset panel but the last leaves an afterimage on the call it expires.
	var inset: Dictionary = panels[first_inset]
	var inset_target := Vector2i(CastLead.NEAR_EDGE + inset["origin"].x, inset["origin"].y)
	var arrive := -1
	for call in range(states.size()):
		if int(states[call]["inset"]) == first_inset and states[call]["inset_anchor"] == inset_target:
			arrive = call
			break
	var inset_count := panels.size() - first_inset
	for index in range(inset_count):
		var expiry: int = arrive + index * inset_delay + inset_delay - 1
		var ghosts: Array = states[expiry]["afterimages"].filter(func(ghost): return int(ghost["panel"]) == first_inset + index)
		if index < inset_count - 1:
			_assert_true(ghosts.size() == 1 and ghosts[0]["anchor"] == inset_target and int(ghosts[0]["level"]) == 6, "inset panel %d leaves a level-6 afterimage at the inset anchor on its last call" % (first_inset + index))
			_assert_true(states[expiry + 1]["afterimages"].any(func(ghost): return int(ghost["panel"]) == first_inset + index) and int(states[expiry + 1]["inset"]) == first_inset + index + 1, "the next panel shows over the fading copy")
		else:
			_assert_true(ghosts.is_empty(), "the last inset panel leaves no afterimage")
	_assert_eq(int(plain["complete_tick"]), 139, "the afterimages do not change the 139-call lead")
	# The mirror: same length, banner from the right, drawn flipped.
	var mirrored: Dictionary = CastLead.compile(program, panels, true)
	_assert_eq(int(mirrored["complete_tick"]), int(plain["complete_tick"]), "a mirrored lead takes the same calls")
	_assert_true(mirrored["states"][0]["banner"] == CastLead.CENTRE + Vector2i(-displacement.x, displacement.y) and bool(mirrored["states"][0]["mirrored"]) and bool(mirrored["states"][0]["afterimages"][0]["mirrored"]), "a side-swapped caster's banner starts at x %d (displacement negated) and is drawn mirrored, its afterimage too" % (CastLead.CENTRE.x - displacement.x))
	# The host: a side_swapped unit gets the mirrored lead; the banner sprite flips, the
	# afterimage draws at level／16.
	var strike := {"skill_id": "special:magicOTHER:magicCode01", "skill_name": "氣刃斬", "attacker_id": "leonard", "defender_id": "enemy021_1", "hit": true, "damage": 9, "defender_hp_before": 22, "defender_hp_after": 13, "attacker_before": {}, "defender_before": {}}
	var swapped := unit("001")
	swapped["side_swapped"] = true
	cutin.play(strike, swapped, unit("021"), false)
	var lead: Dictionary = cutin.cast_lead(cutin.clips[0])
	_assert_true(bool(lead["states"][0]["mirrored"]), "cast_lead reads the unit's side_swapped")
	cutin.show_cast_lead(cutin.clips[0], lead, 0.0)
	var ghost_sprites: Array = cutin.cast_afterimages.filter(func(sprite): return sprite.visible)
	_assert_true(cutin.attacker_sprite.scale == Vector2(-1, 1) and ghost_sprites.size() == 1 and is_equal_approx(ghost_sprites[0].modulate.a, 6.0 / 16.0) and ghost_sprites[0].scale == Vector2(-1, 1) and ghost_sprites[0].position == Vector2(CastLead.CENTRE), "the mirrored banner flips and its afterimage draws at 6/16 at (320,240)")
	cutin.clips.clear()
	cutin.play(strike, unit("001"), unit("021"), false)
	cutin.show_cast_lead(cutin.clips[0], cutin.cast_lead(cutin.clips[0]), 0.0)
	_assert_true(cutin.attacker_sprite.scale == Vector2.ONE, "an ordinary caster's banner is not flipped")
	cutin.queue_free()
	await process_frame


func run() -> void:
	programs = JSON.parse_string(FileAccess.get_file_as_string(PROGRAMS_PATH))
	await ordinary_programs()
	await cast_lead_program()
	await magic_cast_lead_program()
	await caster_without_strip()
	await cast_lead_afterimages_and_mirror()
	# The script player's sounds (氣刃斬／連續突刺) must stop before the batch quits.
	await settle_wall_clock(tree, 0.4)
