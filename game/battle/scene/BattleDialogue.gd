extends Control
## Shared source artwork and pagination; callers own story progression.
## provenance:
##   layout: runtime-measured docs/evidence_packets/runtime_observations/dialogue_death/README.md
##     (the speaking map actor is lit while its message is up — ActorRuntime speaker highlight)
##   layout: resource-derived content/imported/hsl/shared/panels/manifest.json
##   layout: resource-derived content/imported/hsl/chapter01/battle001/portraits/manifest.json
##   layout: resource-derived content/generated/hsl/roles/actor_portraits.json
##   layout: runtime-reference docs/evidence_packets/runtime_observations/original_gameplay_reference/README.md#V01
##     (board bottom edge y≈320, portrait／name／text zones)
##   layout: static-derived docs/evidence_packets/static_reverse/original_dialogue_board.md
##     (name row: proc 0x414280 writes "@3"＋name＋":@1#" (0x476c50／0x476c5c), then 0x413960 wraps it)
##   layout: runtime-measured docs/evidence_packets/static_reverse/original_dialogue_board.md
##     (message 369 on the 2026-09-24 recording: rows at y 342／370／398／426, 19 glyphs a row, the name scrolled away)
##   layout: static-derived docs/evidence_packets/static_reverse/original_dialogue_marker.md
##   layout: runtime-measured docs/evidence_packets/static_reverse/original_dialogue_marker.md
##     (the □ ink: a 20×20 one-pixel outline at (605,438) on the bottom board)
##   layout: static-derived docs/evidence_packets/static_reverse/original_font_script/README.md
##     (name, body and ▼ in FONT.24 via 0x413040／0x4147f1; cell top at window top + 28·row)
##   layout: remake-invented
##     (OPT-WORDBREAK 保護專名: protected_words.json names kept whole where the original's 38-byte break cuts
##     them)
##   strings: resource-derived content/imported/hsl/chapter01/message_text_evidence.json
##   strings: static-derived docs/evidence_packets/static_reverse/original_dialogue_marker.md
##   timing: static-derived docs/evidence_packets/static_reverse/original_dialogue_board.md
##   timing: runtime-measured docs/evidence_packets/runtime_observations/dialogue_death/README.md
##     (dissolves 0.29／0.32 s on the 19.4 ms host)
##   timing: runtime-measured docs/evidence_packets/static_reverse/original_dialogue_board.md
##     (wipe 15 px in 0.1 s, a four-row scroll 0.80 s on the recording)
##   timing: static-derived docs/evidence_packets/static_reverse/original_dialogue_marker.md
##   timing: remake-invented
##     (OPT-PACE 快／極快: a player confirm during the wipe or the scroll acts at once — the original,
##     and OPT-PACE 原版, reads no confirm until the page is still)
const BattleUISkin = preload("res://game/common/BattleUISkin.gd")
const OriginalTick = preload("res://game/common/OriginalTick.gd")
const ContentPaths = preload("res://game/sim/ContentPaths.gd")
const GameOptions = preload("res://game/settings/GameOptions.gd")
## Text window (0x4142aa, 0x414360): rows start 17 px inside the board's top-left corner, 28 px
## apart, four in view (0x414661 splits four rows; the fifth drawn row is the one scrolling in).
const TEXT_INSET := Vector2(17, 17)
const ROW_PITCH := 28.0
const WINDOW_ROWS := 4
## Wide enough for a 38-byte row of the widest ASCII (the 19-glyph row is 456 px in FONT.24).
const TEXT_WINDOW_WIDTH := 470.0
## A confirm scrolls at most this many rows (0x4148e6 +0x98 = 4).
const SCROLL_ROWS := 4
## Wipe (state 1, 0x414494／0x4146c5): the window's clip starts 17 px tall and grows 3 px a tick
## ([0x477c1c]) to the full 112 (0x70); the first tick is the one that splits the rows.
const WIPE_START_PIXELS := 17.0
const WIPE_PIXELS_PER_TICK := 3.0
const WINDOW_PIXELS := 112.0
## Scroll (state 4, 0x414933): the rows move up 3 px a tick; at 28 the row table shifts, so a
## row takes 10 ticks.
const SCROLL_PIXELS_PER_TICK := 3.0
const SCROLL_TICKS_PER_ROW := 10
## Fade (0x41469e／0x4149c3): one of 16 levels a tick, in and out.
const FADE_TICKS := 16
## Board top edge in logical pixels (dialogue handler 0x414280 init, 0x4145f6–0x414618): camera
## y + 320, or camera y + 20 when the board's flag 0x4000 is set. Only 0x414220 sets that flag,
## and only for script-faced lines — actShapeMessage (STORY VM op 74, 0x45194c) and the town's
## teShapeMessage／teCheckMoney shortfall line (0x455612) — so those take the top slot and every
## other line the bottom one, wherever its speaker stands.
const PANEL_TOP_BOTTOM_SLOT := 320.0
const PANEL_TOP_TOP_SLOT := 20.0
## Board left edge: camera x + 144 for a line with a speaker object (0x41461b); a speakerless
## board (defNoOne narration: the slot lookup returns < 0, so +0xa8 = 0) is centred instead,
## (640 − 489) / 2 = 75 (0x41446c–0x414484, used at 0x414632).
const NARRATION_BOARD_X := 75.0
## The name row (row 0) and the body rows (from row 1 under a name, row 0 in narration), both
## inside `text_rows`, which the scroll moves up inside the clipping `text_window`.
var speaker_label: Label
var body_label: Label
var text_window: Control
var text_rows: Control
## The logical page: the first row in view (0 = the name row, or the first body row in
## narration). Changes at once on a confirm; the visible scroll follows it.
var top_row := 0
var _name_row := false
## Page marker (dialogue handler 0x414280, 0x414794–0x4148b8): the ▼ glyph while another page
## follows, the □ glyph (`end_marker`, drawn as its measured ink) on the last page; both
## blink MARKER_BLINK_TICKS shown／hidden once the page is wiped in.
var continue_label: Label
var end_marker: Control
const BOARD_AT := Vector2(144, 0)
## The glyph cell: the board's bottom-right corner minus 30 px (BOARD02 is 489×145).
const MARKER_CELL := BOARD_AT + Vector2(489 - 30, 145 - 30)
## The □ ink inside the cell: a one-pixel white outline 20 px square.
const END_MARKER_INK_OFFSET := Vector2(2, 3)
const END_MARKER_SIZE := 20.0
const MARKER_BLINK_TICKS := 10
var portrait: TextureRect
var _message_key := ""
## The body as the caller passed it (body_label.text carries the row breaks).
var _body_source := ""
var _portraits: Dictionary
var _roster_faces: Dictionary = {}
## actShapeMessage faces (portrait manifest shape_faces: shape member → res_path).
var _faces: Dictionary = {}
## Board fades, the wipe and the scroll are purely visual: the message, its page and `visible`
## change at once, so every caller's logic and input stay as they were.
const DISSOLVE_IN_SECONDS := FADE_TICKS * OriginalTick.TICK_SECONDS
const DISSOLVE_OUT_SECONDS := FADE_TICKS * OriginalTick.TICK_SECONDS
## Seconds since the current board started fading in (negative while an old board still fades
## out) and since the current page's wipe or scroll started.
var _board_clock := 0.0
var _reveal_clock := 0.0
## Rows the current scroll moves (0: the page is the board's first, wiping in).
var _scroll_rows := 0
var _ghost_left := 0.0
var _board_shown := false
## The map actor speaking the shown message (ActorRuntime): lit with its "speaker" highlight
## while its message is up, released when the message changes or the board closes.
var _speaker_actor: Node = null
var _pending_speaker: Node = null
## Where the shown board sat on the previous frame: a board replaced by the next message is
## left behind (dissolving) where the player saw it, not where the new message goes.
var _shown_position := Vector2(0, PANEL_TOP_BOTTOM_SLOT)


func _ready() -> void:
	size = Vector2(640, 160)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# BOARD02 matches the complete dialogue frame, not the legacy detail crop.
	BattleUISkin.board(self, "BOARD02", BOARD_AT)
	portrait = TextureRect.new()
	portrait.position = Vector2(12, 0)
	portrait.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(portrait)
	text_window = Control.new()
	text_window.name = "TextWindow"
	text_window.position = BOARD_AT + TEXT_INSET
	text_window.size = Vector2(TEXT_WINDOW_WIDTH, WINDOW_PIXELS)
	text_window.clip_contents = true
	text_window.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(text_window)
	text_rows = Control.new()
	text_rows.name = "TextRows"
	text_rows.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text_window.add_child(text_rows)
	speaker_label = BattleUISkin.label(text_rows, Vector2.ZERO, BattleUISkin.FONT_BODY)
	speaker_label.add_theme_color_override("font_color", BattleUISkin.TEXT_GREEN)
	body_label = BattleUISkin.label(text_rows, Vector2.ZERO, BattleUISkin.FONT_BODY)
	body_label.add_theme_color_override("font_color", BattleUISkin.TEXT_WHITE)
	for label in [speaker_label, body_label]:
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		label.autowrap_mode = TextServer.AUTOWRAP_OFF
		label.add_theme_color_override("font_shadow_color", BattleUISkin.TEXT_SHADOW)
		# One 28 px row per line; FONT.24's 24 px line puts each glyph cell top on its row (0x413040).
		label.add_theme_constant_override("line_spacing", int(ROW_PITCH) - _font_height(label))
	continue_label = BattleUISkin.text(self, MARKER_CELL, BattleUISkin.TEXT_WHITE, BattleUISkin.FONT_BODY, Vector2(24, 24))
	end_marker = Control.new()
	end_marker.name = "EndMarker"
	end_marker.position = MARKER_CELL + END_MARKER_INK_OFFSET
	end_marker.size = Vector2.ONE * (END_MARKER_SIZE + 1.0)
	end_marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	end_marker.draw.connect(_draw_end_marker)
	add_child(end_marker)
	hide()


static func _font_height(label: Label) -> int:
	return int(ceilf(label.get_theme_font("font").get_height(label.get_theme_font_size("font_size"))))


## A label's top for text row `row` (the text centred on the row's 24 px glyph cell).
func _row_top(label: Label, row: int) -> float:
	return row * ROW_PITCH - (_font_height(label) - 24) / 2.0


func _process(delta: float) -> void:
	_ghost_left = maxf(0.0, _ghost_left - delta)
	if not visible: return
	_shown_position = position
	_board_clock += delta
	_reveal_clock += delta
	modulate.a = clampf(_board_clock / DISSOLVE_IN_SECONDS, 0.0, 1.0)
	_place_rows()
	_blink_marker()


## The text window's clip and the rows' scroll for the current clocks.
func _place_rows() -> void:
	var ticks := OriginalTick.ticks(_reveal_clock)
	if _scroll_rows == 0:
		text_window.size.y = reveal_height(ticks)
		text_rows.position.y = -top_row * ROW_PITCH
	else:
		text_window.size.y = WINDOW_PIXELS
		text_rows.position.y = -(top_row - _scroll_rows) * ROW_PITCH - scroll_offset(ticks, _scroll_rows)


## The □ glyph as the original draws text: once in the shadow colour at (+1,+1), then white.
func _draw_end_marker() -> void:
	var square := Rect2(Vector2(0.5, 0.5), Vector2.ONE * (END_MARKER_SIZE - 1.0))
	end_marker.draw_rect(Rect2(square.position + Vector2.ONE, square.size), BattleUISkin.TEXT_SHADOW, false, 1.0)
	end_marker.draw_rect(square, BattleUISkin.TEXT_WHITE, false, 1.0)


## Whether the page marker is in its shown half `since` seconds after the page finished
## wiping in (negative: still wiping, hidden).
static func marker_shown(since: float) -> bool:
	if since < 0.0:
		return false
	return int(floorf(since / (MARKER_BLINK_TICKS * OriginalTick.TICK_SECONDS) + 0.0001)) % 2 == 0


## Seconds from the start of the current page's wipe (or scroll) until the page is still and
## the marker starts blinking: the first page after the tick that splits its rows and the full
## wipe, a scrolled page after its rows' scroll (then the wipe state passes in one tick).
func page_wipe_seconds() -> float:
	if _scroll_rows == 0:
		return OriginalTick.seconds(1 + ceilf((WINDOW_PIXELS - WIPE_START_PIXELS) / WIPE_PIXELS_PER_TICK) + 1)
	return OriginalTick.seconds(_scroll_rows * SCROLL_TICKS_PER_ROW + 1)


## Whether the board swallows a player confirm now: under OPT-PACE 原版 (docs/OPTIONS.md, read on
## each confirm) the original handler 0x414280 reads the confirm keys only in state 2 — the page
## still, its marker blinking — never during the wipe (state 1) or the scroll (state 4). 快／極快
## take the confirm at once. The hosts' player-input entries ask this before paging; scripted
## drivers call advance_page directly and need no clock.
func holds_confirm() -> bool:
	return visible and _reveal_clock < page_wipe_seconds() and GameOptions.is_original("OPT-PACE")


## A confirm key or click as the dialogue hosts read it (left click, Enter, Space).
static func is_confirm(event: InputEvent) -> bool:
	if event is InputEventMouseButton:
		return event.button_index == MOUSE_BUTTON_LEFT and event.pressed
	return event is InputEventKey and event.pressed and not event.echo and (event.keycode == KEY_ENTER or event.keycode == KEY_SPACE)


func _blink_marker() -> void:
	var shown := marker_shown(_reveal_clock - page_wipe_seconds())
	var last_page := continue_label.text == ""
	continue_label.visible = shown and not last_page
	end_marker.visible = shown and last_page


## The text window's clip height `ticks` after the board appeared: 17 px on the tick that splits
## the rows, then 3 px more every tick, up to the four rows' 112 px — one wipe across rows and
## the gaps between them, top-down.
static func reveal_height(ticks: float) -> float:
	return minf(WINDOW_PIXELS, WIPE_START_PIXELS + WIPE_PIXELS_PER_TICK * maxf(0.0, floorf(ticks) - 1.0))


## How far the rows have scrolled `ticks` into a scroll of `rows` rows: 3 px a tick inside a
## row, and at 28 px the row table shifts (10 ticks a row).
static func scroll_offset(ticks: float, rows: int) -> float:
	var whole := int(floorf(maxf(0.0, ticks)))
	if whole >= rows * SCROLL_TICKS_PER_ROW:
		return rows * ROW_PITCH
	return floori(whole / float(SCROLL_TICKS_PER_ROW)) * ROW_PITCH + (whole % SCROLL_TICKS_PER_ROW) * SCROLL_PIXELS_PER_TICK


## A new board: the previous one (if shown) is left behind as a fading copy and the new board
## fades in once it is gone, its rows wiping in from the same moment.
func _begin_board() -> void:
	_release_speaker()
	if is_instance_valid(_pending_speaker) and _pending_speaker.has_method("set_highlight"):
		_speaker_actor = _pending_speaker
		_speaker_actor.set_highlight("speaker", true)
	_pending_speaker = null
	if visible and _board_shown:
		_leave_ghost()
	_board_shown = true
	_board_clock = -_ghost_left
	_reveal_clock = _board_clock
	_scroll_rows = 0
	modulate.a = 0.0


## Names the map actor who speaks the next shown message (hosts with a battle map: the story
## coordinator, battle-script messages). Hosts without one (towns, the epilogue) never call it.
func set_speaker_actor(actor: Node) -> void:
	_pending_speaker = actor


func _release_speaker() -> void:
	if is_instance_valid(_speaker_actor) and _speaker_actor.has_method("set_highlight"):
		_speaker_actor.set_highlight("speaker", false)
	_speaker_actor = null


## The board as last shown, detached (no script, so no logic or input) and dissolving out.
func _leave_ghost() -> void:
	var parent := get_parent()
	if parent == null or not is_inside_tree(): return
	var ghost: Control = duplicate(Node.DUPLICATE_GROUPS) as Control
	ghost.name = "DialogueDissolve"
	ghost.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(ghost, true)
	ghost.position = _shown_position
	ghost.modulate.a = modulate.a
	var tween := ghost.create_tween()
	tween.tween_property(ghost, "modulate:a", 0.0, DISSOLVE_OUT_SECONDS * ghost.modulate.a)
	tween.tween_callback(ghost.queue_free)
	_ghost_left = DISSOLVE_OUT_SECONDS * ghost.modulate.a


## The host names the portrait manifest its speakers draw from (a scene's
## `resources.portraits`, a town's `town_portraits`, the roster face table for the
## epilogue). There is no default table: an unreadable manifest is reported and
## every later speaker is a "Missing dialogue portrait" instead of another
## chapter's face. Speakers the scene manifest does not list — a party member's
## death line (R31: every PLAYERS row 001–009 has one) in a level whose scripts never
## make that member speak — draw from the roster face table, the one canonical
## face per actor id (ContentPaths.ACTOR_PORTRAITS); a face missing there too is
## still reported.
func configure_portraits(manifest_path: String) -> void:
	_portraits = {}
	_faces = {}
	_roster_faces = ContentPaths.actor_portraits()
	var parsed: Variant = ContentPaths.read_json(manifest_path) if manifest_path != "" and FileAccess.file_exists(manifest_path) else null
	if typeof(parsed) != TYPE_DICTIONARY or typeof((parsed as Dictionary).get("actors")) != TYPE_DICTIONARY:
		push_error("Dialogue portrait manifest missing or invalid: '" + manifest_path + "'")
		return
	_portraits = (parsed as Dictionary)["actors"]
	_faces = (parsed as Dictionary).get("shape_faces", {})


## Whether a script-named face (actShapeMessage shape member) is imported for this scene.
func has_face(shape_member: String) -> bool:
	return _faces.has(shape_member)


## The portrait rows this view can draw (the configured manifest): actor id → {res_path, name, …}.
func portrait_rows() -> Dictionary:
	return _portraits


## The face `show_message` would draw for `actor_id` (scene manifest, else roster face table);
## null when neither has a row.
func face_texture(actor_id: String) -> Texture2D:
	if _portraits.has(actor_id):
		return load(str(_portraits[actor_id]["res_path"]))
	if _roster_faces.has(actor_id):
		return load(str(_roster_faces[actor_id]["res_path"]))
	return null


## A speaker whose row is not in the manifest is a data error (the level assembler enumerates
## every scripted and death-line speaker): it is reported and the line still shows without a
## portrait, so the reader can advance instead of waiting on an invisible panel.
func show_message(message_key: String, speaker: String, body: String, actor_id: String) -> void:
	position = Vector2(0, PANEL_TOP_BOTTOM_SLOT)
	_show_body(message_key, body, true)
	speaker_label.text = speaker + ":"
	if _portraits.has(actor_id):
		BattleUISkin.show_shape(portrait, load(str(_portraits[actor_id]["res_path"])))
		portrait.show()
	elif _roster_faces.has(actor_id):
		BattleUISkin.show_shape(portrait, load(str(_roster_faces[actor_id]["res_path"])))
		portrait.show()
	else:
		push_error("Missing dialogue portrait: " + actor_id)
		BattleUISkin.show_shape(portrait, null)
		portrait.hide()
	_update_continue()
	show()


## actShapeMessage,<face shape>,<name id>,<message id>: a named line whose portrait is
## the script's own face shape (portrait manifest shape_faces) instead of a cast
## member's; an unimported face keeps the name and lets the body span the board.
## The script-faced line is the one the original raises to the top slot (flag 0x4000).
func show_face_message(message_key: String, speaker: String, body: String, shape_member: String) -> void:
	position = Vector2(0, PANEL_TOP_TOP_SLOT)
	_show_body(message_key, body, true)
	speaker_label.text = speaker + ":"
	if _faces.has(shape_member):
		BattleUISkin.show_shape(portrait, load(str((_faces[shape_member] as Dictionary)["res_path"])))
		portrait.show()
	else:
		BattleUISkin.show_shape(portrait, null)
		portrait.hide()
	_update_continue()
	show()


## Speakerless script narration (defNoOne): no portrait or name row — four body rows in view —
## and the board is centred (NARRATION_BOARD_X). `centred` false keeps the speaker board's place for a
## host's remake line that names a speaker without a face (a town line, the select prompt).
func show_narration(message_key: String, body: String, centred: bool = true) -> void:
	position = Vector2(NARRATION_BOARD_X - BOARD_AT.x if centred else 0.0, PANEL_TOP_BOTTOM_SLOT)
	_show_body(message_key, body, false)
	speaker_label.text = ""
	BattleUISkin.show_shape(portrait, null)
	portrait.hide()
	_update_continue()
	show()


## Lays the rows out: the name as row 0 when `name_row`, the body broken into rows by
## BattleUISkin.message_rows (0x413960's 38-byte rule) below it. A per-frame refresh of the same
## message keeps the reader's page.
func _show_body(message_key: String, body: String, name_row: bool) -> void:
	var changed := message_key != _message_key or body != _body_source
	if changed:
		_begin_board()
		top_row = 0
	if changed or name_row != _name_row:
		_name_row = name_row
		body_label.text = "\n".join(BattleUISkin.message_rows(body))
		_body_source = body
		var body_row := 1 if name_row else 0
		speaker_label.visible = name_row
		speaker_label.position = Vector2(0, _row_top(speaker_label, 0))
		speaker_label.size = Vector2(TEXT_WINDOW_WIDTH, 0)
		body_label.position = Vector2(0, _row_top(body_label, body_row))
		body_label.size = Vector2(TEXT_WINDOW_WIDTH, 0)
		_place_rows()
	_message_key = message_key


## The body as the host passed it (body_label.text carries the row breaks as well).
func body_text() -> String:
	return _body_source


## Rows the message has: the name row (when shown) and every body row.
func row_count() -> int:
	return (1 if _name_row else 0) + body_label.get_line_count()


## A confirm: scroll the next rows up — as many as are left below the window, at most
## SCROLL_ROWS — or false on the last page. Earlier rows stay in view when fewer than
## four scroll in, as in the original.
func advance_page() -> bool:
	var rows := mini(SCROLL_ROWS, row_count() - WINDOW_ROWS - top_row)
	if rows <= 0:
		return false
	top_row += rows
	_scroll_rows = rows
	_reveal_clock = 0.0
	_place_rows()
	_update_continue()
	return true


func clear_message() -> void:
	if visible and _board_shown:
		_leave_ghost()
	_board_shown = false
	_release_speaker()
	_pending_speaker = null
	_message_key = ""
	position = Vector2(0, PANEL_TOP_BOTTOM_SLOT)
	body_label.text = ""
	_body_source = ""
	top_row = 0
	_scroll_rows = 0
	speaker_label.text = ""
	continue_label.text = ""
	hide()


func _update_continue() -> void:
	var more_pages := top_row + WINDOW_ROWS < row_count()
	continue_label.text = "▼" if more_pages else ""
	_blink_marker()
