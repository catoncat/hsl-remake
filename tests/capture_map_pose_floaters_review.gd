extends SceneTree
## Manual-acceptance capture for lane R7-POSE
## (docs/evidence_packets/runtime_observations/map_pose_floaters/README.md), on the development
## fixture (first_battle.json) with the scene's own `_process` running:
##   1. cast — 帝國法師 026 casts 幻火 on the map (no m_shape lead): its use_magic pose at the
##      start, the held last frame, the play-back;
##   2. levelup — 雷歐納德 (EXP 99) kills 021: LEVEL UP with his pose and the 36-star shower;
##   3. digits — a two-digit critical damage number on the map (a layout fixture: the receipt is
##      synthetic and passed straight to the map impact, because a real critical hit shows its
##      map number under the close-up) at the first digit, the completed number, the standing
##      number — the number stands alone, no 暴擊 words (UI6, user 2026-09-25 照原版).
## Positions are moved next to each other; a rendering fixture, not a natural playthrough.
## Every snap first checks what it is meant to show — no close-up on screen (the level-up and
## digit snaps), star sprites visible, DamageDigits.digits == "57" with an empty words label,
## and the glyphs' screen rect (canvas transform applied) overlapping the viewport —
## and, with a window, waits for a freshly drawn frame; any miss prints
## MAP_POSE_FLOATERS_REVIEW_FAIL and exits 1. The cast snaps also save a 3× crop centred on the
## caster (`*-zoom.png`).
##
##   tools/godot.sh --headless --script res://tests/capture_map_pose_floaters_review.gd     # log only
##   tools/play.sh --screen 0 --script res://tests/capture_map_pose_floaters_review.gd -- <out_dir>
const Loop = preload("res://game/sim/loop/BattlePlayLoop.gd")
const LoopCombat = preload("res://game/sim/loop/BattleLoopCombat.gd")
const OriginalTick = preload("res://game/common/OriginalTick.gd")
const FIXTURE := "res://content/battles/first_battle.json"
var out_dir := ""
var rendering := false
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	rendering = DisplayServer.get_name() != "headless"
	var args := OS.get_cmdline_user_args()
	if rendering:
		out_dir = args[0] if not args.is_empty() else "res://ignored/map_pose_floaters"
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir))
		root.size = Vector2i(640, 480)
	await cast_case()
	await level_up_case()
	await digits_case()
	if not failures.is_empty():
		for failure in failures: print("MAP_POSE_FLOATERS_REVIEW_FAIL ", failure)
		quit(1)
		return
	print("MAP_POSE_FLOATERS_REVIEW_FINISHED")
	quit(0)


func fixture() -> Node:
	var scene: Node = load("res://game/battle/scene/BattleSceneRuntime.tscn").instantiate()
	scene.scenario_path = FIXTURE
	scene.startup_mode = "dev_first_control"
	root.add_child(scene)
	current_scene = scene
	await process_frame
	scene.start_dev_first_control_harness()
	scene.get_node("BattleMusic").stop()
	return scene


func cast_case() -> void:
	var scene: Node = await fixture()
	var caster := Loop._unit(scene.play_loop, "enemy026_1")
	var target := Loop._unit(scene.play_loop, "enemy023_1")
	target["coord"] = caster["coord"] + Vector2i.RIGHT
	target["hp"] = 200
	caster["mp"] = 100
	var id := "magic:magicFIRE:magicCode01"
	LoopCombat._resolve_skill(scene.play_loop, caster["id"], target["id"], id, Loop.skill_fields(scene.play_loop, id), caster["coord"], func(_n): return 0)
	scene.apply_loop(scene.play_loop, "capture")
	var actor: Node2D = scene.actor_node_for_unit(caster["id"])
	for _guard in range(600):
		if actor.is_posing(): break
		await process_frame
	await snap(scene, "cast-0-pose-start", actor, {"posing": true})
	await hold(OriginalTick.seconds(30))
	await snap(scene, "cast-1-held", actor, {"posing": true})
	await hold(OriginalTick.seconds(42))
	await snap(scene, "cast-2-playback", actor, {"posing": true})
	scene.queue_free()
	await process_frame


func level_up_case() -> void:
	var scene: Node = await fixture()
	var player := Loop._unit(scene.play_loop, "leonard")
	var enemy := Loop._unit(scene.play_loop, "enemy021_1")
	player["exp"] = 99
	enemy["coord"] = player["coord"] + Vector2i.UP
	enemy["hp"] = 1
	enemy["inventory"] = [0, 0, 0, 0, 0, 0, 0, 0]
	scene.apply_loop(Loop.select_player_unit(scene.play_loop, "leonard"), "capture")
	scene.interaction_state = "action_menu"
	scene.menus.choose_command("attack")
	scene.apply_loop(Loop.attack_target(scene.play_loop, "enemy021_1", func(_n): return 0), "capture")
	scene.finish_attack_attempt()
	var view: Node = scene.get_node("BattlePresentation")
	var actor: Node2D = scene.actor_node_for_unit("leonard")
	# The aftermath (and so LEVEL UP) only advances once the close-up has closed.
	for _guard in range(6000):
		if view.aftermath.dialogue_active(): view.aftermath.advance_dialogue()
		if view.aftermath.stage == "level_up" and not cutin_on_screen(view): break
		await process_frame
	if view.aftermath.stage != "level_up": failures.append("levelup: the LEVEL UP stage never started")
	await hold(OriginalTick.seconds(12))
	await snap(scene, "levelup-0-stars", actor, {"posing": true, "map": true, "stars": true})
	await hold(OriginalTick.seconds(28))
	await snap(scene, "levelup-1-stars", actor, {"posing": true, "map": true, "stars": true})
	scene.queue_free()
	await process_frame


func digits_case() -> void:
	var scene: Node = await fixture()
	var view: Node = scene.get_node("BattlePresentation")
	# The camera opens on 雷歐納德; 021 starts ten rows north, off screen — stand it next to him.
	Loop._unit(scene.play_loop, "enemy021_1")["coord"] = Loop._unit(scene.play_loop, "leonard")["coord"] + Vector2i.UP
	scene.apply_loop(scene.play_loop, "capture")
	for _guard in range(600):
		await process_frame
		if not scene.has_actor_motion(): break
	# During a real impact the combat is busy and the ring menu is hidden; this direct call is not.
	scene.interaction_state = "idle"
	scene.menus.set_action_menu_visible(false)
	var attacker := Loop.unit(scene.play_loop, "leonard")
	var defender := Loop.unit(scene.play_loop, "enemy021_1")
	var strike := {"hit": true, "critical": true, "damage": 57, "actual_damage": 57, "defender_hp_after": 9,
		"defender_id": defender["id"], "attacker_id": attacker["id"]}
	view._present_impact(strike, attacker, defender, false)
	var number: Node2D = null
	for child in view.get_children():
		if child.name.begins_with("CombatEffect") and child.get_node_or_null("DamageDigits") != null:
			number = child.get_node("DamageDigits")
	if number == null: failures.append("digits: the map impact made no DamageDigits node")
	await hold(OriginalTick.seconds(3))
	await snap(scene, "digits-0-first", number, {"map": true, "digits": "57"})
	await hold(OriginalTick.seconds(9))
	await snap(scene, "digits-1-complete", number, {"map": true, "digits": "57"})
	await hold(OriginalTick.seconds(14))
	await snap(scene, "digits-2-standing", number, {"map": true, "digits": "57"})
	scene.queue_free()
	await process_frame


func snap(scene: Node, label: String, node: Node2D, expect: Dictionary) -> void:
	var view: Node = scene.get_node("BattlePresentation")
	var detail := {"cutin_on_screen": cutin_on_screen(view), "action_menu": scene.action_menu.visible}
	if node != null and node.has_method("is_posing"):
		detail["posing"] = node.is_posing()
		detail["sprite"] = node.get_node("Sprite2D").texture.resource_path.get_file()
	elif node != null and "digits" in node:
		var shown := []
		for glyph in node.glyphs: shown.append([glyph.visible, glyph.scale.x])
		var words: Label = node.get_parent().get_node_or_null("Damage")
		var digit_rect := Rect2()
		for glyph in node.glyphs:
			if glyph.is_visible_in_tree():
				var glyph_rect: Rect2 = glyph.get_global_transform_with_canvas() * glyph.get_rect()
				digit_rect = glyph_rect if digit_rect.has_area() == false else digit_rect.merge(glyph_rect)
		var words_rect: Rect2 = words.get_global_transform_with_canvas() * Rect2(Vector2.ZERO, words.size) if words != null else Rect2()
		detail.merge({"digits": node.digits, "glyphs": shown, "flash": node.flash.visible,
			"digit_screen_rect": str(digit_rect), "digits_on_screen": on_screen(digit_rect),
			"words": words.text if words != null else "", "words_visible": words != null and words.is_visible_in_tree(),
			"words_screen_rect": str(words_rect), "words_on_screen": on_screen(words_rect)})
	detail["stars"] = visible_stars(view)
	print("MAP_POSE_FLOATERS ", label, " ", JSON.stringify(detail))
	if expect.get("posing", false) and not bool(detail.get("posing", false)): failures.append(label + ": actor not posing")
	if expect.get("map", false) and bool(detail["cutin_on_screen"]): failures.append(label + ": the close-up is on screen")
	if expect.get("stars", false) and int(detail["stars"]) <= 0: failures.append(label + ": no visible star sprite")
	if expect.has("digits"):
		if str(detail.get("digits", "")) != str(expect["digits"]): failures.append(label + ": DamageDigits.digits is not " + str(expect["digits"]))
		if str(detail.get("words", "")) != "": failures.append(label + ": the damage label carries words beside the digits (UI6: numbers only)")
		if node == null or not node.is_visible_in_tree(): failures.append(label + ": DamageDigits not visible")
		if bool(detail["action_menu"]): failures.append(label + ": the ring menu is open over the number")
		if not bool(detail.get("digits_on_screen", false)): failures.append(label + ": the digits' screen rect misses the viewport " + str(detail.get("digit_screen_rect", "")))
	if not rendering: return
	if not await fresh_frame():
		failures.append(label + ": the window drew no new frame (occluded or minimised?)")
		return
	var image := root.get_texture().get_image()
	image.save_png(out_dir.path_join(label + ".png"))
	if node != null and node.has_method("is_posing") and label.begins_with("cast"):
		# 3× crop centred on the caster's body (its node origin is the foot point).
		var centre: Vector2 = node.get_global_transform_with_canvas().origin + Vector2(0, -24)
		var size := Vector2i(image.get_width() / 3, image.get_height() / 3)
		var corner := Vector2i(clampi(int(centre.x) - size.x / 2, 0, image.get_width() - size.x), clampi(int(centre.y) - size.y / 2, 0, image.get_height() - size.y))
		var zoom := image.get_region(Rect2i(corner, size))
		zoom.resize(size.x * 3, size.y * 3, Image.INTERPOLATE_NEAREST)
		zoom.save_png(out_dir.path_join(label + "-zoom.png"))


## A screen-space rect (after the camera's canvas transform) that overlaps the viewport with area.
func on_screen(rect: Rect2) -> bool:
	return rect.has_area() and rect.intersection(root.get_visible_rect()).has_area()


## The close-up covers the map while it has a clip (its panel follows busy()).
func cutin_on_screen(view: Node) -> bool:
	return view.cutin.busy() or view.cutin.panel.is_visible_in_tree()


func visible_stars(view: Node) -> int:
	var count := 0
	for child in view.aftermath.ui.get_children():
		if child.name.begins_with("LevelUpStars"):
			for sprite in child.sprites:
				if sprite.is_visible_in_tree() and sprite.modulate.a > 0.0: count += 1
	return count


## Waits for the renderer to finish a frame drawn after this call, so the saved image is the
## current state rather than the last frame a hidden window managed to draw.
func fresh_frame() -> bool:
	var drawn := [false]
	RenderingServer.frame_post_draw.connect(func(): drawn[0] = true, CONNECT_ONE_SHOT)
	for _guard in range(120):
		await process_frame
		if drawn[0]: return true
	return false


func hold(seconds: float) -> void:
	await create_timer(seconds).timeout
