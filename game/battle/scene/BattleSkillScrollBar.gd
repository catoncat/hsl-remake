extends TextureRect
## The skill list's 0x446060 scroll bar (objects 150–153), shared by the action ring's skill
## page (BattleMagicPanel) and the status page's 魔法／特殊技 pages (BattleStatusPanel): every
## WINDOW20 0x43add0 builds gets one from 0x438330, at WINDOW20 + (200,0). WIN02BAR trough
## 24×264 (its red arrows are baked in), BAR_UP／BAR_DOWN buttons at (5,5)／(5,243), BAR_BLK1
## thumb 14 px wide clipped to its height with the BAR_BLK2 foot on its last 2 px (150's draw
## pass). Track y 22–242 of the bar (+0x6c = 16+6, +0x74 = 264−22). 0x445d70: height
## ⌊⌊9·65536/n⌋·220/65536⌋, top 22 + ⌊220·pos/n⌋, pos in [0, n−9]. 0x445860: n ≤ 9 hides
## all four objects and ignores the keys. The owner moves its rows on `scrolled`.
## The 獲得物品 list (0x414c00 → 0x446060(win, 760, 151, 152, 153, width−24, …, 5 rows)) hangs the
## same arrows and thumb on template 760 VScroll_Bar06 WIN06BAR (24×220): `trough`／`rows` pick
## it, the down arrow and the track end follow the trough height (h−21, h−22).
## provenance:
##   layout: resource-derived content/imported/hsl/shared/panels/manifest.json
##   layout: static-derived docs/evidence_packets/runtime_observations/menus_ui/README.md#5
##   timing: static-derived docs/evidence_packets/runtime_observations/menus_ui/README.md#5
signal scrolled(pos: int)
const BattleUISkin = preload("res://game/common/BattleUISkin.gd")
const BAR_DX := 200
const VISIBLE_ROWS := 9
const ARROW_UP_AT := Vector2(5, 5)
const ARROW_DOWN_AT := Vector2(5, 243)
const ARROW_DOWN_FROM_FOOT := 264 - 243
const THUMB_X := 5
const THUMB_WIDTH := 14
const THUMB_FOOT := 2
const TRACK_TOP := 22
const TRACK_LENGTH := 220
const THUMB_SCALE := 65536
## 0x445cd0: a held arrow is drawn engFLASH with colour 0x4208, each pixel averaged with
## (66,65,66); it steps on release only if the mouse never left it (no auto-repeat).
const ARROW_HELD_SHADER := "shader_type canvas_item;\nvoid fragment() { COLOR.rgb = (COLOR.rgb + vec3(66.0, 65.0, 66.0) / 255.0) * 0.5; }"
const NO_DRAG := -1
var count := 0
var pos := 0
var visible_rows := VISIBLE_ROWS
var track_length := TRACK_LENGTH
var thumb: Control
var _thumb_foot: TextureRect
var _held_arrow: TextureRect
var _drag_grab := NO_DRAG


## `list_at`: the WINDOW20 board's position in the parent.
## `trough`／`rows`／`bar_dx`: the 獲得物品 list passes WIN06BAR, 5 and 351 (WINDOW90 width − 24).
func _init(list_at: Vector2 = Vector2.ZERO, trough: String = "WIN02BAR", rows: int = VISIBLE_ROWS, bar_dx: int = BAR_DX) -> void:
	name = "ScrollBar"
	texture = load(BattleUISkin.ROOT + trough + ".SHP.png")
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	position = list_at + Vector2(bar_dx, 0)
	visible_rows = rows
	var height := texture.get_height()
	track_length = height - 2 * TRACK_TOP
	mouse_filter = Control.MOUSE_FILTER_STOP
	gui_input.connect(_trough_input)
	thumb = Control.new()
	thumb.clip_contents = true
	thumb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(thumb)
	BattleUISkin.board(thumb, "BAR_BLK1", Vector2.ZERO)
	_thumb_foot = BattleUISkin.asset(thumb, "BAR_BLK2", Vector2.ZERO)
	var held := ShaderMaterial.new()
	held.shader = Shader.new()
	held.shader.code = ARROW_HELD_SHADER
	for step in [-1, 1]:
		var arrow := BattleUISkin.asset(self, "BAR_UP" if step < 0 else "BAR_DOWN", ARROW_UP_AT if step < 0 else Vector2(ARROW_DOWN_AT.x, height - ARROW_DOWN_FROM_FOOT))
		arrow.mouse_filter = Control.MOUSE_FILTER_STOP
		arrow.gui_input.connect(_arrow_input.bind(arrow, step, held))
	hide()


## A fresh list of `rows` rows, at row 0 (every opening: 0x43add0 +0xa0 = 2, then 0x438160
## zeroes *0x4c1cd4 on its first tick).
func reset(rows: int) -> void:
	count = rows
	_release_arrow()
	_drag_grab = NO_DRAG
	scroll_to(0)


## Moves the list to row `to` (clamped) and puts the thumb where 0x445d70 does.
func scroll_to(to: int, announce: bool = true) -> void:
	pos = clampi(to, 0, maxi(0, count - visible_rows))
	visible = count > visible_rows
	if visible:
		var height := (visible_rows * THUMB_SCALE / count) * track_length / THUMB_SCALE
		thumb.position = Vector2(THUMB_X, TRACK_TOP + track_length * pos / count)
		thumb.size = Vector2(THUMB_WIDTH, height)
		_thumb_foot.position.y = height - THUMB_FOOT
	if announce: scrolled.emit(pos)


## A list whose length changed under the bar (the 獲得物品 pool after a take): keeps the row,
## clamped, without re-announcing it.
func resize(rows: int) -> void:
	count = rows
	scroll_to(pos, false)


## With the bar up, a new press of ↑／↓ moves one row and PgUp／PgDn nine (0x445f00 key masks
## 4／8／0x800／0x1000). The wheel does nothing: the original window procedure has no
## WM_MOUSEWHEEL case.
func handle_key(event: InputEvent) -> bool:
	if not (visible and event is InputEventKey and event.pressed and not event.echo): return false
	var step: int = {KEY_UP: -1, KEY_DOWN: 1, KEY_PAGEUP: -visible_rows, KEY_PAGEDOWN: visible_rows}.get(event.keycode, 0)
	if step == 0: return false
	scroll_to(pos + step)
	get_viewport().set_input_as_handled()
	return true


## 0x445cd0: pressing an arrow holds it; leaving it lets go without a step; releasing on it
## steps once.
func _arrow_input(event: InputEvent, arrow: TextureRect, step: int, held: ShaderMaterial) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_held_arrow = arrow
			arrow.material = held
		elif _held_arrow == arrow:
			_release_arrow()
			scroll_to(pos + step)
	elif event is InputEventMouseMotion and _held_arrow == arrow and not Rect2(Vector2.ZERO, arrow.size).has_point(event.position):
		_release_arrow()


func _release_arrow() -> void:
	if _held_arrow != null: _held_arrow.material = null
	_held_arrow = null


## 0x445860 on the trough: a press above the thumb pages up nine rows, below it down nine;
## the press then drags the thumb (grab point kept) — it follows the mouse smoothly between
## the track ends while the list follows whole rows, pos = ⌊(top − 22 + ⌊110/n⌋)·n/220⌋; the
## release snaps the thumb onto that row.
func _trough_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			if event.position.y < thumb.position.y: scroll_to(pos - visible_rows)
			elif event.position.y > thumb.position.y + thumb.size.y: scroll_to(pos + visible_rows)
			_drag_grab = int(event.position.y - thumb.position.y)
		elif _drag_grab != NO_DRAG:
			_drag_grab = NO_DRAG
			scroll_to(pos)
	elif event is InputEventMouseMotion and _drag_grab != NO_DRAG:
		var top := clampi(int(event.position.y) - _drag_grab, TRACK_TOP, TRACK_TOP + track_length)
		scroll_to((top - TRACK_TOP + track_length / (2 * count)) * count / track_length)
		thumb.position.y = mini(top, TRACK_TOP + track_length - int(thumb.size.y) - 1)
