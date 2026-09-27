extends "res://tests/capture_permanent_items_review.gd"
## Real item/move/result/resume controls. Only campaign storage is redirected to
## this harness's isolated file; no player campaign data is read or overwritten.
const Campaign = preload("res://game/battle/runtime/CampaignProgress.gd")
const CARRY_OUT := "res://ignored/permanent-carry-review/"
const CARRY_SAVE := CARRY_OUT+"campaign.json"
var carry_before := {}

func run() -> void:
	if DisplayServer.get_name()=="headless": push_error("Carry review needs a rendered window"); quit(2); return
	root.title="HSL Permanent Campaign Review"; root.size=Vector2i(640,480)
	root.position=DisplayServer.screen_get_position(root.current_screen)+Vector2i(60,80)
	root.notify_mouse_entered()
	DirAccess.make_dir_recursive_absolute(CARRY_OUT); started=Time.get_ticks_msec()
	create_timer(600).timeout.connect(func():check(false,"bounded carry review timeout"))
	mode="carry-prepare" if OS.get_cmdline_user_args().is_empty() else str(OS.get_cmdline_user_args()[0])
	Campaign.pending={}; Campaign.last_entry={}
	if mode=="carry-prepare": await prepare_route()
	else: await resume_route()
	await close_scene(); write_receipt(mode+".json")
	print("PERMANENT_CARRY_RENDER_PASS mode=",mode," frames=",frames.size())
	quit(0)

func prepare_route() -> void:
	scene=load("res://game/battle/scene/BattleSceneRuntime.tscn").instantiate()
	scene.startup_mode="dev_first_control"; root.add_child(scene); current_scene=scene; scene.set_process(false)
	var loop := BattleFixture.loop()
	var actor := Loop._unit(loop,"leonard")
	var zone: Vector2i=loop["escape_zone"][0]
	actor["coord"]=zone+Vector2i(-1,0); actor["ai_home_coord"]=actor["coord"]
	actor["inventory"]=[253,0,0,0,0,0,0,0]
	actor["equipment"].append({"slot":"accessory2","item_code":227})
	# Previous acquisitions are explicit input. This action adds its own source roll.
	for field in Acquired.KEYS: actor["permanent_gains"][field]=1
	actor.merge(Loop.ProgressionRules.refresh_growth_stats(actor,loop["equipment_items"]),true)
	var foe := Loop._unit(loop,"enemy021_1"); foe["coord"]=zone+Vector2i(4,0); foe["ai_home_coord"]=foe["coord"]
	# The source report withdraws one021. Keep another live enemy so the report
	# cannot correctly finish the fixture by enemy-clear before our item action.
	var remaining := foe.duplicate(true); remaining["id"]="enemy021_2"
	remaining["coord"]=zone+Vector2i(5,0); remaining["ai_home_coord"]=remaining["coord"]
	loop["units"]=[actor,foe,remaining]; loop["turn"]=6
	loop["turn_queue"]=Loop.CoreTurnQueue.rebuild(loop["units"])
	# Only initial queue seating is supplied; subsequent actions use production completion.
	loop["turn_queue"]["slots"].sort_custom(func(a,b):return a["id"]=="leonard" and b["id"]!="leonard")
	for unit in loop["units"]:
		check(Loop.TraversalRules.placement_error(unit,loop["units"],loop["tiles"],loop["map_size"])=="","legal carry fixture terrain")
	scene.apply_loop(Loop._return_to_player(loop,"leonard"), "test")
	for art in scene.actors_root.get_children(): scene.actors_root.remove_child(art); art.queue_free()
	scene.unit_grid_coords.clear(); scene.resume_turn_presentation(); scene.center_camera_on_grid(actor["coord"])
	scene.settlement_controller.checkpoint_path=CARRY_OUT+"first.save"; scene.set_process(true)
	initial_state=scene.play_loop.duplicate(true)
	await settle("leonard")
	await use_item_real(253,"leonard"); await settle("leonard"); await save_restore()
	carry_before=Loop.unit(scene.play_loop,"leonard")
	check(carry_before["permanent_gains"]["attack_power"]>1,"visible item use adds a new acquired amount")
	await move_to(zone); await click(scene.action_menu.get_node("WaitCommand"))
	await finish_escape()
	check(scene.get_node("BattlePresentation").battle_finished,"actual escape finishes the battle")
	await shot("next-battle"); isolated_handoff()
	await changed_scene()
	check(scene.scenario_path=="res://content/battles/battle_052.json","real reload consumes the next-battle scenario")
	check(Loop.unit(scene.play_loop,"leonard")["permanent_gains"]==carry_before["permanent_gains"],"all gains reach second-battle initialization")
	await shot("second-opening")
	routes.append({"mode":mode,"initial_units":initial_state["units"],"item_receipt":item_receipts,"source_unit":carry_before,"received_unit":Loop.unit(scene.play_loop,"leonard"),"carry_receipt":scene.play_loop["campaign_carry_receipt"],"saved":Campaign.load_progress(CARRY_SAVE)})

func isolated_handoff() -> void:
	var handoff: Dictionary=scene.campaign_progress.prepare_handoff()
	check(not handoff.is_empty() and Campaign.save_progress(handoff,CARRY_SAVE),"production handoff writes to isolated campaign storage")
	Campaign.pending=handoff
	reload_current_scene()

func move_to(coord: Vector2i) -> void:
	var owner: String=scene.selected_unit_id
	await click(scene.action_menu.get_node("MoveCommand"))
	await hover(scene.grid_cell_center_to_logical_position(coord)); await shot("move-preview")
	check(Loop.movement_cells(scene.play_loop).has(coord),"source terrain permits carry-route movement")
	await point(scene.grid_cell_center_to_logical_position(coord)); await settle(owner)

func changed_scene() -> void:
	var old: Node=scene
	for _i in range(180):
		await process_frame
		if is_instance_valid(current_scene) and current_scene!=old:
			scene=current_scene; await process_frame; await process_frame
			scene.settlement_controller.checkpoint_path=CARRY_OUT+"second.save"
			return
	check(false,"scene handoff did not complete")

func finish_escape() -> void:
	for _i in range(3000):
		var view=scene.get_node("BattlePresentation")
		if view.dialogue_active(): await key(KEY_SPACE)
		if view.battle_finished:
			check(scene.play_loop["battle_outcome"]==BattleOutcome.VICTORY_ESCAPE and not scene.action_menu.visible,"escape freezes further actions")
			return
		await create_timer(0.02).timeout
	check(false,"escape result did not finish")

func resume_route() -> void:
	var saved:=Campaign.load_progress(CARRY_SAVE)
	check(not saved.is_empty(),"separate process reads earlier acquired campaign record")
	carry_before=saved["carry"]["units"]["leonard"].duplicate(true)
	scene=load("res://game/battle/scene/BattleSceneRuntime.tscn").instantiate()
	scene.startup_mode="dev_first_control"; root.add_child(scene); current_scene=scene
	# Render the same resume dialog from the isolated record, preserving the
	# production acceptance callback and actual reload into product_opening.
	scene.campaign_progress._show_resume_prompt(saved,"惡夢的終曲")
	await create_timer(0.25).timeout
	await shot("resume-prompt"); await click(scene.campaign_progress.resume_button)
	check(not paused,"real resume button unpauses its production callback")
	await changed_scene()
	check(Acquired.KEYS.all(func(k):return Loop.unit(scene.play_loop,"leonard")["permanent_gains"][k]==carry_before["permanent_gains"][k]),"fresh process resume does not reapply item gains")
	for _i in range(9000):
		var coordinator=scene.opening_coordinator
		if coordinator==null or not coordinator.active: break
		if coordinator.summary().get("current_event_kind")=="dialogue_message_id": await key(KEY_SPACE)
		await create_timer(0.02).timeout
	await settle("leonard"); await status_page("leonard"); await save_restore()
	check(Acquired.KEYS.all(func(k):return Loop.unit(scene.play_loop,"leonard")["permanent_gains"][k]==carry_before["permanent_gains"][k]),"post-opening controls and single-battle load preserve campaign gains")
	var before_restart: Dictionary=Loop.unit(scene.play_loop,"leonard")["permanent_gains"].duplicate(true)
	# Restart is offered only on a result page. Finish by actual Wait actions so
	# this route exercises the button's real eligibility rather than calling it early.
	await finish_defeat()
	reload_current_scene(); await changed_scene()
	check(Loop.unit(scene.play_loop,"leonard")["permanent_gains"]==before_restart,"retry uses entry acquisition exactly once")
	await shot("retry-entry")
	routes.append({"mode":mode,"loaded":saved,"restored_unit":Loop.unit(scene.play_loop,"leonard"),"saves":saves,"restarted":true})

func finish_defeat() -> void:
	for _i in range(15000):
		var view=scene.get_node("BattlePresentation")
		check(scene.play_loop["scenario_ok"],"valid continued campaign battle")
		if view.dialogue_active(): await key(KEY_SPACE)
		if view.battle_finished:
			check(BattleOutcome.lost(scene.play_loop),"actual enemy actions reach defeat before retry")
			await shot("defeat-before-retry"); return
		if scene.action_menu.visible and not scene.action_menu.is_expanding() and not scene.ai_playback_active and not view.combat_busy(scene.play_loop) and not scene.has_actor_motion():
			await click(scene.action_menu.get_node("WaitCommand"))
		await create_timer(0.02).timeout
	check(false,"continued battle did not reach its retry boundary")

func shot(label: String) -> void:
	if is_instance_valid(scene):
		var receipt:Dictionary=scene.play_loop.get("last_item_use",{})
		if not receipt.is_empty() and not item_seen.has(receipt["sequence"]): item_seen[receipt["sequence"]]=true; item_receipts.append(receipt.duplicate(true))
	await process_frame; RenderingServer.force_draw(false)
	var name:=mode+"-"+label+".png"
	check(root.get_texture().get_image().save_png(CARRY_OUT+name)==OK,"capture "+label)
	if not frames.has(name):frames.append(name)

func write_receipt(filename: String) -> void:
	FileAccess.open(CARRY_OUT+filename,FileAccess.WRITE).store_string(JSON.stringify({"schema":"hsl_permanent_carry_review.v1","fixture":true,"pid":OS.get_process_id(),"time_scale":Engine.time_scale,"screen":root.current_screen,"mode":mode,"routes":routes,"frames":frames,"failures":failures,"setup":"First battle source001 and two021 actors at turn6 adjacent to escape, declared prior one-point gains in nine fields plus actual use of253. The report withdraws one021, leaving the other. Extra-action227 is supplied. All subsequent item/move/wait/status/F5/F9/resume controls are real; only campaign file selection and save destination use an isolated harness callback, with unchanged production prepare_handoff/save_progress/take_handoff/apply/reload. Resume reads that disk record in a separate process. No user campaign save is touched."},"  "))
