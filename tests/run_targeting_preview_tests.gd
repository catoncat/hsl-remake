extends SceneTree
## Grid-cursor targeting feedback (BattlePresentation.preview_target／preview_hovered_unit,
## BattleSceneOverlays.refresh_skill_footprint): in every cell-choosing action — move,
## weapon attack, magic, special — the cursor resting on any living unit shows that unit's
## identity strip, whatever its side or legality (own member, other player member, enemy,
## friendly AI, out-of-range enemy, a full-HP ally under a heal); legality only decides the
## hit／effect line. A skill's real effect footprint is drawn at the cursor (毒魔箭: the
## range1Cell cross around the chosen cell). Levels 3 (琥／緹娜／雷歐納德) and 51 (friendly AI).
const TestSuite = preload("res://tests/support/TestSuite.gd")
const Loop = preload("res://game/battle/scene/BattlePlayLoop.gd")
const CampaignProgress = preload("res://game/battle/runtime/CampaignProgress.gd")
const Interaction = preload("res://game/sim/Interaction.gd")
const POISON_ARROW := "special:magicMIND:magicCode03"
const HEALING_WATER := "magic:magicWATER:magicCode06"
var checks := 0
var failures: Array[String] = []
## "action × unit kind → strip shown" rows, printed as the matrix line.
var matrix: Array[String] = []


func _initialize() -> void:
	call_deferred("run")


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		push_error(message)


func run() -> void:
	OS.set_environment("HSL_RNG_SEED", "1")
	CampaignProgress.reset_campaign()
	CampaignProgress.pending = {}
	await _test_level3_matrix()
	await _test_friendly_ai_rows()
	print("TARGETING_PANEL_MATRIX %s" % " ".join(matrix))
	await TestSuite.settle_wall_clock(self, 0.2)
	if failures.is_empty():
		print("TARGETING_PREVIEW_TESTS_PASS checks=%d" % checks)
		quit(0)
	else:
		print("TARGETING_PREVIEW_TESTS_FAIL count=%d" % failures.size())
		quit(1)


func _start(path: String) -> Node:
	var scene = load("res://game/battle/scene/BattleSceneRuntime.tscn").instantiate()
	scene.scenario_path = path
	scene.startup_mode = "dev_first_control"
	root.add_child(scene)
	await process_frame
	await process_frame
	scene.start_dev_first_control_harness()
	await process_frame
	scene.set_process(false)
	return scene


## Hands the turn to `id` (a fresh action of that member) and opens its action menu.
func _give_turn(scene: Node, id: String) -> void:
	var next: Dictionary = scene.play_loop.duplicate(true)
	Loop._clear_extra_action(next)
	next["turn_queue"] = Loop.CoreTurnQueue.rebuild(Loop._queue_actors(next))
	for index in range(next["turn_queue"]["slots"].size()):
		if next["turn_queue"]["slots"][index]["id"] == id: next["turn_queue"]["index"] = index; break
	scene.apply_loop(Loop._return_to_player(next, id), "test")
	scene.resume_turn_presentation()


func _enter(scene: Node, action: String, skill_id: String = "") -> bool:
	scene.cancel_current_interaction()
	scene.menus.choose_command("magic" if action == "magic" else action)
	if skill_id != "":
		scene.menus._choose_magic(skill_id)
	var expected := Interaction.MOVE_SELECT if action == "move" else Interaction.ATTACK_SELECT
	return scene.interaction_state == expected


## Rests the pointer on `cell` (camera centred on it first) and runs one frame.
func _hover(scene: Node, cell: Vector2i) -> void:
	scene.center_camera_on_grid(cell)
	scene.scene_input.handle_pointer_motion(scene.grid_cell_center_to_logical_position(cell))
	scene._process(0.0)


func _strip_shows(scene: Node, id: String) -> bool:
	var vitals = scene.get_node("BattlePresentation").target_vitals
	var unit := Loop.unit(scene.play_loop, id)
	if not vitals.visible: return false
	var hp_text := "%d / %d" % [int(unit["hp"]), int(unit["max_hp"])] if Loop.unit_known(scene.play_loop, id) else "???"
	return vitals.values["hp"].text == hp_text


func _row(scene: Node, action: String, kind: String, id: String) -> void:
	_hover(scene, Loop.unit(scene.play_loop, id)["coord"])
	var shown := _strip_shows(scene, id)
	matrix.append("%s×%s=%s" % [action, kind, "strip" if shown else "none"])
	check(shown, "%s: the cursor on %s (%s) shows its identity strip" % [action, id, kind])


func _test_level3_matrix() -> void:
	var scene = await _start("res://content/battles/battle_003.json")
	var far_foe := "actor028_9"
	# 琥: move, weapon (bow) and 毒魔箭 (20 ST); 雷歐納德 unhurt for the heal rows.
	Loop._unit(scene.play_loop, "hu")["stamina"] = 20
	var leonard_unit: Dictionary = Loop._unit(scene.play_loop, "leonard")
	leonard_unit["hp"] = int(leonard_unit["max_hp"])
	_give_turn(scene, "hu")
	for action in ["move", "attack", "special"]:
		check(_enter(scene, action, POISON_ARROW if action == "special" else ""), "琥 enters %s targeting" % action)
		_row(scene, action, "self", "hu")
		_row(scene, action, "player_member", "tina")
		_row(scene, action, "adjacent_enemy", "actor028_2")
		_row(scene, action, "out_of_range_enemy", far_foe)
		if action != "move":
			_hover(scene, Loop.unit(scene.play_loop, "tina")["coord"])
			check(not scene.get_node("BattlePresentation").combat_label.visible, "%s offers no hit line on an own member" % action)
	# 毒魔箭's real footprint: the range1Cell cross around the chosen cell, only in range.
	_enter(scene, "special", POISON_ARROW)
	var hu: Dictionary = Loop.unit(scene.play_loop, "hu")
	# (4,11): open ground whose whole cross is empty. hu+(0,-2) = (4,7) is a 0x4000 wall that
	# the original's cast range (0x40f5d0, mode −1) never reaches — hovering it draws nothing.
	var center: Vector2i = hu["coord"] + Vector2i(0, 2)
	_hover(scene, hu["coord"] + Vector2i(0, -2))
	check(_effect_cells(scene).is_empty(), "毒魔箭 draws no footprint on the wall two cells north (cast range stops at 0x4000)")
	# (4,10) sits between 緹娜, 雷歐納德 and 琥: the 0x4100e0 mode 2 flood leaves the P cells out.
	_hover(scene, hu["coord"] + Vector2i(0, 1))
	check(_effect_cells(scene) == [hu["coord"] + Vector2i(0, 1), hu["coord"] + Vector2i(0, 2)], "毒魔箭 beside three members draws only the two open cells (drawn %s)" % [_effect_cells(scene)])
	_hover(scene, center)
	var drawn := _effect_cells(scene)
	var expected := [center, center + Vector2i.UP, center + Vector2i.DOWN, center + Vector2i.LEFT, center + Vector2i.RIGHT]
	check(drawn.size() == 5 and expected.all(func(cell): return drawn.has(cell)), "毒魔箭 draws the five-cell cross around the chosen cell (drawn %s)" % [drawn])
	check(drawn == _sorted(scene.overlays.footprint_cells) and scene.overlays.footprint_cells.size() == Loop.Combat.skill_cast_footprint(scene.play_loop, center).size(), "the drawn cells are the settlement footprint")
	check(drawn == _sorted(Loop.Combat.skill_cast_footprint(scene.play_loop, center)) and not Loop.Combat._skill_context(scene.play_loop).get("range_terrain", {}).is_empty(), "the drawn cells are exactly skill_cast_footprint, and the settled context carries the same terrain")
	_check_footprint_style(scene)
	_hover(scene, hu["coord"] + Vector2i(2, 2))
	check(_effect_cells(scene).is_empty(), "a cell outside 毒魔箭's thrust range draws no footprint")
	# 緹娜: 治癒之水 on a full-HP member still shows the member (the cast itself has no effect).
	_give_turn(scene, "tina")
	check(_enter(scene, "magic", HEALING_WATER), "緹娜 enters 治癒之水 targeting")
	var leonard: Dictionary = Loop.unit(scene.play_loop, "leonard")
	check(int(leonard["hp"]) == int(leonard["max_hp"]), "雷歐納德 is at full HP")
	_row(scene, "magic", "full_hp_heal_target", "leonard")
	check(not scene.get_node("BattlePresentation").combat_label.visible, "治癒之水 offers no effect line on a full-HP member")
	_row(scene, "magic", "enemy_under_heal", "actor028_2")
	_row(scene, "magic", "out_of_range_enemy", far_foe)
	_hover(scene, Loop.unit(scene.play_loop, "leonard")["coord"])
	check(_effect_cells(scene).size() == Loop.Combat.skill_cast_footprint(scene.play_loop, Loop.unit(scene.play_loop, "leonard")["coord"]).size(), "the heal's footprint is drawn at an in-range cell")
	scene.queue_free()
	await process_frame


func _test_friendly_ai_rows() -> void:
	var scene = await _start("res://content/battles/battle_051.json")
	var friend := ""
	for unit in scene.play_loop["units"]:
		if unit.get("battle_actor_role") == "friendly_ai" and int(unit["hp"]) > 0: friend = str(unit["id"]); break
	check(friend != "", "level 51 fields a friendly AI unit")
	Loop._unit(scene.play_loop, "leonard")["stamina"] = 20
	scene.apply_loop(scene.play_loop, "test")
	for action in ["move", "attack", "special"]:
		var skill := ""
		if action == "special":
			var options: Array = Loop.special_options(scene.play_loop, "leonard")
			skill = str(options[0]["id"]) if not options.is_empty() else ""
		check(_enter(scene, action, skill), "雷歐納德 enters %s targeting" % action)
		_row(scene, action, "friendly_ai", friend)
	scene.queue_free()
	await process_frame


## The footprint is drawn in its own style, not as another layer of the cast-range palette:
## an outlined magenta cell above every range cell, whose colour never pulses to a palette ramp.
func _check_footprint_style(scene: Node) -> void:
	var overlays = scene.overlays
	var last_range := -1
	var first_footprint := -1
	var styled := true
	for index in range(scene.move_overlay.get_child_count()):
		var child: Node = scene.move_overlay.get_child(index)
		if str(child.name).begins_with("AttackCell"): last_range = index
		elif str(child.name).begins_with("EffectCell"):
			if first_footprint < 0: first_footprint = index
			var edge: Line2D = child.get_node_or_null("Edge")
			var fill: Polygon2D = child.get_node_or_null("Fill")
			styled = styled and child.has_meta("marked") and not child.has_meta("palette") and edge != null and edge.closed and edge.width >= 2.0 and edge.default_color == overlays.FOOTPRINT_EDGE and fill != null and fill.color == overlays.FOOTPRINT_FILL
	check(last_range >= 0 and first_footprint > last_range, "the footprint cells draw above the cast-range cells")
	check(styled, "every footprint cell is an outlined magenta cell, not a cast-range palette cell")
	var ramps: Dictionary = scene.move_overlay._palette_ramps
	check(not ramps.values().any(func(ramp): return ramp.any(func(color): return color.is_equal_approx(overlays.FOOTPRINT_FILL))), "the footprint fill is no range palette colour")
	scene.move_overlay._process(1.0)
	var edge_after: Line2D = scene.move_overlay.get_node_or_null(NodePath("EffectCell00/Edge"))
	check(edge_after != null and edge_after.default_color == overlays.FOOTPRINT_EDGE, "the range pulse leaves the footprint style alone")


func _effect_cells(scene: Node) -> Array:
	var cells: Array = []
	for child in scene.move_overlay.get_children():
		if str(child.name).begins_with("EffectCell"):
			cells.append(scene.map_config.world_to_grid(child.position + Vector2(1, 1)))
	return _sorted(cells)


static func _sorted(cells: Array) -> Array:
	var copy := cells.duplicate()
	copy.sort_custom(func(a, b): return a.y < b.y or (a.y == b.y and a.x < b.x))
	return copy
