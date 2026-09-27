extends RefCounted
## Battle loop combat commit: the one seam player and AI share for a settled offense —
## `resolve_exchange` (counter gate before the primary series, primary then counter
## series through `_resolve_attack_series`／`apply_strike`: per-strike hit／damage／HP,
## stamina and weapon-effect tails on the series' final effective strike, once-per-
## participant experience, one reward commit) and `resolve_skill` (the prepared cast's
## caster／target changes, queue and gold effects, experience, rewards). Receipts are
## immutable presentation input; `last_combat` carries the sequence. Static functions over
## the one loop dictionary; BattlePlayLoop forwards to them and stays the single
## mutable battle-state owner. Numeric kernels live in CoreCombatRules／
## CombatSequenceRules／StaminaRules／WeaponEffectRules／SkillResolutionRules.
## provenance:
##   rules: static-derived docs/evidence_packets/static_reverse/original_ordinary_special.md
##   rules: static-derived docs/evidence_packets/static_reverse/original_extra_attack.md
##   rules: static-derived docs/evidence_packets/static_reverse/original_weapon_effects.md
##   rules: static-derived docs/evidence_packets/static_reverse/original_stamina.md
##   rules: static-derived docs/evidence_packets/static_reverse/original_identity_bar.md
##   rules: runtime-measured docs/evidence_packets/static_reverse/original_identity_bar.md#runtime-measured
##     (any attack reveals its target at confirmation; counters do not)
##   rules: static-derived docs/evidence_packets/static_reverse/original_player_mode.md
##   rules: static-derived docs/evidence_packets/static_reverse/original_damage_random.md
##   rules: remake-invented
##     (one-owner commit ordering and receipt shape — docs/architecture/BATTLE_SYSTEMS.md#corecombatrulesgd)

const BattlePlayLoop = preload("res://game/sim/loop/BattlePlayLoop.gd")
const BattleLoopRewards = preload("res://game/sim/loop/BattleLoopRewards.gd")
const BattleLoopAI = preload("res://game/sim/loop/BattleLoopAI.gd")
const CombatSequence = preload("res://game/sim/CombatSequenceRules.gd")
const WeaponEffects = preload("res://game/sim/WeaponEffectRules.gd")
const CoreTurnQueue = preload("res://game/sim/CoreTurnQueue.gd")
const CoreCombatRules = preload("res://game/sim/CoreCombatRules.gd")
const ExperienceRules = preload("res://game/sim/ExperienceRules.gd")
const StatusEffectRules = preload("res://game/sim/StatusEffectRules.gd")
const StaminaRules = preload("res://game/sim/StaminaRules.gd")
const SkillResolutionRules = preload("res://game/sim/SkillResolutionRules.gd")
const Footprint = preload("res://game/sim/FootprintRules.gd")
const Presence = preload("res://game/sim/BattlePresenceRules.gd")
const BattleOutcome = preload("res://game/sim/BattleOutcome.gd")
const DamageRandomStream = preload("res://game/sim/DamageRandomStream.gd")


## Read-only targeting preview: the footprint the selected skill would settle over if
## cast at `coord` now — SkillTargetRules.cast_footprint with the caster's own cell and the
## player's skill terrain (cast range and effect area over the map words), the same call
## prepare_cast makes with `skill_context`. [] outside skill targeting or the cast range.
static func skill_cast_footprint(loop: Dictionary, coord: Vector2i) -> Array:
	var actor := BattlePlayLoop.unit_ref(loop, str(loop.get("selected_unit_id", "")))
	var id := str(loop.get("selected_skill_id", ""))
	if actor.is_empty() or str(loop.get("interaction", "")) != "attack_select" or loop.get("selected_attack") not in ["magic", "special"] or not loop["skill_book"]["skills"].has(id): return []
	return BattlePlayLoop.SkillTargetRules.cast_footprint(actor["coord"], coord, BattlePlayLoop.skill_fields(loop, id), loop["skill_target_data"], loop["map_size"], BattlePlayLoop.skill_terrain(loop))


static func resolve_exchange(loop: Dictionary, attacker_id: String, defender_id: String, rng: Variant) -> Dictionary:
	if BattleLoopRewards.loot_waiting(loop) or BattleLoopRewards.reward_input_error(loop) != "": return {}
	if BattleOutcome.decided(loop) or not Presence.living(BattlePlayLoop.unit_ref(loop, attacker_id)) or not Presence.living(BattlePlayLoop.unit_ref(loop, defender_id)): return {}
	if StatusEffectRules.paralyzed(BattlePlayLoop.unit_ref(loop, attacker_id)): return {}
	for id in [attacker_id, defender_id]:
		if StaminaRules.input_error(BattlePlayLoop.unit_ref(loop, id), loop["equipment_items"]) != "": return {}
		if ExperienceRules.input_error(loop, BattlePlayLoop.unit_ref(loop, id)) != "": return {}
		if CoreCombatRules.input_error(BattlePlayLoop.unit_ref(loop, id)) != "": return {}
		if not attack_count(loop, BattlePlayLoop.unit_ref(loop, id))["ok"]: return {}
	for pair in [[attacker_id, defender_id], [defender_id, attacker_id]]:
		if not WeaponEffects.prepare(BattlePlayLoop.unit_ref(loop, pair[0]), BattlePlayLoop.unit_ref(loop, pair[1]), loop["skill_book"], loop["equipment_items"], loop["turn_queue"])["ok"]: return {}
	# Target confirmation reveals the defender, whoever attacks: 0x430020 (known byte at
	# 0x43006b) from 0x440279 (AI) as from 0x444388 (player); the counter series pushes no
	# target. The strips of every shot read the set as it stands now — the death write
	# (0x43ef5b) of a counter-killed attacker comes after the cut-in (emulator-measured,
	# original_identity_bar.md).
	BattlePlayLoop.mark_known(loop, defender_id)
	var strip_known: Array = loop["known_unit_ids"].duplicate()
	# The one campaign damage stream (0x42c780): counter gate, damage, hit, critical,
	# weapon effects and experience all draw from it and write it back as they go. An
	# explicit rng is a test injection.
	var source: Variant = rng if rng != null else DamageRandomStream.loop_source(loop)
	var defender := BattlePlayLoop.unit_ref(loop, defender_id)
	var counter_pending := false
	# Native no-attack and paralysis gates precede the defender's counter series.
	if not bool(defender.get("no_attack", false)):
		var profile := CoreCombatRules.combat_profile_from_unit(defender)
		var gate := CoreCombatRules.attack_back_triggered(profile, source)
		counter_pending = bool(gate["triggered"]) and (int(defender.get("status_flags", 0)) & 4) == 0 and Footprint.overlaps(BattlePlayLoop.unit_ref(loop, attacker_id), BattlePlayLoop.attack_cells(loop, defender_id))
	var primary := _resolve_attack_series(loop, attacker_id, defender_id, source)
	primary["counter"] = {}
	if counter_pending and not bool(BattlePlayLoop.unit_ref(loop, defender_id).get("defeated", false)):
		primary["counter"] = _resolve_attack_series(loop, defender_id, attacker_id, source, true)
	# A completed exchange grants once per participant. Neither the primary's
	# level-up nor a changed profile may affect the already committed counter. An undead
	# attacker the counter killed ends the action on its revive (0x407510 from 0x4433eb
	# player／0x43ee9b enemy): neither completion award nor death-sequence payout runs.
	var ended := "undead_action_ended" if _attacker_revived(primary["counter"]) else ""
	BattleLoopRewards.award_experience(loop, primary, ended)
	if not primary["counter"].is_empty(): BattleLoopRewards.award_experience(loop, primary["counter"], ended)
	primary["sequence"] = int(loop.get("last_combat", {}).get("sequence", 0)) + 1
	primary["strip_known_ids"] = strip_known
	BattleLoopRewards.commit_rewards(loop, primary)
	loop["last_combat"] = primary
	return primary


## Whether the counter series left its target — the initiating attacker — revived by the undead
## process (a lethal counter strike with `undead_revived`).
static func _attacker_revived(counter: Dictionary) -> bool:
	if counter.is_empty(): return false
	return CombatSequence.participant_strikes(counter).any(func(strike): return bool(strike.get("undead_revived", false)))


static func attack_count(loop: Dictionary, actor: Dictionary) -> Dictionary:
	return CombatSequence.attack_count(actor, loop["skill_book"]["actors"].get(str(actor.get("actor_id", "")), {}), loop["equipment_items"])


static func _resolve_attack_series(loop: Dictionary, attacker_id: String, defender_id: String, rng: Variant, counter: bool = false) -> Dictionary:
	var count: int = attack_count(loop, BattlePlayLoop.unit_ref(loop, attacker_id))["count"]
	var strikes: Array = []
	for index in range(count):
		if int(BattlePlayLoop.unit_ref(loop, defender_id)["hp"]) <= 0: break
		strikes.append(apply_strike(loop, attacker_id, defender_id, rng, counter, count - index - 1))
	var receipt: Dictionary = strikes[0]
	for index in range(strikes.size()):
		strikes[index]["strike_number"] = index + 1
		strikes[index]["series_size"] = strikes.size()
		strikes[index]["planned_strikes"] = count
	receipt["followups"] = strikes.slice(1)
	return receipt


static func apply_strike(loop: Dictionary, attacker_id: String, defender_id: String, rng: Variant, is_counter: bool = false, remaining: int = 0) -> Dictionary:
	for id in [attacker_id, defender_id]:
		if StaminaRules.input_error(BattlePlayLoop.unit_ref(loop, id), loop["equipment_items"]) != "": return {}
		if ExperienceRules.input_error(loop, BattlePlayLoop.unit_ref(loop, id)) != "": return {}
		if CoreCombatRules.input_error(BattlePlayLoop.unit_ref(loop, id)) != "": return {}
	var weapon := WeaponEffects.prepare(BattlePlayLoop.unit_ref(loop, attacker_id), BattlePlayLoop.unit_ref(loop, defender_id), loop["skill_book"], loop["equipment_items"], loop["turn_queue"])
	if not weapon["ok"]: return {}
	var hp_before := int(BattlePlayLoop.unit_ref(loop, defender_id)["hp"])
	var attacker_before := CoreCombatRules.receipt_vitals(BattlePlayLoop.unit_ref(loop, attacker_id))
	var defender_before := CoreCombatRules.receipt_vitals(BattlePlayLoop.unit_ref(loop, defender_id))
	var strike := CoreCombatRules.resolve_attack(BattlePlayLoop.unit_ref(loop, attacker_id), BattlePlayLoop.unit_ref(loop, defender_id), rng, is_counter)
	# A lethal result ends the series (the damage path raises the death flag at once);
	# an undead defender is revived below, after the death-truncated series is settled.
	var lethal := int(strike["defender_hp_after"]) <= 0
	var series_complete := remaining == 0 or lethal
	strike["attacker_before"] = attacker_before
	strike["defender_before"] = defender_before
	var stamina := {}
	if series_complete and int(strike["damage"]) > 0:
		# 0x44248e passes queued pre-critical damage to stamina. Actual capped
		# HP loss remains separate for contribution/EXP and visible numbers.
		stamina = StaminaRules.prepare(BattlePlayLoop.unit_ref(loop, attacker_id), BattlePlayLoop.unit_ref(loop, defender_id), int(strike["queued_damage"]), int(strike["defender_hp_after"]), loop["equipment_items"])
		if not stamina["ok"]: return {}
	strike["defender_hp_before"] = hp_before
	# Hit-bonus write-back (+0xb0, phase 4 of 0x4423c0 0x44240d..0x44244c) belongs to the player
	# process only: 0x442405 `test byte [mode], 2` jumps past it for the NPC process's exchanges —
	# 0x4414a0 mode 2 (its primary) and 0x4414d3 mode 3 (the counter to it) — while 0x4445cf
	# mode 0／0x444601 mode 1 reach it. The exchange's initiator (this strike's defender on a
	# counter) decides; the hit roll reads +0xb0 either way (0x442591). An NPC-process strike
	# leaves the striker's bonus as it was and its receipt says so.
	var initiator := defender_id if is_counter else attacker_id
	if bool(BattlePlayLoop.unit_ref(loop, initiator).get("player_commandable", false)):
		BattlePlayLoop.unit_ref(loop, attacker_id)["hit_bonus_accum"] = int(strike["hit_bonus_after"])
	else:
		strike["hit_bonus_after"] = int(BattlePlayLoop.unit_ref(loop, attacker_id).get("hit_bonus_accum", 0))
	var hp := int(strike["defender_hp_after"])
	BattlePlayLoop.set_unit_hp(loop, defender_id, hp)
	strike["attacker_id"] = attacker_id
	strike["defender_id"] = defender_id
	var attacker := BattlePlayLoop.unit_ref(loop, attacker_id)
	var basis := ExperienceRules.record(attacker, BattlePlayLoop.unit_ref(loop, defender_id), strike, rng, false, is_counter)
	strike["experience_basis"] = basis
	# Original EXP conversion happens before the once-per-series effects. A last
	# miss does not backfill effects from a successful earlier additional strike.
	if series_complete and int(basis["points"]) > 0 and int(weapon["flags"]) != 0:
		var effects := WeaponEffects.resolve(weapon, rng, int(strike["native_contribution"]), BattlePlayLoop.unit_ref(loop, defender_id))
		loop["turn_queue"] = effects["queue"]
		BattlePlayLoop.unit_ref(loop, defender_id).merge(effects["changes"], true)
		strike["weapon_effects"] = effects["receipt"]
	if not stamina.is_empty():
		BattlePlayLoop.unit_ref(loop, attacker_id)["stamina"] = stamina["attacker"]["after"]
		BattlePlayLoop.unit_ref(loop, defender_id)["stamina"] = stamina["defender"]["after"]
		strike["stamina_gain"] = stamina
	if hp <= 0 and _undead_revives(loop, defender_id):
		# 0x43ee66 (enemy process)／0x4433b6 (player process): a dead-flagged object whose
		# live record carries the undead bit (0x446bb0) clears the flag and sets +0xd8 = 1.
		# The lethal result above (series end, stamina, kill credit) is already settled.
		BattlePlayLoop.set_unit_hp(loop, defender_id, 1)
		strike["defender_hp_after"] = 1
		strike["undead_revived"] = true
	elif hp <= 0:
		# The native helper can touch a zero-HP record. Consume its accepted draws,
		# then release the one actor and clear dead statuses through the normal seam.
		BattlePlayLoop.set_unit_defeated(loop, defender_id, true)
	strike["defender_after"] = CoreCombatRules.receipt_vitals(BattlePlayLoop.unit_ref(loop, defender_id))
	# Native extra scheduling precedes the status/ST tail and caller kill handling.
	# A nonlethal first counter cannot clear the chain before the second counter.
	if series_complete:
		attacker["kill_chain_word"] = basis["kill_word_after"]
		attacker["kill_count"] = int(attacker["kill_count"]) + int(basis["kills_added"])
	return strike


static func resolve_skill(loop: Dictionary, attacker_id: String, defender_id: String, skill_id: String, fields: Dictionary, origin: Vector2i, rng: Variant, center_coord: Variant = null) -> Dictionary:
	if BattleLoopRewards.loot_waiting(loop) or BattleLoopRewards.reward_input_error(loop) != "": return {}
	var attacker := BattlePlayLoop.unit_ref(loop, attacker_id)
	var defender := BattlePlayLoop.unit_ref(loop, defender_id)
	if BattleOutcome.decided(loop) or not Presence.living(attacker) or not Presence.living(defender): return {}
	if ExperienceRules.input_error(loop, attacker) != "": return {}
	if loop["skill_book"]["skills"].get(skill_id, {}).get("channel") == "magic" and BattlePlayLoop.magic_position_error(loop, attacker) != "": return {}
	var stream_before: Variant = loop.get(DamageRandomStream.LOOP_KEY)
	var source: Variant = rng if rng != null else DamageRandomStream.loop_source(loop)
	var result := SkillResolutionRules.resolve_cast(attacker, defender, loop["units"], skill_id, fields, loop["skill_book"], loop["skill_target_data"], loop["equipment_items"], origin, loop["map_size"], source, center_coord, skill_context(loop))
	if not result["ok"]:
		loop[DamageRandomStream.LOOP_KEY] = stream_before
		return {}
	# All qualification, numeric validation and RNG completed without mutations.
	# Player and AI now commit the same resource/HP result at this one seam.
	BattlePlayLoop.set_unit_coord(loop, attacker_id, origin)
	attacker.merge(result["caster_changes"], true)
	var revived: Array = []
	for proposal in result["targets"]:
		BattlePlayLoop.mark_known(loop, str(proposal["id"]))
		BattlePlayLoop.unit_ref(loop, proposal["id"]).merge(proposal["changes"], true)
		if int(BattlePlayLoop.unit_ref(loop, proposal["id"])["hp"]) <= 0:
			if _undead_revives(loop, str(proposal["id"])):
				# The skill proposal marks a zero-HP target defeated; the undead process clears
				# the death flag and sets HP 1 (0x43ee66／0x4433b6), as in the exchange path.
				BattlePlayLoop.unit_ref(loop, proposal["id"])["defeated"] = false
				BattlePlayLoop.set_unit_hp(loop, str(proposal["id"]), 1)
				revived.append(str(proposal["id"]))
			else:
				BattlePlayLoop.set_unit_defeated(loop, proposal["id"], true)
	BattleLoopAI.prune_ai_calls(loop)
	var strike: Dictionary = result["receipt"]
	if not revived.is_empty(): strike["undead_revived"] = revived
	_apply_turn_effects(loop, strike, result.get("turn_effects", []))
	BattleLoopRewards.apply_gold_effects(loop, strike, result.get("gold_effects", []))
	BattleLoopRewards.award_experience(loop, strike)
	strike["sequence"] = int(loop.get("last_combat", {}).get("sequence", 0)) + 1
	BattleLoopRewards.commit_rewards(loop, strike)
	loop["last_combat"] = strike
	return strike


## The undead marker (actSetPlayerUndead → live +0xa0 bit 4, read by 0x446bb0): a unit at
## HP <= 0 survives with 1 HP instead of dying (level 3 漢克斯). Everything else about the
## hit (series truncation, stamina) stays as settled for a lethal result.
static func _undead_revives(loop: Dictionary, unit_id: String) -> bool:
	return bool(BattlePlayLoop.unit_ref(loop, unit_id).get("undead", false))


## Queue-dependent skill gates (天鳴覺醒 ActiveAgain / 獅子吼 CancelActive) read the live queue.
## A player's command cast also carries `range_terrain` (BattlePlayLoop.player_cast_terrain:
## cast range 0x40f8b0 mode -1, effect area 0x4100e0 mode 2／3 over the map words), so it
## settles over the footprint skill_cast_footprint previews; an AI cast stays flat.
static func skill_context(loop: Dictionary) -> Dictionary:
	var context := {"turn_queue": loop.get("turn_queue", {}), "gold": loop.get("gold", 0), "reward_data": loop.get("reward_data", {})}
	var terrain := BattlePlayLoop.player_cast_terrain(loop)
	if not terrain.is_empty(): context["range_terrain"] = terrain
	return context


## 0x4075a0 / 0x407550 proposals from the resolved cast, committed on the one live queue.
static func _apply_turn_effects(loop: Dictionary, strike: Dictionary, effects: Array) -> void:
	if effects.is_empty(): return
	var applied: Array = []
	for effect in effects:
		var outcome: Dictionary
		if effect["kind"] == "reactivate": outcome = CoreTurnQueue.reactivate_consumed(loop["turn_queue"], str(effect["unit_id"]))
		else: outcome = CoreTurnQueue.cancel_pending(loop["turn_queue"], str(effect["unit_id"]))
		if not outcome["ok"]: continue
		loop["turn_queue"] = outcome["queue"]
		var row: Dictionary = effect.duplicate(true)
		row["applied"] = bool(outcome.get("reactivated", outcome.get("cancelled", false)))
		row["slot_index"] = int(outcome["index"])
		applied.append(row)
	strike["turn_effects"] = applied
