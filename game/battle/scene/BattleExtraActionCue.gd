extends CanvasLayer
## Read-only second-action cue; the PlayLoop owns the grant and saved latch.
## provenance:
##   layout: remake-invented (caption outside the menu footprint)
##   strings: remake-invented (「再次行動」)
##   timing: remake-invented
##     (0.55 s input block before the second action — deliberately kept remake beat; the original has no 再次行動 cue.
##     Ablation: with 0 only its own assertion fails, the flow does not need it)
const Interaction = preload("res://game/sim/Interaction.gd")
const LoopKeys = preload("res://game/sim/LoopKeys.gd")
const BattleOutcome = preload("res://game/sim/BattleOutcome.gd")
const DURATION := 0.55
const GameOptions = preload("res://game/settings/GameOptions.gd")
## OPT-GUIDE (docs/OPTIONS.md), read once as each second action comes up: 原版 shows no
## 再次行動 and does not pause (the original has neither); 提示 shows it and holds DURATION.
var hints := false
var shown_sequence := 0
var remaining := 0.0
var label: Label


func _ready() -> void:
	layer = 3
	label = Label.new()
	label.text = "再次行動"
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", 20)
	label.add_theme_constant_override("outline_size", 4)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	add_child(label)
	label.hide()


func pending(loop: Dictionary) -> bool:
	var state: Dictionary = loop.get("extra_action", {})
	return bool(state.get("pending", false)) and int(state.get("sequence", 0)) > shown_sequence and not BattleOutcome.decided(loop)


func busy(loop: Dictionary) -> bool:
	return pending(loop) or remaining > 0


func refresh(loop: Dictionary, point: Vector2, allowed: bool, delta: float, menu_bounds: Rect2 = Rect2()) -> void:
	if not loop.get("extra_action", {}).get("pending", false) or BattleOutcome.decided(loop):
		remaining = 0
		label.hide()
		return
	if not allowed:
		label.hide()
		return
	if pending(loop):
		shown_sequence = int(loop["extra_action"]["sequence"])
		hints = not GameOptions.is_original("OPT-GUIDE")
		remaining = DURATION if hints else 0.0
	else:
		remaining = maxf(0, remaining - maxf(0, delta))
	var size := label.get_combined_minimum_size()
	var position := Vector2(clampf(point.x - size.x / 2, 8, 632 - size.x), clampf(point.y - 94, 8, 472 - size.y))
	if menu_bounds.size != Vector2.ZERO and Rect2(position, size).grow(6).intersects(menu_bounds):
		var above := menu_bounds.position.y - size.y - 8
		position.y = above if above >= 8 else menu_bounds.end.y + 8
	label.position = position
	label.visible = hints and loop.get(LoopKeys.INTERACTION) in [Interaction.ACTION_MENU, Interaction.AI_RESOLVING]


func finish(loop: Dictionary) -> void:
	# Loading an older snapshot must also rewind this presentation cursor.
	shown_sequence = int(loop.get("extra_action", {}).get("sequence", 0))
	remaining = 0
	label.hide()
