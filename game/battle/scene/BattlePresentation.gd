extends Node2D
## Read-only presentation of the PlayLoop objective and the finished-battle flag; never owns battle state.
## provenance:
##   layout: runtime-reference docs/evidence_packets/runtime_observations/original_gameplay_reference/README.md#17
##     (objective text on the map)
##   layout: runtime-measured docs/evidence_packets/static_reverse/original_identity_bar.md#runtime-measured
##     (bottom identity strip on pointer-over a unit in move selection, not while the action ring is open)
##   layout: static-derived docs/evidence_packets/static_reverse/original_identity_bar.md
##     (the strip for any living unit under the cursor in every pick state, none in the action ring)
##   layout: static-derived docs/evidence_packets/runtime_observations/map_pose_floaters/README.md
##   layout: static-derived docs/evidence_packets/static_reverse/original_skill_function_bits.md
##   layout: remake-invented (caption placement above the numbers)
##   strings: resource-derived content/imported/hsl/chapter01/message_text_evidence.json
##   strings: static-derived docs/evidence_packets/static_reverse/original_skill_function_bits.md
##   strings: remake-invented
##     (objective board)
##   strings: remake-invented docs/OPTIONS.md
##     (OPT-INFO=公開 only: status／cure captions, 「N 個目標」 line, 命中 N%／2擊 line, 反擊／連擊／暴擊／閃避／擊倒
##     and HP／MP words over the numbers, strips never masked)
##   timing: static-derived docs/evidence_packets/static_reverse/original_tick_counts.md
##   timing: static-derived docs/evidence_packets/runtime_observations/map_pose_floaters/README.md
##   timing: static-derived docs/evidence_packets/static_reverse/original_map_strike.md
##   timing: static-derived docs/evidence_packets/static_reverse/original_cast_overlays.md#无条带起手序列
##   audio: resource-derived content/imported/hsl/shared/interface_audio/manifest.json
##   audio: resource-derived content/imported/hsl/chapter01/actor_audio.json

const BattleOutcome = preload("res://game/sim/BattleOutcome.gd")
signal experience_presented(growth: Dictionary)
signal level_up_presented(growth: Dictionary)

var _map_config: RefCounted
var cutin: CanvasLayer
var attack_cue: Node2D
var navigation_cue: Node2D
var movement_preview: Node2D
var extra_action_cue: CanvasLayer
var turn_end_cue: CanvasLayer
## loop.terrain_poison receipts already put into the hit state (−1 until the first refresh).
var terrain_poison_shown := -1
var status_label: Label
var combat_label: Label
## The battle is over and its last exchange, loot, level-up and dialogue have played: the
## runtime fades out and leaves (0x42cc10 win／0x42cbd0 lose — no result page). Tests and
## autoplay read this instead of a visible page.
var battle_finished := false
var actors_root: Node2D
const BattlePlayLoop = preload("res://game/sim/loop/BattlePlayLoop.gd")
const CoreCombatRules = preload("res://game/sim/CoreCombatRules.gd")
const GameOptions = preload("res://game/settings/GameOptions.gd")
const RemakeOptionsPage = preload("res://game/settings/RemakeOptionsPage.gd")
const RuleAdapter = preload("res://game/sim/BattleScenarioRuleAdapter.gd")
const ActorSpriteKey = preload("res://game/battle/runtime/ActorSpriteKey.gd")
const Timing = preload("res://game/battle/runtime/CombatPresentationTiming.gd")
const ShowNumberStyle = preload("res://game/battle/runtime/ShowNumberStyle.gd")
const Interaction = preload("res://game/sim/Interaction.gd")
const LoopKeys = preload("res://game/sim/LoopKeys.gd")
const DamageNumberFloater = preload("res://game/battle/scene/DamageNumberFloater.gd")
const ResultNumberFloater = preload("res://game/battle/scene/ResultNumberFloater.gd")
const MapHitState = preload("res://game/battle/scene/MapHitState.gd")
const StatusCatalog = preload("res://game/sim/StatusCatalog.gd")
## Where the original spawns a unit's numbers from its object (x, y), the cell centre: the magic
## channel (0x40aba0／0x40ac24) at y − 0x34, item use (0x444b2f) at y − 0x30.
const MAGIC_NUMBER_OFFSET := Vector2(0, -0x34)
## First-battle table (its presentation-side event/message queue names speakers by resource
## name id only): name id → portrait row. Scenario (winfail) dialogue resolves the speaking
## token to its bound unit instead (_story_speaker_actor) and reaches this table last.
const SPEAKER_PORTRAIT_ACTORS := {"0": "001", "1": "029", "2": "003", "305": "021", "376": "023", "377": "024", "382": "025", "307": "026"}
var audio_manifest: Dictionary = {}
## Job-up rows' sound bindings (010–020), looked up after `audio_manifest` by the unit's
## job-up target row (ActorSpriteKey.audio_binding).
var shared_audio_manifest: Dictionary = {}
var _shown_combat_sequence := 0
var _shown_item_sequence := 0
## The item use's HP／MP numbers (ResultNumberFloater, self-clocked), freed once deleted.
var item_use: Node2D
var status_feedback: CanvasLayer
var dialogue_manifest: Dictionary = {}
var dialogue_view: Control
var _shown_story_events: Array[String] = []
var _dialogue_messages: Array[Dictionary] = []
var target_vitals: Control
var selection_cursor: Control
var debug_hud := false
var aftermath: Node
var magic_impact: Node2D
## The map spell clip whose caster has taken the use_magic pose (_sync_cast_pose).
var _posed_clip: Dictionary = {}
## OPT-INFO (docs/OPTIONS.md) for the targeting screen, read once as it is entered
## (preview_target): 公開 adds the 命中 N%／2擊 line and shows every strip unmasked.
var info_public := false
## OPT-INFO=公開 for the same screen, read with info_public: the magic／support 「N 個目標」 line
## (kept apart from the strip mask it rides beside).
var targets_line := false
## The targeting interaction info_public was read for ("" off the targeting screens).
var _info_screen := ""
## OPT-INFO=公開: the strike words over the close-up (BattleCombatCutin untouched), freed when
## the clip that raised them leaves the cut-in queue.
var _cutin_words: Label
var _cutin_words_clip: Dictionary = {}
## OPT-GUIDE (docs/OPTIONS.md) for the escape phase, read when the scene is built and again when
## the 重製選項 page closes with a change (remake_options_changed): 提示 keeps a gold cell on
## every escape-zone cell while the phase lasts (the remake mark ESCAPEMARK 644178ea removed);
## 原版 draws only the script's obj_Story_Show_Pos marker (OpeningStoryObjects).
var escape_marks := false
var escape_rects: Array[Rect2] = []
## OPT-GUIDE for the move-select screen, read once as it is entered (show_selection): 提示 adds
## the path line, the 「移動 3/5」 cost caption and the reach captions; 原版 shows the range only.
var move_hints := false
## The targeting interaction move_hints was read for ("" off the targeting screens).
var _guide_screen := ""


func _ready() -> void:
	add_to_group("game_cursor_hiders")
	add_to_group(RemakeOptionsPage.LISTENERS)
	escape_marks = not GameOptions.is_original("OPT-GUIDE")
	cutin = preload("res://game/battle/scene/BattleCombatCutin.gd").new()
	add_child(cutin)
	cutin.impact.connect(_present_impact)
	cutin.released.connect(_present_release)
	status_feedback = CanvasLayer.new()
	status_feedback.layer = cutin.layer + 1
	add_child(status_feedback)
	magic_impact = preload("res://game/battle/scene/MagicImpactPresentation.gd").new()
	# Separate from status labels so poison/support keep their established layout.
	var receiver_layer := CanvasLayer.new()
	receiver_layer.layer = cutin.layer + 1
	add_child(receiver_layer)
	receiver_layer.add_child(magic_impact)
	attack_cue = preload("res://game/battle/scene/BattleAttackCue.gd").new()
	attack_cue.hide()
	add_child(attack_cue)
	item_use = preload("res://game/battle/scene/BattleItemUsePresentation.gd").new()
	item_use.name = "ItemUse"
	item_use.view = self
	add_child(item_use)
	navigation_cue = preload("res://game/battle/scene/BattleNavigationCue.gd").new()
	add_child(navigation_cue)
	movement_preview = preload("res://game/battle/scene/BattleMovementPreview.gd").new()
	add_child(movement_preview)
	extra_action_cue = preload("res://game/battle/scene/BattleExtraActionCue.gd").new()
	add_child(extra_action_cue)
	turn_end_cue = preload("res://game/battle/scene/BattleTurnEndCue.gd").new()
	add_child(turn_end_cue)
	z_index = 4090
	var ui := CanvasLayer.new()
	add_child(ui)
	status_label = Label.new()
	status_label.name = "BattleStatus"
	status_label.position = Vector2(12, 8)
	status_label.add_theme_font_size_override("font_size", 16)
	status_label.add_theme_color_override("font_shadow_color", Color.BLACK)
	status_label.add_theme_constant_override("shadow_offset_x", 2)
	status_label.add_theme_constant_override("shadow_offset_y", 2)
	ui.add_child(status_label)
	combat_label = Label.new()
	combat_label.position = Vector2(12, 424)
	combat_label.add_theme_font_size_override("font_size", 17)
	combat_label.add_theme_color_override("font_shadow_color", Color.BLACK)
	combat_label.add_theme_constant_override("shadow_offset_x", 2)
	combat_label.add_theme_constant_override("shadow_offset_y", 2)
	ui.add_child(combat_label)
	debug_hud = OS.get_cmdline_user_args().has("--debug-hud")
	target_vitals = preload("res://game/battle/scene/BattleVitals.gd").new()
	target_vitals.position = Vector2(0, 322)
	target_vitals.resist_gem_at = target_vitals.RESIST_STRIP_GEM_AT
	target_vitals.hide()
	ui.add_child(target_vitals)
	# 0x43b4e0 mode 3 (hover／target strip, 0x43e5bf push 3) sets the ST object's 0x10000.
	target_vitals.st_bar.shared_pulse = true
	selection_cursor = preload("res://game/battle/scene/BattleSelectionCursor.gd").new()
	ui.add_child(selection_cursor)
	dialogue_view = preload("res://game/battle/scene/BattleDialogue.gd").new()
	dialogue_view.name = "StoryDialogue"
	dialogue_view.position = Vector2(0, 320)
	ui.add_child(dialogue_view)
	aftermath = preload("res://game/battle/scene/BattleAftermath.gd").new()
	add_child(aftermath)
	aftermath.dialogue = dialogue_view
	aftermath.disposal_started.connect(_play_sound.bind("dead"))
	aftermath.experience_presented.connect(experience_presented.emit)
	aftermath.level_up_presented.connect(level_up_presented.emit)


## The final blow's level-up window (BattleSceneMenus.terminal_growth_pending) holds the victory
## dialogue and the battle end.
func _terminal_growth_pending() -> bool:
	var menus = get_parent().get("menus")
	return menus != null and menus.terminal_growth_pending()


func has_pending_combat(loop: Dictionary) -> bool:
	return int(loop.get(LoopKeys.LAST_COMBAT, {}).get("sequence", 0)) > _shown_combat_sequence


## `loot_turn`: the get-item window's own check — an aftermath holding its LEVEL UP for that
## window (0x442720 phase 4 before phase 6) does not keep the window shut.
func combat_busy(loop: Dictionary, loot_turn: bool = false) -> bool:
	var aftermath_busy: bool = aftermath.busy() and not (loot_turn and aftermath.holding_for_loot())
	return has_pending_combat(loop) or cutin.busy() or magic_impact.busy() or aftermath_busy or navigation_cue.busy() or item_feedback_busy() or extra_action_cue.busy(loop) or turn_end_cue.busy(loop)


func item_feedback_busy() -> bool:
	return item_use.busy()


func finish_item_feedback() -> void:
	# Presentation interruption/explicit fast-forward never settles another action.
	item_use.finish()


## One immutable receipt drives the same player／AI item beats (BattleItemUsePresentation), never
## an HP mutation: the AI lead-in, the user's use_magic pose (0x4449a7／0x440366／0x4404c7 call
## 0x4071e0 as 0x409e40 applies the item) with sfxUseItem and the Show_Magic_Star effect, then the
## numbers. `world_position` is the target's actor position.
func show_item_use(effect: Dictionary, world_position: Vector2) -> bool:
	var sequence := int(effect.get("sequence", 0))
	if sequence <= _shown_item_sequence: return false
	_shown_item_sequence = sequence
	var runtime := get_parent()
	var loop: Variant = runtime.get("play_loop") if runtime != null else null
	item_use.begin(effect, loop if loop is Dictionary else {}, _map_config, world_position)
	return true


## The map caster's use_magic pose (0x4071e0). A map spell's attacker object calls it as the cast
## lead's fade ends (0x402fd1, sub-state 4 at +0x84 = 32; 0x403128 for a caster without a lead),
## together with the Cast_Star burst and sfx 0x193: the clip's `released`, which ends the
## m_shape lead or, for a caster without one, the 8 shadow calls. Specials cut in and do not pose.
func _sync_cast_pose() -> void:
	if not cutin.busy():
		return
	var clip: Dictionary = cutin.clips[0]
	if is_same(clip, _posed_clip) or not str(clip["strike"].get("skill_id", "")).begins_with("magic:"):
		return
	if not bool(clip["release_emitted"]):
		return
	_posed_clip = clip
	_pose_unit(str(clip["strike"]["attacker_id"]))


func _pose_unit(unit_id: String) -> void:
	var runtime := get_parent()
	if unit_id == "" or runtime == null or not runtime.has_method("actor_node_for_unit"):
		return
	var actor = runtime.actor_node_for_unit(unit_id)
	if actor != null and actor.has_method("play_use_magic"):
		actor.play_use_magic()


## A settled cast's effect cells centred on any map cell (0x4100e0 does not test the range), for
## the AI lead-in's glide and target stages; an empty Callable for a normal attack. Flat, as
## the AI cast settles (only a player command cast reads BattlePlayLoop.player_cast_terrain).
static func _strike_area_at(loop: Dictionary, strike: Dictionary, origin: Vector2i) -> Callable:
	if not strike.has("skill_id"):
		return Callable()
	var fields: Dictionary = BattlePlayLoop.skill_fields(loop, str(strike["skill_id"]))
	var data: Dictionary = loop[LoopKeys.SKILL_TARGET_DATA]
	var map_size: Vector2i = loop[LoopKeys.MAP_SIZE]
	return func(cell: Vector2i) -> Array: return BattlePlayLoop.SkillTargetRules.effect_cells(cell, fields, data, map_size, origin)


func refresh(loop: Dictionary, map_config: RefCounted, playable: bool, combat_ready: bool = true, delta: float = 0.0) -> void:
	_map_config = map_config
	combat_label.hide()
	target_vitals.hide()
	selection_cursor.hide()
	movement_preview.hide()
	status_label.visible = playable and debug_hud
	var terminal_growth := _terminal_growth_pending()
	battle_finished = playable and combat_ready and not combat_busy(loop) and not BattlePlayLoop.loot_waiting(loop) and BattleOutcome.decided(loop) and not terminal_growth
	_refresh_combat_cue(loop, map_config, playable, combat_ready, delta)
	_refresh_objective(loop, map_config, playable)
	_sync_cast_pose()
	_sync_cutin_words()
	if playable and combat_ready and not cutin.busy() and not magic_impact.busy() and not has_pending_combat(loop):
		aftermath.advance(delta, get_parent())
		if not aftermath.busy() and not BattlePlayLoop.loot_waiting(loop) and not turn_end_cue.busy(loop) and not item_feedback_busy() and not terminal_growth:
			_queue_story_dialogue(loop)
	_update_dialogue_page()
	var runtime := get_parent()
	# A moving AI item belongs before final-action recovery. Do not wait for the
	# pending tail cue to finish before starting its prerequisite item playback.
	var ai_action: Dictionary = loop.get(LoopKeys.LAST_AI_ACTION, {})
	if playable and combat_ready and ai_action.get("kind") == "move_then_item":
		runtime.present_item_effect(ai_action["item_use"])
	var extra_owner := BattlePlayLoop.unit(loop, str(loop.get("extra_action", {}).get("owner_id", "")))
	var extra_point: Vector2 = runtime.grid_cell_center_to_logical_position(extra_owner["coord"]) if not extra_owner.is_empty() else Vector2.ZERO
	var quiet: bool = playable and combat_ready and not has_pending_combat(loop) and not cutin.busy() and not magic_impact.busy() and not aftermath.busy() and not navigation_cue.busy() and not item_feedback_busy() and not dialogue_active() and not BattlePlayLoop.loot_waiting(loop)
	if runtime.has_method("modal_open"):
		quiet = quiet and not runtime.modal_open()
	var tail: Dictionary = loop.get("last_action_end", {})
	if quiet and turn_end_cue.pending(loop): runtime.focus_camera_on_grid(tail["coord"])
	var tail_point: Vector2 = runtime.grid_cell_center_to_logical_position(tail["coord"]) if not tail.is_empty() else Vector2.ZERO
	_refresh_terrain_poison(loop, quiet)
	var tail_was_busy: bool = turn_end_cue.busy(loop)
	turn_end_cue.refresh(loop, tail_point, quiet, delta)
	if tail_was_busy and not turn_end_cue.busy(loop) and loop.get(LoopKeys.INTERACTION) == Interaction.ACTION_MENU:
		var successor := BattlePlayLoop.unit(loop, str(loop.get(LoopKeys.SELECTED_UNIT_ID, "")))
		if not successor.is_empty(): runtime.focus_camera_on_grid(successor["coord"])
	var menu_bounds := Rect2()
	if loop.get(LoopKeys.INTERACTION) == Interaction.ACTION_MENU and runtime.get("action_menu") != null:
		menu_bounds = runtime.action_menu.layout_bounds()
		menu_bounds.position += runtime.action_menu.position
	extra_action_cue.refresh(loop, extra_point, quiet and not turn_end_cue.busy(loop), delta, menu_bounds)
	if dialogue_active():
		status_label.hide()
		combat_label.hide()
		battle_finished = false
	if combat_busy(loop):
		status_label.hide()
		combat_label.hide()
		battle_finished = false
	if battle_finished:
		status_label.hide()
		combat_label.hide()
		for child in get_children():
			if child is Node2D and child.get_node_or_null("Damage") != null:
				child.hide()
	_sync_defeated_visibility(loop)


## refresh: a new combat record — aftermath prepared, the attack cue led／skipped／advanced,
## and the strikes shown once the cue completes.
func _refresh_combat_cue(loop: Dictionary, map_config: RefCounted, playable: bool, combat_ready: bool, delta: float) -> void:
	var latest: Dictionary = loop.get(LoopKeys.LAST_COMBAT, {})
	var sequence := int(latest.get("sequence", 0))
	if playable and combat_ready and sequence > _shown_combat_sequence:
		aftermath.prepare(latest, loop.get(LoopKeys.UNITS, []), dialogue_manifest.get("messages", {}))
		if attack_cue.sequence != sequence:
			var attacker: Dictionary = BattlePlayLoop.unit(loop, str(latest["attacker_id"]))
			var defender: Dictionary = BattlePlayLoop.unit(loop, str(latest["defender_id"]))
			if attack_cue.leads(latest, attacker):
				attack_cue.begin(sequence, latest, BattlePlayLoop.strike_range_cells(loop, latest), attacker["coord"], latest.get("cast_center", defender["coord"]), map_config, get_parent().get("camera_controller"), _strike_area_at(loop, latest, attacker["coord"]))
			else:
				attack_cue.skip(sequence)
		else:
			attack_cue.advance(delta)
		if attack_cue.stage() == "complete":
			attack_cue.hide()
			_shown_combat_sequence = sequence
			var strikes: Array = BattlePlayLoop.CombatSequence.strikes(latest)
			for index in range(strikes.size()):
				var strike: Dictionary = strikes[index]
				_show_strike(strike, loop, map_config, bool(strike.get("is_counter", false)), index == 0, index == strikes.size() - 1, latest.get("strip_known_ids"))


## refresh: the status line objective and the escape-zone marks.
func _refresh_objective(loop: Dictionary, map_config: RefCounted, playable: bool) -> void:
	var had_escape_rects := not escape_rects.is_empty()
	escape_rects.clear()
	if playable:
		var escaping := str(loop.get("objective_phase", "hold")) == "escape"
		var objective := _objective_board_text(loop)
		if objective == "":
			objective = "前往撤離點，待機撤離" if escaping else "消滅所有敵人"
		status_label.text = "第 %d 回合 · %s" % [int(loop.get("turn", 1)), objective]
		if escape_marks and escaping and map_config != null and not BattleOutcome.decided(loop):
			var zone: Array = loop.get("escape_zone", [])
			if zone.is_empty():
				zone = loop.get("escape_zone_cells", [])
			for coord in zone:
				var cell: Vector2i = coord if coord is Vector2i else Vector2i(int(coord[0]), int(coord[1]))
				escape_rects.append(Rect2(map_config.grid_to_world(cell), map_config.grid_projection["cell_size"]))
	if had_escape_rects or not escape_rects.is_empty():
		queue_redraw()


func retain_defeated_actor(loop: Dictionary, unit_id: String) -> bool:
	# Do not expose precomputed lethal outcomes before their visible exchange.
	if has_pending_combat(loop):
		return aftermath.defeated_ids(loop[LoopKeys.LAST_COMBAT]).has(unit_id)
	return aftermath.retains(unit_id)


func _sync_defeated_visibility(loop: Dictionary) -> void:
	if actors_root == null:
		return
	for unit in loop.get(LoopKeys.UNITS, []):
		if not bool(unit.get("defeated", false)):
			continue
		for actor in actors_root.get_children():
			if actor.unit_id == str(unit["id"]):
				actor.visible = retain_defeated_actor(loop, str(unit["id"]))


## Every grid-cursor action (move, weapon, magic, special) shows the identity strip of the
## living unit under the cursor, whether or not it is a legal target (0x43e570 at 0x443e2a／
## 0x4445b7／0x444fe6／0x445286 tests only the cell's unit bits): legality only decides the
## hit／effect preview line (a full-HP ally under 治癒之水 still shows its strip).
func preview_target(loop: Dictionary, target_id: String, center_coord: Variant = null) -> void:
	combat_label.hide()
	target_vitals.hide()
	var screen: String = loop.get(LoopKeys.INTERACTION, "") if loop.get(LoopKeys.INTERACTION) in Interaction.TARGETING else ""
	if screen != _info_screen:
		_info_screen = screen
		if screen != "":
			info_public = not GameOptions.is_original("OPT-INFO")
			targets_line = info_public
	if dialogue_active() or cutin.busy():
		return
	if loop.get(LoopKeys.INTERACTION) not in Interaction.TARGETING:
		return
	var shown := _preview_attack_target(loop, target_id, center_coord) if loop.get(LoopKeys.INTERACTION) == Interaction.ATTACK_SELECT else ""
	if target_id != shown:
		preview_hovered_unit(loop, target_id)


## The legal weapon／skill target preview (strip + hit or effect line). Returns the id whose
## strip it showed, "" when the cell holds no legal target.
func _preview_attack_target(loop: Dictionary, target_id: String, center_coord: Variant) -> String:
	var attacker: Dictionary = BattlePlayLoop.unit(loop, str(loop[LoopKeys.SELECTED_UNIT_ID]))
	var fields := BattlePlayLoop.skill_fields(loop, str(loop.get(LoopKeys.SELECTED_SKILL_ID, "")))
	var self_special: bool = loop.get(LoopKeys.SELECTED_ATTACK) == "special" and BattlePlayLoop.SkillTargetRules.self_centered(fields)
	# Support specials (heal / cure / buff) preview like spells: allies and the caster are legal targets.
	var support_special: bool = loop.get(LoopKeys.SELECTED_ATTACK) == "special" and BattlePlayLoop.SkillTargetRules.is_support(fields, loop[LoopKeys.SKILL_TARGET_DATA])
	if (loop.get(LoopKeys.SELECTED_ATTACK) == "magic" or self_special or support_special) and center_coord is Vector2i:
		target_id = BattlePlayLoop.magic_target_id_at_coord(loop, center_coord)
	var target: Dictionary = BattlePlayLoop.unit(loop, target_id)
	if target.is_empty() or int(target["hp"]) <= 0:
		return ""
	if loop.get(LoopKeys.SELECTED_ATTACK) != "magic" and not support_special and not BattlePlayLoop.ActorRoleRules.player_range_selectable(attacker, target, loop.get(LoopKeys.SELECTED_ATTACK) == "special"): return ""
	var target_cell: Variant = center_coord if center_coord is Vector2i else BattlePlayLoop.Footprint.contact(target, BattlePlayLoop.attack_cells(loop))
	if not target_cell is Vector2i or not BattlePlayLoop.attack_cells(loop).has(target_cell):
		return ""
	if loop.get(LoopKeys.SELECTED_ATTACK) != "magic" and not self_special and not BattlePlayLoop.Footprint.contains(target, target_cell):
		return ""
	var special := str(loop[LoopKeys.SELECTED_ATTACK]) == "special"
	var rate := 0
	if special:
		var prepared := BattlePlayLoop.SkillResolutionRules.Special.prepare(attacker, target, fields, loop[LoopKeys.SKILL_BOOK], loop["equipment_items"])
		if not prepared["ok"]: return ""
		rate = 100 if prepared["input"]["no_attack"] else mini(100, int(prepared["input"]["hit_ratio"]) + int(prepared["input"]["hit_bonus"]))
	if loop.get(LoopKeys.SELECTED_ATTACK) == "magic" or self_special or support_special:
		var id: String = loop.get(LoopKeys.SELECTED_SKILL_ID, "")
		var prepared := BattlePlayLoop.SkillResolutionRules.prepare_cast(attacker, target, loop[LoopKeys.UNITS], id, fields, loop[LoopKeys.SKILL_BOOK], loop[LoopKeys.SKILL_TARGET_DATA], loop["equipment_items"], attacker["coord"], loop[LoopKeys.MAP_SIZE], center_coord, {"range_terrain": BattlePlayLoop.skill_terrain(loop)})
		if not prepared["ok"]: return ""
		target_vitals.show_unit(target, -1, _strip_known(loop, target_id))
		target_vitals.show()
		# 「N 個目標」 has no original counterpart: OPT-INFO=公開 only.
		if not targets_line: return target_id
		combat_label.position = Vector2(358, 297)
		var purpose := "驅毒" if fields["function"] == "magicFun_CurePoison" else "回復" if fields["function"] == "magicFun_Heal" else ""
		if fields["function"] in ["magicFun_DefUp", "magicFun_AttUp"]: purpose = "防禦增益" if fields["function"] == "magicFun_DefUp" else "攻擊增益"
		if fields["function"] == "magicFun_ClearAtDfUp": purpose = "清除攻防增益"
		if purpose == "" and support_special:
			var function_text := str(fields["function"])
			if function_text.contains("magicFun_Cure"): purpose = "淨化"
			elif function_text.contains("magicFun_Heal"): purpose = "回復"
			elif function_text.contains("Up"): purpose = "攻防增益" if function_text.contains("DefUp") and function_text.contains("AttUp") else "防禦增益" if function_text.contains("DefUp") else "攻擊增益"
		combat_label.text = "%s %d 個目標" % [purpose, prepared["targets"].size()] if purpose != "" else "%d 個目標" % prepared["targets"].size()
		if self_special and not support_special: combat_label.text = "%d 個目標 · 各5段" % prepared["targets"].size()
		combat_label.show()
		return target_id
	# The strip masks an enemy the player has not fought exactly as the hover strip does
	# (0x434d10 is the one text block behind every WINDOW10 display).
	target_vitals.show_unit(target, -1, _strip_known(loop, target_id))
	target_vitals.show()
	# The original identity/vitals strip carries the target information; no overhead hit line
	# (UI6, user 2026-09-25 照原版) — a skill's hit rate reads on the skill page's description box.
	# OPT-INFO=公開 restores the remake's line from before UI6: 命中 N% (· 2擊 for a double attack).
	if info_public:
		combat_label.position = Vector2(390, 297)
		combat_label.text = "命中 %d%%" % (rate if special else int(CoreCombatRules.attack_accuracy(attacker, target)["hit_rate"]))
		var count := BattlePlayLoop.attack_count(loop, attacker) if not special else {}
		if count.get("ok", false) and int(count["count"]) > 1: combat_label.text += " · 2擊"
		combat_label.show()
	return target_id


## The known flag an identity strip masks by (BattleVitals.mask): OPT-INFO=公開 shows every unit
## as known; the original path reads the known byte (BattlePlayLoop.unit_known).
func _strip_known(loop: Dictionary, unit_id: String) -> bool:
	return info_public or BattlePlayLoop.unit_known(loop, unit_id)


## The original identity strip while the pointer rests on a unit's body cell in any pick state
## (0x43e570 or the item／give pick's inline copy → 0x434d10 text block on WINDOW10): any side,
## the actor itself included, alive (0x43b4e0 skips the death flag), with the ??? mask for a
## unit the player has not yet fought (BattlePlayLoop.unit_known).
func preview_hovered_unit(loop: Dictionary, unit_id: String) -> void:
	if unit_id == "":
		return
	var hovered: Dictionary = BattlePlayLoop.unit(loop, unit_id)
	if hovered.is_empty() or int(hovered["hp"]) <= 0:
		return
	target_vitals.show_unit(hovered, -1, _strip_known(loop, unit_id))
	target_vitals.show()


func show_selection(loop: Dictionary, coord: Vector2i, logical_center: Vector2, cell_size: Vector2) -> void:
	selection_cursor.hide()
	movement_preview.clear()
	var screen: String = loop.get(LoopKeys.INTERACTION, "") if loop.get(LoopKeys.INTERACTION) in Interaction.TARGETING else ""
	if screen != _guide_screen:
		_guide_screen = screen
		if screen == Interaction.MOVE_SELECT: move_hints = not GameOptions.is_original("OPT-GUIDE")
	if loop.get(LoopKeys.INTERACTION) not in Interaction.TARGETING or coord == Interaction.NO_CELL:
		return
	var text := ""
	var in_range := false
	var body_rect := Rect2()
	if loop[LoopKeys.INTERACTION] == Interaction.MOVE_SELECT:
		var envelope := BattlePlayLoop.movement_envelope(loop, str(loop[LoopKeys.SELECTED_UNIT_ID]))
		in_range = envelope.get("reachable_by_coord", {}).has(coord)
		var route: Dictionary = envelope.get("reachable_by_coord", {}).get(coord, envelope.get("transit_by_coord", {}).get(coord, {}))
		var actor := BattlePlayLoop.unit(loop, str(loop[LoopKeys.SELECTED_UNIT_ID]))
		if BattlePlayLoop.Footprint.radius(actor) == 1:
			body_rect = Rect2(logical_center - cell_size * 1.5, cell_size * 3)
		if not route.is_empty():
			text = "%s %d / %d" % ["飛行" if actor["traversal"]["flying"] else "移動", route["cost"], actor["move_point"]]
			if not in_range: text += " · 可通過，不能停留"
			elif not BattlePlayLoop.magic_options(loop, str(actor["id"])).is_empty() and BattlePlayLoop.PositionCapabilities.cast_error(actor, loop[LoopKeys.SKILL_BOOK], loop["equipment_items"], "magic", true) == "magic_unavailable_after_movement":
				text += "\n移動後不能施法；取消可返回原位"
			if move_hints: movement_preview.present(route, _map_config, in_range, BattlePlayLoop.Footprint.radius(actor))
		elif coord != actor["coord"]:
			text = "需要3×3通行空間／足夠移動力" if BattlePlayLoop.Footprint.radius(actor) == 1 else "無法到達"
	else:
		in_range = BattlePlayLoop.attack_cells(loop).has(coord)
		var target := BattlePlayLoop.unit(loop, BattlePlayLoop.unit_id_at_coord(loop, coord))
		if not target.is_empty() and BattlePlayLoop.Footprint.radius(target) == 1:
			var body_center: Vector2 = get_parent().grid_cell_center_to_logical_position(target["coord"])
			body_rect = Rect2(body_center - cell_size * 1.5, cell_size * 3)
		match str(loop[LoopKeys.SELECTED_ATTACK]):
			"special":
				text = str(loop[LoopKeys.SKILL_BOOK]["skills"][loop[LoopKeys.SELECTED_SKILL_ID]]["name"])
				var effect_pattern: Variant = loop[LoopKeys.SKILL_TARGET_DATA]["ranges"].get(BattlePlayLoop.skill_fields(loop, loop[LoopKeys.SELECTED_SKILL_ID]).get("effect_range"))
				if BattlePlayLoop.SkillTargetRules.is_line(effect_pattern):
					text += "\n直線 %d 格，從目標格向外貫穿" % int(effect_pattern["size"])
				if BattlePlayLoop.SkillTargetRules.self_centered(BattlePlayLoop.skill_fields(loop, loop[LoopKeys.SELECTED_SKILL_ID])):
					text += "\n選擇自身，攻擊周圍敵人"
					if in_range and BattlePlayLoop.magic_target_id_at_coord(loop,coord)=="":
						text = "周圍沒有可攻擊的敵人"
						in_range = false
			"magic": text = str(loop[LoopKeys.SKILL_BOOK]["skills"][loop[LoopKeys.SELECTED_SKILL_ID]]["name"])
			_: text = "攻擊"
	if body_rect.has_area(): text += "\n占地3×3"
	if loop[LoopKeys.INTERACTION] == Interaction.MOVE_SELECT and not move_hints:
		text = ""
	selection_cursor.present(Rect2(logical_center - cell_size / 2, cell_size), text, in_range, body_rect, loop[LoopKeys.INTERACTION] == Interaction.ATTACK_SELECT)
	# Keep the cell being selected visible even near the lower edge of the map.
	if target_vitals.visible:
		var top := logical_center.y >= 300
		target_vitals.position = Vector2(0, 8 if top else 322)
		combat_label.position = Vector2(358, 168 if top else 297)
		if selection_cursor.caption.get_global_rect().intersects(combat_label.get_global_rect()) or selection_cursor.caption.get_global_rect().intersects(target_vitals.get_global_rect()):
			selection_cursor.caption.position.y = selection_cursor.cell_rect.position.y - selection_cursor.caption.size.y - 2


## OPT-GUIDE 提示: the escape-zone gold cells (escape_rects, refreshed each frame by refresh).
func _draw() -> void:
	for rect in escape_rects:
		draw_rect(rect.grow(-2), Color(1.0, 0.77, 0.15, 0.22), true)
		draw_rect(rect.grow(-2), Color(1.0, 0.77, 0.15), false, 2.0)


## The 重製選項 page closed with a change: the persistent escape marks follow it at once (the
## ring, move-select and AI cues read the option again the next time they are built).
func remake_options_changed() -> void:
	escape_marks = not GameOptions.is_original("OPT-GUIDE")


## `first_shot`／`last_shot`: the clip's place in the exchange (primary, extras, counter, its
## extras) — the ordinary cut-in opens on the first and closes with the screen transition on
## the last (BattleCombatCutin.play). `known_ids`: the exchange's known set at target
## confirmation (receipt `strip_known_ids`), which every shot's strip reads; null reads the
## loop's current set (a cast marks its targets before it settles).
func _show_strike(strike: Dictionary, loop: Dictionary, map_config: RefCounted, counter: bool, first_shot: bool = true, last_shot: bool = true, known_ids: Variant = null) -> void:
	var units: Array = loop.get(LoopKeys.UNITS, [])
	var attacker: Dictionary = {}
	var defender: Dictionary = {}
	for unit in units:
		if str(unit["id"]) == str(strike["attacker_id"]):
			attacker = unit
		if str(unit["id"]) == str(strike["defender_id"]):
			defender = unit
	if attacker.is_empty() or defender.is_empty() or map_config == null:
		return
	var target_world: Vector2 = map_config.grid_to_world(strike.get("cast_center", defender["coord"])) + map_config.grid_projection["cell_size"] * 0.5
	var caster_world: Vector2 = map_config.grid_to_world(attacker["coord"]) + map_config.grid_projection["cell_size"] * 0.5
	# Every receiver's projected position: a map presenter (magic script, 毒魔箭) plays its
	# effect at each; the ordinary close-up ignores them.
	var affected_positions: Array = []
	for outcome in strike.get("affected_targets", [strike]):
		for unit in units:
			if str(unit["id"]) != str(outcome["defender_id"]): continue
			var world: Vector2 = map_config.grid_to_world(unit["coord"]) + map_config.grid_projection["cell_size"] * 0.5
			affected_positions.append(get_parent().world_to_logical_position(world))
	# Every unit a shot can put in the strip: attacker, defender and, for a repeated special
	# (月花圓舞), each participant the presenter shows in turn — the same 0x434d10 mask.
	# OPT-INFO=公開 (read once per shot) shows every strip unmasked.
	var public := not GameOptions.is_original("OPT-INFO")
	var known := {}
	for unit in [attacker, defender] + (units if strike.has("special_segments") else []):
		known[str(unit["id"])] = public or BattlePlayLoop.unit_known(loop, str(unit["id"]), known_ids)
	cutin.play(strike, attacker, defender, counter, get_parent().world_to_logical_position(target_world), get_parent().world_to_logical_position(caster_world), affected_positions, units if strike.has("special_segments") else [], known, first_shot, last_shot)
	if str(strike.get("skill_id", "")).begins_with("magic:"):
		_note_caster(cutin.clips.back(), str(attacker["id"]))


## A map spell's caster readings the effect player needs: the Cast_Star burst point's height
## h = 0x43d990(caster shape) = the current shape's height + 2 (0x403156), and the use_magic
## pose length 8n + 40 the effect VM waits out on the caster's pose bit (0x442f65).
func _note_caster(clip: Dictionary, unit_id: String) -> void:
	var runtime := get_parent()
	var actor = runtime.actor_node_for_unit(unit_id) if runtime != null and runtime.has_method("actor_node_for_unit") else null
	if actor == null:
		return
	var sprite := actor.get_node_or_null("Sprite2D") as Sprite2D
	if sprite != null and sprite.texture != null:
		clip["caster_height"] = sprite.texture.get_height() + 2
	if not actor.has_method("has_shape_override") or actor.has_shape_override():
		return
	var entry: Dictionary = actor.magic_pose_entry(str(actor.actor_id))
	if not entry.is_empty():
		clip["caster_pose_ticks"] = 2 * actor.MAGIC_POSE_FRAME_TICKS * entry["frames"].size() + actor.MAGIC_POSE_HOLD_TICKS


func _present_release(_strike: Dictionary, attacker: Dictionary, _defender: Dictionary, _counter: bool) -> void:
	# 0x402fd1／0x403128: the map caster poses as its lead releases.
	if str(_strike.get("skill_id", "")).begins_with("magic:") and cutin.busy() and not is_same(cutin.clips[0], _posed_clip):
		_posed_clip = cutin.clips[0]
		_pose_unit(str(_strike.get("attacker_id", "")))
	if _strike.has("support_effects") or _strike.has("stat_effects") or _strike.has("skill_name"): return
	_play_sound(attacker, "attack")


func _present_impact(strike: Dictionary, attacker: Dictionary, defender: Dictionary, counter: bool) -> void:
	if strike.get("silent_after_defeat", false): return
	# The magic channel (0x40aa80) puts every receiver it hurt into the map hit state 0x407230:
	# hit shape and ±1 px shake for 60 ticks, no tint. The close-up's strikes leave the map alone.
	if strike.has("magic_key"):
		MapHitState.begin_strike(strike, get_parent(), self, float(Timing.PACE_MAP.get(GameOptions.value("OPT-PACE"), 1.0)))
	if strike.get("magic_key") in ["wind", "fire", "water"]:
		magic_impact.begin(strike, get_parent())
		return
	# OPT-INFO (read once per impact): 公開 puts the remake's words back beside the numbers.
	var public := not GameOptions.is_original("OPT-INFO")
	if strike.has("status_effects") or strike.has("support_effects") or strike.has("stat_effects"):
		_present_status_effects(strike, public)
		return
	var map_config := _map_config
	var cell: Vector2 = map_config.grid_projection["cell_size"]
	var target: Vector2 = map_config.grid_to_world(defender["coord"]) + cell * 0.5 + Vector2(0, -24)
	# No map object for the strike itself: the original's blade and hit flashes (0x4021df,
	# 0x40418a → 0x401310) live in the close-up only.
	var effect := Node2D.new()
	effect.name = "CombatEffect"
	add_child(effect)
	var words := strike_words(strike, counter, cutin.shows_miss(strike)) if public else ""
	# The label's half width: wider when it carries the 公開 words.
	var half := 40.0 if words == "" else 120.0
	var text := Label.new()
	text.name = "Damage"
	text.position = target + Vector2(-half, -38)
	text.size = Vector2(half * 2, 48)
	text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	text.add_theme_font_size_override("font_size", 22)
	text.add_theme_constant_override("outline_size", 5)
	text.add_theme_color_override("font_outline_color", Color(0.07, 0.05, 0.04))
	var hit := bool(strike["hit"])
	var damage: int = cutin.strike_actual_damage(strike)
	# defProcShowNumber in the original glyphs at the defender's (x, y − 0x34), as the magic
	# channel spawns them (0x40aba0): kind 0 red digits (DamageNumberFloater) or kind 5 MISS
	# (NUM513); the label keeps only what has no glyph — no 暴擊／擊倒／反擊 words (UI6).
	var number_point: Vector2 = map_config.grid_to_world(defender["coord"]) + cell * 0.5 + MAGIC_NUMBER_OFFSET
	var digits: Node2D = null
	var miss: Node2D = null
	if hit and damage > 0 and not cutin.shows_miss(strike):
		digits = DamageNumberFloater.new()
		digits.name = "DamageDigits"
		effect.add_child(digits)
		digits.present(damage)
		digits.position = number_point
		text.text = ""
	elif cutin.shows_miss(strike):
		miss = ResultNumberFloater.new()
		miss.name = "MissGlyph"
		miss.position = number_point
		effect.add_child(miss)
		miss.present("miss")
		text.text = ""
	else:
		text.text = cutin.strike_feedback(strike)
	text.modulate = ShowNumberStyle.DAMAGE
	if words != "":
		text.text = words if text.text == "" else text.text + " · " + words
		text.modulate = ShowNumberStyle.CAPTION
		_show_cutin_words(words, strike)
	effect.add_child(text)
	_play_weapon_hit_sound(strike, attacker, hit)
	# The close-up defender's dodge (0x4041ea..0x404247) plays its template's dodge sound
	# (0x409760, +0xc) on the tick it starts; a magic miss only spawns MISS (0x40aa80).
	if not hit and not strike.has("magic_key"):
		_play_sound(defender, "miss")
	_animate_impact_text(effect, text, digits, miss, words, half)


## _present_impact: the weapon's hit sound for an ordinary strike that hit.
func _play_weapon_hit_sound(strike: Dictionary, attacker: Dictionary, hit: bool) -> void:
	if hit and not strike.has("skill_name") and not strike.has("magic_key"):
		var cue_key: String = cutin.cue_manifest["weapon_hit_sounds"][str(int(attacker["weapon_code"]))]
		if cue_key != "":
			var hit_sound := AudioStreamPlayer.new()
			hit_sound.name = "WeaponImpactSound"
			hit_sound.stream = load(cutin.cue_manifest["sounds"][cue_key]["res_path"])
			add_child(hit_sound)
			hit_sound.finished.connect(hit_sound.queue_free)
			hit_sound.play()


## _present_impact: how the map number／caption label lives and goes (digits, MISS, or a
## rising caption).
func _animate_impact_text(effect: Node2D, text: Label, digits: Node2D, miss: Node2D, words: String, half: float) -> void:
	var life: float = Timing.SHOW_NUMBER_SECONDS
	if digits != null:
		# Kind 0 does not rise; the label (empty unless 公開) follows the digits and fades with their
		# level, and the effect goes when the number is deleted (DamageNumberFloater's own tick clock).
		text.position = digits.position + Vector2(-half, -56)
		digits.followers.append(text)
		digits.finished.connect(effect.queue_free)
		return
	if miss != null:
		# Kind 5 rises and fades on its own tick clock (ResultNumberFloater); the effect goes with it.
		if words != "":
			# 公開: the words stand over MISS and rise with it (½ px per tick).
			text.position = miss.position + Vector2(-half, -56)
			var rise := effect.create_tween().set_parallel(true)
			rise.tween_property(text, "position:y", text.position.y - Timing.SHOW_NUMBER_RISE_PX_PER_SECOND * life, life)
			rise.tween_property(text, "modulate:a", 0.0, Timing.SHOW_NUMBER_FADE_SECONDS).set_delay(life - Timing.SHOW_NUMBER_FADE_SECONDS)
		miss.finished.connect(effect.queue_free)
		return
	# The no-number captions: 46 ticks rising ½ px per tick.
	var animation := effect.create_tween().set_parallel(true)
	animation.tween_property(text, "position:y", text.position.y - Timing.SHOW_NUMBER_RISE_PX_PER_SECOND * life, life)
	animation.tween_property(text, "modulate:a", 0.0, Timing.SHOW_NUMBER_FADE_SECONDS).set_delay(life - Timing.SHOW_NUMBER_FADE_SECONDS)
	animation.chain().tween_callback(effect.queue_free)


## OPT-INFO=公開: the words the remake showed beside a strike's number before UI6 (ea45f5b4) —
## 反擊, 連擊 n/m, 暴擊 or 閃避, 擊倒. The original path shows the number alone (0x404643).
static func strike_words(strike: Dictionary, counter: bool, miss: bool) -> String:
	var words: Array[String] = []
	if counter: words.append("反擊")
	if int(strike.get("series_size", 1)) > 1: words.append("連擊 %d/%d" % [int(strike["strike_number"]), int(strike["series_size"])])
	if miss: words.append("閃避")
	elif bool(strike.get("critical", false)): words.append("暴擊")
	if bool(strike["hit"]) and int(strike["defender_hp_after"]) <= 0: words.append("擊倒")
	return " · ".join(words)


## OPT-INFO=公開: while the close-up is on screen at the impact, its words stand above the shot's
## number point on the layer over the cut-in until that clip leaves the queue (_sync_cutin_words).
func _show_cutin_words(words: String, strike: Dictionary) -> void:
	if not cutin.busy() or not cutin.scenery.visible:
		return
	if _cutin_words != null:
		_cutin_words.queue_free()
	var point: Vector2 = cutin.SCRIPT_NUMBER_POINT if strike.has("skill_name") else cutin.ORDINARY_NUMBER_POINT
	_cutin_words = Label.new()
	_cutin_words.name = "CutinWords"
	_cutin_words.text = words
	_cutin_words.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cutin_words.add_theme_font_size_override("font_size", 20)
	_cutin_words.add_theme_constant_override("outline_size", 4)
	_cutin_words.add_theme_color_override("font_outline_color", Color.BLACK)
	_cutin_words.add_theme_color_override("font_color", ShowNumberStyle.CAPTION)
	status_feedback.add_child(_cutin_words)
	_cutin_words.size = _cutin_words.get_combined_minimum_size()
	_cutin_words.position = point + Vector2(-_cutin_words.size.x / 2, -56 - _cutin_words.size.y / 2)
	_cutin_words_clip = cutin.clips[0]


func _sync_cutin_words() -> void:
	if _cutin_words != null and (not cutin.busy() or not is_same(cutin.clips[0], _cutin_words_clip)):
		_cutin_words.queue_free()
		_cutin_words = null
		_cutin_words_clip = {}


## `unit` is the PlayLoop unit (its job-up target row, when it has one, binds the sound:
## 0x4348f0 copies the target row's attack／miss／dead fields). A row that declares no
## sound for the event plays nothing.
func _play_sound(unit: Dictionary, event: String) -> void:
	var res_path := ActorSpriteKey.audio_binding(unit, event, [audio_manifest, shared_audio_manifest])
	if res_path == "":
		return
	var sound := AudioStreamPlayer.new()
	sound.stream = load(res_path)
	add_child(sound)
	sound.finished.connect(sound.queue_free)
	sound.play()


func dialogue_active() -> bool:
	return aftermath.dialogue_active() or not _dialogue_messages.is_empty()


func advance_dialogue() -> void:
	if aftermath.busy():
		aftermath.advance_dialogue()
		return
	if dialogue_active() and not dialogue_view.advance_page():
		_dialogue_messages.pop_front()
		dialogue_view.clear_message()
	_update_dialogue_page()


func _update_dialogue_page() -> void:
	if aftermath.busy(): return
	if not dialogue_active():
		dialogue_view.clear_message()
		return
	var message := _dialogue_messages[0]
	var speaker_id := str(message["speaker_id"])
	# Scenario lines carry the portrait row resolved from their speaking token when queued;
	# the first battle's own table names speakers by resource name id. Unknown speakers drop
	# the line with an error instead of crashing the battle presentation.
	var actor_id := str(message.get("actor_id", SPEAKER_PORTRAIT_ACTORS.get(speaker_id, "")))
	if actor_id == "":
		push_error("Missing dialogue portrait binding for speaker %s" % speaker_id)
		_dialogue_messages.pop_front()
		dialogue_view.clear_message()
		return
	if message.has("unit_id") and get_parent().has_method("actor_node_for_unit"):
		dialogue_view.set_speaker_actor(get_parent().actor_node_for_unit(str(message["unit_id"])))
	dialogue_view.show_message(speaker_id + ":" + str(message["message_id"]), str(dialogue_manifest["messages"][speaker_id]), str(message["text"]), actor_id)


## `public`: OPT-INFO=公開 (read by _present_impact) shows the status／cure／buff captions and adds
## the HP／MP word the remake put after a heal／MP number before UI6, in the number's colour among
## the captions; the original path shows the numbers alone (0x404643).
func _present_status_effects(strike: Dictionary, public: bool = false) -> void:
	var occupied: Array[Rect2] = []
	var captions: Array[Array] = []
	for result in strike.get("affected_targets", [strike]):
		for actor in actors_root.get_children():
			if actor.unit_id != str(result["defender_id"]): continue
			# The numbers are the magic channel's (0x40aba0): the original glyphs at the target's
			# (x, y − 0x34) — red damage, else green heal with the blue MP 40 ticks behind it at the
			# same point, else blue MP (ResultNumberFloater.spawns). The words the original has no
			# glyph for (status／cure／buff captions) are white Labels stacked above them.
			var point: Vector2 = get_parent().world_to_logical_position(actor.position)
			var amounts := {"damage": 0, "heal": 0, "mp": 0}
			var parts: Array[Dictionary] = []
			for part in cutin.feedback_parts(result):
				if amounts.has(str(part["kind"])): amounts[str(part["kind"])] = int(part["text"])
				else: parts.append(part)
			if public:
				if amounts["mp"] > 0: parts.push_front({"text": "MP", "kind": "mp"})
				if amounts["heal"] > 0: parts.push_front({"text": "HP", "kind": "heal"})
			for effect in result.get("status_effects", []):
				if effect["applied"]: parts.append({"text": StatusCatalog.name_of(effect["status"]), "kind": "caption"})
				elif effect["reason"] != "target_defeated": parts.append({"text": "免疫" if effect["reason"] == "immune" else "未生效", "kind": "caption"})
			for number in ResultNumberFloater.spawn_all(status_feedback, ResultNumberFloater.spawns(amounts["damage"], amounts["heal"], amounts["mp"], false), point + MAGIC_NUMBER_OFFSET):
				number.finished.connect(number.queue_free)
				occupied.append(number.bounds().grow(5))
			for part in parts:
				# The status／cure／buff captions have no original glyph: OPT-INFO=公開 only.
				if not public and str(part["kind"]) == "caption": continue
				var label := Label.new()
				label.text = str(part["text"])
				label.mouse_filter = Control.MOUSE_FILTER_IGNORE
				label.add_theme_font_size_override("font_size", 18)
				label.add_theme_constant_override("outline_size", 4)
				label.add_theme_color_override("font_outline_color", Color.BLACK)
				label.add_theme_color_override("font_color", ShowNumberStyle.color(str(part["kind"])))
				status_feedback.add_child(label)
				label.size = label.get_combined_minimum_size()
				captions.append([label, point])
	# The numbers keep their original points (the original does not move them apart); the captions
	# are laid out once every target's numbers are down, so no caption covers a neighbour's number.
	for caption in captions:
		var label: Label = caption[0]
		var bounds := Rect2(caption[1] + Vector2(-label.size.x / 2, -60), label.size).grow(5)
		# Preserve each target's horizontal anchor. All labels rise together,
		# so separating their measured outlined bounds also separates the flight.
		for _attempt in range(occupied.size() + 1):
			var collision := false
			for previous in occupied:
				if not bounds.intersects(previous): continue
				bounds.position.y = previous.position.y - bounds.size.y - 2
				collision = true
				break
			if not collision: break
		occupied.append(bounds)
		label.position = bounds.position + Vector2(5, 5)
		var fade := label.create_tween()
		fade.tween_property(label, "position:y", label.position.y - Timing.SHOW_NUMBER_RISE_PX_PER_SECOND * Timing.SHOW_NUMBER_SECONDS, Timing.SHOW_NUMBER_SECONDS)
		fade.tween_callback(label.queue_free)


func _board_label(entry: Dictionary) -> String:
	## winfail `message = SID,ID` Win Board row rendered from resource text: the
	## speaker name (message evidence speaker id) followed by the condition text.
	var messages: Dictionary = dialogue_manifest.get("messages", {})
	var speaker := str(messages.get(str(entry.get("speaker_id", "")), ""))
	var text := str(messages.get(str(entry.get("message_id", "")), ""))
	if text == "":
		return ""
	return ("%s %s" % [speaker, text]) if speaker != "" else text


func _objective_board_text(loop: Dictionary) -> String:
	## Scenario-owned objective line from the winfail Win Board labels of the armed
	## statuses: win rows and labelled event rows ("if assign, show in Win Board" —
	## WINFAIL051 event 3 labels the hold phase 等待援軍到來) as 目標, fail rows as 敗北.
	## Development trials carry no board and return "".
	var board: Dictionary = RuleAdapter.objective_board(loop)
	var parts: Array[String] = []
	for entry in board.get("win", []) + board.get("event", []):
		var label := _board_label(entry)
		if label != "":
			parts.append("目標：" + label)
	for entry in board.get("fail", []):
		var label := _board_label(entry)
		if label != "":
			parts.append("敗北：" + label)
	return " ｜ ".join(parts)


func _queue_story_dialogue(loop: Dictionary) -> void:
	if not dialogue_manifest.has("messages") or typeof(dialogue_manifest.get("messages")) != TYPE_DICTIONARY:
		return
	# Scenario rules own the event/outcome -> resource message mapping; this
	# pages them once per key+message in event order.
	for item in RuleAdapter.story_dialogue_messages(loop):
		var shown_key := "%s:%s" % [str(item.get("key", "")), str(item.get("message_id", ""))]
		if _shown_story_events.has(shown_key):
			continue
		_shown_story_events.append(shown_key)
		_append_dialogue(str(item.get("speaker_id", "")), str(item.get("message_id", "")), _story_speaker_actor(loop, str(item.get("actor_token", "")), str(item.get("speaker_id", ""))), _story_speaker_unit(loop, str(item.get("actor_token", ""))))


func mark_story_message_shown(shown_key: String) -> void:
	## A script cutscene already paged this key:message_id; the story queue skips it.
	if not _shown_story_events.has(shown_key):
		_shown_story_events.append(shown_key)


## Portrait row of a scenario (winfail) speaking token — the same rule the level assembler
## checks at build time (hsltools.levels.battle.missing_portraits): the unit the token binds
## (`winfail_runtime.actor_bindings`, first instance; its current job-up row when the level
## portraits carry it), else the SID_ENEMYnnn row itself, else the first-battle name-id table.
func _story_speaker_actor(loop: Dictionary, token: String, speaker_id: String) -> String:
	var bindings: Dictionary = (loop.get(LoopKeys.WINFAIL_RUNTIME, {}) as Dictionary).get("actor_bindings", {})
	for key in bindings:
		if str(key).split("/")[0] != token:
			continue
		var unit := BattlePlayLoop.unit(loop, str(bindings[key]))
		if not unit.is_empty():
			return ActorSpriteKey.row_key(unit, dialogue_view.portrait_rows())
	if token.begins_with("SID_ENEMY") and token.trim_prefix("SID_ENEMY").is_valid_int():
		return token.trim_prefix("SID_ENEMY").pad_zeros(3)
	return str(SPEAKER_PORTRAIT_ACTORS.get(speaker_id, ""))


## The live unit bound to a message's speaking token (first instance), "" when none is on the map.
func _story_speaker_unit(loop: Dictionary, token: String) -> String:
	var bindings: Dictionary = (loop.get(LoopKeys.WINFAIL_RUNTIME, {}) as Dictionary).get("actor_bindings", {})
	for key in bindings:
		if str(key).split("/")[0] == token and not BattlePlayLoop.unit(loop, str(bindings[key])).is_empty():
			return str(bindings[key])
	return ""


func _append_dialogue(speaker_id: String, message_id: String, actor_id: String = "", unit_id: String = "") -> void:
	var messages: Dictionary = dialogue_manifest.get("messages", {})
	if not messages.has(message_id) or not messages.has(speaker_id):
		return
	var record := {"message_id": message_id, "speaker_id": speaker_id, "text": str(messages[message_id])}
	if actor_id != "":
		record["actor_id"] = actor_id
	if unit_id != "":
		record["unit_id"] = unit_id
	_dialogue_messages.append(record)


func current_message_id() -> String:
	if aftermath.dialogue_active(): return aftermath.current_message_id()
	return str(_dialogue_messages[0]["message_id"]) if dialogue_active() else ""


## GameCursor: no sceptre while a close-up or a map magic effect plays ([0x4c1b00] 0x800000 set
## by AnimalDefense 0x4038dd, 0x1000000 by the cast routine 0x442a90).
func hides_game_cursor() -> bool:
	return cutin.busy()


## The terrain-poison action end (0x4454a5／0x441eb8) calls 0x407230 on the poisoned actor before
## 0x409140 poisons it: the hit frame and shake start with that action end's tail numbers. Only
## receipts appended since the last refresh play; a loaded battle does not replay earlier turns'.
func _refresh_terrain_poison(loop: Dictionary, quiet: bool) -> void:
	var receipts: Array = loop.get("terrain_poison", [])
	if terrain_poison_shown < 0 or receipts.size() < terrain_poison_shown:
		# First sight (or a reloaded loop): earlier turns' receipts are history, not new events.
		terrain_poison_shown = receipts.filter(func(receipt): return int(receipt.get("turn", 0)) < int(loop.get("turn", 0))).size()
	if not quiet or receipts.size() == terrain_poison_shown:
		return
	for index in range(terrain_poison_shown, receipts.size()):
		MapHitState.begin(get_parent(), self, str(receipts[index]["unit_id"]), float(Timing.PACE_MAP.get(GameOptions.value("OPT-PACE"), 1.0)))
	terrain_poison_shown = receipts.size()
