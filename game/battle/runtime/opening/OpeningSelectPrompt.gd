extends RefCounted
## actSelectInsertEvent prompt for BattleOpeningCoordinator: the choice buttons beside
## the dialogue board and the splice of the chosen winfail chain into the timeline.
## The coordinator keeps the readback state (`select_options` / `select_selected`,
## reported by summary()) and the timeline cursor; this module owns only the prompt
## controls. Opcode 79 (0x451f2b) opens the same object 704 board as the town select
## (game/common/EventSelectWindow.gd): picture = the named object's face, else none.
## provenance:
##   rules: static-derived docs/evidence_packets/static_reverse/original_select_insert_event.md
##   layout: static-derived docs/evidence_packets/static_reverse/original_select_insert_event.md
##   strings: resource-derived content/imported/hsl/chapter01/message_text_evidence.json

const BattleUISkin = preload("res://game/common/BattleUISkin.gd")
const WinfailScenarioRules = preload("res://game/sim/WinfailScenarioRules.gd")
const EventSelectWindow = preload("res://game/common/EventSelectWindow.gd")

var coordinator: Node
var runtime: Node:
	get:
		return coordinator.runtime
var _select_root: Control


static func create(opening_coordinator: Node) -> RefCounted:
	var prompt := new()
	prompt.coordinator = opening_coordinator
	return prompt


## actSelectInsertEvent,<id>,<serial>,<num>,(<choice message id>,<event code>)*num: the
## speaker's choice between winfail event chains (STORY900: 選擇一 kicks the soldier and
## leaves, 選擇二 fights). Case 0x4f (0x451f2b–0x451fe3) looks the [id][serial] object up
## (0x44fad0) and passes its face (character row +0x5c) as the picture, 0 when absent, fills
## the message ids into 0x4c2940 and the event codes into 0x4c2900 (up to 10), sets the
## result −2 and calls 0x4264a0; it draws no message board and appends no「離開」row. The
## VM phase (0x45354e) waits while the result is −2, then inserts 0x4c2900[result]
## (0x44e7b0) and sets 0x4c1d44 — after the board's 16-tick fade-out. The chosen chain,
## precompiled by tools/hsltools/levels/story_scene.py into
## opening.select_event_timelines["event_<code>"], is spliced into the timeline right after
## this token and plays on. Without a compiled chain the choice is recorded only.
func _show_select_prompt(event: Dictionary) -> void:
	var args: Array = event.get("args", [])
	var count := int(str(args[2])) if args.size() > 2 else 0
	var messages: Dictionary = runtime.message_text_evidence.get("messages", {})
	var timelines: Dictionary = coordinator.config.get("select_event_timelines", {})
	var options: Array[Dictionary] = []
	for k in range(count):
		var position := 3 + 2 * k
		if args.size() <= position + 1:
			break
		var message_id := str(args[position])
		var code := str(args[position + 1])
		options.append({"message_id": message_id, "text": str(messages.get(message_id, message_id)), "event_code": code, "compiled": timelines.has("event_%s" % code)})
	coordinator.select_options = options
	if coordinator.select_options.is_empty():
		coordinator.story_records.append({"kind": "event_select_insert", "source_event_id": str(event.get("id", "")), "args": args.duplicate(), "status": "no_choices"})
		return
	coordinator.select_selected = 0
	var token := str(event.get("actor_token", ""))
	if token == "" and not args.is_empty():
		token = str(args[0])
	var speaker := str(runtime.message_text_evidence.get("speaker_names", {}).get(token, token))
	var serial := str(args[1]) if args.size() > 1 else "1"
	var actor_id := str(coordinator.binding_for_token(token, serial).get("actor_id", ""))
	var face: Texture2D = runtime.opening_overlay.face_texture(actor_id) if actor_id != "" else null
	runtime.opening_overlay.clear_message()
	var labels: Array[String] = []
	for option in coordinator.select_options:
		labels.append(str(option["text"]))
	_select_root = EventSelectWindow.open(runtime.get_node("UI"), labels, face, [], "", "StorySelectPrompt", runtime)
	_select_root.answered.connect(func(pick: int, _leave: bool) -> void: choose_select_option(pick))
	coordinator.story_records.append({"kind": "event_select_insert", "source_event_id": str(event.get("id", "")), "speaker": speaker, "options": coordinator.select_options.duplicate(true), "status": "prompted"})


## Keyboard selection is a remake convenience (0x4264f0 reads only the mouse): the selected
## row takes the board's hover colour.
func _refresh_select_buttons() -> void:
	if is_instance_valid(_select_root):
		_select_root.set_hover(coordinator.select_selected)


func _handle_select_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_UP, KEY_W:
				coordinator.select_selected = posmod(coordinator.select_selected - 1, coordinator.select_options.size())
				_refresh_select_buttons()
			KEY_DOWN, KEY_S:
				coordinator.select_selected = posmod(coordinator.select_selected + 1, coordinator.select_options.size())
				_refresh_select_buttons()
			KEY_ENTER, KEY_SPACE, KEY_Z:
				choose_select_option(coordinator.select_selected)
	# Mouse clicks reach the board's rows, which answer after the fade-out.


## Resolves the open actSelectInsertEvent prompt: the chosen winfail event chain is
## spliced in after the select token and the scene plays on from it.
func choose_select_option(index: int) -> Dictionary:
	if coordinator.select_options.is_empty() or index < 0 or index >= coordinator.select_options.size():
		return coordinator.summary()
	var choice: Dictionary = coordinator.select_options[index]
	var timelines: Dictionary = coordinator.config.get("select_event_timelines", {})
	var event_code := str(choice.get("event_code", ""))
	var chain: Dictionary = timelines.get("event_%s" % event_code, {})
	var inserted := 0
	var state_inserted := false
	if not coordinator.story_mode and event_code.is_valid_int():
		runtime.apply_loop(WinfailScenarioRules.select_event_status(runtime.play_loop, int(event_code)), "select_event_status")
		state_inserted = true
	if not chain.is_empty():
		inserted = runtime.scene_timeline.insert_after_current(chain.get("events", []))
	coordinator.story_records.append({"kind": "event_select_choice", "choice": index, "message_id": str(choice.get("message_id", "")), "event_code": event_code, "inserted_events": inserted, "state_status_inserted": state_inserted, "status": "spliced" if inserted > 0 else "no_compiled_chain"})
	var cleared: Array[Dictionary] = []
	coordinator.select_options = cleared
	coordinator.select_selected = 0
	if is_instance_valid(_select_root):
		_select_root.queue_free()
	_select_root = null
	runtime.opening_overlay.clear_message()
	coordinator.advance("select_choice")
	return coordinator.summary()
