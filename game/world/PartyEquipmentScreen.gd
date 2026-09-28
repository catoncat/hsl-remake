extends CanvasLayer
## 整理裝備: the original's shared status window in mode 0 (0x42ab40(0, …)), opened by the
## world scroll's item 0 (defProcBigMapMenu 0x425a90) and by actEnterStorageWindow (story
## 57／81, winfail 045／078) — both hosts call open() here. The window itself is
## TownShopScreen in MODE_ARRANGE (the shop's boards and button strip, nine buttons by page;
## docs/evidence_packets/static_reverse/original_storage_window.md). This node owns the
## sandbox PlayLoop built from the carry's source scenario and the party storage
## (carry.loop.party_storage, PartyStorageRules), runs every hand gesture through
## PartyEquipmentRules.hand_action (equipment changes in the in-battle validation order), and
## on close projects the sandbox and the storage back into the carry and emits
## closed(next_carry, changes) for the host to persist.
## Presentation only: no second copy of the carry is kept after close.
## provenance:
##   layout: static-derived docs/evidence_packets/static_reverse/original_storage_window.md
##     (mode 0 of the shared window — drawn by TownShopScreen)
##   strings: remake-invented (the no-sandbox failure lines)

signal closed(next_carry: Dictionary, changes: int)

const SCHEMA := "hsl_party_equipment.v1"
const Rules = preload("res://game/sim/PartyEquipmentRules.gd")
const EquipmentRules = preload("res://game/sim/EquipmentRules.gd")
const BattleScenario = preload("res://game/sim/BattleScenario.gd")
const BattlePlayLoop = preload("res://game/sim/loop/BattlePlayLoop.gd")
const StatusWindow = preload("res://game/world/TownShopScreen.gd")
const StorageRules = preload("res://game/sim/PartyStorageRules.gd")
const EquipmentCatalog = preload("res://game/sim/EquipmentCatalog.gd")
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
var storage: Dictionary = {}
var hand: Dictionary = {}
var _portraits: Dictionary = {}


func _ready() -> void:
	layer = 5
	window = StatusWindow.new()
	add_child(window)
	window.name = "PartyEquipment"
	window.hand_requested.connect(_on_hand_requested)
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
	hand = {}
	storage = StorageRules.of_carry(carry)
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
	window.open_arrange(carry, loop, "" if error == "" else str(ERRORS.get(error, "無法整理裝備：%s" % error)), storage)
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


## A hand gesture from the window (place／store／retrieve／drop／use／equip／lift／unequip／back).
func _on_hand_requested(action: String, args: Dictionary, held: Dictionary) -> void:
	if error != "":
		return
	var result := Rules.hand_action(loop, storage, held, action, args, EquipmentCatalog.items())
	if not bool(result["ok"]):
		# A 使用 that returns 0 still keeps its damage-stream draws (PartyEquipmentRules._use_stored).
		if not is_same(result["loop"], loop):
			loop = result["loop"]
			changes += 1
		last_result = {"ok": false, "action": action, "reason": str(result["reason"])}
		window.refuse(str(result["reason"]))
		return
	loop = result["loop"]
	storage = result["storage"]
	hand = result["hand"]
	changes += 1
	last_result = {"ok": true, "action": action, "status": "changed"}
	window.show_state(carry, loop, storage, hand)


## Closes and hands the projected carry back (the input carry when nothing changed / no sandbox).
func close() -> Dictionary:
	if not active:
		return {"ok": false, "reason": "closed"}
	var next_carry := StorageRules.with_carry(Rules.project(carry, loop), storage) if error == "" and changes > 0 else carry.duplicate(true)
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
		"storage": StorageRules.entries(storage),
		"claim_limit": "Original mode 0 window layout, buttons, hand and storage list (static-derived; runtime-measured 2026-09-27); 使用 runs 0x409e40(…, 0, 1): HP／MP／stamina／cures and the permanent items, one item spent on a non-zero return.",
	}
