extends Control
## System scroll in two variants read from content/imported/hsl/global/title/manifest.json:
## "battle" = Title041 (任務說明／儲存戰場記錄／讀取回憶錄／讀取戰場記錄／設定選項／回主選單, lit
## Title042-047) raised by Esc or right click on a fresh player action ring; "world" = Title051 (整理裝備／
## 儲存回憶錄／讀取回憶錄／讀取戰場記錄／設定選項／回主選單, lit Title052-057) raised by Esc on
## the big map, with the Title031 回憶錄 eight-slot list for saving/loading memoirs. Both use
## the Title061-063 確定／取消 pair. Presentation only: every action goes through the runtime's
## existing owners (settlement controller checkpoint, CampaignProgress, scene change) and never
## touches the PlayLoop or world state directly.
##
## Original evidence: the scroll processes (battle 0x4253f0, big map 0x425a90) start the
## panel 400 px below its rest (battle, 0x42549b) or 600 px above it (big map, 0x425b3b),
## step it in with 0x45e882 (each tick min(40, distance >> 3) px, at least 2, snapping inside
## 1 px) and back out to the start with 0x45e91e(…, 40, 0) (40 px a tick). Keyboard selection
## is a remake reading (provisional). The user
## recording 2026-09-24 (docs/evidence_packets/runtime_observations/menus_ui/README.md) shows
## 儲存戰場記錄 and 回主選單 asking 確定／取消 with Title061 over the centre of the open scroll,
## 「進度儲存完成」 on the BOARD02 message board (no portrait, centred) at the bottom while the scroll stays open, and 任務說明
## dissolving the win／fail board (BattleWinFailBoard) in over the scroll. 讀取回憶錄 opens the Title031
## eight-slot load list in both variants (battle proc 0x4253f0 item 2 → 0x423bd0(…, 0), Wine frame
## menus_ui §3); 整理裝備 hands off to the host's PartyEquipmentScreen.
## Opening either scroll plays ACCEPT01 (RESOURCE 398): battle defProcBattleBOSS, big map
## walker state 10 0x427c41. The 確定／取消 prompt carries no question; OPT-GUIDE＝提示 adds a
## question line under the scroll (remake).
## Under the untouched Title039 panel a 重製選項 entry (remake) opens RemakeOptionsPage, the
## second page of the remake's own options (docs/OPTIONS.md); Down past 音樂音量 reaches it.
## provenance:
##   rules: static-derived docs/evidence_packets/runtime_observations/menus_ui/README.md
##     (battle scroll opened by defProcBattleBOSS 0x4082ab; 讀取回憶錄 → load list 0x425842)
##   rules: provisional (確定／取消 on the other battle items, memoir slot confirm)
##   layout: resource-derived content/imported/hsl/global/title/manifest.json
##   layout: runtime-reference docs/evidence_packets/runtime_observations/original_gameplay_reference/README.md#05
##     (scroll rests at (190,67))
##   layout: remake-invented content/authored/options/remake_options.json (重製選項 entry under Title039)
##   layout: runtime-measured docs/evidence_packets/runtime_observations/menus_ui/README.md
##     (Title061 at (256,217), no shade; save notice on BOARD02 at (75,320), no portrait; 任務說明 = WINDOW60 at (136,108))
##   layout: provisional (memoir list position)
##   layout: remake-invented (the confirm question line under the scroll, OPT-GUIDE＝提示 only)
##   strings: resource-derived content/imported/hsl/global/title/manifest.json
##   strings: runtime-measured docs/evidence_packets/runtime_observations/menus_ui/README.md (「進度儲存完成」)
##   strings: remake-invented (memoir labels; confirm questions and hints — OPT-GUIDE＝提示 only)
##   timing: static-derived docs/evidence_packets/runtime_observations/menus_ui/README.md
##     (scroll steps 0x45e882／0x45e91e from 0x4253f0 case 0／4 and 0x425a90)
##   timing: runtime-measured docs/evidence_packets/runtime_observations/menus_ui/README.md
##     (save notice ≈0.24 s in, ≈1 s held, ≈0.14 s out; 任務說明 board dissolves ≈0.4 s each way (32／34 ticks))
##   timing: remake-invented (1.6 s hint line, OPT-GUIDE＝提示 only)
##   audio: static-derived docs/evidence_packets/runtime_observations/menus_ui/README.md
##     (ACCEPT01 on open: 0x4082ab, 0x427c41)
##   audio: resource-derived content/imported/hsl/shared/interface_audio/manifest.json (confirm = ACCEPT01)

## World variant 整理裝備: the host opens the between-battle party equipment screen
## (game/world/PartyEquipmentScreen) with the carried party; the scroll itself closes.
signal arrange_equipment_requested
## A window opened on its own (open_standalone, the title's gem／book) went back.
signal standalone_closed(kind: String)

const MANIFEST_PATH := "res://content/imported/hsl/global/title/manifest.json"
const TITLE_SCENE_PATH := "res://game/title/TitleScreen.tscn"
const BattleUISkin = preload("res://game/common/BattleUISkin.gd")
const CampaignProgress = preload("res://game/common/CampaignProgress.gd")
const WorldMapRules = preload("res://game/world/WorldMapRules.gd")
const GameSettings = preload("res://game/settings/GameSettings.gd")
const RemakeOptionsPage = preload("res://game/settings/RemakeOptionsPage.gd")
const GameOptions = preload("res://game/settings/GameOptions.gd")
const Interaction = preload("res://game/sim/Interaction.gd")
const ContentPaths = preload("res://game/sim/ContentPaths.gd")
const SLIDER_STEP := 0.1
const OriginalTick = preload("res://game/common/OriginalTick.gd")
## Scroll start offsets from the rest position: battle +400 px (0x42549b), big map −600 px
## (0x425b3b); the close returns there.
const SCROLL_START_OFFSET := {"battle": 400.0, "world": -600.0}
## 0x45e882 speed cap and shift (open), 0x45e91e speed with shift 0 (close).
const SCROLL_STEP_CAP := 40
const SCROLL_OPEN_SHIFT := 3
const SCROLL_MIN_STEP := 2
## Upper bound of an open: the big map's 600 px take 40 ticks (battle 400 px: 35).
const SCROLL_SECONDS := 40 * OriginalTick.TICK_SECONDS
const HINT_SECONDS := 1.6
## Battle scroll items that ask 確定／取消 first. The 2026-09-24 recording shows the prompt for
## 儲存戰場記錄 (581.0 s) and 回主選單 (592.5 s); the others share it (provisional). The
## question text is the remake's, shown only under OPT-GUIDE＝提示 (the original shows none).
const CONFIRM_ACTIONS := {
	"save_record": "儲存戰場記錄？",
	"load_record": "讀取戰場記錄，覆蓋目前進度？",
	"main_menu": "回主選單，放棄目前戰鬥？",
}
const WORLD_CONFIRM_ACTIONS := {
	"load_record": "讀取戰場記錄，回到該場戰鬥？",
	"main_menu": "回主選單，放棄目前進度？",
}
## 「進度儲存完成」 on the BOARD02 message board (centred, no portrait) after 儲存戰場記錄 (user recording
## 582.53 → 582.77 s in, held to 583.73 s, out by 583.87 s); the scroll stays open.
const SAVE_NOTICE_TEXT := "進度儲存完成"
const SAVE_NOTICE_AT := Vector2(75, 320)
const SAVE_NOTICE_TEXT_Y := 44.0
const SAVE_NOTICE_IN_SECONDS := 0.25
const SAVE_NOTICE_HOLD_SECONDS := 0.95
const SAVE_NOTICE_OUT_SECONDS := 0.15
## The confirm question under the scroll (remake-invented, OPT-GUIDE＝提示 only; the original shows none).
const CONFIRM_QUESTION_Y := 446.0
const BattleWinFailBoard = preload("res://game/battle/scene/BattleWinFailBoard.gd")
const MEMOIR_HINTS := {"empty": "空的回憶錄", "saved": "回憶錄已儲存", "no_record": "沒有可儲存的進度"}

var runtime: Node
var variant := "battle" # battle | world
var manifest: Dictionary = {}
var items: Array = []
var confirm_items: Array = []
var memoir_layout: Dictionary = {}
var options_rows: Array = []
var options_groove: Dictionary = {}
var options_selected := 0
var selected := 0
var confirm_selected := 1 # 取消 by default
var memoir_selected := 0
var memoir_mode := "" # save | load
var phase := "closed" # closed | opening | menu | confirm | mission | memoir | options | remake_options | closing
var pending_action := ""
var pending_slot := -1
var last_result: Dictionary = {}
var _panel: TextureRect
var _lit: TextureRect
var _memoir_box: Control
var _memoir_heading: TextureRect
var _memoir_rows: Array[Label] = []
var _memoir_cursor: ColorRect
var _options_box: Control
var _options_panel: TextureRect
var _options_cursor: ColorRect
var _options_knobs: Dictionary = {}
## 重製選項 entry under the Title039 panel (row index options_rows.size()) and its page.
var _remake_entry_rect := Rect2()
var _remake_page: Control
var _confirm_box: Control
var _confirm_buttons: TextureRect
var _confirm_lit: TextureRect
var _confirm_question: Label
var _mission_box: Control
## The 任務說明 board (the opening's win／fail board, waiting for input) and its first
## condition row once shown.
var _mission_board: Control
var _mission_text: Label
var _save_notice: Control
var _save_notice_tween: Tween
var _hint: Label
var _hint_timer: Timer
var _panel_open_position := Vector2(190, 67)
var _panel_closed_position := Vector2(190, 480)
var _slide_target := Vector2.ZERO
var _slide_shift := -1
var _slide_done: Callable
var _slide_clock := 0.0
## "" or the window opened without the scroll: "options" (設定選項) or "memoir" (讀取回憶錄 list).
var standalone := ""


func _ready() -> void:
	size = Vector2(640, 480)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	var parsed: Variant = ContentPaths.read_json(MANIFEST_PATH)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("Title manifest missing or invalid: " + MANIFEST_PATH)
		return
	manifest = parsed
	var panel_role := "world_panel" if variant == "world" else "system_panel"
	items = manifest.get("world_items" if variant == "world" else "system_items", [])
	confirm_items = manifest.get("confirm_items", [])
	memoir_layout = manifest.get("memoir_list", {})
	options_rows = (manifest.get("options_rows", []) as Array).duplicate(true)
	options_groove = manifest.get("options_groove", {})
	var layout: Dictionary = manifest.get("layout", {})
	var panel_layout: Dictionary = layout.get(panel_role, {})
	var top_left: Array = panel_layout.get("top_left", [190, 67])
	_panel_open_position = Vector2(float(top_left[0]), float(top_left[1]))
	_panel_closed_position = _panel_open_position + Vector2(0.0, float(SCROLL_START_OFFSET.get(variant, 400.0)))
	_panel = _texture_rect(panel_role)
	_panel.position = _panel_closed_position
	add_child(_panel)
	_lit = TextureRect.new()
	_lit.name = "Lit"
	_lit.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_lit.visible = false
	_panel.add_child(_lit)
	_build_confirm(layout)
	_build_mission_and_notice()
	_build_memoir(layout)
	_build_options(layout)
	_build_remake_entry_and_hint()


## _ready phase: the 確定／取消 prompt.
func _build_confirm(layout: Dictionary) -> void:
	# 確定／取消 prompt (Title061 + lit 062/063) over the open scroll, unshaded as in the
	# original; OPT-GUIDE＝提示 adds a one-line question under the scroll (_ask).
	_confirm_box = Control.new()
	_confirm_box.name = "Confirm"
	_confirm_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_confirm_box.visible = false
	add_child(_confirm_box)
	_confirm_question = BattleUISkin.label(_confirm_box, Vector2(0, CONFIRM_QUESTION_Y), 20)
	_confirm_question.size = Vector2(640, 32)
	_confirm_question.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_confirm_question.add_theme_color_override("font_color", Color(0.97, 0.9, 0.7))
	_confirm_buttons = _texture_rect("confirm_buttons")
	var confirm_layout: Dictionary = layout.get("confirm_buttons", {})
	var confirm_top_left: Array = confirm_layout.get("top_left", [256, 217])
	_confirm_buttons.position = Vector2(float(confirm_top_left[0]), float(confirm_top_left[1]))
	_confirm_box.add_child(_confirm_buttons)
	_confirm_lit = TextureRect.new()
	_confirm_lit.name = "ConfirmLit"
	_confirm_lit.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_confirm_buttons.add_child(_confirm_lit)


## _ready phase: the 任務說明 board and the save notice.
func _build_mission_and_notice() -> void:
	# 任務說明: the win／fail board of the opening (WINDOW60 centred, 勝利條件／失敗條件 over
	# the armed labels) dissolving in over the scroll and waiting for a key or click.
	_mission_box = Control.new()
	_mission_box.name = "Mission"
	_mission_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mission_box.visible = false
	add_child(_mission_box)
	_mission_board = BattleWinFailBoard.new()
	_mission_board.hold_ticks = 0
	_mission_box.add_child(_mission_board)
	# 進度儲存完成 notice after 儲存戰場記錄.
	_save_notice = Control.new()
	_save_notice.name = "SaveNotice"
	_save_notice.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_save_notice.visible = false
	add_child(_save_notice)
	BattleUISkin.board(_save_notice, "BOARD02", SAVE_NOTICE_AT)
	var notice_text := BattleUISkin.text(_save_notice, SAVE_NOTICE_AT + Vector2(0, SAVE_NOTICE_TEXT_Y), BattleUISkin.TEXT_WHITE, BattleUISkin.FONT_BODY, Vector2(489, 24))
	notice_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	notice_text.text = SAVE_NOTICE_TEXT


## _ready phase: the 回憶錄 list.
func _build_memoir(layout: Dictionary) -> void:
	# 回憶錄 list (Title031) with the mode heading (Title032 讀取／Title033 儲存) over its title.
	_memoir_box = Control.new()
	_memoir_box.name = "Memoir"
	_memoir_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_memoir_box.visible = false
	add_child(_memoir_box)
	var memoir_list := _texture_rect("memoir_list")
	var list_layout: Dictionary = layout.get("memoir_list", {})
	var list_top_left: Array = list_layout.get("top_left", [87, 44])
	memoir_list.position = Vector2(float(list_top_left[0]), float(list_top_left[1]))
	_memoir_box.add_child(memoir_list)
	_memoir_heading = TextureRect.new()
	_memoir_heading.name = "Heading"
	_memoir_heading.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var heading_offset: Array = memoir_layout.get("heading_offset", [139, 28])
	_memoir_heading.position = Vector2(float(heading_offset[0]), float(heading_offset[1]))
	memoir_list.add_child(_memoir_heading)
	_memoir_cursor = ColorRect.new()
	_memoir_cursor.name = "Cursor"
	_memoir_cursor.color = Color(0.95, 0.8, 0.35, 0.28)
	_memoir_cursor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var band: Array = memoir_layout.get("slot_band_x", [63, 407])
	_memoir_cursor.size = Vector2(float(band[1] - band[0]), float(memoir_layout.get("slot_height", 28)))
	memoir_list.add_child(_memoir_cursor)
	for slot in range(int(memoir_layout.get("slots", 8))):
		var row := BattleUISkin.label(memoir_list, Vector2(float(band[0]) + 12.0, _slot_top(slot) + 4.0), 16)
		row.size = Vector2(float(band[1] - band[0]) - 24.0, float(memoir_layout.get("slot_height", 28)) - 6.0)
		row.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9))
		_memoir_rows.append(row)


## _ready phase: the 設定選項 panel.
func _build_options(layout: Dictionary) -> void:
	# 設定選項 (Title039): gem knobs on the grooves, a band cursor on the selected row.
	_options_box = Control.new()
	_options_box.name = "Options"
	_options_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_options_box.visible = false
	add_child(_options_box)
	_options_panel = _texture_rect("options_panel")
	var options_layout: Dictionary = layout.get("options_panel", {})
	var options_top_left: Array = options_layout.get("top_left", [142, 90])
	_options_panel.position = Vector2(float(options_top_left[0]), float(options_top_left[1]))
	_options_box.add_child(_options_panel)
	_options_cursor = ColorRect.new()
	_options_cursor.name = "Cursor"
	_options_cursor.color = Color(0.95, 0.8, 0.35, 0.22)
	_options_cursor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var groove_x: Array = options_groove.get("x", [162, 330])
	_options_cursor.size = Vector2(float(groove_x[1]) + 4.0 - 12.0, 30.0)
	_options_panel.add_child(_options_cursor)
	var gem_entry: Dictionary = (manifest.get("shapes", {}) as Dictionary).get(str(options_groove.get("knob", "cursor_gem")), {})
	for row in options_rows:
		if str(row.get("kind", "")) == "not_remade":
			continue
		var knob := TextureRect.new()
		knob.name = "Knob_" + str(row.get("id", ""))
		knob.mouse_filter = Control.MOUSE_FILTER_IGNORE
		knob.texture = load(str(gem_entry.get("texture", "")))
		_options_panel.add_child(knob)
		_options_knobs[str(row.get("id", ""))] = knob


## _ready phase: the 重製選項 entry band and page, and the hint line.
func _build_remake_entry_and_hint() -> void:
	var entry: Dictionary = GameOptions.page_layout().get("entry", {})
	var entry_rect: Array = entry.get("rect", [230, 396, 180, 28])
	_remake_entry_rect = Rect2(float(entry_rect[0]), float(entry_rect[1]), float(entry_rect[2]), float(entry_rect[3]))
	RemakeOptionsPage.band(_options_box, _remake_entry_rect).name = "RemakeOptionsEntry"
	var entry_label := BattleUISkin.label(_options_box, _remake_entry_rect.position, int(entry.get("font", 16)))
	entry_label.text = str(entry.get("label", ""))
	entry_label.size = _remake_entry_rect.size
	entry_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	entry_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	entry_label.add_theme_color_override("font_color", RemakeOptionsPage.GOLD)
	_remake_page = RemakeOptionsPage.new()
	_remake_page.name = "RemakeOptions"
	_remake_page.visible = false
	add_child(_remake_page)
	_remake_page.back_requested.connect(_close_remake_options)
	_hint = BattleUISkin.label(self, Vector2(0, 430), 18)
	_hint.size = Vector2(640, 28)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.add_theme_color_override("font_color", Color(1.0, 0.9, 0.6))
	_hint.visible = false
	_hint_timer = Timer.new()
	_hint_timer.one_shot = true
	_hint_timer.timeout.connect(func() -> void: _hint.visible = false)
	add_child(_hint_timer)


func _texture_rect(role: String) -> TextureRect:
	var entry: Dictionary = (manifest.get("shapes", {}) as Dictionary).get(role, {})
	var rect := TextureRect.new()
	rect.name = "Title_" + role
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.texture = load(str(entry.get("texture", "")))
	return rect


## True while the scroll is up or moving; the runtime routes all input here.
func active() -> bool:
	return phase != "closed"


## Scroll in from the bottom edge (recording 05, frames 001-003). The battle variant opens
## only on a freshly opened player action ring: defProcBattleBOSS 0x4082ab needs
## [0x4c1b00] & 0x7e000000 clear (0x2000000 is set by a ring-icon press 0x43e91a and at
## battle setup 0x42c6b4, cleared only when a new ring opens 0x443a52 — so move／target
## selection, the ring after a move, enemy turns and the wait before the first ring are shut;
## 0x4000000 story chain, 0x8000000／0x10000000 battle end) and the extra-action counter
## [0x4c1cf0] zero (0x4082b7).
func open() -> Dictionary:
	if phase != "closed":
		return {"ok": false, "reason": "already_open"}
	if variant == "battle" and runtime != null:
		if runtime.settlement_controller != null and not runtime.settlement_controller.quiet():
			return {"ok": false, "reason": "not_quiet"}
		if runtime.interaction_state != Interaction.ACTION_MENU:
			return {"ok": false, "reason": "interaction_" + str(runtime.interaction_state)}
		if runtime.pending_move_revert:
			return {"ok": false, "reason": "after_move"}
		if bool((runtime.play_loop.get("extra_action", {}) as Dictionary).get("pending", false)):
			return {"ok": false, "reason": "extra_action"}
	phase = "opening"
	visible = true
	selected = 0
	if runtime != null and runtime.has_method("play_ui_sound"):
		runtime.play_ui_sound("confirm")
	_panel.position = _panel_closed_position
	_show_lit(selected)
	_slide(_panel_open_position, SCROLL_OPEN_SHIFT, func() -> void: phase = "menu")
	return {"ok": true}


## The title's gem and book (defProcMainMenu 0x424037 codes 10／11) open 設定選項 (object 792,
## 0x423b90) or the 讀取回憶錄 list (object 790, 0x423bd0(…, 0)) with no scroll behind them; the
## window's back hides everything and reports standalone_closed (the menu re-arms, 0x424101／0x424117).
func open_standalone(kind: String) -> Dictionary:
	if phase != "closed" or not kind in ["options", "memoir"]:
		return {"ok": false, "reason": phase}
	standalone = kind
	visible = true
	_panel.visible = false
	if kind == "options":
		select_option(0)
		_show_options()
	else:
		memoir_selected = 0
		_show_memoir_list("load")
	return {"ok": true, "status": kind + "_shown"}


func _close_standalone() -> void:
	var kind := standalone
	standalone = ""
	_confirm_box.visible = false
	_memoir_box.visible = false
	_options_box.visible = false
	_panel.visible = true
	phase = "closed"
	visible = false
	standalone_closed.emit(kind)


## Scroll back down and hide.
func close() -> Dictionary:
	if phase in ["closed", "closing"]:
		return {"ok": false, "reason": phase}
	_confirm_box.visible = false
	_mission_board.finish()
	_mission_box.visible = false
	_memoir_box.visible = false
	_options_box.visible = false
	_remake_page.close()
	pending_action = ""
	pending_slot = -1
	phase = "closing"
	_slide(_panel_closed_position, 0, func() -> void:
		phase = "closed"
		visible = false)
	return {"ok": true}


## 整理裝備 (defProcBigMapMenu 0x425a90 case 0): 0x4253d0 hides the scroll's items at once
## (no slide) while the window is up; reopen_now brings the scroll back as it was when the
## window closes (original frame 17 → right click → the scroll, runtime-measured).
func hide_now() -> void:
	_slide_shift = -1
	_confirm_box.visible = false
	pending_action = ""
	pending_slot = -1
	phase = "closed"
	visible = false
	_panel.position = _panel_closed_position


func reopen_now() -> void:
	if phase != "closed":
		return
	phase = "menu"
	visible = true
	_panel.position = _panel_open_position
	_show_lit(selected)


## Moves the panel toward `target` one original tick at a time: `shift` 3 is the open
## (0x45e882), 0 the close (0x45e91e with shift 0).
func _slide(target: Vector2, shift: int, on_done: Callable) -> void:
	_slide_target = target
	_slide_shift = shift
	_slide_done = on_done
	_slide_clock = 0.0


func _process(delta: float) -> void:
	if _slide_shift < 0:
		return
	_slide_clock += maxf(delta, 0.0)
	while _slide_clock >= OriginalTick.TICK_SECONDS and _slide_shift >= 0:
		_slide_clock -= OriginalTick.TICK_SECONDS
		if _slide_tick():
			_slide_shift = -1
			_slide_done.call()


## One tick of 0x45e882／0x45e91e: within 1 px snap and report arrival; otherwise step
## min(40, distance >> shift) px (at least 2) toward the target.
func _slide_tick() -> bool:
	var offset := _slide_target - _panel.position
	var distance := int(sqrt(offset.length_squared()))
	if distance <= 1:
		_panel.position = _slide_target
		return true
	var step := clampi(distance >> _slide_shift, SCROLL_MIN_STEP, SCROLL_STEP_CAP)
	_panel.position = (_panel.position + offset / float(distance) * float(step)).round()
	return false


func _show_lit(index: int) -> void:
	if index < 0 or index >= items.size():
		_lit.visible = false
		return
	var item: Dictionary = items[index]
	var entry: Dictionary = (manifest.get("shapes", {}) as Dictionary).get(str(item.get("lit", "")), {})
	BattleUISkin.show_shape(_lit, load(str(entry.get("texture", ""))))
	var offset: Array = item.get("lit_offset_in_panel", [0, 0])
	_lit.position = Vector2(float(offset[0]), float(offset[1]))
	_lit.visible = true


func _show_confirm_lit(index: int) -> void:
	var item: Dictionary = confirm_items[index]
	var entry: Dictionary = (manifest.get("shapes", {}) as Dictionary).get(str(item.get("lit", "")), {})
	BattleUISkin.show_shape(_confirm_lit, load(str(entry.get("texture", ""))))
	var offset: Array = item.get("lit_offset_in_buttons", [0, 0])
	_confirm_lit.position = Vector2(float(offset[0]), float(offset[1]))


## Item row under a logical (640x480) point, or -1.
func item_at(logical: Vector2) -> int:
	if phase != "menu":
		return -1
	var local := logical - _panel.position
	if local.x < 0.0 or local.x >= float(_panel.texture.get_width()):
		return -1
	for index in range(items.size()):
		var center_y := float(items[index].get("text_center_y_in_panel", 0))
		if absf(local.y - center_y) <= 16.0:
			return index
	return -1


func confirm_item_at(logical: Vector2) -> int:
	if phase != "confirm":
		return -1
	var local := logical - _confirm_buttons.position
	if local.y < 0.0 or local.y >= float(_confirm_buttons.texture.get_height()):
		return -1
	if local.x >= 0.0 and local.x < 64.0:
		return 0
	if local.x >= 64.0 and local.x < 128.0:
		return 1
	return -1


func select(index: int) -> void:
	if items.is_empty():
		return
	selected = wrapi(index, 0, items.size())
	_show_lit(selected)


func hover_at(logical: Vector2) -> void:
	match phase:
		"menu":
			var index := item_at(logical)
			if index >= 0:
				select(index)
		"confirm":
			var index := confirm_item_at(logical)
			if index >= 0:
				confirm_selected = index
				_show_confirm_lit(confirm_selected)
		"memoir":
			var slot := memoir_slot_at(logical)
			if slot >= 0:
				select_memoir(slot)
		"options":
			var row := options_row_at(logical)
			if row >= 0:
				select_option(row)


## 設定選項 row under a logical point, or -1.
func options_row_at(logical: Vector2) -> int:
	if phase != "options":
		return -1
	if _remake_entry_rect.has_point(logical):
		return options_rows.size()
	var local := logical - _options_panel.position
	if local.x < 12.0 or local.x > float(_options_panel.texture.get_width()) - 12.0:
		return -1
	for index in range(options_rows.size()):
		if absf(local.y - float(options_rows[index].get("center_y_in_panel", 0))) <= 15.0:
			return index
	return -1


func select_option(index: int) -> void:
	if options_rows.is_empty():
		return
	options_selected = wrapi(index, 0, options_rows.size() + 1)
	if options_selected == options_rows.size():
		_options_cursor.position = _remake_entry_rect.position - _options_panel.position
		_options_cursor.size = _remake_entry_rect.size
		return
	var groove_x: Array = options_groove.get("x", [162, 330])
	_options_cursor.size = Vector2(float(groove_x[1]) + 4.0 - 12.0, 30.0)
	_options_cursor.position = Vector2(12.0, float(options_rows[options_selected].get("center_y_in_panel", 0)) - 15.0)


func _knob_x(row: Dictionary) -> float:
	var groove_x: Array = options_groove.get("x", [162, 330])
	var margin := float(options_groove.get("knob_margin", 18))
	var left := float(groove_x[0]) + margin
	var right := float(groove_x[1]) - margin
	match str(row.get("kind", "")):
		"toggle":
			return right if bool(GameSettings.get_value(str(row.get("id", "")))) else left
		"slider":
			return lerpf(left, right, float(GameSettings.get_value(str(row.get("id", "")))))
	return left


func _refresh_options() -> void:
	var gem: Dictionary = (manifest.get("shapes", {}) as Dictionary).get(str(options_groove.get("knob", "cursor_gem")), {})
	var origin: Array = gem.get("draw_origin", [14, 14])
	for row in options_rows:
		var knob: TextureRect = _options_knobs.get(str(row.get("id", "")))
		if knob == null:
			continue
		knob.position = Vector2(_knob_x(row) - float(origin[0]), float(row.get("center_y_in_panel", 0)) - float(origin[1]))
	select_option(options_selected)


func _show_options() -> void:
	_lit.visible = false
	_refresh_options()
	_options_box.visible = true
	phase = "options"


## Left/Right (or a click on the groove) change the selected row; Enter flips a toggle.
func adjust_option(direction: int, fraction: float = -1.0) -> Dictionary:
	if phase != "options":
		return {"ok": false, "reason": phase}
	if options_selected == options_rows.size():
		if direction != 0:
			return {"ok": true, "action": "option", "id": "remake_options", "status": "none"}
		_open_remake_options()
		last_result = {"ok": true, "action": "option", "id": "remake_options", "status": "remake_options_shown"}
		return last_result
	var row: Dictionary = options_rows[options_selected]
	var id := str(row.get("id", ""))
	var result: Dictionary = {"ok": true, "action": "option", "id": id}
	match str(row.get("kind", "")):
		"toggle":
			var current := bool(GameSettings.get_value(id))
			var next := (fraction >= 0.5) if fraction >= 0.0 else (not current if direction == 0 else direction > 0)
			GameSettings.set_value(id, next)
			result["status"] = "set"
			result["value"] = next
		"slider":
			var current := float(GameSettings.get_value(id))
			var next := fraction if fraction >= 0.0 else current + SLIDER_STEP * direction
			result["value"] = float(GameSettings.set_value(id, next).get(id, next))
			result["status"] = "set"
		_:
			result["status"] = "not_remade"
			_show_hint("%s尚未重製" % str(row.get("label", id)))
	_refresh_options()
	last_result = result
	return result


## The 重製選項 page takes the place of the Title039 panel until it goes back.
func _open_remake_options() -> void:
	_options_box.visible = false
	_remake_page.open()
	phase = "remake_options"


func _close_remake_options() -> void:
	if phase != "remake_options":
		return
	_remake_page.close()
	_options_box.visible = true
	_refresh_options()
	phase = "options"


func _slot_top(slot: int) -> float:
	return float(memoir_layout.get("slot_first_top", 80)) + float(memoir_layout.get("slot_pitch", 33)) * slot


## Memoir slot band under a logical point, or -1.
func memoir_slot_at(logical: Vector2) -> int:
	if phase != "memoir":
		return -1
	var list: TextureRect = _memoir_box.get_node("Title_memoir_list")
	var local := logical - list.position
	var band: Array = memoir_layout.get("slot_band_x", [63, 407])
	if local.x < float(band[0]) or local.x > float(band[1]):
		return -1
	for slot in range(_memoir_rows.size()):
		var top := _slot_top(slot)
		if local.y >= top and local.y < top + float(memoir_layout.get("slot_height", 28)):
			return slot
	return -1


func select_memoir(slot: int) -> void:
	if _memoir_rows.is_empty():
		return
	memoir_selected = wrapi(slot, 0, _memoir_rows.size())
	var band: Array = memoir_layout.get("slot_band_x", [63, 407])
	_memoir_cursor.position = Vector2(float(band[0]), _slot_top(memoir_selected))


func _show_memoir_list(mode: String) -> void:
	memoir_mode = mode
	var heading_role := "memoir_heading_save" if mode == "save" else "memoir_heading_load"
	var entry: Dictionary = (manifest.get("shapes", {}) as Dictionary).get(heading_role, {})
	BattleUISkin.show_shape(_memoir_heading, load(str(entry.get("texture", ""))))
	var entries: Array = CampaignProgress.memoir_entries()
	for slot in range(_memoir_rows.size()):
		var record: Dictionary = entries[slot] if slot < entries.size() else {"empty": true}
		if bool(record.get("empty", true)):
			_memoir_rows[slot].text = "%d.  ──" % (slot + 1)
		else:
			_memoir_rows[slot].text = "%d.  %s　%s" % [slot + 1, str(record.get("label", "")), CampaignProgress.format_play_seconds(float(record.get("play_seconds", 0.0)))]
	select_memoir(memoir_selected)
	_lit.visible = false
	_memoir_box.visible = true
	phase = "memoir"


## Progress record the world scroll saves: the campaign owner's view of the current position.
func _current_progress_record() -> Dictionary:
	if runtime != null and runtime.campaign_progress != null:
		return runtime.campaign_progress.current_progress_record()
	return {}


func _memoir_label(record: Dictionary) -> String:
	var campaign_data: Dictionary = runtime.campaign_progress.campaign if runtime != null and runtime.campaign_progress != null else {}
	var entry := CampaignProgress.campaign_entry_for_scenario(campaign_data, str(record.get("scenario_path", "")))
	var label := str(entry.get("title", str(record.get("scenario_path", "")).get_file().get_basename()))
	var world: Dictionary = record.get("world", {}) if typeof(record.get("world")) == TYPE_DICTIONARY else {}
	if runtime != null and runtime.world_map_runtime != null and int(world.get("current_point", 0)) > 0:
		label += "　" + str(WorldMapRules.point_label(runtime.world_map_runtime.world_map, int(world.get("current_point", 0))))
	return label


## Enter on a memoir slot: save (asking before overwriting) or load (asking before leaving).
func activate_memoir() -> Dictionary:
	if phase != "memoir":
		return {"ok": false, "reason": phase}
	var slot := memoir_selected
	var existing := CampaignProgress.load_memoir(slot)
	var result: Dictionary = {"ok": true, "action": memoir_mode + "_memoir", "slot": slot}
	if memoir_mode == "save":
		if not existing.is_empty():
			pending_action = "overwrite_memoir"
			pending_slot = slot
			phase = "confirm"
			confirm_selected = 1
			_ask("覆蓋回憶錄 %d？" % (slot + 1))
			result["status"] = "confirm"
			last_result = result
			return result
		return _save_memoir_slot(slot)
	if existing.is_empty():
		result["status"] = "empty"
		_show_hint(MEMOIR_HINTS["empty"])
		last_result = result
		return result
	pending_action = "resume_memoir"
	pending_slot = slot
	phase = "confirm"
	confirm_selected = 1
	_ask("讀取回憶錄 %d，放棄目前進度？" % (slot + 1))
	result["status"] = "confirm"
	last_result = result
	return result


func _save_memoir_slot(slot: int) -> Dictionary:
	var record := _current_progress_record()
	var result: Dictionary = {"ok": true, "action": "save_memoir", "slot": slot}
	if record.is_empty():
		result["status"] = "no_record"
		_show_hint(MEMOIR_HINTS["no_record"])
	else:
		result["status"] = "saved" if CampaignProgress.save_memoir(slot, record, _memoir_label(record)) else "save_failed"
		result["label"] = _memoir_label(record)
		_show_hint(MEMOIR_HINTS["saved"])
		_show_memoir_list("save")
	last_result = result
	return result


func _resume_memoir_slot(slot: int) -> Dictionary:
	var record := CampaignProgress.load_memoir(slot)
	var result: Dictionary = {"ok": true, "action": "load_memoir", "slot": slot, "status": "memoir_resumed", "scenario_path": str(record.get("scenario_path", ""))}
	last_result = result
	if runtime.has_method("resume_memoir_record"):
		runtime.resume_memoir_record(record)
	else:
		runtime.campaign_progress.resume_saved_progress(record)
	return result


## Run the selected item. Destructive items first ask 確定／取消.
func activate() -> Dictionary:
	if phase != "menu":
		return {"ok": false, "reason": phase}
	var action := str(items[selected].get("id", ""))
	var confirm_table: Dictionary = WORLD_CONFIRM_ACTIONS if variant == "world" else CONFIRM_ACTIONS
	if variant == "world" and action == "load_record" and CampaignProgress.battle_record_entries().is_empty():
		return _perform(action) # nothing to confirm: says 沒有戰場記錄
	if confirm_table.has(action):
		pending_action = action
		phase = "confirm"
		confirm_selected = 1
		# The chosen item stays lit under the prompt (user recording 582.0 s, 592.5 s).
		_ask(str(confirm_table[action]))
		return {"ok": true, "status": "confirm", "action": action}
	return _perform(action)


## Shows the 確定／取消 prompt; the question line only under OPT-GUIDE＝提示.
func _ask(question: String) -> void:
	_confirm_question.text = question
	_confirm_question.visible = not GameOptions.is_original("OPT-GUIDE")
	_show_confirm_lit(confirm_selected)
	_confirm_box.visible = true


func confirm(accept: bool) -> Dictionary:
	if phase != "confirm":
		return {"ok": false, "reason": phase}
	var action := pending_action
	var slot := pending_slot
	pending_action = ""
	pending_slot = -1
	_confirm_box.visible = false
	if action in ["overwrite_memoir", "resume_memoir"]:
		phase = "memoir"
		if not accept:
			return {"ok": true, "status": "cancelled", "action": action, "slot": slot}
		return _save_memoir_slot(slot) if action == "overwrite_memoir" else _resume_memoir_slot(slot)
	_lit.visible = true
	phase = "menu"
	if not accept:
		return {"ok": true, "status": "cancelled", "action": action}
	return _perform(action)


func _perform(action: String) -> Dictionary:
	var result: Dictionary = {"ok": true, "action": action}
	if variant == "world":
		match action:
			"save_memoir", "load_memoir":
				_show_memoir_list("save" if action == "save_memoir" else "load")
				result["status"] = "memoir_list"
				last_result = result
				return result
			"arrange_equipment":
				result["status"] = "party_equipment"
				last_result = result
				hide_now()
				arrange_equipment_requested.emit()
				return result
			"load_record":
				var records: Array = CampaignProgress.battle_record_entries()
				if records.is_empty():
					result["status"] = "no_record"
					_show_hint("沒有戰場記錄")
				else:
					var newest: Dictionary = records[0]
					result["status"] = "battle_record_resumed"
					result["scenario_path"] = str(newest.get("scenario_path", ""))
					result["title"] = str(newest.get("title", ""))
					CampaignProgress.queue_battle_record(newest)
					close()
					if runtime.is_inside_tree() and runtime.get_tree().current_scene == runtime:
						runtime.get_tree().reload_current_scene()
				last_result = result
				return result
			"options":
				_show_options()
				result["status"] = "options_shown"
				last_result = result
				return result
	match action:
		"mission":
			var view = runtime.get_node("BattlePresentation")
			var rows: Dictionary = BattleWinFailBoard.rows_for(runtime.play_loop, {}, view._board_label)
			if (rows["win"] as Array).is_empty() and (rows["fail"] as Array).is_empty():
				rows["win"] = [str(view.status_label.text)]
			_mission_board.show_rows(rows)
			_mission_text = _mission_board.row_labels[1] if _mission_board.row_labels.size() > 1 else null
			_lit.visible = false
			_mission_box.visible = true
			phase = "mission"
			result["status"] = "mission_shown"
			result["rows"] = rows
		"save_record":
			var saved: Dictionary = runtime.settlement_controller.save_battle(false)
			result["status"] = "saved" if bool(saved.get("ok", false)) else "save_refused"
			result["detail"] = saved
			if bool(saved.get("ok", false)):
				_show_save_notice()
		"load_record":
			var loaded: Dictionary = runtime.settlement_controller.load_battle()
			result["status"] = "loaded" if bool(loaded.get("ok", false)) else "load_refused"
			result["detail"] = loaded
			close()
		"load_memoir":
			# Battle item 2 opens the same Title031 load list as the world scroll (0x425842
			# calls 0x423bd0(…, 0), the world item-2 call); a chosen slot leaves the battle.
			_show_memoir_list("load")
			result["status"] = "memoir_list"
		"options":
			_show_options()
			result["status"] = "options_shown"
		"main_menu":
			result["status"] = "title"
			close()
			runtime.get_tree().change_scene_to_file(TITLE_SCENE_PATH)
		_:
			result = {"ok": false, "reason": "unknown_action", "action": action}
	last_result = result
	return result


## 進度儲存完成: fade in, hold, fade out, over the still-open scroll.
func _show_save_notice() -> void:
	if _save_notice_tween != null and _save_notice_tween.is_valid():
		_save_notice_tween.kill()
	_save_notice.modulate.a = 0.0
	_save_notice.visible = true
	_save_notice_tween = create_tween()
	_save_notice_tween.tween_property(_save_notice, "modulate:a", 1.0, SAVE_NOTICE_IN_SECONDS)
	_save_notice_tween.tween_interval(SAVE_NOTICE_HOLD_SECONDS)
	_save_notice_tween.tween_property(_save_notice, "modulate:a", 0.0, SAVE_NOTICE_OUT_SECONDS)
	_save_notice_tween.tween_callback(func() -> void: _save_notice.visible = false)


## Remake hint line (空的回憶錄, 沒有戰場記錄…): the original shows nothing; OPT-GUIDE＝提示 only.
func _show_hint(text: String) -> void:
	_hint.text = text
	_hint.visible = not GameOptions.is_original("OPT-GUIDE")
	_hint_timer.start(HINT_SECONDS)


## Keyboard and mouse while the scroll is up. Returns true when consumed.
func handle_input(event: InputEvent) -> bool:
	if not active():
		return false
	if phase in ["opening", "closing"]:
		return true
	if phase == "remake_options":
		_remake_page.handle_input(event, _logical(event.position) if event is InputEventMouse else Vector2.ZERO)
		return true
	if event is InputEventMouseMotion:
		hover_at(_logical(event.position))
		return true
	if event is InputEventMouseButton and event.pressed:
		_handle_click(event)
		return true
	if event is InputEventKey and event.pressed and not event.echo:
		_handle_key(event)
		return true
	return true


## handle_input: a pressed mouse button while the scroll is up.
func _handle_click(event: InputEventMouseButton) -> void:
	var logical: Vector2 = _logical(event.position)
	if event.button_index == MOUSE_BUTTON_RIGHT:
		_back()
	elif event.button_index == MOUSE_BUTTON_LEFT:
		match phase:
			"menu":
				if item_at(logical) >= 0:
					select(item_at(logical))
					activate()
			"confirm":
				var index := confirm_item_at(logical)
				if index >= 0:
					confirm(index == 0)
			"mission":
				_back()
			"memoir":
				if memoir_slot_at(logical) >= 0:
					select_memoir(memoir_slot_at(logical))
					activate_memoir()
			"options":
				var row := options_row_at(logical)
				if row == options_rows.size():
					select_option(row)
					adjust_option(0)
				elif row >= 0:
					select_option(row)
					var groove_x: Array = options_groove.get("x", [162, 330])
					var local_x := logical.x - _options_panel.position.x
					if local_x >= float(groove_x[0]) and local_x <= float(groove_x[1]):
						var margin := float(options_groove.get("knob_margin", 18))
						adjust_option(0, clampf((local_x - float(groove_x[0]) - margin) / (float(groove_x[1]) - float(groove_x[0]) - 2.0 * margin), 0.0, 1.0))
					else:
						adjust_option(0)


## handle_input: a pressed key (no echo) while the scroll is up.
func _handle_key(event: InputEventKey) -> void:
	match event.keycode:
		KEY_ESCAPE:
			_back()
		KEY_UP, KEY_W:
			if phase == "menu":
				select(selected - 1)
			elif phase == "memoir":
				select_memoir(memoir_selected - 1)
			elif phase == "options":
				select_option(options_selected - 1)
			elif phase == "confirm":
				confirm_selected = 0
				_show_confirm_lit(confirm_selected)
		KEY_DOWN, KEY_S:
			if phase == "menu":
				select(selected + 1)
			elif phase == "memoir":
				select_memoir(memoir_selected + 1)
			elif phase == "options":
				select_option(options_selected + 1)
			elif phase == "confirm":
				confirm_selected = 1
				_show_confirm_lit(confirm_selected)
		KEY_LEFT, KEY_A:
			if phase == "confirm":
				confirm_selected = 0
				_show_confirm_lit(confirm_selected)
			elif phase == "options":
				adjust_option(-1)
		KEY_RIGHT, KEY_D:
			if phase == "confirm":
				confirm_selected = 1
				_show_confirm_lit(confirm_selected)
			elif phase == "options":
				adjust_option(1)
		KEY_ENTER, KEY_SPACE, KEY_Z:
			match phase:
				"menu":
					activate()
				"confirm":
					confirm(confirm_selected == 0)
				"mission":
					_back()
				"memoir":
					activate_memoir()
				"options":
					adjust_option(0)


func _logical(viewport_position: Vector2) -> Vector2:
	return runtime.viewport_to_logical_position(viewport_position)


func _back() -> void:
	match phase:
		"confirm":
			confirm(false)
		"mission":
			# The board dissolves out over the scroll; the menu takes input again at once.
			_mission_board.fade_out()
			_lit.visible = true
			phase = "menu"
		"memoir", "options":
			if standalone != "":
				_close_standalone()
				return
			_memoir_box.visible = false
			_options_box.visible = false
			_lit.visible = true
			phase = "menu"
		"remake_options":
			_close_remake_options()
		"menu":
			close()


func summary() -> Dictionary:
	return {
		"schema": "hsl_battle_system_menu.v1",
		"variant": variant,
		"phase": phase,
		"memoir_mode": memoir_mode,
		"memoir_selected": memoir_selected,
		"options_selected": options_selected,
		"settings": GameSettings.load_settings(),
		"remake_options": _remake_page.summary() if _remake_page != null and _remake_page.visible else {},
		"selected": selected,
		"selected_id": str(items[selected].get("id", "")) if selected < items.size() else "",
		"confirm_selected": confirm_selected,
		"confirm_question": _confirm_question.text if _confirm_question != null and _confirm_question.visible and _confirm_box.visible else "",
		"pending_action": pending_action,
		"panel_position": _panel.position if _panel != null else Vector2.ZERO,
		"lit_visible": _lit != null and _lit.visible,
		"last_result": last_result.duplicate(true),
	}
