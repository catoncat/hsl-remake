extends Control
## Read-only two-inventory view. Selections are intents; PlayLoop owns both bags.
## provenance:
##   layout: resource-derived content/imported/hsl/shared/panels/manifest.json
##   layout: resource-derived content/imported/hsl/chapter01/portraits/manifest.json
##   layout: remake-invented (two-bag arrangement; recording 07 shows the original hand-cursor trade, not remade)
##   strings: remake-invented (captions)
signal source_selected(index: int, code: int)
signal destination_selected(index: int, code: int)
signal back_requested
signal finish_requested
const BattleUISkin = preload("res://game/common/BattleUISkin.gd")
var source_buttons: Array[Button] = []
var destination_buttons: Array[Button] = []
static var _portraits: Dictionary = {}


static func unit_name(unit: Dictionary) -> String:
	if _portraits.is_empty():
		_portraits = preload("res://game/sim/ContentPaths.gd").actor_portraits()
	return str(_portraits[str(unit["actor_id"])]["name"])


static func fitted_board(parent: Node, at: Vector2, dimensions: Vector2) -> NinePatchRect:
	var panel := NinePatchRect.new()
	panel.texture = load(BattleUISkin.ROOT + "WINDOW20.SHP.png")
	panel.position = at
	panel.size = dimensions
	panel.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
		panel.set_patch_margin(side, 8)
	panel.axis_stretch_horizontal = NinePatchRect.AXIS_STRETCH_MODE_TILE
	panel.axis_stretch_vertical = NinePatchRect.AXIS_STRETCH_MODE_TILE
	parent.add_child(panel)
	return panel


func show_inventories(sender: Dictionary, receiver: Dictionary, catalog: Dictionary, selected: int) -> void:
	size = Vector2(640, 480)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	BattleUISkin.clear_panel(self)
	var heading := BattleUISkin.label(self, Vector2(22, 18), 19)
	heading.text = "選擇給出的道具" if selected < 0 else "選擇對方的空位或交換道具"
	for column in range(2):
		var unit: Dictionary = sender if column == 0 else receiver
		var x := 12 + column * 314
		fitted_board(self, Vector2(x, 55), Vector2(302, 367))
		var name_label := BattleUISkin.label(self, Vector2(x + 14, 68), 17)
		name_label.text = "%s  %d/8" % [unit_name(unit), 8 - unit["inventory"].count(0)]
		name_label.size = Vector2(276, 26)
		name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		for index in range(8):
			var code := int(unit["inventory"][index])
			var button := Button.new()
			button.name = ("Source_" if column == 0 else "Destination_") + str(index)
			button.position = Vector2(x + 12, 100 + index * 38)
			button.size = Vector2(278, 35)
			button.text = str(catalog[str(code)]["name"]) if code > 0 else "空位"
			button.alignment = HORIZONTAL_ALIGNMENT_LEFT
			button.add_theme_font_size_override("font_size", 17)
			button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
			button.set_meta("inventory_index", index)
			button.set_meta("item_code", code)
			for state in ["normal", "hover", "pressed", "disabled", "focus"]:
				var style := StyleBoxFlat.new()
				style.bg_color = Color(0, 0, 0, 0.14)
				style.border_color = Color(0.9, 0.8, 0.4, 0.8)
				style.set_border_width_all(1 if state in ["hover", "focus"] or (column == 0 and index == selected) else 0)
				style.content_margin_left = 43
				button.add_theme_stylebox_override(state, style)
			add_child(button)
			if code > 0:
				BattleUISkin.asset(button, str(catalog[str(code)]["icon"]), Vector2(4, 1))
			if column == 0:
				button.disabled = code == 0
				button.pressed.connect(func(): source_selected.emit(index, code))
				source_buttons.append(button)
			else:
				button.disabled = selected < 0
				button.pressed.connect(func(): destination_selected.emit(index, code))
				destination_buttons.append(button)
	BattleUISkin.button(self, "選擇同伴", Vector2(18, 438), Vector2(148, 34)).pressed.connect(func(): back_requested.emit())
	BattleUISkin.button(self, "結束給予", Vector2(474, 438), Vector2(148, 34)).pressed.connect(func(): finish_requested.emit())
