extends "res://tests/capture_tactical_items_review.gd"
## Authored setup only; all subsequent uses, growth, movement and saves use UI.
const run_permanent_items_tests = preload("res://tests/run_permanent_items_tests.gd")
const PermanentCapabilityRules = preload("res://game/sim/PermanentCapabilityRules.gd")
const PERM_OUT := "res://ignored/permanent-items-review/"
const WIND := "magic:magicAIR:magicCode01"

func run() -> void:
	if DisplayServer.get_name() == "headless": push_error("Permanent item review needs rendered window"); quit(2); return
	root.title = "HSL Permanent Capability Playable Review"; root.size = Vector2i(640,480)
	root.position = DisplayServer.screen_get_position(root.current_screen) + Vector2i(60,80)
	DirAccess.make_dir_recursive_absolute(PERM_OUT); started = Time.get_ticks_msec()
	create_timer(1800).timeout.connect(func():check(false,"bounded permanent-item review timeout"))
	var names: Array = ["manual","repeat","magic","melee","growth","resistance","cap","mixed","movement","paralysis","ai","speed","details","victory","defeat","escape"]
	if not OS.get_cmdline_user_args().is_empty(): names = Array(OS.get_cmdline_user_args())
	for name in names:
		mode = name; await setup_permanent(); await play_permanent(); await close_scene(); write_receipt("progress.json")
		if not failures.is_empty(): break
	write_receipt("receipt.json")
	print("PERMANENT_ITEMS_RENDER_", "PASS" if failures.is_empty() else "FAIL", " routes=",routes.size())
	call_deferred("quit",0 if failures.is_empty() else 1)

func setup_permanent() -> void:
	impacts=[]; events=[]; sounds={}; observed={}; saves=0; receipts=[]; receipt_sequences={}; item_receipts=[]; item_seen={}
	scene=load("res://game/battle/development/PermanentItemsTrial.tscn").instantiate()
	root.add_child(scene); current_scene=scene; scene.settlement_controller.checkpoint_path=PERM_OUT+mode+".save"
	if mode != "manual":
		scene.set_process(false)
		var loop := run_permanent_items_tests.fixture()
		var actor := BattlePlayLoop._unit(loop,"tina"); var ally := BattlePlayLoop._unit(loop,"companion"); var foe := BattlePlayLoop._unit(loop,"enemy026_1")
		actor["equipment"] = actor["equipment"].filter(func(s):return not s["slot"].begins_with("accessory"))
		actor["inventory"] = [253,253,254,255,256,227,232,0]
		ally["inventory"] = [259,260,261,247,0,0,0,0]
		if mode in ["melee","victory","defeat","growth"]:
			foe["coord"] = Vector2i(15,16); actor["hit_bonus_accum"] = 1000
		if mode == "melee":
			foe["no_attack"] = false; foe["hit_bonus_accum"] = 1000
			foe["growth_profile"]["source"]["attack_back"] = 100; actor["growth_profile"]["source"]["attack_damagex2"] = 100
			TestSuite.own(loop, "skill_book")["actors"]["002"]["double_attack"] = true; TestSuite.own(loop, "skill_book")["actors"]["026"]["double_attack"] = true
		if mode == "magic":
			TestSuite.own(loop, "skill_book")["actors"]["002"]["supported_initial_ids"].append(WIND)
			actor["mp"] = 8; ally["hp"] = 100
		if mode == "growth":
			actor["exp"] = 99; foe["hp"] = 1; ally["hp"] = 100
			actor["inventory"] = [253,227,87,232,244,0,0,0]
			var other := foe.duplicate(true); other["id"] = "enemy026_2"; other["coord"] = Vector2i(18,18); other["hp"] = other["max_hp"]
			loop["units"].append(other)
		if mode in ["resistance","cap"]:
			actor["inventory"] = [257,257,207,227,0,0,0,0]
			actor["permanent_gains"]["resist_0"] = (75-int(actor["combat_profile"]["resist_by_type"]["0"])) if mode == "resistance" else 79-PermanentCapabilityRules.base_value(actor,"resist_0")
		if mode == "details":
			for field in PermanentCapabilityRules.KEYS: actor["permanent_gains"][field] = 10 if field.begins_with("resist_") else 5
		if mode == "mixed":
			actor["inventory"] = [253,247,227,0,0,0,0,0]
			actor.merge(BattlePlayLoop.StatusEffectRules.apply(actor,"poison",3,5)["changes"],true)
			actor.merge(BattlePlayLoop.StatusEffectRules.apply(actor,"no_magic",3)["changes"],true)
			run_support_magic_tests.buff(loop,"tina","attack_up",3,24); run_support_magic_tests.buff(loop,"tina","defense_up",3,30)
			foe["mp"] = 18; TestSuite.own(loop, "skill_book")["actors"]["026"]["supported_initial_ids"] = [run_support_magic_tests.DISPEL]
			TestSuite.own(loop, "skill_book")["skills"][run_support_magic_tests.DISPEL]["fields"]["use_ratio"] = "100"
			TestSuite.own(loop, "ai_profiles")["actors"]["026"]["profile"].merge({"ai_check_hp":0,"ai_check_dying":0,"ai_help_otherhp":0,"ai_help_status":0,"ai_help_attack":0,"ai_att_magic":100},true)
		if mode == "movement": ally["coord"] = Vector2i(15,15); ally["hp"] = 100
		if mode == "paralysis":
			actor["equipment"].append({"slot":"accessory2","item_code":227})
			actor.merge(BattlePlayLoop.StatusEffectRules.apply(actor,"paralysis",2)["changes"],true); actor["status_counters"]["paralysis"] = 1
			actor.merge(BattlePlayLoop.StatusEffectRules.apply(actor,"no_magic",3)["changes"],true)
		if mode == "ai":
			ally["player_commandable"] = false; ally["battle_actor_role"] = BattlePlayLoop.ROLE_FRIENDLY
			ally["inventory"] = [253,0,0,0,0,0,0,0]; ally["hit_bonus_accum"] = 1000
			foe["coord"] = Vector2i(15,15)
		if mode == "speed":
			ally["growth_profile"]["source"]["speed"] += int(actor["live_speed"])-int(ally["live_speed"])-1
			for seed_value in range(1,100):
				if BattlePlayLoop.ItemResolutionRules.DamageRandom.rand(BattlePlayLoop.ItemResolutionRules.DamageRandom.seeded(seed_value),5)["value"] == 4: loop["damage_rng"] = BattlePlayLoop.ItemResolutionRules.DamageRandom.seeded(seed_value); break
		if mode == "victory": actor["exp"] = 99; foe["hp"] = 1
		if mode == "defeat":
			actor["hp"] = 1; foe["no_attack"] = false; foe["hit_bonus_accum"] = 1000
			foe["growth_profile"]["source"].merge({"attack_back":100,"attack_power":1000},true)
		if mode == "escape": actor["coord"] = Vector2i(13,10); ally["coord"] = Vector2i(13,11); foe["coord"] = Vector2i(12,10)
		for unit in loop["units"]:
			unit.merge(BattlePlayLoop.ProgressionRules.refresh_growth_stats(unit,loop["equipment_items"]),true)
			unit["grid_coord"] = unit["coord"]; unit["ai_home_coord"] = unit["coord"]
			check(BattlePlayLoop.TraversalRules.placement_error(unit,loop["units"],loop["tiles"],loop["map_size"]) == "","legal source terrain placement")
		loop["turn_queue"] = BattlePlayLoop.CoreTurnQueue.rebuild(loop["units"])
		scene.apply_loop(BattlePlayLoop._return_to_player(loop,"tina"), "test")
		for art in scene.actors_root.get_children(): scene.actors_root.remove_child(art); art.queue_free()
		scene.unit_grid_coords.clear(); scene.resume_turn_presentation(); scene.center_camera_on_grid(actor["coord"]); scene.set_process(true)
	initial_state = scene.play_loop.duplicate(true)
	scene.get_node("BattlePresentation").cutin.impact.connect(func(strike,attacker,defender,counter):impacts.append({"strike":strike.duplicate(true),"attacker":attacker["id"],"defender":defender["id"],"counter":counter}))
	await create_timer(0.25).timeout

func cancel_item(code: int, disabled: bool = false) -> void:
	var before: Dictionary = scene.play_loop.duplicate(true)
	await click(scene.action_menu.get_node("ItemCommand")); await create_timer(0.25).timeout
	await click(scene.item_panel.menu.get_node("UseCommand")); await click(item_button(code))
	var target: Button = scene.item_panel.target_buttons["tina"]
	check(target.disabled == disabled,"target eligibility reflects intrinsic cap")
	await hover(target.get_global_rect().get_center()); await shot("preview-"+str(code))
	if disabled: await point(target.get_global_rect().get_center())
	await escape(); await escape(); await create_timer(0.25).timeout; await escape(); await settle("tina")
	check(scene.play_loop["units"] == before["units"] and scene.play_loop["damage_rng"] == before["damage_rng"],"preview/cancel/disabled click does not consume or acquire")

func play_permanent() -> void:
	await settle("companion" if mode == "paralysis" else "tina")
	if mode not in ["manual","paralysis"]: await change_gear(227,"accessory2")
	if mode == "manual":
		await use_item_real(253,"tina"); await settle("companion")
		await use_item_real(259,"companion"); await settle("tina")
		check(PermanentCapabilityRules.active(BattlePlayLoop.unit(scene.play_loop,"tina")) and PermanentCapabilityRules.active(BattlePlayLoop.unit(scene.play_loop,"companion")),"public priest and heavy-role kits produce separate persistent gains")
	elif mode == "repeat":
		await cancel_item(253); await use_item_real(253,"tina"); await settle("tina"); await status_page("tina"); await save_restore()
		var first: Dictionary = scene.play_loop["last_item_use"].duplicate(true)
		await use_item_real(253,"tina"); await settle("companion")
		check(item_receipts.size() == 2 and BattlePlayLoop.unit(scene.play_loop,"tina")["permanent_gains"]["attack_power"] == first["permanent_effects"][0]["amount"] + scene.play_loop["last_item_use"]["permanent_effects"][0]["amount"],"two uses accumulate actual rolls while one final tail runs")
	elif mode == "magic":
		await change_gear(232,"accessory1"); await use_item_real(255,"tina"); await settle("tina")
		await move_to(Vector2i(15,16)); await cast_stat(WIND,"enemy026_1"); await settle("companion"); await return_to_tina()
		check(BattlePlayLoop.unit(scene.play_loop,"tina")["mp"] == 0,"permanent magic power never refills spell resource")
		await click(scene.action_menu.get_node("MagicCommand")); check(scene.magic_panel.choices[run_support_magic_tests.HEAL].disabled,"empty MP prevents later support despite acquired magic power"); await shot("empty-mp"); await escape(); await settle("tina")
		check(impacts.any(func(p):return p["strike"].get("skill_id") == WIND and p["strike"].get("actual_damage",0)>0),"source wind damage consumes the increased magic profile")
	elif mode == "melee":
		await use_item_real(254,"tina"); await settle("tina"); await attack("enemy026_1"); await settle("companion")
		check(impacts.size() == 4 and impacts.filter(func(p):return p["counter"]).size() == 2,"permanent defense is used by the two-strike/counter exchange")
	elif mode == "growth":
		await use_item_real(253,"tina"); await settle("tina"); await attack("enemy026_1"); await settle("companion")
		check(observed.has("growth"),"actual permanent-enhanced kill reaches EXP and allocation")
		var gains: Dictionary = BattlePlayLoop.unit(scene.play_loop,"tina")["permanent_gains"].duplicate(true)
		await return_to_tina(); await change_gear(87,"weapon"); await change_gear(232,"accessory1"); await status_page("tina"); await save_restore()
		await move_to(Vector2i(15,16)); await cast_heal("companion"); await settle("tina")
		check(BattlePlayLoop.unit(scene.play_loop,"tina")["permanent_gains"] == gains and impacts.any(func(p):return p["strike"].get("healing",0)>0),"growth/equipment/cleared death tile/moved healing retain exact acquired source")
	elif mode == "resistance":
		await change_gear(207,"accessory1"); await use_item_real(257,"tina"); await settle("tina"); await status_page("tina")
		check(BattlePlayLoop.unit(scene.play_loop,"tina")["combat_profile"]["resist_by_type"]["0"] == 80,"display cap does not reject useful intrinsic resistance")
		await change_gear(0,"accessory1"); await status_page("tina"); await save_restore()
		check(BattlePlayLoop.unit(scene.play_loop,"tina")["combat_profile"]["resist_by_type"]["0"] == 76,"removing equipment reveals previously acquired raw resistance")
	elif mode == "cap":
		await use_item_real(257,"tina"); await settle("tina"); await cancel_item(257,true); await status_page("tina")
		check(PermanentCapabilityRules.base_value(BattlePlayLoop.unit(scene.play_loop,"tina"),"resist_0") + BattlePlayLoop.unit(scene.play_loop,"tina")["permanent_gains"]["resist_0"] == 80 and scene.play_loop["item_use_sequence"] == 1,"raw80 blocks another spend/draw independent of current displayed resistance")
	elif mode == "details":
		await use_item_real(253,"tina"); await settle("tina")
		await click(scene.action_menu.get_node("StatusCommand"))
		var value: Label = scene.status_panel.permanent_summary
		check(value.visible and value.text.contains("永久獲得"),"status reveals permanent gain separately from basic attributes")
		await hover(value.get_global_rect().get_center()); await create_timer(0.9).timeout; await shot("permanent-detail")
		value = scene.status_panel.vitals.resist_values[0]
		check(value.tooltip_text.contains("原始") and value.tooltip_text.contains("職業與裝備另計"),"resistance details expose both cap positions")
		await hover(value.get_global_rect().get_center()); await create_timer(0.9).timeout; await shot("resistance-detail")
		await escape(); await settle("tina")
	elif mode == "mixed":
		await use_item_real(253,"tina"); await settle("tina"); await save_restore()
		await click(scene.action_menu.get_node("WaitCommand")); await settle("companion"); await return_to_tina()
		var actor := BattlePlayLoop.unit(scene.play_loop,"tina")
		check(PermanentCapabilityRules.active(actor) and StatEnhancementRules.word(actor,"attack_up") == 0 and StatEnhancementRules.word(actor,"defense_up") == 0 and BattlePlayLoop.StatusEffectRules.poisoned(actor) and BattlePlayLoop.StatusEffectRules.magic_blocked(actor),"enemy dispel clears temporary layer while permanent gains and negative states survive")
		await use_item_real(247,"tina"); await settle("tina"); await status_page("tina")
	elif mode == "movement":
		await move_to(Vector2i(15,16)); check(not BattlePlayLoop.command_available(scene.play_loop,"magic"),"ordinary moved action cannot cast")
		await use_item_real(254,"companion"); await settle("tina"); await save_restore(); await cast_heal("companion"); await settle("companion")
		check(PermanentCapabilityRules.active(BattlePlayLoop.unit(scene.play_loop,"companion")) and observed.has("movement"),"moved allied permanent use finishes action then independent stationary support remains legal")
	elif mode == "paralysis":
		check(observed.has("skip") and scene.play_loop["item_use_sequence"] == 0,"paralysis does not pre-spend a permanent item")
		await return_to_tina(); await use_item_real(253,"tina"); await settle("tina")
		check(BattlePlayLoop.StatusEffectRules.magic_blocked(BattlePlayLoop.unit(scene.play_loop,"tina")) and PermanentCapabilityRules.active(BattlePlayLoop.unit(scene.play_loop,"tina")),"next legal action may acquire while still silenced")
	elif mode == "ai":
		await use_item_real(253,"companion"); await settle("tina"); await click(scene.action_menu.get_node("WaitCommand")); await settle("tina")
		check(impacts.any(func(p):return p["attacker"] == "companion") and PermanentCapabilityRules.active(BattlePlayLoop.unit(scene.play_loop,"companion")),"AI freshly attacks with acquired profile")
		check(BattlePlayLoop.unit(scene.play_loop,"companion")["inventory"] == [253,0,0,0,0,0,0,0] and scene.play_loop["item_use_sequence"] == 1,"AI does not invent proactive rare-item consumption")
	elif mode == "speed":
		var order: Array = scene.play_loop["turn_queue"]["slots"].duplicate(true)
		await use_item_real(256,"companion"); await settle("tina")
		check(scene.play_loop["turn_queue"]["slots"] == order,"acquired speed does not reorder already prepared round")
		await click(scene.action_menu.get_node("WaitCommand")); await settle("companion"); await click(scene.action_menu.get_node("WaitCommand")); await settle("companion")
		check(scene.play_loop["turn"] >= 2 and BattlePlayLoop.CoreTurnQueue.current(scene.play_loop["turn_queue"])["id"] == "companion","next actual round uses acquired speed for new ordering")
	else:
		await use_item_real(253,"tina"); await settle("tina"); await save_restore()
		if mode == "escape": await move_to(Vector2i(14,10)); await click(scene.action_menu.get_node("WaitCommand"))
		else: await attack("enemy026_1")
		await settle("",true)
	await save_restore()
	var row: Dictionary = {"mode":mode,"initial_units":initial_state["units"],"initial_book":initial_state["skill_book"],"initial_ai":initial_state["ai_profiles"],"final_units":scene.play_loop["units"],"outcome":scene.play_loop["battle_outcome"],"combat_receipts":receipts.duplicate(true),"items":item_receipts.duplicate(true),"impacts":impacts.duplicate(true),"events":events.duplicate(true),"observed":observed.duplicate(true),"sounds":sounds.keys(),"saves":saves,"restarted":false}
	if mode in ["victory","defeat","escape"]:
		var frozen: Dictionary = scene.play_loop.duplicate(true)
		check(BattlePlayLoop.use_item(frozen,"253") == frozen and BattlePlayLoop.step_ai_turn(frozen) == frozen and BattlePlayLoop.finish_exhausted_action(frozen) == frozen,"terminal rejects permanent resampling and additional actions")
		reload_current_scene(); await create_timer(0.4).timeout; scene = current_scene
		check(not BattleOutcome.decided(scene.play_loop) and scene.play_loop["item_use_sequence"] == 0 and scene.play_loop["units"].all(func(u):return not PermanentCapabilityRules.active(u)),"actual restart initializes zero acquired offsets without replay")
		row["restarted"] = true
	routes.append(row)

func shot(label: String) -> void:
	var receipt: Dictionary = scene.play_loop.get("last_item_use",{}) if is_instance_valid(scene) else {}
	if not receipt.is_empty() and not item_seen.has(receipt["sequence"]): item_seen[receipt["sequence"]] = true; item_receipts.append(receipt.duplicate(true))
	await process_frame; RenderingServer.force_draw(false)
	var name := mode+"-"+label+".png"; check(root.get_texture().get_image().save_png(PERM_OUT+name) == OK,"capture "+label)
	if not frames.has(name): frames.append(name)

func write_receipt(filename: String) -> void:
	FileAccess.open(PERM_OUT+filename,FileAccess.WRITE).store_string(JSON.stringify({"schema":"hsl_permanent_items_playable_review.v1","fixture":true,"native_execution":false,"real_control_events":true,"pid":OS.get_process_id(),"time_scale":Engine.time_scale,"screen":root.current_screen,"window_size":root.size,"elapsed_seconds":(Time.get_ticks_msec()-started)/1000.0,
		"setup":"Manual uses published PermanentItemsTrial. Other routes explicitly supply durable source002/024/026 roles, source051 terrain, inventories, EXP99/HP1 and probabilities/double capabilities, initial negative/positive statuses and previous acquired resistance near cap. No post-setup state mutation; source random item sampling, damage, costs, growth, inventory, turns and outcomes are actual production operations via visible controls. Checkpoints are isolated from campaign saves. Rare-item AI proactive policy is not invented.","routes":routes,"frames":frames,"failures":failures,"active":{} if not is_instance_valid(scene) else {"mode":mode,"selected":scene.selected_unit_id,"interaction":scene.play_loop.get("interaction"),"scenario_error":scene.play_loop.get("scenario_error"),"units":scene.play_loop.get("units"),"last_item_use":scene.play_loop.get("last_item_use"),"last_ai_actions":scene.play_loop.get("last_ai_actions"),"observed":observed}},"  "))
