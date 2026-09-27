extends CanvasLayer
## Read-only poison/recovery receipt playback. No resource, RNG or turn mutation.
## Source number types/order are retained; the original spawns each turn-end number at the unit's
## (x, y − 48) in its glyphs — poison and the blood-transfer HP loss red kind 0, HP gain green
## kind 2, MP blue kind 3 — the next one 40 ticks behind (its +0xa8 hold). The remake starts one
## event per 40-tick beat; each number keeps its own tick clock (ResultNumberFloat), so the
## previous one finishes fading while the next appears, and the last lives its full life.
## provenance:
##   layout: static-derived docs/evidence_packets/static_reverse/original_skill_function_bits.md
##   layout: remake-invented (caption position over the actor)
##   strings: resource-derived content/imported/hsl/shared/reward_floats/manifest.json
##   strings: remake-invented (the 麻痺解除／增益結束 captions; number kinds keep source order — original_resource_recovery.md)
##   strings: remake-invented docs/OPTIONS.md (OPT-INFO=公開 only: 中毒／轉化 and HP／MP words over a number beat)
##   timing: static-derived docs/evidence_packets/static_reverse/original_resource_recovery.md
##   timing: static-derived docs/evidence_packets/static_reverse/original_tick_counts.md
const OriginalTick = preload("res://game/common/OriginalTick.gd")
const Timing = preload("res://game/battle/runtime/CombatPresentationTiming.gd")
const ShowNumberStyle = preload("res://game/battle/runtime/ShowNumberStyle.gd")
const BattleOutcome = preload("res://game/sim/BattleOutcome.gd")
const ResultNumberFloat = preload("res://game/battle/scene/ResultNumberFloat.gd")
const GameOptions = preload("res://game/settings/GameOptions.gd")
const StatusCatalog = preload("res://game/sim/StatusCatalog.gd")
const EVENT_INTERVAL_TICKS := 40
const EVENT_SECONDS := OriginalTick.TICK_SECONDS * EVENT_INTERVAL_TICKS
## The last beat's floor: a kind 2／3 number lives 46 ticks (a longer red kind-0 number, 10 per
## digit + 34, holds the beat until it is deleted).
const NUMBER_SECONDS := Timing.SHOW_NUMBER_SECONDS
## The turn-end numbers spawn at the unit object's (x, y − 48).
const NUMBER_OFFSET := Vector2(0, -48)
var shown_sequence := 0
var cursor := -1
var elapsed := 0.0
## The captions the original has no glyph for (麻痺解除, 增益結束); hidden on a number beat.
var label: Label
## One ResultNumberFloat per event of the receipt being shown (null for a caption event).
var numbers: Array = []
var _displaying := false
## OPT-INFO=公開 for the receipt being shown (read once as it spawns): a number beat also
## carries its words (number_words).
var _words := false


func _ready() -> void:
	layer = 3
	label = Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", 20)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 4)
	add_child(label)
	label.hide()


func pending(loop: Dictionary) -> bool:
	var receipt: Dictionary = loop.get("last_action_end", {})
	return not BattleOutcome.decided(loop) and int(receipt.get("sequence", 0)) > shown_sequence and not receipt.get("events", []).is_empty()


func busy(loop: Dictionary) -> bool:
	return pending(loop) or cursor >= 0


## Whether a beat is on screen now (its number or caption).
func showing() -> bool:
	return _displaying


## The number kind of a turn-end event: poison and an HP loss red, MP blue, an HP gain green;
## "" for a caption event.
static func number_kind(event: Dictionary) -> String:
	if expired_status(event) != "" or str(event["kind"]).ends_with("_up_expired"): return ""
	if StatusCatalog.ENTRIES.has(str(event["kind"])) or int(event["amount"]) < 0: return "damage"
	return "mp" if str(event.get("resource", "")) == "mp" else "heal"


## The catalog status whose "<key>_expired" event this is (expiry_event rows, 麻痺), or "".
static func expired_status(event: Dictionary) -> String:
	var kind := str(event["kind"])
	if not kind.ends_with("_expired"): return ""
	var key := kind.trim_suffix("_expired")
	return key if StatusCatalog.ENTRIES.has(key) and StatusCatalog.ENTRIES[key]["expiry_event"] else ""


## OPT-INFO=公開: the words a number beat carried before UI6 (ea45f5b4) — 中毒／轉化 and HP／MP;
## the original path shows the number alone.
static func number_words(event: Dictionary) -> String:
	var head := StatusCatalog.name_of(str(event["kind"])) + " " if StatusCatalog.ENTRIES.has(str(event["kind"])) else "轉化 " if str(event["kind"]).begins_with("transfer_") else ""
	return head + str(event.get("resource", "")).to_upper()


func refresh(loop: Dictionary, point: Vector2, allowed: bool, delta: float) -> void:
	if BattleOutcome.decided(loop):
		finish(loop)
		return
	if not allowed:
		_hide()
		return
	var receipt: Dictionary = loop.get("last_action_end", {})
	var events: Array = receipt.get("events", [])
	if pending(loop):
		shown_sequence = int(receipt["sequence"])
		cursor = 0
		elapsed = 0
		_spawn(events)
	elif cursor >= 0:
		elapsed += maxf(delta, 0)
		var last_event: int = events.size() - 1
		while cursor < last_event and elapsed >= EVENT_SECONDS:
			elapsed -= EVENT_SECONDS
			cursor += 1
		if cursor == last_event and elapsed >= _last_seconds(last_event):
			cursor += 1
	if cursor < 0 or cursor >= events.size():
		cursor = -1
		_hide()
		return
	_displaying = true
	# Every started number draws from its own beat's start, at the same point.
	var now := float(cursor) * EVENT_SECONDS + elapsed
	for index in range(numbers.size()):
		var number: Node2D = numbers[index]
		if number == null: continue
		if index > cursor:
			number.hide()
			continue
		number.position = point + NUMBER_OFFSET
		number.draw_at(OriginalTick.ticks(now - float(index) * EVENT_SECONDS))
	var event: Dictionary = events[cursor]
	var caption := ""
	if expired_status(event) != "": caption = str(StatusCatalog.ENTRIES[expired_status(event)]["cure_label"])
	elif event["kind"] in ["attack_up_expired", "defense_up_expired", "resist_up_expired"]:
		caption = "%s增益結束 −%d" % [{"attack_up_expired": "攻擊", "defense_up_expired": "防禦", "resist_up_expired": "抗性"}[event["kind"]], int(event["before"]) >> 16]
	elif _words:
		caption = number_words(event)
	label.visible = caption != ""
	if caption == "": return
	label.text = caption
	label.add_theme_color_override("font_color", ShowNumberStyle.CAPTION)
	label.reset_size()
	# A 公開 number beat's words stand clear above its number (spawned at y − 48).
	var above := 70.0 if number_kind(event) == "" else 92.0
	label.position = Vector2(clampf(point.x - label.size.x / 2, 8, 632 - label.size.x), clampf(point.y - above - Timing.SHOW_NUMBER_RISE_PX_PER_SECOND * elapsed, 8, 452))


func _spawn(events: Array) -> void:
	_free_numbers()
	_words = not GameOptions.is_original("OPT-INFO")
	for event in events:
		var kind := number_kind(event)
		if kind == "":
			numbers.append(null)
			continue
		var number: Node2D = ResultNumberFloat.new()
		number.clocked = false
		add_child(number)
		number.present(kind, absi(int(event["amount"])))
		number.hide()
		numbers.append(number)


func _last_seconds(index: int) -> float:
	var number: Node2D = numbers[index] if index < numbers.size() else null
	if number == null: return NUMBER_SECONDS
	return maxf(NUMBER_SECONDS, OriginalTick.seconds(number.life_ticks())) if number.kind == "damage" else NUMBER_SECONDS


func _hide() -> void:
	_displaying = false
	if label != null: label.hide()
	for number in numbers:
		if number != null: number.hide()


func _free_numbers() -> void:
	for number in numbers:
		if number != null: number.free()
	numbers.clear()


func finish(loop: Dictionary) -> void:
	# Restoring an older snapshot also rewinds only this presentation cursor.
	shown_sequence = int(loop.get("last_action_end", {}).get("sequence", 0))
	cursor = -1
	elapsed = 0
	_hide()
	_free_numbers()
