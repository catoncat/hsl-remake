extends SceneTree
## Windowed review of the chapter-1 campaign chain after the second battle:
## level-52 victory result page → 下一戰 → level 58 epilogue → level 60 throne hall →
## level 53 battle opening → first player control (緹娜) → escape win (gate cell + wait)
## → 繼續 → playable level-1 歐姆村 opening → a declared all-enemies-defeated
## terminal fixture drives its real win0 outro and return into the 大地圖 →
## 戈爾山道 (level-2 opening preview and back) → 歐姆村 (town screen). The level-52
## victory is an explicit fixture on the dev first-control seam and the level-53 win
## places 緹娜 on a gate cell. Level1 combat is independently played without outcome
## injection by capture_ohm_campaign_review.gd; this older route isolates transitions.
## Story scenes run at fast pacing because this review is
## about the transitions (each scene has its own paced review).
## Output: ignored/campaign-chain-review/*.png + manifest.json (visual review input).
const OUT := "res://ignored/campaign-chain-review/"
const CampaignProgress = preload("res://game/battle/runtime/CampaignProgress.gd")
const BattleOutcome = preload("res://game/sim/BattleOutcome.gd")
var failures: Array[String] = []
var records: Array = []


# A finished battle fades out and leaves by itself (no result page); these captures
# inspect the finished battle, then reload or hand off explicitly.
func _init() -> void:
	preload("res://game/battle/scene/BattleSceneRuntime.gd").hold_finished_battle = true

func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Campaign chain review requires a rendering window")
		quit(2)
		return
	root.title = "HSL Campaign Chain Review"
	root.size = Vector2i(640, 480)
	create_timer(420).timeout.connect(func(): push_error("Campaign chain review timed out"); quit(2))
	DirAccess.make_dir_recursive_absolute(OUT)
	CampaignProgress.reset_campaign()
	var scene = load("res://game/battle/scene/BattleSceneRuntime.tscn").instantiate()
	scene.scenario_path = "res://content/battles/battle_052.json"
	scene.startup_mode = "dev_first_control"
	root.add_child(scene)
	current_scene = scene
	await process_frame
	await process_frame
	var leonard: Dictionary = scene.BattlePlayLoop.unit_ref(scene.play_loop, "leonard")
	leonard["level"] = 3
	scene.play_loop["gold"] = 275
	scene.play_loop["turn"] = 9
	# Decide the battle the product way: the boss falls, the PlayLoop resolves the
	# outcome and commits WINFAIL052 win_0, whose chain (378) plays as a script
	# cutscene before the result page.
	var emperor: Dictionary = scene.BattlePlayLoop.unit_ref(scene.play_loop, "emperor025")
	emperor["hp"] = 0
	emperor["defeated"] = true
	scene.apply_loop(scene.BattlePlayLoop.resolve_outcome(scene.play_loop), "test")
	check(BattleOutcome.of(scene.play_loop) == BattleOutcome.VICTORY_BOSS, "the fallen boss decides the level-52 victory")
	var view = scene.get_node("BattlePresentation")
	var opening_coordinator = scene.opening_coordinator
	var waited := 0
	while waited < 120 and not (opening_coordinator != null and opening_coordinator.cutscene_mode):
		await process_frame
		waited += 1
	check(opening_coordinator != null and opening_coordinator.cutscene_mode and opening_coordinator.cutscene_key == "win_0", "the win_0 chain plays as a script cutscene")
	var confirmations := 0
	while opening_coordinator != null and opening_coordinator.active and confirmations < 20:
		if str(scene.scene_timeline.current_event().get("kind", "")) == "dialogue_message_id":
			if confirmations == 0:
				await create_timer(0.2).timeout
				await shot(scene, "01-level52-victory-line")
			opening_coordinator.advance("review_confirm")
			confirmations += 1
		await process_frame
	await create_timer(0.4).timeout
	check(not view.dialogue_active(), "378 is not paged a second time by the story queue")
	check(view.battle_finished, "the level-52 battle finishes (no result page)")
	await shot(scene, "02-level52-result-next")
	var previous_id: int = scene.get_instance_id()
	check(scene.campaign_progress.start_next_battle(), "the finished level-52 victory hands off")
	var next = await wait_reload(previous_id)
	check(next != null and str(next.scenario_path) == "res://content/battles/story_058.json", "下一戰 loads the level-58 epilogue")
	if next == null:
		failures.append("scene did not reload after the level-52 result")
	if next == null:
		finish(scene)
		return
	var gold := int(((next.campaign_handoff.get("carry", {}) as Dictionary).get("loop", {}) as Dictionary).get("gold", -1))
	check(gold == 275, "the carried party (gold 275) reaches the story scene hand-off")
	await create_timer(0.4).timeout
	await shot(next, "03-level58-opening")
	next = await play_story(next, "04-level58-end")
	check(next != null and str(next.scenario_path) == "res://content/battles/story_060.json", "level 58 hands off to level 60")
	if next == null:
		finish(null)
		return
	await create_timer(0.4).timeout
	await shot(next, "05-level60-opening")
	next = await play_story(next, "06-level60-end")
	check(next != null and str(next.scenario_path) == "res://content/battles/battle_053.json", "level 60 hands off to the level-53 battle")
	if next == null:
		finish(null)
		return
	check(int(((next.campaign_handoff.get("carry", {}) as Dictionary).get("loop", {}) as Dictionary).get("gold", -1)) == 275, "carry survives three story hand-offs")
	await create_timer(0.4).timeout
	await shot(next, "07-level53-opening")
	var coordinator = next.opening_coordinator
	check(coordinator != null and coordinator.active and not coordinator.story_mode, "the level-53 battle opening runs through the coordinator in battle mode")
	fast(coordinator)
	var frames := 0
	while coordinator.active and frames < 6000:
		if str(coordinator.summary().get("current_event_kind", "")) == "dialogue_message_id":
			await key(KEY_SPACE)
			continue
		await process_frame
		frames += 1
	await create_timer(0.5).timeout
	frames = 0
	while str(next.play_loop.get("interaction", "")) != "action_menu" and frames < 600:
		await process_frame
		frames += 1
	frames = 0
	while (next.has_actor_motion() or next.ai_playback_active) and frames < 600:
		await process_frame
		frames += 1
	await create_timer(0.3).timeout
	check(str(next.play_loop.get("selected_unit_id", "")) == "tina", "the chain ends at 緹娜's first player control")
	check(next.action_menu.visible, "緹娜's action menu is open at first control")
	check(not CampaignProgress.has_pending(), "no further hand-off is pending")
	var saved: Dictionary = CampaignProgress.load_progress()
	check(str(saved.get("scenario_path", "")) == "res://content/battles/battle_053.json", "the persisted campaign position is the level-53 battle")
	await shot(next, "08-level53-first-control")
	# Level 53 the product way: 緹娜 standing on a gate cell ends her action → escape
	# win → WINFAIL053 win_0 chain (704) as a cutscene → result page → 繼續 · 歐姆村.
	var loop53: Dictionary = next.play_loop.duplicate(true)
	for unit in loop53["units"]:
		if str(unit.get("id", "")) == "tina":
			unit["coord"] = Vector2i(30, 35)
			unit["grid_coord"] = Vector2i(30, 35)
	loop53 = next.BattlePlayLoop.begin_wait_resolution(next.BattlePlayLoop.choose_command(loop53, "wait"))
	check(BattleOutcome.of(loop53) == BattleOutcome.VICTORY_ESCAPE, "緹娜 on the gate cell decides the level-53 escape win")
	next.apply_loop(loop53, "test")
	frames = 0
	while frames < 240 and not (coordinator != null and coordinator.cutscene_mode):
		await process_frame
		frames += 1
	check(coordinator != null and coordinator.cutscene_mode and coordinator.cutscene_key == "win_0", "the level-53 win_0 chain plays as a script cutscene")
	await create_timer(0.2).timeout
	await shot(next, "09-level53-victory-line")
	frames = 0
	while frames < 240 and coordinator.active:
		coordinator.advance("review_confirm")
		await process_frame
		frames += 1
	var view53 = next.get_node("BattlePresentation")
	frames = 0
	while frames < 240 and not view53.battle_finished:
		await process_frame
		frames += 1
	var progress53 = next.get_node("CampaignProgress")
	check(view53.battle_finished and str(progress53.next_destination(progress53.campaign, next.play_loop, str(next.scenario_path)).get("title", "")) == "歐姆村", "the finished level-53 battle leads to the playable 歐姆村")
	await shot(next, "10-level53-result")
	progress53.start_next_battle()
	var preview = await wait_reload(next.get_instance_id())
	check(preview != null and str(preview.scenario_path) == "res://content/battles/ohm_village_battle.json", "winfail [1,1] enters the playable level-1 battle")
	if preview == null:
		finish(null)
		return
	# Preserve this route's transition-only fixture scope instead of skipping the
	# newly playable battle via the old preview card. The full game is played by
	# capture_ohm_campaign_review without a post-input outcome injection.
	var pc = preview.opening_coordinator
	check(pc != null and pc.active and not pc.story_mode, "level1 plays its opening in battle mode")
	fast(pc)
	frames = 0
	while is_instance_valid(pc) and pc.active and frames < 6000:
		if str(pc.summary().get("current_event_kind", "")) == "dialogue_message_id":
			await key(KEY_SPACE)
			continue
		await process_frame
		frames += 1
	check(is_instance_valid(pc) and not pc.active and preview.play_loop["units"].size()==18, "the level-1 opening reaches a real eighteen-actor battle")
	await create_timer(0.3).timeout
	for actor in preview.play_loop["units"]:
		if actor["battle_actor_role"]==preview.BattlePlayLoop.ROLE_ENEMY:
			actor["hp"]=0;actor["defeated"]=true
	preview.apply_loop(preview.BattlePlayLoop.resolve_outcome(preview.play_loop), "test")
	preview.apply_loop(preview.play_loop, "test")
	frames=0
	while frames<6000 and not preview.get_node("BattlePresentation").battle_finished:
		if pc.active and str(pc.summary().get("current_event_kind",""))=="dialogue_message_id":await key(KEY_SPACE)
		await process_frame
		frames+=1
	check(preview.play_loop["winfail_runtime"]["resolved"]["key"]=="win_0" ,"declared terminal fixture plays source win0 and finishes")
	await shot(preview, "11-level1-victory-result")
	var village_id:int=preview.get_instance_id()
	check(preview.campaign_progress.start_next_battle(), "the finished level-1 victory hands off")
	var map_scene = await wait_reload(village_id)
	check(map_scene != null and map_scene.world_map_runtime != null and map_scene.world_map_runtime.active, "the finished victory exits into the 大地圖")
	if map_scene == null:
		finish(null)
		return
	var map = map_scene.world_map_runtime
	check(int(map.summary().get("current_point", 0)) == 1, "the party stands at 歐姆村 (point 1)")
	await create_timer(1.2).timeout
	await shot(map_scene, "12-world-map-ohm-village")
	# Retained legacy preview regression only: the formal Gol two-stage battle
	# and its real victory→55→56→map are reviewed by capture_gol_road_review.
	# Isolate this historical preview path without changing product registration.
	map_scene.campaign_progress.campaign["battles"]["2"] = {"scenario":"res://content/battles/story_002.json", "title":"戈爾山道（獨立預覽回歸）", "kind":"story"}
	var map_id: int = map_scene.get_instance_id()
	map.select_point(2, "review")
	var preview2 = await wait_reload(map_id)
	check(preview2 != null and str(preview2.scenario_path) == "res://content/battles/story_002.json", "arriving at 戈爾山道 enters the level-2 opening preview")
	if preview2 == null:
		finish(null)
		return
	var pc2 = preview2.opening_coordinator
	check(pc2 != null and pc2.active and pc2.story_mode, "the level-2 preview runs through the coordinator in story mode")
	await create_timer(0.6).timeout
	await shot(preview2, "13-level2-preview-raiders-run")
	fast(pc2)
	frames = 0
	while is_instance_valid(pc2) and not pc2.story_finished and frames < 4000:
		if str(pc2.summary().get("current_event_kind", "")) == "dialogue_message_id":
			await key(KEY_SPACE)
			continue
		await process_frame
		frames += 1
	check(is_instance_valid(pc2) and pc2.story_finished, "the level-2 preview reaches its end card")
	await create_timer(0.3).timeout
	await shot(preview2, "14-level2-preview-end-card")
	await key(KEY_SPACE)
	map_scene = await wait_reload(preview2.get_instance_id())
	check(map_scene != null and map_scene.world_map_runtime != null and map_scene.world_map_runtime.active, "confirming the level-2 card returns to the 大地圖")
	if map_scene == null:
		finish(null)
		return
	map = map_scene.world_map_runtime
	check(int(map.summary().get("current_point", 0)) == 2 and not bool(map.summary().get("card_visible", false)), "the party stands at 戈爾山道 (point 2) with no card")
	await create_timer(1.2).timeout
	await shot(map_scene, "15-world-map-back-at-gorl-pass")
	# Back to 歐姆村: the town screen opens over the map.
	map.select_point(1, "review")
	frames = 0
	while map.traveling and frames < 1200:
		await process_frame
		frames += 1
	await create_timer(0.3).timeout
	check(bool(map.summary().get("town_open", false)), "arriving at 歐姆村 opens the town screen")
	await shot(map_scene, "16-ohm-village-town")
	await key(KEY_ESCAPE)
	await create_timer(0.2).timeout
	check(not bool(map.summary().get("town_open", false)), "Escape leaves the town")
	saved = CampaignProgress.load_progress()
	check(str(saved.get("scenario_path", "")) == "res://content/world/world_map_scene.json" and int((saved.get("world", {}) as Dictionary).get("current_point", 0)) == 1, "the persisted campaign position is the big map at 歐姆村")
	check(int((((saved.get("carry", {}) as Dictionary).get("loop", {}) as Dictionary)).get("gold", -1)) == 275, "Leonard's carry (loop gold 275) passed through level 53 and the preview untouched")
	records.append({"case": "campaign_chain", "fixture": "victory_boss on the level-52 dev first-control seam, level 3 / gold 275; level-53 escape win by gate cell + wait", "saved": saved})
	finish(map_scene)


func play_story(scene: Node, end_label: String) -> Node:
	var coordinator = scene.opening_coordinator
	check(coordinator != null and coordinator.active and coordinator.story_mode, "story scene %s runs through the coordinator" % scene.scenario_path)
	if coordinator == null:
		return null
	fast(coordinator)
	var previous_id: int = scene.get_instance_id()
	var previous_path := str(scene.scenario_path)
	var frames := 0
	var finished := false
	# The scene end hands off and reloads at once, freeing this scene and its
	# coordinator; stop polling as soon as either happens.
	while is_instance_valid(coordinator) and frames < 6000:
		if coordinator.story_finished:
			finished = true
			break
		if str(coordinator.summary().get("current_event_kind", "")) == "dialogue_message_id":
			await key(KEY_SPACE)
			continue
		await process_frame
		frames += 1
	if not is_instance_valid(coordinator):
		finished = true
	check(finished, "story scene %s reached its end" % previous_path)
	if is_instance_valid(scene):
		await shot(scene, end_label)
	var next = await wait_reload(previous_id)
	if next == null:
		failures.append("scene did not reload after %s" % previous_path)
	return next


func fast(coordinator: Node) -> void:
	coordinator.walk_pixels_per_second = 3200.0
	coordinator.delay_token_seconds = 0.002
	coordinator.default_step_seconds = 0.01
	if "move_pixels_per_frame_hz" in coordinator:
		coordinator.move_pixels_per_frame_hz = 6000.0


func wait_reload(previous_id: int) -> Node:
	## reload_current_scene frees the old scene asynchronously; compare instance ids
	## instead of holding the (soon invalid) node reference.
	var waited := 0
	while waited < 240:
		var current = current_scene
		if current != null and is_instance_valid(current) and current.get_instance_id() != previous_id:
			await process_frame
			await process_frame
			return current
		await process_frame
		waited += 1
	return null


func click_button(button: Button) -> void:
	var center: Vector2 = button.get_global_rect().get_center()
	root.notify_mouse_entered()
	var motion := InputEventMouseMotion.new()
	motion.position = center
	root.push_input(motion, true)
	await process_frame
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = center
	root.push_input(press, true)
	await process_frame
	var release := press.duplicate()
	release.pressed = false
	root.push_input(release, true)
	await process_frame
	await process_frame


func key(code: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.pressed = true
	Input.parse_input_event(event)
	await create_timer(0.03).timeout
	event = event.duplicate()
	event.pressed = false
	Input.parse_input_event(event)
	await process_frame
	await process_frame


func finish(scene: Node) -> void:
	var manifest := FileAccess.open(OUT + "manifest.json", FileAccess.WRITE)
	manifest.store_string(JSON.stringify({"schema": "hsl_campaign_chain_review.v1", "records": records, "failures": failures}, "  "))
	manifest.close()
	if scene != null:
		if current_scene == scene:
			current_scene = null
		scene.queue_free()
	await process_frame
	await process_frame
	await create_timer(0.2).timeout
	if failures.is_empty():
		print("CAMPAIGN_CHAIN_REVIEW_PASS shots=%d output=%s" % [records.size(), OUT])
		quit(0)
	else:
		print("CAMPAIGN_CHAIN_REVIEW_FAIL count=%d" % failures.size())
		quit(1)


func shot(scene: Node, label: String) -> void:
	if not label.ends_with("-end"):
		await create_timer(0.12).timeout
	if not is_instance_valid(scene):
		records.append({"capture": label, "scenario": "", "interaction": "scene_already_reloaded"})
	else:
		records.append({"capture": label, "scenario": str(scene.scenario_path), "interaction": scene.interaction_state})
	RenderingServer.force_draw(false)
	check(root.get_texture().get_image().save_png(OUT + label + ".png") == OK, "capture " + label)


func check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)
		push_error(label)
