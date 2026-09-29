extends RefCounted
## Grid overlays for BattleSceneRuntime: the Move overlay (reachable cells) and the
## attack／skill overlay drawn under World/MoveOverlay (a RangeCellOverlay, which paints
## the original's pulsing fill and I_rect border per cell). Cells come from the PlayLoop
## (movement_cells／attack_cells／SkillTargetRules); the runtime keeps the mirrored
## `move_overlay_cells`／`attack_overlay_cells`. The palette follows the original's
## drawers: move (0x411200); every target reach — weapon, magic and special — in the attack
## palette (0x411480); the magic／special footprint at the cursor in 0x4116a0 palette 0／1,
## drawn after (over) the reach. The
## overlay is part of the spatial contract (camera, projection, hit-test, menu anchor)
## and its geometry is not tuned here.
## provenance:
##   layout: runtime-reference docs/evidence_packets/runtime_observations/original_gameplay_reference/README.md#V02
##     (32 px axis-aligned cells, diamond reach outline)
##   layout: static-derived docs/evidence_packets/static_reverse/original_range_cells.md
##     (skill targeting, self-centred specials included: reach in the attack palette,
##     cursor footprint in the skill palette on top)
##   timing: runtime-measured docs/evidence_packets/runtime_observations/dialogue_death/README.md
##     (Wine frames: acting unit lit at the action menu, every actor at attack targeting)
##   timing: static-derived docs/evidence_packets/runtime_observations/dialogue_death/README.md
##     (0x4c1b00 & 0x200000 written only by the player state machine, read by the actor draw 0x43dcc4)
##   timing: provisional (magic／special target, the special pick's recipients after a press,
##     item target and move selection follow the static read and the attack frame; not captured)

const BattlePlayLoop = preload("res://game/sim/loop/BattlePlayLoop.gd")
const LoopKeys = preload("res://game/sim/LoopKeys.gd")
const Interaction = preload("res://game/sim/Interaction.gd")

var runtime: Node
## The footprint cells last drawn under the cursor (refresh_skill_footprint).
var footprint_cells: Array = []


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


## The player's item-use range (0x4448f4 marks it, state 105 draws it with 0x411200, the move
## palette) while the item panel's use pick is up.
func show_item_range(cells: Array) -> void:
	if runtime.move_overlay == null or runtime.map_config == null:
		return
	runtime.move_overlay.clear_all_cells()
	footprint_cells = []
	runtime.move_overlay.add_cells("ItemCell", _cell_rects(cells.filter(func(cell): return runtime.grid_coord_in_world(cell))), "move")
	runtime.move_overlay.visible = true


func clear_item_range() -> void:
	if runtime.move_overlay == null:
		return
	runtime.move_overlay.clear_cells("ItemCell")
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
	# Every reach, a self-centred special's range0Cell included, is the caster-centred 0x40fa80
	# buffer in the attack palette (0x445026 range → 0x445075／0x44508f); its area shows only as
	# the cursor footprint once the cursor is on a reach cell (0x40fab0 at 0x4450ab).
	runtime.move_overlay.add_cells("AttackCell", _cell_rects(runtime.attack_overlay_cells), "attack")
	runtime.move_overlay.visible = true


## The selected skill's real effect area at the cursor cell, drawn over the attack-palette
## reach in the skill's own palette (0x4116a0 after 0x411480 each tick): the cells come from
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
		runtime.move_overlay.add_cells("EffectCell", _cell_rects(cells), footprint_palette(str(runtime.play_loop.get(LoopKeys.SELECTED_ATTACK, ""))))


## The footprint drawer's palette: 0x4116a0 palette 0 (0x441913／0x4419a5) for a magic
## footprint, palette 1 (0x441c19／0x441c9b) for a special-skill footprint.
static func footprint_palette(selected_attack: String) -> String:
	match selected_attack:
		"magic":
			return "magic"
		"special":
			return "special"
		_:
			return "attack"


## The skill page's own states (original 0x77 magic／0x96 special, both the tail 0x4447a7): the actor still lights.
const SKILL_PAGE_STATES := [Interaction.MAGIC_SELECT, Interaction.SPECIAL_SELECT]


## The shared map-actor highlight (ActorRuntime.set_highlight), recomputed every frame from
## the runtime's state (the dialogue board lights speakers itself). Target selection: every
## actor on the field lights in its side colour while the player picks an attack target or an
## item's Use／Give cell — the original's player state machine (dispatch 0x443a00 over the
## byte table 0x445758) sets 0x4c1b00 & 0x200000 in state 0x50 (index 16, 0x4442ef) and on
## leaving the Use／Give range states 104／112 (indices 27／32 → 0x444be4, 0x444bf0), clears it
## on every left press of the pick before the cell is checked (0x444947／0x444c40) and on
## cancel (Use 0x444a67, Give 0x444d46; a rejected press stays in 105／113 unlit —
## BattleSceneMenus.item_pick_lit), and the actor draw 0x43dcc4 lights
## every actor on it (Wine frame: allies blue, enemies pink after 攻擊). The magic／special
## target states 0x79／0x98 are entered through the same tail (0x78 at 0x444ebc, 0x97 at
## 0x44507a／0x445094 → 0x444be1 → 0x444bf0), so both light the whole field too; their per-tick
## recipient light (0x4104d0 from 0x444f5d／0x4451d2, +0x80 |= 0x100 —
## BattlePlayLoop.magic_target_ids_at_coord) is redundant under it. 0x79 clears it only on
## cancel (0x444f9a); 0x98 clears it on every left press before the recipients are enumerated
## (0x44510f) and a press with none stays in 0x98, so from then on only the recipients at the
## cursor light (BattleSceneMenus.special_pick_lit). The move pick never sets it. The skill
## page's slide-out after a row click (the unit waits in 0x77／0x96, the tail 0x4447a7) does not set
## it either: the whole field lights only when 0x78／0x97 advances into 0x79／0x98 through 0x444be1 →
## 0x444bf0, so it stays dark while BattleSceneMenus.cast_pick_hold is up. Actor: the unit
## whose command the player is choosing (action menu, skill page, move or target selection;
## Wine frame: only the acting unit lit at the action menu), not while a dialogue, exchange or
## AI turn is on. The player process sets it before the state dispatch (0x4439b4／0x443a00), so
## the state never matters: when 0x407540 returns this unit (0x44395f), [esp+0x24] — cleared
## each tick at 0x44370e, set at 0x443908 while 0x4c1b00 & 0x4000000 is clear — is nonzero and
## 0x100000 is clear (else 0x443943 jumps to 0x4447b6), 0x443990 ors +0x80 with 0x100 (ebp,
## 0x44395a). So the actor lights through the open page and its slide-out (0x77／0x96), the
## 0x78／0x97 tick, and a cancel's 0x64 and state 0 until the ring is back. The AI's turn sets neither
## (no 0x200000 writer outside the player machine, no +0x80 0x100 writer in the enemy process).
func sync_unit_highlights() -> void:
	if runtime.actors_root == null: return
	var view: Node = runtime.get_node_or_null("BattlePresentation")
	var targeting := false
	var recipients: Variant = null
	var actor_id := ""
	var opening: bool = runtime.opening_coordinator != null and runtime.opening_coordinator.active
	if view != null and not runtime.play_loop.is_empty() and not opening:
		var busy: bool = view.dialogue_active() or view.combat_busy(runtime.play_loop) or view.battle_finished
		var item_pick: bool = runtime.menus != null and runtime.menus.item_pick_lit
		var cast_hold: bool = runtime.menus != null and runtime.menus.cast_pick_hold
		targeting = not busy and not runtime.ai_playback_active and not cast_hold and (runtime.interaction_state == Interaction.ATTACK_SELECT or item_pick)
		if targeting and not item_pick and runtime.play_loop.get(LoopKeys.SELECTED_ATTACK) == "special" and runtime.menus != null and not runtime.menus.special_pick_lit:
			recipients = [] if runtime.hovered_grid_cell == Interaction.NO_CELL else BattlePlayLoop.magic_target_ids_at_coord(runtime.play_loop, runtime.hovered_grid_cell)
		if not busy and not runtime.ai_playback_active and (runtime.interaction_state in Interaction.PLAYER_CONTROL or runtime.interaction_state in SKILL_PAGE_STATES):
			actor_id = runtime.selected_unit_id
	for actor in runtime.actors_root.get_children():
		if not actor.has_method("set_highlight"): continue
		var id: String = actor.unit_id
		actor.set_highlight("target", targeting and id != "" and actor.visible and (recipients == null or recipients.has(id)))
		actor.set_highlight("actor", id != "" and id == actor_id)
