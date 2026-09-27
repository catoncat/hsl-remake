extends Node
## Autoload: Tab opens the 重製選項 page (RemakeOptionsPage, the same page as 設定選項 ›
## 重製選項) over any screen — title, opening, battle, story, town and big map (user request
## 2026-09-26); Tab, Esc, right click or the crumb close it again. While it is up the game is
## held with the SceneTree pause, as under the debug freeze: nothing processes, tweens, times
## or sounds, and every key and click goes to the page, so no dialogue advances and no AI turn
## moves. Closing gives back the pause as it found it.
##
## Order: _input runs in reverse tree order, so this node keeps itself after the current scene
## (right before DebugPause, which stays last when it is on): Tab reaches it before any scene
## handler (a raised modal, the movie's any-key skip) can swallow or act on it. When a
## 重製選項 page is already up under the system scroll, Tab is left to that page (it goes back
## to 設定選項), so the page never opens twice. The page is built on the first Tab: a run that
## never sees one — tests, harnesses — never builds it and never pauses.
##
## Contract with DebugPause: if someone releases the pause while the page is up (the freeze
## resumes or steps), the next process pass pauses again and closing leaves the tree running;
## this node processes right after the freeze (process_priority) so a step frame never reaches
## the game under the page.
## provenance:
##   rules: remake-invented docs/OPTIONS.md (Tab opens and closes 重製選項 over any screen and holds the game with the tree pause while it is up; the original binds no key to Tab)
##   layout: n/a
##   strings: n/a
##   timing: n/a
##   audio: n/a

const RemakeOptionsPage = preload("res://game/settings/RemakeOptionsPage.gd")
const TOGGLE_KEY := KEY_TAB
## Above every game layer (the highest is 20), below the debug freeze badge (128), the popup
## canvas (1024) and the drawn cursor (GameCursor, 1025).
const CANVAS_LAYER := 100

var layer: CanvasLayer
var page: Control
## tree.paused as it was when the page opened; restored when it closes.
var _paused_before := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_priority = -999999
	set_process(false)
	get_tree().root.child_order_changed.connect(_stay_late)
	_stay_late()


func is_open() -> bool:
	return page != null and page.visible


func _input(event: InputEvent) -> void:
	if is_open():
		get_viewport().set_input_as_handled()
		page.handle_input(event, event.position if event is InputEventMouse else Vector2.ZERO)
		return
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo or key.keycode != TOGGLE_KEY:
		return
	if _other_page_open():
		return
	get_viewport().set_input_as_handled()
	open()


func open() -> void:
	if is_open():
		return
	if page == null:
		layer = CanvasLayer.new()
		layer.name = "RemakeOptionsHotkeyLayer"
		layer.layer = CANVAS_LAYER
		add_child(layer)
		page = RemakeOptionsPage.new()
		page.name = "RemakeOptions"
		layer.add_child(page)
		page.back_requested.connect(close)
	_paused_before = get_tree().paused
	get_tree().paused = true
	page.open()
	set_process(true)


func close() -> void:
	if not is_open():
		return
	page.close()
	set_process(false)
	get_tree().paused = _paused_before


func _process(_delta: float) -> void:
	if is_open() and not get_tree().paused:
		# Someone else released their pause under the page (the debug freeze resumed or stepped).
		_paused_before = false
		get_tree().paused = true


## A 重製選項 page other than this one is showing (the system scroll's).
func _other_page_open() -> bool:
	for node in get_tree().get_nodes_in_group(RemakeOptionsPage.GROUP):
		if node != page and (node as CanvasItem).is_visible_in_tree():
			return true
	return false


## root's children change while it is busy adding a scene, so the move is deferred.
func _stay_late() -> void:
	_move_late.call_deferred()


func _move_late() -> void:
	var root := get_parent()
	if not is_inside_tree() or root != get_tree().root:
		return
	var target := root.get_child_count() - 1
	var last := root.get_child(target)
	if last != self and last.name == "DebugPause" and bool(last.get("enabled")):
		target -= 1
	if get_index() != target:
		root.move_child(self, target)
