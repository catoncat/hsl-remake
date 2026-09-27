extends RefCounted
## Battle loop settlement: the once-per-exchange reward commit (`_commit_rewards`: shared
## gold, instantiated pending loot, death de-duplication, kill tallies), the pending-loot
## interaction (`loot_waiting`, `claim_reward`, `finish_rewards`, `reopen_rewards`), the
## enemy installation carry roll (`_initial_carry`), the completed-action experience award
## with its level-up learning (`_award_experience`) and the player's manual growth
## allocation (`allocate_growth`), plus the reward/experience input validators. Static
## functions over the one loop dictionary; BattlePlayLoop forwards to them and stays
## the single mutable battle-state owner.
## provenance:
##   rules: static-derived docs/evidence_packets/static_reverse/battle_reward_inputs.md; static-derived docs/evidence_packets/static_reverse/original_experience.md; static-derived docs/evidence_packets/static_reverse/original_growth_lifecycle.md; static-derived docs/evidence_packets/static_reverse/original_growth_window.md; static-derived docs/evidence_packets/static_reverse/original_skill_function_bits.md; static-derived docs/evidence_packets/static_reverse/original_player_mode.md; runtime-measured tools/hsltools/probes/_reward_rng_trace.py (carry and drops draw the global stream 0x458c10); remake-invented (claim／defer／abandon interaction, sequence／revision guards — docs/architecture/BATTLE_SYSTEMS.md#rewards-and-checkpoints)
##   layout: n/a
##   strings: n/a
##   timing: n/a
##   audio: n/a

const Loop = preload("res://game/battle/scene/BattlePlayLoop.gd")
const CombatSequence = preload("res://game/sim/CombatSequenceRules.gd")
const ProgressionRules = preload("res://game/sim/ProgressionRules.gd")
const ExperienceRules = preload("res://game/sim/ExperienceRules.gd")
const InventoryRules = preload("res://game/sim/InventoryRules.gd")
const RewardRules = preload("res://game/sim/BattleRewardRules.gd")
const ItemResolutionRules = preload("res://game/sim/ItemResolutionRules.gd")
const TurnEndRules = preload("res://game/sim/TurnEndRules.gd")
const Presence = preload("res://game/sim/BattlePresenceRules.gd")
const Treasure = preload("res://game/sim/TreasureRules.gd")
const BattleOutcome = preload("res://game/sim/BattleOutcome.gd")


## `ended`: a reason the action ended before its completion award (the exchange's undead
## attacker revived after the counter — BattleLoopCombat._resolve_exchange); nothing is paid.
static func _award_experience(loop: Dictionary, strike: Dictionary, ended: String = "") -> void:
	var actor := Loop._unit(loop, str(strike["attacker_id"]))
	var total := 0
	var killed := false
	for hit in CombatSequence.participant_outcomes(strike):
		total += int(hit["experience_basis"]["points"])
		killed = killed or bool(hit["experience_basis"]["killed"])
	var multiplier: int = ExperienceRules.multiplier(actor, loop["equipment_items"])["value"]
	var reason := ""
	if ended != "": reason = ended
	elif int(actor["hp"]) == 0 or bool(actor.get("defeated", false)): reason = "actor_defeated"
	elif not actor.has("growth_profile"): reason = "unsupported_growth_model"
	elif actor["growth_profile"].get("allocation") == "fixed_template": reason = "fixed_template_progression"
	elif ProgressionRules.growth_capacity(actor) <= int(actor["pending_stat_points"]): reason = "growth_capacity_exhausted"
	elif total == 0: reason = "no_contribution"
	var amount := total * multiplier if reason == "" else 0
	strike["experience_settlement"] = {"base": total, "multiplier": multiplier, "awarded": amount, "reason": reason,
		"scope": "completed_action", "source": "0x4427a9..0x4427e7"}
	if killed: strike["kill_chain"] = int(actor["kill_chain_word"]) & 0xffff
	if amount <= 0: return
	var old_level := int(actor["level"])
	var old_exp := int(actor["exp"])
	actor.merge(ProgressionRules.resolve_experience(actor, amount, loop["equipment_items"]), true)
	var learned: Array = []
	if int(actor["level"]) > old_level:
		var acquisition := ProgressionRules.Learning.acquire(actor, loop["skill_book"], "magic")
		learned = ProgressionRules.Learning.labels(acquisition["added"], loop["skill_book"])
		actor.merge(ProgressionRules.refresh_growth_stats(acquisition["actor"], loop["equipment_items"]), true)
	strike["experience"] = {"gained": amount, "base": total, "multiplier": multiplier,
		"level_before": old_level, "level_after": int(actor["level"]), "exp_before": old_exp, "exp_after": int(actor["exp"]),
		"allocation": actor["growth_profile"]["allocation"], "learning": learned}


## Any living player-commandable member may spend its points, not only the current actor:
## the original opens the level-up window (0x442720 phase 8) for every player object whose
## experience settles, the enemy turn's counter included. The terminal result still locks it.
static func allocate_growth(loop: Dictionary, unit_id: String, allocation: Dictionary) -> Dictionary:
	var next := Loop.copy(loop)
	if loot_waiting(loop): return next
	var actor := Loop._unit(next, unit_id)
	# A won battle still takes the final blow's points (0x442720 phase 8 opens the window before
	# the win scan); a lost one takes none. Nothing else is allowed after the result.
	if not bool(next.get("scenario_ok", false)) or (BattleOutcome.decided(next) and not BattleOutcome.won(next)):
		return next
	if actor.is_empty() or not bool(actor.get("player_commandable", false)) or not Presence.living(actor) or bool(actor.get("departed", false)):
		return next
	var before_points := int(actor["pending_stat_points"])
	actor.merge(ProgressionRules.apply_allocation(actor, allocation, next["equipment_items"]), true)
	if int(actor["pending_stat_points"]) < before_points:
		var acquired := ProgressionRules.Learning.acquire(actor, next["skill_book"], "special")
		actor.merge(ProgressionRules.refresh_growth_stats(acquired["actor"], next["equipment_items"]), true)
	return next


static func _reward_input_error(loop: Dictionary) -> String:
	var treasure_error := Treasure.state_error(loop)
	if treasure_error != "": return treasure_error
	var settlement_error := Treasure.settlement_error(loop)
	if settlement_error != "": return settlement_error
	var item_error := ItemResolutionRules.state_error(loop)
	if item_error != "": return item_error
	var tail_error := TurnEndRules.state_error(loop)
	if tail_error != "": return tail_error
	if loop.get("stat_refresh_policy") != ProgressionRules.JobStats.MODEL: return "invalid_stat_refresh_policy"
	var extra_error := Loop._extra_action_input_error(loop)
	if extra_error != "": return extra_error
	if not RewardRules.integer(loop.get("gold"), 0, 9000000000000000) or not RewardRules.GlobalRandom.valid(loop.get(RewardRules.GlobalRandom.LOOP_KEY)):
		return "invalid_reward_state"
	return RewardRules.data_error(loop.get("reward_data", {}), loop.get("units", []))


## The birth 0x407cc0 calls the carry selector 0x407c40 once for a pmEnemy (0x407e3b), on the
## global stream after the frame-delay rand(24) and before the level adjustment 0x40e870. Friendly
## inventories and Leonard's authored starting medicine are retained. Respawns sample afresh.
static func _initial_carry(loop: Dictionary, actor: Dictionary) -> void:
	var error := RewardRules.install_carry(loop, actor)
	assert(error == "", "Initial carry needs an available source inventory slot")


static func _commit_rewards(loop: Dictionary, receipt: Dictionary) -> void:
	var sequence := int(receipt["sequence"])
	if sequence <= RewardRules.combat_sequence(loop["settlement"]): return
	assert(not loot_waiting(loop), "Unclaimed loot must finish before another exchange")
	var result := RewardRules.generate(receipt, loop["units"], loop["reward_data"], loop[RewardRules.GlobalRandom.LOOP_KEY], loop["rewarded_unit_ids"], loop["equipment_items"])
	# 金之手 (StealItem): 0x44f2d0 puts the stolen item into the same pending collection the
	# drops use, so claiming, deferring and the full-pack exchange path are shared. A caster that
	# is not a player process takes it into its own bag at state 4 (0x44f600).
	var caster_id := str(receipt.get("attacker_id", ""))
	var caster := Loop._unit(loop, caster_id)
	var ai_caster := not caster.is_empty() and not bool(caster.get("player_commandable", false))
	for item in receipt.get("stolen_items", []):
		var entry := {"code": int(item["code"]), "source_slot": int(item["source_slot"]), "source_id": str(item["unit_id"]),
			"id": "%d:%s:%d:stolen" % [sequence, str(item["unit_id"]), int(item["source_slot"])]}
		if ai_caster:
			entry["unit_id"] = caster_id
			result["taken"].append(entry)
		else:
			result["pending"].append(entry)
	var before := int(loop["gold"])
	# 0x442837..0x44284a: the party payment is capped at 0x3b9ac9ff.
	loop["gold"] = RewardRules.pay_party(before, int(result["gold"]))
	loop[RewardRules.GlobalRandom.LOOP_KEY] = result["state"]
	for id in result["deaths"]:
		loop["rewarded_unit_ids"].append(id)
		Loop._unit(loop, id)["inventory"] = [0, 0, 0, 0, 0, 0, 0, 0]
	# 0x442720 state 4 → 0x44f600: an AI recipient takes the collection into its own bag.
	var taken: Array = []
	var recipients: Array = []
	for entry in result["taken"]:
		if not recipients.has(entry["unit_id"]): recipients.append(entry["unit_id"])
	for unit_id in recipients:
		var recipient := Loop._unit(loop, unit_id)
		var handed := RewardRules.hand_over(recipient.get("inventory", RewardRules.EMPTY_BAG), result["taken"].filter(func(entry): return entry["unit_id"] == unit_id), loop["reward_data"]["items"])
		recipient["inventory"] = handed["inventory"]
		for row in handed["rows"]:
			row["unit_id"] = unit_id
			taken.append(row)
	for kill in result["kills"]:
		var owner := Loop._unit(loop, kill["attacker_id"])
		owner["kills"] = int(owner.get("kills", 0)) + 1
	# 0x442720 state 2: an enemy／NPC killer's kill gold goes to its own record +0x98.
	RewardRules.accrue(loop["units"], result["carried"])
	loop["settlement"] = RewardRules.settle(loop["settlement"], "combat", sequence, before, int(loop["gold"]) - before, result["pending"], result["kills"])
	# Immutable presentation receipt; claim edits never change the combat receipt.
	receipt["rewards"] = {"gold": result["gold"], "kills": result["kills"].duplicate(true), "item_count": result["pending"].size()}
	if not result["carried"].is_empty(): receipt["rewards"]["carried"] = result["carried"].duplicate(true)
	if not taken.is_empty(): receipt["rewards"]["taken"] = taken


static func loot_waiting(loop: Dictionary) -> bool:
	return not loop.get("settlement", {}).is_empty() and not bool(loop["settlement"].get("closed", true))


static func loot_recipients(loop: Dictionary) -> Array:
	return loop["units"].filter(func(actor): return bool(actor.get("player_commandable", false)) and Presence.living(actor)).map(func(actor): return str(actor["id"]))


static func claim_reward(loop: Dictionary, sequence: int, revision: int, entry_id: String, recipient_id: String, slot: int = -1, expected_code: int = 0) -> Dictionary:
	if not _claim_current(loop, sequence, revision) or not loot_recipients(loop).has(recipient_id): return Loop.copy(loop)
	var proposal := RewardRules.transfer(loop["settlement"]["pending"], entry_id, Loop._unit(loop, recipient_id)["inventory"], slot, expected_code)
	if not proposal["ok"]: return Loop.copy(loop)
	var next := Loop.copy(loop)
	Loop._unit(next, recipient_id)["inventory"] = proposal["inventory"]
	next["settlement"]["pending"] = proposal["pending"]
	var claimed: Dictionary = proposal["item"]
	claimed.merge({"recipient_id": recipient_id, "returned_code": proposal["returned_code"]})
	next["settlement"]["claimed"].append(claimed)
	next["settlement"]["revision"] += 1
	next["item_revision"] += 1
	return next


static func finish_rewards(loop: Dictionary, sequence: int, revision: int, abandon: bool = false, defer: bool = false) -> Dictionary:
	if not _claim_current(loop, sequence, revision): return Loop.copy(loop)
	var pending: Array = loop["settlement"]["pending"]
	if not pending.is_empty() and not defer:
		if not abandon: return Loop.copy(loop)
		for item in pending:
			if loop["reward_data"]["items"][str(item["code"])]["important"]: return Loop.copy(loop)
	var next := Loop.copy(loop)
	if not defer:
		next["settlement"]["abandoned"] = pending.duplicate(true)
		next["settlement"]["pending"] = []
	next["settlement"]["closed"] = true
	next["settlement"]["revision"] += 1
	return next


static func reopen_rewards(loop: Dictionary) -> Dictionary:
	var allowed: bool = Loop._player_action_valid(loop, "action_menu", true) or (bool(loop.get("scenario_ok", false)) and BattleOutcome.decided(loop) and not loot_waiting(loop))
	if not allowed or loop.get("settlement", {}).get("pending", []).is_empty(): return Loop.copy(loop)
	var next := Loop.copy(loop)
	next["settlement"]["closed"] = false
	next["settlement"]["revision"] += 1
	return next


static func _claim_current(loop: Dictionary, sequence: int, revision: int) -> bool:
	return bool(loop.get("scenario_ok", false)) and loot_waiting(loop) and _reward_input_error(loop) == "" and int(loop["settlement"]["sequence"]) == sequence and int(loop["settlement"]["revision"]) == revision


## 0x40b4e8 StealGold proposals: a caster with +0x28 bit 0x10000 takes from the target's +0x98
## (not lowered, 0x40b548..0x40b554), any other drains the party gold at once (0x40b55c..0x40b578).
## Both add the take to 0x4c2c84, which the completion award pays the caster through 0x442720
## state 2 (0x4416bc／0x4447d8): into the party (`party_recipient`, capped 0x44283e..0x44284a) or
## its own record +0x98 (0x442856..0x442875) — the same branch as the kill gold, doubled first when
## the caster wears gold_x2 (0x442819..0x442825, RewardRules.gold_multiplier).
static func _apply_gold_effects(loop: Dictionary, strike: Dictionary, effects: Array) -> void:
	if effects.is_empty(): return
	var applied: Array = []
	var caster := Loop._unit(loop, str(strike["attacker_id"]))
	for effect in effects:
		var before := int(loop["gold"])
		var take := int(effect["amount"])
		if effect["from"] == "party":
			# 0x40b562..0x40b566 caps the take by the party gold before it leaves 0x4c1bcc.
			loop["gold"] = maxi(0, before - take)
			take = before - int(loop["gold"])
		var row: Dictionary = effect.duplicate(true)
		var multiplier := RewardRules.gold_multiplier(caster, loop["equipment_items"])
		take *= multiplier
		if multiplier != 1: row["gold_multiplier"] = multiplier
		if RewardRules.party_recipient(caster):
			loop["gold"] = RewardRules.pay_party(int(loop["gold"]), take)
		elif take > 0:
			RewardRules.accrue(loop["units"], [{"unit_id": caster["id"], "gold": take}])
			row["carried_by"] = str(caster["id"])
		row.merge({"gold_before": before, "gold_after": loop["gold"], "paid": take}, true)
		applied.append(row)
	strike["gold_effects"] = applied
