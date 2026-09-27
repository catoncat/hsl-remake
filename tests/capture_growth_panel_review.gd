extends SceneTree
## Frames of the 升級 window, its shade and the dialogue page marker for human review against
## the 2026-09-24 original recording (growth window 340–351 s, dialogue marker 307.9–309.9 s):
## the growth window over a patterned backdrop as it opens (shade level 2), at rest (only the
## four ＋), after one point (that row's －), with every point placed (no ＋, OK shown) and
## mid-close; then a two-page dialogue with its ▼ and its last page's □. Writes
## ignored/r7-growth-review/. A controlled fixture (雷歐納德 one EXP short of level 2); no
## natural playthrough. Needs a rendered window.
##
##   tools/godot.sh --script res://tests/capture_growth_panel_review.gd
const BattleFixture = preload("res://tests/support/BattleFixture.gd")
const BattlePlayLoop = preload("res://game/sim/loop/BattlePlayLoop.gd")
const BattlePanelMotion = preload("res://game/battle/scene/BattlePanelMotion.gd")
const OUT := "res://ignored/r7-growth-review/"
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Growth panel review needs a rendered window")
		quit(2)
		return
	root.title = "HSL Growth Panel"
	root.size = Vector2i(640, 480)
	DirAccess.make_dir_recursive_absolute(OUT)
	var stage := Control.new()
	stage.size = Vector2(640, 480)
	root.add_child(stage)
	for index in range(80):
		var tile := ColorRect.new()
		tile.position = Vector2((index % 10) * 64, (index / 10) * 60)
		tile.size = Vector2(64, 60)
		tile.color = Color(0.55, 0.5, 0.42) if (index + index / 10) % 2 == 0 else Color(0.35, 0.42, 0.3)
		stage.add_child(tile)
	var loop := BattleFixture.loop()
	var unit: Dictionary = BattlePlayLoop.unit_ref(loop, "leonard").duplicate(true)
	unit["exp"] = 99
	unit.merge(BattlePlayLoop.ProgressionRules.resolve_experience(unit, 1, loop["equipment_items"]), true)
	var panel = preload("res://game/battle/scene/BattleGrowthPanel.gd").new()
	stage.add_child(panel)
	await process_frame
	var motion = BattlePanelMotion.attach(panel)
	motion.set_process(false)
	panel.show_unit(unit)
	await shot("growth-01-opening")
	for tick in range(60):
		motion._tick()
	await shot("growth-02-open-only-plus")
	panel.choices["con"]["plus"].pressed.emit()
	await shot("growth-03-one-point-minus")
	for i in range(int(unit["pending_stat_points"]) - 1):
		panel.choices["con"]["plus"].pressed.emit()
	await shot("growth-04-all-placed-ok")
	panel.hide()
	for tick in range(6):
		motion._tick()
	await shot("growth-05-closing")
	motion.finish()
	panel.queue_free()
	var dialogue = preload("res://game/battle/scene/BattleDialogue.gd").new()
	stage.add_child(dialogue)
	await process_frame
	dialogue.configure_portraits("res://content/imported/hsl/chapter01/battle001/portraits/manifest.json")
	dialogue.show_message("review", "雷歐納德", "第一行\n第二行\n第三行\n第四行", "001")
	dialogue.set_process(false)
	dialogue._process(1.0)
	dialogue._reveal_clock = dialogue.page_wipe_seconds() + 0.001
	dialogue._process(0.0)
	await shot("dialogue-01-next-page-marker")
	dialogue.advance_page()
	dialogue._reveal_clock = dialogue.page_wipe_seconds() + 0.001
	dialogue._process(0.0)
	await shot("dialogue-02-last-page-square")
	print("GROWTH_PANEL_REVIEW_", "PASS" if failures.is_empty() else "FAIL", " out=", OUT)
	for failure in failures:
		push_error(failure)
	quit(0 if failures.is_empty() else 1)


func shot(label: String) -> void:
	await process_frame
	RenderingServer.force_draw(false)
	if root.get_texture().get_image().save_png(OUT + label + ".png") != OK:
		failures.append("capture " + label)
