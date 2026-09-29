extends "res://tests/support/TestSuite.gd"
## SkillEffectScriptPlayer: EFFECTS.TXT specCode (special) and effCode (magic) scripts → tick
## timelines, without a scene. Green here proves the interpreter's contract over the tracked
## scripts and manifest, not the original clock or geometry (both provisional; see
## skill_effects/manifest.json policy).
const AdditiveLevelBlend = preload("res://game/battle/scene/AdditiveLevelBlend.gd")
const SkillEffectScriptPlayer = preload("res://game/battle/scene/SkillEffectScriptPlayer.gd")
const PoisonArrowRules = preload("res://game/sim/PoisonArrowRules.gd")
const RepeatedSpecialRules = preload("res://game/sim/RepeatedSpecialRules.gd")
const MultiHitSpecialRules = preload("res://game/sim/MultiHitSpecialRules.gd")
const EffectObjectMotion = preload("res://game/battle/scene/EffectObjectMotion.gd")
const ObjcomdMotion = preload("res://game/battle/scene/ObjcomdMotion.gd")
var manifest: Dictionary
var scope: Dictionary
var motion: Dictionary


func _init() -> void:
	tag = "SKILL_EFFECT_SCRIPT_TESTS"


func run() -> void:
	manifest = JSON.parse_string(FileAccess.get_file_as_string(SkillEffectScriptPlayer.MANIFEST_PATH))
	scope = JSON.parse_string(FileAccess.get_file_as_string(SkillEffectScriptPlayer.SCRIPTS_PATH))
	motion = JSON.parse_string(FileAccess.get_file_as_string(EffectObjectMotion.PATH))
	manifest_contracts()
	parse_contracts()
	every_row_compiles()
	every_magic_row_compiles()
	qi_blade_timeline()
	object_command_sounds()
	effect_program_sounds()
	thunder_sword_timeline()
	geometry_and_flags()
	magic_timelines()
	effect_random_insertion()
	native_motion_tracks()
	native_motion_drawing()
	await run_animal_program()
	await run_cutin_floaters()


## The importer's declarations and the player's spelling agree; every SPECIAL and MAGIC row
## has one presentation and the two dedicated rows are the ids the cut-in routes to modules.
func manifest_contracts() -> void:
	check(SkillEffectScriptPlayer.IMPLEMENTED_OPCODES.size() == 28 and scope["opcode_counts"].keys().all(func(op): return SkillEffectScriptPlayer.IMPLEMENTED_OPCODES.has(op)), "every opcode the 99 rows use is implemented (24 ani* + 4 eff*)")
	check(scope["effect_verbs"] == ["effWait", "effInsertObject", "effInsertRandomObject", "effPlaySound"] and scope["magic_opcode_counts"].keys().all(func(op): return scope["effect_verbs"].has(op)), "the 39 magic scripts use only the four effects.h verbs: %s" % str(scope["magic_opcode_counts"]))
	check(scope["totals"]["effect_blocks"] == 169 and scope["totals"]["rows_special"] == 60 and scope["totals"]["rows_magic"] == 39, "EFFECTS.TXT: 169 [effect] blocks = 130 specCode (60 special rows) + 39 effCode (39 magic rows)")
	check(manifest["rows"].keys() == scope["rows"].keys(), "manifest declares a presentation for exactly the scope's rows")
	var counts := {"script": 0, "dedicated_module": 0, "borrowed_qi_blade": 0}
	for skill_id in manifest["rows"]:
		var row: Dictionary = manifest["rows"][skill_id]
		counts[str(row["presentation"])] += 1
		check(row["channel"] == scope["rows"][skill_id]["channel"], "row channel mirrors the scope: " + skill_id)
		if row["channel"] == "special":
			check(row["attack_code"] == scope["rows"][skill_id]["attack_code"] and row["defense_code"] == scope["rows"][skill_id]["defense_code"], "row codes mirror the scope: " + skill_id)
		else:
			check(row["effect_code"] == scope["rows"][skill_id]["effect_code"] and row["effect_proc"] == scope["rows"][skill_id]["effect_proc"] and row["presentation"] == "script", "magic row mirrors the scope's effCode／effect_proc and plays its script: " + skill_id)
	check(counts == {"script": 97, "dedicated_module": 2, "borrowed_qi_blade": 0}, "97 rows (58 special + 39 magic) play their script, 2 keep their dedicated module, none borrows 氣刃斬: %s" % str(counts))
	check(manifest["rows"][PoisonArrowRules.ID]["presentation"] == "dedicated_module" and str(manifest["rows"][PoisonArrowRules.ID]["module"]) == "PoisonArrowPresentation.gd", "毒魔箭 keeps PoisonArrowPresentation")
	check(manifest["rows"][RepeatedSpecialRules.ID]["presentation"] == "dedicated_module" and str(manifest["rows"][RepeatedSpecialRules.ID]["module"]) == "MoonDancePresentation.gd", "月花圓舞 keeps MoonDancePresentation")
	check(manifest["unresolved_objects"] == ["obj_Special51_05"] and not manifest["objects"].has("obj_Special51_05"), "the OBJ-ALL.H-less object is declared unresolved, not invented")
	# The imported members are the scope objects' shapes plus every member a native effect
	# track draws (the sparks and bullets the effProc* programs spawn); a name hsl.pak lacks is
	# declared missing (negative-evidence), never dropped.
	var script_members := {}
	for name in scope["objects"]:
		for member in scope["objects"][name]["shape_members"]:
			script_members[member] = true
	for member in motion["members"]:
		check(manifest["frames"].has(member) or manifest["missing_members"].has(member), "every native track member is imported or declared missing: " + str(member))
	# The native objcomd.txt runs are native tracks too: a special object's thrown children draw
	# members no script names (objcomd_motion.json variants／hit_variants).
	var objcomd_drawn := _objcomd_drawers()
	for member in manifest["missing_members"]:
		check(script_members.has(member) or motion["members"].has(member) or objcomd_drawn.has(member), "a missing member is named by a scope object or a native track: " + str(member))
		check(not manifest["frames"].has(member), "missing and imported are disjoint: " + str(member))
		if not script_members.has(member):
			var drawers: Array = _tracked_drawers(member) if motion["members"].has(member) else objcomd_drawn.get(member, [])
			check(drawers.size() > 0 and drawers.all(func(name): return motion["objects"].has(name) or ObjcomdMotion.packet()["objects"].has(name)), "a track-only missing member is drawn only by tracked objects (the player cycles its series): " + str(member))
	check(manifest["missing_members"].filter(func(member): return str(member).begins_with("MAGIC\\SP08_")).size() == 40, "the 40 SP08 shape names hsl.pak lacks stay declared missing (negative-evidence)")
	for name in manifest["objects"]:
		var object: Dictionary = manifest["objects"][name]
		check(int(object["frame_ticks"]) == int(object["shape_delay"]) + 1, "frame_ticks is shape_delay + 1: " + name)
		check(object["shape_members"].any(func(member): return manifest["frames"].has(member)), "every object has at least one imported frame: " + name)
		check(object["zoom"].size() == 2 and float(object["zoom"][0]) != 0.0 and float(object["zoom"][1]) != 0.0, "every object carries its obj_ZoomX／Y scale (obj_Special43_06 mirrors with −1): " + name)
		check(str(object["insert_sound"]) == "" or manifest["sounds"].has(object["insert_sound"]), "an obj_X1 insertion WAV is imported: " + name)
	check(manifest["objects"]["obj_Effect_FireBomb"]["zoom"] == [1.25, 1.25] and manifest["objects"]["obj_Effect_AirBlade1"]["insert_sound"] == "WAV\\WIND0001.WAV" and manifest["objects"]["obj_Effect_AirBlade1"]["effect_process"] == "effProcFade", "obj_Effect_FireBomb reads engZOOM 0x14000 as 1.25; obj_Effect_AirBlade1 plays WIND0001 on insertion and names its unrestored effProcFade program")
	check(manifest["totals"]["frames"] == manifest["frames"].size() and manifest["totals"]["missing_members"] == manifest["missing_members"].size() and manifest["totals"]["sounds"] == 131 and manifest["totals"]["objects"] == 373, "totals mirror the frame／missing sets; 131 sounds (111 script／obj_X1 + 7 objcomd-only + 6 effect-program-only + 7 only in the native runs' records), 373 objects (221 special + 152 magic)")


## The tracked objects whose native tree draws `member`.
func _tracked_drawers(member: String) -> Array:
	var index: int = motion["members"].find(member)
	var names: Array = []
	for name in motion["objects"]:
		for instance in motion["objects"][name]["instances"]:
			if int(instance["start"]) >= 0 and instance["member"].any(func(run): return int(run[0]) == index):
				names.append(name)
				break
	return names


## member -> the scope objects whose native objcomd.txt run draws it (any variant, hit or miss run).
func _objcomd_drawers() -> Dictionary:
	var packet: Dictionary = ObjcomdMotion.packet()
	var drawers := {}
	for name in packet["objects"]:
		if not scope["objects"].has(name):
			continue
		var row: Dictionary = packet["objects"][name]
		for instances in row.get("variants", []) + row.get("hit_variants", []):
			for instance in instances:
				for run in instance.get("member", []):
					if int(run[0]) >= 0:
						var member := str(packet["members"][int(run[0])])
						if not drawers.has(member):
							drawers[member] = []
						if not drawers[member].has(name):
							drawers[member].append(name)
	return drawers


## parse() yields one instruction per ani*／eff* token, in source order, with the tokens up to
## the next verb as its arguments — so the instruction count equals the row's opcode occurrences.
func parse_contracts() -> void:
	var parsed := SkillEffectScriptPlayer.parse(["aniDelay,20,aniInsertObject,obj_Special01_02,700,160", "aniDelay,10,aniProcessHitMiss"])
	check(parsed.size() == 4 and parsed[1]["op"] == "aniInsertObject" and parsed[1]["args"] == ["obj_Special01_02", "700", "160"] and parsed[3]["args"] == [], "instructions split at each ani* token and keep argument order")
	var effect := SkillEffectScriptPlayer.parse(["effInsertObject,obj_Effect_AirBlade1,0,0,effWait,10", "effPlaySound,WAV\\WIND0001.WAV"])
	check(effect.size() == 3 and effect[0]["args"] == ["obj_Effect_AirBlade1", "0", "0"] and effect[1] == {"op": "effWait", "args": ["10"]} and effect[2]["args"] == ["WAV\\WIND0001.WAV"], "eff* verbs open instructions the same way")
	check(SkillEffectScriptPlayer.number("-0x00000800") == -2048 and SkillEffectScriptPlayer.number("0x00c60000") == 12976128 and SkillEffectScriptPlayer.number("-100") == -100 and is_equal_approx(SkillEffectScriptPlayer.fixed16("0x00018000"), 1.5), "hex, negative hex and decimal arguments parse")
	var total := 0
	for skill_id in scope["rows"]:
		var row: Dictionary = scope["rows"][skill_id]
		var expected := 0
		var got := 0
		for code in row["actions"]:
			got += SkillEffectScriptPlayer.parse(row["actions"][code]).size()
			for line in row["actions"][code]:
				for token in str(line).split(","):
					if str(token).strip_edges().begins_with("ani") or str(token).strip_edges().begins_with("eff"):
						expected += 1
		check(got == expected, "instruction count equals the row's opcode occurrences: %s (%d vs %d)" % [skill_id, got, expected])
		total += got
	var counted := 0
	for op in scope["opcode_counts"]:
		counted += int(scope["opcode_counts"][op])
	check(total == counted and total > 1000, "all rows together parse to the scope's opcode_counts total (%d)" % total)


## Every `script` row compiles for hit and miss: no unimplemented verb, ordered marks,
## every drawn object／sound／backdrop imported, only obj_Special51_05 skipped, deterministic
## under one seed, and the instruction count preserved.
func every_row_compiles() -> void:
	var player := SkillEffectScriptPlayer.new()
	root.add_child(player)
	var skipped_rows: Array[String] = []
	for skill_id in manifest["rows"]:
		if manifest["rows"][skill_id]["presentation"] != "script" or manifest["rows"][skill_id]["channel"] != "special":
			continue
		for hit in [true, false]:
			var timeline: Dictionary = player.compile_row(skill_id, hit, 7)
			var again: Dictionary = player.compile_row(skill_id, hit, 7)
			var other: Dictionary = player.compile_row(skill_id, hit, 8)
			check(timeline["unimplemented"].is_empty(), "no unimplemented verb: " + skill_id)
			check(str(timeline) == str(again), "same seed, same timeline: " + skill_id)
			# 0x401370／0x4c1404: the teardown deletes the objects, so a random insert (0x401390) whose drawn delay overtakes it never appears — only the script's own events are seed-independent.
			var fixed := func(events: Array) -> int: return events.filter(func(event): return not event.get("random", false)).size()
			check(fixed.call(timeline["events"]) == fixed.call(other["events"]), "the seed changes placements and which random inserts beat the teardown, not the script's own events: " + skill_id)
			var release := int(timeline["release_tick"])
			var impact := int(timeline["impact_tick"])
			var result := int(timeline["result_tick"])
			var complete := int(timeline["complete_tick"])
			check(release > 0 and release <= impact and impact <= result and result < complete, "release ≤ impact ≤ result < complete: %s %s" % [skill_id, str([release, impact, result, complete])])
			check(not timeline["hit_ticks"].is_empty(), "every defense script marks its hit: " + skill_id)
			check(not timeline["result_ticks"].is_empty() or result == impact, "a script without aniShowHitResult shows the result on the hit mark: " + skill_id)
			check(complete >= result + SkillEffectScriptPlayer.RESULT_HOLD_TICKS, "the result stays readable: " + skill_id)
			var row: Dictionary = scope["rows"][skill_id]
			# The rules settle one 0x40b8f0 per op 72 (0x4047e9); the wait marks one strike per op 72.
			if str(row["actions"][row["defense_code"]]).contains("aniProcessHitMissMulti"):
				check(timeline["hit_ticks"].size() == MultiHitSpecialRules.strikes({"fields": {"defense_code": row["defense_code"]}}), "the rules' strike count is the defense objects' op 72 count: %s %d" % [skill_id, timeline["hit_ticks"].size()])
			check(int(timeline["instructions"]) == SkillEffectScriptPlayer.parse(row["actions"][row["attack_code"]]).size() + SkillEffectScriptPlayer.parse(row["actions"][row["defense_code"]]).size(), "instruction count kept: " + skill_id)
			var hit_only_seen := false
			for event in timeline["events"]:
				check(int(event["tick"]) >= 0 and int(event.get("expire", event["tick"])) <= complete, "event inside the clip: " + skill_id)
				if event["kind"] == "sound":
					check(manifest["sounds"].has(event["member"]), "sound imported: %s %s" % [skill_id, event["member"]])
					continue
				check(manifest["objects"].has(event["object"]) and int(event["expire"]) > int(event["tick"]), "object drawn from the manifest with a positive lifetime: " + skill_id)
				for member in event["frames"]:
					check(manifest["frames"].has(member), "object frame imported: " + str(member))
				check(event["motion"] in ["static", "fly", "radial", "spin", "native"], "known motion: " + str(event["motion"]))
				if event["motion"] == "fly":
					check(int(event["arrive"]) > int(event["tick"]) and int(event["expire"]) > int(event["arrive"]), "a flight arrives, then expires: " + skill_id)
				hit_only_seen = true
			for phase in ["attack", "defense"]:
				var backdrop := str(timeline[phase + "_background"])
				check(backdrop == "" or manifest["frames"].has(backdrop), "aniInsertSpecialBG panel imported: " + backdrop)
			for name in timeline["skipped_objects"]:
				check(name == "obj_Special51_05", "only the unresolved object is skipped: " + str(name))
				if not skipped_rows.has(skill_id): skipped_rows.append(skill_id)
			check(hit_only_seen, "every script draws at least one object: " + skill_id)
		var with_hit: Dictionary = player.compile_row(skill_id, true, 7)
		var without: Dictionary = player.compile_row(skill_id, false, 7)
		check(with_hit["events"].size() >= without["events"].size(), "a miss never draws more than a hit: " + skill_id)
	check(skipped_rows == ["special:magicOTHER:magicCode27"], "弒神渺殺斷 is the one row that skips its unresolved object: %s" % str(skipped_rows))
	player.free()


## Every MAGIC row compiles to an `effect` timeline: only the four eff* verbs, every object
## and sound imported, positions are displacements (static, with a fade tail), the impact
## mark never after completion, deterministic under one seed, eff_proc_Global／damage read
## from the row, and hit／miss identical (effCode scripts carry no hit-only verbs).
## Frames of one seed variant of a tracked object (variant 0 is the row itself).
func _variant_frames(object_name: String, variant: int) -> int:
	var row: Dictionary = motion["objects"][object_name]
	return int(row["frames"]) if variant == 0 else int(row["variants"][variant - 1]["frames"])


func every_magic_row_compiles() -> void:
	var player := SkillEffectScriptPlayer.new()
	root.add_child(player)
	var compiled := 0
	var global_rows: Array[String] = []
	var dim_rows := 0
	for skill_id in manifest["rows"]:
		if manifest["rows"][skill_id]["channel"] != "magic":
			continue
		var row: Dictionary = scope["rows"][skill_id]
		var timeline: Dictionary = player.compile_row(skill_id, true, 7)
		check(timeline["kind"] == "effect" and timeline["unimplemented"].is_empty() and timeline["skipped_objects"].is_empty(), "magic row compiles every verb and object: " + skill_id)
		check(str(timeline) == str(player.compile_row(skill_id, true, 7)) and str(timeline) == str(player.compile_row(skill_id, false, 7)), "same seed, same timeline; hit and miss draw the same effect: " + skill_id)
		check(int(timeline["instructions"]) == SkillEffectScriptPlayer.parse(row["actions"][row["effect_code"]]).size() and int(timeline["instructions"]) > 0, "instruction count kept: " + skill_id)
		check(int(timeline["impact_tick"]) >= 0 and int(timeline["impact_tick"]) <= int(timeline["complete_tick"]) and int(timeline["complete_tick"]) > 0, "impact ≤ complete: %s %s" % [skill_id, str([timeline["impact_tick"], timeline["complete_tick"]])])
		var objects := 0
		for event in timeline["events"]:
			check(int(event["tick"]) >= 0 and int(event.get("expire", event["tick"])) <= int(timeline["complete_tick"]), "event inside the clip: " + skill_id)
			if event["kind"] == "sound":
				check(manifest["sounds"].has(event["member"]), "sound imported: %s %s" % [skill_id, event["member"]])
				continue
			objects += 1
			if motion["objects"].has(event["object"]):
				# A natively tracked object plays its tree: it lives exactly the track's frames.
				check(event["motion"] == "native" and not event.has("fade_tick") and int(event["expire"]) == int(event["tick"]) + _variant_frames(str(event["object"]), int(event["variant"])) and bool(event["anchored"]) == (motion["objects"][event["object"]]["motion"] == "anchored"), "a tracked effect object plays its native track for exactly its frames: " + skill_id)
			else:
				# The 13 objects stopped at an unreviewed callee keep the provisional static hold.
				check(motion["unrestored"].has(event["object"]), "an untracked effect object is listed unrestored: " + str(event["object"]))
				check(event["motion"] == "static" and event.has("fade_tick") and int(event["fade_tick"]) >= int(event["tick"]) + SkillEffectScriptPlayer.EFFECT_MIN_LIFETIME_TICKS and int(event["expire"]) == int(event["fade_tick"]) + SkillEffectScriptPlayer.EFFECT_FADE_TICKS, "untracked effect objects stay put, hold at least the minimum lifetime and fade: " + skill_id)
				check(int(event["fade_tick"]) - int(event["tick"]) <= maxi(int(event["lifetime"]), SkillEffectScriptPlayer.EFFECT_MIN_LIFETIME_TICKS) and int(event["fade_tick"]) <= maxi(int(event["tick"]) + SkillEffectScriptPlayer.EFFECT_MIN_LIFETIME_TICKS, int(timeline["complete_tick"]) - SkillEffectScriptPlayer.EFFECT_FADE_TICKS), "an untracked object never holds past its own frames or the script's remaining waits: " + skill_id)
			check(event["frames"].all(func(member): return manifest["frames"].has(member)) and manifest["objects"].has(event["object"]), "object frames imported: " + str(event["object"]))
			check((event["scale"] as Vector2) == Vector2(manifest["objects"][event["object"]]["zoom"][0], manifest["objects"][event["object"]]["zoom"][1]), "object scale is its obj_ZoomX／Y: " + str(event["object"]))
		check(objects > 0, "every magic script draws at least one object: " + skill_id)
		check(bool(timeline["global"]) == (row["effect_proc"] == "eff_proc_Global") and bool(timeline["dim"]) == (row["damage_policy"] == "native_magic_damage"), "eff_proc and damage policy come from the row: " + skill_id)
		if timeline["global"]: global_rows.append(skill_id)
		if timeline["dim"]: dim_rows += 1
		compiled += 1
	check(compiled == 39 and global_rows.size() == 12 and dim_rows == 20, "39 magic rows compile; 12 eff_proc_Global rows play at the screen centre; 20 damage spells dim the map (%d %d %d)" % [compiled, global_rows.size(), dim_rows])
	player.free()


## 氣刃斬 (specCode01／02): BG panel + the blade from (700,160) in the caster's shot for 60
## ticks; in the target's shot the blade re-enters at tick 80, the hit mark at 90 is its
## arrival, sparks burst on a hit, the result shows at 150 and the clip completes at 190.
func qi_blade_timeline() -> void:
	var player := SkillEffectScriptPlayer.new()
	root.add_child(player)
	var hit: Dictionary = player.compile_row("special:magicOTHER:magicCode01", true, 1)
	check(hit["release_tick"] == 60 and hit["impact_tick"] == 90 and hit["result_tick"] == 150 and hit["complete_tick"] >= 190, "氣刃斬 marks (the last spark, rand(delay)＋1 behind the one before it at 0x401455, may run past the 40-tick result hold): %s" % str([hit["release_tick"], hit["impact_tick"], hit["result_tick"], hit["complete_tick"]]))
	check(hit["attack_background"] == "MAGIC\\SP00_001.SHP" and hit["defense_background"] == "", "the attack script's aniInsertSpecialBG panel; the defense keeps the backdrop")
	var sounds: Array = hit["events"].filter(func(event): return event["kind"] == "sound")
	check(sounds[0]["tick"] == 0 and sounds[0]["member"] == "WAV\\SP01-001.WAV", "the attack script's aniPlaySound at tick 0")
	# obj_Special01_03's objcomd.txt command 2 opens with objmPlaySound,WAV\BOMB0017.WAV: each
	# of the 6 bursts plays the landing sound as it appears — the first at 90, each next
	# rand(4) + 1 later (spawner 0x401390), so within 90..110.
	var burst_ticks: Array = []
	for event in hit["events"]:
		if event["kind"] == "object" and event["object"] == "obj_Special01_03":
			burst_ticks.append(int(event["tick"]))
	var landing: Array = sounds.filter(func(event): return event["member"] == "WAV\\BOMB0017.WAV").map(func(event): return int(event["tick"]))
	burst_ticks.sort()
	landing.sort()
	check(landing.size() == 6 and landing == burst_ticks and landing[0] == 90 and landing.all(func(tick): return tick >= 90 and tick <= 110), "the landing sound WAV\\BOMB0017.WAV sounds with the impact bursts at %s (bursts %s)" % [str(landing), str(burst_ticks)])
	check(sounds.size() == 1 + landing.size(), "no other sound: %s" % str(sounds.map(func(event): return event["member"])))
	# Every object here runs its objcomd.txt program's native track (objcomd_motion.json, 0x4051d0).
	var flights: Array = hit["events"].filter(func(event): return event["kind"] == "object" and event["object"] in ["obj_Special01_01", "obj_Special01_02"])
	check(flights.size() == 2 and flights.all(func(event): return event["motion"] == "native" and event["source"] == "objcomd") and flights[0]["tick"] == 0 and flights[1]["tick"] == 80, "the blades run their objcomd.txt programs in the attack and the defense shot")
	check(flights[1]["position"] == Vector2(700, 160) and flights[1]["frames"] == ["MAGIC\\SP01_001.SHP", "MAGIC\\SP01_002.SHP"], "the defense blade is obj_Special01_02 at (700,160)")
	var bursts: Array = hit["events"].filter(func(event): return event["kind"] == "object" and event["object"] in ["obj_Special01_03", "obj_Special01_04"])
	check(bursts.size() == 30 and bursts.all(func(event): return int(event["tick"]) >= 90 and int(event["tick"]) <= 90 + 23 * 2 and (event["position"] as Vector2).distance_to(Vector2(320, 160)) <= 90), "6 + 24 hit sparks appear within the accumulated delay range around the target centre")
	var miss: Dictionary = player.compile_row("special:magicOTHER:magicCode01", false, 1)
	check(miss["events"].filter(func(event): return event["kind"] == "object").size() == 2 and miss["impact_tick"] == 90 and miss["complete_tick"] == 190 + 16, "a miss keeps the blades and the marks, drops the hit-only sparks")
	check(miss["events"].filter(func(event): return event["kind"] == "sound").map(func(event): return event["member"]) == ["WAV\\SP01-001.WAV"], "a miss inserts no burst, so no landing sound")
	var other2: Dictionary = player.compile_row("special:magicOTHER2:magicCode01", true, 1)
	check(other2["events"].any(func(event): return event["kind"] == "sound" and event["member"] == "WAV\\BOMB0017.WAV" and int(event["tick"]) >= 90), "the magicOTHER2 row of 氣刃斬 (specCode121／122, its own obj_Special61 blades) lands with the same BOMB0017 burst")
	player.free()


## Every special object's objcomd.txt command sounds (manifest `command_sounds`) reach the
## timeline of every script row that inserts it, on its own insertion tick plus the frame the
## native run played it (objcomd_motion.json `sounds`, per variant); objmPlayHitSound only on a hit; an object whose frames cannot be
## drawn still sounds. 39 objects in 24 rows carry command sounds.
func object_command_sounds() -> void:
	var player := SkillEffectScriptPlayer.new()
	root.add_child(player)
	var objects := 0
	var carriers: Array[String] = []
	for name in manifest["objects"]:
		var object: Dictionary = manifest["objects"][name]
		check(object["command_sounds"] == scope["objects"][name]["command_sounds"] and str(object["command_code"]) == str(scope["objects"][name]["command_code"]), "manifest command sounds mirror the scope: " + name)
		check(str(object["process"]) != "defProcObjectMove" or str(object["command_code"]) != "", "every defProcObjectMove object names its objcomd.txt command: " + name)
		for sound in object["command_sounds"]:
			check(manifest["sounds"].has(sound["member"]), "command sound imported: %s %s" % [name, sound["member"]])
			check(str(sound["timing"]) == ("provisional" if not sound["unresolved_waits"].is_empty() else "delays"), "a cue behind a motion wait is provisional: " + name)
		if not object["command_sounds"].is_empty():
			objects += 1
			carriers.append(name)
	check(objects == 39, "39 objects carry command sounds: %d" % objects)
	var burst: Dictionary = manifest["objects"]["obj_Special01_03"]
	check(burst["command_code"] == "2" and burst["command_sounds"].size() == 1 and burst["command_sounds"][0]["member"] == "WAV\\BOMB0017.WAV" and not bool(burst["command_sounds"][0]["hit_only"]) and int(burst["command_sounds"][0]["delay_ticks"]) == 0 and burst["command_sounds"][0]["timing"] == "delays", "氣刃斬's burst obj_Special01_03 runs command 2: objmPlaySound,WAV\\BOMB0017.WAV first")
	var rows := 0
	for skill_id in manifest["rows"]:
		if manifest["rows"][skill_id]["presentation"] != "script" or manifest["rows"][skill_id]["channel"] != "special":
			continue
		var row_has := false
		for hit in [true, false]:
			var timeline: Dictionary = player.compile_row(skill_id, hit, 7)
			var cues := {}
			for event in timeline["events"]:
				if event["kind"] == "sound":
					var key := str(event["member"]) + "@" + str(event["tick"])
					cues[key] = int(cues.get(key, 0)) + 1
			var expected := 0
			var order := {}
			for event in timeline["events"]:
				if event["kind"] != "object": continue
				# An angle ring with a native run sounds like its instance's track (`track`, variant k); the
				# other patterned inserts keep their geometry but sound like the object's track, as every object does.
				var variant: int = int(event["variant"]) if event.has("track") else int(order.get(event["object"], 0))
				if not event.has("track"): order[event["object"]] = variant + 1
				var recorded: Array = ObjcomdMotion.sounds(str(event.get("track", event["object"])), variant)
				for sound in recorded:
					if bool(sound[2]) and not hit:
						continue
					var at := int(event["tick"]) + int(sound[0])
					# 0x4029a2／0x404ada: the object is deleted at its page's teardown, its program with it.
					if at >= int(timeline["release_tick"] if event["phase"] == "attack" else timeline["complete_tick"]):
						continue
					expected += 1
					var key := str(sound[1]) + "@" + str(at)
					check(int(cues.get(key, 0)) > 0, "%s %s: %s sounds at insertion %d + %d" % [skill_id, "hit" if hit else "miss", sound[1], int(event["tick"]), int(sound[0])])
					cues[key] = int(cues.get(key, 0)) - 1
			if hit and expected > 0: row_has = true
		if row_has: rows += 1
	check(rows == 24, "24 special rows play object command sounds on a hit: %d" % rows)
	# 百裂突刺's obj_Special34_03 (command 82): the ATTACK17 swish always, HIT00004 only on a hit.
	var thrust_hit: Dictionary = player.compile_row("special:magicOTHER:magicCode18", true, 7)
	var thrust_miss: Dictionary = player.compile_row("special:magicOTHER:magicCode18", false, 7)
	var members := func(timeline: Dictionary) -> Array: return timeline["events"].filter(func(event): return event["kind"] == "sound").map(func(event): return event["member"])
	check(members.call(thrust_hit).has("WAV\\HIT00004.WAV") and not members.call(thrust_miss).has("WAV\\HIT00004.WAV") and members.call(thrust_miss).has("WAV\\ATTACK17.WAV"), "objmPlayHitSound needs a hit; objmPlaySound does not")
	# An object whose frames are not imported is skipped for drawing but still sounds.
	var data: Dictionary = manifest.duplicate(true)
	for member in data["objects"]["obj_Special01_03"]["shape_members"]:
		data["frames"].erase(member)
	var row: Dictionary = scope["rows"]["special:magicOTHER:magicCode01"]
	var bare: Dictionary = SkillEffectScriptPlayer.compile(row["actions"][row["attack_code"]], row["actions"][row["defense_code"]], true, 1, data)
	check(bare["skipped_objects"] == ["obj_Special01_03"] and bare["events"].any(func(event): return event["kind"] == "sound" and event["member"] == "WAV\\BOMB0017.WAV"), "a burst without imported frames still plays its landing sound")
	player.free()


## Every effect object's obj_Y1／obj_X2 cues (manifest `program_sounds`, the effProc* program's
## own events) reach the timeline of every magic row that inserts it, at the object's start plus
## the read delay, inside the clip. 13 objects in 8 spells.
func effect_program_sounds() -> void:
	var player := SkillEffectScriptPlayer.new()
	root.add_child(player)
	var carriers := 0
	for name in manifest["objects"]:
		var object: Dictionary = manifest["objects"][name]
		check(object["program_sounds"] == scope["objects"][name]["program_sounds"], "manifest program sounds mirror the scope: " + name)
		for sound in object["program_sounds"]:
			check(manifest["sounds"].has(sound["member"]) and str(sound["timing"]) in ["counts", "provisional"] and str(sound["field"]) in ["obj_Y1", "obj_X2"], "program sound imported and typed: %s %s" % [name, sound["member"]])
		if not object["program_sounds"].is_empty():
			carriers += 1
			check(str(object["process"]) == "defProcEffectProcess1", "only effect objects carry program sounds: " + name)
	check(carriers == 13, "13 effect objects carry obj_Y1／obj_X2 cues: %d" % carriers)
	var rows := 0
	for skill_id in manifest["rows"]:
		if manifest["rows"][skill_id]["channel"] != "magic":
			continue
		var timeline: Dictionary = player.compile_row(skill_id, true, 7)
		var cues := {}
		for event in timeline["events"]:
			if event["kind"] == "sound":
				cues[str(event["member"]) + "@" + str(event["tick"])] = true
		var expected := 0
		var order := {}
		for event in timeline["events"]:
			if event["kind"] != "object": continue
			var variant: int = order.get(event["object"], 0)
			order[event["object"]] = variant + 1
			if manifest["objects"][event["object"]]["program_sounds"].is_empty(): continue
			expected += 1
			for sound in EffectObjectMotion.sounds(event["object"], variant):
				var at := int(event["tick"]) + int(sound[0])
				check(cues.has(str(sound[1]) + "@" + str(at)) and at <= int(timeline["complete_tick"]), "%s: %s sounds at start %d + native frame %d inside the clip" % [skill_id, sound[1], int(event["tick"]), int(sound[0])])
		if expected > 0: rows += 1
	check(rows == 8, "8 spells play effect-program cues: %d" % rows)
	# 烈蝕水彈 (effCode10): obj_Effect_WaterBig1 enters at 40; its native run throws six balls every
	# 16 ticks from frame 96 (SHOOT002 each), fires the seventh at 238 (+0x46) and bursts WATER008 at 257 (+0x44).
	var ball: Dictionary = player.compile_row("magic:magicWATER:magicCode03", true, 7)
	var big: Array = ball["events"].filter(func(event): return event["kind"] == "object" and event["object"] == "obj_Effect_WaterBig1")
	var shots: Array = ball["events"].filter(func(event): return event["kind"] == "sound" and event["member"] == "WAV\\SHOOT002.WAV").map(func(event): return int(event["tick"]))
	var bursts: Array = ball["events"].filter(func(event): return event["kind"] == "sound" and event["member"] == "WAV\\WATER008.WAV").map(func(event): return int(event["tick"]))
	check(big.size() == 1 and int(big[0]["tick"]) == 40 and shots.has(40 + 96) and shots.has(40 + 238) and bursts == [40 + 257], "烈蝕水彈: SHOOT002 from 136 to 278, WATER008 at 297: %s %s" % [str(shots), str(bursts)])
	player.free()


## 天雷猛襲劍 (specCode03／04): the attack script runs 70 ticks; the defense script's
## sounds and lightning strikes land on their aniDelay cursors; hit sound and burst are hit-only.
func thunder_sword_timeline() -> void:
	var player := SkillEffectScriptPlayer.new()
	root.add_child(player)
	var hit: Dictionary = player.compile_row("special:magicAIR:magicCode01", true, 3)
	check(hit["release_tick"] == 70 and hit["impact_tick"] == 160 and hit["result_tick"] == 200 and hit["complete_tick"] == 240 + 16, "天雷猛襲劍 marks: %s" % str([hit["release_tick"], hit["impact_tick"], hit["result_tick"], hit["complete_tick"]]))
	var sound_ticks: Array = hit["events"].filter(func(event): return event["kind"] == "sound").map(func(event): return int(event["tick"]))
	check(sound_ticks == [0, 90, 100, 110, 140, 160], "sounds at 0 (attack) then 90／100／110 lightning, 140 shoot, 160 hit bomb: %s" % str(sound_ticks))
	var miss: Dictionary = player.compile_row("special:magicAIR:magicCode01", false, 3)
	check(miss["events"].filter(func(event): return event["kind"] == "sound").size() == 5, "the aniPlayHitSound is dropped on a miss")
	check(hit["attack_background"] == "MAGIC\\SP00_003.SHP", "its own SP00_003 panel, not 氣刃斬's")
	var objects: Array = hit["events"].filter(func(event): return event["kind"] == "object")
	check(objects.size() == 12 and miss["events"].filter(func(event): return event["kind"] == "object").size() == 6, "12 objects on a hit (6 of them aniInsertHitRandomObject), 6 on a miss")
	player.free()


## The geometry verbs and the page flags read their ANIMAL.H parameters.
func geometry_and_flags() -> void:
	var player := SkillEffectScriptPlayer.new()
	root.add_child(player)
	var petals: Dictionary = player.compile_row("special:magicFIRE:magicCode01", true, 5)  # 妖華紅蓮舞
	var radial: Array = petals["events"].filter(func(event): return event["kind"] == "object" and event["motion"] == "radial")
	check(radial.size() == 48 and radial.all(func(event): return int(event["fixed_frame"]) >= 0 and int(event["fixed_frame"]) < 16), "three aniInsertAngleObject rings of 16 use the object's 16 direction shapes")
	var ring: Dictionary = player.compile_row("special:magicWATER:magicCode03", true, 5)  # 萬息秘孔術
	var round_events: Array = ring["events"].filter(func(event): return event["kind"] == "object" and event["object"] == "obj_Special12_02")
	check(round_events.size() == 32 and round_events.all(func(event): return absf((event["position"] as Vector2).y - 250.0) <= 62.0 and absf((event["position"] as Vector2).x - 320.0) <= 247.0), "aniInsertRoundRandomObject places 16 per ring on the (radius, radius>>2) ellipse")
	var tornado: Dictionary = player.compile_row("special:magicOTHER:magicCode28", true, 5)  # 虛空無轉
	var spins: Array = tornado["events"].filter(func(event): return event["kind"] == "object" and event["motion"] == "spin")
	check(spins.size() == 35 and spins.all(func(event): return float(event["zoom"]) > 0.0 and event.has("centre")), "two aniInsertTornadoObject columns of 15 + 20 spinning sprites")
	var rage: Dictionary = player.compile_row("special:magicFIRE:magicCode02", true, 5)  # 激怒
	check(rage["xy_disp"] == Vector2(50, 0), "aniSetXYDisp shifts the target shot")
	var roar: Dictionary = player.compile_row("special:magicOTHER:magicCode20", true, 5)  # 獅子吼
	check(roar["show_attacker"] and roar["release_tick"] == 140 and roar["double_page_tick"] == 160, "aniShowAttacker is read; the attack script runs 140 ticks and the double page opens 20 ticks into the defense")
	var flowers: Dictionary = player.compile_row("special:magicOTHER:magicCode07", true, 5)  # 百花撩亂
	check(flowers["no_dark_bg"] and flowers["double_page_tick"] == 30 + 26, "aniNoSpecialDarkBG and the double page after the empty attack lead + 26")
	var stars: Dictionary = player.compile_row("special:magicAIR:magicCode04", true, 5)  # 星辰落牙破
	# 0x45f5f7 runs the defender (plane 46) before the stars (plane 47): an op 72 on tick t counts at t + 1.
	check(stars["hit_ticks"] == [105, 116, 128, 140, 152, 164] and stars["impact_tick"] == 105, "aniProcessHitMissMulti settles one strike per recorded objmSetMultiHitData of the obj_Special24_02 stars, a tick after the op: %s" % [stars["hit_ticks"]])
	var meteors: Array = stars["events"].filter(func(event): return event["kind"] == "object" and event["object"] == "obj_Special24_03")
	check(meteors.size() == 10 and meteors.all(func(event): return event["motion"] == "native" and event["source"] == "objcomd"), "meteors inserted above the stage run their objcomd.txt program's native track")
	check(stars["result_ticks"] == stars["hit_ticks"].map(func(tick): return int(tick) + 1) and stars["result_tick"] == stars["impact_tick"] + 1 and stars["complete_tick"] == 164 + SkillEffectScriptPlayer.MULTI_HIT_STRIKE_TICKS + 160 + 16, "each multi-hit strike spawns its numbers a tick later; the clip completes when the delay after the wait ends: %d" % stars["complete_tick"])
	# The last strike's number holds the defender (0x40478d with the defender as waiter, bumped at
	# release 0x4088fa): a 12 spawns at 165, releases 27 + 20 ticks later, the check comes 2 after.
	var held: Dictionary = player.compile_row("special:magicAIR:magicCode04", true, 5, [], {"damage": 12, "experience": 3})
	check(held["complete_tick"] == 164 + 1 + 47 + 2 + 160 + 16, "the last strike's red number holds the wait until it releases the defender: %d" % held["complete_tick"])
	var split: Dictionary = player.compile_row("special:magicAIR:magicCode04", true, 5, [true, false, true, false, false, true])
	var star_runs: Array = split["events"].filter(func(event): return event.has("strike_tick"))
	star_runs.sort_custom(func(a, b): return int(a["strike_tick"]) < int(b["strike_tick"]))
	check(star_runs.map(func(event): return event["hit"]) == [true, false, true, false, false, true], "each star draws the hit run of the strike its op 72 queued")
	# 0x404630: a strike before the last with both change words zero spawns no number; the last
	# spawns MISS (0x404664) unless the shot's experience is non-zero (0x404772).
	var split_spawns := SkillEffectScriptPlayer.strike_spawns({"hit_segments": [{"actual_damage": 0}, {"actual_damage": 12}, {"actual_damage": 0}]}, stars, [])
	check(split_spawns == [{"kind": "damage", "value": 12, "hold": 11}, {"kind": "miss", "value": 0, "hold": 23}], "each strike spawns its own number at its own result mark; an unchanged strike before the last spawns none: %s" % [split_spawns])
	var earned := SkillEffectScriptPlayer.strike_spawns({"hit_segments": [{"actual_damage": 12, "experience_points": 3}, {"actual_damage": 0}]}, stars, [])
	check(earned == [{"kind": "damage", "value": 12, "hold": 0}], "an unchanged last strike spawns no MISS once the shot earned experience: %s" % [earned])
	var empty: Dictionary = SkillEffectScriptPlayer.compile([], ["aniDelay,10,aniProcessHitMiss", "aniDelay,5,aniShowHitResult"], true, 1, manifest)
	check(empty["release_tick"] == SkillEffectScriptPlayer.EMPTY_ATTACK_LEAD_TICKS and empty["impact_tick"] == 40 and empty["result_tick"] == 45 and empty["complete_tick"] == 85 + 16 and empty["events"].is_empty(), "an empty attack script still leads for EMPTY_ATTACK_LEAD_TICKS")
	var unknown: Dictionary = SkillEffectScriptPlayer.compile([], ["aniSetZoom,0x10000", "aniDelay,4"], true, 1, manifest)
	check(unknown["unimplemented"] == ["aniSetZoom"], "a verb outside the set is reported, not swallowed")
	player.free()


## 風刃 (effCode16): two random wave batches at 0／4, the blades at 54／64 — the last insertion
## is the impact mark — each object instance's obj_X1 WAV as it starts (0x415e1a); every object now plays
## its native track, so a clip completes when the script's waits and the last tree are done.
## 幻火's bombs carry the engZOOM 1.25 scale; 極 plays at the screen centre; 治癒之水 does not dim.
func magic_timelines() -> void:
	var player := SkillEffectScriptPlayer.new()
	root.add_child(player)
	var wind: Dictionary = player.compile_row("magic:magicAIR:magicCode01", true, 1)
	check(wind["instructions"] == 8 and wind["impact_tick"] == 64 and wind["complete_tick"] == _derived_complete(wind, 114) and not wind["global"] and wind["dim"], "風刃 marks: impact 64, complete = the later of its 114 waits and its trees' ends: %s" % str([wind["instructions"], wind["impact_tick"], wind["complete_tick"]]))
	var objects: Array = wind["events"].filter(func(event): return event["kind"] == "object")
	check(objects.size() == 14 and objects.filter(func(event): return event["object"] == "obj_Effect_AirWave1").size() == 6 and objects.filter(func(event): return event["object"] == "obj_Effect_AirBlade2" and event["tick"] == 64 and event["position"] == Vector2.ZERO).size() == 1, "6 + 6 waves, then the two blades at the origin")
	check(objects.filter(func(event): return event["object"] == "obj_Effect_AirWave1").all(func(event): return (event["position"] as Vector2).x >= -4.0 and (event["position"] as Vector2).x <= 5.0 and (event["position"] as Vector2).y >= -17.0 and (event["position"] as Vector2).y <= 18.0), "effInsertRandomObject folds rand(x range 10) into −4..5 and rand(y range 36) into −17..18 around the displacement (0x4238b1)")
	var sounds: Array = wind["events"].filter(func(event): return event["kind"] == "sound").map(func(event): return [int(event["tick"]), str(event["member"])])
	var starts: Array = objects.map(func(event): return [int(event["tick"]), str(manifest["objects"][event["object"]]["insert_sound"])])
	check(sounds == starts and sounds.size() == 14, "each object instance plays its obj_X1 WAV as it starts: %s" % str(sounds))
	var fire: Dictionary = player.compile_row("magic:magicFIRE:magicCode01", true, 1)
	var bombs: Array = fire["events"].filter(func(event): return event["kind"] == "object" and event["object"] == "obj_Effect_FireBomb")
	check(fire["impact_tick"] == 100 and bombs.size() == 6 and bombs.all(func(event): return event["scale"] == Vector2(1.25, 1.25) and int(event["tick"]) >= 50 and int(event["tick"]) <= 50 + 5 * 23), "幻火: 6 bombs at the engZOOM 1.25 scale from tick 50, each at most 23 ticks after the previous (delay range 24 accumulates), impact on the FireBomb2 insertion at 100")
	var water: Dictionary = player.compile_row("magic:magicWATER:magicCode01", true, 1)
	check(water["impact_tick"] == 110 and water["complete_tick"] == _derived_complete(water, 230) and water["events"].filter(func(event): return event["kind"] == "sound" and event["member"] == "WAV\\WATER005.WAV").size() == 1, "水剎: WATER005 once, impact on the last drop batch at 110, complete after the 230 waits and the last drop's track")
	var heal: Dictionary = player.compile_row("magic:magicWATER:magicCode06", true, 1)
	check(heal["impact_tick"] == 12 and not heal["dim"] and heal["events"].filter(func(event): return event["kind"] == "object").size() == 40, "治癒之水: 32 + 4 + 4 stars, impact on the last batch at 12, no map dimming")
	var supreme: Dictionary = player.compile_row("magic:magicOTHER:magicCode03", true, 1)
	check(supreme["global"] and supreme["impact_tick"] == 600 and supreme["complete_tick"] == _derived_complete(supreme, 680), "極 (eff_proc_Global) plays at the screen centre; its waits sum to 680 ticks, its impact is the last batch at 600 (%s)" % str([supreme["impact_tick"], supreme["complete_tick"]]))
	var quake: Dictionary = player.compile_row("magic:magicEARTH:magicCode04", true, 1)  # 怒濤地裂崩
	var lasers: Array = quake["events"].filter(func(event): return event["kind"] == "object" and event["object"] == "obj_Effect_EarthLaser2")
	check(lasers.size() == 10 and lasers.all(func(event): return event["motion"] == "native" and int(event["expire"]) - int(event["tick"]) == _variant_frames("obj_Effect_EarthLaser2", int(event["variant"]))) and quake["complete_tick"] == _derived_complete(quake, 372), "EarthLaser2's shape_delay 30000 no longer needs clamping: its program ends the laser after its native frames (%s)" % str(quake["complete_tick"]))
	# Scripts without random insertion have fixed completions, read off the tracks by hand:
	# 封魔滅殺 (effCode30) inserts obj_Effect_MindBall at 0 and waits 120 — the ball's tree (the
	# ball and its 7 sparks) lasts 162 frames, so the clip ends at 162; 生命之水 (effCode14)
	# inserts obj_Effect_Water_GStarBig at 0 and waits 70 — its tree of 186 stars lasts 190.
	var seal: Dictionary = player.compile_row("magic:magicMIND:magicCode02", true, 1)
	check(seal["complete_tick"] == 162 and int(motion["objects"]["obj_Effect_MindBall"]["frames"]) == 162, "封魔滅殺 completes at 162, when MindBall's native tree ends (%s)" % str(seal["complete_tick"]))
	var life: Dictionary = player.compile_row("magic:magicWATER:magicCode07", true, 1)
	check(life["complete_tick"] == 190 and int(motion["objects"]["obj_Effect_Water_GStarBig"]["frames"]) == 190, "生命之水 completes at 190, when GStarBig's 186-star tree ends (%s)" % str(life["complete_tick"]))
	var unknown: Dictionary = SkillEffectScriptPlayer.compile_effect(["effSetZoom,2", "effWait,4"], 1, manifest, {"effect_proc": "eff_proc_Local", "damage_policy": "x"})
	check(unknown["unimplemented"] == ["effSetZoom"] and unknown["complete_tick"] == 4, "an eff* verb outside the set is reported, not swallowed")
	player.free()


## max(script waits, every object's expire) — the completion rule, computed from the events.
func _derived_complete(timeline: Dictionary, waits: int) -> int:
	var complete := waits
	for event in timeline["events"]:
		complete = maxi(complete, int(event.get("expire", event["tick"])))
	return complete


## effInsertRandomObject's delays accumulate (0x423951): the first object enters at the
## instruction, every next one rand(delay range) = 0..range−1 ticks after the previous — so the
## batch is in order and each gap is below the range, over many seeds.
func effect_random_insertion() -> void:
	for seed in range(40):
		var wind: Dictionary = SkillEffectScriptPlayer.compile_effect(["effInsertRandomObject,obj_Effect_AirWave1,0,0,10,36,16,6", "effWait,4"], seed, manifest, {"effect_proc": "eff_proc_Local", "damage_policy": "x"})
		var ticks: Array = wind["events"].filter(func(event): return event["kind"] == "object").map(func(event): return int(event["tick"]))
		var ordered: bool = ticks.size() == 6 and ticks[0] == 0
		for index in range(1, ticks.size()):
			ordered = ordered and ticks[index] >= ticks[index - 1] and ticks[index] - ticks[index - 1] <= 15
		check(ordered, "seed %d: the waves enter in order, the first at once, each ≤ 15 ticks after the previous: %s" % [seed, str(ticks)])
	var still: Dictionary = SkillEffectScriptPlayer.compile_effect(["effInsertRandomObject,obj_Effect_AirWave1,0,0,0,0,0,3"], 3, manifest, {"effect_proc": "eff_proc_Local", "damage_policy": "x"})
	check(still["events"].filter(func(event): return event["kind"] == "object").all(func(event): return int(event["tick"]) == 0 and event["position"] == Vector2.ZERO), "zero ranges read as rand(1) = 0 and a zero delay range adds nothing")


## The native tracks: the packet covers every MAGIC-script object (tracked or unrestored), and
## the 幻火 tracer tree follows the static reading of original_effect_motion.md.
func native_motion_tracks() -> void:
	var magic_objects := {}
	for skill_id in scope["rows"]:
		if scope["rows"][skill_id]["channel"] == "magic":
			for name in scope["rows"][skill_id]["objects"]:
				magic_objects[name] = true
	for name in magic_objects:
		check(motion["objects"].has(name) != motion["unrestored"].has(name), "a MAGIC object is exactly one of tracked／unrestored: " + str(name))
	for name in motion["unrestored"]:
		check(str(motion["unrestored"][name]["callee"]).begins_with("0x"), "an unrestored object names the unreviewed callee that stopped it: " + str(name))
	# effProcFlyDrop (0x416095): 90 px above the origin, falling 1 px per tick (first drawn
	# frame 1 at −88: the creation frame is skipped), swaying 16·sin at 6/256 turn per tick,
	# four shapes of 7 ticks once, then engMIX levels 16 → 1.
	var drop: Dictionary = EffectObjectMotion.track("obj_Effect_FlyDrop")
	var light: Dictionary = drop["instances"][0]
	var heights: PackedInt32Array = light["y"]
	check(drop["instances"].size() == 1 and int(light["start"]) == 1 and heights[0] == -88 and heights[heights.size() - 1] == -88 + heights.size() - 1, "FlyDrop falls 1 px per tick from 88 px above (%s)" % str([light["start"], heights[0]]))
	var sway := true
	for value in light["x"]:
		sway = sway and absi(value) <= 16
	var modes: PackedInt32Array = light["mode"]
	var levels: PackedInt32Array = light["level"]
	check(sway and heights.size() == 42 and modes[0] == EffectObjectMotion.ENG_ADDCOLOR and modes[modes.size() - 1] == EffectObjectMotion.ENG_ADDCOLOR | EffectObjectMotion.ENG_MIX and levels[levels.size() - 1] == 1, "FlyDrop sways within ±16 px, draws additively, fades through the engMIX levels to 1 over its last 16 frames")
	# effProcFireAndBomb (0x41618a): rises 24 px, loops its six shapes at the template zoom
	# 1.25, then shrinks 1/32 per tick to 0.25 and loops 24 more ticks; it throws three
	# SprayUpDown sparks (object 163) that arc under gravity.
	var bomb: Dictionary = EffectObjectMotion.track("obj_Effect_FireBomb")
	var core: Dictionary = bomb["instances"][0]
	var zooms: PackedInt32Array = core["zoom_x"]
	check((core["y"] as PackedInt32Array).size() == 76 and Array(core["y"]).all(func(value): return value == -24) and zooms[0] == 0x14000 and zooms[29] == 0xf800 and zooms[zooms.size() - 1] == 0x4000, "FireBomb rises 24 px, 1.25 zoom, then 1/32 per tick down to 0.25")
	var sparks: Array = bomb["instances"].filter(func(instance): return int(instance["code"]) == 163)
	check(sparks.size() == 3 and sparks.all(func(instance): return instance["y"][(instance["y"] as PackedInt32Array).size() - 1] > instance["y"][0]), "three SprayUpDown sparks, each ending lower than it started (gravity)")
	var bomb2: Dictionary = EffectObjectMotion.track("obj_Effect_FireBomb2")
	check(bomb2["instances"].filter(func(instance): return int(instance["code"]) == 164).size() == 12, "FireBomb2 also throws 2 × 6 Spray sparks (object 164) 12 ticks in")


## Drawing: the player places a tracked object's tree at the insertion plus the track offset,
## with the track's blend, alpha and scale — not the untracked static hold.
func native_motion_drawing() -> void:
	var player := SkillEffectScriptPlayer.new()
	root.add_child(player)
	var fire: Dictionary = player.compile_row("magic:magicFIRE:magicCode01", true, 1)
	var clip := {"effect_timeline": fire}
	var origin := Vector2(200, 300)
	var light: Dictionary = EffectObjectMotion.track("obj_Effect_FlyDrop")["instances"][0]
	var start := int(light["start"])
	# Frame 10 of FlyDrop (inserted at tick 0 at the origin): its native offset.
	player.draw(clip, 10.0 / SkillEffectScriptPlayer.TICKS_PER_SECOND, [origin])
	var shown: Array = player.sprites.filter(func(sprite): return sprite.visible)
	var expected := origin + Vector2(light["x"][10 - start], light["y"][10 - start])
	check(shown.size() == 1 and shown[0].position == expected and shown[0].material.blend_mode == CanvasItemMaterial.BLEND_MODE_ADD and is_equal_approx(shown[0].modulate.a, 1.0), "幻火 at tick 10: one FlyDrop light at the native offset %s, additive (%s)" % [str(expected), str(shown.map(func(sprite): return sprite.position))])
	# Frame 40: the light's engMIX tail — alpha = level / 16.
	player.draw(clip, 40.0 / SkillEffectScriptPlayer.TICKS_PER_SECOND, [origin])
	shown = player.sprites.filter(func(sprite): return sprite.visible)
	var level: int = light["level"][40 - start]
	check(shown.size() == 1 and is_equal_approx(shown[0].modulate.a, float(level) / 16.0) and level < 16, "幻火 at tick 40: the light fades by its level %d / 16" % level)
	player.clear()
	player.free()


# ---- run_skill_effect_script_tests.gd ----
## The cut-in plays each actor's own ANIMAL.TXT program. The expectations here are computed
## from content/generated/hsl/animation/animal_programs.json (the source programs) with the
## documented dispatcher call model (animal_program_execution.md §5／§8), never from the
## manifest's compiled dispatch — so a stale binding or a hand-authored pose fails.
const BattleCombatCutin = preload("res://game/battle/scene/BattleCombatCutin.gd")
const AnimalCastLead = preload("res://game/battle/scene/AnimalCastLead.gd")
const CommandPresentationRules = preload("res://game/battle/runtime/CommandPresentationRules.gd")
const CombatPresentationTiming = preload("res://game/battle/runtime/CombatPresentationTiming.gd")
const OriginalTick = preload("res://game/common/OriginalTick.gd")
const BattleFixture = preload("res://tests/support/BattleFixture.gd")
const PROGRAMS_PATH := "res://content/generated/hsl/animation/animal_programs.json"
## One dispatcher call per step, a hair over a tick so accumulated float error never lands a
## sample just before the boundary it is meant to have crossed.
const STEP := OriginalTick.TICK_SECONDS * (1.0 + 1e-4)
var programs: Dictionary


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
	var cutin := BattleCombatCutin.new()
	root.add_child(cutin)
	cutin.configure("res://content/imported/hsl/chapter01/combat_animation/manifest.json")
	cutin.set_process(false)
	var release_marks: Array[int] = []
	cutin.released.connect(func(_s, _a, _d, _c): release_marks.append(int(round(OriginalTick.ticks(cutin.elapsed)))))
	var attacker := unit(actor_id)
	var defender := unit(defender_id)
	cutin.play({"hit": true, "damage": 5, "defender_hp_before": 22, "defender_hp_after": 17}, attacker, defender, false)
	var seen: Array[int] = []
	var schedule := CombatPresentationTiming.ordinary(cutin.manifest["actors"][actor_id], cutin.clips[0]["strike"])
	var calls: int = expected["frames"].size()
	# The first shot's phase-100 opening (56 ticks) precedes the program's first call.
	cutin._process(float(schedule["opening"]) * 0.25 / CombatPresentationTiming.PLAYBACK_SPEED)
	_assert_true(cutin.opening_ball.visible and not cutin.attacker_sprite.visible and not cutin.defender_sprite.visible, "%s: the opening's zoom draws fill the screen before the program, attacker hidden" % code)
	cutin._process(float(schedule["opening"]) * 0.75 / CombatPresentationTiming.PLAYBACK_SPEED)
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
	# Phase 101 (0x40298a) holds the shot until the attack flash deletes itself (Timing.ordinary).
	cutin._process((float(schedule["target"]) - cutin.elapsed) / CombatPresentationTiming.PLAYBACK_SPEED + STEP)
	_assert_true(cutin.defender_sprite.visible and not cutin.attacker_sprite.visible, "%s: the target shot follows the program's %d calls and the attack flash's self-delete" % [code, calls])
	_assert_eq(release_marks, [int(expected["release_call"]) + CombatPresentationTiming.OPENING_TICKS], "%s: `released` fires once, at the aniInsertAttackFlash call after the opening" % code)
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


## The 0x45e80d slide as the cast lead calls it (tolerance 16, step 32), independent of the
## menu's (2, 8) defaults: 640 px take 21 calls (19 × 32, one 16, then the snap).
func slide_calls(from: Vector2i, to: Vector2i) -> int:
	var calls := 0
	var at := from
	while at != to:
		at = CommandPresentationRules.opening_step(at, to, AnimalCastLead.SLIDE_TOLERANCE, AnimalCastLead.SLIDE_STEP)
		calls += 1
		assert(calls < 1000)
	return calls


## The 氣刃斬 cast lead of 雷歐納德: ANIMAL.TXT lines 14–15 (aniSetXYDisp −640,0 · aniShadowBG ·
## aniMoveToCenter · aniInsertCastObject −160,−150,2,6,6) against the 7-panel P001_201 strip.
func cast_lead_program() -> void:
	var row := record("SID_PLAYER0")
	var program: Array = row["programs"]["s_action"]
	var cutin := BattleCombatCutin.new()
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
	var panels: Array = AnimalCastLead.panel_metrics(actor["special_frames"], actor["special_frames"].map(func(frame): return load(frame["res_path"])))
	# Expected call counts from the program's numbers and the handler constants.
	var banner_start: Vector2i = AnimalCastLead.CENTRE + displacement
	var move_calls := slide_calls(banner_start, AnimalCastLead.CENTRE)
	_assert_eq(move_calls, 21, "aniMoveToCenter from −640 takes 21 steps of 0x45e80d(16,32)")
	var inset: Dictionary = panels[first_inset]
	var inset_target := Vector2i(AnimalCastLead.NEAR_EDGE + inset["origin"].x, inset["origin"].y)
	var inset_calls := slide_calls(Vector2i(inset["origin"].x - inset["size"].x, inset["origin"].y), inset_target)
	var portrait: Dictionary = panels[1]
	var portrait_target := Vector2i(AnimalCastLead.FAR_RIGHT_EDGE - portrait["size"].x + portrait["origin"].x, AnimalCastLead.PORTRAIT_BOTTOM - portrait["size"].y + portrait["origin"].y)
	var portrait_calls := slide_calls(Vector2i(AnimalCastLead.SCREEN_WIDTH + portrait["origin"].x, portrait_target.y), portrait_target)
	var inset_count := panels.size() - first_inset
	var portrait_hold := 0
	for panel in range(1, first_inset):
		portrait_hold += portrait_delay + (AnimalCastLead.LAST_PORTRAIT_BONUS if first_inset - panel <= 1 else 0)
	var expected_total := (1 + AnimalCastLead.SHADOW_BG_CALLS) + (1 + move_calls) + 1 + inset_calls + inset_count * inset_delay + portrait_calls + portrait_hold + AnimalCastLead.FADE_CALLS + AnimalCastLead.HOLD_CALLS
	_assert_eq(int(lead["complete_tick"]), expected_total, "the lead's call count is the sum the program's numbers give (%d)" % expected_total)
	_assert_eq(int(lead["complete_tick"]), 140, "雷歐納德's 氣刃斬 lead is 140 ticks (the 11th hold call reads 0x4c1408, 0x402f0b)")
	# Phase by phase.
	for call in range(1 + AnimalCastLead.SHADOW_BG_CALLS):
		# 0x4035ef: the shadow level is min(+0x90, 8), from the call after aniShadowBG (0x402499).
		_assert_true(int(states[call]["shadow"]) == call and states[call]["banner"] == banner_start and int(states[call]["inset"]) < 0, "call %d: shadow level %d, banner still displaced, no inset" % [call, call])
	var at := 1 + AnimalCastLead.SHADOW_BG_CALLS
	_assert_eq(states[at]["banner"], banner_start, "the aniMoveToCenter call itself does not move")
	_assert_eq(states[at + 1]["banner"], banner_start + Vector2i(AnimalCastLead.SLIDE_STEP, 0), "the first slide call steps 32 px")
	_assert_eq(states[at + move_calls]["banner"], AnimalCastLead.CENTRE, "the banner arrives at (320,240)")
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
	_assert_true(states[at]["portrait_anchor"].x >= AnimalCastLead.SCREEN_WIDTH, "the portrait starts off-screen on the far side")
	at += portrait_calls
	_assert_true(states[at - 1]["portrait_anchor"] != portrait_target and states[at]["portrait_anchor"] == portrait_target, "the portrait stands with its right edge at 540 and bottom at 480 from the call after its slide")
	_assert_eq(states[at + portrait_hold - 1]["fade"], 0.0, "the portrait holds delay2 + 20 = %d calls before sub-state 4" % portrait_hold)
	# 0x402e55: sub-state 4's 16 calls draw both panels at mode 0 (opaque), not a crossfade.
	_assert_eq(states[at + portrait_hold + AnimalCastLead.FADE_CALLS - 1]["fade"], 0.0, "the panels stay opaque through the 16 calls")
	_assert_eq(states.size() - (at + portrait_hold + AnimalCastLead.FADE_CALLS), AnimalCastLead.HOLD_CALLS, "then 10 calls and the 11th that reads 0x4c1408 end a 絶技 lead")
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
func expected_lead_calls(program: Array, panels: Array, magic: bool = false) -> int:
	var cast_object: Dictionary = program.filter(func(i): return str(i["op"]) == "aniInsertCastObject")[0]
	var first_inset := int(cast_object["args"][2])
	var displacement := Vector2i(int(program[0]["args"][0]), int(program[0]["args"][1]))
	var move_calls := slide_calls(AnimalCastLead.CENTRE + displacement, AnimalCastLead.CENTRE)
	var inset: Dictionary = panels[first_inset]
	var inset_calls := slide_calls(Vector2i(inset["origin"].x - inset["size"].x, inset["origin"].y), Vector2i(AnimalCastLead.NEAR_EDGE + inset["origin"].x, inset["origin"].y))
	var portrait: Dictionary = panels[1]
	var portrait_target := Vector2i(AnimalCastLead.FAR_RIGHT_EDGE - portrait["size"].x + portrait["origin"].x, AnimalCastLead.PORTRAIT_BOTTOM - portrait["size"].y + portrait["origin"].y)
	var portrait_calls := slide_calls(Vector2i(AnimalCastLead.SCREEN_WIDTH + portrait["origin"].x, portrait_target.y), portrait_target)
	var portrait_hold := 0
	for panel in range(1, first_inset):
		portrait_hold += int(cast_object["args"][4]) + (AnimalCastLead.LAST_PORTRAIT_BONUS if first_inset - panel <= 1 else 0)
	return (1 + AnimalCastLead.SHADOW_BG_CALLS) + (1 + move_calls) + 1 + inset_calls + (panels.size() - first_inset) * int(cast_object["args"][3]) + portrait_calls + portrait_hold + AnimalCastLead.FADE_CALLS + AnimalCastLead.HOLD_CALLS + (AnimalCastLead.TAIL_CALLS if magic else 0)


## The magic cast lead: 緹娜's m_action (SID_PLAYER1: aniSetXYDisp −640,0 · aniShadowBG ·
## aniMoveToCenter · aniInsertCastObject −160,−150,2,4,4 over the 7-panel P002_101 strip) plays
## through the map magic presenter before the effCode script — the same AnimalCastLead as the
## 絕技 lead; `released` fires at its end and the script clock starts there. A caster without
## an imported m_shape strip (026, whose m_shape is commented out) plays the 8 shadow calls and the Cast_Star burst.
func magic_cast_lead_program() -> void:
	var row := record("SID_PLAYER1")
	var program: Array = row["programs"]["m_action"]
	var cutin := BattleCombatCutin.new()
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
	var panels: Array = AnimalCastLead.panel_metrics(actor["magic_frames"], actor["magic_frames"].map(func(frame): return load(frame["res_path"])))
	var expected_total := expected_lead_calls(program, panels, true)
	_assert_eq(int(lead["complete_tick"]), expected_total, "the magic lead's call count is the sum the program's numbers give (%d)" % expected_total)
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
	cutin._process(STEP * 12)
	_assert_true(cutin.skill_effects.sprites.any(func(sprite): return sprite.visible and str(sprite.texture.resource_path).contains("cast_star")), "a caster without a magic strip bursts Cast_Star after its 8 shadow calls")
	while cutin.busy():
		cutin._process(0.1)
	for actor_id in cutin.manifest["actors"]:
		var manifest_row: Dictionary = cutin.manifest["actors"][actor_id]
		if not manifest_row["magic_frames"].is_empty():
			_assert_true(AnimalCastLead.playable(manifest_row["magic_cast_program"], manifest_row["magic_frames"].size()), "%s: imported magic strip with a playable m_action" % actor_id)
	cutin.queue_free()
	await process_frame


## A caster whose s_action program exists but whose strip is not in the combat manifest (002:
## its P002_201 strip is the moon-dance import) keeps the standing caster — the manifest's
## declared per-actor gap, not a silent global fallback. 004 漢克斯, whose P004_201…203 strip is
## imported, compiles its s_action lead over it.
func caster_without_strip() -> void:
	var cutin := BattleCombatCutin.new()
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
			_assert_true(AnimalCastLead.playable(row["cast_program"], row["special_frames"].size()), "%s: imported strip with a playable cast program" % actor_id)
	cutin.queue_free()
	await process_frame
	var cast_ops := {}
	for row in programs["records"]:
		for channel in ["m_action", "s_action"]:
			for instruction in row["programs"].get(channel, []):
				cast_ops[str(instruction["op"])] = true
	_assert_eq(cast_ops.keys().size(), AnimalCastLead.CAST_OPCODES.size(), "the live cast programs use exactly the interpreted opcodes (%s)" % str(cast_ops.keys()))
	for op in cast_ops:
		_assert_true(AnimalCastLead.CAST_OPCODES.has(op), "cast opcode interpreted: " + op)


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
	var cutin := BattleCombatCutin.new()
	root.add_child(cutin)
	cutin.configure("res://content/imported/hsl/chapter01/combat_animation/manifest.json")
	cutin.set_process(false)
	var actor: Dictionary = cutin.manifest["actors"]["001"]
	var panels: Array = AnimalCastLead.panel_metrics(actor["special_frames"], actor["special_frames"].map(func(frame): return load(frame["res_path"])))
	var cast_object: Dictionary = program.filter(func(i): return str(i["op"]) == "aniInsertCastObject")[0]
	var first_inset := int(cast_object["args"][2])
	var inset_delay := int(cast_object["args"][3])
	var displacement := Vector2i(int(program[0]["args"][0]), int(program[0]["args"][1]))
	var plain: Dictionary = AnimalCastLead.compile(program, panels)
	var states: Array = plain["states"]
	# The banner's afterimage: at (320,240) from call 0, level 6 for 4 calls, then one less
	# every 4, gone at call 24.
	for call in range(26):
		var banner_ghosts: Array = states[call]["afterimages"].filter(func(ghost): return int(ghost["panel"]) == 0)
		if call < 24:
			_assert_true(banner_ghosts.size() == 1 and banner_ghosts[0]["anchor"] == AnimalCastLead.CENTRE and int(banner_ghosts[0]["level"]) == 6 - int(call / 4) and not bool(banner_ghosts[0]["mirrored"]), "call %d: the banner's afterimage stands at (320,240) at level %d" % [call, 6 - int(call / 4)])
		else:
			_assert_true(banner_ghosts.is_empty(), "call %d: the banner's afterimage is gone after 24 calls" % call)
	# Each inset panel but the last leaves an afterimage on the call it expires.
	var inset: Dictionary = panels[first_inset]
	var inset_target := Vector2i(AnimalCastLead.NEAR_EDGE + inset["origin"].x, inset["origin"].y)
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
	# The mirror: same length, banner from the right, drawn flipped.
	var mirrored: Dictionary = AnimalCastLead.compile(program, panels, true)
	_assert_eq(int(mirrored["complete_tick"]), int(plain["complete_tick"]), "a mirrored lead takes the same calls")
	_assert_true(mirrored["states"][0]["banner"] == AnimalCastLead.CENTRE + Vector2i(-displacement.x, displacement.y) and bool(mirrored["states"][0]["mirrored"]) and bool(mirrored["states"][0]["afterimages"][0]["mirrored"]), "a side-swapped caster's banner starts at x %d (displacement negated) and is drawn mirrored, its afterimage too" % (AnimalCastLead.CENTRE.x - displacement.x))
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
	_assert_true(cutin.attacker_sprite.scale == Vector2(-1, 1) and ghost_sprites.size() == 1 and is_equal_approx(ghost_sprites[0].modulate.a, 6.0 / 16.0) and ghost_sprites[0].scale == Vector2(-1, 1) and ghost_sprites[0].position == Vector2(AnimalCastLead.CENTRE), "the mirrored banner flips and its afterimage draws at 6/16 at (320,240)")
	cutin.clips.clear()
	cutin.play(strike, unit("001"), unit("021"), false)
	cutin.show_cast_lead(cutin.clips[0], cutin.cast_lead(cutin.clips[0]), 0.0)
	_assert_true(cutin.attacker_sprite.scale == Vector2.ONE, "an ordinary caster's banner is not flipped")
	cutin.queue_free()
	await process_frame


func run_animal_program() -> void:
	programs = JSON.parse_string(FileAccess.get_file_as_string(PROGRAMS_PATH))
	await ordinary_programs()
	await cast_lead_program()
	await magic_cast_lead_program()
	await caster_without_strip()
	await cast_lead_afterimages_and_mirror()
	# The script player's sounds (氣刃斬／連續突刺) must stop before the batch quits.
	await settle_wall_clock(tree, 0.4)


# ---- run_skill_effect_script_tests.gd ----
## Close-up layout and aftermath floats (lane R6-P3,
## docs/evidence_packets/runtime_observations/cutin_floaters/README.md).
## Close-up: the defender object 0x4038a0 starts on the shot line and shifts by its row's hit
## move flag (aniKRight −50, aniKLeft +30), then a hit knocks it back 14+13+…+1 = 105 px and a
## miss slides it 150 px (0x45e91e) the same way; the census checks that every cut-in path
## places its actors through CutinLayout and that every combat manifest row declares a flag.
## Floats: the original glyph layout of KILL／EXP／$／LEVEL UP, the defProcShowNumber level
## fade, the aftermath queue order KILL (with the disposal) → EXP → $ → LEVEL UP, and a census
## that no other game file draws a reward float or plays the level-up sound. Vitals: the resist
## row's element gems and "07%"／"MAX" values.

const CutinLayout = preload("res://game/battle/runtime/CutinLayout.gd")
const BattleRewardFloater = preload("res://game/battle/scene/BattleRewardFloater.gd")
const BattleAftermath = preload("res://game/battle/scene/BattleAftermath.gd")
const BattleVitals = preload("res://game/battle/scene/BattleVitals.gd")


func run_cutin_floaters() -> void:
	_test_defender_anchor_and_reaction()
	await _test_float_glyph_layout()
	await _test_aftermath_order()
	await _test_resist_row()
	await run_map_pose_floaters()


func _test_defender_anchor_and_reaction() -> void:
	var right := {"source_k_action": "aniKRight"}
	var left := {"source_k_action": "aniKLeft"}
	var stop := {"source_k_action": "aniKStop"}
	_assert_eq(CutinLayout.attacker_anchor(), Vector2(320, 330), "the attacker stands at (0x140, 0x14a) — the recording's (320,330)")
	_assert_eq(CutinLayout.defender_anchor(left).y, 330.0, "the victim shares the shot line y 0x14a")
	_assert_eq(CutinLayout.defender_anchor(right).x, 270.0, "aniKRight victims start 50 px left of the shot line (0x404560)")
	_assert_eq(CutinLayout.defender_anchor(left).x, 350.0, "aniKLeft victims start 30 px right — the recording's 拉爾斯帝國兵 at x 350")
	_assert_eq(CutinLayout.defender_anchor(stop).x, 320.0, "aniKStop stays on the line")
	var steps: Array[float] = []
	for tick in range(16):
		steps.append(CutinLayout.knockback_x(left, tick))
	_assert_eq(steps.slice(0, 3), [-14.0, -27.0, -39.0], "the knock-back starts at 14 px a tick and slows by 1")
	_assert_eq(steps[13], -105.0, "14 ticks carry it 105 px — the recording's 350 → 245")
	_assert_eq(steps[15], -105.0, "then it stops")
	_assert_eq(CutinLayout.knockback_x(right, 20), 105.0, "aniKRight is knocked to the right")
	_assert_eq(CutinLayout.knockback_x(stop, 20), 0.0, "aniKStop is not moved")
	var dodge: Array[float] = []
	for tick in range(16):
		dodge.append(CutinLayout.dodge_x(right, tick))
	_assert_eq(dodge.slice(0, 4), [36.0, 64.0, 85.0, 101.0], "the dodge steps min(36, remaining／4)")
	_assert_true(dodge[13] < 150.0 and dodge[14] == 150.0 and dodge[15] == 150.0, "14 moving ticks and the arrival land 150 px away (%s)" % str(dodge))
	_assert_eq(CutinLayout.reaction_x(left, false, 30), -150.0, "a miss slides; a hit knocks back")


func _test_float_glyph_layout() -> void:
	var node: Node2D = BattleRewardFloater.new()
	root.add_child(node)
	node.present("experience", 26)
	_assert_eq(node.text, "EXP 26", "the EXP float names its value")
	_assert_eq(node.glyphs.map(func(g): return g.position.x), [-35.0, 21.0, 35.0], "EXP prefix at x − 5 × 7, digits 14 px apart after 4 units (0x408580)")
	_assert_true(node.glyphs[0].texture.resource_path.ends_with("reward_floats/exp.png") and node.glyphs[1].texture.resource_path.ends_with("exp_digit_2.png"), "EXP uses NUM511 and the NUM4xx digits")
	node.present("gold", 100)
	_assert_eq(node.glyphs.map(func(g): return g.position.x), [-28.0, 0.0, 14.0, 28.0], "$ prefix at x − 4 × 7, digits after 2 units")
	_assert_eq(node.text, "$ 100", "the $ float names its value")
	node.present("kill", 3)
	_assert_eq(node.glyphs.map(func(g): return g.position.x), [-57.0, 57.0], "KILL at x − (19 + 38), its digit 114 further (0x4083e0)")
	_assert_true(node.glyphs[1].texture.resource_path.ends_with("kill_digit_3.png"), "the digit 3 is KILL_004")
	node.present("kill", 12)
	_assert_eq(node.glyphs.map(func(g): return g.position.x), [-76.0, 38.0, 76.0], "two digits 38 px apart")
	node.present("level_up")
	_assert_eq([node.text, node.glyphs.size(), node.glyphs[0].position.x], ["LEVEL UP", 1, 0.0], "LEVEL UP is NUM514 alone on the spawn point")
	node.queue_free()
	await process_frame


func _test_aftermath_order() -> void:
	var aftermath: Node = BattleAftermath.new()
	root.add_child(aftermath)
	var units := [
		{"id": "hero", "actor_id": "001", "coord": Vector2i(2, 2), "dead_message": {"messages": []}},
		{"id": "foe", "actor_id": "021", "coord": Vector2i(2, 3), "dead_message": {"messages": []}},
	]
	var receipt := {"sequence": 1, "attacker_id": "hero", "defender_id": "foe", "defender_hp_before": 5, "defender_hp_after": 0,
		"hit": true, "kill_chain": 3, "experience": {"gained": 26, "level_before": 1, "level_after": 3, "exp_before": 90, "exp_after": 16},
		"rewards": {"gold": 100, "kills": [{"attacker_id": "hero", "defender_id": "foe"}]}}
	aftermath.prepare(receipt, units)
	_assert_eq(aftermath.jobs.map(func(job): return job["kind"]), ["death", "experience", "gold", "level_up"], "0x442720: EXP → $ → LEVEL UP after the death, one LEVEL UP for two levels")
	_assert_eq(int(aftermath.jobs[0]["kill_count"]), 3, "the victim carries its killer's chain for its KILL float")
	var countered := {"sequence": 2, "attacker_id": "foe", "defender_id": "hero", "defender_hp_before": 9, "defender_hp_after": 4,
		"hit": true, "kill_chain": 0, "counter": {"attacker_id": "hero", "defender_id": "foe", "defender_hp_before": 3, "defender_hp_after": 0, "hit": true, "kill_chain": 2}}
	aftermath.cursor = aftermath.jobs.size()
	aftermath.prepare(countered, units)
	_assert_eq(int(aftermath.jobs[0]["kill_count"]), 2, "an attacker a counter killed floats the counter's chain")
	aftermath.cursor = aftermath.jobs.size()
	var both_level := {"sequence": 3, "attacker_id": "hero", "defender_id": "foe", "defender_hp_before": 9, "defender_hp_after": 4, "hit": true,
		"experience": {"gained": 19, "level_before": 1, "level_after": 2},
		"counter": {"attacker_id": "foe", "defender_id": "hero", "defender_hp_before": 9, "defender_hp_after": 7, "hit": true, "experience": {"gained": 1, "level_before": 1, "level_after": 1}}}
	aftermath.prepare(both_level, units)
	_assert_eq(aftermath.jobs.map(func(job): return "%s@%s" % [job["kind"], str(job["coord"])]), ["experience@(2, 2)", "level_up@(2, 2)", "experience@(2, 3)"], "each recipient's EXP → LEVEL UP before the countering target's EXP (recording 501.48／502.05／502.70)")
	aftermath.cursor = aftermath.jobs.size()
	aftermath.queue_free()
	await process_frame


func _test_resist_row() -> void:
	_assert_eq([BattleVitals.resist_text(7), BattleVitals.resist_text(0), BattleVitals.resist_text(79), BattleVitals.resist_text(80), BattleVitals.resist_text(95)], ["07%", "00%", "79%", "MAX", "MAX"], "0x434d10 prints two digits and %, MAX from 80")
	var vitals: Control = BattleVitals.new()
	root.add_child(vitals)
	_assert_eq(vitals.resist_gems.size(), 5, "five element gems")
	for index in range(5):
		_assert_true(vitals.resist_gems[index].texture.resource_path.ends_with("panels/magicon%d.png" % (index + 1)), "gem %d is MAGICON%d" % [index, index + 1])
		_assert_eq(vitals.resist_gems[index].position, Vector2(146 + 48 * index, 128), "gem %d at the docked-window frames' (146 + 48·i, 142 − 14)" % index)
		_assert_eq(vitals.resist_values[index].position.x, 156.0 + 48 * index, "value %d cell starts 10 px after its gem (ink at +12)" % index)
	vitals.queue_free()
	await process_frame


# ---- run_skill_effect_script_tests.gd ----
## Map actor pose, LEVEL UP stars and the red damage digits (lane R7-POSE,
## docs/evidence_packets/runtime_observations/map_pose_floaters/README.md).
## Pose: 0x4071e0 plays the SHAPEDEF use_magic frames forward at delay 3, holds the last one
## 40 ticks, plays them back and returns to standing (8 × frames + 40 ticks); its three caller
## classes (map spell lead end, item use, level-up) are the only callers in the game scripts.
## Stars: 0x415c10(x, y, 149, 64, 24, 0, 6, 36) and effProcFlyUpShape → effProcFlyUp2.
## Digits: defProcShowNumber kind 0 (0x40863e) replayed tick by tick — digits appear from the
## left every 10 ticks, the number does not rise, life 10 × digits + 34 ticks.

const ActorRuntime = preload("res://game/battle/runtime/ActorRuntime.gd")
const LevelUpStars = preload("res://game/battle/scene/LevelUpStars.gd")
const DamageNumberFloater = preload("res://game/battle/scene/DamageNumberFloater.gd")
const WALK_MANIFEST := "res://content/imported/hsl/chapter01/actor_walk_frames/actor_walk_manifest.json"
const POSE_MANIFEST := "res://content/imported/hsl/shared/actor_magic_poses/manifest.json"


func run_map_pose_floaters() -> void:
	_test_pose_schedule()
	_test_pose_census()
	await _test_actor_plays_the_pose()
	_test_pose_callers()
	await _test_star_shower()
	_test_damage_digit_states()
	await _test_damage_digit_node()


func _test_pose_schedule() -> void:
	var frames: Array[int] = []
	for tick in range(90):
		frames.append(ActorRuntime.magic_pose_frame(tick, 6))
	_assert_eq([frames[0], frames[3], frames[4], frames[19], frames[20]], [0, 0, 1, 4, 5], "forward at delay 3: each use_magic frame shows 4 ticks (0x45e575)")
	_assert_eq([frames[23], frames[24], frames[63], frames[64], frames[67]], [5, 5, 5, 5, 5], "the last frame holds through +0x92 = 40 (ticks 20–67)")
	_assert_eq([frames[68], frames[72], frames[76], frames[80], frames[84], frames[87]], [4, 3, 2, 1, 0, 0], "played back one frame per 4 ticks (0x45e660)")
	_assert_eq([frames[88], frames[89]], [-1, -1], "the pose is over at 8 × 6 + 40 = 88 ticks; standing resumes")
	_assert_eq(ActorRuntime.magic_pose_frame(8 * 5 + 40 - 1, 5), 0, "five frames (044 lacks M0002) end at 8 × 5 + 40")
	_assert_eq(ActorRuntime.magic_pose_frame(8 * 5 + 40, 5), -1, "and not a tick later")


func _test_pose_census() -> void:
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(POSE_MANIFEST))
	_assert_eq(manifest["program"]["frame_delay"], 3, "the manifest records 0x4071e0's delay 3")
	var walk: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(WALK_MANIFEST))
	var undeclared: Array = []
	for key in walk["actors"]:
		if ActorRuntime.magic_pose_entry(key).is_empty() and not key in manifest["use_magic_is_stand"] and not key in manifest["without_use_magic"]:
			undeclared.append(key)
	_assert_eq(undeclared, [], "every first-chapter walk key has use_magic frames or a declared reason not to")
	_assert_eq(ActorRuntime.magic_pose_entry("001")["frames"].size(), 6, "雷歐納德 has the six 001-M frames")
	_assert_eq(ActorRuntime.magic_pose_entry("026")["frames"].size(), 6, "帝國法師 026 (the recording's caster) has six")


func _test_actor_plays_the_pose() -> void:
	var walk: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(WALK_MANIFEST))
	var actor: Node2D = ActorRuntime.new()
	root.add_child(actor)
	actor.configure_from_manifest("probe", walk["actors"]["026"])
	actor.play_state("idle", "0")
	var standing: String = actor.get_node("Sprite2D").texture.resource_path
	_assert_true(actor.play_use_magic(), "026 takes the use_magic pose")
	_assert_true(actor.is_posing() and _sprite(actor).ends_with("/026-M0001.png"), "the pose starts on M0001 (%s)" % _sprite(actor))
	actor._process(OriginalTick.seconds(20.5))
	_assert_true(_sprite(actor).ends_with("/026-M0006.png"), "tick 20 reaches the last frame (%s)" % _sprite(actor))
	actor._process(OriginalTick.seconds(40.0))
	_assert_true(_sprite(actor).ends_with("/026-M0006.png"), "held at tick 60 (%s)" % _sprite(actor))
	actor._process(OriginalTick.seconds(10.0))
	_assert_true(_sprite(actor).ends_with("/026-M0005.png"), "one frame back by tick 70 (%s)" % _sprite(actor))
	actor._process(OriginalTick.seconds(18.0))
	_assert_true(not actor.is_posing() and actor.animation_state == "idle" and _sprite(actor) == standing, "standing again after 88 ticks (%s)" % _sprite(actor))
	_assert_true(actor.play_use_magic(), "a second pose starts over")
	actor.set_shape_override([{"res_path": "res://content/imported/hsl/shared/actor_hit_poses/026-P.png", "draw_origin": [30, 50]}])
	_assert_true(not actor.is_posing() and _sprite(actor).ends_with("/026-P.png"), "a death hit pose ends the casting pose")
	actor.clear_shape_override()
	_assert_true(actor.play_use_magic(), "posing again")
	actor.move_along([actor.position + Vector2(32, 0)], 0.2)
	_assert_true(not actor.is_posing(), "walking ends the pose")
	actor.queue_free()
	await process_frame
	var stand_only: Node2D = ActorRuntime.new()
	root.add_child(stand_only)
	stand_only.actor_id = "060"
	_assert_true(not stand_only.play_use_magic() and not stand_only.is_posing(), "060, whose use_magic is its stand shape, keeps its frames")
	stand_only.queue_free()
	await process_frame


func _sprite(actor: Node2D) -> String:
	return actor.get_node("Sprite2D").texture.resource_path


## The original's three 0x4071e0 caller classes are the remake's only play_use_magic callers.
func _test_pose_callers() -> void:
	var callers := {}
	for path in _game_scripts_map_pose_floaters("res://game"):
		if path.ends_with("/ActorRuntime.gd"): continue
		var text := FileAccess.get_file_as_string(path)
		if text.contains("play_use_magic("): callers[path] = true
	_assert_eq(callers.keys().map(func(path): return path.get_file()), ["BattleAftermath.gd", "BattlePresentation.gd"], "only the aftermath (level-up) and the presentation (spell lead end, item use) pose actors")
	var aftermath := FileAccess.get_file_as_string("res://game/battle/scene/BattleAftermath.gd")
	var level_up := aftermath.substr(aftermath.find("func _present_level_up"), 900)
	_assert_true(level_up.contains("play_use_magic()") and level_up.contains("LevelUpStars.new()"), "the LEVEL UP stage poses the recipient and scatters its stars (0x442720 phase 6)")
	var presentation := FileAccess.get_file_as_string("res://game/battle/scene/BattlePresentation.gd")
	var item_use := FileAccess.get_file_as_string("res://game/battle/scene/BattleItemUsePresentation.gd")
	_assert_true(item_use.substr(item_use.find("func _start_effect"), 700).contains("_pose_unit("), "item use poses its user (0x4449a7／0x440366／0x4404c7)")
	_assert_true(presentation.contains("\t_sync_cast_pose()\n"), "every refresh checks the running spell clip for the caster pose")


func _test_star_shower() -> void:
	var stars: Node2D = LevelUpStars.new()
	root.add_child(stars)
	stars.begin(12345)
	_assert_eq(stars.stars.size(), 36, "0x415c10 scatters 0x24 = 36 stars")
	var bad_offsets := 0
	var bad_speeds := 0
	var bad_holds := 0
	var bad_steps := 0
	var last_appear := 0
	for index in range(stars.stars.size()):
		var star: Dictionary = stars.stars[index]
		var offset: Vector2 = star["offset"]
		if offset.x < -31 or offset.x > 32 or offset.y < -11 or offset.y > 12: bad_offsets += 1
		var steps := (float(star["speed"]) - 0.25) * 16.0
		if steps < 0.0 or steps > 31.0 or not is_equal_approx(steps, roundf(steps)): bad_speeds += 1
		if int(star["hold"]) < 6 or int(star["hold"]) > 13: bad_holds += 1
		if index > 1 and (int(star["appear"]) - last_appear < 1 or int(star["appear"]) - last_appear > 6): bad_steps += 1
		last_appear = int(star["appear"])
	_assert_eq([bad_offsets, bad_speeds, bad_holds, bad_steps], [0, 0, 0, 0], "stars within x + [−31, 32], y + [−11, 12]; speed 0.25 + k／16 px; hold 6..13; delays 1..6 apart")
	_assert_eq(stars.stars[0]["appear"], 0, "the first star draws at once")
	var texture_ok := true
	for index in range(36):
		var sprite: Sprite2D = stars.get_child(index)
		texture_ok = texture_ok and sprite.texture.resource_path.ends_with("level_up_star_%d.png" % int(stars.stars[index]["frame"])) and sprite.material == AdditiveLevelBlend.material()
	_assert_true(texture_ok, "each star holds one random AIR06_03..06 frame, drawn additively")
	_assert_eq([LevelUpStars.level(0, 8), LevelUpStars.level(9, 8), LevelUpStars.level(10, 8), LevelUpStars.level(24, 8), LevelUpStars.level(25, 8)], [16, 16, 15, 1, 0], "full level for hold + 1 ticks after the first, then −1 a tick (0x422c9a)")
	_assert_eq([LevelUpStars.rise_at(0, 1.5), LevelUpStars.rise_at(1, 1.5), LevelUpStars.rise_at(3, 1.5)], [0.0, 1.0, 4.0], "straight up by floor(speed × age) (0x45ebdc keeps the fraction)")
	stars.advance(OriginalTick.seconds(0.5))
	var first: Sprite2D = stars.get_child(0)
	_assert_true(first.visible and first.position == Vector2(stars.stars[0]["offset"]), "the first star is drawn at its spawn offset on tick 0")
	var end_tick := 0
	for star in stars.stars:
		end_tick = maxi(end_tick, int(star["appear"]) + int(star["hold"]) + 17)
	_assert_true(stars.advance(OriginalTick.seconds(end_tick - 1.5)), "stars are alive until the last one fades")
	_assert_true(not stars.advance(OriginalTick.seconds(1.5)) and not stars.visible, "then the shower is over (%d ticks)" % end_tick)
	var again: Node2D = LevelUpStars.new()
	root.add_child(again)
	again.begin(12345)
	_assert_eq(again.stars, stars.stars, "the same exchange and recipient scatter the same stars")
	stars.queue_free()
	again.queue_free()
	await process_frame


func _test_damage_digit_states() -> void:
	_assert_eq(DamageNumberFloater.state_at(0, 2)["visible"], 0, "the hold tick draws nothing")
	var tick1 := DamageNumberFloater.state_at(1, 2)
	_assert_eq([tick1["visible"], tick1["newest"], tick1["previous"], tick1["flash"], tick1["flash_level"]], [1, 1, 0, 1, 16], "tick 1: only the first (leftmost) digit, at 2×, with the NUM510 flash at level 16")
	_assert_eq([DamageNumberFloater.state_at(6, 2)["flash_level"], DamageNumberFloater.state_at(7, 2)["flash"]], [11, 0], "the flash burns 6 ticks, 16 → 11")
	var tick10 := DamageNumberFloater.state_at(10, 2)
	_assert_eq([tick10["visible"], tick10["newest"], tick10["previous"], tick10["flash"]], [2, 2, 1, 2], "tick 10: the second digit joins at 2×, the first at 1.5×, the flash moves to it")
	_assert_eq(DamageNumberFloater.state_at(11, 2)["previous"], 0, "the 1.5× step lasts to the next half-step")
	var tick20 := DamageNumberFloater.state_at(20, 2)
	_assert_eq([tick20["visible"], tick20["newest"], tick20["previous"]], [2, 0, 2], "tick 20: past the last digit only the 1.5× step remains")
	var tick21 := DamageNumberFloater.state_at(21, 2)
	_assert_eq([tick21["visible"], tick21["newest"], tick21["previous"], tick21["level"]], [2, 0, 0, 16], "then the whole number stands at 1×")
	_assert_eq([DamageNumberFloater.state_at(38, 2)["level"], DamageNumberFloater.state_at(39, 2)["level"], DamageNumberFloater.state_at(53, 2)["level"]], [16, 15, 1], "18 settle ticks, then the level drops a tick")
	_assert_true(not DamageNumberFloater.state_at(54, 2)["alive"], "deleted at level 0")
	_assert_eq([DamageNumberFloater.life_ticks(1), DamageNumberFloater.life_ticks(2), DamageNumberFloater.life_ticks(3)], [44, 54, 64], "life 10 × digits + 34 (original_tick_counts §1)")
	_assert_true(DamageNumberFloater.state_at(43, 1)["alive"] and not DamageNumberFloater.state_at(44, 1)["alive"], "a one-digit number lives 44 ticks")
	var three := []
	for tick in [1, 10, 20, 30]:
		three.append(DamageNumberFloater.state_at(tick, 3)["visible"])
	_assert_eq(three, [1, 2, 3, 3], "digits appear one by one, left to right, every 10 ticks")


func _test_damage_digit_node() -> void:
	var number: Node2D = DamageNumberFloater.new()
	root.add_child(number)
	number.position = Vector2(200, 150)
	number.present(57)
	_assert_true(number.glyphs[0].texture.resource_path.ends_with("damage_digit_5.png") and number.glyphs[1].texture.resource_path.ends_with("damage_digit_7.png"), "NUM105 then NUM107: the digits in reading order")
	_assert_eq([number.glyphs[0].position, number.glyphs[1].position], [Vector2(-7, 0), Vector2(7, 0)], "first digit at x − 7 × (digits − 1), 14 px apart")
	number.set_process(false)
	number.advance(OriginalTick.seconds(1.5))
	_assert_true(number.glyphs[0].visible and not number.glyphs[1].visible and number.glyphs[0].scale == Vector2(2, 2), "tick 1 shows the leftmost digit at 2× — the recording's 203.25 s 「2」 of 「22」")
	_assert_true(number.flash.visible and number.flash.scale == Vector2(4, 4) and number.flash.material == AdditiveLevelBlend.material(), "behind it the 4× additive NUM510 flash")
	number.advance(OriginalTick.seconds(9.0))
	_assert_true(number.glyphs[1].visible and number.glyphs[1].scale == Vector2(2, 2) and number.glyphs[0].scale == Vector2(1.5, 1.5), "tick 10 completes 「57」")
	var positions := []
	for tick in range(40):
		number.advance(OriginalTick.TICK_SECONDS)
		positions.append(number.position.y + number.glyphs[0].position.y)
	_assert_eq(positions.filter(func(y): return y != 150.0), [], "kind 0 does not rise (no 0x10000 toggle)")
	var finished := [false]
	number.finished.connect(func(): finished[0] = true)
	number.advance(OriginalTick.seconds(20.0))
	_assert_true(finished[0] and not number.visible, "finished once the level reaches 0")
	number.queue_free()
	await process_frame


func _game_scripts_map_pose_floaters(directory: String) -> Array[String]:
	var found: Array[String] = []
	for file in DirAccess.get_files_at(directory):
		if file.ends_with(".gd"): found.append("%s/%s" % [directory, file])
	for sub in DirAccess.get_directories_at(directory):
		found.append_array(_game_scripts_map_pose_floaters("%s/%s" % [directory, sub]))
	return found
