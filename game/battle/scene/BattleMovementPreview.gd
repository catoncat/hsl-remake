extends Node2D
## Only draws the route supplied by the same envelope used for confirmation.
## Never stores a unit, spends movement, or decides a path independently.
## provenance:
##   rules: n/a
##   layout: remake-invented (route line drawn over the shared grid projection)
##   strings: n/a
##   timing: n/a
##   audio: n/a
var points := PackedVector2Array()
var stopping := false
var body_extent := Vector2(24,24)


func present(route: Dictionary, map_config: RefCounted, can_stop: bool, footprint_radius: int = 0) -> void:
	points.clear()
	stopping = can_stop
	if route.is_empty() or map_config == null:
		hide()
		return
	body_extent = map_config.grid_projection["cell_size"] * (2 * footprint_radius + 1) - Vector2.ONE * (8 if footprint_radius == 0 else 2)
	for cell in route["path"]:
		points.append(map_config.grid_to_world(cell) + map_config.grid_projection["cell_size"] * 0.5)
	visible = points.size() > 1
	queue_redraw()


func clear() -> void:
	points.clear()
	hide()
	queue_redraw()


func _draw() -> void:
	if points.size() < 2: return
	var color := Color(1.0, 0.88, 0.48, 0.85) if stopping else Color(0.8, 0.85, 0.9, 0.7)
	draw_polyline(points, color, 2.0, true)
	for index in range(1, points.size() - 1): draw_circle(points[index], 2.0, color)
	if stopping: draw_rect(Rect2(points[-1] - body_extent / 2, body_extent), color, false, 1.0)
