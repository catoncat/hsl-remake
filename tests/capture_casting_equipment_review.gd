extends "res://tests/capture_role_resources_review.gd"
## Actual controls on original art/terrain. Encounter/gear grants are explicit fixtures.
const CASTING_OUT := "res://ignored/casting-equipment-review/"
const StatusApplicationRules = preload("res://game/sim/StatusApplicationRules.gd")
const BLOOD := 145
const POISON_MAGIC := "magic:magicAIR:magicCode05"
const SEAL_MAGIC := "magic:magicMIND:magicCode02"
var original_armor := 0
var equipment_previews: Array = []


func run() -> void:
	if DisplayServer.get_name() == "headless": push_error("Casting review requires the rendered built-in window"); quit(2); return
	root.title = "HSL Casting Equipment Review"
	root.size = Vector2i(640,480)
	root.position = DisplayServer.screen_get_position(root.current_screen) + Vector2i(60,80)
	DirAccess.make_dir_recursive_absolute(CASTING_OUT)
	create_timer(600).timeout.connect(func():push_error("CASTING_EQUIPMENT_REVIEW_TIMEOUT");quit(2))
	var names: Array = ["poison_tail","full_mp","one_hp","remove_restore","accuracy","blood_growth","blood_support","blood_item","poison_guard","silence_guard","detour","ai_blood","ai_silence","victory","defeat","escape"]
	if not OS.get_cmdline_user_args().is_empty(): names = Array(OS.get_cmdline_user_args())
	for name in names:
		mode = name
		await setup_casting()
		if failures.is_empty(): await play_casting()
		await close_scene()
		FileAccess.open(CASTING_OUT+"progress.json",FileAccess.WRITE).store_string(JSON.stringify({"routes":routes,"failures":failures},"  "))
		if not failures.is_empty(): break
	FileAccess.open(CASTING_OUT+"receipt.json",FileAccess.WRITE).store_string(JSON.stringify({
		"fixture":true,"native_execution":false,"real_control_events":true,"time_scale":Engine.time_scale,
		"screen":root.current_screen,"window_position":root.position,"window_size":root.size,
		"overrides":"Source art/WRD/job modes and gear eligibility retained. Controlled mage uses original026 under protagonist harness ID with manual allocation; source baseHP+180 and speed+120 keep multicycle fixture stable through actual equip/growth. Named source gear is supplied in eight inventory slots, never granted to formal battle. Current HP/MP, no_attack waiting foe, positions and counter rates are authored once at setup. Blood growth starts99EXP/one target1HP and another durable target. Poison/seal fixtures grant registered source spell to controlled enemy026, source baseMP+100, hit compensation1000 and status rate100 to expose protection reliably; this is not a new default grant or source probability claim. Source HP+180 is omitted in1HP final defeat only as appropriate. AI has source blood armor and half cost, starts0MP or silence1, then follows actual queue cycles. Terminal scenarios use original report hooks/escape cells; fatal counter uses source attack1000. No outcome, damage, experience or combat RNG replacement; no accelerated clock or terrain edits. Transfer samples the normal saved recovery stream.",
		"routes":routes,"failures":failures},"  "))
	print("CASTING_EQUIPMENT_RENDER_","PASS" if failures.is_empty() else "FAIL"," routes=",routes.size())
	quit(0 if failures.is_empty() else 1)


func setup_casting() -> void:
	equipment_previews = []
	await setup_role()
	scene.set_process(false)
	var loop: Dictionary = scene.play_loop
	var actor := BattlePlayLoop.unit_ref(loop,"leonard")
	var enemy := BattlePlayLoop.unit_ref(loop,"enemy021_1")
	var ally := BattlePlayLoop.unit_ref(loop,"enemy023_1")
	original_armor = BattlePlayLoop.EquipmentRules.equipped_code(actor["equipment"],"armor")
	actor["growth_profile"]["source"]["hit_point"] += 180
	actor["growth_profile"]["source"]["speed"] += 120
	actor.merge(BattlePlayLoop.ProgressionRules.refresh_growth_stats(actor,loop["equipment_items"]),true)
	actor["hp"] = actor["max_hp"]
	actor["mp"] = 0
	actor["inventory"] = [145,128,217,219,215,226,218,227]
	enemy["no_attack"] = true
	if mode == "blood_growth":
		actor["exp"] = 99; enemy["hp"] = 1
		var later := enemy.duplicate(true)
		later.merge({"id":"enemy021_2","coord":Vector2i(12,9),"hp":500,"max_hp":500,"live_speed":60},true)
		loop["units"].append(later)
	elif mode == "blood_support":
		TestSuite.own(loop, "skill_book")["actors"][chosen_role]["supported_initial_ids"] = [run_extra_attack_tests.WIND,run_extra_attack_tests.HEAL,run_extra_attack_tests.CURE]
		ally["coord"] = Vector2i(11,8); ally["hp"] = 4; enemy["coord"] = Vector2i(17,18)
	elif mode == "blood_item":
		actor["hp"] = 20; actor["inventory"][1] = 241
	elif mode == "poison_tail":
		actor["hp"] = 20; actor["inventory"][1] = 223; actor["inventory"][2] = 224
		actor.merge(BattlePlayLoop.StatusEffectRules.apply(actor,"poison",3,7)["changes"],true)
		actor.merge(BattlePlayLoop.StatusEffectRules.apply(actor,"no_magic",2)["changes"],true)
	elif mode == "one_hp": actor["hp"] = 1
	elif mode in ["full_mp","accuracy"]: actor["mp"] = actor["max_mp"]
	elif mode == "detour": actor["inventory"][1] = 193
	if mode in ["poison_guard","silence_guard"]:
		actor["mp"] = actor["max_mp"]
		# Keep room for both returned sources; the full eight-item fixture correctly
		# refused unequip. Protection must not bypass the real inventory capacity.
		actor["inventory"] = [128,217,0,0,0,0,0,0] if mode == "poison_guard" else [219,0,0,0,0,0,0,0]
		var caster := BattlePlayLoop.unit(BattleFixture.loop(),"enemy026_1")
		caster.merge({"id":"enemy021_1","coord":Vector2i(11,8),"player_commandable":true,"battle_actor_role":BattlePlayLoop.ROLE_ENEMY,"live_speed":110,"inventory":[0,0,0,0,0,0,0,0]},true)
		caster["growth_profile"]["source"]["magic_point"] += 100
		caster.merge(BattlePlayLoop.ProgressionRules.refresh_growth_stats(caster,loop["equipment_items"]),true)
		caster["mp"] = caster["max_mp"]; caster["live_speed"] = 110; caster["hit_bonus_accum"] = 1000
		var id := POISON_MAGIC if mode == "poison_guard" else SEAL_MAGIC
		TestSuite.own(loop, "skill_book")["actors"]["026"]["supported_initial_ids"] = [run_extra_attack_tests.WIND,id]
		TestSuite.own(loop, "skill_book")["skills"][id]["fields"]["status_hit_ratio"] = "100"
		ally["coord"] = Vector2i(9,8)
		loop["units"] = [actor,caster,ally]
	if mode.begins_with("ai_"):
		actor["equipment"] = actor["equipment"].filter(func(e):return e["slot"] != "armor" and not str(e["slot"]).begins_with("accessory"))
		for entry in [["armor",145],["accessory1",218]]: actor["equipment"].append({"slot":entry[0],"item_code":entry[1],"name":loop["equipment_items"][str(entry[1])]["name"]})
		actor.merge(BattlePlayLoop.ProgressionRules.refresh_growth_stats(actor,loop["equipment_items"]),true)
		actor["mp"] = 0; actor["hp"] = actor["max_hp"]; actor["live_speed"] = 160; actor["no_attack"] = true
		BattlePlayLoop.unit_ref(loop,"resource-initial")["live_speed"] = 200
		if mode == "ai_silence":
			actor.merge(BattlePlayLoop.StatusEffectRules.apply(actor,"no_magic",2)["changes"],true)
			actor["status_counters"]["no_magic"] = 1 # Supplied remaining duration, not a one-turn new application.
	if mode == "defeat":
		actor["hp"] = 1
		enemy["no_attack"] = false
		enemy["hit_bonus_accum"] = 1000
		enemy["combat_profile"]["live_attack_damage"] = 1000
	for unit in loop["units"]:
		unit["grid_coord"] = unit["coord"]; unit["ai_home_coord"] = unit["coord"]
		check(not loop["tiles"].get(unit["coord"],{}).get("blocks_movement",false),"casting fixture stands on original walkable terrain")
	loop["turn_queue"] = BattlePlayLoop.CoreTurnQueue.rebuild(loop["units"])
	scene.apply_loop(BattlePlayLoop.return_to_player(loop,"resource-initial" if mode.begins_with("ai_") else "leonard"), "test")
	scene.settlement_controller.checkpoint_path = CASTING_OUT+mode+".save"
	for node in scene.actors_root.get_children(): scene.actors_root.remove_child(node);node.queue_free()
	scene.unit_grid_coords.clear(); scene.resume_turn_presentation(); scene.center_camera_on_grid(actor["coord"])
	scene.get_node("BattlePresentation").turn_end_cue.finish(scene.play_loop)
	baseline_role = actor.duplicate(true)
	scene.set_process(true)
	await create_timer(0.35).timeout


func change_item(code: int, slot: String, cancellation: bool = false) -> void:
	await open_equipment_real()
	if code == 0: await click(scene.item_panel.equipment_view.slot_controls[slot])
	else:
		await click(item_button(code))
		if slot.begins_with("accessory"): await click(find_button(scene.item_panel.page_root,"飾品 "+slot.right(1)))
	var text := ""
	for label in scene.item_panel.page_root.find_children("*","Label",true,false): text += label.text + "\n"
	check(not scene.item_panel.confirm_button.disabled,"source job permits selected equipment %s/%s: %s" % [code,slot,text])
	if code == 145: check(text.contains("魔力已滿仍耗生命") and text.contains("生命轉魔力"),"blood armor preview states its actual cost even at full MP")
	if code in [215,226]: check(text.contains("魔法命中修正"),"accuracy equipment preview uses the shared current modifier")
	if code in [128,217,219] and not (code==128 and StatusApplicationRules.modifiers(BattlePlayLoop.unit(scene.play_loop,"leonard"),scene.play_loop["skill_book"],scene.play_loop["equipment_items"])["effects"] & 0x800000):
		check(text.contains("不解除已有狀態"),"protection preview distinguishes prevention from cleansing")
	for child in scene.item_panel.page_root.get_children():
		if child is ScrollContainer:
			for _step in range(24):
				var bar = child.get_v_scroll_bar()
				if bar.value >= bar.max_value - bar.page: break
				await hover(child.get_global_rect().get_center())
				var wheel := InputEventMouseButton.new();wheel.position=child.get_global_rect().get_center();wheel.button_index=MOUSE_BUTTON_WHEEL_DOWN;wheel.pressed=true
				root.push_input(wheel,true);wheel=wheel.duplicate();wheel.pressed=false;root.push_input(wheel,true);await process_frame
			check(not child.get_global_rect().intersects(scene.item_panel.confirm_button.get_global_rect()),"long source effect preview stays clear of confirmation")
	await shot("equip-"+str(code)+"-"+slot)
	var before: Dictionary = scene.play_loop.duplicate(true)
	if cancellation:
		await click(find_button(scene.item_panel.page_root,"取消"))
		check(scene.play_loop == before,"cancelled new-equipment proposal does not change resources or action")
		await click(item_button(code))
		if slot.begins_with("accessory"): await click(find_button(scene.item_panel.page_root,"飾品 "+slot.right(1)))
	await click(scene.item_panel.confirm_button);await create_timer(0.3).timeout
	check(BattlePlayLoop.EquipmentRules.equipped_code(BattlePlayLoop.unit(scene.play_loop,"leonard")["equipment"],slot)==code and scene.play_loop["turn_queue"]==before["turn_queue"] and scene.play_loop["extra_action"]==before["extra_action"],"real equip/unequip commits once without spending or renewing action")
	equipment_previews.append({"code":code,"slot":slot,"text":text})


func next_player_cycle() -> void:
	await click(scene.action_menu.get_node("WaitCommand"))
	await settle("leonard")


func play_casting() -> void:
	var terminal: bool = mode in ["victory","defeat","escape"]
	if mode.begins_with("ai_"):
		await click(scene.action_menu.get_node("WaitCommand"));await settle("enemy023_1")
		pair_receipts.append(scene.play_loop["last_ai_action"].duplicate(true))
		check(not pair_receipts[0].has("skill_id") and BattlePlayLoop.unit(scene.play_loop,"leonard")["mp"] >= 4,"unaffordable or silenced AI first falls back then converts blood")
		await click(scene.action_menu.get_node("WaitCommand"));await settle("resource-initial")
		await click(scene.action_menu.get_node("WaitCommand"));await settle("enemy023_1")
		pair_receipts.append(scene.play_loop["last_ai_action"].duplicate(true))
		check(pair_receipts[1].get("skill_id")==run_extra_attack_tests.WIND and pair_receipts[1]["resource_payment"]["amount"]==4,"new actual AI cycle builds and pays one half-cost wind spell from converted MP")
	elif mode in ["poison_guard","silence_guard"]:
		await protection_flow()
	elif mode == "accuracy":
		await change_item(215,"accessory1",true);await change_item(226,"accessory2")
		await move_to(Vector2i(10,8));await cast_real(run_extra_attack_tests.WIND,"enemy021_1");await settle("enemy023_1")
		check(pair_receipts[0]["native_damage_roll"]["hit_rate"] >= 116 and pair_receipts[0]["damage"] > 0,"current equipped hit bonus enters real source wind damage")
	else:
		await change_item(145,"armor",true)
		if mode in ["blood_growth","remove_restore","victory","defeat","escape"]: await change_item(227,"accessory2")
		if mode == "blood_growth": await change_item(226,"accessory1")
		if mode == "blood_support": await change_item(218,"accessory1")
		if mode == "poison_tail": await change_item(223,"accessory1");await change_item(224,"accessory2")
		if mode == "detour": await change_item(193,"foot")
		first_snapshot = scene.play_loop.duplicate(true)
		if mode == "blood_growth":
			await click(scene.action_menu.get_node("WaitCommand"));await settle("leonard")
			check(resource_beats.is_empty() and BattlePlayLoop.unit(scene.play_loop,"leonard")["mp"]==0,"independent first action cannot convert resources early")
			await move_to(Vector2i(10,8));await attack_target();pair_receipts.append(receipt.duplicate(true));await settle("enemy023_1")
			check(observed.has("growth") and BattlePlayLoop.unit(scene.play_loop,"leonard")["level"]==2 and BattlePlayLoop.unit(scene.play_loop,"leonard")["mp"]>=8,"actual lethal second action completes job growth then blood conversion")
			await save_restore();await next_player_cycle()
			await move_to(Vector2i(10,9));await cast_real(run_extra_attack_tests.WIND,"enemy021_2");await settle("leonard")
			await click(scene.action_menu.get_node("WaitCommand"));await settle("enemy023_1")
			check(pair_receipts.back()["defender_hp_after"]>0 and pair_receipts.back().has("experience"),"new-cycle nonlethal spell retains final contribution EXP")
		elif mode == "blood_support":
			await click(scene.action_menu.get_node("WaitCommand"));await settle("enemy023_1");await next_player_cycle()
			await move_to(Vector2i(10,8));await cast_real(run_extra_attack_tests.HEAL,"enemy023_1");await settle("enemy023_1")
			check(pair_receipts.back()["healing"]>0 and pair_receipts.back()["resource_payment"]["amount"]==3 and pair_receipts.back().has("experience"),"blood mana funds a real reduced-cost support contribution")
		elif mode == "blood_item":
			await click(scene.action_menu.get_node("ItemCommand"));await create_timer(0.3).timeout
			await click(scene.item_panel.menu.get_node("UseCommand"));await click(item_button(241));await click(scene.item_panel.target_buttons["leonard"])
			await settle("enemy023_1")
			check(observed.has("item") and not BattlePlayLoop.unit(scene.play_loop,"leonard")["inventory"].has(241),"real item feedback precedes one blood conversion")
		elif mode == "remove_restore" or terminal:
			await click(scene.action_menu.get_node("WaitCommand"));await settle("leonard");await save_restore()
			if terminal:
				await move_to(landing if mode=="escape" else Vector2i(10,8))
				if mode=="escape": await click(scene.action_menu.get_node("WaitCommand"))
				else: await attack_target();pair_receipts.append(receipt.duplicate(true))
			else: await change_item(0,"armor");await click(scene.action_menu.get_node("WaitCommand"))
			await settle("enemy023_1",terminal)
			check(resource_beats.is_empty() and scene.play_loop["damage_rng"]==first_snapshot["damage_rng"],"terminal or removal cannot spend blood or replay a saved grant")
		elif mode == "detour":
			var found := false
			for cell in BattlePlayLoop.movement_cells(scene.play_loop):
				var path := BattlePlayLoop.movement_path(scene.play_loop,"leonard",cell)
				if path.size()>BattlePlayLoop.TacticalGridRules.manhattan(path[0],cell)+1 and Rect2(24,24,592,414).has_point(scene.grid_cell_center_to_logical_position(cell)): landing=cell;found=true;break
			check(found,"source map supports an affordable equipment-enabled detour")
			await move_to(landing);await click(scene.action_menu.get_node("WaitCommand"));await settle("enemy023_1")
		else:
			await click(scene.action_menu.get_node("WaitCommand"));await settle("enemy023_1")
			if mode == "poison_tail": check(resource_beats.map(func(e):return e["kind"])==["poison","auto_hp","auto_mp","transfer_hp","transfer_mp"],"all five actual feedback beats follow the source resource order")
			if mode == "full_mp": check(resource_beats.size()==1 and resource_beats[0]["kind"]=="transfer_hp" and BattlePlayLoop.unit(scene.play_loop,"leonard")["mp"]==baseline_role["max_mp"],"full MP retains the visible HP cost and no fake MP gain")
			if mode == "one_hp": check(resource_beats.is_empty() and scene.play_loop["last_action_end"]["draws"].size()==2 and BattlePlayLoop.unit(scene.play_loop,"leonard")["hp"]==1,"1HP completes with two saved samples and no spurious damage/death beat")
	await save_restore()
	var final: Dictionary = scene.play_loop.duplicate(true)
	routes.append({"mode":mode,"before":compact(baseline_role),"after":compact(BattlePlayLoop.unit(final,"leonard")),"level":BattlePlayLoop.unit(final,"leonard")["level"],"exp":BattlePlayLoop.unit(final,"leonard")["exp"],"equipment":BattlePlayLoop.unit(final,"leonard")["equipment"],"previews":equipment_previews,"beats":resource_beats,"receipts":pair_receipts,"last_action_end":final["last_action_end"],"observed":observed,"cues":cues,"experience":experience_events,"sounds":sound_paths.keys(),"outcome":final["battle_outcome"]})
	if terminal:
		check(final["action_end_sequence"]==0 and not final["extra_action"]["pending"],"terminal action freezes resource tail and repeat latch")
		reload_current_scene();await create_timer(0.3).timeout;scene=current_scene
		check(not BattleOutcome.decided(scene.play_loop) and scene.play_loop["action_end_sequence"]==0 and not BattlePlayLoop.ResourceRecoveryRules.effects(BattlePlayLoop.unit(scene.play_loop,"leonard"),scene.play_loop["equipment_items"])["effects"]["hp_transfer_mp"],"actual retry restores original default gear and fresh resource state")
		routes.back()["restarted"] = true


func protection_flow() -> void:
	var poison: bool = mode == "poison_guard"
	var code := 217 if poison else 219
	var id := POISON_MAGIC if poison else SEAL_MAGIC
	await change_item(code,"accessory1",true)
	if poison: await change_item(128,"armor")
	await click(scene.action_menu.get_node("WaitCommand"));await settle("enemy021_1")
	await cast_real(id,"leonard");await settle("enemy023_1")
	var effect: Dictionary = pair_receipts.back()["status_effects"][0]
	check(effect.get("reason")=="immune" and not effect["applied"],"actual protected target displays immune from shared spell receipt")
	if not poison: check(pair_receipts.back()["damage"]>0,"silence protection does not absorb the spell's preceding damage")
	await next_player_cycle()
	await change_item(0,"accessory1")
	if poison:
		check(StatusApplicationRules.modifiers(BattlePlayLoop.unit(scene.play_loop,"leonard"),scene.play_loop["skill_book"],scene.play_loop["equipment_items"])["effects"] & 0x800000,"removing accessory retains independent protective armor")
		await change_item(0,"armor")
	await save_restore()
	await click(scene.action_menu.get_node("WaitCommand"));await settle("enemy021_1")
	await cast_real(id,"leonard");await settle("enemy023_1")
	check(pair_receipts.back()["status_effects"][0]["applied"],"removing the last protective source permits actual status application")
	await next_player_cycle()
	var counters: Dictionary = BattlePlayLoop.unit(scene.play_loop,"leonard")["status_counters"].duplicate(true)
	await change_item(code,"accessory1")
	check(BattlePlayLoop.unit(scene.play_loop,"leonard")["status_counters"]==counters,"re-equipping protection cannot cure the existing condition")
	if not poison:
		await click(scene.action_menu.get_node("MagicCommand"))
		check(scene.magic_panel.choices[run_extra_attack_tests.WIND].disabled,"actual spell list remains disabled under existing silence")
		await shot("still-silenced");await escape();await create_timer(0.3).timeout
	await shot("protected-status")


func shot(label: String) -> void:
	await process_frame;RenderingServer.force_draw(false)
	check(root.get_texture().get_image().save_png(CASTING_OUT+mode+"-"+label+".png")==OK,"capture "+label)


func check(ok: bool, message: String) -> void:
	if ok: return
	failures.append(mode+": "+message);push_error(mode+": "+message)
	DirAccess.make_dir_recursive_absolute(CASTING_OUT)
	FileAccess.open(CASTING_OUT+"failed.json",FileAccess.WRITE).store_string(JSON.stringify({"mode":mode,"failures":failures,"routes":routes},"  "))
	quit(1)
