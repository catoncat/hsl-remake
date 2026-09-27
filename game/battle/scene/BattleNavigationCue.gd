extends Node2D
## Read-only action feedback. Motion comes from the existing ActorRuntime tween;
## a Wait has a finite visible beat before successor controls become available.
## provenance:
##   rules: n/a
##   layout: remake-invented (path／destination overlay)
##   strings: remake-invented (「待機」／「守候 · 尚餘N次」／「麻痺 · 無法行動」)
##   timing: remake-invented (0.55 s 待機／守候 beat — deliberately kept remake beat; the original shows no AI wait cue)
##   audio: n/a
const WAIT_SECONDS := 0.55
const GameOptions = preload("res://game/settings/GameOptions.gd")
var points := PackedVector2Array()
var wait_remaining := 0.0
var actor_ref: WeakRef
var caption: Label


func _ready() -> void:
	caption = Label.new()
	caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	caption.add_theme_font_size_override("font_size", 18)
	caption.add_theme_constant_override("outline_size", 4)
	caption.add_theme_color_override("font_outline_color", Color.BLACK)
	add_child(caption)
	finish()


func begin(action: Dictionary, actor: Node2D, map_config: RefCounted) -> void:
	finish()
	# OPT-GUIDE (docs/OPTIONS.md), read once per AI action: 原版 shows no wait caption, no
	# pause and no path line (the original has none of them); 提示 keeps all three.
	if GameOptions.is_original("OPT-GUIDE"):
		return
	var kind := str(action.get("kind", ""))
	if kind in ["wait", "paralysis_skip"]:
		wait_remaining = WAIT_SECONDS
		caption.text = "麻痺 · 無法行動" if kind == "paralysis_skip" else "待機"
		if kind == "wait" and action.get("wait_reason") == "wait_round":
			caption.text = "守候 · 尚餘 %d 次" % int(action["ai_decision"]["target_selection"]["wait_remaining"])
		caption.reset_size()
		caption.position = actor.position + Vector2(-caption.size.x / 2, -72)
		caption.show()
	elif kind in ["move", "move_then_attack", "move_then_item"]:
		for cell in action.get("path", []):
			points.append(map_config.grid_to_world(cell) + map_config.grid_projection["cell_size"] * 0.5)
		actor_ref = weakref(actor)
	else:
		return
	show()
	set_process(true)
	queue_redraw()


func busy() -> bool:
	return wait_remaining > 0.0


func _process(delta: float) -> void:
	if wait_remaining > 0:
		wait_remaining = maxf(0.0, wait_remaining - delta)
		if wait_remaining == 0: finish()
	elif actor_ref == null or actor_ref.get_ref() == null or not actor_ref.get_ref().is_moving():
		finish()


func finish() -> void:
	wait_remaining = 0.0
	points.clear()
	actor_ref = null
	if caption != null: caption.hide()
	hide()
	set_process(false)
	queue_redraw()


func _draw() -> void:
	if points.size() < 2: return
	draw_polyline(points, Color(1.0, 0.88, 0.48, 0.6), 2.0, true)
	draw_rect(Rect2(points[-1] - Vector2(14, 14), Vector2(28, 28)), Color(1.0, 0.88, 0.48, 0.85), false, 1.0)
