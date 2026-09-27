extends "res://tests/capture_priest_review.gd"
## Real rendered inputs after one declared setup. No runtime battle/RNG mutation.
const StatEnhancementRules = preload("res://game/sim/StatEnhancementRules.gd")
const STAT_OUT := "res://ignored/stat-magic-review/"
var receipts: Array = []
var receipt_sequences := {}

func run() -> void:
	if DisplayServer.get_name() == "headless": push_error("Stat magic review needs a rendered built-in window"); quit(2); return
	root.title = "HSL Buff and Dispel Playable Review"
	root.size = Vector2i(640,480)
	root.position = DisplayServer.screen_get_position(root.current_screen) + Vector2i(60,80)
	DirAccess.make_dir_recursive_absolute(STAT_OUT)
	started = Time.get_ticks_msec()
	create_timer(1500).timeout.connect(func(): check(false,"bounded stat review timeout"))
	var names: Array = ["manual","repeat","expiry","dispel","movement","melee","growth","empty_mp","silence","paralysis","ai_buff","ai_dispel","ai_blocked","victory","defeat","escape"]
	if not OS.get_cmdline_user_args().is_empty(): names = Array(OS.get_cmdline_user_args())
	for name in names:
		mode = name
		await setup_stat()
		await play_stat()
		await close_scene()
		write_receipt("progress.json")
		if not failures.is_empty(): break
	write_receipt("receipt.json")
	print("STAT_MAGIC_RENDER_", "PASS" if failures.is_empty() else "FAIL", " routes=",routes.size())
	call_deferred("quit",0 if failures.is_empty() else 1)

func setup_stat() -> void:
	impacts = []; events = []; sounds = {}; observed = {}; saves = 0; receipts = []; receipt_sequences = {}
	scene = load("res://game/battle/development/StatMagicTrial.tscn").instantiate()
	root.add_child(scene); current_scene = scene
	scene.settlement_controller.checkpoint_path = STAT_OUT + mode + ".save"
	if mode != "manual":
		scene.set_process(false)
		var loop := run_support_magic_tests.stat_fixture()
		var actor := BattlePlayLoop.unit_ref(loop,"tina")
		var ally := BattlePlayLoop.unit_ref(loop,"companion")
		var foe := BattlePlayLoop.unit_ref(loop,"enemy026_1")
		foe["no_attack"] = true; foe["mp"] = 0; foe["inventory"] = [0,0,0,0,0,0,0,0]
		if mode in ["dispel","ai_dispel"]:
			run_support_magic_tests.buff(loop,foe["id"],"attack_up",3,24)
			run_support_magic_tests.buff(loop,foe["id"],"defense_up",4,30)
			for key in ["poison","no_magic","paralysis"]:
				foe.merge(BattlePlayLoop.StatusEffectRules.apply(foe,key,3,7 if key == "poison" else 0)["changes"],true)
		if mode in ["melee","growth","silence","victory","defeat","escape"]:
			run_support_magic_tests.buff(loop,"tina","attack_up",4,24)
			run_support_magic_tests.buff(loop,"tina","defense_up",4,30)
		if mode in ["melee","victory","defeat"]:
			foe["coord"] = Vector2i(15,16); actor["hit_bonus_accum"] = 1000
		if mode in ["growth","victory"]: actor["exp"] = 99
		if mode == "growth": ally["hp"] = 100
		if mode == "melee":
			TestSuite.own(loop, "skill_book")["actors"]["002"]["double_attack"] = true
			TestSuite.own(loop, "skill_book")["actors"]["026"]["double_attack"] = true
			foe["no_attack"] = false; foe["hit_bonus_accum"] = 1000
			foe["growth_profile"]["source"]["attack_back"] = 100
			actor["growth_profile"]["source"]["attack_damagex2"] = 100
		if mode == "empty_mp": actor["mp"] = 0
		if mode == "silence":
			actor["hp"] -= 20
			foe["coord"] = Vector2i(15,16) # Moon Dance covers the adjacent body, not a two-cell gap.
			actor.merge(BattlePlayLoop.StatusEffectRules.apply(actor,"no_magic",3)["changes"],true)
		if mode == "paralysis":
			actor.merge(BattlePlayLoop.StatusEffectRules.apply(actor,"paralysis",2)["changes"],true)
			actor["status_counters"]["paralysis"] = 1
			run_support_magic_tests.buff(loop,"tina","attack_up",1,24)
			actor["equipment"].append({"slot":"accessory2","item_code":227})
		if mode.begins_with("ai_"):
			actor["player_commandable"] = false; actor["battle_actor_role"] = BattlePlayLoop.ROLE_FRIENDLY
			actor["no_attack"] = true; actor["inventory"] = [0,0,0,0,0,0,0,0]
			actor["equipment"] = actor["equipment"].filter(func(s): return not s["slot"].begins_with("accessory"))
			actor["equipment"].append_array([{"slot":"accessory1","item_code":232},{"slot":"accessory2","item_code":227}])
			ally["growth_profile"]["source"]["speed"] = 300
			TestSuite.own(loop, "skill_book")["actors"]["002"]["supported_initial_ids"] = [run_support_magic_tests.DISPEL] if mode == "ai_dispel" else [run_support_magic_tests.ATT,run_support_magic_tests.DEF]
			TestSuite.own(loop, "ai_profiles")["actors"]["002"]["profile"].merge({"ai_check_hp":0,"ai_check_dying":0,"ai_help_otherhp":0,"ai_help_status":0,"ai_help_attack":100,"ai_att_magic":100},true)
			for id in [run_support_magic_tests.ATT,run_support_magic_tests.DEF,run_support_magic_tests.DISPEL]: TestSuite.own(loop, "skill_book")["skills"][id]["fields"]["use_ratio"] = "100"
			if mode == "ai_buff": ally["coord"] = Vector2i(19,15); foe["coord"] = Vector2i(20,18)
			if mode == "ai_blocked":
				actor["mp"] = 0
				actor.merge(BattlePlayLoop.StatusEffectRules.apply(actor,"no_magic",3)["changes"],true)
		if mode == "victory": foe["hp"] = 1
		if mode == "defeat":
			actor["hp"] = 1; foe["no_attack"] = false; foe["hit_bonus_accum"] = 1000
			foe["growth_profile"]["source"].merge({"attack_back":100,"attack_power":1000},true)
		if mode == "escape": actor["coord"] = Vector2i(13,10); ally["coord"] = Vector2i(13,11); foe["coord"] = Vector2i(12,10)
		for unit in loop["units"]:
			unit.merge(BattlePlayLoop.ProgressionRules.refresh_growth_stats(unit,loop["equipment_items"]),true)
			unit["grid_coord"] = unit["coord"]; unit["ai_home_coord"] = unit["coord"]
			check(BattlePlayLoop.TraversalRules.placement_error(unit,loop["units"],loop["tiles"],loop["map_size"]) == "","fixture is on legal source terrain")
		loop["turn_queue"] = BattlePlayLoop.CoreTurnQueue.rebuild(loop["units"])
		scene.apply_loop(BattlePlayLoop.return_to_player(loop,"companion" if mode.begins_with("ai_") else "tina"), "test")
		for art in scene.actors_root.get_children(): scene.actors_root.remove_child(art); art.queue_free()
		scene.unit_grid_coords.clear(); scene.resume_turn_presentation()
		scene.center_camera_on_grid(actor["coord"]); scene.set_process(true)
	initial_state = scene.play_loop.duplicate(true)
	scene.get_node("BattlePresentation").cutin.impact.connect(func(strike,attacker,defender,counter):
		impacts.append({"strike":strike.duplicate(true),"attacker":attacker["id"],"defender":defender["id"],"counter":counter}))
	await create_timer(0.25).timeout

func settle(id: String, terminal: bool = false) -> void:
	for attempt in range(3000):
		var view = scene.get_node("BattlePresentation")
		check(scene.play_loop["scenario_ok"],"valid live stat scenario: " + str(scene.play_loop.get("scenario_error","")))
		for sound in scene.find_children("*","AudioStreamPlayer",true,false):
			if sound.playing and sound.stream != null and sound.get_playback_position() > 0: sounds[sound.stream.resource_path] = true
		var latest: Dictionary = scene.play_loop.get("last_combat",{})
		if not latest.is_empty() and not receipt_sequences.has(latest["sequence"]):
			receipt_sequences[latest["sequence"]] = true; receipts.append(latest.duplicate(true))
		if scene.has_actor_motion(): observed["movement"] = true
		if view.cutin.busy():
			check(not scene.action_menu.visible and not scene.growth_panel.visible and not view.battle_finished,"clip completes before next controls, growth and result")
			var clip: Dictionary = view.cutin.clips[0]
			var token := "%s-%s-%s" % [receipts.size(),clip["strike"].get("magic_key","ordinary"),clip["impact_emitted"]]
			if not observed.has(token): observed[token] = true; await shot("cast-"+token)
		if view.item_feedback_busy() or view.turn_end_cue.showing():
			check(not scene.action_menu.visible,"resource/status/item feedback finishes before next controls")
			var token := "item-%s" % scene.play_loop["last_item_use"]["sequence"] if view.item_feedback_busy() else "tail-%s-%s" % [scene.play_loop["action_end_sequence"],view.turn_end_cue.cursor]
			if not observed.has(token):
				observed[token] = true
				events.append((scene.play_loop["last_item_use"] if view.item_feedback_busy() else scene.play_loop["last_action_end"]).duplicate(true))
				await shot(token)
		if view.navigation_cue.caption.visible and view.navigation_cue.caption.text.contains("麻痺") and not observed.has("skip"):
			observed["skip"] = true; await shot("skip")
		if view.dialogue_active(): await key(KEY_SPACE)
		var loot = scene.settlement_controller.panel
		if loot.visible:
			if not loot.rows.is_empty() and loot.first_empty_slot() >= 0:
				await click(loot.rows[0])
				await click(loot.slots[loot.first_empty_slot()])
			else: await click(loot.finish_button)
		if scene.growth_panel.visible:
			observed["growth"] = true
			for i in range(int(scene.growth_panel.source_unit["pending_stat_points"])):
				var key: String = ["str","dex","mind","con"][i % 4]
				if not scene.growth_panel.choices[key]["plus"].disabled: await click(scene.growth_panel.choices[key]["plus"])
			await shot("growth"); await click(scene.growth_panel.confirm_button)
		if view.battle_finished:
			check(terminal,"unexpected early terminal before the requested action")
			check(scene.play_loop["battle_outcome"] == {"victory":BattleOutcome.VICTORY_ENEMIES_CLEARED,"defeat":BattleOutcome.DEFEAT_FALLEN,"escape":BattleOutcome.VICTORY_ESCAPE}[mode],"actual selected action reaches intended terminal")
			await shot("result"); return
		if not terminal and scene.selected_unit_id == id and scene.action_menu.visible and not scene.action_menu.is_expanding() and not scene.ai_playback_active and not view.combat_busy(scene.play_loop):
			await shot("ready-"+str(scene.play_loop["action_end_sequence"])); return
		if attempt == 1500: await shot("waiting"); write_receipt("waiting.json")
		await create_timer(0.02).timeout
	check(false,"bounded playback did not return to "+id)

func cast_stat(id: String, target: String) -> void:
	await click(scene.action_menu.get_node("MagicCommand"))
	await click(scene.magic_panel.choices[id])
	var coord: Vector2i = BattlePlayLoop.unit(scene.play_loop,target)["coord"]
	await hover(scene.grid_cell_center_to_logical_position(coord)); await shot("target-"+id.get_slice(":",2))
	await point(scene.grid_cell_center_to_logical_position(coord))
	check(scene.play_loop["last_attack"].get("skill_id") == id,"actual target click commits selected spell")

func status_page(id: String) -> void:
	await click(scene.action_menu.get_node("StatusCommand"))
	check(scene.status_panel.visible,"status page opens after settled transaction")
	await shot("stats-"+id); await escape(); await settle(id)

func return_to_tina() -> void:
	await click(scene.action_menu.get_node("WaitCommand")); await settle("tina")

func play_stat() -> void:
	var start_id := "companion" if mode.begins_with("ai_") or mode == "paralysis" else "tina"
	await settle(start_id)
	if mode == "manual":
		await cast_stat(run_support_magic_tests.DEF,"companion"); await settle("companion")
		check(StatEnhancementRules.power(BattlePlayLoop.unit(scene.play_loop,"companion"),"defense_up") > 0,"published training is playable through real controls")
	elif mode == "repeat":
		await change_gear(227,"accessory2")
		await cast_stat(run_support_magic_tests.ATT,"tina"); await settle("tina")
		var first := StatEnhancementRules.word(BattlePlayLoop.unit(scene.play_loop,"tina"),"attack_up")
		check(scene.play_loop["extra_action"]["pending"] and scene.play_loop["action_end_sequence"] == 0,"first independent cast does not tick duration")
		await status_page("tina"); await save_restore()
		await cast_stat(run_support_magic_tests.ATT,"tina"); await settle("companion")
		var second := StatEnhancementRules.word(BattlePlayLoop.unit(scene.play_loop,"tina"),"attack_up")
		check((second >> 16) >= (first >> 16) and (second >> 16) <= 96 and (second & 65535) > (first & 65535),"repeat merges duration and strength without adding a duplicate bonus")
		check(scene.play_loop["action_end_sequence"] == 1,"only final independent action ticks once")
	elif mode == "expiry":
		await cast_stat(run_support_magic_tests.DEF,"tina"); await settle("companion")
		for _turn in range(6):
			if StatEnhancementRules.word(BattlePlayLoop.unit(scene.play_loop,"tina"),"defense_up") == 0: break
			await return_to_tina(); await status_page("tina"); await save_restore()
			await click(scene.action_menu.get_node("WaitCommand")); await settle("companion")
		check(StatEnhancementRules.word(BattlePlayLoop.unit(scene.play_loop,"tina"),"defense_up") == 0 and events.any(func(e): return e.get("expired",[]).has("defense_up")),"real queue progression expires defense and displays the completed change")
		check(BattlePlayLoop.unit(scene.play_loop,"tina")["combat_profile"]["live_defense"] == BattlePlayLoop.unit(initial_state,"tina")["combat_profile"]["live_defense"],"expired defense returns to exact source-plus-equipment value")
	elif mode == "dispel":
		var before: Dictionary = BattlePlayLoop.unit(scene.play_loop,"enemy026_1")["status_counters"].duplicate(true)
		await cast_stat(run_support_magic_tests.DISPEL,"enemy026_1"); await settle("companion")
		var after := BattlePlayLoop.unit(scene.play_loop,"enemy026_1")
		check(int(after["status_flags"]) == 7,"dispel removes only the two positive combat states")
		for key in ["poison","no_magic","paralysis"]: check(after["status_counters"][key] == before[key],"dispel preserves exact packed condition: "+key)
	elif mode == "movement":
		await change_gear(227,"accessory2"); await change_gear(232,"accessory1")
		var before: Dictionary = scene.play_loop.duplicate(true)
		await move_to(Vector2i(15,16)); await click(scene.action_menu.get_node("MagicCommand")); await escape(); await settle("tina")
		await escape(); await create_timer(0.3).timeout; await escape(); await settle("tina")
		check(scene.play_loop["units"] == before["units"] and not scene.play_loop["moved_this_action"],"cancel returns phase and position without payment or a status tick")
		await move_to(Vector2i(15,16)); await cast_stat(run_support_magic_tests.DEF,"companion"); await settle("tina"); await save_restore()
		await change_gear(0,"accessory1"); await move_to(Vector2i(14,16))
		check(not BattlePlayLoop.command_available(scene.play_loop,"magic"),"second action uses current removed movement permission")
		await change_gear(232,"accessory1"); await cast_stat(run_support_magic_tests.ATT,"tina"); await settle("companion")
		check(scene.play_loop["action_end_sequence"] == 1,"re-equipping allows the existing moved phase without resetting its action")
	elif mode == "melee":
		await change_gear(227,"accessory2"); await attack("enemy026_1"); await settle("tina"); await save_restore()
		check(impacts.size() == 4 and impacts.filter(func(r): return r["counter"]).size() == 2,"buffed ordinary and counter double sequences remain separate strikes")
		await cast_stat(run_support_magic_tests.DEF,"tina"); await settle("companion")
		check(scene.play_loop["action_end_sequence"] == 1,"double strike and recast still have one owner tail")
	elif mode == "growth":
		await change_gear(227,"accessory2"); await change_gear(228,"accessory1")
		await cast_stat(run_support_magic_tests.DEF,"companion"); await settle("tina")
		check(observed.has("growth") and BattlePlayLoop.unit(scene.play_loop,"tina")["level"] > 1,"support contribution reaches final equipment-modified EXP and real allocation")
		await change_gear(87,"weapon"); await status_page("tina"); await save_restore()
		await cast_heal("companion"); await settle("companion")
		check(impacts.any(func(e): return e["strike"].get("healing",0) > 0),"buffed growth and weapon refresh preserve actual healing and costs")
	elif mode in ["empty_mp","silence"]:
		await change_gear(227,"accessory2")
		await click(scene.action_menu.get_node("MagicCommand"))
		check(scene.magic_panel.choices[run_support_magic_tests.ATT].disabled,"MP or silence disables actual buff control")
		await shot("disabled"); await escape(); await settle("tina")
		await use_item_real(244 if mode == "empty_mp" else 241,"tina"); await settle("tina"); await save_restore()
		if mode == "empty_mp": await cast_stat(run_support_magic_tests.DEF,"tina")
		else:
			await click(scene.action_menu.get_node("SpecialCommand"))
			var moon := "special:magicOTHER:magicCode06"
			if scene.play_loop["interaction"] == "special_select": await click(scene.magic_panel.choices[moon])
			await point(scene.grid_cell_center_to_logical_position(BattlePlayLoop.unit(scene.play_loop,"tina")["coord"]))
			check(scene.play_loop["last_attack"].get("skill_id") == moon,"silence blocks MP spells while the owned special still pays stamina")
		await settle("companion")
	elif mode == "paralysis":
		check(observed.has("skip") and not scene.play_loop["extra_action"]["pending"] and StatEnhancementRules.word(BattlePlayLoop.unit(scene.play_loop,"tina"),"attack_up") == 0,"paralysis skips once and final tail expires the supplied buff")
		await return_to_tina(); await cast_stat(run_support_magic_tests.ATT,"tina"); await settle("tina")
		check(scene.play_loop["extra_action"]["pending"],"next normal entry can cast and receives its own legitimate second action")
	elif mode.begins_with("ai_"):
		await click(scene.action_menu.get_node("WaitCommand")); await settle("companion")
		var actions: Array = scene.play_loop["last_ai_actions"].filter(func(a): return a.get("actor_id") == "tina")
		check(actions.size() == 2,"AI uses two current independent decisions")
		if mode == "ai_buff":
			check(actions.all(func(a): return a.get("skill_id") in [run_support_magic_tests.ATT,run_support_magic_tests.DEF]) and actions[0]["skill_id"] != actions[1]["skill_id"],"AI never repeats an already present matching buff")
			check(observed.has("movement") and (int(BattlePlayLoop.unit(scene.play_loop,"companion")["status_flags"]) & 0x30) == 0x30,"AI moves to a legal cast position and supports the same living ally")
		elif mode == "ai_dispel":
			check(actions[0].get("skill_id") == run_support_magic_tests.DISPEL and not actions[1].has("skill_id"),"AI dispels the enhanced enemy then rejects obsolete second-cast coverage")
		else: check(actions.all(func(a): return not a.has("skill_id")) and impacts.is_empty(),"no MP, silence and no ordinary attack yield valid non-spell fallback")
	else:
		await change_gear(227,"accessory2"); await cast_stat(run_support_magic_tests.DEF,"tina"); await settle("tina"); await save_restore()
		if mode == "escape": await move_to(Vector2i(14,10)); await click(scene.action_menu.get_node("WaitCommand"))
		else: await attack("enemy026_1")
		await settle("",true)
	await save_restore()
	var row := {"mode":mode,"initial_units":initial_state["units"],"initial_book":initial_state["skill_book"],"initial_ai":initial_state["ai_profiles"]["actors"]["002"],
		"final_units":scene.play_loop["units"],"outcome":scene.play_loop["battle_outcome"],"receipts":receipts.duplicate(true),"impacts":impacts.duplicate(true),
		"events":events.duplicate(true),"observed":observed.duplicate(true),"sounds":sounds.keys(),"saves":saves,"restarted":false}
	if mode in ["victory","defeat","escape"]:
		var frozen: Dictionary = scene.play_loop.duplicate(true)
		check(BattlePlayLoop.step_ai_turn(frozen) == frozen and BattlePlayLoop.finish_exhausted_action(frozen) == frozen,"terminal cannot apply another cast, tail or action")
		reload_current_scene(); await create_timer(0.4).timeout; scene = current_scene
		check(not BattleOutcome.decided(scene.play_loop) and scene.play_loop["units"].all(func(u): return (int(u["status_flags"]) & 0x30) == 0),"actual restart uses initial unbuffed trial state")
		row["restarted"] = true
	routes.append(row)

func shot(label: String) -> void:
	await process_frame; RenderingServer.force_draw(false)
	var name := mode+"-"+label+".png"
	check(root.get_texture().get_image().save_png(STAT_OUT+name) == OK,"capture "+label)
	if not frames.has(name): frames.append(name)

func save_restore() -> void:
	await super.save_restore()
	# F9 restores the scene and reopens its source animated menu. Test input must
	# wait for the same readiness that a normal next command requires.
	if not BattleOutcome.decided(scene.play_loop) and scene.play_loop["interaction"] == "action_menu":
		await settle(scene.selected_unit_id)

func write_receipt(filename: String) -> void:
	FileAccess.open(STAT_OUT+filename,FileAccess.WRITE).store_string(JSON.stringify({"schema":"hsl_stat_magic_playable_review.v1","fixture":true,"native_execution":false,"real_control_events":true,
		"pid":OS.get_process_id(),"time_scale":Engine.time_scale,"screen":root.current_screen,"window_size":root.size,"elapsed_seconds":(Time.get_ticks_msec()-started)/1000.0,
		"setup":"Published training explicitly grants three stat spells to002 and Dispel to026, with supplied resources. Other routes use that source051 terrain and source job models, setup-only durability/speed/HP1/EXP99, documented status words, current equipment, controlled AI rates/use_ratio100 and intrinsic double/critical overrides. Source combat RNG is not replaced. No post-setup battle mutation; all casts, equips, movement, queue steps, growth, saving and restarts use real controls. Formal source grants unchanged.",
		"routes":routes,"frames":frames,"failures":failures,"active":{} if not is_instance_valid(scene) else {"mode":mode,"selected":scene.selected_unit_id,"interaction":scene.play_loop.get("interaction"),"observed":observed,"scenario_error":scene.play_loop.get("scenario_error"),"units":scene.play_loop.get("units",[]),"last_combat":scene.play_loop.get("last_combat",{}),"last_ai_actions":scene.play_loop.get("last_ai_actions",[])}},"  "))
