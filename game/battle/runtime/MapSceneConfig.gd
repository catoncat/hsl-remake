extends RefCounted
## provenance:
##   layout: static-derived docs/evidence_packets/static_reverse/actor_placement_initialization.md
##   layout: provisional (world size from the decoded map texture)

const SCHEMA := "hsl_map_scene_config.v1"

var scene_id: String = ""
var world_size: Vector2i = Vector2i.ZERO
var logical_viewport_size: Vector2i = Vector2i(640, 480)
var grid_projection: Dictionary = {}


static func from_texture(id: String, texture: Texture2D, viewport_size: Vector2i, projection: Dictionary) -> RefCounted:
	var config := new()
	config.scene_id = id
	config.logical_viewport_size = viewport_size
	if texture != null:
		config.world_size = Vector2i(texture.get_width(), texture.get_height())
	else:
		config.world_size = Vector2i.ZERO
	config.grid_projection = _normalize_projection(projection)
	return config


func grid_to_world(coord: Vector2i) -> Vector2:
	var origin: Vector2 = grid_projection.get("origin", Vector2.ZERO)
	var cell_size: Vector2 = grid_projection.get("cell_size", Vector2(32.0, 32.0))
	return origin + Vector2(float(coord.x) * cell_size.x, float(coord.y) * cell_size.y)


func world_to_grid(world_position: Vector2) -> Vector2i:
	var origin: Vector2 = grid_projection.get("origin", Vector2.ZERO)
	var cell_size: Vector2 = grid_projection.get("cell_size", Vector2(32.0, 32.0))
	if cell_size.x == 0.0 or cell_size.y == 0.0:
		return Vector2i.ZERO
	var local := world_position - origin
	return Vector2i(floori(local.x / cell_size.x), floori(local.y / cell_size.y))


static func _normalize_projection(projection: Dictionary) -> Dictionary:
	var next := projection.duplicate(true)
	if not next.has("origin"):
		next["origin"] = Vector2.ZERO
	if not next.has("cell_size"):
		next["cell_size"] = Vector2(32.0, 32.0)
	if not next.has("provisional"):
		next["provisional"] = true
	return next
