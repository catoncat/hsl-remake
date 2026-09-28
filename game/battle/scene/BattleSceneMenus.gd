extends RefCounted
## Menu and panel orchestration for BattleSceneRuntime: builds the battle panels
## (status／magic／item／growth, the two system scrolls, the 整理裝備 screen) under the
## runtime's UI node, routes their signals, toggles the action menu, and turns every
## command／panel choice into one PlayLoop operation followed by the runtime's sync.
## Panel nodes stay as runtime members (tests and sibling views address them there);
## this module holds no combat state and no visibility truth of its own.
## The available command set is still `BattlePlayLoop.IMPLEMENTED_COMMANDS`.
## provenance:
##   layout: remake-invented (panel draw order and menu anchoring rules)
##   layout: static-derived docs/evidence_packets/static_reverse/original_item_use_presentation.md
##     (the item-use target map pick: move-palette range, cell cursor, hover strip, confirm／cancel)
##   layout: static-derived docs/evidence_packets/static_reverse/original_give_exchange.md
##     (the give target pick shares it: 0x444bc7 marks the adjacent cells without the user's own)
##   timing: static-derived docs/evidence_packets/static_reverse/original_growth_window.md
##   timing: provisional (that ordering is a static reading; a lost battle offers no window — the conservative choice)
##   timing: remake-invented
##     (per-member offered level; Status 成長點, a load and the next battle's first quiet moment reopen points left by an
##     old save or the harness skip)
##   audio: resource-derived content/imported/hsl/shared/interface_audio/manifest.json

const BattlePlayLoop = preload("res://game/sim/loop/BattlePlayLoop.gd")
const BattlePanelMotion = preload("res://game/battle/scene/BattlePanelMotion.gd")
const OriginalTick = preload("res://game/common/OriginalTick.gd")
const ScriptPresentation = preload("res://game/battle/scene/BattleScriptPresentation.gd")
const CampaignProgress = preload("res://game/common/CampaignProgress.gd")
const Interaction = preload("res://game/sim/Interaction.gd")
const LoopKeys = preload("res://game/sim/LoopKeys.gd")
const BattleOutcome = preload("res://game/sim/BattleOutcome.gd")

var runtime: Node


static func create(scene_runtime: Node) -> RefCounted:
	var menus := new()
	menus.runtime = scene_runtime
	return menus


## Instantiates the panels in the runtime's UI draw order and wires their signals.
## Called once from BattleSceneRuntime._ready after the scene modules exist.
func build_panels() -> void:
	var ui: Node = runtime.get_node("UI")
	runtime.status_panel = preload("res://game/battle/scene/BattleStatusPanel.gd").new()
	runtime.magic_panel = preload("res://game/battle/scene/BattleMagicPanel.gd").new()
	ui.add_child(runtime.magic_panel)
	runtime.magic_panel.spell_selected.connect(_choose_magic)
	runtime.magic_panel.cancelled.connect(cancel_magic)
	ui.add_child(runtime.status_panel)
	runtime.item_panel = preload("res://game/battle/scene/BattleItemPanel.gd").new()
	ui.add_child(runtime.item_panel)
	runtime.system_menu = preload("res://game/battle/scene/BattleSystemMenu.gd").new()
	runtime.system_menu.runtime = runtime
	ui.add_child(runtime.system_menu)
	runtime.world_system_menu = preload("res://game/battle/scene/BattleSystemMenu.gd").new()
	runtime.world_system_menu.runtime = runtime
	runtime.world_system_menu.variant = "world"
	ui.add_child(runtime.world_system_menu)
	runtime.world_system_menu.arrange_equipment_requested.connect(_open_party_equipment_from_scroll)
	runtime.party_equipment_screen = preload("res://game/world/PartyEquipmentScreen.tscn").instantiate()
	runtime.party_equipment_screen.closed.connect(_on_party_equipment_closed)
	runtime.add_child(runtime.party_equipment_screen)
	runtime.item_panel.use_requested.connect(use_inventory_item)
	runtime.item_panel.use_pick_started.connect(_begin_item_pick)
	runtime.item_panel.use_pick_pointer.connect(_item_pick_pointer)
	runtime.item_panel.use_pick_ended.connect(_end_item_pick)
	runtime.item_panel.give_started.connect(_begin_give_session)
	runtime.item_panel.give_requested.connect(_confirm_give)
	runtime.item_panel.give_finished.connect(_finish_give_session)
	runtime.item_panel.drop_requested.connect(discard_inventory_item)
	runtime.item_panel.equipment_requested.connect(change_equipment)
	runtime.item_panel.hand_return_requested.connect(return_held_item)
	runtime.item_panel.ui_sound_requested.connect(runtime.play_ui_sound)
	runtime.growth_panel = preload("res://game/battle/scene/BattleGrowthPanel.gd").new()
	ui.add_child(runtime.growth_panel)
	runtime.growth_panel.allocation_requested.connect(allocate_growth)
	runtime.status_panel.growth_requested.connect(open_growth)
	runtime.status_panel.member_step_requested.connect(step_status_member)
	# Input priority of the modals (BattleSceneInput hands the event to the first visible one).
	runtime.modal_panels.assign([runtime.magic_panel, runtime.growth_panel, runtime.item_panel, runtime.status_panel])
	# One open／close motion for every battle panel (BattlePanelMotion; the loot window attaches
	# in BattleSettlementController).
	for panel in runtime.modal_panels:
		BattlePanelMotion.attach(panel)


func configure_action_menu() -> void:
	if runtime.action_menu == null:
		return
	runtime.action_menu.size = Vector2.ZERO
	rebuild_action_menu_buttons()


func rebuild_action_menu_buttons() -> void:
	if runtime.action_menu == null:
		return
	if runtime.play_loop.is_empty():
		return
	runtime.action_menu.rebuild(runtime.play_loop.get(LoopKeys.COMMAND_MENU, {}).get("commands", []))
	update_action_menu_anchor()


func update_action_menu_anchor() -> void:
	if runtime.action_menu == null or runtime.selected_unit_id == "":
		return
	var actor: Node = runtime.actor_node_for_unit(runtime.selected_unit_id)
	if actor != null:
		runtime.action_menu.place_near(runtime.world_to_logical_position(actor.position), map_logical_rect())


## The map in logical (screen) coordinates: the bounds 0x43ea30 keeps ring icons inside.
func map_logical_rect() -> Rect2:
	var config = runtime.camera_controller.map_config if runtime.camera_controller != null else null
	if config == null or config.world_size == Vector2i.ZERO:
		return Rect2(Vector2.ZERO, Vector2(runtime.logical_viewport_size))
	return Rect2(runtime.world_to_logical_position(Vector2.ZERO), Vector2(config.world_size))


func set_action_menu_visible(visible: bool) -> void:
	visible = visible and not ScriptPresentation.pending(runtime) and not ScriptPresentation.active(runtime)
	if runtime.action_menu != null:
		update_action_menu_anchor()
		visible = visible and not BattlePlayLoop.loot_waiting(runtime.play_loop) and not runtime.has_actor_motion() and not runtime.ai_playback_active and not (runtime.growth_panel != null and runtime.growth_panel.visible) and not runtime.get_node("BattlePresentation").combat_busy(runtime.play_loop) and not runtime.get_node("BattlePresentation").dialogue_active()
		runtime.action_menu.visible = visible and _ring_camera_ready(visible)


## State 0 (0x443a1d → 0x43bf30) glides the camera back to the actor before every ring opening
## — first selection, a cancelled move／attack pick (100, move 9), a closed status page or item
## sub-ring (71) — and opens the ring (0x443a3c) only once the glide lands.
func _ring_camera_ready(opening: bool) -> bool:
	var camera = runtime.camera_controller
	if not opening:
		runtime.ring_camera_return = false
		return true
	if runtime.ring_camera_return:
		if camera != null and camera.is_scrolling(): return false
		runtime.ring_camera_return = false
		return true
	if runtime.action_menu.visible or camera == null or runtime.selected_unit_id == "":
		return true
	if camera.is_scrolling() and camera.scroll_mode == "follow": return false
	runtime.focus_camera_on_grid(runtime.unit_grid_coord(runtime.selected_unit_id))
	runtime.ring_camera_return = camera.is_scrolling()
	return not runtime.ring_camera_return


func choose_command(command_id: String) -> void:
	if ScriptPresentation.pending(runtime) or ScriptPresentation.active(runtime): return
	if BattlePlayLoop.loot_waiting(runtime.play_loop): return
	if runtime.ai_playback_active or runtime.has_actor_motion() or runtime.modal_open() or runtime.get_node("BattlePresentation").combat_busy(runtime.play_loop) or runtime.get_node("BattlePresentation").dialogue_active():
		return
	if runtime.selected_unit_id == "" or runtime.play_loop.is_empty():
		return
	if not BattlePlayLoop.command_available(runtime.play_loop, command_id):
		return
	runtime.apply_loop(BattlePlayLoop.choose_command(runtime.play_loop, command_id), "choose_command")
	runtime.mirror_interaction()
	if command_id == "magic":
		runtime.magic_panel.show_spells(BattlePlayLoop.magic_options(runtime.play_loop, runtime.selected_unit_id), "magic", BattlePlayLoop.unit(runtime.play_loop, runtime.selected_unit_id), int(runtime.play_loop.get(LoopKeys.GOLD, 0)))
		set_action_menu_visible(false)
		return
	if command_id == "item":
		if not bool(runtime.play_loop[LoopKeys.ATTACKED_THIS_ACTION]):
			var targets: Array = []
			for id in BattlePlayLoop.recovery_target_ids(runtime.play_loop):
				var target := BattlePlayLoop.unit(runtime.play_loop, id).duplicate(true)
				target["screen_position"] = runtime.world_to_logical_position(runtime.actor_node_for_unit(id).position)
				targets.append(target)
			var actor := BattlePlayLoop.unit(runtime.play_loop, runtime.selected_unit_id)
			runtime.item_panel.map_area = map_logical_rect()
			runtime.item_panel.gold = int(runtime.play_loop.get(LoopKeys.GOLD, 0))
			runtime.item_panel.show_inventory(actor, runtime.play_loop[LoopKeys.CONSUMABLES], targets, runtime.world_to_logical_position(runtime.actor_node_for_unit(runtime.selected_unit_id).position), runtime.play_loop[LoopKeys.SKILL_BOOK]["actors"][actor["actor_id"]])
			set_action_menu_visible(false)
		return
	if command_id == "status":
		runtime.status_panel.show_unit(BattlePlayLoop.unit(runtime.play_loop, runtime.selected_unit_id), BattlePlayLoop.unit_known(runtime.play_loop, runtime.selected_unit_id), true, runtime.play_loop)
		set_action_menu_visible(false)
		return
	if command_id == "wait":
		runtime.resume_turn_presentation()
		return
	if command_id == "move":
		set_action_menu_visible(false)
		runtime.overlays.set_move_overlay_visible(true)
		runtime.overlays.clear_attack_overlay()
		return
	if command_id in ["attack", "special"]:
		if runtime.interaction_state == Interaction.SPECIAL_SELECT:
			runtime.magic_panel.show_spells(BattlePlayLoop.special_options(runtime.play_loop, runtime.selected_unit_id), "special", BattlePlayLoop.unit(runtime.play_loop, runtime.selected_unit_id), int(runtime.play_loop.get(LoopKeys.GOLD, 0)))
			set_action_menu_visible(false)
			return
		if runtime.interaction_state != Interaction.ATTACK_SELECT:
			return
		set_action_menu_visible(false)
		runtime.overlays.set_move_overlay_visible(false)
		runtime.overlays.refresh_attack_overlay()
		return
	rebuild_action_menu_buttons()


func _choose_magic(skill_id: String) -> void:
	if not runtime.magic_panel.visible or runtime.play_loop.get(LoopKeys.INTERACTION) not in [Interaction.MAGIC_SELECT, Interaction.SPECIAL_SELECT]: return
	var next := BattlePlayLoop.choose_special(runtime.play_loop, skill_id) if runtime.play_loop[LoopKeys.INTERACTION] == Interaction.SPECIAL_SELECT else BattlePlayLoop.choose_magic(runtime.play_loop, skill_id)
	if next == runtime.play_loop: return
	runtime.apply_loop(next, "choose_magic")
	runtime.mirror_interaction()
	runtime.magic_panel.hide()
	set_action_menu_visible(false)
	# A row click puts the page into its slide-out (window state 1→2, 0x42946d／0x438f8e); the
	# unit waits in 0x77 drawing nothing until the window's close state (0x428ee4) deletes it and
	# advances the unit, then 0x78 spends one tick building the reach (0x40fa80) before 0x79
	# draws reach, footprint, cursor and strip and reads clicks.
	cast_pick_hold = true
	_cast_pick_clock = 0.0
	tick_cast_pick_hold(0.0)


## True from a skill-row click until target selection begins (see _choose_magic): no overlay,
## cursor or identity strip, and pointer clicks are ignored.
var cast_pick_hold := false
var _cast_pick_clock := 0.0


func tick_cast_pick_hold(delta: float) -> void:
	if not cast_pick_hold:
		return
	if runtime.magic_panel != null and BattlePanelMotion.attach(runtime.magic_panel).closing():
		return
	_cast_pick_clock += delta
	# Headless (no close snapshot) the page is gone at once and the 0x78 tick is not waited for.
	if _cast_pick_clock < OriginalTick.TICK_SECONDS and DisplayServer.get_name() != "headless":
		return
	cast_pick_hold = false
	runtime.overlays.refresh_attack_overlay()


func cancel_magic() -> void:
	if not runtime.magic_panel.visible or runtime.play_loop.get(LoopKeys.INTERACTION) not in [Interaction.MAGIC_SELECT, Interaction.SPECIAL_SELECT]: return
	runtime.apply_loop(BattlePlayLoop.cancel_interaction(runtime.play_loop), "cancel_magic")
	runtime.mirror_interaction()
	runtime.magic_panel.hide()
	rebuild_action_menu_buttons()
	set_action_menu_visible(true)


## States in which the growth window may open: the player's quiet action menu and the
## enemy turn between two AI steps (a counter's level-up there opens before the next foe).
const GROWTH_QUIET_STATES := [Interaction.ACTION_MENU, Interaction.AI_RESOLVING]
## A won battle's final blow opens its window from the state the blow left (the result state,
## or the menu／AI state the scene still mirrors).
const TERMINAL_GROWTH_STATES := [Interaction.BATTLE_RESULT, Interaction.ACTION_MENU, Interaction.AI_RESOLVING]


## The quiet boundary for the growth window: no motion, combat／item feedback, dialogue,
## pending loot or script presentation. A decided battle is quiet only when won: the final
## blow's window comes before the victory dialogue, cutscene and result page (0x442720 phase 8
## runs in the attacker's completion, before the action ends and the win scan 0x44ee20 runs),
## so a pending script does not hold it; a lost battle offers nothing.
func growth_quiet() -> bool:
	var view = runtime.get_node("BattlePresentation")
	if BattlePlayLoop.loot_waiting(runtime.play_loop): return false
	var terminal := BattleOutcome.decided(runtime.play_loop)
	if terminal and not BattleOutcome.won(runtime.play_loop): return false
	if runtime.interaction_state not in (TERMINAL_GROWTH_STATES if terminal else GROWTH_QUIET_STATES): return false
	if runtime.has_actor_motion() or view.combat_busy(runtime.play_loop) or view.dialogue_active(): return false
	if ScriptPresentation.active(runtime): return false
	return terminal or not ScriptPresentation.pending(runtime)


## Opens the window for the first member whose current level has not been offered yet —
## the selected unit first, then roster order. Returns true when a window opened.
func offer_pending_growth() -> bool:
	if runtime.modal_open() or not growth_quiet(): return false
	var id := _unoffered_growth_member()
	if id == "": return false
	open_growth(id)
	return runtime.growth_panel.visible


## A won battle whose final blow levelled a member not offered yet (or whose window is up):
## the victory dialogue, cutscene and result page wait until the window closes.
func terminal_growth_pending() -> bool:
	if not BattleOutcome.won(runtime.play_loop): return false
	return (runtime.growth_panel != null and runtime.growth_panel.visible) or _unoffered_growth_member() != ""


func _unoffered_growth_member() -> String:
	var ids: Array[String] = [runtime.selected_unit_id]
	for unit in runtime.play_loop.get(LoopKeys.UNITS, []):
		ids.append(str(unit["id"]))
	for id in ids:
		var member := BattlePlayLoop.unit(runtime.play_loop, id)
		if growth_available(member) and int(member["level"]) > int(runtime.growth_offered_levels.get(id, 0)):
			return id
	return ""


static func growth_available(member: Dictionary) -> bool:
	return not member.is_empty() and bool(member.get("player_commandable", false)) and int(member.get("pending_stat_points", 0)) > 0 and int(member.get("hp", 0)) > 0 and not bool(member.get("defeated", false)) and not bool(member.get("departed", false))


## Opens the window for `unit_id` (the automatic offer, or Status 成長點 for any member).
func open_growth(unit_id: String) -> void:
	if not growth_quiet():
		return
	var player := BattlePlayLoop.unit(runtime.play_loop, unit_id)
	if not growth_available(player):
		return
	runtime.growth_offered_levels[unit_id] = int(player["level"])
	runtime.status_panel.hide()
	runtime.item_panel.hide()
	runtime.growth_panel.show_unit(player, runtime.play_loop[LoopKeys.SKILL_BOOK])
	set_action_menu_visible(false)
	runtime.get_node("BattlePresentation").status_label.hide()
	runtime.get_node("BattlePresentation").combat_label.hide()


func allocate_growth(unit_id: String, allocation: Dictionary) -> void:
	if not runtime.growth_panel.visible or unit_id != str(runtime.growth_panel.source_unit["id"]):
		return
	var before := BattlePlayLoop.unit(runtime.play_loop, unit_id)
	var next := BattlePlayLoop.allocate_growth(runtime.play_loop, unit_id, allocation)
	var after := BattlePlayLoop.unit(next, unit_id)
	if int(after.get("pending_stat_points", 0)) >= int(before.get("pending_stat_points", 0)):
		runtime.growth_panel.show_unit(before, runtime.play_loop[LoopKeys.SKILL_BOOK])
		return
	runtime.apply_loop(next, "allocate_growth")
	# The original window's 學會特殊技 box previewed the skill while placing points; OK closes without another message.
	runtime.growth_panel.hide()
	runtime.play_ui_sound("confirm")
	# A multi-level award: closing a window sends 0x442720 back to phase 8 (the wait pointer's
	# +0x8c, 0x4c432c 7 → 8), which opens the next level's window while points are left — no
	# second LEVEL UP float or sound. OPT-GROWTH=合成一窗 placed them all in one window.
	if not runtime.growth_panel.postpone_allowed and growth_available(after):
		runtime.growth_panel.show_unit(after, runtime.play_loop[LoopKeys.SKILL_BOOK])
		return
	rebuild_action_menu_buttons()


## The use target is the original's map cell pick (state 104 0x4448f4 → 105 0x44492a):
## 0x40f440(user, 1 (2 if large), mode 4) marks the range, drawn each tick in the move palette
## (0x411200) with the cell cursor (0x430230); a unit under the pointer (cell word 0x70000, any
## side, in range or not) opens its identity strip (0x436490／0x43b4e0 mode 3, 0x4449bb); a left
## press confirms only on a marked cell (0x40f560) holding a player-side unit (0x411c40 & 0x10000)
## that is not no_attack (0x446b00) — recovery_target_ids — otherwise nothing happens.
## Give (state 112 0x444bc7 → 113 0x444c27) is the same pick with the user's cell cleared; its
## left press takes a marked cell whose unit is a give target (0x40f560, 0x411c40 & 0x10000, 0x407800).
var item_pick_cells: Array = []


func _begin_item_pick() -> void:
	var actor := BattlePlayLoop.unit(runtime.play_loop, runtime.selected_unit_id)
	var origin: Vector2i = runtime.unit_grid_coord(runtime.selected_unit_id)
	item_pick_cells = preload("res://game/battle/scene/BattleItemUsePresentation.gd").use_cells(runtime.play_loop, actor, origin)
	if runtime.item_panel.operation == "give":
		item_pick_cells.erase(origin)
	runtime.overlays.show_item_range(item_pick_cells)
	_item_pick_hover(runtime.pointer_logical_position)


func _item_pick_pointer(viewport_position: Vector2, confirm: bool) -> void:
	var logical: Vector2 = runtime.viewport_to_logical_position(viewport_position)
	if not confirm:
		_item_pick_hover(logical)
		return
	var cell := _item_pick_cell(logical)
	var unit_id: String = runtime.scene_input.unit_id_at_grid(cell)
	if not item_pick_cells.has(cell) or unit_id == "":
		return
	if runtime.item_panel.operation == "give":
		if BattlePlayLoop.give_target_ids(runtime.play_loop).has(unit_id):
			runtime.item_panel.select_give_target(unit_id)
	elif BattlePlayLoop.recovery_target_ids(runtime.play_loop).has(unit_id):
		use_inventory_item(runtime.item_panel.selected_item, unit_id)


## Per frame while the pick is up (BattlePresentation.refresh hides the cursor and strip each frame).
func refresh_item_pick() -> void:
	if runtime.item_panel.picking:
		_item_pick_hover(runtime.pointer_logical_position)


func _item_pick_cell(logical: Vector2) -> Vector2i:
	return runtime.grid_at_logical_position(logical) if Rect2(Vector2.ZERO, Vector2(runtime.logical_viewport_size)).has_point(logical) else Interaction.NO_CELL


func _item_pick_hover(logical: Vector2) -> void:
	var view: Node = runtime.get_node("BattlePresentation")
	var cell := _item_pick_cell(logical)
	view.target_vitals.hide()
	if cell == Interaction.NO_CELL:
		view.selection_cursor.hide()
		return
	var center: Vector2 = runtime.grid_cell_center_to_logical_position(cell)
	var size: Vector2 = runtime.grid_cell_size()
	# 0x430230 is the cell cursor of every pick state; the remake's measured form is I_RECT01.
	view.selection_cursor.present(Rect2(center - size / 2, size), "", item_pick_cells.has(cell), Rect2(), true)
	view.preview_hovered_unit(runtime.play_loop, runtime.scene_input.unit_id_at_grid(cell))
	view.target_vitals.position = Vector2(0, 8 if center.y >= 300 else 322)


func _end_item_pick() -> void:
	item_pick_cells = []
	runtime.overlays.clear_item_range()
	var view: Node = runtime.get_node("BattlePresentation")
	view.selection_cursor.hide()
	view.target_vitals.hide()


func use_inventory_item(item_code: String, target_id: String) -> void:
	if not runtime.item_panel.visible or runtime.item_panel.page != "target" or runtime.item_panel.operation != "use" or runtime.item_panel.selected_item != item_code:
		return
	var next := BattlePlayLoop.use_item(runtime.play_loop, item_code, target_id, runtime.item_panel.selected_index)
	if next == runtime.play_loop:
		return
	runtime.apply_loop(next, "use_item")
	var effect: Dictionary = runtime.play_loop[LoopKeys.LAST_ITEM_USE]
	runtime.item_panel.hide()
	# Confirming the cell goes straight to the use pose (0x4449a7) and the next tick clears the
	# held item (0x444aba): the range, cursor, strip and icon vanish in place — the pick page's
	# held icon must not leave a close snapshot sliding out (original_item_use_presentation.md).
	BattlePanelMotion.attach(runtime.item_panel).finish()
	runtime.present_item_effect(effect)
	runtime.resume_turn_presentation()
	if runtime.ai_playback_active:
		runtime.ai_playback_wait_remaining = 0.75


func discard_inventory_item(item_code: String) -> void:
	if not runtime.item_panel.visible or runtime.item_panel.selected_item != item_code:
		return
	if runtime.item_panel.operation != "drop" or runtime.item_panel.page != "hand" or runtime.item_panel.held_code != int(item_code):
		return
	var next := BattlePlayLoop.discard_item(runtime.play_loop, item_code, runtime.item_panel.selected_index)
	if next == runtime.play_loop:
		return
	runtime.apply_loop(next, "discard_item")
	# The mode-5 window stays up with an empty hand (0x43aae1 only clears [0x4c1ce4]).
	runtime.item_panel.hand_item_dropped(BattlePlayLoop.unit(runtime.play_loop, runtime.selected_unit_id))
	runtime.play_ui_sound("confirm")
	rebuild_action_menu_buttons()


func _give_recipients() -> Array:
	var result: Array = []
	for id in BattlePlayLoop.give_target_ids(runtime.play_loop):
		var target := BattlePlayLoop.unit(runtime.play_loop, id)
		target["screen_position"] = runtime.world_to_logical_position(runtime.actor_node_for_unit(id).position)
		result.append(target)
	return result


func _begin_give_session() -> void:
	if not runtime.item_panel.visible or runtime.item_panel.page != "commands":
		return
	var next := BattlePlayLoop.begin_give(runtime.play_loop)
	if next == runtime.play_loop:
		return
	runtime.apply_loop(next, "begin_give")
	runtime.item_panel.gold = int(runtime.play_loop.get(LoopKeys.GOLD, 0))
	runtime.item_panel.show_give_session(BattlePlayLoop.unit(runtime.play_loop, runtime.selected_unit_id), _give_recipients(), int(runtime.play_loop[LoopKeys.ITEM_REVISION]))


func _confirm_give(target_id: String, index: int, code: int, target_index: int, return_code: int, revision: int) -> void:
	if not runtime.item_panel.visible or runtime.item_panel.page != "give_inventory" or runtime.item_panel.operation != "give":
		return
	if runtime.item_panel.give_revision != revision or runtime.item_panel.give_target_id != target_id or runtime.item_panel.selected_index != index or int(runtime.item_panel.selected_item) != code or runtime.item_panel.give_target_index != target_index or runtime.item_panel.give_return_code != return_code:
		return
	var next := BattlePlayLoop.confirm_give(runtime.play_loop, target_id, index, code, target_index, return_code, revision)
	if next == runtime.play_loop:
		return
	runtime.apply_loop(next, "confirm_give")
	runtime.play_ui_sound("confirm")
	runtime.item_panel.gold = int(runtime.play_loop.get(LoopKeys.GOLD, 0))
	runtime.item_panel.show_give_session(BattlePlayLoop.unit(runtime.play_loop, runtime.selected_unit_id), _give_recipients(), int(runtime.play_loop[LoopKeys.ITEM_REVISION]))


func _finish_give_session(revision: int) -> void:
	if not runtime.item_panel.visible or runtime.item_panel.operation != "give" or runtime.item_panel.page != "inventory" or runtime.item_panel.give_revision != revision:
		return
	var used := bool(runtime.play_loop.get(LoopKeys.GIVE_SESSION, {}).get("action_used", false))
	var next := BattlePlayLoop.finish_give(runtime.play_loop, revision)
	if next == runtime.play_loop:
		return
	runtime.apply_loop(next, "finish_give")
	runtime.item_panel.hide()
	if used:
		runtime.resume_turn_presentation()
	else:
		rebuild_action_menu_buttons()


## Mode 4／5 and the use pick's cancel (0x444a5c): the held bag item goes back first-empty
## (0x436e30 after the lift closed its gap). Already last, the bag is unchanged.
func return_held_item(inventory_index: int, item_code: int) -> void:
	var panel = runtime.item_panel
	var use_pick: bool = panel.operation == "use" and panel.page == "target"
	if not panel.visible or not (use_pick or (panel.operation in ["equip", "drop"] and panel.page == "hand")):
		return
	var held := [panel.selected_index, int(panel.selected_item)] if use_pick else [panel.held_index, panel.held_code]
	if held != [inventory_index, item_code]:
		return
	var inventory: Array = BattlePlayLoop.unit(runtime.play_loop, runtime.selected_unit_id).get("inventory", [])
	if inventory_index < 0 or inventory_index >= inventory.size() or int(inventory[inventory_index]) != item_code:
		return
	var next := BattlePlayLoop.return_held_item(runtime.play_loop, inventory_index, item_code)
	if next != runtime.play_loop:
		runtime.apply_loop(next, "return_held_item")
	runtime.item_panel.hand_item_returned(BattlePlayLoop.unit(runtime.play_loop, runtime.selected_unit_id))


func change_equipment(slot: String, inventory_index: int, item_code: int) -> void:
	if not runtime.item_panel.visible or runtime.item_panel.operation not in ["equip", "drop"] or runtime.item_panel.page != "hand":
		return
	if runtime.item_panel.selected_slot != slot or runtime.item_panel.selected_index != inventory_index or int(runtime.item_panel.selected_item) != item_code:
		return
	var old_code := BattlePlayLoop.EquipmentRules.equipped_code(BattlePlayLoop.unit(runtime.play_loop, runtime.selected_unit_id)["equipment"], slot)
	var next := BattlePlayLoop.change_equipment(runtime.play_loop, slot, inventory_index, item_code)
	if next == runtime.play_loop:
		# 0x436f30 returned -1: the hand keeps its item, no sound.
		return
	runtime.apply_loop(next, "change_equipment")
	# The mode-4／5 window stays up; the piece that came off is in the hand (0x439957／0x4399a0).
	runtime.item_panel.hand_equipment_changed(BattlePlayLoop.unit(runtime.play_loop, runtime.selected_unit_id), old_code)
	rebuild_action_menu_buttons()


## 整理裝備 from the world scroll (and a story scene's actEnterStorageWindow): the screen
## works on the hand-off carry through a sandbox loop of its source scenario
## (PartyEquipmentRules); no PlayLoop here is touched. Returns the screen's open result.
func open_party_equipment() -> Dictionary:
	var carry: Dictionary = runtime.campaign_handoff.get("carry", {}) if typeof(runtime.campaign_handoff.get("carry")) == TYPE_DICTIONARY else {}
	var campaign: Dictionary = runtime.campaign_progress.campaign if runtime.campaign_progress != null else CampaignProgress.load_campaign()
	return runtime.party_equipment_screen.open(carry, campaign)


## World scroll item 0 (defProcBigMapMenu 0x425a90 case 0 hides the scroll's items while the
## window is up): closing the window brings the scroll back (original frame 17 → right click →
## the scroll, docs/evidence_packets/runtime_observations/original_world_town/README.md): the
## scroll hides at once and comes back at once (BattleSystemMenu.hide_now／reopen_now).
var _party_equipment_from_scroll := false


func _open_party_equipment_from_scroll() -> void:
	_party_equipment_from_scroll = true
	open_party_equipment()


## Battle winfail storage uses the current PlayLoop as its party source. The screen
## remains a presentation modal; its close callback projects only equipment fields
## back into that same loop.
func open_battle_party_equipment() -> Dictionary:
	var carry: Dictionary = BattlePlayLoop.CampaignCarryRules.capture(runtime.play_loop)
	var campaign: Dictionary = runtime.campaign_progress.campaign if runtime.campaign_progress != null else CampaignProgress.load_campaign()
	return runtime.party_equipment_screen.open(carry, campaign, runtime.scenario_path)


func apply_battle_party_equipment(next_carry: Dictionary) -> Dictionary:
	var projection := BattlePlayLoop.apply_battle_equipment_carry(runtime.play_loop, next_carry)
	if not bool(projection.get("ok", false)):
		return projection
	runtime.apply_loop(projection["loop"], "apply_battle_equipment_carry")
	return {"ok": true, "error": ""}


## Same write-back path as a town transaction (WorldMapRuntime._on_town_party_changed):
## the hand-off carry and the persisted campaign position both take the new party.
func _on_party_equipment_closed(next_carry: Dictionary, changes: int) -> void:
	if _party_equipment_from_scroll:
		_party_equipment_from_scroll = false
		runtime.world_system_menu.reopen_now()
	if runtime.opening_coordinator != null and runtime.opening_coordinator.cutscene_mode:
		return
	if changes <= 0 or next_carry.is_empty():
		return
	runtime.campaign_handoff["carry"] = next_carry.duplicate(true)
	if runtime.campaign_progress != null:
		var world: Dictionary = runtime.world_map_runtime.state if runtime.world_map_runtime != null and runtime.world_map_runtime.active else (runtime.campaign_handoff.get("world", {}) if typeof(runtime.campaign_handoff.get("world")) == TYPE_DICTIONARY else {})
		runtime.campaign_progress.update_world_state(world, next_carry)


## Status page 上一位／下一位 (mode 0): the previous／next living unit the player commands, in
## roster order, wrapping (0x43aa56 re-targets the page; the roster walk order is provisional).
func step_status_member(step: int) -> void:
	var ids: Array = []
	for member in runtime.play_loop[LoopKeys.UNITS]:
		if bool(member.get("player_commandable", false)) and int(member.get("hp", 0)) > 0 and not bool(member.get("defeated", false)) and not bool(member.get("departed", false)):
			ids.append(str(member["id"]))
	if ids.is_empty():
		return
	var at := ids.find(str(runtime.status_panel.inspected_unit_id))
	var next_id: String = ids[posmod(at + step, ids.size())] if at >= 0 else ids[0]
	runtime.status_panel.show_unit(BattlePlayLoop.unit(runtime.play_loop, next_id), BattlePlayLoop.unit_known(runtime.play_loop, next_id), true, runtime.play_loop)
