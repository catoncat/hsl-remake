extends SceneTree
## The authored level end to end (docs/MODDING_LEVELS.md tracer): content/authored/level200/ and the
## authored character 102 (content/authored/roles/characters.json) reach the player through the
## generated battle_200.json only. Title 戰場記錄 with a saved position at level 200 boots the
## runtime on it through the campaign hand-off; the authored STORY opening plays every line
## (蕾雅 speaks with her own name) and walks 雷歐納德 to the scripted endpoint; every unit is
## labelled `authored`; 蕾雅 stands on the authored job 101 (no TYPE.H define, stats from its
## authored formula row), holds 天雷猛襲劍 and the authored special 龍炎斬 (no SPECIAL.TXT row) and
## casts the latter through the loop's public special command — damage from the authored numbers,
## presentation through the script player —, and the data-only second skill 龍息 (magic); the fixture-free Autoplay driver plays to a natural outcome, the
## result page arms the campaign hand-off the winfail names (game clear 998); the round-3
## event inserts the scripted reinforcement. Not a gate about balance: win or fail is recorded.
## provenance:
##   rules: remake-invented (test harness over the authored level; the rules it drives carry their own headers)
##   layout: n/a
##   strings: resource-derived content/authored/level200/messages.json (the authored lines asserted)
##   timing: n/a
##   audio: n/a
const TitleScene = preload("res://game/title/TitleScreen.tscn")
const RuntimeScene = preload("res://game/battle/scene/BattleSceneRuntime.tscn")
const CampaignProgress = preload("res://game/battle/runtime/CampaignProgress.gd")
const BattleScenario = preload("res://game/battle/runtime/BattleScenario.gd")
const UnitSchema = preload("res://game/sim/UnitSchema.gd")
const Loop = preload("res://game/battle/scene/BattlePlayLoop.gd")
const Autoplay = preload("res://tests/support/Autoplay.gd")
const Brain = preload("res://tests/support/AutoplayBrain.gd")
const ForceWin = preload("res://tests/support/BattleForceWin.gd")
const TestSuite = preload("res://tests/support/TestSuite.gd")
const JobStats = preload("res://game/sim/JobStatsRules.gd")
const EquipmentRules = preload("res://game/sim/EquipmentRules.gd")
const StatusEffects = preload("res://game/sim/StatusEffectRules.gd")
const SkillEffectScriptPlayer = preload("res://game/battle/scene/SkillEffectScriptPlayer.gd")
const BattleOutcome = preload("res://game/sim/BattleOutcome.gd")

const SCENARIO_PATH := "res://content/battles/battle_200.json"
const FIXTURE_CAMPAIGN_PATH := "user://authored_level_tests_campaign.json"
const SPECIAL_ID := "special:magicAIR:magicCode01"
const AUTHORED_SPECIAL_ID := "special:magicFIRE:authoredDragonFlame"
const AUTHORED_MAGIC_ID := "magic:magicFIRE:authoredDragonBreath"
const AUTHORED_SKILLS_PATH := "res://content/authored/roles/skills.json"
const Cutin = preload("res://game/battle/scene/BattleCombatCutin.gd")
const UISkin = preload("res://game/battle/scene/BattleUISkin.gd")
const ContentPaths = preload("res://game/sim/ContentPaths.gd")
const COMBAT_MANIFEST := "res://content/generated/hsl/authored/battle200/combat_animation.json"
## content/authored/actors/<art>/: each authored look's folder (hsltools.assets.authored_art).
const LOOKS := {"102": {"program_of": "003", "sounds_of": "3", "title": "龍騎士", "name": "蕾雅"}, "103": {"program_of": "004", "sounds_of": "4", "title": "盜賊", "name": "托蘭"}}
const OPENING_FRAMES := 6000
const AUTHORED_JOB := 101
const AUTHORED_JOBS_PATH := "res://content/authored/roles/job_formulas.json"

var checks := 0
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("run")


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)


func run() -> void:
	CampaignProgress.pending = {}
	CampaignProgress.resume_prompt_in_headless = false
	Autoplay.ensure_loop_seed()
	_contract_cases()
	await _new_story_case()
	var runtime = await _enter_from_title()
	if runtime != null:
		await _opening_case(runtime)
		_special_case(runtime)
		_magic_case(runtime)
		await _autoplay_case(runtime)
		if is_instance_valid(runtime):
			runtime.queue_free()
		if current_scene != null and is_instance_valid(current_scene):
			current_scene.queue_free()
		await process_frame
		await process_frame
	CampaignProgress.reset_campaign()
	await TestSuite.settle_wall_clock(self, 0.3)
	for failure in failures:
		push_error(failure)
	print("AUTHORED_LEVEL_TESTS_", "PASS" if failures.is_empty() else "FAIL", " checks=", checks)
	quit(0 if failures.is_empty() else 1)


func _contract_cases() -> void:
	var scenario := BattleScenario.load_file(SCENARIO_PATH)
	check(bool(scenario.get("ok", false)), "battle_200.json loads under the battle contract: " + str(scenario.get("error", "")))
	check(int(scenario.get("level", 0)) == 200 and str(scenario.get("status", "")) == "authored", "the assembled level is 200 and marked authored")
	check(str(scenario.get("provenance", {}).get("evidence_tier", "")) == UnitSchema.AUTHORED_TIER and str(scenario["view"]["grid_projection"].get("evidence_tier", "")) == UnitSchema.AUTHORED_TIER, "scenario provenance and view are authored")
	var units := BattleScenario.units(scenario)
	check(units.size() == 7 and units.all(func(unit): return UnitSchema.evidence_tier(unit, "vitals") == UnitSchema.AUTHORED_TIER and UnitSchema.evidence_tier(unit, "position") == UnitSchema.AUTHORED_TIER), "every unit of the authored level is labelled authored (no evidence ledgers)")
	check(UnitSchema.roster_error(units) == "", "the authored roster meets the unit contract: " + UnitSchema.roster_error(units))
	var reia: Dictionary = units.filter(func(unit): return unit["id"] == "reia")[0] if units.any(func(unit): return unit["id"] == "reia") else {}
	check(not reia.is_empty() and str(reia.get("actor_id", "")) == "102" and int(reia.get("growth_profile", {}).get("job_code", 0)) == AUTHORED_JOB and str(reia["growth_profile"].get("allocation", "")) == "manual", "蕾雅 is the authored character 102 on the authored job 101 with manual allocation: " + str(reia.get("growth_profile", {})))
	var seed: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(str(scenario["resources"]["battle_seed"])))
	var sections: Array = seed["scripts"]["winfail"]["sections"].map(func(section): return str(section.get("name", "")))
	check(str(seed.get("evidence_tier", "")) == UnitSchema.AUTHORED_TIER and sections == ["win", "fail", "event"], "the authored seed carries the three winfail sections as authored: " + str(sections))
	var templates: Dictionary = scenario.get("script_actor_templates", {})
	check(templates.has("obj_Level200_Wolf") and str(templates["obj_Level200_Wolf"]["actor"]["actor_id"]) == "036", "the winfail insert symbol resolves to the declared 036 template")
	var loop := Loop.create([], "", scenario)
	check(bool(loop["scenario_ok"]), "create() accepts the authored level: " + str(loop.get("scenario_error", "")))
	_art_cases(scenario, loop)
	check(loop["win_statuses"] == [0] and loop["fail_statuses"] == [0] and loop["event_statuses"] == [0], "the authored STORY arms win_0 / fail_0 / event_0: " + str([loop.get("win_statuses"), loop.get("fail_statuses"), loop.get("event_statuses")]))
	_authored_job_case(loop)


## Job 101 has no TYPE.H `#define`: its row in content/authored/roles/job_formulas.json declares
## the symbol jobDragonLord that 102's `job =` names. 蕾雅's live vitals are that row's terms
## (evaluated here from the authored file, independently of JobStatsRules) plus her source
## offsets and equipment — the same sum as any chapter-1 job.
func _authored_job_case(loop: Dictionary) -> void:
	var authored: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(AUTHORED_JOBS_PATH))
	var row: Dictionary = authored["jobs"].get(str(AUTHORED_JOB), {})
	check(str(row.get("symbol", "")) == "jobDragonLord" and str(row.get("evidence_tier", "")) == UnitSchema.AUTHORED_TIER, "job 101 is an authored row that names itself (no TYPE.H define): " + str(row.get("symbol")))
	var authored_caps := {}
	for key in JobStats.ATTRIBUTES:
		authored_caps[key] = int(row.get("caps", {}).get(key, -1))
	check(JobStats.has_job(AUTHORED_JOB) and JobStats.caps(AUTHORED_JOB) == authored_caps, "the runtime job table carries 101 with the authored caps: " + str(JobStats.caps(AUTHORED_JOB)))
	var reia := Loop._unit(loop, "reia")
	if reia.is_empty() or row.is_empty():
		return
	var variables := {"level": int(reia["level"]), "hp_level": int(reia["level"])}
	for key in JobStats.ATTRIBUTES:
		variables[key] = int(reia["combat_profile"][key])
	var source: Dictionary = reia["growth_profile"]["source"]
	var delta: Dictionary = EquipmentRules.effect_delta(reia["equipment"], loop["equipment_items"])["delta"]
	var expected_hp := _authored_terms(row["max_hp"], variables) + int(source["hit_point"]) + int(delta["max_hp"])
	var expected_speed := _authored_terms(row["speed"], variables) + int(source["speed"]) + int(delta["speed"])
	var expected_attack := _authored_terms(row["attack"], variables) + int(source["attack_power"]) + JobStats.level_attack_bonus(int(reia["level"])) + int(delta["attack"])
	check(int(reia["max_hp"]) == expected_hp and int(reia["live_speed"]) == expected_speed and int(reia["combat_profile"]["live_attack_damage"]) == expected_attack, "蕾雅's max HP / speed / attack are job 101's authored terms: %s" % str([reia["max_hp"], expected_hp, reia["live_speed"], expected_speed, reia["combat_profile"]["live_attack_damage"], expected_attack]))


## [mul, var, div] is mul*var/div, [mul, var, div, pre] mul*(var/pre)/div, a bare int a constant
## (content/authored/roles/job_formulas.json `term_format`).
func _authored_terms(terms: Array, variables: Dictionary) -> int:
	var total := 0
	for term in terms:
		if term is Array:
			var value := int(variables[term[1]])
			if term.size() == 4:
				value = value / int(term[3])
			total += int(term[0]) * value / int(term[2])
		else:
			total += int(term)
	return total


## 102 and 103 are drawn by their own folders under content/authored/actors/ (placeholder
## recolours of 003／004, no sprite_aliases): walk frames, cut-in rows, sounds, faces and
## board titles all come from data. 103 (托蘭, friendly AI) was added by data only — a
## characters.json row, a roster code, an art folder and a level.json unit.
func _art_cases(scenario: Dictionary, loop: Dictionary) -> void:
	var resources: Dictionary = scenario["resources"]
	check(str(resources.get("combat_animation", "")) == COMBAT_MANIFEST, "level 200 names its generated cut-in table: " + str(resources.get("combat_animation", "")))
	var walk: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(str(resources["actor_walk_manifest"])))
	var combat: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(COMBAT_MANIFEST))
	var audio: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(str(resources["actor_audio"])))
	var source_audio: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(str(audio["source_manifest"])))
	var faces := ContentPaths.actor_portraits()
	var chapter_one: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://content/imported/hsl/chapter01/combat_animation/manifest.json"))
	check(combat.get("background") == chapter_one.get("background") and combat.get("opening") == chapter_one.get("opening"), "the level table keeps the source manifest's backdrop and opening shape")
	check(combat["actors"].get("036") == chapter_one["actors"]["036"] and combat["actors"].get("001") == chapter_one["actors"]["001"], "imported rows are copied unchanged into the level table")
	for code in LOOKS:
		var look: Dictionary = LOOKS[code]
		var folder := "res://content/authored/actors/%s/" % code
		var entry: Dictionary = walk["actors"].get(code, {})
		var walk_frames: Array = entry.get("frames", [])
		check(walk_frames.size() == 30 and not entry.has("frames_of_actor") and walk_frames.all(func(frame): return str(frame["res_path"]).begins_with(folder + "walk/") and load(str(frame["res_path"])) is Texture2D), "%s walks with its own 30 frames from %swalk/ (no alias)" % [code, folder])
		check((entry.get("animations", {}) as Dictionary).get("walk", {}).size() == 4 and entry["animations"]["idle"].has("0"), "%s: stand plus four walk directions" % code)
		var row: Dictionary = combat["actors"].get(code, {})
		var strike_frames: Array = row.get("frames", [])
		check(str(row.get("program_of", "")) == look["program_of"] and strike_frames.size() == chapter_one["actors"][look["program_of"]]["frames"].size() and strike_frames.all(func(frame): return str(frame["res_path"]).begins_with(folder + "cutin/") and load(str(frame["res_path"])) is Texture2D), "%s cuts in with its own frames on the %s strike program: %s" % [code, look["program_of"], str(row.get("program_of", ""))])
		check(row.get("dispatch") == chapter_one["actors"][look["program_of"]]["dispatch"] and row.get("special_frames") == [], "%s: the dispatch is the program row's; no s_shape strip (standing caster)" % code)
		check(audio["characters"].has(str(int(code))) and audio["characters"][str(int(code))] == source_audio["characters"].get(look["sounds_of"]), "%s sounds like row %s (art.json sounds_of): %s" % [code, look["sounds_of"], str(audio["characters"].get(str(int(code))))])
		check(str(faces.get(code, {}).get("res_path", "")) == folder + "portrait.png" and str(faces[code].get("name", "")) == look["name"], "%s's face is %sportrait.png under %s" % [code, folder, look["name"]])
		check(str(UISkin.data()["actors"].get(code, {}).get("title", "")) == look["title"], "%s's board title is %s (generated panel table)" % [code, look["title"]])
	var toran := Loop.unit(loop, "toran")
	check(str(toran.get("actor_id", "")) == "103" and str(toran.get("battle_actor_role", "")) == "friendly_ai" and UnitSchema.evidence_tier(toran, "vitals") == UnitSchema.AUTHORED_TIER, "托蘭 (103) stands in level 200 as an authored friendly AI unit")
	for pair in [["reia", "wolf_1"], ["toran", "wolf_2"]]:
		var cutin := Cutin.new()
		root.add_child(cutin)
		check(cutin.configure(COMBAT_MANIFEST), "a cut-in configures from the level table")
		cutin.set_process(false)
		var attacker := Loop.unit(loop, pair[0])
		var defender := Loop.unit(loop, pair[1])
		cutin.play({"hit": true, "damage": 5, "defender_hp_before": int(defender["hp"]), "defender_hp_after": int(defender["hp"]) - 5}, attacker, defender, false)
		var schedule := Cutin.Timing.ordinary(cutin.manifest["actors"][str(attacker["actor_id"])], cutin.clips[0]["strike"])
		cutin._process(float(schedule["opening"]) / Cutin.Timing.PLAYBACK_SPEED + 0.05)
		var path := str(cutin.attacker_sprite.texture.resource_path) if cutin.attacker_sprite.texture != null else ""
		check(cutin.attacker_sprite.visible and path.begins_with("res://content/authored/actors/%s/cutin/" % attacker["actor_id"]), "%s's cut-in draws its own frame after the opening: %s" % [pair[0], path])
		cutin.queue_free()


## 開始新故事 opens campaign.json's start_level: a fixture campaign that starts at 200 (and
## names no start_movie) boots the runtime on level 200 with no hand-off; the product
## campaign still starts at 51 behind start.ani (run_title_screen_tests).
func _new_story_case() -> void:
	var campaign := CampaignProgress.load_campaign()
	check(str(campaign.get("start_level", "")) == "51" and str(campaign.get("start_movie", "")) == "start", "the product campaign starts at 51 behind start.ani")
	campaign["start_level"] = "200"
	campaign.erase("start_movie")
	var file := FileAccess.open(FIXTURE_CAMPAIGN_PATH, FileAccess.WRITE)
	file.store_string(JSON.stringify(campaign))
	file.close()
	CampaignProgress.campaign_path = FIXTURE_CAMPAIGN_PATH
	CampaignProgress.reset_campaign()
	var title = TitleScene.instantiate()
	root.add_child(title)
	current_scene = title
	await process_frame
	title.select(0)
	var transition: Dictionary = title.confirm()
	check(str(transition.get("action", "")) == "new_story" and str(transition.get("start_scenario_path", "")) == SCENARIO_PATH and str(transition.get("start_movie", "")) == "", "開始新故事 on a campaign whose start_level is 200 names level 200 and no film: " + str(transition))
	check(not CampaignProgress.has_pending(), "the new story arms no hand-off")
	await create_timer(title.FADE_SECONDS + 0.3).timeout
	await process_frame
	await process_frame
	var runtime = current_scene
	var booted := runtime != null and runtime.has_method("apply_loop")
	check(booted and str(transition.get("status", "")) == "scene_changed" and not transition.has("movie"), "the fade boots BattleSceneRuntime directly (no start_movie, no film): " + str(transition))
	if booted:
		check(str(runtime.scenario_path) == SCENARIO_PATH and bool(runtime.play_loop.get("scenario_ok", false)) and runtime.campaign_handoff.is_empty(), "the runtime resolves the campaign's start_level 200 without a hand-off: " + str(runtime.scenario_path))
		runtime.queue_free()
	await process_frame
	await process_frame
	CampaignProgress.campaign_path = CampaignProgress.CAMPAIGN_PATH
	DirAccess.remove_absolute(FIXTURE_CAMPAIGN_PATH)
	CampaignProgress.reset_campaign()


## 戰場記錄 on the title with a saved position at level 200: the player's way into a sequel
## level once its predecessor handed over (CampaignProgress.queue_resume, the same pending
## hand-off a result page arms).
func _enter_from_title() -> Node:
	CampaignProgress.reset_campaign()
	var saved := {"scenario_path": SCENARIO_PATH, "carry": {"schema": "hsl_campaign_carry.v1", "units": {}, "gold": 120}, "from_scenario_id": "authored_tracer", "world": {}}
	check(CampaignProgress.save_progress(saved), "a saved campaign position at level 200 is written")
	var title = TitleScene.instantiate()
	root.add_child(title)
	current_scene = title
	await process_frame
	title.select(1)
	var transition: Dictionary = title.confirm()
	check(str(transition.get("action", "")) == "battle_record" and str(transition.get("resume_scenario_path", "")) == SCENARIO_PATH, "戰場記錄 resumes into level 200: " + str(transition))
	check(CampaignProgress.has_pending() and str(CampaignProgress.pending.get("scenario_path", "")) == SCENARIO_PATH, "the title arms the campaign hand-off into level 200")
	await create_timer(title.FADE_SECONDS + 0.3).timeout
	await process_frame
	await process_frame
	var runtime = current_scene
	var booted := runtime != null and runtime.has_method("apply_loop")
	check(booted, "the fade hands over to BattleSceneRuntime")
	if not booted:
		return null
	check(str(runtime.scenario_path) == SCENARIO_PATH and str(runtime.startup_mode) == "product_opening", "the runtime boots level 200 as the product opening: " + str(runtime.scenario_path))
	check(bool(runtime.play_loop.get("scenario_ok", false)), "level 200 loads in the runtime: " + str(runtime.play_loop.get("scenario_error", "")))
	return runtime


func _opening_case(runtime: Node) -> void:
	var coordinator = runtime.opening_coordinator
	check(coordinator != null and coordinator.active, "the authored opening starts in the coordinator")
	if coordinator == null:
		return
	coordinator.walk_pixels_per_second = 6400.0
	var lines := {}
	for _frame in range(OPENING_FRAMES):
		if not coordinator.active:
			break
		if str(coordinator.summary().get("current_event_kind", "")) == "dialogue_message_id":
			if runtime.opening_overlay.visible and runtime.opening_overlay.body_text() != "":
				lines[runtime.opening_overlay.speaker_label.text] = runtime.opening_overlay.body_text()
			coordinator.handle_input(ForceWin.click())
		await process_frame
	check(not coordinator.active, "the opening reaches first control")
	check(lines.has("蕾雅：") and lines["蕾雅："] == "雷歐納德，交給我吧。這把槍還沒嘗過翼狼的血。", "蕾雅 speaks her authored line under her own name: " + str(lines))
	check(lines.has("雷歐納德：") and lines.has("翼狼："), "雷歐納德 and the 翼狼 speak their authored lines: " + str(lines.keys()))
	var skipped: Array = coordinator.summary().get("skipped_records", []).filter(func(record): return str(record.get("kind", "")) == "dialogue_message_id")
	check(skipped.is_empty(), "no authored line was skipped for a missing binding or text: " + str(skipped))
	var reia_node = runtime.actor_node_for_unit("reia")
	var reia_texture: Texture2D = reia_node.get_node("Sprite2D").texture if reia_node != null and reia_node.get_node_or_null("Sprite2D") != null else null
	check(reia_texture != null and reia_texture.resource_path.begins_with("res://content/authored/actors/102/walk/"), "蕾雅 stands on the map in her own walk frame: " + (reia_texture.resource_path if reia_texture != null else "none"))
	check(Loop.unit(runtime.play_loop, "leonard").get("coord") == Vector2i(7, 8), "雷歐納德 stands on the STORY actWalkWait endpoint (7,8) at first control: " + str(Loop.unit(runtime.play_loop, "leonard").get("coord")))
	check(str(runtime.play_loop.get("interaction", "")) != "" and runtime.play_loop["units"].any(func(unit): return unit["player_commandable"]), "the loop is interactive with controlled units at first control")


## 蕾雅 casts the specials her authored row declares — 天雷猛襲劍 (special_wind, a SPECIAL.TXT row)
## and 龍炎斬 (special_fire, a row of content/authored/roles/skills.json that no original table
## has) — through the loop's public command entry points on a copy of the first-control loop.
## The authored special resolves on the native special roll from its table numbers (the
## expected damage is recomputed here from the authored file) and its presentation row plays
## through the script player like an original one.
func _special_case(runtime: Node) -> void:
	var loop: Dictionary = runtime.play_loop.duplicate(true)
	var reia := Loop._unit(loop, "reia")
	var wolf := Loop._unit(loop, "wolf_1")
	check(str(reia.get("actor_id", "")) == "102" and int(reia.get("level", 0)) >= 3, "蕾雅 enters at least at her authored level 3 (entry growth applies as in any level): " + str(reia.get("level")))
	reia["live_speed"] = 300
	reia["stamina"] = 60
	wolf["coord"] = reia["coord"] + Vector2i(2, 0)
	loop["turn_queue"] = Loop.CoreTurnQueue.rebuild(loop["units"])
	loop = Loop.begin_battle(loop)
	loop = Loop.select_player_unit(loop, "reia")
	check(str(loop.get("selected_unit_id", "")) == "reia" and str(loop.get("interaction", "")) == "action_menu", "蕾雅 takes the first action of the rebuilt queue")
	var options := Loop.special_options(loop, "reia")
	var ids: Array = options.map(func(option): return str(option["id"]))
	check(ids == [SPECIAL_ID, AUTHORED_SPECIAL_ID] and options.all(func(option): return bool(option["quote"]["ok"])), "蕾雅's specials are the declared 天雷猛襲劍 and the authored 龍炎斬, both castable at 60 ST: " + str(ids))
	var authored := _authored_skill_row(AUTHORED_SPECIAL_ID)
	var entry: Dictionary = loop["skill_book"]["skills"].get(AUTHORED_SPECIAL_ID, {})
	check(not authored.is_empty() and str(entry.get("name", "")) == str(authored.get("name_text", "")) and str(entry.get("evidence_tier", "")) == UnitSchema.AUTHORED_TIER and str(entry.get("damage_policy", "")) == "native_special_damage", "the skill book carries 龍炎斬 as an authored native-special-damage row: " + str(entry.get("name")))
	var fields: Dictionary = entry.get("fields", {})
	check(["range", "effect_range", "expend", "damage", "hit_ratio", "attackpow_ratio", "function"].all(func(key): return str(fields.get(key, "")) == str(authored.get(key, "?"))), "the book row's fields are the authored table's numbers: " + str(fields))
	check(Loop.can_use_special(loop, "reia"), "the special command is available")
	var candidates: Array = Brain._skill_options(loop, Loop._unit(loop, "reia")).map(func(entry): return str(entry["option"]["id"]))
	check(candidates.has(AUTHORED_SPECIAL_ID), "the autoplay commander (HSL_AUTOPLAY_BRAIN) can legally pick 龍炎斬: " + str(candidates))
	var started := Loop.choose_command(loop, "special")
	check(str(started.get("interaction", "")) == "special_select", "two specials open the special list: " + str(started.get("interaction")))
	started = Loop.choose_special(started, AUTHORED_SPECIAL_ID)
	check(str(started.get("interaction", "")) == "attack_select" and str(started.get("selected_skill_id", "")) == AUTHORED_SPECIAL_ID, "choosing 龍炎斬 goes to target selection: " + str(started.get("interaction")))
	var after := Loop.attack_target(started, "wolf_1", func(_n): return 0)
	var receipt: Dictionary = after.get("last_attack", {})
	check(str(receipt.get("skill_id", "")) == AUTHORED_SPECIAL_ID and str(receipt.get("attacker_id", "")) == "reia" and bool(receipt.get("hit", false)), "龍炎斬 resolves as 蕾雅's attack and hits on zero draws: " + str(receipt.get("skill_id")))
	# Native special roll on zero draws: low + (high-low)/2, plus con/8 + mind/4 + dex/3, scaled by
	# attackpow_ratio, then the target's resistance of the row's element (magicFIRE = slot 3).
	var limits: PackedStringArray = str(authored.get("damage", "0,0")).split(",")
	var live := StatusEffects.weakened_attributes(reia)
	var value := (int(limits[0]) + (int(limits[1]) - int(limits[0])) / 2 + int(live["con"]) / 8 + int(live["mind"]) / 4 + int(live["dex"]) / 3) * int(authored.get("attackpow_ratio", 0)) / 100
	var resistance := int(wolf["combat_profile"]["resist_by_type"]["3"])
	if resistance != 0:
		value = (100 - mini(80, resistance)) * value / 100
	var expected := mini(int(wolf["hp"]), value)
	check(int(receipt.get("damage", -1)) == expected and int(Loop.unit(after, "wolf_1")["hp"]) == int(wolf["hp"]) - expected, "龍炎斬's damage is the native special roll over the authored numbers: %s (expected %d)" % [str(receipt.get("damage")), expected])
	check(int(Loop.unit(after, "reia")["stamina"]) == 60 - int(authored.get("expend", 0)) * 20, "龍炎斬 pays its authored expend in ST: " + str(Loop.unit(after, "reia")["stamina"]))
	_presentation_case(AUTHORED_SPECIAL_ID, "special")


## 龍息 was added to content/authored/roles/skills.json as data only (a MAGIC.TXT-shaped row and an
## effCode script built from implemented eff* opcodes): 蕾雅 declares it in magic_fire, which also
## gives her job 101's MP formula, and casts it through the loop's public magic command. The
## native magic roll reads the authored bounds (sampled = low + (high-low)/2 on zero draws), the
## cast pays the authored MP, targeting reaches the RANGE row the table named (range4CellThrust,
## grown into targeting.json by the generator) and the effCode script plays on the map.
func _magic_case(runtime: Node) -> void:
	var loop: Dictionary = runtime.play_loop.duplicate(true)
	var reia := Loop._unit(loop, "reia")
	var wolf := Loop._unit(loop, "wolf_1")
	var authored := _authored_skill_row(AUTHORED_MAGIC_ID)
	check(int(reia.get("max_mp", 0)) > 0 and bool(reia["growth_profile"]["source"].get("has_magic", false)), "declaring 龍息 gives 蕾雅 MP from job 101's formula: " + str(reia.get("max_mp")))
	reia["live_speed"] = 300
	wolf["coord"] = reia["coord"] + Vector2i(3, 0)
	loop["turn_queue"] = Loop.CoreTurnQueue.rebuild(loop["units"])
	loop = Loop.begin_battle(loop)
	loop = Loop.select_player_unit(loop, "reia")
	var options := Loop.magic_options(loop, "reia")
	check(options.size() == 1 and str(options[0]["id"]) == AUTHORED_MAGIC_ID and bool(options[0]["quote"]["ok"]) and str(options[0]["name"]) == str(authored.get("name_text", "")), "蕾雅's only magic is the authored 龍息 and she can pay for it: " + str(options.map(func(option): return [option["id"], option["quote"]])))
	check(loop["skill_target_data"]["ranges"].has(str(authored.get("range", ""))), "the generated targeting table carries the range the authored row names: " + str(authored.get("range")))
	var candidates: Array = Brain._skill_options(loop, Loop._unit(loop, "reia")).map(func(entry): return str(entry["option"]["id"]))
	check(candidates.has(AUTHORED_MAGIC_ID), "the autoplay commander (HSL_AUTOPLAY_BRAIN) can legally pick 龍息: " + str(candidates))
	var started := Loop.choose_command(loop, "magic")
	started = Loop.choose_magic(started, AUTHORED_MAGIC_ID)
	check(str(started.get("interaction", "")) == "attack_select" and str(started.get("selected_skill_id", "")) == AUTHORED_MAGIC_ID, "choosing 龍息 goes to target selection: " + str(started.get("interaction")))
	var mp_before := int(Loop.unit(started, "reia")["mp"])
	var after := Loop.attack_target(started, "wolf_1", func(_n): return 0)
	var receipt: Dictionary = after.get("last_attack", {})
	var limits: PackedStringArray = str(authored.get("damage", "0,0")).split(",")
	var roll: Dictionary = receipt.get("native_damage_roll", {})
	check(str(receipt.get("skill_id", "")) == AUTHORED_MAGIC_ID and bool(receipt.get("hit", false)) and int(roll.get("sampled", -1)) == int(limits[0]) + (int(limits[1]) - int(limits[0])) / 2, "龍息 resolves on the native magic roll over the authored bounds: " + str(roll))
	check(int(receipt.get("damage", 0)) > 0 and int(Loop.unit(after, "wolf_1")["hp"]) == int(wolf["hp"]) - int(receipt["damage"]), "龍息 damages the 翼狼 by the receipt's amount: " + str(receipt.get("damage")))
	check(int(Loop.unit(after, "reia")["mp"]) == mp_before - int(authored.get("expend", 0)), "龍息 pays its authored MP: %d -> %d" % [mp_before, int(Loop.unit(after, "reia")["mp"])])
	_presentation_case(AUTHORED_MAGIC_ID, "magic")


## The authored row plays through SkillEffectScriptPlayer (authored_effect_scripts.json declares
## `presentation: script`; the imported manifest has no row for it) and compiles to a timeline.
func _presentation_case(skill_id: String, channel: String) -> void:
	var player = SkillEffectScriptPlayer.new()
	root.add_child(player)
	check(player.presentation(skill_id) == "script" and player.matches({"skill_id": skill_id}) and player.channel(skill_id) == channel, "the script player claims the authored %s row: %s" % [channel, player.presentation(skill_id)])
	var timeline: Dictionary = player.compile_row(skill_id, true, 7)
	check(not (timeline.get("events", []) as Array).is_empty() and int(timeline.get("complete_tick", 0)) > 0, "the authored %s row compiles to a timeline: events=%d" % [channel, (timeline.get("events", []) as Array).size()])
	player.queue_free()


func _authored_skill_row(skill_id: String) -> Dictionary:
	var table: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(AUTHORED_SKILLS_PATH))
	for row in table.get("skills", []):
		if "%s:%s:%s" % [row["channel"], row["type"], row["code"]] == skill_id:
			return row
	return {}


func _autoplay_case(runtime: Node) -> void:
	var result := await Autoplay.play_battle(self, runtime, Autoplay.DEFAULT_ROUND_LIMIT, 1)
	print(Autoplay.format_line("200", result))
	print("AUTHORED_LEVEL_AUTOPLAY_ROW ", JSON.stringify({"outcome": str(result["outcome"]), "battle_outcome": result["battle_outcome"], "rounds": int(result["rounds"]), "reason": str(result["reason"]), "unit": str(result["unit"]), "round": int(result["round"]), "detail": str(result["detail"]), "actions": result["actions"], "result_page": bool(result["result_page"])}))
	check(str(result["outcome"]) != Autoplay.OUTCOME_DEAD_END, "autoplay reaches a natural outcome: " + Autoplay.format_line("200", result))
	check(bool(result["result_page"]), "the battle reaches its finished state")
	var fired: Array = runtime.play_loop.get("winfail_runtime", {}).get("fired", []).map(func(entry): return str(entry.get("key", "")))
	var wolves: int = runtime.play_loop["units"].filter(func(unit): return str(unit["actor_id"]) == "036").size()
	if int(result["rounds"]) >= 3:
		check(fired.has("event_0") and wolves == 4, "the round-3 event inserted the scripted fourth 翼狼: fired=%s wolves=%d" % [str(fired), wolves])
	if str(result["outcome"]) == Autoplay.OUTCOME_WIN:
		check(fired.has("win_0") and BattleOutcome.decided(runtime.play_loop), "victory resolves through the authored win_0 status")
		var destination := CampaignProgress.next_destination(CampaignProgress.load_campaign(), runtime.play_loop, SCENARIO_PATH)
		check(str(destination.get("kind", "")) == "game_clear" and int(destination.get("level", 0)) == 998, "the authored winfail hands over to the game-clear card (200,998): " + str(destination))
		# The finished battle's own leave (BattleSceneRuntime.leave_finished_battle) makes this call.
		runtime.campaign_progress.start_next_battle()
		check(str(runtime.campaign_progress.last_handoff.get("kind", "")) == "game_clear" and not CampaignProgress.has_pending(), "the battle end enters the GameClear sequence")
		await process_frame
		await process_frame
		check(current_scene != null and current_scene.get_script() != null and str(current_scene.get_script().resource_path).ends_with("GameClearScreen.gd"), "the GameClear screen is the current scene: " + str(current_scene))
		var showcase: Array = current_scene.get("showcase") if current_scene != null else []
		check(showcase.size() == 3 and showcase.any(func(member): return str(member.get("name", "")) == "蕾雅"), "the showcase lists the three controlled members with 蕾雅 by name: " + str(showcase))
	CampaignProgress.pending = {}
