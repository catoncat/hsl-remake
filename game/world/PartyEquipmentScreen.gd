extends CanvasLayer
## 整理裝備: the original's shared status window in mode 0 (0x42ab40(0, …)), opened by the
## world scroll's item 0 (defProcBigMapMenu 0x425a90) and by actEnterStorageWindow (story
## 57／81, winfail 045／078) — both hosts call open() here. The window itself is
## TownShopScreen in MODE_ARRANGE (the shop's boards and button strip, nine buttons by page;
## docs/evidence_packets/static_reverse/original_storage_window.md). This node owns the
## sandbox PlayLoop built from the carry's source scenario, runs every equip／unequip through
## PartyEquipmentRules.change (the in-battle validation order), and on close projects the
## sandbox back into the carry and emits closed(next_carry, changes) for the host to persist.
## Presentation only: no second copy of the carry is kept after close.
## provenance:
##   layout: static-derived docs/evidence_packets/static_reverse/original_storage_window.md
##     (mode 0 of the shared window — drawn by TownShopScreen)
##   strings: remake-invented (the no-sandbox failure lines)

signal closed(next_carry: Dictionary, changes: int)

const SCHEMA := "hsl_party_equipment.v1"
const Rules = preload("res://game/sim/PartyEquipmentRules.gd")
const EquipmentRules = preload("res://game/sim/EquipmentRules.gd")
const BattleScenario = preload("res://game/battle/runtime/BattleScenario.gd")
const BattlePlayLoop = preload("res://game/battle/scene/BattlePlayLoop.gd")
const StatusWindow = preload("res://game/world/TownShopScreen.gd")
const REASONS := {
	"wrong_job": "職業不符", "wrong_equipment_slot": "部位不符", "inventory_full": "背包已滿",
	"equipment_cannot_be_removed": "無法卸下", "equipment_unchanged": "已裝備", "unsupported_equipment": "效果未開放",
	"missing_weapon_range": "無攻擊範圍", "inventory_selection_changed": "背包已變動",
}
const ERRORS := {"no_party": "沒有可整理的隊伍", "unknown_source_scenario": "找不到隊伍來源的戰鬥場景，無法整理裝備", "no_members": "隊伍中沒有可控制的成員"}

var active := false
var carry: Dictionary = {}
var loop: Dictionary = {}
var error := ""
var changes := 0
var scenario_path := ""
var last_result: Dictionary = {}
var window: Control
var _portraits: Dictionary = {}


func _ready() -> void:
	layer = 5
	window = StatusWindow.new()
	add_child(window)
	window.name = "PartyEquipment"
	window.equip_requested.connect(_on_equip_requested)
	window.unequip_requested.connect(_on_unequip_requested)
	window.close_requested.connect(close)
	_portraits = preload("res://game/sim/ContentPaths.gd").actor_portraits()
	visible = false


## Opens over the carried party. scenario_path_override lets tests / dev scenes name
## the sandbox scenario directly; otherwise carry.from_scenario_id is looked up in the
## campaign's battle entries. Without a resolvable scenario the window only shows the
## failure and closes.
func open(next_carry: Dictionary, campaign: Dictionary, scenario_path_override: String = "") -> Dictionary:
	carry = next_carry.duplicate(true)
	loop = {}
	error = ""
	changes = 0
	active = true
	visible = true
	if carry.is_empty() or str(carry.get("schema", "")) != Rules.CarryRules.SCHEMA:
		error = "no_party"
	else:
		scenario_path = scenario_path_override if scenario_path_override != "" else Rules.template_scenario_path(campaign, str(carry.get("from_scenario_id", "")))
		if scenario_path == "":
			error = "unknown_source_scenario"
		else:
			var box := Rules.sandbox(BattlePlayLoop.create([], "", BattleScenario.load_file(scenario_path)), carry)
			if not bool(box["ok"]):
				error = str(box["error"])
			else:
				loop = box["loop"]
				if Rules.members(loop).is_empty():
					error = "no_members"
					loop = {}
	window.open_arrange(carry, loop, "" if error == "" else str(ERRORS.get(error, "無法整理裝備：%s" % error)))
	last_result = {"ok": error == "", "error": error}
	return last_result


func member_ids() -> Array:
	return Rules.members(loop).map(func(unit): return str(unit["id"])) if not loop.is_empty() else []


func member_name(unit: Dictionary) -> String:
	return str((_portraits.get(str(unit.get("actor_id", "")), {}) as Dictionary).get("name", str(unit.get("id", ""))))


## 上一位／下一位 by id (tests and hosts); the window's own buttons step through the same list.
func select_member(unit_id: String) -> void:
	if active and error == "":
		window.show_member(unit_id)


## Bag equipment of the shown member with the dry-run mark: [{index, code, name, slot, ok, reason}].
func bag_entries() -> Array:
	var out: Array = []
	var selected := str(window.unit_id)
	if error != "" or selected == "":
		return out
	var unit := BattlePlayLoop.unit(loop, selected)
	var catalog: Dictionary = loop["equipment_items"]
	var inventory: Array = unit.get("inventory", [])
	for index in range(inventory.size()):
		var code := int(inventory[index])
		if code <= 0:
			continue
		var item: Dictionary = catalog.get(str(code), {})
		var kind := int(item.get("type_code", 0))
		if kind < 2 or kind > 6:
			continue
		var slot := _slot_for(unit, kind)
		var preview := Rules.preview(loop, selected, slot, index, code)
		out.append({"index": index, "code": code, "name": str(item.get("name", str(code))), "slot": slot, "ok": bool(preview["ok"]), "reason": str(preview["reason"])})
	return out


## The held item's kind picks its slot (0x436f30); accessories go to the first empty accessory
## slot (accessory1 when both hold one).
static func _slot_for(unit: Dictionary, kind: int) -> String:
	if kind != 6:
		return EquipmentRules.SLOTS[kind - 2]
	return "accessory2" if EquipmentRules.equipped_code(unit.get("equipment", []), "accessory1") > 0 and EquipmentRules.equipped_code(unit.get("equipment", []), "accessory2") == 0 else "accessory1"


## The player's gesture in one call: 裝備 page, pick bag item `inventory_index` up, click the
## equipment board.
func request_equip(inventory_index: int, code: int) -> Dictionary:
	if not active or error != "" or str(window.unit_id) == "":
		return {"ok": false, "reason": "inactive"}
	window.set_page(StatusWindow.PAGE_EQUIP)
	window.pick_up(inventory_index)
	if not window.holding():
		last_result = {"ok": false, "action": "equip", "reason": "inventory_selection_changed"}
		return last_result
	window.click_equipment("weapon")
	return last_result


## 裝備 page, empty hand, click the equipped slot.
func request_unequip(slot: String) -> Dictionary:
	if not active or error != "" or str(window.unit_id) == "":
		return {"ok": false, "reason": "inactive"}
	window.set_page(StatusWindow.PAGE_EQUIP)
	last_result = {"ok": false, "action": "unequip", "reason": "equipment_unchanged"}
	window.click_equipment(slot)
	return last_result


func _on_equip_requested(unit_id: String, inventory_index: int, code: int) -> void:
	var unit := BattlePlayLoop.unit(loop, unit_id)
	var item: Dictionary = loop["equipment_items"].get(str(code), {})
	var slot := _slot_for(unit, int(item.get("type_code", 0))) if not item.is_empty() else "weapon"
	_change({"kind": "equip", "unit_id": unit_id, "slot": slot, "index": inventory_index, "code": code})


func _on_unequip_requested(unit_id: String, slot: String) -> void:
	_change({"kind": "unequip", "unit_id": unit_id, "slot": slot, "index": -1, "code": 0})


func _change(request: Dictionary) -> void:
	var result := Rules.change(loop, request["unit_id"], request["slot"], int(request["index"]), int(request["code"]))
	if bool(result["ok"]):
		loop = result["loop"]
		changes += 1
		last_result = {"ok": true, "action": request["kind"], "status": "changed", "slot": request["slot"]}
		window.show_loop(carry, loop)
	else:
		last_result = {"ok": false, "action": request["kind"], "reason": str(result["error"])}
		window.refuse(str(result["error"]))


## Closes and hands the projected carry back (the input carry when nothing changed / no sandbox).
func close() -> Dictionary:
	if not active:
		return {"ok": false, "reason": "closed"}
	var next_carry := Rules.project(carry, loop) if error == "" and changes > 0 else carry.duplicate(true)
	active = false
	visible = false
	last_result = {"ok": true, "action": "close", "changes": changes}
	closed.emit(next_carry, changes)
	return last_result


## Right click／Esc in the original order (TownShopScreen.back): the message board, else the
## held item goes back, else the window closes.
func handle_input(event: InputEvent) -> bool:
	if not active:
		return false
	var escape: bool = event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE
	var right: bool = event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT
	if not escape and not right:
		return false
	if error != "":
		close()
	else:
		window.back()
	return true


func summary() -> Dictionary:
	var members: Array = []
	for unit in Rules.members(loop) if not loop.is_empty() else []:
		members.append({"unit_id": str(unit["id"]), "actor_id": str(unit["actor_id"]), "name": member_name(unit), "weapon_code": int(unit.get("weapon_code", 0)), "attack": int(unit["combat_profile"]["live_attack_damage"])})
	var shown: Dictionary = window.summary()
	return {
		"schema": SCHEMA,
		"active": active,
		"members": members,
		"selected": str(window.unit_id),
		"page": int(shown["page"]),
		"buttons": shown["buttons"],
		"holding": shown["holding"],
		"refusal": str(shown["last_refusal"]),
		"error": error,
		"changes": changes,
		"scenario_path": scenario_path,
		"bag": bag_entries(),
		"message": str(shown["message"]),
		"last_result": last_result.duplicate(true),
		"claim_limit": "Original mode 0 window layout and buttons (static-derived); the remake has no party storage, so 倉庫／丟棄／使用 stay unavailable.",
	}
