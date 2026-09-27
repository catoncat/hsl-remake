extends Control
## provenance:
##   rules: n/a
##   layout: resource-derived content/imported/hsl/shared/command_menu/manifest.json; static-derived content/imported/hsl/shared/command_menu/native_layout.json; static-derived docs/evidence_packets/static_reverse/presentation_source_recovery.md (0x43ea30 command strings 0x4784fc..0x478554: nopqzvw, rtus); remake-invented (viewport clamping, caption placement)
##   strings: resource-derived content/imported/hsl/global/tables/OBJ-ALL.H; remake-invented (Chinese captions under the icons, drawn only under OPT-GUIDE 提示 — the original ring is icons only)
##   timing: static-derived docs/evidence_packets/static_reverse/native_presentation_helpers.md; static-derived docs/evidence_packets/runtime_observations/original_tick_rate/README.md
##   audio: n/a
signal command_selected(command_id: String)
## Presentation only. Icon identity comes from BCMD resources and original captures.
## Radial order is the 0x43ea30 UTF-16 command strings (nopqzvw: move, attack, item, wait,
## status, magic, special; rtus for the item submenu); edge fitting favors readable captions.
const COMMANDS := {
	"move": ["BCMD01_1", "移動"],
	"attack": ["BCMD02_1", "攻擊"],
	"special": ["BCMD10_1", "特殊技"],
	"magic": ["BCMD09_1", "魔法"],
	"item": ["BCMD03_1", "道具"],
	"status": ["BCMD13_1", "狀態"],
	"wait": ["BCMD04_1", "待機"],
	"use": ["BCMD05_1", "使用"],
	"give": ["BCMD06_1", "交換"],
	"equip": ["BCMD07_1", "裝備"],
	"drop": ["BCMD08_1", "丟棄"],
}
const FRAME_PATH := "res://content/imported/hsl/shared/command_menu/manifest.json"
const GameOptions = preload("res://game/settings/GameOptions.gd")
const PresentationRules = preload("res://game/battle/runtime/CommandPresentationRules.gd")
const RADIAL_ORDER := ["move", "attack", "item", "wait", "status", "magic", "special", "use", "equip", "drop", "give"]
## Source frame sequences advance once per original tick (seven calls per hover frame).
const OriginalTick = preload("res://game/battle/runtime/OriginalTick.gd")
const HOVER_UPDATES_PER_SECOND := OriginalTick.TICKS_PER_SECOND
var frames: Dictionary = {}
var looped: Dictionary = {}
var hovered := ""
var hover_elapsed := 0.0
var centers: Dictionary = {}
var gui_interaction := false
var displayed_centers: Dictionary = {}
## OPT-GUIDE (docs/OPTIONS.md), read once per ring (rebuild): 提示 puts the caption under each
## icon, below its hover size so it never covers icon pixels; 原版 draws the icons only.
var captions := false
var _opening := false
var _opening_fraction := 0.0


func _ready() -> void:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(FRAME_PATH))
	for id in data["commands"]:
		frames[id] = []
		looped[id] = bool(data["commands"][id]["looped"])
		for frame in data["commands"][id]["frames"]:
			frames[id].append(load(frame["res_path"]))
	visibility_changed.connect(_visibility_changed)


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	if _opening:
		_opening_fraction += maxf(0, delta) * HOVER_UPDATES_PER_SECOND
		while _opening and _opening_fraction >= 1.0:
			_opening_fraction -= 1.0
			_opening = false
			for id in centers:
				displayed_centers[id] = Vector2(PresentationRules.opening_step(Vector2i(displayed_centers[id]), Vector2i(centers[id])))
				_opening = _opening or displayed_centers[id] != centers[id]
		set_hovered_command(hovered)
		return
	if hovered == "":
		return
	hover_elapsed += maxf(0, delta)
	var button := get_node_or_null(hovered.capitalize() + "Command") as TextureButton
	if button != null and not button.disabled:
		button.texture_normal = frames[hovered][PresentationRules.frame_at(frames[hovered].size(), int(hover_elapsed * HOVER_UPDATES_PER_SECOND), looped[hovered])]


func rebuild(commands: Array) -> void:
	for child in get_children():
		remove_child(child)
		child.free()
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	centers.clear()
	captions = not GameOptions.is_original("OPT-GUIDE")
	var active_ids: Array[String] = []
	for id in RADIAL_ORDER:
		for command in commands:
			if str(command.get("command", "")) == id:
				active_ids.append(id)
	# Original full and post-move captures redistribute remaining commands around
	# the actor. Do not leave gaps at the removed commands' six-slot coordinates.
	var offsets: Array[Vector2] = []
	if not active_ids.is_empty():
		offsets = PresentationRules.centers(active_ids.size())
	for i in range(active_ids.size()):
		centers[active_ids[i]] = offsets[i]
	for command in commands:
		var id := str(command.get("command", ""))
		if not COMMANDS.has(id):
			continue
		var spec: Array = COMMANDS[id]
		var button := TextureButton.new()
		button.name = "%sCommand" % id.capitalize()
		button.texture_normal = frames[id][0]
		button.ignore_texture_size = true
		button.stretch_mode = TextureButton.STRETCH_SCALE
		button.disabled = not bool(command.get("enabled", true))
		button.mouse_filter = Control.MOUSE_FILTER_STOP if gui_interaction else Control.MOUSE_FILTER_IGNORE
		if gui_interaction:
			button.pressed.connect(func():
				if not _opening: command_selected.emit(id))
			button.mouse_entered.connect(set_hovered_command.bind(id))
			button.mouse_exited.connect(set_hovered_command.bind(""))
		button.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		if captions:
			var label := Label.new()
			label.name = "Caption"
			label.text = spec[1]
			label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			label.mouse_filter = Control.MOUSE_FILTER_IGNORE
			label.add_theme_font_size_override("font_size", 14)
			label.add_theme_constant_override("outline_size", 2)
			label.add_theme_color_override("font_outline_color", Color.BLACK)
			button.add_child(label)
		add_child(button)
	_begin_opening()


func set_hovered_command(command_id: String) -> void:
	if command_id != hovered:
		hovered = command_id
		hover_elapsed = 0.0
	for button in get_children():
		var id := str(button.name).trim_suffix("Command").to_lower()
		var active: bool = id == command_id and not button.disabled and not _opening
		if not active and frames.has(id):
			button.texture_normal = frames[id][0]
		var side := 42.0 * float(PresentationRules.data()["hover_scale_fixed"]) / 65536.0 if active else 42.0
		button.size = Vector2(side, side)
		button.position = displayed_centers.get(id, centers[id]) - button.size * 0.5
		button.modulate = Color(1, 1, 1, 0.4 if button.disabled else 1.0)
		var label := button.get_node_or_null("Caption") as Label
		if label != null:
			label.position = Vector2((side - 88) * 0.5, side + 2)
			label.size = Vector2(88, 20)
			label.add_theme_color_override("font_color", Color.YELLOW if active else Color.WHITE)


func layout_bounds() -> Rect2:
	# Full expanded footprint, including the largest hover icon and captions.
	var bounds := Rect2()
	for button in get_children():
		var id := str(button.name).trim_suffix("Command").to_lower()
		var footprint := Rect2(centers[id] + Vector2(-44, -29), Vector2(88, 80))
		bounds = footprint if bounds.size == Vector2.ZERO else bounds.merge(footprint)
	return bounds


func place_near(anchor: Vector2, visible_area: Rect2) -> void:
	var bounds := layout_bounds()
	# Native full/five-item samples center the ring roughly one tile above the foot.
	position = (anchor + Vector2(0, PresentationRules.data()["center_y"])).clamp(visible_area.position - bounds.position, visible_area.end - bounds.end)


func is_expanding() -> bool:
	return _opening and is_visible_in_tree()


func _begin_opening() -> void:
	displayed_centers.clear()
	for id in centers:
		displayed_centers[id] = Vector2.ZERO
	_opening = not centers.is_empty()
	_opening_fraction = 0.0
	hovered = ""
	hover_elapsed = 0.0
	set_hovered_command("")


func _visibility_changed() -> void:
	# Reopening an existing menu is a new expansion, not a continuation of a
	# hidden animation. Repeated show/anchor refreshes do not emit this signal.
	if is_visible_in_tree():
		_begin_opening()
	else:
		set_hovered_command("")
