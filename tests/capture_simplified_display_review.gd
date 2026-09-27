extends "res://tests/capture_ui_class_review.gd"
## Windowed before／after shots for the simplified display seam (lane R6-L9b): the status page,
## the 升級 window, both system scrolls, the title and a story dialogue, once as the player sees
## them (simplified, the default) and once with the seam removed (`-- traditional`, the
## pre-seam display). Reuses capture_ui_class_review's routes; shots go to OUT_DIR (ignored/).
##   tools/godot.sh --script res://tests/capture_simplified_display_review.gd [-- traditional]
const OUT_DIR := "res://ignored/simplified-display-review/"
var mode := "simplified/"


func run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("simplified display review requires a rendered window")
		quit(2)
		return
	print("SIMPLIFIED_DISPLAY_REVIEW_SCREEN screen=%d of=%d size=%s window=%s" % [DisplayServer.window_get_current_screen(), DisplayServer.get_screen_count(), DisplayServer.screen_get_size(DisplayServer.window_get_current_screen()), DisplayServer.window_get_size()])
	root.title = "HSL Simplified Display Review"
	root.size = Vector2i(640, 480)
	create_timer(120.0).timeout.connect(func(): push_error("simplified display review timed out"); quit(2))
	if OS.get_cmdline_user_args().has("traditional"):
		mode = "traditional/"
		var seam = root.get_node("SimplifiedDisplay")
		TranslationServer.remove_translation(seam.translation)
		TranslationServer.add_translation(Translation.new())  # keeps _exit_tree's removal harmless
	DirAccess.make_dir_recursive_absolute(OUT_DIR + mode)
	await status_page()
	await growth_window()
	await system_menus()
	await title_cursor()
	await dialogue_wrap()
	print("SIMPLIFIED_DISPLAY_REVIEW_SHOTS ", mode, " ", shots.size())
	quit(0)


func shot(name: String) -> void:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUT_DIR + mode + name + ".png")
	shots.append(name)


func growth_window() -> void:
	var loop := BattleFixture.loop()
	var unit: Dictionary = Loop._unit(loop, "leonard").duplicate(true)
	unit["pending_stat_points"] = 5
	var panel = preload("res://game/battle/scene/BattleGrowthPanel.gd").new()
	root.add_child(panel)
	await process_frame
	panel.show_unit(unit, loop.get("skill_book", {}))
	await shot("growth_window")
	panel.queue_free()
	await process_frame
