extends Control
## Menu-style town screen hosted by WorldMapRuntime when the party stands on a
## bmpmTown point with town data. The original's towns are menus, not walkable
## maps (TownBG illustration under a stone menu board listing town_event show_names;
## picking an entry runs its te chain). The composition follows the original frames
## (docs/evidence_packets/runtime_observations/original_world_town/README.md 03–07): the big
## map stays undimmed underneath, TownBG sits right of centre, the WINDOW70 board overlaps its
## top-left corner with the entries as white rows, NPC (teShapeMessage) lines use a top
## dialogue board and party (tePlayerMessage) lines the bottom one. Like the original the
## screen shows no town name, gold or party strip and no leave／back buttons (frames 03／04):
## right click or Escape leaves the town or steps out of a sub-menu; a choice lists its rows
## on the bottom BOARD02 select board (member prompts end with a「離開」row). It plays the effects the
## stateless TownEventRules interpreter returns. teCreateShop opens TownShopScreen (the
## original status-window shop); buying/selling is this node's transaction through
## WorldPartyRules. Right click or Escape leaves the town, as in the original. This node owns no world
## truth: it works on copies and hands (state, carry) back through the map. It plays no music
## itself: the host map plays the original town track 05 once the town opens and 06 again when
## it closes (docs/evidence_packets/static_reverse/original_music.md §3.2).
##
## The te VM 0x454e20 (static-derived, town_event_semantics.md «执行模型»): a message parks
## the VM until its board is closed, whatever the script's if_wait flag, so every message
## waits for a confirm; teDelay N holds the chain N + 1 ticks with no board up (counter
## 0x4c1d54, one decrement per process call) and teMenuMoveOut holds it 20 ticks; player
## input does not cut a hold. tePlaySound (0x455710 -> 0x42c180) plays its WAV at once at full
## volume and the chain goes on without waiting; gold and item grants show as narration lines (remake). Shop prices and
## refusals follow the original code (static-derived, original_shop_transaction.md).
## provenance:
##   rules: static-derived docs/evidence_packets/static_reverse/original_shop_transaction.md
##   rules: runtime-measured docs/evidence_packets/runtime_observations/original_world_town/README.md
##     (right click／Esc close the shop and leave the town, frames 13–14)
##   rules: static-derived docs/evidence_packets/static_reverse/town_event_semantics.md
##     (messages wait for their board to close; teDelay／teMenuMoveOut holds)
##   rules: static-derived docs/evidence_packets/static_reverse/original_storage_window.md
##     (shop 裝備／倉庫 pages and 丟棄 through PartyEquipmentRules.hand_action, frames 18–23)
##   rules: provisional (a scripted confirm() cuts a hold)
##   layout: resource-derived content/imported/hsl/global/world_map/town_portraits.json
##   layout: resource-derived content/imported/hsl/shared/panels/manifest.json
##   layout: runtime-measured docs/evidence_packets/runtime_observations/original_world_town/README.md
##     (no dimming; TownBG (158,148), WINDOW70 (60,60); rows x 72 from y 72, 32 px pitch; two boards)
##   layout: static-derived docs/evidence_packets/static_reverse/original_dialogue_board.md
##     (0x414220 top flag: teShapeMessage top, tePlayerMessage bottom)
##   layout: static-derived docs/evidence_packets/runtime_observations/original_world_town/README.md
##     (select board 0x426680, rows 0x4264f0, menu rows 0x4561d0: pulse-green hover)
##   layout: provisional (job-up and narration lines on the bottom board)
##   layout: resource-derived content/generated/hsl/text/protected_words.json
##   layout: remake-invented (the stone board hides during a choice)
##   strings: resource-derived content/imported/hsl/global/world_map/town_messages.json
##   strings: resource-derived content/imported/hsl/global/world_map/towndef.json
##   strings: static-derived docs/evidence_packets/static_reverse/original_shop_transaction.md
##   strings: remake-invented (narration lines for gold／item grants)
##   timing: static-derived docs/evidence_packets/static_reverse/town_event_semantics.md
##     (teDelay N → N + 1 ticks, teMenuMoveOut → 20 ticks, through OriginalTick)
##   timing: static-derived docs/evidence_packets/runtime_observations/original_world_town/README.md
##     (select board 0x426680: 16-tick fade in, clicks only at full level, 16-tick fade out, then hand back)
##   timing: provisional (the stone menus have no clock of their own)
##   audio: static-derived docs/evidence_packets/static_reverse/town_event_semantics.md
##     (tePlaySound 0x455710 -> 0x42c180: plays at volume 255, no wait)
##   audio: resource-derived content/imported/hsl/global/world_map/town_sounds.json
##   audio: static-derived docs/evidence_packets/static_reverse/original_music.md
##   audio: resource-derived content/imported/hsl/music/manifest.json

const Rules = preload("res://game/sim/TownEventRules.gd")
const WorldPartyRules = preload("res://game/world/WorldPartyRules.gd")
const BattleUISkin = preload("res://game/common/BattleUISkin.gd")
const BattleDialogue = preload("res://game/battle/scene/BattleDialogue.gd")
const CarryRules = preload("res://game/sim/CampaignCarryRules.gd")
const TownShopScreen = preload("res://game/world/TownShopScreen.gd")
const PartyEquipmentRules = preload("res://game/sim/PartyEquipmentRules.gd")
const CampaignProgress = preload("res://game/common/CampaignProgress.gd")
const PartyStorageRules = preload("res://game/sim/PartyStorageRules.gd")
const EquipmentCatalog = preload("res://game/sim/EquipmentCatalog.gd")
const BattlePlayLoop = preload("res://game/sim/loop/BattlePlayLoop.gd")
const BattleScenario = preload("res://game/sim/BattleScenario.gd")
const OriginalTick = preload("res://game/common/OriginalTick.gd")
const EventSelectWindow = preload("res://game/common/EventSelectWindow.gd")

const SUMMARY_SCHEMA := "hsl_town_runtime.v1"
## Original frames 03／04 (席達鎮 TownBG06, 兩棲族部落 TownBG14; runtime-measured): TownBG and
## the WINDOW70 stone board template-match at these top-left corners; the entries are white
## FONT.24 rows starting x 72 with glyph rows y 72–87, 104–119, … (32 px pitch).
const TOWN_BG_AT := Vector2(158, 148)
const MENU_BOARD := "WINDOW70"
const MENU_BOARD_AT := Vector2(60, 60)
const MENU_ROW_ORIGIN := Vector2(72, 64)
const MENU_ROW_SIZE := Vector2(216, 32)
const MENU_ROW_PITCH := 32.0
## Dialogue board top edges: the bottom slot is BattleDialogue's; frames 05／07 put the
## teShapeMessage board 300 px higher (text board y 22 against 322).
const DIALOGUE_TOP_Y := 20.0
## RESOURCE.TXT ids the original shop engine shows (static-derived, see _reason_text).
const SHOP_MESSAGE_NOT_ENOUGH_GOLD := 606
const SHOP_MESSAGE_NOT_BOUGHT := 607
## 0x454e20 case 0x28 (teMenuMoveOut): phase 0xe with the delay counter 0x4c1d54 = 0x14.
const MENU_MOVE_OUT_TICKS := 20

signal closed(town_id: int)
signal level_requested(next_level_event: Array)
signal party_changed(state: Dictionary, carry: Dictionary)

var runtime: Node
var town_id := 0
var town_label := ""
var towndef: Dictionary = {}
var messages: Dictionary = {}
var speakers: Dictionary = {}
var shop_catalog: Dictionary = {}
var portraits_path := ""
var sounds_path := ""
var sound_records: Array[Dictionary] = []
var _sound_table: Dictionary = {}
var background: Texture2D
var state: Dictionary = {}
var carry: Dictionary = {}
var mode := "menu"
var run: Dictionary = {}
var effect_queue: Array = []
var records: Array[Dictionary] = []
var current_text := ""
var current_speaker := ""
var shop_message := ""
var _party_before: Dictionary = {}
var _consumed_effects := 0
var _exit_ran := false
var _picture: TextureRect
var _board: TextureRect
var _dialogue: Control
var _menu_root: Control
var _choice_root: Control
var shop_screen: Control
## from_scenario_id → source battle path (TownRuntime._shop_scenario_path).
static var _scenario_paths: Dictionary = {}
var dialogue_slot := ""
var _hold_serial := 0


func open() -> void:
	name = "TownRuntime"
	size = Vector2(640, 480)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if background != null:
		_picture = TextureRect.new()
		_picture.name = "TownBG"
		_picture.texture = background
		_picture.position = TOWN_BG_AT
		_picture.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		_picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_picture)
	_board = BattleUISkin.asset(self, MENU_BOARD, MENU_BOARD_AT)
	_board.name = "MenuBoard"
	_board.hide()
	_dialogue = BattleDialogue.new()
	_dialogue.position = Vector2(0, BattleDialogue.PANEL_TOP_BOTTOM_SLOT)
	add_child(_dialogue)
	if portraits_path != "":
		_dialogue.configure_portraits(portraits_path)
	_menu_root = Control.new()
	_menu_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_menu_root)
	_choice_root = Control.new()
	_choice_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_choice_root)
	var town := _town_state()
	var exec_event := int(town.get("exec_event", 0))
	records.append({"kind": "open", "town_id": town_id, "exec_event": exec_event})
	if exec_event > 0:
		_start_run(exec_event, "exec_event")
	else:
		_show_root_menu()


## ---------------------------------------------------------------------------
## Menus

func _show_root_menu() -> void:
	mode = "menu"
	_clear(_menu_root)
	_clear(_choice_root)
	var entries := Rules.menu_entries(state, towndef, town_id, 0)
	for index in range(entries.size()):
		var entry: Dictionary = entries[index]
		var code := int(entry.get("code", 0))
		var row := _menu_row(_menu_root, index, _entry_text(entry), "Entry%d" % code)
		row.disabled = not bool(entry.get("known", false))
		row.pressed.connect(select_entry.bind(code))
	_refresh_board()


static func _entry_text(entry: Dictionary) -> String:
	var text := str(entry.get("show_name_text", ""))
	return "〔事件 %d〕" % int(entry.get("code", 0)) if text == "" or not bool(entry.get("known", false)) else text


## One entry of the stone board (0x4561d0 draw pass): FONT.24 white over the 0x8430 shadow at
## (+1,+1); the hovered row (+0x9a) is drawn in the 0x42c130 pulse green, shadow kept.
func _menu_row(parent: Control, index: int, text: String, node_name: String) -> Button:
	var row := Button.new()
	row.name = node_name
	row.text = text
	row.flat = true
	row.focus_mode = Control.FOCUS_NONE
	row.alignment = HORIZONTAL_ALIGNMENT_LEFT
	row.position = MENU_ROW_ORIGIN + Vector2(0, MENU_ROW_PITCH * index)
	row.size = MENU_ROW_SIZE
	row.clip_text = true
	for style in ["normal", "hover", "pressed", "disabled", "focus", "hover_pressed"]:
		row.add_theme_stylebox_override(style, StyleBoxEmpty.new())
	row.add_theme_font_size_override("font_size", BattleUISkin.FONT_BODY)
	row.add_theme_color_override("font_color", BattleUISkin.TEXT_WHITE)
	row.add_theme_color_override("font_hover_color", select_hover_colour())
	row.add_theme_color_override("font_pressed_color", BattleUISkin.TEXT_WHITE)
	row.add_theme_color_override("font_hover_pressed_color", select_hover_colour())
	row.mouse_entered.connect(_hover_menu_row.bind(row))
	row.mouse_exited.connect(_hover_menu_row.bind(null))
	set_process(true)
	row.add_theme_color_override("font_disabled_color", Color(0.62, 0.6, 0.56))
	row.add_theme_color_override("font_shadow_color", BattleUISkin.TEXT_SHADOW)
	row.add_theme_constant_override("shadow_offset_x", 1)
	row.add_theme_constant_override("shadow_offset_y", 1)
	parent.add_child(row)
	return row


## The stone board shows while a menu or sub-menu lists its rows; the original hides it while
## a message plays (frames 05–07), and a choice lists its rows on the select board instead.
func _refresh_board() -> void:
	if _board != null:
		_board.visible = mode in ["menu", "sub_menu"]


func menu_codes() -> Array[int]:
	var result: Array[int] = []
	for entry in Rules.menu_entries(state, towndef, town_id, 0):
		result.append(int(entry.get("code", 0)))
	return result


## Player picks a root menu entry (button or test): runs its te chain.
func select_entry(code: int) -> Dictionary:
	if mode != "menu":
		records.append({"kind": "select_entry", "code": code, "status": "ignored_mode_" + mode})
		return {"status": "ignored", "mode": mode}
	if not menu_codes().has(code):
		records.append({"kind": "select_entry", "code": code, "status": "not_in_menu"})
		return {"status": "not_in_menu"}
	records.append({"kind": "select_entry", "code": code, "status": "run"})
	_start_run(code, "menu")
	return {"status": "run", "code": code}


## Leaving runs the town's exit event first (teSetTownExitExecEvent) when one is
## armed, then closes the screen.
func leave() -> void:
	if mode != "menu":
		records.append({"kind": "leave", "status": "ignored_mode_" + mode})
		return
	var exit_event := int(_town_state().get("exit_exec_event", 0))
	if exit_event > 0 and not _exit_ran:
		records.append({"kind": "leave", "status": "exit_event", "event": exit_event})
		_start_run(exit_event, "exit_event")
		return
	records.append({"kind": "leave", "status": "closed"})
	mode = "closed"
	closed.emit(town_id)


## ---------------------------------------------------------------------------
## Runs

func _start_run(event_code: int, trigger: String) -> void:
	_clear(_menu_root)
	_clear(_choice_root)
	_board.hide()
	_party_before = WorldPartyRules.party_from_carry(carry, speakers)
	run = Rules.begin_event(state, _party_before, towndef, town_id, event_code)
	_consumed_effects = 0
	records.append({"kind": "run", "event": event_code, "trigger": trigger, "error": str(run.get("error", ""))})
	if trigger == "exit_event":
		run["_exit_run"] = true
	_consume_run()


func _consume_run() -> void:
	var effects: Array = run.get("effects", [])
	while _consumed_effects < effects.size():
		effect_queue.append(effects[_consumed_effects])
		_consumed_effects += 1
	_play_next_effect()


## Plays the queued effects one at a time; when the queue is empty the run's
## pending prompt (select / sub-menu / shop) or its completion takes over.
func _play_next_effect() -> void:
	while not effect_queue.is_empty():
		var effect: Dictionary = effect_queue.pop_front()
		var kind := str(effect.get("kind", ""))
		match kind:
			"player_message":
				var token := str(effect.get("player_token", ""))
				var speaker: Dictionary = speakers.get(token, {})
				_show_dialogue("%s:%d" % [token, int(effect.get("message_id", 0))], str(speaker.get("name_text", token)), message_text(int(effect.get("message_id", 0))), str(speaker.get("portrait_key", "")))
				return
			"shape_message":
				var face := str(effect.get("face_member", ""))
				var key := _portrait_key(face)
				_show_dialogue("%s:%d" % [face, int(effect.get("message_id", 0))], message_text(int(effect.get("name_resource_id", 0))), message_text(int(effect.get("message_id", 0))), key, true)
				return
			"job_up":
				# 0x454e20 case 0x1f composes RESOURCE.TXT 1299「的稱號由」/ 1300「變成」
				# around the member's name and the old/new titles into the 1354 buffer
				# and shows it as the member's face message (original_town_job_up.md).
				var token := str(effect.get("player_token", ""))
				var speaker: Dictionary = speakers.get(token, {})
				var name := str(speaker.get("name_text", token))
				var text := "%s的稱號由%s變成%s" % [name, _job_title(str(effect.get("from_actor_id", ""))), _job_title(str(effect.get("to_actor_id", "")))]
				records.append({"kind": "effect", "effect": effect, "status": "applied"})
				_show_dialogue("job_up:%s:%s" % [token, str(effect.get("to_actor_id", ""))], name, text, str(speaker.get("portrait_key", "")))
				return
			"get_gold":
				_show_narration("gold:%d" % int(effect.get("amount", 0)), "獲得 %d 金錢" % int(effect.get("amount", 0)))
				return
			"get_item":
				_show_narration("item:%d" % int(effect.get("item_id", 0)), "獲得 %s × %d" % [item_name(int(effect.get("item_id", 0))), int(effect.get("count", 1))])
				return
			"remove_item":
				_show_narration("lost:%d" % int(effect.get("item_id", 0)), "交出 %s" % item_name(int(effect.get("item_id", 0))))
				return
			"next_level":
				records.append({"kind": "effect", "effect": effect})
			"delay", "menu_move_out":
				var ticks := MENU_MOVE_OUT_TICKS if kind == "menu_move_out" else int(effect.get("ticks", 0))
				records.append({"kind": "effect", "effect": effect, "status": "applied"})
				if ticks > 0:
					_hold(ticks)
					return
			"play_sound":
				records.append({"kind": "effect", "effect": effect, "status": "applied" if _play_sound(str(effect.get("sound", ""))) else "missing_sound"})
			"recorded_only", "delete_player_message", "delete_shape_message":
				records.append({"kind": "effect", "effect": effect, "status": "recorded_only"})
			_:
				records.append({"kind": "effect", "effect": effect})
	if _dialogue.visible:
		_dialogue.clear_message()
	current_text = ""
	current_speaker = ""
	var pending: Variant = run.get("pending")
	if typeof(pending) == TYPE_DICTIONARY and not bool(run.get("done", false)):
		_show_pending(pending)
		return
	_finish_run()


## tePlaySound: 0x455710 hands the WAV member to 0x42c180, which loads (0x459a20) and plays
## (0x45a390) it at volume 255 and returns; the te chain continues the same call. The sound
## player hangs off the runtime so leaving the town does not cut it.
func _play_sound(member: String) -> bool:
	if _sound_table.is_empty() and sounds_path != "" and FileAccess.file_exists(sounds_path):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(sounds_path))
		if typeof(parsed) == TYPE_DICTIONARY and typeof((parsed as Dictionary).get("sounds")) == TYPE_DICTIONARY:
			_sound_table = (parsed as Dictionary)["sounds"]
	var path := str((_sound_table.get(member, {}) as Dictionary).get("res_path", ""))
	if path == "" or not ResourceLoader.exists(path):
		sound_records.append({"sound": member, "status": "missing"})
		return false
	var player := AudioStreamPlayer.new()
	player.name = "TownSound"
	player.stream = load(path)
	player.finished.connect(player.queue_free)
	(runtime if runtime != null else self).add_child(player)
	player.play()
	sound_records.append({"sound": member, "status": "played", "stream": path})
	return true


## `top`: an NPC line (teShapeMessage) on the top board; party lines, job-up results and the
## remake's narration lines keep the bottom board (original frames 05–07).
func _show_dialogue(key: String, speaker: String, body: String, portrait_key: String, top: bool = false) -> void:
	mode = "dialogue"
	_board.hide()
	current_text = body
	current_speaker = speaker
	if portrait_key != "" and _dialogue._portraits.has(portrait_key):
		_dialogue.show_message(key, speaker, body, portrait_key)
	else:
		if portrait_key != "":
			records.append({"kind": "portrait_missing", "key": portrait_key, "speaker": speaker})
		_dialogue.show_narration(key, "%s：%s" % [speaker, body] if speaker != "" else body, speaker == "")
	_place_dialogue(top)


func _show_narration(key: String, body: String) -> void:
	mode = "dialogue"
	_board.hide()
	current_text = body
	current_speaker = ""
	_dialogue.show_narration(key, body)
	_place_dialogue(false)


func _place_dialogue(top: bool) -> void:
	dialogue_slot = "top" if top else "bottom"
	_dialogue.position.y = DIALOGUE_TOP_Y if top else BattleDialogue.PANEL_TOP_BOTTOM_SLOT


## teDelay N (0x454e20 case 0xe): the VM stores N in 0x4c1d54, each later process call
## decrements it and the call that reaches 0 only resets the phase, so the next token runs
## N + 1 ticks after the delay; the previous board is already closed (the VM left the
## message phase only once it was), so nothing shows meanwhile.
func _hold(ticks: int) -> void:
	mode = "delay"
	_board.hide()
	if _dialogue.visible:
		_dialogue.clear_message()
	current_text = ""
	current_speaker = ""
	_hold_serial += 1
	get_tree().create_timer(OriginalTick.seconds(ticks + 1), false).timeout.connect(_end_hold.bind(_hold_serial))  # process_always=false: waits out a debug freeze


func _end_hold(serial: int) -> void:
	if mode == "delay" and serial == _hold_serial:
		_play_next_effect()


## Confirm (click / Space / Enter) while a message shows: next page, else next effect.
## Player input never reaches here during a teDelay hold (handle_input); a scripted
## confirm() cuts the hold so headless drivers need no clock.
func confirm() -> void:
	if mode == "delay":
		_hold_serial += 1
		_play_next_effect()
		return
	if mode != "dialogue":
		return
	if _dialogue.advance_page():
		return
	_play_next_effect()


func _show_pending(pending: Dictionary) -> void:
	var kind := str(pending.get("kind", ""))
	_clear(_choice_root)
	match kind:
		"select":
			mode = "select"
			var speaker: Dictionary = speakers.get(str(pending.get("speaker", "")), {})
			var labels: Array[String] = []
			for option in pending.get("options", []):
				labels.append(message_text(int((option as Dictionary).get("message_id", 0))))
			_show_select_window(labels, str(speaker.get("portrait_key", "")), false)
		"player_select":
			mode = "select"
			var labels: Array[String] = []
			var picks: Array[int] = []
			var options: Array = pending.get("options", [])
			# TownEventRules fills listed: 0x42caa0 in party, [mode] 1／2 +0x134 job-up bits, nine rows.
			for index in pending.get("listed", range(options.size())):
				var option: Dictionary = options[int(index)]
				var speaker: Dictionary = speakers.get(str(option.get("player_token", "")), {})
				labels.append(str(speaker.get("name_text", str(option.get("player_token", "")))))
				picks.append(int(index))
			# Every TOWNDEF use passes shape -1, so the board is centred without a picture.
			_show_select_window(labels, "", true, picks)
		"sub_menu":
			mode = "sub_menu"
			var entries: Array = pending.get("entries", [])
			for index in range(entries.size()):
				var entry: Dictionary = entries[index]
				var code := int(entry.get("code", 0))
				var row := _menu_row(_choice_root, index, _entry_text(entry), "Sub%d" % code)
				row.disabled = not bool(entry.get("known", false))
				row.pressed.connect(menu_pick.bind(code))
		"shop":
			_open_shop(pending)
		_:
			records.append({"kind": "pending_unknown", "pending": pending})
			_resume(null)
	_refresh_board()


## teSelectInsertEvent／tePlayerSelectInsertEvent (0x454e20 case 0xf／0x1e) open the shared
## object 704 select board (game/common/EventSelectWindow.gd). tePlayerSelectInsertEvent appends
## RESOURCE 312「離開」with event −1, which ends the event (0x455831, phase 0x1e: row event −1 →
## VM return 1).
const SELECT_LEAVE_TEXT := "離開"
var _select_clock := 0.0
var _select_window: Control = null
var _hover_row: Button = null


## `picks`: the pending option index behind each row (default: row i answers option i).
func _show_select_window(labels: Array[String], portrait_key: String, leave_row: bool, picks: Array[int] = []) -> void:
	_dialogue.clear_message()
	current_text = ""
	current_speaker = ""
	var face: Texture2D = null
	if portrait_key != "" and _dialogue._portraits.has(portrait_key):
		face = load(str(_dialogue._portraits[portrait_key]["res_path"]))
	_select_window = EventSelectWindow.open(_choice_root, labels, face, picks, SELECT_LEAVE_TEXT if leave_row else "", "SelectWindow", runtime if runtime != null else self)
	_select_window.answered.connect(_select_answered)


func _select_answered(pick: int, leave: bool) -> void:
	if leave:
		cancel_select()
	else:
		choose(pick)


## The stone menu rows' hover colour this tick (the select board's 0x42c130 pulse green).
func select_hover_colour() -> Color:
	return EventSelectWindow.pulse_colour(_select_clock)


func _process(delta: float) -> void:
	_select_clock += delta
	if is_instance_valid(_hover_row) and _hover_row.is_visible_in_tree():
		_hover_row.add_theme_color_override("font_hover_color", select_hover_colour())
		_hover_row.add_theme_color_override("font_hover_pressed_color", select_hover_colour())


func _hover_menu_row(row: Button) -> void:
	_hover_row = row


## Answer a select / player_select prompt by option index.
func choose(index: int) -> void:
	if mode != "select":
		return
	records.append({"kind": "choose", "index": index})
	_resume(index)


## The player_select board's「離開」row (event −1): the script continues past the token — every
## TOWNDEF use is the last token, so the event ends — with no member chosen (TownEventRules
## records the resume as invalid_choice).
func cancel_select() -> void:
	if mode != "select" or str((run.get("pending", {}) as Dictionary).get("kind", "")) != "player_select":
		return
	records.append({"kind": "choose", "index": -1, "status": "cancelled"})
	_resume(-1)


## Pick a child of the open sub-menu.
func menu_pick(code: int) -> void:
	if mode != "sub_menu":
		return
	records.append({"kind": "menu_pick", "code": code})
	_resume({"event": code})


## Leave the open sub-menu (the parked teCreateSubEventMenu advances).
func menu_exit() -> void:
	if mode != "sub_menu":
		return
	records.append({"kind": "menu_exit"})
	_resume(0)


func _resume(choice: Variant) -> void:
	_clear(_choice_root)
	_board.hide()
	run = Rules.resume(run, choice)
	_consume_run()


## The run ended: its state becomes the town's state, its party deltas go into
## the carry, the host persists both, and the (possibly rewritten) root menu returns.
func _finish_run() -> void:
	var was_exit := bool(run.get("_exit_run", false))
	var next_level: Array = run.get("next_level_event", [])
	if not run.is_empty():
		state = (run.get("state", state) as Dictionary).duplicate(true)
		var applied := WorldPartyRules.apply_party(carry, _party_before, run.get("party", _party_before))
		carry = applied["carry"]
		records.append({"kind": "run_finished", "error": str(run.get("error", "")), "receipt": applied["receipt"], "next_level_event": next_level.duplicate()})
		if not (applied["receipt"] as Dictionary).get("dropped", []).is_empty():
			shop_message = "背包已滿，部分物品無法收下"
		party_changed.emit(state, carry)
	run = {}
	if not next_level.is_empty():
		mode = "closed"
		level_requested.emit(next_level)
		return
	if was_exit:
		_exit_ran = true
		mode = "menu"
		leave()
		return
	_show_root_menu()


## ---------------------------------------------------------------------------
## Shop (caller-owned transactions; goods = the event's item_code table)

func _open_shop(pending: Dictionary) -> void:
	mode = "shop"
	shop_message = ""
	run["_shop"] = pending.duplicate(true)
	_set_town_view_visible(false)
	shop_screen = TownShopScreen.new()
	shop_screen.buy_requested.connect(func(item_id: int, _unit_id: String): shop_pick(item_id))
	shop_screen.sell_requested.connect(func(unit_id: String, slot: int): shop_sell(unit_id, slot))
	shop_screen.sell_hand_requested.connect(func(code: int): shop_sell_hand(code))
	shop_screen.close_requested.connect(shop_close)
	shop_screen.hand_requested.connect(func(action: String, args: Dictionary, held: Dictionary): shop_hand(action, args, held))
	shop_screen.unequip_requested.connect(func(unit_id: String, slot: String): shop_unequip(unit_id, slot))
	add_child(shop_screen)
	shop_screen.open(message_text(int(pending.get("shop_name_id", 0))).strip_edges(), shop_goods(), carry, speakers, shop_catalog, _shop_scenario_path())


## The carry's source battle, for the shop's vitals sandbox (the PartyEquipmentScreen lookup;
## the scan parses every battle file, so each id is looked up once per process).
func _shop_scenario_path() -> String:
	var scenario_id := str(carry.get("from_scenario_id", ""))
	if not _scenario_paths.has(scenario_id):
		var campaign: Dictionary = runtime.campaign_progress.campaign if runtime != null and runtime.get("campaign_progress") != null else CampaignProgress.load_campaign()
		_scenario_paths[scenario_id] = PartyEquipmentRules.template_scenario_path(campaign, scenario_id)
	return str(_scenario_paths[scenario_id])


## The shop window replaces the town picture; the big map stays in the gaps as in the
## original frames.
func _set_town_view_visible(visible_now: bool) -> void:
	if _picture != null:
		_picture.visible = visible_now


func shop_goods() -> Array[int]:
	var result: Array[int] = []
	for value in (run.get("_shop", {}) as Dictionary).get("item_ids", []):
		result.append(int(value))
	return result


## The window's goods click (0x414c00 shop branch, empty hand): the price comes off the gold at
## once and the item goes onto the hand (0x41553c writes 0x4c1ce4), no message; the player puts
## it down on a bag slot (shop_hand place) or right click puts it into the shown member's first
## empty slot (0x436e30). Only a refusal (606) raises a board.
func shop_pick(item_id: int) -> Dictionary:
	if mode != "shop":
		return {"ok": false, "reason": "not_in_shop"}
	if not shop_goods().has(item_id):
		return {"ok": false, "reason": "not_for_sale"}
	var entry: Dictionary = shop_catalog.get(str(item_id), {})
	var result := WorldPartyRules.pay_for_hand(carry, item_id, int(entry.get("cost", 0)))
	records.append({"kind": "shop_pick", "item_id": item_id, "result": result.duplicate(true)})
	if not bool(result.get("ok", false)):
		shop_message = _reason_text(str(result.get("reason", "")))
		_show_shop_carry(shop_message, str(result.get("reason", "")))
		return result
	carry = result["carry"]
	shop_message = ""
	party_changed.emit(state, carry)
	if shop_screen != null:
		shop_screen.show_state(carry, {}, PartyStorageRules.of_carry(carry), result["hand"])
	return result


## Scripted purchase (the autoplay shopper): shop_pick and the put-back in one step — into
## `unit_id`'s first empty slot.
func shop_buy(item_id: int, unit_id: String) -> Dictionary:
	if mode != "shop":
		return {"ok": false, "reason": "not_in_shop"}
	if not shop_goods().has(item_id):
		return {"ok": false, "reason": "not_for_sale"}
	var entry: Dictionary = shop_catalog.get(str(item_id), {})
	var result := WorldPartyRules.buy(carry, unit_id, item_id, int(entry.get("cost", 0)))
	records.append({"kind": "shop_buy", "item_id": item_id, "unit_id": unit_id, "result": result.duplicate(true)})
	var board := ""
	if bool(result.get("ok", false)):
		carry = result["carry"]
		shop_message = ""
		party_changed.emit(state, carry)
	else:
		shop_message = _reason_text(str(result.get("reason", "")))
		board = shop_message
	_show_shop_carry(board, str(result.get("reason", "")))
	return result


func shop_sell(unit_id: String, slot: int) -> Dictionary:
	if mode != "shop":
		return {"ok": false, "reason": "not_in_shop"}
	var units: Dictionary = carry.get("units", {})
	if not units.has(unit_id):
		return {"ok": false, "reason": "unknown_member"}
	var inventory: Array = (units[unit_id] as Dictionary).get("inventory", [])
	if slot < 0 or slot >= inventory.size() or int(inventory[slot]) <= 0:
		return {"ok": false, "reason": "empty_slot"}
	var item_id := int(inventory[slot])
	var entry: Dictionary = shop_catalog.get(str(item_id), {})
	var result := WorldPartyRules.sell(carry, unit_id, slot, item_id, WorldPartyRules.sell_price(int(entry.get("cost", 0))), shop_catalog)
	records.append({"kind": "shop_sell", "item_id": item_id, "unit_id": unit_id, "slot": slot, "result": result.duplicate(true)})
	var board := ""
	if bool(result.get("ok", false)):
		carry = result["carry"]
		shop_message = "賣出 %s（%d）" % [item_name(item_id), int(result.get("price", 0))]
		party_changed.emit(state, carry)
	else:
		shop_message = _reason_text(str(result.get("reason", "")))
		board = shop_message
	_show_shop_carry(board, str(result.get("reason", "")))
	return result


## The hand dropped on the goods list (0x4153b1): an important item is refused with 607 and stays
## on the hand; otherwise half price (0x414ab0) is added and the hand empties.
func shop_sell_hand(item_id: int) -> Dictionary:
	if mode != "shop":
		return {"ok": false, "reason": "not_in_shop"}
	var entry: Dictionary = shop_catalog.get(str(item_id), {})
	var result := WorldPartyRules.sell_hand(carry, item_id, WorldPartyRules.sell_price(int(entry.get("cost", 0))), shop_catalog)
	records.append({"kind": "shop_sell", "item_id": item_id, "result": result.duplicate(true)})
	if not bool(result.get("ok", false)):
		shop_message = _reason_text(str(result.get("reason", "")))
		var color: Color = {"insufficient_gold": BattleUISkin.TEXT_RED, "important_item": BattleUISkin.TEXT_YELLOW}.get(str(result.get("reason", "")), BattleUISkin.TEXT_WHITE)
		if shop_screen != null:
			shop_screen.show_carry(carry, shop_message, color, true)
		return result
	carry = result["carry"]
	shop_message = ""
	party_changed.emit(state, carry)
	_show_shop_carry("", "")
	return result


## The shop's hand gestures (裝備 page, 倉庫 page, 丟棄, bag to bag across members) run on a
## sandbox of the carry through PartyEquipmentRules.hand_action — the 整理裝備 path — and the
## result is projected back into the carry with the storage (carry.loop.party_storage).
func shop_hand(action: String, args: Dictionary, held: Dictionary) -> Dictionary:
	if mode != "shop":
		return {"ok": false, "reason": "not_in_shop"}
	var box := _shop_sandbox()
	if not bool(box["ok"]):
		return {"ok": false, "reason": str(box["error"])}
	var storage := PartyStorageRules.of_carry(carry)
	var result := PartyEquipmentRules.hand_action(box["loop"], storage, held, action, args, EquipmentCatalog.items())
	records.append({"kind": "shop_hand", "action": action, "ok": bool(result["ok"]), "reason": str(result.get("reason", ""))})
	if not bool(result["ok"]):
		shop_screen.refuse(str(result["reason"]))
		return {"ok": false, "reason": str(result["reason"])}
	carry = PartyStorageRules.with_carry(PartyEquipmentRules.project(carry, result["loop"]), result["storage"])
	party_changed.emit(state, carry)
	shop_screen.show_state(carry, {}, result["storage"], result["hand"])
	return {"ok": true}


## 裝備 page, empty hand on a worn slot: off into the bag (the rules' unequip).
func shop_unequip(unit_id: String, slot: String) -> Dictionary:
	var box := _shop_sandbox()
	if mode != "shop" or not bool(box["ok"]):
		return {"ok": false, "reason": "no_sandbox"}
	var result := PartyEquipmentRules.change(box["loop"], unit_id, slot, -1, 0)
	if not bool(result["ok"]):
		shop_screen.refuse(str(result["error"]))
		return {"ok": false, "reason": str(result["error"])}
	carry = PartyEquipmentRules.project(carry, result["loop"])
	party_changed.emit(state, carry)
	shop_screen.show_state(carry, {}, PartyStorageRules.of_carry(carry), {})
	return {"ok": true}


func _shop_sandbox() -> Dictionary:
	var path := _shop_scenario_path()
	if path == "":
		return {"ok": false, "error": "unknown_source_scenario"}
	return PartyEquipmentRules.sandbox(BattlePlayLoop.create([], "", BattleScenario.load_file(path)), carry)


## Only refusals raise the shop's message board, as in the original (a sale or purchase just
## changes the bag and the `$:` box); 606 prints @2 red and 607 @5 yellow.
func _show_shop_carry(board: String, reason: String) -> void:
	if shop_screen == null:
		return
	var color: Color = {"insufficient_gold": BattleUISkin.TEXT_RED, "important_item": BattleUISkin.TEXT_YELLOW}.get(reason, BattleUISkin.TEXT_WHITE)
	shop_screen.show_carry(carry, board, color)


## Closing the shop resumes the te chain; the interpreter's party view is
## refreshed from the carry first so later tokens see the post-purchase gold.
func shop_close() -> void:
	if mode != "shop":
		return
	if shop_screen != null:
		shop_screen.queue_free()
		shop_screen = null
	_set_town_view_visible(true)
	run.erase("_shop")
	_party_before = WorldPartyRules.party_from_carry(carry, speakers)
	run["party"] = _party_before.duplicate(true)
	records.append({"kind": "shop_close"})
	_resume(null)


## ---------------------------------------------------------------------------
## Input / helpers

## The map forwards every event while the town is open. Confirm advances a message. Right
## click or Escape (original frames 13／14) leaves the town from the root menu, steps out of a
## sub-menu and steps the shop back (closes its message, puts a
## held item back, else closes the shop); Space／Enter also close the shop's message.
func handle_input(event: InputEvent) -> void:
	var escape: bool = event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE
	var right_click: bool = event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT
	match mode:
		"dialogue":
			if _confirm_pressed(event):
				confirm()
		"menu":
			if escape or right_click:
				leave()
		"shop":
			if escape or right_click:
				shop_screen.back()
			elif event is InputEventKey and _confirm_pressed(event) and shop_screen.message_visible():
				shop_screen.dismiss_message()
		"sub_menu":
			if escape or right_click:
				menu_exit()
		"select":
			pass  # 0x426680／0x4264f0 read no cancel input: only a row click answers.
		_:
			pass


func message_text(message_id: int) -> String:
	var text: Variant = messages.get(str(message_id))
	if text == null:
		records.append({"kind": "message_missing", "message_id": message_id})
		return "〔訊息 %d〕" % message_id
	return str(text)


func item_name(item_id: int) -> String:
	return str((shop_catalog.get(str(item_id), {}) as Dictionary).get("name", "〔物品 %d〕" % item_id))


func party_gold() -> int:
	return int((carry.get("loop", {}) as Dictionary).get("gold", 0)) if str(carry.get("schema", "")) == CarryRules.SCHEMA else 0


func _town_state() -> Dictionary:
	var towns: Dictionary = state.get("towns", {})
	var value: Variant = towns.get(str(town_id))
	return value if typeof(value) == TYPE_DICTIONARY else {}


## Title (稱號) of a PLAYERS template row from the shared panel manifest (job_show_name
## or the TYPE.H job name, the same texts 0x4348a0 / 0x434830 resolve).
static func _job_title(actor_id: String) -> String:
	var entry: Variant = (BattleUISkin.data().get("actors", {}) as Dictionary).get(actor_id)
	if typeof(entry) == TYPE_DICTIONARY and (entry as Dictionary).has("title"):
		return str((entry as Dictionary)["title"])
	return "〔稱號 %s〕" % actor_id


static func _portrait_key(face_member: String) -> String:
	## SHAPE\FACE0062.SHP -> face_0062 (the town portrait manifest's key).
	var file := face_member.replace("\\", "/").get_file().get_basename().to_lower()
	return file.replace("face", "face_") if file.begins_with("face") else file


## The two refusals the original shop code shows are its own RESOURCE.TXT lines
## (606 not enough gold at 0x415611, 607 the shop does not buy this at 0x4153c2;
## docs/evidence_packets/static_reverse/original_shop_transaction.md); the rest
## are remake receipts for flows the original hand cursor never reaches.
func _reason_text(reason: String) -> String:
	match reason:
		"insufficient_gold":
			return message_text(SHOP_MESSAGE_NOT_ENOUGH_GOLD).strip_edges()
		"inventory_full":
			return "背包已滿"
		"important_item":
			return message_text(SHOP_MESSAGE_NOT_BOUGHT).strip_edges()
		"unknown_member", "not_in_shop", "not_for_sale", "empty_slot":
			return "無法交易"
		_:
			return reason


static func _clear(node: Node) -> void:
	if node == null:
		return
	for child in node.get_children():
		child.queue_free()


static func _confirm_pressed(event: InputEvent) -> bool:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		return true
	return event is InputEventKey and event.pressed and not event.echo and (event.keycode == KEY_ENTER or event.keycode == KEY_SPACE)


func summary() -> Dictionary:
	return {
		"schema": SUMMARY_SCHEMA,
		"town_id": town_id,
		"town_label": town_label,
		"mode": mode,
		"menu_codes": menu_codes(),
		"current_speaker": current_speaker,
		"current_text": current_text,
		"dialogue_slot": dialogue_slot if mode == "dialogue" else "",
		"menu_board_visible": _board != null and _board.visible,
		"gold": party_gold(),
		"shop": shop_screen.summary() if shop_screen != null else {},
		"shop_goods": shop_goods(),
		"shop_message": shop_message,
		"pending_kind": str((run.get("pending", {}) as Dictionary).get("kind", "")) if typeof(run.get("pending")) == TYPE_DICTIONARY else "",
		"records": records.duplicate(true),
		"claim_limit": "remake_notes:town_claim_limit",
	}
