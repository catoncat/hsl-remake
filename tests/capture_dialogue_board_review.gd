extends SceneTree
## Frames of the dialogue board for human review against the 2026-09-24 original recording
## (WINFAIL051 message 369, 398.6–400.6 s) and the static reading in
## docs/evidence_packets/static_reverse/original_dialogue_board.md: 369 mid-fade with its rows
## wiping in, its first page still (name row + three body rows, ▼), mid-scroll, its last page
## (four body rows, □); a script-faced actShapeMessage line (level 63's FACE0054 spy) on the
## top slot; a defNoOne narration line (STORY001 712) on the centred board. The board's own
## clocks are stepped by hand on a patterned backdrop, so each frame is a fixed tick. Writes
## ignored/r7-dialogue-board-review/. Needs a rendered window.
##
##   tools/godot.sh --script res://tests/capture_dialogue_board_review.gd
const BattleDialogue = preload("res://game/battle/scene/BattleDialogue.gd")
const OriginalTick = preload("res://game/common/OriginalTick.gd")
const OUT := "res://ignored/r7-dialogue-board-review/"
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Dialogue board review needs a rendered window")
		quit(2)
		return
	root.title = "HSL Dialogue Board"
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
	var board = BattleDialogue.new()
	stage.add_child(board)
	await process_frame
	board.set_process(false)
	var messages: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://content/imported/hsl/chapter01/message_text_evidence.json"))["messages"]
	board.configure_portraits("res://content/imported/hsl/chapter01/battle001/portraits/manifest.json")
	board.show_message("369", "雷歐納德", str(messages["369"]), "001")
	_step(board, 10)
	await shot("01-369-fade-and-wipe-tick10")
	_step(board, 40)
	# The markers blink 10 ticks on / 10 off (0x4146e0); step into an on phase before each shot.
	_step_until_visible(board, board.continue_label)
	await shot("02-369-first-page-marker")
	_check(board.window_rows().size() == 4 and board.continue_label.visible, "369's first page is still, with ▼")
	board.advance_page()
	_step(board, 15)
	await shot("03-369-scrolling-tick15")
	_step(board, 30)
	_step_until_visible(board, board.end_marker)
	await shot("04-369-last-page-square")
	_check(board.end_marker.visible and board.window_rows()[3] == "!!", "369's last page ends on !! with □")
	board.clear_message()
	# The closed board leaves a dissolving copy on the scene clock; let it go before the next shot.
	await create_timer(BattleDialogue.DISSOLVE_OUT_SECONDS + 0.1).timeout
	board.configure_portraits("res://content/imported/hsl/chapter01/battle063/portraits/manifest.json")
	var hall: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://content/imported/hsl/chapter01/battle063/message_text_evidence.json"))["messages"]
	board.show_face_message("997", "???", str(hall["997"]), "SHAPE\\FACE0054.SHP")
	_step(board, 60)
	await shot("05-shape-message-top-slot")
	_check(board.position.y == BattleDialogue.PANEL_TOP_TOP_SLOT, "the actShapeMessage line is on the top slot")
	board.clear_message()
	# The closed board leaves a dissolving copy on the scene clock; let it go before the next shot.
	await create_timer(BattleDialogue.DISSOLVE_OUT_SECONDS + 0.1).timeout
	board.show_narration("712", "不好啦！")
	_step(board, 60)
	await shot("06-narration-centred")
	_check(board.position.x + BattleDialogue.BOARD_AT.x == BattleDialogue.NARRATION_BOARD_X, "the narration board is centred")
	print("DIALOGUE_BOARD_REVIEW_", "PASS" if failures.is_empty() else "FAIL", " out=", OUT)
	for failure in failures:
		push_error(failure)
	quit(0 if failures.is_empty() else 1)


## Advances the board's clocks by `ticks` original ticks, one tick a call (as the game would).
func _step_until_visible(board, marker: CanvasItem) -> void:
	for _tick in range(20):
		if marker.visible:
			return
		_step(board, 1)


func _step(board: Control, ticks: int) -> void:
	for _tick in ticks:
		board._process(OriginalTick.TICK_SECONDS)


func _check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)


func shot(label: String) -> void:
	await process_frame
	RenderingServer.force_draw(false)
	if root.get_texture().get_image().save_png(OUT + label + ".png") != OK:
		failures.append("capture " + label)
