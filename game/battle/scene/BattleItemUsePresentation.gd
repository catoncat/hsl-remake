extends Node2D
## One item use on the map, replayed from its immutable use receipt (PlayLoop already holds the
## settled HP／MP). The player's pick (states 0x69／0x6a／108) and the AI (state word 0xc,
## low-word states 7–0xe, table 0x4422a0) run the same beats; only the AI has the lead-in:
##   lead   — BattleAttackCue.begin_item: camera to the user, 12 ticks of the use range with the
##            cursor on the user, the cursor glide, 12 ticks on the lit target;
##   effect — the user's use_magic pose (0x4071e0), sfxUseItem (0x409e40 → 0x40a349) and
##            0x408b20's Show_Magic_Star objects at the target (x, y − 0x34); the first one
##            spawned carries the wait reference and releases the action when it is deleted;
##   numbers — 0x43b3f0's small HP／MP bars under the target and the green／blue numbers at
##            (x, y − 0x30); the last number releases the action on its 32nd tick and 0x43b4c0
##            drops the bars.
## provenance:
##   layout: static-derived docs/evidence_packets/static_reverse/original_item_use_presentation.md
##     (effect point, burst directions and motion, bar docking)
##   layout: resource-derived content/imported/hsl/shared/skill_effects/manifest.json (WAT04／WAT01 frames)
##   layout: resource-derived content/imported/hsl/shared/reward_floats/manifest.json (NUM510)
##   layout: resource-derived content/imported/hsl/shared/panels/manifest.json (BAR_HP4..6)
##   layout: provisional
##     (range cells: the user's cell and its four neighbours without a hostile occupant; bar y cap at map height − 36;
##     the bars' cur/max text is not drawn)
##   timing: static-derived docs/evidence_packets/static_reverse/original_item_use_presentation.md
##     (12／12 lead ticks, 25-tick effect stagger, 16 sparks 1..3 ticks apart × 24 ticks, 32-tick flash, number release)
##   audio: static-derived docs/evidence_packets/static_reverse/first_battle_audio.md
##     (sfxUseItem 402 = WAV\MHEAL001.WAV, played by 0x409e40 as the item applies)
const OriginalTick = preload("res://game/battle/runtime/OriginalTick.gd")
const ResultNumberFloat = preload("res://game/battle/scene/ResultNumberFloat.gd")
const BattleRewardFloat = preload("res://game/battle/scene/BattleRewardFloat.gd")
const BattleUISkin = preload("res://game/battle/scene/BattleUISkin.gd")
const Footprint = preload("res://game/sim/FootprintRules.gd")
const ActorRoleRules = preload("res://game/sim/ActorRoleRules.gd")
const LoopKeys = preload("res://game/sim/LoopKeys.gd")
const Timing = preload("res://game/battle/runtime/CombatPresentationTiming.gd")
const MANIFEST := "res://content/imported/hsl/shared/skill_effects/manifest.json"

## 0x409e98: 0x408b20 gets (x, y − 0x34); 0x409eb6 lifts it 16 more for a large target (0x446ad0).
const EFFECT_OFFSET := Vector2(0, -0x34)
const LARGE_EFFECT_LIFT := 16.0
## 0x440391／0x444ac9: numbers at (x, y − 0x30).
const NUMBER_OFFSET := Vector2(0, -0x30)
## 0x40a3a9..0x40a591: the i-th of n effects spawned waits (n − 1 − i) × 25 ticks.
const EFFECT_STAGGER_TICKS := 25
## Effect kinds (0x408b20 case = Show_Magic_Star +0x8e) in 0x409e40's spawn order: cure (2),
## temporary stat (7), permanent stat (6), stamina (5), MP (1), HP (0).
const KIND_HP := 0
const KIND_MP := 1
const KIND_CURE := 2
const KIND_STAMINA := 5
const KIND_PERMANENT := 6
const KIND_STAT := 7
## 0x408d48 (cases 0／1): 16 sparks; +0xa8 delays grow by 1 + rand(3); direction rand(48), odd
## sparks 128 − it (256-step circle, 64 = down); 0x45eb9d at 0x20000 = 2 px／tick.
const SPARK_COUNT := 16
const SPARK_SPEED := 2.0
## defProcShowMagicStar (0x408df0) per running tick: move, x speed toward 0 by 0x1800, y speed
## + 0x2000 up to 0x30000, then 0x45e575 (+0x7c 0x50005: a frame every 6 ticks, 4 frames).
const SPARK_DRAG := 0.09375
const SPARK_GRAVITY := 0.125
const SPARK_FALL_LIMIT := 3.0
const SPARK_FRAME_TICKS := 6
const SPARK_FRAMES := 4
const SPARK_FRAME_NAMES := {KIND_HP: "MAGIC\\WAT04_%02d.SHP", KIND_MP: "MAGIC\\WAT01_%02d.SHP"}
## Kind 2 (0x408e69, 0x408faa／0x408f64): NUM510 in mode 0x2c000000, level 0→16 while the
## scale grows 0x4000／0x6400 per tick, then level 16→0 while it shrinks; deleted at level 0.
const FLASH_LEVELS := 16
const FLASH_GROW := Vector2(0.25, 0.390625)
## Kinds 5／6 (0x408bf2／0x408c5b) and 7 (0x408cc4): a 0x401390 emitter (not drawn here) and a
## flagged Show_Magic_Star that only releases after +0xa8 = delay + 108 (5／6) or + 90 (7).
const WAIT_ONLY_TICKS := {KIND_STAMINA: 108, KIND_PERMANENT: 108, KIND_STAT: 90}
## 0x43b3f0: Bar_HP at (x − 21, min(y + 8, [0x4c094c] − 36)), Bar_MP 16 below, shape +3.
const BAR_OFFSET := Vector2(-21, 8)
const BAR_PITCH := 16.0
const BAR_BOTTOM_MARGIN := 36.0

## BattlePresentation (attack cue, pose, map config) and its parent runtime (actors, camera, audio).
var view: Node
var runtime: Node
var _loop: Dictionary = {}
var effect: Dictionary = {}
var stage := "idle"
## Seconds since the effect beat started (the lead is the attack cue's own clock).
var elapsed := 0.0
var target_point := Vector2.ZERO
var effect_point := Vector2.ZERO
var sparks: Array[Dictionary] = []
var flashes: Array[int] = []
var release_tick := 0
var visual_end_tick := 0
var numbers_tick := -1
var bars: Array[Dictionary] = []
var numbers: Array[Node2D] = []
var caption: Label
var _effect_layer: Node2D
var _frames: Dictionary = {}
## Bar and flash art, loaded before the first draw (a texture first loaded inside _draw is drawn
## as a blank placeholder on that draw).
var _art: Dictionary = {}


func _ready() -> void:
	_effect_layer = Node2D.new()
	var additive := CanvasItemMaterial.new()
	additive.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_effect_layer.material = additive
	_effect_layer.draw.connect(_draw_effects)
	add_child(_effect_layer)
	var assets: Dictionary = BattleUISkin.data()["assets"]
	for key in ["bar_hp4", "bar_hp5", "bar_hp6"]:
		_art[key] = {"texture": load(str(assets[key]["res_path"])), "origin": Vector2(float(assets[key]["draw_origin"][0]), float(assets[key]["draw_origin"][1]))}
	var flash: Dictionary = BattleRewardFloat.manifest()["assets"]["damage_flash"]
	_art["flash"] = {"texture": load(str(flash["res_path"])), "origin": Vector2(float(flash["draw_origin"][0]), float(flash["draw_origin"][1]))}
	for kind in SPARK_FRAME_NAMES:
		for frame in range(SPARK_FRAMES): _frame(str(SPARK_FRAME_NAMES[kind]) % (frame + 1))
	set_process(false)


## Whether the action still waits on this use (lead, effect wait or number release).
func busy() -> bool:
	return stage in ["lead", "effect", "numbers"]


## Starts one receipt: the AI's lead-in first, the player's pick straight into the effect.
func begin(receipt: Dictionary, loop: Dictionary, map_config: RefCounted, world_position: Vector2) -> void:
	finish()
	effect = receipt
	_loop = loop
	runtime = view.get_parent()
	target_point = world_position
	var user := _unit(loop, str(effect.get("actor_id", "")))
	var target_id := str(effect.get("target_id", ""))
	var cue: Node2D = view.attack_cue
	if not bool(user.get("player_commandable", false)) and not user.is_empty() and map_config != null and runtime.has_method("unit_grid_coord"):
		var origin: Vector2i = runtime.unit_grid_coord(str(user["id"]))
		cue.begin_item(target_id, use_cells(loop, user, origin), origin, runtime.unit_grid_coord(target_id), map_config, runtime.get("camera_controller"))
		stage = "lead"
	else:
		_start_effect(loop)
	set_process(true)


## Drops every beat at once (explicit fast-forward／interruption); settles nothing.
func finish() -> void:
	if stage == "lead" and view != null and view.attack_cue.item_lead:
		view.attack_cue.hide()
	stage = "idle"
	sparks.clear()
	flashes.clear()
	bars.clear()
	for number in numbers:
		if is_instance_valid(number): number.free()
	numbers.clear()
	if is_instance_valid(caption): caption.free()
	caption = null
	set_process(false)
	queue_redraw()
	if _effect_layer != null: _effect_layer.queue_redraw()


## 0x40f440(user, 1, mode 4) from the user's cell, standing in as FootprintRules distance 1: the
## user's cell and each neighbour on the map without a hostile occupant (provisional).
static func use_cells(loop: Dictionary, user: Dictionary, origin: Vector2i) -> Array:
	var map_size: Vector2i = loop.get(LoopKeys.MAP_SIZE, Vector2i.ZERO)
	var cells: Array = [origin]
	for step in [Vector2i.UP, Vector2i.LEFT, Vector2i.RIGHT, Vector2i.DOWN]:
		var cell: Vector2i = origin + step
		if cell.x < 0 or cell.y < 0 or cell.x >= map_size.x or cell.y >= map_size.y:
			continue
		var occupant := Footprint.unit_at(loop.get(LoopKeys.UNITS, []), cell)
		if not occupant.is_empty() and ActorRoleRules.hostile(user, occupant):
			continue
		cells.append(cell)
	return cells


## 0x409e40's effect kinds for a receipt, in spawn order.
static func effect_kinds(receipt: Dictionary) -> Array[int]:
	var kinds: Array[int] = []
	for key in ["cured_poison", "cured_paralysis", "cured_no_magic", "cured_weaken"]:
		if bool(receipt.get(key, false)):
			kinds.append(KIND_CURE)
			break
	if not receipt.get("stat_effects", []).is_empty(): kinds.append(KIND_STAT)
	if not receipt.get("permanent_effects", []).is_empty(): kinds.append(KIND_PERMANENT)
	if int(receipt.get("restored_stamina", 0)) > 0: kinds.append(KIND_STAMINA)
	var written: Dictionary = receipt.get("heal_numbers", {})
	if written.has("mp") or int(receipt.get("restored_mp", 0)) > 0: kinds.append(KIND_MP)
	if written.has("hp") or int(receipt.get("restored_hp", 0)) > 0: kinds.append(KIND_HP)
	return kinds


func _process(delta: float) -> void:
	if stage == "lead":
		view.attack_cue.advance(delta)
		if view.attack_cue.stage() != "complete":
			return
		view.attack_cue.hide()
		_start_effect(_current_loop())
		return
	elapsed += maxf(delta, 0.0)
	var tick := int(OriginalTick.ticks(elapsed))
	if stage == "effect" and tick >= release_tick:
		_start_numbers(tick)
	if stage == "numbers" and tick >= release_tick:
		# 0x440437／state 0x75: the last number released the action; 0x43b4c0 drops the bars.
		bars.clear()
		stage = "trailing"
		queue_redraw()
	if stage == "trailing" and tick >= visual_end_tick:
		stage = "idle"
		set_process(false)
	_effect_layer.queue_redraw()


func _start_effect(loop: Dictionary) -> void:
	stage = "effect"
	elapsed = 0.0
	var target_id := str(effect.get("target_id", ""))
	var target := _unit(loop, target_id)
	var node: Node = runtime.actor_node_for_unit(target_id) if runtime.has_method("actor_node_for_unit") else null
	if node != null: target_point = node.position
	effect_point = target_point + EFFECT_OFFSET
	if not target.is_empty() and Footprint.radius(target) > 0:
		effect_point.y -= LARGE_EFFECT_LIFT
	view._pose_unit(str(effect.get("actor_id", "")))
	var kinds := effect_kinds(effect)
	if not kinds.is_empty() and runtime.has_method("play_ui_sound"):
		runtime.play_ui_sound("use_item")
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([int(effect.get("sequence", 0)), target_id])
	release_tick = 0
	visual_end_tick = 0
	for index in range(kinds.size()):
		var delay := (kinds.size() - 1 - index) * EFFECT_STAGGER_TICKS
		var end := _spawn(kinds[index], delay, rng)
		# The first effect spawned holds the wait reference (0x40a3c0 pushes the user).
		if index == 0: release_tick = end
	_effect_layer.queue_redraw()


## Spawns one 0x408b20 case with +0xa8 = `delay`; returns the tick its waiter would be released
## (the last spark's deletion for a burst). A delay of 0 or 1 sets up on the first tick.
func _spawn(kind: int, delay: int, rng: RandomNumberGenerator) -> int:
	if kind in SPARK_FRAME_NAMES:
		var spark_delay := delay
		var end := 0
		for index in range(SPARK_COUNT):
			var direction := rng.randi_range(0, 47)
			if index & 1: direction = 128 - direction
			var angle := TAU * direction / 256.0
			var start := maxi(spark_delay - 1, 0)
			sparks.append({"kind": kind, "start": start, "path": _spark_path(Vector2(cos(angle), sin(angle)) * SPARK_SPEED)})
			end = start + SPARK_FRAMES * SPARK_FRAME_TICKS
			spark_delay += 1 + rng.randi_range(0, 2)
		visual_end_tick = maxi(visual_end_tick, end)
		return end
	if kind == KIND_CURE:
		var start := maxi(delay - 1, 0)
		flashes.append(start)
		visual_end_tick = maxi(visual_end_tick, start + 2 * FLASH_LEVELS)
		return start + 2 * FLASH_LEVELS
	return maxi(delay + int(WAIT_ONLY_TICKS.get(kind, 0)) - 1, 0)


## Positions relative to the effect point for the setup tick and each running tick.
static func _spark_path(velocity: Vector2) -> PackedVector2Array:
	var path := PackedVector2Array([Vector2.ZERO])
	var at := Vector2.ZERO
	var speed := velocity
	for _tick in range(SPARK_FRAMES * SPARK_FRAME_TICKS - 1):
		at += speed
		speed.x = maxf(speed.x - SPARK_DRAG, 0.0) if speed.x >= 0.0 else minf(speed.x + SPARK_DRAG, 0.0)
		speed.y = minf(speed.y + SPARK_GRAVITY, SPARK_FALL_LIMIT)
		path.append(at.floor())
	return path


func _start_numbers(tick: int) -> void:
	stage = "numbers"
	numbers_tick = tick
	var target := _unit(_current_loop(), str(effect.get("target_id", "")))
	# 0x43b3f0: the target's small HP bar and the MP bar 16 px under it.
	var world_height := 1e9
	if view._map_config != null: world_height = float(view._map_config.world_size.y)
	var bar_at := target_point + BAR_OFFSET
	bar_at.y = minf(bar_at.y, world_height - BAR_BOTTOM_MARGIN)
	if not target.is_empty():
		bars = [{"at": bar_at, "fill": "bar_hp5", "value": int(target.get("hp", 0)), "max": int(target.get("max_hp", 0))},
			{"at": bar_at + Vector2(0, BAR_PITCH), "fill": "bar_hp6", "value": int(target.get("mp", 0)), "max": int(target.get("max_mp", 0))}]
	var written: Dictionary = effect.get("heal_numbers", {})
	var entries: Array[Dictionary] = []
	for pair in [["restored_hp", "hp", "heal"], ["restored_mp", "mp", "mp"]]:
		if int(effect.get(pair[0], 0)) > 0 or int(written.get(pair[1], -1)) == 0:
			entries.append({"kind": pair[2], "value": int(effect.get(pair[0], 0)), "hold": ResultNumberFloat.MP_AFTER_HP_HOLD_TICKS if not entries.is_empty() else 0})
	var bottom := target_point.y - 41.0
	for number in ResultNumberFloat.spawn_all(self, entries, target_point + NUMBER_OFFSET):
		number.name = "ItemUse" + str(number.kind).capitalize()
		number.finished.connect(number.queue_free)
		numbers.append(number)
		bottom = minf(bottom, number.bounds().position.y)
	# The last number is the waiter: released on its 32nd shown tick; with no number 0x440402
	# ends on the next tick.
	release_tick = tick + (ResultNumberFloat.hidden_ticks(int(entries.back()["hold"])) + Timing.SHOW_NUMBER_RELEASE_TICKS if not entries.is_empty() else 1)
	var last_life := 0
	for number in numbers: last_life = maxi(last_life, number.life_ticks())
	visual_end_tick = maxi(visual_end_tick, tick + last_life)
	_show_caption(bottom)
	queue_redraw()


## The receipt's rows without an original glyph (cure／permanent／buff／stamina): a white caption
## above the numbers (remake text; no original counterpart).
func _show_caption(bottom: float) -> void:
	var captions: Array[String] = []
	for row in preload("res://game/battle/scene/BattleItemText.gd").feedback(effect).split("\n", false):
		var words := row.split(" ")
		if not (words.size() == 2 and words[0].is_valid_int() and words[1] in ["HP", "MP"]): captions.append(row)
	if captions.is_empty():
		return
	caption = Label.new()
	caption.name = "ItemUseFeedback"
	caption.text = "\n".join(captions)
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.add_theme_font_size_override("font_size", 20)
	caption.add_theme_color_override("font_color", preload("res://game/battle/runtime/ShowNumberStyle.gd").CAPTION)
	caption.add_theme_constant_override("outline_size", 4)
	caption.add_theme_color_override("font_outline_color", Color.BLACK)
	add_child(caption)
	caption.size = caption.get_combined_minimum_size()
	caption.position = Vector2(target_point.x - caption.size.x / 2, bottom - maxf(24.0, caption.size.y))
	var fade := caption.create_tween()
	fade.tween_property(caption, "position:y", caption.position.y - Timing.SHOW_NUMBER_RISE_PX_PER_SECOND * Timing.SHOW_NUMBER_SECONDS, Timing.SHOW_NUMBER_SECONDS)
	fade.tween_callback(caption.queue_free)


func _draw() -> void:
	for bar in bars:
		var at: Vector2 = bar["at"]
		draw_texture(_art["bar_hp4"]["texture"], at - _art["bar_hp4"]["origin"])
		var fill: Texture2D = _art[bar["fill"]]["texture"]
		var maximum := int(bar["max"])
		var width := 0.0 if maximum <= 0 else floorf(fill.get_width() * clampf(float(bar["value"]) / maximum, 0.0, 1.0))
		if width > 0.0:
			draw_texture_rect_region(fill, Rect2(at, Vector2(width, fill.get_height())), Rect2(Vector2.ZERO, Vector2(width, fill.get_height())))


func _draw_effects() -> void:
	if stage == "idle" or stage == "lead":
		return
	var tick := int(OriginalTick.ticks(elapsed))
	for spark in sparks:
		var age := tick - int(spark["start"])
		if age < 0 or age >= SPARK_FRAMES * SPARK_FRAME_TICKS:
			continue
		var record := _frame(str(SPARK_FRAME_NAMES[spark["kind"]]) % (age / SPARK_FRAME_TICKS + 1))
		if record.is_empty():
			continue
		var path: PackedVector2Array = spark["path"]
		_effect_layer.draw_texture(record["texture"], effect_point + path[age] - record["origin"])
	for start in flashes:
		var age: int = tick - start
		if age <= 0 or age >= 2 * FLASH_LEVELS:
			continue
		var grown := age if age <= FLASH_LEVELS else 2 * FLASH_LEVELS - age
		var level := float(grown) / FLASH_LEVELS
		_effect_layer.draw_set_transform(effect_point, 0.0, Vector2.ONE + FLASH_GROW * grown)
		_effect_layer.draw_texture(_art["flash"]["texture"], -_art["flash"]["origin"], Color(level, level, level))
		_effect_layer.draw_set_transform(Vector2.ZERO)


func _frame(member: String) -> Dictionary:
	if not _frames.has(member):
		if not _frames.has("__manifest"):
			_frames["__manifest"] = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
		var entry: Dictionary = _frames["__manifest"]["frames"].get(member, {})
		_frames[member] = {} if entry.is_empty() else {"texture": load(str(entry["res_path"])), "origin": Vector2(float(entry["draw_origin"][0]), float(entry["draw_origin"][1]))}
	return _frames[member]


## The runtime's settled loop once the step is mirrored, else the one the use began with.
func _current_loop() -> Dictionary:
	var live: Variant = runtime.get("play_loop") if runtime != null else null
	return live if live is Dictionary and not (live as Dictionary).is_empty() else _loop


static func _unit(loop: Dictionary, unit_id: String) -> Dictionary:
	for unit in loop.get(LoopKeys.UNITS, []):
		if str(unit.get("id", "")) == unit_id: return unit
	return {}
