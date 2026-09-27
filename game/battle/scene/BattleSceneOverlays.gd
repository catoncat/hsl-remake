extends RefCounted
## Grid overlays for BattleSceneRuntime: the Move overlay (reachable cells) and the
## attack／skill overlay drawn under World/MoveOverlay (a RangeCellOverlay, which paints
## the original's pulsing fill and I_rect border per cell). Cells come from the PlayLoop
## (movement_cells／attack_cells／SkillTargetRules); the runtime keeps the mirrored
## `move_overlay_cells`／`attack_overlay_cells`. The palette follows the original's
## drawers: move, attack, magic (0x4116a0 palette 0) and special (palette 1). The
## overlay is part of the spatial contract (camera, projection, hit-test, menu anchor)
## and its geometry is not tuned here.
## provenance:
##   rules: n/a
##   layout: runtime-reference docs/evidence_packets/runtime_observations/original_gameplay_reference/README.md#V02 (32 px axis-aligned cells, diamond reach outline); static-derived docs/evidence_packets/static_reverse/original_range_cells.md; provisional (refresh_skill_footprint: 0x444f08／0x4450e0 feed the cursor cell to 0x4100e0, whose coverage 0x4116a0 draws; per-hover redraw and layering not traced); remake-invented (the footprint's magenta fill and white outline over the range palette, FOOTPRINT_FILL／FOOTPRINT_EDGE — user decision 2026-09-24)
##   strings: n/a
##   timing: runtime-measured docs/evidence_packets/runtime_observations/dialogue_death/README.md (sync_unit_highlights: the original lights the targeted and the acting unit; when is provisional)
##   audio: n/a

const BattlePlayLoop = preload("res://game/battle/scene/BattlePlayLoop.gd")
const LoopKeys = preload("res://game/sim/LoopKeys.gd")
const Interaction = preload("res://game/sim/Interaction.gd")

var runtime: Node
## The footprint cells last drawn under the cursor (refresh_skill_footprint).
var footprint_cells: Array = []
## The settle footprint's own style (remake-invented, user decision 2026-09-24: clearly
## distinct from the cast range): a magenta tint no range palette uses (move blue, attack
## red, magic yellow, special cyan) under a solid white outline, drawn over the range cells.
const FOOTPRINT_FILL := Color(1.0, 0.25, 0.75, 0.5)
const FOOTPRINT_EDGE := Color(1.0, 1.0, 1.0, 0.95)
const FOOTPRINT_EDGE_PX := 2.0


static func create(scene_runtime: Node) -> RefCounted:
	var overlays := new()
	overlays.runtime = scene_runtime
	return overlays


func configure_move_overlay() -> void:
	if runtime.move_overlay == null or runtime.map_config == null:
		return
	refresh_move_overlay()


func refresh_move_overlay() -> void:
	if runtime.move_overlay == null or runtime.map_config == null:
		return
	runtime.move_overlay.clear_all_cells()
	footprint_cells = []
	runtime.move_overlay_cells = _movement_cells_for_selected_unit()
	runtime.move_overlay.add_cells("MoveCell", _cell_rects(runtime.move_overlay_cells), "move")


func _cell_rects(cells: Array) -> Array[Rect2]:
	var rects: Array[Rect2] = []
	var size: Vector2 = runtime.grid_cell_size()
	for cell in cells:
		rects.append(Rect2(runtime.map_config.grid_to_world(cell), size))
	return rects


func _movement_cells_for_selected_unit() -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	if runtime.play_loop.is_empty() or runtime.selected_unit_id == "":
		return cells
	for cell_value in BattlePlayLoop.movement_cells(runtime.play_loop, runtime.selected_unit_id):
		var coord: Vector2i = cell_value
		if runtime.grid_coord_in_world(coord):
			cells.append(coord)
	cells.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		if a.y == b.y:
			return a.x < b.x
		return a.y < b.y
	)
	return cells


## The AI mover's reach before it walks (BattleAiMovePreview), in the move palette.
func show_ai_move_preview(cells: Array) -> void:
	if runtime.move_overlay == null or runtime.map_config == null:
		return
	runtime.move_overlay.clear_all_cells()
	footprint_cells = []
	var shown: Array = cells.filter(func(cell): return runtime.grid_coord_in_world(cell))
	runtime.move_overlay.add_cells("AiMoveCell", _cell_rects(shown), "move")
	runtime.move_overlay.visible = true


func clear_ai_move_preview() -> void:
	if runtime.move_overlay == null:
		return
	runtime.move_overlay.clear_cells("AiMoveCell")
	if runtime.move_overlay.get_child_count() == 0:
		runtime.move_overlay.visible = false


func set_move_overlay_visible(visible: bool) -> void:
	if runtime.move_overlay != null:
		if visible:
			refresh_move_overlay()
		runtime.move_overlay.visible = visible


func clear_attack_overlay() -> void:
	runtime.attack_overlay_cells.clear()
	footprint_cells = []
	if runtime.move_overlay == null:
		return
	runtime.move_overlay.clear_cells("AttackCell")
	runtime.move_overlay.clear_cells("EffectCell")
	if runtime.move_overlay.get_child_count() == 0:
		runtime.move_overlay.visible = false


func refresh_attack_overlay() -> void:
	runtime.attack_overlay_cells.clear()
	if runtime.play_loop.is_empty():
		return
	for cell_value in BattlePlayLoop.attack_cells(runtime.play_loop, runtime.selected_unit_id):
		runtime.attack_overlay_cells.append(cell_value)
	if runtime.move_overlay == null or runtime.map_config == null:
		return
	runtime.move_overlay.clear_all_cells()
	footprint_cells = []
	var shown_cells: Array = runtime.attack_overlay_cells
	var fields := BattlePlayLoop.skill_fields(runtime.play_loop, str(runtime.play_loop.get(LoopKeys.SELECTED_SKILL_ID, "")))
	var selected_attack := str(runtime.play_loop.get(LoopKeys.SELECTED_ATTACK, ""))
	if selected_attack == "special" and BattlePlayLoop.SkillTargetRules.self_centered(fields):
		# A self-centred special can only be cast on the caster's cell: show the area it settles over.
		shown_cells = BattlePlayLoop.Combat.skill_cast_footprint(runtime.play_loop, BattlePlayLoop.unit(runtime.play_loop, runtime.selected_unit_id)["coord"])
	runtime.move_overlay.add_cells("AttackCell", _cell_rects(shown_cells), attack_palette(selected_attack))
	runtime.move_overlay.visible = true


## The selected skill's real effect area at the cursor cell, drawn as a second layer of the
## skill palette over the cast range (brighter where they overlap): the cells come from
## BattleLoopCombat.skill_cast_footprint, the very footprint the cast settles over (毒魔箭's
## range1Cell cross around the chosen cell, a Dir line away from the caster, a circle …).
## Rebuilt only when the set changes; [] (off range, not skill targeting) clears it.
func refresh_skill_footprint(coord: Vector2i) -> void:
	var cells: Array = [] if runtime.play_loop.is_empty() or coord == Interaction.NO_CELL else BattlePlayLoop.Combat.skill_cast_footprint(runtime.play_loop, coord)
	if cells == footprint_cells or runtime.move_overlay == null or runtime.map_config == null:
		return
	footprint_cells = cells
	runtime.move_overlay.clear_cells("EffectCell")
	if not cells.is_empty():
		runtime.move_overlay.add_marked_cells("EffectCell", _cell_rects(cells), FOOTPRINT_FILL, FOOTPRINT_EDGE, FOOTPRINT_EDGE_PX)


## Original drawer per selection state: 0x411480 for the weapon, 0x4116a0 palette 0 for a
## magic footprint and palette 1 for a special-skill footprint.
static func attack_palette(selected_attack: String) -> String:
	match selected_attack:
		"magic":
			return "magic"
		"special":
			return "special"
		_:
			return "attack"


## The shared map-actor highlight (ActorRuntime.set_highlight) for the target and the acting
## unit, recomputed every frame from the runtime's state (the dialogue board lights speakers
## itself). Target: the legal target under the player's target cursor, or an AI strike's
## defender during its lead-in "target" hold. Actor: the unit whose command the player is
## choosing (action menu, move or target selection), not while a dialogue, exchange or AI
## turn is on. runtime-measured colours／pulse in ActorRuntime.HIGHLIGHTS (provisional).
func sync_unit_highlights() -> void:
	if runtime.actors_root == null: return
	var view: Node = runtime.get_node_or_null("BattlePresentation")
	var target_id := ""
	var actor_id := ""
	var opening: bool = runtime.opening_coordinator != null and runtime.opening_coordinator.active
	if view != null and not runtime.play_loop.is_empty() and not opening:
		var busy: bool = view.dialogue_active() or view.combat_busy(runtime.play_loop) or view.battle_finished
		if view.attack_cue.visible and view.attack_cue.stage() == "target":
			target_id = view.attack_cue.target_unit_id
		elif not busy and runtime.interaction_state == Interaction.ATTACK_SELECT:
			target_id = view.previewed_target_id
		if not busy and not runtime.ai_playback_active and runtime.interaction_state in Interaction.PLAYER_CONTROL:
			actor_id = runtime.selected_unit_id
	for actor in runtime.actors_root.get_children():
		if not actor.has_method("set_highlight"): continue
		var id: String = actor.unit_id
		actor.set_highlight("target", id != "" and id == target_id)
		actor.set_highlight("actor", id != "" and id == actor_id)
