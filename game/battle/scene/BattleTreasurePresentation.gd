extends Node
## Shows committed discoveries only. No inventory, RNG, turn or treasure state
## is created here. A visible chest under the original value is disposed at once; a hidden chest
## and every chest under 全部畫出 get a short remake fade.
## Hidden treasure (chest `hidden`: template obj_Attribute without objattrATTACKFLAG) is not
## drawn and gives no hover hint; its discovery plays sfxGetTreasure like 0x445526.
## provenance:
##   rules: static-derived docs/evidence_packets/static_reverse/original_treasure.md
##     (hidden chests not drawn: 0x415730 shape word 0xffff)
##   layout: resource-derived content/imported/hsl/chapter01/map_objects.json
##   layout: remake-invented (discovery caption and hover hint, OPT-TREASURE=全部畫出 only)
##   strings: remake-invented (discovery text and hover hint, OPT-TREASURE=全部畫出 only)
##   timing: remake-invented
##     (0.45 s fade: hidden chests and OPT-TREASURE=全部畫出 only; original value disposes a visible chest at once,
##     original_treasure.md)
##   audio: static-derived docs/evidence_packets/static_reverse/original_treasure.md
##     (hidden chest: 0x4477b0(0xa05) sfxGetTreasure before 0x4156d0)
##   audio: remake-invented
##     (shown chest accept sound, OPT-TREASURE=全部畫出 only; the original plays nothing for a visible chest,
##     0x445526 → 0x4156d0)
const Interaction = preload("res://game/sim/Interaction.gd")
const LoopKeys = preload("res://game/sim/LoopKeys.gd")
const DURATION := 0.45
## The one read point for whether hidden chests are drawn. false = original (hidden
## treasure stays undrawn until found; no discovery caption, hover hint or accept sound — a
## visible chest is disposed silently, 0x445526); true draws every chest closed and restores the
## caption, hover hint and accept sound for all of them.
var reveal_all_chests := false
var runtime: Node
var shown_sequence := 0
var _active_sequence := 0
var _remaining := 0.0
var _fading: Array[CanvasItem] = []
var label: Label


func _ready() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 4
	add_child(layer)
	label = Label.new()
	label.position = Vector2(20, 42)
	label.size = Vector2(600, 36)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 20)
	label.add_theme_constant_override("outline_size", 5)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(label)
	label.hide()
	sync_boxes()


func busy() -> bool:
	return _remaining > 0.0


func hide_hint() -> void:
	if not busy() and label != null: label.hide()


func tick(delta: float) -> bool:
	if not runtime.play_loop.has("treasure_source"): return false
	if busy():
		_remaining = maxf(0.0, _remaining - delta)
		for sprite in _fading:
			if is_instance_valid(sprite): sprite.modulate.a = _remaining / DURATION
		if not busy():
			shown_sequence = _active_sequence
			label.hide()
			sync_boxes()
		return true
	var view: Node = runtime.get_node("BattlePresentation")
	if runtime.interaction_state == Interaction.OPENING_TIMELINE or runtime.ScriptPresentation.active(runtime) or runtime.ScriptPresentation.pending(runtime) or runtime.has_actor_motion() or view.combat_busy(runtime.play_loop) or view.dialogue_active() or view.item_feedback_busy(): return false
	var records: Array = runtime.play_loop.get(LoopKeys.TREASURES, {}).get("receipts", [])
	if records.size() > shown_sequence:
		var receipt: Dictionary = records[shown_sequence]
		_active_sequence = int(receipt["sequence"])
		var found_hidden: bool = runtime.play_loop[LoopKeys.TREASURE_SOURCE]["chests"].any(func(chest): return receipt["chest_ids"].has(chest["id"]) and not chest_drawn(chest))
		# Original (0x445526 → 0x4156d0): a visible chest is disposed at once — no fade, no wait,
		# no caption, no sound. The fade and its wait are the 全部畫出 remake beat.
		if not reveal_all_chests and not found_hidden:
			shown_sequence = _active_sequence
			sync_boxes()
			return false
		_remaining = DURATION
		_fading.clear()
		for chest in runtime.play_loop[LoopKeys.TREASURE_SOURCE]["chests"]:
			if receipt["chest_ids"].has(chest["id"]): _fading.append_array(box_nodes(chest))
		label.text = "發現寶藏 · %d 件物品" % receipt["items"].size()
		label.visible = reveal_all_chests
		runtime.camera_controller.scroll_to_grid(receipt["coord"])
		if found_hidden: runtime.play_ui_sound("get_treasure")
		elif reveal_all_chests: runtime.play_ui_sound("confirm")
		return true
	sync_boxes()
	var actor: Dictionary = runtime.BattlePlayLoop.unit(runtime.play_loop, str(runtime.play_loop.get(LoopKeys.SELECTED_UNIT_ID, "")))
	if runtime.interaction_state in [Interaction.ACTION_MENU, Interaction.MOVE_SELECT] and not actor.is_empty() and not runtime.modal_open() and not view.battle_finished:
		var coord: Vector2i = runtime.hovered_grid_cell if runtime.interaction_state == Interaction.MOVE_SELECT else actor["coord"]
		var chest: Dictionary = runtime.BattlePlayLoop.Treasure.chest_at(runtime.play_loop, coord)
		if reveal_all_chests and not chest.is_empty() and chest_drawn(chest):
			label.text = "寶藏：停留此格，完成行動後領取"
			label.show()
	return false


func chest_drawn(chest: Dictionary) -> bool:
	return reveal_all_chests or not chest["hidden"]


func box_nodes(chest: Dictionary) -> Array[CanvasItem]:
	var result: Array[CanvasItem] = []
	for layer in [runtime.map_objects_back, runtime.map_objects_foreground]:
		for node in layer.get_children():
			if node is CanvasItem and node.get_meta("record_index", -1) == chest["record_index"] and node.get_meta("shape_resource_id", "") == chest["shape_resource_id"]:
				result.append(node)
	return result


func sync_boxes() -> void:
	var opened: Array = []
	var records: Array = runtime.play_loop.get(LoopKeys.TREASURES, {}).get("receipts", [])
	for i in range(mini(shown_sequence, records.size())): opened.append_array(records[i]["chest_ids"])
	for chest in runtime.play_loop.get(LoopKeys.TREASURE_SOURCE, {}).get("chests", []):
		for sprite in box_nodes(chest):
			sprite.modulate.a = 1.0
			sprite.visible = chest_drawn(chest) and not opened.has(chest["id"])


func restore(sequence: int) -> void:
	_remaining = 0.0
	_fading.clear()
	shown_sequence = sequence
	_active_sequence = sequence
	label.hide()
	sync_boxes()
