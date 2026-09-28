extends Control
## Object 704 Event_Select_Window, the script choice board shared by the town
## (teSelectInsertEvent／tePlayerSelectInsertEvent, 0x454e20 case 0xf／0x1e) and the battle
## story (actSelectInsertEvent, opcode 79, 0x451f2b): both call
## 0x4264a0(picture, 0, rows, &result) (global.obs: BOARD02, defProcEventSelectWindow 69 →
## 0x426680). No 0x4000 flag, so the board takes the bottom slot (camera y + 320); x 144 with
## the picture drawn at x − 132 when picture ≠ 0, else centred (640 − 489) / 2.
## Each row is object 705 Event_Select_String (0x4264f0): x board + 17 (rows 5–9: board + 37 +
## width), y board + top + 28·(i mod 5) with top 17 (4 past four rows), width 472 (226 past
## five), 28 high; FONT.24 white over the 0x8430 shadow (0x412760), the hovered row redrawn in
## the 0x42c130 pulse green without shadow (0x412680); a click stores the index and plays
## ACCEPT01 (398). Neither process reads Esc or the right button.
## The board's level (+0x28) climbs 0→16 one step a tick (state 0), rows take a click only at
## level 16 with no pick yet (0x4265e2), and after a pick it falls 16→0 (state 3) before the
## index is written back through +0xac (0x42692e); the board and its rows draw at level/16.
## The host owns what a row means: `answered(pick, leave)` fires once the fade-out ends.
## provenance:
##   layout: static-derived docs/evidence_packets/runtime_observations/original_world_town/README.md
##   layout: resource-derived content/imported/hsl/shared/panels/manifest.json
##   timing: static-derived docs/evidence_packets/runtime_observations/original_world_town/README.md

const BattleUISkin = preload("res://game/common/BattleUISkin.gd")
const OriginalTick = preload("res://game/common/OriginalTick.gd")

signal answered(pick: int, leave: bool)

const BOARD := "BOARD02"
const BOARD_Y := 320.0
const BOARD_X_FACE := 144.0
const BOARD_X_CENTRED := 75.0
const BOARD_WIDTH := 489
const FACE_DX := -132.0
const ROW_INSET := 17
const ROW_PITCH := 28
const ROWS_PER_COLUMN := 5
const HOVER_HALF := 16
const FADE_TICKS := 16
const SOUND := "res://content/imported/hsl/shared/interface_audio/confirm.wav"

var rows: Array[Label] = []
var hover := -1
var level := 0.0
var fading_out := false
var board_at := Vector2.ZERO
var _clock := 0.0
var _pick := -1
var _leave := false
var _sound_host: Node = null


## Builds the board under `parent`. `picks`: the answer behind each row (default: row i
## answers i); `leave_text` appends a last row that answers with leave = true.
static func open(parent: Node, labels: Array[String], face: Texture2D, picks: Array[int] = [], leave_text := "", node_name := "SelectWindow", sound_host: Node = null) -> Control:
	var window := new()
	window.name = node_name
	window.mouse_filter = Control.MOUSE_FILTER_IGNORE
	window.modulate.a = 0.0
	window._sound_host = sound_host
	parent.add_child(window)
	window._build(labels, face, picks, leave_text)
	return window


## The 0x42c130 colour on the 0x42c110 counter: green 255 − 2·|p| with red and blue 0, p
## stepping once a tick through −16..16.
static func pulse_colour(clock: float) -> Color:
	var period := 2 * HOVER_HALF + 1
	var step := int(OriginalTick.ticks(clock)) % period - HOVER_HALF
	return Color8(0, 255 - 2 * absi(step), 0)


func _build(labels: Array[String], face: Texture2D, picks: Array[int], leave_text: String) -> void:
	board_at = Vector2(BOARD_X_FACE if face != null else BOARD_X_CENTRED, BOARD_Y)
	BattleUISkin.board(self, BOARD, board_at)
	if face != null:
		var picture := TextureRect.new()
		picture.name = "Picture"
		picture.position = board_at + Vector2(FACE_DX, 0)
		picture.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
		BattleUISkin.show_shape(picture, face)
		add_child(picture)
	var texts := labels.duplicate()
	if leave_text != "":
		texts.append(leave_text)
	var count := mini(texts.size(), 2 * ROWS_PER_COLUMN)
	var width := BOARD_WIDTH - ROW_INSET
	if count > ROWS_PER_COLUMN:
		width = width / 2 - 10
	var top := 4 if count > 4 else ROW_INSET
	for index in range(count):
		var column_x := ROW_INSET if index < ROWS_PER_COLUMN else ROW_INSET + 20 + width
		var hit := Control.new()
		hit.name = "Choice%d" % index
		hit.position = board_at + Vector2(column_x, top + ROW_PITCH * (index % ROWS_PER_COLUMN))
		hit.size = Vector2(width, ROW_PITCH)
		hit.clip_contents = true
		hit.mouse_filter = Control.MOUSE_FILTER_STOP
		add_child(hit)
		var row := BattleUISkin.text(hit, Vector2.ZERO, BattleUISkin.TEXT_WHITE, BattleUISkin.FONT_BODY, Vector2(width, 24))
		row.text = texts[index]
		rows.append(row)
		hit.mouse_entered.connect(set_hover.bind(index))
		hit.mouse_exited.connect(set_hover.bind(-1))
		var leave := leave_text != "" and index == texts.size() - 1
		hit.gui_input.connect(_row_input.bind(picks[index] if index < picks.size() else index, leave))


## Hover row `index` (−1: none): pulse green without shadow, the others white over the shadow.
func set_hover(index: int) -> void:
	hover = index
	for row_index in range(rows.size()):
		var row := rows[row_index]
		if not is_instance_valid(row):
			continue
		row.add_theme_color_override("font_color", pulse_colour(_clock) if row_index == index else BattleUISkin.TEXT_WHITE)
		row.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0) if row_index == index else BattleUISkin.TEXT_SHADOW)


func _row_input(event: InputEvent, pick: int, leave: bool) -> void:
	if not (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
		return
	if level < FADE_TICKS or fading_out:
		return
	var sound := AudioStreamPlayer.new()
	sound.stream = load(SOUND)
	sound.finished.connect(sound.queue_free)
	(_sound_host if is_instance_valid(_sound_host) else get_parent()).add_child(sound)
	sound.play()
	fading_out = true
	_pick = pick
	_leave = leave


func _process(delta: float) -> void:
	_clock += delta
	var step := OriginalTick.ticks(delta)
	level = clampf(level + (-step if fading_out else step), 0.0, FADE_TICKS)
	modulate.a = floorf(level) / FADE_TICKS
	if fading_out and level <= 0.0:
		fading_out = false
		set_process(false)
		answered.emit(_pick, _leave)
		return
	if hover >= 0 and hover < rows.size() and is_instance_valid(rows[hover]):
		rows[hover].add_theme_color_override("font_color", pulse_colour(_clock))
