extends RefCounted
## Battle loop AI turn driving: `step_ai_turn` resolves the current queue slot (treasure
## hand-off, dead slot, paralysis skip, player hand-back, or one AI action) and
## `_ai_take_turn` performs that action — the read-only preflight `_prepare_ai_turn`
## (identity／strategy／skill validation, source target rows, approach routes, call state,
## skill／physical candidates: all before any RNG), then the decision in native order
## (wait round → self／dying／support priority → fixed-point guard → target lock → state
## 0xa offense → pursuit). Commits go through the shared PlayLoop seams
## (`_resolve_exchange`／`_resolve_skill`／`_resolve_item_use`); `_finish_ai_call` publishes
## call／target retention only with a settled action. Static functions over the one loop
## dictionary; BattlePlayLoop forwards to them and stays the single mutable
## battle-state owner. Composition of the pure kernels (AIDecisionRules, AIPriorityRules,
## AINavigationRules, AICallRules, AISkillPlanning, AISelfPreservation, AISupportPlanning)
## into one turn is a remake policy; whole-AI native equivalence is not claimed.
## provenance:
##   rules: static-derived docs/evidence_packets/static_reverse/original_ai_decisions.md; static-derived docs/evidence_packets/static_reverse/original_ai_priority.md; static-derived docs/evidence_packets/static_reverse/original_ai_navigation.md; static-derived docs/evidence_packets/static_reverse/original_ai_calls.md; static-derived docs/evidence_packets/static_reverse/original_ai_support.md; static-derived docs/evidence_packets/static_reverse/original_fixpos_fly_prev_insert.md; provisional (target／route composition, stable-id call cleanup, dying-path category walk over the chosen foe, not the 0x43f79b loop; level-37 gems wait — docs/architecture/BATTLE_SYSTEMS.md#ai); remake-invented (paralysis_skip and candidate_filters receipts); static-derived docs/evidence_packets/static_reverse/original_level37_tokens.md; static-derived docs/evidence_packets/static_reverse/original_enemy_turn.md
##   layout: n/a
##   strings: n/a
##   timing: n/a
##   audio: n/a

const Loop = preload("res://game/battle/scene/BattlePlayLoop.gd")
const Rewards = preload("res://game/battle/scene/BattleLoopRewards.gd")
const ScriptFlow = preload("res://game/battle/scene/BattleLoopScript.gd")
const Combat = preload("res://game/battle/scene/BattleLoopCombat.gd")
const Inventory = preload("res://game/battle/scene/BattleLoopInventory.gd")
const CoreTurnQueue = preload("res://game/sim/CoreTurnQueue.gd")
const CoreCombatRules = preload("res://game/sim/CoreCombatRules.gd")
const ExperienceRules = preload("res://game/sim/ExperienceRules.gd")
const BattleScenarioRuleAdapter = preload("res://game/sim/BattleScenarioRuleAdapter.gd")
const ActionEntryRules = preload("res://game/sim/ActionEntryRules.gd")
const ActorRoleRules = preload("res://game/sim/ActorRoleRules.gd")
const StatusEffectRules = preload("res://game/sim/StatusEffectRules.gd")
const StaminaRules = preload("res://game/sim/StaminaRules.gd")
const ItemUseRules = preload("res://game/sim/ItemUseRules.gd")
const SkillTargetRules = preload("res://game/sim/SkillTargetRules.gd")
const SkillResolutionRules = preload("res://game/sim/SkillResolutionRules.gd")
const SkillResourceRules = preload("res://game/sim/SkillResourceRules.gd")
const Footprint = preload("res://game/sim/FootprintRules.gd")
const Presence = preload("res://game/sim/BattlePresenceRules.gd")
const Treasure = preload("res://game/sim/TreasureRules.gd")
const AIDecisionRules = preload("res://game/sim/AIDecisionRules.gd")
const AICallRules = preload("res://game/sim/AICallRules.gd")
const AIPriorityRules = preload("res://game/sim/AIPriorityRules.gd")
const AISkillPlanning = preload("res://game/sim/AISkillPlanning.gd")
const AISelfPreservation = preload("res://game/sim/AISelfPreservation.gd")
const AISupportPlanning = preload("res://game/sim/AISupportPlanning.gd")
const AINavigationRules = preload("res://game/sim/AINavigationRules.gd")
const GlobalRandom = preload("res://game/sim/GlobalRandomStream.gd")
const BattleOutcome = preload("res://game/sim/BattleOutcome.gd")

## Diagnostic switch for A/B timing: `HSL_AI_PREP_CACHE=0` recomputes every row's
## validation instead of reading `_row_validation` (default on; results are identical).
const ROW_MEMO_ENV := "HSL_AI_PREP_CACHE"
## Memo of `_ai_target_rows`' per-unit input validation (stamina／experience／combat), a
## pure function of one unit and the shared `equipment_items` block. Every AI actor
## validates every living unit each round, so a unit is re-validated only once its bytes
## change. Lives outside the loop dictionary (no state key, never copied／saved／compared);
## `units` maps unit id → {"bytes": var_to_bytes(unit), "error": String} and is dropped
## whenever the `equipment_items` reference differs (another battle or a restored save).
static var _row_validation := {"equipment_items": null, "units": {}}
static var _row_memo_enabled: Variant = null


static func step_ai_turn(loop: Dictionary, rng: Variant = null) -> Dictionary:
	var next := Loop.copy(loop)
	if BattleOutcome.decided(loop) or not loop.get("scenario_ok", false): return next
	if Rewards.loot_waiting(loop): return next
	if str(next.get("interaction", "")) != "ai_resolving":
		return next
	var reward_error := Rewards._reward_input_error(loop)
	if reward_error != "":
		next["scenario_ok"] = false
		next["scenario_error"] = reward_error
		next["interaction"] = "scenario_error"
		return next
	if Treasure.awaiting_handoff(next):
		next["treasures"]["handoff"] = {}
		return Loop._advance_current_actor(next)
	var cur: Dictionary = CoreTurnQueue.current(next.get("turn_queue", {}))
	var actor_id := str(cur.get("id", ""))
	if actor_id == "":
		next["interaction"] = "idle"
		return next
	var actor: Dictionary = Loop._unit(next, actor_id)
	if not Presence.living(actor):
		return Loop._advance_current_actor(next)
	var entry := ActionEntryRules.prepare(actor)
	if not entry["ok"]:
		next.merge({"scenario_ok": false, "interaction": "scenario_error", "scenario_error": entry["reason"]}, true)
		return next
	if entry["skip"]:
		var error := Loop._skill_input_error(next, actor)
		if error != "":
			next.merge({"scenario_ok": false, "interaction": "scenario_error", "scenario_error": error}, true)
			return next
		var action := {"kind": "paralysis_skip", "actor_id": actor_id, "remaining_before": entry["remaining"],
			"from": actor["coord"], "to": actor["coord"], "path": [], "source": "fresh_action_paralysis_gate"}
		next["last_ai_action"] = action
		next["last_ai_actions"].append(action)
		next["selected_unit_id"] = ""
		next["command_menu"] = {"commands": []}
		next = ScriptFlow._resolve_outcome(next)
		if BattleOutcome.decided(next):
			next["interaction"] = "battle_result"
			return next
		return next if not Loop._is_current_actor(next, actor_id) else Loop._advance_current_actor(next, true)
	if bool(actor.get("player_commandable", false)):
		return Loop._return_to_player(next, actor_id)
	var resource_error := Loop._skill_input_error(next, actor)
	if resource_error != "":
		next["scenario_ok"] = false
		next["scenario_error"] = resource_error
		next["interaction"] = "scenario_error"
		return next
	# `next` is still `loop`'s state (every check above only reads it): the turn may work
	# on it in place, and a rejected step copies `loop` instead.
	var step: Dictionary = _ai_take_owned_turn(next, loop, actor_id, rng, true)
	next = step.get("loop", next)
	if not bool(next.get("scenario_ok", false)):
		return next
	var action: Dictionary = step.get("action", {})
	next["last_ai_action"] = action
	var actions: Array = next.get("last_ai_actions", [])
	actions.append(action)
	next["last_ai_actions"] = actions
	# AI commits through the same exchange/skill resolvers, but does not pass the
	# player's attack_target wrapper. Its new receipt becomes the attack this action's
	# completion scan reads (the 0x4c1ce8 attacker global); items/waits leave none.
	if int(next.get("last_combat", {}).get("sequence", 0)) > int(loop.get("last_combat", {}).get("sequence", 0)):
		next["last_attack"] = next["last_combat"].duplicate(true)
		next["action_attacker_id"] = actor_id
	next = ScriptFlow._resolve_outcome(next)
	if BattleOutcome.decided(next):
		next["interaction"] = "battle_result"
		return next
	return next if not Loop._is_current_actor(next, actor_id) else Loop._advance_current_actor(next)


static func _ai_take_turn(loop: Dictionary, actor_id: String, rng: Variant = null) -> Dictionary:
	return _ai_take_owned_turn(Loop.copy(loop), loop, actor_id, rng)


## `_ai_take_turn` on `next`, a loop the caller owns and lets the turn write in place;
## `loop` holds the state `next` had on entry and is what a rejected step copies.
## `skill_inputs_checked`: the caller has just found `Loop._skill_input_error` empty for
## this actor on this state (`step_ai_turn`), so the preflight does not run it again.
static func _ai_take_owned_turn(next: Dictionary, loop: Dictionary, actor_id: String, rng: Variant = null, skill_inputs_checked: bool = false) -> Dictionary:
	var actor: Dictionary = Loop._unit(next, actor_id)
	if _idle_without_strategy(next, actor):
		return {"loop": next, "action": {"actor_id": actor_id, "kind": "wait", "wait_reason": "no_selectable_target",
			"from": actor["coord"], "to": actor["coord"], "path": [], "source": "undeclared_ai_empty_target_scan"}}
	var prepared := _prepare_ai_turn(next, actor_id, skill_inputs_checked)
	if not prepared["ok"]:
		next["scenario_ok"] = false
		next["scenario_error"] = prepared["reason"]
		next["interaction"] = "scenario_error"
		return {"loop": next, "action": {}}
	# No explicit source: the decision draws from the loop's global stream (0x458c80 on
	# 0x4795d4／0x4795d8), bound to `next`, the dictionary every phase below commits into.
	var source: Variant = rng if rng != null else GlobalRandom.loop_source(next)
	var turn := _ai_open_decision(next, actor_id, actor, prepared, source)
	# Native decision order: wait round → self／dying／support priority (0x440db1) → fixed-
	# point guard (0x440ef1) → target lock (0x441002) → state 0xa offense (0x43fd60);
	# pursuit is the fallthrough.
	# A phase returns the finished step, or {} to hand the turn to the next phase.
	for phase in [_ai_wait_round, _ai_priority_action, _ai_fixed_guard, _ai_lock_check, _ai_no_target_action, _ai_offense]:
		var step: Dictionary = phase.call(loop, next, turn)
		if not step.is_empty(): return step
	return _ai_pursuit(next, turn)


## A unit whose PLAYERS row declares no AI strategy (the level-37 gems 067: no find_type,
## find_range, ai_call_range or ai_fixed) and whose side shares a bit with every living unit
## — pmMagicAttack (pmALL), or pmPlayerEnemy with no pmNPC on the field — gives the target
## scan 0x40bb80 nothing to pick (own & other & 0x870000 != 0 for all) and has no attack of
## its own; it waits instead of failing on the missing strategy (remake reading of the empty
## native scan, provisional). A PLAYERS no_attack row without a strategy (level 18's door 100,
## the level-12／26 hull pieces 101) waits too, hostile units or not: it has no attack to plan.
## With any hostile unit alive any other missing strategy still fails.
static func _idle_without_strategy(loop: Dictionary, actor: Dictionary) -> bool:
	var declared: Dictionary = loop.get("ai_profiles", {}).get("actors", {}).get(str(actor.get("actor_id", "")), {})
	if declared.is_empty() or (declared.get("missing_required", []) as Array).is_empty():
		return false
	if bool(actor.get("no_attack", false)):
		return true
	for unit in loop["units"]:
		if str(unit.get("id", "")) != str(actor.get("id", "")) and Presence.living(unit) and ActorRoleRules.hostile(actor, unit):
			return false
	return true


## Acquire the navigation target, adopt a pending call and open the decision／action
## receipts every later phase writes into. `turn` is the working state of one AI turn:
## actor_id／actor／prepared／source (read-only), selected／pending／priority (set once),
## adoption／action (replaced by phases), decision (mutated in place).
static func _ai_open_decision(next: Dictionary, actor_id: String, actor: Dictionary, prepared: Dictionary, source: Variant) -> Dictionary:
	var selected := AINavigationRules.acquire(actor, next["units"], prepared, source)
	prepared["navigation_selection"] = selected
	var pending: Dictionary = prepared["call"]
	var adoption := AICallRules.adopt(int(selected["index"]), pending["index"], pending["target_id"] != "", pending["eligible"])
	var decision := {"target_selection": selected, "source_actor": actor["actor_id"], "candidate_filters": prepared["candidate_filters"],
		"call_target": {"pending_target_id": pending["target_id"], "adoption": adoption,
			"recipient_ids": pending["recipient_ids"] if adoption["broadcast"] else [],
			"eligibility_policy": "current living enemy, source SID exclusion; stable unit IDs, not reusable native object slots"},
		"near_range_binding": "live move_point; native source+0x130 copied to refreshed+0x12c before equipment",
		"composition_evidence": "provisional", "position_policy": "magic maximizes useful coverage then distance from threat; physical uses legal approach lanes",
		"reachability_policy": "none in the scans (0x40bb80 reads positions); the ordinary category switches to the first registry slot from the held one with an attack station (0x40d8b0)",
		"exclusion_policy": "exclude forbidden SID before scoring; original score/restore quirk remains in pure kernel"}
	var action := {"actor_id": actor_id, "kind": "wait", "ai_decision": decision}
	return {"actor_id": actor_id, "actor": actor, "prepared": prepared, "source": source,
		"selected": selected, "pending": pending, "adoption": adoption, "decision": decision, "action": action, "priority": {}}


## Source wait entry: a healthy waiting guard spends the turn without a call adoption.
static func _ai_wait_round(_loop: Dictionary, next: Dictionary, turn: Dictionary) -> Dictionary:
	if not turn["selected"]["wait"]: return {}
	var action: Dictionary = turn["action"]
	action["wait_reason"] = "wait_round"
	turn["adoption"] = AICallRules.adopt(-1, -1, false, false)
	return _finish_ai_call(next, turn["actor_id"], action, turn["prepared"], turn["adoption"])


## Self-HP item, self／ally spell and ally item priorities commit here; "dying" and
## "ordinary" fall through to the target phases with the selected priority recorded.
static func _ai_priority_action(loop: Dictionary, next: Dictionary, turn: Dictionary) -> Dictionary:
	var actor_id: String = turn["actor_id"]
	var actor: Dictionary = turn["actor"]
	var prepared: Dictionary = turn["prepared"]
	var decision: Dictionary = turn["decision"]
	var action: Dictionary = turn["action"]
	var priority := _select_ai_priority(next, actor_id, prepared, turn["source"])
	decision["priority"] = priority
	turn["priority"] = priority
	if priority["kind"] == "use_item":
		var slot := int(priority["item_slot"])
		var effect := Inventory._resolve_item_use(next, actor_id, actor_id, str(int(actor["inventory"][slot])), slot)
		if effect.is_empty(): return _ai_rejected_step(loop, "prepared_ai_item_changed")
		action.merge({"kind": "use_item", "target_id": actor_id, "item_use": effect}, true)
		return _finish_ai_call(next, actor_id, action, prepared, turn["adoption"])
	if priority["kind"] in ["self_skill", "ally_skill"]:
		action = _execute_ai_skill_choice(next, actor_id, priority["intent"], turn["source"])
		if action.is_empty(): return _ai_rejected_step(loop, "prepared_ai_support_changed")
		action["ai_decision"] = decision
		action["ai_skill_decision"] = priority["self_skill_decision"] if priority["kind"] == "self_skill" else priority["support_decision"]
		return _finish_ai_call(next, actor_id, action, prepared, turn["adoption"])
	if priority["kind"] == "ally_item":
		action = _execute_ai_support_item(next,actor_id,priority["intent"])
		if action.is_empty(): return _ai_rejected_step(loop,"prepared_ai_support_item_changed")
		action["ai_decision"] = decision
		action["ai_support_decision"] = priority["support_decision"]
		return _finish_ai_call(next,actor_id,action,prepared,turn["adoption"])
	return {}


## Target lock (source ai_lock, 0x441002..0x44102e): once every priority check failed, the
## dispatcher's last roll above ai_lock re-runs the target scan 0x40bb80 and a found object
## replaces the held one — a target acquired this turn as much as a retained one (emulator-
## measured battle 051 r1 seed 1: 021_1 acquires Leonard, rolls 83 > 39 and holds 023_1).
## The write is +0x88 alone: the call broadcast stays the acquisition's (0x43f6dc／0x43f5ed).
## With nothing held the native rescan can only repeat the acquisition scan that just came
## back empty, so the remake skips it and its roll (draw structure, not replayed here).
## Never finishes the turn by itself.
static func _ai_lock_check(_loop: Dictionary, _next: Dictionary, turn: Dictionary) -> Dictionary:
	var priority: Dictionary = turn["priority"]
	if priority["kind"] != "ordinary" or int(turn["adoption"]["index"]) < 0: return {}
	var prepared: Dictionary = turn["prepared"]
	var decision: Dictionary = turn["decision"]
	var draws: Array = []
	var roll := int(priority.get("lock_roll", -1))
	if roll < 1: roll = AIDecisionRules._draw(99, turn["source"], draws) + 1
	decision["lock_check"] = {"roll": roll, "threshold": prepared["profile"]["ai_lock"], "draws": draws}
	if roll > int(prepared["profile"]["ai_lock"]):
		var replacement := AIDecisionRules.select_registered_target(prepared["rows"], prepared["registry"], prepared["owner_index"], prepared["profile"], int(turn["actor"]["move_point"]), turn["source"])
		decision["lock_check"]["replacement"] = replacement
		if int(replacement["index"]) >= 0:
			turn["adoption"] = _held_target_write(turn["adoption"], int(replacement["index"]), false)
			decision["call_target"]["adoption"] = turn["adoption"]
	return {}


## A later write of the held target +0x88 in the same turn: the lock (0x44102e) writes it
## alone, the attack-station switch (0x440069) also broadcasts it (0x40bee0, ai_call_range).
## The call recipients hear the last broadcast target; a consumed call stays consumed.
static func _held_target_write(adoption: Dictionary, index: int, broadcast: bool) -> Dictionary:
	var next := adoption.duplicate()
	if not next.has("broadcast_index"): next["broadcast_index"] = int(adoption["index"]) if adoption["broadcast"] else -1
	next["index"] = index
	if broadcast:
		next["broadcast"] = true
		next["broadcast_index"] = index
	return next


## Fixed-point guard (0x440ef1..0x440fe6), once every priority check failed and before the
## lock: with ai_fixed set, a unit without a weapon (0x409090 zero) or holding nothing
## clears +0x88 and returns home (0x440fd3: +0x8c = 0x50000, next frame 0x43fbd6) — the
## lock 0x441002 is not reached. Standing on an EVEF fixed point clears flag 0x4000 and
## ai_fixed (0x43fbf1..0x43fc0e), so the unit is free from its next turn. An armed unit
## keeps a held target inside the home circle: the remake's guard filter has already
## dropped the rest (the native home-position rescan 0x440f56..0x440fd1 is not replayed).
static func _ai_fixed_guard(_loop: Dictionary, next: Dictionary, turn: Dictionary) -> Dictionary:
	var prepared: Dictionary = turn["prepared"]
	if turn["priority"]["kind"] != "ordinary" or int(prepared["profile"]["ai_fixed"]) == 0: return {}
	if int(turn["adoption"]["index"]) >= 0 and not bool(prepared["candidate_filters"]["unarmed"]): return {}
	var actor_id: String = turn["actor_id"]
	var actor: Dictionary = turn["actor"]
	var action: Dictionary = turn["action"]
	turn["adoption"] = _held_target_write(turn["adoption"], -1, false)
	turn["decision"]["call_target"]["adoption"] = turn["adoption"]
	action["wait_reason"] = "no_valid_action"
	if actor["coord"] == actor["ai_home_coord"]:
		if bool(actor.get("ai_fixed_point_pending", false)):
			Loop._unit(next, actor_id)["ai_fixed_point_pending"] = false
			# The release writes the live ai_fixed to 0, whichever word last set it.
			Loop._unit(next, actor_id).erase("ai_fixed_radius")
			action["wait_reason"] = "fixed_point_reached"
	else:
		var approach := AINavigationRules.approach_home(next, actor, prepared["envelope"], turn["source"])
		turn["decision"]["home_approach"] = {"goal": approach["goal"], "route_cost": approach["route_cost"], "candidates": approach["candidates"], "refinements": approach["refinements"], "draws": approach["draws"], "reason": approach["reason"], "source": "0x43fbd6 / 0x4111a0 / 0x411080 / 0x413740"}
		if approach["path"].size() > 1:
			action.merge({"to": approach["to"], "path": approach["path"], "cost": approach["cost"], "goal": approach["goal"], "route_cost": approach["route_cost"]}, true)
			action.merge({"kind": "move", "purpose": "return_home"}, true)
			Loop._set_unit_coord(next, actor_id, approach["to"])
	return _finish_ai_call(next, actor_id, action, prepared, turn["adoption"])


## Without a held target the turn ends (state 0xa entry 0x43fd60: +0x88 zero → 0x441eb8).
## With a target, records `target_index`.
static func _ai_no_target_action(_loop: Dictionary, next: Dictionary, turn: Dictionary) -> Dictionary:
	var priority: Dictionary = turn["priority"]
	var target_index := int(priority["index"]) if priority["kind"] == "dying" else int(turn["adoption"]["index"])
	if target_index >= 0:
		turn["target_index"] = target_index
		return {}
	turn["action"]["wait_reason"] = "no_valid_action"
	return _finish_ai_call(next, turn["actor_id"], turn["action"], turn["prepared"], turn["adoption"])


## Offense against the held target. The dying priority keeps the remake's category walk
## over its chosen foe. State 0xa (0x43fd60..0x4400a2) draws the category once (0x40c570
## at 0x43fe0c) and has no category cycle. The categories on offer are the actor's own
## (0x40dd60／0x40e1f0: an affordable MAGIC／SPECIAL row in bucket 3 or 4, 0x40c620), not
## the held target's: the cast itself (0x40d340／0x40df70 with flag 0, AISkillPlanning.
## choose_any) takes the best coverage anywhere in reach. A special that finds no cast falls
## to the ordinary category (0x440041); a magic one first rolls the side walk (0x43ff1f..
## 0x44003c, _ai_side_walk). The ordinary category needs a weapon (0x409090, else the turn
## ends at 0x441eb8) and runs the station switch 0x40d8b0 from the held slot; the object
## it finds becomes the held target (0x440069), is broadcast to the call range (0x40bee0)
## and state 0xb sub 0 strikes it. No station anywhere hands the turn to the pursuit.
static func _ai_offense(loop: Dictionary, next: Dictionary, turn: Dictionary) -> Dictionary:
	var actor: Dictionary = turn["actor"]
	var prepared: Dictionary = turn["prepared"]
	var priority: Dictionary = turn["priority"]
	var decision: Dictionary = turn["decision"]
	var source: Variant = turn["source"]
	var target: Dictionary = next["units"][int(turn["target_index"])]
	var choice: Dictionary = prepared["physical"].get(target["id"], {})
	var skills: Dictionary = prepared["offensive_skills"] if priority["kind"] == "dying" else prepared["skills"]
	var magic: Dictionary = skills["magic"].get(target["id"], {})
	var special: Dictionary = skills["special"].get(target["id"], {})
	if priority["kind"] == "dying":
		if choice.is_empty() and magic.is_empty() and special.is_empty(): return {}
		var dying_selection := AIDecisionRules.select_action(prepared["profile"], int(actor["status_flags"]), not magic.is_empty(), not special.is_empty(), source)
		decision["action_selection"] = dying_selection
		for kind in dying_selection["order"]:
			if kind == 0 and not choice.is_empty(): return _ai_station_attack(next, turn, target, choice)
			var step := _ai_skill_attempt(loop, next, turn, magic if kind == 1 else special if kind == 2 else {})
			if not step.is_empty(): return step
		return {}
	var any_magic: Dictionary = prepared["any_skills"]["magic"]
	var any_special: Dictionary = prepared["any_skills"]["special"]
	var action_selection := AIDecisionRules.select_action(prepared["profile"], int(actor["status_flags"]), bool(any_magic["available"]), bool(any_special["available"]), source)
	action_selection["source"] = "0x40c570(actor, 0x40dd60(), 0x40e1f0()) at 0x43fe0c; no category cycle in state 0xa (0x43fe14..0x43ff1f fall to 0x440041)"
	decision["action_selection"] = action_selection
	var kind := int(action_selection["kind"])
	if kind != 0:
		var step := _ai_skill_attempt(loop, next, turn, any_magic if kind == 1 else any_special, str(target["id"]))
		if not step.is_empty(): return step
	if bool(prepared["candidate_filters"]["unarmed"]): return {}
	if kind == 1:
		var side := _ai_side_walk(next, turn)
		if not side.is_empty(): return side
	var switched := _ai_station_switch(prepared, int(turn["target_index"]), next["units"])
	decision["station_switch"] = {"held_id": str(target["id"]), "index": switched, "target_id": str(next["units"][switched]["id"]) if switched >= 0 else "",
		"source": "0x440052..0x440085 / 0x40d8b0"}
	if switched < 0: return {}
	turn["adoption"] = _held_target_write(turn["adoption"], switched, true)
	decision["call_target"]["adoption"] = turn["adoption"]
	turn["target_index"] = switched
	var held: Dictionary = next["units"][switched]
	return _ai_station_attack(next, turn, held, prepared["physical"][held["id"]])


## The magic category's side walk (0x43ff1f..0x44003c): after a magic cast found nothing an
## armed actor rolls rand(100) (0x43ff32); at 10 or below it runs the station switch from the
## held slot (0x40d8b0, +0x88 left as it is), takes that object's first sorted station
## (0x413390 → 0x4c6560), steps to the stoppable cell nearest it within a budget-1 flood
## (0x40f440(actor, 1, mode); 0x413900 with the actor's side word, its own cell skipped;
## 0x410a50) and ends in state 0xb sub 1 → sub 7, which
## strikes the held target [0x4c1cec] only if it is in weapon range from there
## (0x441311..0x441369, else 0x441eb8). Any step that finds nothing leaves the ordinary
## category (0x440041) to run as usual. {} then.
static func _ai_side_walk(next: Dictionary, turn: Dictionary) -> Dictionary:
	var prepared: Dictionary = turn["prepared"]
	var decision: Dictionary = turn["decision"]
	var actor: Dictionary = turn["actor"]
	var actor_id: String = turn["actor_id"]
	var origin: Vector2i = actor["coord"]
	var roll := AIDecisionRules.side_walk_roll(turn["source"])
	var receipt := {"roll": roll["roll"], "taken": roll["taken"], "draws": roll["draws"], "source": "0x43ff1f..0x44003c"}
	decision["side_walk"] = receipt
	if not bool(roll["taken"]): return {}
	var switched := _ai_station_switch(prepared, int(turn["target_index"]), next["units"])
	receipt["switch_index"] = switched
	if switched < 0: return {}
	var sorted := AINavigationRules.station_order(prepared["physical"][next["units"][switched]["id"]], turn["source"])
	var first: Vector2i = sorted["order"][0]
	receipt.merge({"switch_id": str(next["units"][switched]["id"]), "station": first, "order_draws": sorted["draws"]}, true)
	var routes: Dictionary = prepared["envelope"]["reachable_by_coord"]
	# 0x43ff5e..0x43ff68: the nearest-cell search reads a fresh 0x40f440(actor, 1, 0x40bab0 mode) flood,
	# budget 1 — one step toward the station, not the move envelope (emulator-measured 17 s2: 0x40f440(035_1,
	# 1, 3) → 0x413900 picks (28,14) for station (30,14), one coin). The move flood (0x440020) only walks it.
	var step := AINavigationRules.Grid.movement_reachability_envelope(actor, next["units"], AINavigationRules.TerrainEdits.tiles(next), next["map_size"], 1)
	if not step["ok"]: return {}
	var near_draws: Array = []
	var mask := AINavigationRules.blocker_mask(AINavigationRules.side_word(actor))
	var pick := AINavigationRules._nearest_stoppable(step["reachable_by_coord"].keys(), first, origin, turn["source"], near_draws, AINavigationRules.neighbour_words(next), mask, next["map_size"])
	receipt["near_draws"] = near_draws
	if pick.is_empty() or not routes.has(pick["cell"]): return {}
	var destination: Vector2i = pick["cell"]
	receipt["to"] = destination
	var target: Dictionary = next["units"][int(turn["target_index"])]
	Loop._set_unit_coord(next, actor_id, destination)
	var terrain: Dictionary = prepared.get("weapon_terrain", {})
	var in_range := false
	if not terrain.is_empty(): in_range = AINavigationRules.target_in_range(next, Loop._unit(next, actor_id), target, terrain)
	else:
		for offset in Loop.weapon_pattern(next, actor)["offsets"]:
			for point in Footprint.cells(target):
				if point - Vector2i(int(offset[0]), int(offset[1])) == destination: in_range = true
	receipt["arrival_in_range"] = in_range
	if not in_range:
		var action: Dictionary = turn["action"]
		action["wait_reason"] = "side_walk_out_of_range"
		action.merge({"to": destination, "path": routes[destination]["path"], "cost": routes[destination]["cost"],
			"kind": "move", "toward": str(target["id"]), "purpose": "side_walk"}, true)
		return _finish_ai_call(next, actor_id, action, prepared, turn["adoption"])
	# Settlement draws from the loop's damage stream (0x42c780), not the decision source.
	var strike := Combat._resolve_exchange(next, actor_id, target["id"], null)
	strike.merge({"actor_id": actor_id, "target_id": target["id"], "to": destination, "path": routes[destination]["path"],
		"kind": "move_then_attack", "purpose": "side_walk", "ai_decision": decision}, true)
	return _finish_ai_call(next, actor_id, strike, prepared, turn["adoption"])


## 0x40d8b0 over the object array: from the held object's slot upward, wrapping past the
## last slot to the first and stopping back at the start, the first object that is hostile
## (0x40ba20 sides disjoint), not the find_no_id exclusion (0x44fa80) and has an attack
## station — the move flood (0x40f440) ∩ the cells its weapon reaches it from (0x40fa80,
## or the nine centres of a large object through 0x40f8b0), counted by 0x413390. No find
## range, guard radius or reachability of the object itself is read. -1 when no object has
## a station. `physical` holds exactly the hostile, non-excluded objects with a station.
static func _ai_station_switch(prepared: Dictionary, held_index: int, units: Array) -> int:
	var physical: Dictionary = prepared["physical"]
	var layout: Array = prepared.get("registry", [])
	if layout.is_empty(): layout = range(units.size())
	var start := layout.find(held_index)
	if start < 0: return held_index if physical.has(units[held_index]["id"]) else -1
	for step in range(layout.size()):
		var index := int(layout[(start + step) % layout.size()])
		if index < 0 or index == int(prepared["owner_index"]): continue
		if physical.has(units[index]["id"]): return index
	return -1


## State 0xb sub 0 on a target with stations: the station order (0x413390), the in-place
## or reposition roll, and the strike through the shared exchange seam. After the walk the
## held target is tested again from the station with the actor's own weapon coverage
## (0x441311..0x441369); a miss (the range flood is not symmetric, walls cut one way)
## ends the turn on the station without a strike (0x441eb8).
static func _ai_station_attack(next: Dictionary, turn: Dictionary, target: Dictionary, choice: Dictionary) -> Dictionary:
	var actor_id: String = turn["actor_id"]
	var actor: Dictionary = turn["actor"]
	var decision: Dictionary = turn["decision"]
	var origin: Vector2i = actor["coord"]
	var routes: Dictionary = turn["prepared"]["envelope"]["reachable_by_coord"]
	var foes_adjacent := AINavigationRules.adjacent_blockers(origin, AINavigationRules.search_mask(actor), AINavigationRules.neighbour_words(next), next["map_size"])
	var station := AINavigationRules.attack_station(choice, origin, foes_adjacent, turn["source"])
	decision["attack_station"] = {"to": station["to"], "reason": station["reason"], "order": station["order"], "draws": station["draws"], "foes_adjacent": foes_adjacent, "roll": station["roll"], "source": "0x40d8b0 / 0x413390 / 0x440b2c state 0xb sub 0"}
	var destination: Vector2i = station["to"]
	Loop._set_unit_coord(next, actor_id, destination)
	var terrain: Dictionary = turn["prepared"].get("weapon_terrain", {})
	if not terrain.is_empty() and not AINavigationRules.target_in_range(next, Loop._unit(next, actor_id), target, terrain):
		decision["attack_station"]["arrival_in_range"] = false
		var missed: Dictionary = turn["action"]
		missed["wait_reason"] = "station_out_of_range"
		if destination != origin:
			missed.merge({"to": destination, "path": routes[destination]["path"], "cost": routes[destination]["cost"],
				"kind": "move", "toward": str(target["id"]), "purpose": "attack_station"}, true)
		return _finish_ai_call(next, actor_id, missed, turn["prepared"], turn["adoption"])
	# Settlement draws from the loop's damage stream (0x42c780), not the decision source.
	var action := Combat._resolve_exchange(next, actor_id, target["id"], null)
	action.merge({"actor_id": actor_id, "target_id": target["id"], "to": destination,
		"path": [] if destination == origin else routes[destination]["path"],
		"kind": "attack" if destination == origin else "move_then_attack", "ai_decision": decision}, true)
	return _finish_ai_call(next, actor_id, action, turn["prepared"], turn["adoption"])


## One skill channel's cast (0x40d340／0x40df70 through the plan's bucket walk); {} when the
## plan is missing or its walk accepts nothing. With `held_id` the plan is the channel's
## held-target-free plan (state 0xa, flag 0: AISkillPlanning.choose_any); without it the
## per-target plan of the dying priority (AISkillPlanning.choose).
static func _ai_skill_attempt(loop: Dictionary, next: Dictionary, turn: Dictionary, skill_choice: Dictionary, held_id: String = "") -> Dictionary:
	if skill_choice.is_empty(): return {}
	var decision: Dictionary = turn["decision"]
	var selected_skill := AISkillPlanning.choose_any(skill_choice, held_id, turn["source"]) if held_id != "" else AISkillPlanning.choose(skill_choice, turn["source"])
	if not decision.has("skill_attempts"): decision["skill_attempts"] = []
	decision["skill_attempts"].append(selected_skill["decision"])
	if selected_skill["intent"].is_empty(): return {}
	var action := _execute_ai_skill_choice(next, turn["actor_id"], selected_skill["intent"], turn["source"])
	if action.is_empty(): return _ai_rejected_step(loop, "prepared_ai_skill_changed")
	action["ai_skill_decision"] = selected_skill["decision"]
	action["ai_decision"] = decision
	return _finish_ai_call(next, turn["actor_id"], action, turn["prepared"], turn["adoption"])


## Fallthrough: no attack this turn (0x40fb20 zero), so state 0xb sub 0 walks toward the
## held target through the refinement walk 0x4111a0 (0x440d5c..0x440d84), or waits. That
## walk measures toward the target's cell and needs no full route to it (static-derived
## 0x4111a0／0x413740: floods from the actor, nearest stoppable cell by distance), so an
## armed unit walks toward an enclosed target too. A unit without an ordinary attack (only
## cast positions to reach) keeps the remake's prefix of the route to its nearest goal;
## unarmed (0x409090 zero) ends the turn at 0x441eb8.
static func _ai_pursuit(next: Dictionary, turn: Dictionary) -> Dictionary:
	var actor_id: String = turn["actor_id"]
	var target: Dictionary = next["units"][int(turn["target_index"])]
	var action: Dictionary = turn["action"]
	var route: Dictionary = turn["prepared"]["approaches"].get(target["id"], {})
	var armed: bool = not bool(turn["prepared"]["candidate_filters"]["unarmed"])
	action["wait_reason"] = "no_accepted_action" if armed else "no_valid_action"
	if not route.is_empty() and bool(turn["actor"].get("no_attack", false)):
		var advance := AINavigationRules.advance_path(turn["actor"], route)
		if advance["path"].size() > 1:
			Loop._set_unit_coord(next, actor_id, advance["to"])
			action.merge(advance, true)
			action.merge({"kind": "move", "toward": str(target["id"]), "purpose": "pursuit"}, true)
	elif armed:
		var approach := AINavigationRules.approach_point(next, turn["actor"], turn["prepared"]["envelope"], target["coord"], turn["source"])
		turn["decision"]["pursuit_approach"] = {"goal": approach["goal"], "refinements": approach["refinements"], "draws": approach["draws"], "reason": approach["reason"], "source": "0x440d5c / 0x4111a0 / 0x411080 / 0x413740"}
		if approach["path"].size() > 1:
			Loop._set_unit_coord(next, actor_id, approach["to"])
			action.merge({"to": approach["to"], "path": approach["path"], "cost": approach["cost"], "goal": approach["goal"], "route_cost": approach["route_cost"]}, true)
			action.merge({"kind": "move", "toward": str(target["id"]), "purpose": "pursuit"}, true)
	return _finish_ai_call(next, actor_id, action, turn["prepared"], turn["adoption"])


static func _ai_rejected_step(loop: Dictionary, reason: String) -> Dictionary:
	var next := Loop.copy(loop)
	next.merge({"scenario_ok": false, "scenario_error": reason, "interaction": "scenario_error"}, true)
	return {"loop": next, "action": {}}


static func _execute_ai_support_item(loop: Dictionary, actor_id: String, intent: Dictionary) -> Dictionary:
	var actor := Loop._unit(loop,actor_id)
	var target := Loop._unit(loop,intent["target_id"])
	if actor.get("battle_actor_role") not in SkillTargetRules.ROLES or target.get("battle_actor_role") not in SkillTargetRules.ROLES: return {}
	if not SkillTargetRules._living(actor) or not SkillTargetRules._living(target) or Loop._are_enemies(actor,target): return {}
	if StatusEffectRules.input_error(actor) != "" or StatusEffectRules.paralyzed(actor): return {}
	var origin: Vector2i = actor["coord"]
	var destination: Vector2i = intent["destination"]
	if Footprint.distance(actor,target,destination) > 1: return {}
	var path := Loop.movement_path(loop,actor_id,destination) if destination != origin else []
	if destination != origin and (path.is_empty() or path.back() != destination): return {}
	var effect := Inventory._resolve_item_use(loop,actor_id,target["id"],intent["item_code"],int(intent["item_slot"]))
	if effect.is_empty(): return {}
	Loop._set_unit_coord(loop,actor_id,destination)
	return {"actor_id":actor_id,"target_id":target["id"],"kind":"use_item" if destination == origin else "move_then_item",
		"to":destination,"path":path,"item_use":effect}


static func _select_ai_priority(loop: Dictionary, actor_id: String, prepared: Dictionary, rng: Variant) -> Dictionary:
	var actor := Loop._unit(loop, actor_id)
	var support_roll := -1
	var attempted := (2 if int(prepared["healing_slot"]) < 0 and prepared["self_support"]["healing"].is_empty() else 0) | (1 if prepared["opportunity_ids"].is_empty() else 0)
	var result := {"kind": "ordinary", "index": -1, "checks": [], "scans": [],
		"composition_policy": "self HP and dying-foe checks, existing self cure, then owned ally support before offense; full native dispatcher remains separate"}
	while attempted != 3:
		var phase := AIPriorityRules.choose_check(prepared["profile"], attempted, rng)
		result["checks"].append(phase)
		attempted = int(phase["attempted"])
		if phase["kind"] == 0:
			support_roll = int(phase["next_roll"])
			break
		if phase["kind"] == 2:
			var health := AIPriorityRules.self_recovery(actor, rng)
			result["self_recovery"] = health
			if health["needed"]:
				var self_choice := AISelfPreservation.choose_healing(prepared["self_support"], actor, prepared["profile"], int(prepared["healing_slot"]), rng)
				result.merge(self_choice, true)
				if self_choice["kind"] != "ordinary": return result
		else:
			# 0x40bf70 walks the object array 0x4c34c0 like 0x40bb80 (registry order).
			var layout: Array = prepared["registry"]
			var scan_rows := AIDecisionRules.registry_rows(prepared["priority_rows"], layout)
			var owner_slot: int = layout.find(prepared["owner_index"]) if not layout.is_empty() else int(prepared["owner_index"])
			var cursor := 0
			while cursor < scan_rows.size():
				var scan := AIPriorityRules.low_hp_target(scan_rows, owner_slot, int(prepared["profile"]["find_range"]), int(prepared["profile"]["find_no_id"]), cursor, rng)
				result["scans"].append(scan)
				if scan["index"] < 0: break
				var found: int = int(layout[int(scan["index"])]) if not layout.is_empty() else int(scan["index"])
				if prepared["opportunity_ids"].has(loop["units"][found]["id"]):
					result["kind"] = "dying"
					result["index"] = found
					return result
				# Resume AFTER a low-HP object with no legal attack, never stall on it.
				cursor = int(scan["native_index"])
	result.merge(AISelfPreservation.choose_cure(prepared["self_support"], actor, rng), true)
	if result["kind"] == "ordinary":
		result.merge(AISupportPlanning.choose(prepared["ally_support"], actor, prepared["profile"], loop["units"], rng, support_roll), true)
	return result


## Preflight physical option for one target (no RNG): the native attack stations
## (AINavigationRules.attack_stations) over the weapon's terrain coverage — the station
## flood from the target and the in-range test from the actor both stop at 0x4000 walls
## (0x40d8b0 → 0x40fa80 flag 0; 0x440d2d → 0x40fb20 flag 1). `terrain` is the actor's
## AINavigationRules.weapon_terrain, built once per turn by the caller (null: build it
## here). `to`／`cost` summarise it before the draw — the actor's own cell when it can
## already hit the target, else the first collected station; the walk target is settled
## at commit by AINavigationRules.attack_station.
static func _ai_physical_choice(loop: Dictionary, actor: Dictionary, target: Dictionary, envelope: Dictionary, terrain: Variant = null) -> Dictionary:
	if bool(actor.get("no_attack", false)): return {}
	var pattern := Loop.weapon_pattern(loop, actor)
	if not pattern["ok"]: return {}
	if not terrain is Dictionary: terrain = AINavigationRules.weapon_terrain(loop, actor, pattern)
	var choice := AINavigationRules.attack_stations(actor, target, pattern["offsets"], int(pattern["index"]) < 2, envelope["reachable_by_coord"], terrain)
	if choice.is_empty(): return {}
	var first: Dictionary = choice["stations"][0]
	choice["to"] = actor["coord"] if choice["in_place"] else first["cell"]
	choice["cost"] = 0 if choice["in_place"] else int(first["cost"])
	return choice


static func _finish_ai_call(loop: Dictionary, actor_id: String, action: Dictionary, prepared: Dictionary, adoption: Dictionary) -> Dictionary:
	# Publish call changes only with a settled action. Failed preflight cannot
	# consume a call or expose half a broadcast to the next actor.
	if adoption["consumed"]: Loop._unit(loop, actor_id)["ai_call_target_id"] = ""
	var actor := Loop._unit(loop, actor_id)
	if prepared.has("navigation_selection"):
		actor["ai_wait_remaining"] = prepared["navigation_selection"]["wait_remaining"]
		actor["ai_target_id"] = str(loop["units"][int(adoption["index"])]["id"]) if int(adoption["index"]) >= 0 else ""
	if adoption["broadcast"]:
		var target_id: String = loop["units"][int(adoption.get("broadcast_index", adoption["index"]))]["id"]
		for recipient_id in prepared["call"]["recipient_ids"]:
			Loop._unit(loop, recipient_id)["ai_call_target_id"] = target_id
	_prune_ai_calls(loop)
	return {"loop": loop, "action": action}


static func _prune_ai_calls(loop: Dictionary) -> void:
	# Stable-ID cleanup is remake lifecycle policy, not a claim about native slot
	# reuse. It runs after death, skill settlement, script departure and outcome.
	# `by_id` is `Loop._unit` for every id at once (first unit with that id); the
	# cleanup rewrites only the two target fields, never an id.
	var by_id := {}
	for unit in loop["units"]:
		if typeof(unit) != TYPE_DICTIONARY: continue
		var id := str(unit.get("id", ""))
		if not by_id.has(id): by_id[id] = unit
	for actor in loop["units"]:
		if not actor.has("ai_call_target_id"): continue
		if BattleOutcome.decided(loop) or not Presence.living(actor):
			actor["ai_call_target_id"] = ""
			actor["ai_target_id"] = ""
			continue
		var target: Dictionary = by_id.get(str(actor["ai_call_target_id"]), {})
		if not Presence.living(target) or not Loop._are_enemies(actor, target):
			actor["ai_call_target_id"] = ""
		var held: Dictionary = by_id.get(str(actor.get("ai_target_id", "")), {})
		if held.is_empty() or not SkillTargetRules._living(held) or not Loop._are_enemies(actor, held): actor["ai_target_id"] = ""


static func _prepare_ai_turn(loop: Dictionary, actor_id: String, skill_inputs_checked: bool = false) -> Dictionary:
	# Read-only preflight across eligible source targets; all failures precede RNG.
	# Each phase fills `work` (the intermediates below) or returns the failing receipt
	# unchanged; the accepted preparation is assembled last in one fixed key order.
	var work := {"skill_inputs_checked": skill_inputs_checked}
	for phase in [_ai_preflight_actor, _ai_target_rows, _ai_approach_routes, _ai_call_state, _ai_action_candidates]:
		var failure: Dictionary = phase.call(loop, actor_id, work)
		if not failure.is_empty(): return failure
	return {"ok": true, "profile": work["profile"], "rows": work["rows"], "owner_index": work["owner_index"], "registry": work["registry"],
		"full_routes": work["full_routes"], "approaches": work["approaches"], "candidate_filters": work["candidate_filters"],
		"call": work["call"],
		"skills": work["skills"], "envelope": work["envelope"], "physical": work["physical"], "offensive_skills": work["offensive_skills"], "any_skills": work["any_skills"],
		"self_support": work["self_support"], "ally_support": work["ally_support"], "healing_slot": work["healing_slot"], "priority_rows": work["priority_rows"], "opportunity_ids": work["opportunity_ids"], "weapon_terrain": work["weapon_terrain"]}


## Actor identity, source strategy, skill／status／equipment inputs, the first owned
## healing medicine, unit identities and the live near-range budget.
static func _ai_preflight_actor(loop: Dictionary, actor_id: String, work: Dictionary) -> Dictionary:
	var actor := Loop._unit(loop, actor_id)
	if not Presence.living(actor): return {"ok": false, "reason": "ai_actor_unavailable"}
	var declared: Dictionary = loop.get("ai_profiles", {}).get("actors", {}).get(str(actor.get("actor_id", "")), {})
	if declared.is_empty() or not declared.get("missing_required", ["unknown"]).is_empty(): return {"ok": false, "reason": "missing_ai_strategy"}
	var profile: Dictionary = AINavigationRules.instance_profile(actor, declared["profile"])
	var error := AIDecisionRules.profile_error(profile)
	if error == "" and not work.get("skill_inputs_checked", false): error = Loop._skill_input_error(loop, actor)
	if error == "": error = AIPriorityRules.profile_error(profile)
	if error == "": error = AINavigationRules.profile_error(profile)
	if error == "": error = AINavigationRules.state_error(actor, int(profile["ai_fixed"]))
	if error != "": return {"ok": false, "reason": error}
	if not actor.get("inventory") is Array: return {"ok": false, "reason": "invalid_inventory_slots"}
	var healing := ItemUseRules.first_healing_slot(actor["inventory"], loop["consumables"])
	if not healing["ok"]: return healing
	var healing_slot := int(healing["index"])
	if healing_slot >= 0:
		var item_effect := ItemUseRules.prepare(actor, loop["consumables"][str(int(actor["inventory"][healing_slot]))])
		if not item_effect["ok"]:
			if item_effect["reason"] != "item_has_no_effect": return item_effect
			healing_slot = -1
	var identities := {}
	for unit in loop["units"]:
		if not unit.get("id") is String or unit["id"] == "" or identities.has(unit["id"]):
			return {"ok": false, "reason": "invalid_ai_unit_identity"}
		if not unit.get("ai_call_target_id") is String:
			return {"ok": false, "reason": "invalid_ai_call_target_id"}
		identities[unit["id"]] = true
	if SkillResourceRules._integer(actor.get("move_point")) < 0 or int(actor["move_point"]) > 512:
		return {"ok": false, "reason": "invalid_ai_near_range"}
	# `healing_index` is the registered slot the ally-support planner reads; `healing_slot`
	# is the self-use slot, cleared when the medicine has no effect on the actor.
	work.merge({"actor": actor, "profile": profile, "healing_index": int(healing["index"]), "healing_slot": healing_slot}, true)
	return {}


## Source target rows (null for a dead slot) with the SID exclusion applied, the living
## hostile list and the actor's own row index; every row's combat inputs validated.
static func _ai_target_rows(loop: Dictionary, actor_id: String, work: Dictionary) -> Dictionary:
	var actor: Dictionary = work["actor"]
	var profile: Dictionary = work["profile"]
	var rows: Array = []
	var foes: Array = []
	var owner_index := -1
	for index in range(loop["units"].size()):
		var unit: Dictionary = loop["units"][index]
		if str(unit["id"]) == actor_id: owner_index = index
		if not Presence.living(unit):
			rows.append(null)
			continue
		if not unit.get("coord") is Vector2i or not SkillTargetRules._inside(unit["coord"], loop["map_size"]):
			# No AI branch reads a living unit standing outside the map; name it instead of
			# letting the row kernel report the current actor's turn as the fault.
			return {"ok": false, "reason": "ai_unit_off_map:" + str(unit["id"])}
		var row_error := _row_input_error(loop, unit)
		if row_error != "": return {"ok": false, "reason": row_error}
		var unit_source: Dictionary = loop["ai_profiles"]["actors"].get(str(unit["actor_id"]), {})
		if unit_source.get("sid") == null or not unit_source.get("profile") is Dictionary:
			return {"ok": false, "reason": "missing_ai_actor_identity"}
		var row := {"coord": unit["coord"], "side": ActorRoleRules.side_mask(unit),
			"job": unit_source["profile"]["job"], "sid": unit_source["sid"], "level": unit.get("level"), "hp": unit["hp"],
			"max_hp": unit.get("max_hp"), "status_flags": unit.get("status_flags"), "removed": int(unit_source["sid"]) == int(profile["find_no_id"])}
		# `excluded`: removed by find_no_id alone. The target scan 0x40bb80 still scores
		# such an object (its baseline update comes before the SID test, 0x40bd4f..) and
		# only then falls back to the previous candidate (AIDecisionRules.select_target).
		row["excluded"] = row["removed"]
		rows.append(row)
		if str(unit["id"]) != actor_id and not row["removed"] and Loop._are_enemies(actor, unit): foes.append(unit)
	var error := AIPriorityRules.scan_error(rows, owner_index, int(profile["find_range"]), int(profile["find_no_id"]))
	if error != "": return {"ok": false, "reason": error}
	# The scans walk the object array 0x4c34c0, not the roster (CoreTurnQueue.registry_layout).
	# `hostile` keeps every foe the station switch 0x40d8b0 may reach (no range／guard test).
	work.merge({"rows": rows, "foes": foes, "hostile": foes.duplicate(), "owner_index": owner_index, "registry": CoreTurnQueue.registry_layout(loop["units"])}, true)
	return {}


## The first stamina／experience／combat input error of one living unit, memoised in
## `_row_validation` by the unit's exact bytes under the current `equipment_items`.
static func _row_input_error(loop: Dictionary, unit: Dictionary) -> String:
	if _row_memo_enabled == null: _row_memo_enabled = OS.get_environment(ROW_MEMO_ENV) != "0"
	if not _row_memo_enabled: return _row_input_error_uncached(loop, unit)
	if not is_same(_row_validation["equipment_items"], loop["equipment_items"]):
		_row_validation = {"equipment_items": loop["equipment_items"], "units": {}}
	var memo: Dictionary = _row_validation["units"]
	var bytes := var_to_bytes(unit)
	var entry: Dictionary = memo.get(unit["id"], {})
	if entry.get("bytes") == bytes: return entry["error"]
	var error := _row_input_error_uncached(loop, unit)
	memo[unit["id"]] = {"bytes": bytes, "error": error}
	return error


static func _row_input_error_uncached(loop: Dictionary, unit: Dictionary) -> String:
	var stamina_error := StaminaRules.input_error(unit, loop["equipment_items"])
	if stamina_error != "": return stamina_error
	var experience_error := ExperienceRules.input_error(loop, unit)
	if experience_error != "": return experience_error
	return CoreCombatRules.input_error(unit)


## Full-map legal routes and per-foe approach routes; foes outside the guard radius leave
## the candidate list (recorded in `candidate_filters`). A foe without a route stays: the
## scan 0x40bb80 reads positions only, and pursuit walks toward it through 0x4111a0.
static func _ai_approach_routes(loop: Dictionary, _actor_id: String, work: Dictionary) -> Dictionary:
	var actor: Dictionary = work["actor"]
	var profile: Dictionary = work["profile"]
	var rows: Array = work["rows"]
	var foes: Array = work["foes"]
	# One traversal context (map tables, occupancy) serves this turn's full-map flood and
	# the movement envelope of `_ai_action_candidates`; a rejected one is left to each
	# flood to prepare and report in its own order.
	var traversal := Loop._traversal_context(loop, actor, loop["units"])
	if not traversal["ok"]: traversal = {}
	# The goal cells do not depend on the flood, so they are known before it and the flood
	# builds routes to them alone; a goal failure still reports after a flood failure.
	var fields_by_id := {}
	for id in loop["skill_book"]["skills"]: fields_by_id[id] = Loop.skill_fields(loop, id)
	var goals := AINavigationRules.approach_goals(loop, actor, foes, fields_by_id)
	var goal_cells := {}
	if goals["ok"]:
		for target_id in goals["goals"]: goal_cells.merge(goals["goals"][target_id])
	var full_routes := AINavigationRules.full_routes(loop, actor, traversal, goal_cells)
	if not full_routes["ok"]: return full_routes
	if not goals["ok"]: return goals
	var approaches: Dictionary = AINavigationRules.approaches(full_routes, goals["goals"])["targets"]
	# Candidate-filter receipt: which preflight step emptied the enemy list. An
	# unarmed actor (weapon_code 0 -> range0, no offsets) has no attack goal cell,
	# so no foe gets an approach route; the original ends such a turn at 0x441eb8
	# after 0x409090 returns 0, before any pursuit.
	var candidate_filters := {"living_foes": foes.size(), "without_approach": 0, "guard_excluded": 0,
		"unarmed": int(actor.get("weapon_code", 0)) == 0 or bool(actor.get("no_attack", false))}
	for index in range(rows.size()):
		if rows[index] == null or not Loop._are_enemies(actor, loop["units"][index]): continue
		var foe_id: String = loop["units"][index]["id"]
		if not approaches.has(foe_id): candidate_filters["without_approach"] += 1
		if not AINavigationRules.guard_allows(actor, loop["units"][index], profile):
			candidate_filters["guard_excluded"] += 1
			rows[index]["removed"] = true
			rows[index]["excluded"] = false
	foes = foes.filter(func(foe): return AINavigationRules.guard_allows(actor, foe, profile))
	work.merge({"full_routes": full_routes, "approaches": approaches, "candidate_filters": candidate_filters, "foes": foes, "traversal": traversal}, true)
	return {}


## The pending call this actor holds (index／eligibility against the rows) and the
## recipients of a call it would broadcast.
static func _ai_call_state(loop: Dictionary, _actor_id: String, work: Dictionary) -> Dictionary:
	var actor: Dictionary = work["actor"]
	var profile: Dictionary = work["profile"]
	var rows: Array = work["rows"]
	var pending_id: String = actor["ai_call_target_id"]
	var pending_index := -1
	var pending_eligible := false
	for index in range(loop["units"].size()):
		if loop["units"][index]["id"] == pending_id:
			pending_index = index
			pending_eligible = rows[index] != null and not rows[index]["removed"] and Loop._are_enemies(actor, loop["units"][index])
	var call_recipient_ids: Array = []
	if int(profile["ai_call_range"]) > 0:
		var broadcast := AICallRules.recipients(rows, work["owner_index"], int(profile["ai_call_range"]))
		if not broadcast["ok"]: return broadcast
		for index in broadcast["indices"]: call_recipient_ids.append(loop["units"][index]["id"])
	work.merge({"call": {"target_id": pending_id, "index": pending_index, "eligible": pending_eligible, "recipient_ids": call_recipient_ids},
		"pending_index": pending_index, "pending_eligible": pending_eligible}, true)
	return {}


## Skill／physical candidates per foe over the current movement envelope, the self and
## ally support plans and the dying-foe opportunity list. Physical stations are kept for
## every hostile, non-excluded foe at any distance: the ordinary category's switch
## 0x40d8b0 walks the whole object array (no find range, no guard radius). The scans see
## every foe in find range whether it can be struck this turn or not (0x40bb80 reads
## positions only); `priority_rows` is the row copy the low-HP scan and retention read.
static func _ai_action_candidates(loop: Dictionary, actor_id: String, work: Dictionary) -> Dictionary:
	var actor: Dictionary = work["actor"]
	var profile: Dictionary = work["profile"]
	var rows: Array = work["rows"]
	var foes: Array = work["foes"]
	var square_foes: Array = foes.filter(func(foe): return AIPriorityRules.within_square(foe["coord"], actor["coord"], int(profile["find_range"])))
	var skill_foes := square_foes.duplicate()
	if work["pending_eligible"] and not skill_foes.has(loop["units"][work["pending_index"]]):
		skill_foes.append(loop["units"][work["pending_index"]])
	# One movement envelope serves both skill channels, the ally support plan and the
	# physical choices: the same read-only query over the same board.
	var envelope := Loop._movement_envelope(loop, actor_id, work["traversal"])
	var skills := {}
	var offensive_skills := {}
	var any_skills := {}
	for channel in ["magic", "special"]:
		var prepared := _ai_skill_plans(loop, actor, skill_foes, channel, envelope)
		if not prepared["ok"]: return prepared
		skills[channel] = prepared["targets"]
		offensive_skills[channel] = prepared["offensive_targets"]
		any_skills[channel] = prepared["any_target"]
	var self_support := AISelfPreservation.prepare(loop, actor)
	if not self_support["ok"]: return self_support
	var ally_support := AISupportPlanning.prepare(loop, actor, envelope, rows, work["owner_index"], profile, int(work["healing_index"]))
	if not ally_support["ok"]: return ally_support
	ally_support["registry"] = work["registry"]
	var physical := {}
	var station_foes: Array = work["hostile"].duplicate()
	for foe in skill_foes:
		if not station_foes.has(foe): station_foes.append(foe)
	var terrain := AINavigationRules.weapon_terrain(loop, actor, Loop.weapon_pattern(loop, actor))
	for foe in station_foes:
		var choice := _ai_physical_choice(loop, actor, foe, envelope, terrain)
		if not choice.is_empty(): physical[foe["id"]] = choice
	var opportunity_ids: Array = []
	for foe in square_foes:
		if physical.has(foe["id"]) or offensive_skills["magic"].has(foe["id"]) or offensive_skills["special"].has(foe["id"]): opportunity_ids.append(foe["id"])
	var priority_rows := rows.duplicate(true)
	work.merge({"skills": skills, "offensive_skills": offensive_skills, "any_skills": any_skills, "envelope": envelope, "self_support": self_support,
		"ally_support": ally_support, "physical": physical, "opportunity_ids": opportunity_ids, "priority_rows": priority_rows, "weapon_terrain": terrain}, true)
	return {}


static func _ai_skill_candidates(loop: Dictionary, actor_id: String, foes: Array, channel: String) -> Dictionary:
	var actor := Loop._unit(loop, actor_id)
	var error := Loop._skill_input_error(loop, actor)
	if error != "": return {"ok": false, "reason": error}
	return _ai_skill_plans(loop, actor, foes, channel, Loop._movement_envelope(loop, actor_id))


## One channel's skill plans over the actor's current movement envelope, without
## `_ai_skill_candidates`' input check: `_ai_action_candidates` runs after
## `_ai_preflight_actor` checked the same actor's skill inputs on the same read-only loop.
static func _ai_skill_plans(loop: Dictionary, actor: Dictionary, foes: Array, channel: String, envelope: Dictionary) -> Dictionary:
	var fields_by_id := {}
	for id in loop["skill_book"]["skills"]:
		if loop["skill_book"]["skills"][id]["channel"] != channel or SkillResolutionRules.ownership_error(actor, id, loop["skill_book"]) != "": continue
		fields_by_id[id] = Loop.skill_fields(loop, id)
	return AISkillPlanning.prepare(loop, actor, foes, channel, fields_by_id, envelope)


static func _try_skill_turn(loop: Dictionary, actor_id: String, foes: Array, rng: Variant, channel: String = "magic") -> Dictionary:
	var prepared := _ai_skill_candidates(loop, actor_id, foes, channel)
	if not prepared["ok"]: return {"kind": "invalid_skill_input", "reason": prepared["reason"]}
	var choice := {}
	for target in prepared["targets"].values():
		if choice.is_empty(): choice = target
	if choice.is_empty(): return {}
	var source: Variant = rng if rng != null else GlobalRandom.loop_source(loop)
	var selected := AISkillPlanning.choose(choice, source)
	if selected["intent"].is_empty(): return {}
	var action := _execute_ai_skill_choice(loop, actor_id, selected["intent"], source)
	if not action.is_empty(): action["ai_skill_decision"] = selected["decision"]
	return action


static func _execute_ai_skill_choice(loop: Dictionary, actor_id: String, choice: Dictionary, rng: Variant) -> Dictionary:
	var source: Variant = rng if rng != null else GlobalRandom.loop_source(loop)
	var origin: Vector2i = Loop._unit(loop, actor_id)["coord"]
	var destination: Vector2i = choice["destination"]
	var target_id: String = choice["target_id"]
	var path := Loop.movement_path(loop, actor_id, destination) if destination != origin else []
	if destination != origin and (path.is_empty() or path.back() != destination): return {}
	var key: String = choice["skill_id"]
	var fields := Loop.skill_fields(loop, key)
	# Settlement draws from the loop's damage stream (0x42c780), not the decision source.
	var strike := Combat._resolve_skill(loop, actor_id, target_id, key, fields, destination, null, choice.get("cast_center"))
	if strike.is_empty():
		return {}
	strike.merge({"actor_id": actor_id, "target_id": target_id, "kind": "attack" if destination == origin else "move_then_attack", "to": destination, "path": path}, true)
	return strike
