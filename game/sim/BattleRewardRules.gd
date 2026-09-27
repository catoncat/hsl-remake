extends RefCounted
## Pure reward proposals. PlayLoop owns money, inventories, RNG and claim revisions.
## Native carry/drop comparisons: battle_reward_inputs.md. Carry and drops draw from the
## original global stream (GlobalRandomStream, not saved); eligibility is a remake policy.
## provenance:
##   rules: static-derived docs/evidence_packets/static_reverse/battle_reward_inputs.md
##   rules: static-derived docs/evidence_packets/static_reverse/original_ai_navigation.md
##   rules: static-derived docs/evidence_packets/static_reverse/original_skill_function_bits.md
##   rules: static-derived docs/evidence_packets/static_reverse/original_player_mode.md
##   rules: provisional (the drops ahead of a StealItem take in one receipt's collection is remake order, unproven)
##   rules: resource-derived content/generated/hsl/combat/rewards.json
##   rules: runtime-measured tools/hsltools/probes/_reward_rng_trace.py
##     (carry 0x407c86 rand(101), drops 0x44f5d3 rand(100), both global 0x458c10; 32 seeds match)
##   rules: remake-invented (eligibility, claim revisions; controlled recipients always take the party branch)
const InventoryRules = preload("res://game/sim/InventoryRules.gd")
const CombatSequenceRules = preload("res://game/sim/CombatSequenceRules.gd")
const ActorRoleRules = preload("res://game/sim/ActorRoleRules.gd")
const GlobalRandomStream = preload("res://game/sim/GlobalRandomStream.gd")
## Gold the unit's own record +0x98 gained in this battle (0x442720 state 2, 0x442856..0x442875):
## kill gold and StealGold takes paid to a recipient that does not pay the party. The template,
## EVEF instance and entry growth part stays derived (carried_gold); only the gain is stored.
const CARRIED_GAINED := "carried_gold_gained"
const MODULUS := 2147483647
const EMPTY_BAG := [0, 0, 0, 0, 0, 0, 0, 0]


static func integer(value: Variant, minimum: int = 0, maximum: int = 2147483647) -> bool:
	return typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(value)) and value >= minimum and value <= maximum and value == int(value)


static func data_error(data: Dictionary, units: Array) -> String:
	if data.get("schema") != "hsl_battle_rewards.v1" or not data.get("actors") is Dictionary or not data.get("items") is Dictionary:
		return "missing_reward_data"
	for code in data["items"]:
		var item: Variant = data["items"][code]
		if not item is Dictionary or not integer(item.get("get_ratio"), 0, 100) or not item.get("important") is bool:
			return "invalid_drop_definition"
	for unit in units:
		if not unit is Dictionary or not data["actors"].get(str(unit.get("actor_id", ""))) is Dictionary:
			return "missing_reward_actor"
		var source: Dictionary = data["actors"][str(unit["actor_id"])]
		if not integer(source.get("gold")) or not source.get("carry_items") is Array:
			return "invalid_reward_actor"
		if not integer(source.get("status_raw")) or int(source["status_raw"]) != 0:
			return "unsupported_reward_actor_flags"
		for code in source["carry_items"]:
			if not integer(code, -1) or (int(code) > 0 and not data["items"].has(str(int(code)))):
				return "invalid_carry_item"
		if unit.has(CARRIED_GAINED) and not integer(unit[CARRIED_GAINED]):
			return "invalid_carried_gold"
		if unit.has("inventory"):
			if not unit["inventory"] is Array or not InventoryRules.valid(unit["inventory"]):
				return "invalid_reward_inventory"
			for code in unit["inventory"]:
				if not integer(code) or (int(code) > 0 and not data["items"].has(str(int(code)))):
					return "unknown_reward_inventory_item"
	return ""


## 0x407c40 (called only from the birth 0x407cc0 at 0x407e3b, for a pmEnemy after the frame-delay
## rand(24) 0x407dba and before the level adjustment 0x40e870): rand(101) at 0x407c86 on the global
## stream per listed code until one is at or under the threshold. `state` is a GlobalRandomStream state.
static func carry(choices: Array, state: Array) -> Dictionary:
	var threshold := 24
	for value in choices:
		var code := int(value)
		if code == 0: break
		if code != -1:
			var roll := GlobalRandomStream.rand(state, 101)
			state = roll["state"]
			if int(roll["value"]) <= threshold:
				return {"code": code, "state": state}
		if threshold >= 10: threshold -= 6
	return {"code": 0, "state": state}


## One birth's carry into `loop`: an enemy_ai (pmEnemy) actor rolls its template carry list once on
## the loop's global stream (written back) and the chosen code goes into its first empty bag slot
## (0x436e30). Other actors draw nothing. Returns "" or "inventory_full".
static func install_carry(loop: Dictionary, actor: Dictionary) -> String:
	if actor.get("battle_actor_role") != "enemy_ai": return ""
	var roll := carry(loop["reward_data"]["actors"][str(actor["actor_id"])]["carry_items"], loop[GlobalRandomStream.LOOP_KEY])
	loop[GlobalRandomStream.LOOP_KEY] = roll["state"]
	if int(roll["code"]) <= 0: return ""
	var inserted := InventoryRules.insert(actor["inventory"], int(roll["code"]))
	if not inserted["ok"]: return "inventory_full"
	actor["inventory"] = inserted["inventory"]
	return ""


## 0x44f580: rand(100) at 0x44f5d3 on the global stream per non-important bag item, in slot order;
## an important item is taken without a draw. `state` is a GlobalRandomStream state.
static func drops(inventory: Array, items: Dictionary, state: Array) -> Dictionary:
	var found: Array = []
	for slot in range(inventory.size()):
		var code := int(inventory[slot])
		if code == 0: continue
		var item: Dictionary = items[str(code)]
		var accepted: bool = item["important"]
		if not accepted:
			var roll := GlobalRandomStream.rand(state, 100)
			state = roll["state"]
			# The native branch skips when (rand(100) + 1) >= get_ratio.
			accepted = int(roll["value"]) + 1 < int(item["get_ratio"])
		if accepted: found.append({"code": code, "source_slot": slot})
	return {"items": found, "state": state}


static func results(receipt: Dictionary) -> Array:
	return CombatSequenceRules.outcomes(receipt).duplicate(true)


static func kill_gold(target: Dictionary, template_gold: int) -> int:
	## The original install callback 0x42bd50 (jump table 0x42c0a8, word index 0) writes
	## the EVEF instance value over live +0x98 after the PLAYERS template copy, so the
	## per-instance word is the kill gold whenever the record carries one.
	var overrides: Variant = target.get("evef_instance", {}).get("overrides", {})
	if overrides is Dictionary and overrides.has("gold"): return int(overrides["gold"])
	return template_gold


static func carried_gold(target: Dictionary, template_gold: int) -> int:
	## Live record +0x98 (record = [0x4c1bc8] + obj+0xa4 * 0x1fc — 0x4c1bc8 holds the table
	## pointer, loaded by 0x40aa87／0x40e394 `mov reg, [0x4c1bc8]`): the template copy, the EVEF
	## instance word (kill_gold) and the entry growth rewrite (EntryGrowthRules.gold). Kill gold
	## 0x40e390 returns this word and StealGold caps a registered caster by it (0x40b548), so
	## both read it here (SpecialUtilityRules STEAL_GOLD). What the record gained in battle
	## (CARRIED_GAINED, `accrues`) adds on top.
	return mini(MODULUS, preload("res://game/sim/EntryGrowthRules.gd").gold(target, kill_gold(target, template_gold)) + int(target.get(CARRIED_GAINED, 0)))


## 0x442720 state 2 (0x442827..0x442835): gold goes to the party 0x4c1bcc only when
## 0x40ba20(recipient) — the live +0x28 & 0x870000 — is exactly 0x10000; every other
## recipient (enemy, NPC, 0x50000／0x30000 camps, 0x870000) adds it to its own record +0x98.
static func pays_party(unit: Dictionary) -> bool:
	return (ActorRoleRules.side_mask(unit) | (int(unit.get("player_mode", 0)) & ActorRoleRules.MAGIC_ONLY_BIT)) == ActorRoleRules.SIDE_PLAYER


## 0x442837..0x44284a: `add [0x4c1bcc], gold` then `cmp 0x3b9ac9ff; jle` — every state-2 payment
## into the party gold is capped at 999,999,999.
const PARTY_GOLD_CAP := 0x3b9ac9ff


## The party gold after one state-2 payment. A remake balance already above the cap (which the
## original cannot reach through state 2) is left as it is rather than lowered.
static func pay_party(before: int, amount: int) -> int:
	return maxi(before, mini(PARTY_GOLD_CAP, before + amount))


## Whether the kill of `victim` in `receipt` pays `recipient` at all. The AI's main strike (0x4415bc
## → 0x4c2c84, paid 0x4416ca), the counter that kills an AI initiator (0x44151d → 0x4c2978, paid by
## the victim's death sequence 0x43f150) and spell kills (0x442e5c／0x443130 → 0x4c2c84) all pay the
## killer. A player-process initiator killed by the counter pays nothing: that series (0x444641)
## never adds 0x40e390 and its death sequence (0x443660) pays gold 0.
static func credited(recipient: Dictionary, victim: Dictionary, receipt: Dictionary) -> bool:
	if str(recipient["id"]) == str(victim["id"]): return false
	return not (str(victim["id"]) == str(receipt.get("attacker_id", "")) and bool(victim.get("player_commandable", false)))


## Whether the kill of `victim` in `receipt` pays `recipient`'s own record +0x98.
static func accrues(recipient: Dictionary, victim: Dictionary, receipt: Dictionary) -> bool:
	return keeps_gold(recipient) and credited(recipient, victim, receipt)


## A state-2 recipient on the party branch: a friendly AI whose 0x40ba20 is exactly 0x10000
## (0x442835), or a controlled recipient — kept on the party path whatever its mode (remake policy,
## unchanged; the original would branch on its live mode too).
static func party_recipient(unit: Dictionary) -> bool:
	return bool(unit.get("player_commandable", false)) or pays_party(unit)


## A recipient whose state-2 gold stays on its own record (0x442856..0x442875).
static func keeps_gold(unit: Dictionary) -> bool:
	return not party_recipient(unit)


## 0x442819..0x442825: before either branch state 2 calls 0x40e2d0(recipient) — 0x40e240 testing the
## live +0x18c bit 0x20 — and doubles the payment (`add esi, esi`); the $ float 0x44288a shows the
## doubled amount. The bit is an equipped ITEM row's gold_x2 (the loader ORs 0x20 at 0x447e7c; the
## equipment refresh ORs the item word into +0x18c at 0x448709..0x448717), so two such items still
## double once. Equipment is the only modelled source; a missing or unknown row does not double.
static func gold_multiplier(unit: Dictionary, equipment: Dictionary) -> int:
	var slots: Variant = unit.get("equipment", [])
	if not slots is Array: return 1
	for slot in slots:
		if not slot is Dictionary or not integer(slot.get("item_code"), 1): continue
		var item: Variant = equipment.get(str(int(slot["item_code"])))
		if item is Dictionary and bool(item.get("gold_double", false)): return 2
	return 1


## A kill row paying `amount` to `recipient` after the state-2 doubling; `gold_multiplier` is only
## recorded when the payment was doubled.
static func _kill_row(recipient_key: String, recipient: Dictionary, defender_id: String, amount: int, multiplier: int) -> Dictionary:
	var row := {recipient_key: recipient["id"], "defender_id": defender_id, "gold": amount * multiplier}
	if multiplier != 1: row["gold_multiplier"] = multiplier
	return row


## 0x442720 state 4 for a recipient that is not a player process (+0x64 != 3, 0x44272b／0x4428c3):
## 0x44f600 walks the pending collection — one (code, count) entry per distinct code, since 0x44f2d0
## adds a repeated code to its entry's count (0x44f290／0x44f39b) — and puts ONE of each code into the
## recipient's first empty bag slot (0x436e30). A full bag drops its first non-important item
## (0x44f510: item+0xa0 bit 0x8000000 guards; 0x436e80 closes the gap) and retries once; a second
## failure stops the walk. 0x44f4e0 then empties the collection, so nothing left over survives.
## Rows: one per distinct code in collection order — `slot` -1 when lost, `discarded` when a bag item
## made room, `sources` the collection entries it stands for.
static func hand_over(inventory: Array, entries: Array, items: Dictionary) -> Dictionary:
	var bag: Array = inventory.map(func(value): return int(value))
	var rows: Array = []
	for entry in entries:
		var code := int(entry["code"])
		var existing: Array = rows.filter(func(row): return int(row["code"]) == code)
		if not existing.is_empty():
			existing[0]["sources"].append(str(entry["id"]))
			continue
		rows.append({"code": code, "slot": -1, "sources": [str(entry["id"])]})
	var stopped := false
	for row in rows:
		if stopped: continue
		var inserted := InventoryRules.insert(bag, int(row["code"]))
		if not inserted["ok"]:
			for slot in range(bag.size()):
				if int(bag[slot]) != 0 and not bool(items[str(int(bag[slot]))]["important"]):
					row["discarded"] = int(bag[slot])
					bag = InventoryRules.remove(bag, slot, int(bag[slot]))["inventory"]
					break
			inserted = InventoryRules.insert(bag, int(row["code"]))
		if inserted["ok"]:
			bag = inserted["inventory"]
			row["slot"] = int(inserted["slot"])
		else:
			stopped = true
	return {"inventory": bag, "rows": rows}


## Add accrual rows ({unit_id, gold}) to the units' own carried gold.
static func accrue(units: Array, rows: Array) -> void:
	for row in rows:
		for unit in units:
			if str(unit["id"]) == str(row["unit_id"]):
				unit[CARRIED_GAINED] = mini(MODULUS, int(unit.get(CARRIED_GAINED, 0)) + int(row["gold"]))


## Whether `hit` is a lethal hit an undead defender got up from: the exchange strike's own flag or
## the skill receipt's revived ids. Its kill gold is still paid (the kill sections read +0xd8 <= 0
## before the victim's tick revives it), but no bag is rolled (0x44f580 skips an undead record,
## 0x446bb0) and it is no death. An undead initiator the counter kills is excluded: its death
## sequence never runs, so nobody is paid (0x407510; BattleLoopCombat._attacker_revived).
static func undead_kill(hit: Dictionary, id: String, revived_ids: Array, receipt: Dictionary) -> bool:
	if id == str(receipt.get("attacker_id", "")): return false
	return (hit.get("undead_revived") is bool and bool(hit["undead_revived"])) or revived_ids.has(id)


## `equipment`: the loop's equipment table, read for the recipient's gold doubling (gold_multiplier).
static func generate(receipt: Dictionary, units: Array, data: Dictionary, state: Array, rewarded: Array, equipment: Dictionary = {}) -> Dictionary:
	var by_id := {}
	for unit in units: by_id[str(unit["id"])] = unit
	var revived_ids: Array = receipt["undead_revived"] if receipt.get("undead_revived") is Array else []
	var undead_paid: Array = []
	var deaths: Array = []
	var kills: Array = []
	var pending: Array = []
	var carried: Array = []
	var taken: Array = []
	var gold := 0
	for hit in results(receipt):
		var id := str(hit["defender_id"])
		var undead := undead_kill(hit, id, revived_ids, receipt)
		if undead:
			if int(hit["defender_hp_before"]) <= 0 or undead_paid.has(id) or rewarded.has(id): continue
			undead_paid.append(id)
		else:
			if int(hit["defender_hp_before"]) <= 0 or int(hit["defender_hp_after"]) > 0 or deaths.has(id) or rewarded.has(id): continue
			deaths.append(id)
		var attacker: Dictionary = by_id[str(hit["attacker_id"])]
		var target: Dictionary = by_id[id]
		var amount := carried_gold(target, int(data["actors"][str(target["actor_id"])]["gold"]))
		var multiplier := gold_multiplier(attacker, equipment)
		if not bool(attacker.get("player_commandable", false)):
			# Its victim's bag is rolled into the collection whatever the victim or the gold
			# (0x44f580 in every kill section, 0x44469e included), and state 4 hands it to the killer.
			if str(attacker["id"]) != id and not undead:
				var rolled_ai := drops(target.get("inventory", EMPTY_BAG), data["items"], state)
				state = rolled_ai["state"]
				for item in rolled_ai["items"]:
					item["id"] = "%d:%s:%d" % [int(receipt["sequence"]), id, int(item["source_slot"])]
					item["source_id"] = id
					item["unit_id"] = str(attacker["id"])
					taken.append(item)
			# An AI killer is paid through 0x442720 state 2 (a zero amount skips, 0x442810): a friendly
			# AI on exactly 0x10000 into the party gold (0x442837..0x44284a), any other into its own
			# record +0x98 (0x442856..0x442875).
			if not credited(attacker, target, receipt) or amount <= 0: continue
			if pays_party(attacker):
				gold += amount * multiplier
				kills.append(_kill_row("attacker_id", attacker, id, amount, multiplier))
			else:
				carried.append(_kill_row("unit_id", attacker, id, amount, multiplier))
			continue
		# Shared party money; controlled actors earn it on hostile kills, including
		# counters. Story departures do not grant player loot.
		if target.get("battle_actor_role") != "enemy_ai": continue
		gold += amount * multiplier
		kills.append(_kill_row("attacker_id", attacker, id, amount, multiplier))
		if undead: continue
		var rolled := drops(target["inventory"], data["items"], state)
		state = rolled["state"]
		for item in rolled["items"]:
			item["id"] = "%d:%s:%d" % [int(receipt["sequence"]), id, int(item["source_slot"])]
			item["source_id"] = id
			pending.append(item)
	return {"gold": gold, "kills": kills, "pending": pending, "deaths": deaths, "state": state, "carried": carried, "taken": taken}


static func transfer(pending: Array, entry_id: String, inventory: Array, slot: int, expected_code: int) -> Dictionary:
	var index := -1
	for i in range(pending.size()):
		if pending[i]["id"] == entry_id: index = i; break
	if index < 0 or not InventoryRules.valid(inventory) or slot < -1 or slot >= InventoryRules.CAPACITY:
		return {"ok": false, "reason": "stale_claim"}
	if (slot == -1 and expected_code != 0) or (slot >= 0 and int(inventory[slot]) != expected_code):
		return {"ok": false, "reason": "stale_inventory_slot"}
	var bag := inventory.duplicate()
	if expected_code != 0: bag = InventoryRules.remove(bag, slot, expected_code)["inventory"]
	var item: Dictionary = pending[index].duplicate(true)
	var inserted := InventoryRules.insert(bag, int(item["code"]))
	if not inserted["ok"]: return inserted
	var remaining := pending.duplicate(true)
	if expected_code == 0:
		remaining.remove_at(index)
	else:
		# Displaced items stay visible in the loot pool; cancelling never destroys one.
		remaining[index]["code"] = expected_code
		remaining[index]["source_id"] = "backpack"
		remaining[index]["source_slot"] = slot
	return {"ok": true, "inventory": inserted["inventory"], "pending": remaining, "item": item, "returned_code": expected_code}


static func combat_sequence(settlement: Dictionary) -> int:
	# Legacy combat-only ledgers used the same number for both streams. A chest
	# must never fabricate a combat receipt or suppress the next real combat.
	return int(settlement.get("combat_sequence", settlement.get("sequence", 0)))


static func settle(previous: Dictionary, kind: String, combat: int, gold_before: int, gold: int, pending: Array, kills: Array, owner_id: String = "", source_id: String = "") -> Dictionary:
	return {"sequence": maxi(combat, int(previous.get("sequence", 0)) + 1), "revision": 0,
		"source_kind": kind, "source_id": source_id, "owner_id": owner_id, "combat_sequence": combat,
		"closed": pending.is_empty(), "gold": gold, "gold_before": gold_before, "gold_after": gold_before + gold,
		"pending": previous.get("pending", []).duplicate(true) + pending.duplicate(true),
		"claimed": [], "abandoned": [], "kills": kills.duplicate(true)}


static func pending_error(entries: Variant, items: Dictionary) -> String:
	if not entries is Array or entries.size() > 4096: return "invalid_pending_items"
	var ids := {}
	for entry in entries:
		if not entry is Dictionary or not entry.get("id") is String or entry["id"] == "" or ids.has(entry["id"]): return "invalid_pending_item_identity"
		if not integer(entry.get("code"), 1) or not items.has(str(int(entry["code"]))) or not entry.get("source_id") is String or not integer(entry.get("source_slot")):
			return "invalid_pending_item_source"
		ids[entry["id"]] = true
	return ""


static func carry_pending(loop: Dictionary) -> Dictionary:
	var entries: Array = loop.get("settlement", {}).get("pending", [])
	if entries.is_empty(): return {}
	var carried: Array = []
	for entry in entries:
		# Namespacing prevents a repeated battle's fresh chest/kill from colliding
		# with unclaimed items brought from the prior visit. This is not a reroll.
		var id := "carry:" + (str(loop.get("scenario_id", loop.get("scenario_path", ""))) + ":" + str(entry["id"])).sha256_text()
		carried.append({"id": id, "code": int(entry["code"]), "source_id": "campaign", "source_slot": carried.size()})
	return {"schema": "hsl_pending_rewards.v1", "items": carried}
