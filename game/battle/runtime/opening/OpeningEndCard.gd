extends RefCounted
## Chapter-end card for BattleOpeningCoordinator: the 「第一章　完」／not-remade card, its
## skip-battle／end-route／world-map rows and the hand-offs a confirmed row triggers
## (CampaignProgress skip / story / world hand-off, restart, GameClear through the
## coordinator). The coordinator keeps the readback state (`end_card_options` /
## `end_card_selected` / `end_route_decision`, reported by summary()) and
## `_finish_story`; this module owns only the card controls. Layout is a remake reading.
## provenance:
##   rules: static-derived docs/evidence_packets/static_reverse/original_ending_dispatch.md
##   rules: remake-invented (skip-battle-as-victory and not-remade rows)
##   layout: remake-invented (card layout)
##   strings: remake-invented (「第一章　完」card, skip／route／world-map row texts)

const EndingDispatchRules = preload("res://game/sim/EndingDispatchRules.gd")

const END_CARD_ROW_TOP := 296.0
const END_CARD_ROW_PITCH := 34.0
const END_CARD_ROW_HEIGHT := 30.0

var coordinator: Node
var runtime: Node:
	get:
		return coordinator.runtime
var _end_card: Control
var _end_card_rows: Array[Label] = []


static func create(opening_coordinator: Node) -> RefCounted:
	var card := new()
	card.coordinator = opening_coordinator
	return card


## Input while the scene has ended (coordinator.story_finished): the plain card confirms
## with click／Enter／Space; a card with rows moves and confirms the highlighted row.
func handle_input(event: InputEvent) -> void:
	if coordinator.end_card_options.is_empty():
		if _confirm_pressed(event) and not _exit_to_world_map():
			_restart_campaign()
		return
	_handle_end_card_input(event)


func _show_end_card() -> void:
	if _end_card != null:
		_end_card.show()
		return
	_end_card = Control.new()
	_end_card.name = "ChapterEndCard"
	_end_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var dim := ColorRect.new()
	dim.size = Vector2(640, 480)
	dim.color = Color(0, 0, 0, 0.85)
	_end_card.add_child(dim)
	var end_card: Dictionary = coordinator.config.get("end_card", {})
	var title := Label.new()
	title.text = str(end_card.get("title", "第一章　完"))
	title.position = Vector2(0, 190)
	title.size = Vector2(640, 48)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 30)
	title.add_theme_color_override("font_color", Color(0.93, 0.87, 0.6))
	_end_card.add_child(title)
	var hint := Label.new()
	var next_label := "level %d" % int(coordinator.next_level_event[0]) if not coordinator.next_level_event.is_empty() else "下一關"
	hint.text = str(end_card.get("hint", "%s 尚未重製　　空格／點擊：回到第一戰" % next_label))
	hint.position = Vector2(0, 250)
	hint.size = Vector2(640, 30)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 16)
	hint.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
	_end_card.add_child(hint)
	coordinator.end_card_options = _end_card_choices()
	if not coordinator.end_card_options.is_empty():
		# With a skip-battle destination the card becomes a two-row choice; the hint
		# keeps its statement ("... 尚未重製") and drops the single-confirm key hint.
		hint.text = hint.text.split("　　")[0]
		coordinator.end_card_selected = 0
		_end_card_rows = []
		for index in range(coordinator.end_card_options.size()):
			var row := Label.new()
			row.position = Vector2(0, END_CARD_ROW_TOP + END_CARD_ROW_PITCH * index)
			row.size = Vector2(640, END_CARD_ROW_HEIGHT)
			row.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			row.add_theme_font_size_override("font_size", 18)
			_end_card.add_child(row)
			_end_card_rows.append(row)
		_refresh_end_card_rows()
	runtime.get_node("UI").add_child(_end_card)


## The card's rows: a preview whose opening.skip_battle (the winfail win section's
## next level, static-derived) leads to a registered scene offers to skip the
## not-remade battle as a victory — continuing the story there, or returning to the
## big map with the win section's world writes applied — beside the plain return.
func _end_card_choices() -> Array[Dictionary]:
	var choices: Array[Dictionary] = []
	var skip := _skip_battle_destination()
	if not skip.is_empty():
		var label := "略過戰鬥（視為勝利）→ 回到大地圖"
		if str(skip.get("kind", "")) != "world_map":
			label = "略過戰鬥（視為勝利）→ 續播劇情『%s』" % str(skip.get("title", ""))
		choices.append({"id": "skip_battle", "label": label, "path": str(skip.get("path", "")), "kind": str(skip.get("kind", ""))})
	choices.append_array(_end_route_choices())
	if choices.is_empty():
		return choices
	var exit_config: Dictionary = coordinator.config.get("end_exit", {})
	if str(exit_config.get("kind", "")) == "world_map":
		choices.append({"id": "world_map", "label": "回到大地圖（不施加戰果）", "path": "", "kind": "world_map"})
	return choices


## opening.end_routes: the finales an actSetNextPlayLevelGetOverEvent ending can
## continue in (STORY057 → 76／77／78), one row per registered route keyed by its
## level. The row shown is the one the original's over-score dispatch picks from the
## hand-off world state (EndingDispatchRules — static-derived); a decision whose
## finale is not registered leaves the card with its plain return and a record.
func _end_route_choices() -> Array[Dictionary]:
	var choices: Array[Dictionary] = []
	var progress: Node = runtime.get_node_or_null("CampaignProgress")
	var routes: Array = coordinator.config.get("end_routes", [])
	if progress == null or routes.is_empty():
		return choices
	var world: Dictionary = progress.world_after_story(coordinator.story_records)
	var decision := EndingDispatchRules.route(world.get("over_score", {}), int(world.get("over_flag", 0)))
	coordinator.end_route_decision = decision
	var next_event := EndingDispatchRules.next_level_event(decision)
	for route_value in routes:
		if typeof(route_value) != TYPE_DICTIONARY:
			continue
		var route: Dictionary = route_value
		var raw_event: Array = route.get("next_level_event", [])
		if raw_event.size() != 2 or int(raw_event[1]) != int(next_event[1]):
			continue
		var destination: Dictionary = progress.next_destination(progress.campaign, {"next_level_event": next_event}, str(runtime.scenario_path))
		if str(destination.get("path", "")) == "":
			continue
		choices.append({"id": "end_route", "label": "結局路線 → 續播『%s』" % str(route.get("title", destination.get("title", ""))), "path": str(destination.get("path", "")), "kind": str(destination.get("kind", "")), "next_level_event": next_event.duplicate()})
	if choices.is_empty():
		coordinator.story_records.append({"kind": "end_route_unregistered", "decision": decision.duplicate(true), "status": "recorded_no_handler"})
	return choices


## Where skipping the battle leads (CampaignProgress.next_destination of
## skip_battle.next_level_event); {} when the preview declares no skip_battle or
## the destination is not registered — the card then keeps its single confirm.
func _skip_battle_destination() -> Dictionary:
	var skip: Dictionary = coordinator.config.get("skip_battle", {})
	if skip.is_empty():
		return {}
	var progress: Node = runtime.get_node_or_null("CampaignProgress")
	if progress == null:
		return {}
	var destination: Dictionary = progress.next_destination(progress.campaign, {"next_level_event": _skip_battle_next_level_event()}, str(runtime.scenario_path))
	if str(destination.get("path", "")) == "":
		return {}
	return destination


func _skip_battle_next_level_event() -> Array:
	var skip: Dictionary = coordinator.config.get("skip_battle", {})
	var value: Variant = skip.get("next_level_event", [])
	return (value as Array).duplicate() if typeof(value) == TYPE_ARRAY else []


func _refresh_end_card_rows() -> void:
	for index in range(_end_card_rows.size()):
		var row := _end_card_rows[index]
		var selected: bool = index == coordinator.end_card_selected
		row.text = ("▶ %s" if selected else "%s") % str(coordinator.end_card_options[index].get("label", ""))
		row.add_theme_color_override("font_color", Color(0.98, 0.9, 0.55) if selected else Color(0.72, 0.72, 0.72))


func _handle_end_card_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_UP, KEY_W:
				select_end_card_option(coordinator.end_card_selected - 1)
				return
			KEY_DOWN, KEY_S:
				select_end_card_option(coordinator.end_card_selected + 1)
				return
			KEY_ENTER, KEY_SPACE, KEY_Z:
				confirm_end_card_option()
				return
		return
	if event is InputEventMouseMotion:
		var hovered := _end_card_row_at(runtime.viewport_to_logical_position(event.position))
		if hovered >= 0:
			select_end_card_option(hovered)
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		var hit := _end_card_row_at(runtime.viewport_to_logical_position(event.position))
		if hit >= 0:
			select_end_card_option(hit)
		confirm_end_card_option()


func _end_card_row_at(logical: Vector2) -> int:
	for index in range(_end_card_rows.size()):
		var row := _end_card_rows[index]
		if logical.y >= row.position.y and logical.y < row.position.y + row.size.y:
			return index
	return -1


func select_end_card_option(index: int) -> Dictionary:
	if coordinator.end_card_options.is_empty():
		return coordinator.summary()
	coordinator.end_card_selected = posmod(index, coordinator.end_card_options.size())
	_refresh_end_card_rows()
	return coordinator.summary()


## Confirms the highlighted card row: skip_battle hands the carried party to the win
## section's destination with its world writes applied; world_map is the plain return.
func confirm_end_card_option() -> Dictionary:
	if coordinator.end_card_options.is_empty() or coordinator.end_card_selected >= coordinator.end_card_options.size():
		return coordinator.summary()
	var choice: Dictionary = coordinator.end_card_options[coordinator.end_card_selected]
	match str(choice.get("id", "")):
		"skip_battle":
			if not _skip_battle():
				_restart_campaign()
		"end_route":
			_take_end_route(choice)
		_:
			if not _exit_to_world_map():
				_restart_campaign()
	return coordinator.summary()


## The dispatched finale continues the story there with the carry unchanged; the
## record keeps the decision (sorted ids, scores, flag) the world state produced.
func _take_end_route(choice: Dictionary) -> void:
	var progress: Node = runtime.get_node_or_null("CampaignProgress")
	var path := str(choice.get("path", ""))
	var next_event: Array = choice.get("next_level_event", [])
	if progress == null or path == "":
		_restart_campaign()
		return
	coordinator.story_records.append({"kind": "end_route_chosen", "next_level_event": next_event.duplicate(), "scenario_path": path, "decision": coordinator.end_route_decision.duplicate(true)})
	progress.start_story_handoff(path, runtime.campaign_handoff.get("carry", {}), coordinator.story_records, next_event)


## Skips the not-remade battle as a victory: the win section's next level is the
## destination and its town / big-map writes (skip_battle.world_actions, {name, args})
## are applied on the way; the carry passes through unchanged — no rewards,
## experience or party changes of the skipped battle are modelled.
func _skip_battle() -> bool:
	var destination := _skip_battle_destination()
	if destination.is_empty():
		return false
	var progress: Node = runtime.get_node_or_null("CampaignProgress")
	if progress == null:
		return false
	var skip: Dictionary = coordinator.config.get("skip_battle", {})
	var actions: Array = []
	for entry in skip.get("world_actions", []):
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var action: Dictionary = entry
		actions.append({"name": str(action.get("name", "")), "args": (action.get("args", []) as Array).duplicate(), "key": "skip_battle:%d" % actions.size()})
	var next_event := _skip_battle_next_level_event()
	coordinator.story_records.append({
		"kind": "battle_skipped",
		"level": int(coordinator.config.get("preview_of_battle_level", 0)),
		"source": str(skip.get("source", "")),
		"next_level_event": next_event.duplicate(),
		"scenario_path": str(destination.get("path", "")),
		"world_action_count": actions.size(),
		"movie": str(skip.get("movie", "")),
	})
	var complete := _complete_skip_battle.bind(destination, actions, next_event)
	if str(skip.get("movie", "")) != "":
		# The win section's actPlayMovie (winfail059: the ending film) plays before the hand-off.
		coordinator.cinematics._start_movie(str(skip.get("movie", "")), "skip_battle", complete)
	else:
		complete.call()
	return true


func _complete_skip_battle(destination: Dictionary, actions: Array, next_event: Array) -> void:
	var path := str(destination.get("path", ""))
	if str(destination.get("kind", "")) == "game_clear":
		# 90,998 after a skipped finale battle: the GameClear sequence, no world writes to place.
		coordinator._enter_game_clear(path, "skip_battle")
		return
	var progress: Node = runtime.get_node_or_null("CampaignProgress")
	if progress != null:
		progress.start_skip_battle_handoff(path, runtime.campaign_handoff.get("carry", {}), coordinator.story_records, actions, next_event)


func _confirm_pressed(event: InputEvent) -> bool:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		return true
	return event is InputEventKey and event.pressed and not event.echo and (event.keycode == KEY_ENTER or event.keycode == KEY_SPACE)


func _restart_campaign() -> void:
	var progress: Node = runtime.get_node_or_null("CampaignProgress")
	if progress != null:
		progress.restart_campaign()


## A preview whose opening config declares end_exit {kind: world_map} continues on the
## campaign's registered big-map scene (the skipped battle's winfail outcome is
## not applied); returns false when nothing is registered so the card restarts.
func _exit_to_world_map() -> bool:
	var exit_config: Dictionary = coordinator.config.get("end_exit", {})
	if str(exit_config.get("kind", "")) != "world_map":
		return false
	var progress: Node = runtime.get_node_or_null("CampaignProgress")
	if progress == null:
		return false
	var path: String = progress.world_map_scenario_path(progress.campaign)
	if path == "":
		return false
	coordinator.story_records.append({"kind": "world_map_exit", "scenario_path": path})
	progress.start_world_handoff(path, runtime.campaign_handoff.get("carry", {}), progress.world_after_story(coordinator.story_records))
	return true
