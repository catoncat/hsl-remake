extends RefCounted
## Menu and panel orchestration for BattleSceneRuntime: builds the battle panels
## (status／magic／item／growth, the two system scrolls, the 整理裝備 screen) under the
## runtime's UI node, routes their signals, toggles the action menu, and turns every
## command／panel choice into one PlayLoop operation followed by the runtime's sync.
## Panel nodes stay as runtime members (tests and sibling views address them there);
## this module holds no combat state and no visibility truth of its own.
## The available command set is still `BattlePlayLoop.IMPLEMENTED_COMMANDS`.
## provenance:
##   rules: n/a
##   layout: remake-invented (panel draw order and menu anchoring rules)
##   strings: n/a
##   timing: static-derived docs/evidence_packets/static_reverse/original_growth_window.md; provisional (that ordering is a static reading; a lost battle offers no window — the conservative choice); remake-invented (per-member offered level; Status 成長點, a load and the next battle's first quiet moment reopen points left by an old save or the harness skip)
##   audio: resource-derived content/imported/hsl/shared/interface_audio/manifest.json

const BattlePlayLoop = preload("res://game/battle/scene/BattlePlayLoop.gd")
const PanelMotion = preload("res://game/battle/scene/BattlePanelMotion.gd")
const ScriptPresentation = preload("res://game/battle/scene/BattleScriptPresentation.gd")
const CampaignProgress = preload("res://game/battle/runtime/CampaignProgress.gd")
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
	runtime.item_panel.give_started.connect(_begin_give_session)
	runtime.item_panel.give_requested.connect(_confirm_give)
	runtime.item_panel.give_finished.connect(_finish_give_session)
	runtime.item_panel.drop_requested.connect(discard_inventory_item)
	runtime.item_panel.equipment_requested.connect(change_equipment)
	runtime.growth_panel = preload("res://game/battle/scene/BattleGrowthPanel.gd").new()
	ui.add_child(runtime.growth_panel)
	runtime.growth_panel.allocation_requested.connect(allocate_growth)
	runtime.status_panel.growth_requested.connect(open_growth)
	# Input priority of the modals (BattleSceneInput hands the event to the first visible one).
	runtime.modal_panels.assign([runtime.magic_panel, runtime.growth_panel, runtime.item_panel, runtime.status_panel])
	# One open／close motion for every battle panel (BattlePanelMotion; the loot window attaches
	# in BattleSettlementController).
	for panel in runtime.modal_panels:
		PanelMotion.attach(panel)


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
		runtime.action_menu.place_near(runtime.world_to_logical_position(actor.position), Rect2(Vector2(12, 12), Vector2(runtime.logical_viewport_size) - Vector2(24, 24)))


func set_action_menu_visible(visible: bool) -> void:
	visible = visible and not ScriptPresentation.pending(runtime) and not ScriptPresentation.active(runtime)
	if runtime.action_menu != null:
		update_action_menu_anchor()
		runtime.action_menu.visible = visible and not BattlePlayLoop.loot_waiting(runtime.play_loop) and not runtime.has_actor_motion() and not runtime.ai_playback_active and not (runtime.growth_panel != null and runtime.growth_panel.visible) and not runtime.get_node("BattlePresentation").combat_busy(runtime.play_loop) and not runtime.get_node("BattlePresentation").dialogue_active()


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
			runtime.item_panel.show_inventory(actor, runtime.play_loop[LoopKeys.CONSUMABLES], targets, runtime.world_to_logical_position(runtime.actor_node_for_unit(runtime.selected_unit_id).position), runtime.play_loop[LoopKeys.SKILL_BOOK]["actors"][actor["actor_id"]])
			set_action_menu_visible(false)
		return
	if command_id == "status":
		runtime.status_panel.show_unit(BattlePlayLoop.unit(runtime.play_loop, runtime.selected_unit_id), BattlePlayLoop.unit_known(runtime.play_loop, runtime.selected_unit_id))
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


func use_inventory_item(item_code: String, target_id: String) -> void:
	if not runtime.item_panel.visible or runtime.item_panel.page != "target" or runtime.item_panel.operation != "use" or runtime.item_panel.selected_item != item_code:
		return
	var next := BattlePlayLoop.use_item(runtime.play_loop, item_code, target_id, runtime.item_panel.selected_index)
	if next == runtime.play_loop:
		return
	runtime.apply_loop(next, "use_item")
	var effect: Dictionary = runtime.play_loop[LoopKeys.LAST_ITEM_USE]
	runtime.item_panel.hide()
	runtime.present_item_effect(effect)
	runtime.resume_turn_presentation()
	if runtime.ai_playback_active:
		runtime.ai_playback_wait_remaining = 0.75


func discard_inventory_item(item_code: String) -> void:
	if not runtime.item_panel.visible or runtime.item_panel.selected_item != item_code:
		return
	if runtime.item_panel.operation != "drop" or runtime.item_panel.page != "drop_confirm":
		return
	var next := BattlePlayLoop.discard_item(runtime.play_loop, item_code, runtime.item_panel.selected_index)
	if next == runtime.play_loop:
		return
	runtime.apply_loop(next, "discard_item")
	runtime.item_panel.hide()
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
	runtime.item_panel.show_give_session(BattlePlayLoop.unit(runtime.play_loop, runtime.selected_unit_id), _give_recipients(), int(runtime.play_loop[LoopKeys.ITEM_REVISION]))


func _confirm_give(target_id: String, index: int, code: int, target_index: int, return_code: int, revision: int) -> void:
	if not runtime.item_panel.visible or runtime.item_panel.page != "give_confirm" or runtime.item_panel.operation != "give":
		return
	if runtime.item_panel.give_revision != revision or runtime.item_panel.give_target_id != target_id or runtime.item_panel.selected_index != index or int(runtime.item_panel.selected_item) != code or runtime.item_panel.give_target_index != target_index or runtime.item_panel.give_return_code != return_code:
		return
	var next := BattlePlayLoop.confirm_give(runtime.play_loop, target_id, index, code, target_index, return_code, revision)
	if next == runtime.play_loop:
		return
	runtime.apply_loop(next, "confirm_give")
	runtime.play_ui_sound("confirm")
	runtime.item_panel.show_give_session(BattlePlayLoop.unit(runtime.play_loop, runtime.selected_unit_id), _give_recipients(), int(runtime.play_loop[LoopKeys.ITEM_REVISION]), true)


func _finish_give_session(revision: int) -> void:
	if not runtime.item_panel.visible or runtime.item_panel.operation != "give" or runtime.item_panel.page not in ["give_inventory", "give_target"] or runtime.item_panel.give_revision != revision:
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


func change_equipment(slot: String, inventory_index: int, item_code: int) -> void:
	if not runtime.item_panel.visible or runtime.item_panel.operation != "equip" or runtime.item_panel.page != "equip_confirm":
		return
	if runtime.item_panel.selected_slot != slot or runtime.item_panel.selected_index != inventory_index or int(runtime.item_panel.selected_item) != item_code:
		return
	var next := BattlePlayLoop.change_equipment(runtime.play_loop, slot, inventory_index, item_code)
	if next == runtime.play_loop:
		return
	runtime.apply_loop(next, "change_equipment")
	runtime.item_panel.hide()
	runtime.play_ui_sound("confirm")
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
