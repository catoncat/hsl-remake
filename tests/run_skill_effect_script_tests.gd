extends "res://tests/support/TestSuite.gd"
## SkillEffectScriptPlayer: EFFECTS.TXT specCode (special) and effCode (magic) scripts → tick
## timelines, without a scene. Green here proves the interpreter's contract over the tracked
## scripts and manifest, not the original clock or geometry (both provisional; see
## skill_effects/manifest.json policy).
const Player = preload("res://game/battle/scene/SkillEffectScriptPlayer.gd")
const PoisonArrow = preload("res://game/sim/PoisonArrowRules.gd")
const MoonDance = preload("res://game/sim/RepeatedSpecialRules.gd")
const Motion = preload("res://game/battle/scene/EffectObjectMotion.gd")
var manifest: Dictionary
var scope: Dictionary
var motion: Dictionary


func _init() -> void:
	tag = "SKILL_EFFECT_SCRIPT_TESTS"


func run() -> void:
	manifest = JSON.parse_string(FileAccess.get_file_as_string(Player.MANIFEST_PATH))
	scope = JSON.parse_string(FileAccess.get_file_as_string(Player.SCRIPTS_PATH))
	motion = JSON.parse_string(FileAccess.get_file_as_string(Motion.PATH))
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


## The importer's declarations and the player's spelling agree; every SPECIAL and MAGIC row
## has one presentation and the two dedicated rows are the ids the cut-in routes to modules.
func manifest_contracts() -> void:
	check(manifest["implemented_opcodes"] == Player.IMPLEMENTED_OPCODES, "manifest implemented_opcodes and the player's list are the same spelling and order")
	check(Player.IMPLEMENTED_OPCODES.size() == 28 and scope["opcode_counts"].keys().all(func(op): return Player.IMPLEMENTED_OPCODES.has(op)), "every opcode the 99 rows use is implemented (24 ani* + 4 eff*)")
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
	check(manifest["rows"][PoisonArrow.ID]["presentation"] == "dedicated_module" and str(manifest["rows"][PoisonArrow.ID]["module"]) == "PoisonArrowPresentation.gd", "毒魔箭 keeps PoisonArrowPresentation")
	check(manifest["rows"][MoonDance.ID]["presentation"] == "dedicated_module" and str(manifest["rows"][MoonDance.ID]["module"]) == "MoonDancePresentation.gd", "月花圓舞 keeps MoonDancePresentation")
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
	for member in manifest["missing_members"]:
		check(script_members.has(member) or motion["members"].has(member), "a missing member is named by a scope object or a native track: " + str(member))
		check(not manifest["frames"].has(member), "missing and imported are disjoint: " + str(member))
		if not script_members.has(member):
			check(_tracked_drawers(member).size() > 0 and _tracked_drawers(member).all(func(name): return motion["objects"].has(name)), "a track-only missing member is drawn only by tracked objects (the player cycles its series): " + str(member))
	check(manifest["missing_members"].filter(func(member): return str(member).begins_with("MAGIC\\SP08_")).size() == 40, "the 40 SP08 shape names hsl.pak lacks stay declared missing (negative-evidence)")
	for name in manifest["objects"]:
		var object: Dictionary = manifest["objects"][name]
		check(int(object["frame_ticks"]) == int(object["shape_delay"]) + 1, "frame_ticks is shape_delay + 1: " + name)
		check(object["shape_members"].any(func(member): return manifest["frames"].has(member)), "every object has at least one imported frame: " + name)
		check(object["zoom"].size() == 2 and float(object["zoom"][0]) != 0.0 and float(object["zoom"][1]) != 0.0, "every object carries its obj_ZoomX／Y scale (obj_Special43_06 mirrors with −1): " + name)
		check(str(object["insert_sound"]) == "" or manifest["sounds"].has(object["insert_sound"]), "an obj_X1 insertion WAV is imported: " + name)
	check(manifest["objects"]["obj_Effect_FireBomb"]["zoom"] == [1.25, 1.25] and manifest["objects"]["obj_Effect_AirBlade1"]["insert_sound"] == "WAV\\WIND0001.WAV" and manifest["objects"]["obj_Effect_AirBlade1"]["effect_process"] == "effProcFade", "obj_Effect_FireBomb reads engZOOM 0x14000 as 1.25; obj_Effect_AirBlade1 plays WIND0001 on insertion and names its unrestored effProcFade program")
	for member in manifest["frames"]:
		check(str(manifest["frames"][member]["res_path"]).begins_with("res://content/imported/hsl/shared/skill_effects/frames/") and manifest["frames"][member]["draw_origin"].size() == 2, "frame record shape: " + member)
	check(manifest["totals"]["frames"] == manifest["frames"].size() and manifest["totals"]["missing_members"] == manifest["missing_members"].size() and manifest["totals"]["sounds"] == 124 and manifest["totals"]["objects"] == 365, "totals mirror the frame／missing sets; 124 sounds (111 script／obj_X1 + 7 objcomd-only + 6 effect-program-only), 365 objects (221 special + 144 magic)")


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


## parse() yields one instruction per ani*／eff* token, in source order, with the tokens up to
## the next verb as its arguments — so the instruction count equals the row's opcode occurrences.
func parse_contracts() -> void:
	var parsed := Player.parse(["aniDelay,20,aniInsertObject,obj_Special01_02,700,160", "aniDelay,10,aniProcessHitMiss"])
	check(parsed.size() == 4 and parsed[1]["op"] == "aniInsertObject" and parsed[1]["args"] == ["obj_Special01_02", "700", "160"] and parsed[3]["args"] == [], "instructions split at each ani* token and keep argument order")
	var effect := Player.parse(["effInsertObject,obj_Effect_AirBlade1,0,0,effWait,10", "effPlaySound,WAV\\WIND0001.WAV"])
	check(effect.size() == 3 and effect[0]["args"] == ["obj_Effect_AirBlade1", "0", "0"] and effect[1] == {"op": "effWait", "args": ["10"]} and effect[2]["args"] == ["WAV\\WIND0001.WAV"], "eff* verbs open instructions the same way")
	check(Player.number("-0x00000800") == -2048 and Player.number("0x00c60000") == 12976128 and Player.number("-100") == -100 and is_equal_approx(Player.fixed16("0x00018000"), 1.5), "hex, negative hex and decimal arguments parse")
	var total := 0
	for skill_id in scope["rows"]:
		var row: Dictionary = scope["rows"][skill_id]
		var expected := 0
		var got := 0
		for code in row["actions"]:
			got += Player.parse(row["actions"][code]).size()
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
	var player := Player.new()
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
			check(timeline["events"].size() == other["events"].size(), "the seed changes placements, not the event set: " + skill_id)
			var release := int(timeline["release_tick"])
			var impact := int(timeline["impact_tick"])
			var result := int(timeline["result_tick"])
			var complete := int(timeline["complete_tick"])
			check(release > 0 and release <= impact and impact <= result and result < complete, "release ≤ impact ≤ result < complete: %s %s" % [skill_id, str([release, impact, result, complete])])
			check(not timeline["hit_ticks"].is_empty(), "every defense script marks its hit: " + skill_id)
			check(not timeline["result_ticks"].is_empty() or result == impact, "a script without aniShowHitResult shows the result on the hit mark: " + skill_id)
			check(complete >= result + Player.RESULT_HOLD_TICKS, "the result stays readable: " + skill_id)
			var row: Dictionary = scope["rows"][skill_id]
			check(int(timeline["instructions"]) == Player.parse(row["actions"][row["attack_code"]]).size() + Player.parse(row["actions"][row["defense_code"]]).size(), "instruction count kept: " + skill_id)
			var hit_only_seen := false
			for event in timeline["events"]:
				check(int(event["tick"]) >= 0 and int(event.get("expire", event["tick"])) <= complete, "event inside the clip: " + skill_id)
				if event["kind"] == "sound":
					check(manifest["sounds"].has(event["member"]), "sound imported: %s %s" % [skill_id, event["member"]])
					continue
				check(manifest["objects"].has(event["object"]) and int(event["expire"]) > int(event["tick"]), "object drawn from the manifest with a positive lifetime: " + skill_id)
				for member in event["frames"]:
					check(manifest["frames"].has(member), "object frame imported: " + str(member))
				check(event["motion"] in ["static", "fly", "radial", "spin"], "known motion: " + str(event["motion"]))
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
func every_magic_row_compiles() -> void:
	var player := Player.new()
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
		check(int(timeline["instructions"]) == Player.parse(row["actions"][row["effect_code"]]).size() and int(timeline["instructions"]) > 0, "instruction count kept: " + skill_id)
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
				check(event["motion"] == "native" and not event.has("fade_tick") and int(event["expire"]) == int(event["tick"]) + int(motion["objects"][event["object"]]["frames"]) and bool(event["anchored"]) == (motion["objects"][event["object"]]["motion"] == "anchored"), "a tracked effect object plays its native track for exactly its frames: " + skill_id)
			else:
				# The 13 objects stopped at an unreviewed callee keep the provisional static hold.
				check(motion["unrestored"].has(event["object"]), "an untracked effect object is listed unrestored: " + str(event["object"]))
				check(event["motion"] == "static" and event.has("fade_tick") and int(event["fade_tick"]) >= int(event["tick"]) + Player.EFFECT_MIN_LIFETIME_TICKS and int(event["expire"]) == int(event["fade_tick"]) + Player.EFFECT_FADE_TICKS, "untracked effect objects stay put, hold at least the minimum lifetime and fade: " + skill_id)
				check(int(event["fade_tick"]) - int(event["tick"]) <= maxi(int(event["lifetime"]), Player.EFFECT_MIN_LIFETIME_TICKS) and int(event["fade_tick"]) <= maxi(int(event["tick"]) + Player.EFFECT_MIN_LIFETIME_TICKS, int(timeline["complete_tick"]) - Player.EFFECT_FADE_TICKS), "an untracked object never holds past its own frames or the script's remaining waits: " + skill_id)
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
	var player := Player.new()
	root.add_child(player)
	var hit: Dictionary = player.compile_row("special:magicOTHER:magicCode01", true, 1)
	check(hit["release_tick"] == 60 and hit["impact_tick"] == 90 and hit["result_tick"] == 150 and hit["complete_tick"] == 190, "氣刃斬 marks: %s" % str([hit["release_tick"], hit["impact_tick"], hit["result_tick"], hit["complete_tick"]]))
	check(hit["attack_background"] == "MAGIC\\SP00_001.SHP" and hit["defense_background"] == "", "the attack script's aniInsertSpecialBG panel; the defense keeps the backdrop")
	var sounds: Array = hit["events"].filter(func(event): return event["kind"] == "sound")
	check(sounds[0]["tick"] == 0 and sounds[0]["member"] == "WAV\\SP01-001.WAV", "the attack script's aniPlaySound at tick 0")
	# obj_Special01_03's objcomd.txt command 2 opens with objmPlaySound,WAV\BOMB0017.WAV: each
	# of the 6 bursts plays the landing sound as it appears, within 90..94.
	var burst_ticks: Array = []
	for event in hit["events"]:
		if event["kind"] == "object" and event["object"] == "obj_Special01_03":
			burst_ticks.append(int(event["tick"]))
	var landing: Array = sounds.filter(func(event): return event["member"] == "WAV\\BOMB0017.WAV").map(func(event): return int(event["tick"]))
	burst_ticks.sort()
	landing.sort()
	check(landing.size() == 6 and landing == burst_ticks and landing.all(func(tick): return tick >= 90 and tick <= 94), "the landing sound WAV\\BOMB0017.WAV sounds with the impact bursts at %s (bursts %s)" % [str(landing), str(burst_ticks)])
	check(sounds.size() == 1 + landing.size(), "no other sound: %s" % str(sounds.map(func(event): return event["member"])))
	var flights: Array = hit["events"].filter(func(event): return event["kind"] == "object" and event["motion"] == "fly")
	check(flights.size() == 2 and flights[0]["tick"] == 0 and flights[0]["arrive"] == 30 and flights[1]["tick"] == 80 and flights[1]["arrive"] == 90, "the blade flies for FLIGHT_TICKS in the attack shot and lands on aniProcessHitMiss in the defense shot")
	check(flights[1]["position"] == Vector2(700, 160) and flights[1]["frames"] == ["MAGIC\\SP01_001.SHP", "MAGIC\\SP01_002.SHP"], "the defense blade is obj_Special01_02 at (700,160)")
	var bursts: Array = hit["events"].filter(func(event): return event["kind"] == "object" and event["motion"] == "static")
	check(bursts.size() == 30 and bursts.all(func(event): return int(event["tick"]) >= 90 and int(event["tick"]) <= 94 and (event["position"] as Vector2).distance_to(Vector2(320, 160)) <= 90), "6 + 24 hit sparks appear within the delay range around the target centre")
	var miss: Dictionary = player.compile_row("special:magicOTHER:magicCode01", false, 1)
	check(miss["events"].filter(func(event): return event["kind"] == "object").size() == 2 and miss["impact_tick"] == 90 and miss["complete_tick"] == 190, "a miss keeps the blades and the marks, drops the hit-only sparks")
	check(miss["events"].filter(func(event): return event["kind"] == "sound").map(func(event): return event["member"]) == ["WAV\\SP01-001.WAV"], "a miss inserts no burst, so no landing sound")
	var other2: Dictionary = player.compile_row("special:magicOTHER2:magicCode01", true, 1)
	check(other2["events"].any(func(event): return event["kind"] == "sound" and event["member"] == "WAV\\BOMB0017.WAV" and int(event["tick"]) >= 90), "the magicOTHER2 row of 氣刃斬 (specCode121／122, its own obj_Special61 blades) lands with the same BOMB0017 burst")
	player.free()


## Every special object's objcomd.txt command sounds (manifest `command_sounds`) reach the
## timeline of every script row that inserts it, on its own insertion tick plus the objmDelay
## ticks ahead of the cue; objmPlayHitSound only on a hit; an object whose frames cannot be
## drawn still sounds. 39 objects in 24 rows carry command sounds.
func object_command_sounds() -> void:
	var player := Player.new()
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
			for event in timeline["events"]:
				if event["kind"] != "object": continue
				for sound in manifest["objects"][event["object"]]["command_sounds"]:
					if bool(sound["hit_only"]) and not hit:
						continue
					expected += 1
					var key := str(sound["member"]) + "@" + str(int(event["tick"]) + int(sound["delay_ticks"]))
					check(int(cues.get(key, 0)) > 0, "%s %s: %s sounds at insertion %d + %d" % [skill_id, "hit" if hit else "miss", sound["member"], int(event["tick"]), int(sound["delay_ticks"])])
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
	var bare: Dictionary = Player.compile(row["actions"][row["attack_code"]], row["actions"][row["defense_code"]], true, 1, data)
	check(bare["skipped_objects"] == ["obj_Special01_03"] and bare["events"].any(func(event): return event["kind"] == "sound" and event["member"] == "WAV\\BOMB0017.WAV"), "a burst without imported frames still plays its landing sound")
	player.free()


## Every effect object's obj_Y1／obj_X2 cues (manifest `program_sounds`, the effProc* program's
## own events) reach the timeline of every magic row that inserts it, at the object's start plus
## the read delay, inside the clip. 13 objects in 8 spells.
func effect_program_sounds() -> void:
	var player := Player.new()
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
		for event in timeline["events"]:
			if event["kind"] != "object": continue
			for sound in manifest["objects"][event["object"]]["program_sounds"]:
				expected += 1
				var at := int(event["tick"]) + int(sound["delay_ticks"])
				check(cues.has(str(sound["member"]) + "@" + str(at)) and at <= int(timeline["complete_tick"]), "%s: %s (%s) sounds at start %d + %d inside the clip" % [skill_id, sound["member"], sound["field"], int(event["tick"]), int(sound["delay_ticks"])])
		if expected > 0: rows += 1
	check(rows == 8, "8 spells play effect-program cues: %d" % rows)
	# 烈蝕水彈 (effCode10): obj_Effect_WaterBig1 enters at 40, fires SHOOT002 (+0x46) then bursts WATER008 (+0x44).
	var ball: Dictionary = player.compile_row("magic:magicWATER:magicCode03", true, 7)
	var ticks := {}
	for event in ball["events"]:
		if event["kind"] == "sound": ticks[str(event["member"])] = int(event["tick"])
	check(ticks.get("WAV\\SHOOT002.WAV", -1) == 40 + 217 and ticks.get("WAV\\WATER008.WAV", -1) == 40 + 242, "烈蝕水彈: SHOOT002 at 257, WATER008 at 282: %s" % str(ticks))
	player.free()


## 天雷猛襲劍 (specCode03／04): the attack script runs 70 ticks; the defense script's
## sounds and lightning strikes land on their aniDelay cursors; hit sound and burst are hit-only.
func thunder_sword_timeline() -> void:
	var player := Player.new()
	root.add_child(player)
	var hit: Dictionary = player.compile_row("special:magicAIR:magicCode01", true, 3)
	check(hit["release_tick"] == 70 and hit["impact_tick"] == 160 and hit["result_tick"] == 200 and hit["complete_tick"] == 240, "天雷猛襲劍 marks: %s" % str([hit["release_tick"], hit["impact_tick"], hit["result_tick"], hit["complete_tick"]]))
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
	var player := Player.new()
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
	check(stars["hit_ticks"].size() == 1 and stars["impact_tick"] == 30 + 20 + 40 + 10, "aniProcessHitMissMulti marks the impact like aniProcessHitMiss")
	var meteors: Array = stars["events"].filter(func(event): return event["kind"] == "object" and event["object"] == "obj_Special24_03")
	check(meteors.size() == 10 and meteors.all(func(event): return event["motion"] == "fly" and int(event["arrive"]) == (stars["impact_tick"] if int(event["tick"]) < int(stars["impact_tick"]) else int(event["tick"]) + Player.FLIGHT_TICKS)), "meteors inserted above the stage fly to the target centre: onto the hit mark when it follows, else for FLIGHT_TICKS")
	check(stars["result_ticks"].is_empty() and stars["result_tick"] == stars["impact_tick"] and stars["complete_tick"] == 100 + 160, "a script without aniShowHitResult shows the result on the hit mark and completes when its last delay ends")
	var empty: Dictionary = Player.compile([], ["aniDelay,10,aniProcessHitMiss", "aniDelay,5,aniShowHitResult"], true, 1, manifest)
	check(empty["release_tick"] == Player.EMPTY_ATTACK_LEAD_TICKS and empty["impact_tick"] == 40 and empty["result_tick"] == 45 and empty["complete_tick"] == 85 and empty["events"].is_empty(), "an empty attack script still leads for EMPTY_ATTACK_LEAD_TICKS")
	var unknown: Dictionary = Player.compile([], ["aniSetZoom,0x10000", "aniDelay,4"], true, 1, manifest)
	check(unknown["unimplemented"] == ["aniSetZoom"], "a verb outside the set is reported, not swallowed")
	player.free()


## 風刃 (effCode16): two random wave batches at 0／4, the blades at 54／64 — the last insertion
## is the impact mark — each object's obj_X1 WAV once per instruction; every object now plays
## its native track, so a clip completes when the script's waits and the last tree are done.
## 幻火's bombs carry the engZOOM 1.25 scale; 極 plays at the screen centre; 治癒之水 does not dim.
func magic_timelines() -> void:
	var player := Player.new()
	root.add_child(player)
	var wind: Dictionary = player.compile_row("magic:magicAIR:magicCode01", true, 1)
	check(wind["instructions"] == 8 and wind["impact_tick"] == 64 and wind["complete_tick"] == _derived_complete(wind, 114) and not wind["global"] and wind["dim"], "風刃 marks: impact 64, complete = the later of its 114 waits and its trees' ends: %s" % str([wind["instructions"], wind["impact_tick"], wind["complete_tick"]]))
	var objects: Array = wind["events"].filter(func(event): return event["kind"] == "object")
	check(objects.size() == 14 and objects.filter(func(event): return event["object"] == "obj_Effect_AirWave1").size() == 6 and objects.filter(func(event): return event["object"] == "obj_Effect_AirBlade2" and event["tick"] == 64 and event["position"] == Vector2.ZERO).size() == 1, "6 + 6 waves, then the two blades at the origin")
	check(objects.filter(func(event): return event["object"] == "obj_Effect_AirWave1").all(func(event): return (event["position"] as Vector2).x >= -4.0 and (event["position"] as Vector2).x <= 5.0 and (event["position"] as Vector2).y >= -17.0 and (event["position"] as Vector2).y <= 18.0), "effInsertRandomObject folds rand(x range 10) into −4..5 and rand(y range 36) into −17..18 around the displacement (0x4238b1)")
	var sounds: Array = wind["events"].filter(func(event): return event["kind"] == "sound").map(func(event): return [int(event["tick"]), str(event["member"])])
	check(sounds == [[0, "WAV\\WIND0002.WAV"], [4, "WAV\\WIND0002.WAV"], [54, "WAV\\WIND0001.WAV"], [64, "WAV\\WIND0001.WAV"]], "the objects' obj_X1 WAVs play once per insertion instruction: %s" % str(sounds))
	var fire: Dictionary = player.compile_row("magic:magicFIRE:magicCode01", true, 1)
	var bombs: Array = fire["events"].filter(func(event): return event["kind"] == "object" and event["object"] == "obj_Effect_FireBomb")
	check(fire["impact_tick"] == 100 and bombs.size() == 6 and bombs.all(func(event): return event["scale"] == Vector2(1.25, 1.25) and int(event["tick"]) >= 50 and int(event["tick"]) <= 50 + 5 * 23), "幻火: 6 bombs at the engZOOM 1.25 scale from tick 50, each at most 23 ticks after the previous (delay range 24 accumulates), impact on the FireBomb2 insertion at 100")
	var water: Dictionary = player.compile_row("magic:magicWATER:magicCode01", true, 1)
	check(water["impact_tick"] == 110 and water["complete_tick"] == _derived_complete(water, 230) and water["events"].filter(func(event): return event["kind"] == "sound").size() == 1, "水剎: WATER005 once, impact on the last drop batch at 110, complete after the 230 waits and the last drop's track")
	var heal: Dictionary = player.compile_row("magic:magicWATER:magicCode06", true, 1)
	check(heal["impact_tick"] == 12 and not heal["dim"] and heal["events"].filter(func(event): return event["kind"] == "object").size() == 40, "治癒之水: 32 + 4 + 4 stars, impact on the last batch at 12, no map dimming")
	var supreme: Dictionary = player.compile_row("magic:magicOTHER:magicCode03", true, 1)
	check(supreme["global"] and supreme["impact_tick"] == 600 and supreme["complete_tick"] == _derived_complete(supreme, 680), "極 (eff_proc_Global) plays at the screen centre; its waits sum to 680 ticks, its impact is the last batch at 600 (%s)" % str([supreme["impact_tick"], supreme["complete_tick"]]))
	var quake: Dictionary = player.compile_row("magic:magicEARTH:magicCode04", true, 1)  # 怒濤地裂崩
	var lasers: Array = quake["events"].filter(func(event): return event["kind"] == "object" and event["object"] == "obj_Effect_EarthLaser2")
	check(lasers.size() == 10 and lasers.all(func(event): return event["motion"] == "native" and int(event["expire"]) - int(event["tick"]) == int(motion["objects"]["obj_Effect_EarthLaser2"]["frames"])) and quake["complete_tick"] == _derived_complete(quake, 372), "EarthLaser2's shape_delay 30000 no longer needs clamping: its program ends the laser after its native frames (%s)" % str(quake["complete_tick"]))
	# Scripts without random insertion have fixed completions, read off the tracks by hand:
	# 封魔滅殺 (effCode30) inserts obj_Effect_MindBall at 0 and waits 120 — the ball's tree (the
	# ball and its 7 sparks) lasts 162 frames, so the clip ends at 162; 生命之水 (effCode14)
	# inserts obj_Effect_Water_GStarBig at 0 and waits 70 — its tree of 186 stars lasts 190.
	var seal: Dictionary = player.compile_row("magic:magicMIND:magicCode02", true, 1)
	check(seal["complete_tick"] == 162 and int(motion["objects"]["obj_Effect_MindBall"]["frames"]) == 162, "封魔滅殺 completes at 162, when MindBall's native tree ends (%s)" % str(seal["complete_tick"]))
	var life: Dictionary = player.compile_row("magic:magicWATER:magicCode07", true, 1)
	check(life["complete_tick"] == 190 and int(motion["objects"]["obj_Effect_Water_GStarBig"]["frames"]) == 190, "生命之水 completes at 190, when GStarBig's 186-star tree ends (%s)" % str(life["complete_tick"]))
	var unknown: Dictionary = Player.compile_effect(["effSetZoom,2", "effWait,4"], 1, manifest, {"effect_proc": "eff_proc_Local", "damage_policy": "x"})
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
		var wind: Dictionary = Player.compile_effect(["effInsertRandomObject,obj_Effect_AirWave1,0,0,10,36,16,6", "effWait,4"], seed, manifest, {"effect_proc": "eff_proc_Local", "damage_policy": "x"})
		var ticks: Array = wind["events"].filter(func(event): return event["kind"] == "object").map(func(event): return int(event["tick"]))
		var ordered: bool = ticks.size() == 6 and ticks[0] == 0
		for index in range(1, ticks.size()):
			ordered = ordered and ticks[index] >= ticks[index - 1] and ticks[index] - ticks[index - 1] <= 15
		check(ordered, "seed %d: the waves enter in order, the first at once, each ≤ 15 ticks after the previous: %s" % [seed, str(ticks)])
	var still: Dictionary = Player.compile_effect(["effInsertRandomObject,obj_Effect_AirWave1,0,0,0,0,0,3"], 3, manifest, {"effect_proc": "eff_proc_Local", "damage_policy": "x"})
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
	var drop: Dictionary = Motion.track("obj_Effect_FlyDrop")
	var light: Dictionary = drop["instances"][0]
	var heights: PackedInt32Array = light["y"]
	check(drop["instances"].size() == 1 and int(light["start"]) == 1 and heights[0] == -88 and heights[heights.size() - 1] == -88 + heights.size() - 1, "FlyDrop falls 1 px per tick from 88 px above (%s)" % str([light["start"], heights[0]]))
	var sway := true
	for value in light["x"]:
		sway = sway and absi(value) <= 16
	var modes: PackedInt32Array = light["mode"]
	var levels: PackedInt32Array = light["level"]
	check(sway and heights.size() == 42 and modes[0] == Motion.ENG_ADDCOLOR and modes[modes.size() - 1] == Motion.ENG_ADDCOLOR | Motion.ENG_MIX and levels[levels.size() - 1] == 1, "FlyDrop sways within ±16 px, draws additively, fades through the engMIX levels to 1 over its last 16 frames")
	# effProcFireAndBomb (0x41618a): rises 24 px, loops its six shapes at the template zoom
	# 1.25, then shrinks 1/32 per tick to 0.25 and loops 24 more ticks; it throws three
	# SprayUpDown sparks (object 163) that arc under gravity.
	var bomb: Dictionary = Motion.track("obj_Effect_FireBomb")
	var core: Dictionary = bomb["instances"][0]
	var zooms: PackedInt32Array = core["zoom_x"]
	check((core["y"] as PackedInt32Array).size() == 76 and Array(core["y"]).all(func(value): return value == -24) and zooms[0] == 0x14000 and zooms[29] == 0xf800 and zooms[zooms.size() - 1] == 0x4000, "FireBomb rises 24 px, 1.25 zoom, then 1/32 per tick down to 0.25")
	var sparks: Array = bomb["instances"].filter(func(instance): return int(instance["code"]) == 163)
	check(sparks.size() == 3 and sparks.all(func(instance): return instance["y"][(instance["y"] as PackedInt32Array).size() - 1] > instance["y"][0]), "three SprayUpDown sparks, each ending lower than it started (gravity)")
	var bomb2: Dictionary = Motion.track("obj_Effect_FireBomb2")
	check(bomb2["instances"].filter(func(instance): return int(instance["code"]) == 164).size() == 12, "FireBomb2 also throws 2 × 6 Spray sparks (object 164) 12 ticks in")


## Drawing: the player places a tracked object's tree at the insertion plus the track offset,
## with the track's blend, alpha and scale — not the untracked static hold.
func native_motion_drawing() -> void:
	var player := Player.new()
	root.add_child(player)
	var fire: Dictionary = player.compile_row("magic:magicFIRE:magicCode01", true, 1)
	var clip := {"effect_timeline": fire}
	var origin := Vector2(200, 300)
	var light: Dictionary = Motion.track("obj_Effect_FlyDrop")["instances"][0]
	var start := int(light["start"])
	# Frame 10 of FlyDrop (inserted at tick 0 at the origin): its native offset.
	player.draw(clip, 10.0 / Player.TICKS_PER_SECOND, [origin])
	var shown: Array = player.sprites.filter(func(sprite): return sprite.visible)
	var expected := origin + Vector2(light["x"][10 - start], light["y"][10 - start])
	check(shown.size() == 1 and shown[0].position == expected and shown[0].material.blend_mode == CanvasItemMaterial.BLEND_MODE_ADD and is_equal_approx(shown[0].modulate.a, 1.0), "幻火 at tick 10: one FlyDrop light at the native offset %s, additive (%s)" % [str(expected), str(shown.map(func(sprite): return sprite.position))])
	# Frame 40: the light's engMIX tail — alpha = level / 16.
	player.draw(clip, 40.0 / Player.TICKS_PER_SECOND, [origin])
	shown = player.sprites.filter(func(sprite): return sprite.visible)
	var level: int = light["level"][40 - start]
	check(shown.size() == 1 and is_equal_approx(shown[0].modulate.a, float(level) / 16.0) and level < 16, "幻火 at tick 40: the light fades by its level %d / 16" % level)
	player.clear()
	player.free()
