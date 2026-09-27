extends RefCounted
## Evidence-gated battle turn/command queue recovered from hsl01.exe.
## Source: content/generated/hsl/static/hsl01/core_logic.json → battle_turn_gating
## Docs: docs/first_battle_core_logic_evidence.md
##
## Separate from engine process dispatch (0x45f5f7). Sort key is live_speed (+0xb8).
## Live queue model; original roster/control and full status lifecycle remain partial.
## provenance:
##   rules: static-derived content/generated/hsl/static/hsl01/core_logic.json; static-derived docs/evidence_packets/static_reverse/initial_battle_initiative.md; runtime-measured docs/evidence_packets/runtime_observations/battle_051_ai_moves/README.md (Leonard before equal-speed friendly 023); runtime-measured docs/evidence_packets/static_reverse/initial_battle_initiative.md (start-of-round snapshot, wrap rebuild, round++ after last turn end, unregister holes)
##   layout: n/a
##   strings: n/a
##   timing: n/a
##   audio: n/a

const PACKET_PATH := "res://content/generated/hsl/static/hsl01/core_logic.json"
const EVIDENCE_DOC := "docs/first_battle_core_logic_evidence.md" # repository document, never loaded at runtime
const REBUILD_ADDR := "0x407340"
const CURRENT_ADDR := "0x407540"
const ADVANCE_ADDR := "0x407510"
const STATUS_TICK_ADDR := "0x40b910"
const MENU_BUILDER_ADDR := "0x43ea30"
const REGISTRATION_ADDR := "0x407660"
## Sort key for a registered player without a PLAYERS number: after slots 0..19.
const REGISTERED_UNNUMBERED := 20

## OBJ-ALL.H obj_BCmd* — UTF-16LE icon codes from 0x43ea30.
const BCMD_MOVE := 110
const BCMD_ATTACK := 111
const BCMD_ITEM := 112
const BCMD_WAIT := 113
const BCMD_MAGIC := 118
const BCMD_SPECIAL := 119
const BCMD_STATUS := 122

const BCMD_BY_ID := {
	110: "move",
	111: "attack",
	112: "item",
	113: "wait",
	114: "use",
	115: "give",
	116: "equip",
	117: "drop",
	118: "magic",
	119: "special",
	120: "ok",
	121: "cancel",
	122: "status",
}


static func packet_summary() -> Dictionary:
	return {
		"schema": "hsl_core_turn_queue_surface.v1",
		"packet_path": PACKET_PATH,
		"evidence_doc": EVIDENCE_DOC,
		"rebuild_function": REBUILD_ADDR,
		"current_object_function": CURRENT_ADDR,
		"advance_function": ADVANCE_ADDR,
		"status_tickdown_function": STATUS_TICK_ADDR,
		"menu_builder_function": MENU_BUILDER_ADDR,
		"sort_key": "live_speed",
		"sort_order": "descending",
		"unresolved_semantics": [
			"NPC registration follows roster (creation) order; native free-slot reuse after the 200-slot wrap is not modelled",
			"BCMD post-select handler mapping",
		],
	}


## Registration slot of one roster unit in the native object array 0x4c34c0: a registered
## player (the growth registry's manual allocation, object word +0xa2 < 20) takes its
## reserved slot +0xa0 = PLAYERS code − 1 (0x407665..0x407678); every other actor takes
## the next free slot from 20 in creation order (0x407681..0x4076e1, cursor reset to 20 at
## 0x407287), i.e. after all players, in roster order. -1 marks a non-player. A registered
## player whose id is not a PLAYERS number (authored sequel content) sorts after the
## numbered ones in roster order (remake-invented).
static func registration_slot(unit: Dictionary) -> int:
	var profile: Variant = unit.get("growth_profile", {})
	if not profile is Dictionary or str(profile.get("allocation", "")) != "manual": return -1
	var actor_id := str(unit.get("actor_id", ""))
	return int(actor_id) - 1 if actor_id.is_valid_int() and int(actor_id) >= 1 and int(actor_id) <= 20 else REGISTERED_UNNUMBERED


## The object array 0x4c34c0 as the AI scans walk it (0x40bb80, 0x40bf70 and 0x40d8b0 go
## slot by slot from 0): entry k is the index in `units` of the unit registered in slot k,
## -1 for an empty slot. Registered players sit in their reserved slots 0..19 (gaps stay
## empty, so slot 0 is PLAYERS code 1 or nobody); unnumbered registered players, then every
## other unit in roster order, follow from slot 20 — the same collection order `rebuild`
## sorts (static-derived 0x407660; emulator-measured on battle 051 r1: Leonard +0x88 value
## 1, 021_1 value 0x15, 023_1 0x1c, 023_2 0x1d). Native free-slot reuse is not modelled.
static func registry_layout(units: Array) -> Array:
	var layout: Array = []
	var later: Array = []
	var others: Array = []
	for index in range(units.size()):
		if typeof(units[index]) != TYPE_DICTIONARY: continue
		var slot := int(units[index].get("registered_slot", registration_slot(units[index])))
		if slot < 0:
			others.append(index)
			continue
		if slot >= REGISTERED_UNNUMBERED:
			later.append(index)
			continue
		while layout.size() <= slot: layout.append(-1)
		if int(layout[slot]) == -1: layout[slot] = index
		else: later.append(index)
	while layout.size() < REGISTERED_UNNUMBERED: layout.append(-1)
	return layout + later + others


## Queue entries {id, live_speed, action_ready, registered_slot} for the units `alive`
## accepts, in roster order (the input of `rebuild`／`end_turn`).
static func queue_actors(units: Array, alive: Callable) -> Array:
	var actors: Array = []
	for unit_value in units:
		if typeof(unit_value) != TYPE_DICTIONARY:
			continue
		var unit: Dictionary = unit_value
		if not alive.call(unit):
			continue
		actors.append({
			"id": str(unit.get("id", "")),
			"live_speed": int(unit.get("live_speed", unit.get("speed", 0))),
			"action_ready": true,
			"registered_slot": registration_slot(unit),
		})
	return actors


## Rebuild a speed-sorted command queue (model of 0x407340).
## actors: Array of {id, live_speed, action_ready?, registered_slot?}
## The collection walks the registration array 0x4c34c0 from slot 0 (0x407365..0x407390),
## so registered players precede NPCs before the stable descending-speed sort and equal
## speeds keep that order (runtime-measured: in the first battle Leonard (14) acts before
## friendly 023 (14) although 023 precedes him in EVEF — battle_051_ai_moves).
static func rebuild(actors: Array) -> Dictionary:
	var registered: Array = []
	var others: Array = []
	for actor_value in actors:
		if typeof(actor_value) != TYPE_DICTIONARY:
			continue
		var actor: Dictionary = actor_value
		if bool(actor.get("exclude_from_queue", false)):
			continue
		# A roster unit passed directly carries its growth profile instead of the key.
		var slot := int(actor.get("registered_slot", registration_slot(actor)))
		if slot >= 0: registered.append({"actor": actor, "slot": slot})
		else: others.append(actor)
	# Stable insertion by slot; equal slots keep roster order.
	for i in range(1, registered.size()):
		var held: Dictionary = registered[i]
		var j := i - 1
		while j >= 0 and int(registered[j]["slot"]) > int(held["slot"]):
			registered[j + 1] = registered[j]
			j -= 1
		registered[j + 1] = held
	var slots: Array = []
	for actor in registered.map(func(entry): return entry["actor"]) + others:
		slots.append({
			"id": str(actor.get("id", "")),
			"live_speed": int(actor.get("live_speed", actor.get("speed", 0))),
			"action_ready": bool(actor.get("action_ready", true)),
			"enabled": true,
		})
	# Insertion sort descending by live_speed (matches 0x407340 compare polarity).
	for i in range(1, slots.size()):
		var key: Dictionary = slots[i]
		var j := i - 1
		while j >= 0 and int(slots[j].get("live_speed", 0)) < int(key.get("live_speed", 0)):
			slots[j + 1] = slots[j]
			j -= 1
		slots[j + 1] = key
	return {
		"schema": "hsl_core_turn_queue.v1",
		"source_address": REBUILD_ADDR,
		"index": 0,
		"round": 0,
		"slots": slots,
	}


static func current(queue: Dictionary) -> Dictionary:
	var slots: Array = queue.get("slots", [])
	var index := int(queue.get("index", 0))
	while index < slots.size():
		var slot: Dictionary = slots[index]
		if bool(slot.get("enabled", true)) and not bool(slot.get("consumed", false)) and str(slot.get("id", "")) != "":
			return {
				"id": str(slot.get("id", "")),
				"live_speed": int(slot.get("live_speed", 0)),
				"action_ready": bool(slot.get("action_ready", false)),
				"index": index,
				"source_address": CURRENT_ADDR,
			}
		index += 1
	return {
		"id": "",
		"index": -1,
		"source_address": CURRENT_ADDR,
		"empty": true,
	}


## Advance past current slot (model of 0x407510 → 0x4074a0).
## When exhausted, rebuild from provided actors and bump round.
static func advance(queue: Dictionary, actors: Array = []) -> Dictionary:
	var next := queue.duplicate(true)
	var slots: Array = next.get("slots", [])
	var index := int(next.get("index", 0)) + 1
	while index < slots.size():
		var slot: Dictionary = slots[index]
		if bool(slot.get("enabled", true)) and not bool(slot.get("consumed", false)) and str(slot.get("id", "")) != "":
			next["index"] = index
			next["advanced_via"] = ADVANCE_ADDR
			return next
		index += 1
	# 0x4074a0 second pass: a slot re-enabled by 0x4075a0 (magicFun_ActiveAgain) is
	# taken from the front before the round rebuilds. Every other slot of this round
	# is already consumed (flag 0) and must stay skipped until the rebuild.
	var reactivated := -1
	for i in range(slots.size()):
		if bool(slots[i].get("reactivated", false)) and bool(slots[i].get("enabled", true)):
			reactivated = i
			break
	if reactivated >= 0:
		var marked: Array = []
		for i in range(slots.size()):
			var slot: Dictionary = slots[i].duplicate(true)
			slot["consumed"] = not bool(slot.get("reactivated", false))
			slot.erase("reactivated")
			marked.append(slot)
		next["slots"] = marked
		next["index"] = reactivated
		next["advanced_via"] = "0x4074a0_second_pass"
		return next
	# Wrap: rebuild and start new round.
	var rebuilt := rebuild(actors if not actors.is_empty() else _actors_from_slots(slots))
	rebuilt["round"] = int(next.get("round", 0)) + 1
	rebuilt["advanced_via"] = ADVANCE_ADDR
	rebuilt["wrapped"] = true
	return rebuilt


## End-turn handoff: clear remake action_ready metadata, then advance.
## STATUS_TICK_ADDR names the original status-duration reference; no full native
## status-effect tick or original action-budget equivalence is implied here.
static func end_turn(queue: Dictionary, actors: Array = []) -> Dictionary:
	var next := queue.duplicate(true)
	var slots: Array = next.get("slots", [])
	var index := int(next.get("index", 0))
	if index >= 0 and index < slots.size():
		var slot: Dictionary = slots[index].duplicate(true)
		slot["action_ready"] = false
		slots[index] = slot
		next["slots"] = slots
		next["status_tickdown"] = STATUS_TICK_ADDR
	return advance(next, actors)


static func remove_actors(queue: Dictionary, ids: Array, survivors: Array) -> Dictionary:
	var error := cancellation_input_error(queue)
	if error != "": return {"ok": false, "reason": error}
	var next := queue.duplicate(true)
	var old_index := int(current(queue).get("index", -1))
	if old_index < 0: old_index = int(queue.get("index", 0))
	var current_removed: bool = ids.has(current(queue).get("id", ""))
	var slots: Array = []
	var index := 0
	for i in range(queue["slots"].size()):
		var slot: Dictionary = queue["slots"][i]
		if ids.has(slot["id"]): continue
		if i < old_index: index += 1
		slots.append(slot.duplicate(true))
	next["slots"] = slots
	next["index"] = mini(index, slots.size())
	# Removing an earlier/future slot must preserve the same current actor and all
	# cancellation/readiness bits. Removing the current slot seeks its successor,
	# without spending the successor or running any status/extra-action callback.
	if current_removed:
		if not current(next).get("id", "").is_empty():
			next["index"] = int(current(next)["index"])
		elif not survivors.is_empty():
			next = rebuild(survivors)
			next["round"] = int(queue["round"]) + 1
			next["wrapped"] = true
	return {"ok": true, "queue": next, "current_removed": current_removed}


static func cancellation_input_error(queue: Dictionary) -> String:
	var slots: Variant = queue.get("slots")
	if not slots is Array or not queue.get("index") is int or int(queue["index"]) < -1 or int(queue["index"]) > 4096 or not queue.get("round") is int or int(queue["round"]) < 0:
		return "invalid_cancellation_queue"
	for slot in slots:
		if not slot is Dictionary or not slot.get("id") is String or not slot.get("enabled") is bool:
			return "invalid_cancellation_slot"
	return ""


static func cancel_pending(queue: Dictionary, unit_id: String) -> Dictionary:
	var error := cancellation_input_error(queue)
	if error != "": return {"ok": false, "reason": error}
	var next := queue.duplicate(true)
	# 0x407550 never changes the current actor (including a counterattack), nor
	# an already-consumed slot. Ordinary rebuilding restores eligibility next round.
	for index in range(int(next["index"]) + 1, next["slots"].size()):
		var slot: Dictionary = next["slots"][index]
		if slot["id"] == unit_id and slot["enabled"] and not bool(slot.get("consumed", false)):
			slot["enabled"] = false
			return {"ok": true, "queue": next, "index": index, "cancelled": true}
	return {"ok": true, "queue": next, "index": -1, "cancelled": false}


## 0x4075a0 (magicFun_ActiveAgain): the target's slot in [0, current) — already acted
## this round (flag 0) — is set back to 1; 0x4074a0's second pass then reaches it
## after the remaining slots. A target that has not acted yet is left alone (0).
static func can_reactivate(queue: Dictionary, unit_id: String) -> bool:
	if cancellation_input_error(queue) != "": return false
	for index in range(mini(int(queue["index"]), queue["slots"].size())):
		var slot: Dictionary = queue["slots"][index]
		if slot["id"] == unit_id and not bool(slot.get("reactivated", false)): return true
	return false


static func reactivate_consumed(queue: Dictionary, unit_id: String) -> Dictionary:
	var error := cancellation_input_error(queue)
	if error != "": return {"ok": false, "reason": error}
	var next := queue.duplicate(true)
	for index in range(mini(int(next["index"]), next["slots"].size())):
		var slot: Dictionary = next["slots"][index]
		if slot["id"] == unit_id and not bool(slot.get("reactivated", false)):
			slot["reactivated"] = true
			slot["enabled"] = true
			slot["consumed"] = false
			slot["action_ready"] = true
			return {"ok": true, "queue": next, "index": index, "reactivated": true}
	return {"ok": true, "queue": next, "index": -1, "reactivated": false}


## Default command set when no magic/special available (0x43ea30 nopqz).
static func command_name(bcmd_id: int) -> String:
	return str(BCMD_BY_ID.get(bcmd_id, ""))


static func build_command_menu(has_special: bool = false, has_magic: bool = false) -> Dictionary:
	# Mirrors 0x43ea30 utf16 tables: nopqz / nopqzv / nopqzw / nopqzvw
	var ids: Array = [BCMD_MOVE, BCMD_ATTACK, BCMD_ITEM, BCMD_WAIT, BCMD_STATUS]
	if has_magic:
		ids.append(BCMD_MAGIC)
	if has_special:
		ids.append(BCMD_SPECIAL)
	var commands: Array = []
	for id_value in ids:
		var id := int(id_value)
		commands.append({
			"id": id,
			"command": command_name(id),
			"obj_bcmd": id,
		})
	return {
		"schema": "hsl_core_bcmd_menu.v1",
		"source_address": MENU_BUILDER_ADDR,
		"commands": commands,
		"has_magic": has_magic,
		"has_special": has_special,
	}


static func _actors_from_slots(slots: Array) -> Array:
	var actors: Array = []
	for slot_value in slots:
		if typeof(slot_value) != TYPE_DICTIONARY:
			continue
		var slot: Dictionary = slot_value
		actors.append({
			"id": str(slot.get("id", "")),
			"live_speed": int(slot.get("live_speed", 0)),
			"action_ready": bool(slot.get("action_ready", true)),
		})
	return actors
