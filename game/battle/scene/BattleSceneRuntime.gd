extends Node2D
## provenance:
##   rules: remake-invented (scene orchestration, dev seams, input gating)
##   rules: static-derived docs/evidence_packets/static_reverse/original_enemy_turn.md
##   rules: remake-invented docs/OPTIONS.md (OPT-TREASURE read point)
##   layout: static-derived docs/evidence_packets/runtime_observations/camera_panel_motion/README.md
##   strings: resource-derived content/imported/hsl/chapter01/battle051/message_text_evidence.json
##   timing: static-derived docs/evidence_packets/static_reverse/original_battle_end_flow.md
##   timing: runtime-measured docs/evidence_packets/static_reverse/original_battle_end_flow.md (≈0.2 s fade to black)
##   audio: static-derived docs/evidence_packets/static_reverse/original_music.md
##     (silent at scene start; plays on past the battle end until the level is left; 讀取戰場記錄 restarts the table track)
##   audio: resource-derived content/imported/hsl/music/manifest.json
##   audio: resource-derived content/imported/hsl/shared/interface_audio/manifest.json

var treasure_view: Node
const ScriptPresentation = preload("res://game/battle/scene/BattleScriptPresentation.gd")
const BattleOutcome = preload("res://game/sim/BattleOutcome.gd")
const GlobalRandomStream = preload("res://game/sim/GlobalRandomStream.gd")
const ScriptActorsPresentation = preload("res://game/battle/scene/BattleScriptActorPresentation.gd")

const GameSettings = preload("res://game/settings/GameSettings.gd")
const GameOptions = preload("res://game/settings/GameOptions.gd")
const RemakeOptionsPage = preload("res://game/settings/RemakeOptionsPage.gd")

const MapSceneConfig = preload("res://game/battle/runtime/MapSceneConfig.gd")
const WorldMapRuntime = preload("res://game/world/WorldMapRuntime.gd")
const BattleCameraController = preload("res://game/battle/runtime/BattleCameraController.gd")
const BattleScenario = preload("res://game/sim/BattleScenario.gd")
const BattleOpeningCoordinator = preload("res://game/battle/scene/BattleScriptCoordinator.gd")
const CampaignProgress = preload("res://game/battle/runtime/CampaignProgress.gd")
const ConditionalPartyRules = preload("res://game/sim/ConditionalPartyRules.gd")
const ActorSpriteKey = preload("res://game/battle/runtime/ActorSpriteKey.gd")
const BattleSceneInput = preload("res://game/battle/scene/BattleSceneInput.gd")
const BattleSceneMenus = preload("res://game/battle/scene/BattleSceneMenus.gd")
const BattleSceneStage = preload("res://game/battle/scene/BattleSceneStage.gd")
const BattleSceneOverlays = preload("res://game/battle/scene/BattleSceneOverlays.gd")
const BattleAiMovePreview = preload("res://game/battle/scene/BattleAiMovePreview.gd")

## InputEvent dispatch and pointer hit-testing; hover state stays on this runtime.
var scene_input: RefCounted = BattleSceneInput.create(self)
## Panel construction, panel signal handlers, command choice and action-menu toggling.
var menus: RefCounted = BattleSceneMenus.create(self)
## AI move preview (reach shown before the walk).
var ai_move_preview: RefCounted = BattleAiMovePreview.create(self)
## ActorRuntime and map-object／background-sound assembly under World.
var stage: RefCounted = BattleSceneStage.create(self)
## Move／attack overlay cells drawn under World/MoveOverlay from PlayLoop cell sets.
var overlays: RefCounted = BattleSceneOverlays.create(self)
var opening_coordinator: Node
## Big-map module for level_kind world_map scenarios (no PlayLoop, no opening).
var world_map_runtime: Node
var campaign_progress: Node
var campaign_handoff: Dictionary = {}
## Random encounters: which install_if_carried slots took the field (ConditionalPartyRules).
var conditional_party_receipt: Dictionary = {}
var settlement_controller: Node
var status_panel: Control
var item_panel: Control
var system_menu: Control
var world_system_menu: Control
## Between-battle 整理裝備 screen (world scroll item 1), over the carried party.
var party_equipment_screen: CanvasLayer
var growth_panel: Control
## The battle modals in input priority (BattleSceneMenus.build_panels): while one is
## visible it owns the frame — the runtime hides the action menu and skips edge scroll,
## and BattleSceneInput hands it every event through its `handle_input(event) -> bool`.
var modal_panels: Array[Control] = []
## Unit id → the level at which its growth window was last offered (BattleSceneMenus.
## offer_pending_growth). A member absent here has never been offered; presentation state
## only — the points themselves are the loop's `pending_stat_points`.
var growth_offered_levels: Dictionary = {}
var ui_audio: AudioStreamPlayer
var ui_sounds: Dictionary
## The finished battle's fade to black (original_battle_end_flow.md): 0x42cc10／0x42cbd0 end the
## level through the screen transition 0x42dc90(2) with no result page. Seconds into it, the
## top-layer black rect, and whether the leave already ran.
var _end_fade_seconds := 0.0
var _end_hold_seconds := 0.0
var _end_fade: ColorRect
var _battle_left := false
## Harness seam: a review／capture host that inspects the finished battle and restarts or hands
## off by itself sets this; the product never does. Headless tests that do not make the runtime
## the tree's current scene never leave either.
static var hold_finished_battle := false

const ActorRuntime = preload("res://game/battle/runtime/ActorRuntime.gd")
const SceneTimeline = preload("res://game/battle/runtime/SceneTimeline.gd")
const MapObjectPlacement = preload("res://game/battle/runtime/MapObjectPlacement.gd")
const OpeningStoryObjects = preload("res://game/battle/runtime/opening/OpeningStoryObjects.gd")
const BattlePlayLoop = preload("res://game/sim/loop/BattlePlayLoop.gd")
const CoreTurnQueue = preload("res://game/sim/CoreTurnQueue.gd")
const BattleScenarioRuleAdapter = preload("res://game/sim/BattleScenarioRuleAdapter.gd")
const Interaction = preload("res://game/sim/Interaction.gd")
const LoopKeys = preload("res://game/sim/LoopKeys.gd")

const MOVE_CELL_PRESENTATION_SECONDS := ActorRuntime.WALK_CELL_SECONDS  # 8 ticks × 16 ms per cell
## Recording 2026-09-24 12.03.22 (first-battle win): the dialogue board closes ≈515.8 s, the
## map holds ≈0.2 s, fades to black in ≈0.2 s (516.0–516.2 s), then STORY052 fades in — no
## page, no key. A defeat leaves through the same transition (0x42cbd0 → 0x42dc90(2)).
const END_HOLD_SECONDS := 0.2
const END_FADE_SECONDS := 0.2
const GAME_OVER_SCENE := "res://game/title/GameOverScreen.tscn"
const TITLE_SCENE := "res://game/title/TitleScreen.tscn"
const STARTUP_MODE_PRODUCT_OPENING := "product_opening"
const STARTUP_MODE_DEV_FIRST_CONTROL := "dev_first_control"
const ENTRYPOINT_PRODUCT_OPENING := "product_opening"
const ENTRYPOINT_DEV_FIRST_CONTROL_HARNESS := "dev_first_control_harness"
## Headless-only seam: this environment variable replaces the clock seed of the loop's
## RNG streams (damage / reward) and of the process's global stream (GlobalRandomStream:
## AI decisions, NPC level adjustment, random positions) so the autoplay sweep's tracked
## results.json is reproducible. A display-server product run never reads it.
const LOOP_SEED_ENV := GlobalRandomStream.SEED_ENV

@export_enum("product_opening", "dev_first_control") var startup_mode: String = STARTUP_MODE_PRODUCT_OPENING
## The scene to boot. Empty (the title's 開始新故事, BattleSceneRuntime.tscn launched directly,
## a campaign restart) opens the campaign's start_level (CampaignProgress.first_scenario_path);
## a pending campaign hand-off replaces it.
@export_file("*.json") var scenario_path: String = ""

var runtime_entrypoint: String = ENTRYPOINT_PRODUCT_OPENING
var first_battle_scenario: Dictionary = {}
var map_texture_path: String = ""
var map_objects_path: String = ""
var map_object_alignment_path: String = ""
var actor_walk_manifest_path: String = ""
var opening_timeline_path: String = ""
var message_text_evidence_path: String = ""
var logical_viewport_size: Vector2i = Vector2i(640, 480)
var map_objects_manifest: Dictionary = {}
var map_object_alignment_manifest: Dictionary = {}
var map_object_records: Array[Dictionary] = []
## EVEF placements whose object loops a WAV (obj_Data9 mapobjPlayBGSound, role
## background_sound in map_objects.json — the camp's 夜晚聲／鳥聲): one looping player each.
var background_sound_records: Array[Dictionary] = []
var map_object_placement: RefCounted = null
var actor_walk_manifest: Dictionary = {}
## Up-title walk frames shared by every battle (town job-up 010–020, level-37 052);
## looked up after the scenario's own manifest (ActorSpriteKey.frame_key).
var shared_actor_walk_manifest: Dictionary = {}
## Level actor_audio manifest and the shared job-up rows' sound bindings (010–020);
## looked up in that order by ActorSpriteKey.audio_binding.
var actor_audio_manifest: Dictionary = {}
var shared_actor_audio_manifest: Dictionary = {}
var opening_timeline_manifest: Dictionary = {}
var message_text_evidence: Dictionary = {}
var map_config: RefCounted = null
var camera_controller: RefCounted = null
## The only mutable battle truth this scene holds; written solely through apply_loop.
var play_loop: Dictionary = {}
## Rule operation named by the last apply_loop call (tests/support readback).
var loop_write_reason: String = ""
## The AI decision entry point (step_ai_turn) gets no source: every AI turn draws from the
## loop's global stream `global_rng`, which the battle took from the process stream when it
## was created (GlobalRandomStream.session) and hands back on every apply_loop. Settlement
## draws from the loop's saved damage stream (DamageRandomStream).
var scene_timeline: RefCounted = null
var opening_timeline_mode: String = "first_control"
var interaction_state: String = "idle"
var selected_unit_id: String = ""
var pending_move_revert: bool = false
var pending_move_original_grid: Vector2i = Vector2i.ZERO
var cancel_evidence_id: String = ""
var last_move_result: Dictionary = {}
var last_attack_result: Dictionary = {}
var unit_grid_coords: Dictionary = {}
var pointer_logical_position: Vector2 = Vector2.ZERO
var pointer_inside_window := false
var pointer_world_position: Vector2 = Vector2.ZERO
var hovered_grid_cell: Vector2i = Interaction.NO_CELL
var hovered_unit_id: String = ""
var hovered_command_id: String = ""
var held_command_id: String = ""
var move_overlay_cells: Array[Vector2i] = []
var attack_overlay_cells: Array[Vector2i] = []
var last_attack_reject: Dictionary = {}
var ai_playback_active: bool = false
var ai_playback_wait_remaining: float = 0.0
## winfail_runtime.fired entries already handed to the coordinator's cutscene mode.
var script_cutscene_consumed: int = 0
## Position-object deletes are presentation mirrors; the mutable battle request remains in PlayLoop.
var _script_object_delete_consumed: int = 0
const AI_PLAYBACK_STEP_SECONDS := 0.35

@onready var world_root: Node2D = $World
@onready var map_objects_back: Node2D = $World/MapObjectsBack
@onready var actors_root: Node2D = $World/Actors
@onready var map_objects_foreground: Node2D = $World/MapObjectsForeground
@onready var map_backdrop: Sprite2D = $World/MapBackdrop
@onready var move_overlay: Node2D = $World/MoveOverlay
@onready var camera: Camera2D = $Camera2D
@onready var action_menu: Control = $UI/ActionMenu
@onready var opening_overlay: Control = $UI/OpeningOverlay
var magic_panel: Control
var departure_view: Node


func _ready() -> void:
	$BattleMusic.volume_db = GameSettings.MUSIC_PLAYER_DB
	$BattleMusic.bus = GameSettings.music_bus() # 設定選項 音樂音量 routes music through its own bus
	_bootstrap_runtime()
	departure_view = preload("res://game/battle/scene/BattleDepartureView.gd").new()
	departure_view.name = "DepartureView"
	departure_view.runtime = self
	add_child(departure_view)
	if _is_world_map():
		world_map_runtime = WorldMapRuntime.new()
		world_map_runtime.name = "WorldMapRuntime"
		world_map_runtime.runtime = self
		add_child(world_map_runtime)
	elif first_battle_scenario.has("opening") and scene_timeline != null:
		opening_coordinator = BattleOpeningCoordinator.new()
		opening_coordinator.name = "OpeningCoordinator"
		opening_coordinator.runtime = self
		add_child(opening_coordinator)
	menus.build_panels()
	var interface_audio := _load_json(BattleScenario.resource_path(first_battle_scenario, "interface_audio"))
	ui_sounds = interface_audio.get("sounds", {})
	ui_audio = AudioStreamPlayer.new()
	ui_audio.volume_db = -6.0
	add_child(ui_audio)
	$BattlePresentation.level_up_presented.connect(play_growth_sound)
	var end_layer := CanvasLayer.new()
	end_layer.layer = 10
	add_child(end_layer)
	_end_fade = ColorRect.new()
	_end_fade.size = Vector2(640, 480)
	_end_fade.color = Color(0, 0, 0, 0)
	_end_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_end_fade.hide()
	end_layer.add_child(_end_fade)
	settlement_controller = preload("res://game/battle/scene/BattleSettlementController.gd").new()
	settlement_controller.runtime = self
	add_child(settlement_controller)
	treasure_view = preload("res://game/battle/scene/BattleTreasurePresentation.gd").new()
	treasure_view.runtime = self
	_read_treasure_option()
	add_child(treasure_view)
	add_to_group(RemakeOptionsPage.LISTENERS)
	campaign_progress = preload("res://game/battle/runtime/GrowthCampaignProgress.gd").new()
	campaign_progress.name = "CampaignProgress"
	campaign_progress.runtime = self
	add_child(campaign_progress)
	_apply_startup_mode()
	get_window().mouse_exited.connect(scene_input.disarm_pointer_scroll)
	get_window().focus_exited.connect(scene_input.disarm_pointer_scroll)


## Closing the window stops the music while the main loop still runs: a stop only queues the
## playback for removal, which the audio thread finishes on its next mix step. Stopped only at
## tree teardown, the engine can shut the audio driver first and the still-listed playback
## keeps its ogg alive ("2 resources still in use at exit"). Leaving the tree releases the
## player's own stream reference as well.
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_EXIT_TREE:
		var music := get_node_or_null("BattleMusic") as AudioStreamPlayer
		if music != null:
			music.stop()
			music.stream = null


func _process(delta: float) -> void:
	advance_camera(delta)
	stamp_presentation_view()
	ai_move_preview.tick(delta)
	if overlays != null: overlays.sync_unit_highlights()
	if treasure_view != null: treasure_view.hide_hint()
	if settlement_controller != null: settlement_controller.autoload_checkpoint()
	if opening_coordinator != null and opening_coordinator.active:
		opening_coordinator.tick(delta)
		return
	if world_map_runtime != null and world_map_runtime.active:
		world_map_runtime.tick(delta)
		return
	if maybe_start_script_cutscene():
		return
	$BattlePresentation.refresh(play_loop, map_config, interaction_state != Interaction.OPENING_TIMELINE, not has_actor_motion(), delta)
	ScriptPresentation.hold_controls(self)
	if treasure_view != null and treasure_view.tick(delta):
		menus.set_action_menu_visible(false)
		return
	if settlement_controller.tick():
		_reset_end_fade()
		return
	var finished: bool = $BattlePresentation.battle_finished
	if modal_open():
		$BattlePresentation.status_label.hide()
		$BattlePresentation.combat_label.hide()
	if finished:
		overlays.set_move_overlay_visible(false)
		if ai_playback_active:
			_finish_ai_playback()
		if not modal_open(): _advance_battle_end(delta)
	else:
		_reset_end_fade()
	if $BattlePresentation.dialogue_active() or modal_open() or $BattlePresentation.combat_busy(play_loop) or finished:
		menus.set_action_menu_visible(false)
		return
	# 0x442720 phase 8: the level-up window follows the EXP／$／LEVEL UP floats and precedes
	# the next hand-off, for any player member — the enemy turn's counter included.
	if menus.offer_pending_growth():
		return
	if interaction_state == Interaction.ACTION_MENU and not ai_playback_active and not has_actor_motion():
		if BattlePlayLoop.action_exhausted(play_loop):
			apply_loop(BattlePlayLoop.finish_exhausted_action(play_loop), "finish_exhausted_action")
			resume_turn_presentation()
			return
	tick_ai_playback(delta)
	if interaction_state in Interaction.PLAYER_CONTROL and not has_actor_motion():
		var pan := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
		if pan == Vector2.ZERO and camera_controller != null:
			pan = camera_controller.edge_direction(pointer_logical_position, pointer_inside_window and get_window().has_focus())
		if camera_controller != null and camera_controller.pan(pan, delta, BattleCameraController.EDGE_SCROLL_PIXELS_PER_SECOND):
			scene_input.update_pointer_hit(pointer_logical_position)
		$BattlePresentation.preview_target(play_loop, hovered_unit_id, hovered_grid_cell)
		overlays.refresh_skill_footprint(hovered_grid_cell)
		$BattlePresentation.show_selection(play_loop, hovered_grid_cell, grid_cell_center_to_logical_position(hovered_grid_cell), grid_cell_size())
	if interaction_state == Interaction.ACTION_MENU:
		menus.set_action_menu_visible(selected_unit_id != "")
	else:
		menus.update_action_menu_anchor()


func start_dev_first_control_harness() -> void:
	## Development seam: skip the product opening. A coordinator that already started
	## the opening is finished here (actors snap to their PlayLoop cells, the timeline
	## cursor rests on first_control_ready) instead of ticking on over the harness.
	if runtime_entrypoint == ENTRYPOINT_DEV_FIRST_CONTROL_HARNESS and not play_loop.is_empty() and interaction_state != Interaction.OPENING_TIMELINE:
		return # already at first control through this seam (startup_mode dev_first_control)
	runtime_entrypoint = ENTRYPOINT_DEV_FIRST_CONTROL_HARNESS
	if opening_coordinator != null and opening_coordinator.active and not opening_coordinator.cutscene_mode:
		opening_coordinator._finish("dev_first_control_harness")
	else:
		enter_first_control_state("dev_first_control_harness")


func _input(event: InputEvent) -> void:
	scene_input.handle_input(event)


## A battle modal (status／item／magic／growth) other than `ignoring` is up. The single
## "panel is open" predicate for the frame loop, command entry, treasure hint,
## quiet-boundary saves (which ignore the status sheet they are raised from) and the
## turn-end cue.
func modal_open(ignoring: Control = null) -> bool:
	for panel in modal_panels:
		if panel != ignoring and panel.visible:
			return true
	return false


## OPT-TREASURE read point (docs/OPTIONS.md): original keeps hidden chests undrawn; 全部畫出
## draws every chest. Read when the scene is built and again when the 重製選項 page closes.
func _read_treasure_option() -> void:
	treasure_view.reveal_all_chests = not GameOptions.is_original("OPT-TREASURE")


## The 重製選項 page closed with a changed value (RemakeOptionsPage.LISTENERS, from 設定選項 or
## the Tab hotkey): the chests redraw under the new OPT-TREASURE at once.
func remake_options_changed() -> void:
	if treasure_view == null:
		return
	_read_treasure_option()
	treasure_view.sync_boxes()


func viewport_to_logical_position(position: Vector2) -> Vector2:
	if camera_controller == null:
		return position
	return camera_controller.viewport_to_logical(position, get_viewport_rect().size)


func logical_to_viewport_position(logical_position: Vector2) -> Vector2:
	if camera_controller == null:
		return logical_position
	return camera_controller.logical_to_viewport(logical_position, get_viewport_rect().size)


func logical_to_world_position(logical_position: Vector2) -> Vector2:
	if camera_controller == null:
		return logical_position
	return camera_controller.logical_to_world(logical_position)


func world_to_logical_position(world_position: Vector2) -> Vector2:
	if camera_controller == null:
		return world_position
	return camera_controller.world_to_logical(world_position)


func grid_cell_center_to_logical_position(coord: Vector2i) -> Vector2:
	if camera_controller == null:
		return Vector2.ZERO
	return camera_controller.grid_cell_center_to_logical(coord)


func unit_grid_coord(unit_id: String) -> Vector2i:
	return unit_grid_coords.get(unit_id, Interaction.NO_CELL)


func grid_at_logical_position(logical_position: Vector2) -> Vector2i:
	if camera_controller == null:
		return Interaction.NO_CELL
	var coord: Vector2i = camera_controller.grid_at_logical(logical_position)
	return coord if grid_coord_in_world(coord) else Interaction.NO_CELL


func select_actor(unit_id: String) -> void:
	if BattlePlayLoop.loot_waiting(play_loop): return
	if ai_playback_active or has_actor_motion() or $BattlePresentation.combat_busy(play_loop) or $BattlePresentation.dialogue_active():
		return
	var actor := actor_node_for_unit(unit_id)
	if actor == null or not is_player_commandable_unit(unit_id):
		return
	if not play_loop.is_empty():
		apply_loop(BattlePlayLoop.select_player_unit(play_loop, unit_id), "select_player_unit")
		if str(play_loop.get(LoopKeys.SELECTED_UNIT_ID, "")) != unit_id:
			return
	selected_unit_id = unit_id
	interaction_state = Interaction.ACTION_MENU
	cancel_evidence_id = ""
	menus.rebuild_action_menu_buttons()
	menus.set_action_menu_visible(true)
	overlays.set_move_overlay_visible(false)
	overlays.clear_attack_overlay()
	focus_camera_on_grid(unit_grid_coord(unit_id))


func cancel_current_interaction() -> void:
	if interaction_state == Interaction.MOVE_SELECT or interaction_state == Interaction.ATTACK_SELECT:
		if not play_loop.is_empty():
			apply_loop(BattlePlayLoop.cancel_interaction(play_loop), "cancel_interaction")
		interaction_state = Interaction.ACTION_MENU
		cancel_evidence_id = "move_select_rclick_return_retry"
		overlays.set_move_overlay_visible(false)
		overlays.clear_attack_overlay()
		menus.rebuild_action_menu_buttons()
		menus.set_action_menu_visible(true)


func move_selected_actor_to_grid(target_grid: Vector2i) -> void:
	if has_actor_motion():
		return
	if selected_unit_id == "":
		return
	var actor := actor_node_for_unit(selected_unit_id)
	if actor == null:
		return
	var original_grid: Vector2i = unit_grid_coords.get(selected_unit_id, target_grid)
	var grid_path := BattlePlayLoop.movement_path(play_loop, selected_unit_id, target_grid)
	if grid_path.is_empty():
		return
	var next := BattlePlayLoop.move_unit_to(play_loop, target_grid)
	if BattlePlayLoop.unit_coords(next).get(selected_unit_id, original_grid) != target_grid:
		apply_loop(next, "move_unit_to_rejected")
		return
	# The walk starts before the mirror step so the actor tweens from its origin
	# instead of snapping to the settled cell (apply_loop leaves moving actors alone).
	var path := _world_path(grid_path)
	last_move_result = actor.move_along(path, path.size() * MOVE_CELL_PRESENTATION_SECONDS)
	apply_loop(next, "move_unit_to")
	interaction_state = Interaction.ACTION_MENU
	cancel_evidence_id = ""
	overlays.set_move_overlay_visible(false)
	overlays.clear_attack_overlay()
	menus.rebuild_action_menu_buttons()
	menus.set_action_menu_visible(true)
	# defProcPlayer 0x443f5a: the camera walks with the walker (camera_panel_motion §1).
	if camera_controller != null:
		camera_controller.follow_walk(actor_world_position_for_grid(original_grid), path)


func cancel_pending_move() -> void:
	if selected_unit_id == "" or not pending_move_revert:
		return
	var actor := actor_node_for_unit(selected_unit_id)
	var next := BattlePlayLoop.cancel_pending_move(play_loop)
	if next == play_loop:
		return
	apply_loop(next, "cancel_pending_move")
	var restored: Vector2i = BattlePlayLoop.unit(play_loop, selected_unit_id)["coord"]
	if actor != null:
		actor.move_along([actor_world_position_for_grid(restored)], 0.0)
		actor.play_state("idle", "0")
	cancel_evidence_id = "move_select_rclick_return_retry"
	mirror_interaction()
	overlays.set_move_overlay_visible(interaction_state == Interaction.MOVE_SELECT)
	overlays.clear_attack_overlay()
	menus.rebuild_action_menu_buttons()
	menus.set_action_menu_visible(interaction_state == Interaction.ACTION_MENU)
	focus_camera_on_grid(restored)


func attack_selected_target(target_unit_id: String) -> void:
	if selected_unit_id == "" or play_loop.is_empty():
		return
	apply_loop(BattlePlayLoop.attack_target(play_loop, target_unit_id), "attack_target")
	finish_attack_attempt()


func attack_selected_coord(coord: Vector2i) -> void:
	if selected_unit_id == "" or play_loop.is_empty():
		return
	apply_loop(BattlePlayLoop.attack_coord(play_loop, coord), "attack_coord")
	finish_attack_attempt()


func finish_attack_attempt() -> void:
	last_attack_result = play_loop.get(LoopKeys.LAST_ATTACK, {})
	last_attack_reject = play_loop.get(LoopKeys.LAST_ATTACK_REJECT, {})
	var rejected := not last_attack_reject.is_empty() and not bool(play_loop.get(LoopKeys.ATTACKED_THIS_ACTION, false))
	if rejected:
		# Stay in attack_select so the player can click a valid adjacent enemy.
		interaction_state = Interaction.ATTACK_SELECT
		overlays.refresh_attack_overlay()
		menus.set_action_menu_visible(false)
		return
	mirror_interaction()
	overlays.clear_attack_overlay()
	menus.rebuild_action_menu_buttons()
	menus.set_action_menu_visible(interaction_state == Interaction.ACTION_MENU)


func resume_turn_presentation() -> void:
	if play_loop.is_empty():
		return
	# Rule operations have already chosen the next actor. Starting presentation
	# must never end that actor merely because it is another controllable player.
	mirror_interaction()
	held_command_id = ""
	selected_unit_id = str(play_loop.get(LoopKeys.SELECTED_UNIT_ID, ""))
	ai_playback_active = false
	ai_playback_wait_remaining = 0.0
	menus.set_action_menu_visible(false)
	overlays.set_move_overlay_visible(false)
	overlays.clear_attack_overlay()
	_sync_from_play_loop()
	if interaction_state == Interaction.AI_RESOLVING:
		ai_playback_active = true
		ai_playback_wait_remaining = 0.05
	elif interaction_state == Interaction.ACTION_MENU:
		menus.rebuild_action_menu_buttons()
		menus.set_action_menu_visible(selected_unit_id != "")
		if selected_unit_id != "":
			focus_camera_on_grid(unit_grid_coord(selected_unit_id))


func maybe_start_script_cutscene() -> bool:
	## A winfail status the interpreter fired (round hook, strike or outcome) whose
	## scenario status timeline has playable events is replayed by the coordinator
	## before the battle continues or finishes. Consumption is by
	## fired-entry index, so every firing of a self re-arming event replays once.
	if play_loop.is_empty() or (opening_coordinator != null and opening_coordinator.active):
		return false
	var winfail_runtime: Dictionary = play_loop.get(LoopKeys.WINFAIL_RUNTIME, {})
	if winfail_runtime.is_empty():
		return false
	var fired: Array = winfail_runtime.get("fired", [])
	ScriptPresentation.reserve_dialogue(self)
	if script_cutscene_consumed >= fired.size():
		return false
	if has_actor_motion() or ScriptPresentation.prerequisites_busy(self) or $BattlePresentation.dialogue_active() or BattlePlayLoop.loot_waiting(play_loop) or growth_panel.visible or menus.terminal_growth_pending():
		return false
	var timelines: Dictionary = (first_battle_scenario.get("scenario_rules", {}) as Dictionary).get("status_timelines", {})
	while script_cutscene_consumed < fired.size():
		var entry: Dictionary = fired[script_cutscene_consumed]
		script_cutscene_consumed += 1
		if bool(entry.get("presentation_inlined", false)):
			continue
		var key := str(entry.get("key", ""))
		var timeline: Dictionary = timelines.get(key, {})
		if int(timeline.get("playable_event_count", 0)) <= 0 and not ScriptPresentation.BattlePoisonGasPresentation.has_gas(play_loop, script_cutscene_consumed - 1):
			# A status that carried actSetNextPlayLevelEvent but has nothing to play
			# still ends an undecided battle (event-only hand-off) — otherwise the
			# scene could never leave. Today 73／78／900 all have playable chains.
			if key != "" and key == str(play_loop.get(LoopKeys.NEXT_LEVEL_EVENT_STATUS, "")) and not BattleOutcome.decided(play_loop):
				_ensure_script_coordinator()
				on_script_cutscene_finished(key)
				return true
			continue
		var events: Array = ScriptActorsPresentation.attach(self, timeline.get("events", []), script_cutscene_consumed - 1)
		events = ScriptPresentation.BattlePoisonGasPresentation.attach(play_loop, events, script_cutscene_consumed - 1)
		# A chain gate (actCheckEventNotExist) that ended this firing: the rest never ran.
		var chain_stop := int(entry.get("chain_stop_index", -1))
		if chain_stop >= 0:
			events = events.filter(func(event): return int(event.get("source_action_index", 0)) < chain_stop)
		mark_cutscene_messages_shown(key, events)
		overlays.clear_attack_overlay()
		ScriptPresentation.defer_extra_action(self)
		_ensure_script_coordinator()
		opening_coordinator.start_cutscene(key, events)
		if opening_coordinator.active:
			return true
	return false


## Script-bearing development/configured battles need not have a product opening.
## They still use the same coordinator for triggered events and event-only hand-offs.
func _ensure_script_coordinator() -> void:
	if opening_coordinator != null:
		return
	opening_coordinator = BattleOpeningCoordinator.new()
	opening_coordinator.name = "OpeningCoordinator"
	opening_coordinator.runtime = self
	add_child(opening_coordinator)


func mark_cutscene_messages_shown(status_key: String, events: Array) -> void:
	## The cutscene pages the chain's messages in script order; the presentation's
	## story-dialogue queue (BattleScenarioRuleAdapter.story_dialogue_messages, keyed
	## by status or outcome) must not page them again afterwards.
	var keys: Array[String] = [status_key]
	if BattleOutcome.decided(play_loop):
		keys.append(BattleScenarioRuleAdapter.TERMINAL_DIALOGUE_KEY)
	for event_value in events:
		if typeof(event_value) != TYPE_DICTIONARY:
			continue
		var event: Dictionary = event_value
		if not str(event.get("kind", "")).begins_with("dialogue_message"):
			continue
		for message_id in [str(event.get("message_id", "")), str(event.get("message_id_false", ""))]:
			if message_id == "":
				continue
			for key in keys:
				$BattlePresentation.mark_story_message_shown("%s:%s" % [key, message_id])


func on_script_cutscene_finished(_status_key: String) -> void:
	## Resolve status changes selected or fired inside the completed cutscene only
	## after its presentation timeline has finished.
	apply_loop(BattlePlayLoop.resolve_outcome(play_loop), "resolve_outcome_after_cutscene")
	## An event-only terminal (WINFAIL073 event_2 / WINFAIL078 event_3 / WINFAIL900
	## event_4) has no win status deciding the battle: the fired event itself carries
	## actSetNextPlayLevelEvent. Only that event's cutscene ends the scene, through the
	## existing scene-end handoff. The default next_level_event prefilled from the win
	## section (WinfailScenarioRules) never does — otherwise every mid-battle dialogue
	## event (WINFAIL010 event_6 at round 5) would leave the battle for the world map.
	var event_handoff: Array = play_loop.get(LoopKeys.NEXT_LEVEL_EVENT, []).duplicate()
	if not BattleOutcome.decided(play_loop) and opening_coordinator != null and _status_key != "" and str(play_loop.get(LoopKeys.NEXT_LEVEL_EVENT_STATUS, "")) == _status_key and not event_handoff.is_empty():
		opening_coordinator.next_level_event = event_handoff.duplicate()
		opening_coordinator._finish_story("event_only_" + _status_key)
		return
	## Back from a script cutscene: an undecided battle resumes its turn
	## presentation from the settled PlayLoop state; a decided one lets the result
	## page appear through the normal refresh. Departed units stay hidden (apply_loop's mirror step).
	if not BattleOutcome.decided(play_loop):
		resume_turn_presentation()


func tick_ai_playback(delta: float) -> void:
	if BattlePlayLoop.loot_waiting(play_loop): return
	if not ai_playback_active or play_loop.is_empty():
		return
	ai_playback_wait_remaining -= maxf(delta, 0.0)
	# A runtime that processes steps the preview in _process (it must run even while a
	# pending move_then_attack receipt holds _process before this call); a harness driving
	# playback by hand with processing off steps it here.
	if not is_processing(): ai_move_preview.tick(delta)
	if has_actor_motion() or $BattlePresentation.combat_busy(play_loop):
		return
	var last_action: Dictionary = play_loop.get(LoopKeys.LAST_AI_ACTION,{})
	if last_action.get("kind") == "move_then_item":
		# Receipt sequence deduplicates feedback; wait for the actual move before
		# showing the shared use-item effect at the recipient's settled position.
		present_item_effect(last_action["item_use"])
	if $BattlePresentation.item_feedback_busy(): return
	if ScriptPresentation.pending(self): return
	if str(play_loop.get(LoopKeys.INTERACTION, "")) != Interaction.AI_RESOLVING:
		_finish_ai_playback()
		return
	if ai_playback_wait_remaining > 0.0:
		return
	stamp_presentation_view()
	var next := BattlePlayLoop.step_ai_turn(play_loop)
	# The receipt's walk starts before the mirror step so the actor tweens from its origin.
	_present_ai_action(next.get(LoopKeys.LAST_AI_ACTION, {}))
	apply_loop(next, "step_ai_turn")
	mirror_interaction()
	if interaction_state != Interaction.AI_RESOLVING and not has_actor_motion() and not $BattlePresentation.combat_busy(play_loop) and not $BattlePresentation.item_feedback_busy():
		_finish_ai_playback()
		return
	ai_playback_wait_remaining = AI_PLAYBACK_STEP_SECONDS


func has_actor_motion() -> bool:
	if ai_move_preview.busy():
		return true
	for actor in actors_root.get_children():
		if actor is ActorRuntime and actor.is_moving():
			return true
	return false


func _world_path(grid_path: Array) -> Array:
	var points: Array = []
	# The first grid is the current position, not a movement segment.
	for cell in grid_path.slice(1):
		points.append(actor_world_position_for_grid(cell))
	return points


func _present_ai_action(action: Dictionary) -> void:
	var actor_id := str(action.get("actor_id", ""))
	if actor_id == "":
		return
	var actor := actor_node_for_unit(actor_id)
	if actor == null:
		return
	var kind := str(action.get("kind", ""))
	if kind in ["move", "move_then_attack", "move_then_item"]:
		# The reach shows at the origin first; the walk (and its navigation cue) starts when
		# the preview ends (BattleAiMovePreview). The loop has not been mirrored yet, so
		# play_loop and unit_grid_coords still hold the origin.
		var path := _world_path(action.get("path", []))
		var origin := unit_grid_coord(actor_id)
		ai_move_preview.begin(action, actor, path, path.size() * MOVE_CELL_PRESENTATION_SECONDS, origin, BattlePlayLoop.movement_cells(play_loop, actor_id))
		return
	elif kind == "attack":
		# The camera goes to the attacker／caster, not the target: BattleAttackCue's camera stage
		# (0x43bf30), then its glide moves the view with the cursor.
		actor.play_state("idle", "0")
	elif kind == "use_item":
		# The item lead-in (BattleItemUsePresentation → BattleAttackCue.begin_item) moves the camera.
		present_item_effect(action["item_use"])
	elif kind in ["wait", "paralysis_skip"]:
		focus_camera_on_grid(unit_grid_coord(actor_id))
	$BattlePresentation.navigation_cue.begin(action, actor, map_config)


## sfxUseItem plays as the item applies (after an AI's lead-in), from the item presentation.
func present_item_effect(effect: Dictionary) -> void:
	var actor := actor_node_for_unit(str(effect["target_id"]))
	if actor != null:
		$BattlePresentation.show_item_use(effect, actor.position)


func _finish_ai_playback() -> void:
	ai_playback_active = false
	ai_playback_wait_remaining = 0.0
	_sync_from_play_loop()
	mirror_interaction()
	selected_unit_id = str(play_loop.get(LoopKeys.SELECTED_UNIT_ID, ""))
	if interaction_state == Interaction.ACTION_MENU and selected_unit_id != "":
		menus.rebuild_action_menu_buttons()
		menus.set_action_menu_visible(true)
		focus_camera_on_grid(unit_grid_coord(selected_unit_id))
	else:
		menus.set_action_menu_visible(false)


## Headless/tests: advance AI playback by an explicit delta (bypasses frame timing).
func advance_ai_playback(delta: float = AI_PLAYBACK_STEP_SECONDS) -> void:
	if not ai_playback_active:
		return
	_finish_ai_presentation()
	ai_playback_wait_remaining = 0.0
	tick_ai_playback(maxf(delta, 0.001))
	# The named fast-forward skips the reach preview: the step's walk starts at once.
	ai_move_preview.finish()


func _finish_ai_presentation() -> void:
	# Explicit fast-forward also settles the previous visual step, without replaying its sound cues.
	ai_move_preview.finish()
	for actor in actors_root.get_children():
		if actor is ActorRuntime and actor.is_moving() and not actor.last_path.is_empty():
			actor.move_along([actor.last_path.back()], 0.0)
			actor.play_state("idle", "0")
	# This explicitly named fast-forward API drains presentation as well as motion;
	# production frames never skip the range/cursor/target stages.
	var presentation := $BattlePresentation
	presentation.finish_item_feedback()
	presentation.extra_action_cue.finish(play_loop)
	presentation.turn_end_cue.finish(play_loop)
	presentation.navigation_cue.finish()
	if presentation.has_pending_combat(play_loop):
		presentation.refresh(play_loop, map_config, true, true)
		presentation.refresh(play_loop, map_config, true, true, presentation.attack_cue.duration)
	for _clip in range(presentation.cutin.clips.size()):
		if presentation.cutin.busy():
			presentation.cutin._process(100.0)
	presentation.aftermath.finish(self)
	presentation.magic_impact.finish()


## Headless/tests: resolve remaining AI turns immediately while still syncing actor positions.
func flush_ai_playback() -> void:
	var guard := 0
	while ai_playback_active and guard < 24:
		advance_ai_playback(AI_PLAYBACK_STEP_SECONDS)
		guard += 1


func _bootstrap_runtime() -> void:
	campaign_handoff = CampaignProgress.take_handoff()
	if not campaign_handoff.is_empty():
		scenario_path = str(campaign_handoff.get("scenario_path", scenario_path))
	if scenario_path == "":
		scenario_path = CampaignProgress.first_scenario_path(CampaignProgress.load_campaign())
	first_battle_scenario = BattleScenario.load_file(scenario_path)
	if not bool(first_battle_scenario.get("ok", false)):
		push_error("Battle scenario failed to load: %s" % str(first_battle_scenario.get("error", "unknown")))
		return
	if ConditionalPartyRules.has_conditional_party(first_battle_scenario):
		# Random encounters install only the party members the campaign carries (有才產生);
		# without a hand-off every slot is fielded (dev / test launch).
		var conditional := ConditionalPartyRules.apply(first_battle_scenario, campaign_handoff.get("carry", {}) if typeof(campaign_handoff.get("carry")) == TYPE_DICTIONARY else {})
		first_battle_scenario = conditional["scenario"]
		conditional_party_receipt = conditional["receipt"]
	if BattleScenarioRuleAdapter.adapter_id(first_battle_scenario) == "":
		push_error("Unsupported battle scenario adapter: %s" % str(first_battle_scenario.get("schema", "")))
		return
	map_texture_path = BattleScenario.resource_path(first_battle_scenario, "map_texture")
	map_objects_path = BattleScenario.resource_path(first_battle_scenario, "map_objects")
	map_object_alignment_path = BattleScenario.resource_path(first_battle_scenario, "map_object_alignment")
	actor_walk_manifest_path = BattleScenario.resource_path(first_battle_scenario, "actor_walk_manifest")
	opening_timeline_path = BattleScenario.resource_path(first_battle_scenario, "opening_timeline")
	message_text_evidence_path = BattleScenario.resource_path(first_battle_scenario, "message_text_evidence")
	logical_viewport_size = BattleScenario.logical_viewport_size(first_battle_scenario)
	map_objects_manifest = load_optional_json(map_objects_path)
	map_object_alignment_manifest = load_optional_json(map_object_alignment_path)
	map_object_placement = MapObjectPlacement.from_alignment_manifest(map_object_alignment_manifest) if not map_object_alignment_manifest.is_empty() else null
	actor_walk_manifest = _load_json(actor_walk_manifest_path)
	shared_actor_walk_manifest = _load_json(ActorSpriteKey.SHARED_WALK_MANIFEST_PATH)
	actor_audio_manifest = _load_json(BattleScenario.resource_path(first_battle_scenario, "actor_audio"))
	shared_actor_audio_manifest = _load_json(ActorSpriteKey.SHARED_AUDIO_MANIFEST_PATH)
	opening_timeline_manifest = load_optional_json(opening_timeline_path)
	message_text_evidence = load_optional_json(message_text_evidence_path)
	# Both dialogue boards draw this scene's speakers from its own manifest; a scene
	# without `resources.portraits` (the world map) configures none and any speaker it
	# names is reported, never drawn from another chapter's table.
	if first_battle_scenario.get("resources", {}).has("portraits"):
		var portraits_path := BattleScenario.resource_path(first_battle_scenario, "portraits")
		opening_overlay.configure_portraits(portraits_path)
		$BattlePresentation.dialogue_view.configure_portraits(portraits_path)
	var map_texture: Texture2D = load(map_texture_path)
	if map_texture == null:
		push_error("Battle map texture failed to load: %s" % map_texture_path)
		return
	map_backdrop.texture = map_texture
	map_backdrop.centered = false
	map_backdrop.position = Vector2.ZERO

	map_config = MapSceneConfig.from_texture(
		str(first_battle_scenario.get("id", "battle_scene")),
		map_texture,
		logical_viewport_size,
		BattleScenario.grid_projection(first_battle_scenario)
	)
	$BattlePresentation.actors_root = actors_root
	$BattlePresentation.dialogue_manifest = message_text_evidence
	$BattlePresentation.audio_manifest = actor_audio_manifest
	$BattlePresentation.shared_audio_manifest = shared_actor_audio_manifest
	# The cut-in draws from the scene's own combat manifest; a scene without one (story
	# scenes, the big map) plays no combat.
	if first_battle_scenario.get("resources", {}).has("combat_animation"):
		$BattlePresentation.cutin.configure(BattleScenario.resource_path(first_battle_scenario, "combat_animation"))
	_configure_camera()
	if is_story_scene() or _is_world_map():
		# Story-only levels and the big map have no battle: the coordinator (or
		# WorldMapRuntime) owns the scene and hands the carried party onward.
		apply_loop({}, "no_battle_scene")
		unit_grid_coords.clear()
	else:
		_configure_play_loop()
	# No roster (story scene, big map): the first frame looks at the map origin cell.
	center_camera_on_grid(unit_grid_coords.get(str(first_battle_scenario["player_unit_id"]), Vector2i.ZERO))
	stage.spawn_map_objects()
	if not opening_timeline_manifest.is_empty():
		_configure_scene_timeline()
	menus.configure_action_menu()
	opening_overlay.hide()
	overlays.configure_move_overlay()


func is_story_scene() -> bool:
	return str(first_battle_scenario.get("level_kind", "")) == "story"


func _is_world_map() -> bool:
	return str(first_battle_scenario.get("level_kind", "")) == "world_map"


func _apply_startup_mode() -> void:
	if startup_mode == STARTUP_MODE_DEV_FIRST_CONTROL:
		start_dev_first_control_harness()
	elif opening_coordinator != null:
		opening_coordinator.start()
	elif world_map_runtime != null:
		world_map_runtime.start()
	else:
		push_error("Scenario %s has no product opening coordinator; use dev_first_control" % str(first_battle_scenario.get("id", "")))


func _loop_seed_overridden() -> bool:
	return DisplayServer.get_name() == "headless" and OS.get_environment(LOOP_SEED_ENV).is_valid_int()


func _loop_seed() -> int:
	return int(OS.get_environment(LOOP_SEED_ENV)) if _loop_seed_overridden() else Time.get_ticks_usec()


## Camera limits come first so the actors apply_loop spawns land on world cells; the
## first centring waits for the PlayLoop (_bootstrap_runtime).
func _configure_camera() -> void:
	camera_controller = BattleCameraController.create(camera, map_config, logical_viewport_size)
	camera_controller.configure_camera_limits()


func _configure_play_loop() -> void:
	var seed := _loop_seed()
	# The battle continues the process's global stream (not per battle, not carried).
	var loop := BattlePlayLoop.create([], "", first_battle_scenario, seed, GlobalRandomStream.session())
	if not campaign_handoff.is_empty():
		var carry: Dictionary = campaign_handoff.get("carry", {})
		if CampaignProgress.separate_party(CampaignProgress.load_campaign(), str(scenario_path)):
			carry = BattlePlayLoop.CampaignCarryRules.initialization_only(carry)
		loop = BattlePlayLoop.apply_campaign_carry(loop, carry)
	unit_grid_coords.clear()
	apply_loop(BattlePlayLoop.initialize_roster_growth(loop), "bootstrap")


## The single write to play_loop. `reason` names the rule operation (or the test
## fixture) that produced `next`; the presentation mirrors — ActorRuntime nodes and
## cells, departed／defeated visibility, `unit_grid_coords`, selection, pending move
## and last attack — follow in the same call. Actors mid-walk keep their tween; start
## a receipt's walk before applying its loop.
func apply_loop(next: Dictionary, reason: String) -> void:
	play_loop = next
	loop_write_reason = reason
	GlobalRandomStream.remember(next)
	_sync_from_play_loop()


## The scene's interaction state follows the loop's after a rule operation; only the
## opening coordinator sets a state the loop does not know (Interaction.OPENING_TIMELINE).
## Called on a loop apply_loop has just written, so the key is present.
func mirror_interaction() -> void:
	interaction_state = str(play_loop[LoopKeys.INTERACTION])


func _sync_from_play_loop() -> void:
	if play_loop.is_empty():
		return
	stage.spawn_scene_actors()
	_consume_script_position_object_deletes()
	var coords: Dictionary = BattlePlayLoop.unit_coords(play_loop)
	# winfail actDeleteObject / actWalkAndDelete departures recorded by the
	# interpreter: the PlayLoop roster keeps the record, the field does not show them.
	var departed: Array = (play_loop.get(LoopKeys.WINFAIL_RUNTIME, {}) as Dictionary).get("departed_unit_ids", [])
	for unit_id in coords.keys():
		var coord: Vector2i = coords[unit_id]
		unit_grid_coords[unit_id] = coord
		var actor := actor_node_for_unit(str(unit_id))
		if actor != null:
			if ScriptActorsPresentation.holds_actor(self, str(unit_id)): continue
			if ai_move_preview.holds(str(unit_id)): continue
			if not actor.is_moving():
				actor.position = actor_world_position_for_grid(coord)
			actor.visible = departed.find(str(unit_id)) == -1
	for unit_value in play_loop.get(LoopKeys.UNITS, []):
		if typeof(unit_value) != TYPE_DICTIONARY:
			continue
		var unit: Dictionary = unit_value
		var unit_id := str(unit.get("id", ""))
		var actor := actor_node_for_unit(unit_id)
		if unit.get("departed", false):
			unit_grid_coords.erase(unit_id)
			if actor != null and not ScriptPresentation.retain_actor(self, unit):
				actor.move_along([actor.position], 0.0)
				actor.play_state("idle", "0")
				actor.hide()
			continue
		if actor == null:
			continue
		stage.sync_actor_row(actor, unit)
		if bool(unit.get("defeated", false)):
			actor.visible = $BattlePresentation.retain_defeated_actor(play_loop, unit_id)
			unit_grid_coords.erase(unit_id)
	pending_move_revert = bool(play_loop.get(LoopKeys.PENDING_MOVE, false))
	if pending_move_revert:
		pending_move_original_grid = play_loop[LoopKeys.PENDING_MOVE_FROM]
	selected_unit_id = str(play_loop.get(LoopKeys.SELECTED_UNIT_ID, selected_unit_id))
	last_attack_result = play_loop.get(LoopKeys.LAST_ATTACK, last_attack_result)


func _consume_script_position_object_deletes() -> void:
	## actDeletePosObject is an object lifecycle request, not a unit departure.
	## Match the same candidate world anchors used during map-object spawning;
	## square-radius and process-code filtering mirror the static contract.
	var runtime: Dictionary = play_loop.get(LoopKeys.WINFAIL_RUNTIME, {})
	var requests: Array = runtime.get("object_delete_requests", [])
	while _script_object_delete_consumed < requests.size():
		var request: Dictionary = requests[_script_object_delete_consumed]
		_script_object_delete_consumed += 1
		var anchor := Vector2(float(request.get("x", 0)), float(request.get("y", 0)))
		var radius := maxf(float(request.get("range", 0)), 0.0)
		var process_code := str(request.get("proc_code", ""))
		for layer in [map_objects_back, map_objects_foreground]:
			if layer == null:
				continue
			for child in layer.get_children():
				if not (child is CanvasItem) or not child.visible or not child.has_meta("candidate_anchor_world"):
					continue
				if process_code != "" and str(child.get_meta("process_code", "")) != process_code:
					continue
				var candidate: Vector2 = child.get_meta("candidate_anchor_world")
				if absi(int(candidate.x - anchor.x)) <= radius and absi(int(candidate.y - anchor.y)) <= radius:
					child.visible = false


## The stand objects the STORY opening removed (PlayLoop opening_story_state.object_deletes:
## STORY037's statues under the guardians, 59's, 77's). Every entry into first control —
## after the opening, the dev harness that skips it — and every restored checkpoint runs
## this one cleanup, so a skipped opening leaves no statue drawn over a guardian. Idempotent.
func apply_opening_object_deletes() -> void:
	for request in play_loop.get("opening_story_state", {}).get("object_deletes", []):
		OpeningStoryObjects.hide_stand_objects(self, Vector2(float(request["x"]), float(request["y"])), maxf(float(request["range"]), 0.0), str(request["proc_code"]))


func _configure_scene_timeline() -> void:
	var events: Array = opening_timeline_manifest.get("events", [])
	if events.is_empty():
		push_error("Opening timeline contains no events: %s" % opening_timeline_path)
		return
	scene_timeline = SceneTimeline.from_events(events, "first_control_ready")
	opening_timeline_mode = "first_control"


func enter_first_control_state(source_event_id: String) -> void:
	if source_event_id == "dev_first_control_harness":
		BattleOpeningCoordinator.resume_skipped_music($BattleMusic, opening_timeline_manifest.get("events", []))
	if scene_timeline != null:
		scene_timeline.seek_to_event_id("first_control_ready")
	opening_timeline_mode = "first_control"
	held_command_id = ""
	cancel_evidence_id = ""
	pending_move_revert = false
	pending_move_original_grid = Vector2i.ZERO
	last_move_result = {}
	last_attack_result = {}
	if play_loop.is_empty():
		apply_loop(BattlePlayLoop.create([], "", first_battle_scenario, 1, GlobalRandomStream.session()), "first_control_without_loop")
	apply_opening_object_deletes()
	# Opening choices use the same status interpreter as in-battle cutscenes.
	# Resolve them at the first-control boundary, after the inserted branch played.
	apply_loop(BattlePlayLoop.resolve_outcome(play_loop), "resolve_outcome_at_first_control")
	if BattleOutcome.decided(play_loop):
		return
	var loop := BattlePlayLoop.begin_battle(play_loop)
	if source_event_id == "dev_first_control_harness":
		# This explicit harness skips presentation, but keeps the preceding NPC actions.
		while str(loop.get(LoopKeys.INTERACTION, "")) == Interaction.AI_RESOLVING and not BattlePlayLoop.loot_waiting(loop):
			loop = BattlePlayLoop.step_ai_turn(loop)
	apply_loop(loop, "begin_battle")
	if source_event_id == "dev_first_control_harness":
		# This named dev shortcut skips the prefix's visuals as well as its turns.
		# Preserve all committed NPC EXP/learning; production opening never uses it.
		_finish_ai_presentation()
	selected_unit_id = str(play_loop.get(LoopKeys.SELECTED_UNIT_ID, ""))
	mirror_interaction()
	menus.rebuild_action_menu_buttons()
	menus.set_action_menu_visible(selected_unit_id != "")
	overlays.set_move_overlay_visible(false)
	overlays.clear_attack_overlay()
	if interaction_state == Interaction.AI_RESOLVING:
		resume_turn_presentation()
	if selected_unit_id != "":
		focus_camera_on_grid(unit_grid_coord(selected_unit_id))


func _load_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_error("Missing BattleSceneRuntime JSON: %s" % path)
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("Unable to open BattleSceneRuntime JSON: %s" % path)
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("Invalid BattleSceneRuntime JSON: %s" % path)
		return {}
	return parsed


func load_optional_json(path: String) -> Dictionary:
	if path == "":
		return {}
	return _load_json(path)


func actor_node_for_unit(unit_id: String) -> Node:
	if actors_root == null:
		return null
	return actors_root.get_node_or_null(actor_node_name(unit_id))


func actor_node_name(unit_id: String) -> String:
	if unit_id == "leonard":
		return "ActorRuntimeLeonard"
	return "ActorRuntime_%s" % unit_id


func is_player_commandable_unit(unit_id: String) -> bool:
	if play_loop.is_empty():
		return false
	var unit: Dictionary = BattlePlayLoop.unit(play_loop, unit_id)
	return str(unit.get("battle_actor_role", "")) == "player_controlled" and bool(unit.get("player_commandable", false))


func actor_world_position_for_grid(coord: Vector2i) -> Vector2:
	if camera_controller == null:
		return Vector2.ZERO
	return camera_controller.grid_cell_center_world(coord)


func grid_coord_in_world(coord: Vector2i) -> bool:
	if map_config == null or coord.x < 0 or coord.y < 0:
		return false
	var top_left: Vector2 = map_config.grid_to_world(coord)
	var size: Vector2 = grid_cell_size()
	return top_left.x >= 0.0 and top_left.y >= 0.0 and top_left.x + size.x <= float(map_config.world_size.x) and top_left.y + size.y <= float(map_config.world_size.y)


func grid_cell_size() -> Vector2:
	if camera_controller == null:
		return Vector2(32.0, 32.0)
	return camera_controller.grid_cell_size()


## Cut to a cell (first frame, Home recenter, tests placing the view): no glide.
func center_camera_on_grid(coord: Vector2i) -> void:
	if coord == Interaction.NO_CELL:
		return
	if camera_controller != null and camera_controller.center_on_grid(coord):
		menus.update_action_menu_anchor()


## Battle focus (selection, AI turns, turn hand-off): the original's 0x43bf30 glide at the
## battle step (BattleCameraController.scroll_to_grid); _process steps it once per tick.
func focus_camera_on_grid(coord: Vector2i) -> void:
	if coord == Interaction.NO_CELL:
		return
	if camera_controller != null and camera_controller.scroll_to_grid(coord):
		menus.update_action_menu_anchor()


## The camera's top-left in map pixels is a read-only input of the rules (the original's
## 0x4c091c／0x4c0920, which 打人閃電 reads): stamped on the current loop before a rule
## operation reads it. Not a rule-state write — rules copy it through and never change it.
## Headless runs (autoplay, suites) step rules without playing the camera, so they leave it
## unset and the rules centre the ending actor instead.
func stamp_presentation_view() -> void:
	if camera_controller == null or map_config == null or play_loop.is_empty() or DisplayServer.get_name() == "headless":
		return
	var origin: Vector2 = map_config.grid_projection.get("origin", Vector2.ZERO)
	play_loop[LoopKeys.PRESENTATION_VIEW] = Vector2i((camera_controller.logical_to_world(Vector2.ZERO) - origin).floor())


## Steps a running camera glide; a moved view refreshes the pointer hit and menu anchor.
func advance_camera(delta: float) -> void:
	if camera_controller != null and camera_controller.advance(delta):
		if interaction_state in Interaction.PLAYER_CONTROL: scene_input.update_pointer_hit(pointer_logical_position)
		menus.update_action_menu_anchor()


func play_growth_sound(growth: Dictionary) -> void:
	if not growth.is_empty() and int(growth["level_after"]) > int(growth["level_before"]):
		play_ui_sound("level_up")


## The finished battle (BattlePresentation.battle_finished) fades to black and leaves by
## itself, as the original's 0x42cc10 (win) and 0x42cbd0 (lose) do. A victory whose pool
## cannot travel first reopens the loot window (GrowthCampaignProgress.hold_for_loot).
func _advance_battle_end(delta: float) -> void:
	if _battle_left or hold_finished_battle or not is_inside_tree() or get_tree().current_scene != self:
		return
	if CampaignProgress.has_pending():
		return # a script cutscene already armed this level's hand-off
	if _end_fade_seconds == 0.0 and BattleOutcome.won(play_loop) and campaign_progress.hold_for_loot():
		return
	# At least four frames each of hold and fade: a long frame (scene load, a stalled headless
	# tick) cannot skip them, as the original advances its transition one tick per frame.
	if _end_hold_seconds < END_HOLD_SECONDS:
		_end_hold_seconds += minf(delta, END_HOLD_SECONDS / 4.0)
		return
	_end_fade_seconds += minf(delta, END_FADE_SECONDS / 4.0)
	var weight := clampf(_end_fade_seconds / END_FADE_SECONDS, 0.0, 1.0)
	_end_fade.color.a = weight
	_end_fade.show()
	if weight >= 1.0:
		leave_finished_battle()


func _reset_end_fade() -> void:
	if (_end_fade_seconds == 0.0 and _end_hold_seconds == 0.0) or _battle_left: return
	_end_fade_seconds = 0.0
	_end_hold_seconds = 0.0
	_end_fade.hide()


## Defeat -> GAME OVER screen -> title (0x42cbd0 level 999 -> defProcGameOverBOSS 0x42aea0 ->
## 0x42cb90 level 0); the saved battle record and campaign position stay on disk for 戰場記錄.
## Victory -> the winfail win section's destination (CampaignProgress.start_next_battle); a
## battle outside the campaign (a development trial) returns to the title.
func leave_finished_battle() -> void:
	_battle_left = true
	$BattleMusic.stop()
	if BattleOutcome.lost(play_loop):
		get_tree().change_scene_to_file(GAME_OVER_SCENE)
	elif not campaign_progress.start_next_battle():
		get_tree().change_scene_to_file(TITLE_SCENE)


## 讀取戰場記錄 re-enters the level (original_music.md §3.1): StopMusic, then the loaded level's
## table track from the top (level_table_music; empty for levels >= 100, which stay silent).
func reset_after_load() -> void:
	_battle_left = false
	_end_fade_seconds = 0.0
	_end_hold_seconds = 0.0
	if _end_fade != null: _end_fade.hide()
	$BattleMusic.stop()
	BattleOpeningCoordinator.play_music_stream($BattleMusic, str(first_battle_scenario.get("level_table_music", {}).get("stream", "")))


func play_ui_sound(event: String) -> void:
	ui_audio.stream = load(str(ui_sounds[event]["res_path"]))
	ui_audio.play()
