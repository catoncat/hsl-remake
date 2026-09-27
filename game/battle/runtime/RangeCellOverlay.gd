extends Node2D
## The original's range-cell art under World/MoveOverlay: every marked 32 px cell is the
## palette's colour ramp averaged 50／50 over the map (the drawers blit the solid
## ICONBOX.SHP in mode 6) under the opaque I_rect border frame. One child per cell; the
## caller (BattleSceneOverlays) decides which cells and which palette, this node only
## paints and pulses them. Cell geometry is taken from the caller — hit-test and
## projection are not touched here (spatial contract). The static fill_color／border_sheet／
## border_region give the same look to BattleAttackCue, which draws the AI lead-in's cells.
## provenance:
##   layout: resource-derived content/imported/hsl/shared/range_cells/manifest.json
##   layout: static-derived docs/evidence_packets/static_reverse/original_range_cells.md
##   layout: runtime-measured docs/evidence_packets/static_reverse/original_range_cells.md#证据
##     (border pixels and averaged fill match the sampled original frame)
##   layout: remake-invented (add_marked_cells: the caller-styled outlined cells of the skill footprint preview)
##   timing: static-derived docs/evidence_packets/static_reverse/original_range_cells.md
##   timing: runtime-measured docs/evidence_packets/static_reverse/original_range_cells.md#证据
##     (pulse counter 0x4c1a7c walks the 17-value triangle live)

const OriginalTick = preload("res://game/common/OriginalTick.gd")
const ContentPaths = preload("res://game/sim/ContentPaths.gd")

const MANIFEST_PATH := "res://content/imported/hsl/shared/range_cells/manifest.json"
const PALETTES: PackedStringArray = ["move", "attack", "magic", "special"]
## Blit mode 6 averages destination and colour, so the ramp shows at half strength.
const FILL_ALPHA := 0.5

static var _manifest: Dictionary = {}
static var _border_sheets: Dictionary = {}

## Border frame period in ticks set before the node enters the tree; 0 keeps the manifest's
## (8, the range drawers). obj_Story_Show_Pos markers use 6 (OpeningStoryObjects).
var frame_ticks: int = 0

var _palette_ramps: Dictionary = {}
var _palette_sheets: Dictionary = {}
var _frame_count: int = 8
var _frame_ticks: int = 8
var _pulse_indices: Array = []
var _elapsed_ticks: float = 0.0
var _tick: int = 0


static func manifest() -> Dictionary:
	if _manifest.is_empty():
		var parsed: Variant = ContentPaths.read_json(MANIFEST_PATH)
		assert(parsed is Dictionary and (parsed as Dictionary).has("palettes"), "range cell manifest missing: " + MANIFEST_PATH)
		_manifest = parsed
	return _manifest


## One cell's look at running tick `tick`, for a caller that draws its own cells (the AI
## lead-in, BattleAttackCue): the half-strength ramp colour of the 17-tick pulse, the border
## sheet and the frame of it (every 8 ticks), as the nodes below paint them.
static func fill_color(palette: String, tick: int) -> Color:
	var data := manifest()
	var indices: Array = data["pulse"]["indices"]
	var rgb: Array = data["palettes"][palette]["ramp_rgb"][absi(int(indices[posmod(tick, indices.size())]))]
	return Color8(int(rgb[0]), int(rgb[1]), int(rgb[2]), int(round(FILL_ALPHA * 255.0)))


static func border_sheet(palette: String) -> Texture2D:
	if not _border_sheets.has(palette):
		_border_sheets[palette] = load(str(manifest()["palettes"][palette]["border_sheet"]))
	return _border_sheets[palette]


static func border_region(palette: String, tick: int) -> Rect2:
	var entry: Dictionary = manifest()["palettes"][palette]
	var px := float(manifest()["cell_px"])
	return Rect2(float(posmod(tick / int(entry["frame_ticks"]), int(entry["frame_count"]))) * px, 0.0, px, px)


func _ready() -> void:
	var data := manifest()
	_pulse_indices = data["pulse"]["indices"]
	for palette in PALETTES:
		var entry: Dictionary = data["palettes"][palette]
		var ramp: Array[Color] = []
		for rgb in entry["ramp_rgb"]:
			ramp.append(Color8(int(rgb[0]), int(rgb[1]), int(rgb[2]), int(round(FILL_ALPHA * 255.0))))
		_palette_ramps[palette] = ramp
		_palette_sheets[palette] = load(str(entry["border_sheet"]))
		_frame_count = int(entry["frame_count"])
		_frame_ticks = int(entry["frame_ticks"])
	if frame_ticks > 0:
		_frame_ticks = frame_ticks


## Adds one cell node per top-left／size pair under `name_prefix` ("MoveCell", "AttackCell").
func add_cells(name_prefix: String, cell_rects: Array[Rect2], palette: String) -> void:
	assert(PALETTES.has(palette), "unknown range palette: " + palette)
	for index in range(cell_rects.size()):
		var cell := Node2D.new()
		cell.name = "%s%02d" % [name_prefix, index]
		cell.set_meta("palette", palette)
		var rect: Rect2 = cell_rects[index]
		var fill := Polygon2D.new()
		fill.name = "Fill"
		fill.polygon = PackedVector2Array([rect.position, rect.position + Vector2(rect.size.x, 0.0), rect.end, rect.position + Vector2(0.0, rect.size.y)])
		cell.add_child(fill)
		var border := Sprite2D.new()
		border.name = "Border"
		border.texture = _palette_sheets[palette]
		border.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		border.centered = false
		border.hframes = _frame_count
		border.position = rect.position
		border.scale = rect.size / Vector2(float(manifest()["cell_px"]), float(manifest()["cell_px"]))
		cell.add_child(border)
		add_child(cell)
		_paint(cell)


## Adds one outlined cell per rect under `name_prefix` in a caller-chosen style (the skill
## footprint preview): a flat `fill` under a `width` px `edge` outline, drawn above the
## palette cells added earlier; these cells keep their colours (no pulse, no I_rect frame).
func add_marked_cells(name_prefix: String, cell_rects: Array[Rect2], fill: Color, edge: Color, width: float) -> void:
	for index in range(cell_rects.size()):
		var rect: Rect2 = cell_rects[index]
		var cell := Node2D.new()
		cell.name = "%s%02d" % [name_prefix, index]
		cell.set_meta("marked", true)
		cell.position = rect.position
		var inset := width / 2.0
		var corners := PackedVector2Array([Vector2(inset, inset), Vector2(rect.size.x - inset, inset), Vector2(rect.size.x - inset, rect.size.y - inset), Vector2(inset, rect.size.y - inset)])
		var body := Polygon2D.new()
		body.name = "Fill"
		body.polygon = PackedVector2Array([Vector2.ZERO, Vector2(rect.size.x, 0.0), rect.size, Vector2(0.0, rect.size.y)])
		body.color = fill
		cell.add_child(body)
		var outline := Line2D.new()
		outline.name = "Edge"
		outline.points = corners
		outline.closed = true
		outline.width = width
		outline.default_color = edge
		outline.joint_mode = Line2D.LINE_JOINT_SHARP
		cell.add_child(outline)
		add_child(cell)


func clear_cells(name_prefix: String) -> void:
	for child in get_children():
		if str(child.name).begins_with(name_prefix):
			remove_child(child)
			child.free()


func clear_all_cells() -> void:
	for child in get_children():
		remove_child(child)
		child.free()


func _process(delta: float) -> void:
	if not visible or get_child_count() == 0:
		return
	_elapsed_ticks += OriginalTick.ticks(delta)
	var steps := floori(_elapsed_ticks)
	if steps <= 0:
		return
	_elapsed_ticks -= float(steps)
	_tick += steps
	for child in get_children():
		_paint(child)


## The original re-evaluates the ramp index and the frame timer each drawn tick; both are
## derived here from one running tick so an added cell joins the pulse in phase.
func _paint(cell: Node) -> void:
	if cell.has_meta("marked"): return
	var palette: String = str(cell.get_meta("palette"))
	var ramp: Array[Color] = _palette_ramps[palette]
	var pulse_index: int = absi(int(_pulse_indices[_tick % _pulse_indices.size()]))
	(cell.get_node("Fill") as Polygon2D).color = ramp[pulse_index]
	(cell.get_node("Border") as Sprite2D).frame = (_tick / _frame_ticks) % _frame_count
