extends Node
## Coordinates loot and explicit safe-boundary saves. Holds no mutable combat state.
## provenance:
##   rules: remake-invented (F5／F9 quiet-boundary saves; the original has no in-battle checkpoint)
##   layout: n/a
##   strings: remake-invented (save／load notices)
##   timing: n/a
##   audio: n/a
const Loop = preload("res://game/battle/scene/BattlePlayLoop.gd")
const Checkpoint = preload("res://game/battle/runtime/BattleCheckpoint.gd")
const Interaction = preload("res://game/sim/Interaction.gd")
const LoopKeys = preload("res://game/sim/LoopKeys.gd")
var runtime: Node
var panel: Control
var checkpoint_path := "user://battle.save" # CampaignProgress._ready sets the scenario's own slot
var notice: Label
var resume_button: Button
var _notice_timer: Timer
var _checkpoint_autoload_done := false


func _ready() -> void:
	panel = preload("res://game/battle/scene/BattleLootPanel.gd").new()
	panel.name = "LootPanel"
	runtime.get_node("UI").add_child(panel)
	preload("res://game/battle/scene/BattlePanelMotion.gd").attach(panel)
	panel.claim_requested.connect(_claim)
	panel.finish_requested.connect(_finish)
	panel.cue_requested.connect(runtime.play_ui_sound)
	runtime.status_panel.save_requested.connect(save_battle)
	runtime.status_panel.load_requested.connect(load_battle)
	runtime.status_panel.rewards_requested.connect(open_rewards)
	resume_button = preload("res://game/battle/scene/BattleUISkin.gd").button(runtime.get_node("UI"), "繼續存檔 F9", Vector2(452, 14), Vector2(172, 34))
	resume_button.pressed.connect(load_battle)
	resume_button.hide()
	var layer := CanvasLayer.new()
	layer.layer = 4
	add_child(layer)
	notice = Label.new()
	notice.position = Vector2(18, 10)
	notice.size = Vector2(604, 30)
	notice.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	notice.add_theme_constant_override("outline_size", 5)
	notice.add_theme_color_override("font_outline_color", Color.BLACK)
	notice.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(notice)
	_notice_timer = Timer.new()
	_notice_timer.one_shot = true
	_notice_timer.wait_time = 3.0
	_notice_timer.timeout.connect(_clear_notice)
	add_child(_notice_timer)


## 讀取戰場記錄 from the title / world scroll: the hand-off asks the battle to resume its
## saved checkpoint at once. Runs on the first battle frame, before the opening coordinator
## takes the frame (the restored battle replaces the opening).
func autoload_checkpoint() -> void:
	if _checkpoint_autoload_done or not bool(runtime.campaign_handoff.get("load_checkpoint", false)):
		return
	_checkpoint_autoload_done = true
	if FileAccess.file_exists(checkpoint_path):
		load_battle()


func tick() -> bool:
	var view = runtime.get_node("BattlePresentation")
	autoload_checkpoint()
	resume_button.visible = runtime.interaction_state == Interaction.OPENING_TIMELINE and FileAccess.file_exists(checkpoint_path)
	runtime.status_panel.money_label.text = str(int(runtime.play_loop[LoopKeys.GOLD]))
	runtime.status_panel.rewards_button.disabled = runtime.play_loop[LoopKeys.SETTLEMENT].get("pending", []).is_empty()
	if not Loop.loot_waiting(runtime.play_loop):
		if panel.visible: panel.close()
		return false
	runtime.menus.set_action_menu_visible(false)
	if not view.combat_busy(runtime.play_loop, true) and not runtime.has_actor_motion() and not view.dialogue_active() and not view.item_feedback_busy():
		for modal in runtime.modal_panels: modal.hide()
		_refresh_panel()
	return true


## The original get-item window belongs to one actor: the killer (0x442720 case 4 sets 0x4c2ae4) or the
## chest opener. A reopen from Status keeps the inspected member; otherwise the visible recipient stays.
func _refresh_panel(preferred: String = "") -> void:
	var loop: Dictionary = runtime.play_loop
	var recipients: Array = Loop.loot_recipients(loop)
	var actors: Array = []
	for id in recipients: actors.append(Loop.unit(loop, id))
	var state: Dictionary = loop[LoopKeys.SETTLEMENT]
	var kills: Array = state.get("kills", [])
	var earner := str(state.get("owner_id", "")) if kills.is_empty() else str(kills[0]["attacker_id"])
	var recipient := ""
	for candidate in [preferred, panel._recipient if panel.visible else "", earner]:
		if recipients.has(candidate): recipient = candidate; break
	panel.show_rewards(state, actors, loop["equipment_items"], int(loop[LoopKeys.GOLD]), recipient, loop[LoopKeys.CONSUMABLES])


func _claim(request: Dictionary) -> void:
	if not panel.accepts(request): return
	var next := Loop.claim_reward(runtime.play_loop, request["sequence"], request["revision"], request["entry_id"], request["recipient_id"], request["slot"], request["expected_code"])
	if next == runtime.play_loop: return
	runtime.apply_loop(next, "claim_reward")
	runtime.play_ui_sound("put_down") # 400 PUT00003: the held item lands in the bag slot
	_refresh_panel()


func _finish(request: Dictionary) -> void:
	if not panel.accepts(request): return
	var next := Loop.finish_rewards(runtime.play_loop, request["sequence"], request["revision"], request["abandon"], request["defer"])
	if next == runtime.play_loop: return
	runtime.apply_loop(next, "finish_rewards")
	panel.close()
	# Runtime's ordinary exhaustion/AI continuation owns the next handoff.


func open_rewards() -> void:
	if not (runtime.status_panel.visible or runtime.get_node("BattlePresentation").battle_finished) or not quiet(): return
	var next := Loop.reopen_rewards(runtime.play_loop)
	if next == runtime.play_loop: return
	var inspected := str(runtime.status_panel.inspected_unit_id) if runtime.status_panel.visible else ""
	runtime.apply_loop(next, "reopen_rewards")
	runtime.status_panel.hide()
	if tick() and panel.visible and inspected != "": _refresh_panel(inspected)


func handle_input(event: InputEvent) -> bool:
	if resume_button.visible and event is InputEventMouseButton and resume_button.get_global_rect().has_point(event.position):
		return true # Let the actual button consume the click without advancing opening dialogue.
	if event is InputEventKey and event.pressed and not event.echo and event.keycode in [KEY_F5, KEY_F9]:
		if event.keycode == KEY_F5: save_battle()
		else: load_battle()
		return true
	if panel.visible:
		# Original root window: right click / Esc with a held item drops it into the first free bag slot;
		# with an empty hand the get-item window does not close this way (離開 does).
		if (event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE) or (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT): panel.quick_place()
		return true # Mouse still reaches actual GUI controls after Runtime returns.
	return false


func quiet() -> bool:
	var view = runtime.get_node("BattlePresentation")
	if runtime.treasure_view != null and runtime.treasure_view.busy(): return false
	if runtime.ScriptPresentation.active(runtime) or runtime.ScriptPresentation.pending(runtime): return false
	if runtime.interaction_state == Interaction.OPENING_TIMELINE or runtime.has_actor_motion() or view.combat_busy(runtime.play_loop) or view.dialogue_active() or view.item_feedback_busy(): return false
	# Saves／loads／rewards are raised from the status sheet itself, so it does not break the quiet boundary.
	if runtime.modal_open(runtime.status_panel) or not runtime.play_loop[LoopKeys.GIVE_SESSION].is_empty(): return false
	return runtime.play_loop[LoopKeys.INTERACTION] in [Interaction.ACTION_MENU, Interaction.BATTLE_RESULT] or panel.visible


## `announce` false: the caller shows its own success notice (the system scroll's
## 進度儲存完成); failures are still explained in the notice line.
func save_battle(announce: bool = true) -> Dictionary:
	if not quiet(): return _report({"ok": false, "reason": "請等演出或目前操作完成後保存。"})
	var view = runtime.get_node("BattlePresentation")
	var meta := {"camera": runtime.camera.position, "shown_story_events": view._shown_story_events.duplicate(),
		"growth_offered_levels": runtime.growth_offered_levels.duplicate(),
		"script_cutscene_consumed": runtime.script_cutscene_consumed,
		"treasure_presented_sequence": runtime.treasure_view.shown_sequence if runtime.treasure_view != null else 0}
	return _report(Checkpoint.write(checkpoint_path, runtime.play_loop, meta), "戰鬥已保存（F9 讀取）。" if announce else "")


func load_battle() -> Dictionary:
	# A freshly launched opening has not accepted a battle action. Loading may
	# replace it directly; an in-progress battle still requires a quiet boundary.
	if runtime.interaction_state != Interaction.OPENING_TIMELINE and not quiet(): return _report({"ok": false, "reason": "請等演出或目前操作完成後讀取。"})
	var result := Checkpoint.read(checkpoint_path, runtime.play_loop)
	if not result["ok"]: return _report(result)
	var saved: Dictionary = result["snapshot"]
	var meta: Dictionary = saved["view"]
	var view = runtime.get_node("BattlePresentation")
	panel.close() # Invalidates every old confirmation, including same sequence/revision.
	for modal in runtime.modal_panels: modal.hide()
	# A fresh opening may be replaced by a save. Retire its coordinator before
	# resuming; active battle cutscenes are rejected by quiet() above.
	if runtime.opening_coordinator != null:
		runtime.opening_coordinator.active = false
		runtime.opening_coordinator.cinematics._kill_camera_tween()
	if runtime.departure_view != null: runtime.departure_view.reset()
	runtime.opening_overlay.clear_message()
	if runtime.opening_coordinator != null: runtime.opening_coordinator.cinematics._set_title_visible(false)
	if runtime.scene_timeline != null: runtime.scene_timeline.seek_to_event_id("first_control_ready")
	runtime.opening_timeline_mode = "first_control"
	runtime.runtime_entrypoint = "restored_battle_checkpoint"
	view._dialogue_messages.clear()
	view.dialogue_view.clear_message()
	view._shown_story_events.assign(meta["shown_story_events"])
	view.finish_item_feedback()
	view.attack_cue.hide()
	view.aftermath.jobs.clear()
	view.aftermath.cursor = 0
	view.aftermath.stage = "idle"
	view.aftermath.clear_floats()
	# The saved roster gets fresh actor nodes: clear the field before the mirror step respawns it.
	for actor in runtime.actors_root.get_children(): runtime.actors_root.remove_child(actor); actor.queue_free()
	runtime.unit_grid_coords.clear()
	if runtime.treasure_view != null: runtime.treasure_view.restore(int(meta.get("treasure_presented_sequence", 0)))
	runtime.script_cutscene_consumed = int(meta.get("script_cutscene_consumed", 0))
	runtime.apply_loop(saved["loop"], "load_checkpoint")
	runtime.apply_opening_object_deletes()
	var sequence := int(runtime.play_loop.get(LoopKeys.LAST_COMBAT, {}).get("sequence", 0))
	view._shown_combat_sequence = sequence
	view.aftermath.sequence = sequence
	view._shown_item_sequence = int(runtime.play_loop.get(LoopKeys.LAST_ITEM_USE, {}).get("sequence", 0))
	view.extra_action_cue.finish(runtime.play_loop)
	view.turn_end_cue.finish(runtime.play_loop)
	runtime.growth_offered_levels = Checkpoint.growth_offered_levels(meta, runtime.play_loop)
	runtime.resume_turn_presentation()
	runtime.camera_controller.snap_to(meta["camera"])
	runtime.scene_input.disarm_pointer_scroll()
	runtime.reset_after_load()
	view.refresh(runtime.play_loop, runtime.map_config, true, true, 0)
	tick()
	return _report({"ok": true}, "已恢復戰鬥與待領物品。")


func _report(result: Dictionary, success: String = "") -> Dictionary:
	var reason := str(result.get("reason", ""))
	var explanations := {"save_not_found": "尚未保存這場戰鬥。", "incompatible_save_configuration": "存檔使用的關卡或規則版本不同。", "save_checksum_mismatch": "存檔不完整，請保留原檔並重新選擇。", "save_replace_failed": "無法寫入存檔，原有存檔已保留。"}
	notice.text = success if result["ok"] else "存讀檔未完成：" + str(explanations.get(reason, reason))
	_notice_timer.start()
	return result


## A line in the notice slot (GrowthCampaignProgress: why a separate party's pool reopened).
func announce(text: String) -> void:
	notice.text = text
	_notice_timer.start()


func _clear_notice() -> void:
	notice.text = ""
