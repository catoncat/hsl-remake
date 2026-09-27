extends Control
## The win／fail conditions board of actShowWinFailStatus (obj_WinFailBoard, OBJ-ALL object 4,
## process defProcWinFailBoard 0x413a80): WINDOW60 centred on the screen, 勝利條件 over the armed
## win／event labels and 失敗條件 over the fail labels, dissolving in, waiting for a key or
## click, dissolving out. The script waits on it (0x407320 → case 0x1f of 0x450840), so the
## opening coordinator holds its timeline while `busy()`. It waits for input only, with no
## timeout, as state 2 does (UI6, user 2026-09-25 照原版); the one exception is the automation
## seam `automation_hold_ticks` for `--script` drivers. The system scroll's 任務說明 shows the
## same board. The "dissolve" is the display list's cross-fade: the rows are drawn into the
## WINDOW60 surface and the object drawn with mode 0x20000000 (0x413bfd, 0x414179) at level
## +0x28 0→16 (state 1, a level every 2 ticks) and 16→−1 (state 3); 0x46b691 kind 4
## (0x4699fd) blends every pixel src × level/16 + dst × (16 − level)/16 through the level
## tables at 0x4bfbf0, with no pixel pattern; level 16 draws mode 0 (0x414144). The remake
## composites board and rows in one CanvasGroup and fades it by level/16.
## provenance:
##   rules: static-derived docs/evidence_packets/runtime_observations/camera_panel_motion/README.md
##     (cross-fade kind 4 0x4699fd at level/16 over the composited board)
##   rules: runtime-measured docs/evidence_packets/runtime_observations/menus_ui/README.md
##     (the system scroll's 任務說明 shows this board over the scroll)
##   rules: remake-invented
##     (under a `--script` SceneTree (tests, autoplay, captures) the opening board ends itself after HOLD_TICKS, the
##     game has no timeout; leaving 任務說明 mid-dissolve fades out from there)
##   layout: resource-derived content/generated/hsl/chapter01/battle038_seed.json
##   layout: static-derived docs/evidence_packets/runtime_observations/camera_panel_motion/README.md
##   layout: runtime-measured docs/evidence_packets/runtime_observations/camera_panel_motion/README.md
##     (board box (136,108)–(502,370) at 32.6 s)
##   layout: remake-invented (system font centred on the 24 px glyph rows)
##   strings: resource-derived content/imported/hsl/chapter01/source_texts/RESOURCE.TXT
##   timing: static-derived docs/evidence_packets/runtime_observations/camera_panel_motion/README.md
##   timing: runtime-measured docs/evidence_packets/runtime_observations/camera_panel_motion/README.md
##     (32.01–32.55 s in, 33.16–33.73 s out)
##   timing: static-derived docs/evidence_packets/runtime_observations/original_tick_rate/README.md
##   audio: runtime-measured docs/evidence_packets/runtime_observations/camera_panel_motion/README.md
##     (no onset during the three boards)

const OriginalTick = preload("res://game/common/OriginalTick.gd")
const BattleUISkin = preload("res://game/common/BattleUISkin.gd")
const RuleAdapter = preload("res://game/sim/BattleScenarioRuleAdapter.gd")

const BOARD_SIZE := Vector2(368, 264)
const LEVEL_TICKS := 2
const LEVELS := 16
const FADE_IN_TICKS := LEVELS * LEVEL_TICKS
const FADE_OUT_TICKS := (LEVELS + 1) * LEVEL_TICKS
## The automation seam's hold: the recording's longest board (402.25–405.1 s, 2.85 s in all)
## minus both fades. Only `--script` drivers get it; the game waits for input only.
const HOLD_TICKS := 112
const ROW_X := 20.0
const ROW_WIDTH := 336.0
const TITLE_Y := 17.0
const WIN_ROWS_Y := 51.0
const FAIL_TITLE_Y := 145.0
const FAIL_ROWS_Y := 179.0
const ROW_STEP := 28.0
const ROWS_PER_KIND := 3
## RESOURCE items 120 and 123.
const WIN_TITLE := "勝利條件"
const FAIL_TITLE := "失敗條件"

## "idle" | "in" | "hold" | "out"
var stage := "idle"
var level := 0
var _stage_ticks := 0
var _clock := 0.0
var shown_count := 0
## Ticks the board waits before dissolving out by itself; 0 waits for input only (0x413a80).
var hold_ticks := 0
## The row Labels of the board last shown, top to bottom (title, rows, title, rows).
var row_labels: Array[Label] = []
var last_rows := {"win": [], "fail": []}
var _rows_root: Control
## Board and rows composited first, then faded as one (the rows live in the WINDOW60 surface).
var _blend: CanvasGroup


func _ready() -> void:
	name = "WinFailBoard"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	position = ((Vector2(640, 480) - BOARD_SIZE) * 0.5).floor()
	size = BOARD_SIZE
	_blend = CanvasGroup.new()
	_blend.name = "Blend"
	add_child(_blend)
	BattleUISkin.board(_blend, "WINDOW60", Vector2.ZERO)
	_rows_root = Control.new()
	_rows_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rows_root.size = BOARD_SIZE
	_blend.add_child(_rows_root)
	visible = false


## The hold the opening gives its board: HOLD_TICKS when the process runs a `--script`
## SceneTree (test suites, autoplay, capture scripts), so bots never wait on a key; 0 — wait
## for input only — in the game, whose main loop is the plain SceneTree.
static func automation_hold_ticks() -> int:
	var tree := Engine.get_main_loop()
	return HOLD_TICKS if tree != null and tree.get_script() != null else 0


func busy() -> bool:
	return stage != "idle"


## Opens the board with the labels of `rows` ({"win": [String], "fail": [String]}).
func show_rows(rows: Dictionary) -> void:
	last_rows = rows.duplicate(true)
	for child in _rows_root.get_children():
		child.queue_free()
	row_labels.clear()
	_row(WIN_TITLE, TITLE_Y, BattleUISkin.TEXT_GREEN)
	var y := WIN_ROWS_Y
	for text in (rows.get("win", []) as Array).slice(0, ROWS_PER_KIND):
		_row(str(text), y, BattleUISkin.TEXT_WHITE)
		y += ROW_STEP
	_row(FAIL_TITLE, FAIL_TITLE_Y, BattleUISkin.TEXT_GREEN)
	y = FAIL_ROWS_Y
	for text in (rows.get("fail", []) as Array).slice(0, ROWS_PER_KIND):
		_row(str(text), y, BattleUISkin.TEXT_WHITE)
		y += ROW_STEP
	stage = "in"
	level = 0
	_stage_ticks = 0
	_clock = 0.0
	shown_count += 1
	_blend.self_modulate.a = 0.0
	visible = true


func _row(text: String, y: float, color: Color) -> void:
	var row := BattleUISkin.text(_rows_root, Vector2(ROW_X, y), color, BattleUISkin.FONT_BODY, Vector2(ROW_WIDTH, 24))
	row.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	row.text = text
	row_labels.append(row)


## A key or click while the board waits starts the dissolve out (state 2 → 3); input during
## the dissolve in or out is ignored, as in the original. Returns whether it was taken.
func dismiss() -> bool:
	if stage != "hold":
		return false
	_enter("out")
	return true


## Starts the dissolve out from the level reached, whether the board is still dissolving in
## or waiting (the scroll's 任務說明 closed by Esc／click). Returns whether it was taken.
func fade_out() -> bool:
	if stage not in ["in", "hold"]:
		return false
	_enter("out")
	_stage_ticks = (LEVELS - level) * LEVEL_TICKS
	return true


## Hides the board at once (the timeline was advanced past it, or the scene ends).
func finish() -> void:
	stage = "idle"
	visible = false


func _enter(next: String) -> void:
	stage = next
	_stage_ticks = 0


func _process(delta: float) -> void:
	advance(delta)


func advance(delta: float) -> void:
	if stage == "idle":
		return
	_clock += maxf(delta, 0.0)
	while _clock >= OriginalTick.TICK_SECONDS and stage != "idle":
		_clock -= OriginalTick.TICK_SECONDS
		_stage_ticks += 1
		match stage:
			"in":
				level = mini(LEVELS, _stage_ticks / LEVEL_TICKS)
				if _stage_ticks >= FADE_IN_TICKS:
					_enter("hold")
			"hold":
				if hold_ticks > 0 and _stage_ticks >= hold_ticks:
					_enter("out")
			"out":
				level = LEVELS - _stage_ticks / LEVEL_TICKS
				if _stage_ticks >= FADE_OUT_TICKS:
					finish()
	_blend.self_modulate.a = clampf(float(level) / float(LEVELS), 0.0, 1.0)


## The board's rows: the win (and labelled event) and fail labels of the statuses armed in
## the loop, together with `token_codes` ({"win": [code], "fail": [...], "event": [...]}) that
## the opening script inserted before its actShowWinFailStatus.
static func rows_for(loop: Dictionary, token_codes: Dictionary, label_of: Callable) -> Dictionary:
	var view := loop.duplicate(false)
	for kind in ["win", "fail", "event"]:
		var armed: Array = (loop.get("%s_statuses" % kind, []) as Array).duplicate()
		for code in token_codes.get(kind, []):
			if str(code).is_valid_int() and armed.find(int(str(code))) == -1:
				armed.append(int(str(code)))
		view["%s_statuses" % kind] = armed
	var board: Dictionary = RuleAdapter.objective_board(view)
	var rows := {"win": [], "fail": []}
	for entry in board.get("win", []) + board.get("event", []):
		var label: String = label_of.call(entry)
		if label != "":
			rows["win"].append(label)
	for entry in board.get("fail", []):
		var label: String = label_of.call(entry)
		if label != "":
			rows["fail"].append(label)
	return rows
