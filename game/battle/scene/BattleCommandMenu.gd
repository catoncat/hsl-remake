extends Control
## provenance:
##   layout: resource-derived content/imported/hsl/shared/command_menu/manifest.json
##   layout: static-derived content/imported/hsl/shared/command_menu/native_layout.json
##   layout: static-derived docs/evidence_packets/static_reverse/presentation_source_recovery.md
##     (0x43ea30 command strings 0x4784fc..0x478554: nopqzvw, rtus)
##   layout: static-derived docs/evidence_packets/static_reverse/native_presentation_helpers.md
##     (0x43ec29..0x43edc1 map-edge shift of icon targets; captions 0x43e5d0 message −1, centre y+13)
##   strings: resource-derived content/imported/hsl/global/tables/OBJ-ALL.H
##   strings: resource-derived content/imported/hsl/global/tables/resource.h
##     (obj-051.obs obj_Data9 bcommand_0..12 → RESOURCE ids 17..20／23..26／28／29／40)
##   timing: static-derived docs/evidence_packets/static_reverse/native_presentation_helpers.md
##   timing: static-derived docs/evidence_packets/runtime_observations/original_tick_rate/README.md
signal command_selected(command_id: String)
## Presentation only. Icon identity comes from BCMD resources and original captures.
## Radial order is the 0x43ea30 UTF-16 command strings (nopqzvw: move, attack, item, wait,
## status, magic, special; rtus for the item submenu). Edge fitting is the native map-edge shift.
## Captions are the RESOURCE strings the original draws under every icon (0x43e5d0, message −1).
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
const PresentationRules = preload("res://game/battle/runtime/CommandPresentationRules.gd")
const ContentPaths = preload("res://game/sim/ContentPaths.gd")
const InterfaceArt = preload("res://game/common/InterfaceArt.gd")
const RADIAL_ORDER := ["move", "attack", "item", "wait", "status", "magic", "special", "use", "equip", "drop", "give"]
## Source frame sequences advance once per original tick (seven calls per hover frame).
const OriginalTick = preload("res://game/common/OriginalTick.gd")
const HOVER_UPDATES_PER_SECOND := OriginalTick.TICKS_PER_SECOND
## 0x43eca2／0x43ecbd: icon centres keep 0x15 px (half the 42 px icon) inside the map.
const EDGE_MARGIN := 0x15
var frames: Dictionary = {}
var looped: Dictionary = {}
var hovered := ""
var hover_elapsed := 0.0
var centers: Dictionary = {}
## Unshifted native offsets from the ring centre; `centers` = these minus the map-edge shift.
var ring_offsets: Dictionary = {}
var gui_interaction := false
var displayed_centers: Dictionary = {}
## Caption colours: RGB565 0xffff／0x8430 (idle) and 0xffef／0x8420 (hovered) as displayed.
const CAPTION_COLOR := Color8(248, 252, 248)
const CAPTION_SHADOW := Color8(128, 132, 128)
const CAPTION_HOVER_COLOR := Color8(248, 252, 120)
const CAPTION_HOVER_SHADOW := Color8(128, 132, 0)
## The caption box is centred on the icon centre; its top is the FONT.15 cell top (centre y+13).
const CAPTION_SIZE := Vector2(88, 16)
const CAPTION_TOP := 13.0
var _opening := false
var _opening_fraction := 0.0


func _ready() -> void:
	var data: Dictionary = ContentPaths.read_json(FRAME_PATH)
	for id in data["commands"]:
		frames[id] = []
		looped[id] = bool(data["commands"][id]["looped"])
		for frame in data["commands"][id]["frames"]:
			frames[id].append(InterfaceArt.texture(frame["res_path"]))
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
	ring_offsets.clear()
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
		ring_offsets[active_ids[i]] = offsets[i]
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
		var label := Label.new()
		label.name = "Caption"
		label.text = spec[1]
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		label.add_theme_font_size_override("font_size", 14)
		label.add_theme_constant_override("shadow_offset_x", 1)
		label.add_theme_constant_override("shadow_offset_y", 1)
		label.add_theme_constant_override("shadow_outline_size", 0)
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
			label.position = Vector2(side * 0.5 - CAPTION_SIZE.x * 0.5, side * 0.5 + CAPTION_TOP)
			label.size = CAPTION_SIZE
			label.add_theme_color_override("font_color", CAPTION_HOVER_COLOR if active else CAPTION_COLOR)
			label.add_theme_color_override("font_shadow_color", CAPTION_HOVER_SHADOW if active else CAPTION_SHADOW)


func layout_bounds() -> Rect2:
	# Full expanded footprint, including the largest hover icon and captions.
	var bounds := Rect2()
	for button in get_children():
		var id := str(button.name).trim_suffix("Command").to_lower()
		var footprint := Rect2(centers[id] + Vector2(-44, -29), Vector2(88, 80))
		bounds = footprint if bounds.size == Vector2.ZERO else bounds.merge(footprint)
	return bounds


## 0x43ea30 places the ring centre at the owner (foot point − 28 in y) and spawns every icon
## there; only the icon targets move: one shift per axis, taken over all icon centres, pulls any
## centre within 0x15 px of the map edge (0, *0x4c0934／38 << 5) back inside (0x43eca2..0x43ed06;
## the right／bottom test runs after the left／top one and wins only when larger), then
## 0x43edae..0x43edb5 subtract it from +0x9e／+0x9c. The viewport is not consulted: 0x443a1d
## (0x43bf30) centres the camera on the owner first. `map_area` is the map in the same
## coordinates as `anchor`.
func place_near(anchor: Vector2, map_area: Rect2) -> void:
	position = anchor + Vector2(0, PresentationRules.data()["center_y"])
	var shift := Vector2.ZERO
	var margin := float(EDGE_MARGIN)
	for id in ring_offsets:
		var point: Vector2 = position + ring_offsets[id] - map_area.position
		for axis in 2:
			if point[axis] < margin and point[axis] - margin < shift[axis]:
				shift[axis] = point[axis] - margin
			if point[axis] > map_area.size[axis] - margin and point[axis] - map_area.size[axis] + margin > shift[axis]:
				shift[axis] = point[axis] - map_area.size[axis] + margin
	for id in ring_offsets:
		centers[id] = ring_offsets[id] - shift
	if not _opening:
		for id in centers:
			displayed_centers[id] = centers[id]
	set_hovered_command(hovered)


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
