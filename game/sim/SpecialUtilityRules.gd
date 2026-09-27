extends RefCounted
## Channel1 utility bits of 0x40aa80: 天鳴覺醒 (ActiveAgain 0x10000), 獅子吼 (CancelActive
## 0x80000) and 吸血劍 (Attack+StealHP 0x100001). Each gates on one proc0 channel1 roll;
## the queue effects are proposals the PlayLoop applies through CoreTurnQueue.
## provenance:
##   rules: static-derived docs/evidence_packets/static_reverse/original_skill_function_bits.md; remake-invented (queue effects applied as proposals through CoreTurnQueue)
##   layout: n/a
##   strings: n/a
##   timing: n/a
##   audio: n/a
const Special = preload("res://game/sim/SpecialDamageRules.gd")
const PoisonArrow = preload("res://game/sim/PoisonArrowRules.gd")
const Number = preload("res://game/sim/SkillResourceRules.gd")
const Queue = preload("res://game/sim/CoreTurnQueue.gd")
const Target = preload("res://game/sim/SkillTargetRules.gd")
const Combat = preload("res://game/sim/CoreCombatRules.gd")
const ACTIVE_AGAIN := 0x10000
const CANCEL_ACTIVE := 0x80000
const STEAL_HP := 0x100000
const STEAL_GOLD := 0x20000
const STEAL_ITEM := 0x40000
## 銀之手 is the pure StealGold row (no Attack bit): same 0x40b4e8 branch without the damage prefix.
const ACCEPTED := [ACTIVE_AGAIN, CANCEL_ACTIVE, 1 | STEAL_HP, 1 | STEAL_GOLD, STEAL_GOLD, STEAL_ITEM]
const Inventory = preload("res://game/sim/InventoryRules.gd")
const Reward = preload("res://game/sim/BattleRewardRules.gd")
const ELEMENTS := {"magicEARTH": "0", "magicWATER": "1", "magicAIR": "2", "magicFIRE": "3", "magicMIND": "4"}


static func prepare(caster: Dictionary, target: Dictionary, fields: Dictionary, book: Dictionary, targeting: Dictionary, equipment: Dictionary, context: Dictionary = {}) -> Dictionary:
	var mask := Target.function_mask(fields.get("function"), targeting["function_bits"])
	if mask not in ACCEPTED: return {"ok": false, "reason": "unsupported_utility_skill"}
	var base := Special.prepare(caster, target, fields, book, equipment)
	if not base["ok"]: return base
	var resistance := 0
	var element: String = ELEMENTS.get(fields.get("type"), "")
	if element != "":
		resistance = Number._integer(target.get("combat_profile", {}).get("resist_by_type", {}).get(element))
		if resistance < 0 or resistance > 80: return {"ok": false, "reason": "missing_skill_resistance"}
	base["input"]["resistance"] = resistance
	base["input"]["proc"] = 0
	base["function_mask"] = mask
	var queue: Variant = context.get("turn_queue")
	if mask == ACTIVE_AGAIN or mask == CANCEL_ACTIVE:
		if not queue is Dictionary or Queue.cancellation_input_error(queue) != "": return {"ok": false, "reason": "missing_turn_queue_context"}
		# Remake interaction choice: refuse a cast whose native queue helper would return 0
		# (target has not acted yet / has no pending slot), like heals on full HP.
		base["useful"] = Queue.can_reactivate(queue, str(target["id"])) if mask == ACTIVE_AGAIN else Queue.cancel_pending(queue, str(target["id"]))["cancelled"]
	elif (mask & STEAL_GOLD) != 0:
		# 0x40b4e8: caster +0x28 bit 0x10000 (source mode: registered player) steals into the
		# battle gold, capped by the target record's live +0x98 (0x40b548 — the word kill gold
		# 0x40e390 returns, so the EVEF instance gold and entry growth apply: carried_gold);
		# otherwise it drains the party gold (0x4c1bcc) directly. Both come from the caller's
		# reward context.
		var mode: Variant = caster.get("growth_profile", {}).get("source", {}).get("mode")
		if not Number._integer(mode) >= 0: return {"ok": false, "reason": "missing_growth_source"}
		var data: Variant = context.get("reward_data")
		if not data is Dictionary or not data.get("actors", {}).get(str(target.get("actor_id", ""))) is Dictionary or Number._integer(data["actors"][str(target["actor_id"])].get("gold")) < 0:
			return {"ok": false, "reason": "missing_reward_context"}
		if Number._integer(context.get("gold")) < 0: return {"ok": false, "reason": "missing_reward_context"}
		base["player_side"] = (int(mode) & 0x10000) != 0
		base["target_gold"] = Reward.carried_gold(target, int(data["actors"][str(target["actor_id"])]["gold"]))
		base["party_gold"] = int(context["gold"])
		base["useful"] = true
	elif mask == STEAL_ITEM:
		# 0x40b5a8: walk the target's eight slots in order until the first empty slot (native receipt
		# original_steal_ratio.json: an empty slot ends the walk, later slots are never rolled);
		# rand(100)+1 < get_ratio + 10 + caster+0x196 steals the first passing item into the pending
		# collection (0x44f2d0) and shifts the slot (0x436e80).
		var data: Variant = context.get("reward_data")
		if not data is Dictionary or not data.get("items") is Dictionary: return {"ok": false, "reason": "missing_reward_context"}
		if not Inventory.valid(target.get("inventory")): return {"ok": false, "reason": "invalid_steal_inventory"}
		var ratios: Array = []
		for code in target["inventory"]:
			if int(code) == 0:
				ratios.append(0)
				continue
			var item: Variant = data["items"].get(str(int(code)))
			if not item is Dictionary or Number._integer(item.get("get_ratio")) < 0: return {"ok": false, "reason": "unknown_reward_inventory_item"}
			ratios.append(int(item["get_ratio"]))
		base["steal_ratios"] = ratios
		# caster +0x196: 0x448840 sets it to the PLAYERS steal_ratio word (12 when 0) and 0x448420 adds
		# every equipped item +0x40 (add_steal_ratio); ProgressionRules.refresh keeps it as combat_profile.steal_ratio.
		var steal_ratio: Variant = caster.get("combat_profile", {}).get("steal_ratio")
		if Number._integer(steal_ratio) < 0: return {"ok": false, "reason": "missing_steal_ratio"}
		base["caster_steal_ratio"] = int(steal_ratio)
		# Only the slots before the first empty one can be stolen; a target whose first slot is empty
		# has nothing the native walk would reach.
		base["useful"] = int(target["inventory"][0]) != 0
	else:
		var maximum := Number._integer(caster.get("max_hp"))
		if maximum <= 0 or maximum > 1000000 or Number._integer(caster.get("hp")) > maximum: return {"ok": false, "reason": "invalid_steal_hp_caster"}
		base["useful"] = true
	return base


static func resolve(prepared: Dictionary, caster: Dictionary, target: Dictionary, rng: Variant) -> Dictionary:
	var input: Dictionary = prepared["input"].duplicate(true)
	var mask := int(prepared["function_mask"])
	var rolled := PoisonArrow.roll(input, rng)
	var hit := bool(rolled["hit_check_passed"])
	var hp_before := int(target["hp"])
	var damage := 0
	var changes := {}
	var caster_changes := {}
	var turn_effects: Array = []
	var contribution := 0
	# Values 0x40aa80 converts through 0x40a5d0 at once (running contribution swapped, then restored);
	# ExperienceRules.record converts them in this order before the tail contribution.
	var immediate: Array = []
	if (mask & 1) != 0:
		damage = mini(hp_before, int(rolled["value"]))
		changes = {"hp": hp_before - damage, "defeated": hp_before - damage == 0}
		contribution = damage
	if (mask & STEAL_HP) != 0 and damage > 0:
		# 0x40b7c8: the caster regains the applied damage, capped at its maximum HP.
		caster_changes["hp"] = mini(int(caster["max_hp"]), int(caster["hp"]) + damage)
		# 0x40b7c3..0x40b814: contribution += damage*20/100 - damage (= damage*20/100 for the Attack+StealHP
		# row), converted at once by 0x40a5d0 (0x40b7fe) only when positive, then restored so the tail
		# conversion (0x40b866) reads the applied damage again.
		var drained_share := contribution + damage * 20 / 100 - damage
		if drained_share > 0: immediate.append(drained_share)
	var gold_effects: Array = []
	var direct_experience := 0
	if hit and (mask & STEAL_GOLD) != 0:
		# 0x40b4b3..0x40b568: rand(|high-low|) + low + 1 + rand(dex/3 + level), capped per side;
		# EXP is amount/2 + rand(amount/2) added directly, not converted through the contribution.
		var spread := absi(int(input["high"]) - int(input["low"]))
		var amount := Combat._rand_range(spread, rng) + int(input["low"]) + 1 + Combat._rand_range(int(input["dex"]) / 3 + int(input["level"]), rng)
		amount = mini(amount, int(prepared["target_gold"]) if bool(prepared["player_side"]) else int(prepared["party_gold"]))
		gold_effects.append({"kind": "steal_gold", "amount": amount, "from": "target_carry" if bool(prepared["player_side"]) else "party", "unit_id": str(target["id"])})
		direct_experience = Combat._rand_range(amount / 2, rng) + amount / 2
	var item_effects: Array = []
	if hit and mask == STEAL_ITEM:
		for slot in range(Inventory.CAPACITY):
			var code := int(target["inventory"][slot])
			if code == 0: break
			var draw := Combat._rand_range(100, rng) + 1
			if draw >= int(prepared["steal_ratios"][slot]) + 10 + int(prepared["caster_steal_ratio"]): continue
			var removed := Inventory.remove(target["inventory"], slot, code)
			changes["inventory"] = removed["inventory"]
			item_effects.append({"kind": "steal_item", "code": code, "source_slot": slot, "unit_id": str(target["id"]), "steal_roll": draw})
			# 0x40b641..0x40b68b: the proc0 value joins the tail contribution; rand(level)+1 converts at once (0x40b674).
			contribution += int(rolled["value"])
			immediate.append(Combat._rand_range(int(input["level"]), rng) + 1)
			break
	if hit and mask in [ACTIVE_AGAIN, CANCEL_ACTIVE]:
		turn_effects.append({"kind": "reactivate" if mask == ACTIVE_AGAIN else "cancel_pending", "unit_id": str(target["id"])})
		# 0x40b6fa / 0x40b770: rand(caster level)+1 converted at once when the queue helper succeeded.
		immediate.append(Combat._rand_range(int(input["level"]), rng) + 1)
	return {"hit": hit, "roll": rolled, "damage": damage, "target_changes": changes, "caster_changes": caster_changes,
		"turn_effects": turn_effects, "gold_effects": gold_effects, "item_effects": item_effects, "direct_experience": direct_experience,
		"native_contribution": contribution, "immediate_contributions": immediate, "hit_bonus_after": int(rolled["hit_bonus_after"])}
